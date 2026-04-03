// File: tb/test/back_to_back_run_smoke_test.sv

// ============================================================
// Back-to-back run smoke test
//
// Purpose:
// - Run multiple GEMM jobs in the same simulation
// - Verify repeated start/done behavior
// - Verify no stale state remains between runs
//
// Planned sequence:
//   RUN 0 -> fixed baseline CASE 0
//   RUN 1 -> fixed baseline CASE 2
//   RUN 2 -> variable-dimension CASE 101
// ============================================================

task automatic run_back_to_back_run_smoke_test();
begin
    $display("====================================================");
    $display("[INFO] BACK-TO-BACK RUN SMOKE TEST START");
    $display("====================================================");

    // --------------------------------------------------------
    // RUN 0: fixed baseline CASE 0
    // --------------------------------------------------------
    $display("[INFO] RUN 0: fixed baseline CASE 0");
    run_4x4_fixed_dimension_baseline_test(0);

    repeat (10) @(posedge dma_clk);

    // --------------------------------------------------------
    // RUN 1: fixed baseline CASE 2
    // --------------------------------------------------------
    $display("[INFO] RUN 1: fixed baseline CASE 2");
    run_4x4_fixed_dimension_baseline_test(2);

    repeat (10) @(posedge dma_clk);

    // --------------------------------------------------------
    // RUN 2: variable-dimension CASE 101
    // --------------------------------------------------------
    $display("[INFO] RUN 2: variable-dimension CASE 101");
    run_variable_dimension_smoke_test(101);

    repeat (10) @(posedge dma_clk);

    $display("====================================================");
    $display("[INFO] BACK-TO-BACK RUN SMOKE TEST PASS");
    $display("====================================================");
end
endtask