`timescale 1ns/1ps
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
  // input #1step samples in the Preponed region: the driver and monitor see
  // exactly the values the DUT's flops sampled at the same edge, so handshake
  // detection can never race the DUT's non-blocking updates.
  // bready/rready are inout: a separate background task (drive_ready_policy)
  // drives them continuously, so the transaction tasks must read back the
  // current value. awvalid/wvalid/arvalid are output-only and stay that way
  // on purpose - only the transaction task that drives one ever needs its
  // value, so it's tracked locally; reading a signal back through the same
  // clocking block in the same task that just wrote it is a self-observation
  // pattern that can stall indefinitely instead of seeing the write.
  clocking drv_cb @(posedge clk);
    default input #1step output #0;
    // Drive only (this task is the only writer, so no read-back needed)
    output awvalid, wvalid, arvalid;
    output awid, awlen, awsize, awaddr, awburst;
    output wid, wdata, wstrb, wlast;
    output arid, araddr, arlen, arsize, arburst;
    // Drive + sample (driven by drive_ready_policy, read by the transaction tasks)
    inout  bready, rready;

    // Sample (from slave/DUT)
    input  awready;
    input  wready;
    input  bvalid, bid, bresp;
    input  arready;
    input  rvalid, rid, rdata, rresp, rlast;
    input  resetn;
  endclocking

  clocking mon_cb @(posedge clk);
    default input #1step;
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
  // 1) Payload stable while stalled (VALID=1, READY=0).
  // |=> (forward, non-overlapped) checks the CYCLE AFTER a stall against the
  // stall itself. The earlier |-> $stable(...) compared against the PRIOR
  // cycle instead, which false-fires whenever a channel's payload legitimately
  // changes on the very first cycle a *new*, unrelated transfer happens to
  // stall (fresh data at cycle N compared against the previous transfer's
  // different data at cycle N-1, not a real held-payload violation).
  property p_stable_aw;
    @(posedge clk) disable iff (!resetn)
      (awvalid && !awready) |=> (awvalid && $stable({awid,awlen,awsize,awaddr,awburst}));
  endproperty
  a_stable_aw: assert property (p_stable_aw)
    else $error("AXI-SVA: AW payload changed while AWVALID stalled");

  property p_stable_w;
    @(posedge clk) disable iff (!resetn)
      (wvalid && !wready) |=> (wvalid && $stable({wid,wdata,wstrb,wlast}));
  endproperty
  a_stable_w: assert property (p_stable_w)
    else $error("AXI-SVA: W payload changed while WVALID stalled");

  property p_stable_ar;
    @(posedge clk) disable iff (!resetn)
      (arvalid && !arready) |=> (arvalid && $stable({arid,araddr,arlen,arsize,arburst}));
  endproperty
  a_stable_ar: assert property (p_stable_ar)
    else $error("AXI-SVA: AR payload changed while ARVALID stalled");

  // DUT must hold B payload stable while BVALID && !BREADY
  property p_stable_b;
    @(posedge clk) disable iff (!resetn)
      (bvalid && !bready) |=> (bvalid && $stable({bid,bresp}));
  endproperty
  a_stable_b: assert property (p_stable_b)
    else $error("AXI-SVA: B payload changed while BVALID stalled");

  // DUT must hold R payload stable while RVALID && !RREADY
  property p_stable_r;
    @(posedge clk) disable iff (!resetn)
      (rvalid && !rready) |=> (rvalid && $stable({rid,rdata,rresp,rlast}));
  endproperty
  a_stable_r: assert property (p_stable_r)
    else $error("AXI-SVA: R payload changed while RVALID stalled");

  // 2) VALID must stay asserted until READY (A3.2.1: no retracting a request)
  property p_hold_aw;
    @(posedge clk) disable iff (!resetn)
      (awvalid && !awready) |=> awvalid;
  endproperty
  a_hold_aw: assert property (p_hold_aw)
    else $error("AXI-SVA: AWVALID deasserted before AWREADY");

  property p_hold_w;
    @(posedge clk) disable iff (!resetn)
      (wvalid && !wready) |=> wvalid;
  endproperty
  a_hold_w: assert property (p_hold_w)
    else $error("AXI-SVA: WVALID deasserted before WREADY");

  property p_hold_ar;
    @(posedge clk) disable iff (!resetn)
      (arvalid && !arready) |=> arvalid;
  endproperty
  a_hold_ar: assert property (p_hold_ar)
    else $error("AXI-SVA: ARVALID deasserted before ARREADY");

  property p_hold_b;
    @(posedge clk) disable iff (!resetn)
      (bvalid && !bready) |=> bvalid;
  endproperty
  a_hold_b: assert property (p_hold_b)
    else $error("AXI-SVA: BVALID deasserted before BREADY");

  property p_hold_r;
    @(posedge clk) disable iff (!resetn)
      (rvalid && !rready) |=> rvalid;
  endproperty
  a_hold_r: assert property (p_hold_r)
    else $error("AXI-SVA: RVALID deasserted before RREADY");

  // 3) Response channels must be quiet while in reset (A3.1.2)
  property p_reset_quiet;
    @(posedge clk)
      (!resetn) |-> ((bvalid === 1'b0) && (rvalid === 1'b0));
  endproperty
  a_reset_quiet: assert property (p_reset_quiet)
    else $error("AXI-SVA: BVALID/RVALID asserted while resetn low");

  // 4) No unknown values on active response payloads or ready outputs
  property p_no_x_b;
    @(posedge clk) disable iff (!resetn)
      bvalid |-> !$isunknown({bid,bresp});
  endproperty
  a_no_x_b: assert property (p_no_x_b)
    else $error("AXI-SVA: X on B payload while BVALID");

  property p_no_x_r;
    @(posedge clk) disable iff (!resetn)
      rvalid |-> !$isunknown({rid,rdata,rresp,rlast});
  endproperty
  a_no_x_r: assert property (p_no_x_r)
    else $error("AXI-SVA: X on R payload while RVALID");

  property p_no_x_ready;
    @(posedge clk) disable iff (!resetn)
      !$isunknown({awready,wready,arready});
  endproperty
  a_no_x_ready: assert property (p_no_x_ready)
    else $error("AXI-SVA: X on a DUT ready output");

endinterface
