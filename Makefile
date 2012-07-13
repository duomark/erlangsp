REBAR=./rebar
ALL_APPS_DIRS=apps/*
CT_LOG_DIRS=apps/ctest/*/logs

all: deps compile

deps: deps/erlangsp

deps/erlangsp:
	@${REBAR} get-deps

compile:
	@${REBAR} compile

dialyze: all
	@dialyzer -Wrace_conditions ebin

gc: crash
	@echo 'Removing all emacs backup files'
	@find . -name "*~" -exec rm -f {} \;
	@find . -name "erl_crash.dump" -exec rm -f {} \;
	@rm -f ${ALL_APPS_DIRS}/src/*.P
	@rm -f ${ALL_APPS_DIRS}/src/*/*.P
	@rm -f ${ALL_APPS_DIRS}/src/*.beam
	@rm -f ${ALL_APPS_DIRS}/src/*/*.beam
	@echo 'Removing all common_test logs'
	@rm -rf ${CT_LOG_DIRS}/*.*
	@rm -f ${CT_LOG_DIRS}/variables-ct*

rel: all
	@echo 'Generating erlangsp release'
	@(cd rel; .${REBAR} generate)

clean: gc
	@${REBAR} clean

crash:
	@find . -name "erl_crash.dump" -exec rm -f {} \;

relclean: crash
	@rm -rf rel/erlangsp

realclean: clean relclean
	@${REBAR} del-deps
	@rm -rf deps/*

test: all
	make ct

ct: 
	@(cd apps/ctest; ct_run -spec coop.spec -pa ../coop/ebin -pa ../../deps/*/ebin)
