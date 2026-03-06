class axi_env extends uvm_env;
  `uvm_component_utils(axi_env)

  axi_cfg       cfg;
  axi_agent     agent;
  axi_scoreboard scb;
  axi_coverage  cov;

  function new(string name, uvm_component parent);
    super.new(name,parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(axi_cfg)::get(this, "", "cfg", cfg))
      cfg = axi_cfg::type_id::create("cfg");

    agent = axi_agent::type_id::create("agent", this);
    scb   = axi_scoreboard::type_id::create("scb", this);
    cov   = axi_coverage ::type_id::create("cov", this);

    // push cfg down
    uvm_config_db#(axi_cfg)::set(this, "agent*", "cfg", cfg);
    uvm_config_db#(axi_cfg)::set(this, "scb",    "cfg", cfg);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.ap.connect(scb.imp);
    agent.ap.connect(cov.analysis_export);
  endfunction

endclass