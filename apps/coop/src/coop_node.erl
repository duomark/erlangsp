%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%    Single graph node process.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop_node).

-include("../erlangsp/include/license_and_copyright.hrl").
-author(jayn).

%% Graph API
-export([
         %% Create coop_node instances...
         new/3, new/4,

         %% Send commands to coop_node control process...
         node_ctl_clone/1, node_ctl_stop/1,
         node_ctl_suspend/1, node_ctl_resume/1, node_ctl_trace/1, node_ctl_untrace/1,
         node_ctl_stats/3, node_ctl_log/3, node_ctl_log_to_file/3,
         node_ctl_install_trace_fn/3, node_ctl_remove_trace_fn/3,

         %% Send commands to coop_node data task process...
         node_task_get_downstream_pids/1, node_task_add_downstream_pids/2,
         node_task_deliver_data/2
        ]).

%% Internal functions for spawned processes
-export([echo_loop/1, link_loop/0]).

%%----------------------------------------------------------------------
%% A Coop Node is a single worker element of a Coop. Every worker
%% element exists to accept data, transform it and pass it on.
%%
%% There are separate pids internal to a Coop Node used to:
%%    1) terminate the entire coop (kill_switch)
%%    2) receive control requests (ctl)
%%    3) execute the transform function (task execs task_fn)
%%    4) relay trace information (trace)
%%    5) record log and telemetry data (log)
%%    6) reflect data flow for user display and analysis (reflect)
%%----------------------------------------------------------------------

-include("coop_dag.hrl").
-include("coop_node.hrl").

%%----------------------------------------------------------------------
%% Create a new coop_node. A coop_node is represented by a pair of
%% pids: a control process and a data task process.
%%----------------------------------------------------------------------
-spec new(pid(), coop_task_fn(), coop_init_fn()) -> coop_node().
-spec new(pid(), coop_task_fn(), coop_init_fn(), data_flow_method()) -> coop_node().

%% Round robin is default for downstream data distribution.
%% Optimized for special case of 1 downstream pid.
new(Kill_Switch, Node_Fn, Init_Fn) ->
    new(Kill_Switch, Node_Fn, Init_Fn, round_robin).

%% Override downstream data distribution.
new(Kill_Switch, {_Task_Mod, _Task_Fn} = Node_Fn, {_Mod, _Fun, _Args} = Init_Fn, Data_Flow_Method)
  when is_pid(Kill_Switch), is_atom(_Task_Mod), is_atom(_Task_Fn), is_atom(_Mod), is_atom(_Fun),
       (        Data_Flow_Method =:= random
         orelse Data_Flow_Method =:= round_robin
         orelse Data_Flow_Method =:= broadcast   ) ->

    %% Start the data task process...
    Task_Pid = make_data_task_pid(Node_Fn, Init_Fn, Data_Flow_Method),

    %% Start support function processes...
    {Trace_Pid, Log_Pid, Reflect_Pid} = make_support_pids(),

    %% Start the control process...
    Ctl_Args = [Kill_Switch, Task_Pid, Init_Fn, Node_Fn, Trace_Pid, Log_Pid, Reflect_Pid],
    Ctl_Pid = proc_lib:spawn(coop_node_ctl_rcv, node_ctl_loop, Ctl_Args),

    %% Link all component pids to the Kill_Switch pid and return the Ctl and Data pids.
    coop_kill_link_rcv:link_to_kill_switch(Kill_Switch, [Ctl_Pid, Task_Pid, Trace_Pid, Log_Pid, Reflect_Pid]),
    {coop_node, Ctl_Pid, Task_Pid}.

make_data_task_pid(Node_Fn, Init_Fn, Data_Flow_Method) ->
    Worker_Set = case Data_Flow_Method of random -> {}; _Other -> queue:new() end,
    Task_Args = [Node_Fn, Init_Fn, Worker_Set, Data_Flow_Method],
    proc_lib:spawn(coop_node_data_rcv, start_node_data_loop, Task_Args).

make_support_pids() ->
    Trace_Pid = proc_lib:spawn(?MODULE, echo_loop, ["NTRC"]),
    [Log_Pid, Reflect_Pid]
        = [proc_lib:spawn(?MODULE, echo_loop, [Type]) || Type <- ["NLOG", "NRFL"]],
    {Trace_Pid, Log_Pid, Reflect_Pid}.


%%----------------------------------------------------------------------
%% Control process interface...
%%----------------------------------------------------------------------
-define(SYNC_RECEIVE_TIME, 2000).

