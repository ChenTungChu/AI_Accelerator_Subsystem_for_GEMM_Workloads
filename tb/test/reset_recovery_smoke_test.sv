// File: tb/test/reset_recovery_smoke_test.sv

// ============================================================
// Reset recovery smoke test
//
// Purpose:
// - Verify subsystem can run, reset, and run again
// - Verify clean recovery after reset
// - Reuse already validated fixed and variable tests
//
// Planned sequence:
//   RUN 0 -> fixed baseline CASE 0
//   RESET
//   RUN 1 -> fixed baseline CASE 2
//   RESET
//   RUN 2 -> variable-dimension CASE 101
// ============================================================

task automatic apply_subsystem_reset();
begin
    $display("[INFO] Apply subsystem reset");

    dma_rst_n <= 1'b0;
    core_rst_n <= 1'b0;
    acc_start <= 1'b0;

    // Put host IF outputs back to idle defaults
    axi0_if.awid    <= '0;
    axi0_if.awaddr  <= '0;
    axi0_if.awlen   <= '0;
    axi0_if.awsize  <= '0;
    axi0_if.awburst <= '0;
    axi0_if.awvalid <= 1'b0;

    axi0_if.wdata   <= '0;
    axi0_if.wstrb   <= '0;
    axi0_if.wlast   <= 1'b0;
    axi0_if.wvalid  <= 1'b0;

    axi0_if.bready  <= 1'b0;

    axi0_if.arid    <= '0;
    axi0_if.araddr  <= '0;
    axi0_if.arlen   <= '0;
    axi0_if.arsize  <= '0;
    axi0_if.arburst <= '0;
    axi0_if.arvalid <= 1'b0;

    axi0_if.rready  <= 1'b0;

    repeat (5) @(posedge dma_clk);
    repeat (5) @(posedge core_clk);

    $display("[INFO] Release subsystem reset");
    dma_rst_n <= 1'b1;
    core_rst_n <= 1'b1;

    repeat (5) @(posedge dma_clk);
    repeat (5) @(posedge core_clk);
end
endtask

task automatic run_reset_recovery_smoke_test();
begin
    $display("====================================================");
    $display("[INFO] RESET RECOVERY SMOKE TEST START");
    $display("====================================================");

    // --------------------------------------------------------
    // RUN 0
    // --------------------------------------------------------
    $display("[INFO] RUN 0: fixed baseline CASE 0");
    run_4x4_fixed_dimension_baseline_test(0);

    repeat (10) @(posedge dma_clk);

    // --------------------------------------------------------
    // RESET 0
    // --------------------------------------------------------
    apply_subsystem_reset();

    // --------------------------------------------------------
    // RUN 1
    // --------------------------------------------------------
    $display("[INFO] RUN 1: fixed baseline CASE 2");
    run_4x4_fixed_dimension_baseline_test(2);

    repeat (10) @(posedge dma_clk);

    // --------------------------------------------------------
    // RESET 1
    // --------------------------------------------------------
    apply_subsystem_reset();

    // --------------------------------------------------------
    // RUN 2
    // --------------------------------------------------------
    $display("[INFO] RUN 2: variable-dimension CASE 101");
    run_variable_dimension_smoke_test(101);

    repeat (10) @(posedge dma_clk);

    $display("====================================================");
    $display("[INFO] RESET RECOVERY SMOKE TEST PASS");
    $display("====================================================");
end
endtask