// File: tb/uvm/test/ai_accel_subsys_csr_queue_timeout_completion_wb_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_TIMEOUT_COMPLETION_WB_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_TIMEOUT_COMPLETION_WB_SMOKE_TEST_SV

// ============================================================
// P24E completion-writeback timeout / blocked completion smoke
//
// Scope:
//   - Extends the P24D queue watchdog validation into the P18
//     completion-writeback phase.
//   - Uses the existing P23 event-driven host runtime helper.
//   - Uses a TB-only comp_wb_inject_if block mode to accept the
//     completion AW/W handshake but withhold BRESP.
//   - Verifies that the queue watchdog expires while completion
//     writeback is active, reports COMMAND_TIMEOUT_ERROR, records
//     DETAIL_TIMEOUT_IN_COMPLETION_WB, raises P22 QUEUE_ERROR_EVENT,
//     and does not advance CQ_TAIL.
//
// This test does not add RTL datapath behavior, new CSR addresses,
// a new CQ format, a new simulation flow, or BRAM/GEMM/DMA/frontend
// changes.  The completion-response block is TB-only stimulus.
// ============================================================

class ai_accel_subsys_csr_queue_timeout_completion_wb_smoke_test
    extends ai_accel_subsys_csr_queue_timeout_desc_fetch_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_timeout_completion_wb_smoke_test)

    virtual comp_wb_inject_if comp_wb_inject_vif;

    localparam int unsigned P24E_QUEUE_DEPTH             = 4;
    localparam int unsigned P24E_DESC_STRIDE             = 32'h0000_0080;

    localparam int unsigned P24E_SQ_BASE                 = 32'h0000_0B00;
    localparam int unsigned P24E_CQ_BASE                 = 32'h0000_0C00;
    localparam int unsigned P24E_DESC_BASE               = 32'h0000_0700;

    localparam logic [31:0] P24E_CMD_TAG                 = 32'hD24E_0000;
    localparam logic [31:0] P24E_DESC_TAG0               = 32'hD24E_1000;
    localparam logic [31:0] P24E_DESC_TAG1               = 32'hD24E_1001;

    // The budget is intentionally longer than the normal descriptor-fetch /
    // recipe path for CASE_ID=102, so the watchdog should expire only after
    // automatic completion writeback has started and BRESP has been blocked.
    localparam int unsigned P24E_COMPLETION_TIMEOUT_CYCLES = 8192;

    localparam int unsigned P24E_QUEUE_TIMEOUT_ERR_BIT    = 6;
    localparam logic [7:0]  P24E_DETAIL_TIMEOUT_IN_COMPLETION_WB = 8'h0F;

    function new(string name = "ai_accel_subsys_csr_queue_timeout_completion_wb_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual comp_wb_inject_if)::get(
                this,
                "",
                "comp_wb_inject_vif",
                comp_wb_inject_vif
            )) begin
            `uvm_fatal("P24E_TIMEOUT/NO_COMP_WB_INJECT_VIF",
                "Missing completion-writeback injection virtual interface")
        end
    endfunction

    task automatic p24e_case_blocked_completion_wb_timeout(
        input ai_accel_event_driven_host_runtime_helper rt,
        input ai_accel_subsys_seq_item                 profile_item
    );
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t       cfg;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t          cmd;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t  snap;
        logic [31:0] event_required;
        logic [31:0] ack_mask;
        logic [31:0] error_status;
        logic [31:0] error_detail;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
        logic [31:0] cq_commit_word;
    begin
        `uvm_info("P24E_CASE/COMP_WB_TIMEOUT",
            "Starting completion-writeback blocked-BRESP watchdog timeout case",
            UVM_MEDIUM)

        rt.make_default_queue_cfg(
            cfg,
            32'(P24E_SQ_BASE),
            32'(P24E_CQ_BASE),
            32'(P24E_QUEUE_DEPTH),
            1'b0
        );

        rt.make_fetch_recipe_cmd(
            cmd,
            32'(P24E_DESC_BASE),
            32'h0000_0002,
            32'(P24E_DESC_STRIDE),
            P24E_CMD_TAG,
            1'b1,
            1'b0
        );
        cmd.timeout_cycles = 32'(P24E_COMPLETION_TIMEOUT_CYCLES);

        event_required = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_ERROR);

        csr_queue_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        rt.initialize_runtime(cfg, event_required, 1'b1);

        csr_check_recipe_idle_ready("before P24E completion-writeback timeout START");

        // Block the first completion writeback BRESP.  AW/W are accepted,
        // but the completion-memory responder withholds BVALID, keeping the
        // completion writeback engine busy until the P24 watchdog expires.
        comp_wb_inject_vif.clear();
        comp_wb_inject_vif.set_bresp_block(1'b1, 0);

        rt.write_sq_command(cfg, 0, cmd, 1'b1);
        rt.ring_sq_tail(32'h0000_0001);
        rt.start_queue();

        wait_p24d_timeout_error(
            P24E_CMD_TAG,
            error_status,
            error_detail,
            cq_tail,
            done_timeout_cycles * 8
        );

        if (!error_status[P24E_QUEUE_TIMEOUT_ERR_BIT]) begin
            `uvm_fatal("P24E_TIMEOUT/ERROR_BIT",
                $sformatf("COMMAND_TIMEOUT_ERROR bit was not set: error=0x%08h detail=0x%08h",
                    error_status,
                    error_detail))
        end

        if (error_detail[7:0] !== P24E_DETAIL_TIMEOUT_IN_COMPLETION_WB) begin
            `uvm_fatal("P24E_TIMEOUT/DETAIL",
                $sformatf("Expected DETAIL_TIMEOUT_IN_COMPLETION_WB(0x0F), got detail=0x%08h code=0x%02h",
                    error_detail,
                    error_detail[7:0]))
        end

        if (cq_tail !== 32'h0000_0000) begin
            `uvm_fatal("P24E_TIMEOUT/CQ_TAIL",
                $sformatf("Blocked completion timeout must not advance CQ_TAIL: cq_tail=0x%08h error=0x%08h detail=0x%08h",
                    cq_tail,
                    error_status,
                    error_detail))
        end

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);
        if (cq_occ !== 32'h0000_0000) begin
            `uvm_fatal("P24E_TIMEOUT/CQ_OCC",
                $sformatf("Blocked completion timeout must not increase CQ occupancy: cq_occ=0x%08h error=0x%08h detail=0x%08h",
                    cq_occ,
                    error_status,
                    error_detail))
        end

        rt.read_dst_word_le(P24E_CQ_BASE, cq_commit_word);
        if (cq_commit_word !== 32'h0000_0000) begin
            `uvm_fatal("P24E_TIMEOUT/CQ_COMMIT",
                $sformatf("Blocked completion timeout should leave CQ commit word uncommitted: commit_word=0x%08h error=0x%08h detail=0x%08h",
                    cq_commit_word,
                    error_status,
                    error_detail))
        end

        rt.wait_events(event_required, snap, done_timeout_cycles * 4, 1'b1);
        expect_p23f_event_snapshot("P24E QUEUE_ERROR completion-writeback timeout", snap, event_required, 1'b1);

        ack_mask = snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.ack_events(ack_mask);
        check_p23f_event_cleanup("P24E QUEUE_ERROR completion-writeback timeout", ack_mask);

        // Keep BRESP blocked until the test ends.  This avoids releasing a
        // late OKAY completion into CQ memory after timeout has already been
        // observed.  Each UVM test starts from reset, so this TB-only block
        // state is not carried into later regressions.

        `uvm_info("P24E_TIMEOUT/COMP_WB_PASS",
            $sformatf("Blocked completion-writeback watchdog timeout PASS: error_status=0x%08h detail=0x%08h cq_tail=0x%08h cq_occ=0x%08h",
                error_status,
                error_detail,
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
        int unsigned             c_elems;
        int unsigned             c_bytes;

        ai_accel_event_driven_host_runtime_helper rt;
    begin
        phase.raise_objection(this);

        `uvm_info("P24E_TIMEOUT/START",
            "Starting P24E completion-writeback timeout / blocked completion smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        comp_wb_inject_vif.clear();

        rt = ai_accel_event_driven_host_runtime_helper::type_id::create("rt");
        rt.set_csr(csr);
        rt.set_ctrl_vif(p17d_ctrl_vif);

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P24E_TIMEOUT/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);
        program_p24d_descriptor_table(P24E_DESC_BASE, P24E_DESC_TAG0, P24E_DESC_TAG1, profile_item, a_flat.size(), b_flat.size(), c_bytes);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_program_completion_wb();

        p24e_case_blocked_completion_wb_timeout(rt, profile_item);

        `uvm_info("P24E_TIMEOUT/PASS",
            $sformatf("P24E completion-writeback timeout smoke completed: CASE_ID=%0d timeout_cycles=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
                selected_case_id,
                P24E_COMPLETION_TIMEOUT_CYCLES,
                a_flat.size(),
                b_flat.size(),
                c_elems),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
