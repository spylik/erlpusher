%% --------------------------------------------------------------------------------
%% File:    erlpusher.erl
%% @author  Oleksii Semilietov <spylik@gmail.com>
%%
%% @doc
%% An Erlang gun-driven pusher.com client.
%% @end
%% --------------------------------------------------------------------------------

-module(erlpusher).

-include("erlpusher.hrl").
-include("deps/teaser/include/utils.hrl").

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
        ->
    error_logger:info_msg("Erlpusher start with state ~p",[State]),
    gen_server:start_link({local, State#erlpusher_state.server}, ?MODULE, [State, self()], []).

% when #erlpusher_state.report_to undefined, we going to send output to parent pid
init([State = #erlpusher_state{report_to = 'undefined'}, Parent]) ->
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

% @doc handle cast for subscribe
handle_cast({'subscribe', Channel}, State) ->
    {noreply, subscribe(State, Channel)};

% @doc send ping to remote
handle_cast('ping', State) ->
    {noreply, send(may_need_connect(State), {text, <<"{\"event\": \"pusher:ping\"}">>})};

% handle_cast for all other thigs
handle_cast(Msg, State) ->
    error_logger:warning_msg("we are in undefined handle_cast with message ~p\n",[Msg]),
    {noreply, State}.
%-----------end of handle_cast-------------


%--------------handle_info-----------------

% @doc hearbeat for find and recovery dead connection
handle_info('heartbeat', State = #erlpusher_state{
        heartbeat_tref = Heartbeat_tref,
        heartbeat_freq = Heartbeat_freq
    }) ->
    _ = erlang:cancel_timer(Heartbeat_tref),
    ?debug(State),
    NewState = may_need_connect(State),
    TRef = erlang:send_after(Heartbeat_freq, self(), heartbeat),
    {noreply, NewState#erlpusher_state{heartbeat_tref=TRef}};

handle_info({'gun_ws', _ConnPid, {text, <<"{\"event\":\"pusher:connection_established\"", _Rest/binary>>}}, State) ->
    ?debug(State),
    NewState = subscribe(State, 'all'),
    ?debug(NewState),
    {noreply, NewState#erlpusher_state{last_frame=get_time()}};

handle_info({'gun_ws', _ConnPid, {text, <<"{\"event\":\"pusher_internal:subscription_succeeded\"", _Rest/binary>> = Frame}}, State) ->
    error_logger:warning_msg("~p", [Frame]),
    {noreply, State#erlpusher_state{last_frame=get_time()}};

handle_info({'gun_ws', _ConnPid, {text, Frame}}, State = #erlpusher_state{pusher_app_id = PusherAppId}) ->
    send_output(State, [{erlpusher_appid, PusherAppId}, {erlpusher_frame, Frame}]),
    {noreply, State#erlpusher_state{last_frame=get_time()}};
    
%% ---- close and other events bringing gun to flush ---- %%

% @doc gun
handle_info({'gun_ws', ConnPid, 'close'}, State) ->
    gun:ws_send(ConnPid, 'close'),
    NewState = flush_gun(State, ConnPid),
    {noreply, NewState};
handle_info({'gun_ws', ConnPid, {'close', Code, _}}, State) ->
    gun:ws_send(ConnPid, {'close', Code, <<>>}),
    NewState = flush_gun(State, ConnPid),
    {noreply, NewState};

% @doc gun_error
handle_info({'gun_error', ConnPid, Reason}, State) ->
    error_logger:error_msg("got gun_error for ConnPid ~p with reason: ~p",[ConnPid, Reason]),
    {noreply, flush_gun(State, ConnPid)};

% @doc gun_down
handle_info({'gun_down', ConnPid, 'ws', _, _, _}, State) ->
    {noreply, flush_gun(State, ConnPid)};

% @doc expected down with state 'normal'
handle_info({'DOWN', _MonRef, 'process', ConnPid, 'normal'}, State) ->
    {noreply, flush_gun(State, ConnPid)};

% @doc unexepted 'DOWN'
handle_info({'DOWN', MonRef, 'process', ConnPid, Reason}, State) ->
    error_logger:error_msg("got DOWN for ConnPid ~p, MonRef ~p with Reason: ~p",[ConnPid, MonRef, Reason]),
    {noreply, flush_gun(State, ConnPid)};

% @doc unknown gun_ws frame
handle_info({'gun_ws', _ConnPid, Frame}, State) ->
    error_logger:warning_msg("got non-text gun_ws event with Frame ~p", [Frame]),
    {noreply, State};

% @doc handle_info for unknown things
handle_info(Msg, State) ->
    error_logger:warning_msg("we are in undefined handle_info with message ~p\n",[Msg]),
    {noreply, State}.
%-----------end of handle_info-------------

% @doc call back for terminate (we going to cancel timer here)
-spec terminate(Reason, State) -> term() when
    Reason :: 'normal' | 'shutdown' | {'shutdown',term()} | term(),
    State :: term().

terminate(_Reason, State) ->
    flush_gun(State, 'undefined').

% @doc call back for code_change
-spec code_change(OldVsn, State, Extra) -> Result when
    OldVsn :: Vsn | {down, Vsn},
    Vsn :: term(),
    State :: term(),
    Extra :: term(),
    Result :: {ok, NewState},
    NewState :: term().

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%--------------non exported functions----------------

% @doc check does we need to connect or reconnect
may_need_connect(State = #erlpusher_state{gun_pid = 'undefined'}) ->
    ?here,
    connect(State);
may_need_connect(State = #erlpusher_state{last_frame = LastFrame}) when is_integer(LastFrame) ->
    ?debug(State),
    case get_time() - LastFrame > State#erlpusher_state.noreceive_ttl of
        true ->
            ?here,
            connect(flush_gun(State, 'undefined'));
        false ->
            ?here,
            State
    end;
may_need_connect(State) ->
    ?here,
    State.

% @doc connect
connect(State = #erlpusher_state{
        pusher_url = Pusher_url, 
        timeout_for_gun_ws_upgrade = Timeout_for_gun_ws_upgrade}) ->
    error_logger:info_msg("Erlpusher trying connect with state ~p", [State]),
    {ok, Pid} = gun:open("wss.pusherapp.com", 443, #{retry=>0}),
    GunMonRef = monitor(process, Pid),
    NewState = case gun:await_up(Pid, 5000, GunMonRef) of
        {ok, Protocol} ->
            error_logger:info_msg("Erlpusher ~p connected to remote with protocol ~p",[Pid, Protocol]),
            gun:ws_upgrade(Pid, Pusher_url, [], #{compress => true}),
            receive
                {'gun_ws_upgrade', Pid, ok, _} ->
                    error_logger:info_msg("Erlpusher ~p got gun_ws_upgrade",[Pid]),
                    State#erlpusher_state{gun_pid=Pid, gun_ref=GunMonRef}
            after Timeout_for_gun_ws_upgrade ->
                error_logger:warning_msg("Erlpusher ~p got timeout_for_gun_ws_upgrade",[Pid]),
                flush_gun(State, Pid)
            end;
        {error, Reason} ->
            error_logger:warning_msg("Some error in Erlpusher '~p' occur in gun during connection to pusher.com host",[Reason]),
            flush_gun(State, Pid)
    end, ?debug(NewState), NewState.

% @doc subscribe section
subscribe(State = #erlpusher_state{channels = []}, 'all') ->
    ?here,
    error_logger:warning_msg("Erlpusher got subscribe(all) with empty list in state"),
    State;

subscribe(State = #erlpusher_state{channels = Channels}, 'all') ->
    NewState = may_need_connect(State),
    ?debug(NewState),
    lists:map(
        fun(Channel) -> 
            send(NewState, {text, <<"{\"event\": \"pusher:subscribe\", \"data\": {\"channel\": \"", Channel/binary, "\"} }">>})
        end, Channels
    ), NewState;

subscribe(State = #erlpusher_state{channels = Channels}, Channel) when is_binary(Channel) ->
    ?debug(State),
    NewState = send(may_need_connect(State), {text, <<"{\"event\": \"pusher:subscribe\", \"data\": {\"channel\": \"", Channel/binary, "\"} }">>}),
    ?debug(NewState),
    NewState#erlpusher_state{channels = [Channel|Channels]}.

% @doc send frame to remote
send(State = #erlpusher_state{gun_pid = 'undefined'}, _Frame) -> 
    State;
send(State = #erlpusher_state{gun_pid = GunPid}, Frame) ->
    gun:ws_send(GunPid, Frame),
    State.

% @doc gun clean_up
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

% @doc get time
get_time() ->
    erlang:convert_time_unit(erlang:system_time(), native, milli_seconds).

% @doc generate url
generate_url(State) ->
    "/app/"++State#erlpusher_state.pusher_app_id++"?client="++State#erlpusher_state.pusher_ident++"&version=1.0&protocol=7".

% @doc generate report topic
generate_topic(State = #erlpusher_state{report_topic = undefined}) ->
    list_to_binary(atom_to_list(State#erlpusher_state.server)++".output");
generate_topic(State) ->
    State#erlpusher_state.report_topic.

% @doc send output
send_output(_State = #erlpusher_state{report_to=erlroute, report_topic=Report_topic, server=Server}, Frame) ->
    erlroute:pub(?MODULE, Server, ?LINE, Report_topic, Frame, 'hybrid', '$erlroute_cmp_erlpusher');
send_output(_State = #erlpusher_state{report_to=ReportTo}, Frame) ->
    ReportTo ! Frame.


