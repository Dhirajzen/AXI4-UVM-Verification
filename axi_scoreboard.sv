class axi_scoreboard extends uvm_component;
  `uvm_component_utils(axi_scoreboard)

  axi_cfg cfg;
  axi_ref_model rm;

  uvm_analysis_imp #(axi_item, axi_scoreboard) imp;

  int unsigned n_writes;
  int unsigned n_reads;

  function new(string name, uvm_component parent);
    super.new(name,parent);
    imp = new("imp", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(axi_cfg)::get(this, "", "cfg", cfg))
      cfg = axi_cfg::type_id::create("cfg");

    rm = axi_ref_model::type_id::create("rm");
    rm.init(128); // must match DUT MEM_BYTES
  endfunction

  // ------------------------------------------------------------------
  // WRITE: predict BRESP per spec and commit the burst to the reference
  // memory only when the whole burst is legal. A slave that errors a
  // burst must not silently commit its data (see axi_wid_test).
  // ------------------------------------------------------------------
  function void check_write(axi_item tr);
    int unsigned beats;
    int unsigned beat_bytes;
    int unsigned boundary_bytes;
    bit [31:0]   addr;
    bit          exp_err = 0;
    bit [1:0]    exp_bresp;

    n_writes++;

    beats          = tr.beats_total();
    beat_bytes     = rm.bytes_per_beat(tr.size);
    boundary_bytes = beats * beat_bytes;

    if (!rm.size_ok(tr.size))   exp_err = 1;
    if (!rm.burst_ok(tr.burst)) exp_err = 1;
    if (tr.wlast_mismatch)      exp_err = 1;
    if (tr.wid_mismatch)        exp_err = 1;

    // Scan every beat address for range violations
    if (!exp_err) begin
      addr = tr.addr;
      for (int unsigned i = 0; i < beats; i++) begin
        if (!rm.addr_ok(addr, beat_bytes)) exp_err = 1;
        addr = rm.next_addr(addr, tr.addr, tr.burst, boundary_bytes, beat_bytes);
      end
    end

    // Commit to reference memory only for a fully legal burst
    if (!exp_err) begin
      addr = tr.addr;
      for (int unsigned i = 0; i < beats; i++) begin
        rm.write_word(addr, tr.size, tr.wdata_q[i], tr.wstrb_q[i]);
        addr = rm.next_addr(addr, tr.addr, tr.burst, boundary_bytes, beat_bytes);
      end
    end

    if (tr.got_bid !== tr.id)
      `uvm_error("AXI_SCB", $sformatf("BID mismatch exp=%0d got=%0d", tr.id, tr.got_bid))

    exp_bresp = exp_err ? AXI_DECERR : AXI_OKAY;
    if (tr.got_bresp !== exp_bresp)
      `uvm_error("AXI_SCB", $sformatf(
        "BRESP mismatch exp=%s got=%0b (addr=0x%0h len=%0d size=%0d burst=%s wid_mm=%0b wlast_mm=%0b)",
        exp_err ? "DECERR" : "OKAY", tr.got_bresp,
        tr.addr, tr.len, tr.size, tr.burst.name(),
        tr.wid_mismatch, tr.wlast_mismatch))
  endfunction

  // ------------------------------------------------------------------
  // READ: exact per-beat checking. Expected RRESP is derived per beat
  // (error is sticky once any beat goes illegal, per this slave's spec),
  // RDATA is compared against the reference memory on every OKAY beat,
  // the beat count must be exactly LEN+1, and RLAST must be asserted on
  // the final beat only.
  // ------------------------------------------------------------------
  function void check_read(axi_item tr);
    int unsigned beats;
    int unsigned beat_bytes;
    int unsigned boundary_bytes;
    bit [31:0]   addr;
    bit          err_sticky;
    bit [1:0]    exp_rresp;

    n_reads++;

    beats          = tr.beats_total();
    beat_bytes     = rm.bytes_per_beat(tr.size);
    boundary_bytes = beats * beat_bytes;

    err_sticky = !rm.size_ok(tr.size) || !rm.burst_ok(tr.burst);

    if (tr.got_rdata_q.size() != beats)
      `uvm_error("AXI_SCB", $sformatf("Read beat count mismatch exp=%0d got=%0d (addr=0x%0h)",
                                      beats, tr.got_rdata_q.size(), tr.addr))

    addr = tr.addr;
    for (int unsigned i = 0; i < tr.got_rdata_q.size(); i++) begin
      if (tr.got_rid_q[i] !== tr.id)
        `uvm_error("AXI_SCB", $sformatf("RID mismatch beat%0d exp=%0d got=%0d", i, tr.id, tr.got_rid_q[i]))

      if (!rm.addr_ok(addr, beat_bytes)) err_sticky = 1;

      exp_rresp = err_sticky ? AXI_DECERR : AXI_OKAY;
      if (tr.got_rresp_q[i] !== exp_rresp)
        `uvm_error("AXI_SCB", $sformatf(
          "RRESP mismatch beat%0d exp=%s got=%0b (addr=0x%0h len=%0d size=%0d burst=%s)",
          i, err_sticky ? "DECERR" : "OKAY", tr.got_rresp_q[i],
          addr, tr.len, tr.size, tr.burst.name()))

      if (!err_sticky) begin
        bit [31:0] exp;
        exp = rm.read_word(addr, tr.size);
        if (tr.got_rdata_q[i] !== exp)
          `uvm_error("AXI_SCB", $sformatf("RDATA mismatch beat%0d addr=0x%0h exp=0x%08h got=0x%08h",
                                          i, addr, exp, tr.got_rdata_q[i]))
      end

      // RLAST on the final beat only
      begin
        bit exp_last;
        exp_last = (i == beats - 1);
        if (tr.got_rlast_q[i] !== exp_last)
          `uvm_error("AXI_SCB", $sformatf("RLAST mismatch beat%0d exp=%0b got=%0b",
                                          i, exp_last, tr.got_rlast_q[i]))
      end

      addr = rm.next_addr(addr, tr.addr, tr.burst, boundary_bytes, beat_bytes);
    end
  endfunction

  function void write(axi_item tr);
    if (tr.dir == AXI_WRITE) check_write(tr);
    else                    check_read(tr);
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("AXI_SCB", $sformatf("Scoreboard checked %0d writes and %0d reads",
                                   n_writes, n_reads), UVM_LOW)
    if ((n_writes + n_reads) == 0)
      `uvm_error("AXI_SCB", "No transactions observed - the test drove nothing; a silent pass is not a pass")
  endfunction

endclass
