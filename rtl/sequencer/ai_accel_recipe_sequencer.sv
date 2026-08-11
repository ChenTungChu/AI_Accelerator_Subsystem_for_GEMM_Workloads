// File: rtl/sequencer/ai_accel_recipe_sequencer.sv

`ifndef AI_ACCEL_RECIPE_SEQUENCER_SV
`define AI_ACCEL_RECIPE_SEQUENCER_SV

module ai_accel_recipe_sequencer #(
    parameter int ADDR_WIDTH             = 32,
    parameter int GEMM_DIM_WIDTH         = 8,
    parameter int P16_RECIPE_QUEUE_DEPTH = 4
)(
    input  logic clk,
    input  logic rst_n,

    // ------------------------------------------------------------
    // Recipe command pulses from the CSR block
    // ------------------------------------------------------------
    input  logic recipe_start_pulse,
    input  logic recipe_clear_done_pulse,
    input  logic recipe_clear_error_pulse,
    input  logic recipe_clear_perf_pulse,
    input  logic recipe_clear_slot_status_pulse,

    // ------------------------------------------------------------
    // Recipe control policy from CSR storage
    // ------------------------------------------------------------
    input  logic [3:0] recipe_count,
    input  logic [3:0] recipe_start_slot,
    input  logic       recipe_stop_on_error,
    input  logic       recipe_clear_job_sticky_each_slot,
    input  logic       recipe_accumulate_perf,

    // ------------------------------------------------------------
    // CSR-resident recipe descriptor slots
    // ------------------------------------------------------------
    input  logic [31:0]               recipe_slot_control [P16_RECIPE_QUEUE_DEPTH],
    input  logic [ADDR_WIDTH-1:0]     recipe_slot_base_addr_a [P16_RECIPE_QUEUE_DEPTH],
    input  logic [ADDR_WIDTH-1:0]     recipe_slot_base_addr_b [P16_RECIPE_QUEUE_DEPTH],
    input  logic [ADDR_WIDTH-1:0]     recipe_slot_base_addr_c [P16_RECIPE_QUEUE_DEPTH],
    input  logic [GEMM_DIM_WIDTH-1:0] recipe_slot_dim_m [P16_RECIPE_QUEUE_DEPTH],
    input  logic [GEMM_DIM_WIDTH-1:0] recipe_slot_dim_n [P16_RECIPE_QUEUE_DEPTH],
    input  logic [GEMM_DIM_WIDTH-1:0] recipe_slot_dim_k [P16_RECIPE_QUEUE_DEPTH],
    input  logic [ADDR_WIDTH-1:0]     recipe_slot_a_src_base_addr [P16_RECIPE_QUEUE_DEPTH],
    input  logic [ADDR_WIDTH-1:0]     recipe_slot_a_dst_base_addr [P16_RECIPE_QUEUE_DEPTH],
    input  logic [31:0]               recipe_slot_a_load_beats [P16_RECIPE_QUEUE_DEPTH],
    input  logic [ADDR_WIDTH-1:0]     recipe_slot_b_src_base_addr [P16_RECIPE_QUEUE_DEPTH],
    input  logic [ADDR_WIDTH-1:0]     recipe_slot_b_dst_base_addr [P16_RECIPE_QUEUE_DEPTH],
    input  logic [31:0]               recipe_slot_b_load_beats [P16_RECIPE_QUEUE_DEPTH],
    input  logic [ADDR_WIDTH-1:0]     recipe_slot_store_src_base_addr [P16_RECIPE_QUEUE_DEPTH],
    input  logic [ADDR_WIDTH-1:0]     recipe_slot_store_dst_base_addr [P16_RECIPE_QUEUE_DEPTH],
    input  logic [31:0]               recipe_slot_store_byte_count [P16_RECIPE_QUEUE_DEPTH],
    input  logic [31:0]               recipe_slot_user_tag [P16_RECIPE_QUEUE_DEPTH],

    // ------------------------------------------------------------
    // Existing P15 single-job worker status
    // ------------------------------------------------------------
    input  logic job_busy,
    input  logic job_done,
    input  logic job_gemm_done,
    input  logic job_store_done,

    input  logic job_dma_load_error,
    input  logic job_axis_load_error,
    input  logic job_ds_load_error,
    input  logic job_dma_store_error,
    input  logic job_sequence_error,

    input  logic [31:0] job_state,
    input  logic [31:0] job_perf_busy_cycles,
    input  logic [31:0] job_perf_mac_count,
    input  logic [31:0] job_perf_output_count,

    // ------------------------------------------------------------
    // Recipe-generated P15 job worker command / descriptor
    // ------------------------------------------------------------
    output logic                  job_start_pulse,
    output logic                  job_clear_done_pulse,
    output logic                  job_clear_error_pulse,
    output logic                  job_clear_perf_pulse,

    output logic [1:0]            job_input_mode,
    output logic [1:0]            job_output_mode,
    output logic                  job_accumulate_enable,

    output logic [ADDR_WIDTH-1:0] job_base_addr_a,
    output logic [ADDR_WIDTH-1:0] job_base_addr_b,
    output logic [ADDR_WIDTH-1:0] job_base_addr_c,
    output logic [GEMM_DIM_WIDTH-1:0] job_dim_m,
    output logic [GEMM_DIM_WIDTH-1:0] job_dim_n,
    output logic [GEMM_DIM_WIDTH-1:0] job_dim_k,

    output logic [ADDR_WIDTH-1:0] job_a_src_base_addr,
    output logic [ADDR_WIDTH-1:0] job_a_dst_base_addr,
    output logic [31:0]           job_a_load_beats,

    output logic [ADDR_WIDTH-1:0] job_b_src_base_addr,
    output logic [ADDR_WIDTH-1:0] job_b_dst_base_addr,
    output logic [31:0]           job_b_load_beats,

    output logic [ADDR_WIDTH-1:0] job_store_src_base_addr,
    output logic [ADDR_WIDTH-1:0] job_store_dst_base_addr,
    output logic [31:0]           job_store_byte_count,

    // ------------------------------------------------------------
    // Recipe status outputs back to the CSR block
    // ------------------------------------------------------------
    output logic                  recipe_busy,
    output logic                  recipe_done,
    output logic                  recipe_all_slots_done,
    output logic                  recipe_final_store_done,

    output logic                  recipe_slot_job_error,
    output logic                  recipe_slot_job_reject,
    output logic                  recipe_sequence_error,
    output logic                  recipe_slot_range_error,
    output logic                  recipe_slot_descriptor_error,

    output logic [31:0]           recipe_state,
    output logic [31:0]           recipe_current_slot,
    output logic [31:0]           recipe_completed_count,
    output logic [31:0]           recipe_slot_done_mask,
    output logic [31:0]           recipe_slot_error_mask,
    output logic [31:0]           recipe_slot_reject_mask,
    output logic [31:0]           recipe_perf_busy_cycles,
    output logic [31:0]           recipe_perf_mac_count,
    output logic [31:0]           recipe_perf_output_count
);

    // ------------------------------------------------------------
    // Slot mode encodings.  These mirror P15 JOB_MODE encodings.
    // ------------------------------------------------------------
    localparam logic [1:0] SLOT_INPUT_HOST_PRELOADED = 2'd0;
    localparam logic [1:0] SLOT_INPUT_DMA_LOAD       = 2'd1;
    localparam logic [1:0] SLOT_INPUT_AXIS_PRELOAD   = 2'd2;
    localparam logic [1:0] SLOT_INPUT_DIRECT_STREAM  = 2'd3;

    localparam logic [1:0] SLOT_OUTPUT_HOST_READBACK = 2'd0;
    localparam logic [1:0] SLOT_OUTPUT_DMA_STORE     = 2'd1;

    // ------------------------------------------------------------
    // Recipe state encodings
    // ------------------------------------------------------------
    localparam logic [3:0] RECIPE_STATE_IDLE           = 4'd0;
    localparam logic [3:0] RECIPE_STATE_VALIDATE       = 4'd2;
    localparam logic [3:0] RECIPE_STATE_DISPATCH_SETUP = 4'd3;
    localparam logic [3:0] RECIPE_STATE_DISPATCH_START = 4'd4;
    localparam logic [3:0] RECIPE_STATE_JOB_WAIT       = 4'd5;
    localparam logic [3:0] RECIPE_STATE_SLOT_COMPLETE  = 4'd6;
    localparam logic [3:0] RECIPE_STATE_ADVANCE        = 4'd7;
    localparam logic [3:0] RECIPE_STATE_DONE           = 4'd8;
    localparam logic [3:0] RECIPE_STATE_ERROR          = 4'd9;

    // ------------------------------------------------------------
    // P15 job state encodings used only for defensive error checking.
    // ------------------------------------------------------------
    localparam logic [3:0] JOB_STATE_ERROR = 4'd14;

    localparam logic [3:0] P16_RECIPE_QUEUE_DEPTH_U4 = P16_RECIPE_QUEUE_DEPTH;
    localparam logic [4:0] P16_RECIPE_QUEUE_DEPTH_U5 = P16_RECIPE_QUEUE_DEPTH;

    // ------------------------------------------------------------
    // Active recipe snapshot
    // ------------------------------------------------------------
    logic [3:0] state_q;
    logic [3:0] recipe_count_q;
    logic [3:0] recipe_start_slot_q;
    logic [3:0] current_slot_q;
    logic [3:0] final_slot_q;

    logic stop_on_error_q;
    logic clear_job_sticky_each_slot_q;
    logic accumulate_perf_q;

    logic [31:0]               slot_control_q [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     slot_base_addr_a_q [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     slot_base_addr_b_q [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     slot_base_addr_c_q [P16_RECIPE_QUEUE_DEPTH];
    logic [GEMM_DIM_WIDTH-1:0] slot_dim_m_q [P16_RECIPE_QUEUE_DEPTH];
    logic [GEMM_DIM_WIDTH-1:0] slot_dim_n_q [P16_RECIPE_QUEUE_DEPTH];
    logic [GEMM_DIM_WIDTH-1:0] slot_dim_k_q [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     slot_a_src_base_addr_q [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     slot_a_dst_base_addr_q [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0]               slot_a_load_beats_q [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     slot_b_src_base_addr_q [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     slot_b_dst_base_addr_q [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0]               slot_b_load_beats_q [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     slot_store_src_base_addr_q [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     slot_store_dst_base_addr_q [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0]               slot_store_byte_count_q [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0]               slot_user_tag_q [P16_RECIPE_QUEUE_DEPTH];

    logic [31:0] slot_done_mask_q;
    logic [31:0] slot_error_mask_q;
    logic [31:0] slot_reject_mask_q;

    logic [31:0] completed_count_q;
    logic        done_pulse_pending_q;
    logic        final_store_done_pending_q;
    logic [31:0] perf_busy_cycles_q;
    logic [31:0] perf_mac_count_q;
    logic [31:0] perf_output_count_q;

    logic [4:0] selected_range_end;
    logic selected_range_valid;
    logic current_slot_valid;
    logic current_slot_is_final;
    logic current_slot_output_dma_store;
    logic current_slot_desc_valid;
    logic any_job_error;

    assign recipe_busy = (state_q != RECIPE_STATE_IDLE) &&
                         (state_q != RECIPE_STATE_DONE) &&
                         (state_q != RECIPE_STATE_ERROR);

    assign recipe_state             = {28'h0000_000, state_q};
    assign recipe_current_slot      = {28'h0000_000, current_slot_q};
    assign recipe_completed_count   = completed_count_q;
    assign recipe_slot_done_mask    = slot_done_mask_q;
    assign recipe_slot_error_mask   = slot_error_mask_q;
    assign recipe_slot_reject_mask  = slot_reject_mask_q;
    assign recipe_perf_busy_cycles  = perf_busy_cycles_q;
    assign recipe_perf_mac_count    = perf_mac_count_q;
    assign recipe_perf_output_count = perf_output_count_q;

    // Keep the active-snapshot range check consistent with the CSR
    // prevalidation and prevent 4-bit start_slot + count wraparound.
    assign selected_range_end = {1'b0, recipe_start_slot_q} +
                                {1'b0, recipe_count_q};
    assign selected_range_valid = (recipe_count_q != 4'd0) &&
                                  (recipe_start_slot_q < P16_RECIPE_QUEUE_DEPTH_U4) &&
                                  (selected_range_end <= P16_RECIPE_QUEUE_DEPTH_U5);

    assign current_slot_valid = (current_slot_q < P16_RECIPE_QUEUE_DEPTH_U4);
    assign current_slot_is_final = (current_slot_q == final_slot_q);
    assign current_slot_output_dma_store = current_slot_valid &&
                                           (slot_control_q[current_slot_q][4:3] == SLOT_OUTPUT_DMA_STORE);

    assign any_job_error = job_dma_load_error  ||
                           job_axis_load_error ||
                           job_ds_load_error   ||
                           job_dma_store_error ||
                           job_sequence_error  ||
                           (job_state[3:0] == JOB_STATE_ERROR);

    // ------------------------------------------------------------
    // Current slot descriptor validity check
    // ------------------------------------------------------------
    always_comb begin
        current_slot_desc_valid = 1'b0;

        if (current_slot_valid && slot_control_q[current_slot_q][0]) begin
            current_slot_desc_valid = 1'b1;

            if (slot_control_q[current_slot_q][4:3] > SLOT_OUTPUT_DMA_STORE) begin
                current_slot_desc_valid = 1'b0;
            end

            if ((slot_dim_m_q[current_slot_q] == '0) ||
                (slot_dim_n_q[current_slot_q] == '0) ||
                (slot_dim_k_q[current_slot_q] == '0)) begin
                current_slot_desc_valid = 1'b0;
            end

            if ((slot_control_q[current_slot_q][2:1] != SLOT_INPUT_HOST_PRELOADED) &&
                (slot_a_load_beats_q[current_slot_q] == 32'h0000_0000)) begin
                current_slot_desc_valid = 1'b0;
            end

            if ((slot_control_q[current_slot_q][2:1] != SLOT_INPUT_HOST_PRELOADED) &&
                (slot_b_load_beats_q[current_slot_q] == 32'h0000_0000)) begin
                current_slot_desc_valid = 1'b0;
            end

            if ((slot_control_q[current_slot_q][4:3] == SLOT_OUTPUT_DMA_STORE) &&
                (slot_store_byte_count_q[current_slot_q] == 32'h0000_0000)) begin
                current_slot_desc_valid = 1'b0;
            end
        end
    end

    // ------------------------------------------------------------
    // Continuous dispatch mapping from selected snapshot slot
    // ------------------------------------------------------------
    always_comb begin
        job_input_mode        = SLOT_INPUT_HOST_PRELOADED;
        job_output_mode       = SLOT_OUTPUT_HOST_READBACK;
        job_accumulate_enable = 1'b0;

        job_base_addr_a = '0;
        job_base_addr_b = '0;
        job_base_addr_c = '0;
        job_dim_m       = '0;
        job_dim_n       = '0;
        job_dim_k       = '0;

        job_a_src_base_addr   = '0;
        job_a_dst_base_addr   = '0;
        job_a_load_beats      = 32'h0000_0000;
        job_b_src_base_addr   = '0;
        job_b_dst_base_addr   = '0;
        job_b_load_beats      = 32'h0000_0000;
        job_store_src_base_addr = '0;
        job_store_dst_base_addr = '0;
        job_store_byte_count    = 32'h0000_0000;

        if (current_slot_valid) begin
            job_input_mode        = slot_control_q[current_slot_q][2:1];
            job_output_mode       = slot_control_q[current_slot_q][4:3];
            job_accumulate_enable = slot_control_q[current_slot_q][5];

            job_base_addr_a = slot_base_addr_a_q[current_slot_q];
            job_base_addr_b = slot_base_addr_b_q[current_slot_q];
            job_base_addr_c = slot_base_addr_c_q[current_slot_q];
            job_dim_m       = slot_dim_m_q[current_slot_q];
            job_dim_n       = slot_dim_n_q[current_slot_q];
            job_dim_k       = slot_dim_k_q[current_slot_q];

            job_a_src_base_addr     = slot_a_src_base_addr_q[current_slot_q];
            job_a_dst_base_addr     = slot_a_dst_base_addr_q[current_slot_q];
            job_a_load_beats        = slot_a_load_beats_q[current_slot_q];
            job_b_src_base_addr     = slot_b_src_base_addr_q[current_slot_q];
            job_b_dst_base_addr     = slot_b_dst_base_addr_q[current_slot_q];
            job_b_load_beats        = slot_b_load_beats_q[current_slot_q];
            job_store_src_base_addr = slot_store_src_base_addr_q[current_slot_q];
            job_store_dst_base_addr = slot_store_dst_base_addr_q[current_slot_q];
            job_store_byte_count    = slot_store_byte_count_q[current_slot_q];
        end
    end

    // ------------------------------------------------------------
    // Recipe FSM
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= RECIPE_STATE_IDLE;

            recipe_count_q      <= 4'd0;
            recipe_start_slot_q <= 4'd0;
            current_slot_q      <= 4'd0;
            final_slot_q        <= 4'd0;

            stop_on_error_q <= 1'b1;
            clear_job_sticky_each_slot_q <= 1'b1;
            accumulate_perf_q <= 1'b1;

            for (int unsigned slot_i = 0; slot_i < P16_RECIPE_QUEUE_DEPTH; slot_i++) begin
                slot_control_q[slot_i] <= 32'h0000_0000;
                slot_base_addr_a_q[slot_i] <= '0;
                slot_base_addr_b_q[slot_i] <= '0;
                slot_base_addr_c_q[slot_i] <= '0;
                slot_dim_m_q[slot_i] <= '0;
                slot_dim_n_q[slot_i] <= '0;
                slot_dim_k_q[slot_i] <= '0;
                slot_a_src_base_addr_q[slot_i] <= '0;
                slot_a_dst_base_addr_q[slot_i] <= '0;
                slot_a_load_beats_q[slot_i] <= 32'h0000_0000;
                slot_b_src_base_addr_q[slot_i] <= '0;
                slot_b_dst_base_addr_q[slot_i] <= '0;
                slot_b_load_beats_q[slot_i] <= 32'h0000_0000;
                slot_store_src_base_addr_q[slot_i] <= '0;
                slot_store_dst_base_addr_q[slot_i] <= '0;
                slot_store_byte_count_q[slot_i] <= 32'h0000_0000;
                slot_user_tag_q[slot_i] <= 32'h0000_0000;
            end

            slot_done_mask_q   <= 32'h0000_0000;
            slot_error_mask_q  <= 32'h0000_0000;
            slot_reject_mask_q <= 32'h0000_0000;

            completed_count_q   <= 32'h0000_0000;
            done_pulse_pending_q <= 1'b0;
            final_store_done_pending_q <= 1'b0;
            perf_busy_cycles_q  <= 32'h0000_0000;
            perf_mac_count_q    <= 32'h0000_0000;
            perf_output_count_q <= 32'h0000_0000;

            job_start_pulse       <= 1'b0;
            job_clear_done_pulse  <= 1'b0;
            job_clear_error_pulse <= 1'b0;
            job_clear_perf_pulse  <= 1'b0;

            recipe_done                  <= 1'b0;
            recipe_all_slots_done        <= 1'b0;
            recipe_final_store_done      <= 1'b0;
            recipe_slot_job_error        <= 1'b0;
            recipe_slot_job_reject       <= 1'b0;
            recipe_sequence_error        <= 1'b0;
            recipe_slot_range_error      <= 1'b0;
            recipe_slot_descriptor_error <= 1'b0;
        end
        else begin
            job_start_pulse       <= 1'b0;
            job_clear_done_pulse  <= 1'b0;
            job_clear_error_pulse <= 1'b0;
            job_clear_perf_pulse  <= 1'b0;

            recipe_done                  <= 1'b0;
            recipe_all_slots_done        <= 1'b0;
            recipe_final_store_done      <= 1'b0;
            recipe_slot_job_error        <= 1'b0;
            recipe_slot_job_reject       <= 1'b0;
            recipe_sequence_error        <= 1'b0;
            recipe_slot_range_error      <= 1'b0;
            recipe_slot_descriptor_error <= 1'b0;

            if (recipe_clear_perf_pulse && !recipe_busy) begin
                perf_busy_cycles_q  <= 32'h0000_0000;
                perf_mac_count_q    <= 32'h0000_0000;
                perf_output_count_q <= 32'h0000_0000;
            end

            if (recipe_clear_slot_status_pulse && !recipe_busy) begin
                slot_done_mask_q   <= 32'h0000_0000;
                slot_error_mask_q  <= 32'h0000_0000;
                slot_reject_mask_q <= 32'h0000_0000;
            end

            if (recipe_clear_done_pulse && (state_q == RECIPE_STATE_DONE)) begin
                state_q <= RECIPE_STATE_IDLE;
            end
            else if (recipe_clear_error_pulse && (state_q == RECIPE_STATE_ERROR)) begin
                state_q <= RECIPE_STATE_IDLE;
            end
            else begin
                unique case (state_q)
                    RECIPE_STATE_IDLE,
                    RECIPE_STATE_DONE,
                    RECIPE_STATE_ERROR: begin
                        if ((state_q == RECIPE_STATE_DONE) && done_pulse_pending_q) begin
                            recipe_done           <= 1'b1;
                            recipe_all_slots_done <= 1'b1;

                            if (final_store_done_pending_q) begin
                                recipe_final_store_done <= 1'b1;
                            end

                            done_pulse_pending_q <= 1'b0;
                            final_store_done_pending_q <= 1'b0;
                        end
                        else if (recipe_start_pulse) begin
                            recipe_count_q      <= recipe_count;
                            recipe_start_slot_q <= recipe_start_slot;
                            current_slot_q      <= recipe_start_slot;
                            final_slot_q        <= recipe_start_slot + recipe_count - 4'd1;

                            stop_on_error_q <= recipe_stop_on_error;
                            clear_job_sticky_each_slot_q <= recipe_clear_job_sticky_each_slot;
                            accumulate_perf_q <= recipe_accumulate_perf;

                            for (int unsigned slot_i = 0; slot_i < P16_RECIPE_QUEUE_DEPTH; slot_i++) begin
                                slot_control_q[slot_i] <= recipe_slot_control[slot_i];
                                slot_base_addr_a_q[slot_i] <= recipe_slot_base_addr_a[slot_i];
                                slot_base_addr_b_q[slot_i] <= recipe_slot_base_addr_b[slot_i];
                                slot_base_addr_c_q[slot_i] <= recipe_slot_base_addr_c[slot_i];
                                slot_dim_m_q[slot_i] <= recipe_slot_dim_m[slot_i];
                                slot_dim_n_q[slot_i] <= recipe_slot_dim_n[slot_i];
                                slot_dim_k_q[slot_i] <= recipe_slot_dim_k[slot_i];
                                slot_a_src_base_addr_q[slot_i] <= recipe_slot_a_src_base_addr[slot_i];
                                slot_a_dst_base_addr_q[slot_i] <= recipe_slot_a_dst_base_addr[slot_i];
                                slot_a_load_beats_q[slot_i] <= recipe_slot_a_load_beats[slot_i];
                                slot_b_src_base_addr_q[slot_i] <= recipe_slot_b_src_base_addr[slot_i];
                                slot_b_dst_base_addr_q[slot_i] <= recipe_slot_b_dst_base_addr[slot_i];
                                slot_b_load_beats_q[slot_i] <= recipe_slot_b_load_beats[slot_i];
                                slot_store_src_base_addr_q[slot_i] <= recipe_slot_store_src_base_addr[slot_i];
                                slot_store_dst_base_addr_q[slot_i] <= recipe_slot_store_dst_base_addr[slot_i];
                                slot_store_byte_count_q[slot_i] <= recipe_slot_store_byte_count[slot_i];
                                slot_user_tag_q[slot_i] <= recipe_slot_user_tag[slot_i];
                            end

                            slot_done_mask_q   <= 32'h0000_0000;
                            slot_error_mask_q  <= 32'h0000_0000;
                            slot_reject_mask_q <= 32'h0000_0000;
                            completed_count_q  <= 32'h0000_0000;
                            done_pulse_pending_q <= 1'b0;
                            final_store_done_pending_q <= 1'b0;
                            perf_busy_cycles_q <= 32'h0000_0000;
                            perf_mac_count_q   <= 32'h0000_0000;
                            perf_output_count_q <= 32'h0000_0000;

                            state_q <= RECIPE_STATE_VALIDATE;
                        end
                    end

                    RECIPE_STATE_VALIDATE: begin
                        if (!selected_range_valid) begin
                            recipe_slot_range_error <= 1'b1;
                            state_q <= RECIPE_STATE_ERROR;
                        end
                        else if (!current_slot_desc_valid) begin
                            recipe_slot_descriptor_error <= 1'b1;
                            if (current_slot_valid) begin
                                slot_reject_mask_q[current_slot_q] <= 1'b1;
                            end
                            state_q <= RECIPE_STATE_ERROR;
                        end
                        else begin
                            state_q <= RECIPE_STATE_DISPATCH_SETUP;
                        end
                    end

                    RECIPE_STATE_DISPATCH_SETUP: begin
                        if (!current_slot_valid || !current_slot_desc_valid) begin
                            recipe_slot_descriptor_error <= 1'b1;
                            if (current_slot_valid) begin
                                slot_reject_mask_q[current_slot_q] <= 1'b1;
                            end
                            state_q <= RECIPE_STATE_ERROR;
                        end
                        else if (job_busy) begin
                            recipe_sequence_error <= 1'b1;
                            slot_error_mask_q[current_slot_q] <= 1'b1;
                            state_q <= RECIPE_STATE_ERROR;
                        end
                        else begin
                            if (clear_job_sticky_each_slot_q) begin
                                job_clear_done_pulse  <= 1'b1;
                                job_clear_error_pulse <= 1'b1;
                                job_clear_perf_pulse  <= 1'b1;
                            end
                            state_q <= RECIPE_STATE_DISPATCH_START;
                        end
                    end

                    RECIPE_STATE_DISPATCH_START: begin
                        if (job_busy) begin
                            recipe_sequence_error <= 1'b1;
                            slot_error_mask_q[current_slot_q] <= 1'b1;
                            state_q <= RECIPE_STATE_ERROR;
                        end
                        else begin
                            job_start_pulse <= 1'b1;
                            state_q <= RECIPE_STATE_JOB_WAIT;
                        end
                    end

                    RECIPE_STATE_JOB_WAIT: begin
                        if (any_job_error) begin
                            recipe_slot_job_error <= 1'b1;
                            slot_error_mask_q[current_slot_q] <= 1'b1;
                            state_q <= RECIPE_STATE_ERROR;
                        end
                        else if (job_done) begin
                            state_q <= RECIPE_STATE_SLOT_COMPLETE;
                        end
                    end

                    RECIPE_STATE_SLOT_COMPLETE: begin
                        slot_done_mask_q[current_slot_q] <= 1'b1;
                        completed_count_q <= completed_count_q + 32'd1;

                        if (accumulate_perf_q) begin
                            perf_busy_cycles_q  <= perf_busy_cycles_q  + job_perf_busy_cycles;
                            perf_mac_count_q    <= perf_mac_count_q    + job_perf_mac_count;
                            perf_output_count_q <= perf_output_count_q + job_perf_output_count;
                        end

                        if (current_slot_is_final) begin
                            done_pulse_pending_q <= 1'b1;
                            final_store_done_pending_q <= current_slot_output_dma_store;
                            state_q <= RECIPE_STATE_DONE;
                        end
                        else begin
                            state_q <= RECIPE_STATE_ADVANCE;
                        end
                    end

                    RECIPE_STATE_ADVANCE: begin
                        current_slot_q <= current_slot_q + 4'd1;
                        state_q <= RECIPE_STATE_VALIDATE;
                    end

                    default: begin
                        recipe_sequence_error <= 1'b1;
                        state_q <= RECIPE_STATE_ERROR;
                    end
                endcase
            end
        end
    end

endmodule

`endif
