PROJECT = erlpusher

DEPS = gun poolboy

dep_gun = git https://github.com/ninenines/gun master
dep_poolboy = git https://github.com/devinus/poolboy master

include erlang.mk
