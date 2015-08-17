%% - need specify by user
-record(erlpusher_state, {
        % user specification section
        server,                                      % moderate: servername
        pusher_app_id,                               % moderate: pusher_app_id
        channels,                                    % moderate: channel for subscribe
        report_topic,                                % generated or predefined output topic
        pusher_ident = "erlpusher",                  % identification of client
        timeout_for_gun_ws_upgrade = 10000,          % timeout for gun_ws_upgrade message
        noreceive_ttl = 60000,                       % timeout before we going to flush gun connection if haven't new messages
        heartbeat_freq = 1000,                       % heartbeat frequency (in milliseconds) 
        % pusher_client operations section
        gun_pid,                                     % current gun connection Pid
        gun_ref,                                     % current gun monitor refference
        heartbeat_tref                               % last heartbeat time refference
    }).
