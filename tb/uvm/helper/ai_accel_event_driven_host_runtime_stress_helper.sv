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
    localparam int unsigned P26_DEFAULT_LIFECYCLE_TIMEOUT_CYCLES = 300000;

    typedef enum int unsigned {
        P26_LIFE_CLEAN_DRAINED,
        P26_LIFE_STOPPED_PRESERVE,
        P26_LIFE_STOPPED_DISCARD,
        P26_LIFE_ERROR_DISCARD
    } p26_lifecycle_policy_e;

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

    typedef struct {
        logic [31:0] event_pending;
        logic [31:0] event_status;
        logic [31:0] event_last_cause;
        logic [31:0] event_count;
        logic [31:0] event_irq_count;
        logic [31:0] queue_status;
        logic [31:0] queue_done_status;
        logic [31:0] queue_error_status;
        logic [31:0] queue_reject_status;
        logic [31:0] queue_state;
        logic [31:0] queue_error_detail;
        logic [31:0] queue_error_index;
        logic [31:0] queue_last_cmd_tag;
        logic [31:0] queue_last_cmd_control;
        logic [31:0] sq_head;
        logic [31:0] sq_tail;
        logic [31:0] cq_head;
        logic [31:0] cq_tail;
        logic [31:0] sq_occupancy;
        logic [31:0] cq_occupancy;
        logic [31:0] cq_space;
        logic [31:0] current_index;
    } p26_lifecycle_snapshot_t;

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


    // ------------------------------------------------------------
    // P26C lifecycle / soft-reset helper extension
    // ------------------------------------------------------------
    function automatic void p26_snapshot_from_p25(output p26_lifecycle_snapshot_t dst,
                                                  input  p25_runtime_snapshot_t     src);
    begin
        dst.event_pending          = src.event_snap.pending;
        dst.event_status           = src.event_snap.status;
        dst.event_last_cause       = src.event_snap.last_cause;
        dst.event_count            = src.event_snap.event_count;
        dst.event_irq_count        = src.event_snap.irq_count;
        dst.queue_status           = src.queue_status;
        dst.queue_done_status      = src.queue_done_status;
        dst.queue_error_status     = src.queue_error_status;
        dst.queue_reject_status    = src.queue_reject_status;
        dst.queue_state            = src.queue_state;
        dst.queue_error_detail     = src.error_detail;
        dst.queue_error_index      = src.error_index;
        dst.queue_last_cmd_tag     = src.last_cmd_tag;
        dst.queue_last_cmd_control = src.last_cmd_control;
        dst.sq_head                = src.sq_head;
        dst.sq_tail                = src.sq_tail;
        dst.cq_head                = src.cq_head;
        dst.cq_tail                = src.cq_tail;
        dst.sq_occupancy           = src.sq_occupancy;
        dst.cq_occupancy           = src.cq_occupancy;
        dst.cq_space               = src.cq_space;
        dst.current_index          = src.current_index;
    end
    endfunction

    task automatic host_rt_lifecycle_capture_snapshot(
        output p26_lifecycle_snapshot_t snap,
        input  string                   label = "host_rt_lifecycle_capture_snapshot",
        input  bit                      log_it = 1'b1
    );
        p25_runtime_snapshot_t rt_snap;
    begin
        check_ready(label);
        read_runtime_snapshot(rt_snap);
        p26_snapshot_from_p25(snap, rt_snap);

        if (log_it) begin
            `uvm_info("P26_LIFECYCLE/SNAPSHOT",
                $sformatf("%s: q_status=0x%08h q_done=0x%08h q_error=0x%08h q_reject=0x%08h state=0x%08h SQ(h/t/occ)=%0d/%0d/%0d CQ(h/t/occ/space)=%0d/%0d/%0d/%0d err_detail=0x%08h err_index=0x%08h last_tag=0x%08h event_pending=0x%08h event_status=0x%08h event_count=%0d irq_count=%0d",
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
                    snap.queue_error_detail,
                    snap.queue_error_index,
                    snap.queue_last_cmd_tag,
                    snap.event_pending,
                    snap.event_status,
                    snap.event_count,
                    snap.event_irq_count),
                UVM_MEDIUM)
        end
    end
    endtask

    task automatic host_rt_lifecycle_wait_idle(
        input string       label = "host_rt_lifecycle_wait_idle",
        input int unsigned timeout_cycles = P26_DEFAULT_LIFECYCLE_TIMEOUT_CYCLES,
        input bit          allow_error = 1'b1
    );
        p25_runtime_snapshot_t snap;
        int unsigned cnt;
    begin
        check_ready(label);
        cnt = 0;

        forever begin
            read_runtime_snapshot(snap);

            if (!queue_is_busy(snap)) begin
                if (!allow_error && queue_has_error(snap)) begin
                    `uvm_fatal("P26_LIFECYCLE/IDLE_ERROR",
                        $sformatf("%s: queue idle but error/reject is set: status=0x%08h error=0x%08h reject=0x%08h detail=0x%08h",
                            label,
                            snap.queue_status,
                            snap.queue_error_status,
                            snap.queue_reject_status,
                            snap.error_detail))
                end

                `uvm_info("P26_LIFECYCLE/IDLE",
                    $sformatf("%s: queue idle after %0d poll(s): status=0x%08h done=0x%08h error=0x%08h reject=0x%08h",
                        label,
                        cnt,
                        snap.queue_status,
                        snap.queue_done_status,
                        snap.queue_error_status,
                        snap.queue_reject_status),
                    UVM_MEDIUM)
                return;
            end

            cnt++;
            if (cnt > timeout_cycles) begin
                log_runtime_snapshot({label, " timeout snapshot"}, snap, UVM_NONE);
                `uvm_fatal("P26_LIFECYCLE/IDLE_TIMEOUT",
                    $sformatf("%s: timeout waiting for queue_busy to deassert", label))
            end
            @(posedge ctrl_vif.clk);
        end
    end
    endtask

    task automatic host_rt_lifecycle_clear_handled_events(
        input logic [31:0] event_mask,
        input string       label = "host_rt_lifecycle_clear_handled_events"
    );
    begin
        check_ready(label);
        if ((event_mask & ai_accel_csr_access_helper::EVENT_VALID_MASK) != 32'h0000_0000) begin
            ack_events(event_mask);
        end
        `uvm_info("P26_LIFECYCLE/EVENT_W1C",
            $sformatf("%s: W1C-cleared handled event mask=0x%08h",
                label,
                event_mask & ai_accel_csr_access_helper::EVENT_VALID_MASK),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_clear_all_events_and_counters(
        input string label = "host_rt_lifecycle_clear_all_events_and_counters"
    );
    begin
        check_ready(label);
        clear_event_state();
        `uvm_info("P26_LIFECYCLE/EVENT_CLEAR_ALL",
            $sformatf("%s: cleared all event pending bits and counters", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_rearm_events(
        input logic [31:0] event_enable_mask,
        input bit          global_irq_enable = 1'b1,
        input logic [31:0] cq_threshold = 32'h0000_0000,
        input bit          capture_snapshot = 1'b1,
        input string       label = "host_rt_lifecycle_rearm_events"
    );
        logic [31:0] control;
    begin
        check_ready(label);
        control = 32'h0000_0000;
        control[ai_accel_csr_access_helper::EVENT_CONTROL_GLOBAL_IRQ_ENABLE] = global_irq_enable;
        control[ai_accel_csr_access_helper::EVENT_CONTROL_CAPTURE_SNAPSHOT]  = capture_snapshot;
        arm_events(event_enable_mask, cq_threshold, control);
        `uvm_info("P26_LIFECYCLE/EVENT_REARM",
            $sformatf("%s: rearmed event mask=0x%08h global_irq=%0d capture_snapshot=%0d threshold=0x%08h",
                label,
                event_enable_mask & ai_accel_csr_access_helper::EVENT_VALID_MASK,
                global_irq_enable,
                capture_snapshot,
                cq_threshold),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_clear_queue_done(
        input string label = "host_rt_lifecycle_clear_queue_done"
    );
        logic [31:0] cmd;
    begin
        check_ready(label);
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_CLEAR_DONE] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_COMMAND, cmd);
        `uvm_info("P26_LIFECYCLE/QUEUE_CLEAR_DONE",
            $sformatf("%s: cleared queue done sticky status", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_clear_queue_error_and_reject(
        input string label = "host_rt_lifecycle_clear_queue_error_and_reject"
    );
        logic [31:0] cmd;
    begin
        check_ready(label);
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_CLEAR_ERROR] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_COMMAND, cmd);
        `uvm_info("P26_LIFECYCLE/QUEUE_CLEAR_ERROR",
            $sformatf("%s: cleared queue error/reject sticky status", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_clear_queue_counters(
        input string label = "host_rt_lifecycle_clear_queue_counters"
    );
        logic [31:0] cmd;
    begin
        check_ready(label);
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_CLEAR_COUNTERS] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_COMMAND, cmd);
        `uvm_info("P26_LIFECYCLE/QUEUE_CLEAR_COUNTERS",
            $sformatf("%s: cleared queue counters / debug snapshots", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_clear_queue_all_sticky(
        input bit    clear_counters = 1'b1,
        input string label = "host_rt_lifecycle_clear_queue_all_sticky"
    );
    begin
        host_rt_lifecycle_clear_queue_done({label, " done"});
        host_rt_lifecycle_clear_queue_error_and_reject({label, " error"});
        if (clear_counters) begin
            host_rt_lifecycle_clear_queue_counters({label, " counters"});
        end
    end
    endtask

    task automatic host_rt_lifecycle_clear_lower_sticky(
        input string label = "host_rt_lifecycle_clear_lower_sticky"
    );
        logic [31:0] cmd;
    begin
        check_ready(label);

        // P14 micro-operation sticky status.
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_CLEAR_DONE]  = 1'b1;
        cmd[ai_accel_csr_access_helper::CMD_CLEAR_ERROR] = 1'b1;
        cmd[ai_accel_csr_access_helper::CMD_CLEAR_PERF]  = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMMAND, cmd);

        // P15 job sticky status.
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::JOB_CMD_CLEAR_DONE]  = 1'b1;
        cmd[ai_accel_csr_access_helper::JOB_CMD_CLEAR_ERROR] = 1'b1;
        cmd[ai_accel_csr_access_helper::JOB_CMD_CLEAR_PERF]  = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_COMMAND, cmd);

        // P16 recipe sticky status and slot masks.
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::RECIPE_CMD_CLEAR_DONE]        = 1'b1;
        cmd[ai_accel_csr_access_helper::RECIPE_CMD_CLEAR_ERROR]       = 1'b1;
        cmd[ai_accel_csr_access_helper::RECIPE_CMD_CLEAR_PERF]        = 1'b1;
        cmd[ai_accel_csr_access_helper::RECIPE_CMD_CLEAR_SLOT_STATUS] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_COMMAND, cmd);

        // P17 descriptor-fetch sticky status.
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::DESC_FETCH_CMD_CLEAR_DONE]  = 1'b1;
        cmd[ai_accel_csr_access_helper::DESC_FETCH_CMD_CLEAR_ERROR] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_COMMAND, cmd);

        // P18 completion-writeback sticky status.
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::COMP_WB_CMD_CLEAR_DONE]  = 1'b1;
        cmd[ai_accel_csr_access_helper::COMP_WB_CMD_CLEAR_ERROR] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_COMMAND, cmd);

        `uvm_info("P26_LIFECYCLE/LOWER_CLEAR",
            $sformatf("%s: cleared P14/P15/P16/P17/P18 lower-level sticky state", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_recycle_sq_slots(
        input p23_queue_cfg_t cfg,
        input int unsigned   first_idx,
        input int unsigned   count,
        input string         label = "host_rt_lifecycle_recycle_sq_slots"
    );
        int unsigned base;
    begin
        check_ready(label);
        for (int unsigned i = 0; i < count; i++) begin
            base = cfg.sq_base + (((first_idx + i) % cfg.sq_depth) * cfg.sq_stride);
            for (int unsigned w = 0; w < (P23_SQ_ENTRY_BYTES / 4); w++) begin
                write_src_word_le(base + (w * 4), 32'h0000_0000);
            end
        end
        `uvm_info("P26_LIFECYCLE/SQ_RECYCLE",
            $sformatf("%s: cleared %0d SQ slot(s) starting at index %0d", label, count, first_idx),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_recycle_cq_slots(
        input p23_queue_cfg_t cfg,
        input int unsigned   first_idx,
        input int unsigned   count,
        input string         label = "host_rt_lifecycle_recycle_cq_slots"
    );
        int unsigned base;
    begin
        check_ready(label);
        for (int unsigned i = 0; i < count; i++) begin
            base = cfg.cq_base + (((first_idx + i) % cfg.cq_depth) * cfg.cq_stride);
            for (int unsigned w = 0; w < (P23_CQ_ENTRY_BYTES / 4); w++) begin
                write_dst_word_le(base + (w * 4), 32'h0000_0000);
            end
        end
        `uvm_info("P26_LIFECYCLE/CQ_RECYCLE",
            $sformatf("%s: cleared %0d CQ slot(s) starting at index %0d", label, count, first_idx),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_consume_visible_cq(
        input p23_queue_cfg_t cfg,
        input p26_lifecycle_snapshot_t snap,
        input bit clear_commit_word = 1'b1,
        input string label = "host_rt_lifecycle_consume_visible_cq"
    );
        p23_cq_record_t rec;
        int unsigned head;
        int unsigned tail;
    begin
        check_ready(label);
        head = snap.cq_head;
        tail = snap.cq_tail;

        if (tail < head) begin
            `uvm_fatal("P26_LIFECYCLE/CQ_POINTER_ORDER",
                $sformatf("%s: CQ_TAIL < CQ_HEAD is unsupported in monotonic no-wrap tests: head=%0d tail=%0d",
                    label,
                    head,
                    tail))
        end

        for (int unsigned idx = head; idx < tail; idx++) begin
            wait_cq_commit(cfg, idx, rec, P26_DEFAULT_LIFECYCLE_TIMEOUT_CYCLES);
            consume_cq_entry(cfg, idx, clear_commit_word);
        end

        `uvm_info("P26_LIFECYCLE/CQ_CONSUME_VISIBLE",
            $sformatf("%s: consumed visible CQ range [%0d, %0d)", label, head, tail),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_reset_pointers_idle(
        input string       label = "host_rt_lifecycle_reset_pointers_idle",
        input bit          require_zero = 1'b1,
        input int unsigned timeout_cycles = P26_DEFAULT_LIFECYCLE_TIMEOUT_CYCLES
    );
        logic [31:0] cmd;
        p26_lifecycle_snapshot_t snap;
        int unsigned cnt;
    begin
        check_ready(label);
        host_rt_lifecycle_wait_idle({label, " wait_idle"}, timeout_cycles, 1'b1);

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_RESET_POINTERS] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_COMMAND, cmd);

        if (require_zero) begin
            cnt = 0;
            forever begin
                host_rt_lifecycle_capture_snapshot(snap, {label, " reset_poll"}, 1'b0);
                if ((snap.sq_head == 32'h0000_0000) &&
                    (snap.sq_tail == 32'h0000_0000) &&
                    (snap.cq_head == 32'h0000_0000) &&
                    (snap.cq_tail == 32'h0000_0000)) begin
                    `uvm_info("P26_LIFECYCLE/PTR_RESET",
                        $sformatf("%s: pointer reset observed after %0d poll(s)", label, cnt),
                        UVM_MEDIUM)
                    return;
                end

                cnt++;
                if (cnt > timeout_cycles) begin
                    `uvm_fatal("P26_LIFECYCLE/PTR_RESET_TIMEOUT",
                        $sformatf("%s: pointer reset timeout, SQ(h/t)=%0d/%0d CQ(h/t)=%0d/%0d",
                            label,
                            snap.sq_head,
                            snap.sq_tail,
                            snap.cq_head,
                            snap.cq_tail))
                end
                @(posedge ctrl_vif.clk);
            end
        end

        `uvm_info("P26_LIFECYCLE/PTR_RESET",
            $sformatf("%s: issued idle-only RESET_QUEUE_POINTERS", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_init_session(
        input p23_queue_cfg_t cfg,
        input logic [31:0]   event_enable_mask,
        input bit            clear_mem = 1'b1,
        input bit            clear_lower_sticky = 1'b1,
        input string         label = "host_rt_lifecycle_init_session"
    );
    begin
        check_ready(label);
        host_rt_lifecycle_wait_idle({label, " wait_idle"}, P26_DEFAULT_LIFECYCLE_TIMEOUT_CYCLES, 1'b1);
        host_rt_lifecycle_clear_queue_all_sticky(1'b1, {label, " queue_clear"});
        if (clear_lower_sticky) begin
            host_rt_lifecycle_clear_lower_sticky({label, " lower_clear"});
        end
        host_rt_lifecycle_clear_all_events_and_counters({label, " event_clear"});
        if (clear_mem) begin
            clear_queue_memory(cfg);
        end
        program_queue(cfg);
        host_rt_lifecycle_rearm_events(event_enable_mask, 1'b1, 32'h0000_0000, 1'b1, {label, " event_rearm"});
        host_rt_lifecycle_check_clean_idle({label, " clean_check"}, 1'b1, 1'b1, 1'b0);
        `uvm_info("P26_LIFECYCLE/INIT_PASS",
            $sformatf("%s: lifecycle session initialized", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_cleanup_drained(
        input p23_queue_cfg_t cfg,
        input logic [31:0]   event_enable_mask,
        input bit            reset_pointers = 1'b1,
        input bit            consume_visible_cq = 1'b1,
        input bit            recycle_memory = 1'b1,
        input string         label = "host_rt_lifecycle_cleanup_drained"
    );
        p26_lifecycle_snapshot_t snap;
    begin
        check_ready(label);
        host_rt_lifecycle_wait_idle({label, " wait_idle"}, P26_DEFAULT_LIFECYCLE_TIMEOUT_CYCLES, 1'b0);
        host_rt_lifecycle_capture_snapshot(snap, {label, " terminal_snapshot"});

        if ((snap.queue_error_status != 32'h0000_0000) ||
            (snap.queue_reject_status != 32'h0000_0000) ||
            (snap.queue_status[2] == 1'b1)) begin
            `uvm_fatal("P26_LIFECYCLE/DRAINED_ERROR",
                $sformatf("%s: drained cleanup saw queue error/reject: status=0x%08h error=0x%08h reject=0x%08h",
                    label,
                    snap.queue_status,
                    snap.queue_error_status,
                    snap.queue_reject_status))
        end

        if (consume_visible_cq) begin
            host_rt_lifecycle_consume_visible_cq(cfg, snap, 1'b1, {label, " consume_cq"});
        end

        host_rt_lifecycle_clear_all_events_and_counters({label, " event_clear"});
        host_rt_lifecycle_clear_queue_done({label, " queue_done_clear"});
        host_rt_lifecycle_clear_queue_counters({label, " queue_counter_clear"});

        if (recycle_memory) begin
            host_rt_lifecycle_recycle_sq_slots(cfg, 0, cfg.sq_depth, {label, " recycle_sq"});
            host_rt_lifecycle_recycle_cq_slots(cfg, 0, cfg.cq_depth, {label, " recycle_cq"});
        end

        if (reset_pointers) begin
            host_rt_lifecycle_reset_pointers_idle({label, " reset_ptr"});
            program_queue(cfg);
        end

        host_rt_lifecycle_rearm_events(event_enable_mask, 1'b1, 32'h0000_0000, 1'b1, {label, " event_rearm"});
        host_rt_lifecycle_check_clean_idle({label, " clean_check"}, 1'b1, 1'b1, 1'b0);

        `uvm_info("P26_LIFECYCLE/DRAINED_PASS",
            $sformatf("%s: drained-session cleanup PASS reset_pointers=%0d recycle_memory=%0d",
                label,
                reset_pointers,
                recycle_memory),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_cleanup_stopped_preserve(
        input p23_queue_cfg_t cfg,
        input logic [31:0]   event_enable_mask,
        input bit            consume_visible_cq = 1'b1,
        input string         label = "host_rt_lifecycle_cleanup_stopped_preserve"
    );
        p26_lifecycle_snapshot_t snap;
    begin
        check_ready(label);
        host_rt_lifecycle_wait_idle({label, " wait_idle"}, P26_DEFAULT_LIFECYCLE_TIMEOUT_CYCLES, 1'b0);
        host_rt_lifecycle_capture_snapshot(snap, {label, " stopped_snapshot"});

        if ((snap.queue_error_status != 32'h0000_0000) ||
            (snap.queue_reject_status != 32'h0000_0000) ||
            (snap.queue_status[2] == 1'b1)) begin
            `uvm_fatal("P26_LIFECYCLE/STOPPED_ERROR",
                $sformatf("%s: stopped-preserve cleanup saw queue error/reject: status=0x%08h error=0x%08h reject=0x%08h",
                    label,
                    snap.queue_status,
                    snap.queue_error_status,
                    snap.queue_reject_status))
        end

        if (consume_visible_cq) begin
            host_rt_lifecycle_consume_visible_cq(cfg, snap, 1'b1, {label, " consume_cq"});
        end

        // Re-read pending after CQ_HEAD updates.  A CQ-space-recovered or
        // completion-related event may be generated while the host consumes CQ.
        host_rt_lifecycle_capture_snapshot(snap, {label, " post_consume_event_snapshot"}, 1'b0);
        host_rt_lifecycle_clear_handled_events(snap.event_pending, {label, " event_w1c"});
        host_rt_lifecycle_clear_queue_done({label, " queue_done_clear"});
        host_rt_lifecycle_rearm_events(event_enable_mask, 1'b1, 32'h0000_0000, 1'b1, {label, " event_rearm"});

        host_rt_lifecycle_capture_snapshot(snap, {label, " preserve_check"});
        if (snap.sq_head == snap.sq_tail) begin
            `uvm_info("P26_LIFECYCLE/STOPPED_NO_PENDING",
                $sformatf("%s: no pending SQ entries remain after stopped cleanup", label),
                UVM_MEDIUM)
        end else begin
            `uvm_info("P26_LIFECYCLE/STOPPED_PENDING",
                $sformatf("%s: pending SQ work preserved SQ_HEAD=%0d SQ_TAIL=%0d", label, snap.sq_head, snap.sq_tail),
                UVM_MEDIUM)
        end

        host_rt_lifecycle_check_clean_idle({label, " clean_check"}, 1'b1, 1'b1, 1'b0);

        `uvm_info("P26_LIFECYCLE/STOPPED_PRESERVE_PASS",
            $sformatf("%s: stopped-session work-preserving cleanup PASS", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_cleanup_stopped_discard(
        input p23_queue_cfg_t cfg,
        input logic [31:0]   event_enable_mask,
        input bit            consume_visible_cq = 1'b1,
        input bit            recycle_memory = 1'b1,
        input string         label = "host_rt_lifecycle_cleanup_stopped_discard"
    );
        p26_lifecycle_snapshot_t snap;
    begin
        check_ready(label);
        host_rt_lifecycle_wait_idle({label, " wait_idle"}, P26_DEFAULT_LIFECYCLE_TIMEOUT_CYCLES, 1'b0);
        host_rt_lifecycle_capture_snapshot(snap, {label, " stopped_discard_snapshot"});

        if (consume_visible_cq) begin
            host_rt_lifecycle_consume_visible_cq(cfg, snap, 1'b1, {label, " consume_cq"});
        end

        host_rt_lifecycle_clear_all_events_and_counters({label, " event_clear"});
        host_rt_lifecycle_clear_queue_done({label, " queue_done_clear"});
        host_rt_lifecycle_clear_queue_error_and_reject({label, " queue_error_clear"});
        host_rt_lifecycle_clear_queue_counters({label, " queue_counter_clear"});

        if (recycle_memory) begin
            host_rt_lifecycle_recycle_sq_slots(cfg, 0, cfg.sq_depth, {label, " recycle_sq"});
            host_rt_lifecycle_recycle_cq_slots(cfg, 0, cfg.cq_depth, {label, " recycle_cq"});
        end

        host_rt_lifecycle_reset_pointers_idle({label, " reset_ptr"});
        program_queue(cfg);
        host_rt_lifecycle_rearm_events(event_enable_mask, 1'b1, 32'h0000_0000, 1'b1, {label, " event_rearm"});
        host_rt_lifecycle_check_clean_idle({label, " clean_check"}, 1'b1, 1'b1, 1'b0);

        `uvm_info("P26_LIFECYCLE/STOPPED_DISCARD_PASS",
            $sformatf("%s: stopped-session discard cleanup PASS", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_capture_error_snapshot(
        output p26_lifecycle_snapshot_t snap,
        input  string                   label = "host_rt_lifecycle_capture_error_snapshot",
        input  bit                      require_error = 1'b1
    );
    begin
        host_rt_lifecycle_capture_snapshot(snap, label, 1'b1);
        if (require_error &&
            (snap.queue_error_status == 32'h0000_0000) &&
            (snap.queue_reject_status == 32'h0000_0000) &&
            (snap.queue_status[2] == 1'b0)) begin
            `uvm_fatal("P26_LIFECYCLE/NO_ERROR",
                $sformatf("%s: expected queue error/reject but status=0x%08h error=0x%08h reject=0x%08h",
                    label,
                    snap.queue_status,
                    snap.queue_error_status,
                    snap.queue_reject_status))
        end

        `uvm_info("P26_LIFECYCLE/ERROR_CAPTURE_PASS",
            $sformatf("%s: captured error diagnostic snapshot error=0x%08h reject=0x%08h detail=0x%08h index=0x%08h tag=0x%08h",
                label,
                snap.queue_error_status,
                snap.queue_reject_status,
                snap.queue_error_detail,
                snap.queue_error_index,
                snap.queue_last_cmd_tag),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_cleanup_error_discard(
        input p23_queue_cfg_t cfg,
        input logic [31:0]   event_enable_mask,
        output p26_lifecycle_snapshot_t error_snap,
        input bit            consume_visible_cq = 1'b1,
        input bit            recycle_memory = 1'b1,
        input bit            clear_lower_sticky = 1'b1,
        input string         label = "host_rt_lifecycle_cleanup_error_discard"
    );
    begin
        check_ready(label);
        host_rt_lifecycle_wait_idle({label, " wait_idle"}, P26_DEFAULT_LIFECYCLE_TIMEOUT_CYCLES, 1'b1);
        host_rt_lifecycle_capture_error_snapshot(error_snap, {label, " error_snapshot"}, 1'b1);

        if (consume_visible_cq) begin
            host_rt_lifecycle_consume_visible_cq(cfg, error_snap, 1'b1, {label, " consume_cq"});
        end

        host_rt_lifecycle_clear_all_events_and_counters({label, " event_clear"});
        host_rt_lifecycle_clear_queue_all_sticky(1'b1, {label, " queue_clear"});
        if (clear_lower_sticky) begin
            host_rt_lifecycle_clear_lower_sticky({label, " lower_clear"});
        end

        if (recycle_memory) begin
            host_rt_lifecycle_recycle_sq_slots(cfg, 0, cfg.sq_depth, {label, " recycle_sq"});
            host_rt_lifecycle_recycle_cq_slots(cfg, 0, cfg.cq_depth, {label, " recycle_cq"});
        end

        host_rt_lifecycle_reset_pointers_idle({label, " reset_ptr"});
        program_queue(cfg);
        host_rt_lifecycle_rearm_events(event_enable_mask, 1'b1, 32'h0000_0000, 1'b1, {label, " event_rearm"});
        host_rt_lifecycle_check_clean_idle({label, " clean_check"}, 1'b1, 1'b1, 1'b0);

        `uvm_info("P26_LIFECYCLE/ERROR_DISCARD_PASS",
            $sformatf("%s: timeout/error session-discard cleanup PASS", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_lifecycle_check_clean_idle(
        input string label = "host_rt_lifecycle_check_clean_idle",
        input bit    allow_done_sticky = 1'b1,
        input bit    require_event_clean = 1'b1,
        input bit    require_zero_pointers = 1'b0
    );
        p26_lifecycle_snapshot_t snap;
    begin
        host_rt_lifecycle_capture_snapshot(snap, label, 1'b1);

        if (snap.queue_status[0]) begin
            `uvm_fatal("P26_LIFECYCLE/BUSY_DIRTY",
                $sformatf("%s: queue is still busy: status=0x%08h", label, snap.queue_status))
        end

        if ((snap.queue_error_status != 32'h0000_0000) ||
            (snap.queue_reject_status != 32'h0000_0000) ||
            (snap.queue_status[2] == 1'b1)) begin
            `uvm_fatal("P26_LIFECYCLE/ERROR_DIRTY",
                $sformatf("%s: queue error/reject not clean: status=0x%08h error=0x%08h reject=0x%08h detail=0x%08h",
                    label,
                    snap.queue_status,
                    snap.queue_error_status,
                    snap.queue_reject_status,
                    snap.queue_error_detail))
        end

        if (!allow_done_sticky && (snap.queue_done_status != 32'h0000_0000)) begin
            `uvm_fatal("P26_LIFECYCLE/DONE_DIRTY",
                $sformatf("%s: queue done sticky not clean: done=0x%08h", label, snap.queue_done_status))
        end

        if (require_event_clean && (snap.event_pending != 32'h0000_0000)) begin
            `uvm_fatal("P26_LIFECYCLE/EVENT_DIRTY",
                $sformatf("%s: event pending not clean: pending=0x%08h status=0x%08h",
                    label,
                    snap.event_pending,
                    snap.event_status))
        end

        if (require_zero_pointers &&
            ((snap.sq_head != 32'h0000_0000) ||
             (snap.sq_tail != 32'h0000_0000) ||
             (snap.cq_head != 32'h0000_0000) ||
             (snap.cq_tail != 32'h0000_0000))) begin
            `uvm_fatal("P26_LIFECYCLE/PTR_DIRTY",
                $sformatf("%s: pointers not zero: SQ(h/t)=%0d/%0d CQ(h/t)=%0d/%0d",
                    label,
                    snap.sq_head,
                    snap.sq_tail,
                    snap.cq_head,
                    snap.cq_tail))
        end

        `uvm_info("P26_LIFECYCLE/CLEAN_IDLE_PASS",
            $sformatf("%s: clean idle check PASS status=0x%08h done=0x%08h SQ(h/t)=%0d/%0d CQ(h/t)=%0d/%0d event_pending=0x%08h",
                label,
                snap.queue_status,
                snap.queue_done_status,
                snap.sq_head,
                snap.sq_tail,
                snap.cq_head,
                snap.cq_tail,
                snap.event_pending),
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
