// File: rtl/sequencer/ai_accel_queue_fetch_controller.sv
// ============================================================
// ai_accel_queue_fetch_controller
// ============================================================
// P24C single-outstanding command queue fetch controller.
//
// Scope through P24C:
//   - Reads one 64-byte SQ command entry from command memory.
//   - Parses and validates the command entry.
//   - Presents one accepted/rejected command context to downstream logic.
//   - Does not launch P17 descriptor fetch directly yet.
//   - Does not update SQ_HEAD / CQ_TAIL directly.
//   - Adds queue disabled / invalid config / empty / full / bad pointer handling.
//   - Exposes CMD_TIMEOUT_CYCLES from SQ word6 to the wrapper-level
//     P24C watchdog. Runtime timeout detection remains in the CSR top
//     queue glue because this fetch block does not own the downstream
//     descriptor/recipe/completion terminal state.
//
// Integration intent for P19D/P19E:
//   cmd_valid/cmd_ready handshake becomes the boundary into the existing
//   descriptor-fetch launch path and completion-writeback allocation path.
//
// Baseline assumptions:
//   - DATA_WIDTH = 64 for the current subsystem baseline.
//   - SQ entry size = 64 bytes, 16 logical 32-bit words.
//   - CQ entry size = 64 bytes, existing P18 completion record format.
//   - One outstanding command context at a time.
// ============================================================

