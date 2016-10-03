PROJECT = erlpusher

TEST_ERLC_OPTS += +warn_export_vars +warn_shadow_vars +warn_obsolete_guard +debug_info
TEST_ERLC_OPTS += +'{parse_transform, lager_transform}'

#ERLC_OPTS += +warn_export_vars +warn_shadow_vars +warn_obsolete_guard +warn_missing_spec #-Werror

# our deps
dep_teaser = git https://github.com/spylik/teaser master
dep_erlroute = git https://github.com/spylik/erlroute master

DEPS = gun 

TEST_DEPS = lager teaser erlroute
SHELL_DEPS = sync

SHELL_OPTS = -config deps/teaser/sys.config +c true +C multi_time_warp -pa ebin/ test/ -eval 'lager:start(), mlibs:discover()' -env ERL_LIBS deps -run mlibs autotest_on_compile

include erlang.mk
