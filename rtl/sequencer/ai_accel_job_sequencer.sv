// File: rtl/sequencer/ai_accel_job_sequencer.sv

`ifndef AI_ACCEL_JOB_SEQUENCER_SV
`define AI_ACCEL_JOB_SEQUENCER_SV

module ai_accel_job_sequencer #(
    parameter int ADDR_WIDTH     = 32,
    parameter int GEMM_DIM_WIDTH = 8
)(
    input  logic clk,
    input  logic rst_n,

    // ------------------------------------------------------------
    // Job command pulses from the CSR block
    // ------------------------------------------------------------
    input  logic job_start_pulse,
    input  logic job_clear_done_pulse,
    input  logic job_clear_error_pulse,
    input  logic job_clear_perf_pulse,

    // ------------------------------------------------------------
    // Job descriptor from CSR storage
    // ------------------------------------------------------------
    input  logic [1:0] job_input_mode,
    input  logic [1:0] job_output_mode,
    input  logic       job_accumulate_enable,

    input  logic [ADDR_WIDTH-1:0]     job_base_addr_a,
    input  logic [ADDR_WIDTH-1:0]     job_base_addr_b,
    input  logic [ADDR_WIDTH-1:0]     job_base_addr_c,
    input  logic [GEMM_DIM_WIDTH-1:0] job_dim_m,
    input  logic [GEMM_DIM_WIDTH-1:0] job_dim_n,
    input  logic [GEMM_DIM_WIDTH-1:0] job_dim_k,

    input  logic [ADDR_WIDTH-1:0] job_a_src_base_addr,
    input  logic [ADDR_WIDTH-1:0] job_a_dst_base_addr,
    input  logic [31:0]           job_a_load_beats,

    input  logic [ADDR_WIDTH-1:0] job_b_src_base_addr,
    input  logic [ADDR_WIDTH-1:0] job_b_dst_base_addr,
    input  logic [31:0]           job_b_load_beats,

    input  logic [ADDR_WIDTH-1:0] job_store_src_base_addr,
    input  logic [ADDR_WIDTH-1:0] job_store_dst_base_addr,
    input  logic [31:0]           job_store_byte_count,

    // ------------------------------------------------------------
    // Existing subsystem status inputs
    // ------------------------------------------------------------
    input  logic acc_busy,
    input  logic acc_done,

    input  logic dma_load_busy,
    input  logic dma_load_done,
    input  logic dma_load_error,

    input  logic axis_load_busy,
    input  logic axis_load_done,
    input  logic axis_load_error,

    input  logic ds_load_busy,
    input  logic ds_load_done,
    input  logic ds_load_error,

    input  logic dma_store_busy,
    input  logic dma_store_done,
    input  logic dma_store_error,

    input  logic [31:0] gemm_perf_busy_cycles,
    input  logic [31:0] gemm_perf_mac_count,
    input  logic [31:0] gemm_perf_output_count,

    // ------------------------------------------------------------
    // Sequencer-generated control/config outputs to ai_accel_subsys
    // ------------------------------------------------------------
    output logic                  acc_start_pulse,
    output logic                  gemm_input_stream_mode,
    output logic                  accumulate_enable,
    output logic [ADDR_WIDTH-1:0] base_addr_a,
    output logic [ADDR_WIDTH-1:0] base_addr_b,
    output logic [ADDR_WIDTH-1:0] base_addr_c,
    output logic [GEMM_DIM_WIDTH-1:0] dim_m,
    output logic [GEMM_DIM_WIDTH-1:0] dim_n,
    output logic [GEMM_DIM_WIDTH-1:0] dim_k,

    output logic                  dma_load_start_pulse,
    output logic [ADDR_WIDTH-1:0] dma_src_base_addr,
    output logic [ADDR_WIDTH-1:0] dma_dst_base_addr,
    output logic [31:0]           dma_load_beats,

    output logic                  axis_load_start_pulse,
    output logic [ADDR_WIDTH-1:0] axis_src_base_addr,
    output logic [ADDR_WIDTH-1:0] axis_dst_base_addr,
    output logic [31:0]           axis_load_beats,

    output logic                  ds_load_start_pulse,
    output logic [ADDR_WIDTH-1:0] ds_src_base_addr,
    output logic [ADDR_WIDTH-1:0] ds_dst_base_addr,
    output logic [31:0]           ds_load_beats,
    output logic                  ds_operand_sel,

    output logic                  dma_store_start_pulse,
    output logic [ADDR_WIDTH-1:0] dma_store_src_base_addr,
    output logic [ADDR_WIDTH-1:0] dma_store_dst_base_addr,
    output logic [31:0]           dma_store_byte_count,

    // ------------------------------------------------------------
    // Job status outputs back to the CSR block
    // ------------------------------------------------------------
    output logic                  job_busy,
    output logic                  job_done,
    output logic                  job_gemm_done,
    output logic                  job_store_done,

    output logic                  job_dma_load_error,
    output logic                  job_axis_load_error,
    output logic                  job_ds_load_error,
    output logic                  job_dma_store_error,
    output logic                  job_sequence_error,

    output logic [31:0]           job_state,
    output logic [31:0]           job_perf_busy_cycles,
    output logic [31:0]           job_perf_mac_count,
    output logic [31:0]           job_perf_output_count
);

    // ------------------------------------------------------------
    // Job mode encodings
    // ------------------------------------------------------------
    localparam logic [1:0] JOB_INPUT_HOST_PRELOADED = 2'd0;
    localparam logic [1:0] JOB_INPUT_DMA_LOAD       = 2'd1;
    localparam logic [1:0] JOB_INPUT_AXIS_PRELOAD   = 2'd2;
    localparam logic [1:0] JOB_INPUT_DIRECT_STREAM  = 2'd3;

    localparam logic [1:0] JOB_OUTPUT_HOST_READBACK = 2'd0;
    localparam logic [1:0] JOB_OUTPUT_DMA_STORE     = 2'd1;

    // ------------------------------------------------------------
    // Job state encodings
    // ------------------------------------------------------------
    localparam logic [3:0] JOB_STATE_IDLE         = 4'd0;
    localparam logic [3:0] JOB_STATE_LOAD_A_SETUP = 4'd1;
    localparam logic [3:0] JOB_STATE_LOAD_A_START = 4'd2;
    localparam logic [3:0] JOB_STATE_LOAD_A_WAIT  = 4'd3;
    localparam logic [3:0] JOB_STATE_LOAD_B_SETUP = 4'd4;
    localparam logic [3:0] JOB_STATE_LOAD_B_START = 4'd5;
    localparam logic [3:0] JOB_STATE_LOAD_B_WAIT  = 4'd6;
    localparam logic [3:0] JOB_STATE_GEMM_SETUP   = 4'd7;
    localparam logic [3:0] JOB_STATE_GEMM_START   = 4'd8;
    localparam logic [3:0] JOB_STATE_GEMM_WAIT    = 4'd9;
    localparam logic [3:0] JOB_STATE_STORE_SETUP  = 4'd10;
    localparam logic [3:0] JOB_STATE_STORE_START  = 4'd11;
    localparam logic [3:0] JOB_STATE_STORE_WAIT   = 4'd12;
    localparam logic [3:0] JOB_STATE_DONE         = 4'd13;
    localparam logic [3:0] JOB_STATE_ERROR        = 4'd14;

    // ------------------------------------------------------------
    // Active descriptor snapshot
    // ------------------------------------------------------------
    logic [3:0] state_q;

    logic [1:0] input_mode_q;
    logic [1:0] output_mode_q;
    logic       accumulate_enable_q;

    logic [ADDR_WIDTH-1:0]     base_addr_a_q;
    logic [ADDR_WIDTH-1:0]     base_addr_b_q;
    logic [ADDR_WIDTH-1:0]     base_addr_c_q;
    logic [GEMM_DIM_WIDTH-1:0] dim_m_q;
    logic [GEMM_DIM_WIDTH-1:0] dim_n_q;
    logic [GEMM_DIM_WIDTH-1:0] dim_k_q;

    logic [ADDR_WIDTH-1:0] a_src_base_q;
    logic [ADDR_WIDTH-1:0] a_dst_base_q;
    logic [31:0]           a_load_beats_q;

    logic [ADDR_WIDTH-1:0] b_src_base_q;
    logic [ADDR_WIDTH-1:0] b_dst_base_q;
    logic [31:0]           b_load_beats_q;

    logic [ADDR_WIDTH-1:0] store_src_base_q;
    logic [ADDR_WIDTH-1:0] store_dst_base_q;
    logic [31:0]           store_byte_count_q;

    logic [31:0] perf_busy_cycles_q;
    logic [31:0] perf_mac_count_q;
    logic [31:0] perf_output_count_q;

    logic load_b_stage;
    logic active_load_stage;
    logic output_dma_store_q;

    assign job_busy = (state_q != JOB_STATE_IDLE) &&
                      (state_q != JOB_STATE_DONE) &&
                      (state_q != JOB_STATE_ERROR);

    assign job_state              = {28'h0000_000, state_q};
    assign job_perf_busy_cycles   = perf_busy_cycles_q;
    assign job_perf_mac_count     = perf_mac_count_q;
    assign job_perf_output_count  = perf_output_count_q;

    assign output_dma_store_q = (output_mode_q == JOB_OUTPUT_DMA_STORE);

    always_comb begin
        load_b_stage = (state_q == JOB_STATE_LOAD_B_SETUP) ||
                       (state_q == JOB_STATE_LOAD_B_START) ||
                       (state_q == JOB_STATE_LOAD_B_WAIT);

        active_load_stage = (state_q == JOB_STATE_LOAD_A_SETUP) ||
                            (state_q == JOB_STATE_LOAD_A_START) ||
                            (state_q == JOB_STATE_LOAD_A_WAIT)  ||
                            (state_q == JOB_STATE_LOAD_B_SETUP) ||
                            (state_q == JOB_STATE_LOAD_B_START) ||
                            (state_q == JOB_STATE_LOAD_B_WAIT);
    end

    // ------------------------------------------------------------
    // Continuous config mapping from the active descriptor snapshot
    // ------------------------------------------------------------
    always_comb begin
        gemm_input_stream_mode = (input_mode_q == JOB_INPUT_DIRECT_STREAM);
        accumulate_enable      = accumulate_enable_q;

        base_addr_a = base_addr_a_q;
        base_addr_b = base_addr_b_q;
        base_addr_c = base_addr_c_q;

        dim_m = dim_m_q;
        dim_n = dim_n_q;
        dim_k = dim_k_q;

        dma_src_base_addr = load_b_stage ? b_src_base_q   : a_src_base_q;
        dma_dst_base_addr = load_b_stage ? b_dst_base_q   : a_dst_base_q;
        dma_load_beats    = load_b_stage ? b_load_beats_q : a_load_beats_q;

        axis_src_base_addr = load_b_stage ? b_src_base_q   : a_src_base_q;
        axis_dst_base_addr = load_b_stage ? b_dst_base_q   : a_dst_base_q;
        axis_load_beats    = load_b_stage ? b_load_beats_q : a_load_beats_q;

        ds_src_base_addr = load_b_stage ? b_src_base_q   : a_src_base_q;
        ds_dst_base_addr = load_b_stage ? b_dst_base_q   : a_dst_base_q;
        ds_load_beats    = load_b_stage ? b_load_beats_q : a_load_beats_q;
        ds_operand_sel   = load_b_stage;

        dma_store_src_base_addr = store_src_base_q;
        dma_store_dst_base_addr = store_dst_base_q;
        dma_store_byte_count    = store_byte_count_q;
    end

    // ------------------------------------------------------------
    // Sequencer FSM
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= JOB_STATE_IDLE;

            input_mode_q         <= JOB_INPUT_HOST_PRELOADED;
            output_mode_q        <= JOB_OUTPUT_HOST_READBACK;
            accumulate_enable_q  <= 1'b0;

            base_addr_a_q <= '0;
            base_addr_b_q <= '0;
            base_addr_c_q <= '0;
            dim_m_q       <= '0;
            dim_n_q       <= '0;
            dim_k_q       <= '0;

            a_src_base_q   <= '0;
            a_dst_base_q   <= '0;
            a_load_beats_q <= 32'h0000_0000;

            b_src_base_q   <= '0;
            b_dst_base_q   <= '0;
            b_load_beats_q <= 32'h0000_0000;

            store_src_base_q   <= '0;
            store_dst_base_q   <= '0;
            store_byte_count_q <= 32'h0000_0000;

            perf_busy_cycles_q  <= 32'h0000_0000;
            perf_mac_count_q    <= 32'h0000_0000;
            perf_output_count_q <= 32'h0000_0000;

            acc_start_pulse       <= 1'b0;
            dma_load_start_pulse  <= 1'b0;
            axis_load_start_pulse <= 1'b0;
            ds_load_start_pulse   <= 1'b0;
            dma_store_start_pulse <= 1'b0;

            job_done            <= 1'b0;
            job_gemm_done       <= 1'b0;
            job_store_done      <= 1'b0;
            job_dma_load_error  <= 1'b0;
            job_axis_load_error <= 1'b0;
            job_ds_load_error   <= 1'b0;
            job_dma_store_error <= 1'b0;
            job_sequence_error  <= 1'b0;
        end
        else begin
            acc_start_pulse       <= 1'b0;
            dma_load_start_pulse  <= 1'b0;
            axis_load_start_pulse <= 1'b0;
            ds_load_start_pulse   <= 1'b0;
            dma_store_start_pulse <= 1'b0;

            job_done            <= 1'b0;
            job_gemm_done       <= 1'b0;
            job_store_done      <= 1'b0;
            job_dma_load_error  <= 1'b0;
            job_axis_load_error <= 1'b0;
            job_ds_load_error   <= 1'b0;
            job_dma_store_error <= 1'b0;
            job_sequence_error  <= 1'b0;

            if (job_clear_perf_pulse && !job_busy) begin
                perf_busy_cycles_q  <= 32'h0000_0000;
                perf_mac_count_q    <= 32'h0000_0000;
                perf_output_count_q <= 32'h0000_0000;
            end

            if (job_clear_done_pulse && (state_q == JOB_STATE_DONE)) begin
                state_q <= JOB_STATE_IDLE;
            end
            else if (job_clear_error_pulse && (state_q == JOB_STATE_ERROR)) begin
                state_q <= JOB_STATE_IDLE;
            end
            else begin
                unique case (state_q)
                    JOB_STATE_IDLE,
                    JOB_STATE_DONE,
                    JOB_STATE_ERROR: begin
                        if (job_start_pulse) begin
                            input_mode_q        <= job_input_mode;
                            output_mode_q       <= job_output_mode;
                            accumulate_enable_q <= job_accumulate_enable;

                            base_addr_a_q <= job_base_addr_a;
                            base_addr_b_q <= job_base_addr_b;
                            base_addr_c_q <= job_base_addr_c;
                            dim_m_q       <= job_dim_m;
                            dim_n_q       <= job_dim_n;
                            dim_k_q       <= job_dim_k;

                            a_src_base_q   <= job_a_src_base_addr;
                            a_dst_base_q   <= job_a_dst_base_addr;
                            a_load_beats_q <= job_a_load_beats;

                            b_src_base_q   <= job_b_src_base_addr;
                            b_dst_base_q   <= job_b_dst_base_addr;
                            b_load_beats_q <= job_b_load_beats;

                            store_src_base_q   <= job_store_src_base_addr;
                            store_dst_base_q   <= job_store_dst_base_addr;
                            store_byte_count_q <= job_store_byte_count;

                            perf_busy_cycles_q  <= 32'h0000_0000;
                            perf_mac_count_q    <= 32'h0000_0000;
                            perf_output_count_q <= 32'h0000_0000;

                            if (job_input_mode == JOB_INPUT_HOST_PRELOADED) begin
                                state_q <= JOB_STATE_GEMM_SETUP;
                            end
                            else begin
                                state_q <= JOB_STATE_LOAD_A_SETUP;
                            end
                        end
                    end

                    JOB_STATE_LOAD_A_SETUP: begin
                        if (!active_load_stage) begin
                            state_q <= JOB_STATE_ERROR;
                            job_sequence_error <= 1'b1;
                        end
                        else begin
                            state_q <= JOB_STATE_LOAD_A_START;
                        end
                    end

                    JOB_STATE_LOAD_A_START: begin
                        unique case (input_mode_q)
                            JOB_INPUT_DMA_LOAD: begin
                                if (dma_load_busy || dma_store_busy) begin
                                    state_q <= JOB_STATE_ERROR;
                                    job_sequence_error <= 1'b1;
                                end
                                else begin
                                    dma_load_start_pulse <= 1'b1;
                                    state_q <= JOB_STATE_LOAD_A_WAIT;
                                end
                            end

                            JOB_INPUT_AXIS_PRELOAD: begin
                                if (axis_load_busy || acc_busy) begin
                                    state_q <= JOB_STATE_ERROR;
                                    job_sequence_error <= 1'b1;
                                end
                                else begin
                                    axis_load_start_pulse <= 1'b1;
                                    state_q <= JOB_STATE_LOAD_A_WAIT;
                                end
                            end

                            JOB_INPUT_DIRECT_STREAM: begin
                                if (ds_load_busy || acc_busy) begin
                                    state_q <= JOB_STATE_ERROR;
                                    job_sequence_error <= 1'b1;
                                end
                                else begin
                                    ds_load_start_pulse <= 1'b1;
                                    state_q <= JOB_STATE_LOAD_A_WAIT;
                                end
                            end

                            default: begin
                                state_q <= JOB_STATE_ERROR;
                                job_sequence_error <= 1'b1;
                            end
                        endcase
                    end

                    JOB_STATE_LOAD_A_WAIT: begin
                        unique case (input_mode_q)
                            JOB_INPUT_DMA_LOAD: begin
                                if (dma_load_error) begin
                                    state_q <= JOB_STATE_ERROR;
                                    job_dma_load_error <= 1'b1;
                                end
                                else if (dma_load_done) begin
                                    state_q <= JOB_STATE_LOAD_B_SETUP;
                                end
                            end

                            JOB_INPUT_AXIS_PRELOAD: begin
                                if (axis_load_error) begin
                                    state_q <= JOB_STATE_ERROR;
                                    job_axis_load_error <= 1'b1;
                                end
                                else if (axis_load_done) begin
                                    state_q <= JOB_STATE_LOAD_B_SETUP;
                                end
                            end

                            JOB_INPUT_DIRECT_STREAM: begin
                                if (ds_load_error) begin
                                    state_q <= JOB_STATE_ERROR;
                                    job_ds_load_error <= 1'b1;
                                end
                                else if (ds_load_done) begin
                                    state_q <= JOB_STATE_LOAD_B_SETUP;
                                end
                            end

                            default: begin
                                state_q <= JOB_STATE_ERROR;
                                job_sequence_error <= 1'b1;
                            end
                        endcase
                    end

                    JOB_STATE_LOAD_B_SETUP: begin
                        state_q <= JOB_STATE_LOAD_B_START;
                    end

                    JOB_STATE_LOAD_B_START: begin
                        unique case (input_mode_q)
                            JOB_INPUT_DMA_LOAD: begin
                                if (dma_load_busy || dma_store_busy) begin
                                    state_q <= JOB_STATE_ERROR;
                                    job_sequence_error <= 1'b1;
                                end
                                else begin
                                    dma_load_start_pulse <= 1'b1;
                                    state_q <= JOB_STATE_LOAD_B_WAIT;
                                end
                            end

                            JOB_INPUT_AXIS_PRELOAD: begin
                                if (axis_load_busy || acc_busy) begin
                                    state_q <= JOB_STATE_ERROR;
                                    job_sequence_error <= 1'b1;
                                end
                                else begin
                                    axis_load_start_pulse <= 1'b1;
                                    state_q <= JOB_STATE_LOAD_B_WAIT;
                                end
                            end

                            JOB_INPUT_DIRECT_STREAM: begin
                                if (ds_load_busy || acc_busy) begin
                                    state_q <= JOB_STATE_ERROR;
                                    job_sequence_error <= 1'b1;
                                end
                                else begin
                                    ds_load_start_pulse <= 1'b1;
                                    state_q <= JOB_STATE_LOAD_B_WAIT;
                                end
                            end

                            default: begin
                                state_q <= JOB_STATE_ERROR;
                                job_sequence_error <= 1'b1;
                            end
                        endcase
                    end

                    JOB_STATE_LOAD_B_WAIT: begin
                        unique case (input_mode_q)
                            JOB_INPUT_DMA_LOAD: begin
                                if (dma_load_error) begin
                                    state_q <= JOB_STATE_ERROR;
                                    job_dma_load_error <= 1'b1;
                                end
                                else if (dma_load_done) begin
                                    state_q <= JOB_STATE_GEMM_SETUP;
                                end
                            end

                            JOB_INPUT_AXIS_PRELOAD: begin
                                if (axis_load_error) begin
                                    state_q <= JOB_STATE_ERROR;
                                    job_axis_load_error <= 1'b1;
                                end
                                else if (axis_load_done) begin
                                    state_q <= JOB_STATE_GEMM_SETUP;
                                end
                            end

                            JOB_INPUT_DIRECT_STREAM: begin
                                if (ds_load_error) begin
                                    state_q <= JOB_STATE_ERROR;
                                    job_ds_load_error <= 1'b1;
                                end
                                else if (ds_load_done) begin
                                    state_q <= JOB_STATE_GEMM_SETUP;
                                end
                            end

                            default: begin
                                state_q <= JOB_STATE_ERROR;
                                job_sequence_error <= 1'b1;
                            end
                        endcase
                    end

                    JOB_STATE_GEMM_SETUP: begin
                        state_q <= JOB_STATE_GEMM_START;
                    end

                    JOB_STATE_GEMM_START: begin
                        if (acc_busy || axis_load_busy || ds_load_busy) begin
                            state_q <= JOB_STATE_ERROR;
                            job_sequence_error <= 1'b1;
                        end
                        else begin
                            acc_start_pulse <= 1'b1;
                            state_q <= JOB_STATE_GEMM_WAIT;
                        end
                    end

                    JOB_STATE_GEMM_WAIT: begin
                        if (acc_done) begin
                            job_gemm_done <= 1'b1;

                            perf_busy_cycles_q  <= gemm_perf_busy_cycles;
                            perf_mac_count_q    <= gemm_perf_mac_count;
                            perf_output_count_q <= gemm_perf_output_count;

                            if (output_dma_store_q) begin
                                state_q <= JOB_STATE_STORE_SETUP;
                            end
                            else begin
                                job_done <= 1'b1;
                                state_q  <= JOB_STATE_DONE;
                            end
                        end
                    end

                    JOB_STATE_STORE_SETUP: begin
                        state_q <= JOB_STATE_STORE_START;
                    end

                    JOB_STATE_STORE_START: begin
                        if (dma_store_busy || dma_load_busy) begin
                            state_q <= JOB_STATE_ERROR;
                            job_sequence_error <= 1'b1;
                        end
                        else begin
                            dma_store_start_pulse <= 1'b1;
                            state_q <= JOB_STATE_STORE_WAIT;
                        end
                    end

                    JOB_STATE_STORE_WAIT: begin
                        if (dma_store_error) begin
                            state_q <= JOB_STATE_ERROR;
                            job_dma_store_error <= 1'b1;
                        end
                        else if (dma_store_done) begin
                            job_store_done <= 1'b1;
                            job_done       <= 1'b1;
                            state_q        <= JOB_STATE_DONE;
                        end
                    end

                    default: begin
                        state_q <= JOB_STATE_ERROR;
                        job_sequence_error <= 1'b1;
                    end
                endcase
            end
        end
    end

endmodule

`endif