module ai_accel_queue_fetch_controller #(
    parameter int ADDR_WIDTH          = 32,
    parameter int DATA_WIDTH          = 64,
    parameter int AXI_ID_WIDTH        = 4,
    parameter int P19_QUEUE_MAX_DEPTH = 16,
    parameter int P19_MAX_DESC_COUNT  = 4,
    parameter int SQ_ENTRY_BYTES      = 64,
    parameter int CQ_ENTRY_BYTES      = 64,
    parameter int P19_FIRST_OPCODE    = 1
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // --------------------------------------------------------
    // Queue control from CSR block
    // --------------------------------------------------------
    input  logic                    start_queue_pulse,
    input  logic                    clear_done_pulse,
    input  logic                    clear_error_pulse,

    input  logic                    queue_enable,
    input  logic                    run_until_empty,
    input  logic                    stop_on_error,

    input  logic [ADDR_WIDTH-1:0]   sq_base_addr,
    input  logic [31:0]             sq_depth,
    input  logic [31:0]             sq_head,
    input  logic [31:0]             sq_tail,
    input  logic [31:0]             sq_stride,

    input  logic [ADDR_WIDTH-1:0]   cq_base_addr,
    input  logic [31:0]             cq_depth,
    input  logic [31:0]             cq_head,
    input  logic [31:0]             cq_tail,
    input  logic [31:0]             cq_stride,

    // --------------------------------------------------------
    // P27 memory access guard configuration
    // --------------------------------------------------------
    input  logic [31:0]             mem_guard_control,
    input  logic [ADDR_WIDTH-1:0]   mem_guard_sq_base,
    input  logic [ADDR_WIDTH-1:0]   mem_guard_sq_limit,
    input  logic [ADDR_WIDTH-1:0]   mem_guard_cq_base,
    input  logic [ADDR_WIDTH-1:0]   mem_guard_cq_limit,
    input  logic [ADDR_WIDTH-1:0]   mem_guard_desc_base,
    input  logic [ADDR_WIDTH-1:0]   mem_guard_desc_limit,

    // Later P19D connects this to the combined P17/P18/P16/P15 idle policy.
    input  logic                    underlying_idle,

    // --------------------------------------------------------
    // Command-memory AXI read master
    // --------------------------------------------------------
    output logic [AXI_ID_WIDTH-1:0] cmd_axi_arid,
    output logic [ADDR_WIDTH-1:0]   cmd_axi_araddr,
    output logic [7:0]              cmd_axi_arlen,
    output logic [2:0]              cmd_axi_arsize,
    output logic [1:0]              cmd_axi_arburst,
    output logic                    cmd_axi_arvalid,
    input  logic                    cmd_axi_arready,

    input  logic [AXI_ID_WIDTH-1:0] cmd_axi_rid,
    input  logic [DATA_WIDTH-1:0]   cmd_axi_rdata,
    input  logic [1:0]              cmd_axi_rresp,
    input  logic                    cmd_axi_rlast,
    input  logic                    cmd_axi_rvalid,
    output logic                    cmd_axi_rready,

    // --------------------------------------------------------
    // Fetched command context output
    // --------------------------------------------------------
    output logic                    cmd_valid,
    input  logic                    cmd_ready,

    output logic                    cmd_reject,
    output logic [31:0]             cmd_error_detail,

    output logic [31:0]             cmd_control,
    output logic [31:0]             cmd_user_tag,
    output logic [ADDR_WIDTH-1:0]   cmd_desc_base_addr,
    output logic [31:0]             cmd_desc_count,
    output logic [31:0]             cmd_desc_stride,
    output logic [31:0]             cmd_completion_flags,
    output logic [31:0]             cmd_timeout_cycles,
    output logic [ADDR_WIDTH-1:0]   cmd_completion_base_addr,
    output logic                    cmd_stop_after_this,

    output logic [31:0]             cmd_sq_head_snapshot,
    output logic [31:0]             cmd_cq_tail_snapshot,
    output logic [7:0]              cmd_sq_index,
    output logic [7:0]              cmd_cq_index,

    // --------------------------------------------------------
    // Queue status outputs back to CSR block
    // --------------------------------------------------------
    output logic                    queue_busy,
    output logic                    queue_drained_pulse,
    output logic                    queue_cmd_fetched_pulse,
    output logic                    queue_cmd_validated_pulse,
    output logic                    queue_error_pulse,
    output logic                    queue_reject_pulse,
    output logic                    queue_cq_full_stall,

    output logic [31:0]             queue_done_status,
    output logic [31:0]             queue_error_status,
    output logic [31:0]             queue_reject_status,
    output logic [31:0]             queue_state,
    output logic [31:0]             queue_current_index,
    output logic [31:0]             queue_error_index,
    output logic [31:0]             queue_error_detail,
    output logic [31:0]             queue_last_cmd_tag,
    output logic [31:0]             queue_last_cmd_control,
    output logic [31:0]             queue_sq_occupancy,
    output logic [31:0]             queue_cq_occupancy,
    output logic [31:0]             queue_cq_space,

    // --------------------------------------------------------
    // P27 memory access guard diagnostics
    // --------------------------------------------------------
    output logic                    mem_guard_check_pulse,
    output logic                    mem_guard_error_pulse,
    output logic [31:0]             mem_guard_error_status,
    output logic [31:0]             mem_guard_reject_status,
    output logic [31:0]             mem_guard_error_detail,
    output logic [ADDR_WIDTH-1:0]   mem_guard_error_addr,
    output logic [31:0]             mem_guard_error_size_bytes,
    output logic [31:0]             mem_guard_error_domain,
    output logic [ADDR_WIDTH-1:0]   mem_guard_last_check_addr,
    output logic [31:0]             mem_guard_last_check_size_bytes,
    output logic [31:0]             mem_guard_last_check_domain
);

    // --------------------------------------------------------
    // Local constants
    // --------------------------------------------------------
    localparam int BYTE_LANES       = DATA_WIDTH / 8;
    localparam int WORDS_PER_BEAT   = DATA_WIDTH / 32;
    localparam int CMD_WORDS        = 16;
    localparam int CMD_ENTRY_BEATS  = SQ_ENTRY_BYTES / BYTE_LANES;
    localparam int AXI_SIZE_VALUE   = $clog2(BYTE_LANES);

    localparam logic [1:0] AXI_BURST_INCR = 2'b01;
    localparam logic [1:0] AXI_RESP_OKAY  = 2'b00;

    localparam logic [31:0] EXPECTED_SQ_STRIDE = SQ_ENTRY_BYTES;
    localparam logic [31:0] EXPECTED_CQ_STRIDE = CQ_ENTRY_BYTES;
    localparam logic [31:0] P19_QUEUE_MAX_DEPTH_U32 = P19_QUEUE_MAX_DEPTH;
    localparam logic [31:0] P19_MAX_DESC_COUNT_U32  = P19_MAX_DESC_COUNT;
    localparam logic [6:0]  P19_FIRST_OPCODE_U7     = P19_FIRST_OPCODE;
    localparam logic [7:0]  CMD_ENTRY_BEATS_U8      = CMD_ENTRY_BEATS;
    localparam logic [2:0]  AXI_SIZE_U3             = AXI_SIZE_VALUE;

    // Queue done bits
    localparam int Q_DONE_STARTED       = 0;
    localparam int Q_DONE_DRAINED       = 1;
    localparam int Q_DONE_CMD_FETCHED   = 2;
    localparam int Q_DONE_CMD_VALIDATED = 3;

    // Queue error bits
    localparam int Q_ERR_CMD_FETCH        = 0;
    localparam int Q_ERR_CMD_VALIDATION   = 1;
    localparam int Q_ERR_UNDERLYING_BUSY  = 2;
    localparam int Q_ERR_BAD_POINTER      = 3;
    localparam int Q_ERR_INTERNAL         = 7;

    // Queue reject bits
    localparam int Q_REJ_QUEUE_BUSY        = 0;
    localparam int Q_REJ_QUEUE_DISABLED    = 1;
    localparam int Q_REJ_INVALID_CFG       = 2;
    localparam int Q_REJ_BAD_POINTER       = 3;
    localparam int Q_REJ_UNSUPPORTED_COMBO = 5;

    // Error detail encodings used by this P24C RTL.
    localparam logic [31:0] ERR_NONE                 = 32'h0000_0000;
    localparam logic [31:0] ERR_DISABLED             = 32'h0000_0001;
    localparam logic [31:0] ERR_INVALID_CFG          = 32'h0000_0002;
    localparam logic [31:0] ERR_BAD_POINTER          = 32'h0000_0003;
    localparam logic [31:0] ERR_AR_RRESP             = 32'h0000_0101;
    localparam logic [31:0] ERR_AR_EARLY_RLAST       = 32'h0000_0102;
    localparam logic [31:0] ERR_AR_MISSING_RLAST     = 32'h0000_0103;
    localparam logic [31:0] ERR_CMD_VALID_ZERO       = 32'h0000_0201;
    localparam logic [31:0] ERR_CMD_BAD_OPCODE       = 32'h0000_0202;
    localparam logic [31:0] ERR_CMD_NO_COMPLETION    = 32'h0000_0203;
    localparam logic [31:0] ERR_CMD_RSVD_BITS        = 32'h0000_0204;
    localparam logic [31:0] ERR_CMD_DESC_UNALIGNED   = 32'h0000_0205;
    localparam logic [31:0] ERR_CMD_DESC_COUNT_ZERO  = 32'h0000_0206;
    localparam logic [31:0] ERR_CMD_DESC_COUNT_RANGE = 32'h0000_0207;
    localparam logic [31:0] ERR_CMD_STRIDE_ZERO      = 32'h0000_0208;
    localparam logic [31:0] ERR_CMD_STRIDE_UNALIGNED = 32'h0000_0209;

    // P27 memory guard control bits.  These mirror the frozen P27B CSR map.
    localparam int MEM_GUARD_CONTROL_ENABLE            = 0;
    localparam int MEM_GUARD_CONTROL_STRICT_REJECT     = 1;
    localparam int MEM_GUARD_CONTROL_SQ_CHECK_ENABLE   = 4;
    localparam int MEM_GUARD_CONTROL_CQ_CHECK_ENABLE   = 5;
    localparam int MEM_GUARD_CONTROL_DESC_CHECK_ENABLE = 6;

    localparam int Q_ERR_MEMORY_GUARD = 9;

    localparam int MEM_GUARD_ERR_ANY        = 0;
    localparam int MEM_GUARD_ERR_SQ_RANGE   = 1;
    localparam int MEM_GUARD_ERR_CQ_RANGE   = 2;
    localparam int MEM_GUARD_ERR_DESC_RANGE = 3;
    localparam int MEM_GUARD_ERR_BASE_LIMIT = 6;
    localparam int MEM_GUARD_ERR_OVERFLOW   = 7;

    localparam logic [31:0] P27_DOMAIN_SQ   = 32'd1;
    localparam logic [31:0] P27_DOMAIN_CQ   = 32'd2;
    localparam logic [31:0] P27_DOMAIN_DESC = 32'd3;

    localparam logic [7:0] P27_DETAIL_SQ_RANGE       = 8'h20;
    localparam logic [7:0] P27_DETAIL_CQ_RANGE       = 8'h21;
    localparam logic [7:0] P27_DETAIL_DESC_RANGE     = 8'h22;
    localparam logic [7:0] P27_DETAIL_ADDR_OVERFLOW  = 8'h25;
    localparam logic [7:0] P27_DETAIL_SPAN_CONFIG    = 8'h27;

    localparam logic [31:0] P27_SQ_ENTRY_SIZE_BYTES   = SQ_ENTRY_BYTES;
    localparam logic [31:0] P27_CQ_ENTRY_SIZE_BYTES   = CQ_ENTRY_BYTES;

    // --------------------------------------------------------
    // State machine
    // --------------------------------------------------------
    typedef enum logic [3:0] {
        Q_IDLE        = 4'd0,
        Q_CHECK_READY = 4'd1,
        Q_ISSUE_AR    = 4'd2,
        Q_READ_CMD    = 4'd3,
        Q_VALIDATE    = 4'd4,
        Q_PRESENT     = 4'd5,
        Q_DRAINED     = 4'd6,
        Q_DONE        = 4'd7,
        Q_ERROR       = 4'd8
    } q_state_e;

    q_state_e state_q, state_d;

    logic [31:0] cmd_words_q [0:CMD_WORDS-1];
    logic [31:0] cmd_words_d [0:CMD_WORDS-1];

    logic [3:0]  rbeat_count_q, rbeat_count_d;
    logic [7:0]  sq_index_q, sq_index_d;
    logic [7:0]  cq_index_q, cq_index_d;
    logic [31:0] sq_head_snapshot_q, sq_head_snapshot_d;
    logic [31:0] cq_tail_snapshot_q, cq_tail_snapshot_d;
    logic [ADDR_WIDTH-1:0] sq_entry_addr_q, sq_entry_addr_d;
    logic [ADDR_WIDTH-1:0] cq_entry_addr_q, cq_entry_addr_d;

    logic [31:0] error_detail_q, error_detail_d;
    logic        fetched_cmd_reject_q, fetched_cmd_reject_d;

    logic [31:0] done_status_q, done_status_d;
    logic [31:0] error_status_q, error_status_d;
    logic [31:0] reject_status_q, reject_status_d;
    logic [31:0] error_index_q, error_index_d;
    logic [31:0] last_cmd_tag_q, last_cmd_tag_d;
    logic [31:0] last_cmd_control_q, last_cmd_control_d;

    logic [31:0] sq_occupancy_w;
    logic [31:0] cq_occupancy_w;
    logic [31:0] cq_space_w;

    logic [31:0] sq_index_calc_w;
    logic [31:0] cq_index_calc_w;
    logic [63:0] sq_offset_calc_w;
    logic [63:0] cq_offset_calc_w;
    logic [63:0] sq_entry_addr_calc_w;
    logic [63:0] cq_entry_addr_calc_w;
    logic [63:0] desc_span_calc_w;

    logic        mem_guard_active_w;
    logic        mem_guard_sq_check_w;
    logic        mem_guard_cq_check_w;
    logic        mem_guard_desc_check_w;

    logic        sq_guard_ok_w;
    logic        cq_guard_ok_w;
    logic        desc_guard_ok_w;
    logic [31:0] sq_guard_status_w;
    logic [31:0] cq_guard_status_w;
    logic [31:0] desc_guard_status_w;
    logic [7:0]  sq_guard_detail_code_w;
    logic [7:0]  cq_guard_detail_code_w;
    logic [7:0]  desc_guard_detail_code_w;

    logic        cfg_valid_w;
    logic        ptr_valid_w;
    logic        sq_empty_w;
    logic        cq_full_w;

    logic        cmd_control_valid_w;
    logic [6:0]  cmd_control_opcode_w;
    logic        cmd_control_completion_w;
    logic        cmd_control_stop_w;
    logic        cmd_control_rsvd_zero_w;
    logic        cmd_desc_base_aligned_w;
    logic        cmd_desc_count_valid_w;
    logic        cmd_desc_stride_valid_w;

    logic [31:0] validation_error_detail_w;
    logic        validation_pass_w;

    logic [31:0] cmd0_w;
    logic [31:0] cmd1_w;
    logic [31:0] cmd2_w;
    logic [31:0] cmd3_w;
    logic [31:0] cmd4_w;
    logic [31:0] cmd5_w;
    logic [31:0] cmd6_w;

    function automatic logic [31:0] p27_make_detail(
        input logic [7:0] detail_code,
        input logic [7:0] domain,
        input logic [7:0] index,
        input logic [7:0] state_code
    );
    begin
        p27_make_detail = {state_code, index, domain, detail_code};
    end
    endfunction

    function automatic logic [31:0] p27_status_for_detail(
        input logic [7:0] detail_code,
        input logic [31:0] domain
    );
        logic [31:0] status;
    begin
        status = 32'h0000_0001;

        if (domain == P27_DOMAIN_SQ) begin
            status[MEM_GUARD_ERR_SQ_RANGE] = 1'b1;
        end
        else if (domain == P27_DOMAIN_CQ) begin
            status[MEM_GUARD_ERR_CQ_RANGE] = 1'b1;
        end
        else if (domain == P27_DOMAIN_DESC) begin
            status[MEM_GUARD_ERR_DESC_RANGE] = 1'b1;
        end

        if (detail_code == P27_DETAIL_ADDR_OVERFLOW) begin
            status[MEM_GUARD_ERR_OVERFLOW] = 1'b1;
        end
        else if (detail_code == P27_DETAIL_SPAN_CONFIG) begin
            status[MEM_GUARD_ERR_BASE_LIMIT] = 1'b1;
        end

        return status;
    end
    endfunction

    function automatic bit p27_range_ok(
        input logic [63:0] addr64,
        input logic [31:0] size_bytes,
        input logic [31:0] region_base,
        input logic [31:0] region_limit,
        output logic [7:0] detail_code
    );
        logic [64:0] end_addr_ext;
    begin
        detail_code = 8'h00;
        end_addr_ext = {1'b0, addr64} + {33'd0, size_bytes};

        if (size_bytes == 32'h0000_0000) begin
            detail_code = P27_DETAIL_SPAN_CONFIG;
            return 1'b0;
        end
        if (region_base >= region_limit) begin
            detail_code = P27_DETAIL_SPAN_CONFIG;
            return 1'b0;
        end
        if (addr64[63:32] != 32'h0000_0000 || end_addr_ext[64] || end_addr_ext[63:32] != 32'h0000_0000) begin
            detail_code = P27_DETAIL_ADDR_OVERFLOW;
            return 1'b0;
        end
        if (addr64[31:0] < region_base || end_addr_ext[31:0] > region_limit) begin
            return 1'b0;
        end

        return 1'b1;
    end
    endfunction

    assign sq_occupancy_w = sq_tail - sq_head;
    assign cq_occupancy_w = cq_tail - cq_head;
    assign cq_space_w     = (cq_depth > cq_occupancy_w) ? (cq_depth - cq_occupancy_w) : 32'd0;

    assign sq_index_calc_w      = (sq_depth != 32'd0) ? (sq_head % sq_depth) : 32'd0;
    assign cq_index_calc_w      = (cq_depth != 32'd0) ? (cq_tail % cq_depth) : 32'd0;
    assign sq_offset_calc_w     = {32'h0000_0000, sq_index_calc_w} * {32'h0000_0000, sq_stride};
    assign cq_offset_calc_w     = {32'h0000_0000, cq_index_calc_w} * {32'h0000_0000, cq_stride};
    assign sq_entry_addr_calc_w = {32'h0000_0000, sq_base_addr} + sq_offset_calc_w;
    assign cq_entry_addr_calc_w = {32'h0000_0000, cq_base_addr} + cq_offset_calc_w;
    assign desc_span_calc_w     = {32'h0000_0000, cmd3_w} * {32'h0000_0000, cmd4_w};

    assign mem_guard_active_w     = mem_guard_control[MEM_GUARD_CONTROL_ENABLE] &&
                                    mem_guard_control[MEM_GUARD_CONTROL_STRICT_REJECT];
    assign mem_guard_sq_check_w   = mem_guard_active_w && mem_guard_control[MEM_GUARD_CONTROL_SQ_CHECK_ENABLE];
    assign mem_guard_cq_check_w   = mem_guard_active_w && mem_guard_control[MEM_GUARD_CONTROL_CQ_CHECK_ENABLE];
    assign mem_guard_desc_check_w = mem_guard_active_w && mem_guard_control[MEM_GUARD_CONTROL_DESC_CHECK_ENABLE];

    always_comb begin
        sq_guard_detail_code_w = P27_DETAIL_SQ_RANGE;
        cq_guard_detail_code_w = P27_DETAIL_CQ_RANGE;
        desc_guard_detail_code_w = P27_DETAIL_DESC_RANGE;

        sq_guard_ok_w = !mem_guard_sq_check_w ||
                        p27_range_ok(sq_entry_addr_calc_w,
                                      P27_SQ_ENTRY_SIZE_BYTES,
                                      mem_guard_sq_base,
                                      mem_guard_sq_limit,
                                      sq_guard_detail_code_w);
        cq_guard_ok_w = !mem_guard_cq_check_w ||
                        p27_range_ok(cq_entry_addr_calc_w,
                                      P27_CQ_ENTRY_SIZE_BYTES,
                                      mem_guard_cq_base,
                                      mem_guard_cq_limit,
                                      cq_guard_detail_code_w);
        desc_guard_ok_w = !mem_guard_desc_check_w ||
                          p27_range_ok({32'h0000_0000, cmd2_w},
                                        desc_span_calc_w[31:0],
                                        mem_guard_desc_base,
                                        mem_guard_desc_limit,
                                        desc_guard_detail_code_w);

        if (desc_span_calc_w[63:32] != 32'h0000_0000) begin
            desc_guard_ok_w = 1'b0;
            desc_guard_detail_code_w = P27_DETAIL_ADDR_OVERFLOW;
        end

        if (sq_guard_detail_code_w == 8'h00) begin
            sq_guard_detail_code_w = P27_DETAIL_SQ_RANGE;
        end
        if (cq_guard_detail_code_w == 8'h00) begin
            cq_guard_detail_code_w = P27_DETAIL_CQ_RANGE;
        end
        if (desc_guard_detail_code_w == 8'h00) begin
            desc_guard_detail_code_w = P27_DETAIL_DESC_RANGE;
        end

        sq_guard_status_w = p27_status_for_detail(sq_guard_detail_code_w, P27_DOMAIN_SQ);
        cq_guard_status_w = p27_status_for_detail(cq_guard_detail_code_w, P27_DOMAIN_CQ);
        desc_guard_status_w = p27_status_for_detail(desc_guard_detail_code_w, P27_DOMAIN_DESC);
    end

    assign sq_empty_w = (sq_head == sq_tail);
    assign cq_full_w  = (cq_occupancy_w >= cq_depth);

    assign ptr_valid_w = (sq_occupancy_w <= sq_depth) &&
                         (cq_occupancy_w <= cq_depth);

    assign cfg_valid_w =
        (sq_base_addr[AXI_SIZE_VALUE-1:0] == '0) &&
        (cq_base_addr[AXI_SIZE_VALUE-1:0] == '0) &&
        (sq_depth != 32'd0) &&
        (cq_depth != 32'd0) &&
        (sq_depth <= P19_QUEUE_MAX_DEPTH_U32) &&
        (cq_depth <= P19_QUEUE_MAX_DEPTH_U32) &&
        (sq_stride == EXPECTED_SQ_STRIDE) &&
        (cq_stride == EXPECTED_CQ_STRIDE);

    assign cmd0_w = cmd_words_q[0];
    assign cmd1_w = cmd_words_q[1];
    assign cmd2_w = cmd_words_q[2];
    assign cmd3_w = cmd_words_q[3];
    assign cmd4_w = cmd_words_q[4];
    assign cmd5_w = cmd_words_q[5];
    assign cmd6_w = cmd_words_q[6];

    assign cmd_control_valid_w      = cmd0_w[0];
    assign cmd_control_opcode_w     = cmd0_w[7:1];
    assign cmd_control_completion_w = cmd0_w[8];
    assign cmd_control_stop_w       = cmd0_w[9];
    assign cmd_control_rsvd_zero_w  = (cmd0_w[31:10] == 22'd0);
    assign cmd_desc_base_aligned_w  = (cmd2_w[AXI_SIZE_VALUE-1:0] == '0);
    assign cmd_desc_count_valid_w   = (cmd3_w != 32'd0) && (cmd3_w <= P19_MAX_DESC_COUNT_U32);
    assign cmd_desc_stride_valid_w  = (cmd4_w != 32'd0) && (cmd4_w[AXI_SIZE_VALUE-1:0] == '0);

    always_comb begin
        validation_error_detail_w = ERR_NONE;

        if (!cmd_control_valid_w) begin
            validation_error_detail_w = ERR_CMD_VALID_ZERO;
        end else if (cmd_control_opcode_w != P19_FIRST_OPCODE_U7) begin
            validation_error_detail_w = ERR_CMD_BAD_OPCODE;
        end else if (!cmd_control_completion_w) begin
            validation_error_detail_w = ERR_CMD_NO_COMPLETION;
        end else if (!cmd_control_rsvd_zero_w) begin
            validation_error_detail_w = ERR_CMD_RSVD_BITS;
        end else if (!cmd_desc_base_aligned_w) begin
            validation_error_detail_w = ERR_CMD_DESC_UNALIGNED;
        end else if (cmd3_w == 32'd0) begin
            validation_error_detail_w = ERR_CMD_DESC_COUNT_ZERO;
        end else if (cmd3_w > P19_MAX_DESC_COUNT_U32) begin
            validation_error_detail_w = ERR_CMD_DESC_COUNT_RANGE;
        end else if (cmd4_w == 32'd0) begin
            validation_error_detail_w = ERR_CMD_STRIDE_ZERO;
        end else if (!cmd_desc_stride_valid_w) begin
            validation_error_detail_w = ERR_CMD_STRIDE_UNALIGNED;
        end
    end

    assign validation_pass_w = (validation_error_detail_w == ERR_NONE);

    // --------------------------------------------------------
    // Next-state logic
    // --------------------------------------------------------
    always_comb begin
        state_d              = state_q;
        rbeat_count_d        = rbeat_count_q;
        sq_index_d           = sq_index_q;
        cq_index_d           = cq_index_q;
        sq_head_snapshot_d   = sq_head_snapshot_q;
        cq_tail_snapshot_d   = cq_tail_snapshot_q;
        sq_entry_addr_d      = sq_entry_addr_q;
        cq_entry_addr_d      = cq_entry_addr_q;
        error_detail_d       = error_detail_q;
        fetched_cmd_reject_d = fetched_cmd_reject_q;

        done_status_d        = done_status_q;
        error_status_d       = error_status_q;
        reject_status_d      = reject_status_q;
        error_index_d        = error_index_q;
        last_cmd_tag_d       = last_cmd_tag_q;
        last_cmd_control_d   = last_cmd_control_q;

        for (int i = 0; i < CMD_WORDS; i++) begin
            cmd_words_d[i] = cmd_words_q[i];
        end

        queue_drained_pulse       = 1'b0;
        queue_cmd_fetched_pulse   = 1'b0;
        queue_cmd_validated_pulse = 1'b0;
        queue_error_pulse         = 1'b0;
        queue_reject_pulse        = 1'b0;
        queue_cq_full_stall       = 1'b0;

        mem_guard_check_pulse           = 1'b0;
        mem_guard_error_pulse           = 1'b0;
        mem_guard_error_status          = 32'h0000_0000;
        mem_guard_reject_status         = 32'h0000_0000;
        mem_guard_error_detail          = 32'h0000_0000;
        mem_guard_error_addr            = '0;
        mem_guard_error_size_bytes      = 32'h0000_0000;
        mem_guard_error_domain          = 32'h0000_0000;
        mem_guard_last_check_addr       = '0;
        mem_guard_last_check_size_bytes = 32'h0000_0000;
        mem_guard_last_check_domain     = 32'h0000_0000;

        cmd_axi_arvalid = 1'b0;
        cmd_axi_rready  = 1'b0;

        if (clear_done_pulse) begin
            done_status_d = 32'd0;
        end

        if (clear_error_pulse) begin
            error_status_d  = 32'd0;
            reject_status_d = 32'd0;
            error_detail_d  = ERR_NONE;
            error_index_d   = 32'd0;
        end

        unique case (state_q)
            Q_IDLE: begin
                rbeat_count_d        = 4'd0;
                fetched_cmd_reject_d = 1'b0;
                error_detail_d       = ERR_NONE;

                if (start_queue_pulse) begin
                    if (!queue_enable) begin
                        reject_status_d[Q_REJ_QUEUE_DISABLED] = 1'b1;
                        error_detail_d = ERR_DISABLED;
                        queue_reject_pulse = 1'b1;
                        state_d = Q_ERROR;
                    end else if (!cfg_valid_w) begin
                        reject_status_d[Q_REJ_INVALID_CFG] = 1'b1;
                        error_detail_d = ERR_INVALID_CFG;
                        queue_reject_pulse = 1'b1;
                        state_d = Q_ERROR;
                    end else if (!ptr_valid_w) begin
                        error_status_d[Q_ERR_BAD_POINTER] = 1'b1;
                        reject_status_d[Q_REJ_BAD_POINTER] = 1'b1;
                        error_detail_d = ERR_BAD_POINTER;
                        error_index_d  = {16'd0, cq_tail[7:0], sq_head[7:0]};
                        queue_reject_pulse = 1'b1;
                        state_d = Q_ERROR;
                    end else begin
                        done_status_d[Q_DONE_STARTED] = 1'b1;
                        state_d = Q_CHECK_READY;
                    end
                end
            end

            Q_CHECK_READY: begin
                if (!queue_enable) begin
                    reject_status_d[Q_REJ_QUEUE_DISABLED] = 1'b1;
                    error_detail_d = ERR_DISABLED;
                    queue_reject_pulse = 1'b1;
                    state_d = Q_ERROR;
                end else if (!cfg_valid_w) begin
                    reject_status_d[Q_REJ_INVALID_CFG] = 1'b1;
                    error_detail_d = ERR_INVALID_CFG;
                    queue_reject_pulse = 1'b1;
                    state_d = Q_ERROR;
                end else if (!ptr_valid_w) begin
                    error_status_d[Q_ERR_BAD_POINTER] = 1'b1;
                    reject_status_d[Q_REJ_BAD_POINTER] = 1'b1;
                    error_detail_d = ERR_BAD_POINTER;
                    error_index_d  = {16'd0, cq_tail[7:0], sq_head[7:0]};
                    queue_reject_pulse = 1'b1;
                    state_d = Q_ERROR;
                end else if (sq_empty_w) begin
                    done_status_d[Q_DONE_DRAINED] = 1'b1;
                    queue_drained_pulse = 1'b1;
                    state_d = Q_DRAINED;
                end else if (cq_full_w) begin
                    queue_cq_full_stall = 1'b1;
                    state_d = Q_CHECK_READY;
                end else if (!underlying_idle) begin
                    state_d = Q_CHECK_READY;
                end else if (!sq_guard_ok_w) begin
                    error_status_d[Q_ERR_MEMORY_GUARD] = 1'b1;
                    error_detail_d = p27_make_detail(sq_guard_detail_code_w,
                                                      P27_DOMAIN_SQ[7:0],
                                                      sq_index_calc_w[7:0],
                                                      {4'h0, Q_CHECK_READY});
                    error_index_d  = {16'd0, cq_index_calc_w[7:0], sq_index_calc_w[7:0]};
                    queue_error_pulse = 1'b1;

                    mem_guard_check_pulse           = 1'b1;
                    mem_guard_error_pulse           = 1'b1;
                    mem_guard_error_status          = sq_guard_status_w;
                    mem_guard_error_detail          = error_detail_d;
                    mem_guard_error_addr            = sq_entry_addr_calc_w[ADDR_WIDTH-1:0];
                    mem_guard_error_size_bytes      = P27_SQ_ENTRY_SIZE_BYTES;
                    mem_guard_error_domain          = P27_DOMAIN_SQ;
                    mem_guard_last_check_addr       = sq_entry_addr_calc_w[ADDR_WIDTH-1:0];
                    mem_guard_last_check_size_bytes = P27_SQ_ENTRY_SIZE_BYTES;
                    mem_guard_last_check_domain     = P27_DOMAIN_SQ;

                    state_d = Q_ERROR;
                end else if (!cq_guard_ok_w) begin
                    error_status_d[Q_ERR_MEMORY_GUARD] = 1'b1;
                    error_detail_d = p27_make_detail(cq_guard_detail_code_w,
                                                      P27_DOMAIN_CQ[7:0],
                                                      cq_index_calc_w[7:0],
                                                      {4'h0, Q_CHECK_READY});
                    error_index_d  = {16'd0, cq_index_calc_w[7:0], sq_index_calc_w[7:0]};
                    queue_error_pulse = 1'b1;

                    mem_guard_check_pulse           = 1'b1;
                    mem_guard_error_pulse           = 1'b1;
                    mem_guard_error_status          = cq_guard_status_w;
                    mem_guard_error_detail          = error_detail_d;
                    mem_guard_error_addr            = cq_entry_addr_calc_w[ADDR_WIDTH-1:0];
                    mem_guard_error_size_bytes      = P27_CQ_ENTRY_SIZE_BYTES;
                    mem_guard_error_domain          = P27_DOMAIN_CQ;
                    mem_guard_last_check_addr       = cq_entry_addr_calc_w[ADDR_WIDTH-1:0];
                    mem_guard_last_check_size_bytes = P27_CQ_ENTRY_SIZE_BYTES;
                    mem_guard_last_check_domain     = P27_DOMAIN_CQ;

                    state_d = Q_ERROR;
                end else begin
                    if (mem_guard_sq_check_w) begin
                        mem_guard_check_pulse           = 1'b1;
                        mem_guard_last_check_addr       = sq_entry_addr_calc_w[ADDR_WIDTH-1:0];
                        mem_guard_last_check_size_bytes = P27_SQ_ENTRY_SIZE_BYTES;
                        mem_guard_last_check_domain     = P27_DOMAIN_SQ;
                    end

                    sq_head_snapshot_d = sq_head;
                    cq_tail_snapshot_d = cq_tail;
                    sq_index_d         = sq_index_calc_w[7:0];
                    cq_index_d         = cq_index_calc_w[7:0];
                    sq_entry_addr_d    = sq_entry_addr_calc_w[ADDR_WIDTH-1:0];
                    cq_entry_addr_d    = cq_entry_addr_calc_w[ADDR_WIDTH-1:0];
                    rbeat_count_d      = 4'd0;

                    for (int i = 0; i < CMD_WORDS; i++) begin
                        cmd_words_d[i] = 32'd0;
                    end

                    state_d = Q_ISSUE_AR;
                end
            end

            Q_ISSUE_AR: begin
                cmd_axi_arvalid = 1'b1;
                if (cmd_axi_arready) begin
                    state_d = Q_READ_CMD;
                end
            end

            Q_READ_CMD: begin
                cmd_axi_rready = 1'b1;
                if (cmd_axi_rvalid) begin
                    if (cmd_axi_rresp != AXI_RESP_OKAY) begin
                        error_status_d[Q_ERR_CMD_FETCH] = 1'b1;
                        error_detail_d = ERR_AR_RRESP;
                        error_index_d  = {16'd0, cq_index_q, sq_index_q};
                        queue_error_pulse = 1'b1;
                        state_d = Q_ERROR;
                    end else begin
                        if (WORDS_PER_BEAT == 2) begin
                            cmd_words_d[rbeat_count_q * 2]     = cmd_axi_rdata[31:0];
                            cmd_words_d[(rbeat_count_q * 2)+1] = cmd_axi_rdata[63:32];
                        end else begin
                            cmd_words_d[rbeat_count_q] = cmd_axi_rdata[31:0];
                        end

                        if ((rbeat_count_q != (CMD_ENTRY_BEATS-1)) && cmd_axi_rlast) begin
                            error_status_d[Q_ERR_CMD_FETCH] = 1'b1;
                            error_detail_d = ERR_AR_EARLY_RLAST;
                            error_index_d  = {16'd0, cq_index_q, sq_index_q};
                            queue_error_pulse = 1'b1;
                            state_d = Q_ERROR;
                        end else if (rbeat_count_q == (CMD_ENTRY_BEATS-1)) begin
                            if (!cmd_axi_rlast) begin
                                error_status_d[Q_ERR_CMD_FETCH] = 1'b1;
                                error_detail_d = ERR_AR_MISSING_RLAST;
                                error_index_d  = {16'd0, cq_index_q, sq_index_q};
                                queue_error_pulse = 1'b1;
                                state_d = Q_ERROR;
                            end else begin
                                done_status_d[Q_DONE_CMD_FETCHED] = 1'b1;
                                queue_cmd_fetched_pulse = 1'b1;
                                state_d = Q_VALIDATE;
                            end
                        end else begin
                            rbeat_count_d = rbeat_count_q + 4'd1;
                        end
                    end
                end
            end

            Q_VALIDATE: begin
                last_cmd_tag_d     = cmd_words_q[1];
                last_cmd_control_d = cmd_words_q[0];
                error_index_d      = {16'd0, cq_index_q, sq_index_q};

                if (validation_pass_w && !desc_guard_ok_w) begin
                    error_status_d[Q_ERR_MEMORY_GUARD] = 1'b1;
                    fetched_cmd_reject_d = 1'b1;
                    error_detail_d = p27_make_detail(desc_guard_detail_code_w,
                                                      P27_DOMAIN_DESC[7:0],
                                                      sq_index_q,
                                                      {4'h0, Q_VALIDATE});
                    queue_error_pulse = 1'b1;

                    mem_guard_check_pulse           = 1'b1;
                    mem_guard_error_pulse           = 1'b1;
                    mem_guard_error_status          = desc_guard_status_w;
                    mem_guard_error_detail          = error_detail_d;
                    mem_guard_error_addr            = cmd2_w[ADDR_WIDTH-1:0];
                    mem_guard_error_size_bytes      = desc_span_calc_w[31:0];
                    mem_guard_error_domain          = P27_DOMAIN_DESC;
                    mem_guard_last_check_addr       = cmd2_w[ADDR_WIDTH-1:0];
                    mem_guard_last_check_size_bytes = desc_span_calc_w[31:0];
                    mem_guard_last_check_domain     = P27_DOMAIN_DESC;
                end else if (validation_pass_w) begin
                    done_status_d[Q_DONE_CMD_VALIDATED] = 1'b1;
                    fetched_cmd_reject_d = 1'b0;
                    error_detail_d = ERR_NONE;
                    queue_cmd_validated_pulse = 1'b1;

                    if (mem_guard_desc_check_w) begin
                        mem_guard_check_pulse           = 1'b1;
                        mem_guard_last_check_addr       = cmd2_w[ADDR_WIDTH-1:0];
                        mem_guard_last_check_size_bytes = desc_span_calc_w[31:0];
                        mem_guard_last_check_domain     = P27_DOMAIN_DESC;
                    end
                end else begin
                    error_status_d[Q_ERR_CMD_VALIDATION] = 1'b1;
                    fetched_cmd_reject_d = 1'b1;
                    error_detail_d = validation_error_detail_w;
                    queue_error_pulse = 1'b1;
                end

                state_d = Q_PRESENT;
            end

            Q_PRESENT: begin
                if (cmd_ready) begin
                    if (run_until_empty && !cmd_stop_after_this && !fetched_cmd_reject_q && !stop_on_error) begin
                        state_d = Q_DONE;
                    end else begin
                        state_d = Q_DONE;
                    end
                end
            end

            Q_DRAINED: begin
                if (run_until_empty && queue_enable && !sq_empty_w && !cq_full_w) begin
                    state_d = Q_CHECK_READY;
                end else if (start_queue_pulse) begin
                    state_d = Q_CHECK_READY;
                end else begin
                    state_d = Q_IDLE;
                end
            end

            Q_DONE: begin
                state_d = Q_IDLE;
            end

            Q_ERROR: begin
                if (clear_error_pulse) begin
                    state_d = Q_IDLE;
                end else begin
                    state_d = Q_ERROR;
                end
            end

            default: begin
                error_status_d[Q_ERR_INTERNAL] = 1'b1;
                error_detail_d = 32'h0000_0BAD;
                queue_error_pulse = 1'b1;
                state_d = Q_ERROR;
            end
        endcase
    end

    // --------------------------------------------------------
    // Registers
    // --------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q              <= Q_IDLE;
            rbeat_count_q        <= 4'd0;
            sq_index_q           <= 8'd0;
            cq_index_q           <= 8'd0;
            sq_head_snapshot_q   <= 32'd0;
            cq_tail_snapshot_q   <= 32'd0;
            sq_entry_addr_q      <= '0;
            cq_entry_addr_q      <= '0;
            error_detail_q       <= ERR_NONE;
            fetched_cmd_reject_q <= 1'b0;
            done_status_q        <= 32'd0;
            error_status_q       <= 32'd0;
            reject_status_q      <= 32'd0;
            error_index_q        <= 32'd0;
            last_cmd_tag_q       <= 32'd0;
            last_cmd_control_q   <= 32'd0;

            for (int i = 0; i < CMD_WORDS; i++) begin
                cmd_words_q[i] <= 32'd0;
            end
        end else begin
            state_q              <= state_d;
            rbeat_count_q        <= rbeat_count_d;
            sq_index_q           <= sq_index_d;
            cq_index_q           <= cq_index_d;
            sq_head_snapshot_q   <= sq_head_snapshot_d;
            cq_tail_snapshot_q   <= cq_tail_snapshot_d;
            sq_entry_addr_q      <= sq_entry_addr_d;
            cq_entry_addr_q      <= cq_entry_addr_d;
            error_detail_q       <= error_detail_d;
            fetched_cmd_reject_q <= fetched_cmd_reject_d;
            done_status_q        <= done_status_d;
            error_status_q       <= error_status_d;
            reject_status_q      <= reject_status_d;
            error_index_q        <= error_index_d;
            last_cmd_tag_q       <= last_cmd_tag_d;
            last_cmd_control_q   <= last_cmd_control_d;

            for (int i = 0; i < CMD_WORDS; i++) begin
                cmd_words_q[i] <= cmd_words_d[i];
            end
        end
    end

    // --------------------------------------------------------
    // Outputs
    // --------------------------------------------------------
    assign cmd_axi_arid    = '0;
    assign cmd_axi_araddr  = sq_entry_addr_q;
    assign cmd_axi_arlen   = CMD_ENTRY_BEATS_U8 - 8'd1;
    assign cmd_axi_arsize  = AXI_SIZE_U3;
    assign cmd_axi_arburst = AXI_BURST_INCR;

    assign cmd_valid                = (state_q == Q_PRESENT);
    assign cmd_reject               = fetched_cmd_reject_q;
    assign cmd_error_detail         = error_detail_q;
    assign cmd_control              = cmd_words_q[0];
    assign cmd_user_tag             = cmd_words_q[1];
    assign cmd_desc_base_addr       = cmd_words_q[2][ADDR_WIDTH-1:0];
    assign cmd_desc_count           = cmd_words_q[3];
    assign cmd_desc_stride          = cmd_words_q[4];
    assign cmd_completion_flags     = cmd_words_q[5];
    assign cmd_timeout_cycles       = cmd_words_q[6];
    assign cmd_completion_base_addr = cq_entry_addr_q;
    assign cmd_stop_after_this      = cmd_words_q[0][9];
    assign cmd_sq_head_snapshot     = sq_head_snapshot_q;
    assign cmd_cq_tail_snapshot     = cq_tail_snapshot_q;
    assign cmd_sq_index             = sq_index_q;
    assign cmd_cq_index             = cq_index_q;

    assign queue_busy          = (state_q != Q_IDLE) && (state_q != Q_DRAINED) && (state_q != Q_ERROR);
    assign queue_done_status   = done_status_q;
    assign queue_error_status  = error_status_q;
    assign queue_reject_status = reject_status_q;
    assign queue_state         = {28'd0, state_q};
    assign queue_current_index = {16'd0, cq_index_q, sq_index_q};
    assign queue_error_index   = error_index_q;
    assign queue_error_detail  = error_detail_q;
    assign queue_last_cmd_tag  = last_cmd_tag_q;
    assign queue_last_cmd_control = last_cmd_control_q;
    assign queue_sq_occupancy  = sq_occupancy_w;
    assign queue_cq_occupancy  = cq_occupancy_w;
    assign queue_cq_space      = cq_space_w;

    // P24C baseline is defined for 64-bit AXI data width.
    // Keep this as a simulation-time guard rather than adding a second unverified path.
    initial begin
        if (DATA_WIDTH != 64) begin
            $error("ai_accel_queue_fetch_controller P24C supports DATA_WIDTH=64 in the current baseline");
        end
        if (SQ_ENTRY_BYTES != 64) begin
            $error("ai_accel_queue_fetch_controller P19C expects SQ_ENTRY_BYTES=64");
        end
        if (CQ_ENTRY_BYTES != 64) begin
            $error("ai_accel_queue_fetch_controller P19C expects CQ_ENTRY_BYTES=64");
        end
    end

endmodule
