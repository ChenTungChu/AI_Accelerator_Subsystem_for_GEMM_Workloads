// File: tb/uvm/test/ai_accel_subsys_csr_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_SMOKE_TEST_SV

// ------------------------------------------------------------
// CSR-controlled host-primary GEMM smoke test
//
// Scope:
//   - use the existing host AXI agent to preload A/B and read back C
//   - use the AXI-Lite CSR path to program GEMM config and issue start
//   - poll CSR sticky done/error status instead of driving sideband start
//   - compare C directly in the test
//   - CASE_ID=102 direct-base smoke also exercises split AW/W arrival
//     and extended software-visible CSR readback semantics
//
// This test intentionally disables the legacy sideband control/result
// scoreboard path.  The sideband control monitor does not observe the
// CSR-generated start pulse inside the wrapper, so this focused test
// checks the CSR-controlled path directly.
// ------------------------------------------------------------

class ai_accel_subsys_csr_smoke_test extends ai_accel_subsys_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_smoke_test)

    typedef virtual axi_lite_if #(
        .ADDR_WIDTH (12),
        .DATA_WIDTH (32)
    ) csr_vif_t;

    csr_vif_t                  csr_vif;
    ai_accel_csr_access_helper csr;

    // CODE-COV-C1.1-D1 P14 status/reject bits.  Keep the constants local to
    // the verification owner rather than extending the shared helper solely
    // for coverage closure.
    localparam int unsigned C1D1_P14_STATUS_GEMM_BUSY      = 0;
    localparam int unsigned C1D1_P14_STATUS_DMA_LOAD_BUSY  = 1;
    localparam int unsigned C1D1_P14_STATUS_AXIS_LOAD_BUSY = 2;
    localparam int unsigned C1D1_P14_STATUS_DS_LOAD_BUSY   = 3;
    localparam int unsigned C1D1_P14_STATUS_DMA_STORE_BUSY = 4;

    localparam int unsigned C1D1_P14_REJ_GEMM_BUSY      = 0;
    localparam int unsigned C1D1_P14_REJ_DMA_LOAD_BUSY  = 1;
    localparam int unsigned C1D1_P14_REJ_AXIS_BUSY      = 2;
    localparam int unsigned C1D1_P14_REJ_DS_BUSY        = 3;
    localparam int unsigned C1D1_P14_REJ_DMA_STORE_BUSY = 4;
    localparam int unsigned C1D1_P14_REJ_UNSUPPORTED    = 8;
    localparam int unsigned C1D1_P14_REJ_ZERO_LENGTH    = 9;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_csr_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(csr_vif_t)::get(this, "", "csr_vif", csr_vif)) begin
            `uvm_fatal("CSR_SMOKE/NOCSRVIF",
                "csr_vif is not set for ai_accel_subsys_csr_smoke_test")
        end

        csr = ai_accel_csr_access_helper::type_id::create("csr");
        csr.set_vif(csr_vif);

        // This is a host-primary CSR test regardless of run-script
        // defaults.  Keep the host agent active and force all memory
        // setup/readback through the host AXI path.
        enable_result_check       = 1'b1;
        force_helper_mem_path     = 1'b0;
        use_host_agent_clear_c    = 1'b1;
        use_host_agent_readback_c = 1'b1;
        use_host_agent_preload_ab = 1'b1;

        uvm_config_db#(uvm_active_passive_enum)::set(
            this, "env", "host_is_active", UVM_ACTIVE);

        // Disable legacy sideband scoreboard/checker expectations for
        // this focused CSR path.  The test performs the final C compare
        // directly after CSR_DONE_STATUS reports GEMM completion.
        uvm_config_db#(bit)::set(
            this, "env.scoreboard", "result_check_enable", 1'b0);

        uvm_config_db#(bit)::set(
            this, "env.host_traffic_checker", "enable_check", 1'b0);

        uvm_config_db#(bit)::set(
            this, "env.host_traffic_checker", "strict_check_enable", 1'b0);

        apply_csr_focused_report_policy();
    endfunction

    // ------------------------------------------------------------
    // End-of-elaboration phase
    // ------------------------------------------------------------
    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        apply_csr_focused_report_policy();
    endfunction

    // ------------------------------------------------------------
    // Start-of-simulation phase
    // ------------------------------------------------------------
    function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);
        apply_csr_focused_report_policy();
    endfunction

    // ------------------------------------------------------------
    // CSR-focused legacy report policy
    // ------------------------------------------------------------
    function void apply_csr_focused_report_policy();
        if ((env != null) && (env.scoreboard != null)) begin
            // The legacy scoreboard observes sideband acc_start/acc_done
            // traffic.  In this test, GEMM is launched by the CSR wrapper
            // and the C result is checked directly after CSR_DONE_STATUS.
            // Demote the expected legacy-sideband no-start summary so the
            // focused CSR test can report a clean pass/fail result.
            env.scoreboard.set_report_severity_id_override(
                UVM_ERROR, "SB/NOSTART", UVM_INFO);
        end

        if ((env != null) &&
            (env.agent != null) &&
            (env.agent.monitor != null)) begin
            // The sideband monitor can still see the public acc_done level,
            // but it does not see the internal CSR-generated acc_start pulse.
            // Demote that expected CSR-mode observation from WARNING to INFO.
            env.agent.monitor.set_report_severity_id_override(
                UVM_WARNING, "MON/DONE_WITHOUT_ACTIVE_JOB", UVM_INFO);
        end
    endfunction

    // ------------------------------------------------------------
    // CSR status helpers
    // ------------------------------------------------------------
    task automatic csr_clear_sticky_status();
        logic [31:0] clear_cmd;
    begin
        clear_cmd = 32'h0000_0000;
        clear_cmd[ai_accel_csr_access_helper::CMD_CLEAR_DONE]  = 1'b1;
        clear_cmd[ai_accel_csr_access_helper::CMD_CLEAR_ERROR] = 1'b1;
        clear_cmd[ai_accel_csr_access_helper::CMD_CLEAR_PERF]  = 1'b1;

        csr.issue_command(clear_cmd);
    end
    endtask

    // CODE-COV-C1.1-C: exercise the architectural direct W1C path on
    // P14 DONE_STATUS using a real completed GEMM sticky value.  Keep this
    // base-test-only so derived CSR tests retain their established cleanup.
    task automatic csr_direct_done_w1c_expect_clear();
        logic [31:0] before_status;
        logic [31:0] after_status;
    begin
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_DONE_STATUS,
            before_status
        );

        if (before_status == 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1C/P14_DONE_PRE",
                "Expected nonzero P14 DONE_STATUS before direct W1C")
        end

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DONE_STATUS,
            before_status
        );
        repeat (2) @(posedge csr_vif.clk);

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_DONE_STATUS,
            after_status
        );

        if ((after_status & before_status) != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1C/P14_DONE_W1C",
                $sformatf("P14 DONE direct W1C failed: before=0x%08h after=0x%08h",
                    before_status, after_status))
        end

        `uvm_info("CODE_COV_C1C/P14_DONE_W1C_PASS",
            $sformatf("P14 DONE direct W1C PASS: before=0x%08h after=0x%08h",
                before_status, after_status),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.1-D1 reusable P14 reject / busy helpers
    // ------------------------------------------------------------
    task automatic csr_wait_p14_status_bit(
        input int unsigned bit_idx,
        input int unsigned timeout_cycles,
        input string       tag
    );
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, error_status);

            if (error_status != 32'h0000_0000) begin
                `uvm_fatal("CODE_COV_C1D1/P14_BUSY_ERROR",
                    $sformatf("%s: P14 ERROR_STATUS became nonzero while waiting for busy bit %0d: status=0x%08h error=0x%08h",
                        tag, bit_idx, status, error_status))
            end

            if (status[bit_idx]) begin
                `uvm_info("CODE_COV_C1D1/P14_BUSY_OBSERVED",
                    $sformatf("%s: observed CSR_STATUS busy bit %0d, status=0x%08h",
                        tag, bit_idx, status),
                    UVM_MEDIUM)
                return;
            end

            if (done_status != 32'h0000_0000) begin
                `uvm_fatal("CODE_COV_C1D1/P14_BUSY_MISSED",
                    $sformatf("%s: operation completed before busy bit %0d was observed: status=0x%08h done=0x%08h",
                        tag, bit_idx, status, done_status))
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1D1/P14_BUSY_TIMEOUT",
                    $sformatf("%s: timed out waiting for CSR_STATUS busy bit %0d after %0d cycles",
                        tag, bit_idx, timeout_cycles))
            end
        end
    end
    endtask

    task automatic csr_expect_p14_reject_bit(
        input int unsigned bit_idx,
        input string       tag
    );
        logic [31:0] reject_status;
        logic [31:0] error_status;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, error_status);

        if (!reject_status[bit_idx]) begin
            `uvm_fatal("CODE_COV_C1D1/P14_REJECT_MISSING",
                $sformatf("%s: expected P14 reject bit %0d, reject=0x%08h error=0x%08h",
                    tag, bit_idx, reject_status, error_status))
        end
        if (error_status != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1D1/P14_REJECT_ERROR",
                $sformatf("%s: reject probe unexpectedly raised ERROR_STATUS=0x%08h reject=0x%08h",
                    tag, error_status, reject_status))
        end

        `uvm_info("CODE_COV_C1D1/P14_REJECT_PASS",
            $sformatf("%s: observed expected P14 reject bit %0d, reject=0x%08h",
                tag, bit_idx, reject_status),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_clear_p14_reject_status(input string tag);
        logic [31:0] before_status;
        logic [31:0] after_status;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, before_status);
        if (before_status == 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1D1/P14_REJECT_CLEAR_PRE",
                $sformatf("%s: expected nonzero P14 reject sticky before direct W1C", tag))
        end

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, before_status);
        repeat (2) @(posedge csr_vif.clk);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, after_status);
        if ((after_status & before_status) != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1D1/P14_REJECT_CLEAR",
                $sformatf("%s: P14 reject direct W1C failed: before=0x%08h after=0x%08h",
                    tag, before_status, after_status))
        end
    end
    endtask

    // Issue one direct AXI-Lite read and require SLVERR.  This is kept local
    // because these two negative ABI probes are the only D1 users; the shared
    // CSR helper remains unchanged.
    task automatic csr_read32_expect_slverr_direct(
        input logic [11:0] addr,
        input string       tag
    );
        int unsigned guard;
    begin
        @(posedge csr_vif.clk);
        csr_vif.araddr  <= addr;
        csr_vif.arvalid <= 1'b1;
        csr_vif.rready  <= 1'b1;

        guard = 0;
        while (!csr_vif.arready) begin
            @(posedge csr_vif.clk);
            guard++;
            if (guard > 100) begin
                `uvm_fatal("CODE_COV_C1D1/SLVERR_AR_TIMEOUT",
                    $sformatf("%s: timed out waiting for ARREADY at addr=0x%03h", tag, addr))
            end
        end
        @(posedge csr_vif.clk);
        csr_vif.arvalid <= 1'b0;

        guard = 0;
        while (!csr_vif.rvalid) begin
            @(posedge csr_vif.clk);
            guard++;
            if (guard > 100) begin
                `uvm_fatal("CODE_COV_C1D1/SLVERR_R_TIMEOUT",
                    $sformatf("%s: timed out waiting for RVALID at addr=0x%03h", tag, addr))
            end
        end

        if (csr_vif.rresp !== 2'b10) begin
            `uvm_fatal("CODE_COV_C1D1/SLVERR_RESP",
                $sformatf("%s: expected AXI-Lite SLVERR at addr=0x%03h, got RRESP=0x%0h RDATA=0x%08h",
                    tag, addr, csr_vif.rresp, csr_vif.rdata))
        end

        `uvm_info("CODE_COV_C1D1/INVALID_ADDR_PASS",
            $sformatf("%s: invalid CSR read correctly returned SLVERR at addr=0x%03h",
                tag, addr),
            UVM_MEDIUM)

        @(posedge csr_vif.clk);
        csr_vif.rready <= 1'b0;
    end
    endtask

    task automatic csr_check_d1_invalid_recipe_addresses();
    begin
        // 0x290 is word aligned and below the 0x300 recipe-slot window, but
        // is not a defined CSR.  It exercises the lower-bound guard.
        csr_read32_expect_slverr_direct(12'h290, "undefined address below recipe slot window");

        // 0x301 is inside the slot address range but is not word aligned.
        csr_read32_expect_slverr_direct(12'h301, "misaligned recipe slot address");
    end
    endtask

    task automatic csr_run_d1_p14_prestart_reject_checks(
        input ai_accel_subsys_seq_item profile_item
    );
        logic [31:0] cmd;
    begin
        csr_clear_sticky_status();
        csr_write_gemm_config(profile_item);

        // Exactly one START_* is legal.  Two simultaneous starts must be
        // rejected as an unsupported command combination.
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_START_GEMM]     = 1'b1;
        cmd[ai_accel_csr_access_helper::CMD_START_DMA_LOAD] = 1'b1;
        csr.issue_command(cmd);
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_p14_reject_bit(C1D1_P14_REJ_UNSUPPORTED,
            "P14 multi-start unsupported command combination");
        csr_clear_p14_reject_status("after P14 multi-start unsupported command combination");

        // A zero GEMM dimension is an architectural zero-length reject.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DIM_M, 32'h0000_0000);
        csr_start_gemm();
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_p14_reject_bit(C1D1_P14_REJ_ZERO_LENGTH,
            "P14 START_GEMM with DIM_M=0");
        csr_clear_p14_reject_status("after P14 zero-dimension reject");

        // Restore the selected profile before the normal accepted run.
        csr_write_gemm_config(profile_item);
        csr_clear_sticky_status();

        `uvm_info("CODE_COV_C1D1/P14_PRESTART_PASS",
            "P14 unsupported-combo and zero-dimension reject probes PASS",
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_inject_d1_gemm_busy_reject();
    begin
        csr_wait_p14_status_bit(
            C1D1_P14_STATUS_GEMM_BUSY,
            done_timeout_cycles,
            "accepted GEMM before busy-start reject");

        csr_start_gemm();
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_p14_reject_bit(C1D1_P14_REJ_GEMM_BUSY,
            "START_GEMM while GEMM busy");
        csr_clear_p14_reject_status("after START_GEMM while GEMM busy");

        `uvm_info("CODE_COV_C1D1/P14_GEMM_BUSY_PASS",
            "P14 START_GEMM while genuinely busy reject PASS",
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Extended CSR ABI preflight
    //
    // This phase is executed only by the direct CASE_ID=102 base smoke
    // item.  Derived CSR tests keep their original timing and setup flow.
    // The checks exercise legal software-visible behavior that is part of
    // the existing CSR contract rather than adding coverage-only behavior.
    // ------------------------------------------------------------
    task automatic csr_check_rw_readback_restore(
        input logic [11:0] addr,
        input logic [31:0] test_value,
        input logic [31:0] expected_value,
        input string       tag
    );
        logic [31:0] original_value;
    begin
        csr.read32_expect_okay(addr, original_value);

        csr.write32_expect_okay(addr, test_value);
        csr.expect_read32(
            addr,
            expected_value,
            $sformatf("%s write/readback", tag)
        );

        csr.write32_expect_okay(addr, original_value);
        csr.expect_read32(
            addr,
            original_value,
            $sformatf("%s restore", tag)
        );
    end
    endtask

    task automatic csr_check_split_write_protocol();
        logic [31:0] original_value;
    begin
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_A,
            original_value
        );

        csr.write32_aw_first_expect_okay(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_A,
            32'h0000_0120
        );
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_A,
            32'h0000_0120,
            "CSR_BASE_ADDR_A AW-first"
        );

        csr.write32_w_first_expect_okay(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_A,
            32'h0000_0240
        );
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_A,
            32'h0000_0240,
            "CSR_BASE_ADDR_A W-first"
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_A,
            original_value
        );
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_A,
            original_value,
            "CSR_BASE_ADDR_A split-write restore"
        );

        `uvm_info("CSR_SMOKE/AXIL_SPLIT_PASS",
            "AXI-Lite AW-first and W-first write-channel independence PASS",
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_check_command_read_zero();
    begin
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_COMMAND,
            32'h0000_0000,
            "CSR_COMMAND read-zero"
        );
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_JOB_COMMAND,
            32'h0000_0000,
            "CSR_JOB_COMMAND read-zero"
        );
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_RECIPE_COMMAND,
            32'h0000_0000,
            "CSR_RECIPE_COMMAND read-zero"
        );
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DESC_FETCH_COMMAND,
            32'h0000_0000,
            "CSR_DESC_FETCH_COMMAND read-zero"
        );
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_COMPLETION_WB_COMMAND,
            32'h0000_0000,
            "CSR_COMPLETION_WB_COMMAND read-zero"
        );
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_QUEUE_COMMAND,
            32'h0000_0000,
            "CSR_QUEUE_COMMAND read-zero"
        );
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_COMMAND,
            32'h0000_0000,
            "CSR_MEM_GUARD_COMMAND read-zero"
        );
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_TELEM_COMMAND,
            32'h0000_0000,
            "CSR_TELEM_COMMAND read-zero"
        );

        `uvm_info("CSR_SMOKE/CMD_RD0_PASS",
            "Extended write-only command-register read-zero checks PASS",
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_check_extended_config_readback();
        logic [11:0] slot0_addr;
    begin
        // Version registers that were not otherwise touched by the direct
        // host-primary smoke path.
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_JOB_VERSION,
            32'h0001_0015,
            "CSR_JOB_VERSION"
        );
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_RECIPE_VERSION,
            32'h0001_0016,
            "CSR_RECIPE_VERSION"
        );
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_QUEUE_VERSION,
            32'h0001_0019,
            "CSR_QUEUE_VERSION"
        );
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_VERSION,
            32'h0001_0027,
            "CSR_MEM_GUARD_VERSION"
        );

        // P15 job descriptor fields.
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_JOB_A_SRC_BASE,
            32'h0000_1100, 32'h0000_1100, "CSR_JOB_A_SRC_BASE");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_JOB_A_DST_BASE,
            32'h0000_1200, 32'h0000_1200, "CSR_JOB_A_DST_BASE");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_JOB_B_SRC_BASE,
            32'h0000_1300, 32'h0000_1300, "CSR_JOB_B_SRC_BASE");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_JOB_B_DST_BASE,
            32'h0000_1400, 32'h0000_1400, "CSR_JOB_B_DST_BASE");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_JOB_STORE_SRC_BASE,
            32'h0000_1500, 32'h0000_1500, "CSR_JOB_STORE_SRC_BASE");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_JOB_STORE_DST_BASE,
            32'h0000_1600, 32'h0000_1600, "CSR_JOB_STORE_DST_BASE");

        // P16 slot-0 software-visible descriptor fields.  One slot is
        // sufficient because all four slots share the same readback logic.
        slot0_addr = csr.recipe_slot_addr(
            0, ai_accel_csr_access_helper::SLOT_BASE_ADDR_A);
        csr_check_rw_readback_restore(
            slot0_addr, 32'h0000_2100, 32'h0000_2100, "RECIPE_SLOT0_BASE_ADDR_A");

        slot0_addr = csr.recipe_slot_addr(
            0, ai_accel_csr_access_helper::SLOT_BASE_ADDR_B);
        csr_check_rw_readback_restore(
            slot0_addr, 32'h0000_2200, 32'h0000_2200, "RECIPE_SLOT0_BASE_ADDR_B");

        slot0_addr = csr.recipe_slot_addr(
            0, ai_accel_csr_access_helper::SLOT_BASE_ADDR_C);
        csr_check_rw_readback_restore(
            slot0_addr, 32'h0000_2300, 32'h0000_2300, "RECIPE_SLOT0_BASE_ADDR_C");

        slot0_addr = csr.recipe_slot_addr(
            0, ai_accel_csr_access_helper::SLOT_A_SRC_BASE);
        csr_check_rw_readback_restore(
            slot0_addr, 32'h0000_2400, 32'h0000_2400, "RECIPE_SLOT0_A_SRC_BASE");

        slot0_addr = csr.recipe_slot_addr(
            0, ai_accel_csr_access_helper::SLOT_A_DST_BASE);
        csr_check_rw_readback_restore(
            slot0_addr, 32'h0000_2500, 32'h0000_2500, "RECIPE_SLOT0_A_DST_BASE");

        slot0_addr = csr.recipe_slot_addr(
            0, ai_accel_csr_access_helper::SLOT_B_SRC_BASE);
        csr_check_rw_readback_restore(
            slot0_addr, 32'h0000_2600, 32'h0000_2600, "RECIPE_SLOT0_B_SRC_BASE");

        slot0_addr = csr.recipe_slot_addr(
            0, ai_accel_csr_access_helper::SLOT_B_DST_BASE);
        csr_check_rw_readback_restore(
            slot0_addr, 32'h0000_2700, 32'h0000_2700, "RECIPE_SLOT0_B_DST_BASE");

        slot0_addr = csr.recipe_slot_addr(
            0, ai_accel_csr_access_helper::SLOT_STORE_SRC_BASE);
        csr_check_rw_readback_restore(
            slot0_addr, 32'h0000_2800, 32'h0000_2800, "RECIPE_SLOT0_STORE_SRC_BASE");

        slot0_addr = csr.recipe_slot_addr(
            0, ai_accel_csr_access_helper::SLOT_STORE_DST_BASE);
        csr_check_rw_readback_restore(
            slot0_addr, 32'h0000_2900, 32'h0000_2900, "RECIPE_SLOT0_STORE_DST_BASE");

        slot0_addr = csr.recipe_slot_addr(
            0, ai_accel_csr_access_helper::SLOT_USER_TAG);
        csr_check_rw_readback_restore(
            slot0_addr, 32'hC0DE_0001, 32'hC0DE_0001, "RECIPE_SLOT0_USER_TAG");

        // A valid reserved slot word reads zero and returns OKAY.
        slot0_addr = csr.recipe_slot_addr(0, 7'h44);
        csr.expect_read32(slot0_addr, 32'h0000_0000, "RECIPE_SLOT0_RESERVED_44");

        // P17 descriptor-fetch configuration and idle status readback.
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_DESC_FETCH_BASE_ADDR,
            32'h0000_3100, 32'h0000_3100, "CSR_DESC_FETCH_BASE_ADDR");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_DESC_FETCH_COUNT,
            32'h0000_0003, 32'h0000_0003, "CSR_DESC_FETCH_COUNT");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_DESC_FETCH_STRIDE_BYTES,
            32'h0000_0080, 32'h0000_0080, "CSR_DESC_FETCH_STRIDE_BYTES");
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DESC_FETCH_CURRENT_INDEX,
            32'h0000_0000,
            "CSR_DESC_FETCH_CURRENT_INDEX idle"
        );

        // P18 completion-writeback control readback.
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_COMPLETION_WB_CONTROL,
            32'h0000_000F, 32'h0000_000F, "CSR_COMPLETION_WB_CONTROL");

        // P19 queue configuration readback.  No START_QUEUE command is
        // issued, so these temporary values cannot launch runtime service.
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_QUEUE_CONTROL,
            32'h0000_0007, 32'h0000_0007, "CSR_QUEUE_CONTROL");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE,
            32'h0000_0700, 32'h0000_0700, "CSR_QUEUE_SQ_BASE");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH,
            32'h0000_0004, 32'h0000_0004, "CSR_QUEUE_SQ_DEPTH");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE,
            32'h0000_0040, 32'h0000_0040, "CSR_QUEUE_SQ_STRIDE");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE,
            32'h0000_0800, 32'h0000_0800, "CSR_QUEUE_CQ_BASE");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH,
            32'h0000_0004, 32'h0000_0004, "CSR_QUEUE_CQ_DEPTH");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE,
            32'h0000_0040, 32'h0000_0040, "CSR_QUEUE_CQ_STRIDE");

        // P27 memory-guard control and all software-visible region bounds.
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_CONTROL,
            32'h0000_11F3, 32'h0000_11F3, "CSR_MEM_GUARD_CONTROL");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_SQ_BASE,
            32'h0000_0900, 32'h0000_0900, "CSR_MEM_GUARD_SQ_BASE");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_SQ_LIMIT,
            32'h0000_0A00, 32'h0000_0A00, "CSR_MEM_GUARD_SQ_LIMIT");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_CQ_BASE,
            32'h0000_0A00, 32'h0000_0A00, "CSR_MEM_GUARD_CQ_BASE");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_CQ_LIMIT,
            32'h0000_0B00, 32'h0000_0B00, "CSR_MEM_GUARD_CQ_LIMIT");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_DESC_BASE,
            32'h0000_0300, 32'h0000_0300, "CSR_MEM_GUARD_DESC_BASE");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_DESC_LIMIT,
            32'h0000_0700, 32'h0000_0700, "CSR_MEM_GUARD_DESC_LIMIT");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_SRC_BASE,
            32'h0000_0000, 32'h0000_0000, "CSR_MEM_GUARD_SRC_BASE");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_SRC_LIMIT,
            32'h0000_2000, 32'h0000_2000, "CSR_MEM_GUARD_SRC_LIMIT");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_DST_BASE,
            32'h0000_0000, 32'h0000_0000, "CSR_MEM_GUARD_DST_BASE");
        csr_check_rw_readback_restore(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_DST_LIMIT,
            32'h0000_2000, 32'h0000_2000, "CSR_MEM_GUARD_DST_LIMIT");

        `uvm_info("CSR_SMOKE/EXT_RD_PASS",
            "Extended P15/P16/P17/P18/P19/P27 CSR readback checks PASS",
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_run_extended_abi_preflight();
    begin
        `uvm_info("CSR_SMOKE/ABI_PREFLIGHT",
            "Starting AXI-Lite split-channel and extended CSR ABI preflight",
            UVM_MEDIUM)

        csr_check_split_write_protocol();
        csr_check_command_read_zero();
        csr_check_extended_config_readback();
        csr_check_d1_invalid_recipe_addresses();

        `uvm_info("CSR_SMOKE/ABI_PREFLIGHT_PASS",
            "AXI-Lite split-channel and extended CSR ABI preflight PASS",
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_write_gemm_config(
        input ai_accel_subsys_seq_item profile_item
    );
        logic [31:0] mode_value;
    begin
        mode_value = 32'h0000_0000;
        mode_value[0] = 1'b0;  // scratchpad/host-primary input path
        mode_value[1] = profile_item.accumulate_enable;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MODE,
            mode_value
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_A,
            profile_item.base_addr_a
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_B,
            profile_item.base_addr_b
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_C,
            profile_item.base_addr_c
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DIM_M,
            32'(profile_item.dim_m)
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DIM_N,
            32'(profile_item.dim_n)
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DIM_K,
            32'(profile_item.dim_k)
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_A,
            profile_item.base_addr_a,
            "CSR_BASE_ADDR_A"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_B,
            profile_item.base_addr_b,
            "CSR_BASE_ADDR_B"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_C,
            profile_item.base_addr_c,
            "CSR_BASE_ADDR_C"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DIM_M,
            32'(profile_item.dim_m),
            "CSR_DIM_M"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DIM_N,
            32'(profile_item.dim_n),
            "CSR_DIM_N"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DIM_K,
            32'(profile_item.dim_k),
            "CSR_DIM_K"
        );

        `uvm_info("CSR_SMOKE",
            $sformatf("Programmed CSR GEMM config: case_id=%0d base_a=0x%08h base_b=0x%08h base_c=0x%08h dim=(%0d,%0d,%0d) mode=0x%08h",
                profile_item.case_id,
                profile_item.base_addr_a,
                profile_item.base_addr_b,
                profile_item.base_addr_c,
                profile_item.dim_m,
                profile_item.dim_n,
                profile_item.dim_k,
                mode_value),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_start_gemm();
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_START_GEMM] = 1'b1;
        csr.issue_command(cmd);

        `uvm_info("CSR_SMOKE",
            "Issued CSR START_GEMM command",
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_poll_gemm_done(
        input int unsigned timeout_cycles
    );
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_DONE_STATUS,
                done_status
            );

            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_ERROR_STATUS,
                error_status
            );

            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS,
                reject_status
            );

            if (error_status != 32'h0000_0000) begin
                `uvm_fatal("CSR_SMOKE/ERROR_STATUS",
                    $sformatf("CSR_ERROR_STATUS became nonzero: 0x%08h",
                        error_status))
            end

            if (reject_status != 32'h0000_0000) begin
                `uvm_fatal("CSR_SMOKE/REJECT_STATUS",
                    $sformatf("CSR_CMD_REJECT_STATUS became nonzero: 0x%08h",
                        reject_status))
            end

            if (done_status[ai_accel_csr_access_helper::DONE_GEMM]) begin
                `uvm_info("CSR_SMOKE",
                    $sformatf("Observed CSR GEMM done after %0d poll cycle(s): DONE_STATUS=0x%08h",
                        cnt, done_status),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("CSR_SMOKE/DONE_TIMEOUT",
                    $sformatf("Timed out waiting for CSR GEMM done after %0d cycles",
                        timeout_cycles))
            end
        end
    end
    endtask

    task automatic csr_check_perf_snapshot();
        logic [31:0] busy_cycles;
        logic [31:0] mac_count;
        logic [31:0] output_count;
    begin
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_PERF_BUSY_CYCLES,
            busy_cycles
        );

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_PERF_MAC_COUNT,
            mac_count
        );

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_PERF_OUTPUT_COUNT,
            output_count
        );

        `uvm_info("CSR_SMOKE",
            $sformatf("CSR perf snapshot: busy_cycles=%0d mac_count=%0d output_count=%0d",
                busy_cycles, mac_count, output_count),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Direct result compare
    // ------------------------------------------------------------
    task automatic compare_result_vectors(
        input int signed expected_c[],
        input int signed actual_c[]
    );
        int unsigned i;
        int unsigned mismatch_count;
    begin
        if (expected_c.size() != actual_c.size()) begin
            `uvm_fatal("CSR_SMOKE/SIZE",
                $sformatf("C result size mismatch: expected=%0d actual=%0d",
                    expected_c.size(), actual_c.size()))
        end

        mismatch_count = 0;

        for (i = 0; i < expected_c.size(); i++) begin
            if (expected_c[i] !== actual_c[i]) begin
                mismatch_count++;

                if (mismatch_count <= 8) begin
                    `uvm_error("CSR_SMOKE/MISMATCH",
                        $sformatf("C mismatch idx=%0d expected=%0d actual=%0d",
                            i, expected_c[i], actual_c[i]))
                end
            end
        end

        if (mismatch_count != 0) begin
            `uvm_fatal("CSR_SMOKE/COMPARE_FAIL",
                $sformatf("CSR-controlled GEMM result compare failed: mismatches=%0d/%0d",
                    mismatch_count, expected_c.size()))
        end

        `uvm_info("CSR_SMOKE",
            $sformatf("CSR-controlled GEMM result compare PASS: elements=%0d",
                expected_c.size()),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ai_accel_subsys_seq_item profile_item;
        int signed               expected_c[];
        int signed               actual_c[];
        bit                      have_expected_payload;
        bit                      have_actual_payload;
    begin
        phase.raise_objection(this);

        `uvm_info("CSR_SMOKE",
            "Starting CSR-controlled host-primary GEMM smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        if ((selected_test_kind != ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE) &&
            (selected_test_kind != ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE) &&
            (selected_test_kind != ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE)) begin
            `uvm_fatal("CSR_SMOKE/BAD_KIND",
                $sformatf("Unsupported CSR smoke test_kind=%0d CASE_ID=%0d",
                    selected_test_kind, selected_case_id))
        end

        profile_item = build_selected_profile_item();

        if ((get_type_name() == "ai_accel_subsys_csr_smoke_test") &&
            (selected_case_id == 102)) begin
            csr_run_extended_abi_preflight();
        end

        prepare_case_result_pre_start(
            expected_c,
            have_expected_payload
        );

        if (!have_expected_payload) begin
            `uvm_fatal("CSR_SMOKE/NO_EXPECTED",
                "Expected payload was not prepared")
        end

        if ((get_type_name() == "ai_accel_subsys_csr_smoke_test") &&
            (selected_case_id == 102)) begin
            csr_run_d1_p14_prestart_reject_checks(profile_item);
        end

        csr_clear_sticky_status();
        csr_write_gemm_config(profile_item);
        csr_start_gemm();
        if ((get_type_name() == "ai_accel_subsys_csr_smoke_test") &&
            (selected_case_id == 102)) begin
            csr_inject_d1_gemm_busy_reject();
        end
        csr_poll_gemm_done(done_timeout_cycles);
        csr_check_perf_snapshot();

        collect_case_actual_post_done(
            actual_c,
            have_actual_payload
        );

        if (!have_actual_payload) begin
            `uvm_fatal("CSR_SMOKE/NO_ACTUAL",
                "Actual C payload was not collected")
        end

        compare_result_vectors(expected_c, actual_c);

        if ((get_type_name() == "ai_accel_subsys_csr_smoke_test") &&
            (selected_case_id == 102)) begin
            csr_direct_done_w1c_expect_clear();
        end

        `uvm_info("CSR_SMOKE",
            $sformatf("CSR-controlled host-primary GEMM smoke completed: CASE_ID=%0d test_kind=%0d",
                selected_case_id, selected_test_kind),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
