
-define(DAG_TOKEN,  '$$_DAG').
-define(DATA_TOKEN, '$$_DATA').
-define(CTL_TOKEN,  '$$_CTL').

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
