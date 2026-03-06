class axi_cfg extends uvm_object;
  `uvm_object_utils(axi_cfg)

  bit             is_active = 1; // active agent (driver+sequencer)
  ready_policy_e  ready_policy = READY_ALWAYS;

  // For READY_BURSTY
  int unsigned    stall_min = 0;
  int unsigned    stall_max = 5;

  // Scoreboard strictness
  bit check_mem_on_error = 0;

  function new(string name="axi_cfg");
    super.new(name);
  endfunction
endclass