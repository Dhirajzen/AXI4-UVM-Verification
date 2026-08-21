class axi_base_seq extends uvm_sequence #(axi_item);
  `uvm_object_utils(axi_base_seq)
  function new(string name="axi_base_seq"); super.new(name); endfunction
endclass

// ------------------------------------------------------------------
// Reusable directed single-burst sequence: set the fields, start it.
// ------------------------------------------------------------------
class axi_directed_seq extends axi_base_seq;
  `uvm_object_utils(axi_directed_seq)

  axi_dir_e   dir       = AXI_WRITE;
  bit [3:0]   id        = 4'h1;
  bit [31:0]  addr      = '0;
  bit [3:0]   len       = 4'd0;
  bit [2:0]   size      = 3'd2;
  axi_burst_e burst     = AXI_BURST_INCR;
  bit [31:0]  base_data = 32'hD000_0000;
  bit [3:0]   strb      = 4'hF;
  bit         early_wlast = 0;
  bit         corrupt_wid = 0;

  function new(string name="axi_directed_seq"); super.new(name); endfunction

  task body();
    axi_item tr;
    tr = axi_item::type_id::create("tr");
    tr.dir   = dir;
    tr.id    = id;
    tr.addr  = addr;
    tr.len   = len;
    tr.size  = size;
    tr.burst = burst;
    tr.early_wlast = early_wlast;
    tr.corrupt_wid = corrupt_wid;
    if (dir == AXI_WRITE) begin
      tr.wdata_q = new[tr.beats_total()];
      tr.wstrb_q = new[tr.beats_total()];
      foreach (tr.wdata_q[i]) begin
        tr.wdata_q[i] = base_data + i;
        tr.wstrb_q[i] = strb;
      end
    end
    start_item(tr);
    finish_item(tr);
  endtask
endclass

