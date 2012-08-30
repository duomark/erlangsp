%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%    A cache implemented using a process dictionary to manage an index
%%%    of data where each datum is a separate erlang process.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(esp_cache).

-include_lib("erlangsp/include/license_and_copyright.hrl").
-author(jayn).

%% Public API
-export([new_cache_coop/1]).

%% Testing API
-export([new_directory_node/1, new_worker_node/1, new_datum_node/2]).

%% Node setup functions
-export([
         init_directory/1,  value_request/2,    % Directory Coop_Node
         init_mfa_worker/1, make_new_datum/2,   % MFA Worker Coop_Node
         init_datum/1,      manage_datum/2      % Cached Datum Coop_Node
         ]).


%%------------------------------------------------------------------------------
%%
%% Erlang/SP caching is implemented using a Coop pattern.
%%
%% Functionally, there is a Coop_Node for the central directory
%% of data keys which each reference a cached datum. Each datum
%% is held in a separate, dynamic Coop_Node instance. A round-
%% robin pool of workers is used to compute values that are not
%% passed directly to a Coop_Node datum instance, to achieve
%% limited but load-balanced concurrency.
%%
%% Two entries exist per Key:
%%    Key lookup:    Key => Coop_Node
%%    Expired Index: {Key, Coop_Node} => Node_Task_Pid
%%
%% This module includes one comparative implementations:
%%   1) Process dictionary for Keys
%%
%% [Two others are not yet implemented]:
%%   2) Public shared concurrent read ETS table for Keys
%%        - One Coop_Node writing to it
%%   3) Concurrent Coop_Node skiplist for Keys
%%
%% An application which employs this cache can either supply a
%% value directly, or provide {Mod, Fun, Args} to execute which
%% result in a cached value. Supplying a value directly incurs
%% the overhead of passing that value as a message argument to
%% a minimum of 2 processes. Using the MFA approach provides a
%% a way to asynchronously generate a large data structure, or
%% to cache a value which may take a long time to initially
%% compute without the penalty of passing that data, but rather
%% waiting for the MFA to complete before the value is available.
%%
%% A global idle expiration time can be set for cached values,
%% or an external application can implement an expiration policy
%% by explicitly removing values from the cache.
%%
%% Future enhancements are expected to include:
%%   1) Independent functions per datum for computing expiration
%%   2) Invoking a function on cached datum rather than returning it
%%   3) Sumbitting a function to update a cached datum
%%
%%------------------------------------------------------------------------------
-include_lib("coop/include/coop_dag.hrl").
-include("esp_cache.hrl").


%% Coop:
%%   Dir => X workers => | no receiver
%%   Dynamic => Datum workers

new_cache_coop(Num_Workers) ->

    %% Make the cache directory and worker function specifications...
    Cache_Directory = coop:make_dag_node(cache, ?COOP_INIT_FN(init_directory, []),
                                         ?COOP_TASK_FN(value_request), round_robin),
    Workers = [coop:make_dag_node(list_to_atom("worker-" ++ N), ?COOP_INIT_FN(init_mfa_worker, []),
                                  ?COOP_TASK_FN(make_new_datum))
               || N <- lists:seq(1, Num_Workers)],

    %% One cache directory fans out to Num_Workers with no final fan in.
    %% New datum nodes are created dynamically by the workers.
    coop:new_fanout(Cache_Directory, Workers, none).


%%========================= Directory Node =================================

-type coop_proc() :: pid() | coop_head() | coop_node().
-type receiver() :: {reference(), coop_proc()}.

-type value_request() :: {?VALUE, any()} | {?MFA, {module(), atom(), list()}}.
-type change_request() :: {any(), value_request(), receiver()}.
-type change_cmd() :: add | remove | replace.

-type lookup_request() :: {any(), receiver()}.
-type fep_request() :: {any(), value_request(), receiver()}.
-type fetch_cmd() :: lookup | find_else_put.

