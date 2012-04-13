-module(coop_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0, init_per_suite/1, end_per_suite/1
         %% init_per_testcase/2, end_per_testcase/2
        ]).
-export([coop_flow_pipeline/1, coop_flow_pipeline_failure/1,
         coop_flow_fanout/1,   coop_flow_fanout_failure/1,
         coop/1]).
-export([receive_pipe_results/0]).
 
all() -> [coop_flow_pipeline, coop_flow_pipeline_failure,
          coop_flow_fanout,   coop_flow_fanout_failure,
          coop].

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

%%----------------------------------------------------------------------
%% Pipeline patterns
%%----------------------------------------------------------------------
coop_flow_pipeline(_Config) ->
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

coop_flow_pipeline_failure(_Config) ->
    try coop_flow:pipeline(a)
    catch error:function_clause -> ok
    end,

    try coop_flow:pipeline([a])
    catch error:{case_clause, false} -> ok
    end.


%%----------------------------------------------------------------------
%% Fanout patterns
%%----------------------------------------------------------------------
coop_flow_fanout(_Config) ->
    Self = self(),
    Fn = fun(_Msg) -> ok end,
    CoopFlow = coop_flow:fanout(Fn, 8, Self),
    10 = digraph:no_vertices(CoopFlow),
    16 = digraph:no_edges(CoopFlow),
    check_fanout_vertex(CoopFlow, Fn, inbound,  0, 8),
    check_fanout_vertex(CoopFlow, Self, outbound, 8, 0),
    [check_fanout_vertex(CoopFlow, 8, ['$v'|N-1], 1, 1) || N <- lists:seq(1,8)].

check_fanout_vertex(Graph, Fn, inbound = Name, InDegree, OutDegree) ->
    {Name, Fn} = digraph:vertex(Graph, Name),
    InDegree   = digraph:in_degree(Graph, Name),
    OutDegree  = digraph:out_degree(Graph, Name),
    InDegree   = length(digraph:in_neighbours(Graph, Name)),
    OutDegree  = length([V || V <- digraph:out_neighbours(Graph, Name), '$v' =:= hd(V), 0 =< tl(V)]);
check_fanout_vertex(Graph, Pid, outbound = Name, InDegree, OutDegree) ->
    {Name, Pid} = digraph:vertex(Graph, Name),
    InDegree    = digraph:in_degree(Graph, Name),
    OutDegree   = digraph:out_degree(Graph, Name),
    InDegree    = length([V || V <- digraph:in_neighbours(Graph, Name), '$v' =:= hd(V), 0 =< tl(V)]),
    OutDegree   = length(digraph:out_neighbours(Graph, Name));
check_fanout_vertex(Graph, _N, Name, 1, 1) ->    
    {Name, []} = digraph:vertex(Graph, Name),
    [inbound] =  digraph:in_neighbours(Graph, Name),
    [outbound] = digraph:out_neighbours(Graph, Name).

coop_flow_fanout_failure(_Config) ->
    try coop_flow:fanout(a, 8, self())
    catch error:function_clause -> ok
    end,
    
    try coop_flow:fanout(fun(_Msg) -> ok end, a, self())
    catch error:function_clause -> ok
    end,
    
    try coop_flow:fanout(fun(_Msg) -> ok end, 8, 3)
    catch error:function_clause -> ok
    end.

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

