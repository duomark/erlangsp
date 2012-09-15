%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @reference The license is based on the template for Modified BSD from
%%%   <a href="http://opensource.org/licenses/BSD-3-Clause">OSI</a>
%%% @doc
%%%    Flow graphs for cooperating processes.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop_flow).
-author('Jay Nelson <jay@duomark.com>').

-include("../erlangsp/include/license_and_copyright.hrl").

%% Friendly API
-export([pipeline/1, chain_vertices/2, fanout/3]).

-include("coop.hrl").
-include("coop_dag.hrl").


%%----------------------------------------------------------------------
%% Pipeline patterns
%%   pipeline flow is Graph<{Name, Fn}, ...>
%%----------------------------------------------------------------------
-spec pipeline([#coop_dag_node{}]) -> digraph().
-spec chain_vertices(digraph(), [digraph:vertex()]) -> digraph().

pipeline([#coop_dag_node{} | _More] = Node_Fns) ->
    Graph = digraph:new([acyclic]),
    Vertices = [digraph:add_vertex(Graph, Name, Fn)
                || #coop_dag_node{name=Name, label=Fn} <- Node_Fns],
    chain_vertices(Graph, Vertices).

chain_vertices(Graph, [])   -> Graph;
chain_vertices(Graph, [_H]) -> Graph;
chain_vertices(Graph, [H1,H2 | T]) -> 
    digraph:add_edge(Graph, H1, H2),
    chain_vertices(Graph, [H2 | T]).


%%----------------------------------------------------------------------
%% Fanout patterns
%%   fanout flow is Graph<{Name, Fn} => [... {Name, Fn} ...] => {Name, Fn}>
%%----------------------------------------------------------------------
-spec fanout(#coop_dag_node{}, [#coop_dag_node{}], coop_receiver()) -> digraph().

fanout(#coop_dag_node{name=Name, label=Node_Fn} = _Router_Fn,
       [#coop_dag_node{}|_More] = Workers, Fan_In_Receiver) ->
    Graph = digraph:new([acyclic]),
    Inbound = make_named_vertex(Graph, Name, Node_Fn, inbound),
    Outbound = case Fan_In_Receiver of
                   none  -> none;
                   _Node -> digraph:add_vertex(Graph, outbound, Fan_In_Receiver)
               end,
    _Frontier = [begin
                     V = make_named_vertex(Graph, FName, FNode_Fn, worker),
                     digraph:add_edge(Graph, Inbound, V),
                     Outbound =:= none orelse digraph:add_edge(Graph, V, Outbound),
                     V
                 end || #coop_dag_node{name=FName, label=FNode_Fn} <- Workers],
    Graph.


make_named_vertex(Graph, Name, Fn, Default_Name) ->
    Vertex_Name = case Name of undefined -> Default_Name; Name -> Name end,
    digraph:add_vertex(Graph, Vertex_Name, Fn).
