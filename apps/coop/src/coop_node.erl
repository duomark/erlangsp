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
         busy_loop/0, link_loop/0, make_kill_switch/0,
         node_ctl_loop/6, node_data_loop/4
        ]).

%% System message API functions
-export([
         system_continue/3, system_terminate/4, system_code_change/4,
         format_status/2
         %% , debug_coop/3
        ]).

%% Temporary compiler warning fix
-export([receive_reply/1]).


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

-type single_data_flow_method() :: random | round_robin.
-type multiple_data_flow_method() :: broadcast.
-type data_flow_method() :: single_data_flow_method() | multiple_data_flow_method().

-type task_function() :: {module(), atom()}.
-type downstream_workers() :: queue().


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
-spec node_data_loop(task_function(), downstream_workers(), data_flow_method(), any()) -> no_return().

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
    Debug_Opts = sys:debug_options([]),
    Worker_Set = case Data_Flow_Method of random -> {}; _Other -> queue:new() end,
    Task_Args = [Node_Fn, Worker_Set, Data_Flow_Method, Debug_Opts],
    Task_Pid = proc_lib:spawn(?MODULE, node_data_loop, Task_Args),

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


%%----------------------------------------------------------------------
%% Coop Node data is executed using Node_Fn and the results are
%% passed to one or more of the downstream workers.
%%----------------------------------------------------------------------
node_data_loop(Node_Fn, Downstream_Pids, Data_Flow_Method, Debug_Opts) ->
    receive
        %% 3 types of system messages: stdlib-1.18.1/doc/html/sys.html...
        {'EXIT', _Parent, Reason} -> exit(Reason);
        {system, From, System_Msg} ->
            Sys_Args = {Node_Fn, Downstream_Pids, Data_Flow_Method, Debug_Opts},
            handle_sys(Sys_Args, From, System_Msg);
        {get_modules, From} ->
            From ! {modules, [?MODULE]},
            node_data_loop(Node_Fn, Downstream_Pids, Data_Flow_Method, Debug_Opts);

        %% Node control messages affecting Node_Fn, Pids or Data_Flow_Method...
        {?DAG_TOKEN, ?CTL_TOKEN, Dag_Ctl_Msg} ->
            New_Opts = sys:handle_debug(Debug_Opts, fun debug_coop/3,
                                        Data_Flow_Method, {in, Dag_Ctl_Msg}),
            New_Downstream_Pids = handle_ctl(Downstream_Pids, Data_Flow_Method, Dag_Ctl_Msg),
            node_data_loop(Node_Fn, New_Downstream_Pids, Data_Flow_Method, New_Opts);

        %% All data is passed as is and untagged for processing.
        Data ->
            New_Opts = sys:handle_debug(Debug_Opts, fun debug_coop/3,
                                        Data_Flow_Method, {in, Data}),
            {Final_Debug_Opts, Maybe_Reordered_Pids}
                = relay_data(Data, Node_Fn, Downstream_Pids, Data_Flow_Method, New_Opts),
            node_data_loop(Node_Fn, Maybe_Reordered_Pids, Data_Flow_Method, Final_Debug_Opts)
    end.


%% Handle system and debug messages...
handle_sys({_Node_Fn, _Downstream_Pids, _Data_Flow_Method, Debug_Opts} = Coop_Internals,
           From, System_Msg) ->
    [Parent | _] = get('$ancestors'),
    sys:handle_system_msg(System_Msg, From, Parent, ?MODULE, Debug_Opts, Coop_Internals).

debug_coop(Dev, Event, State) ->
    io:format(Dev, "~p event = ~p~n", [State, Event]).

system_continue(_Parent, New_Debug_Opts,
                {Node_Fn, Downstream_Pids, Data_Flow_Method, _Old_Debug_Opts} = _Misc) ->
    node_data_loop(Node_Fn, Downstream_Pids, Data_Flow_Method, New_Debug_Opts).

system_terminate(Reason, _Parent, _Debug_Opts, _Misc) -> exit(Reason).
system_code_change(Misc, _Module, _OldVsn, _Extra) -> {ok, Misc}.

format_status(normal, [_PDict, SysState, Parent, New_Debug_Opts,
                       {Node_Fn, Downstream_Pids, Data_Flow_Method, _Old_Debug_Opts}]) ->
    Pid_Count = case Data_Flow_Method of
                    random -> tuple_size(Downstream_Pids);
                    _Not_Random ->
                        case Downstream_Pids of
                            {}    -> 0;
                            {_Pid} -> 1;
                            Queue -> queue:len(Queue)
                        end
                end,
    Hdr = "Status for coop_node",
    Log = sys:get_debug(log, New_Debug_Opts, []),
    [{header, Hdr},
     {data, [{"Status",               SysState},
             {"Node_Fn",              Node_Fn},
             {"Downstream_Pid_Count", Pid_Count},
             {"Data_Flow_Method",     Data_Flow_Method},
             {"Parent",               Parent},
             {"Logged events",        Log},
             {"Debug",                New_Debug_Opts}]
     }];

