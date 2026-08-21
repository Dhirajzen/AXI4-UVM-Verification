`timescale 1ns/1ps
module tb_top;
  import uvm_pkg::*;
  import axi_pkg::*;

  logic clk;
  initial clk = 0;
  always #5 clk = ~clk;

  axi_if axi_vif(.clk(clk));

  // Reset (master-side signals are initialized by the driver through its
  // clocking block - driving them here too would multi-drive the interface)
  initial begin
    axi_vif.resetn = 0;
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

  // Hook up VIF to UVM. Wildcard scope: the test, driver, and monitor all
  // pick it up regardless of hierarchy names (hard-coded absolute paths
  // silently break on any rename).
    initial begin
        uvm_config_db#(virtual axi_if)::set(null, "*", "vif", axi_vif);
        run_test("axi_smoke_test"); // default; +UVM_TESTNAME overrides
    end
endmodule