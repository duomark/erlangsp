%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @reference The license is based on the template for Modified BSD from
%%%   <a href="http://opensource.org/licenses/BSD-3-Clause">OSI</a>
%%% @doc
%%%    Utilities to ease testing
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop_node_util).
-author('Jay Nelson <jay@duomark.com>').

-include("../erlangsp/include/license_and_copyright.hrl").

-export([random_worker/1]).

random_worker(Worker_Set) -> crypto:rand_uniform(1, tuple_size(Worker_Set)).
