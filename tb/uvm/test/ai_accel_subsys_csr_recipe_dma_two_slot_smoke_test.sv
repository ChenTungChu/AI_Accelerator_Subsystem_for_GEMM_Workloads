// File: tb/uvm/test/ai_accel_subsys_csr_recipe_dma_two_slot_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_RECIPE_DMA_TWO_SLOT_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_RECIPE_DMA_TWO_SLOT_SMOKE_TEST_SV

// ------------------------------------------------------------
// CSR recipe-level DMA two-slot smoke
//
// Scope:
//   - preload one A/B payload into the DMA source memory model
//   - program two P16 recipe descriptor slots
//   - issue CSR_RECIPE_COMMAND.START_RECIPE once
//   - let ai_accel_recipe_sequencer dispatch slot0 then slot1
//     through the existing P15 single-job worker
//   - slot0 runs DMA load A/B -> GEMM -> HOST_READBACK
//   - slot1 runs DMA load A/B -> GEMM -> DMA store
//   - poll recipe-level sticky done/error/reject registers
//   - check recipe-level per-slot masks and accumulated perf
//   - compare destination memory against the software reference
//
// This P16C bring-up intentionally validates the queue runner and
// worker dispatch path.  C RMW partial-K recipes are left for P16D.
// ------------------------------------------------------------

