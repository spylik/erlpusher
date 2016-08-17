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

% when #erlpusher_state.report_to undefined, we going to send output to parent pid
init([State = #erlpusher_state{report_to = undefined}, Parent]) ->
    init([State#erlpusher_state{report_to = Parent}, Parent]);
init([State, _Parent]) ->
    TRef = erlang:send_after(State#erlpusher_state.heartbeat_freq, self(), heartbeat),
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
handle_cast({subscribe, all}, State = #erlpusher_state{channels = Channels}) ->
    lists:map(
        fun(Channel) -> gun:ws_send(State#erlpusher_state.gun_pid, {text, <<"{\"event\": \"pusher:subscribe\", \"data\": {\"channel\": \"", Channel/binary, "\"} }">>}) end, 
        Channels
    ),
    {noreply, State};

% send ping
handle_cast(ping, State) ->
    gun:ws_send(State#erlpusher_state.gun_pid, {text, <<"{\"event\": \"pusher:ping\"}">>}),
    {noreply, State};

% handle_cast for all other thigs
handle_cast(Msg, State) ->
    error_logger:warning_msg("we are in undefined handle_cast with message ~p\n",[Msg]),
    {noreply, State}.
%-----------end of handle_cast-------------


%--------------handle_info-----------------
handle_info({gun_ws, _ConnPid, {text, <<"{\"event\":\"pusher:connection_established\"", _Rest/binary>>}}, State) ->
    gen_server:cast(self(), 
        {subscribe, all}
    ),
    {noreply, State#erlpusher_state{last_frame=get_time()}};

handle_info(
        {gun_ws, _ConnPid, {text, Frame}}, 
        State = #erlpusher_state {
            pusher_app_id=PusherAppId
        }) ->
    send_output(State, [{erlpusher_appid, PusherAppId}, {erlpusher_frame, Frame}]),
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
handle_info(heartbeat, State = #erlpusher_state{
        heartbeat_tref = Heartbeat_tref,
        heartbeat_freq = Heartbeat_freq,
        gun_ref = ConnPid,
        last_frame = Last_frame}) ->
    _ = erlang:cancel_timer(Heartbeat_tref),
    NewState = may_need_connect(State, ConnPid, Last_frame),
    TRef = erlang:send_after(Heartbeat_freq, self(), heartbeat),
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
flush_gun(State = #erlpusher_state{gun_ref = Gun_ref, gun_pid = Gun_pid}, ConnRef) ->
    case ConnRef =:= undefined of
        true when Gun_pid =/= undefined ->
            demonitor(Gun_ref),
            gun:close(Gun_pid),
            gun:flush(Gun_pid);
        true ->
            ok;
        false when Gun_pid =:= undefined ->
            gun:close(ConnRef),
            gun:flush(ConnRef);
        false when Gun_pid =:= ConnRef ->
            demonitor(Gun_ref),
            gun:close(Gun_pid),
            gun:flush(Gun_pid)
    end,
    State#erlpusher_state{
        last_frame = undefined,
        gun_pid = undefined, 
        gun_ref = undefined}.

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
connect(State = #erlpusher_state{
        pusher_url = Pusher_url, 
        timeout_for_gun_ws_upgrade = Timeout_for_gun_ws_upgrade}) ->
    error_logger:info_msg("We are in connect section with state ~p", [State]),
    {ok, Pid} = gun:open("wss.pusherapp.com", 443, #{retry=>0}),
    case gun:await_up(Pid) of
        {ok, http} ->
            GunRef = monitor(process, Pid),
            gun:ws_upgrade(Pid, Pusher_url, [], #{compress => true}),
            receive
                {gun_ws_upgrade, Pid, ok, _} ->
                    error_logger:info_msg("connected"),
                    State#erlpusher_state{gun_pid=Pid, gun_ref=GunRef}
            after Timeout_for_gun_ws_upgrade ->
                error_logger:warning_msg("got timeout_for_gun_ws_upgrade for pid ~p",[Pid]),
                flush_gun(State, Pid)
            end;
        {error, timeout} ->
            error_logger:warning_msg("{error, timeout} on gun:await_up when trying to connect with pid ~p",[Pid]),
            flush_gun(State, Pid)
    end.

% get time
get_time() ->
    erlang:convert_time_unit(erlang:system_time(), native, milli_seconds).

% generate url
generate_url(State) ->
    "/app/"++State#erlpusher_state.pusher_app_id++"?client="++State#erlpusher_state.pusher_ident++"&version=1.0&protocol=7".

% generate report topic
generate_topic(State = #erlpusher_state{report_topic = undefined}) ->
    list_to_binary(atom_to_list(State#erlpusher_state.server)++".output");
generate_topic(State) ->
    State#erlpusher_state.report_topic.

% send output
send_output(_State = #erlpusher_state{report_to=erlroute, report_topic=Report_topic, server=Server}, Frame) ->
    erlroute:pub(?MODULE, Server, ?LINE, Report_topic, Frame);
send_output(_State = #erlpusher_state{report_to=ReportTo}, Frame) ->
    ReportTo ! Frame.


