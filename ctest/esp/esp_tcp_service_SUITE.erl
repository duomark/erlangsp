-module(esp_tcp_service_SUITE).

-include("../../src/license_and_copyright.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("coop/include/coop.hrl").
-include_lib("coop/include/coop_dag.hrl").

%% Suite functions
-export([all/0, init_per_suite/1, end_per_suite/1]).

%% Test message flow control for a service
-export([start_and_stop/1]).

all() -> [start_and_stop].

init_per_suite(Config) -> Config.
end_per_suite(_Config) -> ok.

-define(ES, esp_service).
-define(TS, esp_tcp_service).


%%----------------------------------------------------------------------
%% Test functions
%%----------------------------------------------------------------------
start_and_stop(_Config) ->
    Tcp_Service = ?TS:new_active(5),
    new = ?ES:status(Tcp_Service),
    {error, not_started} = ?ES:act_on(Tcp_Service, 5),
    Started_Service = ?TS:start(Tcp_Service, [{client_module, ?MODULE}, {port, 8200}]),
    active = ?ES:status(Started_Service),
    Stopped_Service = ?TS:stop(Started_Service),
    stopped = ?ES:status(Stopped_Service),
    {error, stopped} = ?ES:act_on(Stopped_Service, 4),
    ok.
