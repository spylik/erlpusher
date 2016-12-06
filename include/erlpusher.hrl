-type channel_status()          :: 'toconnect' | 'casted' | 'connected' | 'errored'.
-type channel()                 :: binary().

-record(channel_prop, {
        status = 'toconnect'    :: channel_status(),
        created                 :: pos_integer(),
        cast_sub                :: 'undefined' | pos_integer(),
        get_sub_confirm         :: 'undefined' | pos_integer(),
        last_frame              :: 'undefined' | pos_integer()
    }).
-type channel_prop()            :: #channel_prop{}.

-type channels()                :: #{} | #{channel() => channel_prop()}.
-type pusher_app_id()           :: nonempty_list().
-type register_as()             :: 'undefined' |            % register option: do not register
                                   {'local', atom()} |      % register option: locally
                                   {'global',term()} |      % register option: globally)
                                   {'via',module(),term()}. % register option: via module,name
-type pusher_ident()            :: nonempty_list().
-type report_to()               :: 'undefined' | atom() | pid() | 'erlroute' | {'erlroute', binary()}.

-type gun_pid()         :: pid().
-type mon_ref()         :: reference().
-type stream_ref()      :: reference().
-type gun_ws()          :: {'gun_ws', gun_pid(), {'text', binary()}}.
-type gun_error()       :: {'gun_error', gun_pid(), stream_ref(), term()} | {'gun_error', gun_pid(), term()}.
-type down()            :: {'DOWN', mon_ref(), 'process', stream_ref(), term()}.

-type start_prop() :: #{
        'register' => register_as(),
        'channels' => [channel()],
        'report_to' => report_to(),
        'pusher_ident' => pusher_ident(),
        'heartbeat_freq' => non_neg_integer(),
        'timeout_for_gun_ws_upgrade' => non_neg_integer(),
        'timeout_for_subscribtion' => non_neg_integer(),
        'timeout_before_ping' => 'from_pusher' | non_neg_integer(),
        'timeout_for_ping' => non_neg_integer()
    }.

-record(erlpusher_state, {
        % user specification section
        pusher_app_id               :: pusher_app_id(),  % moderate: pusher_app_id
        register                    :: register_as(),    % register or do not register erlpusher process as
        channels                    :: channels(),       % channel list (some channels can be predefined)
        report_to                   :: report_to(),      % where output output will be sended 
        pusher_ident                :: pusher_ident(),   % identification of client
        timeout_for_gun_ws_upgrade  :: non_neg_integer(),% timeout for gun_ws_upgrade message
        timeout_for_subscribtion    :: non_neg_integer(),% timeout for get confirmation for subscribtion
        timeout_before_ping         :: 'from_pusher' | non_neg_integer(),% timeout before we send ping message
        timeout_for_ping            :: non_neg_integer(),% timeout for get ping message
        % erlpusher operations section
        timeout_before_ping_set     :: 'undefined' | pos_integer(),
        timeout_last_global_frame   :: 'undefined' | pos_integer(),    % timeout before we going to flush gun connection if haven't new messages
        pusher_url                  :: 'undefined' | nonempty_list(),  % generated pusher url
        heartbeat_freq              :: 'undefined' | pos_integer(),    % min(timeout_for_gun_ws_upgrade, timeout_for_subscribtion, timeout_last_global_frame) 
        gun_pid                     :: 'undefined' | pid(),            % current gun connection Pid
        gun_mon_ref                 :: 'undefined' | reference(),      % current gun monitor refference
        connected_since             :: 'undefined' | pos_integer(),    % connected since
        last_frame                  :: 'undefined' | pos_integer(),    % last frame timestamp
        heartbeat_tref              :: 'undefined' | reference()       % last heartbeat time refference
    }).
-type erlpusher_state() :: #erlpusher_state{}.

-record(erlpusher_frame, {
        app_id          :: nonempty_list(),
        channel         :: channel(), 
        data           :: binary()
    }).
-type erlpusher_frame() :: #erlpusher_frame{}.
