class axi_driver extends uvm_driver #(axi_item);
  `uvm_component_utils(axi_driver)

  virtual axi_if vif;
  axi_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name,parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "axi_driver: no vif")

    if (!uvm_config_db#(axi_cfg)::get(this, "", "cfg", cfg))
      cfg = axi_cfg::type_id::create("cfg");
  endfunction

  task run_phase(uvm_phase phase);
    axi_item tr;
    fork
      drive_ready_policy();
    join_none

    // init drives
    vif.drv_cb.awvalid <= 0;
    vif.drv_cb.wvalid  <= 0;
    vif.drv_cb.arvalid <= 0;
    vif.drv_cb.bready  <= 0;
    vif.drv_cb.rready  <= 0;
    @(vif.drv_cb);

    forever begin
      seq_item_port.get_next_item(tr);
      if (tr.dir == AXI_WRITE) begin
        drive_write(tr);
      end else begin
        drive_read(tr);
      end
      seq_item_port.item_done();
    end
  endtask

  // -------------------------
  // Ready policy control
  // -------------------------
  task drive_ready_policy();
    // Master controls bready and rready
    // Policy applies continuously; transaction tasks wait for handshakes.
    int unsigned stall_cycles;
    forever begin
      @(vif.drv_cb);
      if (!vif.drv_cb.resetn) begin
        vif.drv_cb.bready <= 0;
        vif.drv_cb.rready <= 0;
        continue;
      end

      case (cfg.ready_policy)
        READY_ALWAYS: begin
          vif.drv_cb.bready <= 1;
          vif.drv_cb.rready <= 1;
        end

        READY_RANDOM: begin
          vif.drv_cb.bready <= $urandom_range(0,1);
          vif.drv_cb.rready <= $urandom_range(0,1);
        end

        READY_BURSTY: begin
          // hold ready high for a bit, then stall for random cycles
          vif.drv_cb.bready <= 1;
          vif.drv_cb.rready <= 1;
          if ($urandom_range(0,9) == 0) begin
            stall_cycles = (cfg.stall_max > cfg.stall_min) ?
                           $urandom_range(cfg.stall_min, cfg.stall_max) : cfg.stall_min;
            repeat (stall_cycles) begin
              @(vif.drv_cb);
              vif.drv_cb.bready <= 0;
              vif.drv_cb.rready <= 0;
            end
          end
        end
      endcase
    end
  endtask

  // -------------------------
  // Write transaction
  // -------------------------
 task drive_write(axi_item tr);
  int unsigned beats;
  beats = tr.beats_total();

  // Drive AW
  vif.drv_cb.awid    <= tr.id;
  vif.drv_cb.awaddr  <= tr.addr;
  vif.drv_cb.awlen   <= tr.len;
  vif.drv_cb.awsize  <= tr.size;
  vif.drv_cb.awburst <= tr.burst;
  vif.drv_cb.awvalid <= 1;

  // Wait for AW handshake on posedge (raw signals)
  do @(posedge vif.clk); while (!(vif.resetn && vif.awvalid && vif.awready));
  vif.drv_cb.awvalid <= 0;

  // Drive W beats
  for (int unsigned i=0; i<beats; i++) begin
    bit last;
    last = (i == beats-1);

    vif.drv_cb.wid    <= tr.id;
    vif.drv_cb.wdata  <= tr.wdata_q[i];
    vif.drv_cb.wstrb  <= tr.wstrb_q[i];
    vif.drv_cb.wlast  <= last;
    vif.drv_cb.wvalid <= 1;

    do @(posedge vif.clk); while (!(vif.resetn && vif.wvalid && vif.wready));
    vif.drv_cb.wvalid <= 0;
  end

  // Wait for B handshake
  do @(posedge vif.clk); while (!(vif.resetn && vif.bvalid && vif.bready));
  tr.got_bid   = vif.bid;
  tr.got_bresp = vif.bresp;
endtask

  // -------------------------
  // Read transaction
  // -------------------------
  task drive_read(axi_item tr);
    int unsigned beats;
    beats = tr.beats_total();

    // AR handshake
    vif.drv_cb.arid    <= tr.id;
    vif.drv_cb.araddr  <= tr.addr;
    vif.drv_cb.arlen   <= tr.len;
    vif.drv_cb.arsize  <= tr.size;
    vif.drv_cb.arburst <= tr.burst;
    vif.drv_cb.arvalid <= 1;

    do @(vif.drv_cb); while (!vif.drv_cb.arready || !vif.drv_cb.resetn);
    vif.drv_cb.arvalid <= 0;

    // R beats (collect until RLAST seen on handshake)
    tr.got_rid_q.delete();
    tr.got_rdata_q.delete();
    tr.got_rresp_q.delete();
    tr.got_rlast_q.delete();

    for (int unsigned i=0; i<beats; i++) begin
      // wait handshake (rvalid && rready)
      do @(vif.drv_cb); while (!(vif.drv_cb.rvalid && vif.drv_cb.rready) || !vif.drv_cb.resetn);
      tr.got_rid_q.push_back(vif.drv_cb.rid);
      tr.got_rdata_q.push_back(vif.drv_cb.rdata);
      tr.got_rresp_q.push_back(vif.drv_cb.rresp);
      tr.got_rlast_q.push_back(vif.drv_cb.rlast);
      if (vif.drv_cb.rlast) break;
    end
  endtask

endclass