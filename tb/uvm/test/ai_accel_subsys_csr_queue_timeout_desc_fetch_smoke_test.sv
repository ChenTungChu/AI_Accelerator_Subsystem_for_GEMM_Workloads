// File: tb/uvm/test/ai_accel_subsys_csr_queue_timeout_desc_fetch_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_TIMEOUT_DESC_FETCH_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_TIMEOUT_DESC_FETCH_SMOKE_TEST_SV

// ============================================================
// P24D queue timeout / descriptor-fetch watchdog smoke
//
// Scope:
//   - Validates the P24C queue watchdog from the CSR/UVM level.
//   - Uses the existing P23 event-driven host runtime helper.
//   - First subcase proves CMD_TIMEOUT_CYCLES=0 preserves the
//     already-validated normal event-driven queue completion path.
//   - Second subcase programs a valid SQ command with a very small
//     CMD_TIMEOUT_CYCLES budget and verifies that the queue reports
//     COMMAND_TIMEOUT_ERROR through CSR_QUEUE_ERROR_STATUS[6], records
//     a P24 timeout detail code, raises the P22 QUEUE_ERROR_EVENT, and
//     does not commit a normal CQ completion record.
//
// This test does not add RTL, new CSR addresses, new CQ format, a
// standalone timeout interface, a new simulation flow, or BRAM/GEMM/
// DMA/frontend datapath changes.
//
// CODE-COV-C1.2-G7-G3 note:
//   Current clock-sampled watchdog timing makes P24 0x0C COMMAND_TIMEOUT a
//   defensive phase label without a legal sampled producer in this integration.
//   G7-G3 therefore targets the genuine 0x0E RECIPE timeout and preserves 0x0C
//   for waiver disposition after source/timing evidence review.
// ============================================================

