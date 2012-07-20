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

-type restart() :: {supervisor:strategy(), non_neg_integer(), non_neg_integer()}.
-type sup_init_return() :: {ok, {restart(), [supervisor:child_spec()]}}.

-spec init({}) -> sup_init_return().

%% @doc Placeholder for future supervision.
init({}) ->
    {ok, { {one_for_one, 5, 10}, []} }.

