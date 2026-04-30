// File: rtl/subsystem/dma_scratchpad_write_adapter.sv
`ifndef DMA_SCRATCHPAD_WRITE_ADAPTER_SV
`define DMA_SCRATCHPAD_WRITE_ADAPTER_SV

module dma_scratchpad_write_adapter #(
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 64,
    parameter int AXI_ID_WIDTH = 4,
    parameter logic [AXI_ID_WIDTH-1:0] AXI_AWID = '0
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // ------------------------------------------------------------
    // Upstream linear write request from axi_stream_loader
    //
    // v1 assumptions:
    //   - address is already beat-aligned
    //   - full-beat write is the normal mode
    //   - one request is accepted at a time
    // ------------------------------------------------------------
    input  logic                     src_wr_valid,
    output logic                     src_wr_ready,
    input  logic [ADDR_WIDTH-1:0]    src_wr_addr,
    input  logic [DATA_WIDTH-1:0]    src_wr_data,
    input  logic [DATA_WIDTH/8-1:0]  src_wr_strb,
    input  logic                     src_wr_last,

    // ------------------------------------------------------------
    // Session / debug status
    // ------------------------------------------------------------
    output logic                     busy,
    output logic                     done,
    output logic                     error,
    output logic [31:0]              accepted_beats,
    output logic [31:0]              committed_beats,
    output logic                     last_beat_seen,

    // ------------------------------------------------------------
    // AXI-MM write master toward scratchpad
    // ------------------------------------------------------------
    output logic [AXI_ID_WIDTH-1:0]  m_axi_awid,
    output logic [ADDR_WIDTH-1:0]    m_axi_awaddr,
    output logic [7:0]               m_axi_awlen,
    output logic [2:0]               m_axi_awsize,
    output logic [1:0]               m_axi_awburst,
    output logic                     m_axi_awvalid,
    input  logic                     m_axi_awready,

    output logic [DATA_WIDTH-1:0]    m_axi_wdata,
    output logic [DATA_WIDTH/8-1:0]  m_axi_wstrb,
    output logic                     m_axi_wlast,
    output logic                     m_axi_wvalid,
    input  logic                     m_axi_wready,

    input  logic [AXI_ID_WIDTH-1:0]  m_axi_bid,
    input  logic [1:0]               m_axi_bresp,
    input  logic                     m_axi_bvalid,
    output logic                     m_axi_bready,

    // ------------------------------------------------------------
    // AXI-MM read channel (unused in v1)
    // ------------------------------------------------------------
    output logic [AXI_ID_WIDTH-1:0]  m_axi_arid,
    output logic [ADDR_WIDTH-1:0]    m_axi_araddr,
    output logic [7:0]               m_axi_arlen,
    output logic [2:0]               m_axi_arsize,
    output logic [1:0]               m_axi_arburst,
    output logic                     m_axi_arvalid,
    input  logic                     m_axi_arready,

    input  logic [AXI_ID_WIDTH-1:0]  m_axi_rid,
    input  logic [DATA_WIDTH-1:0]    m_axi_rdata,
    input  logic [1:0]               m_axi_rresp,
    input  logic                     m_axi_rlast,
    input  logic                     m_axi_rvalid,
    output logic                     m_axi_rready
);

    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam int BEAT_ADDR_LSB  = (BYTES_PER_BEAT <= 1) ? 0 : $clog2(BYTES_PER_BEAT);
    localparam logic [1:0] AXI_BURST_INCR = 2'b01;
    localparam logic [1:0] AXI_RESP_OKAY  = 2'b00;
    localparam logic [ADDR_WIDTH-1:0] ADDR_STRIDE = ADDR_WIDTH'(BYTES_PER_BEAT);

    typedef enum logic [1:0] {
        S_WAIT_REQ   = 2'd0,
        S_SEND_AW_W  = 2'd1,
        S_WAIT_B     = 2'd2,
        S_DONE_PULSE = 2'd3
    } state_e;

    state_e state, state_n;

    // ------------------------------------------------------------
    // One-entry request buffer
    // ------------------------------------------------------------
    logic                  buf_valid;
    logic [ADDR_WIDTH-1:0] buf_addr;
    logic [DATA_WIDTH-1:0] buf_data;
    logic [DATA_WIDTH/8-1:0] buf_strb;
    logic                  buf_last;

    logic                  aw_sent;
    logic                  w_sent;

    logic                  session_active;

    logic                  req_fire;
    logic                  aw_fire;
    logic                  w_fire;
    logic                  b_fire;

    function automatic bit is_power_of_two(input int value);
        return (value > 0) && ((value & (value - 1)) == 0);
    endfunction

    initial begin
        if ((DATA_WIDTH % 8) != 0) begin
            $fatal(1, "dma_scratchpad_write_adapter: DATA_WIDTH must be byte-aligned");
        end

        if (!is_power_of_two(BYTES_PER_BEAT)) begin
            $fatal(1, "dma_scratchpad_write_adapter: BYTES_PER_BEAT must be a power of two");
        end
    end

    // ------------------------------------------------------------
    // Handshake helpers
    // ------------------------------------------------------------
    always_comb begin
        req_fire = src_wr_valid && src_wr_ready;
        aw_fire  = m_axi_awvalid && m_axi_awready;
        w_fire   = m_axi_wvalid  && m_axi_wready;
        b_fire   = m_axi_bvalid  && m_axi_bready;
    end

    // ------------------------------------------------------------
    // Upstream ready
    // ------------------------------------------------------------
    always_comb begin
        src_wr_ready = (state == S_WAIT_REQ);
    end

    // ------------------------------------------------------------
    // Status
    // ------------------------------------------------------------
    always_comb begin
        busy =
            session_active ||
            (state == S_SEND_AW_W) ||
            (state == S_WAIT_B);
    end

    always_comb begin
        done = (state == S_DONE_PULSE);
    end

    // ------------------------------------------------------------
    // AXI-MM write outputs
    // ------------------------------------------------------------
    always_comb begin
        m_axi_awid    = AXI_AWID;
        m_axi_awaddr  = buf_addr;
        m_axi_awlen   = 8'd0;
        m_axi_awburst = AXI_BURST_INCR;
        m_axi_awvalid = (state == S_SEND_AW_W) && !aw_sent;

        if (BYTES_PER_BEAT <= 1) begin
            m_axi_awsize = 3'd0;
        end
        else begin
            m_axi_awsize = BEAT_ADDR_LSB[2:0];
        end

        m_axi_wdata   = buf_data;
        m_axi_wstrb   = buf_strb;
        m_axi_wlast   = 1'b1;
        m_axi_wvalid  = (state == S_SEND_AW_W) && !w_sent;

        m_axi_bready  = (state == S_WAIT_B);
    end

    // ------------------------------------------------------------
    // AXI-MM read outputs (unused in v1)
    // ------------------------------------------------------------
    always_comb begin
        m_axi_arid    = '0;
        m_axi_araddr  = '0;
        m_axi_arlen   = '0;
        m_axi_arburst = '0;
        m_axi_arvalid = 1'b0;
        m_axi_arsize  = '0;
        m_axi_rready  = 1'b0;
    end

    // ------------------------------------------------------------
    // Next-state logic
    // ------------------------------------------------------------
    always_comb begin
        state_n = state;

        case (state)
            S_WAIT_REQ: begin
                if (req_fire) begin
                    state_n = S_SEND_AW_W;
                end
            end

            S_SEND_AW_W: begin
                if ((aw_sent || aw_fire) && (w_sent || w_fire)) begin
                    state_n = S_WAIT_B;
                end
            end

            S_WAIT_B: begin
                if (b_fire) begin
                    if (buf_last) begin
                        state_n = S_DONE_PULSE;
                    end
                    else begin
                        state_n = S_WAIT_REQ;
                    end
                end
            end

            S_DONE_PULSE: begin
                state_n = S_WAIT_REQ;
            end

            default: begin
                state_n = S_WAIT_REQ;
            end
        endcase
    end

    // ------------------------------------------------------------
    // Sequential logic
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_WAIT_REQ;

            buf_valid       <= 1'b0;
            buf_addr        <= '0;
            buf_data        <= '0;
            buf_strb        <= '0;
            buf_last        <= 1'b0;

            aw_sent         <= 1'b0;
            w_sent          <= 1'b0;

            session_active  <= 1'b0;

            accepted_beats  <= '0;
            committed_beats <= '0;
            last_beat_seen  <= 1'b0;

            error           <= 1'b0;
        end
        else begin
            state <= state_n;

            case (state)
                S_WAIT_REQ: begin
                    if (req_fire) begin
                        // New session starts on first accepted beat
                        if (!session_active) begin
                            accepted_beats  <= '0;
                            committed_beats <= '0;
                            last_beat_seen  <= 1'b0;
                            error           <= 1'b0;
                            session_active  <= 1'b1;
                        end

                        buf_valid <= 1'b1;
                        buf_addr  <= src_wr_addr;
                        buf_data  <= src_wr_data;
                        buf_strb  <= src_wr_strb;
                        buf_last  <= src_wr_last;

                        aw_sent   <= 1'b0;
                        w_sent    <= 1'b0;

                        accepted_beats <= accepted_beats + 32'd1;

                        if (src_wr_last) begin
                            last_beat_seen <= 1'b1;
                        end
                    end
                end

                S_SEND_AW_W: begin
                    if (aw_fire) begin
                        aw_sent <= 1'b1;
                    end

                    if (w_fire) begin
                        w_sent <= 1'b1;
                    end
                end

                S_WAIT_B: begin
                    if (b_fire) begin
                        committed_beats <= committed_beats + 32'd1;

                        if ((m_axi_bresp != AXI_RESP_OKAY) ||
                            (m_axi_bid   != AXI_AWID)) begin
                            error <= 1'b1;
                        end

                        buf_valid <= 1'b0;
                        buf_addr  <= '0;
                        buf_data  <= '0;
                        buf_strb  <= '0;
                        buf_last  <= 1'b0;

                        aw_sent   <= 1'b0;
                        w_sent    <= 1'b0;

                        if (buf_last) begin
                            session_active <= 1'b0;
                        end
                    end
                end

                S_DONE_PULSE: begin
                    // hold sticky status until next session starts
                end

                default: begin
                    // no-op
                end
            endcase
        end
    end

endmodule

`endif