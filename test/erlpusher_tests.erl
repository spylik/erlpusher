-module(erlpusher_tests).

-include_lib("eunit/include/eunit.hrl").
-include("erlpusher.hrl").

-define(TESTMODULE, erlpusher).
-define(TESTSERVER, test_ws_server).
-define(SpawnWaitLoop, 200).
-define(RecieveLoop, 250).

% --------------------------------- fixtures ----------------------------------

% tests for cover standart otp behaviour
otp_test_() ->
    {setup,
        % setup
        fun() ->
            tutils:setup_start([{'apps',[ranch,crypto,asn1,public_key,ssl,cowlib,gun]}])
        end,
        % cleanup
        fun(ToStop) ->
            tutils:cleanup_stop(ToStop)
        end,
        {inparallel,
            [
                {<<"gen_server able to start via ?TESTSERVER:start_link(PusherAppId) and stop">>,
                    fun() ->
                        {ok, Pid} = ?TESTMODULE:start_link("de504dc5763aeef9ff52"),
                        ?assert(
                            is_list(process_info(Pid))
                        ),
                        ok = ?TESTMODULE:stop(Pid),
                        ?assertEqual(
                            'undefined',
                            process_info(Pid)
                        )
                end}
            ]
        }
    }.
