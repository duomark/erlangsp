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
         new/2, new/3, node_ctl_clone/1, node_ctl_stop/1,
         node_task_get_downstream_pids/1,
         node_task_add_downstream_pids/2,
         node_task_deliver_data/2
        ]).

%% Internal functions for spawned processes
-export([
         busy_loop/0, link_loop/0, make_kill_switch/0, node_ctl_loop/6
        ]).


%%----------------------------------------------------------------------
%% A Coop Node is a single worker element of a Coop. Every worker
%% element exists to accept data, transform it and pass it on.
%%
%% There are separate pids for:
%%    1) a kill_switch for terminating the entire coop
%%    2) receiving control requests
%%    3) executing the transform function
%%    4) relaying trace information
%%    5) recording log and telemetry data
%%    6) reflecting the internal state for user display and analysis
%%----------------------------------------------------------------------

-include("coop_dag.hrl").

-record(coop_node, {
          kill_switch :: pid(),
          ctl         :: pid(),
          task        :: pid(),
          task_fn     :: task_function(),
          trace       :: pid(),
          log         :: pid(),
          reflect     :: pid()
         }).

-spec busy_loop() -> no_return().
-spec link_loop() -> no_return().
-spec make_kill_switch() -> pid().

busy_loop() -> receive {stop} -> ok; _Any -> ok end, busy_loop.
link_loop() ->
    receive
        {?DAG_TOKEN, ?CTL_TOKEN, {link, Procs}} ->
            [link(P) || P <- Procs],
            link_loop();
        _Unknown ->
            error_logger:error_msg("Got ~p~n", [_Unknown]),
            link_loop()
    end.

make_kill_switch() -> proc_lib:spawn(?MODULE, link_loop, []).
link_to_kill_switch(Kill_Switch, Procs) when is_list(Procs) ->
    Kill_Switch ! {?DAG_TOKEN, ?CTL_TOKEN, {link, Procs}}.


-spec new(pid(), task_function())
         -> {Ctl_Proc, Data_Proc} when Ctl_Proc :: pid(), Data_Proc :: pid().
-spec new(pid(), task_function(), data_flow_method())
         -> {Ctl_Proc, Data_Proc} when Ctl_Proc :: pid(), Data_Proc :: pid().
-spec node_ctl_loop(pid(), pid(), task_function(), pid(), pid(), pid()) -> no_return().
-spec node_ctl_loop(#coop_node{}) -> no_return().

%%----------------------------------------------------------------------
%% Create a new coop_node. A coop_node is represented by a pair of
%% pids: a control process and a data task process.
%%----------------------------------------------------------------------
new(Kill_Switch, Node_Fn) -> new(Kill_Switch, Node_Fn, round_robin).

new(Kill_Switch, {_Task_Mod, _Task_Fn} = Node_Fn, Data_Flow_Method)
  when is_atom(_Task_Mod), is_atom(_Task_Fn),
       (Data_Flow_Method =:= random orelse Data_Flow_Method =:= round_robin
        orelse Data_Flow_Method =:= broadcast) ->

    %% Start support function processes...
    [Trace_Pid, Log_Pid, Reflect_Pid] =
        [proc_lib:spawn(?MODULE, link_loop, []) || _N <- lists:seq(1,3)],

    %% Start the data task process...
    Worker_Set = case Data_Flow_Method of random -> {}; _Other -> queue:new() end,
    Task_Args = [Node_Fn, Worker_Set, Data_Flow_Method],
    Task_Pid = proc_lib:spawn(coop_node_data_rcv, node_data_loop, Task_Args),

    %% Start the control process...
    Ctl_Args = [Kill_Switch, Task_Pid, Node_Fn, Trace_Pid, Log_Pid, Reflect_Pid],
    Ctl_Pid = proc_lib:spawn(?MODULE, node_ctl_loop, Ctl_Args),

    %% Link all component pids to the Kill_Switch pid and return the Ctl and Data pids.
    link_to_kill_switch(Kill_Switch, [Ctl_Pid, Task_Pid, Trace_Pid, Log_Pid, Reflect_Pid]),
    {Ctl_Pid, Task_Pid}.

node_ctl_clone(Node_Ctl_Pid) -> Node_Ctl_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, clone}.
node_ctl_stop(Node_Ctl_Pid)  -> Node_Ctl_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, stop}.

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
     
node_task_deliver_data(Node_Task_Pid, Data) -> Node_Task_Pid ! Data.


%%----------------------------------------------------------------------
%% Coop Node control functionality.
%%----------------------------------------------------------------------
node_ctl_loop(Kill_Switch, Task_Pid, Node_Fn, Trace_Pid, Log_Pid, Reflect_Pid) ->
    node_ctl_loop(#coop_node{kill_switch=Kill_Switch, ctl=self(), task=Task_Pid, task_fn=Node_Fn,
                             trace=Trace_Pid, log=Log_Pid, reflect=Reflect_Pid}).

node_ctl_loop(#coop_node{} = Coop_Node) ->
    receive
        {?DAG_TOKEN, ?CTL_TOKEN, stop}  -> exit(stopped);
        {?DAG_TOKEN, ?CTL_TOKEN, clone} -> node_clone(Coop_Node), node_ctl_loop(Coop_Node);
        _Skip_Unknown_Msgs              -> node_ctl_loop(Coop_Node)
    end.

node_clone(#coop_node{} = _Coop_Node) -> ok.
