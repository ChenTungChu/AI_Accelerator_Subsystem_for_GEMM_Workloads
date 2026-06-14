// File: tb/uvm/test/ai_accel_subsys_csr_event_driven_multi_command_queue_drain_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_EVENT_DRIVEN_MULTI_COMMAND_QUEUE_DRAIN_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_EVENT_DRIVEN_MULTI_COMMAND_QUEUE_DRAIN_SMOKE_TEST_SV

// ============================================================
// P23D event-driven multi-command queue drain smoke
//
// Scope:
//   - Reuses the validated P20 multi-entry in-order queue drain path.
//   - Uses the P23B event-driven host runtime helper as the host-side
//     driver-style API.
//   - Host programs two SQ command entries, publishes SQ_TAIL=2,
//     starts the queue once with RUN_UNTIL_EMPTY=1, waits for P22
//     event notification, drains CQ[0] and CQ[1], advances CQ_HEAD,
//     and W1C-acks captured event bits.
//   - Verifies two CQ completion records, queue pointer state, P22
//     event pending/IRQ behavior, drained notification, and final
//     GEMM/DMA result correctness.
//
// This is UVM/helper-only validation.  It does not add RTL, standalone
// event CSR blocks, standalone event interfaces, standalone UVM tops,
// new sim flows, or BRAM/GEMM/DMA/frontend datapath changes.
// ============================================================

