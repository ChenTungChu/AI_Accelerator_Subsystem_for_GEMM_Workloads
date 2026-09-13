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
//     does not publish a normal CQ completion entry through CQ_TAIL.
//
// This test does not add RTL, new CSR addresses, new CQ format, a
// standalone timeout interface, a new simulation flow, or BRAM/GEMM/
// DMA/frontend datapath changes.
//
// CODE-COV-C1.2-G7-G3 / G7-Z4-C1 reconciliation note:
//   Z4-C1 constructive timing evidence supersedes the earlier G7-G3 provisional
//   waiver classification for P24 0x0C COMMAND_TIMEOUT.  A legal watchdog budget
//   immediately before the sampled recipe-busy phase reaches the all-idle
//   descriptor->recipe handoff and produces 0x0C without force/deposit.
//
//   P26 timeout/error recovery is a session-discard policy, not an abort,
//   rollback, or cancellation mechanism.  Therefore a lower-level P18 writeback
//   that was already launched before the queue timeout may legally drain after
//   queue ownership terminates.  The queue publication contract is enforced by
//   CQ_TAIL/CQ_OCCUPANCY; a late physical CQ memory write is diagnostic residue
//   for the discarded session and must not be treated as a published completion.
//
// CODE-COV-C1.2-G7-Z4-C1 note:
//   Reuses passive watchdog calibration to constructively probe the narrow
//   descriptor->recipe and recipe-done timeout boundaries.  The recipe path
//   crosses the independent 10 ns DMA / 14 ns core clock relationship, so a
//   reference command's exact recipe/P18 boundary may shift by a small number
//   of DMA cycles on later command launches.  Z4-C1R2 therefore uses a narrow
//   contiguous timeout-budget window instead of treating one calibrated cycle
//   as an invariant phase point.  Fresh merged FEC remains the authoritative
//   evidence for same-cycle term closure.
//
// CODE-COV-C1.2-G7-Z4-C2-C note:
//   Extends the same legal queue/watchdog flow with passive observation of
//   the exact P18 terminal terms.  It constructively targets:
//     * raw completion commit at the watchdog threshold,
//     * raw completion error at the watchdog threshold,
//     * auto-P18 pending while P18 enable is low, and
//     * auto-P18 pending on the exact timeout-pulse cycle.
//   The 10 ns DMA / 14 ns core relationship is treated as phase-sensitive;
//   terminal probes sweep a compact center-out budget window around passive
//   reference measurements.  No force/deposit or DUT state override is used.
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

    localparam logic [31:0] G7_Z4_C1_HANDOFF_CMD_TAG_BASE    = 32'hD24D_E100;
    localparam logic [31:0] G7_Z4_C1_RECIPE_DONE_CMD_TAG_BASE = 32'hD24D_E110;

    // Last timeout detail observed by the Z4-C1 boundary probe.  This is
    // testbench bookkeeping only and is used to characterize the phase window.
    logic [7:0] g7_z4_c1_last_timeout_detail;

    localparam int unsigned P24D_SHORT_TIMEOUT_CYCLES = 4;

    localparam int unsigned P24D_QUEUE_TIMEOUT_ERR_BIT = 6;

    localparam logic [7:0] P24D_DETAIL_COMMAND_TIMEOUT          = 8'h0C;
    localparam logic [7:0] P24D_DETAIL_TIMEOUT_IN_DESC_FETCH    = 8'h0D;
    localparam logic [7:0] P24D_DETAIL_TIMEOUT_IN_RECIPE        = 8'h0E;
    localparam logic [7:0] P24D_DETAIL_TIMEOUT_IN_COMPLETION_WB = 8'h0F;
    localparam logic [7:0] P24D_DETAIL_TIMEOUT_IN_QUEUE_ADVANCE = 8'h10;

    // CODE-COV-C1.2-G7-Z4-C2-C phase-tolerant terminal probes.
    localparam logic [31:0] G7_Z4_C2_C_CMD_TAG_BASE = 32'hD24D_C200;
    localparam int unsigned G7_Z4_C2_C_PHASE_SPAN   = 6;
    // Canonical P18 CSR offset from rtl/csr/ai_accel_csr_regs.sv.
    localparam int unsigned G7_Z4_C2_C_COMPLETION_WB_CONTROL_ADDR = 32'h0000_0558;

    virtual comp_wb_inject_if comp_wb_inject_vif;

    function new(string name = "ai_accel_subsys_csr_queue_timeout_desc_fetch_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual comp_wb_inject_if)::get(
                this, "", "comp_wb_inject_vif", comp_wb_inject_vif)) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/NO_COMP_WB_INJECT_VIF",
                "comp_wb_inject_vif not found in UVM config DB")
        end
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

    function automatic int signed g7_z4_c2c_centered_delta(
        input int unsigned probe_index
    );
    begin
        if (probe_index == 0) begin
            g7_z4_c2c_centered_delta = 0;
        end else if (probe_index[0]) begin
            g7_z4_c2c_centered_delta = -int'((probe_index + 1) / 2);
        end else begin
            g7_z4_c2c_centered_delta = int'(probe_index / 2);
        end
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
    // budget.  The handoff observation is a post-edge phase marker.  Z4-C1
    // later proved that the legal watchdog budget one cycle before this
    // marker can expire in the all-idle descriptor->recipe boundary and
    // constructively produce the 0x0C COMMAND_TIMEOUT detail.
    // ------------------------------------------------------------
    task automatic g7_g3_measure_timeout_phase_budgets(
        output int unsigned handoff_timeout_budget,
        output int unsigned recipe_timeout_budget,
        output int unsigned recipe_done_collision_budget,
        output int unsigned auto_pending_timeout_budget,
        output int unsigned commit_raw_timeout_budget
    );
        int unsigned cycle_index;
    begin
        handoff_timeout_budget         = 0;
        recipe_timeout_budget          = 0;
        recipe_done_collision_budget   = 0;
        auto_pending_timeout_budget    = 0;
        commit_raw_timeout_budget      = 0;

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

        // Z4-C1 recipe/P18 terminal-boundary calibration:
        // recipe_busy drops when the recipe state enters DONE.  The recipe
        // sequencer raises recipe_done on the following core-domain clock and
        // the CSR-top sequential logic observes that registered pulse in the
        // DMA domain.  Because subsequent commands may launch at a different
        // core/DMA relative phase, the derived value is a REFERENCE point only.
        // Z4-C1R2 sweeps a narrow contiguous budget window ending at this
        // reference instead of assuming center-1/center/center+1 are invariant.
        while (p17d_ctrl_vif.recipe_busy_obs === 1'b1) begin
            @(posedge p17d_ctrl_vif.clk);
            #1ps;
            cycle_index++;
            if (cycle_index > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C1/TIMEOUT_CAL_RECIPE_DONE",
                    "Timed out while calibrating recipe-done timeout boundary")
            end
        end

        if (p17d_ctrl_vif.recipe_busy_obs !== 1'b0) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C1/TIMEOUT_CAL_RECIPE_DONE_PHASE",
                $sformatf("Recipe-done calibration ended with unknown/non-idle recipe_busy=%0b cycle=%0d",
                    p17d_ctrl_vif.recipe_busy_obs,
                    cycle_index))
        end

        recipe_done_collision_budget = cycle_index + 2;

        // C2-C extends the same timeout-disabled reference command through
        // auto-P18 pending and the raw queue completion commit pulse.  These
        // remain reference budgets, not invariant absolute cycles.
        while (p17d_ctrl_vif.completion_wb_auto_pending_obs !== 1'b1) begin
            @(posedge p17d_ctrl_vif.clk);
            #1ps;
            cycle_index++;
            if (cycle_index > (done_timeout_cycles * 4)) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/TIMEOUT_CAL_AUTO_PENDING",
                    "Timed out while calibrating auto-P18 pending reference")
            end
        end

        if ((p17d_ctrl_vif.completion_wb_busy_obs !== 1'b0) ||
            (p17d_ctrl_vif.completion_wb_enable_obs !== 1'b1)) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/TIMEOUT_CAL_AUTO_PENDING_PHASE",
                $sformatf("Auto-P18 pending reference is not pending/idle/enabled: pending=%0b busy=%0b enable=%0b cycle=%0d",
                    p17d_ctrl_vif.completion_wb_auto_pending_obs,
                    p17d_ctrl_vif.completion_wb_busy_obs,
                    p17d_ctrl_vif.completion_wb_enable_obs,
                    cycle_index))
        end

        auto_pending_timeout_budget = cycle_index + 1;

        while (p17d_ctrl_vif.queue_completion_commit_raw_obs !== 1'b1) begin
            @(posedge p17d_ctrl_vif.clk);
            #1ps;
            cycle_index++;
            if (cycle_index > (done_timeout_cycles * 8)) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/TIMEOUT_CAL_COMMIT_RAW",
                    "Timed out while calibrating raw completion-commit reference")
            end
        end

        if (p17d_ctrl_vif.queue_completion_error_raw_obs === 1'b1) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/TIMEOUT_CAL_COMMIT_ERROR",
                "Unexpected raw completion error during normal commit reference")
        end

        commit_raw_timeout_budget = cycle_index + 1;

        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_C/CAL_EXT_PASS",
            $sformatf("Extended passive watchdog references: auto_pending=%0d commit_raw=%0d",
                auto_pending_timeout_budget,
                commit_raw_timeout_budget),
            UVM_MEDIUM)

        `uvm_info("CODE_COV_C1_2G7_G3/TIMEOUT_CAL_PASS",
            $sformatf("Calibrated watchdog phase markers from passive observation: handoff=%0d recipe=%0d recipe_done_center=%0d",
                handoff_timeout_budget,
                recipe_timeout_budget,
                recipe_done_collision_budget),
            UVM_MEDIUM)

        `uvm_info("CODE_COV_C1P2_G7_Z4_C1/CAL_PASS",
            $sformatf("Z4-C1 legal timeout-boundary centers: handoff=%0d recipe_done=%0d",
                handoff_timeout_budget,
                recipe_done_collision_budget),
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
        output int unsigned                              recipe_timeout_budget,
        output int unsigned                              recipe_done_collision_budget,
        output int unsigned                              auto_pending_timeout_budget,
        output int unsigned                              commit_raw_timeout_budget
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
                    recipe_timeout_budget,
                    recipe_done_collision_budget,
                    auto_pending_timeout_budget,
                    commit_raw_timeout_budget
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

    // ------------------------------------------------------------
    // Z4-C1 lower-level quiescence helper.
    //
    // P26 timeout/error cleanup is session-discard, not cancellation.  A P18
    // transaction that was already launched before the queue timeout may still
    // drain.  Wait for P18 BUSY to clear before deciding whether a physical CQ
    // word is merely discarded-session residue or a live published completion.
    // ------------------------------------------------------------
    task automatic g7_z4_c1_wait_completion_wb_idle(input string label);
        logic [31:0] comp_status;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_COMPLETION_WB_STATUS,
                comp_status
            );

            if (!comp_status[0]) begin
                `uvm_info("CODE_COV_C1P2_G7_Z4_C1/P18_IDLE",
                    $sformatf("%s: completion-writeback lower stack is idle after %0d poll(s), status=0x%08h",
                        label, cnt, comp_status),
                    UVM_HIGH)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > (done_timeout_cycles * 4)) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C1/P18_IDLE_TIMEOUT",
                    $sformatf("%s: completion-writeback did not quiesce, status=0x%08h",
                        label, comp_status))
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G7-Z4-C1 narrow timeout-boundary probe
    //
    // Each call uses only a legal SQ timeout budget.  It intentionally does
    // not claim the target FEC collision from functional logging alone;
    // fresh merged coverage is the authoritative collision evidence.
    // ------------------------------------------------------------
    task automatic g7_z4_c1_case_timeout_boundary_probe(
        input ai_accel_event_driven_host_runtime_helper rt,
        input logic [31:0] expected_cmd_tag,
        input int unsigned timeout_budget,
        input logic [7:0]  expected_detail_code,
        input bit          allow_late_physical_cq_commit,
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
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C1/BUDGET_ZERO",
                $sformatf("%s: timeout budget must be non-zero", label))
        end

        `uvm_info("CODE_COV_C1P2_G7_Z4_C1/PROBE_START",
            $sformatf("%s: starting legal timeout-boundary probe tag=0x%08h budget=%0d expected_detail=0x%02h allow_late_physical_commit=%0b",
                label,
                expected_cmd_tag,
                timeout_budget,
                expected_detail_code,
                allow_late_physical_cq_commit),
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
            done_timeout_cycles * 4
        );

        g7_z4_c1_last_timeout_detail = error_detail[7:0];

        // expected_detail_code == 8'hFF is the phase-tolerant recipe/P18
        // boundary mode.  At this late lifecycle boundary the legal terminal
        // classifications are COMMAND_TIMEOUT (0x0C), TIMEOUT_IN_RECIPE
        // (0x0E), or TIMEOUT_IN_COMPLETION_WB (0x0F).  The exact code can move
        // by a DMA cycle as the 10 ns DMA and 14 ns core clocks change phase.
        if (expected_detail_code == 8'hFF) begin
            if ((error_detail[7:0] != P24D_DETAIL_COMMAND_TIMEOUT) &&
                (error_detail[7:0] != P24D_DETAIL_TIMEOUT_IN_RECIPE) &&
                (error_detail[7:0] != P24D_DETAIL_TIMEOUT_IN_COMPLETION_WB)) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C1/DETAIL_WINDOW",
                    $sformatf("%s: phase-window probe produced unexpected timeout detail=0x%02h full_detail=0x%08h",
                        label,
                        error_detail[7:0],
                        error_detail))
            end
        end else if (error_detail[7:0] !== expected_detail_code) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C1/DETAIL_MISMATCH",
                $sformatf("%s: timeout detail mismatch: got=0x%02h expected=0x%02h full_detail=0x%08h",
                    label,
                    error_detail[7:0],
                    expected_detail_code,
                    error_detail))
        end

        if (cq_tail !== 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C1/CQ_TAIL",
                $sformatf("%s: timeout-boundary probe unexpectedly published CQ entry: cq_tail=0x%08h error=0x%08h detail=0x%08h",
                    label,
                    cq_tail,
                    error_status,
                    error_detail))
        end

        rt.wait_events(event_required, snap, done_timeout_cycles * 4, 1'b1);
        expect_p23f_event_snapshot({label, " QUEUE_ERROR event"}, snap, event_required, 1'b1);

        ack_mask = snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.ack_events(ack_mask);
        check_p23f_event_cleanup({label, " QUEUE_ERROR event"}, ack_mask);

        // Timeout terminates queue ownership only.  Drain the already-started
        // legal lower stack before reusing the same descriptor/queue resources.
        csr_poll_desc_fetch_done(done_timeout_cycles * 2);
        csr_poll_recipe_done(done_timeout_cycles * 4);
        g7_z4_c1_wait_completion_wb_idle({label, " post-timeout lower-stack drain"});

        // P26 session-discard semantics make CQ_TAIL/CQ_OCCUPANCY the
        // authoritative publication boundary after timeout.  A lower-level P18
        // write that was already launched may physically finish after timeout;
        // such a word is not published while CQ_TAIL remains unchanged.
        rt.read_dst_word_le(P24D_TIMEOUT_CQ_BASE, cq_commit_word);
        if (!allow_late_physical_cq_commit &&
            (cq_commit_word !== 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C1/CQ_PHYSICAL_UNEXPECTED",
                $sformatf("%s: physical CQ word changed even though this boundary must suppress P18 launch: commit_word=0x%08h",
                    label,
                    cq_commit_word))
        end

        if (allow_late_physical_cq_commit &&
            (cq_commit_word !== 32'h0000_0000)) begin
            `uvm_info("CODE_COV_C1P2_G7_Z4_C1/SESSION_DISCARD_CQ_PASS",
                $sformatf("%s: late physical P18 completion drained after timeout while CQ_TAIL remained unpublished; discarded commit_word=0x%08h",
                    label,
                    cq_commit_word),
                UVM_MEDIUM)
        end else if (allow_late_physical_cq_commit) begin
            `uvm_info("CODE_COV_C1P2_G7_Z4_C1/SESSION_DISCARD_CQ_PASS",
                $sformatf("%s: no late physical P18 completion was present after drain; CQ_TAIL remained unpublished",
                    label),
                UVM_MEDIUM)
        end

        g7_g3_clear_for_timeout_probe({label, " post-timeout cleanup"});

        `uvm_info("CODE_COV_C1P2_G7_Z4_C1/PROBE_PASS",
            $sformatf("%s PASS: budget=%0d detail=0x%08h error_status=0x%08h physical_cq_word=0x%08h",
                label,
                timeout_budget,
                error_detail,
                error_status,
                cq_commit_word),
            UVM_MEDIUM)
    end
    endtask


    // ------------------------------------------------------------
    // Z4-C1 post-boundary normal-completion proof.
    //
    // The +1 watchdog budget is intentionally beyond the timeout collision.
    // It must complete through the normal P18/P19 publication path rather than
    // being misclassified as a timeout.
    // ------------------------------------------------------------
    task automatic g7_z4_c1_case_post_boundary_normal_completion(
        input ai_accel_event_driven_host_runtime_helper rt,
        input ai_accel_subsys_seq_item                 profile_item,
        input logic [31:0]                             expected_cmd_tag,
        input int unsigned                             timeout_budget,
        input string                                   label
    );
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t       cfg;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t          cmd;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t       rec;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t  snap;
        logic [31:0] event_required;
        logic [31:0] ack_mask;
        logic [31:0] queue_error_status;
        logic [31:0] queue_reject_status;
        logic [31:0] cq_tail;
    begin
        `uvm_info("CODE_COV_C1P2_G7_Z4_C1/POST_BOUNDARY_START",
            $sformatf("%s: starting +1 legal normal-completion proof tag=0x%08h budget=%0d",
                label, expected_cmd_tag, timeout_budget),
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

        event_required = rt.queue_completion_event_mask();

        g7_g3_clear_for_timeout_probe({"before ", label});
        rt.initialize_runtime(cfg, event_required, 1'b1);
        csr_check_recipe_idle_ready({"before ", label});

        rt.write_sq_command(cfg, 0, cmd, 1'b1);
        rt.ring_sq_tail(32'h0000_0001);
        rt.start_queue();

        // Wait for the queue-published completion first.  This prevents a stale
        // physical word left by the previous discarded session from being used
        // as proof of the new command's completion.
        rt.wait_events(event_required, snap, done_timeout_cycles * 8, 1'b1);
        expect_p23f_event_snapshot(label, snap, event_required, 1'b1);

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,
            queue_error_status
        );
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS,
            queue_reject_status
        );
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,
            cq_tail
        );

        if (queue_error_status != 32'h0000_0000 ||
            queue_reject_status != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C1/POST_BOUNDARY_STATUS",
                $sformatf("%s: +1 normal completion accumulated queue error/reject: error=0x%08h reject=0x%08h",
                    label, queue_error_status, queue_reject_status))
        end

        if (cq_tail !== 32'h0000_0001) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C1/POST_BOUNDARY_CQ_TAIL",
                $sformatf("%s: +1 normal completion did not publish CQ_TAIL=1, got=0x%08h",
                    label, cq_tail))
        end

        rt.wait_cq_commit(cfg, 0, rec, done_timeout_cycles * 4);
        check_p23d_cq_record(
            0,
            rec,
            profile_item,
            P24D_TIMEOUT_DESC_TAG0,
            P24D_TIMEOUT_DESC_TAG1
        );

        ack_mask = snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.consume_cq_entry(cfg, 0, 1'b1);
        rt.ack_events(ack_mask);
        check_p23f_event_cleanup(label, ack_mask);

        g7_g3_clear_for_timeout_probe({label, " post-completion cleanup"});

        `uvm_info("CODE_COV_C1P2_G7_Z4_C1/POST_BOUNDARY_COMPLETION_PASS",
            $sformatf("%s PASS: budget=%0d CQ_TAIL publication and CQ record both completed without timeout",
                label, timeout_budget),
            UVM_MEDIUM)
    end
    endtask

    // ============================================================
    // CODE-COV-C1.2-G7-Z4-C2-C
    // P18 / watchdog terminal-boundary constructive probes
    // ============================================================

    task automatic g7_z4_c2c_set_completion_wb_enable(
        input bit    enable_value,
        input string label
    );
        logic [31:0] control_value;
    begin
        csr.read32_expect_okay(
            G7_Z4_C2_C_COMPLETION_WB_CONTROL_ADDR,
            control_value
        );
        control_value[0] = enable_value;
        csr.write32_expect_okay(
            G7_Z4_C2_C_COMPLETION_WB_CONTROL_ADDR,
            control_value
        );
        repeat (2) @(posedge csr_vif.clk);
        #1ps;

        if (p17d_ctrl_vif.completion_wb_enable_obs !== enable_value) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/P18_ENABLE_WRITE",
                $sformatf("%s: P18 enable observation mismatch: requested=%0b observed=%0b control=0x%08h",
                    label,
                    enable_value,
                    p17d_ctrl_vif.completion_wb_enable_obs,
                    control_value))
        end
    end
    endtask

    task automatic g7_z4_c2c_wait_queue_idle(input string label);
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            @(posedge p17d_ctrl_vif.clk);
            #1ps;
            if (p17d_ctrl_vif.queue_busy_obs === 1'b0) begin
                return;
            end
            cnt++;
            if (cnt > (done_timeout_cycles * 4)) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/QUEUE_IDLE_TIMEOUT",
                    $sformatf("%s: queue did not return idle; busy=%0b",
                        label,
                        p17d_ctrl_vif.queue_busy_obs))
            end
        end
    end
    endtask

    task automatic g7_z4_c2c_ack_any_events(
        input ai_accel_event_driven_host_runtime_helper rt,
        input string label
    );
        logic [31:0] pending;
        logic [31:0] ack_mask;
    begin
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_PENDING,
            pending
        );
        ack_mask = pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        if (ack_mask != 32'h0000_0000) begin
            rt.ack_events(ack_mask);
            check_p23f_event_cleanup(label, ack_mask);
        end
    end
    endtask

    task automatic g7_z4_c2c_finish_terminal_case(
        input ai_accel_event_driven_host_runtime_helper rt,
        input ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input bit          saw_timeout,
        input bit          saw_raw_commit,
        input bit          saw_raw_error,
        input string       label
    );
        logic [31:0] queue_error_status;
        logic [31:0] cq_tail;
    begin
        // P26 timeout/error semantics are session-discard, not cancellation.
        // Always let any already-launched lower P18 transaction drain first.
        g7_z4_c1_wait_completion_wb_idle({label, " P18 drain"});
        g7_z4_c2c_wait_queue_idle({label, " queue idle"});
        repeat (2) @(posedge csr_vif.clk);

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,
            queue_error_status
        );
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,
            cq_tail
        );

        if (saw_timeout) begin
            if (!queue_error_status[P24D_QUEUE_TIMEOUT_ERR_BIT]) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/TIMEOUT_STICKY_MISSING",
                    $sformatf("%s: passive timeout pulse was observed but timeout sticky is absent: error=0x%08h",
                        label, queue_error_status))
            end
            if (cq_tail !== 32'h0000_0000) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/TIMEOUT_PUBLISHED_CQ",
                    $sformatf("%s: timeout session unexpectedly published CQ_TAIL=0x%08h",
                        label, cq_tail))
            end
        end else begin
            if (queue_error_status[P24D_QUEUE_TIMEOUT_ERR_BIT]) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/UNEXPECTED_TIMEOUT_STICKY",
                    $sformatf("%s: raw terminal path unexpectedly set timeout sticky: error=0x%08h",
                        label, queue_error_status))
            end
        end

        if (saw_raw_commit) begin
            if (cq_tail !== 32'h0000_0001) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/COMMIT_CQ_TAIL",
                    $sformatf("%s: raw commit did not publish exactly one CQ entry: cq_tail=0x%08h error=0x%08h",
                        label, cq_tail, queue_error_status))
            end
            rt.consume_cq_entry(cfg, 0, 1'b1);
        end else if (saw_raw_error) begin
            if (cq_tail !== 32'h0000_0000) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/ERROR_CQ_TAIL",
                    $sformatf("%s: raw completion error unexpectedly published CQ_TAIL=0x%08h",
                        label, cq_tail))
            end
        end

        g7_z4_c2c_ack_any_events(rt, {label, " event cleanup"});
        g7_g3_clear_for_timeout_probe({label, " sticky cleanup"});
    end
    endtask

    task automatic g7_z4_c2c_prepare_queue_command(
        input  ai_accel_event_driven_host_runtime_helper rt,
        input  logic [31:0] expected_cmd_tag,
        input  int unsigned timeout_budget,
        output ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg
    );
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd;
        logic [31:0] event_enable;
    begin
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

        event_enable = rt.queue_completion_event_mask() |
                       rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_ERROR);

        g7_g3_clear_for_timeout_probe("before C2-C queue command");
        rt.initialize_runtime(cfg, event_enable, 1'b1);
        csr_check_recipe_idle_ready("before C2-C queue command START");

        rt.write_sq_command(cfg, 0, cmd, 1'b1);
        rt.ring_sq_tail(32'h0000_0001);
    end
    endtask

    task automatic g7_z4_c2c_line1927_enable_low_probe(
        input ai_accel_event_driven_host_runtime_helper rt
    );
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg;
        bit          saw_pending_tuple;
        bit          saw_raw_commit;
        int unsigned cnt;
    begin
        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_C/LINE1927_ENABLE_START",
            "Starting auto-P18 pending with completion_wb_enable=0 constructive probe",
            UVM_MEDIUM)

        comp_wb_inject_vif.clear();
        g7_z4_c2c_set_completion_wb_enable(1'b0, "line1927 enable-low precondition");
        g7_z4_c2c_prepare_queue_command(
            rt,
            G7_Z4_C2_C_CMD_TAG_BASE + 32'h0000_0001,
            0,
            cfg
        );

        saw_pending_tuple = 1'b0;
        fork
            begin
                rt.start_queue();
            end
            begin
                cnt = 0;
                forever begin
                    @(posedge p17d_ctrl_vif.clk);
                    #1ps;
                    if ((p17d_ctrl_vif.completion_wb_auto_pending_obs === 1'b1) &&
                        (p17d_ctrl_vif.completion_wb_busy_obs === 1'b0) &&
                        (p17d_ctrl_vif.completion_wb_enable_obs === 1'b0)) begin
                        saw_pending_tuple = 1'b1;
                        break;
                    end
                    if ((p17d_ctrl_vif.queue_completion_commit_raw_obs === 1'b1) ||
                        (p17d_ctrl_vif.queue_completion_error_raw_obs === 1'b1) ||
                        (p17d_ctrl_vif.queue_timeout_pulse_obs === 1'b1)) begin
                        `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/LINE1927_ENABLE_TERMINAL",
                            "Queue reached a terminal event before enable-low auto-P18 pending tuple")
                    end
                    cnt++;
                    if (cnt > (done_timeout_cycles * 4)) begin
                        `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/LINE1927_ENABLE_TIMEOUT",
                            "Timed out waiting for enable-low auto-P18 pending tuple")
                    end
                end
            end
        join

        if (!saw_pending_tuple) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/LINE1927_ENABLE_NO_TUPLE",
                "Did not observe pending=1/busy=0/enable=0")
        end

        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_C/LINE1927_ENABLE_PASS",
            "Observed completion_wb_auto_pending=1, completion_wb_busy=0, completion_wb_enable=0; line1927 enable-low target is functionally constructed",
            UVM_MEDIUM)

        // Release only the software-visible P18 enable gate.  The pending auto
        // completion remains architectural state and must now complete normally.
        g7_z4_c2c_set_completion_wb_enable(1'b1, "line1927 enable-low release");

        saw_raw_commit = 1'b0;
        cnt = 0;
        forever begin
            @(posedge p17d_ctrl_vif.clk);
            #1ps;
            if (p17d_ctrl_vif.queue_completion_commit_raw_obs === 1'b1) begin
                saw_raw_commit = 1'b1;
                break;
            end
            if ((p17d_ctrl_vif.queue_completion_error_raw_obs === 1'b1) ||
                (p17d_ctrl_vif.queue_timeout_pulse_obs === 1'b1)) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/LINE1927_ENABLE_RELEASE_TERMINAL",
                    "Enable-low recovery terminated through error/timeout instead of raw commit")
            end
            cnt++;
            if (cnt > (done_timeout_cycles * 4)) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/LINE1927_ENABLE_RELEASE_TIMEOUT",
                    "Timed out waiting for normal raw commit after re-enabling P18")
            end
        end

        g7_z4_c2c_finish_terminal_case(
            rt, cfg, 1'b0, saw_raw_commit, 1'b0,
            "C2-C line1927 enable-low recovery"
        );
    end
    endtask

    task automatic g7_z4_c2c_line1927_timeout_case(
        input  ai_accel_event_driven_host_runtime_helper rt,
        input  logic [31:0] expected_cmd_tag,
        input  int unsigned timeout_budget,
        output bit          exact_hit,
        input  string       label
    );
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg;
        bit saw_timeout;
        bit saw_raw_commit;
        bit saw_raw_error;
        int unsigned cnt;
    begin
        exact_hit     = 1'b0;
        saw_timeout   = 1'b0;
        saw_raw_commit= 1'b0;
        saw_raw_error = 1'b0;

        g7_z4_c2c_set_completion_wb_enable(1'b1, {label, " enable"});
        g7_z4_c2c_prepare_queue_command(rt, expected_cmd_tag, timeout_budget, cfg);

        fork
            begin
                rt.start_queue();
            end
            begin
                cnt = 0;
                forever begin
                    @(posedge p17d_ctrl_vif.clk);
                    #1ps;

                    if (p17d_ctrl_vif.queue_timeout_pulse_obs === 1'b1) begin
                        saw_timeout = 1'b1;
                        if ((p17d_ctrl_vif.completion_wb_auto_pending_obs === 1'b1) &&
                            (p17d_ctrl_vif.completion_wb_busy_obs === 1'b0) &&
                            (p17d_ctrl_vif.completion_wb_enable_obs === 1'b1) &&
                            (p17d_ctrl_vif.queue_timeout_error_status_obs == 32'h0000_0000)) begin
                            exact_hit = 1'b1;
                        end
                        break;
                    end

                    if (p17d_ctrl_vif.queue_completion_commit_raw_obs === 1'b1) begin
                        saw_raw_commit = 1'b1;
                        break;
                    end
                    if (p17d_ctrl_vif.queue_completion_error_raw_obs === 1'b1) begin
                        saw_raw_error = 1'b1;
                        break;
                    end

                    cnt++;
                    if (cnt > (done_timeout_cycles * 8)) begin
                        `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/LINE1927_TIMEOUT_WAIT",
                            $sformatf("%s: no timeout/raw terminal for budget=%0d",
                                label, timeout_budget))
                    end
                end
            end
        join

        g7_z4_c2c_finish_terminal_case(
            rt, cfg, saw_timeout, saw_raw_commit, saw_raw_error, label
        );

        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_C/LINE1927_TIMEOUT_CASE",
            $sformatf("%s: budget=%0d exact=%0b terminal(timeout/commit/error)=%0b/%0b/%0b",
                label, timeout_budget, exact_hit,
                saw_timeout, saw_raw_commit, saw_raw_error),
            UVM_MEDIUM)
    end
    endtask

    task automatic g7_z4_c2c_line1250_terminal_case(
        input  ai_accel_event_driven_host_runtime_helper rt,
        input  logic [31:0] expected_cmd_tag,
        input  int unsigned timeout_budget,
        input  bit          inject_bresp_error,
        output bit          exact_hit,
        input  string       label
    );
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg;
        bit saw_timeout;
        bit saw_raw_commit;
        bit saw_raw_error;
        bit at_threshold;
        int unsigned cnt;
    begin
        exact_hit      = 1'b0;
        saw_timeout    = 1'b0;
        saw_raw_commit = 1'b0;
        saw_raw_error  = 1'b0;

        comp_wb_inject_vif.clear();

        g7_z4_c2c_set_completion_wb_enable(1'b1, {label, " enable"});
        g7_z4_c2c_prepare_queue_command(rt, expected_cmd_tag, timeout_budget, cfg);

        // Arm the injected P18 BRESP error only after all queue/CSR/source-memory
        // setup has completed, so beat 0 is unambiguously the next automatic
        // completion-writeback transaction.
        if (inject_bresp_error) begin
            comp_wb_inject_vif.set_bresp_error(1'b1, 0);
        end

        fork
            begin
                rt.start_queue();
            end
            begin
                cnt = 0;
                forever begin
                    @(posedge p17d_ctrl_vif.clk);
                    #1ps;

                    at_threshold =
                        (p17d_ctrl_vif.queue_timeout_watchdog_active_obs === 1'b1) &&
                        (p17d_ctrl_vif.queue_timeout_budget_obs != 32'h0000_0000) &&
                        (p17d_ctrl_vif.queue_timeout_count_obs >=
                            (p17d_ctrl_vif.queue_timeout_budget_obs - 32'd1));

                    if (p17d_ctrl_vif.queue_completion_commit_raw_obs === 1'b1) begin
                        saw_raw_commit = 1'b1;
                        if (at_threshold &&
                            (p17d_ctrl_vif.queue_completion_error_raw_obs === 1'b0) &&
                            (p17d_ctrl_vif.queue_timeout_pulse_obs === 1'b0)) begin
                            exact_hit = !inject_bresp_error;
                        end
                        break;
                    end

                    if (p17d_ctrl_vif.queue_completion_error_raw_obs === 1'b1) begin
                        saw_raw_error = 1'b1;
                        if (at_threshold &&
                            (p17d_ctrl_vif.queue_completion_commit_raw_obs === 1'b0) &&
                            (p17d_ctrl_vif.queue_timeout_pulse_obs === 1'b0)) begin
                            exact_hit = inject_bresp_error;
                        end
                        break;
                    end

                    if (p17d_ctrl_vif.queue_timeout_pulse_obs === 1'b1) begin
                        saw_timeout = 1'b1;
                        break;
                    end

                    cnt++;
                    if (cnt > (done_timeout_cycles * 8)) begin
                        `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/LINE1250_TERMINAL_WAIT",
                            $sformatf("%s: no raw completion/timeout terminal for budget=%0d inject_error=%0b",
                                label, timeout_budget, inject_bresp_error))
                    end
                end
            end
        join

        comp_wb_inject_vif.clear();

        if (!inject_bresp_error && saw_raw_error) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/LINE1250_UNEXPECTED_ERROR",
                $sformatf("%s: normal commit probe observed raw completion error", label))
        end
        if (inject_bresp_error && saw_raw_commit) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/LINE1250_UNEXPECTED_COMMIT",
                $sformatf("%s: injected BRESP-error probe committed instead of reporting raw error", label))
        end

        g7_z4_c2c_finish_terminal_case(
            rt, cfg, saw_timeout, saw_raw_commit, saw_raw_error, label
        );

        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_C/LINE1250_CASE",
            $sformatf("%s: budget=%0d inject_error=%0b exact=%0b terminal(timeout/commit/error)=%0b/%0b/%0b",
                label, timeout_budget, inject_bresp_error, exact_hit,
                saw_timeout, saw_raw_commit, saw_raw_error),
            UVM_MEDIUM)
    end
    endtask

    task automatic g7_z4_c2c_calibrate_error_raw_budget(
        input  ai_accel_event_driven_host_runtime_helper rt,
        output int unsigned error_raw_timeout_budget
    );
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg;
        bit started;
        int unsigned cycle_index;
    begin
        error_raw_timeout_budget = 0;
        started = 1'b0;

        comp_wb_inject_vif.clear();
        g7_z4_c2c_set_completion_wb_enable(1'b1, "C2-C raw-error calibration enable");
        g7_z4_c2c_prepare_queue_command(
            rt,
            G7_Z4_C2_C_CMD_TAG_BASE + 32'h0000_0070,
            0,
            cfg
        );
        // Same safety rule as the constructive error sweep: arm only after
        // setup, immediately before the queue launch that will own P18.
        comp_wb_inject_vif.set_bresp_error(1'b1, 0);

        fork
            begin
                rt.start_queue();
            end
            begin
                while (p17d_ctrl_vif.desc_fetch_start_to_engine_obs !== 1'b1) begin
                    @(posedge p17d_ctrl_vif.clk);
                    #1ps;
                end
                started = 1'b1;
                cycle_index = 0;

                while (p17d_ctrl_vif.queue_completion_error_raw_obs !== 1'b1) begin
                    @(posedge p17d_ctrl_vif.clk);
                    #1ps;
                    cycle_index++;
                    if (p17d_ctrl_vif.queue_completion_commit_raw_obs === 1'b1) begin
                        `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/ERROR_CAL_COMMIT",
                            "Injected raw-error calibration unexpectedly committed")
                    end
                    if (cycle_index > (done_timeout_cycles * 8)) begin
                        `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/ERROR_CAL_TIMEOUT",
                            "Timed out waiting for injected raw completion error")
                    end
                end

                error_raw_timeout_budget = cycle_index + 1;
            end
        join

        if (!started || (error_raw_timeout_budget == 0)) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/ERROR_CAL_INVALID",
                "Raw-error calibration did not establish a non-zero reference")
        end

        comp_wb_inject_vif.clear();
        g7_z4_c2c_finish_terminal_case(
            rt, cfg, 1'b0, 1'b0, 1'b1,
            "C2-C raw-error calibration"
        );

        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_C/ERROR_CAL_PASS",
            $sformatf("Calibrated injected queue_completion_error_raw reference budget=%0d",
                error_raw_timeout_budget),
            UVM_MEDIUM)
    end
    endtask

    task automatic g7_z4_c2c_run_constructive_suite(
        input ai_accel_event_driven_host_runtime_helper rt,
        input int unsigned auto_pending_reference,
        input int unsigned commit_raw_reference
    );
        int unsigned error_raw_reference;
        int unsigned probe_index;
        int signed   delta;
        int signed   budget_signed;
        int unsigned budget;
        bit          exact_hit;
        bit          line1927_timeout_hit;
        bit          line1250_commit_hit;
        bit          line1250_error_hit;
        string       label;
    begin
        if ((auto_pending_reference == 0) || (commit_raw_reference == 0)) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/BAD_REFERENCE",
                $sformatf("Invalid passive references: auto_pending=%0d commit_raw=%0d",
                    auto_pending_reference, commit_raw_reference))
        end

        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_C/START",
            $sformatf("Starting P18/watchdog terminal-boundary suite: auto_pending_ref=%0d commit_raw_ref=%0d span=+/- %0d",
                auto_pending_reference,
                commit_raw_reference,
                G7_Z4_C2_C_PHASE_SPAN),
            UVM_MEDIUM)

        // --------------------------------------------------------
        // line1927: csr_completion_wb_enable=0 decisive while
        // auto-P18 is pending and the engine is idle.
        // --------------------------------------------------------
        g7_z4_c2c_line1927_enable_low_probe(rt);

        // --------------------------------------------------------
        // line1927: exact timeout-pulse suppression of auto-P18 start.
        // Center-out sweep makes the reference robust to the 10/14 ns
        // DMA/core phase relation without assuming one absolute cycle.
        // --------------------------------------------------------
        line1927_timeout_hit = 1'b0;
        for (probe_index = 0;
             probe_index <= (2 * G7_Z4_C2_C_PHASE_SPAN);
             probe_index++) begin
            if (!line1927_timeout_hit) begin
                delta = g7_z4_c2c_centered_delta(probe_index);
                budget_signed = int'(auto_pending_reference) + delta;
                if (budget_signed > 0) begin
                    budget = int'(budget_signed);
                    label = $sformatf("C2-C line1927 timeout delta=%0d", delta);
                    g7_z4_c2c_line1927_timeout_case(
                        rt,
                        G7_Z4_C2_C_CMD_TAG_BASE + 32'h0000_0010 + probe_index,
                        budget,
                        exact_hit,
                        label
                    );
                    if (exact_hit) begin
                        line1927_timeout_hit = 1'b1;
                        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_C/LINE1927_TIMEOUT_PASS",
                            $sformatf("Observed exact pending=1/busy=0/enable=1/status_zero/timeout_pulse=1 tuple at budget=%0d delta=%0d",
                                budget, delta),
                            UVM_MEDIUM)
                    end
                end
            end
        end

        if (!line1927_timeout_hit) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/LINE1927_TIMEOUT_MISS",
                $sformatf("No exact line1927 timeout-pulse tuple in center-out window around reference=%0d span=%0d",
                    auto_pending_reference, G7_Z4_C2_C_PHASE_SPAN))
        end

        // --------------------------------------------------------
        // line1250: raw successful completion at watchdog threshold.
        // The raw completion has sequential priority over timeout.
        // --------------------------------------------------------
        line1250_commit_hit = 1'b0;
        for (probe_index = 0;
             probe_index <= (2 * G7_Z4_C2_C_PHASE_SPAN);
             probe_index++) begin
            if (!line1250_commit_hit) begin
                delta = g7_z4_c2c_centered_delta(probe_index);
                budget_signed = int'(commit_raw_reference) + delta;
                if (budget_signed > 0) begin
                    budget = int'(budget_signed);
                    label = $sformatf("C2-C line1250 commit delta=%0d", delta);
                    g7_z4_c2c_line1250_terminal_case(
                        rt,
                        G7_Z4_C2_C_CMD_TAG_BASE + 32'h0000_0040 + probe_index,
                        budget,
                        1'b0,
                        exact_hit,
                        label
                    );
                    if (exact_hit) begin
                        line1250_commit_hit = 1'b1;
                        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_C/LINE1250_COMMIT_PASS",
                            $sformatf("Observed queue_completion_commit_raw=1 at active nonzero watchdog threshold: budget=%0d delta=%0d",
                                budget, delta),
                            UVM_MEDIUM)
                    end
                end
            end
        end

        if (!line1250_commit_hit) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/LINE1250_COMMIT_MISS",
                $sformatf("No exact raw-commit/watchdog-threshold tuple around reference=%0d span=%0d",
                    commit_raw_reference, G7_Z4_C2_C_PHASE_SPAN))
        end

        // --------------------------------------------------------
        // line1250: independently calibrate a legal P18 beat-0 BRESP
        // error, then align the raw error pulse with the watchdog threshold.
        // --------------------------------------------------------
        g7_z4_c2c_calibrate_error_raw_budget(rt, error_raw_reference);

        line1250_error_hit = 1'b0;
        for (probe_index = 0;
             probe_index <= (2 * G7_Z4_C2_C_PHASE_SPAN);
             probe_index++) begin
            if (!line1250_error_hit) begin
                delta = g7_z4_c2c_centered_delta(probe_index);
                budget_signed = int'(error_raw_reference) + delta;
                if (budget_signed > 0) begin
                    budget = int'(budget_signed);
                    label = $sformatf("C2-C line1250 error delta=%0d", delta);
                    g7_z4_c2c_line1250_terminal_case(
                        rt,
                        G7_Z4_C2_C_CMD_TAG_BASE + 32'h0000_0080 + probe_index,
                        budget,
                        1'b1,
                        exact_hit,
                        label
                    );
                    if (exact_hit) begin
                        line1250_error_hit = 1'b1;
                        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_C/LINE1250_ERROR_PASS",
                            $sformatf("Observed queue_completion_error_raw=1 at active nonzero watchdog threshold: budget=%0d delta=%0d",
                                budget, delta),
                            UVM_MEDIUM)
                    end
                end
            end
        end

        if (!line1250_error_hit) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_C/LINE1250_ERROR_MISS",
                $sformatf("No exact raw-error/watchdog-threshold tuple around reference=%0d span=%0d",
                    error_raw_reference, G7_Z4_C2_C_PHASE_SPAN))
        end

        comp_wb_inject_vif.clear();
        g7_z4_c2c_set_completion_wb_enable(1'b1, "C2-C final restore");
        g7_g3_clear_for_timeout_probe("C2-C final sticky cleanup");
        g7_z4_c2c_ack_any_events(rt, "C2-C final event cleanup");

        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_C/PASS",
            $sformatf("C2-C constructive suite completed: line1927 enable-low + timeout-pulse and line1250 raw commit + raw error; references(auto/commit/error)=%0d/%0d/%0d",
                auto_pending_reference,
                commit_raw_reference,
                error_raw_reference),
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
        int unsigned g7_z4_c1_recipe_done_collision_budget;
        int unsigned g7_z4_c2_c_auto_pending_reference;
        int unsigned g7_z4_c2_c_commit_raw_reference;
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
            g7_g3_recipe_timeout_budget,
            g7_z4_c1_recipe_done_collision_budget,
            g7_z4_c2_c_auto_pending_reference,
            g7_z4_c2_c_commit_raw_reference
        );
        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        // Preserve the original P24D early descriptor-fetch timeout case.
        p24d_case_descriptor_fetch_timeout(rt);

        // Z4-C1 supersedes the earlier provisional G7-G3 0x0C waiver.
        // The calibrated handoff marker is retained, but the legal budget one
        // cycle before that marker is now constructively checked below and is
        // expected to produce P24 DETAIL_COMMAND_TIMEOUT (0x0C).
        `uvm_info("CODE_COV_C1_2G7_G3/COMMAND_TIMEOUT_RECLASS_SUPERSEDED",
            $sformatf("Z4-C1 will constructively retest the descriptor->recipe all-idle boundary: calibrated_handoff=%0d targeted_budget=%0d recipe_marker=%0d",
                g7_g3_handoff_timeout_budget,
                g7_g3_handoff_timeout_budget - 1,
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
            $sformatf("G7-G3 recipe timeout detail remains validated: handoff_marker=%0d recipe_budget=%0d; Z4-C1 below supersedes the earlier 0x0C waiver disposition",
                g7_g3_handoff_timeout_budget,
                g7_g3_recipe_timeout_budget),
            UVM_MEDIUM)

        `uvm_info("CODE_COV_C1P2_G7_Z4_C1/START",
            $sformatf("Starting legal timeout collision probes: handoff_center=%0d recipe/P18_reference=%0d with -5..0 phase window",
                g7_g3_handoff_timeout_budget,
                g7_z4_c1_recipe_done_collision_budget),
            UVM_MEDIUM)

        if (g7_g3_handoff_timeout_budget <= 1) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C1/HANDOFF_CENTER",
                $sformatf("Handoff collision center too small for +/-1 sweep: %0d",
                    g7_g3_handoff_timeout_budget))
        end

        g7_z4_c1_case_timeout_boundary_probe(
            rt,
            G7_Z4_C1_HANDOFF_CMD_TAG_BASE + 32'd0,
            g7_g3_handoff_timeout_budget - 1,
            P24D_DETAIL_COMMAND_TIMEOUT,
            1'b0,
            "Z4-C1 handoff boundary -1"
        );
        g7_z4_c1_case_timeout_boundary_probe(
            rt,
            G7_Z4_C1_HANDOFF_CMD_TAG_BASE + 32'd1,
            g7_g3_handoff_timeout_budget,
            P24D_DETAIL_TIMEOUT_IN_RECIPE,
            1'b0,
            "Z4-C1 handoff boundary center"
        );
        g7_z4_c1_case_timeout_boundary_probe(
            rt,
            G7_Z4_C1_HANDOFF_CMD_TAG_BASE + 32'd2,
            g7_g3_handoff_timeout_budget + 1,
            P24D_DETAIL_TIMEOUT_IN_RECIPE,
            1'b0,
            "Z4-C1 handoff boundary +1"
        );

        `uvm_info("CODE_COV_C1P2_G7_Z4_C1/HANDOFF_SWEEP_PASS",
            $sformatf("Completed legal handoff-boundary sweep: budget=%0d produced COMMAND_TIMEOUT 0x0C and adjacent budgets entered RECIPE timeout 0x0E",
                g7_g3_handoff_timeout_budget - 1),
            UVM_MEDIUM)

        if (g7_z4_c1_recipe_done_collision_budget <= 5) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C1/RECIPE_DONE_CENTER",
                $sformatf("Recipe/P18 reference budget too small for -5..0 phase window: %0d",
                    g7_z4_c1_recipe_done_collision_budget))
        end

        begin : g7_z4_c1_recipe_phase_window
            int signed   delta;
            int unsigned probe_index;
            int unsigned probe_budget;
            int unsigned pre_p18_timeout_count;
            int unsigned p18_timeout_count;
            string       probe_label;

            probe_index            = 0;
            pre_p18_timeout_count  = 0;
            p18_timeout_count      = 0;

            // The recipe runner is core-clocked while the watchdog is DMA-clocked.
            // Sweep every integer timeout budget in a compact six-cycle window.
            // This removes the false assumption that one reference command fixes
            // the exact recipe_done/P18 boundary for later command launches.
            for (delta = -5; delta <= 0; delta++) begin
                probe_budget = int'(g7_z4_c1_recipe_done_collision_budget) + delta;
                probe_label  = $sformatf(
                    "Z4-C1 recipe/P18 phase-window delta=%0d",
                    delta
                );

                g7_z4_c1_case_timeout_boundary_probe(
                    rt,
                    G7_Z4_C1_RECIPE_DONE_CMD_TAG_BASE + probe_index,
                    probe_budget,
                    8'hFF,
                    1'b1,
                    probe_label
                );

                if (g7_z4_c1_last_timeout_detail ==
                    P24D_DETAIL_TIMEOUT_IN_COMPLETION_WB) begin
                    p18_timeout_count++;
                end else begin
                    pre_p18_timeout_count++;
                end

                probe_index++;
            end

            // A useful boundary sweep must straddle the P18 launch boundary:
            // at least one timeout before P18 ownership and at least one while
            // completion writeback is already active.  Fresh FEC, not this
            // functional classification, decides whether line 1902's exact
            // same-cycle timeout term was constructively hit.
            if (pre_p18_timeout_count == 0) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C1/PHASE_WINDOW_PRE_P18",
                    $sformatf("Recipe/P18 phase window never observed a pre-P18 timeout: reference=%0d",
                        g7_z4_c1_recipe_done_collision_budget))
            end

            if (p18_timeout_count == 0) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C1/PHASE_WINDOW_P18",
                    $sformatf("Recipe/P18 phase window never observed TIMEOUT_IN_COMPLETION_WB: reference=%0d",
                        g7_z4_c1_recipe_done_collision_budget))
            end

            `uvm_info("CODE_COV_C1P2_G7_Z4_C1/PHASE_WINDOW_PASS",
                $sformatf("Recipe/P18 phase-tolerant timeout window PASS: reference=%0d budgets=[%0d..%0d] pre_p18=%0d p18=%0d",
                    g7_z4_c1_recipe_done_collision_budget,
                    g7_z4_c1_recipe_done_collision_budget - 5,
                    g7_z4_c1_recipe_done_collision_budget,
                    pre_p18_timeout_count,
                    p18_timeout_count),
                UVM_MEDIUM)
        end

        `uvm_info("CODE_COV_C1P2_G7_Z4_C1/RECIPE_DONE_SWEEP_PASS",
            $sformatf("Completed phase-tolerant recipe-done/P18 timeout sweep around reference=%0d; exact same-cycle closure is deferred to fresh merged FEC",
                g7_z4_c1_recipe_done_collision_budget),
            UVM_MEDIUM)

        `uvm_info("CODE_COV_C1P2_G7_Z4_C1/PASS",
            "Z4-C1R2 legal timeout-boundary reconciliation completed: handoff 0x0C/0x0E boundary plus a core/DMA phase-tolerant recipe/P18 timeout window, without force/deposit or DUT modification",
            UVM_MEDIUM)

        // CODE-COV-C1.2-G7-Z4-C2-C: preserve every C1R2 sub-probe above,
        // then construct the remaining legal P18/watchdog terminal tuples.
        g7_z4_c2c_run_constructive_suite(
            rt,
            g7_z4_c2_c_auto_pending_reference,
            g7_z4_c2_c_commit_raw_reference
        );

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
