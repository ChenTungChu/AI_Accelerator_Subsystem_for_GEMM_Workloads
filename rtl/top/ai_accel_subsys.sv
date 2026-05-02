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
    parameter int COMMIT_BEAT_IDX_W = 8
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
    // v1 policy:
    // - Host/testbench uses axi0_if to preload/readback when DMA load
    //   is not active.
    // - During DMA_LOAD phase, Port0 is owned by dma_load_engine.
    // - Port0 ownership is selected by scratchpad_port0_owner_mux.
    // ------------------------------------------------------------
    axi_mm_if axi0_if,

    // ------------------------------------------------------------
    // DMA load control
    //
    // v1 usage:
    //   1. Pulse dma_load_start in dma_clk domain.
    //   2. Wait dma_load_done.
    //   3. Then pulse acc_start for GEMM.
    //
    // This keeps DMA_LOAD and GEMM_RUN phase-exclusive.
    // ------------------------------------------------------------
    input  logic                      dma_load_start,
    input  logic [ADDR_WIDTH-1:0]     dma_src_base_addr,
    input  logic [ADDR_WIDTH-1:0]     dma_dst_base_addr,
    input  logic [31:0]               dma_load_beats,

    output logic                      dma_load_busy,
    output logic                      dma_load_done,
    output logic                      dma_load_error,

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
    // Accelerator control
    // ------------------------------------------------------------
    input  logic                      acc_start,
    output logic                      acc_busy,
    output logic                      acc_done,

    input  logic [ADDR_WIDTH-1:0]     base_addr_a,
    input  logic [ADDR_WIDTH-1:0]     base_addr_b,
    input  logic [ADDR_WIDTH-1:0]     base_addr_c,

    input  logic [GEMM_DIM_WIDTH-1:0] dim_m,
    input  logic [GEMM_DIM_WIDTH-1:0] dim_n,
    input  logic [GEMM_DIM_WIDTH-1:0] dim_k
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
    // Internal AXI-MM interface for accelerator-side access
    //   adapter (master) <-> BRAM port1 (slave)
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

    // ------------------------------------------------------------
    // Port0 owner select
    //
    // v1 phase-based ownership:
    //   dma_load_busy_i = 0 -> Host owns Port0
    //   dma_load_busy_i = 1 -> DMA load engine owns Port0
    //
    // Requirement:
    //   Do not issue host transactions while dma_load_busy is high.
    // ------------------------------------------------------------
    logic port0_select_dma;

    assign port0_select_dma = dma_load_busy_i;

    // ============================================================
    // Start pulse crossing: acc_start -> core_clk domain
    // ============================================================
    logic start_toggle_dma_q;
    logic start_sync1_q, start_sync2_q, start_sync2_qq;
    logic gemm_start_core;

    always_ff @(posedge dma_clk or negedge dma_rst_n) begin
        if (!dma_rst_n) begin
            start_toggle_dma_q <= 1'b0;
        end
        else if (acc_start) begin
            start_toggle_dma_q <= ~start_toggle_dma_q;
        end
    end

    always_ff @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            start_sync1_q  <= 1'b0;
            start_sync2_q  <= 1'b0;
            start_sync2_qq <= 1'b0;
        end
        else begin
            start_sync1_q  <= start_toggle_dma_q;
            start_sync2_q  <= start_sync1_q;
            start_sync2_qq <= start_sync2_q;
        end
    end

    assign gemm_start_core = start_sync2_q ^ start_sync2_qq;

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

    // done pulse alignment
    logic                     gemm_done_core_q;
    logic                     gemm_done_pulse_core;
    logic                     acc_done_pending_q;
    logic                     acc_done_pulse_q;

    always_ff @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            gemm_done_core_q <= 1'b0;
        end
        else begin
            gemm_done_core_q <= gemm_done_core;
        end
    end

    assign gemm_done_pulse_core = gemm_done_core & ~gemm_done_core_q;

    // ============================================================
    // Subsystem status
    // ============================================================
    always_ff @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            acc_done_pending_q <= 1'b0;
            acc_done_pulse_q   <= 1'b0;
        end
        else begin
            // default: pulse only one cycle
            acc_done_pulse_q <= 1'b0;

            // latch the fact that GEMM core finished
            if (gemm_done_pulse_core) begin
                acc_done_pending_q <= 1'b1;
            end

            // once adapter is no longer busy, emit subsystem done pulse
            if (acc_done_pending_q && !gemm_mem_busy) begin
                acc_done_pulse_q   <= 1'b1;
                acc_done_pending_q <= 1'b0;
            end
        end
    end

    always_comb begin
        // Keep existing behavior for accelerator busy/done.
        // DMA load status is reported separately through dma_load_*.
        acc_busy = gemm_busy_core | gemm_mem_busy;
        acc_done = acc_done_pulse_q;
    end

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
    // Scratchpad Port0 owner mux
    //   Host axi0_if or DMA load engine -> BRAM Port0
    // ============================================================
    scratchpad_port0_owner_mux #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_scratchpad_port0_owner_mux (
        .select_dma  (port0_select_dma),

        .host_axi_if (axi0_if),
        .bram_axi_if (bram_axi0_if),

        .dma_awid    (dma_spad_awid),
        .dma_awaddr  (dma_spad_awaddr),
        .dma_awlen   (dma_spad_awlen),
        .dma_awsize  (dma_spad_awsize),
        .dma_awburst (dma_spad_awburst),
        .dma_awvalid (dma_spad_awvalid),
        .dma_awready (dma_spad_awready),

        .dma_wdata   (dma_spad_wdata),
        .dma_wstrb   (dma_spad_wstrb),
        .dma_wlast   (dma_spad_wlast),
        .dma_wvalid  (dma_spad_wvalid),
        .dma_wready  (dma_spad_wready),

        .dma_bid     (dma_spad_bid),
        .dma_bresp   (dma_spad_bresp),
        .dma_bvalid  (dma_spad_bvalid),
        .dma_bready  (dma_spad_bready)
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

        // Port1 remains GEMM/core side.
        .axi1_if          (axi1_if),

        .apply_if         (apply_if.mp_producer),
        .commit_if        (commit_if.mp_producer),

        .ce_idle          (ce_idle)
    );

    // ============================================================
    // GEMM compute core
    // ============================================================
    gemm_top #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .A_DATA_WIDTH (GEMM_A_WIDTH),
        .B_DATA_WIDTH (GEMM_B_WIDTH),
        .ACC_WIDTH    (GEMM_ACC_WIDTH),
        .DIM_WIDTH    (GEMM_DIM_WIDTH)
    ) u_gemm_top (
        .clk           (core_clk),
        .rst_n         (core_rst_n),

        .start         (gemm_start_core),
        .busy          (gemm_busy_core),
        .done          (gemm_done_core),

        .base_addr_a   (base_addr_a),
        .base_addr_b   (base_addr_b),
        .base_addr_c   (base_addr_c),

        .dim_m         (dim_m),
        .dim_n         (dim_n),
        .dim_k         (dim_k),

        .mem_req_ready (gemm_mem_req_ready),

        .mem_rd_en     (gemm_mem_rd_en),
        .mem_rd_addr   (gemm_mem_rd_addr),
        .mem_rd_data   (gemm_mem_rd_data),
        .mem_rd_valid  (gemm_mem_rd_valid),

        .mem_wr_en     (gemm_mem_wr_en),
        .mem_wr_addr   (gemm_mem_wr_addr),
        .mem_wr_data   (gemm_mem_wr_data),
        .mem_wr_strb   (gemm_mem_wr_strb)
    );

    // ============================================================
    // GEMM local-memory -> scratchpad AXI adapter
    // ============================================================
    gemm_scratchpad_adapter #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_gemm_scratchpad_adapter (
        .clk           (core_clk),
        .rst_n         (core_rst_n),

        .mem_rd_en     (gemm_mem_rd_en),
        .mem_rd_addr   (gemm_mem_rd_addr),
        .mem_rd_data   (gemm_mem_rd_data),
        .mem_rd_valid  (gemm_mem_rd_valid),

        .mem_wr_en     (gemm_mem_wr_en),
        .mem_wr_addr   (gemm_mem_wr_addr),
        .mem_wr_data   (gemm_mem_wr_data),
        .mem_wr_strb   (gemm_mem_wr_strb),

        .mem_req_ready (gemm_mem_req_ready),

        .busy          (gemm_mem_busy),
        .done          (gemm_mem_done),

        .axi_if        (axi1_if)
    );

endmodule

`endif