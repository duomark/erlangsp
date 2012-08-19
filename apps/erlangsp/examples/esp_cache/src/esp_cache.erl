%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%    A cache implemented using a process dictionary to manage an index
%%%    of data where each datum is a separate process.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(esp_cache).

-include_lib("erlangsp/include/license_and_copyright.hrl").
-author(jayn).

%% Friendly API
-export([
         value_request/1,               %% Directory Coop_Node
         new_datum_node/2, init_datum/1, manage_datum/2   %% Datum Coop_Node
        ]).


%%------------------------------------------------------------------------------
%%
%% Erlang/SP caching is implemented using a Coop pattern.
%%
%% Functionally, there is a Coop_Node for the central directory
%% of data keys which each reference a cached datum. Each datum
%% is held in a separate, dynamic Coop_Node instance. A round-
%% robin pool of workers is used to compute values that are not
%% passed directly to a Coop_Node datum instance.
%%
%% Two entries exist per Key:
%%    Key lookup:    Key => Coop_Node
%%    Expired Index: {Key, Coop_Node} => Node_Task_Pid
%%
%% This module includes three comparative implementations:
%%   1) Process dictionary for Keys
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

-define(VALUE, '$$_value').
-define(MFA,   '$$_mfa').

%%========================= Directory Node =================================

-type coop_proc() :: pid() | coop_head() | coop_node().
-type receiver() :: {reference(), coop_proc()}.

-type value_request() :: {?VALUE, any()} | {?MFA, {module(), atom(), list()}}.
-type change_request() :: {any(), value_request(), receiver()}.
-type change_cmd() :: add | remove | replace.

-type lookup_request() :: {any(), receiver()}.
-type fep_request() :: {any(), value_request(), receiver()}.
-type fetch_cmd() :: lookup | find_else_put.

-spec value_request({change_cmd(), change_request()}) -> no_return().
-spec change_value({change_cmd(), change_request()}, coop_proc() | undefined) -> no_return().
-spec return_value({fetch_cmd(), lookup_request() | fep_request()}, coop_proc() | undefined) -> no_return().

%% Modify the cached value process and send the new value to a dynamic downstream coop_node...
value_request({remove,  {Key, _Rcvr}            } = Req) -> change_value(Req, get(Key));
value_request({add,     {Key, _Chg_Type, _Rcvr} } = Req) -> change_value(Req, get(Key));
value_request({replace, {Key, _Chg_Type, _Rcvr} } = Req) -> change_value(Req, get(Key));

%% Return the cached value to a dynamic downstream coop_node...
value_request({lookup,        {Key, _Rcvr}        } = Req) -> return_value(Req, get(Key));
value_request({find_else_put, {Key, _Type, _Rcvr} } = Req) -> return_value(Req, get(Key));

%% Expiration of process removes all references to it in process dictionary.
%%  Key => Coop_Node  +  {Key, Coop_Node} => Node_Data_Pid (the monitored Pid that went down)
value_request({'DOWN', _Ref, process, Pid, _Reason}) ->
    [begin erase(Key), erase(Coop_Key) end || {Key, _Coop_Node} = Coop_Key <- get_keys(Pid)],
    noop;

%% New dynamically created Coop_Nodes are monitored and placed in the process dictionary.
value_request({new, Key, {coop_node, _Node_Ctl_Pid, Node_Task_Pid}} = Coop_Node) ->
    erlang:monitor(process, Node_Task_Pid),
    put({Key, Coop_Node}, Node_Task_Pid),
    put(Key, Coop_Node).



%% Terminate the Coop_Node containing the cached value if there is one...
change_value({remove,  {_Key, {Ref, Requester}          }}, undefined) -> coop:relay_data(Requester, {Ref, undefined}),    noop;
change_value({remove,  {_Key, {_Ref, _Rqstr} = Requester}}, Coop_Node) -> coop:relay_data(Coop_Node, {expire, Requester}), noop;

%% Update the Coop_Node containing the cached value...
change_value({replace, {_Key, _Chg_Type,    {_Ref, _Rqstr}}  = New_Value }, undefined) -> value_request({add, New_Value});
change_value({replace, {_Key, {?VALUE, V},  {_Ref, _Rqstr}   = Requester}}, Coop_Node) -> coop:relay_data(Coop_Node, {replace, V, Requester}), noop;
%% But use the downstream worker pool if M:F(A) must be executed to get the value to cache...
change_value({replace, {_Key, {?MFA, _MFA}, {_Ref, _Rqstr}} = Request},     Coop_Node) -> {replace, Request, Coop_Node};

%% Create a new dynamic Coop_Node containing the cached value using the downstream worker pool.
change_value({add, {_Key, _Chg_Type, {_Ref, _Rqstr}}} = Request, undefined) -> Request;
change_value({add, {_Key, _Chg_Type, {Ref, Requester}}},        _Coop_Node) -> coop:relay_data(Requester, {Ref, defined}), noop.


%% Send the cached value to the requester.
return_value({find_else_put, {_Key, _Add_Type, _Req}     = Args}, undefined) -> value_request({add, Args});
return_value({lookup,        {_Key, {Ref, Requester}}          }, undefined) -> coop:relay_data(Requester, {Ref, undefined}),       noop;
return_value({_Any_Type,     {_Key, {_Ref, _Rqstr} = Requester}}, Coop_Node) -> coop:relay_data(Coop_Node, {get_value, Requester}), noop.


%%========================= M:F(A) Worker =================================

%% %% No state needed.
%% init_mfa_worker() -> {}.


%% %% Compute the replacement value and forward to the existing Coop_Node...
%% make_new_datum({}, {replace, {Key, {?MFA, {Mod, Fun, Args}}, {_Ref, _Rqstr} = Requester}}, Coop_Node) ->
%%     coop:relay_data(Coop_Node, {replace, Mod:Fun(Args), Requester}),
%%     {{}, noop};

%% %% Create a new Coop_Node initialized with the value to cache, notifying the Coop_Head directory.
%% make_new_datum({}, {add, {Key, {?VALUE, V},  {_Ref, _Rqstr} = Requester}}, Coop_Node) ->
%%     coop:relay_high_priority_data(Kill_Switch, {new, Key, new_datum_node(Kill_Switch, V)}),
%%     {{}, noop};
%% make_new_datum({}, {add, {Key, {?MFA, {Mod, Fun, Args}}, {_Ref, _Rqstr} = Requester}}, Coop_Node) ->
%%     coop:relay_high_priority_data(Kill_Switch, {new, Key, new_datum_node(Kill_Switch, Mod:Fun(Args)}),
%%     {{}, noop}.


%%========================= Datum Node ====================================

new_datum_node(Kill_Switch, V) -> coop_node:new(Kill_Switch, {?MODULE, manage_datum}, {?MODULE, init_datum, V}).

-record(pv_state, {value :: any()}).

%% Initialize the Coop_Node with the value to cache.
init_datum(V) -> #pv_state{value=V}.


%% Cached datum is relayed to requester, no downstream listeners.
manage_datum(#pv_state{value=Datum} = State, {get_value, {Ref, Requester}} ) -> coop:relay_data(Requester, {Ref, Datum}), {State, noop};
manage_datum(#pv_state{} = State,  {replace, New_Value,  {Ref, Requester}} ) -> coop:relay_data(Requester, {Ref, New_Value}), {State#pv_state{value=New_Value}, noop};
manage_datum(#pv_state{} = _State, {expire,              {_Ref,   _Rqstr}} ) -> exit(normal).
