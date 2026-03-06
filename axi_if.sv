interface axi_if (input logic clk);
  logic resetn;

  // AW
  logic        awvalid;
  logic        awready;
  logic [3:0]  awid;
  logic [3:0]  awlen;
  logic [2:0]  awsize;
  logic [31:0] awaddr;
  logic [1:0]  awburst;

  // W
  logic        wvalid;
  logic        wready;
  logic [3:0]  wid;
  logic [31:0] wdata;
  logic [3:0]  wstrb;
  logic        wlast;

  // B
  logic        bready;
  logic        bvalid;
  logic [3:0]  bid;
  logic [1:0]  bresp;

  // AR
  logic        arvalid;
  logic        arready;
  logic [3:0]  arid;
  logic [31:0] araddr;
  logic [3:0]  arlen;
  logic [2:0]  arsize;
  logic [1:0]  arburst;

  // R
  logic        rready;
  logic        rvalid;
  logic [3:0]  rid;
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rlast;

  // -------------------------
  // Clocking blocks
  // -------------------------
  clocking drv_cb @(posedge clk);
    default input #1step output #1step;
    // Drive (master)
    output awvalid, awid, awlen, awsize, awaddr, awburst;
    output wvalid, wid, wdata, wstrb, wlast;
    output bready;
    output arvalid, arid, araddr, arlen, arsize, arburst;
    output rready;

    // Sample (from slave/DUT)
    input  awready;
    input  wready;
    input  bvalid, bid, bresp;
    input  arready;
    input  rvalid, rid, rdata, rresp, rlast;
    input  resetn;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step output #1step;
    input resetn;

    input awvalid, awready, awid, awlen, awsize, awaddr, awburst;
    input wvalid, wready, wid, wdata, wstrb, wlast;
    input bvalid, bready, bid, bresp;
    input arvalid, arready, arid, araddr, arlen, arsize, arburst;
    input rvalid, rready, rid, rdata, rresp, rlast;
  endclocking

  // Modports
  modport master_mp (clocking drv_cb, input clk);
  modport monitor_mp (clocking mon_cb, input clk);


  

  // -------------------------
  // Key protocol assertions
  // -------------------------
  // Payload stable while stalled (VALID=1, READY=0)
  property p_stable_aw;
    @(posedge clk) disable iff (!resetn)
      (awvalid && !awready) |-> $stable({awid,awlen,awsize,awaddr,awburst});
  endproperty
  a_stable_aw: assert property (p_stable_aw);

  property p_stable_w;
    @(posedge clk) disable iff (!resetn)
      (wvalid && !wready) |-> $stable({wid,wdata,wstrb,wlast});
  endproperty
  a_stable_w: assert property (p_stable_w);

  property p_stable_ar;
    @(posedge clk) disable iff (!resetn)
      (arvalid && !arready) |-> $stable({arid,araddr,arlen,arsize,arburst});
  endproperty
  a_stable_ar: assert property (p_stable_ar);

  // DUT must hold B payload stable while BVALID && !BREADY
  property p_stable_b;
    @(posedge clk) disable iff (!resetn)
      (bvalid && !bready) |-> $stable({bid,bresp});
  endproperty
  a_stable_b: assert property (p_stable_b);

  // DUT must hold R payload stable while RVALID && !RREADY
  property p_stable_r;
    @(posedge clk) disable iff (!resetn)
      (rvalid && !rready) |-> $stable({rid,rdata,rresp,rlast});
  endproperty
  a_stable_r: assert property (p_stable_r);

endinterface