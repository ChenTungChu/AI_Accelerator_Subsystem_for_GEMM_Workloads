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
    parameter logic [31:0] CSR_VERSION_VALUE = 32'h0001_0014
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
        .CSR_ADDR_WIDTH    (CSR_ADDR_WIDTH),
        .CSR_DATA_WIDTH    (CSR_DATA_WIDTH),
        .CSR_VERSION_VALUE (CSR_VERSION_VALUE)
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

        .dma_load_start     (csr_dma_load_start_pulse),
        .dma_src_base_addr  (csr_dma_src_base_addr),
        .dma_dst_base_addr  (csr_dma_dst_base_addr),
        .dma_load_beats     (csr_dma_load_beats),

        .dma_load_busy      (dma_load_busy_i),
        .dma_load_done      (dma_load_done_i),
        .dma_load_error     (dma_load_error_i),

        .dma_store_start         (csr_dma_store_start_pulse),
        .dma_store_src_base_addr (csr_dma_store_src_base_addr),
        .dma_store_dst_base_addr (csr_dma_store_dst_base_addr),
        .dma_store_byte_count    (csr_dma_store_byte_count),

        .dma_store_busy      (dma_store_busy_i),
        .dma_store_done      (dma_store_done_i),
        .dma_store_error     (dma_store_error_i),

        .axis_load_start     (csr_axis_load_start_pulse),
        .axis_src_base_addr  (csr_axis_src_base_addr),
        .axis_dst_base_addr  (csr_axis_dst_base_addr),
        .axis_load_beats     (csr_axis_load_beats),

        .axis_load_busy      (axis_load_busy_i),
        .axis_load_done      (axis_load_done_i),
        .axis_load_error     (axis_load_error_i),

        .ds_load_start       (csr_ds_load_start_pulse),
        .ds_src_base_addr    (csr_ds_src_base_addr),
        .ds_dst_base_addr    (csr_ds_dst_base_addr),
        .ds_load_beats       (csr_ds_load_beats),
        .ds_operand_sel      (csr_ds_operand_sel),

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

        .gemm_input_stream_mode (csr_gemm_input_stream_mode),
        .accumulate_enable      (csr_accumulate_enable),

        .acc_start      (csr_acc_start_pulse),
        .acc_busy       (acc_busy_i),
        .acc_done       (acc_done_i),

        .base_addr_a    (csr_base_addr_a),
        .base_addr_b    (csr_base_addr_b),
        .base_addr_c    (csr_base_addr_c),

        .dim_m          (csr_dim_m),
        .dim_n          (csr_dim_n),
        .dim_k          (csr_dim_k),

        .gemm_perf_busy_cycles  (gemm_perf_busy_cycles_i),
        .gemm_perf_mac_count    (gemm_perf_mac_count_i),
        .gemm_perf_output_count (gemm_perf_output_count_i)
    );

endmodule

`endif
