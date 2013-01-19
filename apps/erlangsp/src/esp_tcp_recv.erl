%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%    Receive loop for esp_tcp_service connections.
%%% @since v0.0.2
%%% @end
%%%------------------------------------------------------------------------------
-module(esp_tcp_recv).

-include_lib("erlangsp/include/license_and_copyright.hrl").
-author('Jay Nelson <jay@duomark.com>').

%% Public API
-export([active_loop/2, passive_loop/2]).

active_loop(Socket, Handler) ->
    inet:setopts(Socket, [{active, once}]),
    receive
        {tcp, Socket, Data} ->
            try Handler:recv(Data)
            after active_loop(Socket, Handler)
            end;
        {tcp_error, Socket, Reason} ->
            try Handler:recv_error(Reason)
            after active_loop(Socket, Handler)
            end;
        {tcp_closed, Socket} ->
            try Handler:recv_closed()
            catch _:_ -> ok
            end,
            tcp_closed;
        Other ->
            error_logger:info_msg("Other: ~p ~p~n", [Other, self()]),
            active_loop(Socket, Handler)
    end.

passive_loop(_Socket, _Handler) ->
    ok.

