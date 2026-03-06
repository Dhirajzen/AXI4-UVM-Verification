class axi_monitor extends uvm_component;
  `uvm_component_utils(axi_monitor)

  virtual axi_if.monitor_mp vif;
  uvm_analysis_port #(axi_item) ap;

  bit          wr_inflight, rd_inflight;
  axi_item     wr_tr, rd_tr;
  int unsigned wr_beats, rd_beats;
  int unsigned wr_i, rd_i;

  function new(string name, uvm_component parent);
    super.new(name,parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi_if.monitor_mp)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "axi_monitor: no vif")
  endfunction

  task run_phase(uvm_phase phase);
    wr_inflight = 0; rd_inflight = 0;
    wr_i = 0; rd_i = 0;

    forever begin
      @(vif.mon_cb);
      if (!vif.mon_cb.resetn) begin
        wr_inflight = 0; rd_inflight = 0;
        wr_i = 0; rd_i = 0;
        continue;
      end

      // AW accept
      if (vif.mon_cb.awvalid && vif.mon_cb.awready) begin
        wr_tr = axi_item::type_id::create("wr_tr");
        wr_tr.dir   = AXI_WRITE;
        wr_tr.id    = vif.mon_cb.awid;
        wr_tr.addr  = vif.mon_cb.awaddr;
        wr_tr.len   = vif.mon_cb.awlen;
        wr_tr.size  = vif.mon_cb.awsize;
        wr_tr.burst = axi_burst_e'(vif.mon_cb.awburst);

        wr_beats = int'(wr_tr.len) + 1;
        wr_tr.wdata_q = new[wr_beats];
        wr_tr.wstrb_q = new[wr_beats];
        wr_tr.wlast_mismatch = 0;

        wr_inflight = 1;
        wr_i = 0;
      end

      // W accept
      if (wr_inflight && (vif.mon_cb.wvalid && vif.mon_cb.wready)) begin
        if (wr_i < wr_beats) begin
          wr_tr.wdata_q[wr_i] = vif.mon_cb.wdata;
          wr_tr.wstrb_q[wr_i] = vif.mon_cb.wstrb;

          // Check WLAST position vs expected
          bit last_expected = (wr_i == wr_beats-1);
          if (vif.mon_cb.wlast !== last_expected) wr_tr.wlast_mismatch = 1;

          wr_i++;
        end else begin
          // extra beats beyond LEN+1
          wr_tr.wlast_mismatch = 1;
        end
      end

      // B accept
      if (vif.mon_cb.bvalid && vif.mon_cb.bready) begin
        if (wr_inflight) begin
          wr_tr.got_bid   = vif.mon_cb.bid;
          wr_tr.got_bresp = vif.mon_cb.bresp;
          ap.write(wr_tr);
          wr_inflight = 0;
        end
      end

      // AR accept
      if (vif.mon_cb.arvalid && vif.mon_cb.arready) begin
        rd_tr = axi_item::type_id::create("rd_tr");
        rd_tr.dir   = AXI_READ;
        rd_tr.id    = vif.mon_cb.arid;
        rd_tr.addr  = vif.mon_cb.araddr;
        rd_tr.len   = vif.mon_cb.arlen;
        rd_tr.size  = vif.mon_cb.arsize;
        rd_tr.burst = axi_burst_e'(vif.mon_cb.arburst);

        rd_beats = int'(rd_tr.len) + 1;
        rd_tr.got_rid_q.delete();
        rd_tr.got_rdata_q.delete();
        rd_tr.got_rresp_q.delete();
        rd_tr.got_rlast_q.delete();

        rd_inflight = 1;
        rd_i = 0;
      end

      // R accept
      if (rd_inflight && (vif.mon_cb.rvalid && vif.mon_cb.rready)) begin
        rd_tr.got_rid_q.push_back(vif.mon_cb.rid);
        rd_tr.got_rdata_q.push_back(vif.mon_cb.rdata);
        rd_tr.got_rresp_q.push_back(vif.mon_cb.rresp);
        rd_tr.got_rlast_q.push_back(vif.mon_cb.rlast);
        rd_i++;

        if (vif.mon_cb.rlast || (rd_i >= rd_beats)) begin
          ap.write(rd_tr);
          rd_inflight = 0;
        end
      end

    end
  endtask

endclass