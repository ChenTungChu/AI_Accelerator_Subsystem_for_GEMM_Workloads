// File: tb/uvm/test/ai_accel_subsys_csr_mem_guard_cq_recovery_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_MEM_GUARD_CQ_RECOVERY_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_MEM_GUARD_CQ_RECOVERY_SMOKE_TEST_SV

// ============================================================
// P27F memory guard CQ / completion writeback recovery smoke
//
// Scope:
//   - Extends P27D/P27E guard validation to the CQ completion target.
//   - Runs one valid SQ + descriptor + source + destination + CQ guarded
//     command to prove enabled CQ checking preserves the normal path.
//   - Shrinks the CQ guard range so the next CQ slot is unsafe.
//   - Confirms the command is rejected through the existing queue error /
//     P22 event path and no CQ completion record is committed to the
//     unsafe slot.
//   - Clears guard / queue / event sticky state with the P26 lifecycle
//     cleanup policy and proves a known-good recovery command completes.
//
// P27F does not change SQ/CQ entry format, descriptor format,
// completion record format, event bit allocation, BRAM, GEMM, DMA,
// AXI-Stream, or Direct Stream datapath behavior.
// ============================================================

class ai_accel_subsys_csr_mem_guard_cq_recovery_smoke_test
    extends ai_accel_subsys_csr_queue_lifecycle_drained_reinit_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_mem_guard_cq_recovery_smoke_test)

    localparam int unsigned P27F_SQ_BASE     = 32'h0000_0D00;
    localparam int unsigned P27F_CQ_BASE     = 32'h0000_0E00;
    localparam int unsigned P27F_QUEUE_DEPTH = 4;

    localparam int unsigned P27F_DESC_BASE0  = 32'h0000_0300;
    localparam int unsigned P27F_DESC_BASE1  = 32'h0000_0400;
    localparam int unsigned P27F_DESC_STRIDE = 32'h0000_0080;

    localparam logic [31:0] P27F_BASELINE_CMD_TAG = 32'hD27F_0000;
    localparam logic [31:0] P27F_BAD_CQ_CMD_TAG   = 32'hD27F_0001;
    localparam logic [31:0] P27F_RECOVERY_CMD_TAG = 32'hD27F_0002;

    localparam logic [31:0] P27F_DESC0_TAG0 = 32'hD27F_1000;
    localparam logic [31:0] P27F_DESC0_TAG1 = 32'hD27F_1001;
    localparam logic [31:0] P27F_DESC1_TAG0 = 32'hD27F_2000;
    localparam logic [31:0] P27F_DESC1_TAG1 = 32'hD27F_2001;

    // CODE-COV-B5 V4: final deterministic CONFIG_BUSY closure.
    // This phase runs only after the original P27F functional flow is complete.
    localparam int unsigned P27F_B5_EVENT_TIMEOUT_CYCLES = 20000;
    localparam int unsigned P27F_B5_WATCHDOG_CYCLES     = 200000;

    localparam logic [31:0] P27F_B5_CMD0_TAG = 32'hD27F_B500;
    localparam logic [31:0] P27F_B5_CMD1_TAG = 32'hD27F_B510;

    function new(string name = "ai_accel_subsys_csr_mem_guard_cq_recovery_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p27f_make_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg
    );
    begin
        rt.make_default_queue_cfg(
            cfg,
            32'(P27F_SQ_BASE),
            32'(P27F_CQ_BASE),
            32'(P27F_QUEUE_DEPTH),
            1'b1
        );
    end
    endtask

    task automatic p27f_make_cmd(
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
            32'(P27F_DESC_STRIDE),
            user_tag,
            1'b1,
            1'b0
        );
        cmd.timeout_cycles = 32'h0000_0000;
    end
    endtask

    task automatic p27f_make_guard_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        input  ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input  logic [31:0] cq_limit_override,
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
        guard_cfg.cq_limit   = (cq_limit_override != 32'h0000_0000) ?
                               cq_limit_override :
                               rt.host_rt_mem_guard_span_limit(cfg.cq_base, cq_size_bytes);
        guard_cfg.desc_base  = 32'(P27F_DESC_BASE0);
        guard_cfg.desc_limit = rt.host_rt_mem_guard_span_limit(32'(P27F_DESC_BASE0), 32'h0000_0200);
        guard_cfg.src_base   = 32'h0000_0000;
        guard_cfg.src_limit  = 32'h0000_2000;
        guard_cfg.dst_base   = 32'h0000_0000;
        guard_cfg.dst_limit  = 32'h0000_2000;
    end
    endtask

    task automatic p27f_check_no_cq_write(
        input ai_accel_event_driven_host_runtime_stress_helper rt,
        input ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input int unsigned cq_idx,
        input string label
    );
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec;
    begin
        rt.read_cq_record(cfg, cq_idx, rec);

        if (rec.commit_word[0]) begin
            `uvm_fatal("P27F_GUARD/UNSAFE_CQ_WRITE",
                $sformatf("%s: unsafe CQ[%0d] write observed commit=0x%08h status=0x%08h first=0x%08h last=0x%08h",
                    label,
                    cq_idx,
                    rec.commit_word,
                    rec.status_flags,
                    rec.first_user_tag,
                    rec.last_user_tag))
        end

        `uvm_info("P27F_GUARD/NO_CQ_WRITE_PASS",
            $sformatf("%s: CQ[%0d] remained uncommitted after CQ guard reject commit=0x%08h status=0x%08h",
                label,
                cq_idx,
                rec.commit_word,
                rec.status_flags),
            UVM_MEDIUM)
    end
    endtask

    task automatic p27f_cleanup_after_guard_error(
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

        // CQ guard failure is detected before an unsafe completion writeback.
        // No CQ record is expected, so keep host-owned pointers aligned with
        // the hardware-owned monotonic epoch.
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

        `uvm_info("P27F_GUARD/CLEANUP_PASS",
            $sformatf("%s: guard error cleanup PASS SQ(h/t)=%0d/%0d CQ(h/t)=%0d/%0d",
                label,
                cfg.sq_head,
                cfg.sq_tail,
                cfg.cq_head,
                cfg.cq_tail),
            UVM_MEDIUM)
    end
    endtask

    task automatic p27f_run_cq_guard_negative_case(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        ref    ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input  ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd,
        input  int unsigned sq_idx,
        input  int unsigned cq_idx,
        input  logic [31:0] next_tail,
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
            `uvm_fatal("P27F_GUARD/NO_QUEUE_ERROR_STATUS",
                $sformatf("%s: expected QUEUE_STATUS.QUEUE_ERROR, status=0x%08h error=0x%08h",
                    label,
                    snap.queue_status,
                    snap.queue_error_status))
        end

        rt.host_rt_mem_guard_expect_error(
            32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_CQ_RANGE,
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_CQ,
            ai_accel_csr_access_helper::P27_DETAIL_CQ_RANGE,
            {label, " expected_error"}
        );

        `uvm_info("P27F_GUARD/CQ_RANGE_REJECT_PASS",
            $sformatf("%s: expected memory guard reject observed domain=CQ detail=CQ_RANGE pending=0x%08h queue_error=0x%08h",
                label,
                snap.event_snap.pending,
                snap.queue_error_status),
            UVM_MEDIUM)

        p27f_check_no_cq_write(rt, cfg, cq_idx, label);
        p27f_cleanup_after_guard_error(rt, cfg, label);
    end
    endtask


    task automatic p27f_b5_expect_reg_unchanged(
        input logic [31:0] addr,
        input logic [31:0] expected,
        input string       name
    );
        logic [31:0] actual;
    begin
        csr.read32_expect_okay(addr, actual);
        if (actual !== expected) begin
            `uvm_fatal("CODE_COV_B5_V4/MUTATION",
                $sformatf("%s changed during CONFIG_BUSY reject: expected=0x%08h actual=0x%08h",
                    name, expected, actual))
        end

        `uvm_info("CODE_COV_B5_V4/UNCHANGED_PASS",
            $sformatf("%s unchanged at 0x%08h", name, actual),
            UVM_MEDIUM)
    end
    endtask

    task automatic p27f_b5_issue_busy_matrix(
        input ai_accel_event_driven_host_runtime_stress_helper::p27_guard_cfg_t guard_cfg
    );
        logic [31:0] reject_status;
        logic [31:0] queue_status;
        logic [31:0] sq_occ;
        logic [31:0] cq_occ;
        logic [31:0] cq_space;
        logic [31:0] config_busy_mask;
    begin
        config_busy_mask =
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_REJ_CONFIG_BUSY);

        // Start from a clean guard reject register. Do not clear it again
        // until all 11 writes have been attempted.
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_REJECT_STATUS,
            ai_accel_csr_access_helper::MEM_GUARD_ALL_REJECT_MASK
        );

        `uvm_info("CODE_COV_B5_V4/MATRIX_BEGIN",
            "Issuing all 11 Memory Guard configuration writes under one uninterrupted CQ-full queue_busy hold",
            UVM_MEDIUM)

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_CONTROL,
            guard_cfg.control ^ 32'h0000_0001
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_SQ_BASE,
            guard_cfg.sq_base ^ 32'h0000_0040
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_SQ_LIMIT,
            guard_cfg.sq_limit ^ 32'h0000_0040
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_CQ_BASE,
            guard_cfg.cq_base ^ 32'h0000_0040
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_CQ_LIMIT,
            guard_cfg.cq_limit ^ 32'h0000_0040
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_DESC_BASE,
            guard_cfg.desc_base ^ 32'h0000_0040
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_DESC_LIMIT,
            guard_cfg.desc_limit ^ 32'h0000_0040
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_SRC_BASE,
            guard_cfg.src_base ^ 32'h0000_0040
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_SRC_LIMIT,
            guard_cfg.src_limit ^ 32'h0000_0040
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_DST_BASE,
            guard_cfg.dst_base ^ 32'h0000_0040
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_DST_LIMIT,
            guard_cfg.dst_limit ^ 32'h0000_0040
        );

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_REJECT_STATUS,
            reject_status
        );
        if ((reject_status & config_busy_mask) == 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_B5_V4/NO_CONFIG_BUSY",
                $sformatf("CONFIG_BUSY reject bit was not set after 11 busy writes: reject=0x%08h",
                    reject_status))
        end

        // CQ_HEAD has not moved, therefore queue_busy must still be held.
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_STATUS,
            queue_status
        );
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_SQ_OCCUPANCY,
            sq_occ
        );
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY,
            cq_occ
        );
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_CQ_SPACE,
            cq_space
        );

        if (!queue_status[0] ||
            (sq_occ   != 32'h0000_0001) ||
            (cq_occ   != 32'h0000_0001) ||
            (cq_space != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_B5_V4/HOLD_LOST",
                $sformatf("CQ-full ownership hold lost during matrix: q_status=0x%08h SQ_OCC=%0d CQ_OCC=%0d CQ_SPACE=%0d",
                    queue_status, sq_occ, cq_occ, cq_space))
        end

        p27f_b5_expect_reg_unchanged(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_CONTROL,
            guard_cfg.control,
            "MEM_GUARD_CONTROL"
        );
        p27f_b5_expect_reg_unchanged(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_SQ_BASE,
            guard_cfg.sq_base,
            "MEM_GUARD_SQ_BASE"
        );
        p27f_b5_expect_reg_unchanged(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_SQ_LIMIT,
            guard_cfg.sq_limit,
            "MEM_GUARD_SQ_LIMIT"
        );
        p27f_b5_expect_reg_unchanged(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_CQ_BASE,
            guard_cfg.cq_base,
            "MEM_GUARD_CQ_BASE"
        );
        p27f_b5_expect_reg_unchanged(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_CQ_LIMIT,
            guard_cfg.cq_limit,
            "MEM_GUARD_CQ_LIMIT"
        );
        p27f_b5_expect_reg_unchanged(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_DESC_BASE,
            guard_cfg.desc_base,
            "MEM_GUARD_DESC_BASE"
        );
        p27f_b5_expect_reg_unchanged(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_DESC_LIMIT,
            guard_cfg.desc_limit,
            "MEM_GUARD_DESC_LIMIT"
        );
        p27f_b5_expect_reg_unchanged(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_SRC_BASE,
            guard_cfg.src_base,
            "MEM_GUARD_SRC_BASE"
        );
        p27f_b5_expect_reg_unchanged(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_SRC_LIMIT,
            guard_cfg.src_limit,
            "MEM_GUARD_SRC_LIMIT"
        );
        p27f_b5_expect_reg_unchanged(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_DST_BASE,
            guard_cfg.dst_base,
            "MEM_GUARD_DST_BASE"
        );
        p27f_b5_expect_reg_unchanged(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_DST_LIMIT,
            guard_cfg.dst_limit,
            "MEM_GUARD_DST_LIMIT"
        );

        `uvm_info("CODE_COV_B5_V4/MATRIX_PASS",
            $sformatf("All 11 CONFIG_BUSY writes rejected without mutation; reject=0x%08h",
                reject_status),
            UVM_LOW)
    end
    endtask

    task automatic p27f_run_config_busy_matrix_v4(
        input ai_accel_event_driven_host_runtime_stress_helper rt
    );
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t entry_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t stall_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t recovered_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t drained_snap;

        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t busy_cfg;
        ai_accel_event_driven_host_runtime_stress_helper::p27_guard_cfg_t busy_guard_cfg;

        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd0;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd1;

        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t cq0;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t cq1;

        logic [31:0] stall_mask;
        logic [31:0] recovered_mask;
        logic [31:0] drained_mask;
        logic [31:0] event_mask;
        logic [31:0] config_busy_mask;

        int unsigned sq_idx0;
        int unsigned sq_idx1;
        int unsigned cq_idx0;
        int unsigned cq_idx1;
        logic [31:0] new_sq_tail;
    begin
        `uvm_info("CODE_COV_B5_V4/START",
            "Starting B5 with the P30-proven CQ-full recovery sequence after original P27F completion",
            UVM_LOW)

        // Use the already-proven P27F terminal state as the next monotonic
        // pointer epoch. No RESET_QUEUE_POINTERS is used in this B5 phase.
        rt.read_runtime_snapshot(entry_snap);

        p27f_make_cfg(rt, busy_cfg);
        busy_cfg.sq_depth = 32'h0000_0004;
        busy_cfg.cq_depth = 32'h0000_0001;
        busy_cfg.sq_head  = entry_snap.sq_head;
        busy_cfg.sq_tail  = entry_snap.sq_head;
        busy_cfg.cq_head  = entry_snap.cq_head;
        busy_cfg.cq_tail  = entry_snap.cq_head;

        sq_idx0     = int'(entry_snap.sq_head);
        sq_idx1     = int'(entry_snap.sq_head + 32'h0000_0001);
        cq_idx0     = int'(entry_snap.cq_head);
        cq_idx1     = int'(entry_snap.cq_head + 32'h0000_0001);
        new_sq_tail = entry_snap.sq_head + 32'h0000_0002;

        p27f_make_guard_cfg(rt, busy_cfg, 32'h0000_0000, busy_guard_cfg);
        busy_guard_cfg.control = 32'h0000_0000;

        p27f_make_cmd(rt, cmd0, 32'(P27F_DESC_BASE0), P27F_B5_CMD0_TAG);
        p27f_make_cmd(rt, cmd1, 32'(P27F_DESC_BASE1), P27F_B5_CMD1_TAG);

        stall_mask = rt.event_bit(
            ai_accel_csr_access_helper::P22_EVENT_CQ_FULL_STALL
        );
        recovered_mask = rt.event_bit(
            ai_accel_csr_access_helper::P22_EVENT_CQ_SPACE_RECOVERED
        );
        drained_mask = rt.event_bit(
            ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED
        );
        event_mask =
            rt.queue_completion_event_mask() |
            stall_mask |
            recovered_mask |
            drained_mask;

        rt.host_rt_mem_guard_clear_all("CODE-COV-B5 V4 preclear");
        rt.host_rt_mem_guard_program_regions(
            busy_guard_cfg,
            "CODE-COV-B5 V4 programmed regions / guard disabled"
        );

        rt.host_rt_lifecycle_init_session(
            busy_cfg,
            event_mask,
            1'b1,
            1'b1,
            "CODE-COV-B5 V4 session init"
        );

        `uvm_info("CODE_COV_B5_V4/EPOCH",
            $sformatf("B5 epoch SQ=%0d CQ=%0d; submit SQ[%0d:%0d], expect CQ[%0d:%0d]",
                busy_cfg.sq_head,
                busy_cfg.cq_head,
                sq_idx0,
                sq_idx1,
                cq_idx0,
                cq_idx1),
            UVM_MEDIUM)

        rt.write_sq_command(busy_cfg, sq_idx0, cmd0);
        rt.write_sq_command(busy_cfg, sq_idx1, cmd1);
        rt.ring_sq_tail(new_sq_tail);
        rt.start_queue();

        `uvm_info("CODE_COV_B5_V4/WAIT_STALL",
            "Waiting for validated CQ_FULL_STALL event before CONFIG_BUSY matrix",
            UVM_MEDIUM)

        rt.wait_for_progress_event(
            stall_mask,
            stall_snap,
            "CODE-COV-B5 V4 CQ-full stall",
            P27F_B5_EVENT_TIMEOUT_CYCLES,
            1'b1
        );
        p25c_check_event_snapshot(
            "CODE-COV-B5 V4 CQ-full stall",
            stall_snap,
            stall_mask
        );

        if (!stall_snap.queue_status[0] ||
            (stall_snap.sq_occupancy != 32'h0000_0001) ||
            (stall_snap.cq_occupancy != 32'h0000_0001) ||
            (stall_snap.cq_space     != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_B5_V4/BAD_STALL_STATE",
                $sformatf("Unexpected CQ-full state: q_status=0x%08h SQ(h/t/occ)=%0d/%0d/%0d CQ(h/t/occ/space)=%0d/%0d/%0d/%0d",
                    stall_snap.queue_status,
                    stall_snap.sq_head,
                    stall_snap.sq_tail,
                    stall_snap.sq_occupancy,
                    stall_snap.cq_head,
                    stall_snap.cq_tail,
                    stall_snap.cq_occupancy,
                    stall_snap.cq_space))
        end

        rt.wait_and_check_cq_record(
            busy_cfg,
            cq_idx0,
            32'(P27F_DESC0_TAG0),
            32'(P27F_DESC0_TAG1),
            cq0,
            "CODE-COV-B5 V4 first CQ",
            P27F_B5_EVENT_TIMEOUT_CYCLES
        );

        `uvm_info("CODE_COV_B5_V4/HOLD_REACHED",
            $sformatf("Hold reached: SQ(h/t/occ)=%0d/%0d/%0d CQ(h/t/occ/space)=%0d/%0d/%0d/%0d",
                stall_snap.sq_head,
                stall_snap.sq_tail,
                stall_snap.sq_occupancy,
                stall_snap.cq_head,
                stall_snap.cq_tail,
                stall_snap.cq_occupancy,
                stall_snap.cq_space),
            UVM_LOW)

        p27f_b5_issue_busy_matrix(busy_guard_cfg);

        config_busy_mask =
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_REJ_CONFIG_BUSY);
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_REJECT_STATUS,
            config_busy_mask
        );

        rt.consume_cq_entry(busy_cfg, cq_idx0, 1'b1);

        rt.wait_for_progress_event(
            recovered_mask,
            recovered_snap,
            "CODE-COV-B5 V4 CQ-space recovered",
            P27F_B5_EVENT_TIMEOUT_CYCLES,
            1'b1
        );
        p25c_check_event_snapshot(
            "CODE-COV-B5 V4 CQ-space recovered",
            recovered_snap,
            recovered_mask
        );

        rt.wait_for_progress_event(
            drained_mask,
            drained_snap,
            "CODE-COV-B5 V4 second command drained",
            P27F_B5_EVENT_TIMEOUT_CYCLES,
            1'b1
        );
        p25c_check_event_snapshot(
            "CODE-COV-B5 V4 second command drained",
            drained_snap,
            drained_mask
        );

        rt.wait_and_check_cq_record(
            busy_cfg,
            cq_idx1,
            32'(P27F_DESC1_TAG0),
            32'(P27F_DESC1_TAG1),
            cq1,
            "CODE-COV-B5 V4 second CQ",
            P27F_B5_EVENT_TIMEOUT_CYCLES
        );
        rt.consume_cq_entry(busy_cfg, cq_idx1, 1'b1);

        rt.host_rt_lifecycle_cleanup_drained(
            busy_cfg,
            event_mask,
            1'b0,
            1'b0,
            1'b1,
            "CODE-COV-B5 V4 final drained cleanup"
        );

        rt.host_rt_mem_guard_clear_all("CODE-COV-B5 V4 final guard clear");

        `uvm_info("CODE_COV_B5_V4/PASS",
            $sformatf("B5 CONFIG_BUSY matrix PASS: all 11 writes covered; starting SQ/CQ epoch=%0d/%0d",
                entry_snap.sq_head,
                entry_snap.cq_head),
            UVM_LOW)
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
        bit code_cov_b5_v4_done;
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t baseline_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t bad_cq_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t recovery_cmd;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t baseline_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t recovery_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p27_guard_cfg_t guard_cfg;

        logic [31:0] event_mask;
        logic [31:0] bad_cq_limit;
    begin
        phase.raise_objection(this);

        `uvm_info("P27F_GUARD/START",
            "Starting P27F CQ / completion writeback memory guard recovery smoke test",
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
            P27F_DESC_BASE0,
            P27F_DESC0_TAG0,
            P27F_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p25c_program_descriptor_table(
            P27F_DESC_BASE1,
            P27F_DESC1_TAG0,
            P27F_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p27f_make_cfg(rt, cfg);
        p27f_make_cmd(rt, baseline_cmd, 32'(P27F_DESC_BASE0), P27F_BASELINE_CMD_TAG);
        p27f_make_cmd(rt, bad_cq_cmd,   32'(P27F_DESC_BASE1), P27F_BAD_CQ_CMD_TAG);
        p27f_make_cmd(rt, recovery_cmd, 32'(P27F_DESC_BASE1), P27F_RECOVERY_CMD_TAG);

        event_mask = rt.queue_completion_event_mask() |
                     rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);

        // After the valid baseline, the pointer-preserving epoch advances to
        // CQ[1].  This limit makes the next 64-byte CQ slot unsafe, so the
        // queue must reject before writing any completion record there.
        bad_cq_limit = 32'(P27F_CQ_BASE + 32'h0000_0020);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_program_completion_wb();

        p27f_make_guard_cfg(rt, cfg, 32'h0000_0000, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "P27F valid baseline guard cfg");
        rt.host_rt_mem_guard_check_clean("P27F initial guard clean", 1'b1, 1'b0);

        rt.host_rt_lifecycle_init_session(
            cfg,
            event_mask,
            1'b1,
            1'b1,
            "P27F initial lifecycle init"
        );

        p26d_run_drained_session_without_cleanup(
            rt,
            cfg,
            baseline_cmd,
            profile_item,
            P27F_DESC0_TAG0,
            P27F_DESC0_TAG1,
            0,
            "P27F valid baseline",
            baseline_snap
        );

        p26d_cleanup_drained_and_require_clean(
            rt,
            cfg,
            event_mask,
            "P27F valid baseline cleanup"
        );

        p26d_set_cfg_epoch(cfg, 1);
        rt.host_rt_mem_guard_check_clean("P27F after valid baseline guard clean", 1'b1, 1'b1);

        `uvm_info("P27F_GUARD/VALID_BASELINE_PASS",
            "P27F valid SQ/CQ/DESC/SRC/DST guard baseline command completed normally",
            UVM_MEDIUM)

        // CQ range negative: SQ, descriptor, source, and destination ranges
        // are safe, but the current CQ completion slot is outside the CQ
        // guard range.  The queue must not issue an unsafe completion write.
        p27f_make_guard_cfg(rt, cfg, bad_cq_limit, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "P27F CQ range reject guard cfg");

        p27f_run_cq_guard_negative_case(
            rt,
            cfg,
            bad_cq_cmd,
            1,
            1,
            32'h0000_0002,
            "P27F CQ range reject"
        );

        // Known-good recovery after CQ guard reject.
        p27f_make_guard_cfg(rt, cfg, 32'h0000_0000, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "P27F recovery valid guard cfg");
        rt.host_rt_mem_guard_check_clean("P27F recovery guard clean", 1'b1, 1'b1);

        rt.host_rt_lifecycle_init_session(
            cfg,
            event_mask,
            1'b1,
            1'b1,
            "P27F recovery lifecycle init"
        );

        p26d_run_drained_session_without_cleanup(
            rt,
            cfg,
            recovery_cmd,
            profile_item,
            P27F_DESC1_TAG0,
            P27F_DESC1_TAG1,
            1,
            "P27F recovery command",
            recovery_snap
        );

        p26d_cleanup_drained_and_require_clean(
            rt,
            cfg,
            event_mask,
            "P27F recovery final cleanup"
        );

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        rt.host_rt_mem_guard_check_clean("P27F final guard clean", 1'b1, 1'b1);
        rt.host_rt_lifecycle_check_clean_idle("P27F final lifecycle clean idle", 1'b0, 1'b1, 1'b0);

        `uvm_info("P27F_GUARD/RECOVERY_PASS",
            "P27F known-good command completed after CQ guard reject and suppressed unsafe CQ writeback",
            UVM_MEDIUM)

        // ------------------------------------------------------------
        // CODE-COV-B5 final subphase.
        //
        // Run only after the original P27F verification has already passed.
        // The watchdog is independent of helper polling loops, so this phase
        // can no longer look like an infinite simulation.
        // ------------------------------------------------------------
        code_cov_b5_v4_done = 1'b0;
        fork : code_cov_b5_v4_watchdog_fork
            begin : code_cov_b5_v4_body
                p27f_run_config_busy_matrix_v4(rt);
                code_cov_b5_v4_done = 1'b1;
            end
            begin : code_cov_b5_v4_watchdog
                repeat (P27F_B5_WATCHDOG_CYCLES) @(posedge p17d_ctrl_vif.clk);
                if (!code_cov_b5_v4_done) begin
                    `uvm_fatal("CODE_COV_B5_V4/WATCHDOG",
                        $sformatf("B5 exceeded absolute watchdog of %0d ctrl-clock cycles",
                            P27F_B5_WATCHDOG_CYCLES))
                end
            end
        join_any
        disable code_cov_b5_v4_watchdog_fork;

        `uvm_info("P27F_GUARD/PASS",
            $sformatf("P27F CQ / completion writeback memory guard validation PASS: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
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
