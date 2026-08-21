class axi_base_test extends uvm_test;
  `uvm_component_utils(axi_base_test)

  axi_env env;
  axi_cfg cfg;
  virtual axi_if vif;

  function new(string name, uvm_component parent);
    super.new(name,parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cfg = axi_cfg::type_id::create("cfg");
    cfg.is_active = 1;
    cfg.ready_policy = READY_ALWAYS;

    uvm_config_db#(axi_cfg)::set(this, "env", "cfg", cfg);

    env = axi_env::type_id::create("env", this);

    if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "axi_base_test: no vif")

    // Global watchdog: a protocol hang (e.g. Bug #2) becomes a clean
    // timeout failure instead of a wedged simulation.
    uvm_root::get().set_timeout(2ms, 1);
  endfunction
endclass

// ------------------------------------------------------------------
// Directed smoke: one write burst + readback. First thing to run.
// ------------------------------------------------------------------
class axi_smoke_test extends axi_base_test;
  `uvm_component_utils(axi_smoke_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction

  task run_phase(uvm_phase phase);
    axi_smoke_seq seq;
    phase.raise_objection(this);
    seq = axi_smoke_seq::type_id::create("seq");
    seq.start(env.agent.seqr);
    phase.drop_objection(this);
  endtask
endclass

// ------------------------------------------------------------------
// Constrained-random main test (READY_RANDOM backpressure on B/R).
// ------------------------------------------------------------------
class axi_random_test extends axi_base_test;
  `uvm_component_utils(axi_random_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.ready_policy = READY_RANDOM;
  endfunction

  task run_phase(uvm_phase phase);
    axi_rand_seq seq;
    phase.raise_objection(this);
    seq = axi_rand_seq::type_id::create("seq");
    seq.n_ops = 400;
    seq.start(env.agent.seqr);
    phase.drop_objection(this);
  endtask
endclass

// ------------------------------------------------------------------
// Bursty backpressure: READY held low for random stretches, which is
// what actually exercises the B/R stability and hold assertions.
// ------------------------------------------------------------------
class axi_backpressure_test extends axi_base_test;
  `uvm_component_utils(axi_backpressure_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    cfg.ready_policy = READY_BURSTY;
    cfg.stall_min = 1;
    cfg.stall_max = 8;
  endfunction

  task run_phase(uvm_phase phase);
    axi_rand_seq seq;
    phase.raise_objection(this);
    seq = axi_rand_seq::type_id::create("seq");
    seq.n_ops = 200;
    seq.start(env.agent.seqr);
    phase.drop_objection(this);
  endtask
endclass

// ------------------------------------------------------------------
// Back-to-back write/read pairs with zero idle cycles.
// ------------------------------------------------------------------
class axi_b2b_test extends axi_base_test;
  `uvm_component_utils(axi_b2b_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction

  task run_phase(uvm_phase phase);
    axi_b2b_seq seq;
    phase.raise_objection(this);
    seq = axi_b2b_seq::type_id::create("seq");
    seq.start(env.agent.seqr);
    phase.drop_objection(this);
  endtask
endclass

// ------------------------------------------------------------------
// Mid-burst reset: yank resetn during a 16-beat write, then prove the
// DUT and testbench both recover with clean traffic to a fresh region.
// ------------------------------------------------------------------
class axi_reset_test extends axi_base_test;
  `uvm_component_utils(axi_reset_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction

  task run_phase(uvm_phase phase);
    axi_directed_seq s;
    phase.raise_objection(this);

    // Phase 1: long write into region A (0x00..0x3F) + reset mid-burst.
    // Region A's contents are unpredictable afterwards (the DUT keeps
    // partially-written data), so it is never accessed again.
    fork
      begin
        s = axi_directed_seq::type_id::create("rst_wr_a");
        s.dir = AXI_WRITE; s.addr = 32'h0000_0000; s.len = 15; s.size = 2;
        s.id = 4'h3; s.base_data = 32'hAAAA_0000;
        s.start(env.agent.seqr);
      end
      begin
        #120ns; // lands mid W-burst
        `uvm_info("AXI_RST", "Asserting reset mid-burst", UVM_LOW)
        vif.resetn = 0;
        repeat (3) @(posedge vif.clk);
        vif.resetn = 1;
        `uvm_info("AXI_RST", "Reset released", UVM_LOW)
      end
    join

    // Phase 2: clean write + readback in region B (0x40..) must pass.
    s = axi_directed_seq::type_id::create("rst_wr_b");
    s.dir = AXI_WRITE; s.addr = 32'h0000_0040; s.len = 3; s.size = 2;
    s.id = 4'h4; s.base_data = 32'h5E5E_0000;
    s.start(env.agent.seqr);

    s = axi_directed_seq::type_id::create("rst_rd_b");
    s.dir = AXI_READ; s.addr = 32'h0000_0040; s.len = 3; s.size = 2;
    s.id = 4'h5;
    s.start(env.agent.seqr);

    phase.drop_objection(this);
  endtask
endclass

// ==================================================================
// Bug-hunting tests. With the current RTL these FAIL BY DESIGN —
// each failure is the signature of a real DUT bug (see README).
// ==================================================================

// Exposes Bug #1 (stale error flag): cases 5/6 get OKAY where DECERR is due.
class axi_error_test extends axi_base_test;
  `uvm_component_utils(axi_error_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction

  task run_phase(uvm_phase phase);
    axi_err_seq seq;
    phase.raise_objection(this);
    seq = axi_err_seq::type_id::create("seq");
    seq.start(env.agent.seqr);
    phase.drop_objection(this);
  endtask
endclass

// Exposes Bug #3 (memory committed on errored burst): readback mismatches.
class axi_wid_test extends axi_base_test;
  `uvm_component_utils(axi_wid_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction

  task run_phase(uvm_phase phase);
    axi_wid_seq seq;
    phase.raise_objection(this);
    seq = axi_wid_seq::type_id::create("seq");
    seq.start(env.agent.seqr);
    phase.drop_objection(this);
  endtask
endclass

// Exposes Bug #2 (write FSM hang on early WLAST): the watchdog converts
// the hang into a reported error instead of a wedged simulation.
class axi_early_wlast_test extends axi_base_test;
  `uvm_component_utils(axi_early_wlast_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction

  task run_phase(uvm_phase phase);
    axi_early_wlast_seq seq;
    phase.raise_objection(this);
    seq = axi_early_wlast_seq::type_id::create("seq");

    fork begin
      fork
        seq.start(env.agent.seqr);
        begin
          #20us;
          `uvm_error("BUG2_HANG",
            "DUT hung after early WLAST: write FSM ignored WLAST and never returned BRESP (axi_slave.sv WR_DATA state)")
        end
      join_any
      disable fork;
    end join

    phase.drop_objection(this);
  endtask
endclass
