// File: tb/uvm/test/ai_accel_subsys_csr_desc_fetch_dma_completion_wb_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_DESC_FETCH_DMA_COMPLETION_WB_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_DESC_FETCH_DMA_COMPLETION_WB_TEST_SV

// ============================================================
// P18E descriptor-fetch DMA recipe + completion writeback smoke
//
// Scope:
//   - Reuses the existing CSR UVM top and run_uvm.tcl flow.
//   - Reuses the P17D descriptor-fetch DMA two-slot recipe setup.
//   - Enables P18 completion writeback and programs a completion base.
//   - Issues CSR_DESC_FETCH_COMMAND.START_FETCH.
//   - P17 fetches memory-resident descriptors and launches P16 recipe.
//   - P16/P15 executes two DMA recipe slots.
//   - P18E automatically writes one 64-byte completion record after
//     the descriptor-fetch-launched recipe reaches terminal done.
//   - The test checks both final DMA-store result memory and the
//     host-visible completion record.
//
// This test intentionally validates the first end-to-end command /
// completion path without adding a standalone P18 TB or run script.
// ============================================================

class ai_accel_subsys_csr_desc_fetch_dma_completion_wb_test
    extends ai_accel_subsys_csr_desc_fetch_dma_two_slot_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_desc_fetch_dma_completion_wb_test)

    localparam int unsigned P18E_COMP_BASE_ADDR = 32'h0000_0300;
    localparam logic [31:0] P18E_TAG0           = 32'hD18E_0000;
    localparam logic [31:0] P18E_TAG1           = 32'hD18E_0001;

    localparam logic [31:0] EXP_COMMIT_SUCCESS  = 32'h0100_1803;
    localparam logic [31:0] EXP_STATUS_FLAGS    = 32'h0000_003F;
    localparam logic [31:0] EXP_COUNTS          = 32'h0002_0202;
    localparam logic [31:0] EXP_DESC_DONE       = 32'h0000_0003;
    localparam logic [31:0] EXP_ZERO            = 32'h0000_0000;
    localparam logic [31:0] EXP_RECIPE_DONE     = 32'h0000_0007;
    localparam logic [31:0] EXP_SLOT_MASKS      = 32'h0000_0003;

    function new(string name = "ai_accel_subsys_csr_desc_fetch_dma_completion_wb_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function automatic logic [31:0] read_comp_word(input int unsigned byte_offset);
        int unsigned idx;
        logic [31:0] value;
    begin
        idx = P18E_COMP_BASE_ADDR + byte_offset;
        value = 32'h0000_0000;
        value[7:0]   = p17d_ctrl_vif.dma_dst_mem[idx + 0];
        value[15:8]  = p17d_ctrl_vif.dma_dst_mem[idx + 1];
        value[23:16] = p17d_ctrl_vif.dma_dst_mem[idx + 2];
        value[31:24] = p17d_ctrl_vif.dma_dst_mem[idx + 3];
        return value;
    end
    endfunction

    task automatic csr_completion_wb_clear_sticky_status();
        logic [31:0] clear_cmd;
    begin
        clear_cmd = 32'h0000_0000;
        clear_cmd[ai_accel_csr_access_helper::COMP_WB_CMD_CLEAR_DONE]  = 1'b1;
        clear_cmd[ai_accel_csr_access_helper::COMP_WB_CMD_CLEAR_ERROR] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_COMPLETION_WB_COMMAND,
            clear_cmd
        );
    end
    endtask

    task automatic csr_program_completion_wb();
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_COMPLETION_WB_BASE_ADDR,
            32'(P18E_COMP_BASE_ADDR)
        );

        // bit0: enable writeback.  The P18E auto path computes
        // overall_done/error/reject from the terminal descriptor-fetch
        // recipe context; the legacy P18D CSR-trigger path remains
        // available for debug.
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_COMPLETION_WB_CONTROL,
            32'h0000_0001
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_COMPLETION_WB_BASE_ADDR,
            32'(P18E_COMP_BASE_ADDR),
            "CSR_COMPLETION_WB_BASE_ADDR"
        );
    end
    endtask

    task automatic csr_poll_completion_wb_done(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_REJECT_STATUS, reject_status);

            if (error_status != 32'h0000_0000) begin
                `uvm_fatal("P18E_COMP_WB/ERROR_STATUS",
                    $sformatf("Unexpected completion writeback error: status=0x%08h error=0x%08h reject=0x%08h",
                        status,
                        error_status,
                        reject_status))
            end

            if (reject_status != 32'h0000_0000) begin
                `uvm_fatal("P18E_COMP_WB/REJECT_STATUS",
                    $sformatf("Unexpected completion writeback reject: status=0x%08h error=0x%08h reject=0x%08h",
                        status,
                        error_status,
                        reject_status))
            end

            if (done_status[0]) begin
                `uvm_info("P18E_COMP_WB",
                    $sformatf("Completion writeback done after %0d poll(s): status=0x%08h done=0x%08h",
                        cnt,
                        status,
                        done_status),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P18E_COMP_WB/TIMEOUT",
                    $sformatf("Timed out waiting for completion writeback done: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status))
            end
        end
    end
    endtask

    task automatic expect_comp_word(input int unsigned byte_offset,
                                    input logic [31:0] expected,
                                    input string name);
        logic [31:0] actual;
    begin
        actual = read_comp_word(byte_offset);
        if (actual !== expected) begin
            `uvm_fatal("P18E_COMP_WB/RECORD_MISMATCH",
                $sformatf("%s mismatch at +0x%02x: actual=0x%08h expected=0x%08h",
                    name,
                    byte_offset,
                    actual,
                    expected))
        end

        `uvm_info("P18E_COMP_WB/CHECK",
            $sformatf("%s PASS at +0x%02x: 0x%08h",
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic expect_comp_word_nonzero(input int unsigned byte_offset,
                                            input string name);
        logic [31:0] actual;
    begin
        actual = read_comp_word(byte_offset);
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P18E_COMP_WB/RECORD_ZERO",
                $sformatf("%s unexpectedly zero at +0x%02x",
                    name,
                    byte_offset))
        end

        `uvm_info("P18E_COMP_WB/CHECK",
            $sformatf("%s nonzero PASS at +0x%02x: 0x%08h",
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic check_completion_record(input ai_accel_subsys_seq_item profile_item);
        int unsigned expected_macs;
        int unsigned expected_outputs;
    begin
        expected_macs    = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n) * int'(profile_item.dim_k);
        expected_outputs = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n);

        expect_comp_word(16'h00, EXP_COMMIT_SUCCESS, "word0 commit");
        expect_comp_word(16'h04, EXP_STATUS_FLAGS,   "word1 status_flags");
        expect_comp_word(16'h08, P18E_TAG0,          "word2 first_user_tag");
        expect_comp_word(16'h0C, P18E_TAG1,          "word3 last_user_tag");
        expect_comp_word(16'h10, EXP_COUNTS,         "word4 counts");
        expect_comp_word(16'h14, EXP_DESC_DONE,      "word5 desc_fetch_done_status");
        expect_comp_word(16'h18, EXP_ZERO,           "word6 desc_fetch_error_status");
        expect_comp_word(16'h1C, EXP_ZERO,           "word7 desc_fetch_reject_status");
        expect_comp_word(16'h20, EXP_RECIPE_DONE,    "word8 recipe_done_status");
        expect_comp_word(16'h24, EXP_ZERO,           "word9 recipe_error_status");
        expect_comp_word(16'h28, EXP_ZERO,           "word10 recipe_reject_status");
        expect_comp_word(16'h2C, EXP_SLOT_MASKS,     "word11 slot_mask_summary");
        expect_comp_word_nonzero(16'h30,             "word12 perf_busy_cycles");
        expect_comp_word(16'h34, 32'(expected_macs), "word13 perf_mac_count");
        expect_comp_word(16'h38, 32'(expected_outputs), "word14 perf_output_count");
        expect_comp_word(16'h3C, EXP_ZERO,           "word15 error_detail");
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
    begin
        phase.raise_objection(this);

        `uvm_info("P18E_DESC_FETCH_DMA_COMP_WB/START",
            "Starting P18E descriptor-fetch DMA recipe + completion writeback smoke test",
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
            `uvm_fatal("P18E_DESC_FETCH_DMA_COMP_WB/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        // Write descriptors after A/B preparation so the descriptor
        // table is not overwritten by the inherited source-memory setup.
        program_memory_descriptor(
            P17D_DESC_BASE + (0 * P17D_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            P18E_TAG0
        );

        program_memory_descriptor(
            P17D_DESC_BASE + (1 * P17D_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            P18E_TAG1
        );

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_program_completion_wb();

        csr_check_recipe_idle_ready("before descriptor fetch START");

        csr_start_desc_fetch_recipe(P17D_DESC_BASE, 2, P17D_DESC_STRIDE);
        csr_poll_desc_fetch_done(done_timeout_cycles);

        // Existing P17D bridge launches the P16 recipe path from the
        // fetched snapshot.  P18E then observes the terminal recipe
        // done pulse and writes the completion record automatically.
        csr_poll_recipe_done(done_timeout_cycles * 2);
        csr_poll_completion_wb_done(done_timeout_cycles);
        csr_check_recipe_perf_snapshot(profile_item);

        repeat (5) @(posedge csr_vif.clk);

        check_completion_record(profile_item);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P18E_DESC_FETCH_DMA_COMP_WB/PASS",
            $sformatf("P18E descriptor-fetch DMA recipe + completion writeback completed: CASE_ID=%0d test_kind=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
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
