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
-export([pipeline/2]).

%% Exports for spawn_link only
-export([pipe_worker/2]).


pipeline(NameFnPairs, Receiver) ->
    CF = coop_flow:pipeline(NameFnPairs),
    Stages = [digraph:vertex(CF, Name) || {Name, _Fn} <- NameFnPairs],
    {FirstStage, Pipeline} =
        lists:foldr(fun(NameFnPair, {NextStage, Workers}) ->
                            spawn_vertex(NameFnPair, {NextStage, Workers})
                    end, {Receiver, []}, Stages),
    Procs = digraph:new([acyclic]),
    coop_flow:chain_vertices(Procs, Pipeline),
    {FirstStage, Procs}.

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
