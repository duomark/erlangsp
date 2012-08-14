%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%    Receive loop for the Root_Pid in the Coop Head.
%%%
%%%    All messages are handled synchronously so that a single message
%%%    source should only send a single message onto the root_pid queue.
%%%    This allows control messages to interleave with data messages,
%%%    effectively bypassing all pending data requests except the
%%%    currently executing data request.
%%%
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop_head_root_rcv).

-include("../erlangsp/include/license_and_copyright.hrl").
-author(jayn).

%% Receive loop methods
-export([sync_pass_thru_loop/1]).

%% System message API functions
-export([
         system_continue/3, system_terminate/4, system_code_change/4,
         format_status/2, debug_coop/3
        ]).

-include("../include/coop_dag.hrl").


-spec sync_pass_thru_loop(coop_node()) -> no_return().

%% Synchronous pass-thru just relays messages, but does so with ack to sender.
sync_pass_thru_loop(Coop_Root_Node) ->
    sync_pass_thru_loop(Coop_Root_Node, sys:debug_options([])).

sync_pass_thru_loop({coop_node, Node_Ctl_Pid, Node_Task_Pid} = Coop_Root_Node, Debug_Opts) ->
    receive
        %% System messages for compatibility with OTP...
        {'EXIT', _Parent, Reason} -> exit(Reason);
        {system, From, System_Msg} ->
            Sys_Args = {pass_thru, Coop_Root_Node, Debug_Opts},
            handle_sys(Sys_Args, From, System_Msg);
        {get_modules, From} ->
            From ! {modules, [?MODULE]},
            sync_pass_thru_loop(Coop_Root_Node, Debug_Opts);

        %% Control messages are not acked...
        {?CTL_TOKEN, Msg} ->
            Node_Ctl_Pid ! Msg,
            sync_pass_thru_loop(Coop_Root_Node, Debug_Opts);

        %% Data messages are acked for flow control.
        {?DATA_TOKEN, {Ref, From}, Msg} ->
            Node_Task_Pid ! Msg,
            From ! {?ROOT_TOKEN, Ref, self()},
            sync_pass_thru_loop(Coop_Root_Node, Debug_Opts);

        %% Crash the process if unexpected data is received.
        _Unexpected -> exit(coop_root_bad_data)
    end.

%%----------------------------------------------------------------------
%% System, debug and control messages for OTP compatibility
%%----------------------------------------------------------------------
-spec system_continue(pid(), [sys:dbg_opt()], term()) -> no_return().
-spec system_terminate(atom(), pid(), [sys:dbg_opt()], term()) -> no_return().
-spec system_code_change(term(), module(), atom(), term()) -> {ok, term()}.
-spec format_status(normal | terminate, list()) -> [proplists:property()].

handle_sys({_Rcv_Loop_Type, _Coop_Root_Node, Debug_Opts} = Coop_Internals, From, System_Msg) ->
    [Parent | _] = get('$ancestors'),
    sys:handle_system_msg(System_Msg, From, Parent, ?MODULE, Debug_Opts, Coop_Internals).

debug_coop(Dev, Event, State) ->
    io:format(Dev, "DBG: ~p event = ~p~n", [State, Event]).

system_continue(_Parent, New_Debug_Opts, {pass_thru, Coop_Root_Node, _Old_Debug_Opts} = _Misc) ->
    sync_pass_thru_loop(Coop_Root_Node, New_Debug_Opts).

system_terminate(Reason, _Parent, _Debug_Opts, _Misc) -> exit(Reason).
system_code_change(Misc, _Module, _OldVsn, _Extra) -> {ok, Misc}.

format_status(normal, [_PDict, SysState, Parent, New_Debug_Opts,
                       {Rcv_Loop_Type, _Coop_Root_Node, _Old_Debug_Opts}]) ->
    Hdr = "Status for coop_head_root",
    Log = sys:get_debug(log, New_Debug_Opts, []),
    [{header, Hdr},
     {data, [{"Status",               SysState},
             {"Loop",                 Rcv_Loop_Type},
             {"Parent",               Parent},
             {"Logged events",        Log},
             {"Debug",                New_Debug_Opts}]
     }];

format_status(terminate, StatusData) -> [{terminate, StatusData}].
