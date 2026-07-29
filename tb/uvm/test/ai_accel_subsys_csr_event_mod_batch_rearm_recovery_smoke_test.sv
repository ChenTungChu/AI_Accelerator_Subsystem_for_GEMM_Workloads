// File: tb/uvm/test/ai_accel_subsys_csr_event_mod_batch_rearm_recovery_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_EVENT_MOD_BATCH_REARM_RECOVERY_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_EVENT_MOD_BATCH_REARM_RECOVERY_SMOKE_TEST_SV

// ============================================================
// P28F multi-command batch consume / re-arm recovery smoke
//
// Scope:
//   - Reuses the validated P23 event-driven SQ/CQ host runtime path.
//   - Enables the P28 event moderation CSR policy with CQ threshold = 2.
//   - Runs two consecutive two-command batches in one queue pointer epoch.
//   - On the first batch, W1C-acks the threshold notification while CQ
//     occupancy is still 2 and proves RETRIGGER_ON_STILL_NONEMPTY produces
//     a REARM_NONEMPTY moderation release before CQ_HEAD advances.
//   - Host then consumes each visible CQ batch, publishes CQ_HEAD, performs
//     the normal clean W1C/re-arm, and appends the next batch.
//   - Proves both the still-nonempty re-arm path and the second coalesced
//     notification are not lost after W1C/re-arm.
//   - Confirms terminal queue events remain visible while completion-style
//     CQ notification is moderated.
//
// P28F does not change SQ/CQ entry format, descriptor format, completion
// record format, BRAM, GEMM, DMA, AXI-Stream, or Direct Stream datapath
// behavior.
// ============================================================

