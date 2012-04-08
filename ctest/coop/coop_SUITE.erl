-module(coop_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0, init_per_testcase/2, end_per_testcase/2]).
-export([pipeline/1]).
 
all() -> [pipeline].
 
%% init_per_suite(_Config) -> ok.
%% init_per_group(Name, _Config) -> ok.
init_per_testcase(pipeline, _Config) ->
    ok.

%% end_per_suite(_Config) -> ok.
%% end_per_group(Name, _Config) -> ok.
end_per_testcase(pipeline, _Config) ->
    ok.

pipeline(_Config) ->
    1 = 1.
