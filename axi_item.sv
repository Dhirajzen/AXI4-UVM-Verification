class axi_item extends uvm_sequence_item;
  rand axi_dir_e    dir;
  rand bit [3:0]    id;
  rand bit [31:0]   addr;
  rand bit [3:0]    len;     // beats = len+1 (max 16)
  rand bit [2:0]    size;    // 0/1/2 => 1/2/4 bytes
  rand axi_burst_e  burst;

  // Write payload (beats = len+1)
  rand bit [31:0]   wdata_q[];
  rand bit [3:0]    wstrb_q[];

  // Response / observed
  bit [3:0]  got_bid;
  bit [1:0]  got_bresp;

  bit [3:0]  got_rid_q[$];
  bit [31:0] got_rdata_q[$];
  bit [1:0]  got_rresp_q[$];
  bit        got_rlast_q[$];

  // Helpful flags
  bit        wlast_mismatch;

  `uvm_object_utils_begin(axi_item)
    `uvm_field_enum(axi_dir_e, dir, UVM_ALL_ON)
    `uvm_field_int(id,   UVM_ALL_ON)
    `uvm_field_int(addr, UVM_ALL_ON)
    `uvm_field_int(len,  UVM_ALL_ON)
    `uvm_field_int(size, UVM_ALL_ON)
    `uvm_field_enum(axi_burst_e, burst, UVM_ALL_ON)
    `uvm_field_array_int(wdata_q, UVM_ALL_ON)
    `uvm_field_array_int(wstrb_q, UVM_ALL_ON)
    `uvm_field_int(got_bid,   UVM_ALL_ON)
    `uvm_field_int(got_bresp, UVM_ALL_ON)
    `uvm_field_queue_int(got_rid_q,   UVM_ALL_ON)
    `uvm_field_queue_int(got_rdata_q, UVM_ALL_ON)
    `uvm_field_queue_int(got_rresp_q, UVM_ALL_ON)
    `uvm_field_queue_int(got_rlast_q, UVM_ALL_ON)
    `uvm_field_int(wlast_mismatch, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name="axi_item");
    super.new(name);
  endfunction

  function int unsigned beats_total();
    return int'(len) + 1;
  endfunction

  function int unsigned bytes_per_beat();
    case (size)
      3'd0: return 1;
      3'd1: return 2;
      default: return 4; // 3'd2
    endcase
  endfunction

  constraint c_legal_default {
    size inside {3'd0,3'd1,3'd2};
    burst inside {AXI_BURST_FIXED, AXI_BURST_INCR, AXI_BURST_WRAP};
  }

  constraint c_arrays {
    if (dir == AXI_WRITE) {
      wdata_q.size() == beats_total();
      wstrb_q.size() == beats_total();
    } else {
      wdata_q.size() == 0;
      wstrb_q.size() == 0;
    }
  }

endclass