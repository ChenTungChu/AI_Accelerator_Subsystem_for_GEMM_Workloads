// File: tb/uvm/pkg/ai_accel_subsys_uvm_pkg.sv
`ifndef AI_ACCEL_SUBSYS_UVM_PKG_SV
`define AI_ACCEL_SUBSYS_UVM_PKG_SV

package ai_accel_subsys_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ------------------------------------------------------------
    // Sequence item
    // ------------------------------------------------------------
    `include "../seq_item/ai_accel_subsys_seq_item.sv"

    // ------------------------------------------------------------
    // Result item
    // ------------------------------------------------------------
    `include "../item/ai_accel_subsys_result_item.sv"

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------
    `include "../helper/ai_accel_subsys_case_helper.sv"
    `include "../helper/ai_accel_subsys_axi_host_helper.sv"
    `include "../helper/ai_accel_csr_access_helper.sv"

    // ------------------------------------------------------------
    // Result bridge
    // ------------------------------------------------------------
    `include "../bridge/ai_accel_subsys_result_bridge.sv"

    // ------------------------------------------------------------
    // Host sequence item
    // ------------------------------------------------------------
    `include "../item/axi_mm_host_seq_item.sv"

    // ------------------------------------------------------------
    // Host sequencer
    // ------------------------------------------------------------
    `include "../sequencer/axi_mm_host_sequencer.sv"

    // ------------------------------------------------------------
    // Sequencer
    // ------------------------------------------------------------
    `include "../sequencer/ai_accel_subsys_sequencer.sv"

    // ------------------------------------------------------------
    // Host driver
    // ------------------------------------------------------------
    `include "../driver/axi_mm_host_driver.sv"

    // ------------------------------------------------------------
    // Driver
    // ------------------------------------------------------------
    `include "../driver/ai_accel_subsys_driver.sv"

    // ------------------------------------------------------------
    // Host monitor
    // ------------------------------------------------------------
    `include "../monitor/axi_mm_host_monitor.sv"

    // ------------------------------------------------------------
    // Monitor
    // ------------------------------------------------------------
    `include "../monitor/ai_accel_subsys_monitor.sv"

    // ------------------------------------------------------------
    // Scoreboard
    // ------------------------------------------------------------
    `include "../scoreboard/ai_accel_subsys_scoreboard.sv"

    // ------------------------------------------------------------
    // Host traffic checker
    // ------------------------------------------------------------
    `include "../checker/ai_accel_subsys_host_traffic_checker.sv"

    // ------------------------------------------------------------
    // Host agent
    // ------------------------------------------------------------
    `include "../agent/axi_mm_host_agent.sv"

    // ------------------------------------------------------------
    // Agent
    // ------------------------------------------------------------
    `include "../agent/ai_accel_subsys_agent.sv"

    // ------------------------------------------------------------
    // Env
    // ------------------------------------------------------------
    `include "../env/ai_accel_subsys_env.sv"

    // ------------------------------------------------------------
    // Host sequence
    // ------------------------------------------------------------
    `include "../seq/axi_mm_host_seq.sv"

    // ------------------------------------------------------------
    // Sequences
    // ------------------------------------------------------------
    `include "../seq/ai_accel_subsys_smoke_seq.sv"

    // ------------------------------------------------------------
    // Legacy sideband tests
    // ------------------------------------------------------------
    `include "../test/ai_accel_subsys_smoke_test.sv"
    `include "../test/ai_accel_subsys_back_to_back_test.sv"
    `include "../test/ai_accel_subsys_reset_recovery_test.sv"
    `include "../test/ai_accel_subsys_corner_test.sv"
    `include "../test/ai_accel_subsys_midrun_reset_test.sv"

    // ------------------------------------------------------------
    // DMA tests
    // ------------------------------------------------------------
    `include "../test/ai_accel_subsys_dma_load_smoke_test.sv"
    `include "../test/ai_accel_subsys_dma_load_error_test.sv"
    `include "../test/ai_accel_subsys_dma_load_stress_test.sv"
    `include "../test/ai_accel_subsys_dma_store_smoke_test.sv"
    `include "../test/ai_accel_subsys_dma_store_error_test.sv"
    `include "../test/ai_accel_subsys_dma_load_store_stress_test.sv"

    // ------------------------------------------------------------
    // AXI-Stream frontend tests
    // ------------------------------------------------------------
    `include "../test/ai_accel_subsys_axis_stream_preload_smoke_test.sv"
    `include "../test/ai_accel_subsys_axis_stream_preload_error_test.sv"
    `include "../test/ai_accel_subsys_axis_stream_load_store_stress_test.sv"

    // ------------------------------------------------------------
    // Direct Stream frontend tests
    // ------------------------------------------------------------
    `include "../test/ai_accel_subsys_direct_stream_smoke_test.sv"
    `include "../test/ai_accel_subsys_direct_stream_error_test.sv"
    `include "../test/ai_accel_subsys_direct_stream_load_store_stress_test.sv"

    // ------------------------------------------------------------
    // Performance tests
    // ------------------------------------------------------------
    `include "../test/ai_accel_subsys_perf_counter_smoke_test.sv"
    `include "../test/ai_accel_subsys_perf_profile_test.sv"

    // ------------------------------------------------------------
    // P14 CSR tests
    // ------------------------------------------------------------
    // NOTE: ai_accel_csr_regs_smoke_test.sv is intentionally not included here.
    // It is a standalone CSR-register-block test owned by ai_accel_csr_regs_uvm_top.sv.
    `include "../test/ai_accel_subsys_csr_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_dma_load_store_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_axis_stream_load_store_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_direct_stream_load_store_smoke_test.sv"

    // ------------------------------------------------------------
    // P15 CSR job-sequencer tests
    // ------------------------------------------------------------
    `include "../test/ai_accel_subsys_csr_job_dma_load_store_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_job_reject_error_test.sv"
    `include "../test/ai_accel_subsys_csr_job_frontend_mode_smoke_test.sv"

    // ------------------------------------------------------------
    // P16 CSR recipe-sequencer tests
    // ------------------------------------------------------------
    `include "../test/ai_accel_subsys_csr_recipe_dma_two_slot_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_recipe_c_rmw_two_slot_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_recipe_frontend_two_slot_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_recipe_reject_error_test.sv"

    // ------------------------------------------------------------
    // P17 descriptor-fetch tests
    // ------------------------------------------------------------
    `include "../test/ai_accel_subsys_csr_desc_fetch_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_desc_fetch_dma_two_slot_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_desc_fetch_c_rmw_two_slot_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_desc_fetch_direct_stream_two_slot_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_desc_fetch_reject_error_test.sv"

    // ------------------------------------------------------------
    // P18 completion-writeback tests
    // ------------------------------------------------------------
    `include "../test/ai_accel_subsys_csr_completion_wb_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_desc_fetch_dma_completion_wb_test.sv"
    `include "../test/ai_accel_subsys_csr_desc_fetch_direct_stream_completion_wb_test.sv"
    `include "../test/ai_accel_subsys_csr_desc_fetch_c_rmw_completion_wb_test.sv"
    `include "../test/ai_accel_subsys_csr_completion_wb_error_busy_clear_test.sv"

    // ------------------------------------------------------------
    // P19 command/completion queue tests
    // ------------------------------------------------------------
    `include "../test/ai_accel_subsys_csr_queue_desc_fetch_dma_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_queue_completion_wb_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_queue_reject_error_test.sv"

    // ------------------------------------------------------------
    // P20 multi-entry queue-drain tests
    // ------------------------------------------------------------
    `include "../test/ai_accel_subsys_csr_queue_two_command_dma_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_queue_mixed_dma_ds_c_rmw_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_queue_wraparound_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_queue_stop_behavior_smoke_test.sv"

    // ------------------------------------------------------------
    // P21 runtime doorbell / live queue service tests
    // ------------------------------------------------------------
    `include "../test/ai_accel_subsys_csr_queue_runtime_doorbell_dma_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_queue_runtime_doorbell_mixed_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_queue_cq_full_live_recovery_smoke_test.sv"
    `include "../test/ai_accel_subsys_csr_queue_stop_live_service_smoke_test.sv"

    // ------------------------------------------------------------
    // P22 Event notification / interrupt-lite integrated smoke
    // ------------------------------------------------------------
    `include "../test/ai_accel_subsys_event_csr_smoke_test.sv"

endpackage

`endif
