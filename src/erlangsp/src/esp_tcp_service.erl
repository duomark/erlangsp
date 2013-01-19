%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%    Accepting TCP connections asynchronously. A fanout
%%%    Co-op is used to manage a single TCP Listen socket which feeds
%%%    multiple TCP Accept processes. Each Accept process is consumed
%%%    when a connection is established, continuing on its own as the
%%%    source of data for a new Co-op. The Accept processes are slab
%%%    allocated: whenever the number of Acceptors drops below a set
%%%    percentage of the original allocation, a new slab of Acceptors
%%%    are started. When too many concurrent open sockets are running,
%%%    the listen socket can be closed to let the load balancer direct
%%%    new connections elsewhere.
%%% @since v0.0.2
%%% @end
%%%------------------------------------------------------------------------------
-module(esp_tcp_service).
-behaviour(esp_service).

-include("../../license_and_copyright.hrl").
-author('Jay Nelson <jay@duomark.com>').

%% Public API
-export([
         new_active/1,  new_active/2,  new_active/3,
         new_passive/1, new_passive/2, new_passive/3,
         start/2, stop/1
        ]).

%% Callback only or Testing API
-export([
         new/1,
         init_listener/1, listen/2,
         init_acceptor/1, accept/2
        ]).

%%------------------------------------------------------------------------------
%%
%% Erlang/SP TCP listener Co-op as a service
%%
%% A single gen_tcp listener uses asynchronous accept to receive client
%% connections. A fanout of acceptors handles each connection using a
%% round-robin approach that consumes one worker for each connection.
%% The slab allocator will provide a chunk of new workers when the
%% available set of acceptor processes becomes low.
%%
%%------------------------------------------------------------------------------

-include_lib("coop/include/coop.hrl").
-include_lib("coop/include/coop_dag.hrl").
-include("esp_service.hrl").

%% Coop:
%%   TCP Listener => X acceptors
-type service_args() :: {pos_integer(), module()}
                      | {pos_integer(), module(), proplists:proplist()}.

-spec new_active(service_args()) -> coop().
-spec new_active(service_args(), proplists:proplist()) -> coop().

-spec new_passive(service_args()) -> coop().
-spec new_passive(service_args(), proplists:proplist()) -> coop().

-spec start(esp_service(), proplists:proplist()) ->
                   esp_service() | {error, already_started | suspended}.
-spec stop(esp_service()) -> esp_service() | {error, already_stopped}.

-define(SOCKET_OPTIONS, [binary, {packet, raw}, {backlog, 30}, {reuseaddr, true}, {recbuf, 8192}]).

new_active(Num_Acceptors) -> new({Num_Acceptors, Num_Acceptors, ?SOCKET_OPTIONS, active}).
new_active(Max_Acc, Min_Acc)                 -> new({Max_Acc, Min_Acc, ?SOCKET_OPTIONS, active}).
new_active(Max_Acc, Min_Acc, Socket_Options) -> new({Max_Acc, Min_Acc,  Socket_Options, active}).

new_passive(Num_Acceptors) -> new({Num_Acceptors, Num_Acceptors, ?SOCKET_OPTIONS, passive}).
new_passive(Max_Acc, Min_Acc)                 -> new({Max_Acc, Min_Acc, ?SOCKET_OPTIONS, passive}).
new_passive(Max_Acc, Min_Acc, Socket_Options) -> new({Max_Acc, Min_Acc,  Socket_Options, passive}).

new({Max_Acceptors, Min_Acceptors, Socket_Options, Style}) when is_list(Max_Acceptors) ->
    new({list_to_integer(atom_to_list(hd(Max_Acceptors))), Min_Acceptors, Socket_Options, Style});
new({Max_Acceptors, Min_Acceptors, Socket_Options, Style}) when is_list(Min_Acceptors) ->
    new({Max_Acceptors, list_to_integer(atom_to_list(hd(Min_Acceptors))), Socket_Options, Style});
new({Max_Acceptors, Min_Acceptors, Socket_Options, Style})
  when is_integer(Max_Acceptors), Max_Acceptors > 0,
       is_integer(Min_Acceptors), Min_Acceptors > 0,
       is_list(Socket_Options), Style =:= active;

       is_integer(Max_Acceptors), Max_Acceptors > 0,
       is_integer(Min_Acceptors), Min_Acceptors > 0,
       is_list(Socket_Options), Style =:= passive ->

    Opts = [{active, false} | proplists:delete(active, Socket_Options)],

    %% Create a listener that broadcasts to multiple concurrent acceptors...
    Init_Fn = ?COOP_INIT_FN(init_listener, {Opts, Max_Acceptors, Min_Acceptors}),
    Task_Fn = ?COOP_TASK_FN(listen),
    Listener = coop:make_dag_node(inbound, Init_Fn, Task_Fn, [], broadcast),

    %% Create acceptors with no downstream consumers...
    Acc_Init_Fn = ?COOP_INIT_FN(init_acceptor, {Style}),
    Acc_Task_Fn = ?COOP_TASK_FN(accept),
    Acceptors = coop:make_dag_nodes(Max_Acceptors, Acc_Init_Fn, Acc_Task_Fn, []),

    %% Connect up the fanout of Listeners -E Acceptors -> none
    Coop = coop:new_fanout(Listener, Acceptors, none),
    esp_service:make_service(Coop).

start(Tcp_Service, Opts) ->
    case [proplists:get_value(P, Opts) || P <- [client_module, port]] of
        [undefined, undefined] -> {missing_service_opts, {?MODULE, [client_module, port]}};
        [undefined,         _] -> {missing_service_opts, {?MODULE, [client_module]}};
        [_,         undefined] -> {missing_service_opts, {?MODULE, [port]}};
        [Client_Module,  Port] -> start(Tcp_Service, Client_Module, Port)
    end.

