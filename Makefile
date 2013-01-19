REBAR=./rebar
ALL_APPS_DIRS=src/*
ALL_EXAMPLE_DIRS=src/examples/*
COMMON_TEST=ctest
COMMON_TEST_LOG_DIRS=${COMMON_TEST}/logs
CT_DEPS=../deps
CT_TOP=../src

all: deps compile

deps: deps/erlangsp

deps/erlangsp:
	@${REBAR} get-deps

compile:
	@${REBAR} compile

dialyze: all
	@dialyzer -Wrace_conditions ${ALL_APPS_DIRS}/ebin ${ALL_EXAMPLE_DIRS}/ebin

gc: crash
	@echo 'Removing all emacs backup files'
	@find . -name "*~" -exec rm -f {} \;
	@find . -name "erl_crash.dump" -exec rm -f {} \;
	@echo 'Removing all compile artifacts'
	@rm -f ${ALL_APPS_DIRS}/src/*.P
	@rm -f ${ALL_APPS_DIRS}/src/*/*.P
	@rm -f ${ALL_APPS_DIRS}/src/*.beam
	@rm -f ${ALL_APPS_DIRS}/src/*/*.beam
	@echo 'Removing all example compile artifacts'
	@rm -f ${ALL_EXAMPLE_DIRS}/src/*.P
	@rm -f ${ALL_EXAMPLE_DIRS}/src/*/*.P
	@rm -f ${ALL_EXAMPLE_DIRS}/src/*.beam
	@rm -f ${ALL_EXAMPLE_DIRS}/src/*/*.beam
	@echo 'Removing all common_test beams'
	@rm -f ${COMMON_TEST}/*/*.beam
	@echo 'Removing all common_test logs'
	@rm -rf ${COMMON_TEST_LOG_DIRS}/*.*
	@rm -f ${COMMON_TEST_LOG_DIRS}/variables-ct*

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
	@(cd ${COMMON_TEST}; ct_run -spec coop.spec -pz ${CT_TOP}/coop/ebin -pz ${CT_DEPS}/*/ebin)
	@(cd ${COMMON_TEST}; ct_run -spec esp.spec -pz ${CT_TOP}/coop/ebin -pz ${CT_TOP}/erlangsp/ebin -pz ${CT_DEPS}/*/ebin)
	@(cd ${COMMON_TEST}; ct_run -spec examples.spec -pz ${CT_TOP}/coop/ebin -pz ${CT_TOP}/erlangsp/ebin -pz ${CT_TOP}/examples/*/ebin -pz ${CT_DEPS}/*/ebin)

coop_test: all
	@(cd ${COMMON_TEST}; ct_run -spec coop.spec -pz ${CT_TOP}/coop/ebin -pz ${CT_DEPS}/*/ebin)

esp_test: all
	@(cd ${COMMON_TEST}; ct_run -spec esp.spec -pz ${CT_TOP}/coop/ebin  -pz ${CT_TOP}/erlangsp/ebin -pz ${CT_DEPS}/*/ebin)

examples_test: all
	@(cd ${COMMON_TEST}; ct_run -spec examples.spec -pz ${CT_TOP}/coop/ebin -pz ${CT_TOP}/erlangsp/ebin -pz ${CT_TOP}/examples/*/ebin -pz ${CT_DEPS}/*/ebin)

ct: coop_test

et: esp_test

ext: examples_test