%% -type stats_cmd() :: num_keys.

-spec value_request({}, {change_cmd(), change_request()}) -> no_return().
-spec change_value ({}, {change_cmd(), change_request()}, coop_proc() | undefined) -> {{}, noop} | {{}, {add, change_request()}}.
-spec return_value ({}, {fetch_cmd(), lookup_request() | fep_request()}, coop_proc() | undefined) -> {{}, noop}.

%% Create a new directory Coop_Node.
new_directory_node(Coop_Head) ->
    Kill_Switch = coop:get_kill_switch(Coop_Head),
    coop_node:new(Kill_Switch, ?COOP_TASK_FN(value_request), ?COOP_INIT_FN(init_directory, {})).

%% No state needed.
init_directory(State) -> State.


%% Modify the cached value process and send the new value to a dynamic downstream coop_node...
value_request(State, {remove,  {Key, _Rcvr}            } = Req) -> change_value(State, Req, get(Key));
value_request(State, {add,     {Key, _Chg_Type, _Rcvr} } = Req) -> change_value(State, Req, get(Key));
value_request(State, {replace, {Key, _Chg_Type, _Rcvr} } = Req) -> change_value(State, Req, get(Key));

%% Return the cached value to a dynamic downstream coop_node...
value_request(State, {lookup,        {Key, _Rcvr}        } = Req) -> return_value(State, Req, get(Key));
value_request(State, {find_else_put, {Key, _Type, _Rcvr} } = Req) -> return_value(State, Req, get(Key));

%% Return the number of active keys...
value_request(State, {num_keys, {Ref, Rcvr}}) ->
    %% 2 entries for each key and proc_lib added '$ancestors' and '$initial_call'
    coop:relay_data(Rcvr, {Ref, (length(get()) - 2) div 2}),
    {State, noop};

%% Expiration of process removes all references to it in process dictionary.
%%  Key => Coop_Node  +  {Key, Coop_Node} => Node_Data_Pid (the monitored Pid that went down)
value_request(State, {'DOWN', _Ref, process, Pid, _Reason}) ->
    [begin erase(Key), erase(Coop_Key) end || {Key, _Coop_Node} = Coop_Key <- get_keys(Pid)],
    {State, noop};

%% New dynamically created Coop_Nodes are monitored and placed in the process dictionary.
value_request(State, {new, Key, {coop_node, _Node_Ctl_Pid, Node_Task_Pid} = Coop_Node}) ->
    erlang:monitor(process, Node_Task_Pid),
    put({Key, Coop_Node}, Node_Task_Pid),
    put(Key, Coop_Node),
    {State, noop}.


%% Terminate the Coop_Node containing the cached value if there is one...
change_value(State, {remove, {_Key, {Ref, Requester}}}, undefined) ->
    coop:relay_data(Requester, {Ref, undefined}),
    {State, noop};
change_value(State, {remove, {Key, {_Ref, _Rqstr} = Requester}}, Coop_Node) ->
    erase(Key),
    erase({Key, Coop_Node}),
    coop:relay_data(Coop_Node, {expire, Requester}),
    {State, noop};

%% Update the Coop_Node containing the cached value...
change_value(State, {replace, {_Key, _Chg_Type,    {_Ref, _Rqstr}}  = New_Value }, undefined) -> value_request(State, {add, New_Value});
change_value(State, {replace, {_Key, {?VALUE, V},  {_Ref, _Rqstr}   = Requester}}, Coop_Node) -> coop:relay_data(Coop_Node, {replace, V, Requester}), {State, noop};
%% But use the downstream worker pool if M:F(A) must be executed to get the value to cache...
change_value(State, {replace, {_Key, {?MFA, _MFA}, {_Ref, _Rqstr}} = Request},     Coop_Node) -> {State, {replace, Request, Coop_Node}};

