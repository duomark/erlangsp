%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%    Utilities to ease testing
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop_node_util).

-include("../erlangsp/include/license_and_copyright.hrl").
-author(jayn).

-export([random_worker/1]).

random_worker(Worker_Set) -> crypto:rand_uniform(1, tuple_size(Worker_Set)).
