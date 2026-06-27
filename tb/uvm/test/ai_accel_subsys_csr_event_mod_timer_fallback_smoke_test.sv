// File: tb/uvm/test/ai_accel_subsys_csr_event_mod_timer_fallback_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_EVENT_MOD_TIMER_FALLBACK_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_EVENT_MOD_TIMER_FALLBACK_SMOKE_TEST_SV

// ============================================================
// P28E moderation timer fallback smoke
//
// Scope:
//   - Reuses the validated P23 event-driven SQ/CQ host runtime path.
//   - Enables the P28 event moderation CSR policy with CQ threshold above
//     the sparse workload CQ occupancy and moderation timer enabled.
//   - Proves a sparse single-command completion can remain pending without
//     threshold notification, then is released by the moderation timer.
//   - Host consumes the visible CQ record through the P28 batch-CQ helper,
//     publishes one CQ_HEAD update, W1C-acks the event, and re-arms the
//     event path.
//
// P28E does not change SQ/CQ entry format, descriptor format, completion
// record format, BRAM, GEMM, DMA, AXI-Stream, or Direct Stream datapath
// behavior.
// ============================================================

class ai_accel_subsys_csr_event_mod_timer_fallback_smoke_test
    extends ai_accel_subsys_csr_event_driven_multi_command_queue_drain_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_event_mod_timer_fallback_smoke_test)

    localparam int unsigned P28E_SQ_BASE       = 32'h0000_0700;
    localparam int unsigned P28E_CQ_BASE       = 32'h0000_0800;
    localparam int unsigned P28E_QUEUE_DEPTH   = 4;

    localparam int unsigned P28E_DESC_BASE0    = 32'h0000_0300;
    localparam int unsigned P28E_DESC_STRIDE   = 32'h0000_0080;

    localparam logic [31:0] P28E_CMD0_TAG      = 32'hD28E_0000;
    localparam logic [31:0] P28E_DESC0_TAG0    = 32'hD28E_1000;
    localparam logic [31:0] P28E_DESC0_TAG1    = 32'hD28E_1001;

    localparam logic [31:0] P28E_CQ_THRESHOLD  = 32'h0000_0003;
    localparam logic [31:0] P28E_TIMER_LIMIT   = 32'h0000_0200;

    function new(string name = "ai_accel_subsys_csr_event_mod_timer_fallback_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p28e_make_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg
    );
    begin
        rt.make_default_queue_cfg(
            cfg,
            32'(P28E_SQ_BASE),
            32'(P28E_CQ_BASE),
            32'(P28E_QUEUE_DEPTH),
            1'b0
        );
    end
    endtask

    task automatic p28e_make_cmd(
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
            32'(P28E_DESC_STRIDE),
            user_tag,
            1'b1,
            1'b0
        );
        cmd.timeout_cycles = 32'h0000_0000;
    end
    endtask

    task automatic p28e_wait_cq_occupancy(
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
                `uvm_info("P28E_MOD/CQ_OCC_PASS",
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
                `uvm_fatal("P28E_MOD/CQ_OCC_TIMEOUT",
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

    task automatic p28e_check_basic_cq_record(
        input ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec,
        input logic [31:0] expected_first_tag,
        input logic [31:0] expected_last_tag,
        input string label
    );
    begin
        if (!rec.commit_word[0]) begin
            `uvm_fatal("P28E_MOD/CQ_NOT_COMMITTED",
                $sformatf("%s: CQ record is not committed commit=0x%08h status=0x%08h",
                    label,
                    rec.commit_word,
                    rec.status_flags))
        end

        if (rec.first_user_tag !== expected_first_tag) begin
            `uvm_fatal("P28E_MOD/FIRST_TAG",
                $sformatf("%s: first_user_tag mismatch actual=0x%08h expected=0x%08h",
                    label,
                    rec.first_user_tag,
                    expected_first_tag))
        end

        if (rec.last_user_tag !== expected_last_tag) begin
            `uvm_fatal("P28E_MOD/LAST_TAG",
                $sformatf("%s: last_user_tag mismatch actual=0x%08h expected=0x%08h",
                    label,
                    rec.last_user_tag,
                    expected_last_tag))
        end

        `uvm_info("P28E_MOD/CQ_RECORD_PASS",
            $sformatf("%s: CQ record committed commit=0x%08h status=0x%08h first=0x%08h last=0x%08h",
                label,
                rec.commit_word,
                rec.status_flags,
                rec.first_user_tag,
                rec.last_user_tag),
            UVM_MEDIUM)
    end
    endtask

    task automatic p28e_check_rearm_clean(
        input ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t snap,
        input logic [31:0] ack_mask,
        input string label
    );
    begin
        if ((snap.event_pending & ack_mask) != 32'h0000_0000) begin
            `uvm_fatal("P28E_MOD/REARM_PENDING",
                $sformatf("%s: acked event bits still pending pending=0x%08h ack_mask=0x%08h",
                    label,
                    snap.event_pending,
                    ack_mask))
        end

        if (snap.event_status[ai_accel_csr_access_helper::EVENT_STATUS_EVENT_IRQ_OUT]) begin
            `uvm_fatal("P28E_MOD/REARM_IRQ",
                $sformatf("%s: event IRQ still asserted after timer consume + W1C re-arm status=0x%08h pending=0x%08h",
                    label,
                    snap.event_status,
                    snap.event_pending))
        end

        `uvm_info("P28E_MOD/REARM_PASS",
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
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg_timer;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd0;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec0;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_cfg_t mod_cfg;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t pre_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t one_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t timer_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t rearm_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p28_cq_batch_result_t batch_result;

        logic [31:0] completion_event_mask;
        logic [31:0] timer_required_mask;
        logic [31:0] threshold_forbidden_mask;
        logic [31:0] ack_mask;
        logic [7:0]  timer_release_count;
        logic [7:0]  threshold_release_count;
    begin
        phase.raise_objection(this);

        `uvm_info("P28E_MOD/START",
            "Starting P28E moderation timer fallback smoke test",
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
            `uvm_fatal("P28E_MOD/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        program_p23d_descriptor_table(
            P28E_DESC_BASE0,
            P28E_DESC0_TAG0,
            P28E_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p28e_make_cfg(rt, cfg_timer);
        p28e_make_cmd(rt, cmd0, 32'(P28E_DESC_BASE0), P28E_CMD0_TAG);

        completion_event_mask = rt.host_rt_event_mod_completion_mask(
            1'b1, // QUEUE_COMMAND_COMPLETED_EVENT
            1'b1, // CQ_NOT_EMPTY_EVENT
            1'b1, // CQ_THRESHOLD_EVENT, enabled but not expected in P28E
            1'b1  // CQ_MODERATION_TIMER_EVENT
        );

        timer_required_mask = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_NOT_EMPTY) |
                              rt.event_bit(ai_accel_csr_access_helper::P28_EVENT_CQ_MOD_TIMER);
        threshold_forbidden_mask = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_THRESHOLD);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_program_completion_wb();

        // ------------------------------------------------------------
        // Sparse timer session:
        // One valid command produces one CQ record.  CQ threshold is higher
        // than the sparse occupancy, so no threshold release should occur.
        // The moderation timer bounds notification latency and releases the
        // coalesced CQ notification.
        // ------------------------------------------------------------
        rt.host_rt_lifecycle_init_session(
            cfg_timer,
            completion_event_mask,
            1'b1,
            1'b1,
            "P28E timer init"
        );

        rt.host_rt_event_mod_default_cfg(
            mod_cfg,
            1'b1, // moderation_enable
            1'b1, // cq_threshold_enable
            1'b1, // moderation_timer_enable
            1'b1, // retrigger_on_nonempty
            P28E_CQ_THRESHOLD,
            P28E_TIMER_LIMIT,
            completion_event_mask,
            1'b1,
            1'b1
        );
        rt.host_rt_event_mod_program(mod_cfg, "P28E timer moderation cfg");
        rt.host_rt_event_mod_capture_snapshot(pre_snap);

        rt.write_sq_command(cfg_timer, 0, cmd0, 1'b1);
        rt.ring_sq_tail(32'h0000_0001);
        rt.start_queue();

        p28e_wait_cq_occupancy(1, "P28E sparse CQ occupancy");
        rt.host_rt_event_mod_capture_snapshot(one_snap);
        rt.host_rt_event_mod_log_snapshot("P28E sparse post-CQ pre-timer", one_snap, UVM_MEDIUM);

        rt.host_rt_event_mod_expect_no_irq_delta(pre_snap, one_snap, "P28E no early IRQ before timer");
        rt.host_rt_event_mod_expect_pending(
            one_snap,
            32'h0000_0000,
            completion_event_mask,
            "P28E no completion-style pending before timer"
        );

        rt.wait_cq_commit(cfg_timer, 0, rec0, done_timeout_cycles * 4);
        p28e_check_basic_cq_record(rec0, P28E_DESC0_TAG0, P28E_DESC0_TAG1, "P28E valid baseline CQ[0]");

        `uvm_info("P28E_MOD/BASELINE_PASS",
            $sformatf("P28E valid sparse baseline produced one CQ record with threshold=%0d timer_limit=%0d",
                P28E_CQ_THRESHOLD,
                P28E_TIMER_LIMIT),
            UVM_MEDIUM)

        rt.host_rt_event_mod_wait_notification(
            timer_required_mask,
            timer_snap,
            "P28E wait timer fallback notification",
            done_timeout_cycles * 8,
            1'b1
        );

        rt.host_rt_event_mod_expect_pending(
            timer_snap,
            timer_required_mask,
            threshold_forbidden_mask,
            "P28E timer pending check"
        );

        threshold_release_count = rt.host_rt_event_mod_debug_threshold_count(timer_snap.mod_debug);
        timer_release_count     = rt.host_rt_event_mod_debug_timer_count(timer_snap.mod_debug);

        if (threshold_release_count != 0) begin
            `uvm_fatal("P28E_MOD/UNEXPECTED_THRESHOLD",
                $sformatf("P28E threshold release occurred in timer fallback test: threshold_count=%0d mod_debug=0x%08h",
                    threshold_release_count,
                    timer_snap.mod_debug))
        end

        `uvm_info("P28E_MOD/NO_THRESHOLD_PASS",
            $sformatf("P28E no-threshold PASS: cq_occ=%0d threshold=%0d threshold_count=%0d pending=0x%08h",
                timer_snap.cq_occupancy,
                P28E_CQ_THRESHOLD,
                threshold_release_count,
                timer_snap.event_pending),
            UVM_MEDIUM)

        if (timer_release_count == 0) begin
            `uvm_fatal("P28E_MOD/TIMER_RELEASE",
                $sformatf("P28E timer release counter did not increment: mod_debug=0x%08h mod_status=0x%08h",
                    timer_snap.mod_debug,
                    timer_snap.mod_status))
        end

        rt.host_rt_event_mod_expect_release_cause(
            timer_snap,
            ai_accel_csr_access_helper::P28_MOD_RELEASE_TIMER,
            "P28E timer release cause"
        );

        rt.host_rt_event_mod_expect_cq_occupancy(
            timer_snap,
            1,
            1,
            "P28E timer CQ occupancy"
        );

        `uvm_info("P28E_MOD/TIMER_IRQ_PASS",
            $sformatf("P28E timer fallback IRQ PASS: pending=0x%08h status=0x%08h mod_status=0x%08h mod_debug=0x%08h timer_count=%0d",
                timer_snap.event_pending,
                timer_snap.event_status,
                timer_snap.mod_status,
                timer_snap.mod_debug,
                timer_release_count),
            UVM_MEDIUM)

        rt.host_rt_event_mod_consume_cq_batch(
            cfg_timer,
            timer_snap,
            0,
            batch_result,
            1,
            1'b1,
            "P28E timer batch consume",
            done_timeout_cycles * 4
        );

        if (batch_result.first_user_tag !== P28E_DESC0_TAG0) begin
            `uvm_fatal("P28E_MOD/BATCH_FIRST_TAG",
                $sformatf("Timer batch CQ first_user_tag mismatch actual=0x%08h expected=0x%08h",
                    batch_result.first_user_tag,
                    P28E_DESC0_TAG0))
        end
        if (batch_result.last_user_tag !== P28E_DESC0_TAG1) begin
            `uvm_fatal("P28E_MOD/BATCH_LAST_TAG",
                $sformatf("Timer batch CQ last_user_tag mismatch actual=0x%08h expected=0x%08h",
                    batch_result.last_user_tag,
                    P28E_DESC0_TAG1))
        end

        `uvm_info("P28E_MOD/BATCH_CONSUME_PASS",
            $sformatf("P28E timer batch consume PASS: consumed=%0d CQ_HEAD %0d->%0d first_tag=0x%08h last_tag=0x%08h",
                batch_result.consumed_count,
                batch_result.start_cq_head,
                batch_result.final_cq_head,
                batch_result.first_user_tag,
                batch_result.last_user_tag),
            UVM_MEDIUM)

        ack_mask = timer_snap.event_pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.host_rt_event_mod_ack_and_rearm(
            ack_mask,
            completion_event_mask,
            P28E_CQ_THRESHOLD,
            1'b1,
            1'b1,
            "P28E timer ack/rearm"
        );
        rt.host_rt_event_mod_capture_snapshot(rearm_snap);
        rt.host_rt_event_mod_log_snapshot("P28E post-rearm", rearm_snap, UVM_MEDIUM);
        p28e_check_rearm_clean(rearm_snap, ack_mask, "P28E post-timer rearm clean");

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P28E_MOD/PASS",
            $sformatf("P28E moderation timer fallback PASS: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d threshold=%0d timer_limit=%0d consumed=%0d ack_mask=0x%08h",
                selected_case_id,
                a_flat.size(),
                b_flat.size(),
                c_elems,
                P28E_CQ_THRESHOLD,
                P28E_TIMER_LIMIT,
                batch_result.consumed_count,
                ack_mask),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