node_ctl_clone  (Coop_Node) -> ?SEND_CTL_MSG(Coop_Node, clone).
node_ctl_stop   (Coop_Node) -> ?SEND_CTL_MSG(Coop_Node, stop).
node_ctl_suspend(Coop_Node) -> ?SEND_CTL_MSG(Coop_Node, suspend).
node_ctl_resume (Coop_Node) -> ?SEND_CTL_MSG(Coop_Node, resume).
node_ctl_trace  (Coop_Node) -> ?SEND_CTL_MSG(Coop_Node, trace).
node_ctl_untrace(Coop_Node) -> ?SEND_CTL_MSG(Coop_Node, untrace).

wait_ctl_response(Type, Ref) ->
    receive {Type, Ref, Info} -> Info
    after ?SYNC_RECEIVE_TIME  -> timeout
    end.
    
node_ctl_log(Coop_Node, Flag, From) ->
    Ref = make_ref(),
    ?SEND_CTL_MSG(Coop_Node, log, Flag, {Ref, From}),
    wait_ctl_response(node_ctl_log, Ref).
    
node_ctl_log_to_file(Coop_Node, File, From) ->
    Ref = make_ref(),
    ?SEND_CTL_MSG(Coop_Node, log_to_file, File, {Ref, From}),
    wait_ctl_response(node_ctl_log_to_file, Ref).

node_ctl_stats(Coop_Node, Flag, From) ->
    Ref = make_ref(),
    ?SEND_CTL_MSG(Coop_Node, stats, Flag, {Ref, From}),
    wait_ctl_response(node_ctl_stats, Ref).

node_ctl_install_trace_fn(Coop_Node, {Func, Func_State}, From) ->
    Ref = make_ref(),
    ?SEND_CTL_MSG(Coop_Node, install_trace_fn, {Func, Func_State}, {Ref, From}),
    wait_ctl_response(node_ctl_install_trace_fn, Ref).

node_ctl_remove_trace_fn(Coop_Node, Func, From) ->
    Ref = make_ref(),
    ?SEND_CTL_MSG(Coop_Node, remove_trace_fn, Func, {Ref, From}),
    wait_ctl_response(node_ctl_remove_trace_fn, Ref).

%%----------------------------------------------------------------------
%% Task process interface...
%%----------------------------------------------------------------------
node_task_get_downstream_pids({coop_node, _Node_Ctl_Pid, Node_Task_Pid}) ->
    Ref = make_ref(),
    Node_Task_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, {get_downstream, {Ref, self()}}},
    receive
        {get_downstream, Ref, Pids} -> Pids
    after ?SYNC_RECEIVE_TIME -> timeout
    end.

node_task_add_downstream_pids({coop_node, _Node_Ctl_Pid, Node_Task_Pid}, Pids) when is_list(Pids) ->
    Node_Task_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, {add_downstream, Pids}},
    ok.

%% Deliver data to a downstream Pid or Coop_Node.
node_task_deliver_data({coop_node, _Node_Ctl_Pid, Node_Task_Pid}, Data) ->
    Node_Task_Pid ! Data, ok;
node_task_deliver_data(Pid, Data) when is_pid(Pid) ->
    Pid ! Data, ok.


%%----------------------------------------------------------------------
%% Coop Node receive loops for support pids.
%%----------------------------------------------------------------------

-spec echo_loop(string()) -> no_return().
-spec link_loop() -> no_return().

%% Trace, Log and Reflect process receive loop
echo_loop(Type) ->
    receive
        {stop} -> ok;
        Any -> error_logger:info_msg("~p ~p: ~p~n", [Type, self(), Any])
    end,
    echo_loop(Type).

%% Kill_switch process receive loop
link_loop() ->
    receive

        %%------------------------------------------------------------
        %% TODO: This code needs to be improved to handle remote
        %% support processes. Right now all are assumed to be local
        %% to the coop_node's erlang VM node.
        {?DAG_TOKEN, ?CTL_TOKEN, {link, Procs}} ->
            [case is_process_alive(P) of

                 %% Crash if process to link is already dead
                 false ->
                     [exit(Pid, kill) || Pid <- Procs],
                     exit(kill);

                 %% Otherwise link and continue
                 true  -> link(P)

             end || P <- Procs],
            link_loop();
        %%------------------------------------------------------------

        _Unknown ->
            error_logger:error_msg("KILL ~p: Ignoring ~p~n", [self(), _Unknown]),
            link_loop()
    end.
