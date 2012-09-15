%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @reference The license is based on the template for Modified BSD from
%%%   <a href="http://opensource.org/licenses/BSD-3-Clause">OSI</a>
%%% @doc
%%%    Coop Head data process receive loop.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop_head_data_rcv).
-author('Jay Nelson <jay@duomark.com>').

-include("../erlangsp/include/license_and_copyright.hrl").

%% Receive loop methods
-export([one_at_a_time_loop/2, relay_msg_to_root_pid/3]).

-include("coop.hrl").
-include("coop_dag.hrl").


-spec one_at_a_time_loop(pid(), pos_integer() | none) -> no_return().
            
%% One-at-a-time sends one synchronous message (waits for the ack) before the next.
one_at_a_time_loop(Root_Pid, Timeout) ->
    receive

        %% Ctl tag is used for meta-data about the data process...
        {?DAG_TOKEN, ?CTL_TOKEN, {change_timeout, New_Timeout}} ->
            one_at_a_time_loop(Root_Pid, New_Timeout);

        %% Data must be tagged as such to be processed...
        {?DAG_TOKEN, ?DATA_TOKEN, Data_Msg} ->
            ack = relay_msg_to_root_pid(Data_Msg, Root_Pid, Timeout),
            one_at_a_time_loop(Root_Pid, Timeout);

        %% Quit if random data shows up.
        _Unexpected ->
            exit(coop_head_bad_data)
    end.

relay_msg_to_root_pid(Msg, Root_Pid, Timeout) ->
    
    %% New ref causes selective receive optimization when looking for ACK.
    Ref = make_ref(),
    Root_Pid ! {?DATA_TOKEN, {Ref, self()}, Msg},

    %% Wait for Root_Pid to ack the receipt of data.
    case Timeout of
        none -> receive {?ROOT_TOKEN, Ref, Root_Pid} -> ack end;
        Milliseconds when is_integer(Milliseconds), Milliseconds > 0 ->
            receive {?ROOT_TOKEN, Ref, Root_Pid} -> ack
            after Timeout -> exit(root_ack_timeout)
            end
    end.
