module axi_slave #(
  parameter int MEM_BYTES = 128
)(
  input  logic        clk,
  input  logic        resetn,

  // ---------------- Write Address (AW) ----------------
  input  logic        awvalid,
  output logic        awready,
  input  logic [3:0]  awid,
  input  logic [3:0]  awlen,     // beats = awlen + 1  (here max 16)
  input  logic [2:0]  awsize,    // bytes/beat = 2^awsize (support 0/1/2)
  input  logic [31:0] awaddr,
  input  logic [1:0]  awburst,   // 00 FIXED, 01 INCR, 10 WRAP

  // ---------------- Write Data (W) ----------------
  input  logic        wvalid,
  output logic        wready,
  input  logic [3:0]  wid,       // AXI3-only; optional check vs awid
  input  logic [31:0] wdata,
  input  logic [3:0]  wstrb,
  input  logic        wlast,

  // ---------------- Write Response (B) ----------------
  input  logic        bready,
  output logic        bvalid,
  output logic [3:0]  bid,
  output logic [1:0]  bresp,     // 00 OKAY, 11 DECERR

  // ---------------- Read Address (AR) ----------------
  output logic        arready,
  input  logic [3:0]  arid,
  input  logic [31:0] araddr,
  input  logic [3:0]  arlen,     // beats = arlen + 1
  input  logic [2:0]  arsize,    // support 0/1/2
  input  logic [1:0]  arburst,   // 00 FIXED, 01 INCR, 10 WRAP
  input  logic        arvalid,

  // ---------------- Read Data (R) ----------------
  output logic [3:0]  rid,
  output logic [31:0] rdata,
  output logic [1:0]  rresp,     // 00 OKAY, 11 DECERR
  output logic        rlast,
  output logic        rvalid,
  input  logic        rready
);

  // ------------------------------------------------------------
  // Memory (byte-addressable)
  // ------------------------------------------------------------
  logic [7:0] mem [0:MEM_BYTES-1];
  initial begin
    for (int i = 0; i < MEM_BYTES; i++) mem[i] = 8'h0C;
  end

  // ------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------
  localparam logic [1:0] OKAY   = 2'b00;
  localparam logic [1:0] DECERR = 2'b11;

  function automatic logic size_ok(input logic [2:0] size);
    return (size == 3'd0) || (size == 3'd1) || (size == 3'd2);
  endfunction

  function automatic int unsigned bytes_per_beat(input logic [2:0] size);
    case (size)
      3'd0: return 1;
      3'd1: return 2;
      default: return 4; // 3'd2
    endcase
  endfunction

  function automatic logic burst_ok(input logic [1:0] burst);
    return (burst == 2'b00) || (burst == 2'b01) || (burst == 2'b10);
  endfunction

  function automatic logic addr_ok(input logic [31:0] addr, input int unsigned nbytes);
    // check [addr .. addr+nbytes-1] within memory
    if (addr >= MEM_BYTES) return 1'b0;
    if ((addr + nbytes - 1) >= MEM_BYTES) return 1'b0;
    return 1'b1;
  endfunction

  // AXI wrap: wrap boundary = (LEN+1)*bytes_per_beat, base aligned to boundary
  function automatic logic [31:0] wrap_next_addr(
    input logic [31:0] curr_addr,
    input logic [31:0] start_addr,
    input int unsigned boundary_bytes,
    input int unsigned beat_bytes
  );
    logic [31:0] base;
    logic [31:0] next;
    base = start_addr - (start_addr % boundary_bytes);
    next = curr_addr + beat_bytes;
    if ((next - base) >= boundary_bytes) next = next - boundary_bytes;
    return next;
  endfunction

  function automatic logic [31:0] next_addr(
    input logic [31:0] curr_addr,
    input logic [31:0] start_addr,
    input logic [1:0]  burst,
    input int unsigned boundary_bytes,
    input int unsigned beat_bytes
  );
    case (burst)
      2'b00: return curr_addr;                       // FIXED
      2'b01: return curr_addr + beat_bytes;          // INCR
      2'b10: return wrap_next_addr(curr_addr, start_addr, boundary_bytes, beat_bytes); // WRAP
      default: return curr_addr;
    endcase
  endfunction

  // Read 1/2/4 bytes into 32-bit word (little-endian)
  function automatic logic [31:0] mem_read(
    input logic [31:0] addr,
    input logic [2:0]  size
  );
    logic [31:0] tmp;
    tmp = 32'h0;
    case (size)
      3'd0: tmp[7:0] = mem[addr];
      3'd1: begin
        tmp[7:0]  = mem[addr];
        tmp[15:8] = mem[addr + 1];
      end
      default: begin // 3'd2
        tmp[7:0]   = mem[addr];
        tmp[15:8]  = mem[addr + 1];
        tmp[23:16] = mem[addr + 2];
        tmp[31:24] = mem[addr + 3];
      end
    endcase
    return tmp;
  endfunction

  // Write bytes with WSTRB (little-endian lanes)
  task automatic mem_write(
    input logic [31:0] addr,
    input logic [2:0]  size,
    input logic [31:0] data,
    input logic [3:0]  strb
  );
    int unsigned nbytes;
    nbytes = bytes_per_beat(size);

    // Honor WSTRB, but don't write beyond beat width
    if (nbytes >= 1 && strb[0] && (addr + 0) < MEM_BYTES) mem[addr + 0] <= data[7:0];
    if (nbytes >= 2 && strb[1] && (addr + 1) < MEM_BYTES) mem[addr + 1] <= data[15:8];
    if (nbytes >= 3 && strb[2] && (addr + 2) < MEM_BYTES) mem[addr + 2] <= data[23:16];
    if (nbytes >= 4 && strb[3] && (addr + 3) < MEM_BYTES) mem[addr + 3] <= data[31:24];
  endtask

  // ============================================================
  // WRITE PATH (AW/W/B) — single outstanding write burst
  // ============================================================
  typedef enum logic [1:0] {WR_IDLE, WR_DATA, WR_RESP} wr_state_e;
  wr_state_e wr_state;

  logic [31:0] wr_addr, wr_start_addr;
  logic [3:0]  wr_id, wr_len;
  logic [2:0]  wr_size;
  logic [1:0]  wr_burst;
  logic [4:0]  wr_beat_cnt;       // 0..15
  logic [4:0]  wr_beats_total;    // len+1
  logic        wr_err;

  // ready signals derived from state (no glitchy combinational feedback loops)
  assign awready = (wr_state == WR_IDLE);
  assign wready  = (wr_state == WR_DATA);

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      wr_state      <= WR_IDLE;
      wr_addr       <= '0;
      wr_start_addr <= '0;
      wr_id         <= '0;
      wr_len        <= '0;
      wr_size       <= '0;
      wr_burst      <= '0;
      wr_beat_cnt   <= '0;
      wr_beats_total<= '0;
      wr_err        <= 1'b0;

      bvalid        <= 1'b0;
      bid           <= '0;
      bresp         <= OKAY;
    end else begin
      // Consume write response
      if (bvalid && bready) bvalid <= 1'b0;

      // Accept AW only on handshake
      if (awvalid && awready) begin
        wr_id          <= awid;
        wr_len         <= awlen;
        wr_size        <= awsize;
        wr_burst       <= awburst;
        wr_addr        <= awaddr;
        wr_start_addr  <= awaddr;
        wr_beat_cnt    <= 0;
        wr_beats_total <= {1'b0, awlen} + 5'd1;

        // pre-check supported + first beat range
        wr_err <= !(size_ok(awsize) && burst_ok(awburst) &&
                    addr_ok(awaddr, bytes_per_beat(awsize)));

        wr_state <= WR_DATA;
      end

      // Accept W beats only on handshake
      if (wvalid && wready) begin
        int unsigned beat_bytes;
        int unsigned boundary_bytes;
        logic        last_expected;

        beat_bytes     = bytes_per_beat(wr_size);
        boundary_bytes = (wr_beats_total * beat_bytes);
        last_expected  = (wr_beat_cnt == (wr_beats_total - 1));

        // Optional: if you want, treat WID mismatch as error (since you have WID)
        if (wid !== wr_id) wr_err <= 1'b1;

        // Range/support check per beat
        if (!(size_ok(wr_size) && burst_ok(wr_burst) && addr_ok(wr_addr, beat_bytes)))
          wr_err <= 1'b1;
        else
          mem_write(wr_addr, wr_size, wdata, wstrb);

        // WLAST must match last beat (great DV corner-case)
        if (wlast !== last_expected) wr_err <= 1'b1;

        // If this was the last beat (by counter), move to response
        if (last_expected) begin
          bvalid   <= 1'b1;
          bid      <= wr_id;
          bresp    <= (wr_err) ? DECERR : OKAY;
          wr_state <= WR_RESP;
        end else begin
          // advance for next beat
          wr_beat_cnt <= wr_beat_cnt + 1;
          wr_addr     <= next_addr(wr_addr, wr_start_addr, wr_burst, boundary_bytes, beat_bytes);
        end
      end

      // Wait for B channel handshake to finish write transaction
      if (wr_state == WR_RESP) begin
        if (bvalid && bready) begin
          wr_state <= WR_IDLE;
        end
      end
    end
  end

  // ============================================================
  // READ PATH (AR/R) — single outstanding read burst
  // ============================================================
  typedef enum logic [1:0] {RD_IDLE, RD_SEND} rd_state_e;
  rd_state_e rd_state;

  logic [31:0] rd_addr, rd_start_addr;
  logic [3:0]  rd_id, rd_len;
  logic [2:0]  rd_size;
  logic [1:0]  rd_burst;
  logic [4:0]  rd_beat_cnt;
  logic [4:0]  rd_beats_total;
  logic        rd_err;

  assign arready = (rd_state == RD_IDLE);

  always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      rd_state      <= RD_IDLE;
      rd_addr       <= '0;
      rd_start_addr <= '0;
      rd_id         <= '0;
      rd_len        <= '0;
      rd_size       <= '0;
      rd_burst      <= '0;
      rd_beat_cnt   <= '0;
      rd_beats_total<= '0;
      rd_err        <= 1'b0;

      rvalid        <= 1'b0;
      rid           <= '0;
      rdata         <= '0;
      rresp         <= OKAY;
      rlast         <= 1'b0;
    end else begin
      // Accept AR only on handshake
      if (arvalid && arready) begin
        int unsigned beat_bytes;

        rd_id          <= arid;
        rd_len         <= arlen;
        rd_size        <= arsize;
        rd_burst       <= arburst;
        rd_addr        <= araddr;
        rd_start_addr  <= araddr;
        rd_beat_cnt    <= 0;
        rd_beats_total <= {1'b0, arlen} + 5'd1;

        beat_bytes = bytes_per_beat(arsize);
        rd_err <= !(size_ok(arsize) && burst_ok(arburst) &&
                    addr_ok(araddr, beat_bytes));

        // Drive first beat immediately and HOLD until accepted
        rid   <= arid;
        rresp <= (size_ok(arsize) && burst_ok(arburst) && addr_ok(araddr, beat_bytes)) ? OKAY : DECERR;
        rdata <= (size_ok(arsize) && burst_ok(arburst) && addr_ok(araddr, beat_bytes)) ? mem_read(araddr, arsize) : 32'h0;
        rlast <= (arlen == 0);
        rvalid<= 1'b1;

        rd_state <= RD_SEND;
      end

      // Hold rvalid/rdata stable until rready; advance only on handshake
      if (rd_state == RD_SEND) begin
        if (rvalid && rready) begin
          int unsigned beat_bytes;
          int unsigned boundary_bytes;
          logic [31:0] na;

          beat_bytes     = bytes_per_beat(rd_size);
          boundary_bytes = (rd_beats_total * beat_bytes);

          // If last beat just transferred, finish
          if (rd_beat_cnt == (rd_beats_total - 1)) begin
            rvalid   <= 1'b0;
            rlast    <= 1'b0;
            rd_state <= RD_IDLE;
          end else begin
            // compute next address and prepare next beat
            na = next_addr(rd_addr, rd_start_addr, rd_burst, boundary_bytes, beat_bytes);

            rd_beat_cnt <= rd_beat_cnt + 1;
            rd_addr     <= na;

            if (!(size_ok(rd_size) && burst_ok(rd_burst) && addr_ok(na, beat_bytes)))
              rd_err <= 1'b1;

            rid   <= rd_id;
            rresp <= (rd_err) ? DECERR : OKAY;
            rdata <= (!rd_err && addr_ok(na, beat_bytes)) ? mem_read(na, rd_size) : 32'h0;
            rlast <= ((rd_beat_cnt + 1) == (rd_beats_total - 1));
            rvalid<= 1'b1;
          end
        end
      end
    end
  end

endmodule