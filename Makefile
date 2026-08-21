# ==========================================================================
# AXI4 UVM testbench - Cadence Xcelium (xrun) makefile
#
#   make smoke            first sanity run (directed write + readback)
#   make random           400 constrained-random bursts, READY_RANDOM
#   make backpressure     bursty B/R stalls (exercises stability SVA)
#   make b2b              back-to-back write/read pairs
#   make reset            mid-burst reset + recovery
#   make regress          all of the above; each must end with 0 UVM_ERRORs
#
#   make errors           }  bug-hunting tests: with the current RTL these
#   make wid              }  FAIL ON PURPOSE - each failure is the signature
#   make early_wlast      }  of a real DUT bug (see README "Bugs found")
#   make bugs             run all three
#
#   make waves TEST=...   same run + SHM waveform dump (view: simvision waves.shm &)
#   make cov  TEST=...    same run + coverage (view: imc -load cov_work/scope/<test> &)
#   make gui  TEST=...    interactive SimVision session
#   make clean
#
# Knobs: TEST=<uvm test>  SEED=<int|random>  VERBOSITY=UVM_LOW|UVM_MEDIUM|UVM_HIGH
# ==========================================================================

XRUN      ?= xrun
TEST      ?= axi_smoke_test
SEED      ?= random
VERBOSITY ?= UVM_MEDIUM

XRUN_OPTS  = -64bit -sv -uvm -timescale 1ns/1ps \
             +incdir+. -f filelist.f \
             -access +rwc -svseed $(SEED) \
             +UVM_VERBOSITY=$(VERBOSITY)

PASS_TESTS = axi_smoke_test axi_random_test axi_backpressure_test axi_b2b_test axi_reset_test
BUG_TESTS  = axi_error_test axi_wid_test axi_early_wlast_test

.PHONY: help smoke random backpressure b2b reset errors wid early_wlast \
        regress bugs run _run _pass _bug waves cov gui clean

help:
	@sed -n '2,30p' Makefile

# ---- passing tests -------------------------------------------------------
smoke:        ; @$(MAKE) --no-print-directory _pass TEST=axi_smoke_test
random:       ; @$(MAKE) --no-print-directory _pass TEST=axi_random_test
backpressure: ; @$(MAKE) --no-print-directory _pass TEST=axi_backpressure_test
b2b:          ; @$(MAKE) --no-print-directory _pass TEST=axi_b2b_test
reset:        ; @$(MAKE) --no-print-directory _pass TEST=axi_reset_test

# ---- bug-hunting tests (expected to fail on current RTL) -----------------
errors:       ; @$(MAKE) --no-print-directory _bug TEST=axi_error_test
wid:          ; @$(MAKE) --no-print-directory _bug TEST=axi_wid_test
early_wlast:  ; @$(MAKE) --no-print-directory _bug TEST=axi_early_wlast_test

regress:
	@for t in $(PASS_TESTS); do \
	  $(MAKE) --no-print-directory _pass TEST=$$t || exit 1; \
	done
	@echo "==== REGRESSION PASSED: $(PASS_TESTS) ===="

bugs:
	@for t in $(BUG_TESTS); do \
	  $(MAKE) --no-print-directory _bug TEST=$$t; \
	done
	@echo "==== Bug demos done - inspect logs/<test>.log for the failure signatures ===="

# ---- plumbing ------------------------------------------------------------
run: _run

_run:
	@mkdir -p logs
	$(XRUN) $(XRUN_OPTS) +UVM_TESTNAME=$(TEST) -l logs/$(TEST).log

_pass: _run
	@if grep -Eq "UVM_ERROR *: *0" logs/$(TEST).log && \
	    grep -Eq "UVM_FATAL *: *0" logs/$(TEST).log; then \
	  echo "PASS: $(TEST)"; \
	else \
	  echo "FAIL: $(TEST)  (see logs/$(TEST).log)"; exit 1; \
	fi

_bug: _run
	@if grep -Eq "UVM_ERROR *: *0" logs/$(TEST).log && \
	    grep -Eq "UVM_FATAL *: *0" logs/$(TEST).log; then \
	  echo "UNEXPECTED PASS: $(TEST) found no bug - was the RTL fixed?"; \
	else \
	  echo "BUG REPRODUCED by $(TEST) - failure signature in logs/$(TEST).log"; \
	fi

waves:
	@mkdir -p logs
	$(XRUN) $(XRUN_OPTS) +UVM_TESTNAME=$(TEST) -input probe.tcl -l logs/$(TEST)_waves.log
	@echo "View waveforms with:  simvision waves.shm &"

cov:
	@mkdir -p logs
	$(XRUN) $(XRUN_OPTS) +UVM_TESTNAME=$(TEST) -coverage all -covtest $(TEST) \
	  -covoverwrite -l logs/$(TEST)_cov.log
	@echo "View coverage with:   imc -load cov_work/scope/$(TEST) &"

gui:
	$(XRUN) $(XRUN_OPTS) +UVM_TESTNAME=$(TEST) -gui -input probe.tcl

clean:
	rm -rf xcelium.d xrun.history xrun.log xrun.key logs waves.shm \
	       cov_work .simvision *.diag mdv.log *.err simvision*.diag

# --------------------------------------------------------------------------
# Questa fallback:
#   vlog -sv -timescale 1ns/1ps +incdir+. -f filelist.f
#   vsim -c tb_top +UVM_TESTNAME=axi_smoke_test -do "run -all; quit"
# VCS fallback:
#   vcs -full64 -sverilog -ntb_opts uvm -timescale=1ns/1ps +incdir+. -f filelist.f
#   ./simv +UVM_TESTNAME=axi_smoke_test
# --------------------------------------------------------------------------
