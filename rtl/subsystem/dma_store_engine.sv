// File: rtl/subsystem/dma_store_engine.sv
`ifndef DMA_STORE_ENGINE_SV
`define DMA_STORE_ENGINE_SV

module dma_store_engine #(
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 64,
    parameter int AXI_ID_WIDTH = 4,

    parameter logic [AXI_ID_WIDTH-1:0] SPAD_ARID = '0,
    parameter logic [AXI_ID_WIDTH-1:0] DST_AWID  = '0
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // ------------------------------------------------------------
    // Simple control interface
    //
    // v1 behavior:
    //   - one store job at a time
    //   - store_byte_count must be non-zero
    //   - src_base_addr and dst_base_addr must be beat-aligned
    //   - final beat may be partial and uses WSTRB
    //   - single-beat AXI transactions are used internally
    //   - store_done is a one-cycle pulse
    //   - store_error is sticky until the next accepted start
    // ------------------------------------------------------------
    input  logic                     store_start,
    input  logic [ADDR_WIDTH-1:0]    src_base_addr,      // scratchpad C base
    input  logic [ADDR_WIDTH-1:0]    dst_base_addr,      // destination memory base
    input  logic [31:0]              store_byte_count,

    output logic                     store_busy,
    output logic                     store_done,
    output logic                     store_error,

    // ------------------------------------------------------------
    // Debug / status
    // ------------------------------------------------------------
    output logic [31:0]              read_beats,
    output logic [31:0]              write_beats,
    output logic [31:0]              committed_beats,
    output logic                     last_beat_seen,

    // ------------------------------------------------------------
    // Scratchpad AXI-MM read master
    // ------------------------------------------------------------
    output logic [AXI_ID_WIDTH-1:0]  spad_axi_arid,
    output logic [ADDR_WIDTH-1:0]    spad_axi_araddr,
    output logic [7:0]               spad_axi_arlen,
    output logic [2:0]               spad_axi_arsize,
    output logic [1:0]               spad_axi_arburst,
    output logic                     spad_axi_arvalid,
    input  logic                     spad_axi_arready,

    input  logic [AXI_ID_WIDTH-1:0]  spad_axi_rid,
    input  logic [DATA_WIDTH-1:0]    spad_axi_rdata,
    input  logic [1:0]               spad_axi_rresp,
    input  logic                     spad_axi_rlast,
    input  logic                     spad_axi_rvalid,
    output logic                     spad_axi_rready,

    // ------------------------------------------------------------
    // Destination AXI-MM write master
    // ------------------------------------------------------------
    output logic [AXI_ID_WIDTH-1:0]  dst_axi_awid,
    output logic [ADDR_WIDTH-1:0]    dst_axi_awaddr,
    output logic [7:0]               dst_axi_awlen,
    output logic [2:0]               dst_axi_awsize,
    output logic [1:0]               dst_axi_awburst,
    output logic                     dst_axi_awvalid,
    input  logic                     dst_axi_awready,

    output logic [DATA_WIDTH-1:0]    dst_axi_wdata,
    output logic [DATA_WIDTH/8-1:0]  dst_axi_wstrb,
    output logic                     dst_axi_wlast,
    output logic                     dst_axi_wvalid,
    input  logic                     dst_axi_wready,

    input  logic [AXI_ID_WIDTH-1:0]  dst_axi_bid,
    input  logic [1:0]               dst_axi_bresp,
    input  logic                     dst_axi_bvalid,
    output logic                     dst_axi_bready
);

    // ------------------------------------------------------------
    // Local parameters
    // ------------------------------------------------------------
    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam int BEAT_ADDR_LSB  = (BYTES_PER_BEAT <= 1) ? 0 : $clog2(BYTES_PER_BEAT);

    localparam logic [1:0] AXI_BURST_INCR = 2'b01;
    localparam logic [1:0] AXI_RESP_OKAY  = 2'b00;

    localparam logic [ADDR_WIDTH-1:0] ADDR_STRIDE =
        ADDR_WIDTH'(BYTES_PER_BEAT);

    localparam logic [31:0] BYTES_PER_BEAT_U32 =
        32'(BYTES_PER_BEAT);

    typedef enum logic [2:0] {
        S_IDLE        = 3'd0,
        S_SEND_AR     = 3'd1,
        S_WAIT_R      = 3'd2,
        S_SEND_AW_W   = 3'd3,
        S_WAIT_B      = 3'd4,
        S_DONE_PULSE  = 3'd5
    } state_e;

    state_e state, state_n;

    // ------------------------------------------------------------
    // Latched store parameters / current beat tracking
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] curr_src_addr_q;
    logic [ADDR_WIDTH-1:0] curr_dst_addr_q;
    logic [31:0]           remaining_bytes_q;

    logic [DATA_WIDTH-1:0]   rdata_buf_q;
    logic [DATA_WIDTH/8-1:0] wstrb_buf_q;
    logic                    last_beat_buf_q;

    logic                    aw_sent_q;
    logic                    w_sent_q;

    // ------------------------------------------------------------
    // Handshake helpers
    // ------------------------------------------------------------
    logic ar_fire;
    logic r_fire;
    logic aw_fire;
    logic w_fire;
    logic b_fire;

    logic r_error_now;
    logic b_error_now;
    logic store_req_valid;

    // ------------------------------------------------------------
    // Helper functions
    // ------------------------------------------------------------
    function automatic bit is_power_of_two(input int value);
        return (value > 0) && ((value & (value - 1)) == 0);
    endfunction

    function automatic bit addr_is_aligned(input logic [ADDR_WIDTH-1:0] addr);
        if (BYTES_PER_BEAT <= 1) begin
            return 1'b1;
        end
        else begin
            return (addr[BEAT_ADDR_LSB-1:0] == '0);
        end
    endfunction

    function automatic logic [DATA_WIDTH/8-1:0] make_wstrb(
        input logic [31:0] remaining_bytes
    );
        logic [DATA_WIDTH/8-1:0] strb;

        begin
            strb = '0;

            for (int i = 0; i < BYTES_PER_BEAT; i++) begin
                if (remaining_bytes > $unsigned(i)) begin
                    strb[i] = 1'b1;
                end
            end

            return strb;
        end
    endfunction

    function automatic bit is_last_beat(input logic [31:0] remaining_bytes);
        return (remaining_bytes <= BYTES_PER_BEAT_U32);
    endfunction

    // ------------------------------------------------------------
    // Static checks
    // ------------------------------------------------------------
    initial begin
        if ((DATA_WIDTH % 8) != 0) begin
            $fatal(1, "dma_store_engine: DATA_WIDTH must be byte-aligned");
        end

        if (!is_power_of_two(BYTES_PER_BEAT)) begin
            $fatal(1, "dma_store_engine: BYTES_PER_BEAT must be a power of two");
        end
    end

    // ------------------------------------------------------------
    // Request validation
    //
    // v1 alignment policy:
    //   - source scratchpad address must be beat-aligned
    //   - destination address must be beat-aligned
    //   - byte count must be non-zero
    //
    // Partial final beat is allowed through WSTRB.
    // ------------------------------------------------------------
    always_comb begin
        store_req_valid =
            (store_byte_count != 0) &&
            addr_is_aligned(src_base_addr) &&
            addr_is_aligned(dst_base_addr);
    end

    // ------------------------------------------------------------
    // Handshake / error helpers
    // ------------------------------------------------------------
    always_comb begin
        ar_fire = spad_axi_arvalid && spad_axi_arready;
        r_fire  = spad_axi_rvalid  && spad_axi_rready;

        aw_fire = dst_axi_awvalid  && dst_axi_awready;
        w_fire  = dst_axi_wvalid   && dst_axi_wready;
        b_fire  = dst_axi_bvalid   && dst_axi_bready;
    end

    always_comb begin
        r_error_now =
            r_fire &&
            (
                (spad_axi_rresp != AXI_RESP_OKAY) ||
                (spad_axi_rid   != SPAD_ARID)     ||
                (spad_axi_rlast != 1'b1)
            );
    end

    always_comb begin
        b_error_now =
            b_fire &&
            (
                (dst_axi_bresp != AXI_RESP_OKAY) ||
                (dst_axi_bid   != DST_AWID)
            );
    end

    // ------------------------------------------------------------
    // Public status
    //
    // store_busy is controlled by wrapper FSM state.
    // Do not infer ownership directly from downstream handshakes.
    // ------------------------------------------------------------
    always_comb begin
        store_busy =
            (state == S_SEND_AR)   ||
            (state == S_WAIT_R)    ||
            (state == S_SEND_AW_W) ||
            (state == S_WAIT_B);
    end

    always_comb begin
        store_done = (state == S_DONE_PULSE);
    end

    // ------------------------------------------------------------
    // Scratchpad AXI-MM read outputs
    // ------------------------------------------------------------
    always_comb begin
        spad_axi_arid    = SPAD_ARID;
        spad_axi_araddr  = curr_src_addr_q;
        spad_axi_arlen   = 8'd0;
        spad_axi_arburst = AXI_BURST_INCR;
        spad_axi_arvalid = (state == S_SEND_AR);

        if (BYTES_PER_BEAT <= 1) begin
            spad_axi_arsize = 3'd0;
        end
        else begin
            spad_axi_arsize = BEAT_ADDR_LSB[2:0];
        end

        spad_axi_rready = (state == S_WAIT_R);
    end

    // ------------------------------------------------------------
    // Destination AXI-MM write outputs
    // ------------------------------------------------------------
    always_comb begin
        dst_axi_awid    = DST_AWID;
        dst_axi_awaddr  = curr_dst_addr_q;
        dst_axi_awlen   = 8'd0;
        dst_axi_awburst = AXI_BURST_INCR;
        dst_axi_awvalid = (state == S_SEND_AW_W) && !aw_sent_q;

        if (BYTES_PER_BEAT <= 1) begin
            dst_axi_awsize = 3'd0;
        end
        else begin
            dst_axi_awsize = BEAT_ADDR_LSB[2:0];
        end

        dst_axi_wdata   = rdata_buf_q;
        dst_axi_wstrb   = wstrb_buf_q;
        dst_axi_wlast   = 1'b1;
        dst_axi_wvalid  = (state == S_SEND_AW_W) && !w_sent_q;

        dst_axi_bready  = (state == S_WAIT_B);
    end

    // ------------------------------------------------------------
    // Next-state logic
    // ------------------------------------------------------------
    always_comb begin
        state_n = state;

        case (state)
            S_IDLE: begin
                if (store_start) begin
                    if (store_req_valid) begin
                        state_n = S_SEND_AR;
                    end
                    else begin
                        state_n = S_DONE_PULSE;
                    end
                end
            end

            S_SEND_AR: begin
                if (ar_fire) begin
                    state_n = S_WAIT_R;
                end
            end

            S_WAIT_R: begin
                if (r_fire) begin
                    if (r_error_now) begin
                        state_n = S_DONE_PULSE;
                    end
                    else begin
                        state_n = S_SEND_AW_W;
                    end
                end
            end

            S_SEND_AW_W: begin
                if ((aw_sent_q || aw_fire) && (w_sent_q || w_fire)) begin
                    state_n = S_WAIT_B;
                end
            end

            S_WAIT_B: begin
                if (b_fire) begin
                    if (b_error_now) begin
                        state_n = S_DONE_PULSE;
                    end
                    else if (last_beat_buf_q) begin
                        state_n = S_DONE_PULSE;
                    end
                    else begin
                        state_n = S_SEND_AR;
                    end
                end
            end

            S_DONE_PULSE: begin
                state_n = S_IDLE;
            end

            default: begin
                state_n = S_IDLE;
            end
        endcase
    end

    // ------------------------------------------------------------
    // Sequential logic
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= S_IDLE;

            curr_src_addr_q   <= '0;
            curr_dst_addr_q   <= '0;
            remaining_bytes_q <= '0;

            rdata_buf_q       <= '0;
            wstrb_buf_q       <= '0;
            last_beat_buf_q   <= 1'b0;

            aw_sent_q         <= 1'b0;
            w_sent_q          <= 1'b0;

            store_error       <= 1'b0;

            read_beats        <= '0;
            write_beats       <= '0;
            committed_beats   <= '0;
            last_beat_seen    <= 1'b0;
        end
        else begin
            state <= state_n;

            case (state)
                S_IDLE: begin
                    if (store_start) begin
                        curr_src_addr_q   <= src_base_addr;
                        curr_dst_addr_q   <= dst_base_addr;
                        remaining_bytes_q <= store_byte_count;

                        rdata_buf_q       <= '0;
                        wstrb_buf_q       <= '0;
                        last_beat_buf_q   <= 1'b0;

                        aw_sent_q         <= 1'b0;
                        w_sent_q          <= 1'b0;

                        read_beats        <= '0;
                        write_beats       <= '0;
                        committed_beats   <= '0;
                        last_beat_seen    <= 1'b0;

                        store_error       <= 1'b0;

                        if (!store_req_valid) begin
                            store_error <= 1'b1;
                        end
                    end
                end

                S_SEND_AR: begin
                    // AR is driven combinationally.
                    // No sequential state update required here.
                    if (store_start) begin
                        // start while busy: flag error but allow
                        // current job to drain safely.
                        store_error <= 1'b1;
                    end
                end

                S_WAIT_R: begin
                    if (store_start) begin
                        store_error <= 1'b1;
                    end

                    if (r_fire) begin
                        read_beats <= read_beats + 32'd1;

                        if (r_error_now) begin
                            store_error <= 1'b1;
                        end
                        else begin
                            rdata_buf_q     <= spad_axi_rdata;
                            wstrb_buf_q     <= make_wstrb(remaining_bytes_q);
                            last_beat_buf_q <= is_last_beat(remaining_bytes_q);

                            aw_sent_q       <= 1'b0;
                            w_sent_q        <= 1'b0;

                            if (is_last_beat(remaining_bytes_q)) begin
                                last_beat_seen <= 1'b1;
                            end
                        end
                    end
                end

                S_SEND_AW_W: begin
                    if (store_start) begin
                        store_error <= 1'b1;
                    end

                    if (aw_fire) begin
                        aw_sent_q <= 1'b1;
                    end

                    if (w_fire) begin
                        w_sent_q    <= 1'b1;
                        write_beats <= write_beats + 32'd1;
                    end
                end

                S_WAIT_B: begin
                    if (store_start) begin
                        store_error <= 1'b1;
                    end

                    if (b_fire) begin
                        committed_beats <= committed_beats + 32'd1;

                        if (b_error_now) begin
                            store_error <= 1'b1;
                        end

                        aw_sent_q <= 1'b0;
                        w_sent_q  <= 1'b0;

                        if (!b_error_now && !last_beat_buf_q) begin
                            curr_src_addr_q <= curr_src_addr_q + ADDR_STRIDE;
                            curr_dst_addr_q <= curr_dst_addr_q + ADDR_STRIDE;

                            if (remaining_bytes_q > BYTES_PER_BEAT_U32) begin
                                remaining_bytes_q <= remaining_bytes_q - BYTES_PER_BEAT_U32;
                            end
                            else begin
                                remaining_bytes_q <= '0;
                            end
                        end
                    end
                end

                S_DONE_PULSE: begin
                    // Hold sticky store_error until next store_start.
                    aw_sent_q       <= 1'b0;
                    w_sent_q        <= 1'b0;
                    last_beat_buf_q <= 1'b0;
                end

                default: begin
                    // no-op
                end
            endcase
        end
    end

endmodule

`endif