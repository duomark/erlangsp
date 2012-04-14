%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%    Process clusters modeled on coop_flow graphs.
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop).

-license("New BSD").
-copyright("(c) 2012, DuoMark International, Inc.  All rights reserved").
-author(jayn).

%% Friendly API
-export([pipeline/2, fanout/3]).

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
                            spawn_vertex(NameFnPair, {NextStage, Workers})
                    end, {Receiver, []}, Stages),
    Procs = digraph:new([acyclic]),
    coop_flow:chain_vertices(Procs, Pipeline),
    {FirstStage, CoopFlow, Procs}.

spawn_vertex({_Name, Fn}, {Receiver, Workers}) ->
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
    {inbound, _Fn} = digraph:vertex(CoopFlow, inbound),
    {outbound, _FanInReceiver} = digraph:vertex(CoopFlow, outbound),
    _Vertices = digraph:out_neighbours(CoopFlow, inbound).


    
