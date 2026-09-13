// File: tb/uvm/test/ai_accel_subsys_csr_mem_guard_dma_range_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_MEM_GUARD_DMA_RANGE_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_MEM_GUARD_DMA_RANGE_SMOKE_TEST_SV

// ============================================================
// P27E memory guard DMA source / destination range validation smoke
//
// Scope:
//   - Extends the P27D SQ/DESC guard validation to descriptor-payload
//     source and destination memory ranges.
//   - Runs one valid SQ + descriptor + source + destination guarded
//     command to prove that enabled SRC/DST checks preserve the normal
//     queue path.
//   - Shrinks the source-memory guard range so descriptor payload
//     validation rejects before any lower-level preload read can launch.
//   - Restores source range and shrinks the destination-memory guard
//     range so descriptor payload validation rejects before any lower-level
//     DMA store write can launch.
//   - Adds CODE-COV-C1.2-G7-Z4-A legal non-range failure probes for the
//     B-source and destination fallback-detail branches.
//   - Adds CODE-COV-C1.2-G7-Z4-C3-A legal STRICT_REJECT=0 and
//     mode-dependent zero-payload constructive probes.
//   - Adds CODE-COV-C1.2-G7-Z4-C4-A legal manual-policy / standalone
//     accumulate-enable CSR mux constructive probes after the queue path
//     has returned to a clean idle state.
//   - Clears guard / queue / event sticky state with the P26 lifecycle
//     cleanup policy and proves a known-good recovery command completes.
//
// P27E does not change SQ/CQ entry format, descriptor format,
// completion record format, event bit allocation, BRAM, GEMM, DMA,
// AXI-Stream, or Direct Stream datapath behavior.
// ============================================================

