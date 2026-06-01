// File: tb/top/ai_accel_csr_regs_uvm_top.sv
`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"

// Local unit-level status-control interface for standalone CSR register smoke.
// Kept inside this top so the main subsystem testbench does not need
// an extra standalone-only tb/interface file.

`ifndef AI_ACCEL_CSR_STATUS_IF_SV
`define AI_ACCEL_CSR_STATUS_IF_SV

interface ai_accel_csr_status_if #(
    parameter int DATA_WIDTH = 32
)(
    input logic clk
);

    // ------------------------------------------------------------
    // Live operation status inputs to the standalone CSR DUT
    // ------------------------------------------------------------
    logic acc_busy;
    logic acc_done;

    logic dma_load_busy;
    logic dma_load_done;
    logic dma_load_error;

    logic axis_load_busy;
    logic axis_load_done;
    logic axis_load_error;

    logic ds_load_busy;
    logic ds_load_done;
    logic ds_load_error;

    logic dma_store_busy;
    logic dma_store_done;
    logic dma_store_error;

    // ------------------------------------------------------------
    // Performance counter inputs
    // ------------------------------------------------------------
    logic [DATA_WIDTH-1:0] gemm_perf_busy_cycles;
    logic [DATA_WIDTH-1:0] gemm_perf_mac_count;
    logic [DATA_WIDTH-1:0] gemm_perf_output_count;

    // ------------------------------------------------------------
    // Initialize all DUT status inputs
    // ------------------------------------------------------------
    task automatic init_status_inputs();
    begin
        acc_busy  = 1'b0;
        acc_done  = 1'b0;

        dma_load_busy  = 1'b0;
        dma_load_done  = 1'b0;
        dma_load_error = 1'b0;

        axis_load_busy  = 1'b0;
        axis_load_done  = 1'b0;
        axis_load_error = 1'b0;

        ds_load_busy  = 1'b0;
        ds_load_done  = 1'b0;
        ds_load_error = 1'b0;

        dma_store_busy  = 1'b0;
        dma_store_done  = 1'b0;
        dma_store_error = 1'b0;

        gemm_perf_busy_cycles  = '0;
        gemm_perf_mac_count    = '0;
        gemm_perf_output_count = '0;
    end
    endtask

    // ------------------------------------------------------------
    // One-cycle completion/error pulses for sticky CSR checks
    // ------------------------------------------------------------
    task automatic pulse_acc_done(
        input logic [DATA_WIDTH-1:0] busy_cycles,
        input logic [DATA_WIDTH-1:0] mac_count,
        input logic [DATA_WIDTH-1:0] output_count
    );
    begin
        @(posedge clk);
        gemm_perf_busy_cycles  <= busy_cycles;
        gemm_perf_mac_count    <= mac_count;
        gemm_perf_output_count <= output_count;
        acc_done               <= 1'b1;

        @(posedge clk);
        acc_done               <= 1'b0;
    end
    endtask

    task automatic pulse_dma_load_done(input bit with_error = 1'b0);
    begin
        @(posedge clk);
        dma_load_done  <= 1'b1;
        dma_load_error <= with_error;

        @(posedge clk);
        dma_load_done  <= 1'b0;
        dma_load_error <= 1'b0;
    end
    endtask

    task automatic pulse_axis_load_done(input bit with_error = 1'b0);
    begin
        @(posedge clk);
        axis_load_done  <= 1'b1;
        axis_load_error <= with_error;

        @(posedge clk);
        axis_load_done  <= 1'b0;
        axis_load_error <= 1'b0;
    end
    endtask

    task automatic pulse_ds_load_done(input bit with_error = 1'b0);
    begin
        @(posedge clk);
        ds_load_done  <= 1'b1;
        ds_load_error <= with_error;

        @(posedge clk);
        ds_load_done  <= 1'b0;
        ds_load_error <= 1'b0;
    end
    endtask

    task automatic pulse_dma_store_done(input bit with_error = 1'b0);
    begin
        @(posedge clk);
        dma_store_done  <= 1'b1;
        dma_store_error <= with_error;

        @(posedge clk);
        dma_store_done  <= 1'b0;
        dma_store_error <= 1'b0;
    end
    endtask

endinterface

`endif

