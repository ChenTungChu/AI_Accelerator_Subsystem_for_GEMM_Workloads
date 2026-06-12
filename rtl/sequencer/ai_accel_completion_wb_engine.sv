// File: rtl/sequencer/ai_accel_completion_wb_engine.sv
// ============================================================
// AI Accelerator Completion Writeback Engine
// P18C/P18D: Completion writeback engine RTL / CSR smoke
//
// Scope:
//   - Writes one 64-byte host-visible completion record to external
//     completion memory through a dedicated AXI-MM write master.
//   - Uses single-beat 64-bit writes only.
//   - Uses no-partial-WSTRB Option B: words 2..15 first,
//     then word0 cleared + word1, then final commit word0 + word1.
//
// P18D FIX6 note:
//   - Uses scalar completion-word snapshot registers and registered
//     AXI AW/W payload registers.
//   - A dedicated ST_PREP state builds each write beat before AWVALID
//     or WVALID is asserted, avoiding any first-payload-beat dependency
//     on combinational functions reading freshly-updated snapshot state.
// ============================================================

`timescale 1ns/1ps

module ai_accel_completion_wb_engine #(
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 64,
    parameter int AXI_ID_WIDTH = 4
)(
    input  logic clk,
    input  logic rst_n,

    // Writeback control
    input  logic                  wb_start,
    input  logic                  wb_enable,
    input  logic [ADDR_WIDTH-1:0] completion_base_addr,

    input  logic                  clear_done,
    input  logic                  clear_error,

    // Completion record payload snapshot
    input  logic                  overall_done,
    input  logic                  overall_error,
    input  logic                  overall_reject,
    input  logic [31:0]           status_flags,

    input  logic [31:0]           first_user_tag,
    input  logic [31:0]           last_user_tag,
    input  logic [7:0]            programmed_count,
    input  logic [7:0]            fetched_count,
    input  logic [7:0]            completed_count,

    input  logic [31:0]           desc_fetch_done_status,
    input  logic [31:0]           desc_fetch_error_status,
    input  logic [31:0]           desc_fetch_reject_status,

    input  logic [31:0]           recipe_done_status,
    input  logic [31:0]           recipe_error_status,
    input  logic [31:0]           recipe_reject_status,

    input  logic [31:0]           slot_done_mask,
    input  logic [31:0]           slot_error_mask,
    input  logic [31:0]           slot_reject_mask,

    input  logic [31:0]           perf_busy_cycles,
    input  logic [31:0]           perf_mac_count,
    input  logic [31:0]           perf_output_count,
    input  logic [31:0]           error_detail,

    // Writeback status
    output logic                  wb_busy,
    output logic                  wb_done,
    output logic                  wb_error,
    output logic                  wb_reject,
    output logic [31:0]           wb_error_status,
    output logic [31:0]           wb_reject_status,
    output logic [31:0]           wb_state,
    output logic [3:0]            current_write_step,
    output logic [7:0]            wb_written_beats,

    // Completion-memory AXI-MM write master
    output logic [AXI_ID_WIDTH-1:0]     comp_axi_awid,
    output logic [ADDR_WIDTH-1:0]       comp_axi_awaddr,
    output logic [7:0]                  comp_axi_awlen,
    output logic [2:0]                  comp_axi_awsize,
    output logic [1:0]                  comp_axi_awburst,
    output logic                        comp_axi_awvalid,
    input  logic                        comp_axi_awready,

    output logic [DATA_WIDTH-1:0]       comp_axi_wdata,
    output logic [DATA_WIDTH/8-1:0]     comp_axi_wstrb,
    output logic                        comp_axi_wlast,
    output logic                        comp_axi_wvalid,
    input  logic                        comp_axi_wready,

    input  logic [AXI_ID_WIDTH-1:0]     comp_axi_bid,
    input  logic [1:0]                  comp_axi_bresp,
    input  logic                        comp_axi_bvalid,
    output logic                        comp_axi_bready
);

    localparam int DATA_BYTES = DATA_WIDTH / 8;

    localparam logic [2:0] AXI_SIZE =
        (DATA_BYTES <= 1 ) ? 3'd0 :
        (DATA_BYTES <= 2 ) ? 3'd1 :
        (DATA_BYTES <= 4 ) ? 3'd2 :
        (DATA_BYTES <= 8 ) ? 3'd3 :
        (DATA_BYTES <= 16) ? 3'd4 :
        (DATA_BYTES <= 32) ? 3'd5 :
        (DATA_BYTES <= 64) ? 3'd6 : 3'd7;

    localparam int COMP_WRITE_STEPS = 9;

    localparam logic [7:0] COMP_FORMAT_MAJOR = 8'h01;
    localparam logic [7:0] COMP_FORMAT_MINOR = 8'h00;
    localparam logic [7:0] COMP_FEATURE_ID   = 8'h18;

    localparam int ERR_BRESP_BIT    = 0;
    localparam int ERR_BID_BIT      = 1;
    localparam int ERR_SEQUENCE_BIT = 8;

    localparam int REJECT_BUSY_BIT           = 0;
    localparam int REJECT_UNALIGNED_BASE_BIT = 1;

    typedef enum logic [2:0] {
        ST_IDLE     = 3'd0,
        ST_SNAPSHOT = 3'd1,
        ST_PREP     = 3'd2,
        ST_ISSUE    = 3'd3,
        ST_RESP     = 3'd4,
        ST_ERROR    = 3'd5
    } wb_state_e;

    wb_state_e state_q;

    logic [ADDR_WIDTH-1:0] base_addr_q;
    logic [3:0]            step_q;
    logic                  aw_done_q;
    logic                  w_done_q;

    logic [31:0]           word0_q;
    logic [31:0]           word1_q;
    logic [31:0]           word2_q;
    logic [31:0]           word3_q;
    logic [31:0]           word4_q;
    logic [31:0]           word5_q;
    logic [31:0]           word6_q;
    logic [31:0]           word7_q;
    logic [31:0]           word8_q;
    logic [31:0]           word9_q;
    logic [31:0]           word10_q;
    logic [31:0]           word11_q;
    logic [31:0]           word12_q;
    logic [31:0]           word13_q;
    logic [31:0]           word14_q;
    logic [31:0]           word15_q;

    logic [31:0]           commit_word;
    logic [31:0]           start_reject_bits;
    logic                  start_accepted;
    logic                  start_rejected;
    logic                  base_aligned;

    logic [ADDR_WIDTH-1:0] awaddr_q;
    logic [DATA_WIDTH-1:0] wdata_q;
    logic                  awvalid_q;
    logic                  wvalid_q;

`ifndef SYNTHESIS
    initial begin
        if (DATA_WIDTH != 64) begin
            $error("ai_accel_completion_wb_engine: P18D baseline requires DATA_WIDTH=64");
        end
        if (AXI_ID_WIDTH <= 0) begin
            $error("ai_accel_completion_wb_engine: AXI_ID_WIDTH must be > 0");
        end
    end
