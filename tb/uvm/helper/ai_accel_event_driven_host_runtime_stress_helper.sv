// File: tb/uvm/helper/ai_accel_event_driven_host_runtime_stress_helper.sv
`ifndef AI_ACCEL_EVENT_DRIVEN_HOST_RUNTIME_STRESS_HELPER_SV
`define AI_ACCEL_EVENT_DRIVEN_HOST_RUNTIME_STRESS_HELPER_SV

// ============================================================
// P25B event-driven host runtime stress helper extension
//
// Scope:
//   - TB/UVM helper only.
//   - Extends the existing P23 event-driven host runtime helper.
//   - Adds reusable stress-oriented snapshot, cleanup, re-arm,
//     CQ-consume, and queue-reusable checks for P25C/P25D/P25E.
//   - Does not change RTL, CSR map, SQ/CQ formats, event bits,
//     descriptor format, completion record format, or sim flow.
// ============================================================

class ai_accel_event_driven_host_runtime_stress_helper
    extends ai_accel_event_driven_host_runtime_helper;

    `uvm_object_utils(ai_accel_event_driven_host_runtime_stress_helper)

    localparam int unsigned P25_DEFAULT_STRESS_TIMEOUT_CYCLES = 300000;
    localparam int unsigned P25_DEFAULT_REUSABLE_TIMEOUT_CYCLES = 200000;

    typedef struct {
        logic [31:0] queue_status;
        logic [31:0] queue_done_status;
        logic [31:0] queue_error_status;
        logic [31:0] queue_reject_status;
        logic [31:0] queue_state;
        logic [31:0] sq_head;
        logic [31:0] sq_tail;
        logic [31:0] cq_head;
        logic [31:0] cq_tail;
        logic [31:0] sq_occupancy;
        logic [31:0] cq_occupancy;
        logic [31:0] cq_space;
        logic [31:0] current_index;
        logic [31:0] error_index;
        logic [31:0] error_detail;
        logic [31:0] last_cmd_tag;
        logic [31:0] last_cmd_control;
        p23_event_snapshot_t event_snap;
    } p25_runtime_snapshot_t;

    function new(string name = "ai_accel_event_driven_host_runtime_stress_helper");
        super.new(name);
    endfunction

    // ------------------------------------------------------------
    // Stress mask helpers
    // ------------------------------------------------------------
    function automatic logic [31:0] queue_error_event_mask();
        return event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_ERROR);
    endfunction

    function automatic logic [31:0] queue_progress_event_mask();
        return queue_completion_event_mask() |
               event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED) |
               event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_STOPPED);
    endfunction

    function automatic logic [31:0] all_runtime_queue_event_mask();
        return queue_completion_event_mask() |
               queue_terminal_event_mask()   |
               runtime_event_mask()          |
               event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_FULL_STALL) |
               event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_SPACE_RECOVERED);
    endfunction

    function automatic bit queue_has_error(input p25_runtime_snapshot_t snap);
        return (snap.queue_error_status != 32'h0000_0000) ||
               (snap.queue_reject_status != 32'h0000_0000) ||
               (snap.queue_status[2] == 1'b1);
    endfunction

    function automatic bit queue_is_busy(input p25_runtime_snapshot_t snap);
        return snap.queue_status[0];
    endfunction

    function automatic bit event_irq_asserted(input p23_event_snapshot_t snap);
        return snap.status[2];
    endfunction

    // ------------------------------------------------------------
    // Runtime snapshot helpers
    // ------------------------------------------------------------
    task automatic read_runtime_snapshot(output p25_runtime_snapshot_t snap);
    begin
        check_ready("read_runtime_snapshot");

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS,           snap.queue_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS,      snap.queue_done_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,     snap.queue_error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS,    snap.queue_reject_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATE,            snap.queue_state);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,          snap.sq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,          snap.sq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,          snap.cq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,          snap.cq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_OCCUPANCY,     snap.sq_occupancy);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY,     snap.cq_occupancy);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_SPACE,         snap.cq_space);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CURRENT_INDEX,    snap.current_index);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_INDEX,      snap.error_index);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_DETAIL,     snap.error_detail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG,     snap.last_cmd_tag);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_CONTROL, snap.last_cmd_control);

        read_event_snapshot(snap.event_snap);
    end
    endtask

    function automatic void log_runtime_snapshot(input string label,
                                                 input p25_runtime_snapshot_t snap,
                                                 input uvm_verbosity verbosity = UVM_MEDIUM);
        `uvm_info("P25_HOST_RT/SNAPSHOT",
            $sformatf("%s: q_status=0x%08h q_done=0x%08h q_error=0x%08h q_reject=0x%08h state=0x%08h SQ(h/t/occ)=%0d/%0d/%0d CQ(h/t/occ/space)=%0d/%0d/%0d/%0d err_detail=0x%08h last_tag=0x%08h event_pending=0x%08h event_status=0x%08h event_count=%0d irq_count=%0d",
                label,
                snap.queue_status,
                snap.queue_done_status,
                snap.queue_error_status,
                snap.queue_reject_status,
                snap.queue_state,
                snap.sq_head,
                snap.sq_tail,
                snap.sq_occupancy,
                snap.cq_head,
                snap.cq_tail,
                snap.cq_occupancy,
                snap.cq_space,
                snap.error_detail,
                snap.last_cmd_tag,
                snap.event_snap.pending,
                snap.event_snap.status,
                snap.event_snap.event_count,
                snap.event_snap.irq_count),
            verbosity)
    endfunction

    task automatic snapshot_and_log(input string label,
                                    output p25_runtime_snapshot_t snap,
                                    input uvm_verbosity verbosity = UVM_MEDIUM);
    begin
        read_runtime_snapshot(snap);
        log_runtime_snapshot(label, snap, verbosity);
    end
    endtask

    // ------------------------------------------------------------
    // Cleanup / reusable checks
    // ------------------------------------------------------------
    task automatic ack_pending_from_snapshot(input p25_runtime_snapshot_t snap,
                                             input string label = "ack_pending_from_snapshot");
        logic [31:0] ack_mask;
    begin
        check_ready(label);
        ack_mask = snap.event_snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        if (ack_mask != 32'h0000_0000) begin
            ack_events(ack_mask);
        end
        `uvm_info("P25_HOST_RT/EVENT_ACK",
            $sformatf("%s: acked pending mask=0x%08h", label, ack_mask),
            UVM_MEDIUM)
    end
    endtask

    task automatic clear_runtime_sticky(input string label = "clear_runtime_sticky");
    begin
        check_ready(label);
        clear_queue_sticky();

        // The P24/P25 runtime tests rely on the queue-level sticky clear
        // for queue ownership.  Lower-level P17/P18/P16/P15 stickies are
        // already cleared by the validated queue AUTO_CLEAR policy on the
        // next accepted command.  Tests that intentionally inject a lower-
        // level failure can still clear those windows explicitly.
        `uvm_info("P25_HOST_RT/CLEAR",
            $sformatf("%s: issued queue sticky clear", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic wait_queue_reusable(input string label = "wait_queue_reusable",
                                       input int unsigned timeout_cycles = P25_DEFAULT_REUSABLE_TIMEOUT_CYCLES,
                                       input bit allow_done_sticky = 1'b1);
        p25_runtime_snapshot_t snap;
        int unsigned cnt;
    begin
        check_ready(label);
        cnt = 0;

        forever begin
            read_runtime_snapshot(snap);

            if (!queue_is_busy(snap) && !queue_has_error(snap)) begin
                if (!allow_done_sticky && (snap.queue_done_status != 32'h0000_0000)) begin
                    // keep polling only if the caller asked for fully clean done status
                end else begin
                    `uvm_info("P25_HOST_RT/REUSABLE",
                        $sformatf("%s: queue reusable after %0d poll(s): status=0x%08h done=0x%08h error=0x%08h reject=0x%08h SQ_HEAD=%0d CQ_TAIL=%0d CQ_HEAD=%0d",
                            label,
                            cnt,
                            snap.queue_status,
                            snap.queue_done_status,
                            snap.queue_error_status,
                            snap.queue_reject_status,
                            snap.sq_head,
                            snap.cq_tail,
                            snap.cq_head),
                        UVM_MEDIUM)
                    return;
                end
            end

            cnt++;
            if (cnt > timeout_cycles) begin
                log_runtime_snapshot({label, " timeout snapshot"}, snap, UVM_NONE);
                `uvm_fatal("P25_HOST_RT/REUSABLE_TIMEOUT",
                    $sformatf("%s: timeout waiting for reusable queue state", label))
            end
            @(posedge ctrl_vif.clk);
        end
    end
    endtask

    task automatic require_no_queue_error(input string label = "require_no_queue_error");
        p25_runtime_snapshot_t snap;
    begin
        snapshot_and_log(label, snap, UVM_HIGH);
        if (queue_has_error(snap)) begin
            `uvm_fatal("P25_HOST_RT/QUEUE_ERROR",
                $sformatf("%s: unexpected queue error/reject: status=0x%08h error=0x%08h reject=0x%08h detail=0x%08h",
                    label,
                    snap.queue_status,
                    snap.queue_error_status,
                    snap.queue_reject_status,
                    snap.error_detail))
        end
    end
    endtask

    task automatic require_event_clean(input string label = "require_event_clean");
        p23_event_snapshot_t event_snap;
    begin
        read_event_snapshot(event_snap);
        if (event_snap.pending != 32'h0000_0000) begin
            `uvm_fatal("P25_HOST_RT/EVENT_DIRTY",
                $sformatf("%s: event pending not clean: pending=0x%08h status=0x%08h last_cause=0x%08h",
                    label,
                    event_snap.pending,
                    event_snap.status,
                    event_snap.last_cause))
        end
        `uvm_info("P25_HOST_RT/EVENT_CLEAN",
            $sformatf("%s: event pending clean, status=0x%08h", label, event_snap.status),
            UVM_MEDIUM)
    end
    endtask

    task automatic clear_and_rearm_runtime(input p23_queue_cfg_t cfg,
                                           input logic [31:0] event_enable_mask,
                                           input bit clear_mem = 1'b1,
                                           input string label = "clear_and_rearm_runtime");
    begin
        check_ready(label);
        initialize_runtime(cfg, event_enable_mask, clear_mem);
        `uvm_info("P25_HOST_RT/REARM",
            $sformatf("%s: runtime initialized and event mask armed: mask=0x%08h clear_mem=%0d",
                label,
                event_enable_mask,
                clear_mem),
            UVM_MEDIUM)
    end
    endtask

    task automatic event_ack_and_require_clean(input p25_runtime_snapshot_t snap,
                                               input string label = "event_ack_and_require_clean");
    begin
        ack_pending_from_snapshot(snap, label);
        @(posedge ctrl_vif.clk);
        require_event_clean(label);
    end
    endtask

    // ------------------------------------------------------------
    // Pointer / CQ helpers for stress tests
    // ------------------------------------------------------------
    task automatic require_queue_pointers(input string label,
                                          input logic [31:0] expected_sq_head,
                                          input logic [31:0] expected_cq_head,
                                          input logic [31:0] expected_cq_tail,
                                          input logic [31:0] expected_cq_occ);
        p25_runtime_snapshot_t snap;
    begin
        snapshot_and_log(label, snap, UVM_HIGH);

        if (snap.sq_head != expected_sq_head) begin
            `uvm_fatal("P25_HOST_RT/SQ_HEAD_MISMATCH",
                $sformatf("%s: SQ_HEAD mismatch expected=0x%08h actual=0x%08h",
                    label,
                    expected_sq_head,
                    snap.sq_head))
        end

        if (snap.cq_head != expected_cq_head) begin
            `uvm_fatal("P25_HOST_RT/CQ_HEAD_MISMATCH",
                $sformatf("%s: CQ_HEAD mismatch expected=0x%08h actual=0x%08h",
                    label,
                    expected_cq_head,
                    snap.cq_head))
        end

        if (snap.cq_tail != expected_cq_tail) begin
            `uvm_fatal("P25_HOST_RT/CQ_TAIL_MISMATCH",
                $sformatf("%s: CQ_TAIL mismatch expected=0x%08h actual=0x%08h",
                    label,
                    expected_cq_tail,
                    snap.cq_tail))
        end

        if (snap.cq_occupancy != expected_cq_occ) begin
            `uvm_fatal("P25_HOST_RT/CQ_OCC_MISMATCH",
                $sformatf("%s: CQ_OCC mismatch expected=0x%08h actual=0x%08h",
                    label,
                    expected_cq_occ,
                    snap.cq_occupancy))
        end

        `uvm_info("P25_HOST_RT/PTR_PASS",
            $sformatf("%s: pointer check PASS SQ_HEAD=%0d CQ_HEAD=%0d CQ_TAIL=%0d CQ_OCC=%0d",
                label,
                snap.sq_head,
                snap.cq_head,
                snap.cq_tail,
                snap.cq_occupancy),
            UVM_MEDIUM)
    end
    endtask

    task automatic wait_and_check_cq_record(input p23_queue_cfg_t cfg,
                                            input int unsigned entry_index,
                                            input logic [31:0] expected_first_tag,
                                            input logic [31:0] expected_last_tag,
                                            output p23_cq_record_t rec,
                                            input string label = "wait_and_check_cq_record",
                                            input int unsigned timeout_cycles = P25_DEFAULT_STRESS_TIMEOUT_CYCLES);
    begin
        wait_cq_commit(cfg, entry_index, rec, timeout_cycles);

        if (rec.commit_word[0] != 1'b1) begin
            `uvm_fatal("P25_HOST_RT/CQ_INVALID",
                $sformatf("%s: CQ[%0d] commit valid bit is not set: commit=0x%08h",
                    label,
                    entry_index,
                    rec.commit_word))
        end

        if (rec.first_user_tag != expected_first_tag) begin
            `uvm_fatal("P25_HOST_RT/CQ_FIRST_TAG",
                $sformatf("%s: CQ[%0d] first tag mismatch expected=0x%08h actual=0x%08h",
                    label,
                    entry_index,
                    expected_first_tag,
                    rec.first_user_tag))
        end

        if (rec.last_user_tag != expected_last_tag) begin
            `uvm_fatal("P25_HOST_RT/CQ_LAST_TAG",
                $sformatf("%s: CQ[%0d] last tag mismatch expected=0x%08h actual=0x%08h",
                    label,
                    entry_index,
                    expected_last_tag,
                    rec.last_user_tag))
        end

        `uvm_info("P25_HOST_RT/CQ_PASS",
            $sformatf("%s: CQ[%0d] PASS commit=0x%08h status=0x%08h first=0x%08h last=0x%08h counts=0x%08h",
                label,
                entry_index,
                rec.commit_word,
                rec.status_flags,
                rec.first_user_tag,
                rec.last_user_tag,
                rec.counts),
            UVM_MEDIUM)
    end
    endtask

    task automatic consume_cq_range(input p23_queue_cfg_t cfg,
                                    input int unsigned start_index,
                                    input int unsigned count,
                                    input bit clear_commit_word = 1'b1,
                                    input string label = "consume_cq_range");
    begin
        check_ready(label);
        for (int unsigned i = 0; i < count; i++) begin
            consume_cq_entry(cfg, start_index + i, clear_commit_word);
        end
        `uvm_info("P25_HOST_RT/CQ_CONSUME",
            $sformatf("%s: consumed %0d CQ entries from index %0d", label, count, start_index),
            UVM_MEDIUM)
    end
    endtask

    task automatic wait_for_progress_event(input logic [31:0] required_mask,
                                           output p25_runtime_snapshot_t snap,
                                           input string label = "wait_for_progress_event",
                                           input int unsigned timeout_cycles = P25_DEFAULT_STRESS_TIMEOUT_CYCLES,
                                           input bit require_irq_summary = 1'b1);
        p23_event_snapshot_t event_snap;
    begin
        wait_events(required_mask, event_snap, timeout_cycles, require_irq_summary);
        read_runtime_snapshot(snap);
        log_runtime_snapshot(label, snap, UVM_MEDIUM);
    end
    endtask

    // ------------------------------------------------------------
    // Session-level thin wrappers
    // ------------------------------------------------------------
    task automatic start_session_with_single_command(
        input p23_queue_cfg_t cfg,
        input p23_sq_cmd_t   cmd,
        input logic [31:0]   event_enable_mask,
        input string         label = "start_session_with_single_command",
        input bit            clear_mem = 1'b1
    );
    begin
        clear_and_rearm_runtime(cfg, event_enable_mask, clear_mem, label);
        submit_command_and_doorbell(cfg, 0, cmd, 32'h0000_0001);
        start_queue();
        `uvm_info("P25_HOST_RT/SESSION_START",
            $sformatf("%s: started single-command session tag=0x%08h", label, cmd.user_tag),
            UVM_MEDIUM)
    end
    endtask

    task automatic complete_single_command_session(
        input  p23_queue_cfg_t       cfg,
        input  logic [31:0]          event_mask,
        input  logic [31:0]          expected_first_tag,
        input  logic [31:0]          expected_last_tag,
        output p23_cq_record_t       rec,
        output p25_runtime_snapshot_t snap,
        input  string                label = "complete_single_command_session",
        input  bit                   consume_cq = 1'b1,
        input  bit                   clear_cq_commit = 1'b1
    );
    begin
        wait_for_progress_event(event_mask, snap, label);
        wait_and_check_cq_record(cfg, 0, expected_first_tag, expected_last_tag, rec, label);

        if (consume_cq) begin
            consume_cq_entry(cfg, 0, clear_cq_commit);
        end

        event_ack_and_require_clean(snap, label);
        wait_queue_reusable(label);
        require_no_queue_error(label);

        `uvm_info("P25_HOST_RT/SESSION_PASS",
            $sformatf("%s: single-command session PASS", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic deterministic_gap(input int unsigned cycle_count,
                                     input string label = "deterministic_gap");
    begin
        check_ready(label);
        `uvm_info("P25_HOST_RT/GAP",
            $sformatf("%s: waiting %0d cycle(s)", label, cycle_count),
            UVM_HIGH)
        repeat (cycle_count) @(posedge ctrl_vif.clk);
    end
    endtask

endclass

`endif