%% Create a new dynamic Coop_Node containing the cached value using the downstream worker pool.
change_value(State, {add, {_Key, _Chg_Type, {_Ref, _Rqstr}}} = Request, undefined) -> {State, Request};
change_value(State, {add, {_Key, _Chg_Type, {Ref, Requester}}},        _Coop_Node) -> coop:relay_data(Requester, {Ref, defined}), {State, noop}.


%% Send the cached value to the requester.
return_value(State, {find_else_put, {_Key, _Add_Type, _Req}     = Args}, undefined) -> value_request(State, {add, Args});
return_value(State, {lookup,        {_Key, {Ref, Requester}}          }, undefined) -> coop:relay_data(Requester, {Ref, undefined}),       {State, noop};
return_value(State, {_Any_Type,     {_Key, {_Ref, _Rqstr} = Requester}}, Coop_Node) -> coop:relay_data(Coop_Node, {get_value, Requester}), {State, noop}.


%%========================= M:F(A) Worker =================================

%% Create a new worker Coop_Node.
new_worker_node(Coop_Head) ->
    Kill_Switch = coop:get_kill_switch(Coop_Head),
    coop_node:new(Kill_Switch, ?COOP_TASK_FN(make_new_datum), ?COOP_INIT_FN(init_mfa_worker, {Coop_Head, Kill_Switch})).

%% State is used for relaying new entries back to the Cache Directory.
init_mfa_worker({{coop_head, _Node_Ctl_Pid, _Node_Task_Pid}, _Kill_Switch} = State) -> State.


%% Compute the replacement value and forward to the existing Coop_Node...
make_new_datum(State, {replace, {_Key, {?MFA, {Mod, Fun, Args}}, {_Ref, _Rqstr} = Requester}, Coop_Node}) ->
    %% Directory already knows about this datum, using worker for potentially long running M:F(A)
    coop:relay_data(Coop_Node, {replace, Mod:Fun(Args), Requester}),
    {State, noop};

%% Create a new Coop_Node initialized with the value to cache, notifying the Coop_Head directory.
make_new_datum({Coop_Head, Kill_Switch} = State, {add, {Key, {?VALUE, V},  {_Ref, _Rqstr} = Requester}}) ->
    New_Coop_Node = new_datum_node(Kill_Switch, V),
    relay_new_datum(Coop_Head, Key, New_Coop_Node, Requester, State);
make_new_datum({Coop_Head, Kill_Switch} = State, {add, {Key, {?MFA, {Mod, Fun, Args}}, {_Ref, _Rqstr} = Requester}}) ->
    New_Coop_Node = new_datum_node(Kill_Switch, Mod:Fun(Args)),
    relay_new_datum(Coop_Head, Key, New_Coop_Node, Requester, State).

relay_new_datum(Coop_Head, Key, New_Coop_Node, Requester, State) ->
    coop:relay_high_priority_data(Coop_Head, {new, Key, New_Coop_Node}),
    coop:relay_data(New_Coop_Node, {get_value, Requester}),
    {State, noop}.


%%========================= Datum Node ====================================

%% New Datum processes are dynamically created Coop Nodes.
new_datum_node(Kill_Switch, V) ->
    coop_node:new(Kill_Switch, ?COOP_TASK_FN(manage_datum), ?COOP_INIT_FN(init_datum, V)).
    
    
%% Initialize the Coop_Node with the value to cache.
init_datum(V) -> V.

%% Cached datum is relayed to requester, no downstream listeners.
manage_datum( Datum, {expire,               {Ref, Requester}} ) -> coop:relay_data(Requester, {Ref, Datum}), exit(normal);
manage_datum( Datum, {get_value,            {Ref, Requester}} ) -> coop:relay_data(Requester, {Ref, Datum}), {Datum, noop};
manage_datum(_Datum, {replace,   New_Value, {Ref, Requester}} ) -> coop:relay_data(Requester, {Ref, New_Value}), {New_Value, noop}.
