class axi_coverage extends uvm_subscriber #(axi_item);
  `uvm_component_utils(axi_coverage)

  // Derived sample values (computed in write() before sampling)
  bit [1:0] wstrb_kind; // 0 = all lanes enabled, 1 = partial, 2 = some beat all-zero
  bit [1:0] resp_val;   // worst response seen in the transaction

  covergroup cg with function sample(axi_item t);
    option.per_instance = 1;

    dir_cp   : coverpoint t.dir;
    burst_cp : coverpoint t.burst;
    size_cp  : coverpoint t.size { bins legal[] = {0,1,2}; bins illegal = default; }

    // every burst length individually
    len_cp   : coverpoint t.len { bins len_b[] = {[0:15]}; }

    // coarse groups used for the cross (keeps the cross closable)
    len_grp_cp : coverpoint t.len {
      bins len_short = {[0:3]};
      bins len_mid   = {[4:7]};
      bins len_long  = {[8:15]};
    }

    // start-address alignment (byte lanes)
    align_cp : coverpoint t.addr[1:0];

    // write-strobe shapes (writes only)
    wstrb_cp : coverpoint wstrb_kind iff (t.dir == AXI_WRITE) {
      bins full_lanes = {0};
      bins partial    = {1};
      bins zero_beat  = {2};
    }

    // response coverage: did we see both OKAY and DECERR paths?
    resp_cp : coverpoint resp_val {
      bins okay   = {2'b00};
      bins decerr = {2'b11};
    }

    x_dbsl : cross dir_cp, burst_cp, size_cp, len_grp_cp;
  endgroup

  function new(string name, uvm_component parent);
    super.new(name,parent);
    cg = new();
  endfunction

  virtual function void write(axi_item t);
    // classify write strobes: worst case over all beats
    wstrb_kind = 2'd0;
    if (t.dir == AXI_WRITE) begin
      int unsigned nbytes;
      bit [3:0]    full_mask;
      nbytes    = t.bytes_per_beat();
      full_mask = 4'((1 << nbytes) - 1);
      foreach (t.wstrb_q[i]) begin
        if ((t.wstrb_q[i] & full_mask) == 4'h0)            wstrb_kind = 2'd2;
        else if (((t.wstrb_q[i] & full_mask) != full_mask)
                 && (wstrb_kind != 2'd2))                  wstrb_kind = 2'd1;
      end
      resp_val = t.got_bresp;
    end else begin
      resp_val = 2'b00;
      foreach (t.got_rresp_q[i])
        if (t.got_rresp_q[i] != 2'b00) resp_val = t.got_rresp_q[i];
    end

    cg.sample(t);
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("AXI_COV", $sformatf("Functional coverage (this run): %0.2f%%",
                                   cg.get_inst_coverage()), UVM_LOW)
  endfunction
endclass