class axi_smoke_seq extends axi_base_seq;
  `uvm_object_utils(axi_smoke_seq)
  function new(string name="axi_smoke_seq"); super.new(name); endfunction

  task body();
    axi_item w, r;

    // Write: INCR, 4 beats, 4 bytes/beat
    w = axi_item::type_id::create("w");
    w.dir   = AXI_WRITE;
    w.id    = 4'h1;
    w.addr  = 32'h0000_0010;
    w.len   = 4'd3;                  // 4 beats
    w.size  = 3'd2;                  // 4 bytes
    w.burst = AXI_BURST_INCR;
    w.wdata_q = new[w.beats_total()];
    w.wstrb_q = new[w.beats_total()];
    foreach (w.wdata_q[i]) begin
      w.wdata_q[i] = 32'hA0A0_0000 + i;
      w.wstrb_q[i] = 4'hF;
    end

    start_item(w);
    finish_item(w);

    // Read back same burst
    r = axi_item::type_id::create("r");
    r.dir   = AXI_READ;
    r.id    = 4'h2;
    r.addr  = 32'h0000_0010;
    r.len   = 4'd3;
    r.size  = 3'd2;
    r.burst = AXI_BURST_INCR;

    start_item(r);
    finish_item(r);
  endtask
endclass

// ------------------------------------------------------------------
// Constrained-random main sequence. Bursts are kept in the legal
// address range; illegal stimulus lives in axi_err_seq.
// ------------------------------------------------------------------
class axi_rand_seq extends axi_base_seq;
  `uvm_object_utils(axi_rand_seq)
  rand int unsigned n_ops = 400;

  function new(string name="axi_rand_seq"); super.new(name); endfunction

  task body();
    axi_item tr;
    repeat (n_ops) begin
      tr = axi_item::type_id::create("tr");
      if (!tr.randomize() with {
        dir dist {AXI_WRITE:=50, AXI_READ:=50};
        size inside {0,1,2};
        burst inside {AXI_BURST_FIXED, AXI_BURST_INCR, AXI_BURST_WRAP};
        len inside {[0:15]};
        addr[31:8] == '0;
        // stay inside the 128-byte memory for every beat of the burst
        if (burst == AXI_BURST_FIXED)
          addr + (32'd1 << size) <= 128;
        if (burst == AXI_BURST_INCR)
          addr + ((int'(len)+1) * (32'd1 << size)) <= 128;
        if (burst == AXI_BURST_WRAP)
          (addr - (addr % ((int'(len)+1) * (32'd1 << size))))
            + ((int'(len)+1) * (32'd1 << size)) <= 128;
        id inside {[0:15]};
        foreach (wstrb_q[i]) wstrb_q[i] inside {[0:15]};
      })
        `uvm_fatal("RANDFAIL", "axi_rand_seq: randomize() failed")

      // Fill write payload if needed
      if (tr.dir == AXI_WRITE) begin
        foreach (tr.wdata_q[i]) tr.wdata_q[i] = $urandom();
      end

      start_item(tr);
      finish_item(tr);
    end
  endtask
endclass

// ------------------------------------------------------------------
// Back-to-back traffic: zero-idle write/read pairs sweeping addresses.
// ------------------------------------------------------------------
class axi_b2b_seq extends axi_base_seq;
  `uvm_object_utils(axi_b2b_seq)
  int unsigned n_pairs = 12;

  function new(string name="axi_b2b_seq"); super.new(name); endfunction

  task body();
    axi_directed_seq s;
    for (int unsigned k = 0; k < n_pairs; k++) begin
      s = axi_directed_seq::type_id::create($sformatf("b2b_wr%0d", k));
      s.dir = AXI_WRITE; s.id = 4'(k); s.addr = (k * 8) % 120;
      s.len = 4'd1; s.size = 3'd2; s.base_data = 32'hB2B0_0000 + (k << 8);
      s.start(m_sequencer);

      s = axi_directed_seq::type_id::create($sformatf("b2b_rd%0d", k));
      s.dir = AXI_READ; s.id = 4'(k); s.addr = (k * 8) % 120;
      s.len = 4'd1; s.size = 3'd2;
      s.start(m_sequencer);
    end
  endtask
endclass

// ------------------------------------------------------------------
// Directed error injection: every case must complete with DECERR.
// Cases 5 and 6 are the ones that expose RTL Bug #1 (stale error
// flag read in the same clock it is set): the DUT answers OKAY on
// the first illegal beat. See README "Bugs found".
// ------------------------------------------------------------------
class axi_err_seq extends axi_base_seq;
  `uvm_object_utils(axi_err_seq)
  function new(string name="axi_err_seq"); super.new(name); endfunction

  task body();
    axi_directed_seq s;

    // 1) Read entirely out of range -> DECERR from beat 0
    s = axi_directed_seq::type_id::create("err_rd_oob");
    s.dir = AXI_READ; s.addr = 32'h0000_0200; s.len = 0; s.size = 2;
    s.start(m_sequencer);

    // 2) Write entirely out of range -> DECERR
    s = axi_directed_seq::type_id::create("err_wr_oob");
    s.dir = AXI_WRITE; s.addr = 32'h0000_0200; s.len = 0; s.size = 2;
    s.start(m_sequencer);

    // 3) Illegal SIZE (8 bytes/beat unsupported) -> DECERR
    s = axi_directed_seq::type_id::create("err_rd_size");
    s.dir = AXI_READ; s.addr = 32'h0; s.len = 1; s.size = 3'd5;
    s.start(m_sequencer);

    // 4) Reserved burst type 2'b11 -> DECERR
    s = axi_directed_seq::type_id::create("err_wr_burst");
    s.dir = AXI_WRITE; s.addr = 32'h0; s.len = 1; s.size = 2;
    s.burst = axi_burst_e'(2'b11);
    s.start(m_sequencer);

    // 5) Read burst that runs off the end of memory:
    //    beats at 0x78,0x7C,0x80,0x84 - beat 2 is the first illegal one.
    //    Expect DECERR from beat 2; buggy RTL answers OKAY there. (Bug #1)
    s = axi_directed_seq::type_id::create("err_rd_cross");
    s.dir = AXI_READ; s.addr = 32'h0000_0078; s.len = 3; s.size = 2;
    s.start(m_sequencer);

    // 6) Write burst whose FINAL beat is the first illegal one:
    //    beats at 0x74,0x78,0x7C,0x80. Expect BRESP=DECERR; buggy RTL
    //    reads the stale error flag and answers OKAY. (Bug #1, write side)
    s = axi_directed_seq::type_id::create("err_wr_lastbeat");
    s.dir = AXI_WRITE; s.addr = 32'h0000_0074; s.len = 3; s.size = 2;
    s.start(m_sequencer);
  endtask
endclass

// ------------------------------------------------------------------
// WID corruption: burst errors with DECERR, so per spec its data must
// not be committed - the readback shows the DUT wrote it anyway. (Bug #3)
// ------------------------------------------------------------------
class axi_wid_seq extends axi_base_seq;
  `uvm_object_utils(axi_wid_seq)
  function new(string name="axi_wid_seq"); super.new(name); endfunction

  task body();
    axi_directed_seq s;

    s = axi_directed_seq::type_id::create("wid_wr");
    s.dir = AXI_WRITE; s.addr = 32'h0000_0040; s.len = 3; s.size = 2;
    s.base_data = 32'hC1D0_0000;
    s.corrupt_wid = 1;
    s.start(m_sequencer);

    // Reference model (correctly) discarded the errored burst; the DUT
    // committed it. This readback flags RDATA mismatches on every beat.
    s = axi_directed_seq::type_id::create("wid_rd");
    s.dir = AXI_READ; s.addr = 32'h0000_0040; s.len = 3; s.size = 2;
    s.start(m_sequencer);
  endtask
endclass

// ------------------------------------------------------------------
// Early WLAST: master terminates the burst one beat early. The DUT's
// write FSM keeps waiting for the full beat count and never sends B,
// hanging the bus. (Bug #2 - the test's watchdog turns the hang into
// a reported failure.)
// ------------------------------------------------------------------
class axi_early_wlast_seq extends axi_base_seq;
  `uvm_object_utils(axi_early_wlast_seq)
  function new(string name="axi_early_wlast_seq"); super.new(name); endfunction

  task body();
    axi_directed_seq s;
    s = axi_directed_seq::type_id::create("early_wlast_wr");
    s.dir = AXI_WRITE; s.addr = 32'h0000_0020; s.len = 3; s.size = 2;
    s.base_data = 32'hEE00_0000;
    s.early_wlast = 1;
    s.start(m_sequencer);
  endtask
endclass
