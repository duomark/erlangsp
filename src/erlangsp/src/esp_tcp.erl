%%%------------------------------------------------------------------------------
%%% @copyright (c) 2012, DuoMark International, Inc.  All rights reserved
%%% @author Jay Nelson <jay@duomark.com>
%%% @doc
%%%    Accepting TCP connections for handling by a Proxy Module. A fanout
%%%    Co-op is used to manage a single TCP Listen socket which feeds
%%%    multiple TCP Accept processes. Each Accept process is consumed
%%%    when a connection is established, continuing on its own as the
%%%    source of data for a new Co-op. The Accept processes are slab
%%%    allocated: whenever the number of Acceptors drops below a set
%%%    percentage of the original allocation, a new slab of Acceptors
%%%    are started.
%%% @since v0.0.2
%%% @end
%%%------------------------------------------------------------------------------
-module(esp_tcp).

-include("../../license_and_copyright.hrl").
-author('Jay Nelson <jay@duomark.com>').

%% Public API
-export([accept_connections/3, accept_connections/4, accept_connections/5,
         init_listen/1, listen/2,
         start_listen/1, stop_listen/1, pause_listen/1,
         init_accept/1, handle_accept/2,
         start_acceptor/2
        ]).

-include_lib("coop/include/coop.hrl").
-include_lib("coop/include/coop_dag.hrl").

-type socket_parse_fn() :: {module(), atom()} |  function().
-spec accept_connections(integer(), integer(), socket_parse_fn()) -> coop().
-spec accept_connections(integer(), integer(), socket_parse_fn(), proplists:proplist()) -> coop().
-spec accept_connections(string(), integer(), integer(), socket_parse_fn(), proplists:proplist()) -> coop().

accept_connections(Port, Num_Acceptors, Parse_Fn)
  when is_integer(Port), Port >= 0 ->
    accept_connections(Port, Num_Acceptors, Parse_Fn, []).

accept_connections(Port, Num_Acceptors, Parse_Fn, Options)
  when is_integer(Port), Port >= 0, is_list(Options) ->
    accept_connections("tcp_listener_" ++ integer_to_list(Port), Port, Num_Acceptors, Parse_Fn, Options).

accept_connections(Name, Port, Num_Acceptors, Parse_Fn, Options) ->

    %% First coop node sets up the Listen socket...
    Init_Fn = ?COOP_INIT_FN(init_listen, {Port, Options}),
    Task_Fn = ?COOP_TASK_FN(listen),
    Listener = coop:make_dag_node(list_to_atom(Name), Init_Fn, Task_Fn, [], broadcast),

    %% Fanout tier are acceptor proxies of the Listen socket...
    Acc_Init_Fn = ?COOP_INIT_FN(init_accept, {Parse_Fn}),
    Acc_Task_Fn = ?COOP_TASK_FN(handle_accept),
    Acceptors = [begin
                     Acc_Name = list_to_atom(Name ++ "_" ++ integer_to_list(N)),
                     coop:make_dag_node(Acc_Name, Acc_Init_Fn, Acc_Task_Fn, [])
                 end || N <- lists:seq(1,Num_Acceptors)],

    %% No downstream Pids, since Acceptor proxies spawn Acceptors.
    %% coop:new_fanout(Listener, Num_Acceptors, Acceptor, none).
    coop:new_fanout(Listener, Acceptors, none).


%%%------------------------------------------------------------------------------
%%% Root Node: Manage Socket Listener
%%%------------------------------------------------------------------------------

-record(esp_tcp_state, {started  = erlang:now() :: {integer(), integer(), integer()},
                        port     = -1 :: integer(),
                        options  = [] :: list(),
                        listener = -1 :: any()
                       }).
          
-define(SOCKET_OPTIONS, [binary, {packet, http_bin}, {reuseaddr, true},
                         {keepalive, true}, {backlog, 30},
                         {active, false}, {recbuf, 8192}]).


%% Internal state is the listen port and the socket options.
init_listen({Port}) ->
    #esp_tcp_state{port=Port, options=?SOCKET_OPTIONS};
init_listen({Port, Options}) ->
    Socket_Opts = Options ++ proplists:delete(packet, ?SOCKET_OPTIONS),
    #esp_tcp_state{port=Port, options=Socket_Opts}.

%% Listen socket tells fanout procs to Accept when successful.
listen(State, {start}) -> start_listen(State);
listen(State, {stop})  -> stop_listen(State);
listen(State, {pause}) -> pause_listen(State).
    

start_listen(#esp_tcp_state{port=Port, listener=-1, options=Socket_Opts} = State) ->
    case gen_tcp:listen(Port, Socket_Opts) of
        {ok, LSock} -> error_logger:error_msg("LSock ~p~n", [LSock]), {State#esp_tcp_state{listener=LSock}, {accept, LSock}};
        Error       -> error_logger:error_msg(Error), exit(Error)
    end.

stop_listen(_State) ->
    coop:shutdown(self()).

pause_listen(#esp_tcp_state{listener=-1} = State)    -> {State, ?COOP_NOOP};
pause_listen(#esp_tcp_state{listener=LSock} = State) -> {State#esp_tcp_state{listener=-1}, {unaccept, LSock}}.

    
%%%------------------------------------------------------------------------------
%%% Fanout Nodes: Acceptors
%%%------------------------------------------------------------------------------

%% Internal state is the listen socket
init_accept({Parse_Fn}) -> {Parse_Fn}.

%% Accept after already accepting, or unaccepting when not accepting is a NOOP...
handle_accept({Parse_Fn, {Acceptor, Monitor_Ref}}, {accept, _LSock}) ->
    {{Parse_Fn, {Acceptor, Monitor_Ref}}, ?COOP_NOOP};
handle_accept({Parse_Fn}, {unaccept, _LSock}) ->
    {{Parse_Fn}, ?COOP_NOOP};

%% Accept spawns a new process, while unaccept stops the accepting process.
handle_accept({Parse_Fn}, {accept, LSock}) ->
    {{Parse_Fn, spawn_accept(LSock, Parse_Fn)}, ?COOP_NOOP};
handle_accept({Parse_Fn, {Acceptor, _Monitor_Ref}}, {unaccept, _LSock}) ->
    exit(Acceptor, normal), {{Parse_Fn}, ?COOP_NOOP};

%% Monitor messages, etc.
handle_accept(State, Msg) ->
    error_logger:error_msg("~p:handle_accept state: ~p  msg: ~p~n", [?MODULE, State, Msg]),
    {State, ?COOP_NOOP}.

spawn_accept(LSock, Parse_Fn) ->
    error_logger:error_msg("Spawning ~p to parse with ~p~n", [LSock, Parse_Fn]),
    {Pid, Monitor_Ref}
        = try spawn_monitor(?MODULE, start_acceptor, [LSock, Parse_Fn])
          catch {A,B} ->
                  error_logger:error_msg(A, B),
                  {undefined, undefined}
          end,
    error_logger:error_msg("Spawned ~p ~p~n", [LSock, Pid]),
    {Pid, Monitor_Ref}.

start_acceptor(LSock, Parse_Fn) ->
    case gen_tcp:accept(LSock) of
        {error, closed}  -> error_logger:error_msg("Closed~n"), closed;
        {error, timeout} -> error_logout:error_msg("Timeout~n"), timeout;
        {error, system_limit} -> error_logout:error_msg("Too many sockets~n"), too_many_sockets;
        {ok, Socket} -> case Parse_Fn of
                            {Mod, Fun} -> Mod:Fun(Socket);
                            Fun -> Fun(Socket)
                        end
    end.
