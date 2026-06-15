// File: tb/uvm/test/ai_accel_subsys_csr_event_driven_append_consume_stress_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_EVENT_DRIVEN_APPEND_CONSUME_STRESS_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_EVENT_DRIVEN_APPEND_CONSUME_STRESS_TEST_SV

// ============================================================
// P25D event-driven runtime append + CQ consume timing stress
//
// Scope:
//   - Reuses the validated P21 runtime doorbell / live queue service
//     policy, P22 event notification layer, and P23/P25 host runtime
//     helper model.
//   - Starts a queue session with only SQ[0] visible, then appends
//     SQ[1] while SQ[0] is active by writing SQ[1] and publishing
//     SQ_TAIL=2 without a second START_QUEUE.
//   - Uses CQ_DEPTH=1 to force a command-boundary CQ-full stall after
//     CQ[0] commits and before the runtime-appended SQ[1] can be
//     accepted.
//   - Delays host CQ consume / CQ_HEAD update while the queue is stalled,
//     then consumes CQ[0], verifies CQ-space recovery, lets SQ[1]
//     complete into the wrapped physical CQ slot, consumes it, W1C-acks
//     all accumulated event bits, and proves the queue is reusable.
//
// This is UVM/helper-only validation.  It does not add RTL, CSR map
// changes, SQ/CQ format changes, descriptor-format changes, completion
// record changes, event bits, standalone tops, or datapath changes.
// ============================================================