`include "ai_accel_csr_regs_smoke_test.sv"

module ai_accel_csr_regs_uvm_top;

    // ============================================================
    // Parameters
    // ============================================================
    localparam int ADDR_WIDTH     = 32;
    localparam int GEMM_DIM_WIDTH = 8;
    localparam int CSR_ADDR_WIDTH = 12;
    localparam int CSR_DATA_WIDTH = 32;

    localparam logic [31:0] CSR_VERSION_VALUE = 32'h0001_0014;

    // ============================================================
    // Clock / reset
    // ============================================================
    logic clk;
    logic rst_n;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
    end

    // ============================================================
    // Interfaces
    // ============================================================
    axi_lite_if #(
        .ADDR_WIDTH (CSR_ADDR_WIDTH),
        .DATA_WIDTH (CSR_DATA_WIDTH)
    ) csr_if (
        .clk   (clk),
        .rst_n (rst_n)
    );

    ai_accel_csr_status_if #(
        .DATA_WIDTH (CSR_DATA_WIDTH)
    ) status_if (
        .clk (clk)
    );

    // ============================================================
    // CSR DUT
    // ============================================================
    ai_accel_csr_regs #(
        .ADDR_WIDTH        (ADDR_WIDTH),
        .GEMM_DIM_WIDTH    (GEMM_DIM_WIDTH),
        .CSR_ADDR_WIDTH    (CSR_ADDR_WIDTH),
        .CSR_DATA_WIDTH    (CSR_DATA_WIDTH),
        .CSR_VERSION_VALUE (CSR_VERSION_VALUE)
    ) u_csr_regs (
        .clk                    (clk),
        .rst_n                  (rst_n),

        .csr_if                 (csr_if),

        .acc_start_pulse        (),
        .gemm_input_stream_mode (),
        .accumulate_enable      (),

        .base_addr_a            (),
        .base_addr_b            (),
        .base_addr_c            (),

        .dim_m                  (),
        .dim_n                  (),
        .dim_k                  (),

        .dma_load_start_pulse   (),
        .dma_src_base_addr      (),
        .dma_dst_base_addr      (),
        .dma_load_beats         (),

        .axis_load_start_pulse  (),
        .axis_src_base_addr     (),
        .axis_dst_base_addr     (),
        .axis_load_beats        (),

        .ds_load_start_pulse    (),
        .ds_src_base_addr       (),
        .ds_dst_base_addr       (),
        .ds_load_beats          (),
        .ds_operand_sel         (),

        .dma_store_start_pulse  (),
        .dma_store_src_base_addr(),
        .dma_store_dst_base_addr(),
        .dma_store_byte_count   (),

        .acc_busy               (status_if.acc_busy),
        .acc_done               (status_if.acc_done),

        .dma_load_busy          (status_if.dma_load_busy),
        .dma_load_done          (status_if.dma_load_done),
        .dma_load_error         (status_if.dma_load_error),

        .axis_load_busy         (status_if.axis_load_busy),
        .axis_load_done         (status_if.axis_load_done),
        .axis_load_error        (status_if.axis_load_error),

        .ds_load_busy           (status_if.ds_load_busy),
        .ds_load_done           (status_if.ds_load_done),
        .ds_load_error          (status_if.ds_load_error),

        .dma_store_busy         (status_if.dma_store_busy),
        .dma_store_done         (status_if.dma_store_done),
        .dma_store_error        (status_if.dma_store_error),

        .gemm_perf_busy_cycles  (status_if.gemm_perf_busy_cycles),
        .gemm_perf_mac_count    (status_if.gemm_perf_mac_count),
        .gemm_perf_output_count (status_if.gemm_perf_output_count)
    );

    // ============================================================
    // UVM config handoff
    // ============================================================
    typedef virtual axi_lite_if #(
        .ADDR_WIDTH (CSR_ADDR_WIDTH),
        .DATA_WIDTH (CSR_DATA_WIDTH)
    ) csr_vif_t;

    typedef virtual ai_accel_csr_status_if #(
        .DATA_WIDTH (CSR_DATA_WIDTH)
    ) status_vif_t;

    initial begin
        uvm_config_db#(csr_vif_t)::set(
            null, "uvm_test_top", "csr_vif", csr_if);

        uvm_config_db#(status_vif_t)::set(
            null, "uvm_test_top", "status_vif", status_if);

        run_test();
    end

endmodule
