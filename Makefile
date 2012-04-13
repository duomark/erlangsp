all: deps compile

deps: deps/erlangsp

deps/erlangsp:
	@./rebar get-deps

compile:
	@./rebar compile

dialyze: all
	@dialyzer -Wrace_conditions ebin

gc: crash
	@echo 'Removing all emacs backup files'
	@find . -name "*~" -exec rm -f {} \;
	@rm -f src/*.P
	@rm -f src/*.beam

rel: all
	@echo 'Generating erlangsp release'
	@(cd rel; ../rebar generate)

clean: gc
	@./rebar clean

crash:
	@find . -name "erl_crash.dump" -exec rm -f {} \;

relclean: crash
	@rm -rf rel/erlangsp

realclean: clean relclean
	@./rebar del-deps
	@rm -rf deps/*

test: all
	make ct

ct: 
	@(cd ctest; ct_run -spec coop.spec -pa ../ebin)
