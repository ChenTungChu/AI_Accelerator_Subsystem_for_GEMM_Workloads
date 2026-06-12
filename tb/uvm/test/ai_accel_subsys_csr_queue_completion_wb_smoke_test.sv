// File: tb/uvm/test/ai_accel_subsys_csr_queue_completion_wb_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_COMPLETION_WB_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_COMPLETION_WB_SMOKE_TEST_SV

// ============================================================
// P19E completion queue writeback integration smoke
//
// Scope:
//   - Reuses the P19D queue command -> P17 descriptor-fetch flow.
//   - Sets CMD_COMPLETION_FLAGS[0] to request P19E CQ writeback.
//   - Verifies the existing P18 completion writeback engine writes the
//     completion record at CQ_BASE + CQ_TAIL * CQ_STRIDE instead of the
//     legacy CSR_COMPLETION_WB_BASE_ADDR.
//   - Verifies CSR SQ_HEAD and CQ_TAIL advance after the completion
//     record commits successfully.
//
// P19E remains single-outstanding.  It does not add interrupts,
// multi-outstanding command execution, or completion queue error
// injection.
// ============================================================

class ai_accel_subsys_csr_queue_completion_wb_smoke_test
    extends ai_accel_subsys_csr_queue_desc_fetch_dma_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_completion_wb_smoke_test)

    localparam int unsigned P19E_SQ_BASE      = 32'h0000_0700;
    localparam int unsigned P19E_CQ_BASE      = 32'h0000_0800;
    localparam int unsigned P19E_QUEUE_DEPTH  = 4;
    localparam int unsigned P19E_ENTRY_STRIDE = 32'h0000_0040;

    localparam logic [31:0] P19E_CMD_CONTROL  = 32'h0000_0303;
    localparam logic [31:0] P19E_CMD_TAG      = 32'hD19E_0000;
    localparam logic [31:0] P19E_COMP_FLAGS   = 32'h0000_0001;

    localparam logic [31:0] EXP_COMMIT_SUCCESS = 32'h0100_1803;
    localparam logic [31:0] EXP_STATUS_FLAGS   = 32'h0000_003F;
    localparam logic [31:0] EXP_COUNTS         = 32'h0002_0202;
    localparam logic [31:0] EXP_DESC_DONE      = 32'h0000_0003;
    localparam logic [31:0] EXP_ZERO           = 32'h0000_0000;
    localparam logic [31:0] EXP_RECIPE_DONE    = 32'h0000_0007;
    localparam logic [31:0] EXP_SLOT_MASKS     = 32'h0000_0003;

    function new(string name = "ai_accel_subsys_csr_queue_completion_wb_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic program_sq_command_entry();
        int unsigned base;
    begin
        base = P19E_SQ_BASE;

        write_src_word_le(base + 16'h00, P19E_CMD_CONTROL);
        write_src_word_le(base + 16'h04, P19E_CMD_TAG);
        write_src_word_le(base + 16'h08, 32'(P17D_DESC_BASE));
        write_src_word_le(base + 16'h0C, 32'h0000_0002);
        write_src_word_le(base + 16'h10, 32'(P17D_DESC_STRIDE));
        write_src_word_le(base + 16'h14, P19E_COMP_FLAGS);
        write_src_word_le(base + 16'h18, 32'h0000_0000);

        for (int unsigned w = 7; w < 16; w++) begin
            write_src_word_le(base + (w * 4), 32'h0000_0000);
        end

        `uvm_info("P19E_QUEUE/SQ",
            $sformatf("Programmed SQ command entry at 0x%08h control=0x%08h tag=0x%08h desc_base=0x%08h count=2 stride=0x%08h comp_flags=0x%08h",
                P19E_SQ_BASE,
                P19E_CMD_CONTROL,
                P19E_CMD_TAG,
                P17D_DESC_BASE,
                P17D_DESC_STRIDE,
                P19E_COMP_FLAGS),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_program_queue();
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE,   32'(P19E_SQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH,  32'(P19E_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,   32'h0000_0001);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, 32'(P19E_ENTRY_STRIDE));

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE,   32'(P19E_CQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH,  32'(P19E_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, 32'(P19E_ENTRY_STRIDE));

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

        `uvm_info("P19E_QUEUE/START", "Issued CSR_QUEUE_COMMAND.START_QUEUE", UVM_MEDIUM)
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
                `uvm_fatal("P19E_QUEUE/ERROR",
                    $sformatf("Queue command failed: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status))
            end

            if (done_status[3]) begin
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);
                if (last_tag !== P19E_CMD_TAG) begin
                    `uvm_fatal("P19E_QUEUE/BAD_TAG",
                        $sformatf("Expected last command tag=0x%08h got=0x%08h", P19E_CMD_TAG, last_tag))
                end

                `uvm_info("P19E_QUEUE/VALIDATED",
                    $sformatf("Queue command fetched/validated after %0d poll(s): status=0x%08h done=0x%08h tag=0x%08h",
                        cnt,
                        status,
                        done_status,
                        last_tag),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P19E_QUEUE/TIMEOUT",
                    $sformatf("Timed out waiting for queue command validated: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status))
            end
        end
    end
    endtask

    function automatic logic [31:0] read_queue_comp_word(input int unsigned byte_offset);
        int unsigned idx;
        logic [31:0] value;
    begin
        idx = P19E_CQ_BASE + byte_offset;
        value = 32'h0000_0000;
        value[7:0]   = p17d_ctrl_vif.dma_dst_mem[idx + 0];
        value[15:8]  = p17d_ctrl_vif.dma_dst_mem[idx + 1];
        value[23:16] = p17d_ctrl_vif.dma_dst_mem[idx + 2];
        value[31:24] = p17d_ctrl_vif.dma_dst_mem[idx + 3];
        return value;
    end
    endfunction

    task automatic expect_queue_comp_word(input int unsigned byte_offset,
                                          input logic [31:0] expected,
                                          input string name);
        logic [31:0] actual;
    begin
        actual = read_queue_comp_word(byte_offset);
        if (actual !== expected) begin
            `uvm_fatal("P19E_CQ_WB/RECORD_MISMATCH",
                $sformatf("%s mismatch at +0x%02x: actual=0x%08h expected=0x%08h",
                    name,
                    byte_offset,
                    actual,
                    expected))
        end

        `uvm_info("P19E_CQ_WB/CHECK",
            $sformatf("%s PASS at +0x%02x: 0x%08h",
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic expect_queue_comp_word_nonzero(input int unsigned byte_offset,
                                                  input string name);
        logic [31:0] actual;
    begin
        actual = read_queue_comp_word(byte_offset);
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P19E_CQ_WB/RECORD_ZERO",
                $sformatf("%s unexpectedly zero at +0x%02x",
                    name,
                    byte_offset))
        end

        `uvm_info("P19E_CQ_WB/CHECK",
            $sformatf("%s nonzero PASS at +0x%02x: 0x%08h",
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic check_queue_completion_record(input ai_accel_subsys_seq_item profile_item);
        int unsigned expected_macs;
        int unsigned expected_outputs;
    begin
        expected_macs    = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n) * int'(profile_item.dim_k);
        expected_outputs = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n);

        expect_queue_comp_word(16'h00, EXP_COMMIT_SUCCESS, "word0 commit");
        expect_queue_comp_word(16'h04, EXP_STATUS_FLAGS,   "word1 status_flags");
        expect_queue_comp_word(16'h08, 32'hD18E_0000,      "word2 first_user_tag");
        expect_queue_comp_word(16'h0C, 32'hD18E_0001,      "word3 last_user_tag");
        expect_queue_comp_word(16'h10, EXP_COUNTS,         "word4 counts");
        expect_queue_comp_word(16'h14, EXP_DESC_DONE,      "word5 desc_fetch_done_status");
        expect_queue_comp_word(16'h18, EXP_ZERO,           "word6 desc_fetch_error_status");
        expect_queue_comp_word(16'h1C, EXP_ZERO,           "word7 desc_fetch_reject_status");
        expect_queue_comp_word(16'h20, EXP_RECIPE_DONE,    "word8 recipe_done_status");
        expect_queue_comp_word(16'h24, EXP_ZERO,           "word9 recipe_error_status");
        expect_queue_comp_word(16'h28, EXP_ZERO,           "word10 recipe_reject_status");
        expect_queue_comp_word(16'h2C, EXP_SLOT_MASKS,     "word11 slot_mask_summary");
        expect_queue_comp_word_nonzero(16'h30,             "word12 perf_busy_cycles");
        expect_queue_comp_word(16'h34, 32'(expected_macs), "word13 perf_mac_count");
        expect_queue_comp_word(16'h38, 32'(expected_outputs), "word14 perf_output_count");
        expect_queue_comp_word(16'h3C, EXP_ZERO,           "word15 error_detail");
    end
    endtask

    task automatic check_queue_pointers_after_completion();
        logic [31:0] sq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL, cq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);

        if (sq_head !== 32'h0000_0001) begin
            `uvm_fatal("P19E_QUEUE/BAD_SQ_HEAD",
                $sformatf("Expected CSR_QUEUE_SQ_HEAD=1 after committed CQ entry, got 0x%08h", sq_head))
        end

        if (cq_tail !== 32'h0000_0001) begin
            `uvm_fatal("P19E_QUEUE/BAD_CQ_TAIL",
                $sformatf("Expected CSR_QUEUE_CQ_TAIL=1 after committed CQ entry, got 0x%08h", cq_tail))
        end

        if (cq_occ !== 32'h0000_0001) begin
            `uvm_fatal("P19E_QUEUE/BAD_CQ_OCC",
                $sformatf("Expected CSR_QUEUE_CQ_OCCUPANCY=1 after committed CQ entry, got 0x%08h", cq_occ))
        end

        `uvm_info("P19E_QUEUE/POINTERS",
            $sformatf("Queue pointers advanced after completion commit: SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h",
                sq_head,
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
    begin
        phase.raise_objection(this);

        `uvm_info("P19E_QUEUE_CQ_WB/START",
            "Starting P19E command queue -> descriptor fetch -> CQ completion writeback smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P19E_QUEUE_CQ_WB/EXPECTED_SIZE",
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

        check_queue_completion_record(profile_item);
        check_queue_pointers_after_completion();

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P19E_QUEUE_CQ_WB/PASS",
            $sformatf("P19E CQ completion writeback completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
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
