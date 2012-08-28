-module(esp_cache_SUITE).

-include("../../erlangsp/include/license_and_copyright.hrl").
-include_lib("common_test/include/ct.hrl").
-include("../../coop/include/coop_dag.hrl").

%% Suite functions
-export([all/0, init_per_suite/1, end_per_suite/1]).

%% Pipeline and fanout tests
-export([datum_value/1]).

%% Test procs for validating process message output
%% -export([receive_pipe_results/0, receive_round_robin_results/2]).
 
all() -> [datum_value].

init_per_suite(Config) -> Config.
end_per_suite(_Config) -> ok.


%%----------------------------------------------------------------------
%% Coop Node tests
%%----------------------------------------------------------------------
datum_value(_Config) ->

    %% Get original value...
    Kill_Switch = coop_kill_link_rcv:make_kill_switch(),
    {coop_node, _Node_Ctl_Pid, Node_Task_Pid} = Coop_Node = esp_cache:new_datum_node(Kill_Switch, 17),
    R1 = make_ref(),
    coop:relay_data(Coop_Node, {get_value, {R1, self()}}),
    17 = check_datum(R1),
    R2 = make_ref(),
    coop:relay_data(Coop_Node, {get_value, {R2, self()}}),
    17 = check_datum(R2),
    
    %% Replace value and get new value...
    R3 = make_ref(),
    coop:relay_data(Coop_Node, {replace, 23, {R3, self()}}),
    23 = check_datum(R3),
    R4 = make_ref(),
    coop:relay_data(Coop_Node, {get_value, {R4, self()}}),
    23 = check_datum(R4),
    
    %% Check for expiration...
    erlang:monitor(process, Node_Task_Pid),
    coop:relay_data(Coop_Node, {expire, {foo, self()}}),
    {exited, _Pid} = check_datum(foo).

check_datum(Ref) ->
    receive
        {Ref, Value} -> Value;
        {'DOWN', _MRef, process, Pid, normal} -> {exited, Pid}
    after 1000 -> timeout
    end.

