// File: rtl/top/ai_accel_subsys.sv
`ifndef AI_ACCEL_SUBSYS_SV
`define AI_ACCEL_SUBSYS_SV

module ai_accel_subsys #(
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

    // P5 packed B-cache preload.
    // Default-off so the current baseline behavior is unchanged unless explicitly enabled.
    parameter bit GEMM_ENABLE_PACKED_BCACHE_PRELOAD = 1'b0,

    // P6 safe parameter patch.
    // Default-off so the current P5 baseline behavior is unchanged.
    parameter bit GEMM_ENABLE_A_ROW_CACHE = 1'b0,
    parameter int GEMM_A_ROW_CACHE_MAX_K  = 4,

    // P7 safe parameter patch.
    // Default-off so the current P6 baseline behavior is unchanged.
    parameter bit GEMM_ENABLE_PACKED_A_ROW_PRELOAD = 1'b0,

    // P10 K-tiling parameterization.
    // Default-off so the pre-P10 baseline behavior is unchanged.
    parameter bit GEMM_ENABLE_K_TILING = 1'b0,
    parameter int GEMM_K_TILE_SIZE     = 8,

    // P11B safe parameter plumbing.
    // Default-off so the current P10 baseline behavior is unchanged.
    parameter bit GEMM_ENABLE_N_TILING = 1'b0,
    parameter int GEMM_N_TILE_SIZE     = 8
)(
    // ------------------------------------------------------------
    // Clocks / resets
    // ------------------------------------------------------------
    input  logic dma_clk,
    input  logic dma_rst_n,
    input  logic core_clk,
    input  logic core_rst_n,

    // ------------------------------------------------------------
    // External AXI-MM slave-visible port
    //
    // Policy:
    // - Host/testbench uses axi0_if to preload/readback when DMA
    //   load/store is not active.
    // - During DMA_LOAD phase, Port0 is owned by dma_load_engine.
    // - During DMA_STORE phase, Port0 is owned by dma_store_engine.
    // - Port0 ownership is selected by scratchpad_port0_owner_mux.
    // ------------------------------------------------------------
    axi_mm_if axi0_if,

    // ------------------------------------------------------------
    // DMA load control
    //
    // Usage:
    //   1. Pulse dma_load_start in dma_clk domain.
    //   2. Wait dma_load_done.
    //   3. Then launch GEMM.
    // ------------------------------------------------------------
    input  logic                      dma_load_start,
    input  logic [ADDR_WIDTH-1:0]     dma_src_base_addr,
    input  logic [ADDR_WIDTH-1:0]     dma_dst_base_addr,
    input  logic [31:0]               dma_load_beats,

    output logic                      dma_load_busy,
    output logic                      dma_load_done,
    output logic                      dma_load_error,

    // ------------------------------------------------------------
    // DMA store control
    //
    // Usage:
    //   1. Wait acc_done after GEMM writes C into scratchpad.
    //   2. Pulse dma_store_start in dma_clk domain.
    //   3. Store engine reads C from scratchpad Port0.
    //   4. Store engine writes C to destination memory.
    //
    // Note:
    //   dma_store_byte_count is byte-based. This allows partial
    //   final-beat WSTRB generation for C sizes not aligned to
    //   DATA_WIDTH bytes.
    // ------------------------------------------------------------
    input  logic                      dma_store_start,
    input  logic [ADDR_WIDTH-1:0]     dma_store_src_base_addr,
    input  logic [ADDR_WIDTH-1:0]     dma_store_dst_base_addr,
    input  logic [31:0]               dma_store_byte_count,

    output logic                      dma_store_busy,
    output logic                      dma_store_done,
    output logic                      dma_store_error,

    // ------------------------------------------------------------
    // AXI-Stream preload control
    //
    // Usage:
    //   1. Pulse axis_load_start in dma_clk domain.
    //   2. axis_preload_engine reads source memory through
    //      axis_src_axi_ar/r.
    //   3. Data crosses AXI-Stream async FIFO into core_clk.
    //   4. Stream loader writes A/B payload into scratchpad Port1.
    //   5. Wait axis_load_done before launching GEMM.
    // ------------------------------------------------------------
    input  logic                      axis_load_start,
    input  logic [ADDR_WIDTH-1:0]     axis_src_base_addr,
    input  logic [ADDR_WIDTH-1:0]     axis_dst_base_addr,
    input  logic [31:0]               axis_load_beats,

    output logic                      axis_load_busy,
    output logic                      axis_load_done,
    output logic                      axis_load_error,

    // ------------------------------------------------------------
    // Direct-stream GEMM operand preload control
    //
    // ds_operand_sel:
    //   0 = operand A
    //   1 = operand B
    // ------------------------------------------------------------
    input  logic                      ds_load_start,
    input  logic [ADDR_WIDTH-1:0]     ds_src_base_addr,
    input  logic [ADDR_WIDTH-1:0]     ds_dst_base_addr,
    input  logic [31:0]               ds_load_beats,
    input  logic                      ds_operand_sel,

    output logic                      ds_load_busy,
    output logic                      ds_load_done,
    output logic                      ds_load_error,

    // ------------------------------------------------------------
    // DMA source AXI-MM read master port
    //
    // This is the source side used by dma_load_engine.
    // In TB, connect this to a source memory/read responder.
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
    //
    // This source side is used by axis_preload_engine / axi_mm2s_dma.
    // In TB, this can reuse the same source memory contents as the
    // existing DMA load source memory model.
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
    // Direct-stream preload source AXI-MM read master port
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
    // DMA destination AXI-MM write master port
    //
    // This is the destination side used by dma_store_engine.
    // In TB, connect this to a destination memory/write responder.
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
    // Accelerator control
    //
    // External acc_start/config are treated as dma_clk-domain
    // control inputs.
    //
    // acc_busy / acc_done are reported back in dma_clk domain.
    // ------------------------------------------------------------
    input  logic                      gemm_input_stream_mode,

    input  logic                      acc_start,
    output logic                      acc_busy,
    output logic                      acc_done,

    input  logic [ADDR_WIDTH-1:0]     base_addr_a,
    input  logic [ADDR_WIDTH-1:0]     base_addr_b,
    input  logic [ADDR_WIDTH-1:0]     base_addr_c,

    input  logic [GEMM_DIM_WIDTH-1:0] dim_m,
    input  logic [GEMM_DIM_WIDTH-1:0] dim_n,
    input  logic [GEMM_DIM_WIDTH-1:0] dim_k,

    // ------------------------------------------------------------
    // GEMM performance counters
    //
    // Core-clock-domain snapshots.
    // Values are cleared on accepted GEMM start and remain stable
    // after GEMM done until the next accepted start.
    // ------------------------------------------------------------
    output logic [31:0]               gemm_perf_busy_cycles,
    output logic [31:0]               gemm_perf_mac_count,
    output logic [31:0]               gemm_perf_output_count
);

    // ============================================================
    // Internal AXI-MM interface for BRAM Port0
    //   Port0 owner mux output -> BRAM port0 slave
    // ============================================================
    axi_mm_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .HAS_BURST  (1)
    ) bram_axi0_if (
        .clk   (dma_clk),
        .rst_n (dma_rst_n)
    );

    // ============================================================
    // Internal AXI-MM interface for BRAM Port1
    //   Port1 owner mux output -> BRAM port1 slave
    // ============================================================
    axi_mm_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .HAS_BURST  (1)
    ) axi1_if (
        .clk   (core_clk),
        .rst_n (core_rst_n)
    );

    // ============================================================
    // Internal AXI-MM interface for GEMM adapter
    //   GEMM scratchpad adapter master -> Port1 owner mux GEMM input
    // ============================================================
    axi_mm_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .HAS_BURST  (1)
    ) gemm_axi1_if (
        .clk   (core_clk),
        .rst_n (core_rst_n)
    );

    // ============================================================
    // Observation interfaces from BRAM
    // ============================================================
    axi_mm_apply_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .BEAT_IDX_W (APPLY_BEAT_IDX_W)
    ) apply_if (
        .clk   (dma_clk),
        .rst_n (dma_rst_n)
    );

    axi_mm_commit_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .BEAT_IDX_W (COMMIT_BEAT_IDX_W)
    ) commit_if (
        .clk   (dma_clk),
        .rst_n (dma_rst_n)
    );

    // ============================================================
    // BRAM commit-engine idle
    // ============================================================
    logic ce_idle;

    // ============================================================
    // DMA load engine internal wires
    // ============================================================
    logic dma_load_busy_i;
    logic dma_load_done_i;
    logic dma_load_error_i;

    assign dma_load_busy  = dma_load_busy_i;
    assign dma_load_done  = dma_load_done_i;
    assign dma_load_error = dma_load_error_i;

    logic [31:0] dma_loader_accepted_beats;
    logic [31:0] dma_loader_written_beats;
    logic        dma_loader_tlast_seen;

    logic [31:0] dma_adapter_accepted_beats;
    logic [31:0] dma_adapter_committed_beats;
    logic        dma_adapter_last_beat_seen;

    logic        dma_done_seen;
    logic        dma_loader_done_seen;
    logic        dma_adapter_done_seen;

    // ------------------------------------------------------------
    // DMA load engine -> scratchpad Port0 write path
    // ------------------------------------------------------------
    logic [ID_WIDTH-1:0]       dma_spad_awid;
    logic [ADDR_WIDTH-1:0]     dma_spad_awaddr;
    logic [7:0]                dma_spad_awlen;
    logic [2:0]                dma_spad_awsize;
    logic [1:0]                dma_spad_awburst;
    logic                      dma_spad_awvalid;
    logic                      dma_spad_awready;

    logic [DATA_WIDTH-1:0]     dma_spad_wdata;
    logic [DATA_WIDTH/8-1:0]   dma_spad_wstrb;
    logic                      dma_spad_wlast;
    logic                      dma_spad_wvalid;
    logic                      dma_spad_wready;

    logic [ID_WIDTH-1:0]       dma_spad_bid;
    logic [1:0]                dma_spad_bresp;
    logic                      dma_spad_bvalid;
    logic                      dma_spad_bready;

    // ============================================================
    // DMA store engine internal wires
    // ============================================================
    logic dma_store_busy_i;
    logic dma_store_done_i;
    logic dma_store_error_i;

    assign dma_store_busy  = dma_store_busy_i;
    assign dma_store_done  = dma_store_done_i;
    assign dma_store_error = dma_store_error_i;

    logic [31:0] dma_store_read_beats;
    logic [31:0] dma_store_write_beats;
    logic [31:0] dma_store_committed_beats;
    logic        dma_store_last_beat_seen;

    // ------------------------------------------------------------
    // DMA store engine -> scratchpad Port0 read path
    // ------------------------------------------------------------
    logic [ID_WIDTH-1:0]       dma_store_spad_arid;
    logic [ADDR_WIDTH-1:0]     dma_store_spad_araddr;
    logic [7:0]                dma_store_spad_arlen;
    logic [2:0]                dma_store_spad_arsize;
    logic [1:0]                dma_store_spad_arburst;
    logic                      dma_store_spad_arvalid;
    logic                      dma_store_spad_arready;

    logic [ID_WIDTH-1:0]       dma_store_spad_rid;
    logic [DATA_WIDTH-1:0]     dma_store_spad_rdata;
    logic [1:0]                dma_store_spad_rresp;
    logic                      dma_store_spad_rlast;
    logic                      dma_store_spad_rvalid;
    logic                      dma_store_spad_rready;

    // ============================================================
    // AXI-Stream preload internal wires
    // ============================================================
    logic axis_load_busy_i;
    logic axis_load_done_i;
    logic axis_load_error_i;

    assign axis_load_busy  = axis_load_busy_i;
    assign axis_load_done  = axis_load_done_i;
    assign axis_load_error = axis_load_error_i;

    logic axis_stream_load_active;

    logic axis_fifo_full;
    logic axis_fifo_empty;
    logic [4:0] axis_fifo_wr_level;
    logic [4:0] axis_fifo_rd_level;

    logic [31:0] axis_loader_accepted_beats;
    logic [31:0] axis_loader_written_beats;
    logic        axis_loader_tlast_seen;

    logic [31:0] axis_adapter_accepted_writes;
    logic [31:0] axis_adapter_completed_writes;

    // ------------------------------------------------------------
    // AXI-Stream preload engine -> scratchpad Port1 write path
    // ------------------------------------------------------------
    logic [ID_WIDTH-1:0]       axis_spad_awid;
    logic [ADDR_WIDTH-1:0]     axis_spad_awaddr;
    logic [7:0]                axis_spad_awlen;
    logic [2:0]                axis_spad_awsize;
    logic [1:0]                axis_spad_awburst;
    logic                      axis_spad_awvalid;
    logic                      axis_spad_awready;

    logic [DATA_WIDTH-1:0]     axis_spad_wdata;
    logic [DATA_WIDTH/8-1:0]   axis_spad_wstrb;
    logic                      axis_spad_wlast;
    logic                      axis_spad_wvalid;
    logic                      axis_spad_wready;

    logic [ID_WIDTH-1:0]       axis_spad_bid;
    logic [1:0]                axis_spad_bresp;
    logic                      axis_spad_bvalid;
    logic                      axis_spad_bready;

    // ============================================================
    // Direct-stream preload internal wires
    // ============================================================
    logic ds_load_busy_i;
    logic ds_load_done_i;
    logic ds_load_error_i;

    assign ds_load_busy  = ds_load_busy_i;
    assign ds_load_done  = ds_load_done_i;
    assign ds_load_error = ds_load_error_i;

    logic direct_stream_load_active;

    logic ds_fifo_full;
    logic ds_fifo_empty;
    logic [4:0] ds_fifo_wr_level;
    logic [4:0] ds_fifo_rd_level;

    logic [31:0] ds_loader_accepted_beats;
    logic [31:0] ds_loader_written_beats;
    logic        ds_loader_tlast_seen;

    logic [31:0] ds_adapter_accepted_writes;
    logic [31:0] ds_adapter_forwarded_writes;
    logic [31:0] ds_adapter_dropped_writes;

    logic        ds_operand_buf_clear_a;
    logic        ds_operand_buf_clear_b;
    logic        ds_operand_buf_clear_status;

    // Direct-stream preload engine -> operand buffer write path
    logic                         ds_buf_wr_valid;
    logic                         ds_buf_wr_ready;
    logic                         ds_buf_wr_operand_sel;
    logic [ADDR_WIDTH-1:0]        ds_buf_wr_addr;
    logic [DATA_WIDTH-1:0]        ds_buf_wr_data;
    logic [DATA_WIDTH/8-1:0]      ds_buf_wr_strb;
    logic                         ds_buf_wr_last;

    // Operand buffer -> GEMM input router read path
    logic                         op_rd_valid;
    logic                         op_rd_ready;
    logic                         op_rd_operand_sel;
    logic [ADDR_WIDTH-1:0]        op_rd_addr;
    logic [31:0]                  op_rd_data;
    logic                         op_rd_data_valid;

    // Operand buffer status
    logic                         ds_a_loaded;
    logic                         ds_b_loaded;

    logic [31:0]                  ds_a_written_beats;
    logic [31:0]                  ds_b_written_beats;
    logic [31:0]                  ds_operand_buffer_read_count;

    logic                         ds_buf_wr_accept_pulse;
    logic                         ds_buf_rd_accept_pulse;
    logic                         ds_buf_write_error_pulse;
    logic                         ds_buf_read_error_pulse;
    logic                         ds_operand_buffer_error;

    // GEMM input memory router status
    logic                         gemm_router_busy;
    logic                         gemm_router_error_pulse;
    logic                         gemm_router_error;

    logic [31:0]                  gemm_router_op_read_count;
    logic [31:0]                  gemm_router_sp_read_count;
    logic [31:0]                  gemm_router_sp_write_count;
    logic [31:0]                  gemm_router_invalid_read_count;
    logic [31:0]                  gemm_router_simultaneous_req_count;

    // GEMM input router -> scratchpad adapter local-memory side
    logic                         sp_mem_req_ready;

    logic                         sp_mem_rd_en;
    logic [ADDR_WIDTH-1:0]        sp_mem_rd_addr;
    logic [31:0]                  sp_mem_rd_data;
    logic                         sp_mem_rd_valid;

    logic                         sp_mem_wr_en;
    logic [ADDR_WIDTH-1:0]        sp_mem_wr_addr;
    logic [31:0]                  sp_mem_wr_data;
    logic [3:0]                   sp_mem_wr_strb;

    // ------------------------------------------------------------
    // Scratchpad Port1 owner mux status
    // ------------------------------------------------------------
    logic port1_owner_stream;
    logic port1_owner_gemm;
    logic port1_illegal_overlap;

    // ------------------------------------------------------------
    // Port0 owner select
    //
    // Phase-based ownership:
    //   dma_load_busy_i  = 0 and dma_store_busy_i = 0 -> Host owns Port0
    //   dma_load_busy_i  = 1 and dma_store_busy_i = 0 -> DMA load owns Port0
    //   dma_load_busy_i  = 0 and dma_store_busy_i = 1 -> DMA store owns Port0
    //
    // Requirement:
    //   Do not issue host transactions while dma_load_busy or
    //   dma_store_busy is high.
    // ------------------------------------------------------------
    logic port0_select_dma;
    logic port0_select_dma_store;

    assign port0_select_dma       = dma_load_busy_i;
    assign port0_select_dma_store = dma_store_busy_i;

