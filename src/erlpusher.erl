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

% we will use ?MODULE as servername
-define(SERVER, ?MODULE).
-define(deadlinkTTL, 60000).
-define(heartbeat_freq, 1000).
-define(timeout_for_gun_ws_upgrade, 10000).

% start api

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
    TRef = erlang:send_after(?heartbeat_freq, self(), heartbeat),
    {ok, #erlpusher_state{tref=TRef}}.

%--------------handle_call-----------------


% handle_call for all other thigs
handle_call(Msg, _From, State) ->
    error_logger:warning_msg("we are in undefined handle_call with message ~p\n",[Msg]),
    {reply, ok, State}.
%-----------end of handle_call-------------


%--------------handle_cast-----------------
% subscribe
handle_cast({subscribe, all}, State) ->
    subscribe(State#erlpusher_state.gun_pid),
    {noreply, State};

% handle_cast for all other thigs
handle_cast(Msg, State) ->
    error_logger:warning_msg("we are in undefined handle_cast with message ~p\n",[Msg]),
    {noreply, State}.
%-----------end of handle_cast-------------


%--------------handle_info-----------------
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
    error_loger:warning_msg("got non-text gun_ws event with Frame ~p", [Frame]),
    {noreply, State};


% hearbeat for find and recovery dead connection
handle_info(heartbeat, State) ->
    error_loger:info_msg("We are in hearbeat section with state ~p", [State]),
    _ = erlang:cancel_timer(State#erlpusher_state.tref),
    case is_integer(State#erlpusher_state.last_frame) of
        true ->
            IsDead = get_time() - State#erlpusher_state.last_frame,
            NeedConnect = IsDead > ?deadlinkTTL;
        false ->
            NeedConnect = false
    end,

    case State#erlpusher_state.gun_ref of
        undefined ->
            NewState = connect(State);
        _ when NeedConnect =:= true ->
            NewState = connect(flush_gun(State, undefined));
        _ ->
            NewState = State
    end,

    TRef = erlang:send_after(?heartbeat_freq, ?SERVER, heartbeat),
    {noreply, NewState#erlpusher_state{tref=TRef}};


% handle_info for all other thigs
handle_info(Msg, State) ->
    error_logger:warning_msg("we are in undefined handle_info with message ~p\n",[Msg]),
    {noreply, State}.
%-----------end of handle_info-------------


terminate(_Reason, State) ->
    demonitor(State#erlpusher_state.gun_ref),
    gun:close(State#erlpusher_state.gun_pid),
    gun:flush(State#erlpusher_state.gun_pid).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%--------------non exported functions----------------

% gun clean_up
flush_gun(State, ConnRef) ->
    error_logger:info_msg("We are in flush gun section with state ~p", State),
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

connect(State) ->
    error_logger:info_msg("We are in connect section with state ~p", State),
    {ok, Pid} = gun:open("wss.pusherapp.com", 443, #{retry=>0}),
    case gun:await_up(Pid) of
        {ok, http} ->
            GunRef = monitor(process, Pid),
            gun:ws_upgrade(Pid, "/app/de504dc5763aeef9ff52?client=maria&version=1.0&protocol=7", [], #{compress => true}),
            receive
                {gun_ws_upgrade, Pid, ok, _} ->
                    error_logger:info_msg("connected"),
                    NewState = State#erlpusher_state{gun_pid=Pid, gun_ref=GunRef}
            after ?timeout_for_gun_ws_upgrade ->
                error_logger:warning_msg("got timeout_for_gun_ws_upgrade"),
                NewState = flush_gun(State, Pid)
            end;
        {error, timeout} ->
            error_logger:warning_msg("{error, timeout} when trying to connect"),
            NewState = flush_gun(State, Pid)
    end,
    error_logger:info_msg("Checkout from connect"),
    NewState.

% get time
get_time() ->
    erlang:convert_time_unit(erlang:system_time(), native, milli_seconds).

% subscribe to channels
subscribe(Pid) -> 
    subscribe(Pid, diff_order_book),
    subscribe(Pid, live_trades).

subscribe(Pid, diff_order_book) ->
    gun:ws_send(Pid, {text, <<"{\"event\": \"pusher:subscribe\", \"data\": {\"channel\": \"diff_order_book\"} }">>});
subscribe(Pid, live_trades) ->
    gun:ws_send(Pid, {text, <<"{\"event\": \"pusher:subscribe\", \"data\": {\"channel\": \"live_trades\"} }">>}).