class ai_accel_subsys_csr_event_driven_append_consume_stress_test
    extends ai_accel_subsys_csr_event_driven_multi_session_stress_test;
    `uvm_component_utils(ai_accel_subsys_csr_event_driven_append_consume_stress_test)

    localparam int unsigned P25D_SQ_BASE       = 32'h0000_0D00;
    localparam int unsigned P25D_CQ_BASE       = 32'h0000_0E00;
    localparam int unsigned P25D_SQ_DEPTH      = 4;
    localparam int unsigned P25D_CQ_DEPTH      = 1;
    localparam int unsigned P25D_ENTRY_STRIDE  = 32'h0000_0040;
    localparam int unsigned P25D_DESC_STRIDE   = 32'h0000_0080;

    localparam int unsigned P25D_DESC_BASE0    = 32'h0000_0300;
    localparam int unsigned P25D_DESC_BASE1    = 32'h0000_0400;

    localparam int unsigned P25D_HOST_DELAY_CYCLES = 23;

    localparam logic [31:0] P25D_QUEUE_CONTROL_DRAIN = 32'h0000_0007;

    localparam logic [31:0] P25D_CMD0_TAG      = 32'hD25D_0000;
    localparam logic [31:0] P25D_CMD1_TAG      = 32'hD25D_0001;

    localparam logic [31:0] P25D_DESC0_TAG0    = 32'hD25D_1000;
    localparam logic [31:0] P25D_DESC0_TAG1    = 32'hD25D_1001;
    localparam logic [31:0] P25D_DESC1_TAG0    = 32'hD25D_2000;
    localparam logic [31:0] P25D_DESC1_TAG1    = 32'hD25D_2001;

    function new(string name = "ai_accel_subsys_csr_event_driven_append_consume_stress_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function automatic bit p25d_queue_service_active(input logic [31:0] status);
    begin
        // P21/P22 queue status may briefly report sub-engine busy bits
        // without QUEUE_BUSY during command-fetch handoff micro-states.
        // Any lower queue-service activity before SQ_HEAD/CQ_TAIL
        // advancement is a valid live-service window for publishing
        // the runtime SQ_TAIL doorbell.
        p25d_queue_service_active = status[0]  ||  // QUEUE_BUSY
                                    status[8]  ||  // CMD_FETCH_BUSY
                                    status[9]  ||  // DESC_FETCH_BUSY
                                    status[10] ||  // RECIPE_BUSY
                                    status[11] ||  // COMP_BUSY
                                    status[12];    // UNDERLYING_BUSY
    end
    endfunction

    task automatic p25d_program_descriptor_table(
        input int unsigned             desc_base,
        input logic [31:0]             first_tag,
        input logic [31:0]             second_tag,
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
    begin
        program_memory_descriptor(
            desc_base + (0 * P25D_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            first_tag
        );

        program_memory_descriptor(
            desc_base + (1 * P25D_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            second_tag
        );
    end
    endtask

    task automatic p25d_make_cfg(
        output ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg
    );
    begin
        cfg.sq_base       = 32'(P25D_SQ_BASE);
        cfg.sq_depth      = 32'(P25D_SQ_DEPTH);
        cfg.sq_head       = 32'h0000_0000;
        cfg.sq_tail       = 32'h0000_0000;
        cfg.sq_stride     = 32'(P25D_ENTRY_STRIDE);
        cfg.cq_base       = 32'(P25D_CQ_BASE);
        cfg.cq_depth      = 32'(P25D_CQ_DEPTH);
        cfg.cq_head       = 32'h0000_0000;
        cfg.cq_tail       = 32'h0000_0000;
        cfg.cq_stride     = 32'(P25D_ENTRY_STRIDE);
        cfg.queue_control = P25D_QUEUE_CONTROL_DRAIN;
    end
    endtask

    task automatic p25d_make_cmd(
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
            32'(P25D_DESC_STRIDE),
            user_tag,
            1'b1,
            1'b0
        );

        // P25D stresses runtime append and CQ consume timing.  Timeout
        // recovery remains covered by P24F/P25E.
        cmd.timeout_cycles = 32'h0000_0000;
    end
    endtask

    task automatic p25d_check_event_snapshot(
        input string label,
        input ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t snap,
        input logic [31:0] required_mask,
        input logic [31:0] optional_mask = 32'h0000_0000
    );
        logic [31:0] optional_seen;
    begin
        optional_seen = snap.event_snap.pending & optional_mask;

        if ((snap.event_snap.pending & required_mask) !== required_mask) begin
            `uvm_fatal("P25D_HOST_RT/EVENT_MISSING",
                $sformatf("%s: required event bits missing pending=0x%08h required=0x%08h optional_seen=0x%08h",
                    label,
                    snap.event_snap.pending,
                    required_mask,
                    optional_seen))
        end

        if ((snap.event_snap.status & 32'h0000_0007) == 32'h0000_0000) begin
            `uvm_fatal("P25D_HOST_RT/EVENT_STATUS",
                $sformatf("%s: expected pending/eligible/IRQ event status before ack, status=0x%08h",
                    label,
                    snap.event_snap.status))
        end

        if (snap.event_snap.event_count == 32'h0000_0000) begin
            `uvm_fatal("P25D_HOST_RT/EVENT_COUNT",
                $sformatf("%s: expected EVENT_COUNT to increment", label))
        end

        if (snap.event_snap.irq_count == 32'h0000_0000) begin
            `uvm_fatal("P25D_HOST_RT/IRQ_COUNT",
                $sformatf("%s: expected IRQ_COUNT to increment for enabled events", label))
        end

        `uvm_info("P25D_HOST_RT/EVENT",
            $sformatf("%s: event snapshot PASS pending=0x%08h required=0x%08h optional=0x%08h optional_seen=0x%08h status=0x%08h last_cause=0x%08h count=%0d irq_count=%0d snapshot0=0x%08h snapshot1=0x%08h",
                label,
                snap.event_snap.pending,
                required_mask,
                optional_mask,
                optional_seen,
                snap.event_snap.status,
                snap.event_snap.last_cause,
                snap.event_snap.event_count,
                snap.event_snap.irq_count,
                snap.event_snap.snapshot0,
                snap.event_snap.snapshot1),
            UVM_MEDIUM)
    end
    endtask

    task automatic p25d_wait_queue_active_before_append(input int unsigned timeout_cycles);
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
                `uvm_fatal("P25D_HOST_RT/ERROR_BEFORE_APPEND",
                    $sformatf("Queue failed before runtime append: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h SQ_HEAD=0x%08h SQ_TAIL=0x%08h CQ_TAIL=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        sq_tail,
                        cq_tail))
            end

            if (p25d_queue_service_active(status) &&
                (sq_head == 32'h0000_0000) &&
                (sq_tail == 32'h0000_0001) &&
                (cq_tail == 32'h0000_0000)) begin
                `uvm_info("P25D_HOST_RT/ACTIVE",
                    $sformatf("Queue service active before runtime append PASS: status=0x%08h done=0x%08h SQ_HEAD=0x%08h SQ_TAIL=0x%08h CQ_TAIL=0x%08h",
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
                `uvm_fatal("P25D_HOST_RT/ACTIVE_TIMEOUT",
                    $sformatf("Timeout waiting for queue active before runtime append: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h SQ_HEAD=0x%08h SQ_TAIL=0x%08h CQ_TAIL=0x%08h",
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

    task automatic p25d_append_sq1_while_active(
        input ai_accel_event_driven_host_runtime_stress_helper rt,
        input ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd1
    );
        logic [31:0] status_before;
        logic [31:0] sq_head_after;
        logic [31:0] sq_tail_after;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status_before);
        if (!p25d_queue_service_active(status_before)) begin
            `uvm_fatal("P25D_HOST_RT/NOT_ACTIVE_AT_APPEND",
                $sformatf("Expected queue service activity before runtime append, status=0x%08h",
                    status_before))
        end

        rt.write_sq_command(cfg, 1, cmd1, 1'b1);
        rt.ring_sq_tail(32'h0000_0002);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head_after);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL, sq_tail_after);

        if (sq_tail_after !== 32'h0000_0002) begin
            `uvm_fatal("P25D_HOST_RT/SQ_TAIL_APPEND_FAIL",
                $sformatf("Expected SQ_TAIL=2 after runtime append, got 0x%08h",
                    sq_tail_after))
        end

        if (sq_head_after !== 32'h0000_0000) begin
            `uvm_fatal("P25D_HOST_RT/SQ_HEAD_ADVANCED_TOO_EARLY",
                $sformatf("Expected SQ_HEAD to remain 0 immediately after runtime append, got 0x%08h",
                    sq_head_after))
        end

        `uvm_info("P25D_HOST_RT/APPEND_PASS",
            $sformatf("Runtime append PASS: wrote SQ[1], published SQ_TAIL 1->2 while queue active, status_before=0x%08h",
                status_before),
            UVM_MEDIUM)
    end
    endtask

    task automatic p25d_wait_cq_full_stall(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] sq_head;
        logic [31:0] sq_tail;
        logic [31:0] cq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
        logic [31:0] cq_space;
        logic [31:0] last_tag;
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
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,       cq_head);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,       cq_tail);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY,  cq_occ);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_SPACE,      cq_space);

            if ((error_status != 32'h0000_0000) ||
                (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P25D_HOST_RT/CQ_FULL_ERROR",
                    $sformatf("CQ full should stall, not error/reject: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h SQ_HEAD=0x%08h SQ_TAIL=0x%08h CQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h CQ_SPACE=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        sq_tail,
                        cq_head,
                        cq_tail,
                        cq_occ,
                        cq_space))
            end

            if ((sq_head  == 32'h0000_0001) &&
                (sq_tail  == 32'h0000_0002) &&
                (cq_head  == 32'h0000_0000) &&
                (cq_tail  == 32'h0000_0001) &&
                (cq_occ   == 32'h0000_0001) &&
                (cq_space == 32'h0000_0000)) begin
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);
                if (last_tag !== P25D_CMD0_TAG) begin
                    `uvm_fatal("P25D_HOST_RT/CQ_FULL_LAST_TAG",
                        $sformatf("Expected last accepted command tag to remain SQ[0]=0x%08h during CQ-full stall, got 0x%08h",
                            P25D_CMD0_TAG,
                            last_tag))
                end

                if (!status[0]) begin
                    `uvm_fatal("P25D_HOST_RT/NOT_BUSY_ON_CQ_FULL",
                        $sformatf("Expected queue_busy=1 while stalled on CQ full with SQ[1] pending: status=0x%08h done=0x%08h",
                            status,
                            done_status))
                end

                `uvm_info("P25D_HOST_RT/CQ_FULL_STALL_PASS",
                    $sformatf("CQ-full stall PASS: status=0x%08h done=0x%08h SQ_HEAD=%0d SQ_TAIL=%0d CQ_HEAD=%0d CQ_TAIL=%0d CQ_OCC=%0d CQ_SPACE=%0d last_tag=0x%08h",
                        status,
                        done_status,
                        sq_head,
                        sq_tail,
                        cq_head,
                        cq_tail,
                        cq_occ,
                        cq_space,
                        last_tag),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P25D_HOST_RT/CQ_FULL_TIMEOUT",
                    $sformatf("Timeout waiting for CQ-full stall: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h SQ_HEAD=0x%08h SQ_TAIL=0x%08h CQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h CQ_SPACE=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        sq_tail,
                        cq_head,
                        cq_tail,
                        cq_occ,
                        cq_space))
            end
        end
    end
    endtask

    task automatic p25d_run_append_consume_variation(
        input ai_accel_event_driven_host_runtime_stress_helper rt,
        input ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd0,
        input ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd1,
        input ai_accel_subsys_seq_item profile_item
    );
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec0;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec1;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t snap_stall;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t snap_final;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t snap_after_consume;
        logic [31:0] completion_mask;
        logic [31:0] runtime_mask;
        logic [31:0] full_stall_mask;
        logic [31:0] space_recovered_mask;
        logic [31:0] drained_mask;
        logic [31:0] first_required_mask;
        logic [31:0] final_required_mask;
        logic [31:0] event_enable_mask;
    begin
        completion_mask      = rt.queue_completion_event_mask();
        runtime_mask         = rt.runtime_event_mask();
        full_stall_mask      = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_FULL_STALL);
        space_recovered_mask = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_SPACE_RECOVERED);
        drained_mask         = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);

        first_required_mask  = completion_mask | full_stall_mask;
        final_required_mask  = completion_mask | drained_mask | space_recovered_mask;
        event_enable_mask    = completion_mask | drained_mask | full_stall_mask |
                               space_recovered_mask | runtime_mask;

        rt.clear_and_rearm_runtime(
            cfg,
            event_enable_mask,
            1'b1,
            "P25D runtime append plus delayed CQ consume session"
        );
        csr_check_recipe_idle_ready("P25D before START_QUEUE");

        rt.submit_command_and_doorbell(cfg, 0, cmd0, 32'h0000_0001);
        rt.start_queue();

        p25d_wait_queue_active_before_append(done_timeout_cycles * 4);
        rt.deterministic_gap(5, "P25D gap before runtime append");
        p25d_append_sq1_while_active(rt, cfg, cmd1);

        rt.wait_for_progress_event(
            first_required_mask,
            snap_stall,
            "P25D first completion plus CQ-full stall event wait",
            done_timeout_cycles * 12,
            1'b1
        );
        p25d_check_event_snapshot(
            "P25D first completion plus CQ-full stall",
            snap_stall,
            first_required_mask,
            runtime_mask
        );

        p25d_wait_cq_full_stall(done_timeout_cycles * 4);

        rt.wait_and_check_cq_record(
            cfg,
            0,
            P25D_DESC0_TAG0,
            P25D_DESC0_TAG1,
            rec0,
            "P25D first CQ record before delayed consume",
            done_timeout_cycles * 4
        );
        check_p23d_cq_record(0, rec0, profile_item, P25D_DESC0_TAG0, P25D_DESC0_TAG1);

        rt.require_queue_pointers("P25D pointers during deliberate CQ-full stall",
            32'h0000_0001,
            32'h0000_0000,
            32'h0000_0001,
            32'h0000_0001);

        rt.deterministic_gap(P25D_HOST_DELAY_CYCLES, "P25D delayed host CQ consume while queue is stalled");

        rt.require_queue_pointers("P25D pointers still stalled before CQ consume",
            32'h0000_0001,
            32'h0000_0000,
            32'h0000_0001,
            32'h0000_0001);

        rt.consume_cq_entry(cfg, 0, 1'b1);

        rt.wait_for_progress_event(
            final_required_mask,
            snap_final,
            "P25D final completion after CQ_HEAD recovery event wait",
            done_timeout_cycles * 12,
            1'b1
        );
        p25d_check_event_snapshot(
            "P25D final completion after CQ_HEAD recovery",
            snap_final,
            final_required_mask,
            runtime_mask | full_stall_mask
        );

        rt.wait_and_check_cq_record(
            cfg,
            1,
            P25D_DESC1_TAG0,
            P25D_DESC1_TAG1,
            rec1,
            "P25D second CQ record after CQ-space recovery",
            done_timeout_cycles * 4
        );
        check_p23d_cq_record(1, rec1, profile_item, P25D_DESC1_TAG0, P25D_DESC1_TAG1);

        rt.require_queue_pointers("P25D pointers before final CQ consume",
            32'h0000_0002,
            32'h0000_0001,
            32'h0000_0002,
            32'h0000_0001);

        rt.consume_cq_entry(cfg, 1, 1'b1);
        rt.snapshot_and_log("P25D event snapshot after final CQ consume", snap_after_consume, UVM_MEDIUM);
        rt.event_ack_and_require_clean(snap_after_consume, "P25D accumulated event cleanup");
        rt.wait_queue_reusable("P25D queue reusable after append/consume variation");
        rt.require_no_queue_error("P25D no queue error after append/consume variation");
        rt.require_queue_pointers("P25D pointers after final consume",
            32'h0000_0002,
            32'h0000_0002,
            32'h0000_0002,
            32'h0000_0000);

        `uvm_info("P25D_HOST_RT/RECOVERY_PASS",
            $sformatf("P25D CQ consume timing recovery PASS: cmd_tags=0x%08h/0x%08h desc0=0x%08h/0x%08h desc1=0x%08h/0x%08h",
                cmd0.user_tag,
                cmd1.user_tag,
                P25D_DESC0_TAG0,
                P25D_DESC0_TAG1,
                P25D_DESC1_TAG0,
                P25D_DESC1_TAG1),
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
    begin
        phase.raise_objection(this);

        `uvm_info("P25D_HOST_RT/START",
            "Starting P25D event-driven runtime append + CQ consume timing stress smoke test",
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
            `uvm_fatal("P25D_HOST_RT/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        // Write descriptor tables after source/destination preparation so
        // descriptor memory is not overwritten by inherited source setup.
        p25d_program_descriptor_table(
            P25D_DESC_BASE0,
            P25D_DESC0_TAG0,
            P25D_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p25d_program_descriptor_table(
            P25D_DESC_BASE1,
            P25D_DESC1_TAG0,
            P25D_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p25d_make_cfg(cfg);
        p25d_make_cmd(rt, cmd0, 32'(P25D_DESC_BASE0), P25D_CMD0_TAG);
        p25d_make_cmd(rt, cmd1, 32'(P25D_DESC_BASE1), P25D_CMD1_TAG);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_program_completion_wb();

        rt.require_event_clean("P25D initial event state");
        rt.wait_queue_reusable("P25D initial reusable state");

        p25d_run_append_consume_variation(rt, cfg, cmd0, cmd1, profile_item);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P25D_HOST_RT/PASS",
            $sformatf("P25D runtime append + CQ consume timing stress PASS: CASE_ID=%0d commands=2 CQ_DEPTH=%0d host_delay=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
                selected_case_id,
                P25D_CQ_DEPTH,
                P25D_HOST_DELAY_CYCLES,
                a_flat.size(),
                b_flat.size(),
                c_elems),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
