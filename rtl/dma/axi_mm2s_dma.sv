// File: rtl/dma/axi_mm2s_dma.sv
`ifndef AXI_MM2S_DMA_SV
`define AXI_MM2S_DMA_SV

module axi_mm2s_dma #(
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 64,
    parameter int AXI_ID_WIDTH = 4,
    parameter logic [AXI_ID_WIDTH-1:0] AXI_ARID = '0
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // ------------------------------------------------------------
    // Simple control interface
    // ------------------------------------------------------------
    input  logic                     start,
    input  logic [ADDR_WIDTH-1:0]    src_addr,
    input  logic [31:0]              xfer_len_beats,

    output logic                     busy,
    output logic                     done,
    output logic                     error,

    // ------------------------------------------------------------
    // AXI-MM write channels (unused in v1, tied inactive)
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
    // AXI-MM read address channel
    // ------------------------------------------------------------
    output logic [AXI_ID_WIDTH-1:0]  m_axi_arid,
    output logic [ADDR_WIDTH-1:0]    m_axi_araddr,
    output logic [7:0]               m_axi_arlen,
    output logic [2:0]               m_axi_arsize,
    output logic [1:0]               m_axi_arburst,
    output logic                     m_axi_arvalid,
    input  logic                     m_axi_arready,

    // ------------------------------------------------------------
    // AXI-MM read data channel
    // ------------------------------------------------------------
    input  logic [AXI_ID_WIDTH-1:0]  m_axi_rid,
    input  logic [DATA_WIDTH-1:0]    m_axi_rdata,
    input  logic [1:0]               m_axi_rresp,
    input  logic                     m_axi_rlast,
    input  logic                     m_axi_rvalid,
    output logic                     m_axi_rready,

    // ------------------------------------------------------------
    // AXI-Stream output
    // ------------------------------------------------------------
    output logic [DATA_WIDTH-1:0]    m_axis_tdata,
    output logic                     m_axis_tvalid,
    input  logic                     m_axis_tready,
    output logic                     m_axis_tlast
);

    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam int BEAT_ADDR_LSB  = (BYTES_PER_BEAT <= 1) ? 0 : $clog2(BYTES_PER_BEAT);

    localparam logic [1:0] AXI_BURST_INCR = 2'b01;
    localparam logic [1:0] AXI_RESP_OKAY  = 2'b00;

    typedef enum logic [2:0] {
        S_IDLE       = 3'd0,
        S_ISSUE_AR   = 3'd1,
        S_WAIT_R     = 3'd2,
        S_STREAM     = 3'd3,
        S_DONE_PULSE = 3'd4
    } state_e;

    state_e state, state_n;

    logic [ADDR_WIDTH-1:0] curr_addr;
    logic [31:0]           beats_remaining;

    logic [DATA_WIDTH-1:0] data_buf;
    logic                  data_buf_valid;
    logic                  data_buf_last;

    logic                  launch_req_valid;

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

    function automatic bit launch_is_valid(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [31:0]           len_beats
    );
        return (len_beats != 0) && addr_is_aligned(addr);
    endfunction

    initial begin
        if ((DATA_WIDTH % 8) != 0) begin
            $fatal(1, "axi_mm2s_dma: DATA_WIDTH must be byte-aligned");
        end

        if (!is_power_of_two(BYTES_PER_BEAT)) begin
            $fatal(1, "axi_mm2s_dma: BYTES_PER_BEAT must be a power of two");
        end
    end

    always_comb begin
        launch_req_valid = launch_is_valid(src_addr, xfer_len_beats);
    end

    always_comb begin
        busy = 1'b0;
        case (state)
            S_ISSUE_AR,
            S_WAIT_R,
            S_STREAM: busy = 1'b1;
            default:  busy = 1'b0;
        endcase
    end

    always_comb begin
        done = (state == S_DONE_PULSE);
    end

    always_comb begin
        // Unused write channels
        m_axi_awid    = '0;
        m_axi_awaddr  = '0;
        m_axi_awlen   = '0;
        m_axi_awsize  = '0;
        m_axi_awburst = '0;
        m_axi_awvalid = 1'b0;

        m_axi_wdata   = '0;
        m_axi_wstrb   = '0;
        m_axi_wlast   = 1'b0;
        m_axi_wvalid  = 1'b0;

        m_axi_bready  = 1'b0;

        // Read address channel
        m_axi_arid    = AXI_ARID;
        m_axi_araddr  = curr_addr;
        m_axi_arlen   = 8'd0;
        m_axi_arburst = AXI_BURST_INCR;
        m_axi_arvalid = (state == S_ISSUE_AR);

        if (BYTES_PER_BEAT <= 1) begin
            m_axi_arsize = 3'd0;
        end
        else begin
            m_axi_arsize = BEAT_ADDR_LSB[2:0];
        end

        // Read data channel
        m_axi_rready  = (state == S_WAIT_R);
    end

    always_comb begin
        m_axis_tdata  = data_buf;
        m_axis_tvalid = (state == S_STREAM) && data_buf_valid;
        m_axis_tlast  = data_buf_last;
    end

    always_comb begin
        state_n = state;

        case (state)
            S_IDLE: begin
                if (start) begin
                    if (launch_req_valid) begin
                        state_n = S_ISSUE_AR;
                    end
                    else begin
                        state_n = S_DONE_PULSE;
                    end
                end
            end

            S_ISSUE_AR: begin
                if (m_axi_arvalid && m_axi_arready) begin
                    state_n = S_WAIT_R;
                end
            end

            S_WAIT_R: begin
                if (m_axi_rvalid && m_axi_rready) begin
                    if ((m_axi_rresp != AXI_RESP_OKAY) ||
                        (m_axi_rid   != AXI_ARID)     ||
                        (m_axi_rlast != 1'b1)) begin
                        state_n = S_DONE_PULSE;
                    end
                    else begin
                        state_n = S_STREAM;
                    end
                end
            end

            S_STREAM: begin
                if (m_axis_tvalid && m_axis_tready) begin
                    if (data_buf_last) begin
                        state_n = S_DONE_PULSE;
                    end
                    else begin
                        state_n = S_ISSUE_AR;
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            curr_addr       <= '0;
            beats_remaining <= '0;
            data_buf        <= '0;
            data_buf_valid  <= 1'b0;
            data_buf_last   <= 1'b0;
            error           <= 1'b0;
        end
        else begin
            state <= state_n;

            case (state)
                S_IDLE: begin
                    data_buf_valid <= 1'b0;
                    data_buf_last  <= 1'b0;

                    if (start) begin
                        error           <= 1'b0;
                        curr_addr       <= src_addr;
                        beats_remaining <= xfer_len_beats;

                        if (!launch_req_valid) begin
                            error <= 1'b1;
                        end
                    end
                end

                S_ISSUE_AR: begin
                    // no-op
                end

                S_WAIT_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        if ((m_axi_rresp != AXI_RESP_OKAY) ||
                            (m_axi_rid   != AXI_ARID)     ||
                            (m_axi_rlast != 1'b1)) begin
                            error <= 1'b1;
                        end
                        else begin
                            data_buf       <= m_axi_rdata;
                            data_buf_valid <= 1'b1;
                            data_buf_last  <= (beats_remaining == 32'd1);

                            curr_addr       <= curr_addr + ADDR_WIDTH'(BYTES_PER_BEAT);
                            beats_remaining <= beats_remaining - 32'd1;
                        end
                    end
                end

                S_STREAM: begin
                    if (m_axis_tvalid && m_axis_tready) begin
                        data_buf_valid <= 1'b0;
                        data_buf_last  <= 1'b0;
                    end
                end

                S_DONE_PULSE: begin
                    data_buf_valid <= 1'b0;
                    data_buf_last  <= 1'b0;
                end

                default: begin
                    // no-op
                end
            endcase
        end
    end

endmodule

`endif