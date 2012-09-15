%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @reference The license is based on the template for Modified BSD from
%%%   <a href="http://opensource.org/licenses/BSD-3-Clause">OSI</a>
%%% @doc
%%%    Single graph node process.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop_node).
-author('Jay Nelson <jay@duomark.com>').

-include("../erlangsp/include/license_and_copyright.hrl").

%% Graph API
-export([
         %% Create coop_node instances...
         new/5, new/6,

         %% Send commands to coop_node control process...
         node_ctl_clone/1, node_ctl_stop/1,
         node_ctl_suspend/1, node_ctl_resume/1, node_ctl_trace/1, node_ctl_untrace/1,
         node_ctl_stats/3, node_ctl_log/3, node_ctl_log_to_file/3,
         node_ctl_install_trace_fn/3, node_ctl_remove_trace_fn/3
        ]).

%% Internal functions that are exported (not part of the external API)
-export([
         %% Send data to a node...
         node_task_deliver_data/2,

         %% Inspect and add to downstream receivers.
         node_task_get_downstream_pids/1, node_task_add_downstream_pids/2
        ]).

%% Internal functions for spawned processes
-export([echo_loop/1, link_loop/0]).

-include("coop.hrl").
-include("coop_dag.hrl").
-include("coop_node.hrl").

%%----------------------------------------------------------------------
%% Create a new coop_node. A coop_node is represented by a pair of
%% pids: a control process and a data task process.
%%----------------------------------------------------------------------
-spec new(coop_head(), pid(), coop_task_fn(), coop_init_fn(), coop_data_options()) -> coop_node().
-spec new(coop_head(), pid(), coop_task_fn(), coop_init_fn(), coop_data_options(), data_flow_method()) -> coop_node().

%% Broadcast is default for downstream data distribution.
%% Optimized for special case of 1 downstream pid.
new(Coop_Head, Kill_Switch, Node_Fn, Init_Fn, Data_Opts) ->
    new(Coop_Head, Kill_Switch, Node_Fn, Init_Fn, Data_Opts, broadcast).

%% Override downstream data distribution.
new(#coop_head{ctl_pid=Head_Ctl_Pid, data_pid=Head_Data_Pid} = Coop_Head, Kill_Switch,
    {_Task_Mod, _Task_Fn} = Node_Fn, {_Mod, _Fun, _Args} = Init_Fn,
    Data_Opts, Data_Flow_Method)

  when is_pid(Head_Ctl_Pid), is_pid(Head_Data_Pid), is_pid(Kill_Switch),
       is_atom(_Task_Mod), is_atom(_Task_Fn), is_atom(_Mod), is_atom(_Fun),
       is_list(Data_Opts),
       (        Data_Flow_Method =:= random
         orelse Data_Flow_Method =:= round_robin
         orelse Data_Flow_Method =:= broadcast   ) ->

    %% Start the data task process...
    Task_Pid = make_data_task_pid(Coop_Head, Node_Fn, Init_Fn, Data_Opts, Data_Flow_Method),

    %% Start support function processes...
    {Trace_Pid, Log_Pid, Reflect_Pid} = make_support_pids(),

    %% Start the control process...
    Ctl_Args = [Kill_Switch, Task_Pid, Init_Fn, Node_Fn, Trace_Pid, Log_Pid, Reflect_Pid],
    Ctl_Pid = proc_lib:spawn(coop_node_ctl_rcv, node_ctl_loop, Ctl_Args),

    %% Link all component pids to the Kill_Switch pid and return the Ctl and Data pids.
    coop_kill_link_rcv:link_to_kill_switch(Kill_Switch, [Ctl_Pid, Task_Pid, Trace_Pid, Log_Pid, Reflect_Pid]),
    #coop_node{ctl_pid=Ctl_Pid, task_pid=Task_Pid}.

make_data_task_pid(Coop_Head, Node_Fn, Init_Fn, Data_Opts, Data_Flow_Method) ->
    Worker_Set = case Data_Flow_Method of random -> {}; _Other -> queue:new() end,
    Task_Args = [Coop_Head, Node_Fn, Init_Fn, Worker_Set, Data_Opts, Data_Flow_Method],
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
node_task_get_downstream_pids(#coop_node{task_pid=Node_Task_Pid}) ->
    Ref = make_ref(),
    Node_Task_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, {get_downstream, {Ref, self()}}},
    receive
        {get_downstream, Ref, Pids} -> Pids
    after ?SYNC_RECEIVE_TIME -> timeout
    end.

node_task_add_downstream_pids(#coop_node{task_pid=Node_Task_Pid}, Pids) when is_list(Pids) ->
    Node_Task_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, {add_downstream, Pids}},
    ok.

%% Deliver data to a downstream Pid or Coop_Node.
node_task_deliver_data(#coop_node{task_pid=Node_Task_Pid}, Data) ->
    Node_Task_Pid ! Data,
    ok;
node_task_deliver_data(Pid, Data) when is_pid(Pid) ->
    Pid ! Data,
    ok.


%%----------------------------------------------------------------------
%% Co-op Node receive loops for support pids.
%%----------------------------------------------------------------------

-spec echo_loop(string()) -> no_return().
-spec link_loop() -> no_return().

%% Trace, Log and Reflect process receive loop
echo_loop(Type) ->
    receive
        {stop} -> ok;
        Any -> error_logger:info_msg("~p ~p ~p: ~p~n", [?MODULE, Type, self(), Any])
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
            error_logger:error_msg("~p ~p: Ignoring ~p~n", [?MODULE, self(), _Unknown]),
            link_loop()
    end.
