-module(esp_cache_SUITE).

-include("../../erlangsp/include/license_and_copyright.hrl").
-include_lib("common_test/include/ct.hrl").
-include("../../coop/include/coop_dag.hrl").

%% Suite functions
-export([all/0, init_per_suite/1, end_per_suite/1]).

%% Pipeline and fanout tests
-export([datum_node/1]).

%% Test procs for validating process message output
%% -export([receive_pipe_results/0, receive_round_robin_results/2]).
 
all() -> [datum_node].

init_per_suite(Config) -> Config.
end_per_suite(_Config) -> ok.


%%----------------------------------------------------------------------
%% Coop Node tests
%%----------------------------------------------------------------------
datum_node(_Config) ->
    Kill_Switch = coop_kill_link_rcv:make_kill_switch(),
    Coop_Node = esp_cache:new_datum_node(Kill_Switch, 17),
    R1 = make_ref(),
    coop:relay_data(Coop_Node, {get_value, {R1, self()}}),
    check_datum(R1).

check_datum(Ref) ->
    receive {Ref, 17} -> 17
    after 1000 -> timeout
    end.