class ai_accel_subsys_csr_event_driven_multi_command_queue_drain_smoke_test
    extends ai_accel_subsys_csr_event_driven_single_queue_command_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_event_driven_multi_command_queue_drain_smoke_test)

    localparam int unsigned P23D_SQ_BASE     = 32'h0000_0700;
    localparam int unsigned P23D_CQ_BASE     = 32'h0000_0800;
    localparam int unsigned P23D_QUEUE_DEPTH = 4;

    localparam int unsigned P23D_DESC_BASE0  = 32'h0000_0300;
    localparam int unsigned P23D_DESC_BASE1  = 32'h0000_0400;
    localparam int unsigned P23D_DESC_STRIDE = 32'h0000_0080;

    localparam logic [31:0] P23D_CMD0_TAG    = 32'hD23D_0000;
    localparam logic [31:0] P23D_CMD1_TAG    = 32'hD23D_0001;

    localparam logic [31:0] P23D_DESC0_TAG0  = 32'hD23D_1000;
    localparam logic [31:0] P23D_DESC0_TAG1  = 32'hD23D_1001;
    localparam logic [31:0] P23D_DESC1_TAG0  = 32'hD23D_2000;
    localparam logic [31:0] P23D_DESC1_TAG1  = 32'hD23D_2001;

    function new(string name = "ai_accel_subsys_csr_event_driven_multi_command_queue_drain_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic expect_p23d_eq32(input string       name,
                                    input logic [31:0] actual,
                                    input logic [31:0] expected);
    begin
        if (actual !== expected) begin
            `uvm_fatal("P23D_HOST_RT/MISMATCH",
                $sformatf("%s mismatch: actual=0x%08h expected=0x%08h",
                    name,
                    actual,
                    expected))
        end

        `uvm_info("P23D_HOST_RT/CHECK",
            $sformatf("%s PASS: 0x%08h", name, actual),
            UVM_LOW)
    end
    endtask

    task automatic expect_p23d_nonzero32(input string       name,
                                         input logic [31:0] actual);
    begin
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P23D_HOST_RT/ZERO",
                $sformatf("%s unexpectedly zero", name))
        end

        `uvm_info("P23D_HOST_RT/CHECK",
            $sformatf("%s nonzero PASS: 0x%08h", name, actual),
            UVM_LOW)
    end
    endtask

    task automatic program_p23d_descriptor_table(
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
            desc_base + (0 * P23D_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            first_tag
        );

        program_memory_descriptor(
            desc_base + (1 * P23D_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            second_tag
        );
    end
    endtask

    task automatic check_p23d_cq_record(
        input int unsigned                                                 cq_slot,
        input ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec,
        input ai_accel_subsys_seq_item                                    profile_item,
        input logic [31:0]                                                 first_desc_tag,
        input logic [31:0]                                                 last_desc_tag
    );
        int unsigned expected_macs;
        int unsigned expected_outputs;
    begin
        expected_macs    = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n) * int'(profile_item.dim_k);
        expected_outputs = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n);

        expect_p23d_eq32($sformatf("CQ[%0d] word0 commit",             cq_slot), rec.commit_word,       32'h0100_1803);
        expect_p23d_eq32($sformatf("CQ[%0d] word1 status_flags",       cq_slot), rec.status_flags,      32'h0000_003F);
        expect_p23d_eq32($sformatf("CQ[%0d] word2 first_user_tag",     cq_slot), rec.first_user_tag,    first_desc_tag);
        expect_p23d_eq32($sformatf("CQ[%0d] word3 last_user_tag",      cq_slot), rec.last_user_tag,     last_desc_tag);
        expect_p23d_eq32($sformatf("CQ[%0d] word4 counts",             cq_slot), rec.counts,            32'h0002_0202);
        expect_p23d_eq32($sformatf("CQ[%0d] word5 desc_fetch_done",    cq_slot), rec.desc_fetch_done,   32'h0000_0003);
        expect_p23d_eq32($sformatf("CQ[%0d] word6 desc_fetch_error",   cq_slot), rec.desc_fetch_error,  32'h0000_0000);
        expect_p23d_eq32($sformatf("CQ[%0d] word7 desc_fetch_reject",  cq_slot), rec.desc_fetch_reject, 32'h0000_0000);
        expect_p23d_eq32($sformatf("CQ[%0d] word8 recipe_done",        cq_slot), rec.recipe_done,       32'h0000_0007);
        expect_p23d_eq32($sformatf("CQ[%0d] word9 recipe_error",       cq_slot), rec.recipe_error,      32'h0000_0000);
        expect_p23d_eq32($sformatf("CQ[%0d] word10 recipe_reject",     cq_slot), rec.recipe_reject,     32'h0000_0000);
        expect_p23d_eq32($sformatf("CQ[%0d] word11 slot_mask_summary", cq_slot), rec.slot_mask_summary, 32'h0000_0003);
        expect_p23d_nonzero32($sformatf("CQ[%0d] word12 perf_busy_cycles", cq_slot), rec.perf_busy_cycles);
        expect_p23d_eq32($sformatf("CQ[%0d] word13 perf_mac_count",    cq_slot), rec.perf_mac_count,    32'(expected_macs));
        expect_p23d_eq32($sformatf("CQ[%0d] word14 perf_output_count", cq_slot), rec.perf_output_count, 32'(expected_outputs));
        expect_p23d_eq32($sformatf("CQ[%0d] word15 error_detail",      cq_slot), rec.error_detail,      32'h0000_0000);
    end
    endtask

    task automatic check_p23d_event_snapshot_before_ack(
        input ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t snap,
        input logic [31:0] required_mask
    );
    begin
        if ((snap.pending & required_mask) !== required_mask) begin
            `uvm_fatal("P23D_HOST_RT/EVENT_MISSING",
                $sformatf("Required event bits missing: pending=0x%08h required=0x%08h",
                    snap.pending,
                    required_mask))
        end

        if ((snap.status & 32'h0000_001F) !== 32'h0000_001F) begin
            `uvm_fatal("P23D_HOST_RT/EVENT_STATUS",
                $sformatf("Expected event status summary bits [4:0] set before ack, got status=0x%08h",
                    snap.status))
        end

        if (snap.event_count < 32'h0000_0002) begin
            `uvm_fatal("P23D_HOST_RT/EVENT_COUNT",
                $sformatf("Expected EVENT_COUNT >= 2 for multi-command drain, got %0d",
                    snap.event_count))
        end

        if (snap.irq_count == 32'h0000_0000) begin
            `uvm_fatal("P23D_HOST_RT/IRQ_COUNT",
                "Expected EVENT_IRQ_COUNT to increment for enabled queue events")
        end

        `uvm_info("P23D_HOST_RT/EVENT",
            $sformatf("Event snapshot before ack PASS: pending=0x%08h required=0x%08h status=0x%08h last_cause=0x%08h count=%0d irq_count=%0d snapshot0=0x%08h snapshot1=0x%08h",
                snap.pending,
                required_mask,
                snap.status,
                snap.last_cause,
                snap.event_count,
                snap.irq_count,
                snap.snapshot0,
                snap.snapshot1),
            UVM_MEDIUM)
    end
    endtask

    task automatic check_p23d_queue_state_before_consume();
        logic [31:0] sq_head;
        logic [31:0] cq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
        logic [31:0] done_status;
        logic [31:0] last_tag;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,          sq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,          cq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,          cq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY,     cq_occ);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS,      done_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG,     last_tag);

        expect_p23d_eq32("SQ_HEAD after two-command drain",       sq_head,         32'h0000_0002);
        expect_p23d_eq32("CQ_HEAD before host consume",           cq_head,         32'h0000_0000);
        expect_p23d_eq32("CQ_TAIL after two completion commits",  cq_tail,         32'h0000_0002);
        expect_p23d_eq32("CQ_OCC before host consume",            cq_occ,          32'h0000_0002);
        expect_p23d_eq32("QUEUE_LAST_CMD_TAG",                    last_tag,        P23D_CMD1_TAG);

        if (!done_status[1] || !done_status[2]) begin
            `uvm_fatal("P23D_HOST_RT/DONE_STATUS",
                $sformatf("Expected QUEUE_DRAINED and COMMAND_COMPLETED sticky bits set, done_status=0x%08h",
                    done_status))
        end

        `uvm_info("P23D_HOST_RT/CHECK",
            $sformatf("Queue drained sticky status PASS: done_status=0x%08h", done_status),
            UVM_LOW)
    end
    endtask

    task automatic check_p23d_runtime_cleanup_after_consume(
        input logic [31:0] ack_mask
    );
        logic [31:0] cq_head;
        logic [31:0] cq_occ;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t snap;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,      cq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);

        expect_p23d_eq32("CQ_HEAD after consuming CQ[0]/CQ[1]", cq_head, 32'h0000_0002);
        expect_p23d_eq32("CQ_OCC after consuming CQ[0]/CQ[1]",  cq_occ,  32'h0000_0000);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_PENDING, snap.pending);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_STATUS,  snap.status);

        if ((snap.pending & ack_mask) != 32'h0000_0000) begin
            `uvm_fatal("P23D_HOST_RT/EVENT_ACK_FAIL",
                $sformatf("Acked event bits still pending: pending=0x%08h ack_mask=0x%08h",
                    snap.pending,
                    ack_mask))
        end

        if ((snap.status & 32'h0000_0007) != 32'h0000_0000) begin
            `uvm_fatal("P23D_HOST_RT/IRQ_STILL_SET",
                $sformatf("Pending/eligible/IRQ status bits still set after ack: status=0x%08h",
                    snap.status))
        end

        `uvm_info("P23D_HOST_RT/CHECK",
            $sformatf("Runtime cleanup after draining two CQ records + event ack PASS: pending=0x%08h status=0x%08h",
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
        logic [31:0] event_mask;
        logic [31:0] ack_mask;
    begin
        phase.raise_objection(this);

        `uvm_info("P23D_HOST_RT/START",
            "Starting P23D event-driven multi-command queue drain smoke test",
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
            `uvm_fatal("P23D_HOST_RT/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        // Write descriptors after A/B preparation so the descriptor tables
        // are not overwritten by the inherited source-memory setup.
        program_p23d_descriptor_table(
            P23D_DESC_BASE0,
            P23D_DESC0_TAG0,
            P23D_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        program_p23d_descriptor_table(
            P23D_DESC_BASE1,
            P23D_DESC1_TAG0,
            P23D_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        rt.make_default_queue_cfg(
            cfg,
            32'(P23D_SQ_BASE),
            32'(P23D_CQ_BASE),
            32'(P23D_QUEUE_DEPTH),
            1'b1
        );

        rt.make_fetch_recipe_cmd(
            cmd0,
            32'(P23D_DESC_BASE0),
            32'h0000_0002,
            32'(P23D_DESC_STRIDE),
            P23D_CMD0_TAG,
            1'b1,
            1'b0
        );

        rt.make_fetch_recipe_cmd(
            cmd1,
            32'(P23D_DESC_BASE1),
            32'h0000_0002,
            32'(P23D_DESC_STRIDE),
            P23D_CMD1_TAG,
            1'b1,
            1'b0
        );

        event_mask = rt.queue_completion_event_mask() |
                     rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();

        csr_program_completion_wb();

        rt.initialize_runtime(cfg, event_mask, 1'b1);

        csr_check_recipe_idle_ready("before P23D event-driven queue START");

        // Driver-style queue submission: payloads first, then publish the
        // final SQ_TAIL doorbell value.  One START_QUEUE kick drains both
        // commands through RUN_UNTIL_EMPTY.
        rt.write_sq_command(cfg, 0, cmd0, 1'b1);
        rt.write_sq_command(cfg, 1, cmd1, 1'b1);
        rt.ring_sq_tail(32'h0000_0002);
        rt.start_queue();

        // Wait for the P22 event summary to report both completion-visible
        // work and the final drained terminal condition.  The host runtime
        // then drains all visible CQ records.
        rt.wait_events(event_mask, event_snap, done_timeout_cycles * 8, 1'b1);
        check_p23d_event_snapshot_before_ack(event_snap, event_mask);

        rt.wait_cq_commit(cfg, 0, rec0, done_timeout_cycles * 4);
        rt.wait_cq_commit(cfg, 1, rec1, done_timeout_cycles * 4);

        check_p23d_cq_record(0, rec0, profile_item, P23D_DESC0_TAG0, P23D_DESC0_TAG1);
        check_p23d_cq_record(1, rec1, profile_item, P23D_DESC1_TAG0, P23D_DESC1_TAG1);
        check_p23d_queue_state_before_consume();

        ack_mask = event_snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.consume_cq_entry(cfg, 0, 1'b1);
        rt.consume_cq_entry(cfg, 1, 1'b1);
        rt.ack_events(ack_mask);
        check_p23d_runtime_cleanup_after_consume(ack_mask);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P23D_HOST_RT/PASS",
            $sformatf("P23D event-driven multi-command queue drain completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d SQ_entries=2 CQ_entries=2 event_mask=0x%08h ack_mask=0x%08h",
                selected_case_id,
                a_flat.size(),
                b_flat.size(),
                c_elems,
                event_mask,
                ack_mask),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
