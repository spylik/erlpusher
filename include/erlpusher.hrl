-type channel_status() :: 'toconnect' | 'casted' | 'connected' | 'errored'.

-record(channel_prop, {
        status = 'toconnect' :: channel_status(),
        created :: pos_integer(),
        cast_sub :: 'undefined' | pos_integer(),
        get_sub_confirm :: 'undefined' | pos_integer(),
        last_frame :: 'undefined' | pos_integer()
    }).
-type channel_prop() :: #channel_prop{}.

-record(erlpusher_state, {
        % user specification section
        server :: atom(),                                                   % moderate: servername
        pusher_app_id :: nonempty_list(),                                   % moderate: pusher_app_id
        channels = #{} :: #{} | #{binary() => channel_prop()},              % channel list
        report_to :: 'undefined' | atom() | pid(),                          % send output frames to pid or erlroute
        report_topic :: binary(),                                           % generated or predefined output topic for erlroute
        pusher_ident = "erlpusher" :: nonempty_list(),                                         % identification of client
        timeout_for_gun_ws_upgrade = 10000 :: non_neg_integer(),            % timeout for gun_ws_upgrade message
        timeout_for_subscribtion = 10000 :: non_neg_integer(),              % timeout for get confirmation for subscribtion
        noreceive_conn_ttl = 60000 :: pos_integer(),                        % timeout before we going to flush gun connection if haven't new messages
        heartbeat_freq = 1000 :: pos_integer(),                             % heartbeat frequency (in milliseconds) 
        % pusher_client operations section
        pusher_url :: 'undefined' | nonempty_list(),                        % generated pusher url
        gun_pid :: 'undefined' | pid(),                                     % current gun connection Pid
        gun_mon_ref :: reference(),                                             % current gun monitor refference
        last_frame :: 'undefined' | pos_integer(),                          % last frame timestamp
        heartbeat_tref :: reference()                                       % last heartbeat time refference
    }).
-type erlpusher_state() :: #erlpusher_state{}.
