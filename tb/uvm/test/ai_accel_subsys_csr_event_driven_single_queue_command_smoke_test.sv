// File: tb/uvm/test/ai_accel_subsys_csr_event_driven_single_queue_command_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_EVENT_DRIVEN_SINGLE_QUEUE_COMMAND_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_EVENT_DRIVEN_SINGLE_QUEUE_COMMAND_SMOKE_TEST_SV

// ============================================================
// P23C event-driven single queue command smoke
//
// Scope:
//   - Reuses the validated P19E queue command -> P17 descriptor-fetch
//     -> P18 CQ completion path.
//   - Uses the P23B event-driven host runtime helper as the host-side
//     driver-style API.
//   - Host programs one SQ command, rings SQ_TAIL as the doorbell,
//     starts the queue, waits on P22 event notification, consumes one
//     CQ record, advances CQ_HEAD, and W1C-acks captured event bits.
//   - Verifies the CQ completion record, queue pointer state, P22 event
//     pending/IRQ behavior, and final GEMM/DMA result correctness.
//
// This is UVM/helper-only validation.  It does not add RTL, standalone
// event CSR blocks, standalone event interfaces, standalone UVM tops,
// new sim flows, or BRAM/GEMM/DMA/frontend datapath changes.
// ============================================================

class ai_accel_subsys_csr_event_driven_single_queue_command_smoke_test
    extends ai_accel_subsys_csr_queue_completion_wb_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_event_driven_single_queue_command_smoke_test)

    localparam int unsigned P23C_SQ_BASE     = 32'h0000_0700;
    localparam int unsigned P23C_CQ_BASE     = 32'h0000_0800;
    localparam int unsigned P23C_QUEUE_DEPTH = 4;

    localparam logic [31:0] P23C_CMD_TAG     = 32'hD23C_0000;

    function new(string name = "ai_accel_subsys_csr_event_driven_single_queue_command_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic expect_eq32(input string       name,
                               input logic [31:0] actual,
                               input logic [31:0] expected);
    begin
        if (actual !== expected) begin
            `uvm_fatal("P23C_HOST_RT/MISMATCH",
                $sformatf("%s mismatch: actual=0x%08h expected=0x%08h",
                    name,
                    actual,
                    expected))
        end

        `uvm_info("P23C_HOST_RT/CHECK",
            $sformatf("%s PASS: 0x%08h", name, actual),
            UVM_LOW)
    end
    endtask

    task automatic expect_nonzero32(input string       name,
                                    input logic [31:0] actual);
    begin
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P23C_HOST_RT/ZERO",
                $sformatf("%s unexpectedly zero", name))
        end

        `uvm_info("P23C_HOST_RT/CHECK",
            $sformatf("%s nonzero PASS: 0x%08h", name, actual),
            UVM_LOW)
    end
    endtask

    task automatic check_runtime_cq_record(
        input ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec,
        input ai_accel_subsys_seq_item profile_item
    );
        int unsigned expected_macs;
        int unsigned expected_outputs;
    begin
        expected_macs    = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n) * int'(profile_item.dim_k);
        expected_outputs = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n);

        expect_eq32("CQ word0 commit",                 rec.commit_word,       32'h0100_1803);
        expect_eq32("CQ word1 status_flags",           rec.status_flags,      32'h0000_003F);
        expect_eq32("CQ word2 first_user_tag",         rec.first_user_tag,    32'hD18E_0000);
        expect_eq32("CQ word3 last_user_tag",          rec.last_user_tag,     32'hD18E_0001);
        expect_eq32("CQ word4 counts",                 rec.counts,            32'h0002_0202);
        expect_eq32("CQ word5 desc_fetch_done",        rec.desc_fetch_done,   32'h0000_0003);
        expect_eq32("CQ word6 desc_fetch_error",       rec.desc_fetch_error,  32'h0000_0000);
        expect_eq32("CQ word7 desc_fetch_reject",      rec.desc_fetch_reject, 32'h0000_0000);
        expect_eq32("CQ word8 recipe_done",            rec.recipe_done,       32'h0000_0007);
        expect_eq32("CQ word9 recipe_error",           rec.recipe_error,      32'h0000_0000);
        expect_eq32("CQ word10 recipe_reject",         rec.recipe_reject,     32'h0000_0000);
        expect_eq32("CQ word11 slot_mask_summary",     rec.slot_mask_summary, 32'h0000_0003);
        expect_nonzero32("CQ word12 perf_busy_cycles", rec.perf_busy_cycles);
        expect_eq32("CQ word13 perf_mac_count",        rec.perf_mac_count,    32'(expected_macs));
        expect_eq32("CQ word14 perf_output_count",     rec.perf_output_count, 32'(expected_outputs));
        expect_eq32("CQ word15 error_detail",          rec.error_detail,      32'h0000_0000);
    end
    endtask

    task automatic check_event_snapshot_before_ack(
        input ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t snap,
        input logic [31:0] required_mask
    );
    begin
        if ((snap.pending & required_mask) !== required_mask) begin
            `uvm_fatal("P23C_HOST_RT/EVENT_MISSING",
                $sformatf("Required event bits missing: pending=0x%08h required=0x%08h",
                    snap.pending,
                    required_mask))
        end

        if ((snap.status & 32'h0000_001F) !== 32'h0000_001F) begin
            `uvm_fatal("P23C_HOST_RT/EVENT_STATUS",
                $sformatf("Expected event status summary bits [4:0] set before ack, got status=0x%08h",
                    snap.status))
        end

        if (snap.event_count == 32'h0000_0000) begin
            `uvm_fatal("P23C_HOST_RT/EVENT_COUNT",
                "Expected EVENT_COUNT to increment for real queue completion event")
        end

        if (snap.irq_count == 32'h0000_0000) begin
            `uvm_fatal("P23C_HOST_RT/IRQ_COUNT",
                "Expected EVENT_IRQ_COUNT to increment for enabled queue completion event")
        end

        `uvm_info("P23C_HOST_RT/EVENT",
            $sformatf("Event snapshot before ack PASS: pending=0x%08h status=0x%08h last_cause=0x%08h count=%0d irq_count=%0d snapshot0=0x%08h snapshot1=0x%08h",
                snap.pending,
                snap.status,
                snap.last_cause,
                snap.event_count,
                snap.irq_count,
                snap.snapshot0,
                snap.snapshot1),
            UVM_MEDIUM)
    end
    endtask

    task automatic check_queue_state_before_consume();
        logic [31:0] sq_head;
        logic [31:0] cq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
        logic [31:0] last_tag;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,       sq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,       cq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,       cq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY,  cq_occ);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG,  last_tag);

        expect_eq32("SQ_HEAD after single command",      sq_head,  32'h0000_0001);
        expect_eq32("CQ_HEAD before host consume",       cq_head,  32'h0000_0000);
        expect_eq32("CQ_TAIL after completion commit",   cq_tail,  32'h0000_0001);
        expect_eq32("CQ_OCC before host consume",        cq_occ,   32'h0000_0001);
        expect_eq32("QUEUE_LAST_CMD_TAG",                last_tag, P23C_CMD_TAG);
    end
    endtask

    task automatic check_runtime_cleanup_after_consume(
        input logic [31:0] ack_mask
    );
        logic [31:0] cq_head;
        logic [31:0] cq_occ;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t snap;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,      cq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);

        expect_eq32("CQ_HEAD after host consume", cq_head, 32'h0000_0001);
        expect_eq32("CQ_OCC after host consume",  cq_occ,  32'h0000_0000);

        // The host runtime acks all pending bits captured by the event wait.
        // This clears enabled completion bits and any disabled terminal bits
        // that arrived in the same queue terminal event group.
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_PENDING, snap.pending);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_STATUS,  snap.status);

        if ((snap.pending & ack_mask) != 32'h0000_0000) begin
            `uvm_fatal("P23C_HOST_RT/EVENT_ACK_FAIL",
                $sformatf("Acked event bits still pending: pending=0x%08h ack_mask=0x%08h",
                    snap.pending,
                    ack_mask))
        end

        if ((snap.status & 32'h0000_0007) != 32'h0000_0000) begin
            `uvm_fatal("P23C_HOST_RT/IRQ_STILL_SET",
                $sformatf("Pending/eligible/IRQ status bits still set after ack: status=0x%08h",
                    snap.status))
        end

        `uvm_info("P23C_HOST_RT/CHECK",
            $sformatf("Runtime cleanup after CQ consume + event ack PASS: pending=0x%08h status=0x%08h",
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
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t event_snap;
        logic [31:0] event_mask;
        logic [31:0] ack_mask;
    begin
        phase.raise_objection(this);

        `uvm_info("P23C_HOST_RT/START",
            "Starting P23C event-driven single queue command smoke test",
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
            `uvm_fatal("P23C_HOST_RT/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        program_memory_descriptor(
            P17D_DESC_BASE + (0 * P17D_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            32'hD18E_0000
        );

        program_memory_descriptor(
            P17D_DESC_BASE + (1 * P17D_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            32'hD18E_0001
        );

        rt.make_default_queue_cfg(
            cfg,
            32'(P23C_SQ_BASE),
            32'(P23C_CQ_BASE),
            32'(P23C_QUEUE_DEPTH),
            1'b0
        );

        rt.make_fetch_recipe_cmd(
            cmd,
            32'(P17D_DESC_BASE),
            32'h0000_0002,
            32'(P17D_DESC_STRIDE),
            P23C_CMD_TAG,
            1'b1,
            1'b0
        );

        event_mask = rt.queue_completion_event_mask();

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();

        csr_program_completion_wb();

        rt.initialize_runtime(cfg, event_mask, 1'b1);

        csr_check_recipe_idle_ready("before event-driven queue START");

        rt.submit_command_and_doorbell(cfg, 0, cmd, 32'h0000_0001);
        rt.start_queue();

        // The host runtime does not poll the lower-level descriptor / recipe /
        // completion engines here.  It waits for the P22 event summary, then
        // consumes the CQ record as a driver would.
        rt.wait_events(event_mask, event_snap, done_timeout_cycles * 4, 1'b1);
        check_event_snapshot_before_ack(event_snap, event_mask);

        rt.wait_cq_commit(cfg, 0, rec, done_timeout_cycles * 4);
        check_runtime_cq_record(rec, profile_item);

        // Cross-check using the legacy P19E CQ record checker as a guardrail.
        check_queue_completion_record(profile_item);
        check_queue_state_before_consume();

        ack_mask = event_snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.consume_cq_entry(cfg, 0, 1'b1);
        rt.ack_events(ack_mask);
        check_runtime_cleanup_after_consume(ack_mask);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P23C_HOST_RT/PASS",
            $sformatf("P23C event-driven single queue command completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d event_mask=0x%08h ack_mask=0x%08h",
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
