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
-module(esp_http).

-include_lib("erlangsp/include/license_and_copyright.hrl").
-author('Jay Nelson <jay@duomark.com>').

%% Public API
-export([parse_socket_data/1]).

%% Start listener with the following:
%%   Coop = esp_tcp:accept_connections(8000, 5, {esp_http, parse_socket_data}, [{packet, http_bin}]).
%%   coop:relay_data(Coop, {start}).

parse_socket_data(Socket) ->
    case gen_tcp:recv(Socket, 0) of
        {ok, Request} -> handle_request(Socket, Request, <<>>);
        {ok, Request, Rest} -> handle_request(Socket, Request, Rest);
        {error, Reason} -> error_logger:error_msg("HTTP Request failure: ~p~n", [Reason]);
        {more, Length} -> error_logger:error_msg("HTTP More: ~p~n", [Length])
    end.
            
handle_request(Socket, {http_request, Http_Method, {abs_path, Path}, {1,0} = _Vsn}, Rest) ->
    validate_request_10(Socket, Http_Method, Path, Rest);
handle_request(Socket, {http_request, Http_Method, {abs_path, Path}, {1,1} = _Vsn}, Rest) ->
    validate_request_11(Socket, Http_Method, Path, Rest);
handle_request(_Socket, Unexpected, _Rest) ->
    error_logger:error_msg("Unexpected HTTP Request: ~p~n", [Unexpected]).

validate_request_10(Socket, 'GET', Path, _Rest) ->
    error_logger:info_msg("GET 1.0 Headers for path ~p: ~p~n", [Path, fetch_headers(Socket)]).

validate_request_11(Socket, 'GET', Path, _Rest) ->
    error_logger:info_msg("GET 1.1 Headers for path ~p: ~p~n", [Path, fetch_headers(Socket)]).


-record(http_header, {num :: integer(), field :: term(), reserved :: term(), value :: binary()}).

fetch_headers(Socket) ->
    Hdrs = fetch_headers(Socket, gen_tcp:recv(Socket, 0), []),
    lists:sort(fun(Hdr1, Hdr2) -> Hdr1#http_header.num =< Hdr2#http_header.num end, Hdrs).


%% Error parsing headers, short-circuit...
fetch_headers(_Socket, {error, Reason},           Hdrs) -> lists:reverse([{error, Reason} | Hdrs]);
fetch_headers(_Socket, {ok, {http_error, Error}}, Hdrs) -> lists:reverse([Error           | Hdrs]);

%% Last header parsed...    
fetch_headers(_Socket, {ok, http_eoh},        Hdrs) -> lists:reverse(Hdrs);
fetch_headers(_Socket, {ok, http_eoh, _Rest}, Hdrs) -> lists:reverse(Hdrs);

%% Collect headers found.
fetch_headers( Socket, {ok, {http_header, _Hdr_Num, _Http_Field, _Rsrvd, _Hdr_Value} = Header}, Hdrs) ->
%%    error_logger:info_msg(" ... ~p~n", [Header]),
    fetch_headers(Socket, gen_tcp:recv(Socket, 0), [Header | Hdrs]);
fetch_headers( Socket, {ok, {http_header, _Hdr_Num, _Http_Field, _Rsrvd, _Hdr_Value} = Header, _Rest}, Hdrs) ->
%%    error_logger:info_msg(" ... ~p~n", [Header]),
    fetch_headers(Socket, gen_tcp:recv(Socket, 0), [Header | Hdrs]).

     
