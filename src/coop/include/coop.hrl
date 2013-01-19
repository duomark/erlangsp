
%% Cooperating Processes (Co-op) data structure definitions

%% A Co-op is a graph of process clusters, split into a Co-op Head and Co-op Body
%% A Co-op Head receives incoming data and feeds it to the Co-op Body
%% Co-op Nodes withing the Co-op Body are linked into a directed graph upon which the data flows
%% Each Co-op Node executes a task function on the data that flows in, passing the result onward
-record(coop_head, {
          ctl_pid  :: pid(),
          data_pid :: pid()
         }).

-record(coop_node, {
          ctl_pid  :: pid(),
          task_pid :: pid()
         }).

-type coop_head() :: #coop_head{} | none.
-type coop_node() :: #coop_node{} | none.
-type coop_body() :: coop_node().

%% A Co-op Instance is a Co-op Head and Co-op Body with live processes populating the graph nodes
-record(coop_instance, {
          id          :: integer(),
          name        :: atom(),
          head = none :: coop_head(),
          body = none :: coop_body(),
          dag         :: digraph()
          }).

-type coop_instance() :: #coop_instance{}.

%% Dataflow methods determine how data is distributed to Co-op instances and
%% within a Fanout Co-op Body to the downstream Co-op Nodes.
-type single_data_flow_method()   :: random | round_robin.
-type multiple_data_flow_method() :: broadcast.
-type data_flow_method() :: single_data_flow_method() | multiple_data_flow_method().

-define(DATAFLOW_TYPES, [random, round_robin, broadcast]).

%% TODO: Add 'select' to execute M:F(A) to determine one or more destinations
%% TODO: Add 'shuffle' to randomly sample without duplicates
%% TODO: Add 'replace' to use replacement policy to select process
%% TODO: Add 'consume' to use round_robin but expire at end of task
%% TODO:   consume requires {Init_Count, Threshold_Count, Replenish_Count}

%% A Co-op is a static Directed Acyclic Graph (DAG) template and a collection of Co-op Instances
%% Each Co-op Instance is a clone of the DAG template, populated with active processes.
%% An ets table is used to allow distributed access to the Co-op Collection (round_robin/random),
%% unless there is only one Coop Instance.
-type coop_collection() :: ets:tid().

%% The attributes of the Coop Collection ets table are standardized.
-define(NEW_COOP_ETS, ets:new(coop, [set, public, {write_concurrency, true},
                                     {keypos, #coop_instance.id}])).
          
-record(coop, {
          instances    :: coop_instance() | coop_collection(),
          dataflow     :: data_flow_method(),
          dag_template :: digraph()
         }).

-type coop() :: #coop{}.

%% Output from a Co-op or internal Co-op Nodes can flow to Pids, other Co-ops, or internal Co-op Nodes
-type coop_receiver() :: pid() | coop() | coop_node() | none.

%% A given Co-op Node can have 0, 1 or N direct receivers of its results.
-type downstream_workers() :: queue() | {coop_receiver()} | {}.

%% A proplist of options (currently only 'access_coop_head') can be specified on Co-op Nodes.
%% If true, access_coop_head exposes the Co-op Head in the arglist of the Node Task Function.
-type coop_data_options() :: [proplists:property()].
-record(coop_node_options, {
          access_coop_head = false :: boolean()
         }).

%% Co-op Nodes are initialized as M:F(Arg) or M:F({Coop_Head, Arg})
%% Generally, use a tuple for the arg structure.
-type coop_init_fn() :: {module(), atom(), any()}.
%% Task functions are Module + Function, with args of (State, Data) or (Coop_Head, State, Data)
-type coop_task_fn() :: {module(), atom()}.

-record(coop_node_fn, {
          init             :: coop_init_fn(),
          task             :: coop_task_fn(),
          options = []     :: coop_data_options(),
          flow = broadcast :: data_flow_method()
         }).

-record(coop_dag_node, {
          name  :: string() | atom(),
          label :: #coop_node_fn{}
         }).

-type coop_dag_node() :: #coop_dag_node{}.
