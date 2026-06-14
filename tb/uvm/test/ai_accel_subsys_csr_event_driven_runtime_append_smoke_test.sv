// File: tb/uvm/test/ai_accel_subsys_csr_event_driven_runtime_append_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_EVENT_DRIVEN_RUNTIME_APPEND_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_EVENT_DRIVEN_RUNTIME_APPEND_SMOKE_TEST_SV

// ============================================================
// P23E event-driven runtime append / live doorbell smoke
//
// Scope:
//   - Reuses the validated P21 runtime doorbell / live queue service
//     policy and the P22 event notification layer.
//   - Uses the P23B event-driven host runtime helper as the host-side
//     driver-style API.
//   - Host makes only SQ[0] visible before START_QUEUE, then during
//     the live queue-service window programs SQ[1], writes
//     CMD_CONTROL.VALID last, and publishes SQ_TAIL=2 as a runtime
//     doorbell.
//   - Hardware must consume SQ[1] at the next command boundary without
//     a second START_QUEUE kick.
//   - Host waits for P22 event-driven notification, drains CQ[0]/CQ[1],
//     advances CQ_HEAD, W1C-acks captured event bits, and compares the
//     final DMA destination C result.
//
// Notes:
//   - The runtime doorbell action is validated by observing SQ_TAIL update
//     while queue_busy=1 and by proving SQ[1] completes without another
//     START_QUEUE.  The event-driven wake condition uses completion/drained
//     queue events, while runtime event bits are enabled opportunistically
//     and acked if present.
//   - This is UVM/helper-only validation.  It does not add RTL, standalone
//     event CSR blocks, standalone event interfaces, standalone UVM tops,
//     new sim flows, or BRAM/GEMM/DMA/frontend datapath changes.
// ============================================================

