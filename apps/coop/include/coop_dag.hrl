
%% Extra single data flow methods to add:
%%   TODO: Add 'shuffle' to randomly sample without duplicates
%%   TODO: Add 'consume' to use round_robin but expire at end of task
%%          consume requires {Init_Count, Threshold_Count, Replenish_Count}

-type single_data_flow_method() :: random | round_robin.

%% Extra multiple data flow methods to add:
%%    TODO: Add 'multichoice' for selecting subset of nodes

-type multiple_data_flow_method() :: broadcast.

-type data_flow_method() :: single_data_flow_method() | multiple_data_flow_method().

-type downstream_workers() :: queue().

-type coop_task_fn() :: {module(), atom()}.
-type coop_init_fn() :: {module(), atom(), any()}.

-record(coop_node_fn, {
          init              :: coop_init_fn(),
          task              :: coop_task_fn(),
          flow = broadcastn :: data_flow_method()
         }).

-record(coop_dag_node, {
          name  :: string() | atom(),
          label :: #coop_node_fn{}
         }).

-type coop_head() :: {coop_head, pid(), pid()}.
-type coop_node() :: {coop_node, pid(), pid()}.

-type coop_receiver() :: pid() | coop_head() | coop_node() | none.


%% Coop internal tokens are uppercase prefixed with '$$_'.
%% Applications should avoid using this prefix for atoms.
-define(DAG_TOKEN,  '$$_DAG').
-define(DATA_TOKEN, '$$_DATA').
-define(CTL_TOKEN,  '$$_CTL').
-define(ROOT_TOKEN, '$$_ROOT').

%% TODO: Convert these to a function call instead of a macro.
-define(SEND_CTL_MSG(__Coop_Node, __Ctl_Msg),
        {coop_node, __Ctl_Pid, __Task_Pid} = __Coop_Node,
        __Ctl_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, __Ctl_Msg}).

-define(SEND_CTL_MSG(__Coop_Node, __Ctl_Msg, __Flag, __Caller),
        {coop_node, __Ctl_Pid, __Task_Pid} = __Coop_Node,
        __Ctl_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, __Ctl_Msg, __Flag, __Caller}).

