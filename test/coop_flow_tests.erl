%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%   Eunit tests for coop_flow.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop_flow_tests).
-copyright("(c) 2012, DuoMark International, Inc.  All rights reserved").
-author(jayn).

%% Externally available examples for other tests
-export([example_pipeline_fn_pairs/0]).

-include_lib("eunit/include/eunit.hrl").

-define(TM, coop_flow).

example_pipeline_fn_pairs() ->
    %% Pipeline => 3 * (X+2) - 5
    F1 = fun(Num) when is_integer(Num) -> Num + 2 end,
    F2 = fun(Num) when is_integer(Num) -> Num * 3 end,
    F3 = fun(Num) when is_integer(Num) -> Num - 5 end,
    [{a, F1}, {b, F2}, {c, F3}].

coop_flow_test_() -> [fun check_pipeline_too_short/0, fun check_pipeline_ok/0].

check_pipeline_too_short() ->
    ?assertException(error, {case_clause, false}, ?TM:pipeline([a])).

check_pipeline_ok() ->
    PipeProps = example_pipeline_fn_pairs(),
    Pipeline = ?TM:pipeline(PipeProps),
    PipeStats = digraph:info(Pipeline),
    ?assertMatch(acyclic, proplists:get_value(cyclicity, PipeStats)),

    %% Check a -> b -> c...
    ?assertMatch(3, digraph:no_vertices(Pipeline)),
    ?assertMatch(2, digraph:no_edges(Pipeline)),

    %% Unidirectional flow...
    ?assertMatch([a,b,c], digraph:get_path(Pipeline, a, c)),
    ?assertMatch(false,   digraph:get_path(Pipeline, c, a)),
    
    %% Check graph vertices.
    ?assertMatch(3, length(digraph:vertices(Pipeline))),
    [A, B, C] = [proplists:lookup(N, PipeProps) || {N, _Fn} <- PipeProps],
    ?assertMatch(A, digraph:vertex(Pipeline, a)),
    ?assertMatch(B, digraph:vertex(Pipeline, b)),
    ?assertMatch(C, digraph:vertex(Pipeline, c)).
