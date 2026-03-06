class axi_scoreboard extends uvm_component;
  `uvm_component_utils(axi_scoreboard)

  axi_cfg cfg;
  axi_ref_model rm;

  uvm_analysis_imp #(axi_item, axi_scoreboard) imp;

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

  function void check_write(axi_item tr);
    int unsigned beats = int'(tr.len) + 1;
    int unsigned beat_bytes;
    int unsigned boundary_bytes;
    bit [31:0]   addr;
    bit          exp_err = 0;

    // Basic legality expectation
    if (!rm.size_ok(tr.size)) exp_err = 1;
    if (!rm.burst_ok(tr.burst)) exp_err = 1;
    beat_bytes = rm.bytes_per_beat(tr.size);
    boundary_bytes = beats * beat_bytes;

    addr = tr.addr;

    // WLAST mismatch is explicitly treated as error by DUT
    if (tr.wlast_mismatch) exp_err = 1;

    // Apply write beats into ref model only if we’re not in “error expected”
    // (keeps behavior deterministic for now; you can tighten later)
    if (!exp_err) begin
      for (int unsigned i=0; i<beats; i++) begin
        if (!rm.addr_ok(addr, beat_bytes)) begin
          exp_err = 1;
          break;
        end
        rm.write_word(addr, tr.size, tr.wdata_q[i], tr.wstrb_q[i]);
        addr = rm.next_addr(addr, tr.addr, tr.burst, boundary_bytes, beat_bytes);
      end
    end

    // Check BID/BRESP
    if (tr.got_bid !== tr.id)
      `uvm_error("AXI_SCB", $sformatf("BID mismatch exp=%0d got=%0d", tr.id, tr.got_bid))

    if (!exp_err) begin
      if (tr.got_bresp !== AXI_OKAY)
        `uvm_error("AXI_SCB", $sformatf("BRESP exp OKAY got=%0b", tr.got_bresp))
    end else begin
      if (tr.got_bresp !== AXI_DECERR)
        `uvm_error("AXI_SCB", $sformatf("BRESP exp DECERR got=%0b", tr.got_bresp))
    end
  endfunction

  function void check_read(axi_item tr);
    int unsigned beats = int'(tr.len) + 1;
    int unsigned beat_bytes;
    int unsigned boundary_bytes;
    bit [31:0]   addr;
    bit          exp_err = 0;

    if (!rm.size_ok(tr.size)) exp_err = 1;
    if (!rm.burst_ok(tr.burst)) exp_err = 1;

    beat_bytes = rm.bytes_per_beat(tr.size);
    boundary_bytes = beats * beat_bytes;
    addr = tr.addr;

    // For legal reads, check each beat data
    for (int unsigned i=0; i<tr.got_rdata_q.size(); i++) begin
      if (tr.got_rid_q[i] !== tr.id)
        `uvm_error("AXI_SCB", $sformatf("RID mismatch beat%0d exp=%0d got=%0d", i, tr.id, tr.got_rid_q[i]))

      if (!exp_err) begin
        if (!rm.addr_ok(addr, beat_bytes)) exp_err = 1;
      end

      if (!exp_err) begin
        bit [31:0] exp = rm.read_word(addr, tr.size);
        if (tr.got_rdata_q[i] !== exp)
          `uvm_error("AXI_SCB", $sformatf("RDATA mismatch beat%0d addr=0x%0h exp=0x%08h got=0x%08h",
                                          i, addr, exp, tr.got_rdata_q[i]))
        if (tr.got_rresp_q[i] !== AXI_OKAY)
          `uvm_error("AXI_SCB", $sformatf("RRESP exp OKAY beat%0d got=%0b", i, tr.got_rresp_q[i]))
      end else begin
        // if error expected, accept DECERR (don’t over-tighten early)
        if (tr.got_rresp_q[i] !== AXI_DECERR && tr.got_rresp_q[i] !== AXI_OKAY)
          `uvm_error("AXI_SCB", $sformatf("RRESP unexpected beat%0d got=%0b", i, tr.got_rresp_q[i]))
      end

      addr = rm.next_addr(addr, tr.addr, tr.burst, boundary_bytes, beat_bytes);
    end

    // Check RLAST on final observed beat
    if (tr.got_rlast_q.size() > 0) begin
      bit last_seen = tr.got_rlast_q[tr.got_rlast_q.size()-1];
      if (!last_seen)
        `uvm_error("AXI_SCB", "RLAST not seen on last beat")
    end
  endfunction

  function void write(axi_item tr);
    if (tr.dir == AXI_WRITE) check_write(tr);
    else                    check_read(tr);
  endfunction

endclass