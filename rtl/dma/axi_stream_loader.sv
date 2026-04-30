// File: rtl/dma/axi_stream_loader.sv
`ifndef AXI_STREAM_LOADER_SV
`define AXI_STREAM_LOADER_SV

module axi_stream_loader #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int CAPTURE_DEPTH = 1024,
    parameter int CAPTURE_ADDR_WIDTH = (CAPTURE_DEPTH <= 1) ? 1 : $clog2(CAPTURE_DEPTH)
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // ------------------------------------------------------------
    // Simple control interface
    // ------------------------------------------------------------
    input  logic                     start,
    input  logic [ADDR_WIDTH-1:0]    dst_base_addr,
    input  logic [31:0]              expected_beats,

    output logic                     busy,
    output logic                     done,
    output logic                     error,

    // ------------------------------------------------------------
    // AXI-Stream input
    // ------------------------------------------------------------
    input  logic [DATA_WIDTH-1:0]    s_axis_tdata,
    input  logic                     s_axis_tvalid,
    output logic                     s_axis_tready,
    input  logic                     s_axis_tlast,

    // ------------------------------------------------------------
    // Simple linear write-request output
    // ------------------------------------------------------------
    output logic                     wr_valid,
    input  logic                     wr_ready,
    output logic [ADDR_WIDTH-1:0]    wr_addr,
    output logic [DATA_WIDTH-1:0]    wr_data,
    output logic [DATA_WIDTH/8-1:0]  wr_strb,
    output logic                     wr_last,

    // ------------------------------------------------------------
    // Debug / readback port
    // ------------------------------------------------------------
    input  logic                     rd_en,
    input  logic [CAPTURE_ADDR_WIDTH-1:0] rd_addr,
    output logic [DATA_WIDTH-1:0]    rd_data,

    // ------------------------------------------------------------
    // Status / debug
    // ------------------------------------------------------------
    output logic [31:0]              accepted_beats,
    output logic [31:0]              written_beats,
    output logic                     tlast_seen
);

    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam int BEAT_ADDR_LSB  = (BYTES_PER_BEAT <= 1) ? 0 : $clog2(BYTES_PER_BEAT);
    localparam logic [DATA_WIDTH/8-1:0] FULL_STRB = {DATA_WIDTH/8{1'b1}};

    typedef enum logic [1:0] {
        S_IDLE       = 2'd0,
        S_ACTIVE     = 2'd1,
        S_DONE_PULSE = 2'd2
    } state_e;

    state_e state, state_n;

    // ------------------------------------------------------------
    // One-beat internal buffer
    // ------------------------------------------------------------
    logic                  buf_valid;
    logic [ADDR_WIDTH-1:0] buf_addr;
    logic [DATA_WIDTH-1:0] buf_data;
    logic                  buf_last;

    // ------------------------------------------------------------
    // Capture memory for debug / readback
    // ------------------------------------------------------------
    logic [DATA_WIDTH-1:0] capture_mem [0:CAPTURE_DEPTH-1];

    // ------------------------------------------------------------
    // Transfer tracking
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] next_dst_addr;
    logic                  end_pending;
    logic                  end_error;

    logic                  launch_req_valid;
    logic                  axis_fire;
    logic                  wr_fire;

    logic [31:0]           next_accepted_beats;
    logic                  tlast_len_mismatch;
    logic                  missing_tlast_at_expected_end;
    logic                  terminal_error_on_accept;
    logic                  terminal_success_on_accept;
    logic                  hit_capture_capacity;

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

    initial begin
        if ((DATA_WIDTH % 8) != 0) begin
            $fatal(1, "axi_stream_loader: DATA_WIDTH must be byte-aligned");
        end

        if (!is_power_of_two(BYTES_PER_BEAT)) begin
            $fatal(1, "axi_stream_loader: BYTES_PER_BEAT must be a power of two");
        end
    end

    always_comb begin
        launch_req_valid = addr_is_aligned(dst_base_addr);
    end

    always_comb begin
        s_axis_tready = 1'b0;
        if ((state == S_ACTIVE) && !end_pending) begin
            s_axis_tready = (!buf_valid) || wr_ready;
        end
    end

    always_comb begin
        axis_fire = s_axis_tvalid && s_axis_tready;
        wr_fire   = wr_valid && wr_ready;
    end

    always_comb begin
        next_accepted_beats = accepted_beats + 32'd1;
    end

    always_comb begin
        hit_capture_capacity = axis_fire && (accepted_beats >= CAPTURE_DEPTH);
    end

    always_comb begin
        tlast_len_mismatch =
            axis_fire &&
            s_axis_tlast &&
            (expected_beats != 0) &&
            (next_accepted_beats != expected_beats);
    end

    always_comb begin
        missing_tlast_at_expected_end =
            axis_fire &&
            !s_axis_tlast &&
            (expected_beats != 0) &&
            (next_accepted_beats >= expected_beats);
    end

    always_comb begin
        terminal_error_on_accept =
            hit_capture_capacity ||
            tlast_len_mismatch   ||
            missing_tlast_at_expected_end;
    end

    always_comb begin
        terminal_success_on_accept =
            axis_fire &&
            s_axis_tlast &&
            !terminal_error_on_accept;
    end

    always_comb begin
        busy = (state == S_ACTIVE);
    end

    always_comb begin
        done = (state == S_DONE_PULSE);
    end

    always_comb begin
        wr_valid = buf_valid;
        wr_addr  = buf_addr;
        wr_data  = buf_data;
        wr_strb  = FULL_STRB;
        wr_last  = buf_last;
    end

    always_comb begin
        rd_data = '0;
        if (rd_en) begin
            if (rd_addr < CAPTURE_DEPTH) begin
                rd_data = capture_mem[rd_addr];
            end
        end
    end

    always_comb begin
        state_n = state;

        case (state)
            S_IDLE: begin
                if (start) begin
                    if (launch_req_valid) begin
                        state_n = S_ACTIVE;
                    end
                    else begin
                        state_n = S_DONE_PULSE;
                    end
                end
            end

            S_ACTIVE: begin
                if (end_pending && !buf_valid) begin
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= S_IDLE;

            buf_valid       <= 1'b0;
            buf_addr        <= '0;
            buf_data        <= '0;
            buf_last        <= 1'b0;

            next_dst_addr   <= '0;

            accepted_beats  <= '0;
            written_beats   <= '0;
            tlast_seen      <= 1'b0;

            end_pending     <= 1'b0;
            end_error       <= 1'b0;

            error           <= 1'b0;
        end
        else begin
            state <= state_n;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        buf_valid      <= 1'b0;
                        buf_addr       <= '0;
                        buf_data       <= '0;
                        buf_last       <= 1'b0;

                        next_dst_addr  <= dst_base_addr;

                        accepted_beats <= '0;
                        written_beats  <= '0;
                        tlast_seen     <= 1'b0;

                        end_pending    <= 1'b0;
                        end_error      <= 1'b0;

                        error          <= 1'b0;

                        if (!launch_req_valid) begin
                            error <= 1'b1;
                        end
                    end
                end

                S_ACTIVE: begin
                    if (wr_fire) begin
                        written_beats <= written_beats + 32'd1;
                    end

                    unique case ({axis_fire, wr_fire})
                        2'b00: begin
                            // hold
                        end

                        2'b01: begin
                            buf_valid <= 1'b0;
                            buf_addr  <= '0;
                            buf_data  <= '0;
                            buf_last  <= 1'b0;
                        end

                        2'b10,
                        2'b11: begin
                            buf_valid <= 1'b1;
                            buf_addr  <= next_dst_addr;
                            buf_data  <= s_axis_tdata;
                            buf_last  <= s_axis_tlast;
                        end

                        default: begin
                            // no-op
                        end
                    endcase

                    if (axis_fire) begin
                        if (!hit_capture_capacity) begin
                            capture_mem[accepted_beats[CAPTURE_ADDR_WIDTH-1:0]] <= s_axis_tdata;
                        end

                        accepted_beats <= next_accepted_beats;
                        next_dst_addr  <= next_dst_addr + ADDR_WIDTH'(BYTES_PER_BEAT);

                        if (s_axis_tlast) begin
                            tlast_seen <= 1'b1;
                        end

                        if (terminal_error_on_accept) begin
                            end_pending <= 1'b1;
                            end_error   <= 1'b1;
                            error       <= 1'b1;
                        end
                        else if (terminal_success_on_accept) begin
                            end_pending <= 1'b1;
                            end_error   <= 1'b0;
                        end
                    end
                end

                S_DONE_PULSE: begin
                    // hold status until next start
                end

                default: begin
                    // no-op
                end
            endcase
        end
    end

endmodule

`endif