format_status(terminate, StatusData) -> [terminate, StatusData].


%% Control message requests...            
handle_ctl(Downstream_Pids, _Data_Flow_Method, {add_downstream, []}) ->
    Downstream_Pids;
handle_ctl(Downstream_Pids,  Data_Flow_Method, {add_downstream, New_Pids})
  when is_list(New_Pids) ->
    do_add_downstream(Data_Flow_Method, Downstream_Pids, New_Pids);
handle_ctl(Downstream_Pids,  Data_Flow_Method, {get_downstream, {Ref, From}}) ->
    reply_downstream_pids_as_list(Data_Flow_Method, Downstream_Pids, Ref, From),
    Downstream_Pids;
handle_ctl(Downstream_Pids, _Data_Flow_Method, _Unknown_Cmd) ->
    error_logger:info_msg("Unknown DAG Cmd: ~p~n", [_Unknown_Cmd]),
    Downstream_Pids.

do_add_downstream(random, Downstream_Pids, New_Pids) ->
    list_to_tuple(tuple_to_list(Downstream_Pids) ++ New_Pids);

do_add_downstream(_Not_Random, {},     [Pid])    -> {Pid};
do_add_downstream(_Not_Random, {},     New_Pids) -> queue:from_list(New_Pids);
do_add_downstream(_Not_Random, {Pid},  New_Pids) -> queue:from_list([Pid | New_Pids]);
do_add_downstream(_Not_Random, Downstream_Pids, New_Pids) ->
    queue:join(Downstream_Pids, queue:from_list(New_Pids)).

reply_downstream_pids_as_list(random, Downstream_Pids, Ref, From) ->
    From ! {get_downstream, Ref, tuple_to_list(Downstream_Pids)};
reply_downstream_pids_as_list(_Not_Random, Downstream_Pids, Ref, From) ->
    case Downstream_Pids of
        {}    -> From ! {get_downstream, Ref, []};
        {Pid} -> From ! {get_downstream, Ref, [Pid]};
        Queue -> From ! {get_downstream, Ref, queue:to_list(Queue)}
    end.


%% Relay data to all Downstream_Pids...
relay_data(Data, {Module, Function} = _Node_Fn, Worker_Set, broadcast, Debug_Opts) ->
    Fn_Result = Module:Function(Data),
    New_Opts = lists:foldl(fun(To, Opts) ->
                                   To ! Fn_Result,
                                   sys:handle_debug(Opts, fun debug_coop/3,
                                                    broadcast, {out, Fn_Result, To})
                           end, Debug_Opts, queue:to_list(Worker_Set)),
    {New_Opts, Worker_Set};
%% Faster routing if only one Downstream_Pid...
relay_data(Data, {Module, Function} = _Node_Fn, {Pid} = Worker_Set,
           Single_Data_Flow_Method, Debug_Opts) ->
    Fn_Result = Module:Function(Data),
    Pid ! Fn_Result,
    notify_debug_and_return(Debug_Opts, Single_Data_Flow_Method, Pid, Fn_Result, Worker_Set);
%% Relay data with random or round_robin has to choose a single destination.
relay_data(Data, {Module, Function} = _Node_Fn, Worker_Set,
           Single_Data_Flow_Method, Debug_Opts) ->
    {Worker, New_Worker_Set} = choose_worker(Worker_Set, Single_Data_Flow_Method),
    Fn_Result = Module:Function(Data),
    Worker ! Fn_Result,
    notify_debug_and_return(Debug_Opts, Single_Data_Flow_Method, Worker, Fn_Result, New_Worker_Set).

notify_debug_and_return(Debug_Opts, Data_Flow_Method, Pid, Result, Worker_Set) ->
    New_Opts = sys:handle_debug(Debug_Opts, fun debug_coop/3,
                                Data_Flow_Method, {out, Result, Pid}),
    {New_Opts, Worker_Set}.

%% Choose a worker randomly without changing the Worker_Set...
choose_worker(Worker_Set, random) ->
    N = coop_node_util:random_worker(Worker_Set),
    {element(N, Worker_Set), Worker_Set};
%% Grab first worker, then rotate worker list for round_robin.
choose_worker(Worker_Set, round_robin) ->
    {{value, Worker}, Set_Minus_Worker} = queue:out(Worker_Set),
    {Worker, queue:in(Worker, Set_Minus_Worker)}.
