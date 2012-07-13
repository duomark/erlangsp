%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%   Erlang/SP supervisor for graphical display of library execution.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(erlangsp_sup).

-include("license_and_copyright.hrl").
-author(jayn).

-behaviour(supervisor).

%% External API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).


%% ===================================================================
%% API functions
%% ===================================================================

-spec start_link() -> {ok, pid()}.

%% @doc Start the root Erlang/SP supervisor.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, {}).


%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

-spec init(Args::{}) -> {ok, any()}.

%% @doc Placeholder for future supervision.
init({}) ->
    {ok, { {one_for_one, 5, 10}, []} }.