start(Tcp_Service, Client_Module, Port) ->
    Started = esp_service:start(Tcp_Service),
    ok = esp_service:act_on(Started, {client_module, Client_Module}),
    ok = esp_service:act_on(Started, {start_listen, Port}),
    Started.

stop(Tcp_Service) ->
    ok = esp_service:act_on(Tcp_Service, stop_listen),
    esp_service:stop(Tcp_Service).


%%========================= Coop Nodes API =================================

-define(NONE, -1).

-type now() :: {integer(), integer(), integer()}.
-record(esp_tcp_state, {started  = erlang:now() :: now(),
                        client_module           :: module(),
                        port          = ?NONE   :: integer(),
                        listener      = ?NONE   :: any(),
                        max_acceptors = 0       :: non_neg_integer(),
                        min_acceptors = 0       :: non_neg_integer(),
                        socket_opts   = []      :: proplists:proplist()
                       }).

%%===== Listener Node =====
%% Create an #esp_tcp_state{} instance for the Coop_Head
init_listener({Socket_Opts, Max_Acceptors, Min_Acceptors}) ->
    #esp_tcp_state{socket_opts   = Socket_Opts,
                   max_acceptors = Max_Acceptors,
                   min_acceptors = Min_Acceptors
                  }.

listen(#esp_tcp_state{} = State, {client_module, Client_Module}) ->
    {State#esp_tcp_state{client_module=Client_Module}, {client_module, Client_Module}};
listen(#esp_tcp_state{} = State, {start_listen, Port}) -> start_listen(State, Port);
listen(#esp_tcp_state{} = State, stop_listen)          -> stop_listen(State).

%%===== Acceptor Nodes =====
init_acceptor({Style}) when Style =:= active; Style =:= passive -> {Style, undefined}.

%% Errors with client connections in listener layer...
accept(State, {error, {accept, _Error}}) -> {State, ?COOP_NOOP};
accept(State, {error, {listen, _Error}}) -> {State, ?COOP_NOOP};
accept(State, {error, {socket_options, _Error}}) -> {State, ?COOP_NOOP};

%% Change the client module used to receive data...
accept({Style, _Old_Client_Module}, {client_module, Client_Module}) ->
    {{Style, Client_Module}, ?COOP_NOOP};

%% Listen for client connections and pass them to the handler...
accept(State, {do_async_accept, Listen_Socket}) ->
    %% error_logger:info_msg("Accepting on ~p ~p~n", [self(), erlang:port_info(Listen_Socket)]),
    {ok, _Accept_Ref} = prim_inet:async_accept(Listen_Socket, -1),
    {State, ?COOP_NOOP};
accept(State, {inet_async, _, _, _} = Inet_Async) ->
    handle_accept(State, Inet_Async);

%% Handle a new client connection...
accept({active, Client_Module}, {accept, Client_Socket}) ->
    try esp_tcp_recv:active_loop(Client_Socket, Client_Module)
    after exit(normal) %%% {State, ?COOP_EXIT}
    end;
accept({passive, Client_Module}, {accept, Client_Socket}) ->
    try esp_tcp_recv:passive_loop(Client_Socket, Client_Module)
    after exit(normal) %%% {State, ?COOP_EXIT}
    end.


%%========================= Listener Node =================================

%% Start listening only when requested to...
start_listen(#esp_tcp_state{socket_opts=Socket_Opts} = State, Port) ->
    case gen_tcp:listen(Port, Socket_Opts) of
        {ok, Listen_Socket} ->
            {State#esp_tcp_state{port=Port, listener=Listen_Socket},
             {do_async_accept, Listen_Socket}};
        Error ->
            {State, {error, {listen, Error}}}
    end.

%% Stop listening only when requested to...
stop_listen(#esp_tcp_state{listener=Listen_Socket} = State) ->
    prim_inet:close(Listen_Socket),
    {State#esp_tcp_state{listener=?NONE, port=?NONE}, ?COOP_NOOP}.

%% Receive an asynchronous notification of a new client connection or an error...
handle_accept(State, {inet_async, Listen_Socket, _Accept_Ref, {ok, Client_Socket}}) ->
    %% error_logger:error_msg("Connect ~p ~p ~p~n", [self(), Client_Socket, erlang:port_info(Client_Socket)]),
    case set_sockopt(Listen_Socket, Client_Socket) of
        ok    -> coop:relay_data(self(), {accept, Client_Socket}),           {State, ?COOP_NOOP};
        Error -> coop:relay_data(self(), {error,  {socket_options, Error}}), {State, ?COOP_NOOP}
    end;
handle_accept(State, {inet_async, _Listen_Socket, _Accept_Ref, Error}) ->
    {State, {error, {accept, Error}}}.

set_sockopt(Listen_Socket, Client_Socket) ->
    true = inet_db:register_socket(Client_Socket, inet_tcp),
    Opt_Names = [active, nodelay, keepalive, delay_send, priority, tos],
    case prim_inet:getopts(Listen_Socket, Opt_Names) of
        {ok, Opts} ->
            %% error_logger:info_msg("Socket options: ~p~n", [Opts]),
            case prim_inet:setopts(Client_Socket, Opts) of
                ok    -> ok;
                Error -> report_sockopt_failure(Client_Socket, Error)
            end;
        Failure ->
            report_sockopt_failure(Client_Socket, Failure)
    end.

report_sockopt_failure(Cli_Socket, Reason) ->
    %% IP = dkhs:get_client_ip(Cli_Socket),
    Msg = "Error setting socket options: ~w for client ~p~n",
    error_logger:error_msg(Msg, [Reason, Cli_Socket]),
    gen_tcp:close(Cli_Socket),
    Reason.

