
%% Temporary compiler warning fix
-export([receive_reply/1]).

%% TODO: Add 'ephemeral' to use round_robin but expire at end of task
-type single_data_flow_method() :: random | round_robin.
-type multiple_data_flow_method() :: broadcast.
-type data_flow_method() :: single_data_flow_method() | multiple_data_flow_method().

-type task_function() :: {module(), atom()}.
-type downstream_workers() :: queue().

-type coop_head() :: {coop_head, pid(), pid()}.
-type coop_node() :: {coop_node, pid(), pid()}.

-define(DAG_TOKEN,  '$$_DAG').
-define(DATA_TOKEN, '$$_DATA').
-define(CTL_TOKEN,  '$$_CTL').
-define(ROOT_TOKEN, '$$_ROOT').

-define(SEND_CTL_MSG(__Coop_Node, __Ctl_Msg),
        {coop_node, __Ctl_Pid, __Task_Pid} = __Coop_Node,
        __Ctl_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, __Ctl_Msg}).

-define(SEND_CTL_MSG(__Coop_Node, __Ctl_Msg, __Flag, __Caller),
        {coop_node, __Ctl_Pid, __Task_Pid} = __Coop_Node,
        __Ctl_Pid ! {?DAG_TOKEN, ?CTL_TOKEN, __Ctl_Msg, __Flag, __Caller}).

%%----------------------------------------------------------
%% Old code that may be eliminated soon
%%----------------------------------------------------------
-define(DAG_MSG(__Graph, __Type),
        __Ref = make_ref(),
        __Graph ! {?DAG_TOKEN, __Type, {__Ref, self()}},
        receive_reply(__Ref)).
-define(DAG_MSG(__Graph, __Type, __Arg1),
        __Ref = make_ref(),
        __Graph ! {?DAG_TOKEN, __Type, {__Ref, self()}, __Arg1},
        receive_reply(__Ref)).
-define(DAG_MSG(__Graph, __Type, __Arg1, __Arg2),
        begin
            __Ref = make_ref(),
            error_logger:info_msg("~p: ~p ~p ~p ~p ~p~n", [__Graph, ?DAG_TOKEN, __Type, {__Ref, self()}, __Arg1, __Arg2]),
            __Graph ! {?DAG_TOKEN, __Type, {__Ref, self()}, __Arg1, __Arg2},
            receive_reply(__Ref)
        end).
-define(DAG_MSG(__Graph, __Type, __Arg1, __Arg2, __Arg3),
        __Ref = make_ref(),
        __Graph ! {?DAG_TOKEN, __Type, {__Ref, self()}, __Arg1, __Arg2, __Arg3},
        receive_reply(__Ref)).

receive_reply(Ref) ->
    error_logger:info_msg("Waiting for ~p~n", [Ref]),
    receive
        %% Strip the identifiers when returning results...
        {?DAG_TOKEN, Ref, Any} ->
            error_logger:error_msg("Any ~p ~p~n", [Ref, Any]),
            Any;

        %% Drain unexpected messages from the mailbox.
        _Unknown ->
            error_logger:error_msg("Unknown msg ~p in ~p:~p~n", [_Unknown, ?MODULE, receive_reply]),
            receive_reply(Ref)

    after 2000 -> timeout
    end.
