// File: tb/uvm/test/ai_accel_subsys_csr_queue_lifecycle_timeout_error_reinit_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_LIFECYCLE_TIMEOUT_ERROR_REINIT_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_LIFECYCLE_TIMEOUT_ERROR_REINIT_SMOKE_TEST_SV

// ============================================================
// P26F queue lifecycle timeout/error cleanup + reinit smoke
//
// Scope:
//   - Reuses the P26C lifecycle helper extension and the P26D
//     pointer-preserving monotonic queue epoch model.
//   - Starts a queue session with one finite-timeout SQ command.
//   - Observes P24 COMMAND_TIMEOUT_ERROR through the existing P22
//     QUEUE_ERROR_EVENT notification path.
//   - Captures queue/event diagnostic state before cleanup.
//   - Performs lifecycle error-session discard cleanup:
//       * consume any visible timeout CQ record, if one was committed
//       * clear event pending/counters
//       * clear queue error/reject/done/counter sticky state
//       * clear lower-level P14/P15/P16/P17/P18 sticky state
//       * recycle SQ/CQ memory
//       * realign host-owned SQ_TAIL and CQ_HEAD to the observed
//         hardware-owned SQ_HEAD/CQ_TAIL epoch instead of requiring
//         zero-pointer reset
//   - Reinitializes the cleaned queue context and submits a known-good
//     timeout-disabled command.
//   - Verifies the known-good command completes normally, produces a CQ
//     record, passes result compare, and leaves queue/event state clean.
//
// This is UVM/helper-only validation.  It does not add RTL, CSR map
// changes, SQ/CQ format changes, descriptor-format changes, completion
// record changes, event bits, standalone tops, or datapath changes.
// ============================================================