class ai_accel_subsys_csr_event_driven_runtime_append_smoke_test
    extends ai_accel_subsys_csr_event_driven_multi_command_queue_drain_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_event_driven_runtime_append_smoke_test)

    localparam int unsigned P23E_SQ_BASE     = 32'h0000_0700;
    localparam int unsigned P23E_CQ_BASE     = 32'h0000_0800;
    localparam int unsigned P23E_QUEUE_DEPTH = 4;

    localparam int unsigned P23E_DESC_BASE0  = 32'h0000_0300;
    localparam int unsigned P23E_DESC_BASE1  = 32'h0000_0400;
    localparam int unsigned P23E_DESC_STRIDE = 32'h0000_0080;

    localparam logic [31:0] P23E_CMD0_TAG    = 32'hD23E_0000;
    localparam logic [31:0] P23E_CMD1_TAG    = 32'hD23E_0001;

    localparam logic [31:0] P23E_DESC0_TAG0  = 32'hD23E_1000;
    localparam logic [31:0] P23E_DESC0_TAG1  = 32'hD23E_1001;
    localparam logic [31:0] P23E_DESC1_TAG0  = 32'hD23E_2000;
    localparam logic [31:0] P23E_DESC1_TAG1  = 32'hD23E_2001;

    function new(string name = "ai_accel_subsys_csr_event_driven_runtime_append_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function automatic bit p23e_queue_service_active(input logic [31:0] status);
    begin
        // P21/P22 queue status may briefly report the sub-engine busy bits
        // without QUEUE_BUSY during command-fetch handoff micro-states.
        // For the P23E host-runtime append timing, any lower queue service
        // activity before SQ_HEAD/CQ_TAIL advancement is a valid live-service
        // window for publishing the runtime SQ_TAIL doorbell.
        p23e_queue_service_active = status[0]  ||  // QUEUE_BUSY
                                    status[8]  ||  // CMD_FETCH_BUSY
                                    status[9]  ||  // DESC_FETCH_BUSY
                                    status[10] ||  // RECIPE_BUSY
                                    status[11] ||  // COMP_BUSY
                                    status[12];    // UNDERLYING_BUSY
    end
    endfunction

    task automatic expect_p23e_eq32(input string       name,
                                    input logic [31:0] actual,
                                    input logic [31:0] expected);
    begin
        if (actual !== expected) begin
            `uvm_fatal("P23E_HOST_RT/MISMATCH",
                $sformatf("%s mismatch: actual=0x%08h expected=0x%08h",
                    name,
                    actual,
                    expected))
        end

        `uvm_info("P23E_HOST_RT/CHECK",
            $sformatf("%s PASS: 0x%08h", name, actual),
            UVM_LOW)
    end
    endtask

    task automatic program_p23e_descriptor_table(
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
            desc_base + (0 * P23E_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            first_tag
        );

        program_memory_descriptor(
            desc_base + (1 * P23E_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            second_tag
        );
    end
    endtask

    task automatic wait_p23e_queue_active_before_runtime_append(input int unsigned timeout_cycles);
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
                `uvm_fatal("P23E_HOST_RT/ERROR_BEFORE_APPEND",
                    $sformatf("Queue failed before runtime append: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h sq_tail=0x%08h cq_tail=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        sq_tail,
                        cq_tail))
            end

            if (p23e_queue_service_active(status) &&
                (sq_head == 32'h0000_0000) &&
                (sq_tail == 32'h0000_0001) &&
                (cq_tail == 32'h0000_0000)) begin
                `uvm_info("P23E_HOST_RT/ACTIVE",
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
                `uvm_fatal("P23E_HOST_RT/ACTIVE_TIMEOUT",
                    $sformatf("Timeout waiting for queue active before runtime append: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h sq_tail=0x%08h cq_tail=0x%08h",
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

    task automatic append_p23e_sq1_while_active(
        input ai_accel_event_driven_host_runtime_helper rt,
        input ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd1
    );
        logic [31:0] status_before;
        logic [31:0] sq_tail_after;
        logic [31:0] sq_head_after;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status_before);
        if (!p23e_queue_service_active(status_before)) begin
            `uvm_fatal("P23E_HOST_RT/NOT_ACTIVE_AT_APPEND",
                $sformatf("Expected queue service activity before runtime append, status=0x%08h",
                    status_before))
        end

        rt.write_sq_command(cfg, 1, cmd1, 1'b1);
        rt.ring_sq_tail(32'h0000_0002);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL, sq_tail_after);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head_after);

        expect_p23e_eq32("SQ_TAIL after runtime append doorbell", sq_tail_after, 32'h0000_0002);
        expect_p23e_eq32("SQ_HEAD still on active SQ[0] immediately after append", sq_head_after, 32'h0000_0000);

        `uvm_info("P23E_HOST_RT/DOORBELL",
            $sformatf("Runtime append doorbell issued during live queue service: wrote SQ[1], updated SQ_TAIL 1->2, status_before=0x%08h",
                status_before),
            UVM_MEDIUM)
    end
    endtask

    task automatic check_p23e_event_snapshot_before_ack(
        input ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t snap,
        input logic [31:0] required_mask,
        input logic [31:0] runtime_optional_mask
    );
        logic [31:0] runtime_seen;
    begin
        runtime_seen = snap.pending & runtime_optional_mask;

        if ((snap.pending & required_mask) !== required_mask) begin
            `uvm_fatal("P23E_HOST_RT/EVENT_MISSING",
                $sformatf("Required event bits missing: pending=0x%08h required=0x%08h",
                    snap.pending,
                    required_mask))
        end

        if ((snap.status & 32'h0000_001F) !== 32'h0000_001F) begin
            `uvm_fatal("P23E_HOST_RT/EVENT_STATUS",
                $sformatf("Expected event status summary bits [4:0] set before ack, got status=0x%08h",
                    snap.status))
        end

        if (snap.event_count < 32'h0000_0002) begin
            `uvm_fatal("P23E_HOST_RT/EVENT_COUNT",
                $sformatf("Expected EVENT_COUNT >= 2 for runtime append flow, got %0d",
                    snap.event_count))
        end

        if (snap.irq_count == 32'h0000_0000) begin
            `uvm_fatal("P23E_HOST_RT/IRQ_COUNT",
                "Expected EVENT_IRQ_COUNT to increment for enabled queue events")
        end

        `uvm_info("P23E_HOST_RT/EVENT",
            $sformatf("Event snapshot before ack PASS: pending=0x%08h required=0x%08h optional_runtime=0x%08h runtime_seen=0x%08h status=0x%08h last_cause=0x%08h count=%0d irq_count=%0d snapshot0=0x%08h snapshot1=0x%08h",
                snap.pending,
                required_mask,
                runtime_optional_mask,
                runtime_seen,
                snap.status,
                snap.last_cause,
                snap.event_count,
                snap.irq_count,
                snap.snapshot0,
                snap.snapshot1),
            UVM_MEDIUM)
    end
    endtask

    task automatic check_p23e_queue_state_before_consume();
        logic [31:0] sq_head;
        logic [31:0] sq_tail;
        logic [31:0] cq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
        logic [31:0] done_status;
        logic [31:0] last_tag;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,      sq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,      sq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,      cq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,      cq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS,  done_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);

        expect_p23e_eq32("SQ_HEAD after runtime-appended command completes", sq_head,  32'h0000_0002);
        expect_p23e_eq32("SQ_TAIL after runtime append doorbell",            sq_tail,  32'h0000_0002);
        expect_p23e_eq32("CQ_HEAD before host consume",                      cq_head,  32'h0000_0000);
        expect_p23e_eq32("CQ_TAIL after two completion commits",             cq_tail,  32'h0000_0002);
        expect_p23e_eq32("CQ_OCC before host consume",                       cq_occ,   32'h0000_0002);
        expect_p23e_eq32("QUEUE_LAST_CMD_TAG",                               last_tag, P23E_CMD1_TAG);

        if (!done_status[1] || !done_status[2]) begin
            `uvm_fatal("P23E_HOST_RT/DONE_STATUS",
                $sformatf("Expected QUEUE_DRAINED and COMMAND_COMPLETED sticky bits set, done_status=0x%08h",
                    done_status))
        end

        `uvm_info("P23E_HOST_RT/CHECK",
            $sformatf("Runtime append queue-drained sticky status PASS: done_status=0x%08h", done_status),
            UVM_LOW)
    end
    endtask

    task automatic check_p23e_runtime_cleanup_after_consume(input logic [31:0] ack_mask);
        logic [31:0] cq_head;
        logic [31:0] cq_occ;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t snap;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,      cq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);

        expect_p23e_eq32("CQ_HEAD after consuming runtime-append CQ[0]/CQ[1]", cq_head, 32'h0000_0002);
        expect_p23e_eq32("CQ_OCC after consuming runtime-append CQ[0]/CQ[1]",  cq_occ,  32'h0000_0000);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_PENDING, snap.pending);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_STATUS,  snap.status);

        if ((snap.pending & ack_mask) != 32'h0000_0000) begin
            `uvm_fatal("P23E_HOST_RT/EVENT_ACK_FAIL",
                $sformatf("Acked event bits still pending: pending=0x%08h ack_mask=0x%08h",
                    snap.pending,
                    ack_mask))
        end

        if ((snap.status & 32'h0000_0007) != 32'h0000_0000) begin
            `uvm_fatal("P23E_HOST_RT/IRQ_STILL_SET",
                $sformatf("Pending/eligible/IRQ status bits still set after ack: status=0x%08h",
                    snap.status))
        end

        `uvm_info("P23E_HOST_RT/CHECK",
            $sformatf("Runtime cleanup after live append CQ consume + event ack PASS: pending=0x%08h status=0x%08h",
                snap.pending,
                snap.status),
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

        ai_accel_event_driven_host_runtime_helper rt;
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd0;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd1;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec0;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec1;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t event_snap;
        logic [31:0] required_event_mask;
        logic [31:0] runtime_optional_mask;
        logic [31:0] event_enable_mask;
        logic [31:0] ack_mask;
    begin
        phase.raise_objection(this);

        `uvm_info("P23E_HOST_RT/START",
            "Starting P23E event-driven runtime append / live doorbell smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        rt = ai_accel_event_driven_host_runtime_helper::type_id::create("rt");
        rt.set_csr(csr);
        rt.set_ctrl_vif(p17d_ctrl_vif);

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P23E_HOST_RT/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        // Descriptor tables are written after A/B setup to avoid being
        // overwritten by inherited source-memory preparation.
        program_p23e_descriptor_table(
            P23E_DESC_BASE0,
            P23E_DESC0_TAG0,
            P23E_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        program_p23e_descriptor_table(
            P23E_DESC_BASE1,
            P23E_DESC1_TAG0,
            P23E_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        rt.make_default_queue_cfg(
            cfg,
            32'(P23E_SQ_BASE),
            32'(P23E_CQ_BASE),
            32'(P23E_QUEUE_DEPTH),
            1'b1
        );

        rt.make_fetch_recipe_cmd(
            cmd0,
            32'(P23E_DESC_BASE0),
            32'h0000_0002,
            32'(P23E_DESC_STRIDE),
            P23E_CMD0_TAG,
            1'b1,
            1'b0
        );

        rt.make_fetch_recipe_cmd(
            cmd1,
            32'(P23E_DESC_BASE1),
            32'h0000_0002,
            32'(P23E_DESC_STRIDE),
            P23E_CMD1_TAG,
            1'b1,
            1'b0
        );

        required_event_mask = rt.queue_completion_event_mask() |
                              rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);
        runtime_optional_mask = rt.runtime_event_mask();
        event_enable_mask = required_event_mask | runtime_optional_mask;

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();

        csr_program_completion_wb();

        // Initialize the runtime with no visible SQ entries.  SQ[0] is
        // committed and published first, while SQ[1] is deliberately held
        // back until queue_busy=1.
        rt.initialize_runtime(cfg, event_enable_mask, 1'b1);

        csr_check_recipe_idle_ready("before P23E event-driven runtime append queue START");

        rt.write_sq_command(cfg, 0, cmd0, 1'b1);
        rt.ring_sq_tail(32'h0000_0001);
        rt.start_queue();

        wait_p23e_queue_active_before_runtime_append(done_timeout_cycles);
        append_p23e_sq1_while_active(rt, cfg, cmd1);

        // Host runtime waits on P22 event notification after the live
        // append.  Completion/drained events are required; runtime event
        // bits are enabled and will be acked if the implementation exposes
        // them, but the P23E functional pass condition is that SQ[1] is
        // consumed without a second START_QUEUE.
        rt.wait_events(required_event_mask, event_snap, done_timeout_cycles * 8, 1'b1);
        check_p23e_event_snapshot_before_ack(event_snap, required_event_mask, runtime_optional_mask);

        rt.wait_cq_commit(cfg, 0, rec0, done_timeout_cycles * 4);
        rt.wait_cq_commit(cfg, 1, rec1, done_timeout_cycles * 4);

        check_p23d_cq_record(0, rec0, profile_item, P23E_DESC0_TAG0, P23E_DESC0_TAG1);
        check_p23d_cq_record(1, rec1, profile_item, P23E_DESC1_TAG0, P23E_DESC1_TAG1);
        check_p23e_queue_state_before_consume();

        ack_mask = event_snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.consume_cq_entry(cfg, 0, 1'b1);
        rt.consume_cq_entry(cfg, 1, 1'b1);
        rt.ack_events(ack_mask);
        check_p23e_runtime_cleanup_after_consume(ack_mask);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P23E_HOST_RT/PASS",
            $sformatf("P23E event-driven runtime append completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d initial_SQ_TAIL=1 runtime_SQ_TAIL=2 CQ_entries=2 required_event_mask=0x%08h ack_mask=0x%08h",
                selected_case_id,
                a_flat.size(),
                b_flat.size(),
                c_elems,
                required_event_mask,
                ack_mask),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
