%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%    Flow graphs for cooperating processes.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop_flow).

-license("New BSD").
-copyright("(c) 2012, DuoMark International, Inc.  All rights reserved").
-author(jayn).

%% Friendly API
-export([pipeline/1, chain_vertices/2]).


%%----------------------------------------------------------------------
%% Pipeline patterns
%%----------------------------------------------------------------------
pipeline(NameFnPairs) when is_list(NameFnPairs) ->
    case length(NameFnPairs) > 1 of
        true ->
            Graph = digraph:new([acyclic]),
            Vertices = [digraph:add_vertex(Graph, Name, Fn) || {Name, Fn} <- NameFnPairs],
            chain_vertices(Graph, Vertices)
    end.

chain_vertices(Graph, [])   -> Graph;
chain_vertices(Graph, [_H]) -> Graph;
chain_vertices(Graph, [H1,H2 | T]) -> 
    digraph:add_edge(Graph, H1, H2),
    chain_vertices(Graph, [H2 | T]).
