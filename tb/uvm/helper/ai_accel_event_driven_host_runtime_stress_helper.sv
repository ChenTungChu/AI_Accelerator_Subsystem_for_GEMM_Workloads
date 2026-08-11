// File: tb/uvm/helper/ai_accel_event_driven_host_runtime_stress_helper.sv
`ifndef AI_ACCEL_EVENT_DRIVEN_HOST_RUNTIME_STRESS_HELPER_SV
`define AI_ACCEL_EVENT_DRIVEN_HOST_RUNTIME_STRESS_HELPER_SV

// ============================================================
// P25B event-driven host runtime stress helper extension
// P26C queue lifecycle helper extension
// P27C memory guard helper / checker utility extension
// P28C host runtime batch-CQ consume helper extension
// P30C driver-facing runtime ABI helper consolidation
//
// Scope:
//   - TB/UVM helper only.
//   - Extends the existing P23 event-driven host runtime helper.
//   - Adds reusable stress-oriented snapshot, cleanup, re-arm,
//     CQ-consume, queue-reusable, lifecycle, and P27 guard setup /
//     checker utilities.
//   - Does not change RTL, CSR map, SQ/CQ formats, event bits,
//     descriptor format, completion record format, or sim flow.
// ============================================================

class ai_accel_event_driven_host_runtime_stress_helper
    extends ai_accel_event_driven_host_runtime_helper;

    `uvm_object_utils(ai_accel_event_driven_host_runtime_stress_helper)

    localparam int unsigned P25_DEFAULT_STRESS_TIMEOUT_CYCLES = 300000;
    localparam int unsigned P25_DEFAULT_REUSABLE_TIMEOUT_CYCLES = 200000;
    localparam int unsigned P26_DEFAULT_LIFECYCLE_TIMEOUT_CYCLES = 300000;
    localparam int unsigned P27_DEFAULT_GUARD_TIMEOUT_CYCLES = 300000;
    localparam int unsigned P28_DEFAULT_MOD_TIMEOUT_CYCLES = 300000;
    localparam int unsigned P30_DEFAULT_ABI_TIMEOUT_CYCLES = 300000;

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


    typedef struct {
        logic [31:0] control;
        logic [31:0] sq_base;
        logic [31:0] sq_limit;
        logic [31:0] cq_base;
        logic [31:0] cq_limit;
        logic [31:0] desc_base;
        logic [31:0] desc_limit;
        logic [31:0] src_base;
        logic [31:0] src_limit;
        logic [31:0] dst_base;
        logic [31:0] dst_limit;
    } p27_guard_cfg_t;

    typedef struct {
        logic [31:0] status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] error_detail;
        logic [31:0] error_addr;
        logic [31:0] error_size_bytes;
        logic [31:0] error_domain;
        logic [31:0] check_count;
        logic [31:0] error_count;
        logic [31:0] last_check_addr;
        logic [31:0] last_check_size_bytes;
        logic [31:0] last_check_domain;
        logic [31:0] queue_status;
        logic [31:0] queue_error_status;
        logic [31:0] queue_error_detail;
        logic [31:0] event_pending;
    } p27_guard_snapshot_t;

    typedef struct {
        logic [31:0] mod_control;
        logic [31:0] event_enable_mask;
        logic [31:0] event_control;
        logic [31:0] cq_threshold;
        logic [31:0] timer_limit;
    } p28_event_mod_cfg_t;

    typedef struct {
        logic [31:0] event_status;
        logic [31:0] event_pending;
        logic [31:0] event_enable;
        logic [31:0] event_control;
        logic [31:0] event_last_cause;
        logic [31:0] event_count;
        logic [31:0] event_irq_count;
        logic [31:0] event_cq_threshold;
        logic [31:0] mod_control;
        logic [31:0] mod_status;
        logic [31:0] mod_timer_limit;
        logic [31:0] mod_debug;
        logic [31:0] queue_status;
        logic [31:0] queue_done_status;
        logic [31:0] queue_error_status;
        logic [31:0] queue_reject_status;
        logic [31:0] sq_head;
        logic [31:0] sq_tail;
        logic [31:0] cq_head;
        logic [31:0] cq_tail;
        logic [31:0] sq_occupancy;
        logic [31:0] cq_occupancy;
        logic [31:0] cq_space;
    } p28_event_mod_snapshot_t;



    typedef struct {
        logic [31:0] version;
        logic [31:0] status;
        logic [31:0] control;
        logic [31:0] queue_start_count;
        logic [31:0] sq_accept_count;
        logic [31:0] cmd_complete_count;
        logic [31:0] cq_commit_count;
        logic [31:0] queue_drained_count;
        logic [31:0] queue_stopped_count;
        logic [31:0] queue_error_count;
        logic [31:0] cq_head_update_count;
        logic [31:0] cq_consumed_count;
        logic [31:0] max_cq_batch_size;
        logic [31:0] event_capture_count;
        logic [31:0] irq_eligible_count;
        logic [31:0] completion_event_count;
        logic [31:0] coalesced_release_count;
        logic [31:0] threshold_release_count;
        logic [31:0] timer_release_count;
        logic [31:0] urgent_bypass_count;
        logic [31:0] cq_full_stall_count;
        logic [31:0] cq_space_recovered_count;
        logic [31:0] timeout_error_count;
        logic [31:0] mem_guard_error_count;
        logic [31:0] stop_queue_request_count;
        logic [31:0] queue_enabled_cycles;
        logic [31:0] queue_busy_cycles;
        logic [31:0] queue_idle_cycles;
        logic [31:0] queue_stalled_cycles;
        logic [31:0] cq_full_stall_cycles;
        logic [31:0] lower_wait_cycles;
    } p29_runtime_telem_snapshot_t;

    typedef struct {
        p23_queue_cfg_t      queue_cfg;
        p27_guard_cfg_t      guard_cfg;
        p28_event_mod_cfg_t  event_mod_cfg;
        logic [31:0]         event_enable_mask;
        logic [31:0]         event_cq_threshold;
        logic [31:0]         event_control;
        logic [31:0]         telemetry_control;
        bit                  enable_guard;
        bit                  enable_event_moderation;
        bit                  enable_telemetry;
        bit                  clear_queue_memory;
        bit                  clear_lower_sticky;
    } p30_driver_runtime_abi_cfg_t;

    typedef struct {
        logic [31:0] start_cq_head;
        logic [31:0] start_cq_tail;
        logic [31:0] visible_count;
        logic [31:0] consumed_count;
        logic [31:0] final_cq_head;
        logic [31:0] first_commit_word;
        logic [31:0] last_commit_word;
        logic [31:0] first_user_tag;
        logic [31:0] last_user_tag;
    } p28_cq_batch_result_t;

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

    function automatic void host_rt_lifecycle_make_zero_epoch_cfg(
        output p23_queue_cfg_t zero_cfg,
        input  p23_queue_cfg_t cfg
    );
    begin
        zero_cfg = cfg;
        zero_cfg.sq_head = 32'h0000_0000;
        zero_cfg.sq_tail = 32'h0000_0000;
        zero_cfg.cq_head = 32'h0000_0000;
        zero_cfg.cq_tail = 32'h0000_0000;
    end
    endfunction

    task automatic host_rt_lifecycle_init_session(
        input p23_queue_cfg_t cfg,
        input logic [31:0]   event_enable_mask,
        input bit            clear_mem = 1'b1,
        input bit            clear_lower_sticky = 1'b1,
        input string         label = "host_rt_lifecycle_init_session",
        input bit            fresh_pointer_epoch = 1'b0
    );
        p23_queue_cfg_t programmed_cfg;
    begin
        check_ready(label);
        programmed_cfg = cfg;

        host_rt_lifecycle_wait_idle({label, " wait_idle"}, P26_DEFAULT_LIFECYCLE_TIMEOUT_CYCLES, 1'b1);
        host_rt_lifecycle_clear_queue_all_sticky(1'b1, {label, " queue_clear"});
        if (clear_lower_sticky) begin
            host_rt_lifecycle_clear_lower_sticky({label, " lower_clear"});
        end
        host_rt_lifecycle_clear_all_events_and_counters({label, " event_clear"});

        // A lifecycle init can either preserve an already-clean monotonic
        // pointer epoch or establish a fresh zero-counter epoch.  Only the
        // explicit fresh mode may issue RESET_QUEUE_POINTERS.  After reset,
        // normalize all expected / host-owned counter fields before calling
        // program_queue(); SQ_HEAD and CQ_TAIL remain hardware-owned.
        if (fresh_pointer_epoch) begin
            host_rt_lifecycle_reset_pointers_idle({label, " reset_ptr"});
            host_rt_lifecycle_make_zero_epoch_cfg(programmed_cfg, cfg);
        end

        if (clear_mem) begin
            clear_queue_memory(programmed_cfg);
        end
        program_queue(programmed_cfg);
        host_rt_lifecycle_rearm_events(event_enable_mask, 1'b1, 32'h0000_0000, 1'b1, {label, " event_rearm"});
        host_rt_lifecycle_check_clean_idle(
            {label, " clean_check"},
            1'b1,
            1'b1,
            fresh_pointer_epoch
        );
        `uvm_info("P26_LIFECYCLE/INIT_PASS",
            $sformatf("%s: lifecycle session initialized fresh_pointer_epoch=%0d SQ(h/t)=%0d/%0d CQ(h/t)=%0d/%0d",
                label,
                fresh_pointer_epoch,
                programmed_cfg.sq_head,
                programmed_cfg.sq_tail,
                programmed_cfg.cq_head,
                programmed_cfg.cq_tail),
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
        p23_queue_cfg_t          programmed_cfg;
    begin
        check_ready(label);
        programmed_cfg = cfg;
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
            host_rt_lifecycle_make_zero_epoch_cfg(programmed_cfg, cfg);
            program_queue(programmed_cfg);
        end

        host_rt_lifecycle_rearm_events(event_enable_mask, 1'b1, 32'h0000_0000, 1'b1, {label, " event_rearm"});
        host_rt_lifecycle_check_clean_idle(
            {label, " clean_check"},
            1'b1,
            1'b1,
            reset_pointers
        );

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
        p23_queue_cfg_t          programmed_cfg;
    begin
        check_ready(label);
        programmed_cfg = cfg;
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
        host_rt_lifecycle_make_zero_epoch_cfg(programmed_cfg, cfg);
        program_queue(programmed_cfg);
        host_rt_lifecycle_rearm_events(event_enable_mask, 1'b1, 32'h0000_0000, 1'b1, {label, " event_rearm"});
        host_rt_lifecycle_check_clean_idle({label, " clean_check"}, 1'b1, 1'b1, 1'b1);

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
        p23_queue_cfg_t programmed_cfg;
    begin
        check_ready(label);
        programmed_cfg = cfg;
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
        host_rt_lifecycle_make_zero_epoch_cfg(programmed_cfg, cfg);
        program_queue(programmed_cfg);
        host_rt_lifecycle_rearm_events(event_enable_mask, 1'b1, 32'h0000_0000, 1'b1, {label, " event_rearm"});
        host_rt_lifecycle_check_clean_idle({label, " clean_check"}, 1'b1, 1'b1, 1'b1);

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

        // These lifecycle helpers use monotonic no-wrap counter epochs.
        // Reject impossible host-visible ordering before unsigned occupancy
        // arithmetic can disguise it as 0xffffffff / 0xfffffffe.
        if (snap.sq_tail < snap.sq_head) begin
            `uvm_fatal("P26_LIFECYCLE/SQ_POINTER_ORDER",
                $sformatf("%s: SQ_TAIL < SQ_HEAD: SQ(h/t)=%0d/%0d",
                    label,
                    snap.sq_head,
                    snap.sq_tail))
        end

        if (snap.cq_tail < snap.cq_head) begin
            `uvm_fatal("P26_LIFECYCLE/CQ_POINTER_ORDER",
                $sformatf("%s: CQ_TAIL < CQ_HEAD: CQ(h/t)=%0d/%0d",
                    label,
                    snap.cq_head,
                    snap.cq_tail))
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



    // ------------------------------------------------------------
    // P27 memory guard helper / checker utilities
    // ------------------------------------------------------------
    function automatic logic [31:0] host_rt_mem_guard_control_value(
        input bit guard_enable = 1'b1,
        input bit strict_reject_enable = 1'b1,
        input bit sq_check_enable = 1'b1,
        input bit cq_check_enable = 1'b1,
        input bit desc_check_enable = 1'b1,
        input bit src_check_enable = 1'b1,
        input bit dst_check_enable = 1'b1,
        input bit write_cq_error_if_safe = 1'b1
    );
        logic [31:0] value;
    begin
        value = 32'h0000_0000;
        value[ai_accel_csr_access_helper::MEM_GUARD_CONTROL_ENABLE]              = guard_enable;
        value[ai_accel_csr_access_helper::MEM_GUARD_CONTROL_STRICT_REJECT]       = strict_reject_enable;
        value[ai_accel_csr_access_helper::MEM_GUARD_CONTROL_SQ_CHECK_ENABLE]     = sq_check_enable;
        value[ai_accel_csr_access_helper::MEM_GUARD_CONTROL_CQ_CHECK_ENABLE]     = cq_check_enable;
        value[ai_accel_csr_access_helper::MEM_GUARD_CONTROL_DESC_CHECK_ENABLE]   = desc_check_enable;
        value[ai_accel_csr_access_helper::MEM_GUARD_CONTROL_SRC_CHECK_ENABLE]    = src_check_enable;
        value[ai_accel_csr_access_helper::MEM_GUARD_CONTROL_DST_CHECK_ENABLE]    = dst_check_enable;
        value[ai_accel_csr_access_helper::MEM_GUARD_CONTROL_WRITE_CQ_ERROR_SAFE] = write_cq_error_if_safe;
        return value;
    end
    endfunction

    function automatic logic [31:0] host_rt_mem_guard_span_limit(
        input logic [31:0] base_addr,
        input logic [31:0] size_bytes
    );
        logic [32:0] end_addr_ext;
    begin
        end_addr_ext = {1'b0, base_addr} + {1'b0, size_bytes};
        if (end_addr_ext[32]) begin
            return 32'hFFFF_FFFF;
        end
        return end_addr_ext[31:0];
    end
    endfunction

    function automatic bit host_rt_mem_guard_range_valid(
        input logic [31:0] addr,
        input logic [31:0] size_bytes,
        input logic [31:0] region_base,
        input logic [31:0] region_limit
    );
        logic [32:0] end_addr_ext;
    begin
        end_addr_ext = {1'b0, addr} + {1'b0, size_bytes};
        return (size_bytes != 32'h0000_0000) &&
               (region_base < region_limit) &&
               (end_addr_ext[32] == 1'b0) &&
               (addr >= region_base) &&
               (end_addr_ext[31:0] <= region_limit);
    end
    endfunction

    function automatic bit host_rt_mem_guard_region_config_valid(
        input logic [31:0] region_base,
        input logic [31:0] region_limit
    );
    begin
        return (region_base < region_limit);
    end
    endfunction

    function automatic string host_rt_mem_guard_domain_name(input logic [31:0] domain);
    begin
        case (domain)
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_NONE:   return "NONE";
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_SQ:     return "SQ";
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_CQ:     return "CQ";
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_DESC:   return "DESC";
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_SRC:    return "SRC";
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_DST:    return "DST";
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_CONFIG: return "CONFIG";
            default: return $sformatf("UNKNOWN_%0d", domain);
        endcase
    end
    endfunction

    function automatic string host_rt_mem_guard_detail_name(input logic [7:0] detail_code);
    begin
        case (detail_code)
            ai_accel_csr_access_helper::P27_DETAIL_SQ_RANGE:        return "SQ_RANGE";
            ai_accel_csr_access_helper::P27_DETAIL_CQ_RANGE:        return "CQ_RANGE";
            ai_accel_csr_access_helper::P27_DETAIL_DESC_RANGE:      return "DESC_RANGE";
            ai_accel_csr_access_helper::P27_DETAIL_SRC_RANGE:       return "SRC_RANGE";
            ai_accel_csr_access_helper::P27_DETAIL_DST_RANGE:       return "DST_RANGE";
            ai_accel_csr_access_helper::P27_DETAIL_ADDR_OVERFLOW:   return "ADDR_OVERFLOW";
            ai_accel_csr_access_helper::P27_DETAIL_ALIGNMENT:       return "ALIGNMENT";
            ai_accel_csr_access_helper::P27_DETAIL_SPAN_CONFIG:     return "SPAN_CONFIG";
            ai_accel_csr_access_helper::P27_DETAIL_DOMAIN_MISMATCH: return "DOMAIN_MISMATCH";
            default: return $sformatf("DETAIL_0x%02h", detail_code);
        endcase
    end
    endfunction

    task automatic host_rt_mem_guard_default_cfg_from_queue(
        input  p23_queue_cfg_t queue_cfg,
        input  logic [31:0]    desc_base,
        input  logic [31:0]    desc_size_bytes,
        input  logic [31:0]    src_base,
        input  logic [31:0]    src_limit,
        input  logic [31:0]    dst_base,
        input  logic [31:0]    dst_limit,
        input  logic [31:0]    control,
        output p27_guard_cfg_t guard_cfg
    );
        logic [31:0] sq_size_bytes;
        logic [31:0] cq_size_bytes;
    begin
        sq_size_bytes = queue_cfg.sq_depth * queue_cfg.sq_stride;
        cq_size_bytes = queue_cfg.cq_depth * queue_cfg.cq_stride;

        guard_cfg.control    = control;
        guard_cfg.sq_base    = queue_cfg.sq_base;
        guard_cfg.sq_limit   = host_rt_mem_guard_span_limit(queue_cfg.sq_base, sq_size_bytes);
        guard_cfg.cq_base    = queue_cfg.cq_base;
        guard_cfg.cq_limit   = host_rt_mem_guard_span_limit(queue_cfg.cq_base, cq_size_bytes);
        guard_cfg.desc_base  = desc_base;
        guard_cfg.desc_limit = host_rt_mem_guard_span_limit(desc_base, desc_size_bytes);
        guard_cfg.src_base   = src_base;
        guard_cfg.src_limit  = src_limit;
        guard_cfg.dst_base   = dst_base;
        guard_cfg.dst_limit  = dst_limit;
    end
    endtask

    task automatic host_rt_mem_guard_program_regions(
        input p27_guard_cfg_t guard_cfg,
        input string          label = "host_rt_mem_guard_program_regions"
    );
    begin
        check_ready(label);

        // Program regions while disabled so partially-programmed base/limit pairs
        // do not create transient enabled-region diagnostics.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_CONTROL, 32'h0000_0000);

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_SQ_BASE,    guard_cfg.sq_base);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_SQ_LIMIT,   guard_cfg.sq_limit);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_CQ_BASE,    guard_cfg.cq_base);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_CQ_LIMIT,   guard_cfg.cq_limit);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_DESC_BASE,  guard_cfg.desc_base);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_DESC_LIMIT, guard_cfg.desc_limit);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_SRC_BASE,   guard_cfg.src_base);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_SRC_LIMIT,  guard_cfg.src_limit);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_DST_BASE,   guard_cfg.dst_base);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_DST_LIMIT,  guard_cfg.dst_limit);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_CONTROL,    guard_cfg.control);

        `uvm_info("P27_GUARD/PROGRAM",
            $sformatf("%s: control=0x%08h SQ=[0x%08h,0x%08h) CQ=[0x%08h,0x%08h) DESC=[0x%08h,0x%08h) SRC=[0x%08h,0x%08h) DST=[0x%08h,0x%08h)",
                label,
                guard_cfg.control,
                guard_cfg.sq_base,
                guard_cfg.sq_limit,
                guard_cfg.cq_base,
                guard_cfg.cq_limit,
                guard_cfg.desc_base,
                guard_cfg.desc_limit,
                guard_cfg.src_base,
                guard_cfg.src_limit,
                guard_cfg.dst_base,
                guard_cfg.dst_limit),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_mem_guard_disable(
        input string label = "host_rt_mem_guard_disable"
    );
    begin
        check_ready(label);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_CONTROL, 32'h0000_0000);
        `uvm_info("P27_GUARD/DISABLE",
            $sformatf("%s: disabled memory guard checks", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_mem_guard_clear_all(
        input string label = "host_rt_mem_guard_clear_all"
    );
        logic [31:0] cmd;
    begin
        check_ready(label);
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::MEM_GUARD_CMD_CLEAR_ERROR]    = 1'b1;
        cmd[ai_accel_csr_access_helper::MEM_GUARD_CMD_CLEAR_REJECT]   = 1'b1;
        cmd[ai_accel_csr_access_helper::MEM_GUARD_CMD_CLEAR_COUNTERS] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_COMMAND, cmd);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_ERROR_STATUS,
                                ai_accel_csr_access_helper::MEM_GUARD_ALL_ERROR_MASK);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_REJECT_STATUS,
                                ai_accel_csr_access_helper::MEM_GUARD_ALL_REJECT_MASK);

        `uvm_info("P27_GUARD/CLEAR_ALL",
            $sformatf("%s: cleared guard error/reject/counter state", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_mem_guard_capture_snapshot(
        output p27_guard_snapshot_t snap,
        input  string               label = "host_rt_mem_guard_capture_snapshot",
        input  bit                  log_it = 1'b0
    );
    begin
        check_ready(label);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_STATUS,                snap.status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_ERROR_STATUS,          snap.error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_REJECT_STATUS,         snap.reject_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_ERROR_DETAIL,          snap.error_detail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_ERROR_ADDR,            snap.error_addr);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_ERROR_SIZE_BYTES,      snap.error_size_bytes);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_ERROR_DOMAIN,          snap.error_domain);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_CHECK_COUNT,           snap.check_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_ERROR_COUNT,           snap.error_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_LAST_CHECK_ADDR,       snap.last_check_addr);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_LAST_CHECK_SIZE_BYTES, snap.last_check_size_bytes);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_MEM_GUARD_LAST_CHECK_DOMAIN,     snap.last_check_domain);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS,                    snap.queue_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,              snap.queue_error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_DETAIL,              snap.queue_error_detail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_PENDING,                   snap.event_pending);

        if (log_it) begin
            host_rt_mem_guard_log_snapshot(label, snap);
        end
    end
    endtask

    function automatic void host_rt_mem_guard_log_snapshot(
        input string               label,
        input p27_guard_snapshot_t snap,
        input uvm_verbosity        verbosity = UVM_MEDIUM
    );
        logic [7:0] detail_code;
    begin
        detail_code = snap.error_detail[7:0];
        `uvm_info("P27_GUARD/SNAPSHOT",
            $sformatf("%s: status=0x%08h error=0x%08h reject=0x%08h detail=0x%08h(%s) addr=0x%08h size=%0d domain=0x%08h(%s) checks=%0d errors=%0d last_check=0x%08h/%0d/%s q_status=0x%08h q_error=0x%08h q_detail=0x%08h event_pending=0x%08h",
                label,
                snap.status,
                snap.error_status,
                snap.reject_status,
                snap.error_detail,
                host_rt_mem_guard_detail_name(detail_code),
                snap.error_addr,
                snap.error_size_bytes,
                snap.error_domain,
                host_rt_mem_guard_domain_name(snap.error_domain),
                snap.check_count,
                snap.error_count,
                snap.last_check_addr,
                snap.last_check_size_bytes,
                host_rt_mem_guard_domain_name(snap.last_check_domain),
                snap.queue_status,
                snap.queue_error_status,
                snap.queue_error_detail,
                snap.event_pending),
            verbosity)
    end
    endfunction

    task automatic host_rt_mem_guard_check_clean(
        input string label = "host_rt_mem_guard_check_clean",
        input bit    require_queue_guard_clean = 1'b1,
        input bit    require_event_clean = 1'b0
    );
        p27_guard_snapshot_t snap;
    begin
        host_rt_mem_guard_capture_snapshot(snap, label, 1'b1);

        if (snap.error_status != 32'h0000_0000) begin
            `uvm_fatal("P27_GUARD/ERROR_DIRTY",
                $sformatf("%s: guard error status is not clean: error=0x%08h detail=0x%08h addr=0x%08h size=%0d domain=%s",
                    label,
                    snap.error_status,
                    snap.error_detail,
                    snap.error_addr,
                    snap.error_size_bytes,
                    host_rt_mem_guard_domain_name(snap.error_domain)))
        end

        if (snap.reject_status != 32'h0000_0000) begin
            `uvm_fatal("P27_GUARD/REJECT_DIRTY",
                $sformatf("%s: guard reject status is not clean: reject=0x%08h", label, snap.reject_status))
        end

        if (require_queue_guard_clean &&
            snap.queue_error_status[ai_accel_csr_access_helper::P27_QUEUE_MEMORY_GUARD_ERROR_BIT]) begin
            `uvm_fatal("P27_GUARD/QUEUE_ERROR_DIRTY",
                $sformatf("%s: queue MEMORY_GUARD_ERROR bit is still set: queue_error=0x%08h queue_detail=0x%08h",
                    label,
                    snap.queue_error_status,
                    snap.queue_error_detail))
        end

        if (require_event_clean && (snap.event_pending != 32'h0000_0000)) begin
            `uvm_fatal("P27_GUARD/EVENT_DIRTY",
                $sformatf("%s: event pending is not clean: pending=0x%08h", label, snap.event_pending))
        end

        `uvm_info("P27_GUARD/CLEAN_PASS",
            $sformatf("%s: guard clean check PASS status=0x%08h checks=%0d errors=%0d",
                label,
                snap.status,
                snap.check_count,
                snap.error_count),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_mem_guard_expect_error(
        input logic [31:0] required_error_mask,
        input logic [31:0] expected_domain,
        input logic [7:0]  expected_detail,
        input string       label = "host_rt_mem_guard_expect_error"
    );
        p27_guard_snapshot_t snap;
        logic [31:0] queue_guard_mask;
    begin
        queue_guard_mask = 32'h0000_0001 << ai_accel_csr_access_helper::P27_QUEUE_MEMORY_GUARD_ERROR_BIT;
        host_rt_mem_guard_capture_snapshot(snap, label, 1'b1);

        if ((snap.error_status & required_error_mask) != required_error_mask) begin
            `uvm_fatal("P27_GUARD/EXPECTED_ERROR_MISSING",
                $sformatf("%s: required guard error mask 0x%08h missing, actual=0x%08h detail=0x%08h domain=%s",
                    label,
                    required_error_mask,
                    snap.error_status,
                    snap.error_detail,
                    host_rt_mem_guard_domain_name(snap.error_domain)))
        end

        if (expected_domain != 32'h0000_0000) begin
            if ((snap.error_domain != expected_domain) && (snap.error_detail[15:8] != expected_domain[7:0])) begin
                `uvm_fatal("P27_GUARD/DOMAIN_MISMATCH",
                    $sformatf("%s: expected domain %s(%0d), actual domain=%s(%0d), detail=0x%08h",
                        label,
                        host_rt_mem_guard_domain_name(expected_domain),
                        expected_domain,
                        host_rt_mem_guard_domain_name(snap.error_domain),
                        snap.error_domain,
                        snap.error_detail))
            end
        end

        if (expected_detail != 8'h00) begin
            if ((snap.error_detail[7:0] != expected_detail) && (snap.queue_error_detail[7:0] != expected_detail)) begin
                `uvm_fatal("P27_GUARD/DETAIL_MISMATCH",
                    $sformatf("%s: expected detail %s(0x%02h), guard_detail=0x%08h queue_detail=0x%08h",
                        label,
                        host_rt_mem_guard_detail_name(expected_detail),
                        expected_detail,
                        snap.error_detail,
                        snap.queue_error_detail))
            end
        end

        if ((snap.queue_error_status & queue_guard_mask) == 32'h0000_0000) begin
            `uvm_fatal("P27_GUARD/QUEUE_ERROR_MISSING",
                $sformatf("%s: queue MEMORY_GUARD_ERROR bit missing: queue_error=0x%08h expected_mask=0x%08h",
                    label,
                    snap.queue_error_status,
                    queue_guard_mask))
        end

        `uvm_info("P27_GUARD/EXPECTED_ERROR_PASS",
            $sformatf("%s: expected guard error observed error=0x%08h domain=%s detail=%s queue_error=0x%08h",
                label,
                snap.error_status,
                host_rt_mem_guard_domain_name(expected_domain),
                host_rt_mem_guard_detail_name(expected_detail),
                snap.queue_error_status),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_mem_guard_clear_for_reuse(
        input bit    clear_queue_error = 1'b1,
        input bit    clear_event_pending = 1'b1,
        input string label = "host_rt_mem_guard_clear_for_reuse"
    );
    begin
        check_ready(label);
        host_rt_mem_guard_clear_all({label, " guard_clear"});

        if (clear_queue_error) begin
            host_rt_lifecycle_clear_queue_error_and_reject({label, " queue_error_clear"});
        end

        if (clear_event_pending) begin
            host_rt_lifecycle_clear_all_events_and_counters({label, " event_clear"});
        end

        `uvm_info("P27_GUARD/REUSE_CLEAR_PASS",
            $sformatf("%s: guard/queue/event state cleared for reuse", label),
            UVM_MEDIUM)
    end
    endtask


    // ------------------------------------------------------------
    // P28C event coalescing / interrupt moderation helper extension
    // ------------------------------------------------------------
    function automatic logic [31:0] host_rt_event_mod_control_value(
        input bit moderation_enable       = 1'b1,
        input bit cq_threshold_enable     = 1'b0,
        input bit moderation_timer_enable = 1'b0,
        input bit retrigger_on_nonempty   = 1'b1
    );
        logic [31:0] value;
    begin
        value = 32'h0000_0000;
        value[ai_accel_csr_access_helper::EVENT_MOD_CONTROL_ENABLE]             = moderation_enable;
        value[ai_accel_csr_access_helper::EVENT_MOD_CONTROL_THRESHOLD_ENABLE]   = cq_threshold_enable;
        value[ai_accel_csr_access_helper::EVENT_MOD_CONTROL_TIMER_ENABLE]       = moderation_timer_enable;
        value[ai_accel_csr_access_helper::EVENT_MOD_CONTROL_RETRIGGER_NONEMPTY] = retrigger_on_nonempty;
        return value;
    end
    endfunction

    function automatic logic [31:0] host_rt_event_mod_completion_mask(
        input bit include_queue_completed = 1'b1,
        input bit include_cq_not_empty    = 1'b1,
        input bit include_threshold       = 1'b1,
        input bit include_timer           = 1'b1
    );
        logic [31:0] mask;
    begin
        mask = 32'h0000_0000;
        if (include_queue_completed) begin
            mask |= event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_COMPLETED);
        end
        if (include_cq_not_empty) begin
            mask |= event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_NOT_EMPTY);
        end
        if (include_threshold) begin
            mask |= event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_THRESHOLD);
        end
        if (include_timer) begin
            mask |= event_bit(ai_accel_csr_access_helper::P28_EVENT_CQ_MOD_TIMER);
        end
        return mask & ai_accel_csr_access_helper::EVENT_VALID_MASK;
    end
    endfunction

    function automatic string host_rt_event_mod_release_name(input logic [7:0] cause);
    begin
        case (cause)
            ai_accel_csr_access_helper::P28_MOD_RELEASE_NONE:      return "NONE";
            ai_accel_csr_access_helper::P28_MOD_RELEASE_THRESHOLD: return "THRESHOLD";
            ai_accel_csr_access_helper::P28_MOD_RELEASE_TIMER:     return "TIMER";
            ai_accel_csr_access_helper::P28_MOD_RELEASE_IMMEDIATE: return "IMMEDIATE_COMPAT";
            ai_accel_csr_access_helper::P28_MOD_RELEASE_URGENT:    return "URGENT_BYPASS";
            ai_accel_csr_access_helper::P28_MOD_RELEASE_REARM:     return "REARM_NONEMPTY";
            default: return $sformatf("RELEASE_0x%02h", cause);
        endcase
    end
    endfunction

    function automatic logic [7:0] host_rt_event_mod_status_cq_occ(input logic [31:0] mod_status);
    begin
        return mod_status[ai_accel_csr_access_helper::EVENT_MOD_STATUS_CQ_OCC_MSB:
                          ai_accel_csr_access_helper::EVENT_MOD_STATUS_CQ_OCC_LSB];
    end
    endfunction

    function automatic logic [7:0] host_rt_event_mod_status_unnotified(input logic [31:0] mod_status);
    begin
        return mod_status[ai_accel_csr_access_helper::EVENT_MOD_STATUS_UNNOTIFIED_MSB:
                          ai_accel_csr_access_helper::EVENT_MOD_STATUS_UNNOTIFIED_LSB];
    end
    endfunction

    function automatic logic [7:0] host_rt_event_mod_debug_release_cause(input logic [31:0] mod_debug);
    begin
        return mod_debug[ai_accel_csr_access_helper::EVENT_MOD_DEBUG_CAUSE_MSB:
                         ai_accel_csr_access_helper::EVENT_MOD_DEBUG_CAUSE_LSB];
    end
    endfunction

    function automatic logic [7:0] host_rt_event_mod_debug_release_count(input logic [31:0] mod_debug);
    begin
        return mod_debug[ai_accel_csr_access_helper::EVENT_MOD_DEBUG_RELEASE_COUNT_MSB:
                         ai_accel_csr_access_helper::EVENT_MOD_DEBUG_RELEASE_COUNT_LSB];
    end
    endfunction

    function automatic logic [7:0] host_rt_event_mod_debug_threshold_count(input logic [31:0] mod_debug);
    begin
        return mod_debug[ai_accel_csr_access_helper::EVENT_MOD_DEBUG_THRESHOLD_COUNT_MSB:
                         ai_accel_csr_access_helper::EVENT_MOD_DEBUG_THRESHOLD_COUNT_LSB];
    end
    endfunction

    function automatic logic [7:0] host_rt_event_mod_debug_timer_count(input logic [31:0] mod_debug);
    begin
        return mod_debug[ai_accel_csr_access_helper::EVENT_MOD_DEBUG_TIMER_COUNT_MSB:
                         ai_accel_csr_access_helper::EVENT_MOD_DEBUG_TIMER_COUNT_LSB];
    end
    endfunction

    task automatic host_rt_event_mod_default_cfg(
        output p28_event_mod_cfg_t cfg,
        input  bit                 moderation_enable       = 1'b1,
        input  bit                 cq_threshold_enable     = 1'b1,
        input  bit                 moderation_timer_enable = 1'b0,
        input  bit                 retrigger_on_nonempty   = 1'b1,
        input  logic [31:0]        cq_threshold            = 32'h0000_0002,
        input  logic [31:0]        timer_limit             = 32'h0000_0000,
        input  logic [31:0]        event_enable_mask       = 32'h0000_0000,
        input  bit                 global_irq_enable       = 1'b1,
        input  bit                 capture_snapshot        = 1'b1
    );
    begin
        cfg.mod_control       = host_rt_event_mod_control_value(
                                    moderation_enable,
                                    cq_threshold_enable,
                                    moderation_timer_enable,
                                    retrigger_on_nonempty);
        cfg.event_enable_mask = event_enable_mask;
        cfg.event_control     = 32'h0000_0000;
        cfg.event_control[ai_accel_csr_access_helper::EVENT_CONTROL_GLOBAL_IRQ_ENABLE] = global_irq_enable;
        cfg.event_control[ai_accel_csr_access_helper::EVENT_CONTROL_CAPTURE_SNAPSHOT]  = capture_snapshot;
        cfg.cq_threshold      = cq_threshold;
        cfg.timer_limit       = timer_limit;
    end
    endtask

    task automatic host_rt_event_mod_program(
        input p28_event_mod_cfg_t cfg,
        input string              label = "host_rt_event_mod_program"
    );
    begin
        check_ready(label);

        // Program with moderation disabled first so threshold/timer updates do
        // not race a live coalescing session in future RTL.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_MOD_CONTROL, 32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_CQ_THRESHOLD, cfg.cq_threshold);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_MOD_TIMER_LIMIT, cfg.timer_limit);
        arm_events(cfg.event_enable_mask, cfg.cq_threshold, cfg.event_control);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_MOD_CONTROL, cfg.mod_control);

        `uvm_info("P28_MOD/PROGRAM",
            $sformatf("%s: mod_control=0x%08h event_enable=0x%08h event_control=0x%08h cq_threshold=%0d timer_limit=%0d",
                label,
                cfg.mod_control,
                cfg.event_enable_mask & ai_accel_csr_access_helper::EVENT_VALID_MASK,
                cfg.event_control,
                cfg.cq_threshold,
                cfg.timer_limit),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_event_mod_disable(input string label = "host_rt_event_mod_disable");
    begin
        check_ready(label);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_MOD_CONTROL, 32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_MOD_TIMER_LIMIT, 32'h0000_0000);
        `uvm_info("P28_MOD/DISABLE",
            $sformatf("%s: event moderation disabled", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_event_mod_capture_snapshot(output p28_event_mod_snapshot_t snap);
    begin
        check_ready("host_rt_event_mod_capture_snapshot");

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_STATUS,          snap.event_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_PENDING,         snap.event_pending);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_ENABLE,          snap.event_enable);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_CONTROL,         snap.event_control);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_LAST_CAUSE,      snap.event_last_cause);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_COUNT,           snap.event_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_IRQ_COUNT,       snap.event_irq_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_CQ_THRESHOLD,    snap.event_cq_threshold);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_MOD_CONTROL,     snap.mod_control);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_MOD_STATUS,      snap.mod_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_MOD_TIMER_LIMIT, snap.mod_timer_limit);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_MOD_DEBUG,       snap.mod_debug);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS,          snap.queue_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS,     snap.queue_done_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,    snap.queue_error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS,   snap.queue_reject_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,         snap.sq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,         snap.sq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,         snap.cq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,         snap.cq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_OCCUPANCY,    snap.sq_occupancy);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY,    snap.cq_occupancy);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_SPACE,        snap.cq_space);
    end
    endtask

    function automatic void host_rt_event_mod_log_snapshot(
        input string                   label,
        input p28_event_mod_snapshot_t snap,
        input uvm_verbosity            verbosity = UVM_MEDIUM
    );
        logic [7:0] cause;
    begin
        cause = host_rt_event_mod_debug_release_cause(snap.mod_debug);
        `uvm_info("P28_MOD/SNAPSHOT",
            $sformatf("%s: pending=0x%08h status=0x%08h enable=0x%08h event_count=%0d irq_count=%0d threshold=%0d mod_ctrl=0x%08h mod_status=0x%08h cq_occ=%0d unnotified=%0d timer_limit=%0d release=%s count=%0d th_count=%0d timer_count=%0d SQ(h/t)=%0d/%0d CQ(h/t/occ/space)=%0d/%0d/%0d/%0d q_error=0x%08h",
                label,
                snap.event_pending,
                snap.event_status,
                snap.event_enable,
                snap.event_count,
                snap.event_irq_count,
                snap.event_cq_threshold,
                snap.mod_control,
                snap.mod_status,
                host_rt_event_mod_status_cq_occ(snap.mod_status),
                host_rt_event_mod_status_unnotified(snap.mod_status),
                snap.mod_timer_limit,
                host_rt_event_mod_release_name(cause),
                host_rt_event_mod_debug_release_count(snap.mod_debug),
                host_rt_event_mod_debug_threshold_count(snap.mod_debug),
                host_rt_event_mod_debug_timer_count(snap.mod_debug),
                snap.sq_head,
                snap.sq_tail,
                snap.cq_head,
                snap.cq_tail,
                snap.cq_occupancy,
                snap.cq_space,
                snap.queue_error_status),
            verbosity)
    end
    endfunction

    task automatic host_rt_event_mod_snapshot_and_log(
        input  string                   label,
        output p28_event_mod_snapshot_t snap,
        input  uvm_verbosity            verbosity = UVM_MEDIUM
    );
    begin
        host_rt_event_mod_capture_snapshot(snap);
        host_rt_event_mod_log_snapshot(label, snap, verbosity);
    end
    endtask

    task automatic host_rt_event_mod_wait_notification(
        input  logic [31:0]             required_mask,
        output p28_event_mod_snapshot_t snap,
        input  string                   label = "host_rt_event_mod_wait_notification",
        input  int unsigned             timeout_cycles = P28_DEFAULT_MOD_TIMEOUT_CYCLES,
        input  bit                      require_irq_summary = 1'b1
    );
        p23_event_snapshot_t event_snap;
    begin
        wait_events(required_mask, event_snap, timeout_cycles, require_irq_summary);
        host_rt_event_mod_snapshot_and_log({label, " snapshot"}, snap, UVM_MEDIUM);

        if ((snap.event_pending & required_mask) == 32'h0000_0000) begin
            `uvm_fatal("P28_MOD/EVENT_MISSING",
                $sformatf("%s: required event mask missing after wait required=0x%08h pending=0x%08h",
                    label,
                    required_mask,
                    snap.event_pending))
        end

        `uvm_info("P28_MOD/EVENT_PASS",
            $sformatf("%s: observed coalesced event mask required=0x%08h pending=0x%08h irq_count=%0d",
                label,
                required_mask,
                snap.event_pending,
                snap.event_irq_count),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_event_mod_expect_no_irq_delta(
        input p28_event_mod_snapshot_t before_snap,
        input p28_event_mod_snapshot_t after_snap,
        input string                   label = "host_rt_event_mod_expect_no_irq_delta"
    );
    begin
        if (after_snap.event_irq_count != before_snap.event_irq_count) begin
            `uvm_fatal("P28_MOD/IRQ_DELTA",
                $sformatf("%s: unexpected IRQ count delta before=%0d after=%0d",
                    label,
                    before_snap.event_irq_count,
                    after_snap.event_irq_count))
        end

        if (after_snap.event_status[ai_accel_csr_access_helper::EVENT_STATUS_EVENT_IRQ_OUT] === 1'b1) begin
            `uvm_fatal("P28_MOD/IRQ_OUT",
                $sformatf("%s: event IRQ asserted when no IRQ delta was expected: event_status=0x%08h",
                    label,
                    after_snap.event_status))
        end

        `uvm_info("P28_MOD/NO_EARLY_IRQ_PASS",
            $sformatf("%s: no IRQ count delta observed irq_count=%0d",
                label,
                after_snap.event_irq_count),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_event_mod_expect_pending(
        input p28_event_mod_snapshot_t snap,
        input logic [31:0]             required_mask,
        input logic [31:0]             forbidden_mask = 32'h0000_0000,
        input string                   label = "host_rt_event_mod_expect_pending"
    );
    begin
        required_mask  &= ai_accel_csr_access_helper::EVENT_VALID_MASK;
        forbidden_mask &= ai_accel_csr_access_helper::EVENT_VALID_MASK;

        if ((snap.event_pending & required_mask) != required_mask) begin
            `uvm_fatal("P28_MOD/PENDING_MISSING",
                $sformatf("%s: pending missing required bits required=0x%08h pending=0x%08h",
                    label,
                    required_mask,
                    snap.event_pending))
        end

        if ((snap.event_pending & forbidden_mask) != 32'h0000_0000) begin
            `uvm_fatal("P28_MOD/PENDING_FORBIDDEN",
                $sformatf("%s: forbidden pending bits observed forbidden=0x%08h pending=0x%08h",
                    label,
                    forbidden_mask,
                    snap.event_pending))
        end

        `uvm_info("P28_MOD/PENDING_PASS",
            $sformatf("%s: pending check PASS required=0x%08h forbidden=0x%08h pending=0x%08h",
                label,
                required_mask,
                forbidden_mask,
                snap.event_pending),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_event_mod_expect_release_cause(
        input p28_event_mod_snapshot_t snap,
        input logic [7:0]              expected_cause,
        input string                   label = "host_rt_event_mod_expect_release_cause"
    );
        logic [7:0] cause;
    begin
        cause = host_rt_event_mod_debug_release_cause(snap.mod_debug);
        if (cause != expected_cause) begin
            `uvm_fatal("P28_MOD/RELEASE_CAUSE",
                $sformatf("%s: release cause mismatch expected=%s(0x%02h) actual=%s(0x%02h) debug=0x%08h",
                    label,
                    host_rt_event_mod_release_name(expected_cause),
                    expected_cause,
                    host_rt_event_mod_release_name(cause),
                    cause,
                    snap.mod_debug))
        end

        `uvm_info("P28_MOD/RELEASE_CAUSE_PASS",
            $sformatf("%s: release cause PASS %s(0x%02h)",
                label,
                host_rt_event_mod_release_name(cause),
                cause),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_event_mod_expect_cq_occupancy(
        input p28_event_mod_snapshot_t snap,
        input int unsigned             expected_min,
        input int unsigned             expected_max,
        input string                   label = "host_rt_event_mod_expect_cq_occupancy"
    );
    begin
        if ((snap.cq_occupancy < expected_min) || (snap.cq_occupancy > expected_max)) begin
            `uvm_fatal("P28_MOD/CQ_OCC",
                $sformatf("%s: CQ occupancy outside expected range min=%0d max=%0d actual=%0d head=%0d tail=%0d",
                    label,
                    expected_min,
                    expected_max,
                    snap.cq_occupancy,
                    snap.cq_head,
                    snap.cq_tail))
        end

        `uvm_info("P28_MOD/CQ_OCC_PASS",
            $sformatf("%s: CQ occupancy PASS actual=%0d range=[%0d,%0d]",
                label,
                snap.cq_occupancy,
                expected_min,
                expected_max),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_event_mod_consume_cq_batch(
        input  p23_queue_cfg_t       cfg,
        input  p28_event_mod_snapshot_t snap,
        input  int unsigned          max_count,
        output p28_cq_batch_result_t result,
        input  int                   expected_count = -1,
        input  bit                   clear_commit_word = 1'b1,
        input  string                label = "host_rt_event_mod_consume_cq_batch",
        input  int unsigned          timeout_cycles = P28_DEFAULT_MOD_TIMEOUT_CYCLES
    );
        p23_cq_record_t rec;
        int unsigned visible;
        int unsigned consume_count;
        int unsigned cq_idx;
        int unsigned cq_addr;
    begin
        check_ready(label);

        result.start_cq_head    = 32'h0000_0000;
        result.start_cq_tail    = 32'h0000_0000;
        result.visible_count    = 32'h0000_0000;
        result.consumed_count   = 32'h0000_0000;
        result.final_cq_head    = 32'h0000_0000;
        result.first_commit_word= 32'h0000_0000;
        result.last_commit_word = 32'h0000_0000;
        result.first_user_tag   = 32'h0000_0000;
        result.last_user_tag    = 32'h0000_0000;

        result.start_cq_head = snap.cq_head;
        result.start_cq_tail = snap.cq_tail;

        if (snap.cq_tail < snap.cq_head) begin
            `uvm_fatal("P28_MOD/CQ_POINTER_ORDER",
                $sformatf("%s: CQ_TAIL < CQ_HEAD is unsupported in monotonic no-wrap tests: head=%0d tail=%0d",
                    label,
                    snap.cq_head,
                    snap.cq_tail))
        end

        visible = snap.cq_tail - snap.cq_head;
        result.visible_count = visible;

        if (max_count == 0) begin
            consume_count = visible;
        end else if (visible > max_count) begin
            consume_count = max_count;
        end else begin
            consume_count = visible;
        end

        if ((expected_count >= 0) && (consume_count != expected_count)) begin
            `uvm_fatal("P28_MOD/BATCH_COUNT",
                $sformatf("%s: batch consume count mismatch expected=%0d actual=%0d visible=%0d max=%0d",
                    label,
                    expected_count,
                    consume_count,
                    visible,
                    max_count))
        end

        for (int unsigned i = 0; i < consume_count; i++) begin
            wait_cq_commit(cfg, snap.cq_head + i, rec, timeout_cycles);

            if (rec.commit_word[0] != 1'b1) begin
                `uvm_fatal("P28_MOD/CQ_INVALID",
                    $sformatf("%s: CQ[%0d] commit valid bit is not set: commit=0x%08h",
                        label,
                        snap.cq_head + i,
                        rec.commit_word))
            end

            if (i == 0) begin
                result.first_commit_word = rec.commit_word;
                result.first_user_tag    = rec.first_user_tag;
            end
            result.last_commit_word = rec.commit_word;
            result.last_user_tag    = rec.last_user_tag;

            if (clear_commit_word) begin
                cq_idx  = (snap.cq_head + i) % cfg.cq_depth;
                cq_addr = cfg.cq_base + (cq_idx * cfg.cq_stride);
                write_dst_word_le(cq_addr, 32'h0000_0000);
            end
        end

        result.consumed_count = consume_count;
        result.final_cq_head  = snap.cq_head + consume_count;

        // P28 batch helper advances CQ_HEAD once after the batch, matching a
        // host driver that reads N CQ records and publishes one consumer update.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD, result.final_cq_head);

        `uvm_info("P28_MOD/BATCH_CONSUME_PASS",
            $sformatf("%s: consumed batch visible=%0d consumed=%0d CQ_HEAD %0d->%0d first_tag=0x%08h last_tag=0x%08h clear_commit=%0d",
                label,
                result.visible_count,
                result.consumed_count,
                result.start_cq_head,
                result.final_cq_head,
                result.first_user_tag,
                result.last_user_tag,
                clear_commit_word),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_event_mod_ack_and_rearm(
        input logic [31:0] event_mask,
        input logic [31:0] event_enable_mask,
        input logic [31:0] cq_threshold,
        input bit          global_irq_enable = 1'b1,
        input bit          capture_snapshot = 1'b1,
        input string       label = "host_rt_event_mod_ack_and_rearm"
    );
    begin
        check_ready(label);
        host_rt_lifecycle_clear_handled_events(event_mask, {label, " clear"});
        host_rt_lifecycle_rearm_events(
            event_enable_mask,
            global_irq_enable,
            cq_threshold,
            capture_snapshot,
            {label, " rearm"});

        `uvm_info("P28_MOD/REARM_PASS",
            $sformatf("%s: cleared mask=0x%08h rearmed mask=0x%08h threshold=%0d",
                label,
                event_mask & ai_accel_csr_access_helper::EVENT_VALID_MASK,
                event_enable_mask & ai_accel_csr_access_helper::EVENT_VALID_MASK,
                cq_threshold),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_event_mod_expect_urgent_bypass(
        input p28_event_mod_snapshot_t snap,
        input logic [31:0]             urgent_mask,
        input string                   label = "host_rt_event_mod_expect_urgent_bypass"
    );
    begin
        urgent_mask &= ai_accel_csr_access_helper::EVENT_VALID_MASK;
        if ((snap.event_pending & urgent_mask) == 32'h0000_0000) begin
            `uvm_fatal("P28_MOD/URGENT_MISSING",
                $sformatf("%s: urgent bypass event missing urgent_mask=0x%08h pending=0x%08h",
                    label,
                    urgent_mask,
                    snap.event_pending))
        end

        if (snap.event_status[ai_accel_csr_access_helper::EVENT_STATUS_EVENT_IRQ_OUT] !== 1'b1) begin
            `uvm_fatal("P28_MOD/URGENT_IRQ",
                $sformatf("%s: urgent bypass pending did not assert IRQ status=0x%08h pending=0x%08h",
                    label,
                    snap.event_status,
                    snap.event_pending))
        end

        `uvm_info("P28_MOD/URGENT_BYPASS_PASS",
            $sformatf("%s: urgent bypass PASS urgent_mask=0x%08h pending=0x%08h status=0x%08h",
                label,
                urgent_mask,
                snap.event_pending,
                snap.event_status),
            UVM_MEDIUM)
    end
    endtask



    // ------------------------------------------------------------
    // P29 telemetry helper primitives
    // ------------------------------------------------------------
    function automatic logic [31:0] host_rt_telem_control_value(
        input bit telemetry_enable        = 1'b1,
        input bit cycle_count_enable      = 1'b1,
        input bit host_cq_consume_enable  = 1'b1,
        input bit event_eff_enable        = 1'b1
    );
        logic [31:0] value;
    begin
        value = 32'h0000_0000;
        value[ai_accel_csr_access_helper::TELEM_CONTROL_ENABLE]                 = telemetry_enable;
        value[ai_accel_csr_access_helper::TELEM_CONTROL_CYCLE_COUNT_ENABLE]     = cycle_count_enable;
        value[ai_accel_csr_access_helper::TELEM_CONTROL_HOST_CQ_CONSUME_ENABLE] = host_cq_consume_enable;
        value[ai_accel_csr_access_helper::TELEM_CONTROL_EVENT_EFF_ENABLE]       = event_eff_enable;
        return value;
    end
    endfunction

    task automatic host_rt_telem_read(
        input  logic [11:0] addr,
        input  string       name,
        output logic [31:0] data,
        input  uvm_verbosity verbosity = UVM_HIGH
    );
    begin
        check_ready("host_rt_telem_read");
        csr.read32_expect_okay(addr, data);
        `uvm_info("P30_ABI/TELEM_READ",
            $sformatf("%s = 0x%08h", name, data),
            verbosity)
    end
    endtask

    task automatic host_rt_telem_clear(input string label = "host_rt_telem_clear");
    begin
        check_ready(label);
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_TELEM_COMMAND,
            ai_accel_csr_access_helper::TELEM_CMD_CLEAR_COUNTERS_VALUE);
        repeat (2) @(posedge ctrl_vif.clk);

        `uvm_info("P30_ABI/TELEM_CLEAR",
            $sformatf("%s: issued CLEAR_TELEMETRY_COUNTERS", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_telem_enable(
        input logic [31:0] control_value = ai_accel_csr_access_helper::TELEM_ENABLE_ALL_VALUE,
        input string       label = "host_rt_telem_enable"
    );
        logic [31:0] status;
    begin
        check_ready(label);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_CONTROL, control_value);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_STATUS, status);

        if (control_value[ai_accel_csr_access_helper::TELEM_CONTROL_ENABLE] &&
            !status[ai_accel_csr_access_helper::TELEM_STATUS_ENABLED]) begin
            `uvm_fatal("P30_ABI/TELEM_ENABLE",
                $sformatf("%s: telemetry enable did not mirror into status: control=0x%08h status=0x%08h",
                    label,
                    control_value,
                    status))
        end

        `uvm_info("P30_ABI/TELEM_ENABLE",
            $sformatf("%s: telemetry control=0x%08h status=0x%08h",
                label,
                control_value,
                status),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_telem_disable(input string label = "host_rt_telem_disable");
    begin
        check_ready(label);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_CONTROL, 32'h0000_0000);
        `uvm_info("P30_ABI/TELEM_DISABLE",
            $sformatf("%s: telemetry disabled", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_telem_capture_snapshot(
        output p29_runtime_telem_snapshot_t snap,
        input  string                       label = "host_rt_telem_capture_snapshot"
    );
    begin
        check_ready(label);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_VERSION,                  snap.version);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_STATUS,                   snap.status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_CONTROL,                  snap.control);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_QUEUE_START_COUNT,        snap.queue_start_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_SQ_ACCEPT_COUNT,          snap.sq_accept_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_CMD_COMPLETE_COUNT,       snap.cmd_complete_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_CQ_COMMIT_COUNT,          snap.cq_commit_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_QUEUE_DRAINED_COUNT,      snap.queue_drained_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_QUEUE_STOPPED_COUNT,      snap.queue_stopped_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_QUEUE_ERROR_COUNT,        snap.queue_error_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_CQ_HEAD_UPDATE_COUNT,     snap.cq_head_update_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_CQ_CONSUMED_COUNT,        snap.cq_consumed_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_MAX_CQ_BATCH_SIZE,        snap.max_cq_batch_size);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_EVENT_CAPTURE_COUNT,      snap.event_capture_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_IRQ_ELIGIBLE_COUNT,       snap.irq_eligible_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_COMPLETION_EVENT_COUNT,   snap.completion_event_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_COALESCED_RELEASE_COUNT,  snap.coalesced_release_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_THRESHOLD_RELEASE_COUNT,  snap.threshold_release_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_TIMER_RELEASE_COUNT,      snap.timer_release_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_URGENT_BYPASS_COUNT,      snap.urgent_bypass_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_CQ_FULL_STALL_COUNT,      snap.cq_full_stall_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_CQ_SPACE_RECOVERED_COUNT, snap.cq_space_recovered_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_TIMEOUT_ERROR_COUNT,      snap.timeout_error_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_MEM_GUARD_ERROR_COUNT,    snap.mem_guard_error_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_STOP_QUEUE_REQUEST_COUNT, snap.stop_queue_request_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_QUEUE_ENABLED_CYCLES,     snap.queue_enabled_cycles);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_QUEUE_BUSY_CYCLES,        snap.queue_busy_cycles);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_QUEUE_IDLE_CYCLES,        snap.queue_idle_cycles);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_QUEUE_STALLED_CYCLES,     snap.queue_stalled_cycles);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_CQ_FULL_STALL_CYCLES,     snap.cq_full_stall_cycles);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_TELEM_LOWER_WAIT_CYCLES,        snap.lower_wait_cycles);
    end
    endtask

    function automatic void host_rt_telem_log_snapshot(
        input string                       label,
        input p29_runtime_telem_snapshot_t snap,
        input uvm_verbosity                verbosity = UVM_MEDIUM
    );
        `uvm_info("P30_ABI/TELEM_SNAPSHOT",
            $sformatf("%s: ctrl=0x%08h status=0x%08h start=%0d accept=%0d complete=%0d cq_commit=%0d drained=%0d stopped=%0d error=%0d cq_update=%0d cq_consumed=%0d max_batch=%0d event=%0d irq=%0d completion_event=%0d coal=%0d threshold=%0d timer=%0d urgent=%0d stall=%0d recovered=%0d timeout=%0d guard=%0d stop=%0d cycles(en/busy/idle/stall/cqfull/lower)=%0d/%0d/%0d/%0d/%0d/%0d",
                label,
                snap.control,
                snap.status,
                snap.queue_start_count,
                snap.sq_accept_count,
                snap.cmd_complete_count,
                snap.cq_commit_count,
                snap.queue_drained_count,
                snap.queue_stopped_count,
                snap.queue_error_count,
                snap.cq_head_update_count,
                snap.cq_consumed_count,
                snap.max_cq_batch_size,
                snap.event_capture_count,
                snap.irq_eligible_count,
                snap.completion_event_count,
                snap.coalesced_release_count,
                snap.threshold_release_count,
                snap.timer_release_count,
                snap.urgent_bypass_count,
                snap.cq_full_stall_count,
                snap.cq_space_recovered_count,
                snap.timeout_error_count,
                snap.mem_guard_error_count,
                snap.stop_queue_request_count,
                snap.queue_enabled_cycles,
                snap.queue_busy_cycles,
                snap.queue_idle_cycles,
                snap.queue_stalled_cycles,
                snap.cq_full_stall_cycles,
                snap.lower_wait_cycles),
            verbosity)
    endfunction

    task automatic host_rt_telem_snapshot_and_log(
        output p29_runtime_telem_snapshot_t snap,
        input  string                       label = "host_rt_telem_snapshot_and_log",
        input  uvm_verbosity                verbosity = UVM_MEDIUM
    );
    begin
        host_rt_telem_capture_snapshot(snap, label);
        host_rt_telem_log_snapshot(label, snap, verbosity);
    end
    endtask

    task automatic host_rt_telem_check_selected_zero(
        input string label = "host_rt_telem_check_selected_zero"
    );
        p29_runtime_telem_snapshot_t snap;
    begin
        host_rt_telem_capture_snapshot(snap, label);
        if ((snap.queue_start_count        != 32'h0000_0000) ||
            (snap.sq_accept_count          != 32'h0000_0000) ||
            (snap.cmd_complete_count       != 32'h0000_0000) ||
            (snap.cq_commit_count          != 32'h0000_0000) ||
            (snap.cq_head_update_count     != 32'h0000_0000) ||
            (snap.cq_consumed_count        != 32'h0000_0000) ||
            (snap.event_capture_count      != 32'h0000_0000) ||
            (snap.irq_eligible_count       != 32'h0000_0000) ||
            (snap.cq_full_stall_count      != 32'h0000_0000) ||
            (snap.cq_space_recovered_count != 32'h0000_0000) ||
            (snap.queue_stalled_cycles     != 32'h0000_0000) ||
            (snap.cq_full_stall_cycles     != 32'h0000_0000)) begin
            `uvm_fatal("P30_ABI/TELEM_NOT_ZERO",
                $sformatf("%s: selected telemetry counters not zero", label))
        end

        `uvm_info("P30_ABI/TELEM_ZERO_PASS",
            $sformatf("%s: selected telemetry counters are zero", label),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // P30 driver-facing runtime ABI composite helpers
    // ------------------------------------------------------------
    task automatic host_rt_abi_default_cfg(
        output p30_driver_runtime_abi_cfg_t cfg,
        input  p23_queue_cfg_t              queue_cfg,
        input  logic [31:0]                 event_enable_mask,
        input  p27_guard_cfg_t              guard_cfg,
        input  p28_event_mod_cfg_t          event_mod_cfg,
        input  bit                          enable_guard = 1'b0,
        input  bit                          enable_event_moderation = 1'b0,
        input  bit                          enable_telemetry = 1'b1,
        input  logic [31:0]                 telemetry_control = ai_accel_csr_access_helper::TELEM_ENABLE_ALL_VALUE,
        input  bit                          clear_queue_memory = 1'b1,
        input  bit                          clear_lower_sticky = 1'b1
    );
    begin
        cfg.queue_cfg              = queue_cfg;
        cfg.guard_cfg              = guard_cfg;
        cfg.event_mod_cfg          = event_mod_cfg;
        cfg.event_enable_mask      = event_enable_mask & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        cfg.event_cq_threshold     = 32'h0000_0000;
        cfg.event_control          = P23_EVENT_CONTROL_IRQ_SNAPSHOT;
        cfg.telemetry_control      = telemetry_control;
        cfg.enable_guard           = enable_guard;
        cfg.enable_event_moderation= enable_event_moderation;
        cfg.enable_telemetry       = enable_telemetry;
        cfg.clear_queue_memory     = clear_queue_memory;
        cfg.clear_lower_sticky     = clear_lower_sticky;
    end
    endtask

    task automatic host_rt_abi_cold_boot_init(
        input p30_driver_runtime_abi_cfg_t cfg,
        input string                       label = "host_rt_abi_cold_boot_init"
    );
        p23_queue_cfg_t programmed_queue_cfg;
    begin
        check_ready(label);
        programmed_queue_cfg = cfg.queue_cfg;

        host_rt_lifecycle_wait_idle({label, " wait_idle"}, P30_DEFAULT_ABI_TIMEOUT_CYCLES, 1'b1);
        host_rt_lifecycle_clear_queue_all_sticky(1'b1, {label, " queue_clear"});
        if (cfg.clear_lower_sticky) begin
            host_rt_lifecycle_clear_lower_sticky({label, " lower_clear"});
        end

        host_rt_event_mod_disable({label, " moderation_disable"});
        host_rt_lifecycle_clear_all_events_and_counters({label, " event_clear"});
        host_rt_mem_guard_clear_all({label, " guard_clear"});
        host_rt_telem_clear({label, " telemetry_clear"});

        // Driver cold-boot initialization owns a fresh queue counter epoch.
        // Reset hardware-owned SQ_HEAD / CQ_TAIL architecturally before the
        // host-owned queue configuration is programmed.
        host_rt_lifecycle_reset_pointers_idle({label, " reset_ptr"});
        host_rt_lifecycle_make_zero_epoch_cfg(programmed_queue_cfg, cfg.queue_cfg);

        if (cfg.clear_queue_memory) begin
            clear_queue_memory(programmed_queue_cfg);
        end

        if (cfg.enable_guard) begin
            host_rt_mem_guard_program_regions(cfg.guard_cfg, {label, " guard_program"});
        end else begin
            host_rt_mem_guard_disable({label, " guard_disable"});
        end

        program_queue(programmed_queue_cfg);

        if (cfg.enable_event_moderation) begin
            host_rt_event_mod_program(cfg.event_mod_cfg, {label, " moderation_program"});
        end else begin
            arm_events(cfg.event_enable_mask, cfg.event_cq_threshold, cfg.event_control);
        end

        if (cfg.enable_telemetry) begin
            host_rt_telem_enable(cfg.telemetry_control, {label, " telemetry_enable"});
        end

        host_rt_lifecycle_check_clean_idle({label, " clean_check"}, 1'b1, 1'b1, 1'b1);

        `uvm_info("P30_ABI/INIT_PASS",
            $sformatf("%s: driver ABI cold-boot init PASS guard=%0d moderation=%0d telemetry=%0d SQ(base=0x%08h depth=%0d) CQ(base=0x%08h depth=%0d) event_mask=0x%08h",
                label,
                cfg.enable_guard,
                cfg.enable_event_moderation,
                cfg.enable_telemetry,
                cfg.queue_cfg.sq_base,
                cfg.queue_cfg.sq_depth,
                cfg.queue_cfg.cq_base,
                cfg.queue_cfg.cq_depth,
                cfg.event_enable_mask),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_abi_submit_command(
        input p30_driver_runtime_abi_cfg_t cfg,
        input int unsigned                 entry_index,
        input p23_sq_cmd_t                 cmd,
        input logic [31:0]                 new_tail,
        input string                       label = "host_rt_abi_submit_command"
    );
    begin
        check_ready(label);
        write_sq_command(cfg.queue_cfg, entry_index, cmd, 1'b1);
        ring_sq_tail(new_tail);
        `uvm_info("P30_ABI/SUBMIT",
            $sformatf("%s: SQ[%0d] submitted tag=0x%08h new_tail=%0d",
                label,
                entry_index,
                cmd.user_tag,
                new_tail),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_abi_start_queue(input string label = "host_rt_abi_start_queue");
    begin
        start_queue();
        `uvm_info("P30_ABI/START_QUEUE",
            $sformatf("%s: START_QUEUE issued", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_abi_consume_one_cq(
        input  p30_driver_runtime_abi_cfg_t cfg,
        input  int unsigned                 entry_index,
        output p23_cq_record_t              rec,
        input  bit                          clear_cq_commit = 1'b1,
        input  string                       label = "host_rt_abi_consume_one_cq"
    );
    begin
        wait_cq_commit(cfg.queue_cfg, entry_index, rec, P30_DEFAULT_ABI_TIMEOUT_CYCLES);
        consume_cq_entry(cfg.queue_cfg, entry_index, clear_cq_commit);
        `uvm_info("P30_ABI/CQ_CONSUME",
            $sformatf("%s: consumed CQ[%0d] commit=0x%08h tag=0x%08h",
                label,
                entry_index,
                rec.commit_word,
                rec.first_user_tag),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_abi_ack_and_rearm(
        input p30_driver_runtime_abi_cfg_t cfg,
        input logic [31:0]                 event_mask,
        input string                       label = "host_rt_abi_ack_and_rearm"
    );
    begin
        check_ready(label);
        if (cfg.enable_event_moderation) begin
            host_rt_event_mod_ack_and_rearm(
                event_mask,
                cfg.event_mod_cfg.event_enable_mask,
                cfg.event_mod_cfg.cq_threshold,
                cfg.event_mod_cfg.event_control[ai_accel_csr_access_helper::EVENT_CONTROL_GLOBAL_IRQ_ENABLE],
                cfg.event_mod_cfg.event_control[ai_accel_csr_access_helper::EVENT_CONTROL_CAPTURE_SNAPSHOT],
                label);
        end else begin
            host_rt_lifecycle_clear_handled_events(event_mask, {label, " clear"});
            host_rt_lifecycle_rearm_events(
                cfg.event_enable_mask,
                cfg.event_control[ai_accel_csr_access_helper::EVENT_CONTROL_GLOBAL_IRQ_ENABLE],
                cfg.event_cq_threshold,
                cfg.event_control[ai_accel_csr_access_helper::EVENT_CONTROL_CAPTURE_SNAPSHOT],
                {label, " rearm"});
        end

        `uvm_info("P30_ABI/ACK_REARM_PASS",
            $sformatf("%s: ack/re-arm completed event_mask=0x%08h",
                label,
                event_mask & ai_accel_csr_access_helper::EVENT_VALID_MASK),
            UVM_MEDIUM)
    end
    endtask

    task automatic host_rt_abi_sample_telemetry(
        output p29_runtime_telem_snapshot_t snap,
        input  string                       label = "host_rt_abi_sample_telemetry"
    );
    begin
        host_rt_telem_snapshot_and_log(snap, label, UVM_MEDIUM);
        `uvm_info("P30_ABI/TELEM_SAMPLE_PASS",
            $sformatf("%s: telemetry sample captured", label),
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