`endif

    assign base_aligned = (completion_base_addr[$clog2(DATA_BYTES)-1:0] == '0);

    always_comb begin
        start_reject_bits = 32'h0000_0000;
        if (wb_busy) begin
            start_reject_bits[REJECT_BUSY_BIT] = 1'b1;
        end
        if (!base_aligned) begin
            start_reject_bits[REJECT_UNALIGNED_BASE_BIT] = 1'b1;
        end
    end

    assign start_rejected = wb_start && (start_reject_bits != 32'h0000_0000);
    assign start_accepted = wb_start && (start_reject_bits == 32'h0000_0000);

    always_comb begin
        commit_word = {
            COMP_FORMAT_MAJOR,
            COMP_FORMAT_MINOR,
            COMP_FEATURE_ID,
            4'h0,
            overall_reject,
            overall_error,
            overall_done,
            1'b1
        };
    end

    function automatic logic [ADDR_WIDTH-1:0] prep_addr(input logic [3:0] step);
        begin
            case (step)
                4'd0: prep_addr = base_addr_q + {{(ADDR_WIDTH-4){1'b0}}, 4'h8};
                4'd1: prep_addr = base_addr_q + {{(ADDR_WIDTH-5){1'b0}}, 5'h10};
                4'd2: prep_addr = base_addr_q + {{(ADDR_WIDTH-5){1'b0}}, 5'h18};
                4'd3: prep_addr = base_addr_q + {{(ADDR_WIDTH-6){1'b0}}, 6'h20};
                4'd4: prep_addr = base_addr_q + {{(ADDR_WIDTH-6){1'b0}}, 6'h28};
                4'd5: prep_addr = base_addr_q + {{(ADDR_WIDTH-6){1'b0}}, 6'h30};
                4'd6: prep_addr = base_addr_q + {{(ADDR_WIDTH-6){1'b0}}, 6'h38};
                default: prep_addr = base_addr_q;
            endcase
        end
    endfunction

    function automatic logic [DATA_WIDTH-1:0] prep_data(input logic [3:0] step);
        logic [DATA_WIDTH-1:0] data_v;
        begin
            data_v = '0;
            case (step)
                4'd0: data_v = {word3_q,  word2_q};
                4'd1: data_v = {word5_q,  word4_q};
                4'd2: data_v = {word7_q,  word6_q};
                4'd3: data_v = {word9_q,  word8_q};
                4'd4: data_v = {word11_q, word10_q};
                4'd5: data_v = {word13_q, word12_q};
                4'd6: data_v = {word15_q, word14_q};
                4'd7: data_v = {word1_q,  32'h0000_0000};
                4'd8: data_v = {word1_q,  word0_q};
                default: data_v = '0;
            endcase
            prep_data = data_v;
        end
    endfunction

    assign comp_axi_awid    = '0;
    assign comp_axi_awaddr  = awaddr_q;
    assign comp_axi_awlen   = 8'd0;
    assign comp_axi_awsize  = AXI_SIZE;
    assign comp_axi_awburst = 2'b01;
    assign comp_axi_awvalid = awvalid_q;

    assign comp_axi_wdata   = wdata_q;
    assign comp_axi_wstrb   = {DATA_BYTES{1'b1}};
    assign comp_axi_wlast   = 1'b1;
    assign comp_axi_wvalid  = wvalid_q;

    assign comp_axi_bready  = (state_q == ST_RESP);

    assign wb_busy            = (state_q == ST_SNAPSHOT) ||
                                (state_q == ST_PREP)     ||
                                (state_q == ST_ISSUE)    ||
                                (state_q == ST_RESP);
    assign wb_state           = {29'd0, state_q};
    assign current_write_step = step_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q          <= ST_IDLE;
            base_addr_q      <= '0;
            step_q           <= 4'd0;
            aw_done_q        <= 1'b0;
            w_done_q         <= 1'b0;
            awaddr_q         <= '0;
            wdata_q          <= '0;
            awvalid_q        <= 1'b0;
            wvalid_q         <= 1'b0;
            wb_done          <= 1'b0;
            wb_error         <= 1'b0;
            wb_reject        <= 1'b0;
            wb_error_status  <= 32'h0000_0000;
            wb_reject_status <= 32'h0000_0000;
            wb_written_beats <= 8'd0;

            word0_q  <= 32'h0000_0000;
            word1_q  <= 32'h0000_0000;
            word2_q  <= 32'h0000_0000;
            word3_q  <= 32'h0000_0000;
            word4_q  <= 32'h0000_0000;
            word5_q  <= 32'h0000_0000;
            word6_q  <= 32'h0000_0000;
            word7_q  <= 32'h0000_0000;
            word8_q  <= 32'h0000_0000;
            word9_q  <= 32'h0000_0000;
            word10_q <= 32'h0000_0000;
            word11_q <= 32'h0000_0000;
            word12_q <= 32'h0000_0000;
            word13_q <= 32'h0000_0000;
            word14_q <= 32'h0000_0000;
            word15_q <= 32'h0000_0000;
        end else begin
            if (clear_done) begin
                wb_done <= 1'b0;
            end

            if (clear_error) begin
                wb_error         <= 1'b0;
                wb_reject        <= 1'b0;
                wb_error_status  <= 32'h0000_0000;
                wb_reject_status <= 32'h0000_0000;
            end

            if (start_rejected) begin
                wb_reject        <= 1'b1;
                wb_reject_status <= wb_reject_status | start_reject_bits;
            end

            case (state_q)
                ST_IDLE: begin
                    aw_done_q <= 1'b0;
                    w_done_q  <= 1'b0;
                    awvalid_q <= 1'b0;
                    wvalid_q  <= 1'b0;
                    step_q    <= 4'd0;

                    if (start_accepted) begin
                        wb_done          <= 1'b0;
                        wb_written_beats <= 8'd0;

                        word0_q  <= commit_word;
                        word1_q  <= status_flags;
                        word2_q  <= first_user_tag;
                        word3_q  <= last_user_tag;
                        word4_q  <= {8'h00, completed_count, fetched_count, programmed_count};
                        word5_q  <= desc_fetch_done_status;
                        word6_q  <= desc_fetch_error_status;
                        word7_q  <= desc_fetch_reject_status;
                        word8_q  <= recipe_done_status;
                        word9_q  <= recipe_error_status;
                        word10_q <= recipe_reject_status;
                        word11_q <= {20'h00000, slot_reject_mask[3:0], slot_error_mask[3:0], slot_done_mask[3:0]};
                        word12_q <= perf_busy_cycles;
                        word13_q <= perf_mac_count;
                        word14_q <= perf_output_count;
                        word15_q <= error_detail;

                        if (wb_enable) begin
                            base_addr_q <= completion_base_addr;
                            state_q     <= ST_SNAPSHOT;
                        end else begin
                            wb_done <= 1'b1;
                            state_q <= ST_IDLE;
                        end
                    end
                end

                ST_SNAPSHOT: begin
                    aw_done_q <= 1'b0;
                    w_done_q  <= 1'b0;
                    awvalid_q <= 1'b0;
                    wvalid_q  <= 1'b0;
                    state_q   <= ST_PREP;
                end

                ST_PREP: begin
                    awaddr_q  <= prep_addr(step_q);
                    wdata_q   <= prep_data(step_q);
                    aw_done_q <= 1'b0;
                    w_done_q  <= 1'b0;
                    awvalid_q <= 1'b1;
                    wvalid_q  <= 1'b1;
                    state_q   <= ST_ISSUE;
                end

                ST_ISSUE: begin
                    logic aw_fire_now;
                    logic w_fire_now;

                    aw_fire_now = awvalid_q && comp_axi_awready;
                    w_fire_now  = wvalid_q  && comp_axi_wready;

                    if (aw_fire_now) begin
                        awvalid_q <= 1'b0;
                        aw_done_q <= 1'b1;
                    end

                    if (w_fire_now) begin
                        wvalid_q <= 1'b0;
                        w_done_q <= 1'b1;
                    end

                    if ((aw_fire_now || aw_done_q) &&
                        (w_fire_now  || w_done_q)) begin
                        awvalid_q <= 1'b0;
                        wvalid_q  <= 1'b0;
                        state_q   <= ST_RESP;
                    end
                end

                ST_RESP: begin
                    if (comp_axi_bvalid) begin
                        if (comp_axi_bresp != 2'b00) begin
                            wb_error_status[ERR_BRESP_BIT] <= 1'b1;
                            wb_error                       <= 1'b1;
                            state_q                        <= ST_ERROR;
                        end else if (comp_axi_bid != '0) begin
                            wb_error_status[ERR_BID_BIT] <= 1'b1;
                            wb_error                     <= 1'b1;
                            state_q                      <= ST_ERROR;
                        end else begin
                            wb_written_beats <= wb_written_beats + 8'd1;
                            aw_done_q        <= 1'b0;
                            w_done_q         <= 1'b0;

                            if (step_q == (COMP_WRITE_STEPS - 1)) begin
                                wb_done <= 1'b1;
                                state_q <= ST_IDLE;
                            end else begin
                                step_q  <= step_q + 4'd1;
                                state_q <= ST_PREP;
                            end
                        end
                    end
                end

                ST_ERROR: begin
                    awvalid_q <= 1'b0;
                    wvalid_q  <= 1'b0;
                    aw_done_q <= 1'b0;
                    w_done_q  <= 1'b0;
                    state_q   <= ST_IDLE;
                end

                default: begin
                    wb_error_status[ERR_SEQUENCE_BIT] <= 1'b1;
                    wb_error                         <= 1'b1;
                    awvalid_q                        <= 1'b0;
                    wvalid_q                         <= 1'b0;
                    aw_done_q                        <= 1'b0;
                    w_done_q                         <= 1'b0;
                    state_q                          <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
