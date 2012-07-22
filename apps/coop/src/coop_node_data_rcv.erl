%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%    Default receive loop for coop_node data.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop_node_data_rcv).

-include("../erlangsp/include/license_and_copyright.hrl").
-author(jayn).

%% Graph API
-export([node_data_loop/4]).

%% System message API functions
-export([
         system_continue/3, system_terminate/4, system_code_change/4,
         format_status/2, debug_coop/3
        ]).

-include("coop_dag.hrl").


%%----------------------------------------------------------------------
%% Coop Node data is executed using Node_Fn and the results are
%% passed to one or more of the downstream workers.
%%----------------------------------------------------------------------
-spec node_data_loop(task_function(), downstream_workers(), data_flow_method(), any()) -> no_return().

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


%%----------------------------------------------------------------------
%% Control message requests affecting data receive loop
%%----------------------------------------------------------------------
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


%%----------------------------------------------------------------------
%% System, debug and control messages for OTP compatibility
%%----------------------------------------------------------------------
handle_sys({_Node_Fn, _Downstream_Pids, _Data_Flow_Method, Debug_Opts} = Coop_Internals,
           From, System_Msg) ->
    [Parent | _] = get('$ancestors'),
    sys:handle_system_msg(System_Msg, From, Parent, ?MODULE, Debug_Opts, Coop_Internals).

debug_coop(Dev, Event, State) ->
    io:format(Dev, "DBG: ~p event = ~p~n", [State, Event]).

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
