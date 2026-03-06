`timescale 1ns/1ps
module tb_top;
  import uvm_pkg::*;
  import axi_pkg::*;

  logic clk;
  initial clk = 0;
  always #5 clk = ~clk;

  axi_if axi_vif(.clk(clk));

  // Reset
  initial begin
    axi_vif.resetn = 0;

    // default drives
    axi_vif.awvalid = 0;
    axi_vif.wvalid  = 0;
    axi_vif.arvalid = 0;
    axi_vif.bready  = 0;
    axi_vif.rready  = 0;

    repeat (5) @(posedge clk);
    axi_vif.resetn = 1;
  end

  // DUT
  axi_slave #(.MEM_BYTES(128)) dut (
    .clk     (clk),
    .resetn  (axi_vif.resetn),

    .awvalid (axi_vif.awvalid),
    .awready (axi_vif.awready),
    .awid    (axi_vif.awid),
    .awlen   (axi_vif.awlen),
    .awsize  (axi_vif.awsize),
    .awaddr  (axi_vif.awaddr),
    .awburst (axi_vif.awburst),

    .wvalid  (axi_vif.wvalid),
    .wready  (axi_vif.wready),
    .wid     (axi_vif.wid),
    .wdata   (axi_vif.wdata),
    .wstrb   (axi_vif.wstrb),
    .wlast   (axi_vif.wlast),

    .bready  (axi_vif.bready),
    .bvalid  (axi_vif.bvalid),
    .bid     (axi_vif.bid),
    .bresp   (axi_vif.bresp),

    .arready (axi_vif.arready),
    .arid    (axi_vif.arid),
    .araddr  (axi_vif.araddr),
    .arlen   (axi_vif.arlen),
    .arsize  (axi_vif.arsize),
    .arburst (axi_vif.arburst),
    .arvalid (axi_vif.arvalid),

    .rid     (axi_vif.rid),
    .rdata   (axi_vif.rdata),
    .rresp   (axi_vif.rresp),
    .rlast   (axi_vif.rlast),
    .rvalid  (axi_vif.rvalid),
    .rready  (axi_vif.rready)
  );

  // Hook up VIF to UVM
    initial begin
        uvm_config_db#(virtual axi_if.master_mp)::set(
        null, "uvm_test_top.env.agent.drv", "vif", axi_vif.master_mp
        );
        uvm_config_db#(virtual axi_if.monitor_mp)::set(
        null, "uvm_test_top.env.agent.mon", "vif", axi_vif.monitor_mp
        );
        run_test(); // allow +UVM_TESTNAME
    end
endmodule