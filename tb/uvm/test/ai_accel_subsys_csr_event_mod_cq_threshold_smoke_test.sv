// File: tb/uvm/test/ai_accel_subsys_csr_event_mod_cq_threshold_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_EVENT_MOD_CQ_THRESHOLD_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_EVENT_MOD_CQ_THRESHOLD_SMOKE_TEST_SV

// ============================================================
// P28D CQ threshold interrupt moderation smoke
//
// Scope:
//   - Reuses the validated P23 event-driven SQ/CQ host runtime path.
//   - Enables the P28 event moderation CSR policy with CQ threshold = 2.
//   - Proves a single CQ completion can remain pending in CQ memory without
//     asserting an interrupt-eligible completion event before threshold.
//   - Runs a two-command queue drain and proves the second completion releases
//     a coalesced CQ notification through CQ_THRESHOLD / CQ_NOT_EMPTY.
//   - Host consumes the visible CQ records as a batch, publishes one CQ_HEAD
//     update, W1C-acks the event, and re-arms the event path.
//
// P28D does not change SQ/CQ entry format, descriptor format, completion
// record format, BRAM, GEMM, DMA, AXI-Stream, or Direct Stream datapath
// behavior.
// ============================================================

class ai_accel_subsys_csr_event_mod_cq_threshold_smoke_test
    extends ai_accel_subsys_csr_event_driven_multi_command_queue_drain_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_event_mod_cq_threshold_smoke_test)

    localparam int unsigned P28D_SQ_BASE     = 32'h0000_0700;
    localparam int unsigned P28D_CQ_BASE     = 32'h0000_0800;
    localparam int unsigned P28D_QUEUE_DEPTH = 4;

    localparam int unsigned P28D_DESC_BASE0  = 32'h0000_0300;
    localparam int unsigned P28D_DESC_BASE1  = 32'h0000_0400;
    localparam int unsigned P28D_DESC_STRIDE = 32'h0000_0080;

    localparam logic [31:0] P28D_CMD0_TAG    = 32'hD28D_0000;
    localparam logic [31:0] P28D_CMD1_TAG    = 32'hD28D_0001;

    localparam logic [31:0] P28D_DESC0_TAG0  = 32'hD28D_1000;
    localparam logic [31:0] P28D_DESC0_TAG1  = 32'hD28D_1001;
    localparam logic [31:0] P28D_DESC1_TAG0  = 32'hD28D_2000;
    localparam logic [31:0] P28D_DESC1_TAG1  = 32'hD28D_2001;

    function new(string name = "ai_accel_subsys_csr_event_mod_cq_threshold_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p28d_make_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input  bit run_until_empty
    );
    begin
        rt.make_default_queue_cfg(
            cfg,
            32'(P28D_SQ_BASE),
            32'(P28D_CQ_BASE),
            32'(P28D_QUEUE_DEPTH),
            run_until_empty
        );
    end
    endtask

    task automatic p28d_make_cmd(
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
            32'(P28D_DESC_STRIDE),
            user_tag,
            1'b1,
            1'b0
        );
        cmd.timeout_cycles = 32'h0000_0000;
    end
    endtask

    task automatic p28d_wait_cq_occupancy(
        input int unsigned expected_occ,
        input string label,
        input int unsigned timeout_cycles = 300000
    );
        logic [31:0] cq_occ;
        logic [31:0] cq_head;
        logic [31:0] cq_tail;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,      cq_head);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,      cq_tail);

            if (cq_occ == 32'(expected_occ)) begin
                `uvm_info("P28D_MOD/CQ_OCC_PASS",
                    $sformatf("%s: CQ occupancy reached %0d after %0d poll(s) CQ_HEAD=%0d CQ_TAIL=%0d",
                        label,
                        expected_occ,
                        cnt,
                        cq_head,
                        cq_tail),
                    UVM_MEDIUM)
                return;
            end

            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P28D_MOD/CQ_OCC_TIMEOUT",
                    $sformatf("%s: timeout waiting for CQ occupancy=%0d last_occ=%0d CQ_HEAD=%0d CQ_TAIL=%0d",
                        label,
                        expected_occ,
                        cq_occ,
                        cq_head,
                        cq_tail))
            end
            @(posedge p17d_ctrl_vif.clk);
        end
    end
    endtask

    task automatic p28d_check_basic_cq_record(
        input ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec,
        input logic [31:0] expected_first_tag,
        input logic [31:0] expected_last_tag,
        input string label
    );
    begin
        if (!rec.commit_word[0]) begin
            `uvm_fatal("P28D_MOD/CQ_NOT_COMMITTED",
                $sformatf("%s: CQ record is not committed commit=0x%08h status=0x%08h",
                    label,
                    rec.commit_word,
                    rec.status_flags))
        end

        if (rec.first_user_tag !== expected_first_tag) begin
            `uvm_fatal("P28D_MOD/FIRST_TAG",
                $sformatf("%s: first_user_tag mismatch actual=0x%08h expected=0x%08h",
                    label,
                    rec.first_user_tag,
                    expected_first_tag))
        end

        if (rec.last_user_tag !== expected_last_tag) begin
            `uvm_fatal("P28D_MOD/LAST_TAG",
                $sformatf("%s: last_user_tag mismatch actual=0x%08h expected=0x%08h",
                    label,
                    rec.last_user_tag,
                    expected_last_tag))
        end

        `uvm_info("P28D_MOD/CQ_RECORD_PASS",
            $sformatf("%s: CQ record committed commit=0x%08h status=0x%08h first=0x%08h last=0x%08h",
                label,
                rec.commit_word,
                rec.status_flags,
                rec.first_user_tag,
                rec.last_user_tag),
            UVM_MEDIUM)
    end
    endtask

    task automatic p28d_check_rearm_clean(
        input ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t snap,
        input logic [31:0] ack_mask,
        input string label
    );
    begin
        if ((snap.event_pending & ack_mask) != 32'h0000_0000) begin
            `uvm_fatal("P28D_MOD/REARM_PENDING",
                $sformatf("%s: acked event bits still pending pending=0x%08h ack_mask=0x%08h",
                    label,
                    snap.event_pending,
                    ack_mask))
        end

        if (snap.event_status[ai_accel_csr_access_helper::EVENT_STATUS_EVENT_IRQ_OUT]) begin
            `uvm_fatal("P28D_MOD/REARM_IRQ",
                $sformatf("%s: event IRQ still asserted after batch consume + W1C re-arm status=0x%08h pending=0x%08h",
                    label,
                    snap.event_status,
                    snap.event_pending))
        end

        `uvm_info("P28D_MOD/REARM_PASS",
            $sformatf("%s: event path re-armed cleanly pending=0x%08h status=0x%08h CQ(h/t/occ)=%0d/%0d/%0d",
                label,
                snap.event_pending,
                snap.event_status,
                snap.cq_head,
                snap.cq_tail,
                snap.cq_occupancy),
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
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg_single;
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg_batch;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd0;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd1;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec0;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_cfg_t mod_cfg;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t pre_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t one_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t threshold_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t rearm_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p28_cq_batch_result_t batch_result;

        logic [31:0] completion_event_mask;
        logic [31:0] threshold_required_mask;
        logic [31:0] ack_mask;
        logic [7:0]  threshold_release_count;
        logic [7:0]  threshold_release_cause;
    begin
        phase.raise_objection(this);

        `uvm_info("P28D_MOD/START",
            "Starting P28D CQ threshold interrupt moderation smoke test",
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
            `uvm_fatal("P28D_MOD/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        program_p23d_descriptor_table(
            P28D_DESC_BASE0,
            P28D_DESC0_TAG0,
            P28D_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        program_p23d_descriptor_table(
            P28D_DESC_BASE1,
            P28D_DESC1_TAG0,
            P28D_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p28d_make_cfg(rt, cfg_single, 1'b0);
        p28d_make_cfg(rt, cfg_batch,  1'b1);
        p28d_make_cmd(rt, cmd0, 32'(P28D_DESC_BASE0), P28D_CMD0_TAG);
        p28d_make_cmd(rt, cmd1, 32'(P28D_DESC_BASE1), P28D_CMD1_TAG);

        completion_event_mask = rt.host_rt_event_mod_completion_mask(
            1'b1, // QUEUE_COMMAND_COMPLETED_EVENT
            1'b1, // CQ_NOT_EMPTY_EVENT
            1'b1, // CQ_THRESHOLD_EVENT
            1'b0  // no timer event for P28D
        );

        threshold_required_mask = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_NOT_EMPTY) |
                                  rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_THRESHOLD);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_program_completion_wb();

        // ------------------------------------------------------------
        // Baseline/no-early-IRQ session:
        // One valid command produces one CQ record.  With moderation enabled
        // and threshold=2, completion-style events must not assert IRQ yet.
        // ------------------------------------------------------------
        rt.host_rt_lifecycle_init_session(
            cfg_single,
            completion_event_mask,
            1'b1,
            1'b1,
            "P28D single-command init",
            1'b1 // fresh zero-pointer epoch
        );

        rt.host_rt_event_mod_default_cfg(
            mod_cfg,
            1'b1, // moderation_enable
            1'b1, // cq_threshold_enable
            1'b0, // moderation_timer_enable
            1'b1, // retrigger_on_nonempty
            32'h0000_0002,
            32'h0000_0000,
            completion_event_mask,
            1'b1,
            1'b1
        );
        rt.host_rt_event_mod_program(mod_cfg, "P28D single-command moderation cfg");
        rt.host_rt_event_mod_capture_snapshot(pre_snap);

        rt.write_sq_command(cfg_single, 0, cmd0, 1'b1);
        rt.ring_sq_tail(32'h0000_0001);
        rt.start_queue();

        p28d_wait_cq_occupancy(1, "P28D single-command CQ occupancy");
        rt.host_rt_event_mod_capture_snapshot(one_snap);
        rt.host_rt_event_mod_log_snapshot("P28D single-command post-CQ", one_snap, UVM_MEDIUM);

        rt.host_rt_event_mod_expect_no_irq_delta(pre_snap, one_snap, "P28D no early IRQ before threshold");
        rt.host_rt_event_mod_expect_pending(
            one_snap,
            32'h0000_0000,
            completion_event_mask,
            "P28D no completion-style pending before threshold"
        );

        rt.wait_cq_commit(cfg_single, 0, rec0, done_timeout_cycles * 4);
        p28d_check_basic_cq_record(rec0, P28D_DESC0_TAG0, P28D_DESC0_TAG1, "P28D valid baseline CQ[0]");

        `uvm_info("P28D_MOD/VALID_BASELINE_PASS",
            "P28D valid single-command baseline produced one CQ record with moderation enabled",
            UVM_MEDIUM)

        `uvm_info("P28D_MOD/NO_EARLY_IRQ_PASS",
            $sformatf("P28D no early IRQ before threshold PASS: event_pending=0x%08h irq_count_before=%0d irq_count_after=%0d",
                one_snap.event_pending,
                pre_snap.event_irq_count,
                one_snap.event_irq_count),
            UVM_MEDIUM)

        // Keep this cleanup path pointer-epoch preserving.  The threshold
        // session below is a separate fresh lifecycle session, so
        // host_rt_lifecycle_init_session(..., fresh_pointer_epoch=1) establishes
        // the next zero-counter epoch through the architectural idle-only
        // RESET_QUEUE_POINTERS command.
        rt.host_rt_lifecycle_cleanup_drained(
            cfg_single,
            completion_event_mask,
            1'b0, // preserve here; next fresh init resets pointers architecturally
            1'b1, // consume visible CQ
            1'b1, // recycle SQ/CQ memory
            "P28D single-command cleanup"
        );

        // ------------------------------------------------------------
        // Threshold session:
        // Two valid commands accumulate two CQ records.  The second commit
        // reaches threshold=2 and releases one coalesced notification.
        // ------------------------------------------------------------
        rt.host_rt_lifecycle_init_session(
            cfg_batch,
            completion_event_mask,
            1'b1,
            1'b1,
            "P28D threshold init",
            1'b1 // fresh zero-pointer epoch
        );

        rt.host_rt_event_mod_program(mod_cfg, "P28D threshold moderation cfg");

        rt.write_sq_command(cfg_batch, 0, cmd0, 1'b1);
        rt.write_sq_command(cfg_batch, 1, cmd1, 1'b1);
        rt.ring_sq_tail(32'h0000_0002);
        rt.start_queue();

        rt.host_rt_event_mod_wait_notification(
            threshold_required_mask,
            threshold_snap,
            "P28D wait threshold notification",
            done_timeout_cycles * 8,
            1'b1
        );

        rt.host_rt_event_mod_expect_pending(
            threshold_snap,
            threshold_required_mask,
            32'h0000_0000,
            "P28D threshold pending check"
        );
        // A drained queue can generate an urgent/lifecycle event in the same
        // notification window as the CQ threshold release.  In that case the
        // diagnostic last-release-cause field may legally report URGENT_BYPASS
        // even though the threshold release occurred.  P28D therefore checks
        // the threshold pending bits plus the threshold-release counter rather
        // than requiring the last-release-cause field to be exclusively
        // THRESHOLD.
        threshold_release_count = rt.host_rt_event_mod_debug_threshold_count(threshold_snap.mod_debug);
        threshold_release_cause = rt.host_rt_event_mod_debug_release_cause(threshold_snap.mod_debug);
        if (threshold_release_count == 0) begin
            `uvm_fatal("P28D_MOD/THRESHOLD_RELEASE",
                $sformatf("P28D threshold release counter did not increment: mod_debug=0x%08h release=%s(0x%02h)",
                    threshold_snap.mod_debug,
                    rt.host_rt_event_mod_release_name(threshold_release_cause),
                    threshold_release_cause))
        end
        `uvm_info("P28D_MOD/THRESHOLD_RELEASE_PASS",
            $sformatf("P28D threshold release observed: threshold_count=%0d release=%s(0x%02h) mod_debug=0x%08h",
                threshold_release_count,
                rt.host_rt_event_mod_release_name(threshold_release_cause),
                threshold_release_cause,
                threshold_snap.mod_debug),
            UVM_MEDIUM)

        rt.host_rt_event_mod_expect_cq_occupancy(
            threshold_snap,
            2,
            2,
            "P28D threshold CQ occupancy"
        );

        `uvm_info("P28D_MOD/THRESHOLD_IRQ_PASS",
            $sformatf("P28D threshold IRQ PASS: pending=0x%08h status=0x%08h mod_status=0x%08h mod_debug=0x%08h",
                threshold_snap.event_pending,
                threshold_snap.event_status,
                threshold_snap.mod_status,
                threshold_snap.mod_debug),
            UVM_MEDIUM)

        rt.host_rt_event_mod_consume_cq_batch(
            cfg_batch,
            threshold_snap,
            0,
            batch_result,
            2,
            1'b1,
            "P28D threshold batch consume",
            done_timeout_cycles * 4
        );

        if (batch_result.first_user_tag !== P28D_DESC0_TAG0) begin
            `uvm_fatal("P28D_MOD/BATCH_FIRST_TAG",
                $sformatf("First batch CQ first_user_tag mismatch actual=0x%08h expected=0x%08h",
                    batch_result.first_user_tag,
                    P28D_DESC0_TAG0))
        end
        if (batch_result.last_user_tag !== P28D_DESC1_TAG1) begin
            `uvm_fatal("P28D_MOD/BATCH_LAST_TAG",
                $sformatf("Last batch CQ last_user_tag mismatch actual=0x%08h expected=0x%08h",
                    batch_result.last_user_tag,
                    P28D_DESC1_TAG1))
        end

        `uvm_info("P28D_MOD/BATCH_CONSUME_PASS",
            $sformatf("P28D batch consume PASS: consumed=%0d CQ_HEAD %0d->%0d first_tag=0x%08h last_tag=0x%08h",
                batch_result.consumed_count,
                batch_result.start_cq_head,
                batch_result.final_cq_head,
                batch_result.first_user_tag,
                batch_result.last_user_tag),
            UVM_MEDIUM)

        ack_mask = threshold_snap.event_pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.host_rt_event_mod_ack_and_rearm(
            ack_mask,
            completion_event_mask,
            32'h0000_0002,
            1'b1,
            1'b1,
            "P28D threshold ack/rearm"
        );
        rt.host_rt_event_mod_capture_snapshot(rearm_snap);
        rt.host_rt_event_mod_log_snapshot("P28D post-rearm", rearm_snap, UVM_MEDIUM);
        p28d_check_rearm_clean(rearm_snap, ack_mask, "P28D post-batch rearm clean");

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P28D_MOD/PASS",
            $sformatf("P28D CQ threshold interrupt moderation PASS: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d threshold=2 batch_consumed=%0d ack_mask=0x%08h",
                selected_case_id,
                a_flat.size(),
                b_flat.size(),
                c_elems,
                batch_result.consumed_count,
                ack_mask),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
