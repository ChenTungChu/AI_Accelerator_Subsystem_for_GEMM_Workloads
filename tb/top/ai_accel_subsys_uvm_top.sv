// File: tb/top/ai_accel_subsys_uvm_top.sv
`timescale 1ns/1ps

module ai_accel_subsys_uvm_top;

    import uvm_pkg::*;
    import ai_accel_subsys_uvm_pkg::*;
    `include "uvm_macros.svh"

    // ============================================================
    // Parameters
    // ============================================================
    localparam int ADDR_WIDTH      = 32;
    localparam int DATA_WIDTH      = 64;
    localparam int ID_WIDTH        = 4;
    localparam int DEPTH_WORDS     = 1024;

    localparam int GEMM_A_WIDTH    = 8;
    localparam int GEMM_B_WIDTH    = 8;
    localparam int GEMM_ACC_WIDTH  = 32;
    localparam int GEMM_DIM_WIDTH  = 8;

    // ============================================================
    // Clocks / resets
    // ============================================================
    logic dma_clk;
    logic dma_rst_n;
    logic core_clk;
    logic core_rst_n;

    // ============================================================
    // DUT control / status
    // ============================================================
    logic acc_busy;
    logic acc_done;

    // ============================================================
    // External AXI-MM host interface (Port0)
    //   For first-step UVM smoke, keep it idle.
    // ============================================================
    axi_mm_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .HAS_BURST  (1)
    ) axi0_if (
        .clk   (dma_clk),
        .rst_n (dma_rst_n)
    );

    // ============================================================
    // UVM control/config interface
    // ============================================================
    ai_accel_subsys_ctrl_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DIM_WIDTH  (GEMM_DIM_WIDTH)
    ) ctrl_if (
        .clk (dma_clk)
    );

    // ============================================================
    // DUT
    // ============================================================
    ai_accel_subsys #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .DATA_WIDTH      (DATA_WIDTH),
        .ID_WIDTH        (ID_WIDTH),
        .DEPTH_WORDS     (DEPTH_WORDS),
        .GEMM_A_WIDTH    (GEMM_A_WIDTH),
        .GEMM_B_WIDTH    (GEMM_B_WIDTH),
        .GEMM_ACC_WIDTH  (GEMM_ACC_WIDTH),
        .GEMM_DIM_WIDTH  (GEMM_DIM_WIDTH)
    ) dut (
        .dma_clk     (dma_clk),
        .dma_rst_n   (dma_rst_n),
        .core_clk    (core_clk),
        .core_rst_n  (core_rst_n),

        .axi0_if     (axi0_if),

        .acc_start   (ctrl_if.acc_start),
        .acc_busy    (acc_busy),
        .acc_done    (acc_done),

        .base_addr_a (ctrl_if.base_addr_a),
        .base_addr_b (ctrl_if.base_addr_b),
        .base_addr_c (ctrl_if.base_addr_c),

        .dim_m       (ctrl_if.dim_m),
        .dim_n       (ctrl_if.dim_n),
        .dim_k       (ctrl_if.dim_k)
    );

    // ============================================================
    // Connect DUT status/reset observation into ctrl_if
    // ============================================================
    assign ctrl_if.dma_rst_n  = dma_rst_n;
    assign ctrl_if.core_rst_n = core_rst_n;

    assign ctrl_if.acc_busy   = acc_busy;
    assign ctrl_if.acc_done   = acc_done;

    // ============================================================
    // BRAM observation interface ready
    // ============================================================
    initial begin
        force dut.apply_if.ready  = 1'b1;
        force dut.commit_if.ready = 1'b1;
    end

    // ============================================================
    // Clock generation
    // ============================================================
    initial begin
        dma_clk = 1'b0;
        forever #5 dma_clk = ~dma_clk;      // 100 MHz
    end

    initial begin
        core_clk = 1'b0;
        forever #7 core_clk = ~core_clk;    // ~71.4 MHz
    end

    // ============================================================
    // Reset generation
    // ============================================================
    initial begin
        dma_rst_n  = 1'b0;
        core_rst_n = 1'b0;

        repeat (5) @(posedge dma_clk);
        dma_rst_n = 1'b1;

        repeat (5) @(posedge core_clk);
        core_rst_n = 1'b1;
    end

    // ============================================================
    // Default idle values
    //   First-step UVM smoke does not yet drive AXI preload/readback.
    // ============================================================
    initial begin
        // ctrl_if defaults
        ctrl_if.acc_start   = 1'b0;
        ctrl_if.base_addr_a = '0;
        ctrl_if.base_addr_b = '0;
        ctrl_if.base_addr_c = '0;
        ctrl_if.dim_m       = '0;
        ctrl_if.dim_n       = '0;
        ctrl_if.dim_k       = '0;

        // axi0_if idle defaults
        axi0_if.awid    = '0;
        axi0_if.awaddr  = '0;
        axi0_if.awlen   = '0;
        axi0_if.awsize  = '0;
        axi0_if.awburst = '0;
        axi0_if.awvalid = 1'b0;

        axi0_if.wdata   = '0;
        axi0_if.wstrb   = '0;
        axi0_if.wlast   = 1'b0;
        axi0_if.wvalid  = 1'b0;

        axi0_if.bready  = 1'b0;

        axi0_if.arid    = '0;
        axi0_if.araddr  = '0;
        axi0_if.arlen   = '0;
        axi0_if.arsize  = '0;
        axi0_if.arburst = '0;
        axi0_if.arvalid = 1'b0;

        axi0_if.rready  = 1'b0;
    end

    // ============================================================
    // UVM hookup
    // ============================================================
    initial begin
        uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::set(
            null, "*", "vif", ctrl_if
        );

        run_test();
    end

endmodule