%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @reference The license is based on the template for Modified BSD from
%%%   <a href="http://opensource.org/licenses/BSD-3-Clause">OSI</a>
%%% @doc
%%%    Coop Head control process receive loop.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop_head_ctl_rcv).
-author('Jay Nelson <jay@duomark.com>').

-include("../erlangsp/include/license_and_copyright.hrl").

%% Receive loop methods
-export([msg_loop/3]).

%% System message API functions
-export([
         system_continue/3, system_terminate/4, system_code_change/4,
         format_status/2, debug_coop/3
        ]).

-include("coop.hrl").
-include("coop_dag.hrl").
-include("coop_head.hrl").

%% Exit, initialize, timeout changes and getting the root_pid don't need root_pid involvement...
msg_loop(State, Root_Pid, Timeout) ->
    msg_loop(State, Root_Pid, Timeout, sys:debug_options([])).

%% Until init finished, respond only to OTP and receiving an initial state record.
msg_loop({} = State, Root_Pid, Timeout, Debug_Opts) ->
    receive
        %% System messages for compatibility with OTP...
        {'EXIT', _Parent, Reason} -> exit(Reason);
        {system, From, System_Msg} ->
            Sys_Args = {State, Root_Pid, Timeout, Debug_Opts},
            handle_sys(Sys_Args, From, System_Msg);
        {get_modules, From} ->
            From ! {modules, [?MODULE]},
            msg_loop(State, Root_Pid, Timeout, Debug_Opts);
        {?DAG_TOKEN, ?CTL_TOKEN, {init_state, #coop_head_state{} = New_State}} ->
            msg_loop(New_State, Root_Pid, Timeout, Debug_Opts)
    end;

%% Normal message loop after initial state is received.
msg_loop(#coop_head_state{} = State, Root_Pid, Timeout, Debug_Opts) ->
    receive
        %% System messages for compatibility with OTP...
        {'EXIT', _Parent, Reason} -> exit(Reason);
        {system, From, System_Msg} ->
            Sys_Args = {State, Root_Pid, Timeout, Debug_Opts},
            handle_sys(Sys_Args, From, System_Msg);
        {get_modules, From} ->
            From ! {modules, [?MODULE]},
            msg_loop(State, Root_Pid, Timeout, Debug_Opts);

        %% Coop System message control messages...
        {?DAG_TOKEN, ?CTL_TOKEN, {stop}} ->
            exit(stopped);
        {?DAG_TOKEN, ?CTL_TOKEN, {suspend}} ->
            sys:suspend(Root_Pid),
            msg_loop(State, Root_Pid, Timeout, Debug_Opts);
        {?DAG_TOKEN, ?CTL_TOKEN, {resume}} ->
            sys:resume(Root_Pid),
            msg_loop(State, Root_Pid, Timeout, Debug_Opts);
        {?DAG_TOKEN, ?CTL_TOKEN, {stats, Flag, {Ref, From}}} ->
            From ! {stats, Ref, sys:statistics(Root_Pid, Flag)},
            msg_loop(State, Root_Pid, Timeout, Debug_Opts);
        {?DAG_TOKEN, ?CTL_TOKEN, {format_status}} ->
            State#coop_head_state.log ! sys:get_status(Root_Pid),
            msg_loop(State, Root_Pid, Timeout, Debug_Opts);
        {?DAG_TOKEN, ?CTL_TOKEN, {log, Flag, {Ref, From}}} ->
            From ! {log, Ref, sys:log(Root_Pid, Flag)},
            msg_loop(State, Root_Pid, Timeout, Debug_Opts);
        {?DAG_TOKEN, ?CTL_TOKEN, log_to_file, File,  {Ref, From}} ->
            From ! {log_to_file, Ref, sys:log_to_file(Root_Pid, File)},
            msg_loop(State, Root_Pid, Timeout, Debug_Opts);

        %% State management and access control messages...
        {?DAG_TOKEN, ?CTL_TOKEN, {change_timeout, New_Timeout}} ->
            msg_loop(State, Root_Pid, New_Timeout, Debug_Opts);
        {?DAG_TOKEN, ?CTL_TOKEN, {get_kill_switch, {Ref, From}}} ->
            From ! {get_kill_switch, Ref, State#coop_head_state.kill_switch},
            msg_loop(State, Root_Pid, Timeout, Debug_Opts);
        {?DAG_TOKEN, ?CTL_TOKEN, {get_root_pid, {Ref, From}}} ->
            From ! {get_root_pid, Ref, Root_Pid},
            msg_loop(State, Root_Pid, Timeout, Debug_Opts);
        {?DAG_TOKEN, ?CTL_TOKEN, {set_root_node, {coop_node, _, _} = Coop_Node, {Ref, From}} = Msg} ->
            case State#coop_head_state.coop_root_node of
                none ->
                    Root_Pid ! {?CTL_TOKEN, Msg},
                    New_State = State#coop_head_state{coop_root_node=Coop_Node},
                    msg_loop(New_State, Root_Pid, Timeout, Debug_Opts);
                _Already_Set ->
                    From ! {set_root_node, Ref, false},
                    msg_loop(State, Root_Pid, Timeout, Debug_Opts)
            end;

        %% Priority data messages bypass data queue via control channel,
        %% but can clog control processing waiting for ACKs. The timeout
        %% used is relatively short, and backlog can cause the Coop to
        %% crash, so high priority data should be sent sparingly.
        {?DAG_TOKEN, ?DATA_TOKEN, Data_Msg} ->
            ack = coop_head_data_rcv:relay_msg_to_root_pid(Data_Msg, Root_Pid, Timeout),
            msg_loop(State, Root_Pid, Timeout, Debug_Opts);

        %% Unrecognized control msgs are forwarded to Root Pid, without regard to how
        %% many messages are currently pending on the Root Pid queue. Sending too many
        %% can cause a high priority data message to crash the entire Coop.
        {?DAG_TOKEN, ?CTL_TOKEN, Ctl_Msg} ->
            Root_Pid ! {?CTL_TOKEN, Ctl_Msg},
            msg_loop(State, Root_Pid, Timeout, Debug_Opts);

        %% Quit if random data shows up.
        _Unexpected ->
            exit(coop_head_bad_ctl)
    end.

%%----------------------------------------------------------------------
%% System, debug and control messages for OTP compatibility
%%----------------------------------------------------------------------
-spec system_continue(pid(), [sys:dbg_opt()], term()) -> no_return().
-spec system_terminate(atom(), pid(), [sys:dbg_opt()], term()) -> no_return().
-spec system_code_change(term(), module(), atom(), term()) -> {ok, term()}.
-spec format_status(normal | terminate, list()) -> [proplists:property()].

handle_sys({_State, _Root_Pid, _Timeout, Debug_Opts} = Ctl_Internals, From, System_Msg) ->
    [Parent | _] = get('$ancestors'),
    sys:handle_system_msg(System_Msg, From, Parent, ?MODULE, Debug_Opts, Ctl_Internals).

debug_coop(Dev, Event, State) ->
    io:format(Dev, "DBG: ~p event = ~p~n", [State, Event]).

system_continue(_Parent, New_Debug_Opts, {State, Root_Pid, Timeout, _Old_Debug_Opts} = _Misc) ->
    msg_loop(State, Root_Pid, Timeout, New_Debug_Opts).

system_terminate(Reason, _Parent, _Debug_Opts, _Misc) -> exit(Reason).
system_code_change(Misc, _Module, _OldVsn, _Extra) -> {ok, Misc}.

format_status(normal, [_PDict, Sys_State, Parent, New_Debug_Opts,
                       {_State, _Root_Pid, _Timeout, _Old_Debug_Opts}]) ->
    Hdr = "Status for " ++ atom_to_list(?MODULE),
    Log = sys:get_debug(log, New_Debug_Opts, []),
    [{header, Hdr},
     {data, [{"Status",          Sys_State},
             {"Parent",          Parent},
             {"Logged events",   Log},
             {"Debug",           New_Debug_Opts}]
     }];

format_status(terminate, Status_Data) -> [{terminate, Status_Data}].
