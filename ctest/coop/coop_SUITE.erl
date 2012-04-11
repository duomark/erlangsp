-module(coop_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1
         %% init_per_testcase/2, end_per_testcase/2
        ]).
-export([coop_flow/1, coop/1]).
-export([receive_pipe_results/0]).
 
all() -> [coop_flow, coop].

example_pipeline_fn_pairs() ->
    %% Pipeline => 3 * (X+2) - 5
    F1 = fun(Num) when is_integer(Num) -> Num + 2 end,
    F2 = fun(Num) when is_integer(Num) -> Num * 3 end,
    F3 = fun(Num) when is_integer(Num) -> Num - 5 end,
    [{a, F1}, {b, F2}, {c, F3}].

init_per_suite(Config) -> Config.
end_per_suite(_Config) -> ok.

%% init_per_group(pipeline, _Config) -> ok.
%% end_per_group(Name, _Config) -> ok.

%% init_per_testcase(_Any, _Config) -> ok.
%% end_per_testcase(_Any, _Config) ->  ok.

coop_flow(_Config) ->
    try coop_flow:pipeline([a])
    catch error:{case_clause, false} -> ok
    end,

    PipeProps = example_pipeline_fn_pairs(),
    Pipeline = coop_flow:pipeline(PipeProps),
    PipeStats = digraph:info(Pipeline),
    acyclic = proplists:get_value(cyclicity, PipeStats),

    %% Check a -> b -> c...
    3 = digraph:no_vertices(Pipeline),
    2 = digraph:no_edges(Pipeline),

    %% Unidirectional flow...
    [a,b,c] = digraph:get_path(Pipeline, a, c),
    false   = digraph:get_path(Pipeline, c, a),
    
    %% Check graph vertices.
    3 = length(digraph:vertices(Pipeline)),
    [A, B, C] = [proplists:lookup(N, PipeProps) || {N, _Fn} <- PipeProps],
    A = digraph:vertex(Pipeline, a),
    B = digraph:vertex(Pipeline, b),
    C = digraph:vertex(Pipeline, c).

coop(_Config) ->
    Pid = spawn_link(?MODULE, receive_pipe_results, []),
    PipeProps = example_pipeline_fn_pairs(),
    {FirstStage, Pipeline} = coop:pipeline(PipeProps, Pid),
    PipeStats = digraph:info(Pipeline),
    acyclic = proplists:get_value(cyclicity, PipeStats),
    FirstStage ! 7,
    timer:sleep(100),
    ok = fetch_results(Pid).
    

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

