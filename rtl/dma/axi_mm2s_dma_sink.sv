// File: rtl/dma/axi_mm2s_dma_sink.sv
`ifndef AXI_MM2S_DMA_SINK_SV
`define AXI_MM2S_DMA_SINK_SV

module axi_mm2s_dma_sink #(
    parameter int DATA_WIDTH = 64,
    parameter int CAPTURE_DEPTH = 1024,
    parameter int CAPTURE_ADDR_WIDTH = (CAPTURE_DEPTH <= 1) ? 1 : $clog2(CAPTURE_DEPTH)
)(
    input  logic                          clk,
    input  logic                          rst_n,

    // ------------------------------------------------------------
    // Simple control interface
    //
    // v1 behavior:
    //   - start arms a new capture in IDLE
    //   - expected_beats == 0 means:
    //       capture until TLAST without count checking
    //   - expected_beats != 0 means:
    //       TLAST must arrive exactly on that beat count
    // ------------------------------------------------------------
    input  logic                          start,
    input  logic [31:0]                   expected_beats,

    output logic                          busy,
    output logic                          done,
    output logic                          error,

    // ------------------------------------------------------------
    // AXI-Stream sink
    // ------------------------------------------------------------
    input  logic [DATA_WIDTH-1:0]         s_axis_tdata,
    input  logic                          s_axis_tvalid,
    output logic                          s_axis_tready,
    input  logic                          s_axis_tlast,

    // ------------------------------------------------------------
    // Simple debug / readback port
    // ------------------------------------------------------------
    input  logic                          rd_en,
    input  logic [CAPTURE_ADDR_WIDTH-1:0] rd_addr,
    output logic [DATA_WIDTH-1:0]         rd_data,

    // ------------------------------------------------------------
    // Status
    // ------------------------------------------------------------
    output logic [31:0]                   captured_beats,
    output logic                          tlast_seen
);

    typedef enum logic [1:0] {
        S_IDLE       = 2'd0,
        S_CAPTURE    = 2'd1,
        S_DONE_PULSE = 2'd2
    } state_e;

    state_e state, state_n;

    logic [DATA_WIDTH-1:0] capture_mem [0:CAPTURE_DEPTH-1];

    logic [31:0] next_captured_beats;

    logic axis_fire;
    logic hit_capacity;
    logic tlast_len_mismatch;
    logic missing_tlast_at_expected_end;
    logic terminal_error;
    logic terminal_success;
    logic terminal_event;

    // ------------------------------------------------------------
    // Combinational helpers
    // ------------------------------------------------------------
    always_comb begin
        axis_fire = (state == S_CAPTURE) && s_axis_tvalid && s_axis_tready;
    end

    always_comb begin
        next_captured_beats = captured_beats + 32'd1;
    end

    always_comb begin
        hit_capacity = axis_fire && (captured_beats >= CAPTURE_DEPTH);
    end

    always_comb begin
        tlast_len_mismatch =
            axis_fire &&
            s_axis_tlast &&
            (expected_beats != 0) &&
            (next_captured_beats != expected_beats);
    end

    always_comb begin
        missing_tlast_at_expected_end =
            axis_fire &&
            !s_axis_tlast &&
            (expected_beats != 0) &&
            (next_captured_beats >= expected_beats);
    end

    always_comb begin
        terminal_error =
            hit_capacity ||
            tlast_len_mismatch ||
            missing_tlast_at_expected_end;
    end

    always_comb begin
        terminal_success =
            axis_fire &&
            s_axis_tlast &&
            !terminal_error;
    end

    always_comb begin
        terminal_event = terminal_error || terminal_success;
    end

    // ------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------
    always_comb begin
        busy = (state == S_CAPTURE);
    end

    always_comb begin
        done = (state == S_DONE_PULSE);
    end

    always_comb begin
        s_axis_tready = (state == S_CAPTURE);
    end

    // ------------------------------------------------------------
    // Readback port
    // ------------------------------------------------------------
    always_comb begin
        rd_data = '0;

        if (rd_en) begin
            if (rd_addr < CAPTURE_DEPTH) begin
                rd_data = capture_mem[rd_addr];
            end
        end
    end

    // ------------------------------------------------------------
    // Next-state logic
    // ------------------------------------------------------------
    always_comb begin
        state_n = state;

        case (state)
            S_IDLE: begin
                if (start) begin
                    state_n = S_CAPTURE;
                end
            end

            S_CAPTURE: begin
                if (terminal_event) begin
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
            state          <= S_IDLE;
            captured_beats <= '0;
            tlast_seen     <= 1'b0;
            error          <= 1'b0;
        end
        else begin
            state <= state_n;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        captured_beats <= '0;
                        tlast_seen     <= 1'b0;
                        error          <= 1'b0;
                    end
                end

                S_CAPTURE: begin
                    if (axis_fire) begin
                        if (!hit_capacity) begin
                            capture_mem[captured_beats[CAPTURE_ADDR_WIDTH-1:0]] <= s_axis_tdata;
                            captured_beats <= next_captured_beats;
                        end

                        if (s_axis_tlast) begin
                            tlast_seen <= 1'b1;
                        end

                        if (terminal_error) begin
                            error <= 1'b1;
                        end
                    end
                end

                S_DONE_PULSE: begin
                    // hold sticky status until next start
                end

                default: begin
                    // no-op
                end
            endcase
        end
    end

endmodule

`endif