class ai_accel_subsys_csr_queue_timeout_desc_fetch_smoke_test
    extends ai_accel_subsys_csr_event_driven_cq_full_stop_error_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_timeout_desc_fetch_smoke_test)

    localparam int unsigned P24D_QUEUE_DEPTH          = 4;
    localparam int unsigned P24D_DESC_STRIDE          = 32'h0000_0080;

    localparam int unsigned P24D_NORMAL_SQ_BASE       = 32'h0000_0D00;
    localparam int unsigned P24D_NORMAL_CQ_BASE       = 32'h0000_0E00;
    localparam int unsigned P24D_NORMAL_DESC_BASE     = 32'h0000_0700;

    localparam int unsigned P24D_TIMEOUT_SQ_BASE      = 32'h0000_0F00;
    // Keep CQ base inside the existing destination-memory range.
    // The previous 0x1000 boundary address can read back X on memory models
    // sized as 0x0000-0x0FFF, even when CQ_TAIL correctly remains zero.
    localparam int unsigned P24D_TIMEOUT_CQ_BASE      = 32'h0000_0F00;
    localparam int unsigned P24D_TIMEOUT_DESC_BASE    = 32'h0000_0800;

    localparam logic [31:0] P24D_NORMAL_CMD_TAG       = 32'hD24D_0000;
    localparam logic [31:0] P24D_NORMAL_DESC_TAG0     = 32'hD24D_1000;
    localparam logic [31:0] P24D_NORMAL_DESC_TAG1     = 32'hD24D_1001;

    localparam logic [31:0] P24D_TIMEOUT_CMD_TAG      = 32'hD24D_E000;
    localparam logic [31:0] P24D_TIMEOUT_DESC_TAG0    = 32'hD24D_2000;
    localparam logic [31:0] P24D_TIMEOUT_DESC_TAG1    = 32'hD24D_2001;

    localparam logic [31:0] G7_G3_RECIPE_TIMEOUT_CMD_TAG = 32'hD24D_E002;

    localparam int unsigned P24D_SHORT_TIMEOUT_CYCLES = 4;

    localparam int unsigned P24D_QUEUE_TIMEOUT_ERR_BIT = 6;

    localparam logic [7:0] P24D_DETAIL_COMMAND_TIMEOUT          = 8'h0C;
    localparam logic [7:0] P24D_DETAIL_TIMEOUT_IN_DESC_FETCH    = 8'h0D;
    localparam logic [7:0] P24D_DETAIL_TIMEOUT_IN_RECIPE        = 8'h0E;
    localparam logic [7:0] P24D_DETAIL_TIMEOUT_IN_COMPLETION_WB = 8'h0F;
    localparam logic [7:0] P24D_DETAIL_TIMEOUT_IN_QUEUE_ADVANCE = 8'h10;

    function new(string name = "ai_accel_subsys_csr_queue_timeout_desc_fetch_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function automatic bit p24d_is_timeout_detail_code(input logic [7:0] detail_code);
    begin
        p24d_is_timeout_detail_code =
            (detail_code == P24D_DETAIL_COMMAND_TIMEOUT)          ||
            (detail_code == P24D_DETAIL_TIMEOUT_IN_DESC_FETCH)    ||
            (detail_code == P24D_DETAIL_TIMEOUT_IN_RECIPE)        ||
            (detail_code == P24D_DETAIL_TIMEOUT_IN_COMPLETION_WB) ||
            (detail_code == P24D_DETAIL_TIMEOUT_IN_QUEUE_ADVANCE);
    end
    endfunction

    task automatic program_p24d_descriptor_table(
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
            desc_base + (0 * P24D_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            first_tag
        );

        program_memory_descriptor(
            desc_base + (1 * P24D_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            second_tag
        );
    end
    endtask

    task automatic wait_p24d_timeout_error(
        input  logic [31:0] expected_last_tag,
        output logic [31:0] error_status_o,
        output logic [31:0] error_detail_o,
        output logic [31:0] cq_tail_o,
        input  int unsigned timeout_cycles
    );
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] reject_status;
        logic [31:0] sq_head;
        logic [31:0] cq_occ;
        logic [31:0] last_tag;
        int unsigned cnt;
    begin
        cnt = 0;
        error_status_o = 32'h0000_0000;
        error_detail_o = 32'h0000_0000;
        cq_tail_o      = 32'h0000_0000;

        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS,        status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS,   done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,  error_status_o);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_DETAIL,  error_detail_o);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,       sq_head);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,       cq_tail_o);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY,  cq_occ);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG,  last_tag);

            if (error_status_o[P24D_QUEUE_TIMEOUT_ERR_BIT]) begin
                if (last_tag !== expected_last_tag) begin
                    `uvm_fatal("P24D_TIMEOUT/LAST_TAG",
                        $sformatf("Timeout reported for unexpected command tag: last_tag=0x%08h expected=0x%08h status=0x%08h done=0x%08h error=0x%08h detail=0x%08h",
                            last_tag,
                            expected_last_tag,
                            status,
                            done_status,
                            error_status_o,
                            error_detail_o))
                end

                if (!p24d_is_timeout_detail_code(error_detail_o[7:0])) begin
                    `uvm_fatal("P24D_TIMEOUT/DETAIL",
                        $sformatf("Unexpected P24 timeout detail code: detail=0x%08h code=0x%02h",
                            error_detail_o,
                            error_detail_o[7:0]))
                end

                if (reject_status != 32'h0000_0000) begin
                    `uvm_fatal("P24D_TIMEOUT/REJECT",
                        $sformatf("Timeout command should be valid and should not set reject_status: reject=0x%08h status=0x%08h error=0x%08h detail=0x%08h",
                            reject_status,
                            status,
                            error_status_o,
                            error_detail_o))
                end

                `uvm_info("P24D_TIMEOUT/OBSERVED",
                    $sformatf("Queue timeout observed after %0d poll(s): status=0x%08h done=0x%08h error=0x%08h detail=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h last_tag=0x%08h",
                        cnt,
                        status,
                        done_status,
                        error_status_o,
                        error_detail_o,
                        sq_head,
                        cq_tail_o,
                        cq_occ,
                        last_tag),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P24D_TIMEOUT/WAIT",
                    $sformatf("Timeout waiting for COMMAND_TIMEOUT_ERROR bit: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h detail=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h last_tag=0x%08h",
                        status,
                        done_status,
                        error_status_o,
                        reject_status,
                        error_detail_o,
                        sq_head,
                        cq_tail_o,
                        cq_occ,
                        last_tag))
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G7-G3-C deterministic timeout-phase calibration
    //
    // The control interface signals below are passive observations wired
    // by the existing CSR UVM top.  They do not drive DUT state.  Measuring
    // the accepted descriptor-start -> handoff -> recipe-busy distance in
    // the timeout-disabled reference command avoids guessing a watchdog
    // budget.  The handoff observation is a post-edge phase marker only;
    // the watchdog detail is captured synchronously on a later clock edge,
    // so the all-idle handoff phase is not itself a capturable 0x0C detail.
    // ------------------------------------------------------------
    task automatic g7_g3_measure_timeout_phase_budgets(
        output int unsigned handoff_timeout_budget,
        output int unsigned recipe_timeout_budget
    );
        int unsigned cycle_index;
    begin
        handoff_timeout_budget = 0;
        recipe_timeout_budget  = 0;

        while (p17d_ctrl_vif.desc_fetch_start_to_engine_obs !== 1'b1) begin
            @(posedge p17d_ctrl_vif.clk);
            #1ps;
        end

        // Budget=1 would assert the watchdog threshold from this accepted-start epoch.
        cycle_index = 0;

        while (p17d_ctrl_vif.desc_fetch_recipe_start_pulse_obs !== 1'b1) begin
            @(posedge p17d_ctrl_vif.clk);
            #1ps;
            cycle_index++;
            if (cycle_index > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1_2G7_G3/TIMEOUT_CAL_HANDOFF",
                    "Timed out while calibrating descriptor-to-recipe handoff budget")
            end
        end

        if ((p17d_ctrl_vif.desc_fetch_busy_obs === 1'b1) ||
            (p17d_ctrl_vif.recipe_busy_obs === 1'b1)) begin
            `uvm_fatal("CODE_COV_C1_2G7_G3/TIMEOUT_CAL_HANDOFF_PHASE",
                $sformatf("Handoff observation is not the expected all-idle post-edge phase: desc_busy=%0b recipe_busy=%0b cycle=%0d",
                    p17d_ctrl_vif.desc_fetch_busy_obs,
                    p17d_ctrl_vif.recipe_busy_obs,
                    cycle_index))
        end

        handoff_timeout_budget = cycle_index + 1;

        while (p17d_ctrl_vif.recipe_busy_obs !== 1'b1) begin
            @(posedge p17d_ctrl_vif.clk);
            #1ps;
            cycle_index++;
            if (cycle_index > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1_2G7_G3/TIMEOUT_CAL_RECIPE",
                    "Timed out while calibrating recipe-busy watchdog budget")
            end
        end

        if (p17d_ctrl_vif.desc_fetch_busy_obs === 1'b1) begin
            `uvm_fatal("CODE_COV_C1_2G7_G3/TIMEOUT_CAL_RECIPE_PHASE",
                $sformatf("Recipe calibration cycle still reports desc_fetch_busy: cycle=%0d", cycle_index))
        end

        recipe_timeout_budget = cycle_index + 1;

        if (recipe_timeout_budget <= handoff_timeout_budget) begin
            `uvm_fatal("CODE_COV_C1_2G7_G3/TIMEOUT_CAL_ORDER",
                $sformatf("Invalid calibrated timeout budget order: handoff=%0d recipe=%0d",
                    handoff_timeout_budget,
                    recipe_timeout_budget))
        end

        `uvm_info("CODE_COV_C1_2G7_G3/TIMEOUT_CAL_PASS",
            $sformatf("Calibrated watchdog phase markers from passive observation: handoff=%0d recipe=%0d",
                handoff_timeout_budget,
                recipe_timeout_budget),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // G7-G3-C reusable timeout-probe cleanup
    //
    // Recipe sticky masks cross the recipe-runner -> CSR boundary.  A
    // single clear pulse can leave a one-cycle CSR-visible OR residue
    // from a just-completed previous recipe.  Clear twice and verify
    // that the next timeout probe starts from a zero-sticky recipe
    // baseline.  This is architectural CSR cleanup only; no force or
    // hierarchical state corruption is used.
    // ------------------------------------------------------------
    task automatic g7_g3_clear_for_timeout_probe(input string label);
        logic [31:0] recipe_done_status;
        logic [31:0] recipe_error_status;
        logic [31:0] recipe_reject_status;
        logic [31:0] recipe_slot_done_mask;
        logic [31:0] recipe_slot_error_mask;
        logic [31:0] recipe_slot_reject_mask;
    begin
        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        repeat (6) @(posedge csr_vif.clk);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        repeat (6) @(posedge csr_vif.clk);

        csr_check_recipe_idle_ready(label);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_DONE_STATUS, recipe_done_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_ERROR_STATUS, recipe_error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS, recipe_reject_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_DONE_MASK, recipe_slot_done_mask);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_ERROR_MASK, recipe_slot_error_mask);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_REJECT_MASK, recipe_slot_reject_mask);

        if ((recipe_done_status != 32'h0000_0000) ||
            (recipe_error_status != 32'h0000_0000) ||
            (recipe_reject_status != 32'h0000_0000) ||
            (recipe_slot_done_mask != 32'h0000_0000) ||
            (recipe_slot_error_mask != 32'h0000_0000) ||
            (recipe_slot_reject_mask != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1_2G7_G3/TIMEOUT_PRECLEAN",
                $sformatf("%s: timeout-probe pre-clean left recipe sticky residue: done=0x%08h error=0x%08h reject=0x%08h masks(done/error/reject)=0x%08h/0x%08h/0x%08h",
                    label,
                    recipe_done_status,
                    recipe_error_status,
                    recipe_reject_status,
                    recipe_slot_done_mask,
                    recipe_slot_error_mask,
                    recipe_slot_reject_mask))
        end
    end
    endtask

    task automatic p24d_case_timeout_disabled_normal_completion(
        input  ai_accel_event_driven_host_runtime_helper rt,
        input  ai_accel_subsys_seq_item                 profile_item,
        output int unsigned                              handoff_timeout_budget,
        output int unsigned                              recipe_timeout_budget
    );
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t       cfg;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t          cmd;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t       rec;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t  snap;
        logic [31:0] event_required;
        logic [31:0] ack_mask;
    begin
        `uvm_info("P24D_CASE/TIMEOUT_DISABLED",
            "Starting CMD_TIMEOUT_CYCLES=0 compatibility case",
            UVM_MEDIUM)

        rt.make_default_queue_cfg(
            cfg,
            32'(P24D_NORMAL_SQ_BASE),
            32'(P24D_NORMAL_CQ_BASE),
            32'(P24D_QUEUE_DEPTH),
            1'b1
        );

        rt.make_fetch_recipe_cmd(
            cmd,
            32'(P24D_NORMAL_DESC_BASE),
            32'h0000_0002,
            32'(P24D_DESC_STRIDE),
            P24D_NORMAL_CMD_TAG,
            1'b1,
            1'b0
        );
        cmd.timeout_cycles = 32'h0000_0000;

        event_required = rt.queue_completion_event_mask() |
                         rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);

        csr_queue_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        rt.initialize_runtime(cfg, event_required, 1'b1);

        csr_check_recipe_idle_ready("before P24D timeout-disabled START");

        rt.write_sq_command(cfg, 0, cmd, 1'b1);
        rt.ring_sq_tail(32'h0000_0001);

        fork
            begin
                g7_g3_measure_timeout_phase_budgets(
                    handoff_timeout_budget,
                    recipe_timeout_budget
                );
            end
            begin
                rt.start_queue();
            end
        join

        rt.wait_events(event_required, snap, done_timeout_cycles * 8, 1'b1);
        expect_p23f_event_snapshot("P24D timeout disabled normal completion", snap, event_required, 1'b1);

        rt.wait_cq_commit(cfg, 0, rec, done_timeout_cycles * 4);
        check_p23d_cq_record(0, rec, profile_item, P24D_NORMAL_DESC_TAG0, P24D_NORMAL_DESC_TAG1);

        ack_mask = snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.consume_cq_entry(cfg, 0, 1'b1);
        rt.ack_events(ack_mask);
        check_p23f_event_cleanup("P24D timeout disabled normal completion", ack_mask);

        `uvm_info("P24D_TIMEOUT/DISABLED_PASS",
            "CMD_TIMEOUT_CYCLES=0 preserved normal event-driven queue completion",
            UVM_MEDIUM)
    end
    endtask

    task automatic p24d_case_descriptor_fetch_timeout(
        input ai_accel_event_driven_host_runtime_helper rt
    );
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t       cfg;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t          cmd;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t  snap;
        logic [31:0] event_required;
        logic [31:0] ack_mask;
        logic [31:0] error_status;
        logic [31:0] error_detail;
        logic [31:0] cq_tail;
        logic [31:0] cq_commit_word;
    begin
        `uvm_info("P24D_CASE/DESC_FETCH_TIMEOUT",
            "Starting descriptor-fetch watchdog timeout case",
            UVM_MEDIUM)

        rt.make_default_queue_cfg(
            cfg,
            32'(P24D_TIMEOUT_SQ_BASE),
            32'(P24D_TIMEOUT_CQ_BASE),
            32'(P24D_QUEUE_DEPTH),
            1'b0
        );

        rt.make_fetch_recipe_cmd(
            cmd,
            32'(P24D_TIMEOUT_DESC_BASE),
            32'h0000_0002,
            32'(P24D_DESC_STRIDE),
            P24D_TIMEOUT_CMD_TAG,
            1'b1,
            1'b0
        );
        cmd.timeout_cycles = 32'(P24D_SHORT_TIMEOUT_CYCLES);

        event_required = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_ERROR);

        g7_g3_clear_for_timeout_probe("before P24D descriptor-fetch timeout START");
        rt.initialize_runtime(cfg, event_required, 1'b1);

        csr_check_recipe_idle_ready("before P24D timeout START");

        rt.write_sq_command(cfg, 0, cmd, 1'b1);
        rt.ring_sq_tail(32'h0000_0001);
        rt.start_queue();

        wait_p24d_timeout_error(
            P24D_TIMEOUT_CMD_TAG,
            error_status,
            error_detail,
            cq_tail,
            done_timeout_cycles * 2
        );

        if (cq_tail !== 32'h0000_0000) begin
            `uvm_fatal("P24D_TIMEOUT/CQ_TAIL",
                $sformatf("Timeout should not report a normal CQ commit in P24D: cq_tail=0x%08h error=0x%08h detail=0x%08h",
                    cq_tail,
                    error_status,
                    error_detail))
        end

        rt.read_dst_word_le(P24D_TIMEOUT_CQ_BASE, cq_commit_word);
        if (cq_commit_word !== 32'h0000_0000) begin
            `uvm_fatal("P24D_TIMEOUT/CQ_COMMIT",
                $sformatf("Timeout CQ slot should remain uncommitted in P24D: commit_word=0x%08h error=0x%08h detail=0x%08h",
                    cq_commit_word,
                    error_status,
                    error_detail))
        end

        rt.wait_events(event_required, snap, done_timeout_cycles * 2, 1'b1);
        expect_p23f_event_snapshot("P24D QUEUE_ERROR timeout", snap, event_required, 1'b1);

        ack_mask = snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.ack_events(ack_mask);
        check_p23f_event_cleanup("P24D QUEUE_ERROR timeout", ack_mask);

        // Drain the already-started legal lower stack before the next
        // G7-G3 calibrated timeout case reuses the queue/descriptor path.
        csr_poll_desc_fetch_done(done_timeout_cycles * 2);
        csr_poll_recipe_done(done_timeout_cycles * 4);

        g7_g3_clear_for_timeout_probe("after P24D descriptor-fetch timeout drain");

        `uvm_info("P24D_TIMEOUT/DESC_FETCH_PASS",
            $sformatf("Descriptor-fetch watchdog timeout PASS: error_status=0x%08h detail=0x%08h cq_tail=0x%08h",
                error_status,
                error_detail,
                cq_tail),
            UVM_MEDIUM)
    end
    endtask

    task automatic g7_g3_case_exact_timeout_detail(
        input ai_accel_event_driven_host_runtime_helper rt,
        input logic [31:0] expected_cmd_tag,
        input int unsigned timeout_budget,
        input logic [7:0]  expected_detail_code,
        input string       pass_id,
        input string       label
    );
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t       cfg;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t          cmd;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t  snap;
        logic [31:0] event_required;
        logic [31:0] ack_mask;
        logic [31:0] error_status;
        logic [31:0] error_detail;
        logic [31:0] cq_tail;
        logic [31:0] cq_commit_word;
    begin
        if (timeout_budget == 0) begin
            `uvm_fatal("CODE_COV_C1_2G7_G3/TIMEOUT_BUDGET_ZERO",
                $sformatf("%s: calibrated timeout budget must be non-zero", label))
        end

        `uvm_info("CODE_COV_C1_2G7_G3/TIMEOUT_CASE",
            $sformatf("%s: starting exact timeout-detail case budget=%0d expected_detail=0x%02h",
                label,
                timeout_budget,
                expected_detail_code),
            UVM_MEDIUM)

        rt.make_default_queue_cfg(
            cfg,
            32'(P24D_TIMEOUT_SQ_BASE),
            32'(P24D_TIMEOUT_CQ_BASE),
            32'(P24D_QUEUE_DEPTH),
            1'b0
        );

        rt.make_fetch_recipe_cmd(
            cmd,
            32'(P24D_TIMEOUT_DESC_BASE),
            32'h0000_0002,
            32'(P24D_DESC_STRIDE),
            expected_cmd_tag,
            1'b1,
            1'b0
        );
        cmd.timeout_cycles = 32'(timeout_budget);

        event_required = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_ERROR);

        g7_g3_clear_for_timeout_probe({"before ", label});
        rt.initialize_runtime(cfg, event_required, 1'b1);

        csr_check_recipe_idle_ready({"before ", label});

        rt.write_sq_command(cfg, 0, cmd, 1'b1);
        rt.ring_sq_tail(32'h0000_0001);
        rt.start_queue();

        wait_p24d_timeout_error(
            expected_cmd_tag,
            error_status,
            error_detail,
            cq_tail,
            done_timeout_cycles * 2
        );

        if (error_detail[7:0] !== expected_detail_code) begin
            `uvm_fatal("CODE_COV_C1_2G7_G3/TIMEOUT_DETAIL_MISMATCH",
                $sformatf("%s: expected timeout detail 0x%02h, got detail=0x%08h budget=%0d",
                    label,
                    expected_detail_code,
                    error_detail,
                    timeout_budget))
        end

        if (cq_tail !== 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1_2G7_G3/TIMEOUT_CQ_TAIL",
                $sformatf("%s: timeout unexpectedly advanced CQ tail: cq_tail=0x%08h",
                    label,
                    cq_tail))
        end

        rt.read_dst_word_le(P24D_TIMEOUT_CQ_BASE, cq_commit_word);
        if (cq_commit_word !== 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1_2G7_G3/TIMEOUT_CQ_COMMIT",
                $sformatf("%s: timeout CQ slot should remain uncommitted: commit_word=0x%08h",
                    label,
                    cq_commit_word))
        end

        rt.wait_events(event_required, snap, done_timeout_cycles * 2, 1'b1);
        expect_p23f_event_snapshot({label, " QUEUE_ERROR event"}, snap, event_required, 1'b1);

        ack_mask = snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.ack_events(ack_mask);
        check_p23f_event_cleanup({label, " QUEUE_ERROR event"}, ack_mask);

        // A P24 timeout terminates queue ownership, but it intentionally
        // does not force-corrupt or asynchronously abort the already-started
        // lower stack.  Drain the legal descriptor/recipe work before reuse.
        csr_poll_desc_fetch_done(done_timeout_cycles * 2);
        csr_poll_recipe_done(done_timeout_cycles * 4);

        g7_g3_clear_for_timeout_probe({label, " post-timeout cleanup"});

        `uvm_info(pass_id,
            $sformatf("%s PASS: budget=%0d detail=0x%08h error_status=0x%08h",
                label,
                timeout_budget,
                error_detail,
                error_status),
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
        int unsigned g7_g3_handoff_timeout_budget;
        int unsigned g7_g3_recipe_timeout_budget;
    begin
        phase.raise_objection(this);

        `uvm_info("P24D_TIMEOUT/START",
            "Starting P24D queue timeout / descriptor-fetch watchdog smoke test",
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
            `uvm_fatal("P24D_TIMEOUT/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        program_p24d_descriptor_table(P24D_NORMAL_DESC_BASE,  P24D_NORMAL_DESC_TAG0,  P24D_NORMAL_DESC_TAG1,  profile_item, a_flat.size(), b_flat.size(), c_bytes);
        program_p24d_descriptor_table(P24D_TIMEOUT_DESC_BASE, P24D_TIMEOUT_DESC_TAG0, P24D_TIMEOUT_DESC_TAG1, profile_item, a_flat.size(), b_flat.size(), c_bytes);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_program_completion_wb();

        p24d_case_timeout_disabled_normal_completion(
            rt,
            profile_item,
            g7_g3_handoff_timeout_budget,
            g7_g3_recipe_timeout_budget
        );
        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        // Preserve the original P24D early descriptor-fetch timeout case.
        p24d_case_descriptor_fetch_timeout(rt);

        // G7-G3-C corrected reachability disposition:
        //   - P24_DETAIL_TIMEOUT_IN_RECIPE (0x0E) is genuinely reachable.
        //   - P24_DETAIL_COMMAND_TIMEOUT (0x0C) is not targeted here.  The
        //     apparent desc-fetch->recipe all-idle handoff exists only as a
        //     post-edge observation; the watchdog error/detail is captured
        //     synchronously, so the adjacent clock-sampled phases transition
        //     from DESC_FETCH (0x0D) directly to RECIPE (0x0E).
        // The handoff marker is retained as evidence, while the recipe-busy
        // marker is used for the genuine targeted closure.
        `uvm_info("CODE_COV_C1_2G7_G3/COMMAND_TIMEOUT_RECLASS_EVIDENCE",
            $sformatf("Clock-sampled timeout classification skips the post-edge all-idle handoff: handoff_marker=%0d recipe_marker=%0d; line 1015 is a waiver candidate, not a stimulus target",
                g7_g3_handoff_timeout_budget,
                g7_g3_recipe_timeout_budget),
            UVM_MEDIUM)

        g7_g3_case_exact_timeout_detail(
            rt,
            G7_G3_RECIPE_TIMEOUT_CMD_TAG,
            g7_g3_recipe_timeout_budget,
            P24D_DETAIL_TIMEOUT_IN_RECIPE,
            "CODE_COV_C1_2G7_G3/RECIPE_TIMEOUT_PASS",
            "G7-G3 recipe-busy timeout"
        );

        `uvm_info("CODE_COV_C1_2G7_G3/TIMEOUT_SUITE_PASS",
            $sformatf("G7-G3 timeout detail suite completed: handoff_marker=%0d recipe_budget=%0d; 0x0E targeted, 0x0C reclassified unreachable",
                g7_g3_handoff_timeout_budget,
                g7_g3_recipe_timeout_budget),
            UVM_MEDIUM)

        `uvm_info("P24D_TIMEOUT/PASS",
            $sformatf("P24D queue timeout watchdog smoke completed: CASE_ID=%0d timeout_cycles=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
                selected_case_id,
                P24D_SHORT_TIMEOUT_CYCLES,
                a_flat.size(),
                b_flat.size(),
                c_elems),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
