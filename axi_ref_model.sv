class axi_ref_model extends uvm_object;
  `uvm_object_utils(axi_ref_model)

  byte unsigned ref_mem[];

  int unsigned mem_bytes;

  function new(string name="axi_ref_model");
    super.new(name);
  endfunction

  function void init(int unsigned bytes);
    mem_bytes = bytes;
    ref_mem = new[mem_bytes];
    foreach (ref_mem[i]) ref_mem[i] = 8'h0C;
  endfunction

  function int unsigned bytes_per_beat(bit [2:0] size);
    case (size)
      3'd0: return 1;
      3'd1: return 2;
      default: return 4;
    endcase
  endfunction

  function bit size_ok(bit [2:0] size);
    return (size==0)||(size==1)||(size==2);
  endfunction

  function bit burst_ok(axi_burst_e burst);
    return (burst inside {AXI_BURST_FIXED, AXI_BURST_INCR, AXI_BURST_WRAP});
  endfunction

  function bit addr_ok(bit [31:0] addr, int unsigned nbytes);
    if (addr >= mem_bytes) return 0;
    if ((addr + nbytes - 1) >= mem_bytes) return 0;
    return 1;
  endfunction

  function bit [31:0] wrap_base(bit [31:0] start_addr, int unsigned boundary_bytes);
    return start_addr - (start_addr % boundary_bytes);
  endfunction

  function bit [31:0] next_addr(bit [31:0] curr, bit [31:0] start,
                                axi_burst_e burst,
                                int unsigned boundary_bytes,
                                int unsigned beat_bytes);
    bit [31:0] base;
    case (burst)
      AXI_BURST_FIXED: return curr;
      AXI_BURST_INCR : return curr + beat_bytes;
      AXI_BURST_WRAP : begin
        base = wrap_base(start, boundary_bytes);
        bit [31:0] nxt = curr + beat_bytes;
        if ((nxt - base) >= boundary_bytes) nxt = nxt - boundary_bytes;
        return nxt;
      end
      default: return curr;
    endcase
  endfunction

  function bit [31:0] read_word(bit [31:0] addr, bit [2:0] size);
    bit [31:0] tmp = 32'h0;
    case (size)
      3'd0: tmp[7:0] = ref_mem[addr];
      3'd1: begin
        tmp[7:0]  = ref_mem[addr];
        tmp[15:8] = ref_mem[addr+1];
      end
      default: begin
        tmp[7:0]   = ref_mem[addr];
        tmp[15:8]  = ref_mem[addr+1];
        tmp[23:16] = ref_mem[addr+2];
        tmp[31:24] = ref_mem[addr+3];
      end
    endcase
    return tmp;
  endfunction

  function void write_word(bit [31:0] addr, bit [2:0] size, bit [31:0] data, bit [3:0] strb);
    int unsigned nbytes = bytes_per_beat(size);
    if (nbytes >= 1 && strb[0]) ref_mem[addr+0] = data[7:0];
    if (nbytes >= 2 && strb[1]) ref_mem[addr+1] = data[15:8];
    if (nbytes >= 3 && strb[2]) ref_mem[addr+2] = data[23:16];
    if (nbytes >= 4 && strb[3]) ref_mem[addr+3] = data[31:24];
  endfunction

endclass