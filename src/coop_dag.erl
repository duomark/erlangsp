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
-export([new/3, new/4, live_node/2]).

%% Loop functions for keeping graph live
%% -export([boot_graph/1, boot_node/3]).

%% External API for obtaining services
%% -export([feed_data/2]).

%% -include("coop_dag.hrl").


%%----------------------------------------------------------------------
%% A Coop Erg is a single worker element of a Coop. Every worker
%% element exists to accept data, transform it and pass it on.
%%
%% There are separate pids for:
%%    1) executing the transform function
%%    2) relaying trace information
%%    3) recording log and telemetry data
%%    4) reflecting the internal state for user display and analysis
%%----------------------------------------------------------------------
%% -record(coop_erg, {
%%           task    :: pid(),
%%           task_fn :: function(),
%%           trace   :: pid(),
%%           log     :: pid(),
%%           reflect :: pid()
%%          }).

%%----------------------------------------------------------------------
%% A Coop contains a template graph, 1 or more coop_ergs and a separate
%% process for the root and control mechanisms. All control and data
%% request packets flow through the coop pid and then on to the root
%% pid of one or more workers.
%%----------------------------------------------------------------------
-record(coop_state, {
          name       :: string(),
          template   :: pid(), %% digraph(),
          %% router_fn  :: function(),
          data       :: pid(),
          control    :: pid(),
          workers    :: queue()
         }).

%%----------------------------------------------------------------------
%% Functions to create coop elements
%%----------------------------------------------------------------------
-type coop() :: pid().

-spec new(string(), digraph(), {module(), atom()}) -> coop() | {error, graph_is_cyclic}.
%% -spec feed_data(coop(), any()) -> ok.
%% -spec feed_cmd(coop(), any()) -> ok.
%% -spec clone_dag(coop()) -> ok.

new(Name, Static_Graph, Root_Vertex) ->
    case proplists:get_value(cyclicity, digraph:info(Static_Graph)) of
        cyclic ->  {error, graph_is_cyclic};
        acyclic ->
            {Root_Vertex, Root_Fn} = digraph:vertex(Static_Graph, Root_Vertex),
            new(Name, Static_Graph, Root_Vertex, enliven(Static_Graph, Root_Vertex, Root_Fn))
    end.

new(Name, _Static_Graph, _Root_Vertex, Live_Graph) ->
    Data_Pid = proc_lib:spawn(?MODULE, boot_data, []),
    Ctl_Pid  = proc_lib:spawn(?MODULE, boot_ctl,  []),
    First_Worker = Data_Pid, %% digraph:copy(Live_Graph),
    Workers = queue:new(),
    Coop_State = #coop_state{name=Name, template=Live_Graph, data=Data_Pid,
                             control=Ctl_Pid, workers=queue:in(First_Worker, Workers)},
    proc_lib:spawn(?MODULE, boot_coop, [Coop_State]).

enliven(Graph, Root_Vertex, Root_Fn) ->
    Root_Pid = proc_lib:spawn(?MODULE, live_node, [Graph, Root_Fn]),
    Root_Pid ! {spawn_vertices, digraph:out_neighbours(Graph, Root_Vertex), Root_Pid},
    Root_Pid.

live_node(Graph, Vertex_Fn) ->
    receive
        
        %% Shutdown quietly...
        {stop} -> ok;

        %% Create a copy of the graph node...
        {{_Ref, From}, clone} ->
            From ! clone, %% {clone, Ref, proc_lib:spawn(Vertex_Fn)},
            live_node(Graph, Vertex_Fn);

        %% Create the downstream graph nodes...
        {spawn_vertices, []} -> live_node(Graph, Vertex_Fn);
        {spawn_vertices, Vertices} ->
            [spawn_live_node(Graph, V, self()) || V <- Vertices],
            live_node(Graph, Vertex_Fn);

        %% Data flowing through, apply the graph node function.
        Other -> Vertex_Fn(Other)
    end.

spawn_live_node(Graph, {_Vertex_Name, Vertex_Fn} = Vertex, _Upstream_Node_Pid)
  when is_function(Vertex_Fn) ->
    Pid = proc_lib:spawn_link(?MODULE, live_node, [Vertex_Fn]),
    Vertices = digraph:out_neighbours(Graph, Vertex),
    Pid ! {spawn_vertices, Vertices}.
    

