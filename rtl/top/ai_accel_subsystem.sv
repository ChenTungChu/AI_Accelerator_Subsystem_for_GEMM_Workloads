// File: rtl/top/ai_accel_subsystem.sv
`ifndef AI_ACCEL_SUBSYSTEM_SV
`define AI_ACCEL_SUBSYSTEM_SV

module ai_accel_subsystem #(
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
    // - Only axi0_if is exposed externally.
    // - Host/testbench uses axi0_if to preload A/B and read back C.
    // - Accelerator-side AXI path is kept internal to subsystem.
    // ------------------------------------------------------------
    axi_mm_if axi0_if,

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
    // Adapter status
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
        acc_busy = gemm_busy_core | gemm_mem_busy;
        acc_done = acc_done_pulse_q;
    end

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

        .axi0_if          (axi0_if),
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