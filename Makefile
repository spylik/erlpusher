PROJECT = erlpusher

TEST_ERLC_OPTS += +warn_export_vars +warn_shadow_vars +warn_obsolete_guard +debug_info
TEST_ERLC_OPTS += +'{parse_transform, lager_transform}'

#ERLC_OPTS += +warn_export_vars +warn_shadow_vars +warn_obsolete_guard +warn_missing_spec #-Werror

# our deps
dep_teaser = git https://github.com/spylik/teaser master
dep_erlroute = git https://github.com/spylik/erlroute master

# 3-rd party deps
dep_gun = git https://github.com/ninenines/gun master
dep_poolboy = git https://github.com/devinus/poolboy master

DEPS = gun 

TEST_DEPS = teaser erlroute poolboy
SHELL_DEPS = sync lager

SHELL_OPTS = -config deps/teaser/sys.config +c true +C multi_time_warp -pa ebin/ test/ -eval 'lager:start(), mlibs:discover()' -env ERL_LIBS deps -run mlibs autotest_on_compile

include erlang.mk
