// File: tb/uvm/test/ai_accel_subsys_csr_completion_wb_error_busy_clear_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_COMPLETION_WB_ERROR_BUSY_CLEAR_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_COMPLETION_WB_ERROR_BUSY_CLEAR_TEST_SV

// ------------------------------------------------------------
// P18G completion-writeback error / busy / sticky clear handling
//
// Scope:
//   - CSR-triggered P18 completion writeback debug path only
//   - validates busy-start rejection while an accepted writeback is active
//   - validates base-alignment rejection
//   - validates AXI BRESP error propagation from the completion-memory model
//   - validates sticky done/error/reject clear behavior
//
// This test intentionally does not launch P17/P16/P15 recipes.  P18E/P18F
// already validate automatic descriptor-fetch completion writeback success
// paths.  P18G focuses on completion-writeback negative/control paths.
// ------------------------------------------------------------

class ai_accel_subsys_csr_completion_wb_error_busy_clear_test extends uvm_test;
    `uvm_component_utils(ai_accel_subsys_csr_completion_wb_error_busy_clear_test)

    typedef virtual axi_lite_if #(
        .ADDR_WIDTH (12),
        .DATA_WIDTH (32)
    ) csr_vif_t;

    virtual ai_accel_subsys_ctrl_if vif;
    csr_vif_t                       csr_vif;
    virtual comp_wb_inject_if       comp_wb_inject_vif;
    ai_accel_csr_access_helper      csr;

    localparam int unsigned COMP_BASE_ADDR_A = 32'h0000_0300;
    localparam int unsigned COMP_BASE_ADDR_B = 32'h0000_0380;
    localparam int unsigned COMP_BASE_BAD    = 32'h0000_0304; // not 64-bit aligned

    localparam logic [31:0] EXP_STATUS_FLAGS = 32'h0000_005A;
    localparam logic [31:0] EXP_USER_TAG_A   = 32'hD18A_0001;
    localparam logic [31:0] EXP_USER_TAG_B   = 32'hD18A_0002;
    localparam logic [31:0] EXP_COUNTS       = 32'h0001_0101;

    localparam int STATUS_BUSY_BIT      = 0;
    localparam int STATUS_DONE_BIT      = 1;
    localparam int STATUS_ANY_ERROR_BIT = 2;

    localparam int DONE_WRITE_BIT       = 0;
    localparam int ERROR_ENGINE_BIT     = 0;
    localparam int REJECT_BUSY_BIT      = 0;
    localparam int REJECT_ALIGN_BIT     = 1;
    localparam int C1D1_REJECT_UNSUPPORTED_BIT = 8;

    function new(string name = "ai_accel_subsys_csr_completion_wb_error_busy_clear_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("P18G_COMP_WB/NOVIF", "virtual interface ai_accel_subsys_ctrl_if is not set")
        end

        if (!uvm_config_db#(csr_vif_t)::get(this, "", "csr_vif", csr_vif)) begin
            `uvm_fatal("P18G_COMP_WB/NOCSRVIF", "csr_vif is not set")
        end

        if (!uvm_config_db#(virtual comp_wb_inject_if)::get(
                this,
                "",
                "comp_wb_inject_vif",
                comp_wb_inject_vif
            )) begin
            `uvm_fatal("P18G_COMP_WB/NO_COMP_WB_INJECT_VIF",
                "Missing completion-writeback injection virtual interface")
        end

        csr = ai_accel_csr_access_helper::type_id::create("csr");
        csr.set_vif(csr_vif);
    endfunction

    function automatic logic [31:0] bit_mask(input int bit_idx);
        return (32'h0000_0001 << bit_idx);
    endfunction

    task automatic csr_comp_wb_clear_all();
        logic [31:0] cmd;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::COMP_WB_CMD_CLEAR_DONE]  = 1'b1;
        cmd[ai_accel_csr_access_helper::COMP_WB_CMD_CLEAR_ERROR] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_COMMAND, cmd);

        repeat (3) @(posedge csr_vif.clk);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_DONE_STATUS, done_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_ERROR_STATUS, error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_REJECT_STATUS, reject_status);

        if (done_status != 32'h0000_0000 ||
            error_status != 32'h0000_0000 ||
            reject_status != 32'h0000_0000) begin
            `uvm_fatal("P18G_COMP_WB/CLEAR_FAIL",
                $sformatf("clear_all failed: done=0x%08h error=0x%08h reject=0x%08h",
                    done_status, error_status, reject_status))
        end
    end
    endtask

    task automatic program_manual_payload(
        input logic [31:0] base_addr,
        input logic [31:0] user_tag
    );
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_BASE_ADDR, base_addr);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_CONTROL, 32'h0000_0003); // enable + overall_done
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_STATUS_FLAGS, EXP_STATUS_FLAGS);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_USER_TAG, user_tag);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_COUNTS, EXP_COUNTS);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_RECIPE_DONE, 32'h0000_0001);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_RECIPE_ERROR, 32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_RECIPE_REJECT, 32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_PERF_MAC_COUNT, 32'h0000_0004);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_ERROR_DETAIL, 32'h0000_0000);
    end
    endtask

    task automatic start_completion_wb();
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::COMP_WB_CMD_START] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_COMMAND, cmd);
    end
    endtask

    task automatic wait_for_busy(input int unsigned timeout_cycles = 100);
        logic [31:0] status;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_STATUS, status);
            if (status[STATUS_BUSY_BIT]) begin
                `uvm_info("P18G_COMP_WB/BUSY",
                    $sformatf("Completion writeback busy observed after %0d poll(s): status=0x%08h", cnt, status),
                    UVM_LOW)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P18G_COMP_WB/BUSY_TIMEOUT",
                    $sformatf("Timed out waiting for completion writeback busy; last status=0x%08h", status))
            end
        end
    end
    endtask

    task automatic wait_for_done(input int unsigned timeout_cycles = 500);
        logic [31:0] status;
        logic [31:0] done_status;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            // Read the sticky DONE register first.  The STATUS read is a
            // separate AXI-Lite transaction, so reading STATUS first can see
            // the cycle immediately before the sticky DONE bit is captured.
            // Once DONE_STATUS is observed, wait one clock and read STATUS
            // again before checking the summary bit.
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_DONE_STATUS, done_status);

            if (done_status[DONE_WRITE_BIT]) begin
                @(posedge csr_vif.clk);
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_STATUS, status);

                if (!status[STATUS_DONE_BIT]) begin
                    `uvm_fatal("P18G_COMP_WB/DONE_STATUS_SUMMARY",
                        $sformatf("DONE_STATUS bit set but STATUS.DONE summary clear after resample: status=0x%08h done=0x%08h",
                            status, done_status))
                end
                `uvm_info("P18G_COMP_WB/DONE",
                    $sformatf("Completion writeback done after %0d poll(s): status=0x%08h done=0x%08h", cnt, status, done_status),
                    UVM_LOW)
                return;
            end

            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_STATUS, status);
            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P18G_COMP_WB/DONE_TIMEOUT",
                    $sformatf("Timed out waiting for completion writeback done; status=0x%08h done=0x%08h", status, done_status))
            end
        end
    end
    endtask

    task automatic wait_for_error(input int unsigned timeout_cycles = 300);
        logic [31:0] status;
        logic [31:0] error_status;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_ERROR_STATUS, error_status);

            if (error_status != 32'h0000_0000) begin
                @(posedge csr_vif.clk);
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_STATUS, status);

                if (!status[STATUS_ANY_ERROR_BIT]) begin
                    `uvm_fatal("P18G_COMP_WB/ERROR_SUMMARY",
                        $sformatf("ERROR_STATUS set but STATUS.ANY_ERROR clear after resample: status=0x%08h error=0x%08h",
                            status, error_status))
                end
                `uvm_info("P18G_COMP_WB/ERROR",
                    $sformatf("Completion writeback error observed after %0d poll(s): status=0x%08h error=0x%08h", cnt, status, error_status),
                    UVM_LOW)
                return;
            end

            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_STATUS, status);
            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P18G_COMP_WB/ERROR_TIMEOUT",
                    $sformatf("Timed out waiting for completion writeback error; status=0x%08h error=0x%08h", status, error_status))
            end
        end
    end
    endtask

    task automatic wait_for_reject(input int unsigned timeout_cycles = 100);
        logic [31:0] status;
        logic [31:0] reject_status;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_REJECT_STATUS, reject_status);

            if (reject_status != 32'h0000_0000) begin
                @(posedge csr_vif.clk);
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_STATUS, status);

                if (!status[STATUS_ANY_ERROR_BIT]) begin
                    `uvm_fatal("P18G_COMP_WB/REJECT_SUMMARY",
                        $sformatf("REJECT_STATUS set but STATUS.ANY_ERROR clear after resample: status=0x%08h reject=0x%08h",
                            status, reject_status))
                end
                `uvm_info("P18G_COMP_WB/REJECT",
                    $sformatf("Completion writeback reject observed after %0d poll(s): status=0x%08h reject=0x%08h", cnt, status, reject_status),
                    UVM_LOW)
                return;
            end

            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_STATUS, status);
            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P18G_COMP_WB/REJECT_TIMEOUT",
                    $sformatf("Timed out waiting for completion writeback reject; status=0x%08h reject=0x%08h", status, reject_status))
            end
        end
    end
    endtask

    task automatic expect_done_status(input logic [31:0] expected, input string tag);
        logic [31:0] actual;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_DONE_STATUS, actual);
        if (actual !== expected) begin
            `uvm_fatal("P18G_COMP_WB/DONE_MISMATCH",
                $sformatf("%s expected DONE_STATUS=0x%08h actual=0x%08h", tag, expected, actual))
        end
    end
    endtask

    task automatic expect_error_has(input logic [31:0] mask, input string tag);
        logic [31:0] actual;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_ERROR_STATUS, actual);
        if ((actual & mask) != mask) begin
            `uvm_fatal("P18G_COMP_WB/ERROR_MASK",
                $sformatf("%s expected ERROR_STATUS mask=0x%08h actual=0x%08h", tag, mask, actual))
        end
        `uvm_info("P18G_COMP_WB/CHECK",
            $sformatf("%s ERROR_STATUS PASS: actual=0x%08h mask=0x%08h", tag, actual, mask),
            UVM_LOW)
    end
    endtask

    task automatic expect_reject_has(input logic [31:0] mask, input string tag);
        logic [31:0] actual;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_REJECT_STATUS, actual);
        if ((actual & mask) != mask) begin
            `uvm_fatal("P18G_COMP_WB/REJECT_MASK",
                $sformatf("%s expected REJECT_STATUS mask=0x%08h actual=0x%08h", tag, mask, actual))
        end
        `uvm_info("P18G_COMP_WB/CHECK",
            $sformatf("%s REJECT_STATUS PASS: actual=0x%08h mask=0x%08h", tag, actual, mask),
            UVM_LOW)
    end
    endtask

    // CODE-COV-C1.1-C: direct W1C of a real completion-WB DONE sticky.
    task automatic p18g_direct_done_w1c_preserve_reject();
        logic [31:0] done_before;
        logic [31:0] done_after;
        logic [31:0] reject_before;
        logic [31:0] reject_after;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_DONE_STATUS, done_before);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_REJECT_STATUS, reject_before);

        if (done_before == 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1C/P18_DONE_PRE",
                "Expected nonzero completion-WB DONE_STATUS before direct W1C")
        end

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_DONE_STATUS, done_before);
        repeat (3) @(posedge csr_vif.clk);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_DONE_STATUS, done_after);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_REJECT_STATUS, reject_after);

        if ((done_after & done_before) != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1C/P18_DONE_W1C",
                $sformatf("Completion-WB DONE direct W1C failed: before=0x%08h after=0x%08h",
                    done_before, done_after))
        end
        if (reject_after !== reject_before) begin
            `uvm_fatal("CODE_COV_C1C/P18_DONE_ISOLATION",
                $sformatf("Completion-WB DONE direct W1C disturbed REJECT_STATUS: before=0x%08h after=0x%08h",
                    reject_before, reject_after))
        end

        `uvm_info("CODE_COV_C1C/P18_DONE_W1C_PASS",
            $sformatf("Completion-WB DONE direct W1C PASS: done 0x%08h->0x%08h reject preserved=0x%08h",
                done_before, done_after, reject_after),
            UVM_MEDIUM)
    end
    endtask

    task automatic run_busy_reject_case();
    begin
        `uvm_info("P18G_COMP_WB/BUSY_CASE", "Starting busy-start reject case", UVM_MEDIUM)

        csr_comp_wb_clear_all();
        program_manual_payload(COMP_BASE_ADDR_A, EXP_USER_TAG_A);

        start_completion_wb();
        wait_for_busy();

        // A second START while the engine is busy must not disturb the
        // already-accepted writeback.  It should set a sticky reject bit.
        start_completion_wb();
        wait_for_done();
        expect_done_status(bit_mask(DONE_WRITE_BIT), "busy case accepted writeback still completed");
        expect_reject_has(bit_mask(REJECT_BUSY_BIT), "busy-start reject");

        p18g_direct_done_w1c_preserve_reject();
        csr_comp_wb_clear_all();
    end
    endtask

    task automatic run_unaligned_reject_case();
    begin
        `uvm_info("P18G_COMP_WB/ALIGN_CASE", "Starting base-alignment reject case", UVM_MEDIUM)

        csr_comp_wb_clear_all();
        program_manual_payload(COMP_BASE_BAD, EXP_USER_TAG_A);
        start_completion_wb();
        wait_for_reject();

        expect_done_status(32'h0000_0000, "unaligned reject must not set done");
        expect_reject_has(bit_mask(REJECT_ALIGN_BIT), "unaligned-base reject");

        // Exercise W1C clear on reject status directly.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_REJECT_STATUS, 32'hFFFF_FFFF);
        repeat (3) @(posedge csr_vif.clk);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_COMPLETION_WB_REJECT_STATUS, 32'h0000_0000, "reject W1C clear");
    end
    endtask

    task automatic p18g_run_d1_unsupported_combo_on_real_error();
        logic [31:0] cmd;
        logic [31:0] error_before;
        logic [31:0] error_after;
        logic [31:0] reject_status;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_ERROR_STATUS, error_before);
        if (error_before == 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1D1/P18_UNSUPPORTED_PRE",
                "Expected genuine completion-WB error sticky before START+CLEAR_ERROR unsupported-combo probe")
        end

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::COMP_WB_CMD_START]       = 1'b1;
        cmd[ai_accel_csr_access_helper::COMP_WB_CMD_CLEAR_ERROR] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_COMMAND, cmd);
        repeat (3) @(posedge csr_vif.clk);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_ERROR_STATUS, error_after);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_REJECT_STATUS, reject_status);

        if (error_after !== error_before) begin
            `uvm_fatal("CODE_COV_C1D1/P18_UNSUPPORTED_ERROR_PRESERVE",
                $sformatf("Unsupported START+CLEAR_ERROR disturbed genuine ERROR_STATUS: before=0x%08h after=0x%08h",
                    error_before, error_after))
        end
        if (!reject_status[C1D1_REJECT_UNSUPPORTED_BIT]) begin
            `uvm_fatal("CODE_COV_C1D1/P18_UNSUPPORTED_MISSING",
                $sformatf("Expected completion-WB unsupported-command reject bit %0d, reject=0x%08h",
                    C1D1_REJECT_UNSUPPORTED_BIT, reject_status))
        end

        `uvm_info("CODE_COV_C1D1/P18_UNSUPPORTED_PASS",
            $sformatf("Completion-WB START+CLEAR_ERROR on genuine error rejected and error preserved: error=0x%08h reject=0x%08h",
                error_after, reject_status),
            UVM_MEDIUM)
    end
    endtask

    task automatic run_bresp_error_case();
    begin
        `uvm_info("P18G_COMP_WB/BRESP_CASE", "Starting completion-memory BRESP error case", UVM_MEDIUM)

        csr_comp_wb_clear_all();
        comp_wb_inject_vif.set_bresp_error(1'b1, 0);

        program_manual_payload(COMP_BASE_ADDR_B, EXP_USER_TAG_B);
        start_completion_wb();
        wait_for_error();
        expect_error_has(bit_mask(ERROR_ENGINE_BIT), "BRESP error propagation");
        expect_done_status(32'h0000_0000, "BRESP error must not set done");

        p18g_run_d1_unsupported_combo_on_real_error();

        comp_wb_inject_vif.clear();

        // Exercise W1C clear on error status directly.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_ERROR_STATUS, 32'hFFFF_FFFF);
        repeat (3) @(posedge csr_vif.clk);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_COMPLETION_WB_ERROR_STATUS, 32'h0000_0000, "error W1C clear");
    end
    endtask

    task run_phase(uvm_phase phase);
    begin
        phase.raise_objection(this);

        `uvm_info("P18G_COMP_WB", "Starting P18G completion writeback error / busy / sticky clear test", UVM_MEDIUM)

        repeat (10) @(posedge csr_vif.clk);
        vif.dma_dst_mem_clear();
        comp_wb_inject_vif.clear();

        csr.expect_read32(ai_accel_csr_access_helper::CSR_COMPLETION_WB_VERSION, 32'h0001_0018, "CSR_COMPLETION_WB_VERSION");

        run_busy_reject_case();
        run_unaligned_reject_case();
        run_bresp_error_case();

        csr_comp_wb_clear_all();
        comp_wb_inject_vif.clear();

        `uvm_info("P18G_COMP_WB/PASS", "P18G completion writeback error / busy / sticky clear handling completed", UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