class ai_accel_subsys_csr_recipe_dma_two_slot_smoke_test extends ai_accel_subsys_csr_job_dma_load_store_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_recipe_dma_two_slot_smoke_test)

    localparam logic [31:0] SLOT0_CONTROL_DMA_HOST_READBACK = 32'h0000_0003;
    localparam logic [31:0] SLOT1_CONTROL_DMA_DMA_STORE     = 32'h0000_000B;
    localparam logic [31:0] RECIPE_CONTROL_TWO_SLOTS        = 32'h0000_0702;

    localparam logic [3:0] RECIPE_STATE_DONE  = 4'd8;
    localparam logic [3:0] RECIPE_STATE_ERROR = 4'd9;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_csr_recipe_dma_two_slot_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Recipe helpers
    // ------------------------------------------------------------
    task automatic csr_recipe_clear_sticky_status();
        logic [31:0] clear_cmd;
    begin
        clear_cmd = 32'h0000_0000;
        clear_cmd[ai_accel_csr_access_helper::RECIPE_CMD_CLEAR_DONE]        = 1'b1;
        clear_cmd[ai_accel_csr_access_helper::RECIPE_CMD_CLEAR_ERROR]       = 1'b1;
        clear_cmd[ai_accel_csr_access_helper::RECIPE_CMD_CLEAR_PERF]        = 1'b1;
        clear_cmd[ai_accel_csr_access_helper::RECIPE_CMD_CLEAR_SLOT_STATUS] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_RECIPE_COMMAND,
            clear_cmd
        );
    end
    endtask

    task automatic csr_check_recipe_idle_ready(input string tag);
        logic [31:0] recipe_status;
        logic [31:0] recipe_error;
        logic [31:0] recipe_reject;
    begin
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_RECIPE_STATUS,
            recipe_status
        );

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_RECIPE_ERROR_STATUS,
            recipe_error
        );

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS,
            recipe_reject
        );

        if (recipe_error != 32'h0000_0000) begin
            `uvm_fatal("CSR_RECIPE_DMA_SMOKE/RECIPE_ERROR_PRE",
                $sformatf("%s: CSR_RECIPE_ERROR_STATUS is nonzero before START_RECIPE: 0x%08h",
                    tag, recipe_error))
        end

        if (recipe_reject != 32'h0000_0000) begin
            `uvm_fatal("CSR_RECIPE_DMA_SMOKE/RECIPE_REJECT_PRE",
                $sformatf("%s: CSR_RECIPE_REJECT_STATUS is nonzero before START_RECIPE: 0x%08h",
                    tag, recipe_reject))
        end

        if (!recipe_status[3]) begin
            `uvm_fatal("CSR_RECIPE_DMA_SMOKE/NOT_READY",
                $sformatf("%s: CSR_RECIPE_STATUS.RECIPE_ACCEPT_READY is low: 0x%08h",
                    tag, recipe_status))
        end
    end
    endtask

    task automatic csr_write_recipe_slot(
        input int unsigned             slot_idx,
        input logic [31:0]             slot_control,
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes,
        input logic [31:0]             user_tag
    );
        logic [11:0] slot_base;
        int unsigned a_beats;
        int unsigned b_beats;
    begin
        slot_base = csr.recipe_slot_addr(slot_idx, 7'h00);
        a_beats  = bytes_to_beats(a_bytes);
        b_beats  = bytes_to_beats(b_bytes);

        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_CONTROL, slot_control);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_BASE_ADDR_A, profile_item.base_addr_a);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_BASE_ADDR_B, profile_item.base_addr_b);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_BASE_ADDR_C, profile_item.base_addr_c);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_DIM_M, 32'(profile_item.dim_m));
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_DIM_N, 32'(profile_item.dim_n));
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_DIM_K, 32'(profile_item.dim_k));

        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_A_SRC_BASE, DMA_SRC_A_BASE);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_A_DST_BASE, profile_item.base_addr_a);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_A_LOAD_BEATS, 32'(a_beats));

        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_B_SRC_BASE, DMA_SRC_B_BASE);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_B_DST_BASE, profile_item.base_addr_b);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_B_LOAD_BEATS, 32'(b_beats));

        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_STORE_SRC_BASE, profile_item.base_addr_c);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_STORE_DST_BASE, DMA_DST_C_BASE);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_STORE_BYTE_COUNT, 32'(c_bytes));
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_USER_TAG, user_tag);

        csr.expect_read32(slot_base + ai_accel_csr_access_helper::SLOT_CONTROL, slot_control, "SLOT_CONTROL");
        csr.expect_read32(slot_base + ai_accel_csr_access_helper::SLOT_DIM_M, 32'(profile_item.dim_m), "SLOT_DIM_M");
        csr.expect_read32(slot_base + ai_accel_csr_access_helper::SLOT_DIM_N, 32'(profile_item.dim_n), "SLOT_DIM_N");
        csr.expect_read32(slot_base + ai_accel_csr_access_helper::SLOT_DIM_K, 32'(profile_item.dim_k), "SLOT_DIM_K");
        csr.expect_read32(slot_base + ai_accel_csr_access_helper::SLOT_A_LOAD_BEATS, 32'(a_beats), "SLOT_A_LOAD_BEATS");
        csr.expect_read32(slot_base + ai_accel_csr_access_helper::SLOT_B_LOAD_BEATS, 32'(b_beats), "SLOT_B_LOAD_BEATS");
        csr.expect_read32(slot_base + ai_accel_csr_access_helper::SLOT_STORE_BYTE_COUNT, 32'(c_bytes), "SLOT_STORE_BYTE_COUNT");

        `uvm_info("CSR_RECIPE_DMA_SMOKE",
            $sformatf("Programmed recipe slot%0d: control=0x%08h A src=0x%08h dst=0x%08h beats=%0d B src=0x%08h dst=0x%08h beats=%0d C src=0x%08h dst=0x%08h bytes=%0d tag=0x%08h dim=(%0d,%0d,%0d)",
                slot_idx,
                slot_control,
                DMA_SRC_A_BASE,
                profile_item.base_addr_a,
                a_beats,
                DMA_SRC_B_BASE,
                profile_item.base_addr_b,
                b_beats,
                profile_item.base_addr_c,
                DMA_DST_C_BASE,
                c_bytes,
                user_tag,
                profile_item.dim_m,
                profile_item.dim_n,
                profile_item.dim_k),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_write_recipe_control();
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_RECIPE_CONTROL,
            RECIPE_CONTROL_TWO_SLOTS
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_RECIPE_CONTROL,
            RECIPE_CONTROL_TWO_SLOTS,
            "CSR_RECIPE_CONTROL"
        );
    end
    endtask

    task automatic csr_start_recipe();
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::RECIPE_CMD_START] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_RECIPE_COMMAND,
            cmd
        );

        `uvm_info("CSR_RECIPE_DMA_SMOKE",
            "Issued CSR_RECIPE_COMMAND.START_RECIPE",
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_poll_recipe_done(input int unsigned timeout_cycles);
        logic [31:0] recipe_status;
        logic [31:0] recipe_done_status;
        logic [31:0] recipe_error_status;
        logic [31:0] recipe_reject_status;
        logic [31:0] recipe_state;
        logic [31:0] current_slot;
        logic [31:0] completed_count;
        logic [31:0] slot_done_mask;
        logic [31:0] slot_error_mask;
        logic [31:0] slot_reject_mask;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_STATUS, recipe_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_DONE_STATUS, recipe_done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_ERROR_STATUS, recipe_error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS, recipe_reject_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_STATE, recipe_state);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_CURRENT_SLOT, current_slot);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_COMPLETED_COUNT, completed_count);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_DONE_MASK, slot_done_mask);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_ERROR_MASK, slot_error_mask);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_REJECT_MASK, slot_reject_mask);

            if (recipe_error_status != 32'h0000_0000) begin
                `uvm_fatal("CSR_RECIPE_DMA_SMOKE/RECIPE_ERROR_STATUS",
                    $sformatf("CSR_RECIPE_ERROR_STATUS became nonzero: error=0x%08h reject=0x%08h state=0x%08h current_slot=%0d done_mask=0x%08h err_mask=0x%08h rej_mask=0x%08h",
                        recipe_error_status,
                        recipe_reject_status,
                        recipe_state,
                        current_slot,
                        slot_done_mask,
                        slot_error_mask,
                        slot_reject_mask))
            end

            if (recipe_reject_status != 32'h0000_0000) begin
                `uvm_fatal("CSR_RECIPE_DMA_SMOKE/RECIPE_REJECT_STATUS",
                    $sformatf("CSR_RECIPE_REJECT_STATUS became nonzero: reject=0x%08h state=0x%08h current_slot=%0d status=0x%08h",
                        recipe_reject_status,
                        recipe_state,
                        current_slot,
                        recipe_status))
            end

            if (recipe_state[3:0] == RECIPE_STATE_ERROR) begin
                `uvm_fatal("CSR_RECIPE_DMA_SMOKE/RECIPE_ERROR_STATE",
                    $sformatf("CSR_RECIPE_STATE reached ERROR without sticky error: state=0x%08h status=0x%08h done=0x%08h",
                        recipe_state,
                        recipe_status,
                        recipe_done_status))
            end

            if (recipe_done_status[ai_accel_csr_access_helper::RECIPE_DONE]) begin
                if (!recipe_done_status[ai_accel_csr_access_helper::RECIPE_ALL_SLOTS_DONE]) begin
                    `uvm_fatal("CSR_RECIPE_DMA_SMOKE/NO_ALL_SLOTS_DONE",
                        $sformatf("RECIPE_DONE set without ALL_SLOTS_DONE: DONE_STATUS=0x%08h",
                            recipe_done_status))
                end

                if (!recipe_done_status[ai_accel_csr_access_helper::RECIPE_FINAL_STORE_DONE]) begin
                    `uvm_fatal("CSR_RECIPE_DMA_SMOKE/NO_FINAL_STORE_DONE",
                        $sformatf("RECIPE_DONE set without FINAL_STORE_DONE: DONE_STATUS=0x%08h",
                            recipe_done_status))
                end

                if (recipe_state[3:0] != RECIPE_STATE_DONE) begin
                    `uvm_fatal("CSR_RECIPE_DMA_SMOKE/BAD_DONE_STATE",
                        $sformatf("RECIPE_DONE set but CSR_RECIPE_STATE is not DONE: state=0x%08h done=0x%08h",
                            recipe_state,
                            recipe_done_status))
                end

                if (completed_count != 32'd2) begin
                    `uvm_fatal("CSR_RECIPE_DMA_SMOKE/BAD_COMPLETED_COUNT",
                        $sformatf("CSR_RECIPE_COMPLETED_COUNT mismatch: expected=2 actual=%0d",
                            completed_count))
                end

                if (slot_done_mask[1:0] != 2'b11) begin
                    `uvm_fatal("CSR_RECIPE_DMA_SMOKE/BAD_SLOT_DONE_MASK",
                        $sformatf("CSR_RECIPE_SLOT_DONE_MASK mismatch: expected low bits=2'b11 actual=0x%08h",
                            slot_done_mask))
                end

                if ((slot_error_mask != 32'h0000_0000) || (slot_reject_mask != 32'h0000_0000)) begin
                    `uvm_fatal("CSR_RECIPE_DMA_SMOKE/BAD_SLOT_ERROR_MASK",
                        $sformatf("Unexpected slot error/reject masks: error=0x%08h reject=0x%08h",
                            slot_error_mask,
                            slot_reject_mask))
                end

                `uvm_info("CSR_RECIPE_DMA_SMOKE",
                    $sformatf("Observed CSR recipe done after %0d poll cycle(s): DONE_STATUS=0x%08h STATE=0x%08h completed=%0d slot_done_mask=0x%08h",
                        cnt,
                        recipe_done_status,
                        recipe_state,
                        completed_count,
                        slot_done_mask),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("CSR_RECIPE_DMA_SMOKE/RECIPE_TIMEOUT",
                    $sformatf("Timed out waiting for CSR recipe done after %0d cycles; status=0x%08h done=0x%08h error=0x%08h reject=0x%08h state=0x%08h current_slot=%0d completed=%0d masks(done/error/reject)=0x%08h/0x%08h/0x%08h",
                        timeout_cycles,
                        recipe_status,
                        recipe_done_status,
                        recipe_error_status,
                        recipe_reject_status,
                        recipe_state,
                        current_slot,
                        completed_count,
                        slot_done_mask,
                        slot_error_mask,
                        slot_reject_mask))
            end
        end
    end
    endtask

    task automatic csr_check_recipe_perf_snapshot(
        input ai_accel_subsys_seq_item profile_item
    );
        logic [31:0] busy_cycles;
        logic [31:0] mac_count;
        logic [31:0] output_count;
        int unsigned expected_macs;
        int unsigned expected_outputs;
    begin
        expected_macs    = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n) * int'(profile_item.dim_k);
        expected_outputs = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_PERF_BUSY_CYCLES, busy_cycles);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_PERF_MAC_COUNT, mac_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_PERF_OUTPUT_COUNT, output_count);

        if (busy_cycles == 32'h0000_0000) begin
            `uvm_fatal("CSR_RECIPE_DMA_SMOKE/PERF_BUSY_ZERO",
                "CSR_RECIPE_PERF_BUSY_CYCLES stayed zero after completed recipe")
        end

        if (mac_count != 32'(expected_macs)) begin
            `uvm_fatal("CSR_RECIPE_DMA_SMOKE/PERF_MAC",
                $sformatf("CSR_RECIPE_PERF_MAC_COUNT mismatch: expected=%0d actual=%0d",
                    expected_macs,
                    mac_count))
        end

        if (output_count != 32'(expected_outputs)) begin
            `uvm_fatal("CSR_RECIPE_DMA_SMOKE/PERF_OUTPUT",
                $sformatf("CSR_RECIPE_PERF_OUTPUT_COUNT mismatch: expected=%0d actual=%0d",
                    expected_outputs,
                    output_count))
        end

        `uvm_info("CSR_RECIPE_DMA_SMOKE",
            $sformatf("CSR recipe perf snapshot PASS: busy_cycles=%0d mac_count=%0d output_count=%0d",
                busy_cycles,
                mac_count,
                output_count),
            UVM_MEDIUM)
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
        int unsigned             c_elems;
        int unsigned             c_bytes;
    begin
        phase.raise_objection(this);

        `uvm_info("CSR_RECIPE_DMA_SMOKE",
            "Starting CSR recipe-level DMA two-slot smoke test",
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

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("CSR_RECIPE_DMA_SMOKE/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(), c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_check_recipe_idle_ready("before START_RECIPE");

        csr_write_recipe_slot(
            0,
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            32'h0000_1600
        );

        csr_write_recipe_slot(
            1,
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            32'h0000_1601
        );

        csr_write_recipe_control();
        csr_start_recipe();
        csr_poll_recipe_done(done_timeout_cycles * 2);
        csr_check_recipe_perf_snapshot(profile_item);

        repeat (5) @(posedge csr_vif.clk);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("CSR_RECIPE_DMA_SMOKE",
            $sformatf("CSR recipe-level DMA two-slot smoke completed: CASE_ID=%0d test_kind=%0d slots=2 A_bytes=%0d B_bytes=%0d C_words=%0d",
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