class ai_accel_subsys_csr_mem_guard_dma_range_smoke_test
    extends ai_accel_subsys_csr_queue_lifecycle_drained_reinit_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_mem_guard_dma_range_smoke_test)

    localparam int unsigned P27E_SQ_BASE     = 32'h0000_0D00;
    localparam int unsigned P27E_CQ_BASE     = 32'h0000_0E00;
    localparam int unsigned P27E_QUEUE_DEPTH = 4;

    localparam int unsigned P27E_DESC_BASE0  = 32'h0000_0300;
    localparam int unsigned P27E_DESC_BASE1  = 32'h0000_0400;
    localparam int unsigned P27E_DESC_STRIDE = 32'h0000_0080;

    localparam logic [31:0] P27E_BASELINE_CMD_TAG = 32'hD27E_0000;
    localparam logic [31:0] P27E_BAD_SRC_CMD_TAG  = 32'hD27E_0001;
    localparam logic [31:0] P27E_BAD_DST_CMD_TAG  = 32'hD27E_0002;
    localparam logic [31:0] P27E_RECOVERY_CMD_TAG = 32'hD27E_0003;

    // CODE-COV-C1.2-G7-G3 targeted payload-guard commands.
    // These remain legal queue commands; only the P27 guard configuration
    // or the memory-backed descriptor payload address is changed.
    localparam logic [31:0] G7_G3_BAD_B_SRC_CMD_TAG = 32'hD27E_0010;
    localparam logic [31:0] G7_G3_SPAN_CFG_CMD_TAG  = 32'hD27E_0011;
    localparam logic [31:0] G7_G3_OVERFLOW_CMD_TAG  = 32'hD27E_0012;

    // CODE-COV-C1.2-G7-Z2-B: legal full-width descriptor beat count
    // whose byte-size conversion exceeds 32 bits (0x2000_0000 * 8).
    localparam logic [31:0] G7_Z2_B_LARGE_SIZE_CMD_TAG = 32'hD27E_0020;

    // CODE-COV-C1.2-G7-Z4-A: legal non-range detail propagation probes.
    // The B-source case mirrors the proven Z2-B widened-size overflow, but
    // applies it to descriptor word 12 so the A payload passes first and the
    // B-specific detail fallback branch sees a non-zero ADDR_OVERFLOW code.
    // The destination case uses a legal host-programmed BASE==LIMIT region
    // to make the store-destination helper return SPAN_CONFIG directly.
    localparam logic [31:0] G7_Z4_A_B_LARGE_SIZE_CMD_TAG = 32'hD27E_0030;
    localparam logic [31:0] G7_Z4_A_DST_SPAN_CFG_CMD_TAG = 32'hD27E_0031;

    // CODE-COV-C1.2-G7-Z4-C3-A: legal P27 payload-wrapper control and
    // mode-dependent zero-payload probes.  These commands run only after
    // the original P27E/Z2/G3/Z4-A suite and its known-good recovery are
    // complete, preserving the already validated pointer/recovery flow.
    localparam logic [31:0] G7_Z4_C3_A_STRICT_OFF_CMD_TAG   = 32'hD27E_0040;
    localparam logic [31:0] G7_Z4_C3_A_ZERO_A_STORE_CMD_TAG = 32'hD27E_0041;
    localparam logic [31:0] G7_Z4_C3_A_ZERO_B_CMD_TAG       = 32'hD27E_0042;

    localparam logic [31:0] G7_Z4_C3_A_CTRL_HOST_PRELOADED_HOST_READBACK = 32'h0000_0001;

    // CODE-COV-C1.2-G7-Z4-C4-A: legal CSR-only effective-control mux
    // probe masks.  These bit positions are the canonical CSR definitions:
    //   RECIPE_CONTROL[10:8] = accumulate_perf / clear_job_sticky / stop_on_error
    //   JOB_MODE[4]          = accumulate_enable
    //   MODE[1]              = accumulate_enable
    localparam logic [31:0] G7_Z4_C4_A_RECIPE_POLICY_MASK = 32'h0000_0700;
    localparam logic [31:0] G7_Z4_C4_A_JOB_ACCUM_MASK     = 32'h0000_0010;
    localparam logic [31:0] G7_Z4_C4_A_MODE_ACCUM_MASK    = 32'h0000_0002;

    localparam int unsigned G7_Z4_C3_A_DESC_WORD_CONTROL          = 0;
    localparam int unsigned G7_G3_DESC_WORD_A_SRC_BASE             = 7;
    localparam int unsigned G7_Z2_B_DESC_WORD_A_LOAD_BEATS = 9;
    localparam int unsigned G7_Z4_A_DESC_WORD_B_LOAD_BEATS = 12;
    localparam int unsigned G7_Z4_C3_A_DESC_WORD_STORE_BYTE_COUNT = 15;
    localparam logic [31:0] G7_Z2_B_A_LOAD_BEATS = 32'h2000_0000;
    localparam logic [31:0] G7_Z4_A_B_LOAD_BEATS = 32'h2000_0000;

    localparam logic [31:0] P27E_DESC0_TAG0 = 32'hD27E_1000;
    localparam logic [31:0] P27E_DESC0_TAG1 = 32'hD27E_1001;
    localparam logic [31:0] P27E_DESC1_TAG0 = 32'hD27E_2000;
    localparam logic [31:0] P27E_DESC1_TAG1 = 32'hD27E_2001;

    function new(string name = "ai_accel_subsys_csr_mem_guard_dma_range_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p27e_make_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg
    );
    begin
        rt.make_default_queue_cfg(
            cfg,
            32'(P27E_SQ_BASE),
            32'(P27E_CQ_BASE),
            32'(P27E_QUEUE_DEPTH),
            1'b1
        );
    end
    endtask

    task automatic p27e_make_cmd(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd,
        input  logic [31:0] desc_base,
        input  logic [31:0] user_tag
    );
    begin
        rt.make_fetch_recipe_cmd(
            cmd,
            desc_base,
            32'h0000_0002,
            32'(P27E_DESC_STRIDE),
            user_tag,
            1'b1,
            1'b0
        );
        cmd.timeout_cycles = 32'h0000_0000;
    end
    endtask

    task automatic p27e_make_guard_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        input  ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input  logic [31:0] src_limit_override,
        input  logic [31:0] dst_limit_override,
        output ai_accel_event_driven_host_runtime_stress_helper::p27_guard_cfg_t guard_cfg
    );
        logic [31:0] control;
        logic [31:0] sq_size_bytes;
        logic [31:0] cq_size_bytes;
    begin
        control = rt.host_rt_mem_guard_control_value(
            1'b1, // guard_enable
            1'b1, // strict_reject_enable
            1'b1, // SQ check
            1'b1, // CQ check
            1'b1, // descriptor check
            1'b1, // source check
            1'b1, // destination check
            1'b1  // write CQ error if safe
        );

        sq_size_bytes = cfg.sq_depth * cfg.sq_stride;
        cq_size_bytes = cfg.cq_depth * cfg.cq_stride;

        guard_cfg.control    = control;
        guard_cfg.sq_base    = cfg.sq_base;
        guard_cfg.sq_limit   = rt.host_rt_mem_guard_span_limit(cfg.sq_base, sq_size_bytes);
        guard_cfg.cq_base    = cfg.cq_base;
        guard_cfg.cq_limit   = rt.host_rt_mem_guard_span_limit(cfg.cq_base, cq_size_bytes);
        guard_cfg.desc_base  = 32'(P27E_DESC_BASE0);
        guard_cfg.desc_limit = rt.host_rt_mem_guard_span_limit(32'(P27E_DESC_BASE0), 32'h0000_0200);
        guard_cfg.src_base   = 32'h0000_0000;
        guard_cfg.src_limit  = (src_limit_override != 32'h0000_0000) ?
                               src_limit_override :
                               32'h0000_2000;
        guard_cfg.dst_base   = 32'h0000_0000;
        guard_cfg.dst_limit  = (dst_limit_override != 32'h0000_0000) ?
                               dst_limit_override :
                               32'h0000_2000;
    end
    endtask

    task automatic p27e_cleanup_after_guard_error(
        input ai_accel_event_driven_host_runtime_stress_helper rt,
        ref   ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input string label
    );
        ai_accel_event_driven_host_runtime_stress_helper::p26_lifecycle_snapshot_t snap;
    begin
        rt.host_rt_lifecycle_wait_idle(
            {label, " wait_idle"},
            ai_accel_event_driven_host_runtime_stress_helper::P26_DEFAULT_LIFECYCLE_TIMEOUT_CYCLES,
            1'b1
        );

        rt.host_rt_lifecycle_capture_snapshot(snap, {label, " snapshot"}, 1'b1);

        // No completion commit is expected for the P27E negative cases.
        // Align host-owned pointers back to the hardware-owned monotonic epoch.
        cfg.sq_head = snap.sq_head;
        cfg.sq_tail = snap.sq_head;
        cfg.cq_head = snap.cq_tail;
        cfg.cq_tail = snap.cq_tail;

        rt.host_rt_mem_guard_clear_for_reuse(1'b1, 1'b1, {label, " clear_for_reuse"});
        rt.host_rt_lifecycle_clear_queue_all_sticky(1'b1, {label, " queue_clear_all"});
        rt.host_rt_lifecycle_clear_lower_sticky({label, " lower_clear"});
        rt.host_rt_lifecycle_recycle_sq_slots(cfg, 0, cfg.sq_depth, {label, " recycle_sq"});
        rt.host_rt_lifecycle_recycle_cq_slots(cfg, 0, cfg.cq_depth, {label, " recycle_cq"});
        rt.program_queue(cfg);
        rt.host_rt_lifecycle_check_clean_idle({label, " clean_idle"}, 1'b0, 1'b1, 1'b0);

        `uvm_info("P27E_GUARD/CLEANUP_PASS",
            $sformatf("%s: guard error cleanup PASS SQ(h/t)=%0d/%0d CQ(h/t)=%0d/%0d",
                label,
                cfg.sq_head,
                cfg.sq_tail,
                cfg.cq_head,
                cfg.cq_tail),
            UVM_MEDIUM)
    end
    endtask

    task automatic p27e_run_guard_negative_case(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        ref    ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input  ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd,
        input  int unsigned sq_idx,
        input  logic [31:0] next_tail,
        input  logic [31:0] required_error_mask,
        input  logic [31:0] expected_domain,
        input  logic [7:0]  expected_detail,
        input  string       pass_id,
        input  string       label
    );
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t snap;
        logic [31:0] event_mask;
    begin
        event_mask = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_ERROR);

        rt.host_rt_lifecycle_rearm_events(
            event_mask,
            1'b1,
            32'h0000_0000,
            1'b1,
            {label, " event_rearm"}
        );

        rt.submit_command_and_doorbell(cfg, sq_idx, cmd, next_tail);
        rt.start_queue();

        rt.wait_for_progress_event(
            event_mask,
            snap,
            {label, " event wait"},
            ai_accel_event_driven_host_runtime_stress_helper::P27_DEFAULT_GUARD_TIMEOUT_CYCLES,
            1'b1
        );
        p25c_check_event_snapshot(label, snap, event_mask);

        if (!snap.queue_status[2]) begin
            `uvm_fatal("P27E_GUARD/NO_QUEUE_ERROR_STATUS",
                $sformatf("%s: expected QUEUE_STATUS.QUEUE_ERROR, status=0x%08h error=0x%08h",
                    label,
                    snap.queue_status,
                    snap.queue_error_status))
        end

        rt.host_rt_mem_guard_expect_error(
            required_error_mask,
            expected_domain,
            expected_detail,
            {label, " expected_error"}
        );

        `uvm_info(pass_id,
            $sformatf("%s: expected memory guard reject observed domain=%s detail=%s pending=0x%08h queue_error=0x%08h",
                label,
                rt.host_rt_mem_guard_domain_name(expected_domain),
                rt.host_rt_mem_guard_detail_name(expected_detail),
                snap.event_snap.pending,
                snap.queue_error_status),
            UVM_MEDIUM)

        p27e_cleanup_after_guard_error(rt, cfg, label);
    end
    endtask

    task automatic g7_z4_c4_a_run_manual_policy_accumulate_probe(
        input ai_accel_event_driven_host_runtime_stress_helper rt
    );
        logic [31:0] recipe_control_saved;
        logic [31:0] recipe_control_target;
        logic [31:0] recipe_control_readback;
        logic [31:0] job_mode_saved;
        logic [31:0] job_mode_target;
        logic [31:0] job_mode_readback;
        logic [31:0] mode_saved;
        logic [31:0] mode_target;
        logic [31:0] mode_readback;
        logic [31:0] desc_status;
        logic [31:0] recipe_status;
        logic [31:0] job_status;
        logic [31:0] p14_status;
    begin
        `uvm_info("CODE_COV_C1P2_G7_Z4_C4_A/START",
            "Starting legal manual recipe-policy-zero and standalone accumulate-enable constructive probes",
            UVM_MEDIUM)

        // Enter from the already proven C3-A clean endpoint.  The CSR-only
        // states below are deliberately held while P17/P16/P15/P14 are idle;
        // no command pulse, force/deposit, or hierarchical DUT mutation is used.
        rt.host_rt_lifecycle_check_clean_idle(
            "G7-Z4-C4-A pre-probe clean idle",
            1'b0,
            1'b1,
            1'b0
        );

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_STATUS, desc_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_STATUS, recipe_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_STATUS, job_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, p14_status);
        if (desc_status[0] || recipe_status[0] || job_status[0] || p14_status[0]) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C4_A/PRE_IDLE",
                $sformatf("Expected P17/P16/P15/P14 idle before C4-A probe: desc=0x%08h recipe=0x%08h job=0x%08h p14=0x%08h",
                    desc_status, recipe_status, job_status, p14_status))
        end

        // --------------------------------------------------------
        // Window 1: lines 2326 / 2331 / 2333.
        // Keep the P17 auto-recipe selector inactive and clear only the
        // three host-programmable manual recipe policy bits.  For each
        // ternary this makes selector=0 and selected CSR value=0, so both
        // previously masked terms become decisive in legal software state.
        // --------------------------------------------------------
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_RECIPE_CONTROL,
            recipe_control_saved
        );
        recipe_control_target = recipe_control_saved & ~G7_Z4_C4_A_RECIPE_POLICY_MASK;
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_RECIPE_CONTROL,
            recipe_control_target,
            4'hF
        );
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_RECIPE_CONTROL,
            recipe_control_readback
        );
        if (recipe_control_readback !== recipe_control_target) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C4_A/RECIPE_POLICY_RD",
                $sformatf("RECIPE_CONTROL policy-zero readback mismatch: expected=0x%08h actual=0x%08h saved=0x%08h",
                    recipe_control_target, recipe_control_readback, recipe_control_saved))
        end
        if ((recipe_control_readback & G7_Z4_C4_A_RECIPE_POLICY_MASK) != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C4_A/RECIPE_POLICY_BITS",
                $sformatf("RECIPE_CONTROL[10:8] must be zero for C4-A target, got 0x%08h",
                    recipe_control_readback))
        end

        // Additional legal read transactions keep the policy-zero state
        // stable across multiple DMA-clock cycles and reconfirm no producer
        // became active while the effective-control mux is being sampled.
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_STATUS, desc_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_STATUS, recipe_status);
        if (desc_status[0] || recipe_status[0]) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C4_A/RECIPE_POLICY_IDLE",
                $sformatf("Unexpected P17/P16 activity during policy-zero window: desc=0x%08h recipe=0x%08h",
                    desc_status, recipe_status))
        end

        `uvm_info("CODE_COV_C1P2_G7_Z4_C4_A/RECIPE_POLICY_ZERO_PASS",
            $sformatf("Manual recipe policy-zero window held legally: RECIPE_CONTROL saved=0x%08h target/readback=0x%08h",
                recipe_control_saved, recipe_control_readback),
            UVM_MEDIUM)

        // --------------------------------------------------------
        // Window 2: line 2490.
        // With recipe_busy=0, set the standalone P15 JOB_MODE accumulate
        // bit.  This makes csr_job_accumulate_enable=1 the selected mux arm.
        // --------------------------------------------------------
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_MODE, job_mode_saved);
        job_mode_target = job_mode_saved | G7_Z4_C4_A_JOB_ACCUM_MASK;
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_MODE,
            job_mode_target,
            4'hF
        );
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_MODE, job_mode_readback);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_STATUS, recipe_status);
        if (job_mode_readback !== job_mode_target) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C4_A/JOB_ACCUM_RD",
                $sformatf("JOB_MODE accumulate=1 readback mismatch: expected=0x%08h actual=0x%08h saved=0x%08h",
                    job_mode_target, job_mode_readback, job_mode_saved))
        end
        if (!job_mode_readback[4] || recipe_status[0]) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C4_A/JOB_ACCUM_STATE",
                $sformatf("Expected standalone JOB accumulate=1 with recipe_busy=0: job_mode=0x%08h recipe_status=0x%08h",
                    job_mode_readback, recipe_status))
        end

        `uvm_info("CODE_COV_C1P2_G7_Z4_C4_A/JOB_ACCUM_PASS",
            $sformatf("Standalone P15 accumulate-enable window held legally: JOB_MODE saved=0x%08h target/readback=0x%08h recipe_busy=0",
                job_mode_saved, job_mode_readback),
            UVM_MEDIUM)

        // --------------------------------------------------------
        // Window 3: line 2631.
        // With job_busy=0, set the standalone P14 MODE accumulate bit.
        // This makes csr_accumulate_enable=1 the selected subsystem mux arm.
        // --------------------------------------------------------
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_MODE, mode_saved);
        mode_target = mode_saved | G7_Z4_C4_A_MODE_ACCUM_MASK;
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MODE,
            mode_target,
            4'hF
        );
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_MODE, mode_readback);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_STATUS, job_status);
        if (mode_readback !== mode_target) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C4_A/P14_ACCUM_RD",
                $sformatf("MODE accumulate=1 readback mismatch: expected=0x%08h actual=0x%08h saved=0x%08h",
                    mode_target, mode_readback, mode_saved))
        end
        if (!mode_readback[1] || job_status[0]) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C4_A/P14_ACCUM_STATE",
                $sformatf("Expected standalone P14 accumulate=1 with job_busy=0: mode=0x%08h job_status=0x%08h",
                    mode_readback, job_status))
        end

        `uvm_info("CODE_COV_C1P2_G7_Z4_C4_A/P14_ACCUM_PASS",
            $sformatf("Standalone P14 accumulate-enable window held legally: MODE saved=0x%08h target/readback=0x%08h job_busy=0",
                mode_saved, mode_readback),
            UVM_MEDIUM)

        // Restore all host-visible controls exactly as found so this remains
        // a non-destructive coverage probe even if later phases are appended.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MODE, mode_saved, 4'hF);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_MODE, job_mode_saved, 4'hF);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_CONTROL, recipe_control_saved, 4'hF);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_MODE, mode_readback);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_MODE, job_mode_readback);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_CONTROL, recipe_control_readback);
        if ((mode_readback !== mode_saved) ||
            (job_mode_readback !== job_mode_saved) ||
            (recipe_control_readback !== recipe_control_saved)) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C4_A/RESTORE",
                $sformatf("CSR restore mismatch: MODE 0x%08h/0x%08h JOB_MODE 0x%08h/0x%08h RECIPE_CONTROL 0x%08h/0x%08h",
                    mode_saved, mode_readback,
                    job_mode_saved, job_mode_readback,
                    recipe_control_saved, recipe_control_readback))
        end

        rt.host_rt_lifecycle_check_clean_idle(
            "G7-Z4-C4-A post-probe clean idle",
            1'b0,
            1'b1,
            1'b0
        );

        `uvm_info("CODE_COV_C1P2_G7_Z4_C4_A/RESTORE_PASS",
            "Restored RECIPE_CONTROL, JOB_MODE, and MODE exactly after C4-A constructive windows",
            UVM_MEDIUM)

        `uvm_info("CODE_COV_C1P2_G7_Z4_C4_A/PASS",
            "C4-A legal manual recipe-policy-zero and standalone P15/P14 accumulate-enable constructive probes completed",
            UVM_MEDIUM)
    end
    endtask

    task run_phase(uvm_phase phase);
        ai_accel_subsys_seq_item profile_item;
        int signed               a_flat[];
        int signed               b_flat[];
        int signed               expected_c[];
        int signed               actual_c[];
        int unsigned             c_elems;
        int unsigned             c_bytes;

        ai_accel_event_driven_host_runtime_stress_helper rt;
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t baseline_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t bad_src_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t bad_dst_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t recovery_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t g7_g3_bad_b_src_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t g7_g3_span_cfg_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t g7_g3_overflow_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t g7_z2_b_large_size_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t g7_z4_a_b_large_size_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t g7_z4_a_dst_span_cfg_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t g7_z4_c3_a_strict_off_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t g7_z4_c3_a_zero_a_store_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t g7_z4_c3_a_zero_b_cmd;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t baseline_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t recovery_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t g7_z4_c3_a_strict_off_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t g7_z4_c3_a_zero_a_store_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t g7_z4_c3_a_zero_b_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p27_guard_cfg_t guard_cfg;

        logic [31:0] event_mask;
        logic [31:0] bad_src_base;
        logic [31:0] bad_dst_limit;
        logic [31:0] g7_g3_guard_control_readback;
        logic [31:0] g7_z4_c3_a_guard_control_readback;
    begin
        phase.raise_objection(this);

        `uvm_info("P27E_GUARD/START",
            "Starting P27E DMA source / destination memory guard range validation smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        rt = ai_accel_event_driven_host_runtime_stress_helper::type_id::create("rt");
        rt.set_csr(csr);
        rt.set_ctrl_vif(p17d_ctrl_vif);

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        prepare_dma_source_and_destination(a_flat, b_flat);

        p25c_program_descriptor_table(
            P27E_DESC_BASE0,
            P27E_DESC0_TAG0,
            P27E_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p25c_program_descriptor_table(
            P27E_DESC_BASE1,
            P27E_DESC1_TAG0,
            P27E_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p27e_make_cfg(rt, cfg);
        p27e_make_cmd(rt, baseline_cmd,       32'(P27E_DESC_BASE0), P27E_BASELINE_CMD_TAG);
        p27e_make_cmd(rt, bad_src_cmd,        32'(P27E_DESC_BASE0), P27E_BAD_SRC_CMD_TAG);
        p27e_make_cmd(rt, bad_dst_cmd,        32'(P27E_DESC_BASE1), P27E_BAD_DST_CMD_TAG);
        p27e_make_cmd(rt, recovery_cmd,       32'(P27E_DESC_BASE1), P27E_RECOVERY_CMD_TAG);
        p27e_make_cmd(rt, g7_g3_bad_b_src_cmd,32'(P27E_DESC_BASE0), G7_G3_BAD_B_SRC_CMD_TAG);
        p27e_make_cmd(rt, g7_g3_span_cfg_cmd, 32'(P27E_DESC_BASE0), G7_G3_SPAN_CFG_CMD_TAG);
        p27e_make_cmd(rt, g7_g3_overflow_cmd, 32'(P27E_DESC_BASE0), G7_G3_OVERFLOW_CMD_TAG);
        p27e_make_cmd(rt, g7_z2_b_large_size_cmd, 32'(P27E_DESC_BASE0), G7_Z2_B_LARGE_SIZE_CMD_TAG);
        p27e_make_cmd(rt, g7_z4_a_b_large_size_cmd, 32'(P27E_DESC_BASE0), G7_Z4_A_B_LARGE_SIZE_CMD_TAG);
        p27e_make_cmd(rt, g7_z4_a_dst_span_cfg_cmd, 32'(P27E_DESC_BASE0), G7_Z4_A_DST_SPAN_CFG_CMD_TAG);
        p27e_make_cmd(rt, g7_z4_c3_a_strict_off_cmd, 32'(P27E_DESC_BASE1), G7_Z4_C3_A_STRICT_OFF_CMD_TAG);
        p27e_make_cmd(rt, g7_z4_c3_a_zero_a_store_cmd, 32'(P27E_DESC_BASE0), G7_Z4_C3_A_ZERO_A_STORE_CMD_TAG);
        p27e_make_cmd(rt, g7_z4_c3_a_zero_b_cmd, 32'(P27E_DESC_BASE0), G7_Z4_C3_A_ZERO_B_CMD_TAG);

        event_mask = rt.queue_completion_event_mask() |
                     rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);

        // These intentionally exclude one descriptor payload range while
        // preserving a non-empty legal guard span.  G7-Z2-A raises the SRC
        // lower bound above the slot0 A/B payload address so the payload
        // helper's lower-bound comparison is the decisive range failure.
        // The destination limit keeps the original P27E upper-bound reject.
        bad_src_base  = 32'h0000_0004;
        bad_dst_limit = 32'h0000_0020;

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_program_completion_wb();

        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'h0000_0000, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "P27E valid baseline guard cfg");
        rt.host_rt_mem_guard_check_clean("P27E initial guard clean", 1'b1, 1'b0);

        rt.host_rt_lifecycle_init_session(
            cfg,
            event_mask,
            1'b1,
            1'b1,
            "P27E initial lifecycle init"
        );

        p26d_run_drained_session_without_cleanup(
            rt,
            cfg,
            baseline_cmd,
            profile_item,
            P27E_DESC0_TAG0,
            P27E_DESC0_TAG1,
            0,
            "P27E valid baseline",
            baseline_snap
        );

        p26d_cleanup_drained_and_require_clean(
            rt,
            cfg,
            event_mask,
            "P27E valid baseline cleanup"
        );

        p26d_set_cfg_epoch(cfg, 1);
        rt.host_rt_mem_guard_check_clean("P27E after valid baseline guard clean", 1'b1, 1'b1);

        `uvm_info("P27E_GUARD/VALID_BASELINE_PASS",
            "P27E valid SQ/CQ/DESC/SRC/DST guard baseline command completed normally",
            UVM_MEDIUM)

        // Source range negative / CODE-COV-C1.2-G7-Z2-A:
        // SQ and descriptor table are safe, but the fetched descriptor
        // payload starts below SRC_BASE while still ending below SRC_LIMIT.
        // This makes (addr < region_base) the decisive range predicate and
        // must reject before launching any lower-level preload read.
        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'h0000_0000, guard_cfg);
        guard_cfg.src_base = bad_src_base;

        `uvm_info("CODE_COV_C1P2_G7_Z2_A/START",
            $sformatf("Starting P27 payload lower-bound range probe: SRC=[0x%08h,0x%08h)",
                guard_cfg.src_base,
                guard_cfg.src_limit),
            UVM_MEDIUM)

        rt.host_rt_mem_guard_program_regions(guard_cfg, "P27E source lower-bound range reject guard cfg");

        p27e_run_guard_negative_case(
            rt,
            cfg,
            bad_src_cmd,
            1,
            32'h0000_0002,
            32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_SRC_RANGE,
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_SRC,
            ai_accel_csr_access_helper::P27_DETAIL_SRC_RANGE,
            "P27E_GUARD/SRC_RANGE_REJECT_PASS",
            "P27E source lower-bound range reject"
        );

        `uvm_info("CODE_COV_C1P2_G7_Z2_A/LOWER_BOUND_PASS",
            $sformatf("P27 payload lower-bound range probe PASS: payload address 0x%08h is below SRC_BASE=0x%08h with SRC_LIMIT=0x%08h",
                32'h0000_0000,
                bad_src_base,
                guard_cfg.src_limit),
            UVM_MEDIUM)

        // Destination range negative: source range is valid again, but the
        // fetched descriptor payload store destination span is outside DST
        // range.  The wrapper must reject before any lower-level DMA store
        // write can launch.
        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, bad_dst_limit, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "P27E destination range reject guard cfg");

        p27e_run_guard_negative_case(
            rt,
            cfg,
            bad_dst_cmd,
            1,
            32'h0000_0002,
            32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_DST_RANGE,
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_DST,
            ai_accel_csr_access_helper::P27_DETAIL_DST_RANGE,
            "P27E_GUARD/DST_RANGE_REJECT_PASS",
            "P27E destination range reject"
        );

        // ------------------------------------------------------------
        // CODE-COV-C1.2-G7-G3-A
        //
        // 1) Keep slot0 A inside the source range while placing slot0 B
        //    exactly at the exclusive limit.  This reaches the genuine B
        //    source materialization path without altering RTL or forcing
        //    internal state.
        // ------------------------------------------------------------
        p27e_make_guard_cfg(rt, cfg, 32'h0000_0100, 32'h0000_0000, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "G7-G3 B-source range guard cfg");

        p27e_run_guard_negative_case(
            rt,
            cfg,
            g7_g3_bad_b_src_cmd,
            1,
            32'h0000_0002,
            32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_SRC_RANGE,
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_SRC,
            ai_accel_csr_access_helper::P27_DETAIL_SRC_RANGE,
            "CODE_COV_C1_2G7_G3/B_SRC_PASS",
            "G7-G3 B-source range reject"
        );

        // 2) A non-empty payload with BASE == LIMIT is a legal host
        //    misconfiguration and must report SPAN_CONFIG + BASE_LIMIT.
        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'h0000_0000, guard_cfg);
        guard_cfg.src_base  = 32'h0000_1000;
        guard_cfg.src_limit = 32'h0000_1000;
        rt.host_rt_mem_guard_program_regions(guard_cfg, "G7-G3 source BASE>=LIMIT guard cfg");

        p27e_run_guard_negative_case(
            rt,
            cfg,
            g7_g3_span_cfg_cmd,
            1,
            32'h0000_0002,
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_SRC_RANGE) |
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_BASE_LIMIT),
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_SRC,
            ai_accel_csr_access_helper::P27_DETAIL_SPAN_CONFIG,
            "CODE_COV_C1_2G7_G3/SPAN_CONFIG_PASS",
            "G7-G3 source span-config reject"
        );

        // 3) Move slot0 A to the top of the 32-bit address space.  The
        //    non-zero A transfer then crosses the 32-bit boundary and must
        //    report ADDR_OVERFLOW.  Restore the descriptor immediately after
        //    the negative case so later recovery remains the canonical table.
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_G3_DESC_WORD_A_SRC_BASE,
            32'hFFFF_FFFC
        );

        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'h0000_0000, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "G7-G3 source overflow guard cfg");

        p27e_run_guard_negative_case(
            rt,
            cfg,
            g7_g3_overflow_cmd,
            1,
            32'h0000_0002,
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_SRC_RANGE) |
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_ADDR_OVERFLOW),
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_SRC,
            ai_accel_csr_access_helper::P27_DETAIL_ADDR_OVERFLOW,
            "CODE_COV_C1_2G7_G3/OVERFLOW_PASS",
            "G7-G3 source address-overflow reject"
        );

        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_G3_DESC_WORD_A_SRC_BASE,
            32'h0000_0000
        );

        // ------------------------------------------------------------
        // CODE-COV-C1.2-G7-Z2-B
        //
        // Keep the payload address itself inside the canonical SRC guard
        // span, but program a legal non-zero 32-bit A beat count whose
        // byte conversion exceeds 32 bits:
        //
        //   0x2000_0000 beats * 8 bytes/beat
        //     = 0x0000_0001_0000_0000 bytes
        //
        // P17 descriptor validation intentionally accepts any non-zero
        // 32-bit load-beat value.  P27 must catch the widened byte-size
        // before any lower-level preload launch, making
        // size_bytes64[63:32] != 0 the decisive ADDR_OVERFLOW term.
        // ------------------------------------------------------------
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z2_B_DESC_WORD_A_LOAD_BEATS,
            G7_Z2_B_A_LOAD_BEATS
        );

        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'h0000_0000, guard_cfg);

        `uvm_info("CODE_COV_C1P2_G7_Z2_B/START",
            $sformatf("Starting P27 large payload-size upper-word overflow probe: A_load_beats=0x%08h expected_size64=0x0000000100000000",
                G7_Z2_B_A_LOAD_BEATS),
            UVM_MEDIUM)

        rt.host_rt_mem_guard_program_regions(guard_cfg, "G7-Z2-B large payload-size overflow guard cfg");

        p27e_run_guard_negative_case(
            rt,
            cfg,
            g7_z2_b_large_size_cmd,
            1,
            32'h0000_0002,
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_SRC_RANGE) |
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_ADDR_OVERFLOW),
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_SRC,
            ai_accel_csr_access_helper::P27_DETAIL_ADDR_OVERFLOW,
            "CODE_COV_C1P2_G7_Z2_B/LARGE_SIZE_OVERFLOW_PASS",
            "G7-Z2-B large payload-size upper-word overflow reject"
        );

        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z2_B_DESC_WORD_A_LOAD_BEATS,
            32'h0000_0001
        );

        `uvm_info("CODE_COV_C1P2_G7_Z2_B/RESTORE_PASS",
            "Restored slot0 A load-beat count after large-size overflow probe",
            UVM_MEDIUM)

        // ------------------------------------------------------------
        // CODE-COV-C1.2-G7-Z4-A
        //
        // Target 1: line 2173 B-source fallback-detail FALSE branch.
        //
        // A remains the canonical small legal transfer and therefore passes
        // first.  B uses the same legal non-zero 32-bit beat count already
        // proven by Z2-B:
        //
        //   0x2000_0000 beats * 8 bytes/beat
        //     = 0x0000_0001_0000_0000 bytes
        //
        // The P27 helper returns ADDR_OVERFLOW directly for the B payload.
        // Therefore detail_code is already non-zero when the B-specific
        // fallback executes, constructively taking:
        //
        //   if (detail_code == 8'h00) ...  // FALSE
        // ------------------------------------------------------------
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z4_A_DESC_WORD_B_LOAD_BEATS,
            G7_Z4_A_B_LOAD_BEATS
        );

        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'h0000_0000, guard_cfg);

        `uvm_info("CODE_COV_C1P2_G7_Z4_A/B_SRC_NON_RANGE_START",
            $sformatf("Starting B-source non-range detail probe: B_load_beats=0x%08h expected_size64=0x0000000100000000",
                G7_Z4_A_B_LOAD_BEATS),
            UVM_MEDIUM)

        rt.host_rt_mem_guard_program_regions(
            guard_cfg,
            "G7-Z4-A B-source non-range detail guard cfg"
        );

        p27e_run_guard_negative_case(
            rt,
            cfg,
            g7_z4_a_b_large_size_cmd,
            1,
            32'h0000_0002,
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_SRC_RANGE) |
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_ADDR_OVERFLOW),
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_SRC,
            ai_accel_csr_access_helper::P27_DETAIL_ADDR_OVERFLOW,
            "CODE_COV_C1P2_G7_Z4_A/B_SRC_NON_RANGE_PASS",
            "G7-Z4-A B-source ADDR_OVERFLOW detail propagation"
        );

        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z4_A_DESC_WORD_B_LOAD_BEATS,
            32'h0000_0001
        );

        `uvm_info("CODE_COV_C1P2_G7_Z4_A/B_SRC_RESTORE_PASS",
            "Restored slot0 B load-beat count after B-source non-range detail probe",
            UVM_MEDIUM)

        // ------------------------------------------------------------
        // Target 2: line 2197 destination fallback-detail FALSE branch.
        //
        // Keep SQ/CQ/DESC/SRC regions legal.  Program only the destination
        // region with BASE == LIMIT.  The non-zero store payload reaches the
        // destination helper, which returns SPAN_CONFIG and BASE_LIMIT before
        // any DMA-store launch.  The caller must preserve that non-zero detail
        // instead of replacing it with the ordinary DST_RANGE fallback.
        // ------------------------------------------------------------
        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'h0000_0000, guard_cfg);
        guard_cfg.dst_base  = 32'h0000_1000;
        guard_cfg.dst_limit = 32'h0000_1000;

        `uvm_info("CODE_COV_C1P2_G7_Z4_A/DST_NON_RANGE_START",
            $sformatf("Starting destination non-range detail probe: DST_BASE=0x%08h DST_LIMIT=0x%08h",
                guard_cfg.dst_base,
                guard_cfg.dst_limit),
            UVM_MEDIUM)

        rt.host_rt_mem_guard_program_regions(
            guard_cfg,
            "G7-Z4-A destination BASE==LIMIT detail guard cfg"
        );

        p27e_run_guard_negative_case(
            rt,
            cfg,
            g7_z4_a_dst_span_cfg_cmd,
            1,
            32'h0000_0002,
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_DST_RANGE) |
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_BASE_LIMIT),
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_DST,
            ai_accel_csr_access_helper::P27_DETAIL_SPAN_CONFIG,
            "CODE_COV_C1P2_G7_Z4_A/DST_NON_RANGE_PASS",
            "G7-Z4-A destination SPAN_CONFIG detail propagation"
        );

        `uvm_info("CODE_COV_C1P2_G7_Z4_A/PASS",
            "G7-Z4-A B-source and destination non-range fallback-detail constructive probes PASS",
            UVM_MEDIUM)

        // Known-good recovery after the original, G7-G3, G7-Z2-B, and
        // G7-Z4-A guard rejects.
        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'h0000_0000, guard_cfg);
        guard_cfg.control = rt.host_rt_mem_guard_control_value(
            1'b1, // guard_enable
            1'b1, // strict_reject_enable
            1'b1, // SQ check
            1'b1, // CQ check
            1'b1, // descriptor check
            1'b1, // source check
            1'b0, // destination check: G7-G3 SRC-only success target
            1'b1  // write CQ error if safe
        );
        rt.host_rt_mem_guard_program_regions(guard_cfg, "P27E recovery SRC-only guard cfg");
        rt.host_rt_mem_guard_check_clean("P27E recovery guard clean", 1'b1, 1'b1);

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_CONTROL,
            g7_g3_guard_control_readback
        );
        if (g7_g3_guard_control_readback !== guard_cfg.control) begin
            `uvm_fatal("CODE_COV_C1_2G7_G3/SRC_ONLY_CONTROL",
                $sformatf("SRC-only guard control readback mismatch: expected=0x%08h actual=0x%08h",
                    guard_cfg.control,
                    g7_g3_guard_control_readback))
        end

        rt.host_rt_lifecycle_init_session(
            cfg,
            event_mask,
            1'b1,
            1'b1,
            "P27E recovery lifecycle init"
        );

        p26d_run_drained_session_without_cleanup(
            rt,
            cfg,
            recovery_cmd,
            profile_item,
            P27E_DESC1_TAG0,
            P27E_DESC1_TAG1,
            1,
            "P27E recovery command",
            recovery_snap
        );

        p26d_cleanup_drained_and_require_clean(
            rt,
            cfg,
            event_mask,
            "P27E recovery final cleanup"
        );

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("CODE_COV_C1_2G7_G3/SRC_ONLY_PASS",
            $sformatf("SRC-only guarded recovery completed with DST check disabled: control=0x%08h",
                g7_g3_guard_control_readback),
            UVM_MEDIUM)

        rt.host_rt_mem_guard_check_clean("P27E final guard clean", 1'b1, 1'b1);
        rt.host_rt_lifecycle_check_clean_idle("P27E final lifecycle clean idle", 1'b0, 1'b1, 1'b0);

        `uvm_info("P27E_GUARD/RECOVERY_PASS",
            "P27E known-good command completed after source/destination, G7-G3, G7-Z2-B, and G7-Z4-A guard rejects",
            UVM_MEDIUM)

        `uvm_info("CODE_COV_C1_2G7_G3/PAYLOAD_GUARD_SUITE_PASS",
            "G7-G3 payload guard targeted suite completed: B-source, span-config, overflow, and SRC-only success",
            UVM_MEDIUM)

        `uvm_info("CODE_COV_C1P2_G7_Z2_B/PASS",
            "G7-Z2-B large payload-size upper-word overflow probe and recovery completed",
            UVM_MEDIUM)

        // ------------------------------------------------------------
        // CODE-COV-C1.2-G7-Z4-C3-A
        // P27 Strict-Mode / Legal Zero-Payload Constructive Probe
        //
        // All three cases are architecturally legal.  No force/deposit or
        // hierarchical DUT state mutation is used.  The first case changes
        // only the host-programmable STRICT_REJECT bit.  The second and
        // third cases use the descriptor's HOST_PRELOADED/HOST_READBACK mode
        // contract, where zero A/B preload lengths and zero store length are
        // legal.  Fresh merged FEC remains the authoritative physical check.
        // ------------------------------------------------------------
        `uvm_info("CODE_COV_C1P2_G7_Z4_C3_A/START",
            "Starting P27 strict-off and legal mode-dependent zero-payload constructive probes",
            UVM_MEDIUM)

        // Preserve the original P27E recovery endpoint exactly, then continue
        // from its clean monotonic pointer epoch (2/2).
        p26d_set_cfg_epoch(cfg, 2);

        // --------------------------------------------------------
        // Case 1: line 2136 STRICT_REJECT == 0 decisive term.
        // ENABLE stays asserted and a genuine descriptor-fetch recipe
        // handoff is executed; only STRICT_REJECT is cleared.
        // --------------------------------------------------------
        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'h0000_0000, guard_cfg);
        guard_cfg.control = rt.host_rt_mem_guard_control_value(
            1'b1, // guard_enable
            1'b0, // strict_reject_enable -- C3-A target
            1'b1, // SQ check
            1'b1, // CQ check
            1'b1, // descriptor check
            1'b1, // source check
            1'b1, // destination check
            1'b1  // write CQ error if safe
        );
        rt.host_rt_mem_guard_program_regions(guard_cfg, "G7-Z4-C3-A strict-off guard cfg");
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_CONTROL,
            g7_z4_c3_a_guard_control_readback
        );
        if (g7_z4_c3_a_guard_control_readback !== guard_cfg.control) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C3_A/STRICT_OFF_CONTROL",
                $sformatf("STRICT_REJECT=0 control readback mismatch: expected=0x%08h actual=0x%08h",
                    guard_cfg.control,
                    g7_z4_c3_a_guard_control_readback))
        end

        rt.host_rt_lifecycle_init_session(
            cfg,
            event_mask,
            1'b1,
            1'b1,
            "G7-Z4-C3-A strict-off lifecycle init"
        );
        p26d_run_drained_session_without_cleanup(
            rt,
            cfg,
            g7_z4_c3_a_strict_off_cmd,
            profile_item,
            P27E_DESC1_TAG0,
            P27E_DESC1_TAG1,
            2,
            "G7-Z4-C3-A strict-off command",
            g7_z4_c3_a_strict_off_snap
        );
        p26d_cleanup_drained_and_require_clean(
            rt,
            cfg,
            event_mask,
            "G7-Z4-C3-A strict-off cleanup"
        );
        p26d_set_cfg_epoch(cfg, 3);

        `uvm_info("CODE_COV_C1P2_G7_Z4_C3_A/LINE2136_STRICT_OFF_PASS",
            $sformatf("Legal desc-fetch handoff completed with MEM_GUARD ENABLE=1 STRICT_REJECT=0 control=0x%08h",
                g7_z4_c3_a_guard_control_readback),
            UVM_MEDIUM)

        // --------------------------------------------------------
        // Case 2: line 2144 A_LOAD_BEATS == 0 and line 2188
        // STORE_BYTE_COUNT == 0 decisive terms.
        //
        // SLOT_CONTROL=0x1 => VALID + HOST_PRELOADED + HOST_READBACK.
        // Under the canonical descriptor validator, HOST_PRELOADED does not
        // require A/B preload lengths and HOST_READBACK does not require a
        // DMA-store byte count.  Therefore these zero values are legal.
        // --------------------------------------------------------
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z4_C3_A_DESC_WORD_CONTROL,
            G7_Z4_C3_A_CTRL_HOST_PRELOADED_HOST_READBACK
        );
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z2_B_DESC_WORD_A_LOAD_BEATS,
            32'h0000_0000
        );
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z4_A_DESC_WORD_B_LOAD_BEATS,
            32'h0000_0000
        );
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z4_C3_A_DESC_WORD_STORE_BYTE_COUNT,
            32'h0000_0000
        );

        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'h0000_0000, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "G7-Z4-C3-A legal zero-A/store guard cfg");
        rt.host_rt_lifecycle_init_session(
            cfg,
            event_mask,
            1'b1,
            1'b1,
            "G7-Z4-C3-A legal zero-A/store lifecycle init"
        );
        p26d_run_drained_session_without_cleanup(
            rt,
            cfg,
            g7_z4_c3_a_zero_a_store_cmd,
            profile_item,
            P27E_DESC0_TAG0,
            P27E_DESC0_TAG1,
            3,
            "G7-Z4-C3-A legal zero-A/store command",
            g7_z4_c3_a_zero_a_store_snap
        );
        p26d_cleanup_drained_and_require_clean(
            rt,
            cfg,
            event_mask,
            "G7-Z4-C3-A legal zero-A/store cleanup"
        );
        p26d_set_cfg_epoch(cfg, 4);

        `uvm_info("CODE_COV_C1P2_G7_Z4_C3_A/LINE2144_A_ZERO_PASS",
            "Legal HOST_PRELOADED descriptor completed with slot0 A_LOAD_BEATS=0 while SRC_CHECK_ENABLE=1",
            UVM_MEDIUM)
        `uvm_info("CODE_COV_C1P2_G7_Z4_C3_A/LINE2188_STORE_ZERO_PASS",
            "Legal HOST_READBACK descriptor completed with slot0 STORE_BYTE_COUNT=0 while DST_CHECK_ENABLE=1",
            UVM_MEDIUM)

        // Restore the canonical slot0 fields before constructing the isolated
        // B-zero case.
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z4_C3_A_DESC_WORD_CONTROL,
            32'h0000_0003
        );
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z2_B_DESC_WORD_A_LOAD_BEATS,
            32'h0000_0001
        );
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z4_A_DESC_WORD_B_LOAD_BEATS,
            32'h0000_0001
        );
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z4_C3_A_DESC_WORD_STORE_BYTE_COUNT,
            32'(c_bytes)
        );

        // --------------------------------------------------------
        // Case 3: line 2165 B_LOAD_BEATS == 0 decisive term.
        // Keep A non-zero and in-range so the nested B check is reached.
        // HOST_PRELOADED makes B=0 legal; keep STORE_BYTE_COUNT non-zero so
        // the destination condition does not provide the target in this case.
        // --------------------------------------------------------
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z4_C3_A_DESC_WORD_CONTROL,
            G7_Z4_C3_A_CTRL_HOST_PRELOADED_HOST_READBACK
        );
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z2_B_DESC_WORD_A_LOAD_BEATS,
            32'h0000_0001
        );
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z4_A_DESC_WORD_B_LOAD_BEATS,
            32'h0000_0000
        );
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z4_C3_A_DESC_WORD_STORE_BYTE_COUNT,
            32'(c_bytes)
        );

        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'h0000_0000, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "G7-Z4-C3-A legal zero-B guard cfg");
        rt.host_rt_lifecycle_init_session(
            cfg,
            event_mask,
            1'b1,
            1'b1,
            "G7-Z4-C3-A legal zero-B lifecycle init"
        );
        p26d_run_drained_session_without_cleanup(
            rt,
            cfg,
            g7_z4_c3_a_zero_b_cmd,
            profile_item,
            P27E_DESC0_TAG0,
            P27E_DESC0_TAG1,
            4,
            "G7-Z4-C3-A legal zero-B command",
            g7_z4_c3_a_zero_b_snap
        );
        p26d_cleanup_drained_and_require_clean(
            rt,
            cfg,
            event_mask,
            "G7-Z4-C3-A legal zero-B cleanup"
        );
        p26d_set_cfg_epoch(cfg, 5);

        `uvm_info("CODE_COV_C1P2_G7_Z4_C3_A/LINE2165_B_ZERO_PASS",
            "Legal HOST_PRELOADED descriptor completed with A_LOAD_BEATS=1 and B_LOAD_BEATS=0, reaching the nested B zero-length term",
            UVM_MEDIUM)

        // Restore the exact canonical slot0 descriptor image used by the
        // original P27E suite, then prove final reusable state and result.
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z4_C3_A_DESC_WORD_CONTROL,
            32'h0000_0003
        );
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z2_B_DESC_WORD_A_LOAD_BEATS,
            32'h0000_0001
        );
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z4_A_DESC_WORD_B_LOAD_BEATS,
            32'h0000_0001
        );
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_Z4_C3_A_DESC_WORD_STORE_BYTE_COUNT,
            32'(c_bytes)
        );

        `uvm_info("CODE_COV_C1P2_G7_Z4_C3_A/RESTORE_PASS",
            "Restored canonical slot0 descriptor control/load/store fields after C3-A probes",
            UVM_MEDIUM)

        rt.host_rt_mem_guard_check_clean("G7-Z4-C3-A final guard clean", 1'b1, 1'b1);
        rt.host_rt_lifecycle_check_clean_idle("G7-Z4-C3-A final lifecycle clean idle", 1'b0, 1'b1, 1'b0);
        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("CODE_COV_C1P2_G7_Z4_C3_A/PASS",
            "G7-Z4-C3-A strict-off, A-zero, B-zero, and store-zero constructive probes completed with clean recovery",
            UVM_MEDIUM)

        // CODE-COV-C1.2-G7-Z4-C4-A runs only after all P27 queue work has
        // returned to the clean idle endpoint.  It changes only legal CSR
        // configuration fields, verifies readback/idle prerequisites, and
        // restores the exact prior values before final test completion.
        g7_z4_c4_a_run_manual_policy_accumulate_probe(rt);

        `uvm_info("P27E_GUARD/PASS",
            $sformatf("P27E DMA source / destination memory guard validation PASS: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
                selected_case_id,
                a_flat.size(),
                b_flat.size(),
                c_elems),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
