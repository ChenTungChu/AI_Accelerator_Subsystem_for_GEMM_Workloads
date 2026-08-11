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
    // P15 job-sequencer status inputs to the standalone CSR DUT
    // ------------------------------------------------------------
    logic                  job_busy;
    logic                  job_done;
    logic                  job_gemm_done;
    logic                  job_store_done;

    logic                  job_dma_load_error;
    logic                  job_axis_load_error;
    logic                  job_ds_load_error;
    logic                  job_dma_store_error;
    logic                  job_sequence_error;

    logic [DATA_WIDTH-1:0] job_state;
    logic [DATA_WIDTH-1:0] job_perf_busy_cycles;
    logic [DATA_WIDTH-1:0] job_perf_mac_count;
    logic [DATA_WIDTH-1:0] job_perf_output_count;

    // ------------------------------------------------------------
    // P16 recipe-sequencer status inputs to the standalone CSR DUT
    // ------------------------------------------------------------
    logic                  recipe_busy;
    logic                  recipe_done;
    logic                  recipe_all_slots_done;
    logic                  recipe_final_store_done;

    logic                  recipe_slot_job_error;
    logic                  recipe_slot_job_reject;
    logic                  recipe_sequence_error;
    logic                  recipe_slot_range_error;
    logic                  recipe_slot_descriptor_error;

    logic [DATA_WIDTH-1:0] recipe_state;
    logic [DATA_WIDTH-1:0] recipe_current_slot;
    logic [DATA_WIDTH-1:0] recipe_completed_count;
    logic [DATA_WIDTH-1:0] recipe_slot_done_mask;
    logic [DATA_WIDTH-1:0] recipe_slot_error_mask;
    logic [DATA_WIDTH-1:0] recipe_slot_reject_mask;
    logic [DATA_WIDTH-1:0] recipe_perf_busy_cycles;
    logic [DATA_WIDTH-1:0] recipe_perf_mac_count;
    logic [DATA_WIDTH-1:0] recipe_perf_output_count;

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

        job_busy            = 1'b0;
        job_done            = 1'b0;
        job_gemm_done       = 1'b0;
        job_store_done      = 1'b0;

        job_dma_load_error  = 1'b0;
        job_axis_load_error = 1'b0;
        job_ds_load_error   = 1'b0;
        job_dma_store_error = 1'b0;
        job_sequence_error  = 1'b0;

        job_state             = '0;
        job_perf_busy_cycles  = '0;
        job_perf_mac_count    = '0;
        job_perf_output_count = '0;

        recipe_busy            = 1'b0;
        recipe_done            = 1'b0;
        recipe_all_slots_done  = 1'b0;
        recipe_final_store_done= 1'b0;

        recipe_slot_job_error       = 1'b0;
        recipe_slot_job_reject      = 1'b0;
        recipe_sequence_error       = 1'b0;
        recipe_slot_range_error     = 1'b0;
        recipe_slot_descriptor_error= 1'b0;

        recipe_state             = '0;
        recipe_current_slot      = '0;
        recipe_completed_count   = '0;
        recipe_slot_done_mask    = '0;
        recipe_slot_error_mask   = '0;
        recipe_slot_reject_mask  = '0;
        recipe_perf_busy_cycles  = '0;
        recipe_perf_mac_count    = '0;
        recipe_perf_output_count = '0;
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

    task automatic pulse_job_gemm_done(
        input logic [DATA_WIDTH-1:0] busy_cycles,
        input logic [DATA_WIDTH-1:0] mac_count,
        input logic [DATA_WIDTH-1:0] output_count
    );
    begin
        @(posedge clk);
        job_perf_busy_cycles  <= busy_cycles;
        job_perf_mac_count    <= mac_count;
        job_perf_output_count <= output_count;
        job_gemm_done         <= 1'b1;

        @(posedge clk);
        job_gemm_done         <= 1'b0;
    end
    endtask

    task automatic pulse_job_done(input bit with_store_done = 1'b1);
    begin
        @(posedge clk);
        job_done       <= 1'b1;
        job_store_done <= with_store_done;

        @(posedge clk);
        job_done       <= 1'b0;
        job_store_done <= 1'b0;
    end
    endtask

    task automatic pulse_job_errors(
        input bit dma_load_error  = 1'b0,
        input bit axis_load_error = 1'b0,
        input bit ds_load_error   = 1'b0,
        input bit store_error     = 1'b0,
        input bit sequence_error  = 1'b0
    );
    begin
        @(posedge clk);
        job_dma_load_error  <= dma_load_error;
        job_axis_load_error <= axis_load_error;
        job_ds_load_error   <= ds_load_error;
        job_dma_store_error <= store_error;
        job_sequence_error  <= sequence_error;

        @(posedge clk);
        job_dma_load_error  <= 1'b0;
        job_axis_load_error <= 1'b0;
        job_ds_load_error   <= 1'b0;
        job_dma_store_error <= 1'b0;
        job_sequence_error  <= 1'b0;
    end
    endtask


    task automatic pulse_recipe_done(
        input logic [DATA_WIDTH-1:0] slot_mask,
        input logic [DATA_WIDTH-1:0] busy_cycles,
        input logic [DATA_WIDTH-1:0] mac_count,
        input logic [DATA_WIDTH-1:0] output_count
    );
    begin
        @(posedge clk);
        recipe_slot_done_mask    <= slot_mask;
        recipe_perf_busy_cycles  <= busy_cycles;
        recipe_perf_mac_count    <= mac_count;
        recipe_perf_output_count <= output_count;
        recipe_done              <= 1'b1;
        recipe_all_slots_done    <= 1'b1;
        recipe_final_store_done  <= 1'b1;

        @(posedge clk);
        recipe_done              <= 1'b0;
        recipe_all_slots_done    <= 1'b0;
        recipe_final_store_done  <= 1'b0;
        recipe_slot_done_mask    <= '0;
    end
    endtask

    task automatic pulse_recipe_error(input logic [DATA_WIDTH-1:0] slot_mask,
                                      input logic [DATA_WIDTH-1:0] reject_mask);
    begin
        @(posedge clk);
        recipe_slot_error_mask  <= slot_mask;
        recipe_slot_reject_mask <= reject_mask;
        recipe_slot_job_error   <= (slot_mask != '0);
        recipe_slot_job_reject  <= (reject_mask != '0);

        @(posedge clk);
        recipe_slot_error_mask  <= '0;
        recipe_slot_reject_mask <= '0;
        recipe_slot_job_error   <= 1'b0;
        recipe_slot_job_reject  <= 1'b0;
    end
    endtask

    task automatic pulse_recipe_reject(input logic [DATA_WIDTH-1:0] reject_mask);
    begin
        pulse_recipe_error('0, reject_mask);
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

    localparam logic [31:0] CSR_VERSION_VALUE        = 32'h0001_0014;
    localparam logic [31:0] CSR_JOB_VERSION_VALUE        = 32'h0001_0015;
    localparam logic [31:0] CSR_RECIPE_VERSION_VALUE     = 32'h0001_0016;
    localparam logic [31:0] CSR_DESC_FETCH_VERSION_VALUE = 32'h0001_0017;
    localparam int          P16_RECIPE_QUEUE_DEPTH   = 4;

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


    logic [31:0] recipe_slot_control [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0] recipe_slot_base_addr_a [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0] recipe_slot_base_addr_b [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0] recipe_slot_base_addr_c [P16_RECIPE_QUEUE_DEPTH];
    logic [GEMM_DIM_WIDTH-1:0] recipe_slot_dim_m [P16_RECIPE_QUEUE_DEPTH];
    logic [GEMM_DIM_WIDTH-1:0] recipe_slot_dim_n [P16_RECIPE_QUEUE_DEPTH];
    logic [GEMM_DIM_WIDTH-1:0] recipe_slot_dim_k [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0] recipe_slot_a_src_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0] recipe_slot_a_dst_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_a_load_beats [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0] recipe_slot_b_src_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0] recipe_slot_b_dst_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_b_load_beats [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0] recipe_slot_store_src_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [ADDR_WIDTH-1:0] recipe_slot_store_dst_base_addr [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_store_byte_count [P16_RECIPE_QUEUE_DEPTH];
    logic [31:0] recipe_slot_user_tag [P16_RECIPE_QUEUE_DEPTH];
    // ============================================================
    // CSR DUT
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

        .job_start_pulse        (),
        .job_clear_done_pulse   (),
        .job_clear_error_pulse  (),
        .job_clear_perf_pulse   (),

        .job_input_mode         (),
        .job_output_mode        (),
        .job_accumulate_enable  (),
        .job_clear_p14_sticky_on_start(),

        .job_base_addr_a        (),
        .job_base_addr_b        (),
        .job_base_addr_c        (),

        .job_dim_m              (),
        .job_dim_n              (),
        .job_dim_k              (),

        .job_a_src_base_addr    (),
        .job_a_dst_base_addr    (),
        .job_a_load_beats       (),

        .job_b_src_base_addr    (),
        .job_b_dst_base_addr    (),
        .job_b_load_beats       (),

        .job_store_src_base_addr(),
        .job_store_dst_base_addr(),
        .job_store_byte_count   (),

        .recipe_start_pulse             (),
        .recipe_clear_done_pulse        (),
        .recipe_clear_error_pulse       (),
        .recipe_clear_perf_pulse        (),
        .recipe_clear_slot_status_pulse (),

        .recipe_count                   (),
        .recipe_start_slot              (),
        .recipe_stop_on_error           (),
        .recipe_clear_job_sticky_each_slot(),
        .recipe_accumulate_perf         (),
        .recipe_allow_slot_writes_while_busy(),

        .recipe_slot_control            (recipe_slot_control),
        .recipe_slot_base_addr_a        (recipe_slot_base_addr_a),
        .recipe_slot_base_addr_b        (recipe_slot_base_addr_b),
        .recipe_slot_base_addr_c        (recipe_slot_base_addr_c),
        .recipe_slot_dim_m              (recipe_slot_dim_m),
        .recipe_slot_dim_n              (recipe_slot_dim_n),
        .recipe_slot_dim_k              (recipe_slot_dim_k),
        .recipe_slot_a_src_base_addr    (recipe_slot_a_src_base_addr),
        .recipe_slot_a_dst_base_addr    (recipe_slot_a_dst_base_addr),
        .recipe_slot_a_load_beats       (recipe_slot_a_load_beats),
        .recipe_slot_b_src_base_addr    (recipe_slot_b_src_base_addr),
        .recipe_slot_b_dst_base_addr    (recipe_slot_b_dst_base_addr),
        .recipe_slot_b_load_beats       (recipe_slot_b_load_beats),
        .recipe_slot_store_src_base_addr(recipe_slot_store_src_base_addr),
        .recipe_slot_store_dst_base_addr(recipe_slot_store_dst_base_addr),
        .recipe_slot_store_byte_count   (recipe_slot_store_byte_count),
        .recipe_slot_user_tag           (recipe_slot_user_tag),

        .desc_fetch_start_pulse         (),
        .desc_fetch_clear_done_pulse    (),
        .desc_fetch_clear_error_pulse   (),
        .desc_fetch_base_addr           (),
        .desc_fetch_count               (),
        .desc_fetch_stride_bytes        (),

        .desc_fetch_busy                (1'b0),
        .desc_fetch_launch_ownership    (1'b0),
        .desc_fetch_done                (1'b0),
        .desc_fetch_error               (1'b0),
        .desc_fetch_reject              (1'b0),
        .desc_fetch_error_status        (32'h0000_0000),
        .desc_fetch_reject_status       (32'h0000_0000),
        .desc_fetch_current_index       (4'h0),
        .desc_fetch_fetched_count       (4'h0),
        .desc_fetch_snapshot_valid      (1'b0),
        .desc_fetch_recipe_count        (4'h0),

        .job_busy               (status_if.job_busy),
        .job_done               (status_if.job_done),
        .job_gemm_done          (status_if.job_gemm_done),
        .job_store_done         (status_if.job_store_done),

        .job_dma_load_error     (status_if.job_dma_load_error),
        .job_axis_load_error    (status_if.job_axis_load_error),
        .job_ds_load_error      (status_if.job_ds_load_error),
        .job_dma_store_error    (status_if.job_dma_store_error),
        .job_sequence_error     (status_if.job_sequence_error),

        .job_state              (status_if.job_state),
        .job_perf_busy_cycles   (status_if.job_perf_busy_cycles),
        .job_perf_mac_count     (status_if.job_perf_mac_count),
        .job_perf_output_count  (status_if.job_perf_output_count),

        .recipe_busy            (status_if.recipe_busy),
        .recipe_done            (status_if.recipe_done),
        .recipe_all_slots_done  (status_if.recipe_all_slots_done),
        .recipe_final_store_done(status_if.recipe_final_store_done),

        .recipe_slot_job_error  (status_if.recipe_slot_job_error),
        .recipe_slot_job_reject (status_if.recipe_slot_job_reject),
        .recipe_sequence_error  (status_if.recipe_sequence_error),
        .recipe_slot_range_error(status_if.recipe_slot_range_error),
        .recipe_slot_descriptor_error(status_if.recipe_slot_descriptor_error),

        .recipe_state           (status_if.recipe_state),
        .recipe_current_slot    (status_if.recipe_current_slot),
        .recipe_completed_count (status_if.recipe_completed_count),
        .recipe_slot_done_mask  (status_if.recipe_slot_done_mask),
        .recipe_slot_error_mask (status_if.recipe_slot_error_mask),
        .recipe_slot_reject_mask(status_if.recipe_slot_reject_mask),
        .recipe_perf_busy_cycles(status_if.recipe_perf_busy_cycles),
        .recipe_perf_mac_count  (status_if.recipe_perf_mac_count),
        .recipe_perf_output_count(status_if.recipe_perf_output_count),

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
