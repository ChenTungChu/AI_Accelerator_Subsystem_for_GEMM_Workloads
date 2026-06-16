// File: tb/uvm/test/ai_accel_subsys_csr_queue_lifecycle_stopped_preserve_restart_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_LIFECYCLE_STOPPED_PRESERVE_RESTART_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_LIFECYCLE_STOPPED_PRESERVE_RESTART_SMOKE_TEST_SV

// ============================================================
// P26E queue lifecycle STOP_QUEUE stopped-session preserve/restart smoke
//
// Scope:
//   - Reuses the P26C lifecycle helper extension and the P26D
//     pointer-preserving lifecycle cleanup model.
//   - Starts a live queue session with SQ[0].
//   - Runtime-appends SQ[1] while SQ[0] is active.
//   - Issues STOP_QUEUE while the active command is still in flight.
//   - Verifies SQ[0] completes and CQ[0] commits normally.
//   - Verifies SQ[1] is not consumed automatically in the stopped
//     session and remains pending as SQ_HEAD=1, SQ_TAIL=2.
//   - Uses stopped-session work-preserving lifecycle cleanup to consume
//     CQ[0], clear/re-arm events, clear queue sticky done state, and
//     preserve the pending SQ[1] entry.
//   - Restarts the queue and verifies the pending SQ[1] command
//     completes into CQ[1].
//
// This is UVM/helper-only validation.  It does not add RTL, CSR map
// changes, SQ/CQ format changes, descriptor-format changes, completion
// record changes, event bits, standalone tops, or datapath changes.
// ============================================================

