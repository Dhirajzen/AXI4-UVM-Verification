class axi_sequencer extends uvm_sequencer #(axi_item);
  `uvm_component_utils(axi_sequencer)
  function new(string name, uvm_component parent);
    super.new(name,parent);
  endfunction
endclass

class axi_agent extends uvm_component;
  `uvm_component_utils(axi_agent)

  axi_cfg       cfg;
  axi_sequencer seqr;
  axi_driver    drv;
  axi_monitor   mon;

  uvm_analysis_port #(axi_item) ap;

  function new(string name, uvm_component parent);
    super.new(name,parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(axi_cfg)::get(this, "", "cfg", cfg))
      cfg = axi_cfg::type_id::create("cfg");

    mon = axi_monitor::type_id::create("mon", this);

    if (cfg.is_active) begin
      seqr = axi_sequencer::type_id::create("seqr", this);
      drv  = axi_driver   ::type_id::create("drv",  this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    mon.ap.connect(ap);
    if (cfg.is_active) begin
      drv.seq_item_port.connect(seqr.seq_item_export);
    end
  endfunction

endclass