%% feed_data(Coop, Data) when is_pid(Coop) -> ?DAG_MSG(Coop, ?DATA_TOKEN, Data), ok.
%% feed_cmd(Coop, Cmd) when is_pid(Coop)   -> ?DAG_MSG(Coop, ?CMD_TOKEN, Cmd),   ok

%% clone_dag(Coop) -> feed_cmd(Coop, ?DAG_CLONE).


%% %%----------------------------------------------------------------------
%% %% The coop pid accepts data and control messages.
%% %%----------------------------------------------------------------------

%% boot_coop(#coop_state{template=Dag, data=Data_Pid, control=Ctl_Pid} = State)
%%   when is_pid(Data_Pid), is_pid(Ctl_Pid) ->
%%     case proplists:get_value(cyclicity, digraph:info(Dag)) of
%%         cyclic  -> {failed, cyclic};
%%         acyclic -> case digraph:is_tree(Dag) of
%%                        false -> {failed, not_a_tree};
%%                        true  -> coop_loop(State)
%%                    end
%%     end.
    
%% coop_loop(#coop_dag{template=Dag, data=Data_Pid, control=Ctl_Pid} = State) ->

%%     receive
%%         %% Control msgs are simply sent to the control pid...
%%         {?DAG_TOKEN, ?CONTROL_TOKEN, {_Ref, _From},  _Cmd} = Msg ->
%%             Ctl_Pid  ! Msg, New_State = State;

%%         %% Data messages are farmed to the next worker...
%%         {?DAG_TOKEN, ?DATA_TOKEN,    {_Ref, _From}, _Data} = Msg ->
%%             New_State = State#coop_state{workers=relay_data(Data_Pid, Msg, State#coop_state.workers)};

%%         %% Clone request creates another worker from the DAG template...
%%         {?DAG_TOKEN, ?CLONE_CMD,     {_Ref, _From},  _Cmd} = Msg -> 
%%             New_State = State#coop_state{workers=add_new_worker(Dag, State#coop_state.workers)};

%%         %% Drain unknown messages.
%%         Unknown ->
%%             error_logger:error_msg("~p:~p graph ~p ignored unknown_msg ~p~n",
%%                                    [?MODULE, "coop_loop/1", Unknown]),
%%             New_State = State
%%     end,
%%     ?MODULE:coop_loop(New_State).

%% %% Adding a new worker means stamping a pid-populated DAG and putting it in worker pool.
%% add_new_worker(Dag, Workers) -> [animate_template(Dag) | State#coop_state.workers].
%% animate_template(Dag) -> ok.

%% %% Relaying data requires a worker choice.
%% relay_data(Data_Pid, Msg, Worker_Set) ->
%%     {Worker, New_Worker_Set} = choose_worker(Worker_Set),
%%     Data_Pid ! {single_worker, Worker, Msg},
%%     New_Worker_Set.

%% %% Rotate a queue for round-robin.
%% choose_worker(Worker_Set) ->
%%     {{value, Worker}, Set_Minus_Worker} = queue:out(Worker_Set),
%%     {Worker, queue:in(Worker, Set_Minus_Worker)}.
    

%% %%----------------------------------------------------------------------
%% %% Data and control pids receive inbound data traffic.
%% %%----------------------------------------------------------------------

%% boot_data() -> data_loop().
%% data_loop() ->
%%     receive
%%         {single_worker, Worker_Pid, {?DAG_TOKEN, ?DATA_TOKEN, _Data} = Msg} ->
%%             Worker_Pid ! Msg,
%%             data_loop();

%%         {all_workers, Workers, {?DAG_TOKEN, ?DATA_TOKEN, _Data} = Msg} ->
%%             [Worker_Pid ! Msg || Worker_Pid <- Workers],
%%             data_loop();

%%         %% Drain unknown messages.
%%         Unknown ->
%%             Msg = "~p:~p ignored unknown_msg ~p~n",
%%             error_logger:error_msg(Msg, [?MODULE, "data_loop/0", Unknown]),
%%             data_loop()
%%     end.


%% boot_ctl() -> ctl_loop().
%% ctl_loop() ->
%%     receive
%%         pause  -> ctl_loop();
%%         resume -> ctl_loop();

%%         %% Drain unknown messages.
%%         Unknown ->
%%             Msg = "~p:~p ignored unknown_msg ~p~n",
%%             error_logger:error_msg(Msg, [?MODULE, "ctl_loop/1", Unknown]),
%%             ctl_loop()
%%     end.
