// File: rtl/csr/ai_accel_csr_regs.sv

`ifndef AI_ACCEL_CSR_REGS_SV
`define AI_ACCEL_CSR_REGS_SV

module ai_accel_csr_regs #(
    parameter int ADDR_WIDTH      = 32,
    parameter int GEMM_DIM_WIDTH  = 8,
    parameter int CSR_ADDR_WIDTH  = 12,
    parameter int CSR_DATA_WIDTH  = 32,

    parameter logic [31:0] CSR_VERSION_VALUE        = 32'h0001_0014,
    parameter logic [31:0] CSR_JOB_VERSION_VALUE        = 32'h0001_0015,
    parameter logic [31:0] CSR_RECIPE_VERSION_VALUE     = 32'h0001_0016,
    parameter logic [31:0] CSR_DESC_FETCH_VERSION_VALUE = 32'h0001_0017,
    parameter logic [31:0] CSR_COMPLETION_WB_VERSION_VALUE = 32'h0001_0018,
    parameter logic [31:0] CSR_QUEUE_VERSION_VALUE         = 32'h0001_0019,
    parameter logic [31:0] CSR_EVENT_VERSION_VALUE         = 32'h0001_0022,
    parameter logic [31:0] CSR_MEM_GUARD_VERSION_VALUE     = 32'h0001_0027,
    parameter logic [31:0] CSR_EVENT_CONTROL_RESET         = 32'h0000_0004,
    parameter int          P16_RECIPE_QUEUE_DEPTH       = 4
)(
    input  logic clk,
    input  logic rst_n,

    axi_lite_if.slave csr_if,

    // ------------------------------------------------------------
    // GEMM control/config outputs
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

    // ------------------------------------------------------------
    // DMA load control/config outputs
    // ------------------------------------------------------------
    output logic                  dma_load_start_pulse,
    output logic [ADDR_WIDTH-1:0] dma_src_base_addr,
    output logic [ADDR_WIDTH-1:0] dma_dst_base_addr,
    output logic [31:0]           dma_load_beats,

    // ------------------------------------------------------------
    // AXI-Stream preload control/config outputs
    // ------------------------------------------------------------
    output logic                  axis_load_start_pulse,
    output logic [ADDR_WIDTH-1:0] axis_src_base_addr,
    output logic [ADDR_WIDTH-1:0] axis_dst_base_addr,
    output logic [31:0]           axis_load_beats,

    // ------------------------------------------------------------
    // Direct Stream preload control/config outputs
    // ------------------------------------------------------------
    output logic                  ds_load_start_pulse,
    output logic [ADDR_WIDTH-1:0] ds_src_base_addr,
    output logic [ADDR_WIDTH-1:0] ds_dst_base_addr,
    output logic [31:0]           ds_load_beats,
    output logic                  ds_operand_sel,

    // ------------------------------------------------------------
    // DMA store control/config outputs
    // ------------------------------------------------------------
    output logic                  dma_store_start_pulse,
    output logic [ADDR_WIDTH-1:0] dma_store_src_base_addr,
    output logic [ADDR_WIDTH-1:0] dma_store_dst_base_addr,
    output logic [31:0]           dma_store_byte_count,

    // ------------------------------------------------------------
    // P15 job descriptor / sequencer control outputs
    // ------------------------------------------------------------
    output logic                  job_start_pulse,
    output logic                  job_clear_done_pulse,
    output logic                  job_clear_error_pulse,
    output logic                  job_clear_perf_pulse,

    output logic [1:0]            job_input_mode,
    output logic [1:0]            job_output_mode,
    output logic                  job_accumulate_enable,
    output logic                  job_clear_p14_sticky_on_start,

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
    // P16 recipe descriptor / queue control outputs
    // ------------------------------------------------------------
    output logic                  recipe_start_pulse,
    output logic                  recipe_clear_done_pulse,
    output logic                  recipe_clear_error_pulse,
    output logic                  recipe_clear_perf_pulse,
    output logic                  recipe_clear_slot_status_pulse,

    output logic [3:0]            recipe_count,
    output logic [3:0]            recipe_start_slot,
    output logic                  recipe_stop_on_error,
    output logic                  recipe_clear_job_sticky_each_slot,
    output logic                  recipe_accumulate_perf,
    output logic                  recipe_allow_slot_writes_while_busy,

    output logic [31:0]           recipe_slot_control          [P16_RECIPE_QUEUE_DEPTH],
    output logic [ADDR_WIDTH-1:0] recipe_slot_base_addr_a      [P16_RECIPE_QUEUE_DEPTH],
    output logic [ADDR_WIDTH-1:0] recipe_slot_base_addr_b      [P16_RECIPE_QUEUE_DEPTH],
    output logic [ADDR_WIDTH-1:0] recipe_slot_base_addr_c      [P16_RECIPE_QUEUE_DEPTH],
    output logic [GEMM_DIM_WIDTH-1:0] recipe_slot_dim_m        [P16_RECIPE_QUEUE_DEPTH],
    output logic [GEMM_DIM_WIDTH-1:0] recipe_slot_dim_n        [P16_RECIPE_QUEUE_DEPTH],
    output logic [GEMM_DIM_WIDTH-1:0] recipe_slot_dim_k        [P16_RECIPE_QUEUE_DEPTH],
    output logic [ADDR_WIDTH-1:0] recipe_slot_a_src_base_addr  [P16_RECIPE_QUEUE_DEPTH],
    output logic [ADDR_WIDTH-1:0] recipe_slot_a_dst_base_addr  [P16_RECIPE_QUEUE_DEPTH],
    output logic [31:0]           recipe_slot_a_load_beats     [P16_RECIPE_QUEUE_DEPTH],
    output logic [ADDR_WIDTH-1:0] recipe_slot_b_src_base_addr  [P16_RECIPE_QUEUE_DEPTH],
    output logic [ADDR_WIDTH-1:0] recipe_slot_b_dst_base_addr  [P16_RECIPE_QUEUE_DEPTH],
    output logic [31:0]           recipe_slot_b_load_beats     [P16_RECIPE_QUEUE_DEPTH],
    output logic [ADDR_WIDTH-1:0] recipe_slot_store_src_base_addr [P16_RECIPE_QUEUE_DEPTH],
    output logic [ADDR_WIDTH-1:0] recipe_slot_store_dst_base_addr [P16_RECIPE_QUEUE_DEPTH],
    output logic [31:0]           recipe_slot_store_byte_count [P16_RECIPE_QUEUE_DEPTH],
    output logic [31:0]           recipe_slot_user_tag         [P16_RECIPE_QUEUE_DEPTH],

    // ------------------------------------------------------------
    // P17 descriptor-fetch CSR control outputs
    // ------------------------------------------------------------
    output logic                  desc_fetch_start_pulse,
    output logic                  desc_fetch_clear_done_pulse,
    output logic                  desc_fetch_clear_error_pulse,

    output logic [ADDR_WIDTH-1:0] desc_fetch_base_addr,
    output logic [3:0]            desc_fetch_count,
    output logic [15:0]           desc_fetch_stride_bytes,

    // ------------------------------------------------------------
    // P17 descriptor-fetch status inputs
    // ------------------------------------------------------------
    input  logic                  desc_fetch_busy,
    input  logic                  desc_fetch_done,
    input  logic                  desc_fetch_error,
    input  logic                  desc_fetch_reject,
    input  logic [31:0]           desc_fetch_error_status,
    input  logic [31:0]           desc_fetch_reject_status,
    input  logic [3:0]            desc_fetch_current_index,
    input  logic [3:0]            desc_fetch_fetched_count,
    input  logic                  desc_fetch_snapshot_valid,
    input  logic [3:0]            desc_fetch_recipe_count,

    // ------------------------------------------------------------
    // P18 completion-writeback CSR control outputs
    // ------------------------------------------------------------
    output logic                  completion_wb_start_pulse,
    output logic                  completion_wb_clear_done_pulse,
    output logic                  completion_wb_clear_error_pulse,

    output logic                  completion_wb_enable,
    output logic                  completion_wb_overall_done,
    output logic                  completion_wb_overall_error,
    output logic                  completion_wb_overall_reject,
    output logic [ADDR_WIDTH-1:0] completion_wb_base_addr,
    output logic [31:0]           completion_wb_status_flags,
    output logic [31:0]           completion_wb_user_tag,
    output logic [7:0]            completion_wb_programmed_count,
    output logic [7:0]            completion_wb_fetched_count,
    output logic [7:0]            completion_wb_completed_count,
    output logic [31:0]           completion_wb_recipe_done_status,
    output logic [31:0]           completion_wb_recipe_error_status,
    output logic [31:0]           completion_wb_recipe_reject_status,
    output logic [31:0]           completion_wb_perf_mac_count,
    output logic [31:0]           completion_wb_error_detail,

    // ------------------------------------------------------------
    // P18 completion-writeback status inputs
    // ------------------------------------------------------------
    input  logic                  completion_wb_busy,
    input  logic                  completion_wb_done,
    input  logic                  completion_wb_error,
    input  logic                  completion_wb_reject,
    input  logic [31:0]           completion_wb_error_status,
    input  logic [31:0]           completion_wb_reject_status,
    input  logic [31:0]           completion_wb_state,
    input  logic [3:0]            completion_wb_current_write_step,
    input  logic [7:0]            completion_wb_written_beats,


    // ------------------------------------------------------------
    // P19 command/completion queue CSR control outputs
    // ------------------------------------------------------------
    output logic                  queue_start_pulse,
    output logic                  queue_stop_pulse,
    output logic                  queue_clear_done_pulse,
    output logic                  queue_clear_error_pulse,

    output logic                  queue_enable,
    output logic                  queue_run_until_empty,
    output logic                  queue_stop_on_error,

    output logic [ADDR_WIDTH-1:0] queue_sq_base_addr,
    output logic [31:0]           queue_sq_depth,
    output logic [31:0]           queue_sq_head,
    output logic [31:0]           queue_sq_tail,
    output logic [31:0]           queue_sq_stride,

    output logic [ADDR_WIDTH-1:0] queue_cq_base_addr,
    output logic [31:0]           queue_cq_depth,
    output logic [31:0]           queue_cq_head,
    output logic [31:0]           queue_cq_tail,
    output logic [31:0]           queue_cq_stride,

    // ------------------------------------------------------------
    // P19 command/completion queue status inputs
    // ------------------------------------------------------------
    input  logic                  queue_busy,
    input  logic                  queue_drained_pulse,
    input  logic                  queue_cmd_fetched_pulse,
    input  logic                  queue_cmd_validated_pulse,
    input  logic                  queue_error_pulse,
    input  logic                  queue_reject_pulse,
    input  logic                  queue_cq_full_stall,

    input  logic [31:0]           queue_done_status,
    input  logic [31:0]           queue_error_status,
    input  logic [31:0]           queue_reject_status,
    input  logic [31:0]           queue_state,
    input  logic [31:0]           queue_current_index,
    input  logic [31:0]           queue_error_index,
    input  logic [31:0]           queue_error_detail,
    input  logic [31:0]           queue_last_cmd_tag,
    input  logic [31:0]           queue_last_cmd_control,
    input  logic [31:0]           queue_sq_occupancy,
    input  logic [31:0]           queue_cq_occupancy,
    input  logic [31:0]           queue_cq_space,
    input  logic                  queue_completion_commit_pulse,
    input  logic                  queue_completion_error_pulse,

    // ------------------------------------------------------------
    // P27 memory access guard CSR configuration outputs
    // ------------------------------------------------------------
    output logic [31:0]           mem_guard_control,
    output logic [ADDR_WIDTH-1:0] mem_guard_sq_base,
    output logic [ADDR_WIDTH-1:0] mem_guard_sq_limit,
    output logic [ADDR_WIDTH-1:0] mem_guard_cq_base,
    output logic [ADDR_WIDTH-1:0] mem_guard_cq_limit,
    output logic [ADDR_WIDTH-1:0] mem_guard_desc_base,
    output logic [ADDR_WIDTH-1:0] mem_guard_desc_limit,
    output logic [ADDR_WIDTH-1:0] mem_guard_src_base,
    output logic [ADDR_WIDTH-1:0] mem_guard_src_limit,
    output logic [ADDR_WIDTH-1:0] mem_guard_dst_base,
    output logic [ADDR_WIDTH-1:0] mem_guard_dst_limit,

    // ------------------------------------------------------------
    // P27 memory access guard diagnostics from queue path
    // ------------------------------------------------------------
    input  logic                  mem_guard_check_pulse,
    input  logic                  mem_guard_error_pulse,
    input  logic [31:0]           mem_guard_error_status,
    input  logic [31:0]           mem_guard_reject_status,
    input  logic [31:0]           mem_guard_error_detail,
    input  logic [ADDR_WIDTH-1:0] mem_guard_error_addr,
    input  logic [31:0]           mem_guard_error_size_bytes,
    input  logic [31:0]           mem_guard_error_domain,
    input  logic [ADDR_WIDTH-1:0] mem_guard_last_check_addr,
    input  logic [31:0]           mem_guard_last_check_size_bytes,
    input  logic [31:0]           mem_guard_last_check_domain,

    // ------------------------------------------------------------
    // Live status inputs from the future P15 job sequencer
    // ------------------------------------------------------------
    input  logic                  job_busy,
    input  logic                  job_done,
    input  logic                  job_gemm_done,
    input  logic                  job_store_done,

    input  logic                  job_dma_load_error,
    input  logic                  job_axis_load_error,
    input  logic                  job_ds_load_error,
    input  logic                  job_dma_store_error,
    input  logic                  job_sequence_error,

    input  logic [31:0]           job_state,
    input  logic [31:0]           job_perf_busy_cycles,
    input  logic [31:0]           job_perf_mac_count,
    input  logic [31:0]           job_perf_output_count,

    // ------------------------------------------------------------
    // Live status inputs from the future P16 recipe sequencer
    // ------------------------------------------------------------
    input  logic                  recipe_busy,
    input  logic                  recipe_done,
    input  logic                  recipe_all_slots_done,
    input  logic                  recipe_final_store_done,

    input  logic                  recipe_slot_job_error,
    input  logic                  recipe_slot_job_reject,
    input  logic                  recipe_sequence_error,
    input  logic                  recipe_slot_range_error,
    input  logic                  recipe_slot_descriptor_error,

    input  logic [31:0]           recipe_state,
    input  logic [31:0]           recipe_current_slot,
    input  logic [31:0]           recipe_completed_count,
    input  logic [31:0]           recipe_slot_done_mask,
    input  logic [31:0]           recipe_slot_error_mask,
    input  logic [31:0]           recipe_slot_reject_mask,
    input  logic [31:0]           recipe_perf_busy_cycles,
    input  logic [31:0]           recipe_perf_mac_count,
    input  logic [31:0]           recipe_perf_output_count,

    // ------------------------------------------------------------
    // Live status inputs from the existing subsystem
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

    // ------------------------------------------------------------
    // GEMM performance counter inputs
    //
    // The existing subsystem keeps these values stable after GEMM
    // done until the next accepted GEMM start.  This CSR block
    // captures them into readable snapshot registers on acc_done.
    // ------------------------------------------------------------
    input  logic [31:0] gemm_perf_busy_cycles,
    input  logic [31:0] gemm_perf_mac_count,
    input  logic [31:0] gemm_perf_output_count,

    // ------------------------------------------------------------
    // P22 interrupt-lite event summary output
    // ------------------------------------------------------------
    output logic event_irq
);

    localparam int STRB_WIDTH = CSR_DATA_WIDTH / 8;

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    // ------------------------------------------------------------
    // Register offsets
    // ------------------------------------------------------------
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_VERSION_ADDR              = 12'h000;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMMAND_ADDR              = 12'h004;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_STATUS_ADDR               = 12'h008;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DONE_STATUS_ADDR          = 12'h00C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_ERROR_STATUS_ADDR         = 12'h010;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MODE_ADDR                 = 12'h014;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_CMD_REJECT_STATUS_ADDR    = 12'h018;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RESERVED_01C_ADDR         = 12'h01C;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_BASE_ADDR_A_ADDR          = 12'h020;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_BASE_ADDR_B_ADDR          = 12'h024;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_BASE_ADDR_C_ADDR          = 12'h028;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DIM_M_ADDR                = 12'h02C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DIM_N_ADDR                = 12'h030;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DIM_K_ADDR                = 12'h034;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RESERVED_038_ADDR         = 12'h038;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RESERVED_03C_ADDR         = 12'h03C;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DMA_LOAD_SRC_BASE_ADDR    = 12'h040;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DMA_LOAD_DST_BASE_ADDR    = 12'h044;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DMA_LOAD_BEATS_ADDR       = 12'h048;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RESERVED_04C_ADDR         = 12'h04C;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_AXIS_SRC_BASE_ADDR        = 12'h050;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_AXIS_DST_BASE_ADDR        = 12'h054;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_AXIS_LOAD_BEATS_ADDR      = 12'h058;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RESERVED_05C_ADDR         = 12'h05C;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DS_SRC_BASE_ADDR          = 12'h060;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DS_DST_BASE_ADDR          = 12'h064;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DS_LOAD_BEATS_ADDR        = 12'h068;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DS_CONTROL_ADDR           = 12'h06C;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DMA_STORE_SRC_BASE_ADDR   = 12'h070;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DMA_STORE_DST_BASE_ADDR   = 12'h074;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DMA_STORE_BYTE_COUNT_ADDR = 12'h078;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RESERVED_07C_ADDR         = 12'h07C;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_PERF_BUSY_CYCLES_ADDR     = 12'h080;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_PERF_MAC_COUNT_ADDR       = 12'h084;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_PERF_OUTPUT_COUNT_ADDR    = 12'h088;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RESERVED_08C_ADDR         = 12'h08C;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_VERSION_ADDR          = 12'h100;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_COMMAND_ADDR          = 12'h104;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_STATUS_ADDR           = 12'h108;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_DONE_STATUS_ADDR      = 12'h10C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_ERROR_STATUS_ADDR     = 12'h110;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_MODE_ADDR             = 12'h114;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_REJECT_STATUS_ADDR    = 12'h118;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_STATE_ADDR            = 12'h11C;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_BASE_ADDR_A_ADDR      = 12'h120;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_BASE_ADDR_B_ADDR      = 12'h124;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_BASE_ADDR_C_ADDR      = 12'h128;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_DIM_M_ADDR            = 12'h12C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_DIM_N_ADDR            = 12'h130;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_DIM_K_ADDR            = 12'h134;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_A_SRC_BASE_ADDR       = 12'h138;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_A_DST_BASE_ADDR       = 12'h13C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_A_LOAD_BEATS_ADDR     = 12'h140;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_RESERVED_144_ADDR     = 12'h144;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_B_SRC_BASE_ADDR       = 12'h148;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_B_DST_BASE_ADDR       = 12'h14C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_B_LOAD_BEATS_ADDR     = 12'h150;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_RESERVED_154_ADDR     = 12'h154;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_STORE_SRC_BASE_ADDR   = 12'h158;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_STORE_DST_BASE_ADDR   = 12'h15C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_STORE_BYTE_COUNT_ADDR = 12'h160;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_RESERVED_164_ADDR     = 12'h164;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_PERF_BUSY_CYCLES_ADDR = 12'h180;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_PERF_MAC_COUNT_ADDR   = 12'h184;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_PERF_OUTPUT_COUNT_ADDR= 12'h188;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_JOB_RESERVED_18C_ADDR     = 12'h18C;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_VERSION_ADDR       = 12'h200;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_COMMAND_ADDR       = 12'h204;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_STATUS_ADDR        = 12'h208;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_DONE_STATUS_ADDR   = 12'h20C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_ERROR_STATUS_ADDR  = 12'h210;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_CONTROL_ADDR       = 12'h214;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_REJECT_STATUS_ADDR = 12'h218;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_STATE_ADDR         = 12'h21C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_CURRENT_SLOT_ADDR  = 12'h220;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_COMPLETED_COUNT_ADDR = 12'h224;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_SLOT_DONE_MASK_ADDR  = 12'h228;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_SLOT_ERROR_MASK_ADDR = 12'h22C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_SLOT_REJECT_MASK_ADDR= 12'h230;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_RESERVED_234_ADDR  = 12'h234;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_PERF_BUSY_CYCLES_ADDR = 12'h280;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_PERF_MAC_COUNT_ADDR   = 12'h284;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_PERF_OUTPUT_COUNT_ADDR= 12'h288;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_RESERVED_28C_ADDR     = 12'h28C;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RECIPE_SLOT_BASE_ADDR = 12'h300;
    localparam int unsigned CSR_RECIPE_SLOT_STRIDE = 128;

    localparam logic [6:0] SLOT_CONTROL_OFFSET          = 7'h00;
    localparam logic [6:0] SLOT_BASE_ADDR_A_OFFSET      = 7'h04;
    localparam logic [6:0] SLOT_BASE_ADDR_B_OFFSET      = 7'h08;
    localparam logic [6:0] SLOT_BASE_ADDR_C_OFFSET      = 7'h0C;
    localparam logic [6:0] SLOT_DIM_M_OFFSET            = 7'h10;
    localparam logic [6:0] SLOT_DIM_N_OFFSET            = 7'h14;
    localparam logic [6:0] SLOT_DIM_K_OFFSET            = 7'h18;
    localparam logic [6:0] SLOT_A_SRC_BASE_OFFSET       = 7'h1C;
    localparam logic [6:0] SLOT_A_DST_BASE_OFFSET       = 7'h20;
    localparam logic [6:0] SLOT_A_LOAD_BEATS_OFFSET     = 7'h24;
    localparam logic [6:0] SLOT_B_SRC_BASE_OFFSET       = 7'h28;
    localparam logic [6:0] SLOT_B_DST_BASE_OFFSET       = 7'h2C;
    localparam logic [6:0] SLOT_B_LOAD_BEATS_OFFSET     = 7'h30;
    localparam logic [6:0] SLOT_STORE_SRC_BASE_OFFSET   = 7'h34;
    localparam logic [6:0] SLOT_STORE_DST_BASE_OFFSET   = 7'h38;
    localparam logic [6:0] SLOT_STORE_BYTE_COUNT_OFFSET = 7'h3C;
    localparam logic [6:0] SLOT_USER_TAG_OFFSET         = 7'h40;
    localparam logic [6:0] SLOT_RESERVED_44_OFFSET      = 7'h44;
    localparam logic [6:0] SLOT_RESERVED_48_OFFSET      = 7'h48;
    localparam logic [6:0] SLOT_RESERVED_4C_OFFSET      = 7'h4C;

    // P17 descriptor-fetch CSR window.  P17C uses this as a
    // CSR-level fetch smoke path only; P17D will bridge the fetched
    // snapshot into the P16 recipe sequencer.
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DESC_FETCH_VERSION_ADDR      = 12'h500;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DESC_FETCH_COMMAND_ADDR      = 12'h504;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DESC_FETCH_STATUS_ADDR       = 12'h508;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DESC_FETCH_DONE_STATUS_ADDR  = 12'h50C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DESC_FETCH_ERROR_STATUS_ADDR = 12'h510;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DESC_FETCH_REJECT_STATUS_ADDR= 12'h514;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DESC_FETCH_BASE_ADDR_ADDR    = 12'h518;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DESC_FETCH_COUNT_ADDR        = 12'h51C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DESC_FETCH_STRIDE_BYTES_ADDR = 12'h520;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DESC_FETCH_CURRENT_INDEX_ADDR= 12'h524;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DESC_FETCH_FETCHED_COUNT_ADDR= 12'h528;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DESC_FETCH_SNAPSHOT_STATUS_ADDR = 12'h52C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DESC_FETCH_RESERVED_530_ADDR = 12'h530;

    // P18 completion-writeback CSR window.
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMPLETION_WB_VERSION_ADDR        = 12'h540;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMPLETION_WB_COMMAND_ADDR        = 12'h544;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMPLETION_WB_STATUS_ADDR         = 12'h548;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMPLETION_WB_DONE_STATUS_ADDR    = 12'h54C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMPLETION_WB_ERROR_STATUS_ADDR   = 12'h550;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMPLETION_WB_REJECT_STATUS_ADDR  = 12'h554;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMPLETION_WB_CONTROL_ADDR        = 12'h558;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMPLETION_WB_BASE_ADDR_ADDR      = 12'h55C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMPLETION_WB_STATUS_FLAGS_ADDR   = 12'h560;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMPLETION_WB_USER_TAG_ADDR       = 12'h564;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMPLETION_WB_COUNTS_ADDR         = 12'h568;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMPLETION_WB_RECIPE_DONE_ADDR    = 12'h56C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMPLETION_WB_RECIPE_ERROR_ADDR   = 12'h570;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMPLETION_WB_RECIPE_REJECT_ADDR  = 12'h574;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMPLETION_WB_PERF_MAC_COUNT_ADDR = 12'h578;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMPLETION_WB_ERROR_DETAIL_ADDR   = 12'h57C;

    // P19 command/completion queue CSR window.
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_VERSION_ADDR          = 12'h580;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_COMMAND_ADDR          = 12'h584;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_STATUS_ADDR           = 12'h588;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_DONE_STATUS_ADDR      = 12'h58C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_ERROR_STATUS_ADDR     = 12'h590;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_CONTROL_ADDR          = 12'h594;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_REJECT_STATUS_ADDR    = 12'h598;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_STATE_ADDR            = 12'h59C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_SQ_BASE_ADDR          = 12'h5A0;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_SQ_DEPTH_ADDR         = 12'h5A4;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_SQ_HEAD_ADDR          = 12'h5A8;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_SQ_TAIL_ADDR          = 12'h5AC;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_SQ_STRIDE_ADDR        = 12'h5B0;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_CQ_BASE_ADDR          = 12'h5B4;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_CQ_DEPTH_ADDR         = 12'h5B8;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_CQ_HEAD_ADDR          = 12'h5BC;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_CQ_TAIL_ADDR          = 12'h5C0;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_CQ_STRIDE_ADDR        = 12'h5C4;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_CURRENT_INDEX_ADDR    = 12'h5C8;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_ERROR_INDEX_ADDR      = 12'h5CC;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_ERROR_DETAIL_ADDR     = 12'h5D0;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_LAST_CMD_TAG_ADDR     = 12'h5D4;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_LAST_CMD_CONTROL_ADDR = 12'h5D8;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_SQ_OCCUPANCY_ADDR     = 12'h5DC;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_CQ_OCCUPANCY_ADDR     = 12'h5E0;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_CQ_SPACE_ADDR         = 12'h5E4;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_RESERVED_5E8_ADDR     = 12'h5E8;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_RESERVED_5EC_ADDR     = 12'h5EC;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_RESERVED_5F0_ADDR     = 12'h5F0;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_RESERVED_5F4_ADDR     = 12'h5F4;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_RESERVED_5F8_ADDR     = 12'h5F8;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_QUEUE_RESERVED_5FC_ADDR     = 12'h5FC;


    // ------------------------------------------------------------
    // P22 event notification / interrupt-lite CSR window
    // ------------------------------------------------------------
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_EVENT_VERSION_ADDR      = 12'h600;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_EVENT_COMMAND_ADDR      = 12'h604;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_EVENT_STATUS_ADDR       = 12'h608;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_EVENT_PENDING_ADDR      = 12'h60C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_EVENT_ENABLE_ADDR       = 12'h610;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_EVENT_CONTROL_ADDR      = 12'h614;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_EVENT_LAST_CAUSE_ADDR   = 12'h618;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_EVENT_COUNT_ADDR        = 12'h61C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_EVENT_SNAPSHOT0_ADDR    = 12'h620;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_EVENT_SNAPSHOT1_ADDR    = 12'h624;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_EVENT_CQ_THRESHOLD_ADDR = 12'h628;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_EVENT_IRQ_COUNT_ADDR       = 12'h62C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_EVENT_MOD_CONTROL_ADDR     = 12'h630;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_EVENT_MOD_STATUS_ADDR      = 12'h634;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_EVENT_MOD_TIMER_LIMIT_ADDR = 12'h638;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_EVENT_MOD_DEBUG_ADDR       = 12'h63C;

    // ------------------------------------------------------------
    // P27 memory access guard CSR window
    // ------------------------------------------------------------
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_VERSION_ADDR              = 12'h640;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_COMMAND_ADDR              = 12'h644;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_STATUS_ADDR               = 12'h648;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_ERROR_STATUS_ADDR         = 12'h64C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_CONTROL_ADDR              = 12'h650;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_REJECT_STATUS_ADDR        = 12'h654;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_ERROR_DETAIL_ADDR         = 12'h658;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_ERROR_ADDR_ADDR           = 12'h65C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_ERROR_SIZE_BYTES_ADDR     = 12'h660;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_ERROR_DOMAIN_ADDR         = 12'h664;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_CHECK_COUNT_ADDR          = 12'h668;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_ERROR_COUNT_ADDR          = 12'h66C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_LAST_CHECK_ADDR_ADDR      = 12'h670;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_LAST_CHECK_SIZE_BYTES_ADDR= 12'h674;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_LAST_CHECK_DOMAIN_ADDR    = 12'h678;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_SQ_BASE_ADDR              = 12'h680;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_SQ_LIMIT_ADDR             = 12'h684;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_CQ_BASE_ADDR              = 12'h688;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_CQ_LIMIT_ADDR             = 12'h68C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_DESC_BASE_ADDR            = 12'h690;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_DESC_LIMIT_ADDR           = 12'h694;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_SRC_BASE_ADDR             = 12'h698;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_SRC_LIMIT_ADDR            = 12'h69C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_DST_BASE_ADDR             = 12'h6A0;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MEM_GUARD_DST_LIMIT_ADDR            = 12'h6A4;

    // ------------------------------------------------------------
    // P27 memory access guard constants
    // ------------------------------------------------------------
    localparam int MEM_GUARD_CMD_CLEAR_ERROR    = 8;
    localparam int MEM_GUARD_CMD_CLEAR_REJECT   = 9;
    localparam int MEM_GUARD_CMD_CLEAR_COUNTERS = 10;

    localparam int MEM_GUARD_CONTROL_ENABLE              = 0;
    localparam int MEM_GUARD_CONTROL_STRICT_REJECT       = 1;
    localparam int MEM_GUARD_CONTROL_SQ_CHECK_ENABLE     = 4;
    localparam int MEM_GUARD_CONTROL_CQ_CHECK_ENABLE     = 5;
    localparam int MEM_GUARD_CONTROL_DESC_CHECK_ENABLE   = 6;
    localparam int MEM_GUARD_CONTROL_SRC_CHECK_ENABLE    = 7;
    localparam int MEM_GUARD_CONTROL_DST_CHECK_ENABLE    = 8;
    localparam int MEM_GUARD_CONTROL_WRITE_CQ_ERROR_SAFE = 12;

    localparam int MEM_GUARD_STATUS_GUARD_ENABLED      = 0;
    localparam int MEM_GUARD_STATUS_STRICT_ENABLED     = 1;
    localparam int MEM_GUARD_STATUS_ANY_ERROR          = 2;
    localparam int MEM_GUARD_STATUS_ANY_REJECT         = 3;
    localparam int MEM_GUARD_STATUS_SQ_CHECK_ENABLED   = 4;
    localparam int MEM_GUARD_STATUS_CQ_CHECK_ENABLED   = 5;
    localparam int MEM_GUARD_STATUS_DESC_CHECK_ENABLED = 6;
    localparam int MEM_GUARD_STATUS_SRC_CHECK_ENABLED  = 7;
    localparam int MEM_GUARD_STATUS_DST_CHECK_ENABLED  = 8;
    localparam int MEM_GUARD_STATUS_ERROR_PENDING      = 9;
    localparam int MEM_GUARD_STATUS_QUEUE_ERROR_MIRROR = 10;

    localparam int MEM_GUARD_ERR_ANY              = 0;
    localparam int MEM_GUARD_ERR_SQ_RANGE         = 1;
    localparam int MEM_GUARD_ERR_CQ_RANGE         = 2;
    localparam int MEM_GUARD_ERR_DESC_RANGE       = 3;
    localparam int MEM_GUARD_ERR_SRC_RANGE        = 4;
    localparam int MEM_GUARD_ERR_DST_RANGE        = 5;
    localparam int MEM_GUARD_ERR_BASE_LIMIT       = 6;
    localparam int MEM_GUARD_ERR_ADDR_OVERFLOW    = 7;
    localparam int MEM_GUARD_ERR_ALIGNMENT        = 8;
    localparam int MEM_GUARD_ERR_STRIDE           = 9;
    localparam int MEM_GUARD_ERR_DEPTH            = 10;
    localparam int MEM_GUARD_ERR_SIZE_ZERO        = 11;
    localparam int MEM_GUARD_ERR_UNSAFE_CQ_SUPP   = 12;
    localparam int MEM_GUARD_ERR_DOMAIN_MISMATCH  = 13;
    localparam int MEM_GUARD_ERR_CONFIG_BUSY      = 14;
    localparam int MEM_GUARD_ERR_INTERNAL         = 15;

    localparam int MEM_GUARD_REJ_CONFIG_BUSY      = 0;
    localparam int MEM_GUARD_REJ_INVALID_REGION   = 1;
    localparam int MEM_GUARD_REJ_UNSUPPORTED_CMD  = 2;
    localparam int MEM_GUARD_REJ_STRICT_START     = 3;

    localparam int P27_QUEUE_MEMORY_GUARD_ERROR_BIT = 9;

    localparam logic [31:0] MEM_GUARD_CONTROL_WR_MASK = 32'h0000_11F3;
    localparam logic [31:0] MEM_GUARD_ALL_ERROR_MASK  = 32'h0000_FFFF;
    localparam logic [31:0] MEM_GUARD_ALL_REJECT_MASK = 32'h0000_000F;

    // ------------------------------------------------------------
    // P22 event notification / P28 moderation constants
    // ------------------------------------------------------------
    localparam int EVENT_WIDTH = 12;

    // CSR_EVENT_COMMAND bits
    localparam int EVENT_CMD_CLEAR_PENDING  = 0;
    localparam int EVENT_CMD_FORCE_TEST     = 1;
    localparam int EVENT_CMD_CLEAR_COUNTERS = 8;

    // CSR_EVENT_CONTROL bits
    localparam int EVENT_CONTROL_GLOBAL_IRQ_ENABLE = 0;
    localparam int EVENT_CONTROL_IRQ_PULSE_MODE    = 1; // Reserved in P22C; read/write only.
    localparam int EVENT_CONTROL_CAPTURE_SNAPSHOT  = 2;
    localparam int EVENT_CONTROL_COUNT_TEST_EVENTS = 3;

    // Event source bits frozen by P22B / P28B
    localparam int P22_EVENT_QUEUE_COMPLETED    = 0;
    localparam int P22_EVENT_QUEUE_DRAINED      = 1;
    localparam int P22_EVENT_QUEUE_STOPPED      = 2;
    localparam int P22_EVENT_QUEUE_ERROR        = 3;
    localparam int P22_EVENT_CQ_NOT_EMPTY       = 4;
    localparam int P22_EVENT_CQ_THRESHOLD       = 5;
    localparam int P22_EVENT_CQ_FULL_STALL      = 6;
    localparam int P22_EVENT_CQ_SPACE_RECOVERED = 7;
    localparam int P22_EVENT_RUNTIME_DOORBELL   = 8;
    localparam int P22_EVENT_RUNTIME_CONSUMED   = 9;
    localparam int P22_EVENT_TEST               = 10;
    localparam int P28_EVENT_CQ_MOD_TIMER       = 11;

    localparam logic [31:0] EVENT_VALID_MASK      = 32'h0000_0FFF;
    localparam logic [31:0] EVENT_CONTROL_WR_MASK = 32'h0000_000F;

    // P28 CSR_EVENT_MOD_CONTROL bits
    localparam int EVENT_MOD_CONTROL_ENABLE             = 0;
    localparam int EVENT_MOD_CONTROL_THRESHOLD_ENABLE   = 1;
    localparam int EVENT_MOD_CONTROL_TIMER_ENABLE       = 2;
    localparam int EVENT_MOD_CONTROL_RETRIGGER_NONEMPTY = 3;

    // P28 CSR_EVENT_MOD_STATUS bits
    localparam int EVENT_MOD_STATUS_ACTIVE              = 0;
    localparam int EVENT_MOD_STATUS_THRESHOLD_ACTIVE    = 1;
    localparam int EVENT_MOD_STATUS_TIMER_ACTIVE        = 2;
    localparam int EVENT_MOD_STATUS_TIMER_RUNNING       = 3;
    localparam int EVENT_MOD_STATUS_THRESHOLD_MET       = 4;
    localparam int EVENT_MOD_STATUS_TIMER_EXPIRED       = 5;
    localparam int EVENT_MOD_STATUS_RELEASE_PENDING     = 6;
    localparam int EVENT_MOD_STATUS_URGENT_BYPASS       = 7;

    localparam logic [31:0] EVENT_MOD_CONTROL_WR_MASK = 32'h0000_000F;

    localparam logic [7:0] P28_MOD_RELEASE_NONE      = 8'h00;
    localparam logic [7:0] P28_MOD_RELEASE_THRESHOLD = 8'h01;
    localparam logic [7:0] P28_MOD_RELEASE_TIMER     = 8'h02;
    localparam logic [7:0] P28_MOD_RELEASE_IMMEDIATE = 8'h03;
    localparam logic [7:0] P28_MOD_RELEASE_URGENT    = 8'h04;
    localparam logic [7:0] P28_MOD_RELEASE_REARM     = 8'h05;

    // Source-class values used in CSR_EVENT_LAST_CAUSE[15:8]
    localparam logic [7:0] EVENT_SRC_NONE             = 8'h00;
    localparam logic [7:0] EVENT_SRC_QUEUE_COMPLETION = 8'h01;
    localparam logic [7:0] EVENT_SRC_QUEUE_TERMINAL   = 8'h02;
    localparam logic [7:0] EVENT_SRC_QUEUE_ERROR      = 8'h03;
    localparam logic [7:0] EVENT_SRC_CQ_BACKPRESSURE  = 8'h04;
    localparam logic [7:0] EVENT_SRC_RUNTIME_DOORBELL = 8'h05;
    localparam logic [7:0] EVENT_SRC_SOFTWARE_TEST    = 8'h06;

    // ------------------------------------------------------------
    // Command bits
    // ------------------------------------------------------------
    localparam int CMD_START_GEMM_BIT      = 0;
    localparam int CMD_START_DMA_LOAD_BIT  = 1;
    localparam int CMD_START_AXIS_LOAD_BIT = 2;
    localparam int CMD_START_DS_LOAD_BIT   = 3;
    localparam int CMD_START_DMA_STORE_BIT = 4;
    localparam int CMD_CLEAR_DONE_BIT      = 8;
    localparam int CMD_CLEAR_ERROR_BIT     = 9;
    localparam int CMD_CLEAR_PERF_BIT      = 10;

    localparam logic [31:0] CMD_START_MASK = 32'h0000_001F;

    // ------------------------------------------------------------
    // Sticky status bit positions
    // ------------------------------------------------------------
    localparam int DONE_GEMM_BIT      = 0;
    localparam int DONE_DMA_LOAD_BIT  = 1;
    localparam int DONE_AXIS_LOAD_BIT = 2;
    localparam int DONE_DS_LOAD_BIT   = 3;
    localparam int DONE_DMA_STORE_BIT = 4;

    localparam int ERR_DMA_LOAD_BIT   = 0;
    localparam int ERR_AXIS_LOAD_BIT  = 1;
    localparam int ERR_DS_LOAD_BIT    = 2;
    localparam int ERR_DMA_STORE_BIT  = 3;
    localparam int ERR_GEMM_RSVD_BIT  = 4;

    localparam int REJ_GEMM_BUSY_BIT      = 0;
    localparam int REJ_DMA_LOAD_BUSY_BIT  = 1;
    localparam int REJ_AXIS_BUSY_BIT      = 2;
    localparam int REJ_DS_BUSY_BIT        = 3;
    localparam int REJ_DMA_STORE_BUSY_BIT = 4;
    localparam int REJ_UNSUPPORTED_BIT    = 8;
    localparam int REJ_ZERO_LENGTH_BIT    = 9;

    // ------------------------------------------------------------
    // P15 job command / sticky status bit positions
    // ------------------------------------------------------------
    localparam int JOB_CMD_START_BIT       = 0;
    localparam int JOB_CMD_CLEAR_DONE_BIT  = 8;
    localparam int JOB_CMD_CLEAR_ERROR_BIT = 9;
    localparam int JOB_CMD_CLEAR_PERF_BIT  = 10;

    localparam int JOB_DONE_BIT       = 0;
    localparam int JOB_GEMM_DONE_BIT  = 1;
    localparam int JOB_STORE_DONE_BIT = 2;

    localparam int JOB_ERR_DMA_LOAD_BIT       = 0;
    localparam int JOB_ERR_AXIS_LOAD_BIT      = 1;
    localparam int JOB_ERR_DS_LOAD_BIT        = 2;
    localparam int JOB_ERR_DMA_STORE_BIT      = 3;
    localparam int JOB_ERR_GEMM_RSVD_BIT      = 4;
    localparam int JOB_ERR_SEQUENCE_BIT       = 8;

    localparam int JOB_REJ_BUSY_BIT           = 0;
    localparam int JOB_REJ_MICRO_OP_BUSY_BIT  = 1;
    localparam int JOB_REJ_UNSUPPORTED_MODE   = 2;
    localparam int JOB_REJ_ZERO_DIM_BIT       = 3;
    localparam int JOB_REJ_ZERO_A_LENGTH_BIT  = 4;
    localparam int JOB_REJ_ZERO_B_LENGTH_BIT  = 5;
    localparam int JOB_REJ_ZERO_STORE_LEN_BIT = 6;
    localparam int JOB_REJ_MANUAL_CMD_BIT     = 7;
    localparam int JOB_REJ_UNSUPPORTED_COMBO  = 8;

    localparam logic [1:0] JOB_INPUT_HOST_PRELOADED = 2'd0;
    localparam logic [1:0] JOB_INPUT_DMA_LOAD       = 2'd1;
    localparam logic [1:0] JOB_INPUT_AXIS_PRELOAD   = 2'd2;
    localparam logic [1:0] JOB_INPUT_DIRECT_STREAM  = 2'd3;

    localparam logic [1:0] JOB_OUTPUT_HOST_READBACK = 2'd0;
    localparam logic [1:0] JOB_OUTPUT_DMA_STORE     = 2'd1;

    localparam logic [31:0] JOB_MODE_MASK = 32'h0000_003F;

    // ------------------------------------------------------------
    // P16 recipe command / sticky status bit positions
    // ------------------------------------------------------------
    localparam int RECIPE_CMD_START_BIT             = 0;
    localparam int RECIPE_CMD_CLEAR_DONE_BIT        = 8;
    localparam int RECIPE_CMD_CLEAR_ERROR_BIT       = 9;
    localparam int RECIPE_CMD_CLEAR_PERF_BIT        = 10;
    localparam int RECIPE_CMD_CLEAR_SLOT_STATUS_BIT = 11;

    localparam int RECIPE_DONE_BIT             = 0;
    localparam int RECIPE_ALL_SLOTS_DONE_BIT   = 1;
    localparam int RECIPE_FINAL_STORE_DONE_BIT = 2;

    localparam int RECIPE_ERR_SLOT_JOB_ERROR_BIT        = 0;
    localparam int RECIPE_ERR_SLOT_JOB_REJECT_BIT       = 1;
    localparam int RECIPE_ERR_SEQUENCE_BIT              = 2;
    localparam int RECIPE_ERR_SLOT_RANGE_BIT            = 3;
    localparam int RECIPE_ERR_SLOT_DESCRIPTOR_BIT       = 4;
    localparam int RECIPE_ERR_TIMEOUT_RSVD_BIT          = 8;

    localparam int RECIPE_REJ_BUSY_BIT          = 0;
    localparam int RECIPE_REJ_JOB_BUSY_BIT      = 1;
    localparam int RECIPE_REJ_MICRO_OP_BUSY_BIT = 2;
    localparam int RECIPE_REJ_ZERO_COUNT_BIT    = 3;
    localparam int RECIPE_REJ_SLOT_RANGE_BIT    = 4;
    localparam int RECIPE_REJ_SLOT_INVALID_BIT  = 5;
    localparam int RECIPE_REJ_SLOT_DESC_BIT     = 6;
    localparam int RECIPE_REJ_MANUAL_CMD_BIT    = 7;
    localparam int RECIPE_REJ_UNSUPPORTED_COMBO = 8;

    localparam logic [31:0] RECIPE_CONTROL_MASK = 32'h0000_0FFF;
    localparam logic [31:0] RECIPE_SLOT_CONTROL_MASK = 32'h0000_007F;
    localparam logic [3:0]  P16_RECIPE_QUEUE_DEPTH_U4 = P16_RECIPE_QUEUE_DEPTH;

    // ------------------------------------------------------------
    // P17 descriptor-fetch command/status bit positions
    // ------------------------------------------------------------
    localparam int DESC_FETCH_CMD_START_BIT       = 0;
    localparam int DESC_FETCH_CMD_CLEAR_DONE_BIT  = 8;
    localparam int DESC_FETCH_CMD_CLEAR_ERROR_BIT = 9;

    localparam int DESC_FETCH_DONE_BIT            = 0;
    localparam int DESC_FETCH_SNAPSHOT_VALID_BIT  = 1;

    localparam logic [31:0] DESC_FETCH_COUNT_MASK  = 32'h0000_000F;
    localparam logic [31:0] DESC_FETCH_STRIDE_MASK = 32'h0000_FFFF;

    // ------------------------------------------------------------
    // P18 completion writeback command / sticky status bit positions
    // ------------------------------------------------------------
    localparam int COMP_WB_CMD_START_BIT       = 0;
    localparam int COMP_WB_CMD_CLEAR_DONE_BIT  = 8;
    localparam int COMP_WB_CMD_CLEAR_ERROR_BIT = 9;

    localparam int COMP_WB_DONE_BIT            = 0;
    localparam int COMP_WB_ERR_ENGINE_BIT      = 0;
    localparam int COMP_WB_REJ_ENGINE_BIT      = 0;
    localparam int COMP_WB_REJ_UNSUPPORTED_BIT = 8;

    localparam logic [31:0] COMP_WB_CONTROL_MASK = 32'h0000_000F;

    // ------------------------------------------------------------
    // P19 queue command / control bit positions
    // ------------------------------------------------------------
    localparam int QUEUE_CMD_START_BIT       = 0;
    localparam int QUEUE_CMD_STOP_BIT        = 1;
    localparam int QUEUE_CMD_CLEAR_DONE_BIT  = 8;
    localparam int QUEUE_CMD_CLEAR_ERROR_BIT = 9;

    localparam int QUEUE_CONTROL_ENABLE_BIT          = 0;
    localparam int QUEUE_CONTROL_RUN_UNTIL_EMPTY_BIT = 1;
    localparam int QUEUE_CONTROL_STOP_ON_ERROR_BIT   = 2;

    localparam logic [31:0] QUEUE_CONTROL_MASK = 32'h0000_001F;

    // ------------------------------------------------------------
    // AXI-Lite transaction state
    // ------------------------------------------------------------
    logic [CSR_ADDR_WIDTH-1:0] awaddr_q;
    logic                      awaddr_valid_q;

    logic [31:0]               wdata_q;
    logic [STRB_WIDTH-1:0]     wstrb_q;
    logic                      wdata_valid_q;

    logic                      bvalid_q;
    logic [1:0]                bresp_q;

    logic                      rvalid_q;
    logic [31:0]               rdata_q;
    logic [1:0]                rresp_q;

    logic aw_fire;
    logic w_fire;
    logic b_fire;
    logic ar_fire;
    logic r_fire;

    logic write_apply;
    logic [CSR_ADDR_WIDTH-1:0] write_addr;
    logic [31:0]               write_data;
    logic [STRB_WIDTH-1:0]     write_strb;

    logic write_addr_valid;
    logic read_addr_valid;

    logic [31:0] read_data_comb;

    // ------------------------------------------------------------
    // CSR storage registers
    // ------------------------------------------------------------
    logic [31:0] mode_q;

    logic [31:0] base_addr_a_q;
    logic [31:0] base_addr_b_q;
    logic [31:0] base_addr_c_q;

    logic [31:0] dim_m_q;
    logic [31:0] dim_n_q;
    logic [31:0] dim_k_q;

    logic [31:0] dma_load_src_base_q;
    logic [31:0] dma_load_dst_base_q;
    logic [31:0] dma_load_beats_q;

    logic [31:0] axis_src_base_q;
    logic [31:0] axis_dst_base_q;
    logic [31:0] axis_load_beats_q;

    logic [31:0] ds_src_base_q;
    logic [31:0] ds_dst_base_q;
    logic [31:0] ds_load_beats_q;
    logic [31:0] ds_control_q;

    logic [31:0] dma_store_src_base_q;
    logic [31:0] dma_store_dst_base_q;
    logic [31:0] dma_store_byte_count_q;

    logic [31:0] done_status_q;
    logic [31:0] error_status_q;
    logic [31:0] reject_status_q;

    logic [31:0] perf_busy_cycles_q;
    logic [31:0] perf_mac_count_q;
    logic [31:0] perf_output_count_q;

    logic [31:0] job_mode_q;

    logic [31:0] job_base_addr_a_q;
    logic [31:0] job_base_addr_b_q;
    logic [31:0] job_base_addr_c_q;

    logic [31:0] job_dim_m_q;
    logic [31:0] job_dim_n_q;
    logic [31:0] job_dim_k_q;

    logic [31:0] job_a_src_base_q;
    logic [31:0] job_a_dst_base_q;
    logic [31:0] job_a_load_beats_q;

    logic [31:0] job_b_src_base_q;
    logic [31:0] job_b_dst_base_q;
    logic [31:0] job_b_load_beats_q;

    logic [31:0] job_store_src_base_q;
    logic [31:0] job_store_dst_base_q;
    logic [31:0] job_store_byte_count_q;

    logic [31:0] job_done_status_q;
    logic [31:0] job_error_status_q;
    logic [31:0] job_reject_status_q;

    logic [31:0] job_perf_busy_cycles_q;
    logic [31:0] job_perf_mac_count_q;
    logic [31:0] job_perf_output_count_q;

    logic [31:0] recipe_control_q;

    logic [31:0] recipe_done_status_q;
    logic [31:0] recipe_error_status_q;
    logic [31:0] recipe_reject_status_q;
    logic [31:0] recipe_slot_done_mask_q;
    logic [31:0] recipe_slot_error_mask_q;
    logic [31:0] recipe_slot_reject_mask_q;

    logic [31:0] recipe_perf_busy_cycles_q;
    logic [31:0] recipe_perf_mac_count_q;
    logic [31:0] recipe_perf_output_count_q;

    logic [31:0] recipe_slot_control_q          [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_base_addr_a_q      [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_base_addr_b_q      [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_base_addr_c_q      [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_dim_m_q            [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_dim_n_q            [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_dim_k_q            [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_a_src_base_q       [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_a_dst_base_q       [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_a_load_beats_q     [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_b_src_base_q       [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_b_dst_base_q       [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_b_load_beats_q     [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_store_src_base_q   [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_store_dst_base_q   [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_store_byte_count_q [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_user_tag_q         [P16_RECIPE_QUEUE_DEPTH];

    logic [31:0] desc_fetch_base_addr_q;
    logic [31:0] desc_fetch_count_q;
    logic [31:0] desc_fetch_stride_bytes_q;

    logic [31:0] completion_wb_control_q;
    logic [31:0] completion_wb_base_addr_q;
    logic [31:0] completion_wb_status_flags_q;
    logic [31:0] completion_wb_user_tag_q;
    logic [31:0] completion_wb_counts_q;
    logic [31:0] completion_wb_recipe_done_status_q;
    logic [31:0] completion_wb_recipe_error_status_q;
    logic [31:0] completion_wb_recipe_reject_status_q;
    logic [31:0] completion_wb_perf_mac_count_q;
    logic [31:0] completion_wb_error_detail_q;
    logic [31:0] completion_wb_done_status_q;
    logic [31:0] completion_wb_error_status_q;
    logic [31:0] completion_wb_reject_status_q;
    logic        completion_wb_clear_done_holdoff_q;
    logic        completion_wb_clear_error_holdoff_q;


    logic [31:0] queue_control_q;
    logic [31:0] queue_sq_base_addr_q;
    logic [31:0] queue_sq_depth_q;
    logic [31:0] queue_sq_head_q;
    logic [31:0] queue_sq_tail_q;
    logic [31:0] queue_sq_stride_q;
    logic [31:0] queue_cq_base_addr_q;
    logic [31:0] queue_cq_depth_q;
    logic [31:0] queue_cq_head_q;
    logic [31:0] queue_cq_tail_q;
    logic [31:0] queue_cq_stride_q;
    logic [31:0] queue_extra_error_status_q;

    logic [31:0] mem_guard_control_q;
    logic [31:0] mem_guard_error_status_q;
    logic [31:0] mem_guard_reject_status_q;
    logic [31:0] mem_guard_error_detail_q;
    logic [31:0] mem_guard_error_addr_q;
    logic [31:0] mem_guard_error_size_bytes_q;
    logic [31:0] mem_guard_error_domain_q;
    logic [31:0] mem_guard_check_count_q;
    logic [31:0] mem_guard_error_count_q;
    logic [31:0] mem_guard_last_check_addr_q;
    logic [31:0] mem_guard_last_check_size_bytes_q;
    logic [31:0] mem_guard_last_check_domain_q;
    logic [31:0] mem_guard_sq_base_q;
    logic [31:0] mem_guard_sq_limit_q;
    logic [31:0] mem_guard_cq_base_q;
    logic [31:0] mem_guard_cq_limit_q;
    logic [31:0] mem_guard_desc_base_q;
    logic [31:0] mem_guard_desc_limit_q;
    logic [31:0] mem_guard_src_base_q;
    logic [31:0] mem_guard_src_limit_q;
    logic [31:0] mem_guard_dst_base_q;
    logic [31:0] mem_guard_dst_limit_q;

    logic [31:0] mem_guard_status_read_data;
    logic [31:0] mem_guard_command_masked;
    logic        mem_guard_command_has_active_strobe;

    logic [31:0] event_pending_q;
    logic [31:0] event_enable_q;
    logic [31:0] event_control_q;
    logic [31:0] event_last_cause_q;
    logic [31:0] event_count_q;
    logic [31:0] event_snapshot0_q;
    logic [31:0] event_snapshot1_q;
    logic [31:0] event_cq_threshold_q;
    logic [31:0] event_irq_count_q;
    logic [31:0] event_mod_control_q;
    logic [31:0] event_mod_timer_limit_q;
    logic [31:0] event_mod_timer_count_q;
    logic [31:0] event_mod_unnotified_count_q;
    logic [31:0] event_mod_release_count_q;
    logic [31:0] event_mod_threshold_release_count_q;
    logic [31:0] event_mod_timer_release_count_q;
    logic [7:0]  event_mod_last_release_cause_q;
    logic        event_mod_timer_expired_q;

    logic [31:0] event_status_read_data;
    logic [31:0] event_mod_status_read_data;
    logic [31:0] event_mod_debug_read_data;
    logic [31:0] event_command_masked;
    logic [31:0] event_raw_source_mask;
    logic [31:0] event_source_mask;
    logic [31:0] event_clear_mask;
    logic        event_clear_pending_cmd;
    logic        event_clear_counters_cmd;
    logic        event_force_test_cmd;
    logic        event_completion_source;
    logic        event_mod_enabled;
    logic        event_mod_threshold_active;
    logic        event_mod_timer_active;
    logic        event_mod_completion_pending;
    logic        event_mod_threshold_hit;
    logic        event_mod_timer_hit;
    logic        event_mod_release_pulse;
    logic        event_mod_rearm_release;
    logic        event_mod_urgent_bypass;
    logic [31:0] event_mod_effective_cq_occupancy;
    logic [31:0] event_mod_effective_unnotified;
    logic [7:0]  event_mod_release_cause_comb;
    logic        event_countable;
    logic        event_irq_eligible_new;
    logic [31:0] event_snapshot0_comb;
    logic [31:0] event_snapshot1_comb;

    logic        queue_done_stopped_d_q;
    logic        queue_cq_full_stall_d_q;
    logic        queue_cq_space_nonzero_d_q;

    // ------------------------------------------------------------
    // Internal command decode helpers
    // ------------------------------------------------------------
    logic [31:0] command_masked;
    logic [31:0] start_bits;
    logic        command_has_active_strobe;
    logic        command_has_start;
    logic        command_multi_start;
    logic        command_unsupported_combo;

    logic [31:0] job_command_masked;
    logic        job_command_has_active_strobe;
    logic        job_command_has_start;
    logic        job_command_unsupported_combo;

    logic [31:0] recipe_command_masked;
    logic        recipe_command_has_active_strobe;
    logic        recipe_command_has_start;
    logic        recipe_command_unsupported_combo;

    logic [31:0] desc_fetch_command_masked;
    logic        desc_fetch_command_has_active_strobe;
    logic        desc_fetch_command_has_start;

    logic [31:0] completion_wb_command_masked;
    logic        completion_wb_command_has_active_strobe;
    logic        completion_wb_command_has_start;
    logic        completion_wb_command_unsupported_combo;

    logic [31:0] queue_command_masked;
    logic        queue_command_has_active_strobe;
    logic        queue_command_has_start;

    logic [31:0] status_read_data;
    logic [31:0] job_status_read_data;
    logic [31:0] recipe_status_read_data;
    logic [31:0] desc_fetch_status_read_data;
    logic [31:0] desc_fetch_done_read_data;
    logic [31:0] desc_fetch_snapshot_status_read_data;
    logic [31:0] completion_wb_status_read_data;
    logic [31:0] queue_status_read_data;
    logic        micro_op_busy;
    logic        job_preload_required;
    logic        job_store_required;
    logic        job_output_mode_supported;

    logic [3:0]  recipe_count_comb;
    logic [3:0]  recipe_start_slot_comb;
    logic        recipe_range_valid;
    logic        recipe_selected_slots_valid;
    logic        recipe_selected_desc_valid;

    // ------------------------------------------------------------
    // Parameter sanity
    // ------------------------------------------------------------
    function automatic bit is_power_of_two(input int value);
        return (value > 0) && ((value & (value - 1)) == 0);
    endfunction

`ifndef SYNTHESIS
    initial begin
        if (CSR_DATA_WIDTH != 32) begin
            $fatal(1, "ai_accel_csr_regs: CSR_DATA_WIDTH must be 32");
        end

        if (STRB_WIDTH != 4) begin
            $fatal(1, "ai_accel_csr_regs: STRB_WIDTH must be 4");
        end

        if (CSR_ADDR_WIDTH < 12) begin
            $fatal(1, "ai_accel_csr_regs: CSR_ADDR_WIDTH must be at least 12");
        end

        if (ADDR_WIDTH > 32) begin
            $fatal(1, "ai_accel_csr_regs: ADDR_WIDTH above 32 is not supported by 32-bit CSR registers");
        end

        if (P16_RECIPE_QUEUE_DEPTH != 4) begin
            $fatal(1, "ai_accel_csr_regs: P16_RECIPE_QUEUE_DEPTH must be 4 for the P16B CSR map");
        end

        if (GEMM_DIM_WIDTH > 32) begin
            $fatal(1, "ai_accel_csr_regs: GEMM_DIM_WIDTH above 32 is not supported by 32-bit CSR registers");
        end

        if (!is_power_of_two(STRB_WIDTH)) begin
            $fatal(1, "ai_accel_csr_regs: STRB_WIDTH must be a power of two");
        end
    end
`endif

    // ------------------------------------------------------------
    // Byte-strobe helpers
    // ------------------------------------------------------------
    function automatic logic [31:0] strobe_to_mask(
        input logic [STRB_WIDTH-1:0] strb
    );
        logic [31:0] mask;
        int unsigned i;
    begin
        mask = 32'h0000_0000;

        for (i = 0; i < STRB_WIDTH; i++) begin
            if (strb[i]) begin
                mask[(i * 8) +: 8] = 8'hFF;
            end
        end

        return mask;
    end
    endfunction

    function automatic logic [31:0] apply_wstrb32(
        input logic [31:0]           old_value,
        input logic [31:0]           new_value,
        input logic [STRB_WIDTH-1:0] strb
    );
        logic [31:0] mask;
    begin
        mask = strobe_to_mask(strb);
        return (old_value & ~mask) | (new_value & mask);
    end
    endfunction


    function automatic bit recipe_slot_addr_is_valid(
        input logic [CSR_ADDR_WIDTH-1:0] addr
    );
        int unsigned slot_idx;
        logic [CSR_ADDR_WIDTH-1:0] rel_addr;
        logic [6:0] slot_offset;
    begin
        if (addr < CSR_RECIPE_SLOT_BASE_ADDR) begin
            return 1'b0;
        end

        rel_addr    = addr - CSR_RECIPE_SLOT_BASE_ADDR;
        slot_idx    = rel_addr >> 7;
        slot_offset = rel_addr[6:0];

        if (slot_idx >= P16_RECIPE_QUEUE_DEPTH) begin
            return 1'b0;
        end

        if (slot_offset[1:0] != 2'b00) begin
            return 1'b0;
        end

        return 1'b1;
    end
    endfunction

    function automatic int unsigned recipe_slot_index(
        input logic [CSR_ADDR_WIDTH-1:0] addr
    );
        logic [CSR_ADDR_WIDTH-1:0] rel_addr;
    begin
        rel_addr = addr - CSR_RECIPE_SLOT_BASE_ADDR;
        return (rel_addr >> 7);
    end
    endfunction

    function automatic logic [6:0] recipe_slot_offset(
        input logic [CSR_ADDR_WIDTH-1:0] addr
    );
        logic [CSR_ADDR_WIDTH-1:0] rel_addr;
    begin
        rel_addr = addr - CSR_RECIPE_SLOT_BASE_ADDR;
        return rel_addr[6:0];
    end
    endfunction

    function automatic bit recipe_slot_descriptor_valid(
        input int unsigned slot_idx
    );
        logic [1:0] slot_input_mode;
        logic [1:0] slot_output_mode;
    begin
        if (slot_idx >= P16_RECIPE_QUEUE_DEPTH) begin
            return 1'b0;
        end

        slot_input_mode  = recipe_slot_control_q[slot_idx][2:1];
        slot_output_mode = recipe_slot_control_q[slot_idx][4:3];

        if (!recipe_slot_control_q[slot_idx][0]) begin
            return 1'b0;
        end

        if (slot_output_mode > JOB_OUTPUT_DMA_STORE) begin
            return 1'b0;
        end

        if ((recipe_slot_dim_m_q[slot_idx] == 32'h0000_0000) ||
            (recipe_slot_dim_n_q[slot_idx] == 32'h0000_0000) ||
            (recipe_slot_dim_k_q[slot_idx] == 32'h0000_0000)) begin
            return 1'b0;
        end

        if ((slot_input_mode != JOB_INPUT_HOST_PRELOADED) &&
            (recipe_slot_a_load_beats_q[slot_idx] == 32'h0000_0000)) begin
            return 1'b0;
        end

        if ((slot_input_mode != JOB_INPUT_HOST_PRELOADED) &&
            (recipe_slot_b_load_beats_q[slot_idx] == 32'h0000_0000)) begin
            return 1'b0;
        end

        if ((slot_output_mode == JOB_OUTPUT_DMA_STORE) &&
            (recipe_slot_store_byte_count_q[slot_idx] == 32'h0000_0000)) begin
            return 1'b0;
        end

        return 1'b1;
    end
    endfunction

    function automatic logic [31:0] recipe_slot_read_data(
        input logic [CSR_ADDR_WIDTH-1:0] addr
    );
        int unsigned slot_idx;
        logic [6:0]  slot_offset;
    begin
        slot_idx    = recipe_slot_index(addr);
        slot_offset = recipe_slot_offset(addr);

        if (slot_idx >= P16_RECIPE_QUEUE_DEPTH) begin
            return 32'h0000_0000;
        end

        unique case (slot_offset)
            SLOT_CONTROL_OFFSET: begin
                return recipe_slot_control_q[slot_idx];
            end

            SLOT_BASE_ADDR_A_OFFSET: begin
                return recipe_slot_base_addr_a_q[slot_idx];
            end

            SLOT_BASE_ADDR_B_OFFSET: begin
                return recipe_slot_base_addr_b_q[slot_idx];
            end

            SLOT_BASE_ADDR_C_OFFSET: begin
                return recipe_slot_base_addr_c_q[slot_idx];
            end

            SLOT_DIM_M_OFFSET: begin
                return recipe_slot_dim_m_q[slot_idx];
            end

            SLOT_DIM_N_OFFSET: begin
                return recipe_slot_dim_n_q[slot_idx];
            end

            SLOT_DIM_K_OFFSET: begin
                return recipe_slot_dim_k_q[slot_idx];
            end

            SLOT_A_SRC_BASE_OFFSET: begin
                return recipe_slot_a_src_base_q[slot_idx];
            end

            SLOT_A_DST_BASE_OFFSET: begin
                return recipe_slot_a_dst_base_q[slot_idx];
            end

            SLOT_A_LOAD_BEATS_OFFSET: begin
                return recipe_slot_a_load_beats_q[slot_idx];
            end

            SLOT_B_SRC_BASE_OFFSET: begin
                return recipe_slot_b_src_base_q[slot_idx];
            end

            SLOT_B_DST_BASE_OFFSET: begin
                return recipe_slot_b_dst_base_q[slot_idx];
            end

            SLOT_B_LOAD_BEATS_OFFSET: begin
                return recipe_slot_b_load_beats_q[slot_idx];
            end

            SLOT_STORE_SRC_BASE_OFFSET: begin
                return recipe_slot_store_src_base_q[slot_idx];
            end

            SLOT_STORE_DST_BASE_OFFSET: begin
                return recipe_slot_store_dst_base_q[slot_idx];
            end

            SLOT_STORE_BYTE_COUNT_OFFSET: begin
                return recipe_slot_store_byte_count_q[slot_idx];
            end

            SLOT_USER_TAG_OFFSET: begin
                return recipe_slot_user_tag_q[slot_idx];
            end

            default: begin
                return 32'h0000_0000;
            end
        endcase
    end
    endfunction

    function automatic bit csr_addr_is_valid(
        input logic [CSR_ADDR_WIDTH-1:0] addr
    );
    begin
        unique case (addr)
            CSR_VERSION_ADDR,
            CSR_COMMAND_ADDR,
            CSR_STATUS_ADDR,
            CSR_DONE_STATUS_ADDR,
            CSR_ERROR_STATUS_ADDR,
            CSR_MODE_ADDR,
            CSR_CMD_REJECT_STATUS_ADDR,
            CSR_RESERVED_01C_ADDR,

            CSR_BASE_ADDR_A_ADDR,
            CSR_BASE_ADDR_B_ADDR,
            CSR_BASE_ADDR_C_ADDR,
            CSR_DIM_M_ADDR,
            CSR_DIM_N_ADDR,
            CSR_DIM_K_ADDR,
            CSR_RESERVED_038_ADDR,
            CSR_RESERVED_03C_ADDR,

            CSR_DMA_LOAD_SRC_BASE_ADDR,
            CSR_DMA_LOAD_DST_BASE_ADDR,
            CSR_DMA_LOAD_BEATS_ADDR,
            CSR_RESERVED_04C_ADDR,

            CSR_AXIS_SRC_BASE_ADDR,
            CSR_AXIS_DST_BASE_ADDR,
            CSR_AXIS_LOAD_BEATS_ADDR,
            CSR_RESERVED_05C_ADDR,

            CSR_DS_SRC_BASE_ADDR,
            CSR_DS_DST_BASE_ADDR,
            CSR_DS_LOAD_BEATS_ADDR,
            CSR_DS_CONTROL_ADDR,

            CSR_DMA_STORE_SRC_BASE_ADDR,
            CSR_DMA_STORE_DST_BASE_ADDR,
            CSR_DMA_STORE_BYTE_COUNT_ADDR,
            CSR_RESERVED_07C_ADDR,

            CSR_PERF_BUSY_CYCLES_ADDR,
            CSR_PERF_MAC_COUNT_ADDR,
            CSR_PERF_OUTPUT_COUNT_ADDR,
            CSR_RESERVED_08C_ADDR,

            CSR_JOB_VERSION_ADDR,
            CSR_JOB_COMMAND_ADDR,
            CSR_JOB_STATUS_ADDR,
            CSR_JOB_DONE_STATUS_ADDR,
            CSR_JOB_ERROR_STATUS_ADDR,
            CSR_JOB_MODE_ADDR,
            CSR_JOB_REJECT_STATUS_ADDR,
            CSR_JOB_STATE_ADDR,

            CSR_JOB_BASE_ADDR_A_ADDR,
            CSR_JOB_BASE_ADDR_B_ADDR,
            CSR_JOB_BASE_ADDR_C_ADDR,
            CSR_JOB_DIM_M_ADDR,
            CSR_JOB_DIM_N_ADDR,
            CSR_JOB_DIM_K_ADDR,

            CSR_JOB_A_SRC_BASE_ADDR,
            CSR_JOB_A_DST_BASE_ADDR,
            CSR_JOB_A_LOAD_BEATS_ADDR,
            CSR_JOB_RESERVED_144_ADDR,

            CSR_JOB_B_SRC_BASE_ADDR,
            CSR_JOB_B_DST_BASE_ADDR,
            CSR_JOB_B_LOAD_BEATS_ADDR,
            CSR_JOB_RESERVED_154_ADDR,

            CSR_JOB_STORE_SRC_BASE_ADDR,
            CSR_JOB_STORE_DST_BASE_ADDR,
            CSR_JOB_STORE_BYTE_COUNT_ADDR,
            CSR_JOB_RESERVED_164_ADDR,

            CSR_JOB_PERF_BUSY_CYCLES_ADDR,
            CSR_JOB_PERF_MAC_COUNT_ADDR,
            CSR_JOB_PERF_OUTPUT_COUNT_ADDR,
            CSR_JOB_RESERVED_18C_ADDR,

            CSR_RECIPE_VERSION_ADDR,
            CSR_RECIPE_COMMAND_ADDR,
            CSR_RECIPE_STATUS_ADDR,
            CSR_RECIPE_DONE_STATUS_ADDR,
            CSR_RECIPE_ERROR_STATUS_ADDR,
            CSR_RECIPE_CONTROL_ADDR,
            CSR_RECIPE_REJECT_STATUS_ADDR,
            CSR_RECIPE_STATE_ADDR,
            CSR_RECIPE_CURRENT_SLOT_ADDR,
            CSR_RECIPE_COMPLETED_COUNT_ADDR,
            CSR_RECIPE_SLOT_DONE_MASK_ADDR,
            CSR_RECIPE_SLOT_ERROR_MASK_ADDR,
            CSR_RECIPE_SLOT_REJECT_MASK_ADDR,
            CSR_RECIPE_RESERVED_234_ADDR,
            CSR_RECIPE_PERF_BUSY_CYCLES_ADDR,
            CSR_RECIPE_PERF_MAC_COUNT_ADDR,
            CSR_RECIPE_PERF_OUTPUT_COUNT_ADDR,
            CSR_RECIPE_RESERVED_28C_ADDR,

            CSR_DESC_FETCH_VERSION_ADDR,
            CSR_DESC_FETCH_COMMAND_ADDR,
            CSR_DESC_FETCH_STATUS_ADDR,
            CSR_DESC_FETCH_DONE_STATUS_ADDR,
            CSR_DESC_FETCH_ERROR_STATUS_ADDR,
            CSR_DESC_FETCH_REJECT_STATUS_ADDR,
            CSR_DESC_FETCH_BASE_ADDR_ADDR,
            CSR_DESC_FETCH_COUNT_ADDR,
            CSR_DESC_FETCH_STRIDE_BYTES_ADDR,
            CSR_DESC_FETCH_CURRENT_INDEX_ADDR,
            CSR_DESC_FETCH_FETCHED_COUNT_ADDR,
            CSR_DESC_FETCH_SNAPSHOT_STATUS_ADDR,
            CSR_DESC_FETCH_RESERVED_530_ADDR,

            CSR_COMPLETION_WB_VERSION_ADDR,
            CSR_COMPLETION_WB_COMMAND_ADDR,
            CSR_COMPLETION_WB_STATUS_ADDR,
            CSR_COMPLETION_WB_DONE_STATUS_ADDR,
            CSR_COMPLETION_WB_ERROR_STATUS_ADDR,
            CSR_COMPLETION_WB_REJECT_STATUS_ADDR,
            CSR_COMPLETION_WB_CONTROL_ADDR,
            CSR_COMPLETION_WB_BASE_ADDR_ADDR,
            CSR_COMPLETION_WB_STATUS_FLAGS_ADDR,
            CSR_COMPLETION_WB_USER_TAG_ADDR,
            CSR_COMPLETION_WB_COUNTS_ADDR,
            CSR_COMPLETION_WB_RECIPE_DONE_ADDR,
            CSR_COMPLETION_WB_RECIPE_ERROR_ADDR,
            CSR_COMPLETION_WB_RECIPE_REJECT_ADDR,
            CSR_COMPLETION_WB_PERF_MAC_COUNT_ADDR,
            CSR_COMPLETION_WB_ERROR_DETAIL_ADDR,
CSR_QUEUE_VERSION_ADDR,
            CSR_QUEUE_COMMAND_ADDR,
            CSR_QUEUE_STATUS_ADDR,
            CSR_QUEUE_DONE_STATUS_ADDR,
            CSR_QUEUE_ERROR_STATUS_ADDR,
            CSR_QUEUE_CONTROL_ADDR,
            CSR_QUEUE_REJECT_STATUS_ADDR,
            CSR_QUEUE_STATE_ADDR,
            CSR_QUEUE_SQ_BASE_ADDR,
            CSR_QUEUE_SQ_DEPTH_ADDR,
            CSR_QUEUE_SQ_HEAD_ADDR,
            CSR_QUEUE_SQ_TAIL_ADDR,
            CSR_QUEUE_SQ_STRIDE_ADDR,
            CSR_QUEUE_CQ_BASE_ADDR,
            CSR_QUEUE_CQ_DEPTH_ADDR,
            CSR_QUEUE_CQ_HEAD_ADDR,
            CSR_QUEUE_CQ_TAIL_ADDR,
            CSR_QUEUE_CQ_STRIDE_ADDR,
            CSR_QUEUE_CURRENT_INDEX_ADDR,
            CSR_QUEUE_ERROR_INDEX_ADDR,
            CSR_QUEUE_ERROR_DETAIL_ADDR,
            CSR_QUEUE_LAST_CMD_TAG_ADDR,
            CSR_QUEUE_LAST_CMD_CONTROL_ADDR,
            CSR_QUEUE_SQ_OCCUPANCY_ADDR,
            CSR_QUEUE_CQ_OCCUPANCY_ADDR,
            CSR_QUEUE_CQ_SPACE_ADDR,
            CSR_QUEUE_RESERVED_5E8_ADDR,
            CSR_QUEUE_RESERVED_5EC_ADDR,
            CSR_QUEUE_RESERVED_5F0_ADDR,
            CSR_QUEUE_RESERVED_5F4_ADDR,
            CSR_QUEUE_RESERVED_5F8_ADDR,
            CSR_QUEUE_RESERVED_5FC_ADDR,

            CSR_EVENT_VERSION_ADDR,
            CSR_EVENT_COMMAND_ADDR,
            CSR_EVENT_STATUS_ADDR,
            CSR_EVENT_PENDING_ADDR,
            CSR_EVENT_ENABLE_ADDR,
            CSR_EVENT_CONTROL_ADDR,
            CSR_EVENT_LAST_CAUSE_ADDR,
            CSR_EVENT_COUNT_ADDR,
            CSR_EVENT_SNAPSHOT0_ADDR,
            CSR_EVENT_SNAPSHOT1_ADDR,
            CSR_EVENT_CQ_THRESHOLD_ADDR,
            CSR_EVENT_IRQ_COUNT_ADDR,
            CSR_EVENT_MOD_CONTROL_ADDR,
            CSR_EVENT_MOD_STATUS_ADDR,
            CSR_EVENT_MOD_TIMER_LIMIT_ADDR,
            CSR_EVENT_MOD_DEBUG_ADDR,

            CSR_MEM_GUARD_VERSION_ADDR,
            CSR_MEM_GUARD_COMMAND_ADDR,
            CSR_MEM_GUARD_STATUS_ADDR,
            CSR_MEM_GUARD_ERROR_STATUS_ADDR,
            CSR_MEM_GUARD_CONTROL_ADDR,
            CSR_MEM_GUARD_REJECT_STATUS_ADDR,
            CSR_MEM_GUARD_ERROR_DETAIL_ADDR,
            CSR_MEM_GUARD_ERROR_ADDR_ADDR,
            CSR_MEM_GUARD_ERROR_SIZE_BYTES_ADDR,
            CSR_MEM_GUARD_ERROR_DOMAIN_ADDR,
            CSR_MEM_GUARD_CHECK_COUNT_ADDR,
            CSR_MEM_GUARD_ERROR_COUNT_ADDR,
            CSR_MEM_GUARD_LAST_CHECK_ADDR_ADDR,
            CSR_MEM_GUARD_LAST_CHECK_SIZE_BYTES_ADDR,
            CSR_MEM_GUARD_LAST_CHECK_DOMAIN_ADDR,
            CSR_MEM_GUARD_SQ_BASE_ADDR,
            CSR_MEM_GUARD_SQ_LIMIT_ADDR,
            CSR_MEM_GUARD_CQ_BASE_ADDR,
            CSR_MEM_GUARD_CQ_LIMIT_ADDR,
            CSR_MEM_GUARD_DESC_BASE_ADDR,
            CSR_MEM_GUARD_DESC_LIMIT_ADDR,
            CSR_MEM_GUARD_SRC_BASE_ADDR,
            CSR_MEM_GUARD_SRC_LIMIT_ADDR,
            CSR_MEM_GUARD_DST_BASE_ADDR,
            CSR_MEM_GUARD_DST_LIMIT_ADDR: begin
                return 1'b1;
            end

            default: begin
                return recipe_slot_addr_is_valid(addr);
            end
        endcase
    end
    endfunction

    function automatic logic [31:0] csr_read_data(
        input logic [CSR_ADDR_WIDTH-1:0] addr
    );
    begin
        unique case (addr)
            CSR_VERSION_ADDR: begin
                return CSR_VERSION_VALUE;
            end

            CSR_COMMAND_ADDR: begin
                return 32'h0000_0000;
            end

            CSR_STATUS_ADDR: begin
                return status_read_data;
            end

            CSR_DONE_STATUS_ADDR: begin
                return done_status_q;
            end

            CSR_ERROR_STATUS_ADDR: begin
                return error_status_q;
            end

            CSR_MODE_ADDR: begin
                return mode_q;
            end

            CSR_CMD_REJECT_STATUS_ADDR: begin
                return reject_status_q;
            end

            CSR_BASE_ADDR_A_ADDR: begin
                return base_addr_a_q;
            end

            CSR_BASE_ADDR_B_ADDR: begin
                return base_addr_b_q;
            end

            CSR_BASE_ADDR_C_ADDR: begin
                return base_addr_c_q;
            end

            CSR_DIM_M_ADDR: begin
                return dim_m_q;
            end

            CSR_DIM_N_ADDR: begin
                return dim_n_q;
            end

            CSR_DIM_K_ADDR: begin
                return dim_k_q;
            end

            CSR_DMA_LOAD_SRC_BASE_ADDR: begin
                return dma_load_src_base_q;
            end

            CSR_DMA_LOAD_DST_BASE_ADDR: begin
                return dma_load_dst_base_q;
            end

            CSR_DMA_LOAD_BEATS_ADDR: begin
                return dma_load_beats_q;
            end

            CSR_AXIS_SRC_BASE_ADDR: begin
                return axis_src_base_q;
            end

            CSR_AXIS_DST_BASE_ADDR: begin
                return axis_dst_base_q;
            end

            CSR_AXIS_LOAD_BEATS_ADDR: begin
                return axis_load_beats_q;
            end

            CSR_DS_SRC_BASE_ADDR: begin
                return ds_src_base_q;
            end

            CSR_DS_DST_BASE_ADDR: begin
                return ds_dst_base_q;
            end

            CSR_DS_LOAD_BEATS_ADDR: begin
                return ds_load_beats_q;
            end

            CSR_DS_CONTROL_ADDR: begin
                return ds_control_q;
            end

            CSR_DMA_STORE_SRC_BASE_ADDR: begin
                return dma_store_src_base_q;
            end

            CSR_DMA_STORE_DST_BASE_ADDR: begin
                return dma_store_dst_base_q;
            end

            CSR_DMA_STORE_BYTE_COUNT_ADDR: begin
                return dma_store_byte_count_q;
            end

            CSR_PERF_BUSY_CYCLES_ADDR: begin
                return perf_busy_cycles_q;
            end

            CSR_PERF_MAC_COUNT_ADDR: begin
                return perf_mac_count_q;
            end

            CSR_PERF_OUTPUT_COUNT_ADDR: begin
                return perf_output_count_q;
            end

            CSR_JOB_VERSION_ADDR: begin
                return CSR_JOB_VERSION_VALUE;
            end

            CSR_JOB_COMMAND_ADDR: begin
                return 32'h0000_0000;
            end

            CSR_JOB_STATUS_ADDR: begin
                return job_status_read_data;
            end

            CSR_JOB_DONE_STATUS_ADDR: begin
                return job_done_status_q;
            end

            CSR_JOB_ERROR_STATUS_ADDR: begin
                return job_error_status_q;
            end

            CSR_JOB_MODE_ADDR: begin
                return job_mode_q;
            end

            CSR_JOB_REJECT_STATUS_ADDR: begin
                return job_reject_status_q;
            end

            CSR_JOB_STATE_ADDR: begin
                return job_state;
            end

            CSR_JOB_BASE_ADDR_A_ADDR: begin
                return job_base_addr_a_q;
            end

            CSR_JOB_BASE_ADDR_B_ADDR: begin
                return job_base_addr_b_q;
            end

            CSR_JOB_BASE_ADDR_C_ADDR: begin
                return job_base_addr_c_q;
            end

            CSR_JOB_DIM_M_ADDR: begin
                return job_dim_m_q;
            end

            CSR_JOB_DIM_N_ADDR: begin
                return job_dim_n_q;
            end

            CSR_JOB_DIM_K_ADDR: begin
                return job_dim_k_q;
            end

            CSR_JOB_A_SRC_BASE_ADDR: begin
                return job_a_src_base_q;
            end

            CSR_JOB_A_DST_BASE_ADDR: begin
                return job_a_dst_base_q;
            end

            CSR_JOB_A_LOAD_BEATS_ADDR: begin
                return job_a_load_beats_q;
            end

            CSR_JOB_B_SRC_BASE_ADDR: begin
                return job_b_src_base_q;
            end

            CSR_JOB_B_DST_BASE_ADDR: begin
                return job_b_dst_base_q;
            end

            CSR_JOB_B_LOAD_BEATS_ADDR: begin
                return job_b_load_beats_q;
            end

            CSR_JOB_STORE_SRC_BASE_ADDR: begin
                return job_store_src_base_q;
            end

            CSR_JOB_STORE_DST_BASE_ADDR: begin
                return job_store_dst_base_q;
            end

            CSR_JOB_STORE_BYTE_COUNT_ADDR: begin
                return job_store_byte_count_q;
            end

            CSR_JOB_PERF_BUSY_CYCLES_ADDR: begin
                return job_perf_busy_cycles_q;
            end

            CSR_JOB_PERF_MAC_COUNT_ADDR: begin
                return job_perf_mac_count_q;
            end

            CSR_JOB_PERF_OUTPUT_COUNT_ADDR: begin
                return job_perf_output_count_q;
            end

            CSR_RECIPE_VERSION_ADDR: begin
                return CSR_RECIPE_VERSION_VALUE;
            end

            CSR_RECIPE_COMMAND_ADDR: begin
                return 32'h0000_0000;
            end

            CSR_RECIPE_STATUS_ADDR: begin
                return recipe_status_read_data;
            end

            CSR_RECIPE_DONE_STATUS_ADDR: begin
                return recipe_done_status_q;
            end

            CSR_RECIPE_ERROR_STATUS_ADDR: begin
                return recipe_error_status_q;
            end

            CSR_RECIPE_CONTROL_ADDR: begin
                return recipe_control_q;
            end

            CSR_RECIPE_REJECT_STATUS_ADDR: begin
                return recipe_reject_status_q;
            end

            CSR_RECIPE_STATE_ADDR: begin
                return recipe_state;
            end

            CSR_RECIPE_CURRENT_SLOT_ADDR: begin
                return recipe_current_slot;
            end

            CSR_RECIPE_COMPLETED_COUNT_ADDR: begin
                return recipe_completed_count;
            end

            CSR_RECIPE_SLOT_DONE_MASK_ADDR: begin
                return recipe_slot_done_mask_q;
            end

            CSR_RECIPE_SLOT_ERROR_MASK_ADDR: begin
                return recipe_slot_error_mask_q;
            end

            CSR_RECIPE_SLOT_REJECT_MASK_ADDR: begin
                return recipe_slot_reject_mask_q;
            end

            CSR_RECIPE_PERF_BUSY_CYCLES_ADDR: begin
                return recipe_perf_busy_cycles_q;
            end

            CSR_RECIPE_PERF_MAC_COUNT_ADDR: begin
                return recipe_perf_mac_count_q;
            end

            CSR_RECIPE_PERF_OUTPUT_COUNT_ADDR: begin
                return recipe_perf_output_count_q;
            end

            CSR_DESC_FETCH_VERSION_ADDR: begin
                return CSR_DESC_FETCH_VERSION_VALUE;
            end

            CSR_DESC_FETCH_COMMAND_ADDR: begin
                return 32'h0000_0000;
            end

            CSR_DESC_FETCH_STATUS_ADDR: begin
                return desc_fetch_status_read_data;
            end

            CSR_DESC_FETCH_DONE_STATUS_ADDR: begin
                return desc_fetch_done_read_data;
            end

            CSR_DESC_FETCH_ERROR_STATUS_ADDR: begin
                return desc_fetch_error_status;
            end

            CSR_DESC_FETCH_REJECT_STATUS_ADDR: begin
                return desc_fetch_reject_status;
            end

            CSR_DESC_FETCH_BASE_ADDR_ADDR: begin
                return desc_fetch_base_addr_q;
            end

            CSR_DESC_FETCH_COUNT_ADDR: begin
                return desc_fetch_count_q;
            end

            CSR_DESC_FETCH_STRIDE_BYTES_ADDR: begin
                return desc_fetch_stride_bytes_q;
            end

            CSR_DESC_FETCH_CURRENT_INDEX_ADDR: begin
                return {28'h000_0000, desc_fetch_current_index};
            end

            CSR_DESC_FETCH_FETCHED_COUNT_ADDR: begin
                return {28'h000_0000, desc_fetch_fetched_count};
            end

            CSR_DESC_FETCH_SNAPSHOT_STATUS_ADDR: begin
                return desc_fetch_snapshot_status_read_data;
            end

            CSR_COMPLETION_WB_VERSION_ADDR: begin
                return CSR_COMPLETION_WB_VERSION_VALUE;
            end

            CSR_COMPLETION_WB_COMMAND_ADDR: begin
                return 32'h0000_0000;
            end

            CSR_COMPLETION_WB_STATUS_ADDR: begin
                return completion_wb_status_read_data;
            end

            CSR_COMPLETION_WB_DONE_STATUS_ADDR: begin
                return completion_wb_done_status_q;
            end

            CSR_COMPLETION_WB_ERROR_STATUS_ADDR: begin
                return completion_wb_error_status_q;
            end

            CSR_COMPLETION_WB_REJECT_STATUS_ADDR: begin
                return completion_wb_reject_status_q;
            end

            CSR_COMPLETION_WB_CONTROL_ADDR: begin
                return completion_wb_control_q;
            end

            CSR_COMPLETION_WB_BASE_ADDR_ADDR: begin
                return completion_wb_base_addr_q;
            end

            CSR_COMPLETION_WB_STATUS_FLAGS_ADDR: begin
                return completion_wb_status_flags_q;
            end

            CSR_COMPLETION_WB_USER_TAG_ADDR: begin
                return completion_wb_user_tag_q;
            end

            CSR_COMPLETION_WB_COUNTS_ADDR: begin
                return completion_wb_counts_q;
            end

            CSR_COMPLETION_WB_RECIPE_DONE_ADDR: begin
                return completion_wb_recipe_done_status_q;
            end

            CSR_COMPLETION_WB_RECIPE_ERROR_ADDR: begin
                return completion_wb_recipe_error_status_q;
            end

            CSR_COMPLETION_WB_RECIPE_REJECT_ADDR: begin
                return completion_wb_recipe_reject_status_q;
            end

            CSR_COMPLETION_WB_PERF_MAC_COUNT_ADDR: begin
                return completion_wb_perf_mac_count_q;
            end

            CSR_COMPLETION_WB_ERROR_DETAIL_ADDR: begin
                return completion_wb_error_detail_q;
            end


            CSR_QUEUE_VERSION_ADDR: begin
                return CSR_QUEUE_VERSION_VALUE;
            end

            CSR_QUEUE_COMMAND_ADDR: begin
                return 32'h0000_0000;
            end

            CSR_QUEUE_STATUS_ADDR: begin
                return queue_status_read_data;
            end

            CSR_QUEUE_DONE_STATUS_ADDR: begin
                return queue_done_status;
            end

            CSR_QUEUE_ERROR_STATUS_ADDR: begin
                return queue_error_status | queue_extra_error_status_q;
            end

            CSR_QUEUE_CONTROL_ADDR: begin
                return queue_control_q;
            end

            CSR_QUEUE_REJECT_STATUS_ADDR: begin
                return queue_reject_status;
            end

            CSR_QUEUE_STATE_ADDR: begin
                return queue_state;
            end

            CSR_QUEUE_SQ_BASE_ADDR: begin
                return queue_sq_base_addr_q;
            end

            CSR_QUEUE_SQ_DEPTH_ADDR: begin
                return queue_sq_depth_q;
            end

            CSR_QUEUE_SQ_HEAD_ADDR: begin
                return queue_sq_head_q;
            end

            CSR_QUEUE_SQ_TAIL_ADDR: begin
                return queue_sq_tail_q;
            end

            CSR_QUEUE_SQ_STRIDE_ADDR: begin
                return queue_sq_stride_q;
            end

            CSR_QUEUE_CQ_BASE_ADDR: begin
                return queue_cq_base_addr_q;
            end

            CSR_QUEUE_CQ_DEPTH_ADDR: begin
                return queue_cq_depth_q;
            end

            CSR_QUEUE_CQ_HEAD_ADDR: begin
                return queue_cq_head_q;
            end

            CSR_QUEUE_CQ_TAIL_ADDR: begin
                return queue_cq_tail_q;
            end

            CSR_QUEUE_CQ_STRIDE_ADDR: begin
                return queue_cq_stride_q;
            end

            CSR_QUEUE_CURRENT_INDEX_ADDR: begin
                return queue_current_index;
            end

            CSR_QUEUE_ERROR_INDEX_ADDR: begin
                return queue_error_index;
            end

            CSR_QUEUE_ERROR_DETAIL_ADDR: begin
                return queue_error_detail;
            end

            CSR_QUEUE_LAST_CMD_TAG_ADDR: begin
                return queue_last_cmd_tag;
            end

            CSR_QUEUE_LAST_CMD_CONTROL_ADDR: begin
                return queue_last_cmd_control;
            end

            CSR_QUEUE_SQ_OCCUPANCY_ADDR: begin
                return queue_sq_occupancy;
            end

            CSR_QUEUE_CQ_OCCUPANCY_ADDR: begin
                return queue_cq_occupancy;
            end

            CSR_QUEUE_CQ_SPACE_ADDR: begin
                return queue_cq_space;
            end



            CSR_EVENT_VERSION_ADDR: begin
                return CSR_EVENT_VERSION_VALUE;
            end

            CSR_EVENT_COMMAND_ADDR: begin
                return 32'h0000_0000;
            end

            CSR_EVENT_STATUS_ADDR: begin
                return event_status_read_data;
            end

            CSR_EVENT_PENDING_ADDR: begin
                return event_pending_q & EVENT_VALID_MASK;
            end

            CSR_EVENT_ENABLE_ADDR: begin
                return event_enable_q & EVENT_VALID_MASK;
            end

            CSR_EVENT_CONTROL_ADDR: begin
                return event_control_q & EVENT_CONTROL_WR_MASK;
            end

            CSR_EVENT_LAST_CAUSE_ADDR: begin
                return event_last_cause_q;
            end

            CSR_EVENT_COUNT_ADDR: begin
                return event_count_q;
            end

            CSR_EVENT_SNAPSHOT0_ADDR: begin
                return event_snapshot0_q;
            end

            CSR_EVENT_SNAPSHOT1_ADDR: begin
                return event_snapshot1_q;
            end

            CSR_EVENT_CQ_THRESHOLD_ADDR: begin
                return event_cq_threshold_q;
            end

            CSR_EVENT_IRQ_COUNT_ADDR: begin
                return event_irq_count_q;
            end

            CSR_EVENT_MOD_CONTROL_ADDR: begin
                return event_mod_control_q & EVENT_MOD_CONTROL_WR_MASK;
            end

            CSR_EVENT_MOD_STATUS_ADDR: begin
                return event_mod_status_read_data;
            end

            CSR_EVENT_MOD_TIMER_LIMIT_ADDR: begin
                return event_mod_timer_limit_q;
            end

            CSR_EVENT_MOD_DEBUG_ADDR: begin
                return event_mod_debug_read_data;
            end

            CSR_MEM_GUARD_VERSION_ADDR: begin
                return CSR_MEM_GUARD_VERSION_VALUE;
            end

            CSR_MEM_GUARD_COMMAND_ADDR: begin
                return 32'h0000_0000;
            end

            CSR_MEM_GUARD_STATUS_ADDR: begin
                return mem_guard_status_read_data;
            end

            CSR_MEM_GUARD_ERROR_STATUS_ADDR: begin
                return mem_guard_error_status_q;
            end

            CSR_MEM_GUARD_CONTROL_ADDR: begin
                return mem_guard_control_q & MEM_GUARD_CONTROL_WR_MASK;
            end

            CSR_MEM_GUARD_REJECT_STATUS_ADDR: begin
                return mem_guard_reject_status_q;
            end

            CSR_MEM_GUARD_ERROR_DETAIL_ADDR: begin
                return mem_guard_error_detail_q;
            end

            CSR_MEM_GUARD_ERROR_ADDR_ADDR: begin
                return mem_guard_error_addr_q;
            end

            CSR_MEM_GUARD_ERROR_SIZE_BYTES_ADDR: begin
                return mem_guard_error_size_bytes_q;
            end

            CSR_MEM_GUARD_ERROR_DOMAIN_ADDR: begin
                return mem_guard_error_domain_q;
            end

            CSR_MEM_GUARD_CHECK_COUNT_ADDR: begin
                return mem_guard_check_count_q;
            end

            CSR_MEM_GUARD_ERROR_COUNT_ADDR: begin
                return mem_guard_error_count_q;
            end

            CSR_MEM_GUARD_LAST_CHECK_ADDR_ADDR: begin
                return mem_guard_last_check_addr_q;
            end

            CSR_MEM_GUARD_LAST_CHECK_SIZE_BYTES_ADDR: begin
                return mem_guard_last_check_size_bytes_q;
            end

            CSR_MEM_GUARD_LAST_CHECK_DOMAIN_ADDR: begin
                return mem_guard_last_check_domain_q;
            end

            CSR_MEM_GUARD_SQ_BASE_ADDR: begin
                return mem_guard_sq_base_q;
            end

            CSR_MEM_GUARD_SQ_LIMIT_ADDR: begin
                return mem_guard_sq_limit_q;
            end

            CSR_MEM_GUARD_CQ_BASE_ADDR: begin
                return mem_guard_cq_base_q;
            end

            CSR_MEM_GUARD_CQ_LIMIT_ADDR: begin
                return mem_guard_cq_limit_q;
            end

            CSR_MEM_GUARD_DESC_BASE_ADDR: begin
                return mem_guard_desc_base_q;
            end

            CSR_MEM_GUARD_DESC_LIMIT_ADDR: begin
                return mem_guard_desc_limit_q;
            end

            CSR_MEM_GUARD_SRC_BASE_ADDR: begin
                return mem_guard_src_base_q;
            end

            CSR_MEM_GUARD_SRC_LIMIT_ADDR: begin
                return mem_guard_src_limit_q;
            end

            CSR_MEM_GUARD_DST_BASE_ADDR: begin
                return mem_guard_dst_base_q;
            end

            CSR_MEM_GUARD_DST_LIMIT_ADDR: begin
                return mem_guard_dst_limit_q;
            end

            default: begin
                if (recipe_slot_addr_is_valid(addr)) begin
                    return recipe_slot_read_data(addr);
                end

                return 32'h0000_0000;
            end
        endcase
    end
    endfunction



    function automatic logic [7:0] first_event_index(input logic [31:0] mask);
        logic found;
    begin
        found = 1'b0;
        first_event_index = 8'hFF;
        for (int unsigned i = 0; i < 32; i++) begin
            if (!found && mask[i]) begin
                first_event_index = i;
                found = 1'b1;
            end
        end
    end
    endfunction

    function automatic logic [7:0] event_source_class(input logic [7:0] event_index);
    begin
        unique case (event_index)
            P22_EVENT_QUEUE_COMPLETED: begin
                event_source_class = EVENT_SRC_QUEUE_COMPLETION;
            end

            P22_EVENT_QUEUE_DRAINED,
            P22_EVENT_QUEUE_STOPPED: begin
                event_source_class = EVENT_SRC_QUEUE_TERMINAL;
            end

            P22_EVENT_QUEUE_ERROR: begin
                event_source_class = EVENT_SRC_QUEUE_ERROR;
            end

            P22_EVENT_CQ_NOT_EMPTY,
            P22_EVENT_CQ_THRESHOLD,
            P22_EVENT_CQ_FULL_STALL,
            P22_EVENT_CQ_SPACE_RECOVERED,
            P28_EVENT_CQ_MOD_TIMER: begin
                event_source_class = EVENT_SRC_CQ_BACKPRESSURE;
            end

            P22_EVENT_RUNTIME_DOORBELL,
            P22_EVENT_RUNTIME_CONSUMED: begin
                event_source_class = EVENT_SRC_RUNTIME_DOORBELL;
            end

            P22_EVENT_TEST: begin
                event_source_class = EVENT_SRC_SOFTWARE_TEST;
            end

            default: begin
                event_source_class = EVENT_SRC_NONE;
            end
        endcase
    end
    endfunction

    function automatic logic [31:0] build_event_last_cause(input logic [31:0] event_mask);
        logic [7:0] idx;
        logic [7:0] src_class;
    begin
        idx       = first_event_index(event_mask);
        src_class = event_source_class(idx);
        build_event_last_cause = {8'h00, event_snapshot1_comb[7:0], src_class, idx};
    end
    endfunction

    function automatic logic [31:0] count_start_bits(
        input logic [31:0] value
    );
        logic [31:0] cnt;
        int unsigned i;
    begin
        cnt = 32'd0;

        for (i = 0; i < 5; i++) begin
            if (value[i]) begin
                cnt = cnt + 32'd1;
            end
        end

        return cnt;
    end
    endfunction

    // ------------------------------------------------------------
    // Live status readback composition
    // ------------------------------------------------------------
    always_comb begin
        micro_op_busy = acc_busy        |
                        dma_load_busy   |
                        axis_load_busy  |
                        ds_load_busy    |
                        dma_store_busy;

        job_preload_required      = (job_mode_q[1:0] != JOB_INPUT_HOST_PRELOADED);
        job_store_required        = (job_mode_q[3:2] == JOB_OUTPUT_DMA_STORE);
        job_output_mode_supported = (job_mode_q[3:2] <= JOB_OUTPUT_DMA_STORE);

        status_read_data = 32'h0000_0000;

        status_read_data[0]  = acc_busy;
        status_read_data[1]  = dma_load_busy;
        status_read_data[2]  = axis_load_busy;
        status_read_data[3]  = ds_load_busy;
        status_read_data[4]  = dma_store_busy;

        status_read_data[8]  = micro_op_busy;

        status_read_data[12] = |done_status_q;
        status_read_data[13] = (|error_status_q) | (|reject_status_q);
        status_read_data[16] = 1'b1;

        job_status_read_data = 32'h0000_0000;
        job_status_read_data[0]  = job_busy;
        job_status_read_data[1]  = |job_done_status_q;
        job_status_read_data[2]  = (|job_error_status_q) | (|job_reject_status_q);
        job_status_read_data[3]  = !job_busy && !micro_op_busy && !recipe_busy;
        job_status_read_data[8]  = micro_op_busy;
        job_status_read_data[16] = 1'b1;

        recipe_count_comb      = recipe_control_q[3:0];
        recipe_start_slot_comb = recipe_control_q[7:4];
        recipe_range_valid     = (recipe_count_comb != 4'd0) &&
                                 (recipe_start_slot_comb < P16_RECIPE_QUEUE_DEPTH_U4) &&
                                 ((recipe_start_slot_comb + recipe_count_comb) <= P16_RECIPE_QUEUE_DEPTH_U4);

        recipe_selected_slots_valid = 1'b1;
        recipe_selected_desc_valid  = 1'b1;

        for (int unsigned slot_i = 0; slot_i < P16_RECIPE_QUEUE_DEPTH; slot_i++) begin
            if ((slot_i >= recipe_start_slot_comb) &&
                (slot_i < (recipe_start_slot_comb + recipe_count_comb))) begin
                if (!recipe_slot_control_q[slot_i][0]) begin
                    recipe_selected_slots_valid = 1'b0;
                end

                if (!recipe_slot_descriptor_valid(slot_i)) begin
                    recipe_selected_desc_valid = 1'b0;
                end
            end
        end

        recipe_status_read_data = 32'h0000_0000;
        recipe_status_read_data[0]  = recipe_busy;
        recipe_status_read_data[1]  = |recipe_done_status_q;
        recipe_status_read_data[2]  = (|recipe_error_status_q) | (|recipe_reject_status_q);
        recipe_status_read_data[3]  = !recipe_busy && !job_busy && !micro_op_busy;
        recipe_status_read_data[8]  = job_busy;
        recipe_status_read_data[9]  = micro_op_busy;
        recipe_status_read_data[16] = 1'b1;

        desc_fetch_status_read_data = 32'h0000_0000;
        desc_fetch_status_read_data[0]  = desc_fetch_busy;
        desc_fetch_status_read_data[1]  = desc_fetch_done;
        desc_fetch_status_read_data[2]  = desc_fetch_error | desc_fetch_reject;
        desc_fetch_status_read_data[3]  = !desc_fetch_busy && !recipe_busy && !job_busy && !micro_op_busy;
        desc_fetch_status_read_data[4]  = desc_fetch_snapshot_valid;
        desc_fetch_status_read_data[8]  = recipe_busy;
        desc_fetch_status_read_data[9]  = job_busy;
        desc_fetch_status_read_data[10] = micro_op_busy;
        desc_fetch_status_read_data[16] = 1'b1;

        desc_fetch_done_read_data = 32'h0000_0000;
        desc_fetch_done_read_data[DESC_FETCH_DONE_BIT]           = desc_fetch_done;
        desc_fetch_done_read_data[DESC_FETCH_SNAPSHOT_VALID_BIT] = desc_fetch_snapshot_valid;

        desc_fetch_snapshot_status_read_data = 32'h0000_0000;
        desc_fetch_snapshot_status_read_data[0]    = desc_fetch_snapshot_valid;
        desc_fetch_snapshot_status_read_data[7:4]  = desc_fetch_recipe_count;
        desc_fetch_snapshot_status_read_data[15:8] = {4'h0, desc_fetch_fetched_count};

        completion_wb_status_read_data = 32'h0000_0000;
        completion_wb_status_read_data[0]     = completion_wb_busy;
        completion_wb_status_read_data[1]     = |completion_wb_done_status_q;
        completion_wb_status_read_data[2]     = (|completion_wb_error_status_q) | (|completion_wb_reject_status_q);
        completion_wb_status_read_data[3]     = !completion_wb_busy;
        completion_wb_status_read_data[8]     = completion_wb_error;
        completion_wb_status_read_data[9]     = completion_wb_reject;
        completion_wb_status_read_data[15:12] = completion_wb_current_write_step;
        completion_wb_status_read_data[23:16] = completion_wb_written_beats;
        completion_wb_status_read_data[31]    = 1'b1;


        queue_status_read_data = 32'h0000_0000;
        queue_status_read_data[0]  = queue_busy;
        queue_status_read_data[1]  = queue_done_status[1];
        queue_status_read_data[2]  = (|queue_error_status) | (|queue_reject_status);
        queue_status_read_data[3]  = queue_enable && !queue_busy;
        queue_status_read_data[4]  = queue_cq_full_stall;
        queue_status_read_data[8]  = desc_fetch_busy;
        queue_status_read_data[9]  = recipe_busy;
        queue_status_read_data[10] = job_busy;
        queue_status_read_data[11] = micro_op_busy;
        queue_status_read_data[16] = 1'b1;


        // P22 event-source composition.  P22C validates the event CSR
        // window with the software-generated TEST_EVENT.  Queue-derived
        // pulses are already wired here so later P22D/P22E can validate
        // real queue completion / drained / error / CQ-backpressure events
        // without adding another CSR block or standalone top.
        event_command_masked = write_data & strobe_to_mask(write_strb);

        event_clear_pending_cmd = write_apply && write_addr_valid &&
                                  (write_addr == CSR_EVENT_COMMAND_ADDR) &&
                                  (|write_strb) &&
                                  event_command_masked[EVENT_CMD_CLEAR_PENDING];

        event_clear_counters_cmd = write_apply && write_addr_valid &&
                                   (write_addr == CSR_EVENT_COMMAND_ADDR) &&
                                   (|write_strb) &&
                                   event_command_masked[EVENT_CMD_CLEAR_COUNTERS];

        event_force_test_cmd = write_apply && write_addr_valid &&
                               (write_addr == CSR_EVENT_COMMAND_ADDR) &&
                               (|write_strb) &&
                               event_command_masked[EVENT_CMD_FORCE_TEST];

        event_snapshot0_comb = {queue_state[7:0],
                                queue_current_index[7:0],
                                queue_sq_head_q[7:0],
                                queue_sq_tail_q[7:0]};
        event_snapshot1_comb = {queue_cq_head_q[7:0],
                                queue_cq_tail_q[7:0],
                                queue_cq_space[7:0],
                                queue_cq_occupancy[7:0]};

        event_raw_source_mask = 32'h0000_0000;
        event_raw_source_mask[P22_EVENT_QUEUE_COMPLETED]    = queue_completion_commit_pulse;
        event_raw_source_mask[P22_EVENT_QUEUE_DRAINED]      = queue_drained_pulse;
        event_raw_source_mask[P22_EVENT_QUEUE_STOPPED]      = queue_done_status[3] & ~queue_done_stopped_d_q;
        event_raw_source_mask[P22_EVENT_QUEUE_ERROR]        = queue_error_pulse | queue_completion_error_pulse;
        event_raw_source_mask[P22_EVENT_CQ_NOT_EMPTY]       = queue_completion_commit_pulse;
        event_raw_source_mask[P22_EVENT_CQ_FULL_STALL]      = queue_cq_full_stall & ~queue_cq_full_stall_d_q;
        event_raw_source_mask[P22_EVENT_CQ_SPACE_RECOVERED] = queue_busy & (queue_cq_space != 32'h0000_0000) &
                                                              ~queue_cq_space_nonzero_d_q;
        event_raw_source_mask[P22_EVENT_RUNTIME_DOORBELL]   = 1'b0;
        event_raw_source_mask[P22_EVENT_RUNTIME_CONSUMED]   = 1'b0;
        event_raw_source_mask[P22_EVENT_TEST]               = event_force_test_cmd;

        event_clear_mask = 32'h0000_0000;
        if (event_clear_pending_cmd) begin
            event_clear_mask = EVENT_VALID_MASK;
        end
        if (write_apply && write_addr_valid &&
            (write_addr == CSR_EVENT_PENDING_ADDR) && (|write_strb)) begin
            event_clear_mask = event_clear_mask | (event_command_masked & EVENT_VALID_MASK);
        end

        // The queue/CQ occupancy inputs are derived from the CSR pointer
        // registers before this cycle's completion-commit pointer update.
        // Include the same-cycle commit so P28 threshold moderation observes
        // the post-commit CQ occupancy that software will read next cycle.
        event_mod_effective_cq_occupancy = queue_cq_occupancy +
                                           (queue_completion_commit_pulse ? 32'h0000_0001 : 32'h0000_0000);
        event_mod_effective_unnotified   = event_mod_unnotified_count_q +
                                           (queue_completion_commit_pulse ? 32'h0000_0001 : 32'h0000_0000);

        event_mod_enabled          = event_mod_control_q[EVENT_MOD_CONTROL_ENABLE];
        event_mod_threshold_active = event_mod_enabled &&
                                     event_mod_control_q[EVENT_MOD_CONTROL_THRESHOLD_ENABLE] &&
                                     (event_cq_threshold_q != 32'h0000_0000);
        event_mod_timer_active     = event_mod_enabled &&
                                     event_mod_control_q[EVENT_MOD_CONTROL_TIMER_ENABLE] &&
                                     (event_mod_timer_limit_q != 32'h0000_0000);
        event_completion_source    = |(event_raw_source_mask &
                                       ((32'h1 << P22_EVENT_QUEUE_COMPLETED) |
                                        (32'h1 << P22_EVENT_CQ_NOT_EMPTY)));
        event_mod_completion_pending = (event_mod_effective_unnotified != 32'h0000_0000);
        event_mod_threshold_hit    = event_mod_threshold_active &&
                                     event_mod_completion_pending &&
                                     (event_mod_effective_cq_occupancy >= event_cq_threshold_q);
        event_mod_timer_hit        = event_mod_timer_active &&
                                     (event_mod_unnotified_count_q != 32'h0000_0000) &&
                                     (event_mod_timer_count_q >= event_mod_timer_limit_q);
        event_mod_rearm_release    = event_mod_enabled &&
                                     event_mod_control_q[EVENT_MOD_CONTROL_RETRIGGER_NONEMPTY] &&
                                     (event_clear_mask != 32'h0000_0000) &&
                                     ((event_pending_q & event_clear_mask &
                                       ((32'h1 << P22_EVENT_QUEUE_COMPLETED) |
                                        (32'h1 << P22_EVENT_CQ_NOT_EMPTY) |
                                        (32'h1 << P22_EVENT_CQ_THRESHOLD) |
                                        (32'h1 << P28_EVENT_CQ_MOD_TIMER))) != 32'h0000_0000) &&
                                     (queue_cq_occupancy != 32'h0000_0000);
        event_mod_urgent_bypass    = event_mod_enabled &&
                                     |(event_raw_source_mask &
                                       ~((32'h1 << P22_EVENT_QUEUE_COMPLETED) |
                                         (32'h1 << P22_EVENT_CQ_NOT_EMPTY)));
        event_mod_release_pulse    = event_mod_enabled &&
                                     (event_mod_threshold_hit ||
                                      event_mod_timer_hit ||
                                      event_mod_rearm_release);

        event_mod_release_cause_comb = P28_MOD_RELEASE_NONE;
        if (event_mod_threshold_hit) begin
            event_mod_release_cause_comb = P28_MOD_RELEASE_THRESHOLD;
        end else if (event_mod_timer_hit) begin
            event_mod_release_cause_comb = P28_MOD_RELEASE_TIMER;
        end else if (event_mod_rearm_release) begin
            event_mod_release_cause_comb = P28_MOD_RELEASE_REARM;
        end else if (event_mod_urgent_bypass) begin
            event_mod_release_cause_comb = P28_MOD_RELEASE_URGENT;
        end else if (!event_mod_enabled && event_completion_source) begin
            event_mod_release_cause_comb = P28_MOD_RELEASE_IMMEDIATE;
        end

        event_source_mask = 32'h0000_0000;
        if (event_mod_enabled) begin
            // Urgent/terminal/debug events bypass moderation. Completion-style
            // CQ notification bits are held until threshold/timer/re-arm release.
            event_source_mask = event_raw_source_mask &
                                ~((32'h1 << P22_EVENT_QUEUE_COMPLETED) |
                                  (32'h1 << P22_EVENT_CQ_NOT_EMPTY) |
                                  (32'h1 << P22_EVENT_CQ_THRESHOLD) |
                                  (32'h1 << P28_EVENT_CQ_MOD_TIMER));

            if (event_mod_release_pulse) begin
                event_source_mask[P22_EVENT_QUEUE_COMPLETED] = 1'b1;
                event_source_mask[P22_EVENT_CQ_NOT_EMPTY]    = 1'b1;
                if (event_mod_threshold_hit) begin
                    event_source_mask[P22_EVENT_CQ_THRESHOLD] = 1'b1;
                end
                if (event_mod_timer_hit) begin
                    event_source_mask[P28_EVENT_CQ_MOD_TIMER] = 1'b1;
                end
            end
        end else begin
            // P22 compatibility mode: completion and CQ-not-empty events fire
            // immediately, and the existing threshold event is generated when
            // the post-commit CQ occupancy reaches CSR_EVENT_CQ_THRESHOLD.
            event_source_mask = event_raw_source_mask;
            if ((event_cq_threshold_q != 32'h0000_0000) &&
                (event_mod_effective_cq_occupancy >= event_cq_threshold_q) &&
                (|(event_raw_source_mask & ~(32'h1 << P22_EVENT_CQ_THRESHOLD)))) begin
                event_source_mask[P22_EVENT_CQ_THRESHOLD] = 1'b1;
            end
        end

        event_source_mask = event_source_mask & EVENT_VALID_MASK;

        event_countable = |(event_source_mask &
                            ~(event_control_q[EVENT_CONTROL_COUNT_TEST_EVENTS] ?
                              32'h0000_0000 : (32'h1 << P22_EVENT_TEST)));

        event_irq_eligible_new = event_control_q[EVENT_CONTROL_GLOBAL_IRQ_ENABLE] &&
                                 |(event_source_mask & event_enable_q & EVENT_VALID_MASK);

        event_status_read_data = 32'h0000_0000;
        event_status_read_data[0] = |(event_pending_q & EVENT_VALID_MASK);
        event_status_read_data[1] = |(event_pending_q & event_enable_q & EVENT_VALID_MASK);
        event_status_read_data[2] = event_irq;
        event_status_read_data[3] = event_control_q[EVENT_CONTROL_GLOBAL_IRQ_ENABLE];
        event_status_read_data[4] = |(event_pending_q[7:0]);
        event_status_read_data[5] = |(event_pending_q[P22_EVENT_RUNTIME_CONSUMED:P22_EVENT_RUNTIME_DOORBELL]);
        event_status_read_data[6] = event_pending_q[P22_EVENT_TEST];

        event_mod_status_read_data = 32'h0000_0000;
        event_mod_status_read_data[EVENT_MOD_STATUS_ACTIVE]           = event_mod_enabled;
        event_mod_status_read_data[EVENT_MOD_STATUS_THRESHOLD_ACTIVE] = event_mod_threshold_active;
        event_mod_status_read_data[EVENT_MOD_STATUS_TIMER_ACTIVE]     = event_mod_timer_active;
        event_mod_status_read_data[EVENT_MOD_STATUS_TIMER_RUNNING]    = event_mod_timer_active &&
                                                                        (event_mod_unnotified_count_q != 32'h0000_0000);
        event_mod_status_read_data[EVENT_MOD_STATUS_THRESHOLD_MET]    = event_mod_threshold_hit;
        event_mod_status_read_data[EVENT_MOD_STATUS_TIMER_EXPIRED]    = event_mod_timer_expired_q || event_mod_timer_hit;
        event_mod_status_read_data[EVENT_MOD_STATUS_RELEASE_PENDING]  = event_mod_release_pulse;
        event_mod_status_read_data[EVENT_MOD_STATUS_URGENT_BYPASS]    = event_mod_urgent_bypass;
        event_mod_status_read_data[23:16] = event_mod_effective_cq_occupancy[7:0];
        event_mod_status_read_data[31:24] = event_mod_effective_unnotified[7:0];

        event_mod_debug_read_data = {event_mod_timer_release_count_q[7:0],
                                     event_mod_threshold_release_count_q[7:0],
                                     event_mod_release_count_q[7:0],
                                     event_mod_last_release_cause_q};

        mem_guard_status_read_data = 32'h0000_0000;
        mem_guard_status_read_data[MEM_GUARD_STATUS_GUARD_ENABLED]      = mem_guard_control_q[MEM_GUARD_CONTROL_ENABLE];
        mem_guard_status_read_data[MEM_GUARD_STATUS_STRICT_ENABLED]     = mem_guard_control_q[MEM_GUARD_CONTROL_STRICT_REJECT];
        mem_guard_status_read_data[MEM_GUARD_STATUS_ANY_ERROR]          = |mem_guard_error_status_q;
        mem_guard_status_read_data[MEM_GUARD_STATUS_ANY_REJECT]         = |mem_guard_reject_status_q;
        mem_guard_status_read_data[MEM_GUARD_STATUS_SQ_CHECK_ENABLED]   = mem_guard_control_q[MEM_GUARD_CONTROL_SQ_CHECK_ENABLE];
        mem_guard_status_read_data[MEM_GUARD_STATUS_CQ_CHECK_ENABLED]   = mem_guard_control_q[MEM_GUARD_CONTROL_CQ_CHECK_ENABLE];
        mem_guard_status_read_data[MEM_GUARD_STATUS_DESC_CHECK_ENABLED] = mem_guard_control_q[MEM_GUARD_CONTROL_DESC_CHECK_ENABLE];
        mem_guard_status_read_data[MEM_GUARD_STATUS_SRC_CHECK_ENABLED]  = mem_guard_control_q[MEM_GUARD_CONTROL_SRC_CHECK_ENABLE];
        mem_guard_status_read_data[MEM_GUARD_STATUS_DST_CHECK_ENABLED]  = mem_guard_control_q[MEM_GUARD_CONTROL_DST_CHECK_ENABLE];
        mem_guard_status_read_data[MEM_GUARD_STATUS_ERROR_PENDING]      = |mem_guard_error_status_q;
        mem_guard_status_read_data[MEM_GUARD_STATUS_QUEUE_ERROR_MIRROR] = (((queue_error_status | queue_extra_error_status_q) >> P27_QUEUE_MEMORY_GUARD_ERROR_BIT) & 32'h0000_0001);
    end

    // ------------------------------------------------------------
    // AXI-Lite handshake outputs
    // ------------------------------------------------------------
    assign csr_if.awready = !awaddr_valid_q && !bvalid_q;
    assign csr_if.wready  = !wdata_valid_q  && !bvalid_q;
    assign csr_if.bvalid  = bvalid_q;
    assign csr_if.bresp   = bresp_q;

    assign csr_if.arready = !rvalid_q;
    assign csr_if.rvalid  = rvalid_q;
    assign csr_if.rdata   = rdata_q;
    assign csr_if.rresp   = rresp_q;

    assign event_irq = event_control_q[EVENT_CONTROL_GLOBAL_IRQ_ENABLE] &&
                       |(event_pending_q & event_enable_q & EVENT_VALID_MASK);

    always_comb begin
        aw_fire = csr_if.awvalid && csr_if.awready;
        w_fire  = csr_if.wvalid  && csr_if.wready;
        b_fire  = csr_if.bvalid  && csr_if.bready;
        ar_fire = csr_if.arvalid && csr_if.arready;
        r_fire  = csr_if.rvalid  && csr_if.rready;

        write_addr  = aw_fire ? csr_if.awaddr : awaddr_q;
        write_data  = w_fire  ? csr_if.wdata  : wdata_q;
        write_strb  = w_fire  ? csr_if.wstrb  : wstrb_q;

        write_apply = !bvalid_q &&
                      (awaddr_valid_q || aw_fire) &&
                      (wdata_valid_q  || w_fire);

        write_addr_valid = csr_addr_is_valid(write_addr);
        read_addr_valid  = csr_addr_is_valid(csr_if.araddr);
        read_data_comb   = csr_read_data(csr_if.araddr);
    end

    // ------------------------------------------------------------
    // Command decode helpers for the current write transaction
    // ------------------------------------------------------------
    always_comb begin
        command_has_active_strobe = |write_strb;
        command_masked            = write_data & strobe_to_mask(write_strb);
        start_bits                = command_masked & CMD_START_MASK;
        command_has_start         = |start_bits;
        command_multi_start       = (count_start_bits(start_bits) > 32'd1);

        command_unsupported_combo = command_multi_start ||
                                    (command_has_start &&
                                     command_masked[CMD_CLEAR_ERROR_BIT] &&
                                     ((|error_status_q) || (|reject_status_q)));

        job_command_has_active_strobe = |write_strb;
        job_command_masked            = write_data & strobe_to_mask(write_strb);
        job_command_has_start         = job_command_masked[JOB_CMD_START_BIT];

        job_command_unsupported_combo = (job_command_has_start &&
                                         job_command_masked[JOB_CMD_CLEAR_ERROR_BIT] &&
                                         ((|job_error_status_q) || (|job_reject_status_q)));

        recipe_command_has_active_strobe = |write_strb;
        recipe_command_masked            = write_data & strobe_to_mask(write_strb);
        recipe_command_has_start         = recipe_command_masked[RECIPE_CMD_START_BIT];

        recipe_command_unsupported_combo = (recipe_command_has_start &&
                                            recipe_command_masked[RECIPE_CMD_CLEAR_ERROR_BIT] &&
                                            ((|recipe_error_status_q) || (|recipe_reject_status_q)));

        desc_fetch_command_has_active_strobe = |write_strb;
        desc_fetch_command_masked            = write_data & strobe_to_mask(write_strb);
        desc_fetch_command_has_start         = desc_fetch_command_masked[DESC_FETCH_CMD_START_BIT];

        completion_wb_command_has_active_strobe = |write_strb;
        completion_wb_command_masked            = write_data & strobe_to_mask(write_strb);
        completion_wb_command_has_start         = completion_wb_command_masked[COMP_WB_CMD_START_BIT];
        completion_wb_command_unsupported_combo = completion_wb_command_has_start &&
                                                  completion_wb_command_masked[COMP_WB_CMD_CLEAR_ERROR_BIT] &&
                                                  ((|completion_wb_error_status_q) || (|completion_wb_reject_status_q));


        queue_command_has_active_strobe = |write_strb;
        queue_command_masked            = write_data & strobe_to_mask(write_strb);
        queue_command_has_start         = queue_command_masked[QUEUE_CMD_START_BIT];

        mem_guard_command_has_active_strobe = |write_strb;
        mem_guard_command_masked            = write_data & strobe_to_mask(write_strb);
    end

    // ------------------------------------------------------------
    // CSR storage and AXI-Lite transaction state
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awaddr_q        <= '0;
            awaddr_valid_q  <= 1'b0;

            wdata_q         <= 32'h0000_0000;
            wstrb_q         <= '0;
            wdata_valid_q   <= 1'b0;

            bvalid_q        <= 1'b0;
            bresp_q         <= AXI_RESP_OKAY;

            rvalid_q        <= 1'b0;
            rdata_q         <= 32'h0000_0000;
            rresp_q         <= AXI_RESP_OKAY;

            mode_q          <= 32'h0000_0000;

            base_addr_a_q   <= 32'h0000_0000;
            base_addr_b_q   <= 32'h0000_0100;
            base_addr_c_q   <= 32'h0000_0200;

            dim_m_q         <= 32'h0000_0004;
            dim_n_q         <= 32'h0000_0004;
            dim_k_q         <= 32'h0000_0004;

            dma_load_src_base_q    <= 32'h0000_0000;
            dma_load_dst_base_q    <= 32'h0000_0000;
            dma_load_beats_q       <= 32'h0000_0000;

            axis_src_base_q        <= 32'h0000_0000;
            axis_dst_base_q        <= 32'h0000_0000;
            axis_load_beats_q      <= 32'h0000_0000;

            ds_src_base_q          <= 32'h0000_0000;
            ds_dst_base_q          <= 32'h0000_0000;
            ds_load_beats_q        <= 32'h0000_0000;
            ds_control_q           <= 32'h0000_0000;

            dma_store_src_base_q   <= 32'h0000_0000;
            dma_store_dst_base_q   <= 32'h0000_0000;
            dma_store_byte_count_q <= 32'h0000_0000;

            done_status_q          <= 32'h0000_0000;
            error_status_q         <= 32'h0000_0000;
            reject_status_q        <= 32'h0000_0000;

            perf_busy_cycles_q     <= 32'h0000_0000;
            perf_mac_count_q       <= 32'h0000_0000;
            perf_output_count_q    <= 32'h0000_0000;

            job_mode_q             <= 32'h0000_0004;

            job_base_addr_a_q      <= 32'h0000_0000;
            job_base_addr_b_q      <= 32'h0000_0100;
            job_base_addr_c_q      <= 32'h0000_0200;

            job_dim_m_q            <= 32'h0000_0004;
            job_dim_n_q            <= 32'h0000_0004;
            job_dim_k_q            <= 32'h0000_0004;

            job_a_src_base_q       <= 32'h0000_0000;
            job_a_dst_base_q       <= 32'h0000_0000;
            job_a_load_beats_q     <= 32'h0000_0000;

            job_b_src_base_q       <= 32'h0000_0100;
            job_b_dst_base_q       <= 32'h0000_0100;
            job_b_load_beats_q     <= 32'h0000_0000;

            job_store_src_base_q   <= 32'h0000_0200;
            job_store_dst_base_q   <= 32'h0000_0000;
            job_store_byte_count_q <= 32'h0000_0000;

            job_done_status_q      <= 32'h0000_0000;
            job_error_status_q     <= 32'h0000_0000;
            job_reject_status_q    <= 32'h0000_0000;

            job_perf_busy_cycles_q  <= 32'h0000_0000;
            job_perf_mac_count_q    <= 32'h0000_0000;
            job_perf_output_count_q <= 32'h0000_0000;

            recipe_control_q       <= 32'h0000_0700;

            recipe_done_status_q   <= 32'h0000_0000;
            recipe_error_status_q  <= 32'h0000_0000;
            recipe_reject_status_q <= 32'h0000_0000;
            recipe_slot_done_mask_q   <= 32'h0000_0000;
            recipe_slot_error_mask_q  <= 32'h0000_0000;
            recipe_slot_reject_mask_q <= 32'h0000_0000;

            recipe_perf_busy_cycles_q  <= 32'h0000_0000;
            recipe_perf_mac_count_q    <= 32'h0000_0000;
            recipe_perf_output_count_q <= 32'h0000_0000;

            desc_fetch_base_addr_q     <= 32'h0000_0000;
            desc_fetch_count_q         <= 32'h0000_0000;
            desc_fetch_stride_bytes_q  <= 32'h0000_0080;

            completion_wb_control_q              <= 32'h0000_0003;
            completion_wb_base_addr_q            <= 32'h0000_0300;
            completion_wb_status_flags_q         <= 32'h0000_0000;
            completion_wb_user_tag_q             <= 32'h0000_0000;
            completion_wb_counts_q               <= 32'h0000_0000;
            completion_wb_recipe_done_status_q   <= 32'h0000_0000;
            completion_wb_recipe_error_status_q  <= 32'h0000_0000;
            completion_wb_recipe_reject_status_q <= 32'h0000_0000;
            completion_wb_perf_mac_count_q       <= 32'h0000_0000;
            completion_wb_error_detail_q         <= 32'h0000_0000;
            completion_wb_done_status_q          <= 32'h0000_0000;
            completion_wb_error_status_q         <= 32'h0000_0000;
            completion_wb_reject_status_q        <= 32'h0000_0000;
            completion_wb_clear_done_holdoff_q  <= 1'b0;
            completion_wb_clear_error_holdoff_q <= 1'b0;


            queue_control_q      <= 32'h0000_0005;
            queue_sq_base_addr_q <= 32'h0000_0000;
            queue_sq_depth_q     <= 32'h0000_0004;
            queue_sq_head_q      <= 32'h0000_0000;
            queue_sq_tail_q      <= 32'h0000_0000;
            queue_sq_stride_q    <= 32'h0000_0040;
            queue_cq_base_addr_q <= 32'h0000_0000;
            queue_cq_depth_q     <= 32'h0000_0004;
            queue_cq_head_q      <= 32'h0000_0000;
            queue_cq_tail_q      <= 32'h0000_0000;
            queue_cq_stride_q    <= 32'h0000_0040;
            queue_extra_error_status_q <= 32'h0000_0000;

            mem_guard_control_q                <= 32'h0000_0000;
            mem_guard_error_status_q           <= 32'h0000_0000;
            mem_guard_reject_status_q          <= 32'h0000_0000;
            mem_guard_error_detail_q           <= 32'h0000_0000;
            mem_guard_error_addr_q             <= 32'h0000_0000;
            mem_guard_error_size_bytes_q       <= 32'h0000_0000;
            mem_guard_error_domain_q           <= 32'h0000_0000;
            mem_guard_check_count_q            <= 32'h0000_0000;
            mem_guard_error_count_q            <= 32'h0000_0000;
            mem_guard_last_check_addr_q        <= 32'h0000_0000;
            mem_guard_last_check_size_bytes_q  <= 32'h0000_0000;
            mem_guard_last_check_domain_q      <= 32'h0000_0000;
            mem_guard_sq_base_q                <= 32'h0000_0000;
            mem_guard_sq_limit_q               <= 32'h0000_0000;
            mem_guard_cq_base_q                <= 32'h0000_0000;
            mem_guard_cq_limit_q               <= 32'h0000_0000;
            mem_guard_desc_base_q              <= 32'h0000_0000;
            mem_guard_desc_limit_q             <= 32'h0000_0000;
            mem_guard_src_base_q               <= 32'h0000_0000;
            mem_guard_src_limit_q              <= 32'h0000_0000;
            mem_guard_dst_base_q               <= 32'h0000_0000;
            mem_guard_dst_limit_q              <= 32'h0000_0000;

            event_pending_q      <= 32'h0000_0000;
            event_enable_q       <= 32'h0000_0000;
            event_control_q      <= CSR_EVENT_CONTROL_RESET & EVENT_CONTROL_WR_MASK;
            event_last_cause_q   <= 32'h0000_0000;
            event_count_q        <= 32'h0000_0000;
            event_snapshot0_q    <= 32'h0000_0000;
            event_snapshot1_q    <= 32'h0000_0000;
            event_cq_threshold_q <= 32'h0000_0000;
            event_irq_count_q    <= 32'h0000_0000;
            event_mod_control_q                 <= 32'h0000_0000;
            event_mod_timer_limit_q             <= 32'h0000_0000;
            event_mod_timer_count_q             <= 32'h0000_0000;
            event_mod_unnotified_count_q        <= 32'h0000_0000;
            event_mod_release_count_q           <= 32'h0000_0000;
            event_mod_threshold_release_count_q <= 32'h0000_0000;
            event_mod_timer_release_count_q     <= 32'h0000_0000;
            event_mod_last_release_cause_q      <= P28_MOD_RELEASE_NONE;
            event_mod_timer_expired_q           <= 1'b0;
            queue_done_stopped_d_q      <= 1'b0;
            queue_cq_full_stall_d_q     <= 1'b0;
            queue_cq_space_nonzero_d_q  <= 1'b0;

            for (int unsigned slot_i = 0; slot_i < P16_RECIPE_QUEUE_DEPTH; slot_i++) begin
                recipe_slot_control_q[slot_i]          <= 32'h0000_0000;
                recipe_slot_base_addr_a_q[slot_i]      <= 32'h0000_0000;
                recipe_slot_base_addr_b_q[slot_i]      <= 32'h0000_0100;
                recipe_slot_base_addr_c_q[slot_i]      <= 32'h0000_0200;
                recipe_slot_dim_m_q[slot_i]            <= 32'h0000_0004;
                recipe_slot_dim_n_q[slot_i]            <= 32'h0000_0004;
                recipe_slot_dim_k_q[slot_i]            <= 32'h0000_0004;
                recipe_slot_a_src_base_q[slot_i]       <= 32'h0000_0000;
                recipe_slot_a_dst_base_q[slot_i]       <= 32'h0000_0000;
                recipe_slot_a_load_beats_q[slot_i]     <= 32'h0000_0000;
                recipe_slot_b_src_base_q[slot_i]       <= 32'h0000_0100;
                recipe_slot_b_dst_base_q[slot_i]       <= 32'h0000_0100;
                recipe_slot_b_load_beats_q[slot_i]     <= 32'h0000_0000;
                recipe_slot_store_src_base_q[slot_i]   <= 32'h0000_0200;
                recipe_slot_store_dst_base_q[slot_i]   <= 32'h0000_0000;
                recipe_slot_store_byte_count_q[slot_i] <= 32'h0000_0000;
                recipe_slot_user_tag_q[slot_i]         <= 32'h0000_0000;
            end

            acc_start_pulse        <= 1'b0;
            dma_load_start_pulse   <= 1'b0;
            axis_load_start_pulse  <= 1'b0;
            ds_load_start_pulse    <= 1'b0;
            dma_store_start_pulse  <= 1'b0;

            job_start_pulse        <= 1'b0;
            job_clear_done_pulse   <= 1'b0;
            job_clear_error_pulse  <= 1'b0;
            job_clear_perf_pulse   <= 1'b0;

            recipe_start_pulse             <= 1'b0;
            recipe_clear_done_pulse        <= 1'b0;
            recipe_clear_error_pulse       <= 1'b0;
            recipe_clear_perf_pulse        <= 1'b0;
            recipe_clear_slot_status_pulse <= 1'b0;

            desc_fetch_start_pulse       <= 1'b0;
            desc_fetch_clear_done_pulse  <= 1'b0;
            desc_fetch_clear_error_pulse <= 1'b0;

            completion_wb_start_pulse       <= 1'b0;
            completion_wb_clear_done_pulse  <= 1'b0;
            completion_wb_clear_error_pulse <= 1'b0;

            queue_start_pulse       <= 1'b0;
            queue_stop_pulse        <= 1'b0;
            queue_clear_done_pulse  <= 1'b0;
            queue_clear_error_pulse <= 1'b0;
        end
        else begin
            acc_start_pulse       <= 1'b0;
            dma_load_start_pulse  <= 1'b0;
            axis_load_start_pulse <= 1'b0;
            ds_load_start_pulse   <= 1'b0;
            dma_store_start_pulse <= 1'b0;

            job_start_pulse       <= 1'b0;
            job_clear_done_pulse  <= 1'b0;
            job_clear_error_pulse <= 1'b0;
            job_clear_perf_pulse  <= 1'b0;

            recipe_start_pulse             <= 1'b0;
            recipe_clear_done_pulse        <= 1'b0;
            recipe_clear_error_pulse       <= 1'b0;
            recipe_clear_perf_pulse        <= 1'b0;
            recipe_clear_slot_status_pulse <= 1'b0;

            desc_fetch_start_pulse       <= 1'b0;
            desc_fetch_clear_done_pulse  <= 1'b0;
            desc_fetch_clear_error_pulse <= 1'b0;

            completion_wb_start_pulse       <= 1'b0;
            completion_wb_clear_done_pulse  <= 1'b0;
            completion_wb_clear_error_pulse <= 1'b0;

            queue_start_pulse       <= 1'b0;
            queue_stop_pulse        <= 1'b0;
            queue_clear_done_pulse  <= 1'b0;
            queue_clear_error_pulse <= 1'b0;


            queue_done_stopped_d_q     <= queue_done_status[3];
            queue_cq_full_stall_d_q    <= queue_cq_full_stall;
            queue_cq_space_nonzero_d_q <= (queue_cq_space != 32'h0000_0000);

            event_pending_q <= (event_pending_q & ~event_clear_mask) | event_source_mask;

            if (event_clear_counters_cmd) begin
                event_last_cause_q <= 32'h0000_0000;
                event_count_q      <= 32'h0000_0000;
                event_snapshot0_q  <= 32'h0000_0000;
                event_snapshot1_q  <= 32'h0000_0000;
                event_irq_count_q  <= 32'h0000_0000;
            end
            else begin
                if (|event_source_mask) begin
                    event_last_cause_q <= build_event_last_cause(event_source_mask);
                    if (event_control_q[EVENT_CONTROL_CAPTURE_SNAPSHOT]) begin
                        event_snapshot0_q <= event_snapshot0_comb;
                        event_snapshot1_q <= event_snapshot1_comb;
                    end
                end

                if (event_countable) begin
                    event_count_q <= event_count_q + 32'd1;
                end

                if (event_irq_eligible_new) begin
                    event_irq_count_q <= event_irq_count_q + 32'd1;
                end
            end

            if (event_clear_counters_cmd) begin
                event_mod_timer_count_q             <= 32'h0000_0000;
                event_mod_unnotified_count_q        <= 32'h0000_0000;
                event_mod_release_count_q           <= 32'h0000_0000;
                event_mod_threshold_release_count_q <= 32'h0000_0000;
                event_mod_timer_release_count_q     <= 32'h0000_0000;
                event_mod_last_release_cause_q      <= P28_MOD_RELEASE_NONE;
                event_mod_timer_expired_q           <= 1'b0;
            end else begin
                if (!event_mod_enabled || (event_mod_unnotified_count_q == 32'h0000_0000)) begin
                    event_mod_timer_count_q   <= 32'h0000_0000;
                    event_mod_timer_expired_q <= 1'b0;
                end else if (event_mod_release_pulse) begin
                    event_mod_timer_count_q   <= 32'h0000_0000;
                    event_mod_timer_expired_q <= event_mod_timer_hit;
                end else if (event_mod_timer_active) begin
                    event_mod_timer_count_q <= event_mod_timer_count_q + 32'd1;
                end

                if (event_mod_release_pulse || event_mod_urgent_bypass ||
                    (!event_mod_enabled && event_completion_source)) begin
                    event_mod_last_release_cause_q <= event_mod_release_cause_comb;
                end

                if (event_mod_release_pulse) begin
                    event_mod_release_count_q <= event_mod_release_count_q + 32'd1;
                    if (event_mod_threshold_hit) begin
                        event_mod_threshold_release_count_q <= event_mod_threshold_release_count_q + 32'd1;
                    end
                    if (event_mod_timer_hit) begin
                        event_mod_timer_release_count_q <= event_mod_timer_release_count_q + 32'd1;
                    end
                end
            end

            if (!event_mod_enabled) begin
                event_mod_unnotified_count_q <= 32'h0000_0000;
            end else if (event_mod_release_pulse) begin
                event_mod_unnotified_count_q <= 32'h0000_0000;
            end else if (queue_completion_commit_pulse) begin
                event_mod_unnotified_count_q <= event_mod_unnotified_count_q + 32'd1;
            end

            if (queue_completion_commit_pulse) begin
                queue_sq_head_q <= queue_sq_head_q + 32'd1;
                queue_cq_tail_q <= queue_cq_tail_q + 32'd1;
            end

            if (queue_clear_error_pulse) begin
                queue_extra_error_status_q <= 32'h0000_0000;
            end else if (queue_completion_error_pulse) begin
                queue_extra_error_status_q[4] <= 1'b1;
            end

            if (mem_guard_check_pulse) begin
                mem_guard_check_count_q           <= mem_guard_check_count_q + 32'd1;
                mem_guard_last_check_addr_q       <= mem_guard_last_check_addr;
                mem_guard_last_check_size_bytes_q <= mem_guard_last_check_size_bytes;
                mem_guard_last_check_domain_q     <= mem_guard_last_check_domain;
            end

            if (mem_guard_error_pulse) begin
                mem_guard_error_status_q     <= mem_guard_error_status_q | mem_guard_error_status;
                mem_guard_reject_status_q    <= mem_guard_reject_status_q | mem_guard_reject_status;
                mem_guard_error_detail_q     <= mem_guard_error_detail;
                mem_guard_error_addr_q       <= mem_guard_error_addr;
                mem_guard_error_size_bytes_q <= mem_guard_error_size_bytes;
                mem_guard_error_domain_q     <= mem_guard_error_domain;
                mem_guard_error_count_q      <= mem_guard_error_count_q + 32'd1;
            end

            completion_wb_clear_done_holdoff_q  <= 1'b0;
            completion_wb_clear_error_holdoff_q <= 1'b0;

            // Sticky completion and error capture.
            if (acc_done) begin
                done_status_q[DONE_GEMM_BIT] <= 1'b1;

                perf_busy_cycles_q  <= gemm_perf_busy_cycles;
                perf_mac_count_q    <= gemm_perf_mac_count;
                perf_output_count_q <= gemm_perf_output_count;
            end

            if (dma_load_done) begin
                done_status_q[DONE_DMA_LOAD_BIT] <= 1'b1;
            end

            if (axis_load_done) begin
                done_status_q[DONE_AXIS_LOAD_BIT] <= 1'b1;
            end

            if (ds_load_done) begin
                done_status_q[DONE_DS_LOAD_BIT] <= 1'b1;
            end

            if (dma_store_done) begin
                done_status_q[DONE_DMA_STORE_BIT] <= 1'b1;
            end

            if (dma_load_error) begin
                error_status_q[ERR_DMA_LOAD_BIT] <= 1'b1;
            end

            if (axis_load_error) begin
                error_status_q[ERR_AXIS_LOAD_BIT] <= 1'b1;
            end

            if (ds_load_error) begin
                error_status_q[ERR_DS_LOAD_BIT] <= 1'b1;
            end

            if (dma_store_error) begin
                error_status_q[ERR_DMA_STORE_BIT] <= 1'b1;
            end

            if (job_done) begin
                job_done_status_q[JOB_DONE_BIT] <= 1'b1;
            end

            if (job_gemm_done) begin
                job_done_status_q[JOB_GEMM_DONE_BIT] <= 1'b1;

                job_perf_busy_cycles_q  <= job_perf_busy_cycles;
                job_perf_mac_count_q    <= job_perf_mac_count;
                job_perf_output_count_q <= job_perf_output_count;
            end

            if (job_store_done) begin
                job_done_status_q[JOB_STORE_DONE_BIT] <= 1'b1;
            end

            if (job_dma_load_error) begin
                job_error_status_q[JOB_ERR_DMA_LOAD_BIT] <= 1'b1;
            end

            if (job_axis_load_error) begin
                job_error_status_q[JOB_ERR_AXIS_LOAD_BIT] <= 1'b1;
            end

            if (job_ds_load_error) begin
                job_error_status_q[JOB_ERR_DS_LOAD_BIT] <= 1'b1;
            end

            if (job_dma_store_error) begin
                job_error_status_q[JOB_ERR_DMA_STORE_BIT] <= 1'b1;
            end

            if (job_sequence_error) begin
                job_error_status_q[JOB_ERR_SEQUENCE_BIT] <= 1'b1;
            end

            if (recipe_done) begin
                recipe_done_status_q[RECIPE_DONE_BIT] <= 1'b1;

                recipe_perf_busy_cycles_q  <= recipe_perf_busy_cycles;
                recipe_perf_mac_count_q    <= recipe_perf_mac_count;
                recipe_perf_output_count_q <= recipe_perf_output_count;
            end

            if (recipe_all_slots_done) begin
                recipe_done_status_q[RECIPE_ALL_SLOTS_DONE_BIT] <= 1'b1;
            end

            if (recipe_final_store_done) begin
                recipe_done_status_q[RECIPE_FINAL_STORE_DONE_BIT] <= 1'b1;
            end

            if (recipe_slot_job_error) begin
                recipe_error_status_q[RECIPE_ERR_SLOT_JOB_ERROR_BIT] <= 1'b1;
            end

            if (recipe_slot_job_reject) begin
                recipe_error_status_q[RECIPE_ERR_SLOT_JOB_REJECT_BIT] <= 1'b1;
            end

            if (recipe_sequence_error) begin
                recipe_error_status_q[RECIPE_ERR_SEQUENCE_BIT] <= 1'b1;
            end

            if (recipe_slot_range_error) begin
                recipe_error_status_q[RECIPE_ERR_SLOT_RANGE_BIT] <= 1'b1;
            end

            if (recipe_slot_descriptor_error) begin
                recipe_error_status_q[RECIPE_ERR_SLOT_DESCRIPTOR_BIT] <= 1'b1;
            end

            recipe_slot_done_mask_q   <= recipe_slot_done_mask_q   | recipe_slot_done_mask;
            recipe_slot_error_mask_q  <= recipe_slot_error_mask_q  | recipe_slot_error_mask;
            recipe_slot_reject_mask_q <= recipe_slot_reject_mask_q | recipe_slot_reject_mask;

            if (completion_wb_done && !completion_wb_clear_done_holdoff_q) begin
                completion_wb_done_status_q[COMP_WB_DONE_BIT] <= 1'b1;
            end

            if (completion_wb_error && !completion_wb_clear_error_holdoff_q) begin
                completion_wb_error_status_q <= completion_wb_error_status_q |
                                                completion_wb_error_status |
                                                32'h0000_0001;
            end

            if (completion_wb_reject && !completion_wb_clear_error_holdoff_q) begin
                completion_wb_reject_status_q <= completion_wb_reject_status_q |
                                                 completion_wb_reject_status |
                                                 32'h0000_0001;
            end

            // Capture write address/data channels independently.
            if (aw_fire && !write_apply) begin
                awaddr_q       <= csr_if.awaddr;
                awaddr_valid_q <= 1'b1;
            end
            else if (write_apply) begin
                awaddr_valid_q <= 1'b0;
            end

            if (w_fire && !write_apply) begin
                wdata_q       <= csr_if.wdata;
                wstrb_q       <= csr_if.wstrb;
                wdata_valid_q <= 1'b1;
            end
            else if (write_apply) begin
                wdata_valid_q <= 1'b0;
            end

            if (b_fire) begin
                bvalid_q <= 1'b0;
            end

            if (write_apply) begin
                bvalid_q <= 1'b1;
                bresp_q  <= write_addr_valid ? AXI_RESP_OKAY : AXI_RESP_SLVERR;

                if (write_addr_valid && (|write_strb)) begin
                    unique case (write_addr)
                        CSR_COMMAND_ADDR: begin
                            if (command_has_active_strobe) begin
                                if (command_unsupported_combo) begin
                                    reject_status_q[REJ_UNSUPPORTED_BIT] <= 1'b1;
                                end
                                else begin
                                    if (command_masked[CMD_CLEAR_DONE_BIT]) begin
                                        done_status_q <= 32'h0000_0000;
                                    end

                                    if (command_masked[CMD_CLEAR_ERROR_BIT]) begin
                                        error_status_q  <= 32'h0000_0000;
                                        reject_status_q <= 32'h0000_0000;
                                    end

                                    if (command_masked[CMD_CLEAR_PERF_BIT]) begin
                                        perf_busy_cycles_q  <= 32'h0000_0000;
                                        perf_mac_count_q    <= 32'h0000_0000;
                                        perf_output_count_q <= 32'h0000_0000;
                                    end

                                    if (command_has_start && desc_fetch_busy) begin
                                        // P17G: descriptor fetch owns the next recipe-launch window.
                                        // Reject manual P14 micro-op starts while a fetch is active so
                                        // debug/manual traffic cannot race the fetched recipe snapshot.
                                        reject_status_q[REJ_UNSUPPORTED_BIT] <= 1'b1;
                                    end
                                    else if (command_has_start && recipe_busy) begin
                                        recipe_reject_status_q[RECIPE_REJ_MANUAL_CMD_BIT] <= 1'b1;
                                    end
                                    else if (command_has_start && job_busy) begin
                                        job_reject_status_q[JOB_REJ_MANUAL_CMD_BIT] <= 1'b1;
                                    end
                                    else begin
                                        if (command_masked[CMD_START_GEMM_BIT]) begin
                                        if (acc_busy || axis_load_busy || ds_load_busy) begin
                                            reject_status_q[REJ_GEMM_BUSY_BIT] <= 1'b1;
                                        end
                                        else if ((dim_m_q == 32'h0000_0000) ||
                                                 (dim_n_q == 32'h0000_0000) ||
                                                 (dim_k_q == 32'h0000_0000)) begin
                                            reject_status_q[REJ_ZERO_LENGTH_BIT] <= 1'b1;
                                        end
                                        else begin
                                            acc_start_pulse <= 1'b1;
                                        end
                                    end

                                    if (command_masked[CMD_START_DMA_LOAD_BIT]) begin
                                        if (dma_load_busy || dma_store_busy) begin
                                            reject_status_q[REJ_DMA_LOAD_BUSY_BIT] <= 1'b1;
                                        end
                                        else if (dma_load_beats_q == 32'h0000_0000) begin
                                            reject_status_q[REJ_ZERO_LENGTH_BIT] <= 1'b1;
                                        end
                                        else begin
                                            dma_load_start_pulse <= 1'b1;
                                        end
                                    end

                                    if (command_masked[CMD_START_AXIS_LOAD_BIT]) begin
                                        if (axis_load_busy || acc_busy) begin
                                            reject_status_q[REJ_AXIS_BUSY_BIT] <= 1'b1;
                                        end
                                        else if (axis_load_beats_q == 32'h0000_0000) begin
                                            reject_status_q[REJ_ZERO_LENGTH_BIT] <= 1'b1;
                                        end
                                        else begin
                                            axis_load_start_pulse <= 1'b1;
                                        end
                                    end

                                    if (command_masked[CMD_START_DS_LOAD_BIT]) begin
                                        if (ds_load_busy || acc_busy) begin
                                            reject_status_q[REJ_DS_BUSY_BIT] <= 1'b1;
                                        end
                                        else if (ds_load_beats_q == 32'h0000_0000) begin
                                            reject_status_q[REJ_ZERO_LENGTH_BIT] <= 1'b1;
                                        end
                                        else begin
                                            ds_load_start_pulse <= 1'b1;
                                        end
                                    end

                                    if (command_masked[CMD_START_DMA_STORE_BIT]) begin
                                        if (dma_store_busy || dma_load_busy) begin
                                            reject_status_q[REJ_DMA_STORE_BUSY_BIT] <= 1'b1;
                                        end
                                        else if (dma_store_byte_count_q == 32'h0000_0000) begin
                                            reject_status_q[REJ_ZERO_LENGTH_BIT] <= 1'b1;
                                        end
                                        else begin
                                            dma_store_start_pulse <= 1'b1;
                                        end
                                    end
                                    end
                                end
                            end
                        end

                        CSR_JOB_COMMAND_ADDR: begin
                            if (job_command_has_active_strobe) begin
                                if (job_command_unsupported_combo) begin
                                    job_reject_status_q[JOB_REJ_UNSUPPORTED_COMBO] <= 1'b1;
                                end
                                else begin
                                    if (job_command_masked[JOB_CMD_CLEAR_DONE_BIT]) begin
                                        job_done_status_q <= 32'h0000_0000;
                                        job_clear_done_pulse <= 1'b1;
                                    end

                                    if (job_command_masked[JOB_CMD_CLEAR_ERROR_BIT]) begin
                                        job_error_status_q  <= 32'h0000_0000;
                                        job_reject_status_q <= 32'h0000_0000;
                                        job_clear_error_pulse <= 1'b1;
                                    end

                                    if (job_command_masked[JOB_CMD_CLEAR_PERF_BIT]) begin
                                        job_perf_busy_cycles_q  <= 32'h0000_0000;
                                        job_perf_mac_count_q    <= 32'h0000_0000;
                                        job_perf_output_count_q <= 32'h0000_0000;
                                        job_clear_perf_pulse <= 1'b1;
                                    end

                                    if (job_command_masked[JOB_CMD_START_BIT]) begin
                                        if (desc_fetch_busy) begin
                                            // P17G: block manual P15 jobs while descriptor fetch is active.
                                            job_reject_status_q[JOB_REJ_MANUAL_CMD_BIT] <= 1'b1;
                                        end
                                        else if (recipe_busy) begin
                                            recipe_reject_status_q[RECIPE_REJ_MANUAL_CMD_BIT] <= 1'b1;
                                        end
                                        else if (job_busy) begin
                                            job_reject_status_q[JOB_REJ_BUSY_BIT] <= 1'b1;
                                        end
                                        else if (micro_op_busy) begin
                                            job_reject_status_q[JOB_REJ_MICRO_OP_BUSY_BIT] <= 1'b1;
                                        end
                                        else if (!job_output_mode_supported) begin
                                            job_reject_status_q[JOB_REJ_UNSUPPORTED_MODE] <= 1'b1;
                                        end
                                        else if ((job_dim_m_q == 32'h0000_0000) ||
                                                 (job_dim_n_q == 32'h0000_0000) ||
                                                 (job_dim_k_q == 32'h0000_0000)) begin
                                            job_reject_status_q[JOB_REJ_ZERO_DIM_BIT] <= 1'b1;
                                        end
                                        else if (job_preload_required &&
                                                 (job_a_load_beats_q == 32'h0000_0000)) begin
                                            job_reject_status_q[JOB_REJ_ZERO_A_LENGTH_BIT] <= 1'b1;
                                        end
                                        else if (job_preload_required &&
                                                 (job_b_load_beats_q == 32'h0000_0000)) begin
                                            job_reject_status_q[JOB_REJ_ZERO_B_LENGTH_BIT] <= 1'b1;
                                        end
                                        else if (job_store_required &&
                                                 (job_store_byte_count_q == 32'h0000_0000)) begin
                                            job_reject_status_q[JOB_REJ_ZERO_STORE_LEN_BIT] <= 1'b1;
                                        end
                                        else begin
                                            job_done_status_q   <= 32'h0000_0000;
                                            job_error_status_q  <= 32'h0000_0000;
                                            job_reject_status_q <= 32'h0000_0000;
                                            job_start_pulse     <= 1'b1;
                                        end
                                    end
                                end
                            end
                        end

                        CSR_RECIPE_COMMAND_ADDR: begin
                            if (recipe_command_has_active_strobe) begin
                                if (recipe_command_unsupported_combo) begin
                                    recipe_reject_status_q[RECIPE_REJ_UNSUPPORTED_COMBO] <= 1'b1;
                                end
                                else begin
                                    if (recipe_command_masked[RECIPE_CMD_CLEAR_DONE_BIT]) begin
                                        recipe_done_status_q <= 32'h0000_0000;
                                        recipe_slot_done_mask_q <= 32'h0000_0000;
                                        recipe_clear_done_pulse <= 1'b1;
                                    end

                                    if (recipe_command_masked[RECIPE_CMD_CLEAR_ERROR_BIT]) begin
                                        recipe_error_status_q  <= 32'h0000_0000;
                                        recipe_reject_status_q <= 32'h0000_0000;
                                        recipe_slot_error_mask_q  <= 32'h0000_0000;
                                        recipe_slot_reject_mask_q <= 32'h0000_0000;
                                        recipe_clear_error_pulse <= 1'b1;
                                    end

                                    if (recipe_command_masked[RECIPE_CMD_CLEAR_PERF_BIT]) begin
                                        recipe_perf_busy_cycles_q  <= 32'h0000_0000;
                                        recipe_perf_mac_count_q    <= 32'h0000_0000;
                                        recipe_perf_output_count_q <= 32'h0000_0000;
                                        recipe_clear_perf_pulse <= 1'b1;
                                    end

                                    if (recipe_command_masked[RECIPE_CMD_CLEAR_SLOT_STATUS_BIT]) begin
                                        recipe_slot_done_mask_q   <= 32'h0000_0000;
                                        recipe_slot_error_mask_q  <= 32'h0000_0000;
                                        recipe_slot_reject_mask_q <= 32'h0000_0000;
                                        recipe_clear_slot_status_pulse <= 1'b1;
                                    end

                                    if (recipe_command_masked[RECIPE_CMD_START_BIT]) begin
                                        if (desc_fetch_busy) begin
                                            // P17G: block manual P16 recipe starts while descriptor fetch
                                            // is building the fetched snapshot.
                                            recipe_reject_status_q[RECIPE_REJ_MANUAL_CMD_BIT] <= 1'b1;
                                        end
                                        else if (recipe_busy) begin
                                            recipe_reject_status_q[RECIPE_REJ_BUSY_BIT] <= 1'b1;
                                        end
                                        else if (job_busy) begin
                                            recipe_reject_status_q[RECIPE_REJ_JOB_BUSY_BIT] <= 1'b1;
                                        end
                                        else if (micro_op_busy) begin
                                            recipe_reject_status_q[RECIPE_REJ_MICRO_OP_BUSY_BIT] <= 1'b1;
                                        end
                                        else if (recipe_count_comb == 4'd0) begin
                                            recipe_reject_status_q[RECIPE_REJ_ZERO_COUNT_BIT] <= 1'b1;
                                        end
                                        else if (!recipe_range_valid) begin
                                            recipe_reject_status_q[RECIPE_REJ_SLOT_RANGE_BIT] <= 1'b1;
                                        end
                                        else if (!recipe_selected_slots_valid) begin
                                            recipe_reject_status_q[RECIPE_REJ_SLOT_INVALID_BIT] <= 1'b1;
                                        end
                                        else if (!recipe_selected_desc_valid) begin
                                            recipe_reject_status_q[RECIPE_REJ_SLOT_DESC_BIT] <= 1'b1;
                                        end
                                        else begin
                                            recipe_done_status_q      <= 32'h0000_0000;
                                            recipe_error_status_q     <= 32'h0000_0000;
                                            recipe_reject_status_q    <= 32'h0000_0000;
                                            recipe_slot_done_mask_q   <= 32'h0000_0000;
                                            recipe_slot_error_mask_q  <= 32'h0000_0000;
                                            recipe_slot_reject_mask_q <= 32'h0000_0000;
                                            recipe_start_pulse        <= 1'b1;
                                        end
                                    end
                                end
                            end
                        end

                        CSR_DESC_FETCH_COMMAND_ADDR: begin
                            if (desc_fetch_command_has_active_strobe) begin
                                if (desc_fetch_command_masked[DESC_FETCH_CMD_CLEAR_DONE_BIT]) begin
                                    desc_fetch_clear_done_pulse <= 1'b1;
                                end

                                if (desc_fetch_command_masked[DESC_FETCH_CMD_CLEAR_ERROR_BIT]) begin
                                    desc_fetch_clear_error_pulse <= 1'b1;
                                end

                                if (desc_fetch_command_has_start) begin
                                    desc_fetch_start_pulse <= 1'b1;
                                end
                            end
                        end

                        CSR_DESC_FETCH_DONE_STATUS_ADDR: begin
                            desc_fetch_clear_done_pulse <= 1'b1;
                        end

                        CSR_DESC_FETCH_ERROR_STATUS_ADDR: begin
                            desc_fetch_clear_error_pulse <= 1'b1;
                        end

                        CSR_DESC_FETCH_REJECT_STATUS_ADDR: begin
                            desc_fetch_clear_error_pulse <= 1'b1;
                        end

                        CSR_DESC_FETCH_BASE_ADDR_ADDR: begin
                            desc_fetch_base_addr_q <= apply_wstrb32(desc_fetch_base_addr_q, write_data, write_strb);
                        end

                        CSR_DESC_FETCH_COUNT_ADDR: begin
                            desc_fetch_count_q <= apply_wstrb32(desc_fetch_count_q, write_data, write_strb) &
                                                  DESC_FETCH_COUNT_MASK;
                        end

                        CSR_DESC_FETCH_STRIDE_BYTES_ADDR: begin
                            desc_fetch_stride_bytes_q <= apply_wstrb32(desc_fetch_stride_bytes_q, write_data, write_strb) &
                                                         DESC_FETCH_STRIDE_MASK;
                        end

                        CSR_COMPLETION_WB_COMMAND_ADDR: begin
                            if (completion_wb_command_has_active_strobe) begin
                                if (completion_wb_command_unsupported_combo) begin
                                    completion_wb_reject_status_q[COMP_WB_REJ_UNSUPPORTED_BIT] <= 1'b1;
                                end else begin
                                    if (completion_wb_command_masked[COMP_WB_CMD_CLEAR_DONE_BIT]) begin
                                        completion_wb_done_status_q <= 32'h0000_0000;
                                        completion_wb_clear_done_pulse <= 1'b1;
                                        completion_wb_clear_done_holdoff_q <= 1'b1;
                                    end

                                    if (completion_wb_command_masked[COMP_WB_CMD_CLEAR_ERROR_BIT]) begin
                                        completion_wb_error_status_q  <= 32'h0000_0000;
                                        completion_wb_reject_status_q <= 32'h0000_0000;
                                        completion_wb_clear_error_pulse <= 1'b1;
                                        completion_wb_clear_error_holdoff_q <= 1'b1;
                                    end

                                    if (completion_wb_command_has_start) begin
                                        completion_wb_start_pulse <= 1'b1;
                                    end
                                end
                            end
                        end

                        CSR_COMPLETION_WB_DONE_STATUS_ADDR: begin
                            completion_wb_done_status_q <= completion_wb_done_status_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                            if (|write_data) begin
                                completion_wb_clear_done_pulse <= 1'b1;
                                completion_wb_clear_done_holdoff_q <= 1'b1;
                            end
                        end

                        CSR_COMPLETION_WB_ERROR_STATUS_ADDR: begin
                            completion_wb_error_status_q <= completion_wb_error_status_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                            if (|write_data) begin
                                completion_wb_clear_error_pulse <= 1'b1;
                                completion_wb_clear_error_holdoff_q <= 1'b1;
                            end
                        end

                        CSR_COMPLETION_WB_REJECT_STATUS_ADDR: begin
                            completion_wb_reject_status_q <= completion_wb_reject_status_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                            if (|write_data) begin
                                completion_wb_clear_error_pulse <= 1'b1;
                                completion_wb_clear_error_holdoff_q <= 1'b1;
                            end
                        end

                        CSR_COMPLETION_WB_CONTROL_ADDR: begin
                            completion_wb_control_q <= apply_wstrb32(completion_wb_control_q, write_data, write_strb) &
                                                       COMP_WB_CONTROL_MASK;
                        end

                        CSR_COMPLETION_WB_BASE_ADDR_ADDR: begin
                            completion_wb_base_addr_q <= apply_wstrb32(completion_wb_base_addr_q, write_data, write_strb);
                        end

                        CSR_COMPLETION_WB_STATUS_FLAGS_ADDR: begin
                            completion_wb_status_flags_q <= apply_wstrb32(completion_wb_status_flags_q, write_data, write_strb);
                        end

                        CSR_COMPLETION_WB_USER_TAG_ADDR: begin
                            completion_wb_user_tag_q <= apply_wstrb32(completion_wb_user_tag_q, write_data, write_strb);
                        end

                        CSR_COMPLETION_WB_COUNTS_ADDR: begin
                            completion_wb_counts_q <= apply_wstrb32(completion_wb_counts_q, write_data, write_strb);
                        end

                        CSR_COMPLETION_WB_RECIPE_DONE_ADDR: begin
                            completion_wb_recipe_done_status_q <= apply_wstrb32(completion_wb_recipe_done_status_q, write_data, write_strb);
                        end

                        CSR_COMPLETION_WB_RECIPE_ERROR_ADDR: begin
                            completion_wb_recipe_error_status_q <= apply_wstrb32(completion_wb_recipe_error_status_q, write_data, write_strb);
                        end

                        CSR_COMPLETION_WB_RECIPE_REJECT_ADDR: begin
                            completion_wb_recipe_reject_status_q <= apply_wstrb32(completion_wb_recipe_reject_status_q, write_data, write_strb);
                        end

                        CSR_COMPLETION_WB_PERF_MAC_COUNT_ADDR: begin
                            completion_wb_perf_mac_count_q <= apply_wstrb32(completion_wb_perf_mac_count_q, write_data, write_strb);
                        end

                        CSR_COMPLETION_WB_ERROR_DETAIL_ADDR: begin
                            completion_wb_error_detail_q <= apply_wstrb32(completion_wb_error_detail_q, write_data, write_strb);
                        end


                        CSR_MEM_GUARD_COMMAND_ADDR: begin
                            if (mem_guard_command_has_active_strobe) begin
                                if (mem_guard_command_masked[MEM_GUARD_CMD_CLEAR_ERROR]) begin
                                    mem_guard_error_status_q     <= 32'h0000_0000;
                                    mem_guard_error_detail_q     <= 32'h0000_0000;
                                    mem_guard_error_addr_q       <= 32'h0000_0000;
                                    mem_guard_error_size_bytes_q <= 32'h0000_0000;
                                    mem_guard_error_domain_q     <= 32'h0000_0000;
                                end
                                if (mem_guard_command_masked[MEM_GUARD_CMD_CLEAR_REJECT]) begin
                                    mem_guard_reject_status_q <= 32'h0000_0000;
                                end
                                if (mem_guard_command_masked[MEM_GUARD_CMD_CLEAR_COUNTERS]) begin
                                    mem_guard_check_count_q           <= 32'h0000_0000;
                                    mem_guard_error_count_q           <= 32'h0000_0000;
                                    mem_guard_last_check_addr_q       <= 32'h0000_0000;
                                    mem_guard_last_check_size_bytes_q <= 32'h0000_0000;
                                    mem_guard_last_check_domain_q     <= 32'h0000_0000;
                                end
                            end
                        end

                        CSR_MEM_GUARD_ERROR_STATUS_ADDR: begin
                            mem_guard_error_status_q <= mem_guard_error_status_q &
                                                        ~(write_data & strobe_to_mask(write_strb) & MEM_GUARD_ALL_ERROR_MASK);
                        end

                        CSR_MEM_GUARD_REJECT_STATUS_ADDR: begin
                            mem_guard_reject_status_q <= mem_guard_reject_status_q &
                                                         ~(write_data & strobe_to_mask(write_strb) & MEM_GUARD_ALL_REJECT_MASK);
                        end

                        CSR_MEM_GUARD_CONTROL_ADDR: begin
                            if (queue_busy) begin
                                mem_guard_reject_status_q[MEM_GUARD_REJ_CONFIG_BUSY] <= 1'b1;
                            end else begin
                                mem_guard_control_q <= apply_wstrb32(mem_guard_control_q, write_data, write_strb) &
                                                       MEM_GUARD_CONTROL_WR_MASK;
                            end
                        end

                        CSR_MEM_GUARD_SQ_BASE_ADDR: begin
                            if (queue_busy) mem_guard_reject_status_q[MEM_GUARD_REJ_CONFIG_BUSY] <= 1'b1;
                            else mem_guard_sq_base_q <= apply_wstrb32(mem_guard_sq_base_q, write_data, write_strb);
                        end

                        CSR_MEM_GUARD_SQ_LIMIT_ADDR: begin
                            if (queue_busy) mem_guard_reject_status_q[MEM_GUARD_REJ_CONFIG_BUSY] <= 1'b1;
                            else mem_guard_sq_limit_q <= apply_wstrb32(mem_guard_sq_limit_q, write_data, write_strb);
                        end

                        CSR_MEM_GUARD_CQ_BASE_ADDR: begin
                            if (queue_busy) mem_guard_reject_status_q[MEM_GUARD_REJ_CONFIG_BUSY] <= 1'b1;
                            else mem_guard_cq_base_q <= apply_wstrb32(mem_guard_cq_base_q, write_data, write_strb);
                        end

                        CSR_MEM_GUARD_CQ_LIMIT_ADDR: begin
                            if (queue_busy) mem_guard_reject_status_q[MEM_GUARD_REJ_CONFIG_BUSY] <= 1'b1;
                            else mem_guard_cq_limit_q <= apply_wstrb32(mem_guard_cq_limit_q, write_data, write_strb);
                        end

                        CSR_MEM_GUARD_DESC_BASE_ADDR: begin
                            if (queue_busy) mem_guard_reject_status_q[MEM_GUARD_REJ_CONFIG_BUSY] <= 1'b1;
                            else mem_guard_desc_base_q <= apply_wstrb32(mem_guard_desc_base_q, write_data, write_strb);
                        end

                        CSR_MEM_GUARD_DESC_LIMIT_ADDR: begin
                            if (queue_busy) mem_guard_reject_status_q[MEM_GUARD_REJ_CONFIG_BUSY] <= 1'b1;
                            else mem_guard_desc_limit_q <= apply_wstrb32(mem_guard_desc_limit_q, write_data, write_strb);
                        end

                        CSR_MEM_GUARD_SRC_BASE_ADDR: begin
                            if (queue_busy) mem_guard_reject_status_q[MEM_GUARD_REJ_CONFIG_BUSY] <= 1'b1;
                            else mem_guard_src_base_q <= apply_wstrb32(mem_guard_src_base_q, write_data, write_strb);
                        end

                        CSR_MEM_GUARD_SRC_LIMIT_ADDR: begin
                            if (queue_busy) mem_guard_reject_status_q[MEM_GUARD_REJ_CONFIG_BUSY] <= 1'b1;
                            else mem_guard_src_limit_q <= apply_wstrb32(mem_guard_src_limit_q, write_data, write_strb);
                        end

                        CSR_MEM_GUARD_DST_BASE_ADDR: begin
                            if (queue_busy) mem_guard_reject_status_q[MEM_GUARD_REJ_CONFIG_BUSY] <= 1'b1;
                            else mem_guard_dst_base_q <= apply_wstrb32(mem_guard_dst_base_q, write_data, write_strb);
                        end

                        CSR_MEM_GUARD_DST_LIMIT_ADDR: begin
                            if (queue_busy) mem_guard_reject_status_q[MEM_GUARD_REJ_CONFIG_BUSY] <= 1'b1;
                            else mem_guard_dst_limit_q <= apply_wstrb32(mem_guard_dst_limit_q, write_data, write_strb);
                        end


                        CSR_QUEUE_COMMAND_ADDR: begin
                            if (queue_command_has_active_strobe) begin
                                if (queue_command_masked[QUEUE_CMD_CLEAR_DONE_BIT]) begin
                                    queue_clear_done_pulse <= 1'b1;
                                end

                                if (queue_command_masked[QUEUE_CMD_CLEAR_ERROR_BIT]) begin
                                    queue_clear_error_pulse <= 1'b1;
                                end

                                if (queue_command_has_start) begin
                                    queue_start_pulse <= 1'b1;
                                end

                                if (queue_command_masked[QUEUE_CMD_STOP_BIT]) begin
                                    queue_stop_pulse <= 1'b1;
                                end
                            end
                        end

                        CSR_QUEUE_DONE_STATUS_ADDR: begin
                            if (|write_data) begin
                                queue_clear_done_pulse <= 1'b1;
                            end
                        end

                        CSR_QUEUE_ERROR_STATUS_ADDR: begin
                            if (|write_data) begin
                                queue_clear_error_pulse <= 1'b1;
                            end
                        end

                        CSR_QUEUE_REJECT_STATUS_ADDR: begin
                            if (|write_data) begin
                                queue_clear_error_pulse <= 1'b1;
                            end
                        end

                        CSR_QUEUE_CONTROL_ADDR: begin
                            queue_control_q <= apply_wstrb32(queue_control_q, write_data, write_strb) &
                                               QUEUE_CONTROL_MASK;
                        end

                        CSR_QUEUE_SQ_BASE_ADDR: begin
                            queue_sq_base_addr_q <= apply_wstrb32(queue_sq_base_addr_q, write_data, write_strb);
                        end

                        CSR_QUEUE_SQ_DEPTH_ADDR: begin
                            queue_sq_depth_q <= apply_wstrb32(queue_sq_depth_q, write_data, write_strb);
                        end

                        CSR_QUEUE_SQ_HEAD_ADDR: begin
                            queue_sq_head_q <= apply_wstrb32(queue_sq_head_q, write_data, write_strb);
                        end

                        CSR_QUEUE_SQ_TAIL_ADDR: begin
                            queue_sq_tail_q <= apply_wstrb32(queue_sq_tail_q, write_data, write_strb);
                        end

                        CSR_QUEUE_SQ_STRIDE_ADDR: begin
                            queue_sq_stride_q <= apply_wstrb32(queue_sq_stride_q, write_data, write_strb);
                        end

                        CSR_QUEUE_CQ_BASE_ADDR: begin
                            queue_cq_base_addr_q <= apply_wstrb32(queue_cq_base_addr_q, write_data, write_strb);
                        end

                        CSR_QUEUE_CQ_DEPTH_ADDR: begin
                            queue_cq_depth_q <= apply_wstrb32(queue_cq_depth_q, write_data, write_strb);
                        end

                        CSR_QUEUE_CQ_HEAD_ADDR: begin
                            queue_cq_head_q <= apply_wstrb32(queue_cq_head_q, write_data, write_strb);
                        end

                        CSR_QUEUE_CQ_TAIL_ADDR: begin
                            queue_cq_tail_q <= apply_wstrb32(queue_cq_tail_q, write_data, write_strb);
                        end

                        CSR_QUEUE_CQ_STRIDE_ADDR: begin
                            queue_cq_stride_q <= apply_wstrb32(queue_cq_stride_q, write_data, write_strb);
                        end


                        CSR_EVENT_COMMAND_ADDR: begin
                            // W1P commands are handled by event_clear_* / event_force_test_cmd.
                        end

                        CSR_EVENT_PENDING_ADDR: begin
                            // W1C clear is handled by event_clear_mask.
                        end

                        CSR_EVENT_ENABLE_ADDR: begin
                            event_enable_q <= apply_wstrb32(event_enable_q, write_data, write_strb) &
                                              EVENT_VALID_MASK;
                        end

                        CSR_EVENT_CONTROL_ADDR: begin
                            event_control_q <= apply_wstrb32(event_control_q, write_data, write_strb) &
                                               EVENT_CONTROL_WR_MASK;
                        end

                        CSR_EVENT_CQ_THRESHOLD_ADDR: begin
                            event_cq_threshold_q <= apply_wstrb32(event_cq_threshold_q, write_data, write_strb);
                        end

                        CSR_EVENT_MOD_CONTROL_ADDR: begin
                            event_mod_control_q <= apply_wstrb32(event_mod_control_q, write_data, write_strb) &
                                                   EVENT_MOD_CONTROL_WR_MASK;
                        end

                        CSR_EVENT_MOD_TIMER_LIMIT_ADDR: begin
                            event_mod_timer_limit_q <= apply_wstrb32(event_mod_timer_limit_q, write_data, write_strb);
                        end

                        CSR_DONE_STATUS_ADDR: begin
                            done_status_q <= done_status_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                        end

                        CSR_ERROR_STATUS_ADDR: begin
                            error_status_q <= error_status_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                        end

                        CSR_MODE_ADDR: begin
                            mode_q <= apply_wstrb32(mode_q, write_data, write_strb) &
                                      32'h0000_0003;
                        end

                        CSR_CMD_REJECT_STATUS_ADDR: begin
                            reject_status_q <= reject_status_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                        end

                        CSR_BASE_ADDR_A_ADDR: begin
                            base_addr_a_q <= apply_wstrb32(base_addr_a_q, write_data, write_strb);
                        end

                        CSR_BASE_ADDR_B_ADDR: begin
                            base_addr_b_q <= apply_wstrb32(base_addr_b_q, write_data, write_strb);
                        end

                        CSR_BASE_ADDR_C_ADDR: begin
                            base_addr_c_q <= apply_wstrb32(base_addr_c_q, write_data, write_strb);
                        end

                        CSR_DIM_M_ADDR: begin
                            dim_m_q <= apply_wstrb32(dim_m_q, write_data, write_strb);
                        end

                        CSR_DIM_N_ADDR: begin
                            dim_n_q <= apply_wstrb32(dim_n_q, write_data, write_strb);
                        end

                        CSR_DIM_K_ADDR: begin
                            dim_k_q <= apply_wstrb32(dim_k_q, write_data, write_strb);
                        end

                        CSR_DMA_LOAD_SRC_BASE_ADDR: begin
                            dma_load_src_base_q <= apply_wstrb32(dma_load_src_base_q, write_data, write_strb);
                        end

                        CSR_DMA_LOAD_DST_BASE_ADDR: begin
                            dma_load_dst_base_q <= apply_wstrb32(dma_load_dst_base_q, write_data, write_strb);
                        end

                        CSR_DMA_LOAD_BEATS_ADDR: begin
                            dma_load_beats_q <= apply_wstrb32(dma_load_beats_q, write_data, write_strb);
                        end

                        CSR_AXIS_SRC_BASE_ADDR: begin
                            axis_src_base_q <= apply_wstrb32(axis_src_base_q, write_data, write_strb);
                        end

                        CSR_AXIS_DST_BASE_ADDR: begin
                            axis_dst_base_q <= apply_wstrb32(axis_dst_base_q, write_data, write_strb);
                        end

                        CSR_AXIS_LOAD_BEATS_ADDR: begin
                            axis_load_beats_q <= apply_wstrb32(axis_load_beats_q, write_data, write_strb);
                        end

                        CSR_DS_SRC_BASE_ADDR: begin
                            ds_src_base_q <= apply_wstrb32(ds_src_base_q, write_data, write_strb);
                        end

                        CSR_DS_DST_BASE_ADDR: begin
                            ds_dst_base_q <= apply_wstrb32(ds_dst_base_q, write_data, write_strb);
                        end

                        CSR_DS_LOAD_BEATS_ADDR: begin
                            ds_load_beats_q <= apply_wstrb32(ds_load_beats_q, write_data, write_strb);
                        end

                        CSR_DS_CONTROL_ADDR: begin
                            ds_control_q <= apply_wstrb32(ds_control_q, write_data, write_strb) &
                                            32'h0000_0001;
                        end

                        CSR_DMA_STORE_SRC_BASE_ADDR: begin
                            dma_store_src_base_q <= apply_wstrb32(dma_store_src_base_q, write_data, write_strb);
                        end

                        CSR_DMA_STORE_DST_BASE_ADDR: begin
                            dma_store_dst_base_q <= apply_wstrb32(dma_store_dst_base_q, write_data, write_strb);
                        end

                        CSR_DMA_STORE_BYTE_COUNT_ADDR: begin
                            dma_store_byte_count_q <= apply_wstrb32(dma_store_byte_count_q, write_data, write_strb);
                        end

                        CSR_RECIPE_DONE_STATUS_ADDR: begin
                            recipe_done_status_q <= recipe_done_status_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                        end

                        CSR_RECIPE_ERROR_STATUS_ADDR: begin
                            recipe_error_status_q <= recipe_error_status_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                        end

                        CSR_RECIPE_CONTROL_ADDR: begin
                            recipe_control_q <= apply_wstrb32(recipe_control_q, write_data, write_strb) &
                                                RECIPE_CONTROL_MASK;
                        end

                        CSR_RECIPE_REJECT_STATUS_ADDR: begin
                            recipe_reject_status_q <= recipe_reject_status_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                        end

                        CSR_RECIPE_SLOT_DONE_MASK_ADDR: begin
                            recipe_slot_done_mask_q <= recipe_slot_done_mask_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                        end

                        CSR_RECIPE_SLOT_ERROR_MASK_ADDR: begin
                            recipe_slot_error_mask_q <= recipe_slot_error_mask_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                        end

                        CSR_RECIPE_SLOT_REJECT_MASK_ADDR: begin
                            recipe_slot_reject_mask_q <= recipe_slot_reject_mask_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                        end

                        CSR_JOB_DONE_STATUS_ADDR: begin
                            job_done_status_q <= job_done_status_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                        end

                        CSR_JOB_ERROR_STATUS_ADDR: begin
                            job_error_status_q <= job_error_status_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                        end

                        CSR_JOB_MODE_ADDR: begin
                            job_mode_q <= apply_wstrb32(job_mode_q, write_data, write_strb) &
                                          JOB_MODE_MASK;
                        end

                        CSR_JOB_REJECT_STATUS_ADDR: begin
                            job_reject_status_q <= job_reject_status_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                        end

                        CSR_JOB_BASE_ADDR_A_ADDR: begin
                            job_base_addr_a_q <= apply_wstrb32(job_base_addr_a_q, write_data, write_strb);
                        end

                        CSR_JOB_BASE_ADDR_B_ADDR: begin
                            job_base_addr_b_q <= apply_wstrb32(job_base_addr_b_q, write_data, write_strb);
                        end

                        CSR_JOB_BASE_ADDR_C_ADDR: begin
                            job_base_addr_c_q <= apply_wstrb32(job_base_addr_c_q, write_data, write_strb);
                        end

                        CSR_JOB_DIM_M_ADDR: begin
                            job_dim_m_q <= apply_wstrb32(job_dim_m_q, write_data, write_strb);
                        end

                        CSR_JOB_DIM_N_ADDR: begin
                            job_dim_n_q <= apply_wstrb32(job_dim_n_q, write_data, write_strb);
                        end

                        CSR_JOB_DIM_K_ADDR: begin
                            job_dim_k_q <= apply_wstrb32(job_dim_k_q, write_data, write_strb);
                        end

                        CSR_JOB_A_SRC_BASE_ADDR: begin
                            job_a_src_base_q <= apply_wstrb32(job_a_src_base_q, write_data, write_strb);
                        end

                        CSR_JOB_A_DST_BASE_ADDR: begin
                            job_a_dst_base_q <= apply_wstrb32(job_a_dst_base_q, write_data, write_strb);
                        end

                        CSR_JOB_A_LOAD_BEATS_ADDR: begin
                            job_a_load_beats_q <= apply_wstrb32(job_a_load_beats_q, write_data, write_strb);
                        end

                        CSR_JOB_B_SRC_BASE_ADDR: begin
                            job_b_src_base_q <= apply_wstrb32(job_b_src_base_q, write_data, write_strb);
                        end

                        CSR_JOB_B_DST_BASE_ADDR: begin
                            job_b_dst_base_q <= apply_wstrb32(job_b_dst_base_q, write_data, write_strb);
                        end

                        CSR_JOB_B_LOAD_BEATS_ADDR: begin
                            job_b_load_beats_q <= apply_wstrb32(job_b_load_beats_q, write_data, write_strb);
                        end

                        CSR_JOB_STORE_SRC_BASE_ADDR: begin
                            job_store_src_base_q <= apply_wstrb32(job_store_src_base_q, write_data, write_strb);
                        end

                        CSR_JOB_STORE_DST_BASE_ADDR: begin
                            job_store_dst_base_q <= apply_wstrb32(job_store_dst_base_q, write_data, write_strb);
                        end

                        CSR_JOB_STORE_BYTE_COUNT_ADDR: begin
                            job_store_byte_count_q <= apply_wstrb32(job_store_byte_count_q, write_data, write_strb);
                        end

                        default: begin
                            if (recipe_slot_addr_is_valid(write_addr)) begin
                                int unsigned slot_idx;
                                logic [6:0]  slot_offset;

                                slot_idx    = recipe_slot_index(write_addr);
                                slot_offset = recipe_slot_offset(write_addr);

                                if (slot_idx < P16_RECIPE_QUEUE_DEPTH) begin
                                    unique case (slot_offset)
                                        SLOT_CONTROL_OFFSET: begin
                                            recipe_slot_control_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_control_q[slot_idx], write_data, write_strb) &
                                                RECIPE_SLOT_CONTROL_MASK;
                                        end

                                        SLOT_BASE_ADDR_A_OFFSET: begin
                                            recipe_slot_base_addr_a_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_base_addr_a_q[slot_idx], write_data, write_strb);
                                        end

                                        SLOT_BASE_ADDR_B_OFFSET: begin
                                            recipe_slot_base_addr_b_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_base_addr_b_q[slot_idx], write_data, write_strb);
                                        end

                                        SLOT_BASE_ADDR_C_OFFSET: begin
                                            recipe_slot_base_addr_c_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_base_addr_c_q[slot_idx], write_data, write_strb);
                                        end

                                        SLOT_DIM_M_OFFSET: begin
                                            recipe_slot_dim_m_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_dim_m_q[slot_idx], write_data, write_strb);
                                        end

                                        SLOT_DIM_N_OFFSET: begin
                                            recipe_slot_dim_n_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_dim_n_q[slot_idx], write_data, write_strb);
                                        end

                                        SLOT_DIM_K_OFFSET: begin
                                            recipe_slot_dim_k_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_dim_k_q[slot_idx], write_data, write_strb);
                                        end

                                        SLOT_A_SRC_BASE_OFFSET: begin
                                            recipe_slot_a_src_base_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_a_src_base_q[slot_idx], write_data, write_strb);
                                        end

                                        SLOT_A_DST_BASE_OFFSET: begin
                                            recipe_slot_a_dst_base_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_a_dst_base_q[slot_idx], write_data, write_strb);
                                        end

                                        SLOT_A_LOAD_BEATS_OFFSET: begin
                                            recipe_slot_a_load_beats_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_a_load_beats_q[slot_idx], write_data, write_strb);
                                        end

                                        SLOT_B_SRC_BASE_OFFSET: begin
                                            recipe_slot_b_src_base_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_b_src_base_q[slot_idx], write_data, write_strb);
                                        end

                                        SLOT_B_DST_BASE_OFFSET: begin
                                            recipe_slot_b_dst_base_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_b_dst_base_q[slot_idx], write_data, write_strb);
                                        end

                                        SLOT_B_LOAD_BEATS_OFFSET: begin
                                            recipe_slot_b_load_beats_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_b_load_beats_q[slot_idx], write_data, write_strb);
                                        end

                                        SLOT_STORE_SRC_BASE_OFFSET: begin
                                            recipe_slot_store_src_base_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_store_src_base_q[slot_idx], write_data, write_strb);
                                        end

                                        SLOT_STORE_DST_BASE_OFFSET: begin
                                            recipe_slot_store_dst_base_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_store_dst_base_q[slot_idx], write_data, write_strb);
                                        end

                                        SLOT_STORE_BYTE_COUNT_OFFSET: begin
                                            recipe_slot_store_byte_count_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_store_byte_count_q[slot_idx], write_data, write_strb);
                                        end

                                        SLOT_USER_TAG_OFFSET: begin
                                            recipe_slot_user_tag_q[slot_idx] <= apply_wstrb32(
                                                recipe_slot_user_tag_q[slot_idx], write_data, write_strb);
                                        end

                                        default: begin
                                            // Reserved slot registers ignore valid writes.
                                        end
                                    endcase
                                end
                            end
                            else begin
                                // RO and reserved registers ignore valid writes.
                            end
                        end
                    endcase
                end
            end

            if (r_fire) begin
                rvalid_q <= 1'b0;
            end

            if (ar_fire) begin
                rvalid_q <= 1'b1;
                rresp_q  <= read_addr_valid ? AXI_RESP_OKAY : AXI_RESP_SLVERR;
                rdata_q  <= read_addr_valid ? read_data_comb : 32'h0000_0000;
            end
        end
    end

    // ------------------------------------------------------------
    // Sideband output mapping
    // ------------------------------------------------------------
    assign gemm_input_stream_mode = mode_q[0];
    assign accumulate_enable      = mode_q[1];

    assign base_addr_a = base_addr_a_q[ADDR_WIDTH-1:0];
    assign base_addr_b = base_addr_b_q[ADDR_WIDTH-1:0];
    assign base_addr_c = base_addr_c_q[ADDR_WIDTH-1:0];

    assign dim_m = dim_m_q[GEMM_DIM_WIDTH-1:0];
    assign dim_n = dim_n_q[GEMM_DIM_WIDTH-1:0];
    assign dim_k = dim_k_q[GEMM_DIM_WIDTH-1:0];

    assign dma_src_base_addr = dma_load_src_base_q[ADDR_WIDTH-1:0];
    assign dma_dst_base_addr = dma_load_dst_base_q[ADDR_WIDTH-1:0];
    assign dma_load_beats    = dma_load_beats_q;

    assign axis_src_base_addr = axis_src_base_q[ADDR_WIDTH-1:0];
    assign axis_dst_base_addr = axis_dst_base_q[ADDR_WIDTH-1:0];
    assign axis_load_beats    = axis_load_beats_q;

    assign ds_src_base_addr = ds_src_base_q[ADDR_WIDTH-1:0];
    assign ds_dst_base_addr = ds_dst_base_q[ADDR_WIDTH-1:0];
    assign ds_load_beats    = ds_load_beats_q;
    assign ds_operand_sel   = ds_control_q[0];

    assign dma_store_src_base_addr = dma_store_src_base_q[ADDR_WIDTH-1:0];
    assign dma_store_dst_base_addr = dma_store_dst_base_q[ADDR_WIDTH-1:0];
    assign dma_store_byte_count    = dma_store_byte_count_q;

    assign job_input_mode                = job_mode_q[1:0];
    assign job_output_mode               = job_mode_q[3:2];
    assign job_accumulate_enable         = job_mode_q[4];
    assign job_clear_p14_sticky_on_start = job_mode_q[5];

    assign job_base_addr_a = job_base_addr_a_q[ADDR_WIDTH-1:0];
    assign job_base_addr_b = job_base_addr_b_q[ADDR_WIDTH-1:0];
    assign job_base_addr_c = job_base_addr_c_q[ADDR_WIDTH-1:0];

    assign job_dim_m = job_dim_m_q[GEMM_DIM_WIDTH-1:0];
    assign job_dim_n = job_dim_n_q[GEMM_DIM_WIDTH-1:0];
    assign job_dim_k = job_dim_k_q[GEMM_DIM_WIDTH-1:0];

    assign job_a_src_base_addr = job_a_src_base_q[ADDR_WIDTH-1:0];
    assign job_a_dst_base_addr = job_a_dst_base_q[ADDR_WIDTH-1:0];
    assign job_a_load_beats    = job_a_load_beats_q;

    assign job_b_src_base_addr = job_b_src_base_q[ADDR_WIDTH-1:0];
    assign job_b_dst_base_addr = job_b_dst_base_q[ADDR_WIDTH-1:0];
    assign job_b_load_beats    = job_b_load_beats_q;

    assign job_store_src_base_addr = job_store_src_base_q[ADDR_WIDTH-1:0];
    assign job_store_dst_base_addr = job_store_dst_base_q[ADDR_WIDTH-1:0];
    assign job_store_byte_count    = job_store_byte_count_q;

    assign recipe_count                      = recipe_control_q[3:0];
    assign recipe_start_slot                 = recipe_control_q[7:4];
    assign recipe_stop_on_error              = recipe_control_q[8];
    assign recipe_clear_job_sticky_each_slot = recipe_control_q[9];
    assign recipe_accumulate_perf            = recipe_control_q[10];
    assign recipe_allow_slot_writes_while_busy = recipe_control_q[11];

    generate
        for (genvar slot_g = 0; slot_g < P16_RECIPE_QUEUE_DEPTH; slot_g++) begin : g_recipe_slot_outputs
            assign recipe_slot_control[slot_g]             = recipe_slot_control_q[slot_g];
            assign recipe_slot_base_addr_a[slot_g]         = recipe_slot_base_addr_a_q[slot_g][ADDR_WIDTH-1:0];
            assign recipe_slot_base_addr_b[slot_g]         = recipe_slot_base_addr_b_q[slot_g][ADDR_WIDTH-1:0];
            assign recipe_slot_base_addr_c[slot_g]         = recipe_slot_base_addr_c_q[slot_g][ADDR_WIDTH-1:0];
            assign recipe_slot_dim_m[slot_g]               = recipe_slot_dim_m_q[slot_g][GEMM_DIM_WIDTH-1:0];
            assign recipe_slot_dim_n[slot_g]               = recipe_slot_dim_n_q[slot_g][GEMM_DIM_WIDTH-1:0];
            assign recipe_slot_dim_k[slot_g]               = recipe_slot_dim_k_q[slot_g][GEMM_DIM_WIDTH-1:0];
            assign recipe_slot_a_src_base_addr[slot_g]     = recipe_slot_a_src_base_q[slot_g][ADDR_WIDTH-1:0];
            assign recipe_slot_a_dst_base_addr[slot_g]     = recipe_slot_a_dst_base_q[slot_g][ADDR_WIDTH-1:0];
            assign recipe_slot_a_load_beats[slot_g]        = recipe_slot_a_load_beats_q[slot_g];
            assign recipe_slot_b_src_base_addr[slot_g]     = recipe_slot_b_src_base_q[slot_g][ADDR_WIDTH-1:0];
            assign recipe_slot_b_dst_base_addr[slot_g]     = recipe_slot_b_dst_base_q[slot_g][ADDR_WIDTH-1:0];
            assign recipe_slot_b_load_beats[slot_g]        = recipe_slot_b_load_beats_q[slot_g];
            assign recipe_slot_store_src_base_addr[slot_g] = recipe_slot_store_src_base_q[slot_g][ADDR_WIDTH-1:0];
            assign recipe_slot_store_dst_base_addr[slot_g] = recipe_slot_store_dst_base_q[slot_g][ADDR_WIDTH-1:0];
            assign recipe_slot_store_byte_count[slot_g]    = recipe_slot_store_byte_count_q[slot_g];
            assign recipe_slot_user_tag[slot_g]            = recipe_slot_user_tag_q[slot_g];
        end
    endgenerate

    assign desc_fetch_base_addr    = desc_fetch_base_addr_q[ADDR_WIDTH-1:0];
    assign desc_fetch_count        = desc_fetch_count_q[3:0];
    assign desc_fetch_stride_bytes = desc_fetch_stride_bytes_q[15:0];


    assign queue_enable          = queue_control_q[QUEUE_CONTROL_ENABLE_BIT];
    assign queue_run_until_empty = queue_control_q[QUEUE_CONTROL_RUN_UNTIL_EMPTY_BIT];
    assign queue_stop_on_error   = queue_control_q[QUEUE_CONTROL_STOP_ON_ERROR_BIT];

    assign queue_sq_base_addr = queue_sq_base_addr_q[ADDR_WIDTH-1:0];
    assign queue_sq_depth     = queue_sq_depth_q;
    assign queue_sq_head      = queue_sq_head_q;
    assign queue_sq_tail      = queue_sq_tail_q;
    assign queue_sq_stride    = queue_sq_stride_q;

    assign queue_cq_base_addr = queue_cq_base_addr_q[ADDR_WIDTH-1:0];
    assign queue_cq_depth     = queue_cq_depth_q;
    assign queue_cq_head      = queue_cq_head_q;
    assign queue_cq_tail      = queue_cq_tail_q;
    assign queue_cq_stride    = queue_cq_stride_q;

    assign mem_guard_control          = mem_guard_control_q & MEM_GUARD_CONTROL_WR_MASK;
    assign mem_guard_sq_base          = mem_guard_sq_base_q[ADDR_WIDTH-1:0];
    assign mem_guard_sq_limit         = mem_guard_sq_limit_q[ADDR_WIDTH-1:0];
    assign mem_guard_cq_base          = mem_guard_cq_base_q[ADDR_WIDTH-1:0];
    assign mem_guard_cq_limit         = mem_guard_cq_limit_q[ADDR_WIDTH-1:0];
    assign mem_guard_desc_base        = mem_guard_desc_base_q[ADDR_WIDTH-1:0];
    assign mem_guard_desc_limit       = mem_guard_desc_limit_q[ADDR_WIDTH-1:0];
    assign mem_guard_src_base         = mem_guard_src_base_q[ADDR_WIDTH-1:0];
    assign mem_guard_src_limit        = mem_guard_src_limit_q[ADDR_WIDTH-1:0];
    assign mem_guard_dst_base         = mem_guard_dst_base_q[ADDR_WIDTH-1:0];
    assign mem_guard_dst_limit        = mem_guard_dst_limit_q[ADDR_WIDTH-1:0];

    assign completion_wb_enable         = completion_wb_control_q[0];
    assign completion_wb_overall_done   = completion_wb_control_q[1];
    assign completion_wb_overall_error  = completion_wb_control_q[2];
    assign completion_wb_overall_reject = completion_wb_control_q[3];
    assign completion_wb_base_addr      = completion_wb_base_addr_q[ADDR_WIDTH-1:0];
    assign completion_wb_status_flags   = completion_wb_status_flags_q;
    assign completion_wb_user_tag       = completion_wb_user_tag_q;
    assign completion_wb_programmed_count = completion_wb_counts_q[7:0];
    assign completion_wb_fetched_count    = completion_wb_counts_q[15:8];
    assign completion_wb_completed_count  = completion_wb_counts_q[23:16];
    assign completion_wb_recipe_done_status   = completion_wb_recipe_done_status_q;
    assign completion_wb_recipe_error_status  = completion_wb_recipe_error_status_q;
    assign completion_wb_recipe_reject_status = completion_wb_recipe_reject_status_q;
    assign completion_wb_perf_mac_count       = completion_wb_perf_mac_count_q;
    assign completion_wb_error_detail         = completion_wb_error_detail_q;

endmodule

`endif
