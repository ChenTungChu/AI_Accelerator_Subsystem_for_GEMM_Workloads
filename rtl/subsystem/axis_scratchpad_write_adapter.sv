// File: rtl/subsystem/axis_scratchpad_write_adapter.sv

`ifndef AXIS_SCRATCHPAD_WRITE_ADAPTER_SV
`define AXIS_SCRATCHPAD_WRITE_ADAPTER_SV

module axis_scratchpad_write_adapter #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 4,

    parameter logic [ID_WIDTH-1:0] AXI_AWID = '0
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // ------------------------------------------------------------
    // Module role
    //
    // Converts axi_stream_loader linear write requests into
    // single-beat AXI-MM writes toward scratchpad Port1.
    //
    // This adapter is used by the AXI-Stream A/B preload path only.
    // It is not part of GEMM runtime C writes or P13 C RMW old-C
    // reads; those use the GEMM local-memory scratchpad path.
    // ------------------------------------------------------------

    // ------------------------------------------------------------
    // Status clear
    //
    // Intended usage:
    //   Pulse clear_status before launching a new stream preload job.
    // ------------------------------------------------------------
    input  logic                     clear_status,

    // ------------------------------------------------------------
    // Linear write-request input
    //
    // Source:
    //   axi_stream_loader wr_* output.
    //
    // Semantics:
    //   wr_ready means this adapter has accepted one loader write
    //   request. The corresponding AXI write response may complete
    //   later.
    // ------------------------------------------------------------
    input  logic                     wr_valid,
    output logic                     wr_ready,
    input  logic [ADDR_WIDTH-1:0]    wr_addr,
    input  logic [DATA_WIDTH-1:0]    wr_data,
    input  logic [DATA_WIDTH/8-1:0]  wr_strb,
    input  logic                     wr_last,

    // ------------------------------------------------------------
    // AXI-MM write address channel
    //
    // Target:
    //   scratchpad Port1 STREAM_LOAD owner input.
    // ------------------------------------------------------------
    output logic [ID_WIDTH-1:0]      m_axi_awid,
    output logic [ADDR_WIDTH-1:0]    m_axi_awaddr,
    output logic [7:0]               m_axi_awlen,
    output logic [2:0]               m_axi_awsize,
    output logic [1:0]               m_axi_awburst,
    output logic                     m_axi_awvalid,
    input  logic                     m_axi_awready,

    // ------------------------------------------------------------
    // AXI-MM write data channel
    // ------------------------------------------------------------
    output logic [DATA_WIDTH-1:0]    m_axi_wdata,
    output logic [DATA_WIDTH/8-1:0]  m_axi_wstrb,
    output logic                     m_axi_wlast,
    output logic                     m_axi_wvalid,
    input  logic                     m_axi_wready,

    // ------------------------------------------------------------
    // AXI-MM write response channel
    // ------------------------------------------------------------
    input  logic [ID_WIDTH-1:0]      m_axi_bid,
    input  logic [1:0]               m_axi_bresp,
    input  logic                     m_axi_bvalid,
    output logic                     m_axi_bready,

    // ------------------------------------------------------------
    // Status / debug
    //
    // write_done:
    //   one-cycle pulse when one write request has completed.
    //
    // write_error:
    //   one-cycle pulse when the completed write had an error.
    //
    // error:
    //   sticky error bit, cleared by reset or clear_status.
    // ------------------------------------------------------------
    output logic                     busy,
    output logic                     write_done,
    output logic                     write_done_last,
    output logic                     write_error,
    output logic                     error,

    output logic [31:0]              accepted_writes,
    output logic [31:0]              completed_writes
);

    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam int BEAT_ADDR_LSB  = (BYTES_PER_BEAT <= 1) ? 0 : $clog2(BYTES_PER_BEAT);

    localparam logic [1:0] AXI_BURST_INCR = 2'b01;
    localparam logic [1:0] AXI_RESP_OKAY  = 2'b00;

    typedef enum logic [1:0] {
        S_IDLE       = 2'd0,
        S_SEND       = 2'd1,
        S_WAIT_B     = 2'd2,
        S_DONE_PULSE = 2'd3
    } state_e;

    state_e state, state_n;

    // ------------------------------------------------------------
    // Captured write request
    //
    // One linear loader write is converted into one single-beat AXI
    // write. AW and W may handshake in either order; the adapter
    // waits for both before accepting the B response.
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0]   req_addr_q;
    logic [DATA_WIDTH-1:0]   req_data_q;
    logic [DATA_WIDTH/8-1:0] req_strb_q;
    logic                    req_last_q;

    // ------------------------------------------------------------
    // AW/W channel tracking
    // ------------------------------------------------------------
    logic aw_done_q;
    logic w_done_q;

    logic aw_fire;
    logic w_fire;
    logic b_fire;
    logic wr_fire;

    logic req_addr_aligned;
    logic accepted_req_is_valid;

    logic complete_error_q;
    logic complete_last_q;

    // ------------------------------------------------------------
    // Parameter sanity
    // ------------------------------------------------------------
    function automatic bit is_power_of_two(input int value);
        return (value > 0) && ((value & (value - 1)) == 0);
    endfunction

    function automatic bit addr_is_aligned(
        input logic [ADDR_WIDTH-1:0] addr
    );
        if (BYTES_PER_BEAT <= 1) begin
            return 1'b1;
        end
        else begin
            return (addr[BEAT_ADDR_LSB-1:0] == '0);
        end
    endfunction

    initial begin
        if ((DATA_WIDTH % 8) != 0) begin
            $fatal(1,
                "axis_scratchpad_write_adapter: DATA_WIDTH must be byte-aligned"
            );
        end

        if (!is_power_of_two(BYTES_PER_BEAT)) begin
            $fatal(1,
                "axis_scratchpad_write_adapter: BYTES_PER_BEAT must be a power of two"
            );
        end
    end

    // ------------------------------------------------------------
    // Handshake helpers
    // ------------------------------------------------------------
    always_comb begin
        aw_fire = m_axi_awvalid && m_axi_awready;
        w_fire  = m_axi_wvalid  && m_axi_wready;
        b_fire  = m_axi_bvalid  && m_axi_bready;
        wr_fire = wr_valid      && wr_ready;
    end

    always_comb begin
        req_addr_aligned      = addr_is_aligned(wr_addr);
        accepted_req_is_valid = req_addr_aligned;
    end

    // ------------------------------------------------------------
    // Ready / status
    // ------------------------------------------------------------
    always_comb begin
        wr_ready = (state == S_IDLE);
    end

    always_comb begin
        busy = (state == S_SEND) || (state == S_WAIT_B);
    end

    always_comb begin
        write_done      = (state == S_DONE_PULSE);
        write_error     = (state == S_DONE_PULSE) && complete_error_q;
        write_done_last = (state == S_DONE_PULSE) && complete_last_q;
    end

    // ------------------------------------------------------------
    // AXI write output generation
    // ------------------------------------------------------------
    always_comb begin
        m_axi_awid    = AXI_AWID;
        m_axi_awaddr  = req_addr_q;
        m_axi_awlen   = 8'd0;
        m_axi_awburst = AXI_BURST_INCR;
        m_axi_awvalid = (state == S_SEND) && !aw_done_q;

        if (BYTES_PER_BEAT <= 1) begin
            m_axi_awsize = 3'd0;
        end
        else begin
            m_axi_awsize = BEAT_ADDR_LSB[2:0];
        end

        m_axi_wdata   = req_data_q;
        m_axi_wstrb   = req_strb_q;
        m_axi_wlast   = 1'b1;
        m_axi_wvalid  = (state == S_SEND) && !w_done_q;

        m_axi_bready  = (state == S_WAIT_B);
    end

    // ------------------------------------------------------------
    // FSM next-state
    // ------------------------------------------------------------
    always_comb begin
        state_n = state;

        case (state)
            S_IDLE: begin
                if (wr_fire) begin
                    if (accepted_req_is_valid) begin
                        state_n = S_SEND;
                    end
                    else begin
                        state_n = S_DONE_PULSE;
                    end
                end
            end

            S_SEND: begin
                if ((aw_done_q || aw_fire) &&
                    (w_done_q  || w_fire)) begin
                    state_n = S_WAIT_B;
                end
            end

            S_WAIT_B: begin
                if (b_fire) begin
                    state_n = S_DONE_PULSE;
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
            state            <= S_IDLE;

            req_addr_q       <= '0;
            req_data_q       <= '0;
            req_strb_q       <= '0;
            req_last_q       <= 1'b0;

            aw_done_q        <= 1'b0;
            w_done_q         <= 1'b0;

            complete_error_q <= 1'b0;
            complete_last_q  <= 1'b0;

            error            <= 1'b0;
            accepted_writes  <= '0;
            completed_writes <= '0;
        end
        else begin
            state <= state_n;

            if (clear_status) begin
                error            <= 1'b0;
                accepted_writes  <= '0;
                completed_writes <= '0;
            end

            case (state)
                S_IDLE: begin
                    aw_done_q        <= 1'b0;
                    w_done_q         <= 1'b0;
                    complete_error_q <= 1'b0;
                    complete_last_q  <= 1'b0;

                    if (wr_fire) begin
                        req_addr_q <= wr_addr;
                        req_data_q <= wr_data;
                        req_strb_q <= wr_strb;
                        req_last_q <= wr_last;

                        complete_last_q <= wr_last;

                        accepted_writes <= accepted_writes + 32'd1;

                        if (!accepted_req_is_valid) begin
                            complete_error_q <= 1'b1;
                            error            <= 1'b1;
                        end
                    end
                end

                S_SEND: begin
                    if (aw_fire) begin
                        aw_done_q <= 1'b1;
                    end

                    if (w_fire) begin
                        w_done_q <= 1'b1;
                    end
                end

                S_WAIT_B: begin
                    if (b_fire) begin
                        completed_writes <= completed_writes + 32'd1;

                        complete_last_q <= req_last_q;

                        if ((m_axi_bresp != AXI_RESP_OKAY) ||
                            (m_axi_bid   != AXI_AWID)) begin
                            complete_error_q <= 1'b1;
                            error            <= 1'b1;
                        end
                        else begin
                            complete_error_q <= 1'b0;
                        end
                    end
                end

                S_DONE_PULSE: begin
                    aw_done_q <= 1'b0;
                    w_done_q  <= 1'b0;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

`endif