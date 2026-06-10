// File: rtl/top/ai_accel_subsys_csr_top.sv

`ifndef AI_ACCEL_SUBSYS_CSR_TOP_SV
`define AI_ACCEL_SUBSYS_CSR_TOP_SV

module ai_accel_subsys_csr_top #(
    parameter int ADDR_WIDTH      = 32,
    parameter int DATA_WIDTH      = 64,
    parameter int ID_WIDTH        = 4,
    parameter int DEPTH_WORDS     = 1024,

    parameter int GEMM_A_WIDTH    = 8,
    parameter int GEMM_B_WIDTH    = 8,
    parameter int GEMM_ACC_WIDTH  = 32,
    parameter int GEMM_DIM_WIDTH  = 8,

    parameter int APPLY_BEAT_IDX_W  = 8,
    parameter int COMMIT_BEAT_IDX_W = 8,

    parameter int GEMM_MAC_LANES    = 1,

    parameter bit GEMM_ENABLE_B_CACHE = 1'b0,
    parameter int GEMM_B_CACHE_MAX_K  = 4,
    parameter int GEMM_B_CACHE_MAX_N  = 4,

    // Optional GEMM datapath features.
    // All feature parameters remain default-off unless a run script
    // explicitly enables them. This preserves the scalar baseline.
    parameter bit GEMM_ENABLE_PACKED_BCACHE_PRELOAD = 1'b0,
    parameter bit GEMM_ENABLE_A_ROW_CACHE           = 1'b0,
    parameter int GEMM_A_ROW_CACHE_MAX_K            = 4,
    parameter bit GEMM_ENABLE_PACKED_A_ROW_PRELOAD  = 1'b0,

    parameter bit GEMM_ENABLE_K_TILING = 1'b0,
    parameter int GEMM_K_TILE_SIZE     = 8,
    parameter bit GEMM_ENABLE_N_TILING = 1'b0,
    parameter int GEMM_N_TILE_SIZE     = 8,
    parameter bit GEMM_ENABLE_M_TILING = 1'b0,
    parameter int GEMM_M_TILE_SIZE     = 2,

    parameter bit GEMM_ENABLE_C_RMW_ACCUM = 1'b0,

    parameter int CSR_ADDR_WIDTH = 12,
    parameter int CSR_DATA_WIDTH = 32,
    parameter logic [31:0] CSR_VERSION_VALUE        = 32'h0001_0014,
    parameter logic [31:0] CSR_JOB_VERSION_VALUE        = 32'h0001_0015,
    parameter logic [31:0] CSR_RECIPE_VERSION_VALUE     = 32'h0001_0016,
    parameter logic [31:0] CSR_DESC_FETCH_VERSION_VALUE = 32'h0001_0017,
    parameter int          P16_RECIPE_QUEUE_DEPTH       = 4
)(
    // ------------------------------------------------------------
    // Clocks / resets
    // ------------------------------------------------------------
    input  logic dma_clk,
    input  logic dma_rst_n,
    input  logic core_clk,
    input  logic core_rst_n,

    // ------------------------------------------------------------
    // Host-visible control/status register port
    // ------------------------------------------------------------
    axi_lite_if.slave csr_if,

    // ------------------------------------------------------------
    // External AXI-MM scratchpad host port
    //
    // Host software or the UVM environment may still use this port
    // to preload/readback scratchpad contents. Operation launch and
    // configuration are driven through the CSR port in this wrapper.
    // ------------------------------------------------------------
    axi_mm_if axi0_if,

    // ------------------------------------------------------------
    // DMA source AXI-MM read master port
    // ------------------------------------------------------------
    output logic [ID_WIDTH-1:0]       dma_src_axi_arid,
    output logic [ADDR_WIDTH-1:0]     dma_src_axi_araddr,
    output logic [7:0]                dma_src_axi_arlen,
    output logic [2:0]                dma_src_axi_arsize,
    output logic [1:0]                dma_src_axi_arburst,
    output logic                      dma_src_axi_arvalid,
    input  logic                      dma_src_axi_arready,

    input  logic [ID_WIDTH-1:0]       dma_src_axi_rid,
    input  logic [DATA_WIDTH-1:0]     dma_src_axi_rdata,
    input  logic [1:0]                dma_src_axi_rresp,
    input  logic                      dma_src_axi_rlast,
    input  logic                      dma_src_axi_rvalid,
    output logic                      dma_src_axi_rready,

    // ------------------------------------------------------------
    // AXI-Stream preload source AXI-MM read master port
    // ------------------------------------------------------------
    output logic [ID_WIDTH-1:0]       axis_src_axi_arid,
    output logic [ADDR_WIDTH-1:0]     axis_src_axi_araddr,
    output logic [7:0]                axis_src_axi_arlen,
    output logic [2:0]                axis_src_axi_arsize,
    output logic [1:0]                axis_src_axi_arburst,
    output logic                      axis_src_axi_arvalid,
    input  logic                      axis_src_axi_arready,

    input  logic [ID_WIDTH-1:0]       axis_src_axi_rid,
    input  logic [DATA_WIDTH-1:0]     axis_src_axi_rdata,
    input  logic [1:0]                axis_src_axi_rresp,
    input  logic                      axis_src_axi_rlast,
    input  logic                      axis_src_axi_rvalid,
    output logic                      axis_src_axi_rready,

    // ------------------------------------------------------------
    // Direct Stream preload source AXI-MM read master port
    // ------------------------------------------------------------
    output logic [ID_WIDTH-1:0]       ds_src_axi_arid,
    output logic [ADDR_WIDTH-1:0]     ds_src_axi_araddr,
    output logic [7:0]                ds_src_axi_arlen,
    output logic [2:0]                ds_src_axi_arsize,
    output logic [1:0]                ds_src_axi_arburst,
    output logic                      ds_src_axi_arvalid,
    input  logic                      ds_src_axi_arready,

    input  logic [ID_WIDTH-1:0]       ds_src_axi_rid,
    input  logic [DATA_WIDTH-1:0]     ds_src_axi_rdata,
    input  logic [1:0]                ds_src_axi_rresp,
    input  logic                      ds_src_axi_rlast,
    input  logic                      ds_src_axi_rvalid,
    output logic                      ds_src_axi_rready,

    // ------------------------------------------------------------
    // P17 descriptor source AXI-MM read master port
    // ------------------------------------------------------------
    output logic [ID_WIDTH-1:0]       desc_src_axi_arid,
    output logic [ADDR_WIDTH-1:0]     desc_src_axi_araddr,
    output logic [7:0]                desc_src_axi_arlen,
    output logic [2:0]                desc_src_axi_arsize,
    output logic [1:0]                desc_src_axi_arburst,
    output logic                      desc_src_axi_arvalid,
    input  logic                      desc_src_axi_arready,

    input  logic [ID_WIDTH-1:0]       desc_src_axi_rid,
    input  logic [DATA_WIDTH-1:0]     desc_src_axi_rdata,
    input  logic [1:0]                desc_src_axi_rresp,
    input  logic                      desc_src_axi_rlast,
    input  logic                      desc_src_axi_rvalid,
    output logic                      desc_src_axi_rready,

    // ------------------------------------------------------------
    // DMA destination AXI-MM write master port
    // ------------------------------------------------------------
    output logic [ID_WIDTH-1:0]       dma_dst_axi_awid,
    output logic [ADDR_WIDTH-1:0]     dma_dst_axi_awaddr,
    output logic [7:0]                dma_dst_axi_awlen,
    output logic [2:0]                dma_dst_axi_awsize,
    output logic [1:0]                dma_dst_axi_awburst,
    output logic                      dma_dst_axi_awvalid,
    input  logic                      dma_dst_axi_awready,

    output logic [DATA_WIDTH-1:0]     dma_dst_axi_wdata,
    output logic [DATA_WIDTH/8-1:0]   dma_dst_axi_wstrb,
    output logic                      dma_dst_axi_wlast,
    output logic                      dma_dst_axi_wvalid,
    input  logic                      dma_dst_axi_wready,

    input  logic [ID_WIDTH-1:0]       dma_dst_axi_bid,
    input  logic [1:0]                dma_dst_axi_bresp,
    input  logic                      dma_dst_axi_bvalid,
    output logic                      dma_dst_axi_bready,

    // ------------------------------------------------------------
    // Optional live status outputs for testbench observation
    //
    // Software-visible status is available through CSR reads. These
    // sideband outputs are retained only for waveform/debug and for
    // simple UVM observation while CSR tests are being added.
    // ------------------------------------------------------------
    output logic                      dma_load_busy,
    output logic                      dma_load_done,
    output logic                      dma_load_error,

    output logic                      axis_load_busy,
    output logic                      axis_load_done,
    output logic                      axis_load_error,

    output logic                      ds_load_busy,
    output logic                      ds_load_done,
    output logic                      ds_load_error,

    output logic                      dma_store_busy,
    output logic                      dma_store_done,
    output logic                      dma_store_error,

    output logic                      acc_busy,
    output logic                      acc_done,

    output logic [31:0]               gemm_perf_busy_cycles,
    output logic [31:0]               gemm_perf_mac_count,
    output logic [31:0]               gemm_perf_output_count
);

    // ============================================================
    // CSR-generated control/config wires
    // ============================================================
    logic                      csr_acc_start_pulse;
    logic                      csr_gemm_input_stream_mode;
    logic                      csr_accumulate_enable;

    logic [ADDR_WIDTH-1:0]     csr_base_addr_a;
    logic [ADDR_WIDTH-1:0]     csr_base_addr_b;
    logic [ADDR_WIDTH-1:0]     csr_base_addr_c;

    logic [GEMM_DIM_WIDTH-1:0] csr_dim_m;
    logic [GEMM_DIM_WIDTH-1:0] csr_dim_n;
    logic [GEMM_DIM_WIDTH-1:0] csr_dim_k;

    logic                      csr_dma_load_start_pulse;
    logic [ADDR_WIDTH-1:0]     csr_dma_src_base_addr;
    logic [ADDR_WIDTH-1:0]     csr_dma_dst_base_addr;
    logic [31:0]               csr_dma_load_beats;

    logic                      csr_axis_load_start_pulse;
    logic [ADDR_WIDTH-1:0]     csr_axis_src_base_addr;
    logic [ADDR_WIDTH-1:0]     csr_axis_dst_base_addr;
    logic [31:0]               csr_axis_load_beats;

    logic                      csr_ds_load_start_pulse;
    logic [ADDR_WIDTH-1:0]     csr_ds_src_base_addr;
    logic [ADDR_WIDTH-1:0]     csr_ds_dst_base_addr;
    logic [31:0]               csr_ds_load_beats;
    logic                      csr_ds_operand_sel;

    logic                      csr_dma_store_start_pulse;
    logic [ADDR_WIDTH-1:0]     csr_dma_store_src_base_addr;
    logic [ADDR_WIDTH-1:0]     csr_dma_store_dst_base_addr;
    logic [31:0]               csr_dma_store_byte_count;

    // ============================================================
    // P15 CSR job descriptor wires
    //
    // The CSR block stores a single software-visible job descriptor.
    // P15C connects these descriptor wires to ai_accel_job_sequencer,
    // which snapshots them on START_JOB and drives the existing
    // ai_accel_subsys sideband controls for the active job.
    // ============================================================
    logic                      csr_job_start_pulse;
    logic                      csr_job_clear_done_pulse;
    logic                      csr_job_clear_error_pulse;
    logic                      csr_job_clear_perf_pulse;

    logic [1:0]                csr_job_input_mode;
    logic [1:0]                csr_job_output_mode;
    logic                      csr_job_accumulate_enable;
    logic                      csr_job_clear_p14_sticky_on_start;

    logic [ADDR_WIDTH-1:0]     csr_job_base_addr_a;
    logic [ADDR_WIDTH-1:0]     csr_job_base_addr_b;
    logic [ADDR_WIDTH-1:0]     csr_job_base_addr_c;

    logic [GEMM_DIM_WIDTH-1:0] csr_job_dim_m;
    logic [GEMM_DIM_WIDTH-1:0] csr_job_dim_n;
    logic [GEMM_DIM_WIDTH-1:0] csr_job_dim_k;

    logic [ADDR_WIDTH-1:0]     csr_job_a_src_base_addr;
    logic [ADDR_WIDTH-1:0]     csr_job_a_dst_base_addr;
    logic [31:0]               csr_job_a_load_beats;

    logic [ADDR_WIDTH-1:0]     csr_job_b_src_base_addr;
    logic [ADDR_WIDTH-1:0]     csr_job_b_dst_base_addr;
    logic [31:0]               csr_job_b_load_beats;

    logic [ADDR_WIDTH-1:0]     csr_job_store_src_base_addr;
    logic [ADDR_WIDTH-1:0]     csr_job_store_dst_base_addr;
    logic [31:0]               csr_job_store_byte_count;

    // ============================================================
    // P15 job sequencer outputs and status
    // ============================================================
    logic                      job_acc_start_pulse;
    logic                      job_gemm_input_stream_mode;
    logic                      job_accumulate_enable_to_subsys;

    logic [ADDR_WIDTH-1:0]     job_base_addr_a_to_subsys;
    logic [ADDR_WIDTH-1:0]     job_base_addr_b_to_subsys;
    logic [ADDR_WIDTH-1:0]     job_base_addr_c_to_subsys;

    logic [GEMM_DIM_WIDTH-1:0] job_dim_m_to_subsys;
    logic [GEMM_DIM_WIDTH-1:0] job_dim_n_to_subsys;
    logic [GEMM_DIM_WIDTH-1:0] job_dim_k_to_subsys;

    logic                      job_dma_load_start_pulse;
    logic [ADDR_WIDTH-1:0]     job_dma_src_base_addr;
    logic [ADDR_WIDTH-1:0]     job_dma_dst_base_addr;
    logic [31:0]               job_dma_load_beats;

    logic                      job_axis_load_start_pulse;
    logic [ADDR_WIDTH-1:0]     job_axis_src_base_addr;
    logic [ADDR_WIDTH-1:0]     job_axis_dst_base_addr;
    logic [31:0]               job_axis_load_beats;

    logic                      job_ds_load_start_pulse;
    logic [ADDR_WIDTH-1:0]     job_ds_src_base_addr;
    logic [ADDR_WIDTH-1:0]     job_ds_dst_base_addr;
    logic [31:0]               job_ds_load_beats;
    logic                      job_ds_operand_sel;

    logic                      job_dma_store_start_pulse;
    logic [ADDR_WIDTH-1:0]     job_dma_store_src_base_addr;
    logic [ADDR_WIDTH-1:0]     job_dma_store_dst_base_addr;
    logic [31:0]               job_dma_store_byte_count;

    logic                      job_busy_i;
    logic                      job_done_i;
    logic                      job_gemm_done_i;
    logic                      job_store_done_i;

    logic                      job_dma_load_error_i;
    logic                      job_axis_load_error_i;
    logic                      job_ds_load_error_i;
    logic                      job_dma_store_error_i;
    logic                      job_sequence_error_i;

    logic [31:0]               job_state_i;
    logic [31:0]               job_perf_busy_cycles_i;
    logic [31:0]               job_perf_mac_count_i;
    logic [31:0]               job_perf_output_count_i;

    // ============================================================
    // P16 CSR recipe descriptor wires
    //
    // P16 recipe control window and descriptor slots.
    // P16C connects these wires to ai_accel_recipe_sequencer,
    // which dispatches one slot at a time through the P15 worker.
    // ============================================================
    logic                      csr_recipe_start_pulse;
    logic                      csr_recipe_clear_done_pulse;
    logic                      csr_recipe_clear_error_pulse;
    logic                      csr_recipe_clear_perf_pulse;
    logic                      csr_recipe_clear_slot_status_pulse;

    logic [3:0]                csr_recipe_count;
    logic [3:0]                csr_recipe_start_slot;
    logic                      csr_recipe_stop_on_error;
    logic                      csr_recipe_clear_job_sticky_each_slot;
    logic                      csr_recipe_accumulate_perf;
    logic                      csr_recipe_allow_slot_writes_while_busy;

    logic [31:0]               csr_recipe_slot_control [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     csr_recipe_slot_base_addr_a [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     csr_recipe_slot_base_addr_b [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     csr_recipe_slot_base_addr_c [P16_RECIPE_QUEUE_DEPTH];
    logic [GEMM_DIM_WIDTH-1:0] csr_recipe_slot_dim_m [P16_RECIPE_QUEUE_DEPTH];
    logic [GEMM_DIM_WIDTH-1:0] csr_recipe_slot_dim_n [P16_RECIPE_QUEUE_DEPTH];
    logic [GEMM_DIM_WIDTH-1:0] csr_recipe_slot_dim_k [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     csr_recipe_slot_a_src_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     csr_recipe_slot_a_dst_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0]               csr_recipe_slot_a_load_beats [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     csr_recipe_slot_b_src_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     csr_recipe_slot_b_dst_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0]               csr_recipe_slot_b_load_beats [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     csr_recipe_slot_store_src_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     csr_recipe_slot_store_dst_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0]               csr_recipe_slot_store_byte_count [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0]               csr_recipe_slot_user_tag [P16_RECIPE_QUEUE_DEPTH];

    // ============================================================
    // P17 descriptor fetch control/status and fetched snapshot
    //
    // P17C connects the fetch engine to CSR and descriptor memory.
    // The fetched snapshot is not yet bridged into the P16 recipe
    // sequencer; that is reserved for P17D.
    // ============================================================
    logic                      csr_desc_fetch_start_pulse;
    logic                      csr_desc_fetch_clear_done_pulse;
    logic                      csr_desc_fetch_clear_error_pulse;
    logic [ADDR_WIDTH-1:0]     csr_desc_fetch_base_addr;
    logic [3:0]                csr_desc_fetch_count;
    logic [15:0]               csr_desc_fetch_stride_bytes;

    logic                      desc_fetch_busy_i;
    logic                      desc_fetch_done_i;
    logic                      desc_fetch_error_i;
    logic                      desc_fetch_reject_i;
    logic [31:0]               desc_fetch_error_status_i;
    logic [31:0]               desc_fetch_reject_status_i;

    // P17G external start gating/rejects.  These rejects are generated
    // by the CSR/top-level integration layer before a START_FETCH pulse
    // reaches the descriptor fetch engine.
    logic                      desc_fetch_start_blocked_i;
    logic                      desc_fetch_start_to_engine;
    logic                      desc_fetch_external_reject_q;
    logic [31:0]               desc_fetch_external_reject_status_q;
    logic                      desc_fetch_reject_to_csr;
    logic [31:0]               desc_fetch_reject_status_to_csr;
    logic [3:0]                desc_fetch_current_index_i;
    logic [3:0]                desc_fetch_fetched_count_i;
    logic                      desc_fetch_snapshot_valid_i;
    logic [3:0]                desc_fetch_recipe_count_i;

    logic [P16_RECIPE_QUEUE_DEPTH-1:0][31:0]           desc_fetch_slot_control;
    logic [P16_RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0] desc_fetch_slot_base_addr_a;
    logic [P16_RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0] desc_fetch_slot_base_addr_b;
    logic [P16_RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0] desc_fetch_slot_base_addr_c;
    logic [P16_RECIPE_QUEUE_DEPTH-1:0][31:0]           desc_fetch_slot_dim_m;
    logic [P16_RECIPE_QUEUE_DEPTH-1:0][31:0]           desc_fetch_slot_dim_n;
    logic [P16_RECIPE_QUEUE_DEPTH-1:0][31:0]           desc_fetch_slot_dim_k;
    logic [P16_RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0] desc_fetch_slot_a_src_base;
    logic [P16_RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0] desc_fetch_slot_a_dst_base;
    logic [P16_RECIPE_QUEUE_DEPTH-1:0][31:0]           desc_fetch_slot_a_load_beats;
    logic [P16_RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0] desc_fetch_slot_b_src_base;
    logic [P16_RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0] desc_fetch_slot_b_dst_base;
    logic [P16_RECIPE_QUEUE_DEPTH-1:0][31:0]           desc_fetch_slot_b_load_beats;
    logic [P16_RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0] desc_fetch_slot_store_src_base;
    logic [P16_RECIPE_QUEUE_DEPTH-1:0][ADDR_WIDTH-1:0] desc_fetch_slot_store_dst_base;
    logic [P16_RECIPE_QUEUE_DEPTH-1:0][31:0]           desc_fetch_slot_store_byte_count;
    logic [P16_RECIPE_QUEUE_DEPTH-1:0][31:0]           desc_fetch_slot_user_tag;

    // ------------------------------------------------------------
    // P17D fetched-descriptor -> P16 recipe launch bridge
    // ------------------------------------------------------------
    logic                      desc_fetch_done_q;
    logic                      desc_fetch_recipe_start_pulse;
    logic                      eff_recipe_start_pulse;
    logic [3:0]                eff_recipe_count;
    logic [3:0]                eff_recipe_start_slot;
    logic                      eff_recipe_stop_on_error;
    logic                      eff_recipe_clear_job_sticky_each_slot;
    logic                      eff_recipe_accumulate_perf;

    logic [31:0]               eff_recipe_slot_control [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     eff_recipe_slot_base_addr_a [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     eff_recipe_slot_base_addr_b [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     eff_recipe_slot_base_addr_c [P16_RECIPE_QUEUE_DEPTH];
    logic [GEMM_DIM_WIDTH-1:0] eff_recipe_slot_dim_m [P16_RECIPE_QUEUE_DEPTH];
    logic [GEMM_DIM_WIDTH-1:0] eff_recipe_slot_dim_n [P16_RECIPE_QUEUE_DEPTH];
    logic [GEMM_DIM_WIDTH-1:0] eff_recipe_slot_dim_k [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     eff_recipe_slot_a_src_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     eff_recipe_slot_a_dst_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0]               eff_recipe_slot_a_load_beats [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     eff_recipe_slot_b_src_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     eff_recipe_slot_b_dst_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0]               eff_recipe_slot_b_load_beats [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     eff_recipe_slot_store_src_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0]     eff_recipe_slot_store_dst_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0]               eff_recipe_slot_store_byte_count [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0]               eff_recipe_slot_user_tag [P16_RECIPE_QUEUE_DEPTH];

    // ============================================================
    // P16 recipe sequencer outputs and status
    // ============================================================
    logic                      recipe_job_start_pulse;
    logic                      recipe_job_clear_done_pulse;
    logic                      recipe_job_clear_error_pulse;
    logic                      recipe_job_clear_perf_pulse;

    logic [1:0]                recipe_job_input_mode;
    logic [1:0]                recipe_job_output_mode;
    logic                      recipe_job_accumulate_enable;

    logic [ADDR_WIDTH-1:0]     recipe_job_base_addr_a;
    logic [ADDR_WIDTH-1:0]     recipe_job_base_addr_b;
    logic [ADDR_WIDTH-1:0]     recipe_job_base_addr_c;
    logic [GEMM_DIM_WIDTH-1:0] recipe_job_dim_m;
    logic [GEMM_DIM_WIDTH-1:0] recipe_job_dim_n;
    logic [GEMM_DIM_WIDTH-1:0] recipe_job_dim_k;

    logic [ADDR_WIDTH-1:0]     recipe_job_a_src_base_addr;
    logic [ADDR_WIDTH-1:0]     recipe_job_a_dst_base_addr;
    logic [31:0]               recipe_job_a_load_beats;
    logic [ADDR_WIDTH-1:0]     recipe_job_b_src_base_addr;
    logic [ADDR_WIDTH-1:0]     recipe_job_b_dst_base_addr;
    logic [31:0]               recipe_job_b_load_beats;
    logic [ADDR_WIDTH-1:0]     recipe_job_store_src_base_addr;
    logic [ADDR_WIDTH-1:0]     recipe_job_store_dst_base_addr;
    logic [31:0]               recipe_job_store_byte_count;

    logic                      recipe_busy_i;
    logic                      recipe_done_i;
    logic                      recipe_all_slots_done_i;
    logic                      recipe_final_store_done_i;

    logic                      recipe_slot_job_error_i;
    logic                      recipe_slot_job_reject_i;
    logic                      recipe_sequence_error_i;
    logic                      recipe_slot_range_error_i;
    logic                      recipe_slot_descriptor_error_i;

    logic [31:0]               recipe_state_i;
    logic [31:0]               recipe_current_slot_i;
    logic [31:0]               recipe_completed_count_i;
    logic [31:0]               recipe_slot_done_mask_i;
    logic [31:0]               recipe_slot_error_mask_i;
    logic [31:0]               recipe_slot_reject_mask_i;
    logic [31:0]               recipe_perf_busy_cycles_i;
    logic [31:0]               recipe_perf_mac_count_i;
    logic [31:0]               recipe_perf_output_count_i;

    // ============================================================
    // Effective P15 job inputs
    //
    // When a P16 recipe is active, the recipe sequencer owns the
    // P15 single-job worker.  Otherwise, the original P15 CSR job
    // descriptor path remains available for debug and regression.
    // ============================================================
    logic                      eff_job_start_pulse;
    logic                      eff_job_clear_done_pulse;
    logic                      eff_job_clear_error_pulse;
    logic                      eff_job_clear_perf_pulse;

    logic [1:0]                eff_job_input_mode;
    logic [1:0]                eff_job_output_mode;
    logic                      eff_job_accumulate_enable;

    logic [ADDR_WIDTH-1:0]     eff_job_base_addr_a;
    logic [ADDR_WIDTH-1:0]     eff_job_base_addr_b;
    logic [ADDR_WIDTH-1:0]     eff_job_base_addr_c;
    logic [GEMM_DIM_WIDTH-1:0] eff_job_dim_m;
    logic [GEMM_DIM_WIDTH-1:0] eff_job_dim_n;
    logic [GEMM_DIM_WIDTH-1:0] eff_job_dim_k;

    logic [ADDR_WIDTH-1:0]     eff_job_a_src_base_addr;
    logic [ADDR_WIDTH-1:0]     eff_job_a_dst_base_addr;
    logic [31:0]               eff_job_a_load_beats;
    logic [ADDR_WIDTH-1:0]     eff_job_b_src_base_addr;
    logic [ADDR_WIDTH-1:0]     eff_job_b_dst_base_addr;
    logic [31:0]               eff_job_b_load_beats;
    logic [ADDR_WIDTH-1:0]     eff_job_store_src_base_addr;
    logic [ADDR_WIDTH-1:0]     eff_job_store_dst_base_addr;
    logic [31:0]               eff_job_store_byte_count;

    // ============================================================
    // Muxed control/config wires driven into the existing subsystem
    // ============================================================
    logic                      subsys_acc_start_pulse;
    logic                      subsys_gemm_input_stream_mode;
    logic                      subsys_accumulate_enable;

    logic [ADDR_WIDTH-1:0]     subsys_base_addr_a;
    logic [ADDR_WIDTH-1:0]     subsys_base_addr_b;
    logic [ADDR_WIDTH-1:0]     subsys_base_addr_c;

    logic [GEMM_DIM_WIDTH-1:0] subsys_dim_m;
    logic [GEMM_DIM_WIDTH-1:0] subsys_dim_n;
    logic [GEMM_DIM_WIDTH-1:0] subsys_dim_k;

    logic                      subsys_dma_load_start_pulse;
    logic [ADDR_WIDTH-1:0]     subsys_dma_src_base_addr;
    logic [ADDR_WIDTH-1:0]     subsys_dma_dst_base_addr;
    logic [31:0]               subsys_dma_load_beats;

    logic                      subsys_axis_load_start_pulse;
    logic [ADDR_WIDTH-1:0]     subsys_axis_src_base_addr;
    logic [ADDR_WIDTH-1:0]     subsys_axis_dst_base_addr;
    logic [31:0]               subsys_axis_load_beats;

    logic                      subsys_ds_load_start_pulse;
    logic [ADDR_WIDTH-1:0]     subsys_ds_src_base_addr;
    logic [ADDR_WIDTH-1:0]     subsys_ds_dst_base_addr;
    logic [31:0]               subsys_ds_load_beats;
    logic                      subsys_ds_operand_sel;

    logic                      subsys_dma_store_start_pulse;
    logic [ADDR_WIDTH-1:0]     subsys_dma_store_src_base_addr;
    logic [ADDR_WIDTH-1:0]     subsys_dma_store_dst_base_addr;
    logic [31:0]               subsys_dma_store_byte_count;

    // ============================================================
    // Existing subsystem status wires
    // ============================================================
    logic                      dma_load_busy_i;
    logic                      dma_load_done_i;
    logic                      dma_load_error_i;

    logic                      axis_load_busy_i;
    logic                      axis_load_done_i;
    logic                      axis_load_error_i;

    logic                      ds_load_busy_i;
    logic                      ds_load_done_i;
    logic                      ds_load_error_i;

    logic                      dma_store_busy_i;
    logic                      dma_store_done_i;
    logic                      dma_store_error_i;

    logic                      acc_busy_i;
    logic                      acc_done_i;

    logic [31:0]               gemm_perf_busy_cycles_i;
    logic [31:0]               gemm_perf_mac_count_i;
    logic [31:0]               gemm_perf_output_count_i;

    assign dma_load_busy  = dma_load_busy_i;
    assign dma_load_done  = dma_load_done_i;
    assign dma_load_error = dma_load_error_i;

    assign axis_load_busy  = axis_load_busy_i;
    assign axis_load_done  = axis_load_done_i;
    assign axis_load_error = axis_load_error_i;

    assign ds_load_busy  = ds_load_busy_i;
    assign ds_load_done  = ds_load_done_i;
    assign ds_load_error = ds_load_error_i;

    assign dma_store_busy  = dma_store_busy_i;
    assign dma_store_done  = dma_store_done_i;
    assign dma_store_error = dma_store_error_i;

    assign acc_busy = acc_busy_i;
    assign acc_done = acc_done_i;

    assign gemm_perf_busy_cycles  = gemm_perf_busy_cycles_i;
    assign gemm_perf_mac_count    = gemm_perf_mac_count_i;
    assign gemm_perf_output_count = gemm_perf_output_count_i;

    // ============================================================
    // P17G descriptor-fetch top-level start gating
    //
    // START_FETCH is allowed to reach the fetch engine only when no
    // descriptor fetch, P16 recipe, P15 job, or P14 micro-operation is
    // active.  Rejected START_FETCH writes are reported through the
    // descriptor-fetch reject CSR window without modifying the in-flight
    // operation.
    // ============================================================
    assign desc_fetch_start_blocked_i = desc_fetch_busy_i ||
                                        recipe_busy_i     ||
                                        job_busy_i        ||
                                        acc_busy_i        ||
                                        dma_load_busy_i   ||
                                        axis_load_busy_i  ||
                                        ds_load_busy_i    ||
                                        dma_store_busy_i;

    assign desc_fetch_start_to_engine = csr_desc_fetch_start_pulse &&
                                        !desc_fetch_start_blocked_i;

    always_ff @(posedge dma_clk or negedge dma_rst_n) begin
        if (!dma_rst_n) begin
            desc_fetch_external_reject_q        <= 1'b0;
            desc_fetch_external_reject_status_q <= 32'h0000_0000;
        end else begin
            if (csr_desc_fetch_clear_error_pulse) begin
                desc_fetch_external_reject_q        <= 1'b0;
                desc_fetch_external_reject_status_q <= 32'h0000_0000;
            end

            if (csr_desc_fetch_start_pulse && desc_fetch_start_blocked_i) begin
                desc_fetch_external_reject_q           <= 1'b1;
                desc_fetch_external_reject_status_q[0] <= 1'b1;
            end
        end
    end

    assign desc_fetch_reject_to_csr = desc_fetch_reject_i |
                                      desc_fetch_external_reject_q;

    assign desc_fetch_reject_status_to_csr = desc_fetch_reject_status_i |
                                             desc_fetch_external_reject_status_q;

    // ============================================================
    // AXI-Lite CSR register block
    //
    // The CSR block lives entirely in dma_clk domain. It generates
    // one-cycle operation start pulses and holds configuration
    // registers that drive the existing sideband-controlled datapath
    // subsystem.
    // ============================================================
    ai_accel_csr_regs #(
        .ADDR_WIDTH        (ADDR_WIDTH),
        .GEMM_DIM_WIDTH    (GEMM_DIM_WIDTH),
        .CSR_ADDR_WIDTH        (CSR_ADDR_WIDTH),
        .CSR_DATA_WIDTH        (CSR_DATA_WIDTH),
        .CSR_VERSION_VALUE        (CSR_VERSION_VALUE),
        .CSR_JOB_VERSION_VALUE    (CSR_JOB_VERSION_VALUE),
        .CSR_RECIPE_VERSION_VALUE (CSR_RECIPE_VERSION_VALUE),
        .CSR_DESC_FETCH_VERSION_VALUE(CSR_DESC_FETCH_VERSION_VALUE),
        .P16_RECIPE_QUEUE_DEPTH   (P16_RECIPE_QUEUE_DEPTH)
    ) u_ai_accel_csr_regs (
        .clk                    (dma_clk),
        .rst_n                  (dma_rst_n),

        .csr_if                 (csr_if),

        .acc_start_pulse        (csr_acc_start_pulse),
        .gemm_input_stream_mode (csr_gemm_input_stream_mode),
        .accumulate_enable      (csr_accumulate_enable),

        .base_addr_a            (csr_base_addr_a),
        .base_addr_b            (csr_base_addr_b),
        .base_addr_c            (csr_base_addr_c),

        .dim_m                  (csr_dim_m),
        .dim_n                  (csr_dim_n),
        .dim_k                  (csr_dim_k),

        .dma_load_start_pulse   (csr_dma_load_start_pulse),
        .dma_src_base_addr      (csr_dma_src_base_addr),
        .dma_dst_base_addr      (csr_dma_dst_base_addr),
        .dma_load_beats         (csr_dma_load_beats),

        .axis_load_start_pulse  (csr_axis_load_start_pulse),
        .axis_src_base_addr     (csr_axis_src_base_addr),
        .axis_dst_base_addr     (csr_axis_dst_base_addr),
        .axis_load_beats        (csr_axis_load_beats),

        .ds_load_start_pulse    (csr_ds_load_start_pulse),
        .ds_src_base_addr       (csr_ds_src_base_addr),
        .ds_dst_base_addr       (csr_ds_dst_base_addr),
        .ds_load_beats          (csr_ds_load_beats),
        .ds_operand_sel         (csr_ds_operand_sel),

        .dma_store_start_pulse  (csr_dma_store_start_pulse),
        .dma_store_src_base_addr(csr_dma_store_src_base_addr),
        .dma_store_dst_base_addr(csr_dma_store_dst_base_addr),
        .dma_store_byte_count   (csr_dma_store_byte_count),

        .job_start_pulse        (csr_job_start_pulse),
        .job_clear_done_pulse   (csr_job_clear_done_pulse),
        .job_clear_error_pulse  (csr_job_clear_error_pulse),
        .job_clear_perf_pulse   (csr_job_clear_perf_pulse),

        .job_input_mode         (csr_job_input_mode),
        .job_output_mode        (csr_job_output_mode),
        .job_accumulate_enable  (csr_job_accumulate_enable),
        .job_clear_p14_sticky_on_start(csr_job_clear_p14_sticky_on_start),

        .job_base_addr_a        (csr_job_base_addr_a),
        .job_base_addr_b        (csr_job_base_addr_b),
        .job_base_addr_c        (csr_job_base_addr_c),

        .job_dim_m              (csr_job_dim_m),
        .job_dim_n              (csr_job_dim_n),
        .job_dim_k              (csr_job_dim_k),

        .job_a_src_base_addr    (csr_job_a_src_base_addr),
        .job_a_dst_base_addr    (csr_job_a_dst_base_addr),
        .job_a_load_beats       (csr_job_a_load_beats),

        .job_b_src_base_addr    (csr_job_b_src_base_addr),
        .job_b_dst_base_addr    (csr_job_b_dst_base_addr),
        .job_b_load_beats       (csr_job_b_load_beats),

        .job_store_src_base_addr(csr_job_store_src_base_addr),
        .job_store_dst_base_addr(csr_job_store_dst_base_addr),
        .job_store_byte_count   (csr_job_store_byte_count),

        .recipe_start_pulse             (csr_recipe_start_pulse),
        .recipe_clear_done_pulse        (csr_recipe_clear_done_pulse),
        .recipe_clear_error_pulse       (csr_recipe_clear_error_pulse),
        .recipe_clear_perf_pulse        (csr_recipe_clear_perf_pulse),
        .recipe_clear_slot_status_pulse (csr_recipe_clear_slot_status_pulse),

        .recipe_count                   (csr_recipe_count),
        .recipe_start_slot              (csr_recipe_start_slot),
        .recipe_stop_on_error           (csr_recipe_stop_on_error),
        .recipe_clear_job_sticky_each_slot(csr_recipe_clear_job_sticky_each_slot),
        .recipe_accumulate_perf         (csr_recipe_accumulate_perf),
        .recipe_allow_slot_writes_while_busy(csr_recipe_allow_slot_writes_while_busy),

        .recipe_slot_control            (csr_recipe_slot_control),
        .recipe_slot_base_addr_a        (csr_recipe_slot_base_addr_a),
        .recipe_slot_base_addr_b        (csr_recipe_slot_base_addr_b),
        .recipe_slot_base_addr_c        (csr_recipe_slot_base_addr_c),
        .recipe_slot_dim_m              (csr_recipe_slot_dim_m),
        .recipe_slot_dim_n              (csr_recipe_slot_dim_n),
        .recipe_slot_dim_k              (csr_recipe_slot_dim_k),
        .recipe_slot_a_src_base_addr    (csr_recipe_slot_a_src_base_addr),
        .recipe_slot_a_dst_base_addr    (csr_recipe_slot_a_dst_base_addr),
        .recipe_slot_a_load_beats       (csr_recipe_slot_a_load_beats),
        .recipe_slot_b_src_base_addr    (csr_recipe_slot_b_src_base_addr),
        .recipe_slot_b_dst_base_addr    (csr_recipe_slot_b_dst_base_addr),
        .recipe_slot_b_load_beats       (csr_recipe_slot_b_load_beats),
        .recipe_slot_store_src_base_addr(csr_recipe_slot_store_src_base_addr),
        .recipe_slot_store_dst_base_addr(csr_recipe_slot_store_dst_base_addr),
        .recipe_slot_store_byte_count   (csr_recipe_slot_store_byte_count),
        .recipe_slot_user_tag           (csr_recipe_slot_user_tag),

        .desc_fetch_start_pulse         (csr_desc_fetch_start_pulse),
        .desc_fetch_clear_done_pulse    (csr_desc_fetch_clear_done_pulse),
        .desc_fetch_clear_error_pulse   (csr_desc_fetch_clear_error_pulse),
        .desc_fetch_base_addr           (csr_desc_fetch_base_addr),
        .desc_fetch_count               (csr_desc_fetch_count),
        .desc_fetch_stride_bytes        (csr_desc_fetch_stride_bytes),

        .desc_fetch_busy                (desc_fetch_busy_i),
        .desc_fetch_done                (desc_fetch_done_i),
        .desc_fetch_error               (desc_fetch_error_i),
        .desc_fetch_reject              (desc_fetch_reject_to_csr),
        .desc_fetch_error_status        (desc_fetch_error_status_i),
        .desc_fetch_reject_status       (desc_fetch_reject_status_to_csr),
        .desc_fetch_current_index       (desc_fetch_current_index_i),
        .desc_fetch_fetched_count       (desc_fetch_fetched_count_i),
        .desc_fetch_snapshot_valid      (desc_fetch_snapshot_valid_i),
        .desc_fetch_recipe_count        (desc_fetch_recipe_count_i),

        .job_busy               (job_busy_i),
        .job_done               (job_done_i),
        .job_gemm_done          (job_gemm_done_i),
        .job_store_done         (job_store_done_i),

        .job_dma_load_error     (job_dma_load_error_i),
        .job_axis_load_error    (job_axis_load_error_i),
        .job_ds_load_error      (job_ds_load_error_i),
        .job_dma_store_error    (job_dma_store_error_i),
        .job_sequence_error     (job_sequence_error_i),

        .job_state              (job_state_i),
        .job_perf_busy_cycles   (job_perf_busy_cycles_i),
        .job_perf_mac_count     (job_perf_mac_count_i),
        .job_perf_output_count  (job_perf_output_count_i),

        .recipe_busy            (recipe_busy_i),
        .recipe_done            (recipe_done_i),
        .recipe_all_slots_done  (recipe_all_slots_done_i),
        .recipe_final_store_done(recipe_final_store_done_i),

        .recipe_slot_job_error  (recipe_slot_job_error_i),
        .recipe_slot_job_reject (recipe_slot_job_reject_i),
        .recipe_sequence_error  (recipe_sequence_error_i),
        .recipe_slot_range_error(recipe_slot_range_error_i),
        .recipe_slot_descriptor_error(recipe_slot_descriptor_error_i),

        .recipe_state           (recipe_state_i),
        .recipe_current_slot    (recipe_current_slot_i),
        .recipe_completed_count (recipe_completed_count_i),
        .recipe_slot_done_mask  (recipe_slot_done_mask_i),
        .recipe_slot_error_mask (recipe_slot_error_mask_i),
        .recipe_slot_reject_mask(recipe_slot_reject_mask_i),
        .recipe_perf_busy_cycles(recipe_perf_busy_cycles_i),
        .recipe_perf_mac_count  (recipe_perf_mac_count_i),
        .recipe_perf_output_count(recipe_perf_output_count_i),

        .acc_busy               (acc_busy_i),
        .acc_done               (acc_done_i),

        .dma_load_busy          (dma_load_busy_i),
        .dma_load_done          (dma_load_done_i),
        .dma_load_error         (dma_load_error_i),

        .axis_load_busy         (axis_load_busy_i),
        .axis_load_done         (axis_load_done_i),
        .axis_load_error        (axis_load_error_i),

        .ds_load_busy           (ds_load_busy_i),
        .ds_load_done           (ds_load_done_i),
        .ds_load_error          (ds_load_error_i),

        .dma_store_busy         (dma_store_busy_i),
        .dma_store_done         (dma_store_done_i),
        .dma_store_error        (dma_store_error_i),

        .gemm_perf_busy_cycles  (gemm_perf_busy_cycles_i),
        .gemm_perf_mac_count    (gemm_perf_mac_count_i),
        .gemm_perf_output_count (gemm_perf_output_count_i)
    );

    // ============================================================
    // P17 descriptor fetch engine
    //
    // P17C wires the fetch engine into the CSR wrapper and the UVM
    // descriptor memory read port.  It only fetches and validates
    // memory-backed descriptors into an internal P16-compatible
    // snapshot.  P17D will bridge this snapshot into the recipe
    // sequencer start path.
    // ============================================================
    ai_accel_desc_fetch_engine #(
        .ADDR_WIDTH         (ADDR_WIDTH),
        .DATA_WIDTH         (DATA_WIDTH),
        .AXI_ID_WIDTH       (ID_WIDTH),
        .RECIPE_QUEUE_DEPTH (P16_RECIPE_QUEUE_DEPTH)
    ) u_ai_accel_desc_fetch_engine (
        .clk                    (dma_clk),
        .rst_n                  (dma_rst_n),

        .fetch_start            (desc_fetch_start_to_engine),
        .desc_base_addr         (csr_desc_fetch_base_addr),
        .desc_count             (csr_desc_fetch_count),
        .desc_stride_bytes      (csr_desc_fetch_stride_bytes),
        .clear_done             (csr_desc_fetch_clear_done_pulse),
        .clear_error            (csr_desc_fetch_clear_error_pulse),

        .fetch_busy             (desc_fetch_busy_i),
        .fetch_done             (desc_fetch_done_i),
        .fetch_error            (desc_fetch_error_i),
        .fetch_reject           (desc_fetch_reject_i),
        .fetch_error_status     (desc_fetch_error_status_i),
        .fetch_reject_status    (desc_fetch_reject_status_i),
        .current_desc_index     (desc_fetch_current_index_i),
        .fetched_count          (desc_fetch_fetched_count_i),
        .fetched_snapshot_valid (desc_fetch_snapshot_valid_i),
        .fetched_recipe_count   (desc_fetch_recipe_count_i),

        .slot_control           (desc_fetch_slot_control),
        .slot_base_addr_a       (desc_fetch_slot_base_addr_a),
        .slot_base_addr_b       (desc_fetch_slot_base_addr_b),
        .slot_base_addr_c       (desc_fetch_slot_base_addr_c),
        .slot_dim_m             (desc_fetch_slot_dim_m),
        .slot_dim_n             (desc_fetch_slot_dim_n),
        .slot_dim_k             (desc_fetch_slot_dim_k),
        .slot_a_src_base        (desc_fetch_slot_a_src_base),
        .slot_a_dst_base        (desc_fetch_slot_a_dst_base),
        .slot_a_load_beats      (desc_fetch_slot_a_load_beats),
        .slot_b_src_base        (desc_fetch_slot_b_src_base),
        .slot_b_dst_base        (desc_fetch_slot_b_dst_base),
        .slot_b_load_beats      (desc_fetch_slot_b_load_beats),
        .slot_store_src_base    (desc_fetch_slot_store_src_base),
        .slot_store_dst_base    (desc_fetch_slot_store_dst_base),
        .slot_store_byte_count  (desc_fetch_slot_store_byte_count),
        .slot_user_tag          (desc_fetch_slot_user_tag),

        .desc_axi_arid          (desc_src_axi_arid),
        .desc_axi_araddr        (desc_src_axi_araddr),
        .desc_axi_arlen         (desc_src_axi_arlen),
        .desc_axi_arsize        (desc_src_axi_arsize),
        .desc_axi_arburst       (desc_src_axi_arburst),
        .desc_axi_arvalid       (desc_src_axi_arvalid),
        .desc_axi_arready       (desc_src_axi_arready),

        .desc_axi_rid           (desc_src_axi_rid),
        .desc_axi_rdata         (desc_src_axi_rdata),
        .desc_axi_rresp         (desc_src_axi_rresp),
        .desc_axi_rlast         (desc_src_axi_rlast),
        .desc_axi_rvalid        (desc_src_axi_rvalid),
        .desc_axi_rready        (desc_src_axi_rready)
    );

    // ------------------------------------------------------------
    // P17D bridge policy
    //
    // A successful descriptor fetch creates a stable P16-compatible
    // snapshot inside ai_accel_desc_fetch_engine.  The bridge launches
    // the existing P16 recipe sequencer on the rising edge of the
    // descriptor-fetch done status, without writing fetched descriptors
    // back into the live CSR recipe slot registers.
    // ------------------------------------------------------------
    always_ff @(posedge dma_clk or negedge dma_rst_n) begin
        if (!dma_rst_n) begin
            desc_fetch_done_q <= 1'b0;
        end else begin
            desc_fetch_done_q <= desc_fetch_done_i;
        end
    end

    assign desc_fetch_recipe_start_pulse = desc_fetch_done_i &&
                                           !desc_fetch_done_q &&
                                           desc_fetch_snapshot_valid_i &&
                                           !desc_fetch_error_i &&
                                           !desc_fetch_reject_i;

    assign eff_recipe_start_pulse = csr_recipe_start_pulse |
                                    desc_fetch_recipe_start_pulse;

    assign eff_recipe_count = desc_fetch_recipe_start_pulse ?
                              desc_fetch_recipe_count_i :
                              csr_recipe_count;

    assign eff_recipe_start_slot = desc_fetch_recipe_start_pulse ?
                                   4'd0 :
                                   csr_recipe_start_slot;

    assign eff_recipe_stop_on_error = desc_fetch_recipe_start_pulse ?
                                      1'b1 :
                                      csr_recipe_stop_on_error;

    assign eff_recipe_clear_job_sticky_each_slot =
        desc_fetch_recipe_start_pulse ? 1'b1 : csr_recipe_clear_job_sticky_each_slot;

    assign eff_recipe_accumulate_perf = desc_fetch_recipe_start_pulse ?
                                        1'b1 :
                                        csr_recipe_accumulate_perf;

    always_comb begin
        for (int unsigned slot_i = 0; slot_i < P16_RECIPE_QUEUE_DEPTH; slot_i++) begin
            if (desc_fetch_recipe_start_pulse) begin
                eff_recipe_slot_control[slot_i]             = desc_fetch_slot_control[slot_i];
                eff_recipe_slot_base_addr_a[slot_i]         = desc_fetch_slot_base_addr_a[slot_i];
                eff_recipe_slot_base_addr_b[slot_i]         = desc_fetch_slot_base_addr_b[slot_i];
                eff_recipe_slot_base_addr_c[slot_i]         = desc_fetch_slot_base_addr_c[slot_i];
                eff_recipe_slot_dim_m[slot_i]               = desc_fetch_slot_dim_m[slot_i][GEMM_DIM_WIDTH-1:0];
                eff_recipe_slot_dim_n[slot_i]               = desc_fetch_slot_dim_n[slot_i][GEMM_DIM_WIDTH-1:0];
                eff_recipe_slot_dim_k[slot_i]               = desc_fetch_slot_dim_k[slot_i][GEMM_DIM_WIDTH-1:0];
                eff_recipe_slot_a_src_base_addr[slot_i]     = desc_fetch_slot_a_src_base[slot_i];
                eff_recipe_slot_a_dst_base_addr[slot_i]     = desc_fetch_slot_a_dst_base[slot_i];
                eff_recipe_slot_a_load_beats[slot_i]        = desc_fetch_slot_a_load_beats[slot_i];
                eff_recipe_slot_b_src_base_addr[slot_i]     = desc_fetch_slot_b_src_base[slot_i];
                eff_recipe_slot_b_dst_base_addr[slot_i]     = desc_fetch_slot_b_dst_base[slot_i];
                eff_recipe_slot_b_load_beats[slot_i]        = desc_fetch_slot_b_load_beats[slot_i];
                eff_recipe_slot_store_src_base_addr[slot_i] = desc_fetch_slot_store_src_base[slot_i];
                eff_recipe_slot_store_dst_base_addr[slot_i] = desc_fetch_slot_store_dst_base[slot_i];
                eff_recipe_slot_store_byte_count[slot_i]    = desc_fetch_slot_store_byte_count[slot_i];
                eff_recipe_slot_user_tag[slot_i]            = desc_fetch_slot_user_tag[slot_i];
            end else begin
                eff_recipe_slot_control[slot_i]             = csr_recipe_slot_control[slot_i];
                eff_recipe_slot_base_addr_a[slot_i]         = csr_recipe_slot_base_addr_a[slot_i];
                eff_recipe_slot_base_addr_b[slot_i]         = csr_recipe_slot_base_addr_b[slot_i];
                eff_recipe_slot_base_addr_c[slot_i]         = csr_recipe_slot_base_addr_c[slot_i];
                eff_recipe_slot_dim_m[slot_i]               = csr_recipe_slot_dim_m[slot_i];
                eff_recipe_slot_dim_n[slot_i]               = csr_recipe_slot_dim_n[slot_i];
                eff_recipe_slot_dim_k[slot_i]               = csr_recipe_slot_dim_k[slot_i];
                eff_recipe_slot_a_src_base_addr[slot_i]     = csr_recipe_slot_a_src_base_addr[slot_i];
                eff_recipe_slot_a_dst_base_addr[slot_i]     = csr_recipe_slot_a_dst_base_addr[slot_i];
                eff_recipe_slot_a_load_beats[slot_i]        = csr_recipe_slot_a_load_beats[slot_i];
                eff_recipe_slot_b_src_base_addr[slot_i]     = csr_recipe_slot_b_src_base_addr[slot_i];
                eff_recipe_slot_b_dst_base_addr[slot_i]     = csr_recipe_slot_b_dst_base_addr[slot_i];
                eff_recipe_slot_b_load_beats[slot_i]        = csr_recipe_slot_b_load_beats[slot_i];
                eff_recipe_slot_store_src_base_addr[slot_i] = csr_recipe_slot_store_src_base_addr[slot_i];
                eff_recipe_slot_store_dst_base_addr[slot_i] = csr_recipe_slot_store_dst_base_addr[slot_i];
                eff_recipe_slot_store_byte_count[slot_i]    = csr_recipe_slot_store_byte_count[slot_i];
                eff_recipe_slot_user_tag[slot_i]            = csr_recipe_slot_user_tag[slot_i];
            end
        end
    end


    // ============================================================
    // P16 multi-job recipe sequencer
    //
    // The recipe sequencer dispatches CSR-resident descriptor slots
    // through the existing P15 single-job sequencer.  It does not
    // duplicate the preload/GEMM/store FSM; it only selects one slot,
    // starts one P15 job, waits for that job to complete, and advances
    // to the next selected slot.
    // ============================================================
    ai_accel_recipe_sequencer #(
        .ADDR_WIDTH             (ADDR_WIDTH),
        .GEMM_DIM_WIDTH         (GEMM_DIM_WIDTH),
        .P16_RECIPE_QUEUE_DEPTH (P16_RECIPE_QUEUE_DEPTH)
    ) u_ai_accel_recipe_sequencer (
        .clk                    (dma_clk),
        .rst_n                  (dma_rst_n),

        .recipe_start_pulse     (eff_recipe_start_pulse),
        .recipe_clear_done_pulse(csr_recipe_clear_done_pulse),
        .recipe_clear_error_pulse(csr_recipe_clear_error_pulse),
        .recipe_clear_perf_pulse(csr_recipe_clear_perf_pulse),
        .recipe_clear_slot_status_pulse(csr_recipe_clear_slot_status_pulse),

        .recipe_count           (eff_recipe_count),
        .recipe_start_slot      (eff_recipe_start_slot),
        .recipe_stop_on_error   (eff_recipe_stop_on_error),
        .recipe_clear_job_sticky_each_slot(eff_recipe_clear_job_sticky_each_slot),
        .recipe_accumulate_perf (eff_recipe_accumulate_perf),

        .recipe_slot_control            (eff_recipe_slot_control),
        .recipe_slot_base_addr_a        (eff_recipe_slot_base_addr_a),
        .recipe_slot_base_addr_b        (eff_recipe_slot_base_addr_b),
        .recipe_slot_base_addr_c        (eff_recipe_slot_base_addr_c),
        .recipe_slot_dim_m              (eff_recipe_slot_dim_m),
        .recipe_slot_dim_n              (eff_recipe_slot_dim_n),
        .recipe_slot_dim_k              (eff_recipe_slot_dim_k),
        .recipe_slot_a_src_base_addr    (eff_recipe_slot_a_src_base_addr),
        .recipe_slot_a_dst_base_addr    (eff_recipe_slot_a_dst_base_addr),
        .recipe_slot_a_load_beats       (eff_recipe_slot_a_load_beats),
        .recipe_slot_b_src_base_addr    (eff_recipe_slot_b_src_base_addr),
        .recipe_slot_b_dst_base_addr    (eff_recipe_slot_b_dst_base_addr),
        .recipe_slot_b_load_beats       (eff_recipe_slot_b_load_beats),
        .recipe_slot_store_src_base_addr(eff_recipe_slot_store_src_base_addr),
        .recipe_slot_store_dst_base_addr(eff_recipe_slot_store_dst_base_addr),
        .recipe_slot_store_byte_count   (eff_recipe_slot_store_byte_count),
        .recipe_slot_user_tag           (eff_recipe_slot_user_tag),
        .job_busy               (job_busy_i),
        .job_done               (job_done_i),
        .job_gemm_done          (job_gemm_done_i),
        .job_store_done         (job_store_done_i),
        .job_dma_load_error     (job_dma_load_error_i),
        .job_axis_load_error    (job_axis_load_error_i),
        .job_ds_load_error      (job_ds_load_error_i),
        .job_dma_store_error    (job_dma_store_error_i),
        .job_sequence_error     (job_sequence_error_i),
        .job_state              (job_state_i),
        .job_perf_busy_cycles   (job_perf_busy_cycles_i),
        .job_perf_mac_count     (job_perf_mac_count_i),
        .job_perf_output_count  (job_perf_output_count_i),

        .job_start_pulse        (recipe_job_start_pulse),
        .job_clear_done_pulse   (recipe_job_clear_done_pulse),
        .job_clear_error_pulse  (recipe_job_clear_error_pulse),
        .job_clear_perf_pulse   (recipe_job_clear_perf_pulse),
        .job_input_mode         (recipe_job_input_mode),
        .job_output_mode        (recipe_job_output_mode),
        .job_accumulate_enable  (recipe_job_accumulate_enable),
        .job_base_addr_a        (recipe_job_base_addr_a),
        .job_base_addr_b        (recipe_job_base_addr_b),
        .job_base_addr_c        (recipe_job_base_addr_c),
        .job_dim_m              (recipe_job_dim_m),
        .job_dim_n              (recipe_job_dim_n),
        .job_dim_k              (recipe_job_dim_k),
        .job_a_src_base_addr    (recipe_job_a_src_base_addr),
        .job_a_dst_base_addr    (recipe_job_a_dst_base_addr),
        .job_a_load_beats       (recipe_job_a_load_beats),
        .job_b_src_base_addr    (recipe_job_b_src_base_addr),
        .job_b_dst_base_addr    (recipe_job_b_dst_base_addr),
        .job_b_load_beats       (recipe_job_b_load_beats),
        .job_store_src_base_addr(recipe_job_store_src_base_addr),
        .job_store_dst_base_addr(recipe_job_store_dst_base_addr),
        .job_store_byte_count   (recipe_job_store_byte_count),

        .recipe_busy            (recipe_busy_i),
        .recipe_done            (recipe_done_i),
        .recipe_all_slots_done  (recipe_all_slots_done_i),
        .recipe_final_store_done(recipe_final_store_done_i),
        .recipe_slot_job_error  (recipe_slot_job_error_i),
        .recipe_slot_job_reject (recipe_slot_job_reject_i),
        .recipe_sequence_error  (recipe_sequence_error_i),
        .recipe_slot_range_error(recipe_slot_range_error_i),
        .recipe_slot_descriptor_error(recipe_slot_descriptor_error_i),
        .recipe_state           (recipe_state_i),
        .recipe_current_slot    (recipe_current_slot_i),
        .recipe_completed_count (recipe_completed_count_i),
        .recipe_slot_done_mask  (recipe_slot_done_mask_i),
        .recipe_slot_error_mask (recipe_slot_error_mask_i),
        .recipe_slot_reject_mask(recipe_slot_reject_mask_i),
        .recipe_perf_busy_cycles(recipe_perf_busy_cycles_i),
        .recipe_perf_mac_count  (recipe_perf_mac_count_i),
        .recipe_perf_output_count(recipe_perf_output_count_i)
    );

    assign eff_job_start_pulse       = recipe_busy_i ? recipe_job_start_pulse       : csr_job_start_pulse;
    assign eff_job_clear_done_pulse  = recipe_busy_i ? recipe_job_clear_done_pulse  : csr_job_clear_done_pulse;
    assign eff_job_clear_error_pulse = recipe_busy_i ? recipe_job_clear_error_pulse : csr_job_clear_error_pulse;
    assign eff_job_clear_perf_pulse  = recipe_busy_i ? recipe_job_clear_perf_pulse  : csr_job_clear_perf_pulse;

    assign eff_job_input_mode        = recipe_busy_i ? recipe_job_input_mode        : csr_job_input_mode;
    assign eff_job_output_mode       = recipe_busy_i ? recipe_job_output_mode       : csr_job_output_mode;
    assign eff_job_accumulate_enable = recipe_busy_i ? recipe_job_accumulate_enable : csr_job_accumulate_enable;

    assign eff_job_base_addr_a = recipe_busy_i ? recipe_job_base_addr_a : csr_job_base_addr_a;
    assign eff_job_base_addr_b = recipe_busy_i ? recipe_job_base_addr_b : csr_job_base_addr_b;
    assign eff_job_base_addr_c = recipe_busy_i ? recipe_job_base_addr_c : csr_job_base_addr_c;
    assign eff_job_dim_m       = recipe_busy_i ? recipe_job_dim_m       : csr_job_dim_m;
    assign eff_job_dim_n       = recipe_busy_i ? recipe_job_dim_n       : csr_job_dim_n;
    assign eff_job_dim_k       = recipe_busy_i ? recipe_job_dim_k       : csr_job_dim_k;

    assign eff_job_a_src_base_addr     = recipe_busy_i ? recipe_job_a_src_base_addr     : csr_job_a_src_base_addr;
    assign eff_job_a_dst_base_addr     = recipe_busy_i ? recipe_job_a_dst_base_addr     : csr_job_a_dst_base_addr;
    assign eff_job_a_load_beats        = recipe_busy_i ? recipe_job_a_load_beats        : csr_job_a_load_beats;
    assign eff_job_b_src_base_addr     = recipe_busy_i ? recipe_job_b_src_base_addr     : csr_job_b_src_base_addr;
    assign eff_job_b_dst_base_addr     = recipe_busy_i ? recipe_job_b_dst_base_addr     : csr_job_b_dst_base_addr;
    assign eff_job_b_load_beats        = recipe_busy_i ? recipe_job_b_load_beats        : csr_job_b_load_beats;
    assign eff_job_store_src_base_addr = recipe_busy_i ? recipe_job_store_src_base_addr : csr_job_store_src_base_addr;
    assign eff_job_store_dst_base_addr = recipe_busy_i ? recipe_job_store_dst_base_addr : csr_job_store_dst_base_addr;
    assign eff_job_store_byte_count    = recipe_busy_i ? recipe_job_store_byte_count    : csr_job_store_byte_count;

    // ============================================================
    // P15 single-job sequencer
    //
    // The sequencer owns the existing subsystem control/config wires
    // while a job is active.  When no job is active, the original P14
    // CSR micro-operation path remains available for debug and for
    // the existing CSR representative tests.
    // ============================================================
    ai_accel_job_sequencer #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .GEMM_DIM_WIDTH (GEMM_DIM_WIDTH)
    ) u_ai_accel_job_sequencer (
        .clk                    (dma_clk),
        .rst_n                  (dma_rst_n),

        .job_start_pulse        (eff_job_start_pulse),
        .job_clear_done_pulse   (eff_job_clear_done_pulse),
        .job_clear_error_pulse  (eff_job_clear_error_pulse),
        .job_clear_perf_pulse   (eff_job_clear_perf_pulse),

        .job_input_mode         (eff_job_input_mode),
        .job_output_mode        (eff_job_output_mode),
        .job_accumulate_enable  (eff_job_accumulate_enable),

        .job_base_addr_a        (eff_job_base_addr_a),
        .job_base_addr_b        (eff_job_base_addr_b),
        .job_base_addr_c        (eff_job_base_addr_c),
        .job_dim_m              (eff_job_dim_m),
        .job_dim_n              (eff_job_dim_n),
        .job_dim_k              (eff_job_dim_k),

        .job_a_src_base_addr    (eff_job_a_src_base_addr),
        .job_a_dst_base_addr    (eff_job_a_dst_base_addr),
        .job_a_load_beats       (eff_job_a_load_beats),

        .job_b_src_base_addr    (eff_job_b_src_base_addr),
        .job_b_dst_base_addr    (eff_job_b_dst_base_addr),
        .job_b_load_beats       (eff_job_b_load_beats),

        .job_store_src_base_addr(eff_job_store_src_base_addr),
        .job_store_dst_base_addr(eff_job_store_dst_base_addr),
        .job_store_byte_count   (eff_job_store_byte_count),

        .acc_busy               (acc_busy_i),
        .acc_done               (acc_done_i),

        .dma_load_busy          (dma_load_busy_i),
        .dma_load_done          (dma_load_done_i),
        .dma_load_error         (dma_load_error_i),

        .axis_load_busy         (axis_load_busy_i),
        .axis_load_done         (axis_load_done_i),
        .axis_load_error        (axis_load_error_i),

        .ds_load_busy           (ds_load_busy_i),
        .ds_load_done           (ds_load_done_i),
        .ds_load_error          (ds_load_error_i),

        .dma_store_busy         (dma_store_busy_i),
        .dma_store_done         (dma_store_done_i),
        .dma_store_error        (dma_store_error_i),

        .gemm_perf_busy_cycles  (gemm_perf_busy_cycles_i),
        .gemm_perf_mac_count    (gemm_perf_mac_count_i),
        .gemm_perf_output_count (gemm_perf_output_count_i),

        .acc_start_pulse        (job_acc_start_pulse),
        .gemm_input_stream_mode (job_gemm_input_stream_mode),
        .accumulate_enable      (job_accumulate_enable_to_subsys),
        .base_addr_a            (job_base_addr_a_to_subsys),
        .base_addr_b            (job_base_addr_b_to_subsys),
        .base_addr_c            (job_base_addr_c_to_subsys),
        .dim_m                  (job_dim_m_to_subsys),
        .dim_n                  (job_dim_n_to_subsys),
        .dim_k                  (job_dim_k_to_subsys),

        .dma_load_start_pulse   (job_dma_load_start_pulse),
        .dma_src_base_addr      (job_dma_src_base_addr),
        .dma_dst_base_addr      (job_dma_dst_base_addr),
        .dma_load_beats         (job_dma_load_beats),

        .axis_load_start_pulse  (job_axis_load_start_pulse),
        .axis_src_base_addr     (job_axis_src_base_addr),
        .axis_dst_base_addr     (job_axis_dst_base_addr),
        .axis_load_beats        (job_axis_load_beats),

        .ds_load_start_pulse    (job_ds_load_start_pulse),
        .ds_src_base_addr       (job_ds_src_base_addr),
        .ds_dst_base_addr       (job_ds_dst_base_addr),
        .ds_load_beats          (job_ds_load_beats),
        .ds_operand_sel         (job_ds_operand_sel),

        .dma_store_start_pulse  (job_dma_store_start_pulse),
        .dma_store_src_base_addr(job_dma_store_src_base_addr),
        .dma_store_dst_base_addr(job_dma_store_dst_base_addr),
        .dma_store_byte_count   (job_dma_store_byte_count),

        .job_busy               (job_busy_i),
        .job_done               (job_done_i),
        .job_gemm_done          (job_gemm_done_i),
        .job_store_done         (job_store_done_i),

        .job_dma_load_error     (job_dma_load_error_i),
        .job_axis_load_error    (job_axis_load_error_i),
        .job_ds_load_error      (job_ds_load_error_i),
        .job_dma_store_error    (job_dma_store_error_i),
        .job_sequence_error     (job_sequence_error_i),

        .job_state              (job_state_i),
        .job_perf_busy_cycles   (job_perf_busy_cycles_i),
        .job_perf_mac_count     (job_perf_mac_count_i),
        .job_perf_output_count  (job_perf_output_count_i)
    );

    assign subsys_acc_start_pulse = job_busy_i ?
                                    job_acc_start_pulse :
                                    csr_acc_start_pulse;

    assign subsys_gemm_input_stream_mode = job_busy_i ?
                                           job_gemm_input_stream_mode :
                                           csr_gemm_input_stream_mode;

    assign subsys_accumulate_enable = job_busy_i ?
                                      job_accumulate_enable_to_subsys :
                                      csr_accumulate_enable;

    assign subsys_base_addr_a = job_busy_i ? job_base_addr_a_to_subsys : csr_base_addr_a;
    assign subsys_base_addr_b = job_busy_i ? job_base_addr_b_to_subsys : csr_base_addr_b;
    assign subsys_base_addr_c = job_busy_i ? job_base_addr_c_to_subsys : csr_base_addr_c;

    assign subsys_dim_m = job_busy_i ? job_dim_m_to_subsys : csr_dim_m;
    assign subsys_dim_n = job_busy_i ? job_dim_n_to_subsys : csr_dim_n;
    assign subsys_dim_k = job_busy_i ? job_dim_k_to_subsys : csr_dim_k;

    assign subsys_dma_load_start_pulse = job_busy_i ?
                                         job_dma_load_start_pulse :
                                         csr_dma_load_start_pulse;

    assign subsys_dma_src_base_addr = job_busy_i ? job_dma_src_base_addr : csr_dma_src_base_addr;
    assign subsys_dma_dst_base_addr = job_busy_i ? job_dma_dst_base_addr : csr_dma_dst_base_addr;
    assign subsys_dma_load_beats    = job_busy_i ? job_dma_load_beats    : csr_dma_load_beats;

    assign subsys_axis_load_start_pulse = job_busy_i ?
                                          job_axis_load_start_pulse :
                                          csr_axis_load_start_pulse;

    assign subsys_axis_src_base_addr = job_busy_i ? job_axis_src_base_addr : csr_axis_src_base_addr;
    assign subsys_axis_dst_base_addr = job_busy_i ? job_axis_dst_base_addr : csr_axis_dst_base_addr;
    assign subsys_axis_load_beats    = job_busy_i ? job_axis_load_beats    : csr_axis_load_beats;

    assign subsys_ds_load_start_pulse = job_busy_i ?
                                        job_ds_load_start_pulse :
                                        csr_ds_load_start_pulse;

    assign subsys_ds_src_base_addr = job_busy_i ? job_ds_src_base_addr : csr_ds_src_base_addr;
    assign subsys_ds_dst_base_addr = job_busy_i ? job_ds_dst_base_addr : csr_ds_dst_base_addr;
    assign subsys_ds_load_beats    = job_busy_i ? job_ds_load_beats    : csr_ds_load_beats;
    assign subsys_ds_operand_sel   = job_busy_i ? job_ds_operand_sel   : csr_ds_operand_sel;

    assign subsys_dma_store_start_pulse = job_busy_i ?
                                          job_dma_store_start_pulse :
                                          csr_dma_store_start_pulse;

    assign subsys_dma_store_src_base_addr = job_busy_i ?
                                            job_dma_store_src_base_addr :
                                            csr_dma_store_src_base_addr;

    assign subsys_dma_store_dst_base_addr = job_busy_i ?
                                            job_dma_store_dst_base_addr :
                                            csr_dma_store_dst_base_addr;

    assign subsys_dma_store_byte_count = job_busy_i ?
                                         job_dma_store_byte_count :
                                         csr_dma_store_byte_count;

    // ============================================================
    // Existing validated datapath subsystem
    //
    // The CSR wrapper keeps ai_accel_subsys intact and simply
    // drives its existing dma_clk-domain control/config inputs.
    // ============================================================
    ai_accel_subsys #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .DATA_WIDTH      (DATA_WIDTH),
        .ID_WIDTH        (ID_WIDTH),
        .DEPTH_WORDS     (DEPTH_WORDS),

        .GEMM_A_WIDTH    (GEMM_A_WIDTH),
        .GEMM_B_WIDTH    (GEMM_B_WIDTH),
        .GEMM_ACC_WIDTH  (GEMM_ACC_WIDTH),
        .GEMM_DIM_WIDTH  (GEMM_DIM_WIDTH),

        .APPLY_BEAT_IDX_W  (APPLY_BEAT_IDX_W),
        .COMMIT_BEAT_IDX_W (COMMIT_BEAT_IDX_W),

        .GEMM_MAC_LANES    (GEMM_MAC_LANES),

        .GEMM_ENABLE_B_CACHE (GEMM_ENABLE_B_CACHE),
        .GEMM_B_CACHE_MAX_K  (GEMM_B_CACHE_MAX_K),
        .GEMM_B_CACHE_MAX_N  (GEMM_B_CACHE_MAX_N),
        .GEMM_ENABLE_PACKED_BCACHE_PRELOAD (GEMM_ENABLE_PACKED_BCACHE_PRELOAD),
        .GEMM_ENABLE_A_ROW_CACHE           (GEMM_ENABLE_A_ROW_CACHE),
        .GEMM_A_ROW_CACHE_MAX_K            (GEMM_A_ROW_CACHE_MAX_K),
        .GEMM_ENABLE_PACKED_A_ROW_PRELOAD  (GEMM_ENABLE_PACKED_A_ROW_PRELOAD),

        .GEMM_ENABLE_K_TILING (GEMM_ENABLE_K_TILING),
        .GEMM_K_TILE_SIZE     (GEMM_K_TILE_SIZE),
        .GEMM_ENABLE_N_TILING (GEMM_ENABLE_N_TILING),
        .GEMM_N_TILE_SIZE     (GEMM_N_TILE_SIZE),
        .GEMM_ENABLE_M_TILING (GEMM_ENABLE_M_TILING),
        .GEMM_M_TILE_SIZE     (GEMM_M_TILE_SIZE),
        .GEMM_ENABLE_C_RMW_ACCUM (GEMM_ENABLE_C_RMW_ACCUM)
    ) u_ai_accel_subsys (
        .dma_clk        (dma_clk),
        .dma_rst_n      (dma_rst_n),
        .core_clk       (core_clk),
        .core_rst_n     (core_rst_n),

        .axi0_if        (axi0_if),

        .dma_load_start     (subsys_dma_load_start_pulse),
        .dma_src_base_addr  (subsys_dma_src_base_addr),
        .dma_dst_base_addr  (subsys_dma_dst_base_addr),
        .dma_load_beats     (subsys_dma_load_beats),

        .dma_load_busy      (dma_load_busy_i),
        .dma_load_done      (dma_load_done_i),
        .dma_load_error     (dma_load_error_i),

        .dma_store_start         (subsys_dma_store_start_pulse),
        .dma_store_src_base_addr (subsys_dma_store_src_base_addr),
        .dma_store_dst_base_addr (subsys_dma_store_dst_base_addr),
        .dma_store_byte_count    (subsys_dma_store_byte_count),

        .dma_store_busy      (dma_store_busy_i),
        .dma_store_done      (dma_store_done_i),
        .dma_store_error     (dma_store_error_i),

        .axis_load_start     (subsys_axis_load_start_pulse),
        .axis_src_base_addr  (subsys_axis_src_base_addr),
        .axis_dst_base_addr  (subsys_axis_dst_base_addr),
        .axis_load_beats     (subsys_axis_load_beats),

        .axis_load_busy      (axis_load_busy_i),
        .axis_load_done      (axis_load_done_i),
        .axis_load_error     (axis_load_error_i),

        .ds_load_start       (subsys_ds_load_start_pulse),
        .ds_src_base_addr    (subsys_ds_src_base_addr),
        .ds_dst_base_addr    (subsys_ds_dst_base_addr),
        .ds_load_beats       (subsys_ds_load_beats),
        .ds_operand_sel      (subsys_ds_operand_sel),

        .ds_load_busy        (ds_load_busy_i),
        .ds_load_done        (ds_load_done_i),
        .ds_load_error       (ds_load_error_i),

        .dma_src_axi_arid    (dma_src_axi_arid),
        .dma_src_axi_araddr  (dma_src_axi_araddr),
        .dma_src_axi_arlen   (dma_src_axi_arlen),
        .dma_src_axi_arsize  (dma_src_axi_arsize),
        .dma_src_axi_arburst (dma_src_axi_arburst),
        .dma_src_axi_arvalid (dma_src_axi_arvalid),
        .dma_src_axi_arready (dma_src_axi_arready),

        .dma_src_axi_rid     (dma_src_axi_rid),
        .dma_src_axi_rdata   (dma_src_axi_rdata),
        .dma_src_axi_rresp   (dma_src_axi_rresp),
        .dma_src_axi_rlast   (dma_src_axi_rlast),
        .dma_src_axi_rvalid  (dma_src_axi_rvalid),
        .dma_src_axi_rready  (dma_src_axi_rready),

        .axis_src_axi_arid    (axis_src_axi_arid),
        .axis_src_axi_araddr  (axis_src_axi_araddr),
        .axis_src_axi_arlen   (axis_src_axi_arlen),
        .axis_src_axi_arsize  (axis_src_axi_arsize),
        .axis_src_axi_arburst (axis_src_axi_arburst),
        .axis_src_axi_arvalid (axis_src_axi_arvalid),
        .axis_src_axi_arready (axis_src_axi_arready),

        .axis_src_axi_rid     (axis_src_axi_rid),
        .axis_src_axi_rdata   (axis_src_axi_rdata),
        .axis_src_axi_rresp   (axis_src_axi_rresp),
        .axis_src_axi_rlast   (axis_src_axi_rlast),
        .axis_src_axi_rvalid  (axis_src_axi_rvalid),
        .axis_src_axi_rready  (axis_src_axi_rready),

        .ds_src_axi_arid      (ds_src_axi_arid),
        .ds_src_axi_araddr    (ds_src_axi_araddr),
        .ds_src_axi_arlen     (ds_src_axi_arlen),
        .ds_src_axi_arsize    (ds_src_axi_arsize),
        .ds_src_axi_arburst   (ds_src_axi_arburst),
        .ds_src_axi_arvalid   (ds_src_axi_arvalid),
        .ds_src_axi_arready   (ds_src_axi_arready),

        .ds_src_axi_rid       (ds_src_axi_rid),
        .ds_src_axi_rdata     (ds_src_axi_rdata),
        .ds_src_axi_rresp     (ds_src_axi_rresp),
        .ds_src_axi_rlast     (ds_src_axi_rlast),
        .ds_src_axi_rvalid    (ds_src_axi_rvalid),
        .ds_src_axi_rready    (ds_src_axi_rready),

        .dma_dst_axi_awid    (dma_dst_axi_awid),
        .dma_dst_axi_awaddr  (dma_dst_axi_awaddr),
        .dma_dst_axi_awlen   (dma_dst_axi_awlen),
        .dma_dst_axi_awsize  (dma_dst_axi_awsize),
        .dma_dst_axi_awburst (dma_dst_axi_awburst),
        .dma_dst_axi_awvalid (dma_dst_axi_awvalid),
        .dma_dst_axi_awready (dma_dst_axi_awready),

        .dma_dst_axi_wdata   (dma_dst_axi_wdata),
        .dma_dst_axi_wstrb   (dma_dst_axi_wstrb),
        .dma_dst_axi_wlast   (dma_dst_axi_wlast),
        .dma_dst_axi_wvalid  (dma_dst_axi_wvalid),
        .dma_dst_axi_wready  (dma_dst_axi_wready),

        .dma_dst_axi_bid     (dma_dst_axi_bid),
        .dma_dst_axi_bresp   (dma_dst_axi_bresp),
        .dma_dst_axi_bvalid  (dma_dst_axi_bvalid),
        .dma_dst_axi_bready  (dma_dst_axi_bready),

        .gemm_input_stream_mode (subsys_gemm_input_stream_mode),
        .accumulate_enable      (subsys_accumulate_enable),

        .acc_start      (subsys_acc_start_pulse),
        .acc_busy       (acc_busy_i),
        .acc_done       (acc_done_i),

        .base_addr_a    (subsys_base_addr_a),
        .base_addr_b    (subsys_base_addr_b),
        .base_addr_c    (subsys_base_addr_c),

        .dim_m          (subsys_dim_m),
        .dim_n          (subsys_dim_n),
        .dim_k          (subsys_dim_k),

        .gemm_perf_busy_cycles  (gemm_perf_busy_cycles_i),
        .gemm_perf_mac_count    (gemm_perf_mac_count_i),
        .gemm_perf_output_count (gemm_perf_output_count_i)
    );

endmodule

`endif