class ai_accel_subsys_csr_queue_lifecycle_timeout_error_reinit_smoke_test
    extends ai_accel_subsys_csr_queue_lifecycle_drained_reinit_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_lifecycle_timeout_error_reinit_smoke_test)

    localparam int unsigned P26F_SQ_BASE     = 32'h0000_0D00;
    localparam int unsigned P26F_CQ_BASE     = 32'h0000_0E00;
    localparam int unsigned P26F_QUEUE_DEPTH = 4;

    localparam int unsigned P26F_TIMEOUT_DESC_BASE  = 32'h0000_0300;
    localparam int unsigned P26F_RECOVERY_DESC_BASE = 32'h0000_0400;
    localparam int unsigned P26F_DESC_STRIDE        = 32'h0000_0080;

    localparam logic [31:0] P26F_TIMEOUT_CMD_TAG    = 32'hD26F_0000;
    localparam logic [31:0] P26F_RECOVERY_CMD_TAG   = 32'hD26F_0001;

    localparam logic [31:0] P26F_TIMEOUT_DESC_TAG0  = 32'hD26F_1000;
    localparam logic [31:0] P26F_TIMEOUT_DESC_TAG1  = 32'hD26F_1001;
    localparam logic [31:0] P26F_RECOVERY_DESC_TAG0 = 32'hD26F_2000;
    localparam logic [31:0] P26F_RECOVERY_DESC_TAG1 = 32'hD26F_2001;

    // P24B canonical queue timeout status bit.
    localparam int unsigned P26F_QUEUE_ERROR_COMMAND_TIMEOUT_BIT = 6;

    // Keep the timeout small enough to fire before the normal descriptor
    // fetch / recipe / GEMM / completion path reaches terminal completion.
    localparam logic [31:0] P26F_SHORT_TIMEOUT_CYCLES = 32'h0000_0020;

    function new(string name = "ai_accel_subsys_csr_queue_lifecycle_timeout_error_reinit_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p26f_make_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg
    );
    begin
        rt.make_default_queue_cfg(
            cfg,
            32'(P26F_SQ_BASE),
            32'(P26F_CQ_BASE),
            32'(P26F_QUEUE_DEPTH),
            1'b1  // RUN_UNTIL_EMPTY for the post-clean known-good command.
        );
    end
    endtask

    task automatic p26f_make_cmd(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd,
        input  logic [31:0] desc_base,
        input  logic [31:0] user_tag,
        input  logic [31:0] timeout_cycles
    );
    begin
        rt.make_fetch_recipe_cmd(
            cmd,
            desc_base,
            32'h0000_0002,
            32'(P26F_DESC_STRIDE),
            user_tag,
            1'b1,
            1'b0
        );

        cmd.timeout_cycles = timeout_cycles;
    end
    endtask

    task automatic p26f_expect_timeout_error_snapshot(
        input ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t snap,
        input string label
    );
    begin
        if ((snap.event_snap.pending & (32'h1 << ai_accel_csr_access_helper::P22_EVENT_QUEUE_ERROR)) == 32'h0000_0000) begin
            `uvm_fatal("P26F_LIFECYCLE/NO_QUEUE_ERROR_EVENT",
                $sformatf("%s: expected QUEUE_ERROR_EVENT pending, pending=0x%08h status=0x%08h",
                    label,
                    snap.event_snap.pending,
                    snap.event_snap.status))
        end

        if (!snap.queue_status[2]) begin
            `uvm_fatal("P26F_LIFECYCLE/NO_QUEUE_ERROR_STATUS",
                $sformatf("%s: expected QUEUE_STATUS.QUEUE_ERROR, status=0x%08h error=0x%08h reject=0x%08h",
                    label,
                    snap.queue_status,
                    snap.queue_error_status,
                    snap.queue_reject_status))
        end

        if (!snap.queue_error_status[P26F_QUEUE_ERROR_COMMAND_TIMEOUT_BIT]) begin
            `uvm_fatal("P26F_LIFECYCLE/TIMEOUT_BIT_MISSING",
                $sformatf("%s: expected CSR_QUEUE_ERROR_STATUS[%0d] COMMAND_TIMEOUT_ERROR, error=0x%08h detail=0x%08h index=0x%08h tag=0x%08h",
                    label,
                    P26F_QUEUE_ERROR_COMMAND_TIMEOUT_BIT,
                    snap.queue_error_status,
                    snap.error_detail,
                    snap.error_index,
                    snap.last_cmd_tag))
        end

        if (snap.last_cmd_tag !== P26F_TIMEOUT_CMD_TAG) begin
            `uvm_fatal("P26F_LIFECYCLE/TIMEOUT_TAG_MISMATCH",
                $sformatf("%s: expected timeout command tag 0x%08h, got 0x%08h",
                    label,
                    P26F_TIMEOUT_CMD_TAG,
                    snap.last_cmd_tag))
        end

        `uvm_info("P26F_LIFECYCLE/TIMEOUT_OBSERVED",
            $sformatf("%s: timeout error observed pending=0x%08h error=0x%08h detail=0x%08h index=0x%08h SQ(h/t)=%0d/%0d CQ(h/t)=%0d/%0d",
                label,
                snap.event_snap.pending,
                snap.queue_error_status,
                snap.error_detail,
                snap.error_index,
                snap.sq_head,
                snap.sq_tail,
                snap.cq_head,
                snap.cq_tail),
            UVM_MEDIUM)
    end
    endtask

    task automatic p26f_cleanup_error_session_and_reinit_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        ref    ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input  logic [31:0] event_enable_mask,
        output ai_accel_event_driven_host_runtime_stress_helper::p26_lifecycle_snapshot_t error_snap,
        input  string label
    );
        ai_accel_event_driven_host_runtime_stress_helper::p26_lifecycle_snapshot_t post_snap;
    begin
        rt.host_rt_lifecycle_wait_idle(
            {label, " wait_idle"},
            ai_accel_event_driven_host_runtime_stress_helper::P26_DEFAULT_LIFECYCLE_TIMEOUT_CYCLES,
            1'b1
        );

        rt.host_rt_lifecycle_capture_error_snapshot(
            error_snap,
            {label, " diagnostic_snapshot"},
            1'b1
        );

        if (!error_snap.queue_error_status[P26F_QUEUE_ERROR_COMMAND_TIMEOUT_BIT]) begin
            `uvm_fatal("P26F_LIFECYCLE/CLEANUP_NOT_TIMEOUT",
                $sformatf("%s: cleanup expected timeout error bit, error=0x%08h detail=0x%08h",
                    label,
                    error_snap.queue_error_status,
                    error_snap.queue_error_detail))
        end

        // If the timeout path produced a valid CQ record and advanced CQ_TAIL,
        // consume it before discarding the session.  If no CQ record exists,
        // this is a no-op because CQ_HEAD == CQ_TAIL.
        rt.host_rt_lifecycle_consume_visible_cq(
            cfg,
            error_snap,
            1'b1,
            {label, " consume_optional_timeout_cq"}
        );

        rt.host_rt_lifecycle_clear_all_events_and_counters({label, " event_clear"});
        rt.host_rt_lifecycle_clear_queue_all_sticky(1'b1, {label, " queue_clear"});
        rt.host_rt_lifecycle_clear_lower_sticky({label, " lower_clear"});

        rt.host_rt_lifecycle_recycle_sq_slots(cfg, 0, cfg.sq_depth, {label, " recycle_sq"});
        rt.host_rt_lifecycle_recycle_cq_slots(cfg, 0, cfg.cq_depth, {label, " recycle_cq"});

        // Session-discard realignment policy:
        //   SQ_HEAD / CQ_TAIL are hardware-owned monotonic counters.
        //   The host discards the errored session by aligning host-owned
        //   SQ_TAIL to observed SQ_HEAD and CQ_HEAD to observed CQ_TAIL.
        // This avoids relying on zero-pointer reset, matching the P26D/P26E
        // pointer-preserving lifecycle policy already validated in this RTL.
        cfg.sq_head = error_snap.sq_head;
        cfg.sq_tail = error_snap.sq_head;
        cfg.cq_head = error_snap.cq_tail;
        cfg.cq_tail = error_snap.cq_tail;

        rt.program_queue(cfg);
        rt.host_rt_lifecycle_rearm_events(event_enable_mask, 1'b1, 32'h0000_0000, 1'b1, {label, " event_rearm"});
        rt.host_rt_lifecycle_check_clean_idle({label, " clean_check"}, 1'b0, 1'b1, 1'b0);
        rt.host_rt_lifecycle_capture_snapshot(post_snap, {label, " reinit_epoch"}, 1'b1);

        if ((post_snap.sq_head !== cfg.sq_head) ||
            (post_snap.sq_tail !== cfg.sq_tail) ||
            (post_snap.cq_head !== cfg.cq_head) ||
            (post_snap.cq_tail !== cfg.cq_tail)) begin
            `uvm_fatal("P26F_LIFECYCLE/REINIT_EPOCH_MISMATCH",
                $sformatf("%s: expected reinit epoch SQ(h/t)=%0d/%0d CQ(h/t)=%0d/%0d, got SQ(h/t)=%0d/%0d CQ(h/t)=%0d/%0d",
                    label,
                    cfg.sq_head,
                    cfg.sq_tail,
                    cfg.cq_head,
                    cfg.cq_tail,
                    post_snap.sq_head,
                    post_snap.sq_tail,
                    post_snap.cq_head,
                    post_snap.cq_tail))
        end

        `uvm_info("P26F_LIFECYCLE/ERROR_CLEANUP_PASS",
            $sformatf("%s: timeout/error discard cleanup PASS; reinit epoch SQ=%0d CQ=%0d",
                label,
                cfg.sq_tail,
                cfg.cq_head),
            UVM_MEDIUM)
    end
    endtask


    // Timeout is a queue-level terminal error; it does not abort or roll back
    // the already-launched lower-level P17/P16/P15/P18 path.  After the queue
    // error sticky state is cleared, the host must still wait until the lower
    // path has naturally quiesced before launching a known-good recovery
    // command.  Otherwise the P16 recipe sequencer may correctly keep
    // RECIPE_ACCEPT_READY low even though the queue window itself is clean.
    task automatic p26f_wait_lower_path_quiescent_after_timeout(
        input ai_accel_event_driven_host_runtime_stress_helper rt,
        input string label,
        input int unsigned timeout_cycles = 200000
    );
        logic [31:0] queue_status;
        logic [31:0] csr_status;
        logic [31:0] job_status;
        logic [31:0] recipe_status;
        logic [31:0] desc_fetch_status;
        logic [31:0] comp_wb_status;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, queue_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, csr_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_STATUS, job_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_STATUS, recipe_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_STATUS, desc_fetch_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_STATUS, comp_wb_status);

            // CSR_QUEUE_STATUS bits [12:8] summarize live command-fetch,
            // descriptor-fetch, recipe, completion-writeback, and lower-level
            // busy state.  Bit[0] is QUEUE_BUSY and bit[2] is QUEUE_ERROR.
            // For recovery, busy/error must be clear and QUEUE_ACCEPT_READY
            // bit[3] must be asserted.
            if (((queue_status & 32'h0000_1F05) == 32'h0000_0000) && queue_status[3]) begin
                `uvm_info("P26F_LIFECYCLE/LOWER_IDLE_PASS",
                    $sformatf("%s: lower path quiescent after %0d poll(s): queue=0x%08h csr=0x%08h job=0x%08h recipe=0x%08h desc=0x%08h comp=0x%08h",
                        label,
                        cnt,
                        queue_status,
                        csr_status,
                        job_status,
                        recipe_status,
                        desc_fetch_status,
                        comp_wb_status),
                    UVM_MEDIUM)
                return;
            end

            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P26F_LIFECYCLE/LOWER_IDLE_TIMEOUT",
                    $sformatf("%s: timeout waiting for lower path quiescent: queue=0x%08h csr=0x%08h job=0x%08h recipe=0x%08h desc=0x%08h comp=0x%08h",
                        label,
                        queue_status,
                        csr_status,
                        job_status,
                        recipe_status,
                        desc_fetch_status,
                        comp_wb_status))
            end

            rt.deterministic_gap(1, {label, " poll"});
        end
    end
    endtask

    task automatic p26f_finalize_error_discard_after_lower_quiesce(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        ref    ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input  logic [31:0] event_enable_mask,
        input  string label
    );
    begin
        p26f_wait_lower_path_quiescent_after_timeout(
            rt,
            {label, " wait_lower_idle"},
            done_timeout_cycles * 20
        );

        // The timed-out lower path may have completed in the background after
        // the queue timeout was already reported.  Clear those late stickies
        // and re-arm events so the recovery command observes a clean epoch.
        rt.host_rt_lifecycle_clear_all_events_and_counters({label, " event_clear_after_lower_idle"});
        rt.host_rt_lifecycle_clear_queue_all_sticky(1'b1, {label, " queue_clear_after_lower_idle"});
        rt.host_rt_lifecycle_clear_lower_sticky({label, " lower_clear_after_lower_idle"});
        rt.program_queue(cfg);
        rt.host_rt_lifecycle_rearm_events(event_enable_mask, 1'b1, 32'h0000_0000, 1'b1, {label, " event_rearm_after_lower_idle"});
        rt.host_rt_lifecycle_check_clean_idle({label, " clean_after_lower_idle"}, 1'b0, 1'b1, 1'b0);

        `uvm_info("P26F_LIFECYCLE/ERROR_REINIT_READY_PASS",
            $sformatf("%s: timeout/error discard context is fully quiescent and ready for known-good recovery START_QUEUE",
                label),
            UVM_MEDIUM)
    end
    endtask

    task automatic p26f_run_known_good_after_error_cleanup(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        input  ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input  ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd,
        input  ai_accel_subsys_seq_item profile_item,
        output ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t done_snap
    );
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec;
        int unsigned sq_idx;
        int unsigned cq_idx;
        logic [31:0] next_tail;
        logic [31:0] expected_cq_tail;
        logic [31:0] event_mask;
    begin
        event_mask       = rt.queue_completion_event_mask() |
                           rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);
        sq_idx           = cfg.sq_tail % cfg.sq_depth;
        cq_idx           = cfg.cq_tail % cfg.cq_depth;
        next_tail        = cfg.sq_tail + 32'h0000_0001;
        expected_cq_tail = cfg.cq_tail + 32'h0000_0001;

        csr_check_recipe_idle_ready("P26F before known-good START_QUEUE after error cleanup");

        rt.submit_command_and_doorbell(cfg, sq_idx, cmd, next_tail);
        rt.start_queue();

        rt.wait_for_progress_event(
            event_mask,
            done_snap,
            "P26F known-good command after timeout cleanup event wait",
            done_timeout_cycles * 12,
            1'b1
        );
        p25c_check_event_snapshot("P26F known-good command after timeout cleanup", done_snap, event_mask);

        rt.wait_and_check_cq_record(
            cfg,
            cq_idx,
            P26F_RECOVERY_DESC_TAG0,
            P26F_RECOVERY_DESC_TAG1,
            rec,
            $sformatf("P26F CQ[%0d] after timeout/error lifecycle reinit", cq_idx),
            done_timeout_cycles * 4
        );
        check_p23d_cq_record(cq_idx, rec, profile_item, P26F_RECOVERY_DESC_TAG0, P26F_RECOVERY_DESC_TAG1);

        rt.require_queue_pointers(
            "P26F known-good command pointers before final cleanup",
            next_tail,
            cfg.cq_head,
            expected_cq_tail,
            32'h0000_0001
        );

        `uvm_info("P26F_LIFECYCLE/REINIT_PASS",
            $sformatf("P26F reinit PASS: known-good timeout-disabled command completed at SQ[%0d] / CQ[%0d] after error cleanup",
                sq_idx,
                cq_idx),
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
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t timeout_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t recovery_cmd;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t timeout_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t recovery_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p26_lifecycle_snapshot_t error_snap;

        logic [31:0] error_event_mask;
        logic [31:0] recovery_event_mask;
        logic [31:0] event_enable_mask;
    begin
        phase.raise_objection(this);

        `uvm_info("P26F_LIFECYCLE/START",
            "Starting P26F timeout/error lifecycle cleanup + reinit smoke test",
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

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P26F_LIFECYCLE/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        p25c_program_descriptor_table(
            P26F_TIMEOUT_DESC_BASE,
            P26F_TIMEOUT_DESC_TAG0,
            P26F_TIMEOUT_DESC_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p25c_program_descriptor_table(
            P26F_RECOVERY_DESC_BASE,
            P26F_RECOVERY_DESC_TAG0,
            P26F_RECOVERY_DESC_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p26f_make_cfg(rt, cfg);
        p26f_make_cmd(rt, timeout_cmd, 32'(P26F_TIMEOUT_DESC_BASE), P26F_TIMEOUT_CMD_TAG, P26F_SHORT_TIMEOUT_CYCLES);
        p26f_make_cmd(rt, recovery_cmd, 32'(P26F_RECOVERY_DESC_BASE), P26F_RECOVERY_CMD_TAG, 32'h0000_0000);

        error_event_mask    = rt.queue_error_event_mask();
        recovery_event_mask = rt.queue_completion_event_mask() |
                              rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);
        event_enable_mask   = error_event_mask | recovery_event_mask;

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_program_completion_wb();

        rt.host_rt_lifecycle_init_session(
            cfg,
            event_enable_mask,
            1'b1,
            1'b1,
            "P26F initial lifecycle init"
        );

        csr_check_recipe_idle_ready("P26F before timeout START_QUEUE");

        rt.submit_command_and_doorbell(cfg, 0, timeout_cmd, 32'h0000_0001);
        rt.start_queue();

        rt.wait_for_progress_event(
            error_event_mask,
            timeout_snap,
            "P26F timeout/error event wait",
            done_timeout_cycles * 12,
            1'b1
        );
        p25c_check_event_snapshot("P26F timeout/error event", timeout_snap, error_event_mask);
        p26f_expect_timeout_error_snapshot(timeout_snap, "P26F timeout/error event");

        p26f_cleanup_error_session_and_reinit_cfg(
            rt,
            cfg,
            event_enable_mask,
            error_snap,
            "P26F timeout/error lifecycle cleanup"
        );

        `uvm_info("P26F_LIFECYCLE/ERROR_DISCARD_PASS",
            $sformatf("P26F error discard PASS: captured timeout tag=0x%08h detail=0x%08h and reinitialized at SQ=%0d CQ=%0d",
                error_snap.queue_last_cmd_tag,
                error_snap.queue_error_detail,
                cfg.sq_tail,
                cfg.cq_head),
            UVM_MEDIUM)

        p26f_finalize_error_discard_after_lower_quiesce(
            rt,
            cfg,
            event_enable_mask,
            "P26F timeout/error post-clean lower quiesce"
        );

        rt.deterministic_gap(9, "P26F gap after lower quiesce before known-good command");

        p26f_run_known_good_after_error_cleanup(
            rt,
            cfg,
            recovery_cmd,
            profile_item,
            recovery_snap
        );

        p26d_cleanup_drained_and_require_clean(
            rt,
            cfg,
            recovery_event_mask,
            "P26F final drained cleanup after timeout/error reinit"
        );

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        rt.host_rt_lifecycle_check_clean_idle(
            "P26F final clean idle state",
            1'b0,
            1'b1,
            1'b0
        );

        `uvm_info("P26F_LIFECYCLE/PASS",
            $sformatf("P26F timeout/error lifecycle cleanup + reinit PASS: CASE_ID=%0d timeout_cycles=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
                selected_case_id,
                P26F_SHORT_TIMEOUT_CYCLES,
                a_flat.size(),
                b_flat.size(),
                c_elems),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
