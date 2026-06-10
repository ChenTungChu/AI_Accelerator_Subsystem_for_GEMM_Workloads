// File: rtl/sequencer/ai_accel_desc_fetch_engine.sv
// ============================================================
// AI Accelerator Descriptor Fetch Engine
// P17B: Descriptor fetch engine RTL / compile smoke
//
// Scope:
//   - Standalone RTL block for fetching memory-backed recipe
//     descriptors into an internal P16-compatible slot snapshot.
//   - Uses discrete AXI-MM read-channel wires.  It does not use
//     axi_mm_if directly.
//   - Does not start P16/P15/P14 by itself.  Integration and
//     recipe launch are handled in later P17 milestones.
//
// Descriptor format:
//   The first implementation mirrors the P16 CSR slot descriptor
//   layout.  Constants are intentionally kept local to this module
//   for P17B so no P17-only package is required.
// ============================================================

`timescale 1ns/1ps

module ai_accel_desc_fetch_engine #(
    parameter int ADDR_WIDTH          = 32,
    parameter int DATA_WIDTH          = 64,
    parameter int AXI_ID_WIDTH        = 4,
    parameter int RECIPE_QUEUE_DEPTH  = 4
)(
    input  logic clk,
    input  logic rst_n,

    // --------------------------------------------------------
    // Fetch control
    // --------------------------------------------------------
    input  logic                  fetch_start,
    input  logic [ADDR_WIDTH-1:0] desc_base_addr,
    input  logic [3:0]            desc_count,
    input  logic [15:0]           desc_stride_bytes,

    input  logic                  clear_done,
    input  logic                  clear_error,

    output logic                  fetch_busy,
    output logic                  fetch_done,
    output logic                  fetch_error,
    output logic                  fetch_reject,
    output logic [31:0]           fetch_error_status,
    output logic [31:0]           fetch_reject_status,
    output logic [3:0]            current_desc_index,
    output logic [3:0]            fetched_count,

    // --------------------------------------------------------
    // P16-compatible fetched recipe snapshot
    //
    // The arrays are packed as [slot][field_bits].  Later P17
    // integration can feed these into the existing P16 recipe
    // snapshot path without writing back live P16 CSR slot regs.
    // --------------------------------------------------------
    output logic                  fetched_snapshot_valid,
    output logic [3:0]            fetched_recipe_count,

    output logic [RECIPE_QUEUE_DEPTH-1:0][31:0]             slot_control,
    output logic [RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0]   slot_base_addr_a,
    output logic [RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0]   slot_base_addr_b,
    output logic [RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0]   slot_base_addr_c,
    output logic [RECIPE_QUEUE_DEPTH-1:0][31:0]             slot_dim_m,
    output logic [RECIPE_QUEUE_DEPTH-1:0][31:0]             slot_dim_n,
    output logic [RECIPE_QUEUE_DEPTH-1:0][31:0]             slot_dim_k,
    output logic [RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0]   slot_a_src_base,
    output logic [RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0]   slot_a_dst_base,
    output logic [RECIPE_QUEUE_DEPTH-1:0][31:0]             slot_a_load_beats,
    output logic [RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0]   slot_b_src_base,
    output logic [RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0]   slot_b_dst_base,
    output logic [RECIPE_QUEUE_DEPTH-1:0][31:0]             slot_b_load_beats,
    output logic [RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0]   slot_store_src_base,
    output logic [RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0]   slot_store_dst_base,
    output logic [RECIPE_QUEUE_DEPTH-1:0][31:0]             slot_store_byte_count,
    output logic [RECIPE_QUEUE_DEPTH-1:0][31:0]             slot_user_tag,

    // --------------------------------------------------------
    // Descriptor memory AXI-MM read master
    //
    // P17B uses single-beat incrementing reads.  The engine reads
    // enough DATA_WIDTH beats to collect the first 17 descriptor
    // words.  Any unused upper words in the final beat are ignored.
    // --------------------------------------------------------
    output logic [AXI_ID_WIDTH-1:0] desc_axi_arid,
    output logic [ADDR_WIDTH-1:0]   desc_axi_araddr,
    output logic [7:0]              desc_axi_arlen,
    output logic [2:0]              desc_axi_arsize,
    output logic [1:0]              desc_axi_arburst,
    output logic                    desc_axi_arvalid,
    input  logic                    desc_axi_arready,

    input  logic [AXI_ID_WIDTH-1:0] desc_axi_rid,
    input  logic [DATA_WIDTH-1:0]   desc_axi_rdata,
    input  logic [1:0]              desc_axi_rresp,
    input  logic                    desc_axi_rlast,
    input  logic                    desc_axi_rvalid,
    output logic                    desc_axi_rready
);

    // --------------------------------------------------------
    // Compile-time geometry
    // --------------------------------------------------------
    localparam int DESC_WORD_BITS       = 32;
    localparam int DATA_BYTES           = DATA_WIDTH / 8;
    localparam int WORDS_PER_BEAT       = DATA_WIDTH / DESC_WORD_BITS;

    // Descriptor word offsets.  These mirror the P16 slot layout.
    localparam int DESC_WORD_CONTROL          = 0;
    localparam int DESC_WORD_BASE_ADDR_A      = 1;
    localparam int DESC_WORD_BASE_ADDR_B      = 2;
    localparam int DESC_WORD_BASE_ADDR_C      = 3;
    localparam int DESC_WORD_DIM_M            = 4;
    localparam int DESC_WORD_DIM_N            = 5;
    localparam int DESC_WORD_DIM_K            = 6;
    localparam int DESC_WORD_A_SRC_BASE       = 7;
    localparam int DESC_WORD_A_DST_BASE       = 8;
    localparam int DESC_WORD_A_LOAD_BEATS     = 9;
    localparam int DESC_WORD_B_SRC_BASE       = 10;
    localparam int DESC_WORD_B_DST_BASE       = 11;
    localparam int DESC_WORD_B_LOAD_BEATS     = 12;
    localparam int DESC_WORD_STORE_SRC_BASE   = 13;
    localparam int DESC_WORD_STORE_DST_BASE   = 14;
    localparam int DESC_WORD_STORE_BYTE_COUNT = 15;
    localparam int DESC_WORD_USER_TAG         = 16;
    localparam int DESC_WORDS_REQUIRED        = 17;
    localparam int DESC_BYTES_REQUIRED        = DESC_WORDS_REQUIRED * 4;

    // SLOT_CONTROL fields.
    localparam int SLOT_CTRL_VALID_BIT        = 0;
    localparam int SLOT_CTRL_INPUT_MODE_LSB   = 1;
    localparam int SLOT_CTRL_INPUT_MODE_MSB   = 2;
    localparam int SLOT_CTRL_OUTPUT_MODE_LSB  = 3;
    localparam int SLOT_CTRL_OUTPUT_MODE_MSB  = 4;

    localparam logic [1:0] INPUT_MODE_HOST_PRELOADED = 2'd0;
    localparam logic [1:0] INPUT_MODE_DMA_LOAD       = 2'd1;
    localparam logic [1:0] INPUT_MODE_AXIS_PRELOAD   = 2'd2;
    localparam logic [1:0] INPUT_MODE_DIRECT_STREAM  = 2'd3;

    localparam logic [1:0] OUTPUT_MODE_HOST_READBACK = 2'd0;
    localparam logic [1:0] OUTPUT_MODE_DMA_STORE     = 2'd1;

    // fetch_reject_status bits: command acceptance rejects.
    localparam int REJECT_BUSY_BIT            = 0;
    localparam int REJECT_ZERO_COUNT_BIT      = 1;
    localparam int REJECT_COUNT_RANGE_BIT     = 2;
    localparam int REJECT_BASE_ALIGN_BIT      = 3;
    localparam int REJECT_STRIDE_ALIGN_BIT    = 4;
    localparam int REJECT_STRIDE_SMALL_BIT    = 5;

    // fetch_error_status bits: errors after an accepted fetch.
    localparam int ERROR_AXI_RRESP_BIT        = 0;
    localparam int ERROR_AXI_RLAST_BIT        = 1;
    localparam int ERROR_DESC_INVALID_BIT     = 2;
    localparam int ERROR_INTERNAL_BIT         = 8;

    // Descriptor validation detail bits are ORed into the upper half
    // of fetch_error_status when ERROR_DESC_INVALID_BIT is set.
    localparam int DESCERR_VALID_BIT          = 16;
    localparam int DESCERR_OUTPUT_MODE_BIT    = 17;
    localparam int DESCERR_DIM_ZERO_BIT       = 18;
    localparam int DESCERR_A_LENGTH_ZERO_BIT  = 19;
    localparam int DESCERR_B_LENGTH_ZERO_BIT  = 20;
    localparam int DESCERR_STORE_LENGTH_BIT   = 21;

    // AXI constants.
    localparam logic [1:0] AXI_BURST_INCR = 2'b01;
    localparam logic [1:0] AXI_RESP_OKAY  = 2'b00;

    localparam logic [2:0] AXI_SIZE_VALUE =
        (DATA_BYTES <= 1)  ? 3'd0 :
        (DATA_BYTES <= 2)  ? 3'd1 :
        (DATA_BYTES <= 4)  ? 3'd2 :
        (DATA_BYTES <= 8)  ? 3'd3 :
        (DATA_BYTES <= 16) ? 3'd4 :
        (DATA_BYTES <= 32) ? 3'd5 :
        (DATA_BYTES <= 64) ? 3'd6 : 3'd7;

    // --------------------------------------------------------
    // Internal FSM
    // --------------------------------------------------------
    typedef enum logic [2:0] {
        ST_IDLE     = 3'd0,
        ST_AR       = 3'd1,
        ST_R        = 3'd2,
        ST_VALIDATE = 3'd3
    } fetch_state_e;

    fetch_state_e state_q;

    logic [ADDR_WIDTH-1:0] desc_base_addr_q;
    logic [3:0]            desc_count_q;
    logic [15:0]           desc_stride_bytes_q;
    logic [3:0]            desc_index_q;
    logic [7:0]            word_index_q;
    logic [31:0]           desc_words_q [0:DESC_WORDS_REQUIRED-1];

    logic [31:0]           start_reject_bits;
    logic [31:0]           desc_validation_bits;
    logic [ADDR_WIDTH-1:0] read_addr;

    integer i;

    // --------------------------------------------------------
    // Parameter sanity.  P17B compile target uses DATA_WIDTH=64.
    // These checks protect future accidental unsupported geometry.
    // --------------------------------------------------------
    initial begin
        if (DATA_WIDTH < 32) begin
            $error("ai_accel_desc_fetch_engine: DATA_WIDTH must be >= 32");
        end
        if ((DATA_WIDTH % 32) != 0) begin
            $error("ai_accel_desc_fetch_engine: DATA_WIDTH must be a multiple of 32");
        end
        if (RECIPE_QUEUE_DEPTH <= 0) begin
            $error("ai_accel_desc_fetch_engine: RECIPE_QUEUE_DEPTH must be > 0");
        end
        if (RECIPE_QUEUE_DEPTH > 15) begin
            $error("ai_accel_desc_fetch_engine: RECIPE_QUEUE_DEPTH must be <= 15 for P17B 4-bit count/index fields");
        end
    end

    // --------------------------------------------------------
    // Start-command acceptance validation
    // --------------------------------------------------------
    always_comb begin
        start_reject_bits = 32'h0000_0000;

        if (fetch_busy) begin
            start_reject_bits[REJECT_BUSY_BIT] = 1'b1;
        end

        if (desc_count == 4'd0) begin
            start_reject_bits[REJECT_ZERO_COUNT_BIT] = 1'b1;
        end

        if (desc_count > RECIPE_QUEUE_DEPTH) begin
            start_reject_bits[REJECT_COUNT_RANGE_BIT] = 1'b1;
        end

        if ((desc_base_addr & (DATA_BYTES - 1)) != '0) begin
            start_reject_bits[REJECT_BASE_ALIGN_BIT] = 1'b1;
        end

        if ((desc_stride_bytes & (DATA_BYTES - 1)) != 16'h0000) begin
            start_reject_bits[REJECT_STRIDE_ALIGN_BIT] = 1'b1;
        end

        if (desc_stride_bytes < DESC_BYTES_REQUIRED) begin
            start_reject_bits[REJECT_STRIDE_SMALL_BIT] = 1'b1;
        end
    end

    // --------------------------------------------------------
    // Descriptor validation after all descriptor words are fetched
    // --------------------------------------------------------
    function automatic logic [31:0] calc_desc_validation_bits(
        input logic [31:0] control,
        input logic [31:0] dim_m,
        input logic [31:0] dim_n,
        input logic [31:0] dim_k,
        input logic [31:0] a_load_beats,
        input logic [31:0] b_load_beats,
        input logic [31:0] store_byte_count
    );
        logic [31:0] bits;
        logic [1:0]  input_mode;
        logic [1:0]  output_mode;
    begin
        bits        = 32'h0000_0000;
        input_mode  = control[SLOT_CTRL_INPUT_MODE_MSB:SLOT_CTRL_INPUT_MODE_LSB];
        output_mode = control[SLOT_CTRL_OUTPUT_MODE_MSB:SLOT_CTRL_OUTPUT_MODE_LSB];

        if (control[SLOT_CTRL_VALID_BIT] == 1'b0) begin
            bits[DESCERR_VALID_BIT] = 1'b1;
        end

        if ((output_mode != OUTPUT_MODE_HOST_READBACK) &&
            (output_mode != OUTPUT_MODE_DMA_STORE)) begin
            bits[DESCERR_OUTPUT_MODE_BIT] = 1'b1;
        end

        if ((dim_m == 32'h0000_0000) ||
            (dim_n == 32'h0000_0000) ||
            (dim_k == 32'h0000_0000)) begin
            bits[DESCERR_DIM_ZERO_BIT] = 1'b1;
        end

        if (input_mode != INPUT_MODE_HOST_PRELOADED) begin
            if (a_load_beats == 32'h0000_0000) begin
                bits[DESCERR_A_LENGTH_ZERO_BIT] = 1'b1;
            end

            if (b_load_beats == 32'h0000_0000) begin
                bits[DESCERR_B_LENGTH_ZERO_BIT] = 1'b1;
            end
        end

        if ((output_mode == OUTPUT_MODE_DMA_STORE) &&
            (store_byte_count == 32'h0000_0000)) begin
            bits[DESCERR_STORE_LENGTH_BIT] = 1'b1;
        end

        calc_desc_validation_bits = bits;
    end
    endfunction

    always_comb begin
        desc_validation_bits = calc_desc_validation_bits(
            desc_words_q[DESC_WORD_CONTROL],
            desc_words_q[DESC_WORD_DIM_M],
            desc_words_q[DESC_WORD_DIM_N],
            desc_words_q[DESC_WORD_DIM_K],
            desc_words_q[DESC_WORD_A_LOAD_BEATS],
            desc_words_q[DESC_WORD_B_LOAD_BEATS],
            desc_words_q[DESC_WORD_STORE_BYTE_COUNT]
        );
    end

    // Address for the current single-beat read.
    always_comb begin
        read_addr = desc_base_addr_q
                  + ({{(ADDR_WIDTH-4){1'b0}}, desc_index_q} * desc_stride_bytes_q)
                  + ({{(ADDR_WIDTH-8){1'b0}}, word_index_q} * 4);
    end

    // --------------------------------------------------------
    // Constant AXI read attributes
    // --------------------------------------------------------
    assign desc_axi_arid    = '0;
    assign desc_axi_araddr  = read_addr;
    assign desc_axi_arlen   = 8'd0;
    assign desc_axi_arsize  = AXI_SIZE_VALUE;
    assign desc_axi_arburst = AXI_BURST_INCR;
    assign desc_axi_arvalid = (state_q == ST_AR);
    assign desc_axi_rready  = (state_q == ST_R);

    assign fetch_busy         = (state_q != ST_IDLE);
    assign current_desc_index = desc_index_q;

    // --------------------------------------------------------
    // Main FSM
    // --------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q                <= ST_IDLE;
            desc_base_addr_q       <= '0;
            desc_count_q           <= 4'd0;
            desc_stride_bytes_q    <= 16'd0;
            desc_index_q           <= 4'd0;
            word_index_q           <= 8'd0;
            fetched_count          <= 4'd0;
            fetched_recipe_count   <= 4'd0;
            fetched_snapshot_valid <= 1'b0;

            fetch_done             <= 1'b0;
            fetch_error            <= 1'b0;
            fetch_reject           <= 1'b0;
            fetch_error_status     <= 32'h0000_0000;
            fetch_reject_status    <= 32'h0000_0000;

            for (i = 0; i < DESC_WORDS_REQUIRED; i = i + 1) begin
                desc_words_q[i] <= 32'h0000_0000;
            end

            for (i = 0; i < RECIPE_QUEUE_DEPTH; i = i + 1) begin
                slot_control[i]          <= 32'h0000_0000;
                slot_base_addr_a[i]      <= '0;
                slot_base_addr_b[i]      <= '0;
                slot_base_addr_c[i]      <= '0;
                slot_dim_m[i]            <= 32'h0000_0000;
                slot_dim_n[i]            <= 32'h0000_0000;
                slot_dim_k[i]            <= 32'h0000_0000;
                slot_a_src_base[i]       <= '0;
                slot_a_dst_base[i]       <= '0;
                slot_a_load_beats[i]     <= 32'h0000_0000;
                slot_b_src_base[i]       <= '0;
                slot_b_dst_base[i]       <= '0;
                slot_b_load_beats[i]     <= 32'h0000_0000;
                slot_store_src_base[i]   <= '0;
                slot_store_dst_base[i]   <= '0;
                slot_store_byte_count[i] <= 32'h0000_0000;
                slot_user_tag[i]         <= 32'h0000_0000;
            end
        end else begin
            // Sticky status clears.
            if (clear_done) begin
                fetch_done <= 1'b0;
            end

            if (clear_error) begin
                fetch_error         <= 1'b0;
                fetch_reject        <= 1'b0;
                fetch_error_status  <= 32'h0000_0000;
                fetch_reject_status <= 32'h0000_0000;
            end

            case (state_q)
                ST_IDLE: begin
                    if (fetch_start) begin
                        if (start_reject_bits != 32'h0000_0000) begin
                            fetch_reject        <= 1'b1;
                            fetch_reject_status <= fetch_reject_status | start_reject_bits;
                        end else begin
                            // New accepted fetch invalidates the old fetched snapshot and
                            // clears old sticky status for the new operation.
                            fetch_done             <= 1'b0;
                            fetch_error            <= 1'b0;
                            fetch_reject           <= 1'b0;
                            fetch_error_status     <= 32'h0000_0000;
                            fetch_reject_status    <= 32'h0000_0000;
                            fetched_snapshot_valid <= 1'b0;
                            fetched_recipe_count   <= 4'd0;
                            fetched_count          <= 4'd0;

                            desc_base_addr_q    <= desc_base_addr;
                            desc_count_q        <= desc_count;
                            desc_stride_bytes_q <= desc_stride_bytes;
                            desc_index_q        <= 4'd0;
                            word_index_q        <= 8'd0;

                            for (i = 0; i < DESC_WORDS_REQUIRED; i = i + 1) begin
                                desc_words_q[i] <= 32'h0000_0000;
                            end

                            state_q <= ST_AR;
                        end
                    end
                end

                ST_AR: begin
                    if (desc_axi_arready) begin
                        state_q <= ST_R;
                    end
                end

                ST_R: begin
                    if (desc_axi_rvalid) begin
                        if (desc_axi_rresp != AXI_RESP_OKAY) begin
                            fetch_error                       <= 1'b1;
                            fetch_error_status[ERROR_AXI_RRESP_BIT] <= 1'b1;
                            state_q                           <= ST_IDLE;
                        end else if (!desc_axi_rlast) begin
                            fetch_error                       <= 1'b1;
                            fetch_error_status[ERROR_AXI_RLAST_BIT] <= 1'b1;
                            state_q                           <= ST_IDLE;
                        end else begin
                            for (i = 0; i < WORDS_PER_BEAT; i = i + 1) begin
                                if ((word_index_q + i) < DESC_WORDS_REQUIRED) begin
                                    desc_words_q[word_index_q + i] <= desc_axi_rdata[(i * 32) +: 32];
                                end
                            end

                            if ((word_index_q + WORDS_PER_BEAT) >= DESC_WORDS_REQUIRED) begin
                                state_q <= ST_VALIDATE;
                            end else begin
                                word_index_q <= word_index_q + WORDS_PER_BEAT;
                                state_q      <= ST_AR;
                            end
                        end
                    end
                end

                ST_VALIDATE: begin
                    if (desc_validation_bits != 32'h0000_0000) begin
                        fetch_error                             <= 1'b1;
                        fetch_error_status[ERROR_DESC_INVALID_BIT] <= 1'b1;
                        fetch_error_status                     <= fetch_error_status | desc_validation_bits | (32'h1 << ERROR_DESC_INVALID_BIT);
                        state_q                                 <= ST_IDLE;
                    end else begin
                        slot_control[desc_index_q]          <= desc_words_q[DESC_WORD_CONTROL];
                        slot_base_addr_a[desc_index_q]      <= desc_words_q[DESC_WORD_BASE_ADDR_A][ADDR_WIDTH-1:0];
                        slot_base_addr_b[desc_index_q]      <= desc_words_q[DESC_WORD_BASE_ADDR_B][ADDR_WIDTH-1:0];
                        slot_base_addr_c[desc_index_q]      <= desc_words_q[DESC_WORD_BASE_ADDR_C][ADDR_WIDTH-1:0];
                        slot_dim_m[desc_index_q]            <= desc_words_q[DESC_WORD_DIM_M];
                        slot_dim_n[desc_index_q]            <= desc_words_q[DESC_WORD_DIM_N];
                        slot_dim_k[desc_index_q]            <= desc_words_q[DESC_WORD_DIM_K];
                        slot_a_src_base[desc_index_q]       <= desc_words_q[DESC_WORD_A_SRC_BASE][ADDR_WIDTH-1:0];
                        slot_a_dst_base[desc_index_q]       <= desc_words_q[DESC_WORD_A_DST_BASE][ADDR_WIDTH-1:0];
                        slot_a_load_beats[desc_index_q]     <= desc_words_q[DESC_WORD_A_LOAD_BEATS];
                        slot_b_src_base[desc_index_q]       <= desc_words_q[DESC_WORD_B_SRC_BASE][ADDR_WIDTH-1:0];
                        slot_b_dst_base[desc_index_q]       <= desc_words_q[DESC_WORD_B_DST_BASE][ADDR_WIDTH-1:0];
                        slot_b_load_beats[desc_index_q]     <= desc_words_q[DESC_WORD_B_LOAD_BEATS];
                        slot_store_src_base[desc_index_q]   <= desc_words_q[DESC_WORD_STORE_SRC_BASE][ADDR_WIDTH-1:0];
                        slot_store_dst_base[desc_index_q]   <= desc_words_q[DESC_WORD_STORE_DST_BASE][ADDR_WIDTH-1:0];
                        slot_store_byte_count[desc_index_q] <= desc_words_q[DESC_WORD_STORE_BYTE_COUNT];
                        slot_user_tag[desc_index_q]         <= desc_words_q[DESC_WORD_USER_TAG];

                        fetched_count <= desc_index_q + 4'd1;

                        if ((desc_index_q + 4'd1) >= desc_count_q) begin
                            fetched_recipe_count   <= desc_count_q;
                            fetched_snapshot_valid <= 1'b1;
                            fetch_done             <= 1'b1;
                            state_q                <= ST_IDLE;
                        end else begin
                            desc_index_q <= desc_index_q + 4'd1;
                            word_index_q <= 8'd0;

                            for (i = 0; i < DESC_WORDS_REQUIRED; i = i + 1) begin
                                desc_words_q[i] <= 32'h0000_0000;
                            end

                            state_q <= ST_AR;
                        end
                    end
                end

                default: begin
                    fetch_error                         <= 1'b1;
                    fetch_error_status[ERROR_INTERNAL_BIT] <= 1'b1;
                    state_q                             <= ST_IDLE;
                end
            endcase
        end
    end

    // desc_axi_rid is intentionally unused in P17B.  The first
    // implementation issues only one single-beat read at a time and
    // keeps desc_axi_arid fixed at zero.  A future robustness pass can
    // add RID checking if a shared descriptor interconnect is introduced.
    logic unused_desc_axi_rid;
    assign unused_desc_axi_rid = ^desc_axi_rid;

endmodule
