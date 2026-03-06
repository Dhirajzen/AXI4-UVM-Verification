class axi_base_seq extends uvm_sequence #(axi_item);
  `uvm_object_utils(axi_base_seq)
  function new(string name="axi_base_seq"); super.new(name); endfunction
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

class axi_rand_seq extends axi_base_seq;
  `uvm_object_utils(axi_rand_seq)
  rand int unsigned n_ops = 200;

  function new(string name="axi_rand_seq"); super.new(name); endfunction

  task body();
    axi_item tr;
    repeat (n_ops) begin
      tr = axi_item::type_id::create("tr");
      assert(tr.randomize() with {
        dir dist {AXI_WRITE:=50, AXI_READ:=50};
        len inside {[0:7]}; // keep short for speed
        addr inside {[0:96]}; // avoid out-of-range for now
        size inside {0,1,2};
        burst inside {AXI_BURST_FIXED, AXI_BURST_INCR, AXI_BURST_WRAP};
        id inside {[0:15]};
        if (dir==AXI_WRITE) foreach (wstrb_q[i]) wstrb_q[i] inside {[0:15]};
      });

      // Fill write payload if needed
      if (tr.dir == AXI_WRITE) begin
        foreach (tr.wdata_q[i]) tr.wdata_q[i] = $urandom();
      end

      start_item(tr);
      finish_item(tr);
    end
  endtask
endclass