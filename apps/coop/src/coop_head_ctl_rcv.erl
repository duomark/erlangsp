%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%    Coop Head control process receive loop.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop_head_ctl_rcv).

-include("../erlangsp/include/license_and_copyright.hrl").
-author(jayn).

%% Receive loop methods
-export([msg_loop/3]).

-include("../include/coop_dag.hrl").
-include("../include/coop_head.hrl").

%% Exit, initialize, timeout changes and getting the root_pid don't need root_pid involvement...
msg_loop(State, Root_Pid, Timeout) ->
    receive

        %% OTP System message control messages...
        {?DAG_TOKEN, ?CTL_TOKEN, {stop}}    -> exit(stopped);
        {?DAG_TOKEN, ?CTL_TOKEN, {suspend}} -> sys:suspend(Root_Pid), msg_loop(State, Root_Pid, Timeout);
        {?DAG_TOKEN, ?CTL_TOKEN, {resume}}  -> sys:resume(Root_Pid),  msg_loop(State, Root_Pid, Timeout);

        %% State management and access control messages...
        {?DAG_TOKEN, ?CTL_TOKEN, {init_state, #coop_head_state{} = New_State}} ->
            msg_loop(New_State, Root_Pid, Timeout);
        {?DAG_TOKEN, ?CTL_TOKEN, {change_timeout, New_Timeout}} ->
            msg_loop(State, Root_Pid, New_Timeout);
        {?DAG_TOKEN, ?CTL_TOKEN, {get_root_pid, {Ref, From}}} ->
            From ! {get_root_pid, Ref, Root_Pid},
            msg_loop(State, Root_Pid, Timeout);

        %% Priority data messages bypass data queue via control channel,
        %% but can clog control processing waiting for ACKs. The timeout
        %% used is relatively short, and backlog can cause the Coop to
        %% crash, so high priority data should be sent sparingly.
        {?DAG_TOKEN, ?DATA_TOKEN, Data_Msg} ->
            ack = coop_head_data_rcv:relay_msg_to_root_pid(Data_Msg, Root_Pid, Timeout),
            msg_loop(State, Root_Pid, Timeout);

        %% Unrecognized control msgs are forwarded to Root Pid, without regard to how
        %% many messages are currently pending on the Root Pid queue. Sending too many
        %% can cause a high priority data message to crash the entire Coop.
        {?DAG_TOKEN, ?CTL_TOKEN, Ctl_Msg} ->
            Root_Pid ! {?CTL_TOKEN, Ctl_Msg},
            msg_loop(State, Root_Pid, Timeout);

        %% Quit if random data shows up.
        _Unexpected ->
            exit(coop_head_bad_ctl)
    end.
