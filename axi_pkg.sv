package axi_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum bit {AXI_READ=0, AXI_WRITE=1} axi_dir_e;

  typedef enum logic [1:0] {
    AXI_BURST_FIXED = 2'b00,
    AXI_BURST_INCR  = 2'b01,
    AXI_BURST_WRAP  = 2'b10
  } axi_burst_e;

  typedef enum int unsigned {
    READY_ALWAYS = 0,
    READY_RANDOM = 1,
    READY_BURSTY = 2
  } ready_policy_e;

  localparam logic [1:0] AXI_OKAY   = 2'b00;
  localparam logic [1:0] AXI_DECERR = 2'b11;

  `include "axi_item.sv"
  `include "axi_cfg.sv"
  `include "axi_driver.sv"
  `include "axi_monitor.sv"
  `include "axi_agent.sv"
  `include "axi_ref_model.sv"
  `include "axi_scoreboard.sv"
  `include "axi_coverage.sv"
  `include "axi_env.sv"
  `include "axi_seqs.sv"
  `include "axi_tests.sv"
endpackage