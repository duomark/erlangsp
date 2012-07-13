%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%   Erlang/SP application for graphical display of library execution.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(erlangsp_app).

-include("license_and_copyright.hrl").
-author(jayn).

-behaviour(application).

%% Application callbacks
-export([start/0, start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

-spec start() -> {ok, pid()}.
-spec start(any(), any()) -> {ok, pid()}.
-spec stop([]) -> ok.

%% @doc Start the application's root supervisor in erl listener.
start() ->
    erlangsp_sup:start_link().

%% @doc Start the application's root supervisor from boot.
start(_StartType, _StartArgs) ->
    erlangsp_sup:start_link().

%% @doc Stop the application.
stop(_State) -> ok.
