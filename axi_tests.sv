class axi_base_test extends uvm_test;
  `uvm_component_utils(axi_base_test)

  axi_env env;
  axi_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name,parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cfg = axi_cfg::type_id::create("cfg");
    cfg.is_active = 1;
    cfg.ready_policy = READY_ALWAYS; // start stable; switch to RANDOM later

    uvm_config_db#(axi_cfg)::set(this, "env", "cfg", cfg);

    env = axi_env::type_id::create("env", this);
  endfunction
endclass

class axi_smoke_test extends axi_base_test;
  `uvm_component_utils(axi_smoke_test)
  function new(string name, uvm_component parent); super.new(name,parent); endfunction

  task run_phase(uvm_phase phase);
    axi_smoke_seq seq;
    phase.raise_objection(this);

    // turn on some backpressure after smoke passes
    cfg.ready_policy = READY_ALWAYS;

    seq = axi_smoke_seq::type_id::create("seq");
    seq.start(env.agent.seqr);

    phase.drop_objection(this);
  endtask
endclass