class ai_accel_subsys_csr_event_mod_batch_rearm_recovery_smoke_test
    extends ai_accel_subsys_csr_event_driven_multi_command_queue_drain_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_event_mod_batch_rearm_recovery_smoke_test)

    localparam int unsigned P28F_SQ_BASE       = 32'h0000_0700;
    localparam int unsigned P28F_CQ_BASE       = 32'h0000_0800;
    localparam int unsigned P28F_QUEUE_DEPTH   = 4;

    localparam int unsigned P28F_DESC_BASE0    = 32'h0000_0300;
    localparam int unsigned P28F_DESC_BASE1    = 32'h0000_0400;
    localparam int unsigned P28F_DESC_BASE2    = 32'h0000_0500;
    localparam int unsigned P28F_DESC_BASE3    = 32'h0000_0600;
    localparam int unsigned P28F_DESC_STRIDE   = 32'h0000_0080;

    localparam logic [31:0] P28F_CMD0_TAG      = 32'hD28F_0000;
    localparam logic [31:0] P28F_CMD1_TAG      = 32'hD28F_0001;
    localparam logic [31:0] P28F_CMD2_TAG      = 32'hD28F_0002;
    localparam logic [31:0] P28F_CMD3_TAG      = 32'hD28F_0003;

    localparam logic [31:0] P28F_DESC0_TAG0    = 32'hD28F_1000;
    localparam logic [31:0] P28F_DESC0_TAG1    = 32'hD28F_1001;
    localparam logic [31:0] P28F_DESC1_TAG0    = 32'hD28F_2000;
    localparam logic [31:0] P28F_DESC1_TAG1    = 32'hD28F_2001;
    localparam logic [31:0] P28F_DESC2_TAG0    = 32'hD28F_3000;
    localparam logic [31:0] P28F_DESC2_TAG1    = 32'hD28F_3001;
    localparam logic [31:0] P28F_DESC3_TAG0    = 32'hD28F_4000;
    localparam logic [31:0] P28F_DESC3_TAG1    = 32'hD28F_4001;

    localparam logic [31:0] P28F_CQ_THRESHOLD  = 32'h0000_0002;

    function new(string name = "ai_accel_subsys_csr_event_mod_batch_rearm_recovery_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p28f_make_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg
    );
    begin
        rt.make_default_queue_cfg(
            cfg,
            32'(P28F_SQ_BASE),
            32'(P28F_CQ_BASE),
            32'(P28F_QUEUE_DEPTH),
            1'b1
        );
    end
    endtask

    task automatic p28f_make_cmd(
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
            32'(P28F_DESC_STRIDE),
            user_tag,
            1'b1,
            1'b0
        );
        cmd.timeout_cycles = 32'h0000_0000;
    end
    endtask

    task automatic p28f_check_rearm_clean(
        input ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t snap,
        input logic [31:0] ack_mask,
        input string label
    );
    begin
        if ((snap.event_pending & ack_mask) != 32'h0000_0000) begin
            `uvm_fatal("P28F_MOD/REARM_PENDING",
                $sformatf("%s: acked event bits still pending pending=0x%08h ack_mask=0x%08h",
                    label,
                    snap.event_pending,
                    ack_mask))
        end

        if (snap.event_status[ai_accel_csr_access_helper::EVENT_STATUS_EVENT_IRQ_OUT]) begin
            `uvm_fatal("P28F_MOD/REARM_IRQ",
                $sformatf("%s: event IRQ still asserted after batch consume + W1C re-arm status=0x%08h pending=0x%08h",
                    label,
                    snap.event_status,
                    snap.event_pending))
        end

        `uvm_info("P28F_MOD/REARM_PASS",
            $sformatf("%s: event path re-armed cleanly pending=0x%08h status=0x%08h SQ(h/t)=%0d/%0d CQ(h/t/occ)=%0d/%0d/%0d",
                label,
                snap.event_pending,
                snap.event_status,
                snap.sq_head,
                snap.sq_tail,
                snap.cq_head,
                snap.cq_tail,
                snap.cq_occupancy),
            UVM_MEDIUM)
    end
    endtask

    task automatic p28f_check_nonempty_rearm(
        input ai_accel_event_driven_host_runtime_stress_helper rt,
        input ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t snap,
        input logic [31:0] required_mask,
        input logic [31:0] expected_cq_head,
        input logic [31:0] expected_cq_occupancy,
        input string label
    );
    begin
        if ((snap.event_pending & required_mask) != required_mask) begin
            `uvm_fatal("P28F_MOD/NONEMPTY_REARM_PENDING",
                $sformatf("%s: expected re-armed completion-style pending bits required=0x%08h pending=0x%08h",
                    label,
                    required_mask,
                    snap.event_pending))
        end

        if (snap.cq_head != expected_cq_head) begin
            `uvm_fatal("P28F_MOD/NONEMPTY_REARM_HEAD",
                $sformatf("%s: CQ_HEAD changed before host consume actual=%0d expected=%0d",
                    label,
                    snap.cq_head,
                    expected_cq_head))
        end

        if (snap.cq_occupancy != expected_cq_occupancy) begin
            `uvm_fatal("P28F_MOD/NONEMPTY_REARM_OCC",
                $sformatf("%s: CQ occupancy changed before host consume actual=%0d expected=%0d head=%0d tail=%0d",
                    label,
                    snap.cq_occupancy,
                    expected_cq_occupancy,
                    snap.cq_head,
                    snap.cq_tail))
        end

        if (snap.event_status[ai_accel_csr_access_helper::EVENT_STATUS_EVENT_IRQ_OUT] !== 1'b1) begin
            `uvm_fatal("P28F_MOD/NONEMPTY_REARM_IRQ",
                $sformatf("%s: re-armed completion notification did not reassert IRQ status=0x%08h pending=0x%08h",
                    label,
                    snap.event_status,
                    snap.event_pending))
        end

        rt.host_rt_event_mod_expect_release_cause(
            snap,
            ai_accel_csr_access_helper::P28_MOD_RELEASE_REARM,
            {label, " release cause"}
        );

        `uvm_info("P28F_MOD/NONEMPTY_REARM_PASS",
            $sformatf("%s: still-nonempty W1C/re-arm PASS pending=0x%08h status=0x%08h CQ(h/t/occ)=%0d/%0d/%0d release=%s(0x%02h)",
                label,
                snap.event_pending,
                snap.event_status,
                snap.cq_head,
                snap.cq_tail,
                snap.cq_occupancy,
                rt.host_rt_event_mod_release_name(
                    rt.host_rt_event_mod_debug_release_cause(snap.mod_debug)),
                rt.host_rt_event_mod_debug_release_cause(snap.mod_debug)),
            UVM_MEDIUM)
    end
    endtask

    task automatic p28f_check_urgent_visible(
        input ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t snap,
        input logic [31:0] urgent_mask,
        input string label
    );
    begin
        if ((snap.event_pending & urgent_mask) == 32'h0000_0000) begin
            `uvm_fatal("P28F_MOD/URGENT_MISSING",
                $sformatf("%s: expected queue terminal / urgent pending bits while moderation is enabled, pending=0x%08h urgent_mask=0x%08h",
                    label,
                    snap.event_pending,
                    urgent_mask))
        end

        `uvm_info("P28F_MOD/URGENT_BYPASS_PASS",
            $sformatf("%s: urgent/terminal bits visible with moderation enabled pending=0x%08h urgent_mask=0x%08h mod_debug=0x%08h",
                label,
                snap.event_pending,
                urgent_mask,
                snap.mod_debug),
            UVM_LOW)
    end
    endtask

    task automatic p28f_check_threshold_release_delta(
        input ai_accel_event_driven_host_runtime_stress_helper rt,
        input ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t snap,
        input logic [7:0] previous_threshold_count,
        input string label,
        output logic [7:0] threshold_count
    );
        logic [7:0] release_cause;
    begin
        threshold_count = rt.host_rt_event_mod_debug_threshold_count(snap.mod_debug);
        release_cause   = rt.host_rt_event_mod_debug_release_cause(snap.mod_debug);

        if (threshold_count == previous_threshold_count) begin
            `uvm_fatal("P28F_MOD/THRESHOLD_RELEASE",
                $sformatf("%s: threshold release counter did not advance previous=%0d current=%0d release=%s(0x%02h) mod_debug=0x%08h",
                    label,
                    previous_threshold_count,
                    threshold_count,
                    rt.host_rt_event_mod_release_name(release_cause),
                    release_cause,
                    snap.mod_debug))
        end

        `uvm_info("P28F_MOD/THRESHOLD_RELEASE_PASS",
            $sformatf("%s: threshold release advanced previous=%0d current=%0d release=%s(0x%02h) mod_debug=0x%08h",
                label,
                previous_threshold_count,
                threshold_count,
                rt.host_rt_event_mod_release_name(release_cause),
                release_cause,
                snap.mod_debug),
            UVM_MEDIUM)
    end
    endtask

    task automatic p28f_check_batch_result(
        input ai_accel_event_driven_host_runtime_stress_helper::p28_cq_batch_result_t batch_result,
        input int unsigned expected_consumed,
        input int unsigned expected_start_head,
        input int unsigned expected_final_head,
        input logic [31:0] expected_first_tag,
        input logic [31:0] expected_last_tag,
        input string label,
        input string marker_id
    );
    begin
        if (batch_result.consumed_count != expected_consumed) begin
            `uvm_fatal("P28F_MOD/BATCH_COUNT",
                $sformatf("%s: consumed_count mismatch actual=%0d expected=%0d",
                    label,
                    batch_result.consumed_count,
                    expected_consumed))
        end

        if (batch_result.start_cq_head != expected_start_head) begin
            `uvm_fatal("P28F_MOD/BATCH_START_HEAD",
                $sformatf("%s: start CQ_HEAD mismatch actual=%0d expected=%0d",
                    label,
                    batch_result.start_cq_head,
                    expected_start_head))
        end

        if (batch_result.final_cq_head != expected_final_head) begin
            `uvm_fatal("P28F_MOD/BATCH_FINAL_HEAD",
                $sformatf("%s: final CQ_HEAD mismatch actual=%0d expected=%0d",
                    label,
                    batch_result.final_cq_head,
                    expected_final_head))
        end

        if (batch_result.first_user_tag !== expected_first_tag) begin
            `uvm_fatal("P28F_MOD/BATCH_FIRST_TAG",
                $sformatf("%s: first_user_tag mismatch actual=0x%08h expected=0x%08h",
                    label,
                    batch_result.first_user_tag,
                    expected_first_tag))
        end

        if (batch_result.last_user_tag !== expected_last_tag) begin
            `uvm_fatal("P28F_MOD/BATCH_LAST_TAG",
                $sformatf("%s: last_user_tag mismatch actual=0x%08h expected=0x%08h",
                    label,
                    batch_result.last_user_tag,
                    expected_last_tag))
        end

        `uvm_info(marker_id,
            $sformatf("%s PASS: consumed=%0d CQ_HEAD %0d->%0d first_tag=0x%08h last_tag=0x%08h",
                label,
                batch_result.consumed_count,
                batch_result.start_cq_head,
                batch_result.final_cq_head,
                batch_result.first_user_tag,
                batch_result.last_user_tag),
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
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd0;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd1;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd2;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd3;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_cfg_t mod_cfg;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t first_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t first_nonempty_rearm_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t first_rearm_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t second_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t second_rearm_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p28_cq_batch_result_t first_batch;
        ai_accel_event_driven_host_runtime_stress_helper::p28_cq_batch_result_t second_batch;

        logic [31:0] event_enable_mask;
        logic [31:0] threshold_required_mask;
        logic [31:0] nonempty_rearm_required_mask;
        logic [31:0] urgent_bypass_mask;
        logic [31:0] ack_mask0;
        logic [31:0] ack_mask0_cleanup;
        logic [31:0] ack_mask1;
        logic [7:0]  threshold_count0;
        logic [7:0]  threshold_count1;
    begin
        phase.raise_objection(this);

        `uvm_info("P28F_MOD/START",
            "Starting P28F multi-command batch consume / re-arm recovery smoke test",
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
            `uvm_fatal("P28F_MOD/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        program_p23d_descriptor_table(
            P28F_DESC_BASE0,
            P28F_DESC0_TAG0,
            P28F_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        program_p23d_descriptor_table(
            P28F_DESC_BASE1,
            P28F_DESC1_TAG0,
            P28F_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        program_p23d_descriptor_table(
            P28F_DESC_BASE2,
            P28F_DESC2_TAG0,
            P28F_DESC2_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        program_p23d_descriptor_table(
            P28F_DESC_BASE3,
            P28F_DESC3_TAG0,
            P28F_DESC3_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p28f_make_cfg(rt, cfg);
        p28f_make_cmd(rt, cmd0, 32'(P28F_DESC_BASE0), P28F_CMD0_TAG);
        p28f_make_cmd(rt, cmd1, 32'(P28F_DESC_BASE1), P28F_CMD1_TAG);
        p28f_make_cmd(rt, cmd2, 32'(P28F_DESC_BASE2), P28F_CMD2_TAG);
        p28f_make_cmd(rt, cmd3, 32'(P28F_DESC_BASE3), P28F_CMD3_TAG);

        event_enable_mask = rt.host_rt_event_mod_completion_mask(
            1'b1, // QUEUE_COMMAND_COMPLETED_EVENT
            1'b1, // CQ_NOT_EMPTY_EVENT
            1'b1, // CQ_THRESHOLD_EVENT
            1'b0  // no timer event for P28F
        ) |
        rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED) |
        rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_STOPPED);

        threshold_required_mask = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_NOT_EMPTY) |
                                  rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_THRESHOLD);
        nonempty_rearm_required_mask =
            rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_COMPLETED) |
            rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_NOT_EMPTY);
        urgent_bypass_mask = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED) |
                             rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_STOPPED);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_program_completion_wb();

        rt.host_rt_lifecycle_init_session(
            cfg,
            event_enable_mask,
            1'b1,
            1'b1,
            "P28F batch/rearm init"
        );

        rt.host_rt_event_mod_default_cfg(
            mod_cfg,
            1'b1, // moderation_enable
            1'b1, // cq_threshold_enable
            1'b0, // moderation_timer_enable
            1'b1, // retrigger_on_nonempty
            P28F_CQ_THRESHOLD,
            32'h0000_0000,
            event_enable_mask,
            1'b1,
            1'b1
        );
        rt.host_rt_event_mod_program(mod_cfg, "P28F threshold moderation cfg");

        // ------------------------------------------------------------
        // Batch 0:
        // Two commands produce CQ[0]/CQ[1].  Threshold=2 releases one
        // coalesced notification.  The host consumes both records and re-arms.
        // ------------------------------------------------------------
        rt.write_sq_command(cfg, 0, cmd0, 1'b1);
        rt.write_sq_command(cfg, 1, cmd1, 1'b1);
        rt.ring_sq_tail(32'h0000_0002);
        rt.start_queue();

        rt.host_rt_event_mod_wait_notification(
            threshold_required_mask,
            first_snap,
            "P28F first batch threshold notification",
            done_timeout_cycles * 8,
            1'b1
        );
        rt.host_rt_event_mod_expect_pending(
            first_snap,
            threshold_required_mask,
            32'h0000_0000,
            "P28F first batch pending check"
        );
        p28f_check_urgent_visible(first_snap, urgent_bypass_mask, "P28F first batch urgent bypass");
        p28f_check_threshold_release_delta(rt, first_snap, 8'h00, "P28F first batch threshold release", threshold_count0);
        rt.host_rt_event_mod_expect_cq_occupancy(first_snap, 2, 2, "P28F first batch CQ occupancy");

        // CODE-COV-D3:
        // ACK the first threshold notification before CQ consumption.  CQ is
        // deliberately still non-empty (occupancy=2), so the enabled
        // RETRIGGER_ON_STILL_NONEMPTY policy must generate a REARM release.
        ack_mask0 = first_snap.event_pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.host_rt_event_mod_ack_and_rearm(
            ack_mask0,
            event_enable_mask,
            P28F_CQ_THRESHOLD,
            1'b1,
            1'b1,
            "P28F first batch still-nonempty ack/rearm"
        );
        rt.host_rt_event_mod_capture_snapshot(first_nonempty_rearm_snap);
        rt.host_rt_event_mod_log_snapshot(
            "P28F after first still-nonempty rearm",
            first_nonempty_rearm_snap,
            UVM_MEDIUM
        );
        p28f_check_nonempty_rearm(
            rt,
            first_nonempty_rearm_snap,
            nonempty_rearm_required_mask,
            first_snap.cq_head,
            32'h0000_0002,
            "P28F first still-nonempty rearm"
        );

        // Only after proving the REARM_NONEMPTY notification do we consume
        // CQ[0:1].  This preserves the original batch result checking.
        rt.host_rt_event_mod_consume_cq_batch(
            cfg,
            first_nonempty_rearm_snap,
            0,
            first_batch,
            2,
            1'b1,
            "P28F first batch consume after nonempty rearm",
            done_timeout_cycles * 4
        );
        p28f_check_batch_result(
            first_batch,
            2,
            0,
            2,
            P28F_DESC0_TAG0,
            P28F_DESC1_TAG1,
            "P28F first coalesced batch",
            "P28F_MOD/BATCH1_PASS"
        );

        // CQ is now empty.  Clear the reasserted completion-style event and
        // perform the existing clean re-arm check before appending batch 1.
        ack_mask0_cleanup =
            first_nonempty_rearm_snap.event_pending &
            ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.host_rt_event_mod_ack_and_rearm(
            ack_mask0_cleanup,
            event_enable_mask,
            P28F_CQ_THRESHOLD,
            1'b1,
            1'b1,
            "P28F first batch post-consume cleanup ack/rearm"
        );
        rt.host_rt_event_mod_capture_snapshot(first_rearm_snap);
        rt.host_rt_event_mod_log_snapshot("P28F after first clean rearm", first_rearm_snap, UVM_MEDIUM);
        p28f_check_rearm_clean(
            first_rearm_snap,
            ack_mask0_cleanup,
            "P28F first post-consume rearm clean"
        );
        `uvm_info("P28F_MOD/RECOVERY_READY_PASS",
            $sformatf("P28F first rearm completed: SQ(h/t)=%0d/%0d CQ(h/t/occ)=%0d/%0d/%0d threshold_count=%0d",
                first_rearm_snap.sq_head,
                first_rearm_snap.sq_tail,
                first_rearm_snap.cq_head,
                first_rearm_snap.cq_tail,
                first_rearm_snap.cq_occupancy,
                threshold_count0),
            UVM_MEDIUM)

        // ------------------------------------------------------------
        // Batch 1 / recovery:
        // Without resetting the queue pointer epoch, append SQ[2]/SQ[3].
        // The second threshold notification proves W1C/re-arm did not lose
        // the next coalesced completion window.
        // ------------------------------------------------------------
        rt.write_sq_command(cfg, 2, cmd2, 1'b1);
        rt.write_sq_command(cfg, 3, cmd3, 1'b1);
        rt.ring_sq_tail(32'h0000_0004);
        rt.start_queue();

        rt.host_rt_event_mod_wait_notification(
            threshold_required_mask,
            second_snap,
            "P28F second batch threshold notification",
            done_timeout_cycles * 8,
            1'b1
        );
        rt.host_rt_event_mod_expect_pending(
            second_snap,
            threshold_required_mask,
            32'h0000_0000,
            "P28F second batch pending check"
        );
        p28f_check_urgent_visible(second_snap, urgent_bypass_mask, "P28F second batch urgent bypass");
        p28f_check_threshold_release_delta(rt, second_snap, threshold_count0, "P28F second batch threshold release", threshold_count1);
        rt.host_rt_event_mod_expect_cq_occupancy(second_snap, 2, 2, "P28F second batch CQ occupancy");

        rt.host_rt_event_mod_consume_cq_batch(
            cfg,
            second_snap,
            2,
            second_batch,
            2,
            1'b1,
            "P28F second batch consume",
            done_timeout_cycles * 4
        );
        p28f_check_batch_result(
            second_batch,
            2,
            2,
            4,
            P28F_DESC2_TAG0,
            P28F_DESC3_TAG1,
            "P28F second coalesced batch after rearm",
            "P28F_MOD/BATCH2_PASS"
        );

        ack_mask1 = second_snap.event_pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.host_rt_event_mod_ack_and_rearm(
            ack_mask1,
            event_enable_mask,
            P28F_CQ_THRESHOLD,
            1'b1,
            1'b1,
            "P28F second batch ack/rearm"
        );
        rt.host_rt_event_mod_capture_snapshot(second_rearm_snap);
        rt.host_rt_event_mod_log_snapshot("P28F after second rearm", second_rearm_snap, UVM_MEDIUM);
        p28f_check_rearm_clean(second_rearm_snap, ack_mask1, "P28F second rearm clean");

        if (second_rearm_snap.cq_occupancy != 32'h0000_0000) begin
            `uvm_fatal("P28F_MOD/FINAL_CQ_OCC",
                $sformatf("P28F final CQ occupancy not clean after second batch consume: CQ(h/t/occ)=%0d/%0d/%0d",
                    second_rearm_snap.cq_head,
                    second_rearm_snap.cq_tail,
                    second_rearm_snap.cq_occupancy))
        end

        `uvm_info("P28F_MOD/RECOVERY_PASS",
            $sformatf("P28F re-arm recovery PASS: threshold_count %0d->%0d, CQ_HEAD %0d->%0d, nonempty_ack0=0x%08h cleanup_ack0=0x%08h ack1=0x%08h",
                threshold_count0,
                threshold_count1,
                first_batch.start_cq_head,
                second_batch.final_cq_head,
                ack_mask0,
                ack_mask0_cleanup,
                ack_mask1),
            UVM_MEDIUM)

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P28F_MOD/PASS",
            $sformatf("P28F multi-command batch consume / re-arm recovery PASS: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d threshold=%0d consumed0=%0d consumed1=%0d final_CQ_HEAD=%0d",
                selected_case_id,
                a_flat.size(),
                b_flat.size(),
                c_elems,
                P28F_CQ_THRESHOLD,
                first_batch.consumed_count,
                second_batch.consumed_count,
                second_batch.final_cq_head),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
