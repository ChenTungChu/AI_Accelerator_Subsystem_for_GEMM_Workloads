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
    // Tests
    // ------------------------------------------------------------
    `include "../test/ai_accel_subsys_smoke_test.sv"
    `include "../test/ai_accel_subsys_back_to_back_test.sv"
    `include "../test/ai_accel_subsys_reset_recovery_test.sv"
    `include "../test/ai_accel_subsys_corner_test.sv"
    `include "../test/ai_accel_subsys_midrun_reset_test.sv"
    `include "../test/ai_accel_subsys_dma_load_smoke_test.sv"
    `include "../test/ai_accel_subsys_dma_load_error_test.sv"
    `include "../test/ai_accel_subsys_dma_load_stress_test.sv"
    `include "../test/ai_accel_subsys_dma_store_smoke_test.sv"
    `include "../test/ai_accel_subsys_dma_store_error_test.sv"
    `include "../test/ai_accel_subsys_dma_load_store_stress_test.sv"
    `include "../test/ai_accel_subsys_axis_stream_preload_smoke_test.sv"
    `include "../test/ai_accel_subsys_axis_stream_preload_error_test.sv"
    `include "../test/ai_accel_subsys_axis_stream_load_store_stress_test.sv"

endpackage

`endif