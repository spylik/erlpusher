%% --------------------------------------------------------------------------------
%% File:    erlpusher.erl
%% @author  Oleksii Semilietov <spylik@gmail.com>
%%
%% @doc
%% @end
%% --------------------------------------------------------------------------------

-module(erlpusher).

-include("erlpusher.hrl").

% gen server is here
-behaviour(gen_server).

% gen_server api
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

% public api
-export([
        start_link/1
    ]).

% start api
start_link(State) when State#erlpusher_state.server =/= undefined
        andalso State#erlpusher_state.pusher_app_id =/= undefined 
        andalso State#erlpusher_state.channels =/= undefined
        ->
    error_logger:info_msg("Erlpusher start with state ~p",[State]),
    gen_server:start_link({local, State#erlpusher_state.server}, ?MODULE, [State, self()], []).

init([State, Parent]) when State#erlpusher_state.report_to =:= undefined ->
    init([State#erlpusher_state{report_to=Parent}, Parent]);
init([State, _Parent]) ->
    TRef = erlang:send_after(State#erlpusher_state.heartbeat_freq, self(), heartbeat),
    
    % return state
    {ok, 
        State#erlpusher_state{
            heartbeat_tref = TRef,
            pusher_url = generate_url(State),
            report_topic = generate_topic(State)
        }}.

%--------------handle_call-----------------


% handle_call for all other thigs
handle_call(Msg, _From, State) ->
    error_logger:warning_msg("we are in undefined handle_call with message ~p\n",[Msg]),
    {reply, ok, State}.
%-----------end of handle_call-------------


%--------------handle_cast-----------------
% subscribe
handle_cast({subscribe, all}, State) ->
    ChannelList = State#erlpusher_state.channels,
    lists:map(
        fun(Channel) -> gun:ws_send(State#erlpusher_state.gun_pid, {text, <<"{\"event\": \"pusher:subscribe\", \"data\": {\"channel\": \"", Channel/binary, "\"} }">>}) end, 
        ChannelList
    ),
    {noreply, State};

handle_cast(ping, State) ->
    gun:ws_send(State#erlpusher_state.gun_pid, {text, <<"{\"event\": \"pusher:ping\"}">>}),
    {noreply, State};

% handle_cast for all other thigs
handle_cast(Msg, State) ->
    error_logger:warning_msg("we are in undefined handle_cast with message ~p\n",[Msg]),
    {noreply, State}.
%-----------end of handle_cast-------------


%--------------handle_info-----------------
handle_info({gun_ws, ConnPid, {text, <<"{\"event\":\"pusher:connection_established\"", _Rest/binary>>}}, State) ->
    % going to subscribe
%    lists:map(
    io:format("got pusher:connection_established for pid ~p", [ConnPid]),
    gen_server:cast(self(), {subscribe, all}),
    {noreply, State#erlpusher_state{last_frame=get_time()}};

handle_info({gun_ws, _ConnPid, {text, Frame}}, State) ->
    error_logger:info_msg("got {text, Frame}: ~p", [Frame]),
%    Worker = poolboy:checkout(bitstamp_parser),
%    gen_server:cast(Worker, {parse_wss, Frame}),
%    poolboy:checkin(bitstamp_parser, Worker),
    {noreply, State#erlpusher_state{last_frame=get_time()}};

% close and other events bringing gun to flush
handle_info({gun_ws, ConnPid, close}, State) ->
    gun:ws_send(ConnPid, close),
    NewState = flush_gun(State, ConnPid),
    {noreply, NewState};

handle_info({gun_ws, ConnPid, {close, Code, _}}, State) ->
    gun:ws_send(ConnPid, {close, Code, <<>>}),
    NewState = flush_gun(State, ConnPid),
    {noreply, NewState};

handle_info({gun_down, ConnPid, ws, _, _, _}, State) ->
    NewState = flush_gun(State, ConnPid),
    {noreply, NewState};

handle_info({'DOWN', _ReqRef, _, ConnPid, _}, State) ->
    NewState = flush_gun(State, ConnPid),
    {noreply, NewState};

% unknown frame
handle_info({gun_ws, _ConnPid, Frame}, State) ->
    error_logger:warning_msg("got non-text gun_ws event with Frame ~p", [Frame]),
    {noreply, State};


% hearbeat for find and recovery dead connection
handle_info(heartbeat, State) ->
%    error_logger:info_msg("We are in hearbeat section with state ~p", [State]),
    _ = erlang:cancel_timer(State#erlpusher_state.heartbeat_tref),
    NewState = may_need_connect(State, State#erlpusher_state.gun_ref, State#erlpusher_state.last_frame),
    TRef = erlang:send_after(State#erlpusher_state.heartbeat_freq, self(), heartbeat),
    {noreply, NewState#erlpusher_state{heartbeat_tref=TRef}};


% handle_info for all other thigs
handle_info(Msg, State) ->
    error_logger:warning_msg("we are in undefined handle_info with message ~p\n",[Msg]),
    {noreply, State}.
%-----------end of handle_info-------------


terminate(_Reason, State) ->
    flush_gun(State, undefined).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%--------------non exported functions----------------

% gun clean_up
flush_gun(State, ConnRef) ->
    error_logger:info_msg("We are in flush gun section with state ~p", [State]),
    case ConnRef =:= undefined of
        true when State#erlpusher_state.gun_ref =/= undefined ->
            demonitor(State#erlpusher_state.gun_ref),
            gun:close(State#erlpusher_state.gun_pid),
            gun:flush(State#erlpusher_state.gun_pid);
        true ->
            ok;
        false when State#erlpusher_state.gun_pid =:= undefined ->
            gun:close(ConnRef),
            gun:flush(ConnRef);
        false when State#erlpusher_state.gun_pid =:= ConnRef ->
            demonitor(State#erlpusher_state.gun_ref),
            gun:close(State#erlpusher_state.gun_pid),
            gun:flush(State#erlpusher_state.gun_pid)
    end,
    State#erlpusher_state{last_frame=undefined,gun_pid=undefined, gun_ref=undefined}.

% may need connect
may_need_connect(State, undefined, _LastFrame) ->
    connect(State);
may_need_connect(State, _GunRef, LastFrame) when is_integer(LastFrame) ->
    case get_time() - LastFrame > State#erlpusher_state.noreceive_ttl of
        true -> 
            connect(flush_gun(State, undefined));
        false ->
            State
    end;
may_need_connect(State, _GunRef, _LastFrame) ->
    State.


% connect
connect(State) ->
    error_logger:info_msg("We are in connect section with state ~p", [State]),
    {ok, Pid} = gun:open("wss.pusherapp.com", 443, #{retry=>0}),
    case gun:await_up(Pid) of
        {ok, http} ->
            GunRef = monitor(process, Pid),
            gun:ws_upgrade(Pid, State#erlpusher_state.pusher_url, [], #{compress => true}),
            receive
                {gun_ws_upgrade, Pid, ok, _} ->
                    error_logger:info_msg("connected"),
                    State#erlpusher_state{gun_pid=Pid, gun_ref=GunRef}
            after State#erlpusher_state.timeout_for_gun_ws_upgrade ->
                error_logger:warning_msg("got timeout_for_gun_ws_upgrade"),
                flush_gun(State, Pid)
            end;
        {error, timeout} ->
            error_logger:warning_msg("{error, timeout} when trying to connect"),
            flush_gun(State, Pid)
    end.


% get time
get_time() ->
    erlang:convert_time_unit(erlang:system_time(), native, milli_seconds).

% generate url
generate_url(State) ->
    "/app/"++State#erlpusher_state.pusher_app_id++"?client="++State#erlpusher_state.pusher_ident++"&version=1.0&protocol=7".

% generate report topic
generate_topic(State) when State#erlpusher_state.report_topic =:= undefined ->
    atom_to_list(State#erlpusher_state.server)++".output";
generate_topic(State) ->
    State#erlpusher_state.report_topic.
