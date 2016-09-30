-record(erlpusher_state, {
        % user specification section
        server :: atom(),                                       % moderate: servername
        pusher_app_id :: nonempty_list(),                       % moderate: pusher_app_id
        channels = [] :: [] | [binary()],                       % channel for subscribe after re-connect
        subscribed = [] :: [] | [binary()],                     % subscribed to channels 
        report_to :: 'undefined' | atom() | pid(),              % send output frames to pid or erlroute
        report_topic :: binary(),                               % generated or predefined output topic for erlroute
        pusher_ident = "erlpusher",                             % identification of client
        timeout_for_gun_ws_upgrade = 10000 :: non_neg_integer(),% timeout for gun_ws_upgrade message
        noreceive_ttl = 60000 :: pos_integer(),                 % timeout before we going to flush gun connection if haven't new messages
        heartbeat_freq = 1000 :: pos_integer(),                 % heartbeat frequency (in milliseconds) 
        % pusher_client operations section
        pusher_url :: 'undefined' | nonempty_list(),            % generated pusher url
        gun_pid :: 'undefined' | pid(),                         % current gun connection Pid
        gun_ref :: reference(),                                 % current gun monitor refference
        last_frame :: 'undefined' | pos_integer(),                            % last frame timestamp
        heartbeat_tref :: reference()                           % last heartbeat time refference
    }).
