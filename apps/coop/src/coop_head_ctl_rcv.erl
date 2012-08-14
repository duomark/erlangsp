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
-export([msg_loop/2]).

-include("../include/coop_dag.hrl").
-include("../include/coop_head.hrl").


%% Exit, initialize, timeout changes and getting the root_pid don't need root_pid involvement...
msg_loop(State, Root_Pid) ->
    receive

        %% OTP System message control messages...
        {?DAG_TOKEN, ?CTL_TOKEN, {stop}}    -> exit(stopped);
        {?DAG_TOKEN, ?CTL_TOKEN, {suspend}} -> sys:suspend(Root_Pid), msg_loop(State, Root_Pid);
        {?DAG_TOKEN, ?CTL_TOKEN, {resume}}  -> sys:resume(Root_Pid),  msg_loop(State, Root_Pid);

        %% State management and access control messages...
        {?DAG_TOKEN, ?CTL_TOKEN, {init_state, #coop_head_state{} = New_State}} ->
            msg_loop(New_State, Root_Pid);
        {?DAG_TOKEN, ?CTL_TOKEN, {get_root_pid, {Ref, From}}} ->
            From ! {get_root_pid, Ref, Root_Pid},
            msg_loop(State, Root_Pid);

        %% Unrecognized msgs are forwarded to Root Pid, without regard to how
        %% many messages are currently pending on the Root Pid queue.
        {?DAG_TOKEN, ?CTL_TOKEN, Msg} ->
            Root_Pid ! {?CTL_TOKEN, Msg},
            msg_loop(State, Root_Pid)
    end.
            
