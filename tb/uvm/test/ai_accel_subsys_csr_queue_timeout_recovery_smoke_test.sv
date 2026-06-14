// File: tb/uvm/test/ai_accel_subsys_csr_queue_timeout_recovery_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_TIMEOUT_RECOVERY_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_TIMEOUT_RECOVERY_SMOKE_TEST_SV

// ============================================================
// P24F event-driven host timeout recovery smoke
//
// Scope:
//   - Reuses the P24D descriptor-fetch watchdog timeout path as the
//     fault stimulus.
//   - Uses the existing P23 event-driven host runtime helper to observe
//     P22 QUEUE_ERROR_EVENT, acknowledge the event, clear queue timeout
//     sticky status, reinitialize the queue, and submit a valid command.
//   - Verifies that a post-timeout command completes normally, commits a
//     CQ record, advances CQ_TAIL/CQ_OCC, and preserves the existing DMA
//     destination result compare path.
//
// This test does not add RTL, new CSR addresses, a new completion format,
// a new simulation flow, or BRAM/GEMM/DMA/frontend datapath changes.
// ============================================================

class ai_accel_subsys_csr_queue_timeout_recovery_smoke_test
    extends ai_accel_subsys_csr_queue_timeout_desc_fetch_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_timeout_recovery_smoke_test)

    localparam int unsigned P24F_QUEUE_DEPTH               = 4;
    localparam int unsigned P24F_DESC_STRIDE               = 32'h0000_0080;

    localparam int unsigned P24F_SQ_BASE                   = 32'h0000_0B00;
    localparam int unsigned P24F_CQ_BASE                   = 32'h0000_0C00;
    localparam int unsigned P24F_TIMEOUT_DESC_BASE         = 32'h0000_0800;
    localparam int unsigned P24F_RECOVERY_DESC_BASE        = 32'h0000_0700;

    localparam logic [31:0] P24F_TIMEOUT_CMD_TAG           = 32'hD24F_E000;
    localparam logic [31:0] P24F_TIMEOUT_DESC_TAG0         = 32'hD24F_E100;
    localparam logic [31:0] P24F_TIMEOUT_DESC_TAG1         = 32'hD24F_E101;

    localparam logic [31:0] P24F_RECOVERY_CMD_TAG          = 32'hD24F_0000;
    localparam logic [31:0] P24F_RECOVERY_DESC_TAG0        = 32'hD24F_1000;
    localparam logic [31:0] P24F_RECOVERY_DESC_TAG1        = 32'hD24F_1001;

    localparam int unsigned P24F_SHORT_TIMEOUT_CYCLES      = 4;
    localparam int unsigned P24F_RECOVERY_WAIT_CYCLES      = 200000;

    localparam logic [31:0] P24F_QUEUE_LIVE_BUSY_MASK      = 32'h0000_1F01;

    function new(string name = "ai_accel_subsys_csr_queue_timeout_recovery_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p24f_wait_recovery_ready(input string tag,
                                            input int unsigned timeout_cycles = P24F_RECOVERY_WAIT_CYCLES);
        logic [31:0] status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        int unsigned cnt;
    begin
        cnt = 0;

        // First clear the queue-level timeout sticky bits and the lower-level
        // sticky summaries.  The active low-level command may still finish in
        // the background; the loop below waits until the queue-visible live
        // busy sources are also quiescent.
        csr_queue_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();

        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS,        status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,  error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);

            if (((status & P24F_QUEUE_LIVE_BUSY_MASK) == 32'h0000_0000) &&
                (error_status == 32'h0000_0000) &&
                (reject_status == 32'h0000_0000)) begin
                csr_desc_fetch_clear_sticky_status();
                csr_recipe_clear_sticky_status();
                csr_completion_wb_clear_sticky_status();
                csr_queue_clear_sticky_status();

                csr_check_recipe_idle_ready(tag);

                `uvm_info("P24F_TIMEOUT/RECOVERY_READY",
                    $sformatf("%s: queue/lower-level path ready after timeout cleanup: status=0x%08h error=0x%08h reject=0x%08h polls=%0d",
                        tag,
                        status,
                        error_status,
                        reject_status,
                        cnt),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("P24F_TIMEOUT/RECOVERY_READY_TIMEOUT",
                    $sformatf("%s: timeout waiting for queue/lower-level path to become reusable after timeout cleanup: status=0x%08h error=0x%08h reject=0x%08h live_mask=0x%08h",
                        tag,
                        status,
                        error_status,
                        reject_status,
                        status & P24F_QUEUE_LIVE_BUSY_MASK))
            end
        end
    end
    endtask

    task automatic p24f_case_timeout_then_recover(
        input ai_accel_event_driven_host_runtime_helper rt,
        input ai_accel_subsys_seq_item                 profile_item
    );
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t       cfg;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t          timeout_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t          recovery_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t       rec;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t  snap;
        logic [31:0] timeout_event;
        logic [31:0] recovery_events;
        logic [31:0] ack_mask;
        logic [31:0] error_status;
        logic [31:0] error_detail;
        logic [31:0] saved_timeout_detail;
        logic [31:0] reject_status;
        logic [31:0] cq_tail;
        logic [31:0] sq_head;
        logic [31:0] cq_occ;
    begin
        `uvm_info("P24F_CASE/TIMEOUT_RECOVERY",
            "Starting event-driven timeout recovery smoke case",
            UVM_MEDIUM)

        rt.make_default_queue_cfg(
            cfg,
            32'(P24F_SQ_BASE),
            32'(P24F_CQ_BASE),
            32'(P24F_QUEUE_DEPTH),
            1'b0
        );

        rt.make_fetch_recipe_cmd(
            timeout_cmd,
            32'(P24F_TIMEOUT_DESC_BASE),
            32'h0000_0002,
            32'(P24F_DESC_STRIDE),
            P24F_TIMEOUT_CMD_TAG,
            1'b1,
            1'b0
        );
        timeout_cmd.timeout_cycles = 32'(P24F_SHORT_TIMEOUT_CYCLES);

        rt.make_fetch_recipe_cmd(
            recovery_cmd,
            32'(P24F_RECOVERY_DESC_BASE),
            32'h0000_0002,
            32'(P24F_DESC_STRIDE),
            P24F_RECOVERY_CMD_TAG,
            1'b1,
            1'b0
        );
        recovery_cmd.timeout_cycles = 32'h0000_0000;

        timeout_event   = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_ERROR);
        // A successful post-timeout recovery command only requires the
        // completion-visible event pair.  Depending on queue-control policy,
        // the terminal summary may be QUEUE_STOPPED_EVENT (single-command
        // service) or QUEUE_DRAINED_EVENT (drain service).  Requiring drained
        // here over-constrains the recovery proof and can miss a valid
        // completion notification when the queue stops cleanly after one
        // command.
        recovery_events = rt.queue_completion_event_mask();

        // ------------------------------------------------------------
        // Phase 1: force a watchdog timeout and handle it through the
        // event-driven path.
        // ------------------------------------------------------------
        csr_queue_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        rt.initialize_runtime(cfg, timeout_event, 1'b1);

        csr_check_recipe_idle_ready("before P24F timeout START");

        rt.write_sq_command(cfg, 0, timeout_cmd, 1'b1);
        rt.ring_sq_tail(32'h0000_0001);
        rt.start_queue();

        wait_p24d_timeout_error(
            P24F_TIMEOUT_CMD_TAG,
            error_status,
            error_detail,
            cq_tail,
            done_timeout_cycles * 2
        );

        if (!error_status[P24D_QUEUE_TIMEOUT_ERR_BIT]) begin
            `uvm_fatal("P24F_TIMEOUT/ERROR_BIT",
                $sformatf("COMMAND_TIMEOUT_ERROR bit was not set: error=0x%08h detail=0x%08h",
                    error_status,
                    error_detail))
        end

        if (!p24d_is_timeout_detail_code(error_detail[7:0])) begin
            `uvm_fatal("P24F_TIMEOUT/DETAIL",
                $sformatf("Expected a P24 timeout detail code, got detail=0x%08h", error_detail))
        end

        saved_timeout_detail = error_detail;

        if (cq_tail !== 32'h0000_0000) begin
            `uvm_fatal("P24F_TIMEOUT/CQ_TAIL_PRE_RECOVERY",
                $sformatf("Timeout phase must not advance CQ_TAIL before recovery: cq_tail=0x%08h error=0x%08h detail=0x%08h",
                    cq_tail,
                    error_status,
                    error_detail))
        end

        rt.wait_events(timeout_event, snap, done_timeout_cycles * 2, 1'b1);
        expect_p23f_event_snapshot("P24F QUEUE_ERROR timeout before recovery", snap, timeout_event, 1'b1);

        ack_mask = snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.ack_events(ack_mask);
        check_p23f_event_cleanup("P24F QUEUE_ERROR timeout before recovery", ack_mask);

        `uvm_info("P24F_TIMEOUT/TIMEOUT_HANDLED",
            $sformatf("Timeout event handled before recovery: error_status=0x%08h detail=0x%08h cq_tail=0x%08h",
                error_status,
                error_detail,
                cq_tail),
            UVM_MEDIUM)

        // ------------------------------------------------------------
        // Phase 2: clear sticky timeout state and prove that the same
        // event-driven runtime can submit and complete a valid command.
        // ------------------------------------------------------------
        p24f_wait_recovery_ready("after P24F timeout event handling");

        rt.initialize_runtime(cfg, recovery_events, 1'b1);
        csr_check_recipe_idle_ready("before P24F recovery START");

        rt.write_sq_command(cfg, 0, recovery_cmd, 1'b1);
        rt.ring_sq_tail(32'h0000_0001);
        rt.start_queue();

        rt.wait_events(recovery_events, snap, done_timeout_cycles * 8, 1'b1);
        expect_p23f_event_snapshot("P24F post-timeout recovery completion", snap, recovery_events, 1'b1);

        rt.wait_cq_commit(cfg, 0, rec, done_timeout_cycles * 4);
        check_p23d_cq_record(0, rec, profile_item, P24F_RECOVERY_DESC_TAG0, P24F_RECOVERY_DESC_TAG1);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,      sq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,      cq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);
        expect_p23f_eq32("P24F recovery SQ_HEAD", sq_head, 32'h0000_0001);
        expect_p23f_eq32("P24F recovery CQ_TAIL", cq_tail, 32'h0000_0001);
        expect_p23f_eq32("P24F recovery CQ_OCC",  cq_occ,  32'h0000_0001);

        ack_mask = snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.consume_cq_entry(cfg, 0, 1'b1);
        rt.ack_events(ack_mask);
        check_p23f_event_cleanup("P24F post-timeout recovery completion", ack_mask);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,  error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
        if ((error_status != 32'h0000_0000) || (reject_status != 32'h0000_0000)) begin
            `uvm_fatal("P24F_TIMEOUT/POST_RECOVERY_STICKY",
                $sformatf("Post-timeout recovery must leave queue error/reject clear: error=0x%08h reject=0x%08h",
                    error_status,
                    reject_status))
        end

        `uvm_info("P24F_TIMEOUT/RECOVERY_PASS",
            $sformatf("Event-driven timeout recovery PASS: timeout_detail=0x%08h recovery_cq_tail=0x%08h recovery_cq_occ=0x%08h",
                saved_timeout_detail,
                cq_tail,
                cq_occ),
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
    begin
        phase.raise_objection(this);

        `uvm_info("P24F_TIMEOUT/START",
            "Starting P24F event-driven host timeout recovery smoke test",
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
            `uvm_fatal("P24F_TIMEOUT/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        program_p24d_descriptor_table(P24F_TIMEOUT_DESC_BASE,  P24F_TIMEOUT_DESC_TAG0,  P24F_TIMEOUT_DESC_TAG1,  profile_item, a_flat.size(), b_flat.size(), c_bytes);
        program_p24d_descriptor_table(P24F_RECOVERY_DESC_BASE, P24F_RECOVERY_DESC_TAG0, P24F_RECOVERY_DESC_TAG1, profile_item, a_flat.size(), b_flat.size(), c_bytes);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_program_completion_wb();

        p24f_case_timeout_then_recover(rt, profile_item);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P24F_TIMEOUT/PASS",
            $sformatf("P24F event-driven host timeout recovery smoke completed: CASE_ID=%0d timeout_cycles=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
                selected_case_id,
                P24F_SHORT_TIMEOUT_CYCLES,
                a_flat.size(),
                b_flat.size(),
                c_elems),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
