%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%    Process clusters modeled on coop_flow graphs.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop).

-include("../erlangsp/include/license_and_copyright.hrl").
-author(jayn).

%% Friendly API
-export([pipeline/2, fanout/3, fanout_router/2, fanout_router_loop/3]).
-export([relay_data/2, relay_high_priority_data/2]).

%% Exports for spawn_link only
-export([pipe_worker/2]).


%%----------------------------------------------------------------------
%% Pipeline patterns
%%----------------------------------------------------------------------
pipeline(NameFnPairs, Receiver) ->
    pipeline(coop_flow:pipeline(NameFnPairs), NameFnPairs, Receiver).

pipeline(CoopFlow, NameFnPairs, Receiver)
  when is_list(NameFnPairs), is_pid(Receiver) ->
    Stages = [digraph:vertex(CoopFlow, Name) || {Name, _Fn} <- NameFnPairs],
    {FirstStage, Pipeline} =
        lists:foldr(fun(NameFnPair, {NextStage, Workers}) ->
                            spawn_pipeline_stage(NameFnPair, {NextStage, Workers})
                    end, {Receiver, []}, Stages),
    Procs = digraph:new([acyclic]),
    coop_flow:chain_vertices(Procs, Pipeline),
    {FirstStage, CoopFlow, Procs}.

spawn_pipeline_stage({_Name, Fn}, {Receiver, Workers}) ->
    Pid = proc_lib:spawn_link(?MODULE, pipe_worker, [Fn, Receiver]),
    {Pid, [Pid | Workers]}.
    

%% Workers used to execute graph resident functions.
pipe_worker(Fn, NextStage) ->
    receive
        {'$$stop'} -> ok;
        Msg ->
            NextStage ! Fn(Msg),
            pipe_worker(Fn, NextStage)
    end.


%%----------------------------------------------------------------------
%% Fanout patterns
%%----------------------------------------------------------------------
fanout(Fn, NumWorkers, FanInReceiver)
  when is_function(Fn), is_integer(NumWorkers), NumWorkers > 0,
       is_pid(FanInReceiver) ->
    fanout(coop_flow:fanout(Fn, NumWorkers, FanInReceiver), NumWorkers).
    
fanout(CoopFlow, NumWorkers)
  when is_integer(NumWorkers), NumWorkers > 0 ->
    {inbound, Fn} = digraph:vertex(CoopFlow, inbound),
    {outbound, FanInReceiver} = digraph:vertex(CoopFlow, outbound),
    _Vertices = digraph:out_neighbours(CoopFlow, inbound),
    ProcVertices = [proc_lib:spawn_link(?MODULE, fanout_worker, [Fn, FanInReceiver])
                    || _N <- lists:seq(1, NumWorkers)],
    _InPid = proc_lib:spawn_link(?MODULE, fanout_router, [Fn, ProcVertices]).

fanout_router(Fn, ProcVertices) when is_function(Fn), is_list(ProcVertices) ->
    fanout_router_loop(Fn, 1, list_to_tuple(ProcVertices)).

fanout_router_loop(Fn, N, ProcVertices)
  when is_function(Fn), is_integer(N), N > 0, is_tuple(ProcVertices) ->
    receive
        {'$$stop'} -> ok;
        Msg ->
            _NewN = case N >= tuple_size(ProcVertices) of
                        false -> 
                            element(N, ProcVertices) ! Fn(Msg),
                            fanout_router_loop(Fn, N, ProcVertices);
                        true  ->
                            element(1, ProcVertices) ! Fn(Msg),
                            fanout_router_loop(Fn, 2, ProcVertices)
                    end
    end,

    _InPid = proc_lib:spawn_link(?MODULE, fanout_router, [Fn, ProcVertices]).




%%----------------------------------------------------------------------
%% Utilities to treat Coops like Pids
%%----------------------------------------------------------------------

%% Relay data is used to deliver Node output to Coop_Head, Coop_Node or raw Pid.
relay_data(Pid, Data) when is_pid(Pid) ->
    Pid ! Data, ok;
relay_data({coop_head, _Head_Ctl_Pid, _Head_Data_Pid} = Coop_Head, Data) ->
    coop_head:send_data_msg(Coop_Head, Data), ok;
relay_data({coop_node, _Node_Ctl_Pid, _Node_Task_Pid} = Coop_Node, Data) ->
    coop_node:node_task_deliver_data(Coop_Node, Data), ok.

%% High priority only works for a Coop_Head, bypassing all pending Data requests.
relay_high_priority_data({coop_head, _Head_Ctl_Pid, _Head_Data_Pid} = Coop_Head, Data) ->
    coop_head:send_priority_data_msg(Coop_Head, Data), ok;
relay_high_priority_data(Dest, Data) ->
    relay_data(Dest, Data), ok.
