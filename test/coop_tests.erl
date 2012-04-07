%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%   Eunit tests for coop.erl
%%% @since v0.0.1
%%% @end
%%%------------------------------------------------------------------------------
-module(coop_tests).
-copyright("(c) 2011, DuoMark International, Inc.  All rights reserved").
-author(jayn).

%% Spawned to read results asynchronously
-export([receive_pipe_results/0]).

-include_lib("eunit/include/eunit.hrl").

-define(TM, coop).

coop_test_() -> [fun check_pipeline/0].

check_pipeline() ->
    Pid = spawn_link(?MODULE, receive_pipe_results, []),
    PipeProps = coop_flow_tests:example_pipeline_fn_pairs(),
    {FirstStage, Pipeline} = ?TM:pipeline(PipeProps, Pid),
    PipeStats = digraph:info(Pipeline),
    ?assertMatch(acyclic, proplists:get_value(cyclicity, PipeStats)),
    FirstStage ! 7,
    timer:sleep(100),
    ?assertMatch(ok, fetch_results(Pid)).
    

fetch_results(Pid) ->
    Pid ! {fetch, self()},
    receive Any -> Any
    after 3000 -> timeout_waiting
    end.
    
receive_pipe_results() ->
    receive
        3 * (7+2) - 5 -> hold_results(ok);
        Other ->  hold_results({fail, Other})
    after 3000 -> hold_results(timeout)
    end.

hold_results(Results) ->
    receive
        {fetch, From} -> From ! Results
    after 3000 -> timeout
    end.

                                     
            