class ai_accel_subsys_csr_queue_lifecycle_stopped_preserve_restart_smoke_test
    extends ai_accel_subsys_csr_queue_lifecycle_drained_reinit_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_lifecycle_stopped_preserve_restart_smoke_test)

    localparam int unsigned P26E_SQ_BASE     = 32'h0000_0D00;
    localparam int unsigned P26E_CQ_BASE     = 32'h0000_0E00;
    localparam int unsigned P26E_QUEUE_DEPTH = 4;

    localparam int unsigned P26E_DESC_BASE0  = 32'h0000_0300;
    localparam int unsigned P26E_DESC_BASE1  = 32'h0000_0400;
    localparam int unsigned P26E_DESC_STRIDE = 32'h0000_0080;

    localparam logic [31:0] P26E_CMD0_TAG    = 32'hD26E_0000;
    localparam logic [31:0] P26E_CMD1_TAG    = 32'hD26E_0001;

    localparam logic [31:0] P26E_DESC0_TAG0  = 32'hD26E_1000;
    localparam logic [31:0] P26E_DESC0_TAG1  = 32'hD26E_1001;
    localparam logic [31:0] P26E_DESC1_TAG0  = 32'hD26E_2000;
    localparam logic [31:0] P26E_DESC1_TAG1  = 32'hD26E_2001;

    localparam int unsigned P26E_QUEUE_DONE_DRAINED_BIT = 1;
    localparam int unsigned P26E_QUEUE_DONE_STOPPED_BIT = 3;

    function new(string name = "ai_accel_subsys_csr_queue_lifecycle_stopped_preserve_restart_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function automatic bit p26e_queue_service_active(input logic [31:0] status);
    begin
        // Match the P25D live-service interpretation: during handoff
        // windows, lower queue-service sub-engine busy bits are enough to
        // prove that the queue is active for a runtime append / STOP_QUEUE
        // interaction even if QUEUE_BUSY itself is briefly low.
        p26e_queue_service_active = status[0]  ||  // QUEUE_BUSY
                                    status[8]  ||  // CMD_FETCH_BUSY
                                    status[9]  ||  // DESC_FETCH_BUSY
                                    status[10] ||  // RECIPE_BUSY
                                    status[11] ||  // COMP_BUSY
                                    status[12];    // UNDERLYING_BUSY
    end
    endfunction

    task automatic p26e_make_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg
    );
    begin
        rt.make_default_queue_cfg(
            cfg,
            32'(P26E_SQ_BASE),
            32'(P26E_CQ_BASE),
            32'(P26E_QUEUE_DEPTH),
            1'b1  // RUN_UNTIL_EMPTY so restart of pending SQ[1] can drain.
        );
    end
    endtask

    task automatic p26e_make_cmd(
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
            32'(P26E_DESC_STRIDE),
            user_tag,
            1'b1,
            1'b0
        );

        // P26E validates STOP_QUEUE lifecycle behavior.  Timeout/error
        // discard remains reserved for P26F.
        cmd.timeout_cycles = 32'h0000_0000;
    end
    endtask

    task automatic p26e_wait_queue_active_before_append(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] sq_head;
        logic [31:0] sq_tail;
        logic [31:0] cq_tail;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS,        status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS,   done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,  error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,       sq_head);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,       sq_tail);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,       cq_tail);

            if ((error_status != 32'h0000_0000) ||
                (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P26E_LIFECYCLE/ERROR_BEFORE_STOP_APPEND",
                    $sformatf("Queue failed before runtime append/STOP: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h SQ_HEAD=0x%08h SQ_TAIL=0x%08h CQ_TAIL=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        sq_tail,
                        cq_tail))
            end

            if (p26e_queue_service_active(status) &&
                (sq_head == 32'h0000_0000) &&
                (sq_tail == 32'h0000_0001) &&
                (cq_tail == 32'h0000_0000)) begin
                `uvm_info("P26E_LIFECYCLE/ACTIVE",
                    $sformatf("Queue service active before STOP preserve append PASS: status=0x%08h done=0x%08h SQ_HEAD=0x%08h SQ_TAIL=0x%08h CQ_TAIL=0x%08h",
                        status,
                        done_status,
                        sq_head,
                        sq_tail,
                        cq_tail),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P26E_LIFECYCLE/ACTIVE_TIMEOUT",
                    $sformatf("Timeout waiting for queue active before STOP preserve append: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h SQ_HEAD=0x%08h SQ_TAIL=0x%08h CQ_TAIL=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        sq_tail,
                        cq_tail))
            end
        end
    end
    endtask

    task automatic p26e_append_sq1_while_active(
        input ai_accel_event_driven_host_runtime_stress_helper rt,
        input ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd1
    );
        logic [31:0] status_before;
        logic [31:0] sq_head_after;
        logic [31:0] sq_tail_after;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status_before);
        if (!p26e_queue_service_active(status_before)) begin
            `uvm_fatal("P26E_LIFECYCLE/NOT_ACTIVE_AT_APPEND",
                $sformatf("Expected queue service activity before runtime append, status=0x%08h",
                    status_before))
        end

        rt.write_sq_command(cfg, 1, cmd1, 1'b1);
        rt.ring_sq_tail(32'h0000_0002);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head_after);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL, sq_tail_after);

        if (sq_tail_after !== 32'h0000_0002) begin
            `uvm_fatal("P26E_LIFECYCLE/SQ_TAIL_APPEND_FAIL",
                $sformatf("Expected SQ_TAIL=2 after runtime append, got 0x%08h",
                    sq_tail_after))
        end

        if (sq_head_after !== 32'h0000_0000) begin
            `uvm_fatal("P26E_LIFECYCLE/SQ_HEAD_ADVANCED_TOO_EARLY",
                $sformatf("Expected SQ_HEAD to remain 0 immediately after runtime append, got 0x%08h",
                    sq_head_after))
        end

        `uvm_info("P26E_LIFECYCLE/APPEND_PASS",
            $sformatf("Runtime append PASS: wrote SQ[1], published SQ_TAIL 1->2 while queue active, status_before=0x%08h",
                status_before),
            UVM_MEDIUM)
    end
    endtask

    task automatic p26e_require_cq_not_committed(
        input ai_accel_event_driven_host_runtime_stress_helper rt,
        input ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input int unsigned entry_index,
        input string label
    );
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec;
    begin
        rt.read_cq_record(cfg, entry_index, rec);
        if (rec.commit_word[0]) begin
            `uvm_fatal("P26E_LIFECYCLE/PENDING_CQ_COMMITTED",
                $sformatf("%s: expected CQ[%0d] to remain uncommitted before restart, got commit=0x%08h status=0x%08h tag=0x%08h",
                    label,
                    entry_index,
                    rec.commit_word,
                    rec.status_flags,
                    rec.first_user_tag))
        end

        `uvm_info("P26E_LIFECYCLE/PENDING_CQ_CLEAN",
            $sformatf("%s: CQ[%0d] is still uncommitted before restart, proving pending SQ work was not auto-consumed",
                label,
                entry_index),
            UVM_MEDIUM)
    end
    endtask

    task automatic p26e_require_stopped_terminal_state(
        input ai_accel_event_driven_host_runtime_stress_helper rt,
        input ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t snap,
        input string label
    );
    begin
        if (!snap.queue_done_status[P26E_QUEUE_DONE_STOPPED_BIT]) begin
            `uvm_fatal("P26E_LIFECYCLE/STOPPED_MISSING",
                $sformatf("%s: expected STOPPED_AFTER_COMMAND sticky before cleanup, done=0x%08h status=0x%08h",
                    label,
                    snap.queue_done_status,
                    snap.queue_status))
        end

        if (snap.queue_done_status[P26E_QUEUE_DONE_DRAINED_BIT]) begin
            `uvm_fatal("P26E_LIFECYCLE/DRAINED_UNEXPECTED",
                $sformatf("%s: queue reported drained even though SQ[1] should remain pending, done=0x%08h SQ_HEAD=%0d SQ_TAIL=%0d",
                    label,
                    snap.queue_done_status,
                    snap.sq_head,
                    snap.sq_tail))
        end

        if ((snap.sq_head !== 32'h0000_0001) ||
            (snap.sq_tail !== 32'h0000_0002) ||
            (snap.cq_head !== 32'h0000_0000) ||
            (snap.cq_tail !== 32'h0000_0001) ||
            (snap.cq_occupancy !== 32'h0000_0001)) begin
            `uvm_fatal("P26E_LIFECYCLE/STOPPED_POINTERS",
                $sformatf("%s: expected stopped epoch SQ(h/t)=1/2 CQ(h/t/occ)=0/1/1, got SQ(h/t)=%0d/%0d CQ(h/t/occ)=%0d/%0d/%0d status=0x%08h done=0x%08h",
                    label,
                    snap.sq_head,
                    snap.sq_tail,
                    snap.cq_head,
                    snap.cq_tail,
                    snap.cq_occupancy,
                    snap.queue_status,
                    snap.queue_done_status))
        end

        `uvm_info("P26E_LIFECYCLE/STOPPED_OBSERVED",
            $sformatf("%s: stopped terminal state observed with pending SQ preserved SQ_HEAD=%0d SQ_TAIL=%0d CQ_HEAD=%0d CQ_TAIL=%0d pending=0x%08h done=0x%08h",
                label,
                snap.sq_head,
                snap.sq_tail,
                snap.cq_head,
                snap.cq_tail,
                snap.event_snap.pending,
                snap.queue_done_status),
            UVM_MEDIUM)
    end
    endtask

    task automatic p26e_require_preserved_pending_epoch(
        input ai_accel_event_driven_host_runtime_stress_helper rt,
        input string label
    );
        ai_accel_event_driven_host_runtime_stress_helper::p26_lifecycle_snapshot_t snap;
    begin
        rt.host_rt_lifecycle_capture_snapshot(snap, label, 1'b1);

        if ((snap.sq_head !== 32'h0000_0001) ||
            (snap.sq_tail !== 32'h0000_0002) ||
            (snap.sq_occupancy !== 32'h0000_0001) ||
            (snap.cq_head !== 32'h0000_0001) ||
            (snap.cq_tail !== 32'h0000_0001) ||
            (snap.cq_occupancy !== 32'h0000_0000)) begin
            `uvm_fatal("P26E_LIFECYCLE/PRESERVE_POINTERS",
                $sformatf("%s: expected work-preserving cleanup to keep SQ pending epoch SQ(h/t/occ)=1/2/1 CQ(h/t/occ)=1/1/0, got SQ=%0d/%0d/%0d CQ=%0d/%0d/%0d",
                    label,
                    snap.sq_head,
                    snap.sq_tail,
                    snap.sq_occupancy,
                    snap.cq_head,
                    snap.cq_tail,
                    snap.cq_occupancy))
        end

        if (snap.event_pending != 32'h0000_0000) begin
            `uvm_fatal("P26E_LIFECYCLE/PRESERVE_EVENT_DIRTY",
                $sformatf("%s: expected events clean after stopped-preserve cleanup, pending=0x%08h status=0x%08h",
                    label,
                    snap.event_pending,
                    snap.event_status))
        end

        `uvm_info("P26E_LIFECYCLE/PRESERVE_PASS",
            $sformatf("%s: stopped-session preserve cleanup PASS; SQ[1] remains pending and CQ[0] has been consumed",
                label),
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
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec0;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec1;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t stopped_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t restart_snap;
        logic [31:0] completion_mask;
        logic [31:0] stopped_mask;
        logic [31:0] drained_mask;
        logic [31:0] runtime_mask;
        logic [31:0] stopped_required_mask;
        logic [31:0] restart_required_mask;
        logic [31:0] event_enable_mask;
    begin
        phase.raise_objection(this);

        `uvm_info("P26E_LIFECYCLE/START",
            "Starting P26E STOP_QUEUE stopped-session preserve/restart lifecycle smoke test",
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
            `uvm_fatal("P26E_LIFECYCLE/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        p25c_program_descriptor_table(
            P26E_DESC_BASE0,
            P26E_DESC0_TAG0,
            P26E_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p25c_program_descriptor_table(
            P26E_DESC_BASE1,
            P26E_DESC1_TAG0,
            P26E_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p26e_make_cfg(rt, cfg);
        p26e_make_cmd(rt, cmd0, 32'(P26E_DESC_BASE0), P26E_CMD0_TAG);
        p26e_make_cmd(rt, cmd1, 32'(P26E_DESC_BASE1), P26E_CMD1_TAG);

        completion_mask       = rt.queue_completion_event_mask();
        stopped_mask          = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_STOPPED);
        drained_mask          = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);
        runtime_mask          = rt.runtime_event_mask();
        stopped_required_mask = completion_mask | stopped_mask;
        restart_required_mask = completion_mask | drained_mask;
        event_enable_mask     = completion_mask | stopped_mask | drained_mask | runtime_mask;

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
            "P26E initial lifecycle init"
        );

        csr_check_recipe_idle_ready("P26E before initial START_QUEUE");

        rt.submit_command_and_doorbell(cfg, 0, cmd0, 32'h0000_0001);
        rt.start_queue();

        p26e_wait_queue_active_before_append(done_timeout_cycles * 4);
        rt.deterministic_gap(5, "P26E gap before runtime append and STOP_QUEUE");
        p26e_append_sq1_while_active(rt, cfg, cmd1);
        rt.deterministic_gap(3, "P26E gap between runtime append and STOP_QUEUE");
        rt.stop_queue();

        rt.wait_for_progress_event(
            stopped_required_mask,
            stopped_snap,
            "P26E stopped terminal event wait",
            done_timeout_cycles * 12,
            1'b1
        );
        p25c_check_event_snapshot("P26E stopped terminal event", stopped_snap, stopped_required_mask);
        p26e_require_stopped_terminal_state(rt, stopped_snap, "P26E stopped terminal before lifecycle cleanup");

        rt.wait_and_check_cq_record(
            cfg,
            0,
            P26E_DESC0_TAG0,
            P26E_DESC0_TAG1,
            rec0,
            "P26E CQ[0] before stopped-preserve cleanup",
            done_timeout_cycles * 4
        );
        check_p23d_cq_record(0, rec0, profile_item, P26E_DESC0_TAG0, P26E_DESC0_TAG1);

        p26e_require_cq_not_committed(
            rt,
            cfg,
            1,
            "P26E pending SQ[1] CQ slot before restart"
        );

        rt.host_rt_lifecycle_cleanup_stopped_preserve(
            cfg,
            event_enable_mask,
            1'b1,
            "P26E stopped preserve cleanup"
        );
        p26e_require_preserved_pending_epoch(rt, "P26E stopped preserve post-clean epoch");

        rt.deterministic_gap(11, "P26E gap after stopped-preserve cleanup before restart");
        csr_check_recipe_idle_ready("P26E before restart of pending SQ[1]");
        rt.start_queue();

        rt.wait_for_progress_event(
            restart_required_mask,
            restart_snap,
            "P26E restart pending SQ[1] event wait",
            done_timeout_cycles * 12,
            1'b1
        );
        p25c_check_event_snapshot("P26E restart pending SQ[1] event", restart_snap, restart_required_mask);

        if (!restart_snap.queue_done_status[P26E_QUEUE_DONE_DRAINED_BIT]) begin
            `uvm_fatal("P26E_LIFECYCLE/RESTART_DRAINED_MISSING",
                $sformatf("P26E restart expected QUEUE_DRAINED sticky, done=0x%08h status=0x%08h",
                    restart_snap.queue_done_status,
                    restart_snap.queue_status))
        end

        rt.wait_and_check_cq_record(
            cfg,
            1,
            P26E_DESC1_TAG0,
            P26E_DESC1_TAG1,
            rec1,
            "P26E CQ[1] after restart of preserved pending SQ[1]",
            done_timeout_cycles * 4
        );
        check_p23d_cq_record(1, rec1, profile_item, P26E_DESC1_TAG0, P26E_DESC1_TAG1);

        rt.require_queue_pointers("P26E restart pointers before final lifecycle cleanup",
            32'h0000_0002,
            32'h0000_0001,
            32'h0000_0002,
            32'h0000_0001);

        `uvm_info("P26E_LIFECYCLE/RESTART_PASS",
            "P26E restart PASS: preserved SQ[1] completed after stopped-session cleanup and explicit START_QUEUE",
            UVM_MEDIUM)

        p26d_cleanup_drained_and_require_clean(
            rt,
            cfg,
            event_enable_mask,
            "P26E final drained cleanup after preserved restart"
        );

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        rt.host_rt_lifecycle_check_clean_idle(
            "P26E final clean idle state",
            1'b0,
            1'b1,
            1'b0
        );

        `uvm_info("P26E_LIFECYCLE/PASS",
            $sformatf("P26E STOP_QUEUE stopped-session preserve/restart PASS: CASE_ID=%0d commands=2 A_bytes=%0d B_bytes=%0d C_words=%0d",
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
