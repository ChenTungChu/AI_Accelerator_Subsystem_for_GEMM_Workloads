// File: tb/uvm/test/ai_accel_subsys_csr_queue_desc_fetch_dma_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_DESC_FETCH_DMA_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_DESC_FETCH_DMA_SMOKE_TEST_SV

// ============================================================
// P19D command queue -> P17 descriptor fetch launch smoke
//
// Scope:
//   - Reuses the P18E descriptor-fetch DMA recipe + completion
//     writeback end-to-end setup.
//   - Programs one 64-byte SQ command entry in source memory.
//   - Programs P19 queue CSR base/depth/head/tail/stride.
//   - Issues CSR_QUEUE_COMMAND.START_QUEUE.
//   - P19 queue fetch controller reads and validates the SQ entry.
//   - Accepted queue command launches the existing P17 descriptor
//     fetch path with descriptor base/count/stride from the SQ entry.
//   - Existing P17/P16/P15/P18 path executes the two-slot DMA recipe
//     and writes the completion record through the existing P18 path.
//
// P19D intentionally does not validate CQ-tail advancement or P18
// completion-base redirection into a real CQ.  That is P19E scope.
// ============================================================

class ai_accel_subsys_csr_queue_desc_fetch_dma_smoke_test
    extends ai_accel_subsys_csr_desc_fetch_dma_completion_wb_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_desc_fetch_dma_smoke_test)

    localparam int unsigned P19D_SQ_BASE      = 32'h0000_0700;
    localparam int unsigned P19D_CQ_BASE      = 32'h0000_0800;
    localparam int unsigned P19D_QUEUE_DEPTH  = 4;
    localparam int unsigned P19D_ENTRY_STRIDE = 32'h0000_0040;

    localparam logic [31:0] P19D_CMD_CONTROL  = 32'h0000_0303;
    localparam logic [31:0] P19D_CMD_TAG      = 32'hD19D_0000;

    function new(string name = "ai_accel_subsys_csr_queue_desc_fetch_dma_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic program_sq_command_entry();
        int unsigned base;
    begin
        base = P19D_SQ_BASE;

        write_src_word_le(base + 16'h00, P19D_CMD_CONTROL);
        write_src_word_le(base + 16'h04, P19D_CMD_TAG);
        write_src_word_le(base + 16'h08, 32'(P17D_DESC_BASE));
        write_src_word_le(base + 16'h0C, 32'h0000_0002);
        write_src_word_le(base + 16'h10, 32'(P17D_DESC_STRIDE));
        write_src_word_le(base + 16'h14, 32'h0000_0000);
        write_src_word_le(base + 16'h18, 32'h0000_0000);

        for (int unsigned w = 7; w < 16; w++) begin
            write_src_word_le(base + (w * 4), 32'h0000_0000);
        end

        `uvm_info("P19D_QUEUE/SQ",
            $sformatf("Programmed SQ command entry at 0x%08h control=0x%08h tag=0x%08h desc_base=0x%08h count=2 stride=0x%08h",
                P19D_SQ_BASE,
                P19D_CMD_CONTROL,
                P19D_CMD_TAG,
                P17D_DESC_BASE,
                P17D_DESC_STRIDE),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_queue_clear_sticky_status();
        logic [31:0] clear_cmd;
    begin
        clear_cmd = 32'h0000_0000;
        clear_cmd[ai_accel_csr_access_helper::QUEUE_CMD_CLEAR_DONE]  = 1'b1;
        clear_cmd[ai_accel_csr_access_helper::QUEUE_CMD_CLEAR_ERROR] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_COMMAND,
            clear_cmd
        );
    end
    endtask

    task automatic csr_program_queue();
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE,   32'(P19D_SQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH,  32'(P19D_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,   32'h0000_0001);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, 32'(P19D_ENTRY_STRIDE));

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE,   32'(P19D_CQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH,  32'(P19D_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, 32'(P19D_ENTRY_STRIDE));

        // bit0: queue_enable, bit2: stop_on_error.  run_until_empty
        // stays 0 so this P19D smoke consumes exactly one command.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CONTROL, 32'h0000_0005);
    end
    endtask

    task automatic csr_start_queue();
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_START] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_COMMAND,
            cmd
        );

        `uvm_info("P19D_QUEUE/START", "Issued CSR_QUEUE_COMMAND.START_QUEUE", UVM_MEDIUM)
    end
    endtask

    task automatic csr_poll_queue_validated(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] last_tag;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);

            if ((error_status != 32'h0000_0000) ||
                (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P19D_QUEUE/ERROR",
                    $sformatf("Queue command failed: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status))
            end

            if (done_status[3]) begin
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);
                if (last_tag !== P19D_CMD_TAG) begin
                    `uvm_fatal("P19D_QUEUE/BAD_TAG",
                        $sformatf("Expected last command tag=0x%08h got=0x%08h", P19D_CMD_TAG, last_tag))
                end

                `uvm_info("P19D_QUEUE/VALIDATED",
                    $sformatf("Queue command fetched/validated after %0d poll(s): status=0x%08h done=0x%08h",
                        cnt,
                        status,
                        done_status),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P19D_QUEUE/TIMEOUT",
                    $sformatf("Timed out waiting for queue command validated: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status))
            end
        end
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

        `uvm_info("P19D_QUEUE_DESC_FETCH_DMA/START",
            "Starting P19D queue command -> descriptor fetch DMA recipe smoke test",
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
            `uvm_fatal("P19D_QUEUE_DESC_FETCH_DMA/EXPECTED_SIZE",
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

        program_sq_command_entry();

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();

        csr_program_completion_wb();
        csr_program_queue();

        csr_check_recipe_idle_ready("before queue START");
        csr_start_queue();

        csr_poll_queue_validated(done_timeout_cycles);
        csr_poll_desc_fetch_done(done_timeout_cycles);
        csr_poll_recipe_done(done_timeout_cycles * 2);
        csr_poll_completion_wb_done(done_timeout_cycles);
        csr_check_recipe_perf_snapshot(profile_item);

        repeat (5) @(posedge csr_vif.clk);

        check_completion_record(profile_item);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P19D_QUEUE_DESC_FETCH_DMA/PASS",
            $sformatf("P19D queue command -> descriptor-fetch DMA recipe completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
                selected_case_id,
                a_flat.size(),
                b_flat.size(),
                c_elems),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
