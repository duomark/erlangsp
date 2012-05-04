%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%    Directed Acyclic Graphs (DAGs) implemented with a process per node.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop_dag).

-license("New BSD").
-copyright("(c) 2012, DuoMark International, Inc.  All rights reserved").
-author(jayn).

%% Graph API
-export([new/1, add_vertex/3, add_edge/3, vertex_id/2]).

%% Loop functions for keeping graph live
-export([boot_graph/1, boot_node/3]).

%% External API for obtaining services
-export([feed_data/2]).

-include("coop_dag.hrl").

-record(coop_dag, {
          fn      :: function(),
          root    :: pid(),
          control :: pid(),
          trace   :: pid(),
          graph   :: digraph()
         }).


%%----------------------------------------------------------------------
%% A graph is represented by 2 processes:
%%    Graph: container of all nodes, used for adding nodes
%%    Root:  root pid node of graph, used for actual graph activity
%%----------------------------------------------------------------------
new(Fn) when is_function(Fn) ->
    Root = proc_lib:spawn(?MODULE, boot_node, [self(), Fn, '$root']),
    proc_lib:spawn(?MODULE, boot_graph, [#coop_dag{fn=Fn, root=Root}]).

add_vertex(Graph, Name, Fn) when is_pid(Graph) ->
    {added_vertex, {Name, _Pid} = Vertex_Id}
        = ?DAG_MSG(Graph, add_vertex, Name, Fn),
    Vertex_Id.

add_edge(Graph, Node1, Node2) when is_pid(Graph) ->
    {added_edge, {Node1, Node2} = Node_Pair}
        = ?DAG_MSG(Graph, add_edge, Node1, Node2),
    Node_Pair.

feed_data(Graph, Data) when is_pid(Graph) ->
    ?DAG_MSG(Graph, ?DATA_TOKEN, Data),
    ok.

vertex_id(_Graph, Node) ->    
    {vertex_id, Vertex_Id} = ?DAG_MSG(Node, vertex_id),
    Vertex_Id.


%%----------------------------------------------------------------------
%% Live graph logic loop
%%
%%   The graph instance is a loop that 
%%----------------------------------------------------------------------

boot_graph(#coop_dag{} = State) ->
    graph_loop(State#coop_dag{graph = digraph:new([acyclic])}). 
    
graph_loop(#coop_dag{graph=Graph, root=Root} = State) ->
    receive

        %% Graph construction messages...
        {?DAG_TOKEN, add_vertex, {Ref, From}, Name, Fn} ->
                From ! start,
            Pid = proc_lib:spawn_link(?MODULE, boot_node, [self(), Name, Fn]),
            Vertex_Id = {Name, Pid},
            Vertex_Id = digraph:add_vertex(Graph, Vertex_Id, Fn),
            From ! {?DAG_TOKEN, Ref, {added_vertex, Vertex_Id}};

        {?DAG_TOKEN, add_edge, {Ref, From}, Node1, Node2} ->
            digraph:add_edge(Graph, Node1, Node2),
            Node1 ! {?DAG_TOKEN, self(), add_child, Node2},
            From ! {?DAG_TOKEN, Ref, {added_edge, {Node1, Node2}}};

        %% Data processing messages...
        {?DAG_TOKEN, ?DATA_TOKEN, {_Ref, _From}, _Data} = Msg ->
            Root ! Msg;

        %% Drain unknown messages.
        Unknown ->
            error_logger:error_msg("~p:~p graph ~p ignored unknown_msg ~p~n",
                                   [?MODULE, "graph_loop/1", Graph, Unknown])
    end,
    ?MODULE:graph_loop(State).


%%----------------------------------------------------------------------
%% Live node logic loop
%%----------------------------------------------------------------------

-record(coop_dag_node, {
          graph     :: pid(),
          vertex    :: {any(), pid()},
          fn        :: function(),
          kids = [] :: [pid()]
         }).

boot_node(Graph_Pid, Name, Node_Fn) when is_function(Node_Fn, 1) ->
    node_loop(#coop_dag_node{graph=Graph_Pid, fn=Node_Fn, vertex=Name}).

node_loop(#coop_dag_node{graph=Graph, fn=Fn, kids=Kids, vertex=Vertex_Id} = State) ->
    receive
        {?DAG_TOKEN, Graph, {ref, From}, vertex_id} ->
            From ! {vertex_id, {Vertex_Id, self()}},
            node_loop(State);

        {?DAG_TOKEN, Graph, add_child, Node} ->
            node_loop(State#coop_dag_node{kids = [Node|Kids]});

        {?DAG_TOKEN, ?DATA_TOKEN, Msg} ->
            [Kid ! {?DAG_TOKEN, ?DATA_TOKEN, Fn(Msg)} || Kid <- Kids],
            node_loop(State);

        %% Drain unknown messages.
        Unknown ->
            Msg = "~p:~p graph ~p node ~p ignored unknown_msg ~p~n",
            error_logger:error_msg(Msg, [?MODULE, "node_loop/1", Graph, Vertex_Id, Unknown]),
            node_loop(State)
    end.

