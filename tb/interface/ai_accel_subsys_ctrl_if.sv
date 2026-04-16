// File: tb/interface/ai_accel_subsys_ctrl_if.sv

`ifndef AI_ACCEL_SUBSYS_CTRL_IF_SV
`define AI_ACCEL_SUBSYS_CTRL_IF_SV

interface ai_accel_subsys_ctrl_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DIM_WIDTH  = 8
)(
    input logic clk
);

    // ------------------------------------------------------------
    // Reset/status observation
    // ------------------------------------------------------------
    logic dma_rst_n;
    logic core_rst_n;

    // ------------------------------------------------------------
    // Accelerator control / status
    // ------------------------------------------------------------
    logic acc_start;
    logic acc_busy;
    logic acc_done;

    // ------------------------------------------------------------
    // Runtime configuration
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] base_addr_a;
    logic [ADDR_WIDTH-1:0] base_addr_b;
    logic [ADDR_WIDTH-1:0] base_addr_c;

    logic [DIM_WIDTH-1:0]  dim_m;
    logic [DIM_WIDTH-1:0]  dim_n;
    logic [DIM_WIDTH-1:0]  dim_k;

    // ------------------------------------------------------------
    // Driver clocking block
    // ------------------------------------------------------------
    clocking cb_drv @(posedge clk);
        output acc_start;

        output base_addr_a;
        output base_addr_b;
        output base_addr_c;

        output dim_m;
        output dim_n;
        output dim_k;

        input  dma_rst_n;
        input  core_rst_n;

        input  acc_busy;
        input  acc_done;
    endclocking

    // ------------------------------------------------------------
    // Monitor clocking block
    // ------------------------------------------------------------
    clocking cb_mon @(posedge clk);
        input dma_rst_n;
        input core_rst_n;

        input acc_start;
        input acc_busy;
        input acc_done;

        input base_addr_a;
        input base_addr_b;
        input base_addr_c;

        input dim_m;
        input dim_n;
        input dim_k;
    endclocking

    // ------------------------------------------------------------
    // Modports
    // ------------------------------------------------------------
    modport drv (
        clocking cb_drv
    );

    modport mon (
        clocking cb_mon
    );

endinterface

`endif