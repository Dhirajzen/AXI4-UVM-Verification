module axi4_ram_slave #(
    parameter int ID_WIDTH        = 4,
    parameter int ADDR_WIDTH      = 16,
    parameter int DATA_WIDTH      = 32,
    parameter int MEM_SIZE_BYTES  = 65536
) (
    input  logic                     aclk,
    input  logic                     aresetn,

    // Write address channel
    input  logic [ID_WIDTH-1:0]      s_axi_awid,
    input  logic [ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  logic [7:0]               s_axi_awlen,
    input  logic [2:0]               s_axi_awsize,
    input  logic [1:0]               s_axi_awburst,
    input  logic                     s_axi_awvalid,
    output logic                     s_axi_awready,

    // Write data channel
    input  logic [DATA_WIDTH-1:0]    s_axi_wdata,
    input  logic [DATA_WIDTH/8-1:0]  s_axi_wstrb,
    input  logic                     s_axi_wlast,
    input  logic                     s_axi_wvalid,
    output logic                     s_axi_wready,

    // Write response channel
    output logic [ID_WIDTH-1:0]      s_axi_bid,
    output logic [1:0]               s_axi_bresp,
    output logic                     s_axi_bvalid,
    input  logic                     s_axi_bready,

    // Read address channel
    input  logic [ID_WIDTH-1:0]      s_axi_arid,
    input  logic [ADDR_WIDTH-1:0]    s_axi_araddr,
    input  logic [7:0]               s_axi_arlen,
    input  logic [2:0]               s_axi_arsize,
    input  logic [1:0]               s_axi_arburst,
    input  logic                     s_axi_arvalid,
    output logic                     s_axi_arready,

    // Read data channel
    output logic [ID_WIDTH-1:0]      s_axi_rid,
    output logic [DATA_WIDTH-1:0]    s_axi_rdata,
    output logic [1:0]               s_axi_rresp,
    output logic                     s_axi_rlast,
    output logic                     s_axi_rvalid,
    input  logic                     s_axi_rready
);
    localparam int BYTE_LANES = DATA_WIDTH / 8;

    typedef enum logic [1:0] {
        AXI_BURST_FIXED = 2'b00,
        AXI_BURST_INCR  = 2'b01,
        AXI_BURST_WRAP  = 2'b10
    } axi_burst_t;

    logic [7:0] mem [0:MEM_SIZE_BYTES-1];

    logic [ID_WIDTH-1:0]   w_id_q;
    logic [ADDR_WIDTH-1:0] w_addr_q;
    logic [7:0]            w_beats_left_q;
    logic [2:0]            w_size_q;
    logic [1:0]            w_burst_q;
    logic                  w_active_q;
    logic                  w_error_q;

    logic [ID_WIDTH-1:0]   r_id_q;
    logic [ADDR_WIDTH-1:0] r_addr_q;
    logic [7:0]            r_beats_left_q;
    logic [2:0]            r_size_q;
    logic [1:0]            r_burst_q;
    logic                  r_active_q;
    logic                  r_error_q;

    function automatic [ADDR_WIDTH-1:0] burst_next_addr(
        input [ADDR_WIDTH-1:0] curr,
        input [2:0]            size,
        input [1:0]            burst
    );
        burst_next_addr = curr;
        case (burst)
            AXI_BURST_FIXED: burst_next_addr = curr;
            AXI_BURST_INCR:  burst_next_addr = curr + (1 << size);
            default:         burst_next_addr = curr;
        endcase
    endfunction

    function automatic logic addr_in_range(input [ADDR_WIDTH-1:0] addr);
        addr_in_range = (addr < MEM_SIZE_BYTES);
    endfunction

    function automatic [DATA_WIDTH-1:0] read_word(input [ADDR_WIDTH-1:0] addr);
        int i;
        read_word = '0;
        for (i = 0; i < BYTE_LANES; i++) begin
            if (addr_in_range(addr + i)) begin
                read_word[i*8 +: 8] = mem[addr + i];
            end
        end
    endfunction

    assign s_axi_awready = (!w_active_q) && (!s_axi_bvalid);
    assign s_axi_wready  = w_active_q && (!s_axi_bvalid);
    assign s_axi_arready = (!r_active_q) && (!s_axi_rvalid);

    always_ff @(posedge aclk or negedge aresetn) begin : axi_slave_seq
        int i;
        if (!aresetn) begin
            w_id_q          <= '0;
            w_addr_q        <= '0;
            w_beats_left_q  <= '0;
            w_size_q        <= '0;
            w_burst_q       <= AXI_BURST_FIXED;
            w_active_q      <= 1'b0;
            w_error_q       <= 1'b0;
            s_axi_bid       <= '0;
            s_axi_bresp     <= 2'b00;
            s_axi_bvalid    <= 1'b0;

            r_id_q          <= '0;
            r_addr_q        <= '0;
            r_beats_left_q  <= '0;
            r_size_q        <= '0;
            r_burst_q       <= AXI_BURST_FIXED;
            r_active_q      <= 1'b0;
            r_error_q       <= 1'b0;
            s_axi_rid       <= '0;
            s_axi_rdata     <= '0;
            s_axi_rresp     <= 2'b00;
            s_axi_rlast     <= 1'b0;
            s_axi_rvalid    <= 1'b0;

            for (i = 0; i < MEM_SIZE_BYTES; i++) begin
                mem[i] <= '0;
            end
        end else begin
            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (s_axi_awvalid && s_axi_awready) begin
                w_id_q         <= s_axi_awid;
                w_addr_q       <= s_axi_awaddr;
                w_beats_left_q <= s_axi_awlen + 8'd1;
                w_size_q       <= s_axi_awsize;
                w_burst_q      <= s_axi_awburst;
                w_active_q     <= 1'b1;
                w_error_q      <= (s_axi_awburst == AXI_BURST_WRAP);
            end

            if (s_axi_wvalid && s_axi_wready) begin
                logic expected_last;
                expected_last = (w_beats_left_q == 8'd1);

                for (i = 0; i < BYTE_LANES; i++) begin
                    if (s_axi_wstrb[i]) begin
                        if (addr_in_range(w_addr_q + i)) begin
                            mem[w_addr_q + i] <= s_axi_wdata[i*8 +: 8];
                        end else begin
                            w_error_q <= 1'b1;
                        end
                    end
                end

                if (s_axi_wlast != expected_last) begin
                    w_error_q <= 1'b1;
                end

                if (expected_last || s_axi_wlast) begin
                    w_active_q     <= 1'b0;
                    s_axi_bvalid   <= 1'b1;
                    s_axi_bid      <= w_id_q;
                    s_axi_bresp    <= w_error_q ? 2'b10 : 2'b00;
                end else begin
                    w_beats_left_q <= w_beats_left_q - 8'd1;
                    w_addr_q       <= burst_next_addr(w_addr_q, w_size_q, w_burst_q);
                end
            end

            if (s_axi_rvalid && s_axi_rready) begin
                if (r_beats_left_q == 8'd1) begin
                    s_axi_rvalid <= 1'b0;
                    s_axi_rlast  <= 1'b0;
                    r_active_q   <= 1'b0;
                end else begin
                    r_beats_left_q <= r_beats_left_q - 8'd1;
                    r_addr_q       <= burst_next_addr(r_addr_q, r_size_q, r_burst_q);
                    s_axi_rdata    <= read_word(burst_next_addr(r_addr_q, r_size_q, r_burst_q));
                    s_axi_rresp    <= r_error_q ? 2'b10 : 2'b00;
                    s_axi_rlast    <= (r_beats_left_q == 8'd2);
                end
            end

            if (s_axi_arvalid && s_axi_arready) begin
                r_id_q          <= s_axi_arid;
                r_addr_q        <= s_axi_araddr;
                r_beats_left_q  <= s_axi_arlen + 8'd1;
                r_size_q        <= s_axi_arsize;
                r_burst_q       <= s_axi_arburst;
                r_active_q      <= 1'b1;
                r_error_q       <= (s_axi_arburst == AXI_BURST_WRAP) || !addr_in_range(s_axi_araddr);

                s_axi_rid       <= s_axi_arid;
                s_axi_rdata     <= read_word(s_axi_araddr);
                s_axi_rresp     <= ((s_axi_arburst == AXI_BURST_WRAP) || !addr_in_range(s_axi_araddr)) ? 2'b10 : 2'b00;
                s_axi_rlast     <= (s_axi_arlen == 8'd0);
                s_axi_rvalid    <= 1'b1;
            end
        end
    end
endmodule