`ifndef SYNTHESIS
    always_comb begin
        if (dma_load_busy_i && dma_store_busy_i) begin
            $error("ai_accel_subsys: dma_load_busy_i and dma_store_busy_i are both asserted");
        end
    end
`endif

    // ============================================================
    // Accelerator control CDC
    //
    // External acc_start/config are considered dma_clk-domain.
    //
    // Flow:
    //   dma_clk:
    //     - detect acc_start rising edge
    //     - capture config bus
    //     - toggle start event
    //
    //   core_clk:
    //     - synchronize start toggle
    //     - generate one-cycle gemm_start_core pulse
    //     - latch captured config into core-domain registers
    //
    // Notes:
    //   This is a bundled-data style CDC for configuration.
    //   The config registers are captured in dma_clk before the
    //   start event reaches core_clk. The source config registers
    //   must remain stable until the start event is sampled in
    //   core_clk. Current software/testbench sequencing satisfies
    //   this because config is only changed between GEMM jobs.
    //
    // AXI-Stream preload rule:
    //   GEMM start is accepted only when axis_load_busy_i is low.
    //   This prevents GEMM from taking Port1 while stream preload
    //   still owns Port1.
    // ============================================================

    // ------------------------------------------------------------
    // dma_clk side: acc_start rising-edge detect
    // ------------------------------------------------------------
    logic acc_start_dma_q;
    logic acc_start_pulse_dma;
    logic acc_start_pulse_dma_accepted;

    assign acc_start_pulse_dma = acc_start & ~acc_start_dma_q;

    assign acc_start_pulse_dma_accepted =
        acc_start_pulse_dma &&
        !axis_load_busy_i   &&
        !ds_load_busy_i;

    always_ff @(posedge dma_clk or negedge dma_rst_n) begin
        if (!dma_rst_n) begin
            acc_start_dma_q <= 1'b0;
        end
        else begin
            acc_start_dma_q <= acc_start;
        end
    end

    // ------------------------------------------------------------
    // dma_clk side: captured GEMM configuration
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0]     base_addr_a_dma_q;
    logic [ADDR_WIDTH-1:0]     base_addr_b_dma_q;
    logic [ADDR_WIDTH-1:0]     base_addr_c_dma_q;

    logic [GEMM_DIM_WIDTH-1:0] dim_m_dma_q;
    logic [GEMM_DIM_WIDTH-1:0] dim_n_dma_q;
    logic [GEMM_DIM_WIDTH-1:0] dim_k_dma_q;

    logic                      gemm_input_stream_mode_dma_q;

    logic                      start_toggle_dma_q;

    always_ff @(posedge dma_clk or negedge dma_rst_n) begin
        if (!dma_rst_n) begin
            base_addr_a_dma_q <= '0;
            base_addr_b_dma_q <= '0;
            base_addr_c_dma_q <= '0;

            dim_m_dma_q       <= '0;
            dim_n_dma_q       <= '0;
            dim_k_dma_q       <= '0;

            gemm_input_stream_mode_dma_q <= 1'b0;

            start_toggle_dma_q <= 1'b0;
        end
        else if (acc_start_pulse_dma_accepted) begin
            base_addr_a_dma_q <= base_addr_a;
            base_addr_b_dma_q <= base_addr_b;
            base_addr_c_dma_q <= base_addr_c;

            dim_m_dma_q       <= dim_m;
            dim_n_dma_q       <= dim_n;
            dim_k_dma_q       <= dim_k;

            gemm_input_stream_mode_dma_q <= gemm_input_stream_mode;

            start_toggle_dma_q <= ~start_toggle_dma_q;
        end
    end

    // ------------------------------------------------------------
    // core_clk side: start toggle synchronizer
    //
    // The armed flag prevents a false start pulse after reset when
    // the synchronized toggle value initializes to the current
    // source-domain toggle value.
    // ------------------------------------------------------------
    logic start_sync1_q;
    logic start_sync2_q;
    logic start_sync2_qq;
    logic start_sync_armed_q;

    logic gemm_start_core;

    always_ff @(posedge core_clk or negedge core_rst_n or negedge dma_rst_n) begin
        if (!core_rst_n || !dma_rst_n) begin
            start_sync1_q      <= 1'b0;
            start_sync2_q      <= 1'b0;
            start_sync2_qq     <= 1'b0;
            start_sync_armed_q <= 1'b0;
        end
        else if (!start_sync_armed_q) begin
            start_sync1_q      <= start_toggle_dma_q;
            start_sync2_q      <= start_toggle_dma_q;
            start_sync2_qq     <= start_toggle_dma_q;
            start_sync_armed_q <= 1'b1;
        end
        else begin
            start_sync1_q      <= start_toggle_dma_q;
            start_sync2_q      <= start_sync1_q;
            start_sync2_qq     <= start_sync2_q;
        end
    end

    assign gemm_start_core = start_sync_armed_q &&
                             (start_sync2_q ^ start_sync2_qq);

    // ------------------------------------------------------------
    // core_clk side: latched GEMM configuration
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0]     base_addr_a_core_q;
    logic [ADDR_WIDTH-1:0]     base_addr_b_core_q;
    logic [ADDR_WIDTH-1:0]     base_addr_c_core_q;

    logic [GEMM_DIM_WIDTH-1:0] dim_m_core_q;
    logic [GEMM_DIM_WIDTH-1:0] dim_n_core_q;
    logic [GEMM_DIM_WIDTH-1:0] dim_k_core_q;

    logic                      gemm_input_stream_mode_core_q;

    always_ff @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            base_addr_a_core_q <= '0;
            base_addr_b_core_q <= '0;
            base_addr_c_core_q <= '0;

            dim_m_core_q       <= '0;
            dim_n_core_q       <= '0;
            dim_k_core_q       <= '0;

            gemm_input_stream_mode_core_q <= 1'b0;
        end
        else if (gemm_start_core) begin
            base_addr_a_core_q <= base_addr_a_dma_q;
            base_addr_b_core_q <= base_addr_b_dma_q;
            base_addr_c_core_q <= base_addr_c_dma_q;

            dim_m_core_q       <= dim_m_dma_q;
            dim_n_core_q       <= dim_n_dma_q;
            dim_k_core_q       <= dim_k_dma_q;

            gemm_input_stream_mode_core_q <= gemm_input_stream_mode_dma_q;
        end
    end

    // ============================================================
    // Direct-stream operand region size calculation
    //
    // GEMM A/B are compact int8 matrices in current baseline:
    //   A_bytes = M * K * (GEMM_A_WIDTH / 8)
    //   B_bytes = K * N * (GEMM_B_WIDTH / 8)
    //
    // Router uses padded byte regions so final stream beat padding
    // is considered valid address space.
    // ============================================================
    logic [31:0] direct_a_bytes_core;
    logic [31:0] direct_b_bytes_core;
    logic [31:0] direct_a_region_bytes_core;
    logic [31:0] direct_b_region_bytes_core;

    function automatic logic [31:0] round_up_to_data_beat(
        input logic [31:0] byte_count
    );
        logic [31:0] beat_bytes;
        logic [31:0] rem;
    begin
        beat_bytes = 32'(DATA_WIDTH / 8);
        rem        = byte_count % beat_bytes;

        if (byte_count == 0) begin
            round_up_to_data_beat = 32'd0;
        end
        else if (rem == 0) begin
            round_up_to_data_beat = byte_count;
        end
        else begin
            round_up_to_data_beat = byte_count + beat_bytes - rem;
        end
    end
    endfunction

    always_comb begin
        direct_a_bytes_core =
            32'(int'(dim_m_core_q) * int'(dim_k_core_q) * (GEMM_A_WIDTH / 8));

        direct_b_bytes_core =
            32'(int'(dim_k_core_q) * int'(dim_n_core_q) * (GEMM_B_WIDTH / 8));

        direct_a_region_bytes_core = round_up_to_data_beat(direct_a_bytes_core);
        direct_b_region_bytes_core = round_up_to_data_beat(direct_b_bytes_core);
    end

    // ============================================================
    // GEMM <-> local memory interface
    // ============================================================
    logic                     gemm_busy_core;
    logic                     gemm_done_core;

    logic                     gemm_mem_req_ready;

    logic                     gemm_mem_rd_en;
    logic [ADDR_WIDTH-1:0]    gemm_mem_rd_addr;
    logic [31:0]              gemm_mem_rd_data;
    logic                     gemm_mem_rd_valid;

    logic                     gemm_mem_wr_en;
    logic [ADDR_WIDTH-1:0]    gemm_mem_wr_addr;
    logic [31:0]              gemm_mem_wr_data;
    logic [3:0]               gemm_mem_wr_strb;

    // ============================================================
    // GEMM scratchpad adapter status
    // ============================================================
    logic                     gemm_mem_busy;
    logic                     gemm_mem_done;

    // ============================================================
    // Core-domain accelerator done generation
    //
    // GEMM core done means computation FSM is done.
    // Subsystem done is delayed until the scratchpad adapter is no
    // longer busy, so C writeback is fully complete from the local
    // adapter point of view.
    // ============================================================
    logic                     gemm_done_core_q;
    logic                     gemm_done_pulse_core;

    logic                     acc_done_pending_core_q;
    logic                     acc_done_core_pulse_q;
    logic                     acc_done_toggle_core_q;

    logic                     acc_busy_core;

    always_ff @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            gemm_done_core_q <= 1'b0;
        end
        else begin
            gemm_done_core_q <= gemm_done_core;
        end
    end

    assign gemm_done_pulse_core = gemm_done_core & ~gemm_done_core_q;

    always_ff @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            acc_done_pending_core_q <= 1'b0;
            acc_done_core_pulse_q   <= 1'b0;
            acc_done_toggle_core_q  <= 1'b0;
        end
        else begin
            // default: pulse only one core_clk cycle
            acc_done_core_pulse_q <= 1'b0;

            // latch the fact that GEMM core finished
            if (gemm_done_pulse_core) begin
                acc_done_pending_core_q <= 1'b1;
            end

            // once adapter is no longer busy, emit subsystem done pulse
            if (acc_done_pending_core_q && !gemm_mem_busy && !gemm_router_busy) begin
                acc_done_core_pulse_q   <= 1'b1;
                acc_done_pending_core_q <= 1'b0;
                acc_done_toggle_core_q  <= ~acc_done_toggle_core_q;
            end
        end
    end

    assign acc_busy_core = gemm_busy_core | gemm_mem_busy | gemm_router_busy;

    // ============================================================
    // Accelerator status CDC back to dma_clk
    //
    // acc_busy:
    //   core_clk level -> dma_clk 2FF synchronizer
    //
    // acc_done:
    //   core_clk pulse -> toggle -> dma_clk pulse
    //
    // The done armed flag prevents a false done pulse after reset
    // when the destination synchronizer initializes to the current
    // source-domain toggle value.
    // ============================================================
    logic acc_busy_sync1_dma_q;
    logic acc_busy_sync2_dma_q;

    logic done_sync1_dma_q;
    logic done_sync2_dma_q;
    logic done_sync2_dma_qq;
    logic done_sync_armed_dma_q;

    logic acc_done_dma_pulse;

    always_ff @(posedge dma_clk or negedge dma_rst_n or negedge core_rst_n) begin
        if (!dma_rst_n || !core_rst_n) begin
            acc_busy_sync1_dma_q <= 1'b0;
            acc_busy_sync2_dma_q <= 1'b0;
        end
        else begin
            acc_busy_sync1_dma_q <= acc_busy_core;
            acc_busy_sync2_dma_q <= acc_busy_sync1_dma_q;
        end
    end

    always_ff @(posedge dma_clk or negedge dma_rst_n or negedge core_rst_n) begin
        if (!dma_rst_n || !core_rst_n) begin
            done_sync1_dma_q      <= 1'b0;
            done_sync2_dma_q      <= 1'b0;
            done_sync2_dma_qq     <= 1'b0;
            done_sync_armed_dma_q <= 1'b0;
        end
        else if (!done_sync_armed_dma_q) begin
            done_sync1_dma_q      <= acc_done_toggle_core_q;
            done_sync2_dma_q      <= acc_done_toggle_core_q;
            done_sync2_dma_qq     <= acc_done_toggle_core_q;
            done_sync_armed_dma_q <= 1'b1;
        end
        else begin
            done_sync1_dma_q      <= acc_done_toggle_core_q;
            done_sync2_dma_q      <= done_sync1_dma_q;
            done_sync2_dma_qq     <= done_sync2_dma_q;
        end
    end

    assign acc_done_dma_pulse = done_sync_armed_dma_q &&
                                (done_sync2_dma_q ^ done_sync2_dma_qq);

    assign acc_busy = acc_busy_sync2_dma_q;
    assign acc_done = acc_done_dma_pulse;

    // ============================================================
    // DMA load engine
    // ============================================================
    dma_load_engine #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .AXI_ID_WIDTH (ID_WIDTH),
        .DMA_ARID     ('0),
        .ADAPTER_AWID ('0)
    ) u_dma_load_engine (
        .clk                    (dma_clk),
        .rst_n                  (dma_rst_n),

        .load_start             (dma_load_start),
        .src_base_addr          (dma_src_base_addr),
        .dst_base_addr          (dma_dst_base_addr),
        .load_beats             (dma_load_beats),

        .load_busy              (dma_load_busy_i),
        .load_done              (dma_load_done_i),
        .load_error             (dma_load_error_i),

        .loader_accepted_beats  (dma_loader_accepted_beats),
        .loader_written_beats   (dma_loader_written_beats),
        .loader_tlast_seen      (dma_loader_tlast_seen),

        .adapter_accepted_beats (dma_adapter_accepted_beats),
        .adapter_committed_beats(dma_adapter_committed_beats),
        .adapter_last_beat_seen (dma_adapter_last_beat_seen),

        .dma_done_seen          (dma_done_seen),
        .loader_done_seen       (dma_loader_done_seen),
        .adapter_done_seen      (dma_adapter_done_seen),

        // Source AXI-MM read master
        .src_axi_arid           (dma_src_axi_arid),
        .src_axi_araddr         (dma_src_axi_araddr),
        .src_axi_arlen          (dma_src_axi_arlen),
        .src_axi_arsize         (dma_src_axi_arsize),
        .src_axi_arburst        (dma_src_axi_arburst),
        .src_axi_arvalid        (dma_src_axi_arvalid),
        .src_axi_arready        (dma_src_axi_arready),

        .src_axi_rid            (dma_src_axi_rid),
        .src_axi_rdata          (dma_src_axi_rdata),
        .src_axi_rresp          (dma_src_axi_rresp),
        .src_axi_rlast          (dma_src_axi_rlast),
        .src_axi_rvalid         (dma_src_axi_rvalid),
        .src_axi_rready         (dma_src_axi_rready),

        // Scratchpad AXI-MM write master
        .spad_axi_awid          (dma_spad_awid),
        .spad_axi_awaddr        (dma_spad_awaddr),
        .spad_axi_awlen         (dma_spad_awlen),
        .spad_axi_awsize        (dma_spad_awsize),
        .spad_axi_awburst       (dma_spad_awburst),
        .spad_axi_awvalid       (dma_spad_awvalid),
        .spad_axi_awready       (dma_spad_awready),

        .spad_axi_wdata         (dma_spad_wdata),
        .spad_axi_wstrb         (dma_spad_wstrb),
        .spad_axi_wlast         (dma_spad_wlast),
        .spad_axi_wvalid        (dma_spad_wvalid),
        .spad_axi_wready        (dma_spad_wready),

        .spad_axi_bid           (dma_spad_bid),
        .spad_axi_bresp         (dma_spad_bresp),
        .spad_axi_bvalid        (dma_spad_bvalid),
        .spad_axi_bready        (dma_spad_bready)
    );

    // ============================================================
    // DMA store engine
    //
    // Reads C data from scratchpad Port0 and writes it to the
    // destination AXI-MM memory model.
    // ============================================================
    dma_store_engine #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .AXI_ID_WIDTH (ID_WIDTH),
        .SPAD_ARID    ('0),
        .DST_AWID     ('0)
    ) u_dma_store_engine (
        .clk                    (dma_clk),
        .rst_n                  (dma_rst_n),

        .store_start            (dma_store_start),
        .src_base_addr          (dma_store_src_base_addr),
        .dst_base_addr          (dma_store_dst_base_addr),
        .store_byte_count       (dma_store_byte_count),

        .store_busy             (dma_store_busy_i),
        .store_done             (dma_store_done_i),
        .store_error            (dma_store_error_i),

        .read_beats             (dma_store_read_beats),
        .write_beats            (dma_store_write_beats),
        .committed_beats        (dma_store_committed_beats),
        .last_beat_seen         (dma_store_last_beat_seen),

        // Scratchpad AXI-MM read master
        .spad_axi_arid          (dma_store_spad_arid),
        .spad_axi_araddr        (dma_store_spad_araddr),
        .spad_axi_arlen         (dma_store_spad_arlen),
        .spad_axi_arsize        (dma_store_spad_arsize),
        .spad_axi_arburst       (dma_store_spad_arburst),
        .spad_axi_arvalid       (dma_store_spad_arvalid),
        .spad_axi_arready       (dma_store_spad_arready),

        .spad_axi_rid           (dma_store_spad_rid),
        .spad_axi_rdata         (dma_store_spad_rdata),
        .spad_axi_rresp         (dma_store_spad_rresp),
        .spad_axi_rlast         (dma_store_spad_rlast),
        .spad_axi_rvalid        (dma_store_spad_rvalid),
        .spad_axi_rready        (dma_store_spad_rready),

        // Destination AXI-MM write master
        .dst_axi_awid           (dma_dst_axi_awid),
        .dst_axi_awaddr         (dma_dst_axi_awaddr),
        .dst_axi_awlen          (dma_dst_axi_awlen),
        .dst_axi_awsize         (dma_dst_axi_awsize),
        .dst_axi_awburst        (dma_dst_axi_awburst),
        .dst_axi_awvalid        (dma_dst_axi_awvalid),
        .dst_axi_awready        (dma_dst_axi_awready),

        .dst_axi_wdata          (dma_dst_axi_wdata),
        .dst_axi_wstrb          (dma_dst_axi_wstrb),
        .dst_axi_wlast          (dma_dst_axi_wlast),
        .dst_axi_wvalid         (dma_dst_axi_wvalid),
        .dst_axi_wready         (dma_dst_axi_wready),

        .dst_axi_bid            (dma_dst_axi_bid),
        .dst_axi_bresp          (dma_dst_axi_bresp),
        .dst_axi_bvalid         (dma_dst_axi_bvalid),
        .dst_axi_bready         (dma_dst_axi_bready)
    );

    // ============================================================
    // AXI-Stream preload engine
    //
    // Source AXI-MM read -> AXI-Stream FIFO -> stream loader
    // -> scratchpad Port1 write path.
    // ============================================================
    axis_preload_engine #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .DATA_WIDTH      (DATA_WIDTH),
        .ID_WIDTH        (ID_WIDTH),
        .AXIS_FIFO_DEPTH (16),
        .CAPTURE_DEPTH   (1024),
        .AXI_SRC_ARID    ('0),
        .AXI_SP_AWID     ('0)
    ) u_axis_preload_engine (
        .dma_clk                   (dma_clk),
        .dma_rst_n                 (dma_rst_n),
        .core_clk                  (core_clk),
        .core_rst_n                (core_rst_n),

        .axis_load_start           (axis_load_start),
        .axis_src_base_addr        (axis_src_base_addr),
        .axis_dst_base_addr        (axis_dst_base_addr),
        .axis_load_beats           (axis_load_beats),

        .axis_load_busy            (axis_load_busy_i),
        .axis_load_done            (axis_load_done_i),
        .axis_load_error           (axis_load_error_i),

        // AXI-MM source read master
        .axis_src_axi_arid         (axis_src_axi_arid),
        .axis_src_axi_araddr       (axis_src_axi_araddr),
        .axis_src_axi_arlen        (axis_src_axi_arlen),
        .axis_src_axi_arsize       (axis_src_axi_arsize),
        .axis_src_axi_arburst      (axis_src_axi_arburst),
        .axis_src_axi_arvalid      (axis_src_axi_arvalid),
        .axis_src_axi_arready      (axis_src_axi_arready),

        .axis_src_axi_rid          (axis_src_axi_rid),
        .axis_src_axi_rdata        (axis_src_axi_rdata),
        .axis_src_axi_rresp        (axis_src_axi_rresp),
        .axis_src_axi_rlast        (axis_src_axi_rlast),
        .axis_src_axi_rvalid       (axis_src_axi_rvalid),
        .axis_src_axi_rready       (axis_src_axi_rready),

        // Scratchpad Port1 write master side
        .sp_axi_awid               (axis_spad_awid),
        .sp_axi_awaddr             (axis_spad_awaddr),
        .sp_axi_awlen              (axis_spad_awlen),
        .sp_axi_awsize             (axis_spad_awsize),
        .sp_axi_awburst            (axis_spad_awburst),
        .sp_axi_awvalid            (axis_spad_awvalid),
        .sp_axi_awready            (axis_spad_awready),

        .sp_axi_wdata              (axis_spad_wdata),
        .sp_axi_wstrb              (axis_spad_wstrb),
        .sp_axi_wlast              (axis_spad_wlast),
        .sp_axi_wvalid             (axis_spad_wvalid),
        .sp_axi_wready             (axis_spad_wready),

        .sp_axi_bid                (axis_spad_bid),
        .sp_axi_bresp              (axis_spad_bresp),
        .sp_axi_bvalid             (axis_spad_bvalid),
        .sp_axi_bready             (axis_spad_bready),

        .stream_load_active        (axis_stream_load_active),

        .axis_fifo_full            (axis_fifo_full),
        .axis_fifo_empty           (axis_fifo_empty),
        .axis_fifo_wr_level        (axis_fifo_wr_level),
        .axis_fifo_rd_level        (axis_fifo_rd_level),

        .loader_accepted_beats     (axis_loader_accepted_beats),
        .loader_written_beats      (axis_loader_written_beats),
        .loader_tlast_seen         (axis_loader_tlast_seen),

        .adapter_accepted_writes   (axis_adapter_accepted_writes),
        .adapter_completed_writes  (axis_adapter_completed_writes)
    );

    // ============================================================
    // Direct-stream preload engine
    //
    // Source AXI-MM read -> AXI-Stream FIFO -> stream loader
    // -> operand buffer write adapter -> gemm_operand_buffer.
    //
    // This path does not write A/B into scratchpad.
    // It fills local operand buffers for direct-stream GEMM input.
    // ============================================================
    direct_stream_preload_engine #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .DATA_WIDTH      (DATA_WIDTH),
        .ID_WIDTH        (ID_WIDTH),
        .AXIS_FIFO_DEPTH (16),
        .CAPTURE_DEPTH   (1024),
        .AXI_SRC_ARID    ('0)
    ) u_direct_stream_preload_engine (
        .dma_clk                    (dma_clk),
        .dma_rst_n                  (dma_rst_n),
        .core_clk                   (core_clk),
        .core_rst_n                 (core_rst_n),

        .ds_load_start              (ds_load_start),
        .ds_src_base_addr           (ds_src_base_addr),
        .ds_dst_base_addr           (ds_dst_base_addr),
        .ds_load_beats              (ds_load_beats),
        .ds_operand_sel             (ds_operand_sel),

        .ds_load_busy               (ds_load_busy_i),
        .ds_load_done               (ds_load_done_i),
        .ds_load_error              (ds_load_error_i),

        // AXI-MM source read master
        .ds_src_axi_arid            (ds_src_axi_arid),
        .ds_src_axi_araddr          (ds_src_axi_araddr),
        .ds_src_axi_arlen           (ds_src_axi_arlen),
        .ds_src_axi_arsize          (ds_src_axi_arsize),
        .ds_src_axi_arburst         (ds_src_axi_arburst),
        .ds_src_axi_arvalid         (ds_src_axi_arvalid),
        .ds_src_axi_arready         (ds_src_axi_arready),

        .ds_src_axi_rid             (ds_src_axi_rid),
        .ds_src_axi_rdata           (ds_src_axi_rdata),
        .ds_src_axi_rresp           (ds_src_axi_rresp),
        .ds_src_axi_rlast           (ds_src_axi_rlast),
        .ds_src_axi_rvalid          (ds_src_axi_rvalid),
        .ds_src_axi_rready          (ds_src_axi_rready),

        // Operand buffer clear controls
        .operand_buf_clear_a        (ds_operand_buf_clear_a),
        .operand_buf_clear_b        (ds_operand_buf_clear_b),
        .operand_buf_clear_status   (ds_operand_buf_clear_status),

        // Operand buffer write port
        .buf_wr_valid               (ds_buf_wr_valid),
        .buf_wr_ready               (ds_buf_wr_ready),
        .buf_wr_operand_sel         (ds_buf_wr_operand_sel),
        .buf_wr_addr                (ds_buf_wr_addr),
        .buf_wr_data                (ds_buf_wr_data),
        .buf_wr_strb                (ds_buf_wr_strb),
        .buf_wr_last                (ds_buf_wr_last),

        .operand_buf_error          (ds_operand_buffer_error),
        .operand_buf_write_error_pulse(ds_buf_write_error_pulse),

        .direct_stream_load_active  (direct_stream_load_active),

        .axis_fifo_full             (ds_fifo_full),
        .axis_fifo_empty            (ds_fifo_empty),
        .axis_fifo_wr_level         (ds_fifo_wr_level),
        .axis_fifo_rd_level         (ds_fifo_rd_level),

        .loader_accepted_beats      (ds_loader_accepted_beats),
        .loader_written_beats       (ds_loader_written_beats),
        .loader_tlast_seen          (ds_loader_tlast_seen),

        .adapter_accepted_writes    (ds_adapter_accepted_writes),
        .adapter_forwarded_writes   (ds_adapter_forwarded_writes),
        .adapter_dropped_writes     (ds_adapter_dropped_writes)
    );

    // ============================================================
    // Direct-stream GEMM operand buffer
    //
    // Holds streamed A/B operand payloads.
    // GEMM reads A/B from this buffer in direct-stream mode.
    // ============================================================
    gemm_operand_buffer #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .WR_DATA_WIDTH  (DATA_WIDTH),
        .RD_DATA_WIDTH  (32),
        .A_BUFFER_BYTES (1024),
        .B_BUFFER_BYTES (1024)
    ) u_gemm_operand_buffer (
        .clk                (core_clk),
        .rst_n              (core_rst_n),

        .clear_all          (1'b0),
        .clear_a            (ds_operand_buf_clear_a),
        .clear_b            (ds_operand_buf_clear_b),
        .clear_status       (ds_operand_buf_clear_status),

        // Write side from direct-stream preload engine
        .wr_valid           (ds_buf_wr_valid),
        .wr_ready           (ds_buf_wr_ready),
        .wr_operand_sel     (ds_buf_wr_operand_sel),
        .wr_addr            (ds_buf_wr_addr),
        .wr_data            (ds_buf_wr_data),
        .wr_strb            (ds_buf_wr_strb),
        .wr_last            (ds_buf_wr_last),

        // Read side from GEMM input router
        .rd_valid           (op_rd_valid),
        .rd_ready           (op_rd_ready),
        .rd_operand_sel     (op_rd_operand_sel),
        .rd_addr            (op_rd_addr),
        .rd_data            (op_rd_data),
        .rd_data_valid      (op_rd_data_valid),

        .a_loaded           (ds_a_loaded),
        .b_loaded           (ds_b_loaded),

        .a_written_beats    (ds_a_written_beats),
        .b_written_beats    (ds_b_written_beats),

        .read_count         (ds_operand_buffer_read_count),

        .wr_accept_pulse    (ds_buf_wr_accept_pulse),
        .rd_accept_pulse    (ds_buf_rd_accept_pulse),

        .write_error_pulse  (ds_buf_write_error_pulse),
        .read_error_pulse   (ds_buf_read_error_pulse),

        .error              (ds_operand_buffer_error)
    );

    // ============================================================
    // Scratchpad Port0 owner mux
    //   Host axi0_if, DMA load engine, or DMA store engine
    //   -> BRAM Port0
    // ============================================================
    scratchpad_port0_owner_mux #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_scratchpad_port0_owner_mux (
        .select_dma        (port0_select_dma),
        .select_dma_store  (port0_select_dma_store),

        .host_axi_if       (axi0_if),
        .bram_axi_if       (bram_axi0_if),

        // DMA load write path
        .dma_awid          (dma_spad_awid),
        .dma_awaddr        (dma_spad_awaddr),
        .dma_awlen         (dma_spad_awlen),
        .dma_awsize        (dma_spad_awsize),
        .dma_awburst       (dma_spad_awburst),
        .dma_awvalid       (dma_spad_awvalid),
        .dma_awready       (dma_spad_awready),

        .dma_wdata         (dma_spad_wdata),
        .dma_wstrb         (dma_spad_wstrb),
        .dma_wlast         (dma_spad_wlast),
        .dma_wvalid        (dma_spad_wvalid),
        .dma_wready        (dma_spad_wready),

        .dma_bid           (dma_spad_bid),
        .dma_bresp         (dma_spad_bresp),
        .dma_bvalid        (dma_spad_bvalid),
        .dma_bready        (dma_spad_bready),

        // DMA store read path
        .dma_store_arid    (dma_store_spad_arid),
        .dma_store_araddr  (dma_store_spad_araddr),
        .dma_store_arlen   (dma_store_spad_arlen),
        .dma_store_arsize  (dma_store_spad_arsize),
        .dma_store_arburst (dma_store_spad_arburst),
        .dma_store_arvalid (dma_store_spad_arvalid),
        .dma_store_arready (dma_store_spad_arready),

        .dma_store_rid     (dma_store_spad_rid),
        .dma_store_rdata   (dma_store_spad_rdata),
        .dma_store_rresp   (dma_store_spad_rresp),
        .dma_store_rlast   (dma_store_spad_rlast),
        .dma_store_rvalid  (dma_store_spad_rvalid),
        .dma_store_rready  (dma_store_spad_rready)
    );

    // ============================================================
    // Scratchpad Port1 owner mux
    //   AXI-Stream preload engine or GEMM scratchpad adapter
    //   -> BRAM Port1
    // ============================================================
    scratchpad_port1_owner_mux #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_scratchpad_port1_owner_mux (
        .clk                (core_clk),
        .rst_n              (core_rst_n),

        .stream_load_active (axis_stream_load_active),
        .gemm_active        (acc_busy_core),

        .owner_stream       (port1_owner_stream),
        .owner_gemm         (port1_owner_gemm),
        .illegal_overlap    (port1_illegal_overlap),

        // STREAM_LOAD owner input
        .stream_awid        (axis_spad_awid),
        .stream_awaddr      (axis_spad_awaddr),
        .stream_awlen       (axis_spad_awlen),
        .stream_awsize      (axis_spad_awsize),
        .stream_awburst     (axis_spad_awburst),
        .stream_awvalid     (axis_spad_awvalid),
        .stream_awready     (axis_spad_awready),

        .stream_wdata       (axis_spad_wdata),
        .stream_wstrb       (axis_spad_wstrb),
        .stream_wlast       (axis_spad_wlast),
        .stream_wvalid      (axis_spad_wvalid),
        .stream_wready      (axis_spad_wready),

        .stream_bid         (axis_spad_bid),
        .stream_bresp       (axis_spad_bresp),
        .stream_bvalid      (axis_spad_bvalid),
        .stream_bready      (axis_spad_bready),

        // GEMM owner input
        .gemm_awid          (gemm_axi1_if.awid),
        .gemm_awaddr        (gemm_axi1_if.awaddr),
        .gemm_awlen         (gemm_axi1_if.awlen),
        .gemm_awsize        (gemm_axi1_if.awsize),
        .gemm_awburst       (gemm_axi1_if.awburst),
        .gemm_awvalid       (gemm_axi1_if.awvalid),
        .gemm_awready       (gemm_axi1_if.awready),

        .gemm_wdata         (gemm_axi1_if.wdata),
        .gemm_wstrb         (gemm_axi1_if.wstrb),
        .gemm_wlast         (gemm_axi1_if.wlast),
        .gemm_wvalid        (gemm_axi1_if.wvalid),
        .gemm_wready        (gemm_axi1_if.wready),

        .gemm_bid           (gemm_axi1_if.bid),
        .gemm_bresp         (gemm_axi1_if.bresp),
        .gemm_bvalid        (gemm_axi1_if.bvalid),
        .gemm_bready        (gemm_axi1_if.bready),

        .gemm_arid          (gemm_axi1_if.arid),
        .gemm_araddr        (gemm_axi1_if.araddr),
        .gemm_arlen         (gemm_axi1_if.arlen),
        .gemm_arsize        (gemm_axi1_if.arsize),
        .gemm_arburst       (gemm_axi1_if.arburst),
        .gemm_arvalid       (gemm_axi1_if.arvalid),
        .gemm_arready       (gemm_axi1_if.arready),

        .gemm_rid           (gemm_axi1_if.rid),
        .gemm_rdata         (gemm_axi1_if.rdata),
        .gemm_rresp         (gemm_axi1_if.rresp),
        .gemm_rlast         (gemm_axi1_if.rlast),
        .gemm_rvalid        (gemm_axi1_if.rvalid),
        .gemm_rready        (gemm_axi1_if.rready),

        // Scratchpad Port1 output
        .p1_awid            (axi1_if.awid),
        .p1_awaddr          (axi1_if.awaddr),
        .p1_awlen           (axi1_if.awlen),
        .p1_awsize          (axi1_if.awsize),
        .p1_awburst         (axi1_if.awburst),
        .p1_awvalid         (axi1_if.awvalid),
        .p1_awready         (axi1_if.awready),

        .p1_wdata           (axi1_if.wdata),
        .p1_wstrb           (axi1_if.wstrb),
        .p1_wlast           (axi1_if.wlast),
        .p1_wvalid          (axi1_if.wvalid),
        .p1_wready          (axi1_if.wready),

        .p1_bid             (axi1_if.bid),
        .p1_bresp           (axi1_if.bresp),
        .p1_bvalid          (axi1_if.bvalid),
        .p1_bready          (axi1_if.bready),

        .p1_arid            (axi1_if.arid),
        .p1_araddr          (axi1_if.araddr),
        .p1_arlen           (axi1_if.arlen),
        .p1_arsize          (axi1_if.arsize),
        .p1_arburst         (axi1_if.arburst),
        .p1_arvalid         (axi1_if.arvalid),
        .p1_arready         (axi1_if.arready),

        .p1_rid             (axi1_if.rid),
        .p1_rdata           (axi1_if.rdata),
        .p1_rresp           (axi1_if.rresp),
        .p1_rlast           (axi1_if.rlast),
        .p1_rvalid          (axi1_if.rvalid),
        .p1_rready          (axi1_if.rready)
    );

    // ============================================================
    // Dual-port AXI-MM BRAM scratchpad
    // ============================================================
    axi_mm_dual_port_bram #(
        .ADDR_WIDTH       (ADDR_WIDTH),
        .DATA_WIDTH       (DATA_WIDTH),
        .ID_WIDTH         (ID_WIDTH),
        .DEPTH_WORDS      (DEPTH_WORDS)
    ) u_bram (
        .dma_clk          (dma_clk),
        .dma_rst_n        (dma_rst_n),
        .core_clk         (core_clk),
        .core_rst_n       (core_rst_n),

        // Port0 now goes through owner mux.
        .axi0_if          (bram_axi0_if),

        // Port1 now goes through owner mux.
        .axi1_if          (axi1_if),

        .apply_if         (apply_if.mp_producer),
        .commit_if        (commit_if.mp_producer),

        .ce_idle          (ce_idle)
    );

    // ============================================================
    // GEMM compute core
    //
    // Note:
    //   GEMM receives core_clk-domain start/config.
    //   External dma_clk-domain control/config is captured and
    //   crossed above.
    // ============================================================
    gemm_top #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .A_DATA_WIDTH (GEMM_A_WIDTH),
        .B_DATA_WIDTH (GEMM_B_WIDTH),
        .ACC_WIDTH    (GEMM_ACC_WIDTH),
        .DIM_WIDTH    (GEMM_DIM_WIDTH),
        .GEMM_MAC_LANES (GEMM_MAC_LANES),
        .GEMM_ENABLE_B_CACHE (GEMM_ENABLE_B_CACHE),
        .GEMM_B_CACHE_MAX_K  (GEMM_B_CACHE_MAX_K),
        .GEMM_B_CACHE_MAX_N  (GEMM_B_CACHE_MAX_N),
        .GEMM_ENABLE_PACKED_BCACHE_PRELOAD (GEMM_ENABLE_PACKED_BCACHE_PRELOAD),
        .GEMM_ENABLE_A_ROW_CACHE (GEMM_ENABLE_A_ROW_CACHE),
        .GEMM_A_ROW_CACHE_MAX_K (GEMM_A_ROW_CACHE_MAX_K),
        .GEMM_ENABLE_PACKED_A_ROW_PRELOAD (GEMM_ENABLE_PACKED_A_ROW_PRELOAD),
        .GEMM_ENABLE_K_TILING (GEMM_ENABLE_K_TILING),
        .GEMM_K_TILE_SIZE (GEMM_K_TILE_SIZE),
        .GEMM_ENABLE_N_TILING (GEMM_ENABLE_N_TILING),
        .GEMM_N_TILE_SIZE (GEMM_N_TILE_SIZE)
    ) u_gemm_top (
        .clk           (core_clk),
        .rst_n         (core_rst_n),

        .start         (gemm_start_core),
        .busy          (gemm_busy_core),
        .done          (gemm_done_core),

        .base_addr_a   (base_addr_a_core_q),
        .base_addr_b   (base_addr_b_core_q),
        .base_addr_c   (base_addr_c_core_q),

        .dim_m         (dim_m_core_q),
        .dim_n         (dim_n_core_q),
        .dim_k         (dim_k_core_q),

        .mem_req_ready (gemm_mem_req_ready),
        .mem_wr_done   (gemm_mem_done),

        .mem_rd_en     (gemm_mem_rd_en),
        .mem_rd_addr   (gemm_mem_rd_addr),
        .mem_rd_data   (gemm_mem_rd_data),
        .mem_rd_valid  (gemm_mem_rd_valid),

        .mem_wr_en     (gemm_mem_wr_en),
        .mem_wr_addr   (gemm_mem_wr_addr),
        .mem_wr_data   (gemm_mem_wr_data),
        .mem_wr_strb   (gemm_mem_wr_strb),

        .gemm_perf_busy_cycles  (gemm_perf_busy_cycles),
        .gemm_perf_mac_count    (gemm_perf_mac_count),
        .gemm_perf_output_count (gemm_perf_output_count)
    );

    // ============================================================
    // GEMM input memory router
    //
    // scratchpad mode:
    //   GEMM reads/writes route to gemm_scratchpad_adapter.
    //
    // direct-stream mode:
    //   GEMM A/B reads route to gemm_operand_buffer.
    //   GEMM C writes route to gemm_scratchpad_adapter.
    // ============================================================
    gemm_input_mem_router #(
        .ADDR_WIDTH       (ADDR_WIDTH),
        .LOCAL_DATA_WIDTH (32)
    ) u_gemm_input_mem_router (
        .clk                         (core_clk),
        .rst_n                       (core_rst_n),

        .clear_status                (gemm_start_core),

        .direct_stream_mode          (gemm_input_stream_mode_core_q),

        .base_addr_a                 (base_addr_a_core_q),
        .base_addr_b                 (base_addr_b_core_q),

        .a_region_bytes              (direct_a_region_bytes_core),
        .b_region_bytes              (direct_b_region_bytes_core),

        .operand_a_loaded            (ds_a_loaded),
        .operand_b_loaded            (ds_b_loaded),

        .operand_buf_error           (ds_operand_buffer_error),
        .operand_buf_read_error_pulse(ds_buf_read_error_pulse),

        // GEMM local memory side
        .gemm_mem_req_ready          (gemm_mem_req_ready),

        .gemm_mem_rd_en              (gemm_mem_rd_en),
        .gemm_mem_rd_addr            (gemm_mem_rd_addr),
        .gemm_mem_rd_data            (gemm_mem_rd_data),
        .gemm_mem_rd_valid           (gemm_mem_rd_valid),

        .gemm_mem_wr_en              (gemm_mem_wr_en),
        .gemm_mem_wr_addr            (gemm_mem_wr_addr),
        .gemm_mem_wr_data            (gemm_mem_wr_data),
        .gemm_mem_wr_strb            (gemm_mem_wr_strb),

        // Scratchpad adapter side
        .sp_mem_req_ready            (sp_mem_req_ready),

        .sp_mem_rd_en                (sp_mem_rd_en),
        .sp_mem_rd_addr              (sp_mem_rd_addr),
        .sp_mem_rd_data              (sp_mem_rd_data),
        .sp_mem_rd_valid             (sp_mem_rd_valid),

        .sp_mem_wr_en                (sp_mem_wr_en),
        .sp_mem_wr_addr              (sp_mem_wr_addr),
        .sp_mem_wr_data              (sp_mem_wr_data),
        .sp_mem_wr_strb              (sp_mem_wr_strb),

        // Operand buffer read side
        .op_rd_valid                 (op_rd_valid),
        .op_rd_ready                 (op_rd_ready),
        .op_rd_operand_sel           (op_rd_operand_sel),
        .op_rd_addr                  (op_rd_addr),
        .op_rd_data                  (op_rd_data),
        .op_rd_data_valid            (op_rd_data_valid),

        .busy                        (gemm_router_busy),

        .router_error_pulse          (gemm_router_error_pulse),
        .error                       (gemm_router_error),

        .op_read_count               (gemm_router_op_read_count),
        .sp_read_count               (gemm_router_sp_read_count),
        .sp_write_count              (gemm_router_sp_write_count),
        .invalid_read_count          (gemm_router_invalid_read_count),
        .simultaneous_req_count      (gemm_router_simultaneous_req_count)
    );

    // ============================================================
    // GEMM local-memory -> scratchpad AXI adapter
    //
    // The adapter now drives gemm_axi1_if, which is routed through
    // scratchpad_port1_owner_mux before reaching BRAM Port1.
    // ============================================================
    gemm_scratchpad_adapter #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_gemm_scratchpad_adapter (
        .clk           (core_clk),
        .rst_n         (core_rst_n),

        .mem_rd_en     (sp_mem_rd_en),
        .mem_rd_addr   (sp_mem_rd_addr),
        .mem_rd_data   (sp_mem_rd_data),
        .mem_rd_valid  (sp_mem_rd_valid),

        .mem_wr_en     (sp_mem_wr_en),
        .mem_wr_addr   (sp_mem_wr_addr),
        .mem_wr_data   (sp_mem_wr_data),
        .mem_wr_strb   (sp_mem_wr_strb),

        .mem_req_ready (sp_mem_req_ready),

        .busy          (gemm_mem_busy),
        .done          (gemm_mem_done),

        .axi_if        (gemm_axi1_if)
    );

endmodule

`endif