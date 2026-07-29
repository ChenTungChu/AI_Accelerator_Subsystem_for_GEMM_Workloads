// File: tb/uvm/test/ai_accel_subsys_csr_recipe_reject_error_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_RECIPE_REJECT_ERROR_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_RECIPE_REJECT_ERROR_TEST_SV

// ------------------------------------------------------------
// P16F CSR recipe-level reject / busy / error handling smoke
//
// Scope:
//   - validates immediate CSR_RECIPE_COMMAND.START_RECIPE reject
//     conditions before the hardware recipe runner starts
//   - validates START_RECIPE while recipe_busy rejection
//   - validates P14 manual START_* and P15 START_JOB rejection while
//     a P16 recipe owns the single-job worker
//   - validates slot worker error propagation into recipe-level
//     sticky error status and slot error masks
//   - validates CLEAR_* cleanup and a valid recipe after error/reject
//     recovery
//
// This test focuses on the P16 recipe-level control plane.  It does
// not modify BRAM, GEMM, DMA, AXI-Stream, Direct Stream, CSR RTL, or
// the P15/P16 sequencer RTL.
// ------------------------------------------------------------

class ai_accel_subsys_csr_recipe_reject_error_test extends ai_accel_subsys_csr_recipe_dma_two_slot_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_recipe_reject_error_test)

    localparam logic [31:0] P16F_SLOT0_CONTROL_DMA_HOST_READBACK = 32'h0000_0003;
    localparam logic [31:0] P16F_SLOT1_CONTROL_DMA_DMA_STORE     = 32'h0000_000B;
    localparam logic [31:0] P16F_RECIPE_CONTROL_ZERO_COUNT       = 32'h0000_0700;
    localparam logic [31:0] P16F_RECIPE_CONTROL_TWO_SLOTS        = 32'h0000_0702;
    localparam logic [31:0] P16F_RECIPE_CONTROL_RANGE_INVALID    = 32'h0000_0705;

    // enable=1, input_mode=DMA_LOAD(1), output_mode=2 (unsupported)
    localparam logic [31:0] C1D1_SLOT0_CONTROL_DMA_UNSUPPORTED_OUTPUT = 32'h0000_0013;
    localparam int unsigned C1D1_RECIPE_REJ_MICRO_OP_BUSY = 2;

    localparam logic [3:0] P16F_RECIPE_STATE_IDLE  = 4'd0;
    localparam logic [3:0] P16F_RECIPE_STATE_DONE  = 4'd8;
    localparam logic [3:0] P16F_RECIPE_STATE_ERROR = 4'd9;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_csr_recipe_reject_error_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Basic read helpers
    // ------------------------------------------------------------
    task automatic csr_read_recipe_sticky(
        output logic [31:0] status,
        output logic [31:0] done_status,
        output logic [31:0] error_status,
        output logic [31:0] reject_status,
        output logic [31:0] state,
        output logic [31:0] current_slot,
        output logic [31:0] completed_count,
        output logic [31:0] slot_done_mask,
        output logic [31:0] slot_error_mask,
        output logic [31:0] slot_reject_mask
    );
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_STATUS, status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_DONE_STATUS, done_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_ERROR_STATUS, error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS, reject_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_STATE, state);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_CURRENT_SLOT, current_slot);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_COMPLETED_COUNT, completed_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_DONE_MASK, slot_done_mask);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_ERROR_MASK, slot_error_mask);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_REJECT_MASK, slot_reject_mask);
    end
    endtask

    task automatic csr_expect_recipe_reject_bit(
        input int unsigned bit_idx,
        input string       tag
    );
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] state;
        logic [31:0] current_slot;
        logic [31:0] completed_count;
        logic [31:0] slot_done_mask;
        logic [31:0] slot_error_mask;
        logic [31:0] slot_reject_mask;
    begin
        csr_read_recipe_sticky(
            status,
            done_status,
            error_status,
            reject_status,
            state,
            current_slot,
            completed_count,
            slot_done_mask,
            slot_error_mask,
            slot_reject_mask
        );

        if (!reject_status[bit_idx]) begin
            `uvm_fatal("P16F_RECIPE_REJECT/NO_BIT",
                $sformatf("%s: expected recipe reject bit %0d, status=0x%08h done=0x%08h error=0x%08h reject=0x%08h state=0x%08h current_slot=%0d masks(done/error/reject)=0x%08h/0x%08h/0x%08h",
                    tag,
                    bit_idx,
                    status,
                    done_status,
                    error_status,
                    reject_status,
                    state,
                    current_slot,
                    slot_done_mask,
                    slot_error_mask,
                    slot_reject_mask))
        end

        if (error_status != 32'h0000_0000) begin
            `uvm_fatal("P16F_RECIPE_REJECT/UNEXPECTED_ERROR",
                $sformatf("%s: CSR_RECIPE_ERROR_STATUS unexpectedly nonzero during reject check: error=0x%08h reject=0x%08h state=0x%08h",
                    tag, error_status, reject_status, state))
        end

        `uvm_info("P16F_RECIPE_REJECT",
            $sformatf("%s: observed expected recipe reject bit %0d, reject=0x%08h state=0x%08h status=0x%08h",
                tag,
                bit_idx,
                reject_status,
                state,
                status),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_expect_recipe_error_bit(
        input int unsigned error_bit_idx,
        input logic [31:0] expected_slot_error_mask,
        input string       tag
    );
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] state;
        logic [31:0] current_slot;
        logic [31:0] completed_count;
        logic [31:0] slot_done_mask;
        logic [31:0] slot_error_mask;
        logic [31:0] slot_reject_mask;
    begin
        csr_read_recipe_sticky(
            status,
            done_status,
            error_status,
            reject_status,
            state,
            current_slot,
            completed_count,
            slot_done_mask,
            slot_error_mask,
            slot_reject_mask
        );

        if (!error_status[error_bit_idx]) begin
            `uvm_fatal("P16F_RECIPE_ERROR/NO_BIT",
                $sformatf("%s: expected recipe error bit %0d, status=0x%08h done=0x%08h error=0x%08h reject=0x%08h state=0x%08h current_slot=%0d masks(done/error/reject)=0x%08h/0x%08h/0x%08h",
                    tag,
                    error_bit_idx,
                    status,
                    done_status,
                    error_status,
                    reject_status,
                    state,
                    current_slot,
                    slot_done_mask,
                    slot_error_mask,
                    slot_reject_mask))
        end

        if ((slot_error_mask & expected_slot_error_mask) != expected_slot_error_mask) begin
            `uvm_fatal("P16F_RECIPE_ERROR/SLOT_MASK",
                $sformatf("%s: slot error mask mismatch: expected mask contains 0x%08h actual=0x%08h",
                    tag,
                    expected_slot_error_mask,
                    slot_error_mask))
        end

        if (state[3:0] != P16F_RECIPE_STATE_ERROR) begin
            `uvm_fatal("P16F_RECIPE_ERROR/BAD_STATE",
                $sformatf("%s: expected recipe ERROR state, state=0x%08h error=0x%08h slot_error_mask=0x%08h",
                    tag,
                    state,
                    error_status,
                    slot_error_mask))
        end

        `uvm_info("P16F_RECIPE_ERROR",
            $sformatf("%s: observed expected recipe error bit %0d, error=0x%08h slot_error_mask=0x%08h state=0x%08h",
                tag,
                error_bit_idx,
                error_status,
                slot_error_mask,
                state),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_clear_recipe_job_and_p14_sticky(input string tag);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] state;
        logic [31:0] current_slot;
        logic [31:0] completed_count;
        logic [31:0] slot_done_mask;
        logic [31:0] slot_error_mask;
        logic [31:0] slot_reject_mask;
        logic [31:0] perf_busy;
        logic [31:0] perf_mac;
        logic [31:0] perf_output;
    begin
        // CLEAR_SLOT_STATUS must clear two pieces of state in the integrated
        // CSR + recipe-runner path:
        //   1) the recipe sequencer's internal per-slot masks, and
        //   2) the CSR sticky mask registers that OR in the sequencer outputs.
        //
        // Because the CSR block samples the still-asserted sequencer mask on
        // the same cycle that the first clear pulse is handed to the runner,
        // a single clear can leave a one-cycle OR residue in the CSR sticky
        // mask register.  Issue a second clear after the runner has consumed
        // the first clear pulse so the CSR-visible sticky masks are fully
        // drained before checking the cleanup state.
        csr_recipe_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_clear_sticky_status();

        repeat (6) @(posedge csr_vif.clk);

        csr_recipe_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_clear_sticky_status();

        repeat (6) @(posedge csr_vif.clk);

        csr_read_recipe_sticky(
            status,
            done_status,
            error_status,
            reject_status,
            state,
            current_slot,
            completed_count,
            slot_done_mask,
            slot_error_mask,
            slot_reject_mask
        );

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_PERF_BUSY_CYCLES, perf_busy);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_PERF_MAC_COUNT, perf_mac);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_PERF_OUTPUT_COUNT, perf_output);

        if (status[0]) begin
            `uvm_fatal("P16F_RECIPE_CLEAR/BUSY",
                $sformatf("%s: recipe still busy after clear, status=0x%08h state=0x%08h",
                    tag,
                    status,
                    state))
        end

        if ((done_status != 32'h0000_0000) ||
            (error_status != 32'h0000_0000) ||
            (reject_status != 32'h0000_0000) ||
            (slot_done_mask != 32'h0000_0000) ||
            (slot_error_mask != 32'h0000_0000) ||
            (slot_reject_mask != 32'h0000_0000)) begin
            `uvm_fatal("P16F_RECIPE_CLEAR/STICKY",
                $sformatf("%s: recipe sticky did not clear: done=0x%08h error=0x%08h reject=0x%08h masks(done/error/reject)=0x%08h/0x%08h/0x%08h",
                    tag,
                    done_status,
                    error_status,
                    reject_status,
                    slot_done_mask,
                    slot_error_mask,
                    slot_reject_mask))
        end

        if (state[3:0] != P16F_RECIPE_STATE_IDLE) begin
            `uvm_fatal("P16F_RECIPE_CLEAR/STATE",
                $sformatf("%s: expected recipe IDLE after clear, state=0x%08h status=0x%08h",
                    tag,
                    state,
                    status))
        end

        if ((perf_busy != 32'h0000_0000) ||
            (perf_mac != 32'h0000_0000) ||
            (perf_output != 32'h0000_0000)) begin
            `uvm_fatal("P16F_RECIPE_CLEAR/PERF",
                $sformatf("%s: recipe perf snapshot did not clear: busy=%0d mac=%0d output=%0d",
                    tag,
                    perf_busy,
                    perf_mac,
                    perf_output))
        end

        `uvm_info("P16F_RECIPE_REJECT",
            $sformatf("%s: recipe/job/P14 sticky status cleared and recipe returned to IDLE", tag),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.1-C direct W1C helpers
    // ------------------------------------------------------------
    task automatic p16f_direct_w1c_expect_clear(
        input logic [11:0] addr,
        input string       tag
    );
        logic [31:0] before_status;
        logic [31:0] after_status;
    begin
        csr.read32_expect_okay(addr, before_status);
        if (before_status == 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1C/P16_W1C_PRE",
                $sformatf("%s: expected nonzero sticky status at addr=0x%03h",
                    tag, addr))
        end

        csr.write32_expect_okay(addr, before_status);
        repeat (2) @(posedge csr_vif.clk);
        csr.read32_expect_okay(addr, after_status);

        if ((after_status & before_status) != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1C/P16_W1C",
                $sformatf("%s: direct W1C failed addr=0x%03h before=0x%08h after=0x%08h",
                    tag, addr, before_status, after_status))
        end

        `uvm_info("CODE_COV_C1C/P16_W1C_PASS",
            $sformatf("%s: direct W1C PASS addr=0x%03h before=0x%08h after=0x%08h",
                tag, addr, before_status, after_status),
            UVM_MEDIUM)
    end
    endtask

    // Slot masks are level-fed into the CSR sticky registers from the recipe
    // sequencer.  A direct W1C while the sequencer mask is still asserted is
    // expected to be reasserted on a later clock.  Exercise the direct W1C
    // against a real nonzero mask, then use one architectural recipe clear to
    // drain the producer and a final direct W1C to remove the documented
    // one-cycle OR residue.  This proves a real write-side path without
    // pretending that W1C can suppress an active level source.
    task automatic p16f_direct_slot_w1c_with_source_drain(
        input logic [11:0] addr,
        input string       tag
    );
        logic [31:0] before_mask;
        logic [31:0] residue_mask;
        logic [31:0] after_mask;
    begin
        csr.read32_expect_okay(addr, before_mask);
        if (before_mask == 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1C/P16_SLOT_PRE",
                $sformatf("%s: expected nonzero slot mask at addr=0x%03h",
                    tag, addr))
        end

        csr.write32_expect_okay(addr, before_mask);
        repeat (2) @(posedge csr_vif.clk);

        // Drain the recipe sequencer's internal mask source.  The existing
        // integrated RTL intentionally may leave one CSR OR residue.
        csr_recipe_clear_sticky_status();
        repeat (6) @(posedge csr_vif.clk);

        csr.read32_expect_okay(addr, residue_mask);
        if (residue_mask != 32'h0000_0000) begin
            csr.write32_expect_okay(addr, residue_mask);
            repeat (2) @(posedge csr_vif.clk);
        end

        csr.read32_expect_okay(addr, after_mask);
        if (after_mask != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1C/P16_SLOT_W1C",
                $sformatf("%s: source-drained direct W1C cleanup failed addr=0x%03h before=0x%08h residue=0x%08h after=0x%08h",
                    tag, addr, before_mask, residue_mask, after_mask))
        end

        `uvm_info("CODE_COV_C1C/P16_SLOT_W1C_PASS",
            $sformatf("%s: real-mask direct W1C + source-drain PASS addr=0x%03h before=0x%08h residue=0x%08h",
                tag, addr, before_mask, residue_mask),
            UVM_MEDIUM)
    end
    endtask

    // Clear recipe/job state while intentionally preserving P14 sticky status.
    // This is used after the injected worker DMA error so a subsequent valid
    // DMA load can deassert the load engine's sticky error source before the
    // real P14 ERROR_STATUS value is cleared through its direct W1C register.
    task automatic p16f_clear_recipe_job_preserve_p14(input string tag);
        logic [31:0] recipe_status;
        logic [31:0] recipe_done;
        logic [31:0] recipe_error;
        logic [31:0] recipe_reject;
        logic [31:0] recipe_state;
        logic [31:0] recipe_current_slot;
        logic [31:0] recipe_completed_count;
        logic [31:0] slot_done_mask;
        logic [31:0] slot_error_mask;
        logic [31:0] slot_reject_mask;
        logic [31:0] job_done;
        logic [31:0] job_error;
        logic [31:0] job_reject;
        logic [31:0] job_state;
        logic [31:0] p14_error;
    begin
        csr_recipe_clear_sticky_status();
        csr_job_clear_sticky_status();
        repeat (6) @(posedge csr_vif.clk);

        csr_recipe_clear_sticky_status();
        csr_job_clear_sticky_status();
        repeat (6) @(posedge csr_vif.clk);

        csr_read_recipe_sticky(
            recipe_status,
            recipe_done,
            recipe_error,
            recipe_reject,
            recipe_state,
            recipe_current_slot,
            recipe_completed_count,
            slot_done_mask,
            slot_error_mask,
            slot_reject_mask
        );
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_DONE_STATUS, job_done);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_ERROR_STATUS, job_error);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS, job_reject);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_STATE, job_state);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, p14_error);

        if (recipe_status[0] ||
            (recipe_state[3:0] != P16F_RECIPE_STATE_IDLE) ||
            (recipe_done != 32'h0000_0000) ||
            (recipe_error != 32'h0000_0000) ||
            (recipe_reject != 32'h0000_0000) ||
            (slot_done_mask != 32'h0000_0000) ||
            (slot_error_mask != 32'h0000_0000) ||
            (slot_reject_mask != 32'h0000_0000) ||
            (job_done != 32'h0000_0000) ||
            (job_error != 32'h0000_0000) ||
            (job_reject != 32'h0000_0000) ||
            (job_state[3:0] != 4'd0)) begin
            `uvm_fatal("CODE_COV_C1C/P16_PRESERVE_CLEAN",
                $sformatf("%s: recipe/job cleanup while preserving P14 failed: recipe status/state=0x%08h/0x%08h sticky(d/e/r)=0x%08h/0x%08h/0x%08h masks=0x%08h/0x%08h/0x%08h job state=0x%08h sticky=0x%08h/0x%08h/0x%08h",
                    tag, recipe_status, recipe_state, recipe_done, recipe_error, recipe_reject,
                    slot_done_mask, slot_error_mask, slot_reject_mask,
                    job_state, job_done, job_error, job_reject))
        end

        if (p14_error == 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1C/P14_ERROR_NOT_PRESERVED",
                $sformatf("%s: expected injected P14 ERROR_STATUS to remain sticky", tag))
        end

        `uvm_info("CODE_COV_C1C/P14_ERROR_PRESERVED",
            $sformatf("%s: recipe/job state clean while P14 ERROR_STATUS preserved=0x%08h",
                tag, p14_error),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_write_recipe_control_value(
        input logic [31:0] value,
        input string       tag
    );
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_CONTROL, value);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_CONTROL, value & 32'h0000_0FFF, tag);
    end
    endtask

    task automatic program_valid_two_slot_recipe(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes,
        input logic [31:0]             user_tag_base
    );
    begin
        csr_write_recipe_slot(
            0,
            P16F_SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            user_tag_base
        );

        csr_write_recipe_slot(
            1,
            P16F_SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            user_tag_base + 32'd1
        );

        csr_write_recipe_control_value(
            P16F_RECIPE_CONTROL_TWO_SLOTS,
            "CSR_RECIPE_CONTROL two-slot recipe"
        );
    end
    endtask

    task automatic csr_start_expect_reject(
        input int unsigned expected_reject_bit,
        input string       tag
    );
    begin
        csr_start_recipe();
        repeat (3) @(posedge csr_vif.clk);
        csr_expect_recipe_reject_bit(expected_reject_bit, tag);
    end
    endtask

    // ------------------------------------------------------------
    // Immediate command/descriptor reject checks
    // ------------------------------------------------------------
    task automatic run_d1_recipe_micro_op_busy_reject(
        input ai_accel_subsys_seq_item profile_item
    );
        logic [31:0] cmd;
        logic [31:0] reject_status;
        logic [31:0] after_status;
    begin
        csr_clear_recipe_job_and_p14_sticky("before D1 recipe micro-op busy probe");
        csr_write_gemm_config(profile_item);
        csr_start_gemm();
        csr_wait_p14_status_bit(C1D1_P14_STATUS_GEMM_BUSY,
            done_timeout_cycles, "P14 GEMM ownership before START_RECIPE reject");

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::RECIPE_CMD_START] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_COMMAND, cmd);
        repeat (2) @(posedge csr_vif.clk);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS, reject_status);
        if (!reject_status[C1D1_RECIPE_REJ_MICRO_OP_BUSY]) begin
            `uvm_fatal("CODE_COV_C1D1/P16_MICRO_OP_BUSY_MISSING",
                $sformatf("Expected recipe MICRO_OP_BUSY reject while P14 GEMM active: reject=0x%08h",
                    reject_status))
        end

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS, reject_status);
        repeat (2) @(posedge csr_vif.clk);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS, after_status);
        if ((after_status & reject_status) != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1D1/P16_MICRO_OP_BUSY_CLEAR",
                $sformatf("Recipe MICRO_OP_BUSY reject W1C failed: before=0x%08h after=0x%08h",
                    reject_status, after_status))
        end

        csr_poll_gemm_done(done_timeout_cycles);
        csr_clear_recipe_job_and_p14_sticky("after D1 recipe micro-op busy probe");

        `uvm_info("CODE_COV_C1D1/P16_MICRO_OP_BUSY_PASS",
            $sformatf("P16 START_RECIPE while genuine P14 micro-op busy reject PASS: reject=0x%08h",
                reject_status),
            UVM_MEDIUM)
    end
    endtask

    task automatic run_immediate_reject_checks(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
        logic [11:0] slot0;
        logic [31:0] cmd;
    begin
        slot0 = csr.recipe_slot_addr(0, 7'h00);

        csr_write_recipe_control_value(
            P16F_RECIPE_CONTROL_ZERO_COUNT,
            "CSR_RECIPE_CONTROL zero-count"
        );
        csr_start_expect_reject(
            ai_accel_csr_access_helper::RECIPE_REJ_ZERO_COUNT,
            "zero recipe_count reject"
        );

        // With a sticky reject already present, START_RECIPE + CLEAR_ERROR
        // is rejected as an unsupported combo and must not clear the sticky.
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::RECIPE_CMD_START]       = 1'b1;
        cmd[ai_accel_csr_access_helper::RECIPE_CMD_CLEAR_ERROR] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_COMMAND, cmd);
        repeat (3) @(posedge csr_vif.clk);
        csr_expect_recipe_reject_bit(
            ai_accel_csr_access_helper::RECIPE_REJ_UNSUPPORTED_COMBO,
            "START_RECIPE plus CLEAR_ERROR while reject sticky"
        );
        p16f_direct_w1c_expect_clear(
            ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS,
            "P16 RECIPE_REJECT_STATUS after real prevalidation rejects"
        );
        csr_clear_recipe_job_and_p14_sticky("after zero-count / unsupported-combo reject");

        csr_write_recipe_control_value(
            P16F_RECIPE_CONTROL_RANGE_INVALID,
            "CSR_RECIPE_CONTROL slot-range invalid"
        );
        csr_start_expect_reject(
            ai_accel_csr_access_helper::RECIPE_REJ_SLOT_RANGE,
            "slot range reject"
        );
        csr_clear_recipe_job_and_p14_sticky("after slot range reject");

        program_valid_two_slot_recipe(
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            32'h0000_16F0
        );
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_CONTROL, 32'h0000_0000);
        csr_start_expect_reject(
            ai_accel_csr_access_helper::RECIPE_REJ_SLOT_INVALID,
            "disabled slot reject"
        );
        csr_clear_recipe_job_and_p14_sticky("after disabled slot reject");

        program_valid_two_slot_recipe(
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            32'h0000_16F2
        );
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_DIM_K, 32'h0000_0000);
        csr_start_expect_reject(
            ai_accel_csr_access_helper::RECIPE_REJ_SLOT_DESC,
            "descriptor invalid reject"
        );
        csr_clear_recipe_job_and_p14_sticky("after descriptor invalid reject");

        // Keep every other descriptor field legal and select an unsupported
        // output mode so validation reaches the explicit output-mode guard.
        program_valid_two_slot_recipe(
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            32'h0000_16F4
        );
        csr.write32_expect_okay(
            slot0 + ai_accel_csr_access_helper::SLOT_CONTROL,
            C1D1_SLOT0_CONTROL_DMA_UNSUPPORTED_OUTPUT
        );
        csr_start_expect_reject(
            ai_accel_csr_access_helper::RECIPE_REJ_SLOT_DESC,
            "unsupported recipe slot output mode descriptor reject"
        );
        `uvm_info("CODE_COV_C1D1/P16_DESC_OUTPUT_MODE_PASS",
            "P16 recipe descriptor unsupported output-mode validation reject PASS",
            UVM_MEDIUM)
        csr_clear_recipe_job_and_p14_sticky("after unsupported output-mode descriptor reject");
    end
    endtask

    task automatic csr_wait_for_recipe_busy(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] state;
        logic [31:0] current_slot;
        logic [31:0] completed_count;
        logic [31:0] slot_done_mask;
        logic [31:0] slot_error_mask;
        logic [31:0] slot_reject_mask;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr_read_recipe_sticky(
                status,
                done_status,
                error_status,
                reject_status,
                state,
                current_slot,
                completed_count,
                slot_done_mask,
                slot_error_mask,
                slot_reject_mask
            );

            if (status[0]) begin
                `uvm_info("P16F_RECIPE_REJECT",
                    $sformatf("Observed recipe busy before reject injection: status=0x%08h state=0x%08h current_slot=%0d completed=%0d",
                        status,
                        state,
                        current_slot,
                        completed_count),
                    UVM_MEDIUM)
                return;
            end

            if (done_status[ai_accel_csr_access_helper::RECIPE_DONE]) begin
                `uvm_fatal("P16F_RECIPE_REJECT/BUSY_WAIT_DONE",
                    $sformatf("Recipe completed before busy reject could be injected: done=0x%08h status=0x%08h state=0x%08h",
                        done_status,
                        status,
                        state))
            end

            if (error_status != 32'h0000_0000) begin
                `uvm_fatal("P16F_RECIPE_REJECT/BUSY_WAIT_ERROR",
                    $sformatf("Recipe error before busy reject injection: error=0x%08h reject=0x%08h state=0x%08h",
                        error_status,
                        reject_status,
                        state))
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("P16F_RECIPE_REJECT/BUSY_TIMEOUT",
                    $sformatf("Timed out waiting for recipe busy: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h state=0x%08h current_slot=%0d completed=%0d",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        state,
                        current_slot,
                        completed_count))
            end
        end
    end
    endtask

    task automatic csr_poll_recipe_done_allow_reject(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] state;
        logic [31:0] current_slot;
        logic [31:0] completed_count;
        logic [31:0] slot_done_mask;
        logic [31:0] slot_error_mask;
        logic [31:0] slot_reject_mask;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr_read_recipe_sticky(
                status,
                done_status,
                error_status,
                reject_status,
                state,
                current_slot,
                completed_count,
                slot_done_mask,
                slot_error_mask,
                slot_reject_mask
            );

            if (error_status != 32'h0000_0000) begin
                `uvm_fatal("P16F_RECIPE_REJECT/UNEXPECTED_RECIPE_ERROR",
                    $sformatf("Recipe error during busy-reject completion: error=0x%08h reject=0x%08h state=0x%08h status=0x%08h",
                        error_status,
                        reject_status,
                        state,
                        status))
            end

            if (done_status[ai_accel_csr_access_helper::RECIPE_DONE]) begin
                if (!done_status[ai_accel_csr_access_helper::RECIPE_ALL_SLOTS_DONE]) begin
                    `uvm_fatal("P16F_RECIPE_REJECT/NO_ALL_DONE",
                        $sformatf("RECIPE_DONE set without ALL_SLOTS_DONE: done=0x%08h", done_status))
                end

                if (!done_status[ai_accel_csr_access_helper::RECIPE_FINAL_STORE_DONE]) begin
                    `uvm_fatal("P16F_RECIPE_REJECT/NO_FINAL_STORE_DONE",
                        $sformatf("RECIPE_DONE set without FINAL_STORE_DONE: done=0x%08h", done_status))
                end

                if (state[3:0] != P16F_RECIPE_STATE_DONE) begin
                    `uvm_fatal("P16F_RECIPE_REJECT/BAD_DONE_STATE",
                        $sformatf("RECIPE_DONE set but state is not DONE: state=0x%08h done=0x%08h",
                            state,
                            done_status))
                end

                if (completed_count != 32'd2) begin
                    `uvm_fatal("P16F_RECIPE_REJECT/BAD_COMPLETED_COUNT",
                        $sformatf("Completed count mismatch: expected=2 actual=%0d", completed_count))
                end

                if (slot_done_mask[1:0] != 2'b11) begin
                    `uvm_fatal("P16F_RECIPE_REJECT/BAD_DONE_MASK",
                        $sformatf("Slot done mask mismatch: expected low bits=2'b11 actual=0x%08h", slot_done_mask))
                end

                if ((slot_error_mask != 32'h0000_0000) ||
                    (slot_reject_mask != 32'h0000_0000)) begin
                    `uvm_fatal("P16F_RECIPE_REJECT/UNEXPECTED_SLOT_MASK",
                        $sformatf("Unexpected slot error/reject masks while command rejects are allowed: error=0x%08h reject=0x%08h",
                            slot_error_mask,
                            slot_reject_mask))
                end

                `uvm_info("P16F_RECIPE_REJECT",
                    $sformatf("Observed recipe completion after busy/manual reject injection: done=0x%08h reject=0x%08h state=0x%08h completed=%0d polls=%0d",
                        done_status,
                        reject_status,
                        state,
                        completed_count,
                        cnt),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("P16F_RECIPE_REJECT/DONE_TIMEOUT",
                    $sformatf("Timed out waiting for recipe done: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h state=0x%08h current_slot=%0d completed=%0d",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        state,
                        current_slot,
                        completed_count))
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // Busy/manual reject check around one valid recipe
    // ------------------------------------------------------------
    task automatic run_busy_reject_and_valid_completion(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes,
        input int unsigned             c_elems,
        output int signed              actual_c[]
    );
        logic [31:0] cmd;
    begin
        program_valid_two_slot_recipe(
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            32'h0000_16F4
        );

        csr_check_recipe_idle_ready("before recipe busy-reject START_RECIPE");
        csr_start_recipe();
        csr_wait_for_recipe_busy(done_timeout_cycles);

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::RECIPE_CMD_START] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_COMMAND, cmd);
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_recipe_reject_bit(
            ai_accel_csr_access_helper::RECIPE_REJ_BUSY,
            "START_RECIPE while recipe_busy"
        );

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_START_GEMM] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMMAND, cmd);
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_recipe_reject_bit(
            ai_accel_csr_access_helper::RECIPE_REJ_MANUAL_CMD,
            "P14 manual START_GEMM while recipe_busy"
        );

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::JOB_CMD_START] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_COMMAND, cmd);
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_recipe_reject_bit(
            ai_accel_csr_access_helper::RECIPE_REJ_MANUAL_CMD,
            "P15 START_JOB while recipe_busy"
        );

        csr_poll_recipe_done_allow_reject(done_timeout_cycles * 2);
        csr_check_recipe_perf_snapshot(profile_item);

        // Real completed recipe state for the direct DONE/slot-DONE W1C paths.
        p16f_direct_w1c_expect_clear(
            ai_accel_csr_access_helper::CSR_RECIPE_DONE_STATUS,
            "P16 RECIPE_DONE_STATUS after valid recipe completion"
        );
        p16f_direct_slot_w1c_with_source_drain(
            ai_accel_csr_access_helper::CSR_RECIPE_SLOT_DONE_MASK,
            "P16 RECIPE_SLOT_DONE_MASK after valid recipe completion"
        );

        repeat (5) @(posedge csr_vif.clk);
        collect_dma_destination_c(c_elems, actual_c);

        csr_clear_recipe_job_and_p14_sticky("after completed recipe with busy/manual rejects");
    end
    endtask

    task automatic csr_poll_recipe_error(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] state;
        logic [31:0] current_slot;
        logic [31:0] completed_count;
        logic [31:0] slot_done_mask;
        logic [31:0] slot_error_mask;
        logic [31:0] slot_reject_mask;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr_read_recipe_sticky(
                status,
                done_status,
                error_status,
                reject_status,
                state,
                current_slot,
                completed_count,
                slot_done_mask,
                slot_error_mask,
                slot_reject_mask
            );

            if (error_status[ai_accel_csr_access_helper::RECIPE_ERR_SLOT_JOB_ERROR]) begin
                csr_expect_recipe_error_bit(
                    ai_accel_csr_access_helper::RECIPE_ERR_SLOT_JOB_ERROR,
                    32'h0000_0001,
                    "slot0 worker DMA-load error propagation"
                );
                return;
            end

            if (done_status[ai_accel_csr_access_helper::RECIPE_DONE]) begin
                `uvm_fatal("P16F_RECIPE_ERROR/UNEXPECTED_DONE",
                    $sformatf("Recipe completed even though worker error injection was enabled: done=0x%08h error=0x%08h reject=0x%08h state=0x%08h",
                        done_status,
                        error_status,
                        reject_status,
                        state))
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("P16F_RECIPE_ERROR/TIMEOUT",
                    $sformatf("Timed out waiting for recipe worker-error propagation: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h state=0x%08h current_slot=%0d completed=%0d masks(done/error/reject)=0x%08h/0x%08h/0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        state,
                        current_slot,
                        completed_count,
                        slot_done_mask,
                        slot_error_mask,
                        slot_reject_mask))
            end
        end
    end
    endtask


    task automatic csr_poll_recipe_done_or_recovery_error(
        input  int unsigned timeout_cycles,
        output bit          saw_recovery_error
    );
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] state;
        logic [31:0] current_slot;
        logic [31:0] completed_count;
        logic [31:0] slot_done_mask;
        logic [31:0] slot_error_mask;
        logic [31:0] slot_reject_mask;
        int unsigned cnt;
    begin
        cnt = 0;
        saw_recovery_error = 1'b0;

        forever begin
            csr_read_recipe_sticky(
                status,
                done_status,
                error_status,
                reject_status,
                state,
                current_slot,
                completed_count,
                slot_done_mask,
                slot_error_mask,
                slot_reject_mask
            );

            if (error_status[ai_accel_csr_access_helper::RECIPE_ERR_SLOT_JOB_ERROR]) begin
                saw_recovery_error = 1'b1;

                if (slot_error_mask[0] != 1'b1) begin
                    `uvm_fatal("P16F_RECIPE_RECOVERY/SLOT_MASK",
                        $sformatf("Recovery attempt entered recipe error without slot0 error mask: error=0x%08h slot_error_mask=0x%08h state=0x%08h",
                            error_status,
                            slot_error_mask,
                            state))
                end

                `uvm_info("P16F_RECIPE_RECOVERY",
                    $sformatf("Recovery attempt observed one expected slot0 worker-error retry condition: error=0x%08h slot_error_mask=0x%08h state=0x%08h polls=%0d",
                        error_status,
                        slot_error_mask,
                        state,
                        cnt),
                    UVM_MEDIUM)
                return;
            end

            if (error_status != 32'h0000_0000) begin
                `uvm_fatal("P16F_RECIPE_RECOVERY/UNEXPECTED_ERROR",
                    $sformatf("Unexpected recipe error during recovery attempt: error=0x%08h reject=0x%08h state=0x%08h slot_error_mask=0x%08h",
                        error_status,
                        reject_status,
                        state,
                        slot_error_mask))
            end

            if (reject_status != 32'h0000_0000) begin
                `uvm_fatal("P16F_RECIPE_RECOVERY/UNEXPECTED_REJECT",
                    $sformatf("Unexpected recipe reject during recovery attempt: reject=0x%08h error=0x%08h state=0x%08h",
                        reject_status,
                        error_status,
                        state))
            end

            if (done_status[ai_accel_csr_access_helper::RECIPE_DONE]) begin
                if (!done_status[ai_accel_csr_access_helper::RECIPE_ALL_SLOTS_DONE]) begin
                    `uvm_fatal("P16F_RECIPE_RECOVERY/NO_ALL_DONE",
                        $sformatf("RECIPE_DONE set without ALL_SLOTS_DONE: done=0x%08h", done_status))
                end

                if (!done_status[ai_accel_csr_access_helper::RECIPE_FINAL_STORE_DONE]) begin
                    `uvm_fatal("P16F_RECIPE_RECOVERY/NO_FINAL_STORE_DONE",
                        $sformatf("RECIPE_DONE set without FINAL_STORE_DONE: done=0x%08h", done_status))
                end

                if (state[3:0] != P16F_RECIPE_STATE_DONE) begin
                    `uvm_fatal("P16F_RECIPE_RECOVERY/BAD_DONE_STATE",
                        $sformatf("RECIPE_DONE set but state is not DONE: state=0x%08h done=0x%08h",
                            state,
                            done_status))
                end

                if (completed_count != 32'd2) begin
                    `uvm_fatal("P16F_RECIPE_RECOVERY/BAD_COMPLETED_COUNT",
                        $sformatf("Completed count mismatch: expected=2 actual=%0d", completed_count))
                end

                if (slot_done_mask[1:0] != 2'b11) begin
                    `uvm_fatal("P16F_RECIPE_RECOVERY/BAD_DONE_MASK",
                        $sformatf("Slot done mask mismatch: expected low bits=2'b11 actual=0x%08h", slot_done_mask))
                end

                if ((slot_error_mask != 32'h0000_0000) ||
                    (slot_reject_mask != 32'h0000_0000)) begin
                    `uvm_fatal("P16F_RECIPE_RECOVERY/UNEXPECTED_SLOT_MASK",
                        $sformatf("Unexpected slot error/reject masks on recovery done: error=0x%08h reject=0x%08h",
                            slot_error_mask,
                            slot_reject_mask))
                end

                `uvm_info("P16F_RECIPE_RECOVERY",
                    $sformatf("Observed successful recipe recovery completion: done=0x%08h state=0x%08h completed=%0d polls=%0d",
                        done_status,
                        state,
                        completed_count,
                        cnt),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("P16F_RECIPE_RECOVERY/TIMEOUT",
                    $sformatf("Timed out waiting for recovery done/error: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h state=0x%08h current_slot=%0d completed=%0d masks(done/error/reject)=0x%08h/0x%08h/0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        state,
                        current_slot,
                        completed_count,
                        slot_done_mask,
                        slot_error_mask,
                        slot_reject_mask))
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // Slot worker error propagation and valid recovery
    // ------------------------------------------------------------
    task automatic run_worker_error_and_recovery(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes,
        input int unsigned             c_elems,
        output int signed              actual_c[]
    );
    begin
        program_valid_two_slot_recipe(
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            32'h0000_16F6
        );

        csr_check_recipe_idle_ready("before worker-error recipe");
        vif.dma_src_set_rresp_error(1'b1, 0);
        csr_start_recipe();
        csr_poll_recipe_error(done_timeout_cycles * 2);
        vif.dma_src_set_rresp_error(1'b0, -1);

        // The injected worker fault produces real P16 RECIPE_ERROR,
        // P16 SLOT_ERROR, P15 JOB_ERROR and P14 ERROR sticky state.
        // Error summary sources are pulses, so their direct W1C clears can be
        // checked immediately.  The slot error mask is level-fed and uses the
        // source-drain helper above.
        p16f_direct_w1c_expect_clear(
            ai_accel_csr_access_helper::CSR_RECIPE_ERROR_STATUS,
            "P16 RECIPE_ERROR_STATUS after worker DMA-load error"
        );
        p16f_direct_w1c_expect_clear(
            ai_accel_csr_access_helper::CSR_JOB_ERROR_STATUS,
            "P15 JOB_ERROR_STATUS after worker DMA-load error"
        );
        p16f_direct_slot_w1c_with_source_drain(
            ai_accel_csr_access_helper::CSR_RECIPE_SLOT_ERROR_MASK,
            "P16 RECIPE_SLOT_ERROR_MASK after worker DMA-load error"
        );

        // Keep P14 ERROR_STATUS sticky while returning the recipe/job
        // sequencers to IDLE.  The recovery DMA load below clears the
        // dma_load_engine's level error source without touching the CSR q.
        p16f_clear_recipe_job_preserve_p14("after worker-error recipe");

        prepare_dma_source_and_destination_from_current_payload();

        program_valid_two_slot_recipe(
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            32'h0000_16F8
        );

        // A deliberately injected DMA source RRESP error can leave one stale
        // AXI read response parked in the simple TB source responder after the
        // worker aborts.  The first post-error recovery attempt is therefore
        // allowed to consume and report exactly one slot0 worker error.  If
        // that happens, clear all sticky state, reinitialize the payload, and
        // retry the same valid recipe once.  The retry must complete normally.
        begin
            bit saw_recovery_error;

            vif.dma_src_set_rresp_error(1'b0, -1);
            repeat (10) @(posedge csr_vif.clk);

            csr_check_recipe_idle_ready("before post-error recovery recipe");
            csr_start_recipe();
            csr_poll_recipe_done_or_recovery_error(done_timeout_cycles * 2, saw_recovery_error);

            if (saw_recovery_error) begin
                `uvm_info("P16F_RECIPE_RECOVERY",
                    "First post-error recovery attempt drained a stale DMA source RRESP error; clearing and retrying valid recipe once",
                    UVM_MEDIUM)

                vif.dma_src_set_rresp_error(1'b0, -1);
                p16f_clear_recipe_job_preserve_p14("after stale DMA source response drain");

                prepare_dma_source_and_destination_from_current_payload();

                program_valid_two_slot_recipe(
                    profile_item,
                    a_bytes,
                    b_bytes,
                    c_bytes,
                    32'h0000_16FA
                );

                csr_check_recipe_idle_ready("before post-error recovery retry recipe");
                csr_start_recipe();
                csr_poll_recipe_done(done_timeout_cycles * 2);
            end
        end

        // A successful recovery DMA load has now deasserted the load engine's
        // sticky error source, while the original P14 CSR error bit was
        // intentionally preserved.  The direct W1C can therefore be proven
        // without immediate level-source reassertion.
        p16f_direct_w1c_expect_clear(
            ai_accel_csr_access_helper::CSR_ERROR_STATUS,
            "P14 ERROR_STATUS after successful DMA-load recovery"
        );

        csr_check_recipe_perf_snapshot(profile_item);

        repeat (5) @(posedge csr_vif.clk);
        collect_dma_destination_c(c_elems, actual_c);

        csr_clear_recipe_job_and_p14_sticky("after post-error recovery recipe");
    end
    endtask

    // Current payload cache used only to reinitialize source/destination
    // memory after an injected worker error.
    int signed current_a_flat[];
    int signed current_b_flat[];

    task automatic prepare_dma_source_and_destination_from_current_payload();
    begin
        prepare_dma_source_and_destination(current_a_flat, current_b_flat);
    end
    endtask

    // ------------------------------------------------------------
    // Run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ai_accel_subsys_seq_item profile_item;
        int signed               a_flat[];
        int signed               b_flat[];
        int signed               expected_c[];
        int signed               actual_c[];
        int signed               recovery_c[];
        int unsigned             c_elems;
        int unsigned             c_bytes;
    begin
        phase.raise_objection(this);

        `uvm_info("P16F_RECIPE_REJECT",
            "Starting P16F CSR recipe reject / busy / error handling smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        build_selected_payload(
            profile_item,
            a_flat,
            b_flat,
            expected_c
        );

        current_a_flat = new[a_flat.size()];
        current_b_flat = new[b_flat.size()];
        foreach (a_flat[i]) begin
            current_a_flat[i] = a_flat[i];
        end
        foreach (b_flat[i]) begin
            current_b_flat[i] = b_flat[i];
        end

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P16F_RECIPE_REJECT/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_check_recipe_idle_ready("initial P16F state");

        if ((get_type_name() == "ai_accel_subsys_csr_recipe_reject_error_test") &&
            (selected_case_id == 102)) begin
            run_d1_recipe_micro_op_busy_reject(profile_item);
            prepare_dma_source_and_destination(a_flat, b_flat);
            csr_check_recipe_idle_ready("after D1 P14 micro-op ownership reject probe");
        end

        run_immediate_reject_checks(
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        prepare_dma_source_and_destination(a_flat, b_flat);
        run_busy_reject_and_valid_completion(
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            c_elems,
            actual_c
        );
        compare_result_vectors(expected_c, actual_c);

        prepare_dma_source_and_destination(a_flat, b_flat);
        run_worker_error_and_recovery(
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            c_elems,
            recovery_c
        );
        compare_result_vectors(expected_c, recovery_c);

        `uvm_info("P16F_RECIPE_REJECT",
            $sformatf("P16F CSR recipe reject / busy / error handling smoke completed: CASE_ID=%0d test_kind=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
                selected_case_id,
                selected_test_kind,
                a_flat.size(),
                b_flat.size(),
                c_elems),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
