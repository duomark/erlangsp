
%% Coop command tokens are uppercase prefixed with '$$_'.
%% Applications should avoid using this prefix for atoms.
-define(DAG_TOKEN,  '$$_DAG').
-define(DATA_TOKEN, '$$_DATA').
-define(CTL_TOKEN,  '$$_CTL').
-define(ROOT_TOKEN, '$$_ROOT').

%% Coop data tokens are uppercase prefixed with '##_'.
%% Applications should avoid using this prefix for atoms.
-define(COOP_NOOP,  '##_NOOP').

-define(CTL_MSG(__Msg),  {?DAG_TOKEN, ?CTL_TOKEN,  __Msg}).
-define(DATA_MSG(__Msg), {?DAG_TOKEN, ?DATA_TOKEN, __Msg}).

-define(COOP_INIT_FN(__Fun, __Args), {?MODULE, __Fun, __Args}).
-define(COOP_TASK_FN(__Fun), {?MODULE, __Fun}).

%% TODO: Convert these to a function call instead of a macro.
-define(SEND_CTL_MSG(__Coop_Node, __Ctl_Msg),
        {coop_node, __Ctl_Pid, __Task_Pid} = __Coop_Node,
        __Ctl_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, __Ctl_Msg}).

-define(SEND_CTL_MSG(__Coop_Node, __Ctl_Msg, __Flag, __Caller),
        {coop_node, __Ctl_Pid, __Task_Pid} = __Coop_Node,
        __Ctl_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, __Ctl_Msg, __Flag, __Caller}).
