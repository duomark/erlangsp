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
-module(esp_tcp_asynch).

-include_lib("erlangsp/include/license_and_copyright.hrl").
-author('Jay Nelson <jay@duomark.com>').

%% Public API
-export([new_coop/1]).

%% Testing API
-export([
         init_listener/1, init_listener/2, listen/2,
         init_acceptor/1, accept/3
        ]).

%%------------------------------------------------------------------------------
%%
%% Erlang/SP TCP listener Co-op
%%
%% A single gen_tcp listener uses asynchronous accept to receive client
%% connections. A fanout of acceptors handles each connection using a
%% round-robin approach that consumes one worker for each connection.
%% The slab allocator will provide a chunk of new workers when the
%% available set becomes low.
%%
%%------------------------------------------------------------------------------


-include_lib("coop/include/coop.hrl").
-include_lib("coop/include/coop_dag.hrl").

%% Coop:
%%   TCP Listener => X acceptors
new_coop({Num_Acceptors, Proxy_Module}) ->

    %% Make the cache directory and worker function specifications...
    Listener = coop:make_dag_node(listener,
                                  ?COOP_INIT_FN(init_listener, [Proxy_Module]),
                                  ?COOP_TASK_FN(listen),
                                  [],
                                  round_robin),

    Acceptors = [coop:make_dag_node(list_to_atom("worker-" ++ integer_to_list(N)),
                                    ?COOP_INIT_FN(init_acceptor, {}),
                                    ?COOP_TASK_FN(accept),
                                    [access_coop_head]
                                   )
                 || N <- lists:seq(1, Num_Acceptors)],

    %% Listener -E Acceptors
    coop:new_fanout(Listener, Acceptors, none).


%%========================= Listener Node =================================

-define(NONE, -1).
-define(SOCKET_OPTIONS, [binary, {packet, raw}, {reuseaddr, true},
                         {keepalive, true}, {backlog, 30},
                         {active, false}, {recbuf, 8192}]).

-record(esp_tcp_state, {started  = erlang:now() :: {integer(), integer(), integer()},
                        port     = ?NONE  :: integer(),
                        acceptor = ?NONE  :: any(),
                        listener = ?NONE  :: any(),
                        socket_opts = []  :: proplists:proplist(),
                        proxy = undefined :: module()
                       }).

%% Create an #esp_tcp_state{} instance for the Coop_Head
init_listener(Proxy_Module) -> init_listener(Proxy_Module, ?SOCKET_OPTIONS).
init_listener(Proxy_Module, Socket_Opts) ->
    #esp_tcp_state{proxy=Proxy_Module, socket_opts=Socket_Opts}.

listen(#esp_tcp_state{} = State, {start_listen, Port}) -> start_listen(State, Port);
listen(#esp_tcp_state{} = State, stop_listen)          -> stop_listen(State);
listen(#esp_tcp_state{} = State, Inet_Async)           -> handle_accept(State, Inet_Async).

%% Start listening only when requested to...
start_listen(#esp_tcp_state{socket_opts=Socket_Opts} = State, Port) ->
    case gen_tcp:listen(Port, Socket_Opts) of
        {ok, Listen_Socket} ->
            LState = State#esp_tcp_state{port=Port, listener=Listen_Socket},
            {do_async_accept(Listen_Socket, LState), ?COOP_NOOP};
        Error ->
            {State, {error, {listen, Error}}}
    end.

%% Stop listening only when requested to...
stop_listen(#esp_tcp_state{listener=Listen_Socket} = State) ->
    prim_inet:close(Listen_Socket),
    {State#esp_tcp_state{acceptor=-1, listener=-1, port=-1}, ?COOP_NOOP}.

%% Receive an asynchronous notification of a new client connection...
handle_accept(#esp_tcp_state{proxy=Proxy_Module, listener=Listen_Socket} = State,
              {inet_async, Listen_Socket, Accept_Ref, {ok, Client_Socket}}) ->
    case set_sockopt(Listen_Socket, Client_Socket) of
        ok ->
            New_State = State#esp_tcp_state{acceptor = Accept_Ref},
            {New_State, {accept, {Proxy_Module, Client_Socket, Accept_Ref}}};
        Error ->
            {State, {error, {socket_options, Error}}}
    end;

%% Receive an asynchronous notification of a new client connection failure.
handle_accept(#esp_tcp_state{} = State, {inet_async, _Listen_Socket, _Accept_Ref, Error}) ->
    {State#esp_tcp_state{acceptor = -1}, {error, {accept, Error}}}.

do_async_accept(Listen_Socket, State) ->
    {ok, Accept_Ref} = prim_inet:async_accept(Listen_Socket, -1),
    State#esp_tcp_state{acceptor = Accept_Ref}.

set_sockopt(LSock, Cli_Socket) ->
    true = inet_db:register_socket(Cli_Socket, inet_tcp),
    case prim_inet:getopts(LSock, [active, nodelay, keepalive, delay_send, priority, tos]) of
        {ok, Opts} ->
            case prim_inet:setopts(Cli_Socket, Opts) of
                ok -> ok;
                Error ->
                    report_sockopt_failure(Cli_Socket, Error),
                    Error
            end;
        Failure ->
            report_sockopt_failure(Cli_Socket, Failure),
            Failure
    end.

report_sockopt_failure(Cli_Socket, _Reason) ->
    %% IP = dkhs:get_client_ip(Cli_Socket),
    %% Msg = "Error setting socket options: ~w for client ~s~n",
    %% error_logger:error_msg(Msg, [Reason, IP]),
    gen_tcp:close(Cli_Socket).


%%========================= Acceptor Nodes =================================

init_acceptor({_Coop_Head, {}}) -> {}.

%% Errors with client connections in listener layer...
accept(_Coop_Head, {}, {error, {accept, _Error}}) -> {{}, ?COOP_NOOP};
accept(_Coop_Head, {}, {error, {listen, _Error}}) -> {{}, ?COOP_NOOP};
accept(_Coop_Head, {}, {error, {socket_options, _Error}}) -> {{}, ?COOP_NOOP};

%% Handle a new client connection...
accept(_Coop_Head, {}, {accept, {_Proxy_Module, Client_Socket, _Accept_Ref}}) ->
    error_logger:error_msg("~p~n", [gen_tcp:recv(Client_Socket,0)]),
    gen_tcp:close(Client_Socket),
    {{}, ?COOP_NOOP}.
