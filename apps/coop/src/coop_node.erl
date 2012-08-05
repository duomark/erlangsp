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
         new/2, new/3,
         node_ctl_clone/1, node_ctl_stop/1,
         node_ctl_trace/1, node_ctl_untrace/1,
         node_task_get_downstream_pids/1,
         node_task_add_downstream_pids/2,
         node_task_deliver_data/2
        ]).

%% Internal functions for spawned processes
-export([
         echo_loop/1, link_loop/0, make_kill_switch/0, node_ctl_loop/6
        ]).


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

-record(coop_node_state, {
          kill_switch :: pid(),
          ctl         :: pid(),
          task        :: pid(),
          task_fn     :: task_function(),
          trace       :: pid(),
          log         :: pid(),
          reflect     :: pid()
         }).

-spec echo_loop(string()) -> no_return().
-spec link_loop() -> no_return().
-spec make_kill_switch() -> pid().

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

make_kill_switch() -> proc_lib:spawn(?MODULE, link_loop, []).
link_to_kill_switch(Kill_Switch, Procs) when is_list(Procs) ->
    Kill_Switch ! {?DAG_TOKEN, ?CTL_TOKEN, {link, Procs}}.

%%----------------------------------------------------------------------
%% Create a new coop_node. A coop_node is represented by a pair of
%% pids: a control process and a data task process.
%%----------------------------------------------------------------------

-spec new(pid(), task_function())
         -> {coop_node, Ctl_Proc, Data_Proc} when Ctl_Proc :: pid(), Data_Proc :: pid().
-spec new(pid(), task_function(), data_flow_method())
         -> {coop_node, Ctl_Proc, Data_Proc} when Ctl_Proc :: pid(), Data_Proc :: pid().
-spec node_ctl_loop(pid(), pid(), task_function(), pid(), pid(), pid()) -> no_return().
-spec node_ctl_loop(#coop_node_state{}) -> no_return().

%% Round robin is default for downstream data distribution.
%% Optimized for special case of 1 downstream pid.
new(Kill_Switch, Node_Fn) ->
    new(Kill_Switch, Node_Fn, round_robin).

%% Override downstream data distribution.
new(Kill_Switch, {_Task_Mod, _Task_Fn} = Node_Fn, Data_Flow_Method)
  when is_atom(_Task_Mod), is_atom(_Task_Fn),
       (       Data_Flow_Method =:= random
        orelse Data_Flow_Method =:= round_robin
        orelse Data_Flow_Method =:= broadcast   ) ->

    %% Start support function processes...
    Trace_Pid = proc_lib:spawn(?MODULE, echo_loop, ["TRC"]),
    [Log_Pid, Reflect_Pid]
        = [proc_lib:spawn(?MODULE, echo_loop, [Type]) || Type <- ["LOG", "RFL"]],

    %% Start the data task process...
    Worker_Set = case Data_Flow_Method of random -> {}; _Other -> queue:new() end,
    Task_Args = [Node_Fn, Worker_Set, Data_Flow_Method],
    Task_Pid = proc_lib:spawn(coop_node_data_rcv, node_data_loop, Task_Args),

    %% Start the control process...
    Ctl_Args = [Kill_Switch, Task_Pid, Node_Fn, Trace_Pid, Log_Pid, Reflect_Pid],
    Ctl_Pid = proc_lib:spawn(?MODULE, node_ctl_loop, Ctl_Args),

    %% Link all component pids to the Kill_Switch pid and return the Ctl and Data pids.
    link_to_kill_switch(Kill_Switch, [Ctl_Pid, Task_Pid, Trace_Pid, Log_Pid, Reflect_Pid]),
    {coop_node, Ctl_Pid, Task_Pid}.

node_ctl_clone  (Node_Ctl_Pid) -> Node_Ctl_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, clone}.
node_ctl_stop   (Node_Ctl_Pid) -> Node_Ctl_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, stop}.
node_ctl_trace  (Node_Ctl_Pid) -> Node_Ctl_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, trace}.
node_ctl_untrace(Node_Ctl_Pid) -> Node_Ctl_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, untrace}.
                               
    
-define(SYNC_RECEIVE_TIME, 2000).

node_task_get_downstream_pids(Node_Task_Pid) ->
    Ref = make_ref(),
    Node_Task_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, {get_downstream, {Ref, self()}}},
    receive
        {get_downstream, Ref, Pids} -> Pids
    after ?SYNC_RECEIVE_TIME -> timeout
    end.

node_task_add_downstream_pids(Node_Task_Pid, Pids) when is_list(Pids) ->
    Node_Task_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, {add_downstream, Pids}}.
     
node_task_deliver_data({coop_node, _Node_Ctl_Pid, Node_Task_Pid}, Data)
  when is_pid(_Node_Ctl_Pid), is_pid(Node_Task_Pid) ->
    Node_Task_Pid ! Data;
node_task_deliver_data(Node_Task_Pid, Data)
  when is_pid(Node_Task_Pid) ->
    Node_Task_Pid ! Data.


%%----------------------------------------------------------------------
%% Coop Node control functionality.
%%----------------------------------------------------------------------
node_ctl_loop(Kill_Switch, Task_Pid, Node_Fn, Trace_Pid, Log_Pid, Reflect_Pid) ->
    node_ctl_loop(#coop_node_state{kill_switch=Kill_Switch, ctl=self(),
                                   task=Task_Pid, task_fn=Node_Fn,
                                   trace=Trace_Pid, log=Log_Pid,
                                   reflect=Reflect_Pid}).

node_ctl_loop(#coop_node_state{task=Task_Pid, trace=Trace_Pid} = Coop_Node_State) ->
    receive
        {?DAG_TOKEN, ?CTL_TOKEN, stop}    -> exit(stopped);
        {?DAG_TOKEN, ?CTL_TOKEN, clone}   -> node_clone(Coop_Node_State);
        {?DAG_TOKEN, ?CTL_TOKEN, trace}   -> node_trace(Task_Pid, Trace_Pid);
        {?DAG_TOKEN, ?CTL_TOKEN, untrace} -> node_untrace(Task_Pid, Trace_Pid);
        _Skip_Unknown_Msgs                -> do_nothing
    end,
    node_ctl_loop(Coop_Node_State).


node_clone(#coop_node_state{} = _Coop_Node_State) -> ok.

node_trace  (Task_Pid, Trace_Pid) -> erlang:trace(Task_Pid, true,  trace_options(Trace_Pid)).
node_untrace(Task_Pid, Trace_Pid) -> erlang:trace(Task_Pid, false, trace_options(Trace_Pid)).

trace_options(Tracer_Pid) -> [{tracer, Tracer_Pid}, send, 'receive', procs, timestamp].

    
