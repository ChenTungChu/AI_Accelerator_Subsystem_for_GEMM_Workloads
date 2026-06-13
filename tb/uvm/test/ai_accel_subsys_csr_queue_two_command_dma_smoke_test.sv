// File: tb/uvm/test/ai_accel_subsys_csr_queue_two_command_dma_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_TWO_COMMAND_DMA_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_TWO_COMMAND_DMA_SMOKE_TEST_SV

// ============================================================
// P20C two-command DMA recipe queue smoke
//
// Scope:
//   - Programs two valid 64-byte SQ command entries.
//   - Enables RUN_UNTIL_EMPTY in CSR_QUEUE_CONTROL.
//   - Issues one host START_QUEUE kick.
//   - Verifies the wrapper drains both commands in order while
//     preserving the existing single-active-command execution model.
//   - Verifies two CQ completion records are committed at CQ[0]
//     and CQ[1].
//   - Verifies SQ_HEAD and CQ_TAIL advance to two, and the queue
//     reaches drained status.
//
// P20C does not add multi-outstanding execution, out-of-order
// completion, interrupts, or any GEMM / DMA / frontend datapath change.
// ============================================================

class ai_accel_subsys_csr_queue_two_command_dma_smoke_test
    extends ai_accel_subsys_csr_queue_completion_wb_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_two_command_dma_smoke_test)

    localparam int unsigned P20C_SQ_BASE      = 32'h0000_0700;
    localparam int unsigned P20C_CQ_BASE      = 32'h0000_0800;
    localparam int unsigned P20C_QUEUE_DEPTH  = 4;
    localparam int unsigned P20C_ENTRY_STRIDE = 32'h0000_0040;

    localparam int unsigned P20C_DESC_BASE0   = 32'h0000_0300;
    localparam int unsigned P20C_DESC_BASE1   = 32'h0000_0400;
    localparam int unsigned P20C_DESC_STRIDE  = 32'h0000_0080;

    // VALID=1, OPCODE=0x01, ENABLE_COMPLETION=1.
    // STOP_AFTER_THIS must remain 0 for the P20C auto-drain smoke.
    localparam logic [31:0] P20C_CMD_CONTROL  = 32'h0000_0103;
    localparam logic [31:0] P20C_CMD0_TAG     = 32'hD20C_0000;
    localparam logic [31:0] P20C_CMD1_TAG     = 32'hD20C_0001;
    localparam logic [31:0] P20C_COMP_FLAGS   = 32'h0000_0001;

    localparam logic [31:0] P20C_DESC0_TAG0   = 32'hD20C_1000;
    localparam logic [31:0] P20C_DESC0_TAG1   = 32'hD20C_1001;
    localparam logic [31:0] P20C_DESC1_TAG0   = 32'hD20C_2000;
    localparam logic [31:0] P20C_DESC1_TAG1   = 32'hD20C_2001;

    localparam logic [31:0] P20C_EXP_COMMIT_SUCCESS = 32'h0100_1803;
    localparam logic [31:0] P20C_EXP_STATUS_FLAGS   = 32'h0000_003F;
    localparam logic [31:0] P20C_EXP_COUNTS         = 32'h0002_0202;
    localparam logic [31:0] P20C_EXP_DESC_DONE      = 32'h0000_0003;
    localparam logic [31:0] P20C_EXP_ZERO           = 32'h0000_0000;
    localparam logic [31:0] P20C_EXP_RECIPE_DONE    = 32'h0000_0007;
    localparam logic [31:0] P20C_EXP_SLOT_MASKS     = 32'h0000_0003;

    function new(string name = "ai_accel_subsys_csr_queue_two_command_dma_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic program_one_sq_command_entry(input int unsigned sq_slot,
                                                input logic [31:0] cmd_tag,
                                                input int unsigned desc_base);
        int unsigned base;
    begin
        base = P20C_SQ_BASE + (sq_slot * P20C_ENTRY_STRIDE);

        write_src_word_le(base + 16'h00, P20C_CMD_CONTROL);
        write_src_word_le(base + 16'h04, cmd_tag);
        write_src_word_le(base + 16'h08, 32'(desc_base));
        write_src_word_le(base + 16'h0C, 32'h0000_0002);
        write_src_word_le(base + 16'h10, 32'(P20C_DESC_STRIDE));
        write_src_word_le(base + 16'h14, P20C_COMP_FLAGS);
        write_src_word_le(base + 16'h18, 32'h0000_0000);

        for (int unsigned w = 7; w < 16; w++) begin
            write_src_word_le(base + (w * 4), 32'h0000_0000);
        end

        `uvm_info("P20C_QUEUE/SQ",
            $sformatf("Programmed SQ[%0d] command entry at 0x%08h control=0x%08h tag=0x%08h desc_base=0x%08h count=2 stride=0x%08h comp_flags=0x%08h",
                sq_slot,
                base,
                P20C_CMD_CONTROL,
                cmd_tag,
                desc_base,
                P20C_DESC_STRIDE,
                P20C_COMP_FLAGS),
            UVM_MEDIUM)
    end
    endtask

    task automatic program_sq_command_entries();
    begin
        program_one_sq_command_entry(0, P20C_CMD0_TAG, P20C_DESC_BASE0);
        program_one_sq_command_entry(1, P20C_CMD1_TAG, P20C_DESC_BASE1);
    end
    endtask

    task automatic program_descriptor_table(input int unsigned desc_base,
                                            input logic [31:0] first_tag,
                                            input logic [31:0] second_tag,
                                            input ai_accel_subsys_seq_item profile_item,
                                            input int unsigned a_bytes,
                                            input int unsigned b_bytes,
                                            input int unsigned c_bytes);
    begin
        program_memory_descriptor(
            desc_base + (0 * P20C_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            first_tag
        );

        program_memory_descriptor(
            desc_base + (1 * P20C_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            second_tag
        );
    end
    endtask

    task automatic clear_p20c_cq_memory();
    begin
        for (int unsigned i = 0; i < (2 * P20C_ENTRY_STRIDE); i++) begin
            p17d_ctrl_vif.dma_dst_mem[P20C_CQ_BASE + i] = 8'h00;
        end
    end
    endtask

    task automatic csr_program_queue();
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE,   32'(P20C_SQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH,  32'(P20C_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,   32'h0000_0002);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, 32'(P20C_ENTRY_STRIDE));

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE,   32'(P20C_CQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH,  32'(P20C_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, 32'(P20C_ENTRY_STRIDE));

        // bit0 QUEUE_ENABLE, bit1 RUN_UNTIL_EMPTY, bit2 STOP_ON_ERROR
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CONTROL, 32'h0000_0007);
    end
    endtask

    task automatic p20c_start_queue_once();
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_START] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_COMMAND,
            cmd
        );

        `uvm_info("P20C_QUEUE/START", "Issued one CSR_QUEUE_COMMAND.START_QUEUE kick", UVM_MEDIUM)
    end
    endtask

    task automatic poll_two_command_queue_drained(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] sq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
        logic [31:0] last_tag;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL, cq_tail);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);

            if ((error_status != 32'h0000_0000) ||
                (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P20C_QUEUE/ERROR",
                    $sformatf("Queue failed during two-command drain: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail))
            end

            if ((sq_head == 32'h0000_0002) &&
                (cq_tail == 32'h0000_0002) &&
                (cq_occ  == 32'h0000_0002) &&
                done_status[1]) begin
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);
                if (last_tag !== P20C_CMD1_TAG) begin
                    `uvm_fatal("P20C_QUEUE/BAD_LAST_TAG",
                        $sformatf("Expected last accepted command tag=0x%08h got=0x%08h",
                            P20C_CMD1_TAG,
                            last_tag))
                end

                `uvm_info("P20C_QUEUE/DRAINED",
                    $sformatf("Two-command auto-drain completed after %0d poll(s): status=0x%08h done=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h last_tag=0x%08h",
                        cnt,
                        status,
                        done_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        last_tag),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P20C_QUEUE/TIMEOUT",
                    $sformatf("Timed out waiting for two-command queue drain: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail,
                        cq_occ))
            end
        end
    end
    endtask

    function automatic logic [31:0] read_p20c_cq_word(input int unsigned cq_slot,
                                                      input int unsigned byte_offset);
        int unsigned idx;
        logic [31:0] value;
    begin
        idx = P20C_CQ_BASE + (cq_slot * P20C_ENTRY_STRIDE) + byte_offset;
        value = 32'h0000_0000;
        value[7:0]   = p17d_ctrl_vif.dma_dst_mem[idx + 0];
        value[15:8]  = p17d_ctrl_vif.dma_dst_mem[idx + 1];
        value[23:16] = p17d_ctrl_vif.dma_dst_mem[idx + 2];
        value[31:24] = p17d_ctrl_vif.dma_dst_mem[idx + 3];
        return value;
    end
    endfunction

    task automatic expect_p20c_cq_word(input int unsigned cq_slot,
                                       input int unsigned byte_offset,
                                       input logic [31:0] expected,
                                       input string name);
        logic [31:0] actual;
    begin
        actual = read_p20c_cq_word(cq_slot, byte_offset);
        if (actual !== expected) begin
            `uvm_fatal("P20C_CQ_WB/RECORD_MISMATCH",
                $sformatf("CQ[%0d] %s mismatch at +0x%02x: actual=0x%08h expected=0x%08h",
                    cq_slot,
                    name,
                    byte_offset,
                    actual,
                    expected))
        end

        `uvm_info("P20C_CQ_WB/CHECK",
            $sformatf("CQ[%0d] %s PASS at +0x%02x: 0x%08h",
                cq_slot,
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic expect_p20c_cq_word_nonzero(input int unsigned cq_slot,
                                               input int unsigned byte_offset,
                                               input string name);
        logic [31:0] actual;
    begin
        actual = read_p20c_cq_word(cq_slot, byte_offset);
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P20C_CQ_WB/RECORD_ZERO",
                $sformatf("CQ[%0d] %s unexpectedly zero at +0x%02x",
                    cq_slot,
                    name,
                    byte_offset))
        end

        `uvm_info("P20C_CQ_WB/CHECK",
            $sformatf("CQ[%0d] %s nonzero PASS at +0x%02x: 0x%08h",
                cq_slot,
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic check_one_p20c_cq_record(input int unsigned cq_slot,
                                            input logic [31:0] first_desc_tag,
                                            input logic [31:0] last_desc_tag,
                                            input ai_accel_subsys_seq_item profile_item);
        int unsigned expected_macs;
        int unsigned expected_outputs;
    begin
        expected_macs    = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n) * int'(profile_item.dim_k);
        expected_outputs = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n);

        expect_p20c_cq_word(cq_slot, 16'h00, P20C_EXP_COMMIT_SUCCESS, "word0 commit");
        expect_p20c_cq_word(cq_slot, 16'h04, P20C_EXP_STATUS_FLAGS,   "word1 status_flags");
        expect_p20c_cq_word(cq_slot, 16'h08, first_desc_tag,     "word2 first_user_tag");
        expect_p20c_cq_word(cq_slot, 16'h0C, last_desc_tag,      "word3 last_user_tag");
        expect_p20c_cq_word(cq_slot, 16'h10, P20C_EXP_COUNTS,         "word4 counts");
        expect_p20c_cq_word(cq_slot, 16'h14, P20C_EXP_DESC_DONE,      "word5 desc_fetch_done_status");
        expect_p20c_cq_word(cq_slot, 16'h18, P20C_EXP_ZERO,           "word6 desc_fetch_error_status");
        expect_p20c_cq_word(cq_slot, 16'h1C, P20C_EXP_ZERO,           "word7 desc_fetch_reject_status");
        expect_p20c_cq_word(cq_slot, 16'h20, P20C_EXP_RECIPE_DONE,    "word8 recipe_done_status");
        expect_p20c_cq_word(cq_slot, 16'h24, P20C_EXP_ZERO,           "word9 recipe_error_status");
        expect_p20c_cq_word(cq_slot, 16'h28, P20C_EXP_ZERO,           "word10 recipe_reject_status");
        expect_p20c_cq_word(cq_slot, 16'h2C, P20C_EXP_SLOT_MASKS,     "word11 slot_mask_summary");
        expect_p20c_cq_word_nonzero(cq_slot, 16'h30,             "word12 perf_busy_cycles");
        expect_p20c_cq_word(cq_slot, 16'h34, 32'(expected_macs), "word13 perf_mac_count");
        expect_p20c_cq_word(cq_slot, 16'h38, 32'(expected_outputs), "word14 perf_output_count");
        expect_p20c_cq_word(cq_slot, 16'h3C, P20C_EXP_ZERO,           "word15 error_detail");
    end
    endtask

    task automatic check_p20c_cq_records(input ai_accel_subsys_seq_item profile_item);
    begin
        check_one_p20c_cq_record(0, P20C_DESC0_TAG0, P20C_DESC0_TAG1, profile_item);
        check_one_p20c_cq_record(1, P20C_DESC1_TAG0, P20C_DESC1_TAG1, profile_item);
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

        `uvm_info("P20C_QUEUE_TWO_CMD_DMA/START",
            "Starting P20C two-command in-order queue drain DMA recipe smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P20C_QUEUE_TWO_CMD_DMA/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);
        clear_p20c_cq_memory();

        program_descriptor_table(
            P20C_DESC_BASE0,
            P20C_DESC0_TAG0,
            P20C_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        program_descriptor_table(
            P20C_DESC_BASE1,
            P20C_DESC1_TAG0,
            P20C_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        program_sq_command_entries();

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();

        csr_program_completion_wb();
        csr_program_queue();

        csr_check_recipe_idle_ready("before P20C queue START");
        p20c_start_queue_once();

        poll_two_command_queue_drained(done_timeout_cycles * 4);

        repeat (5) @(posedge csr_vif.clk);

        check_p20c_cq_records(profile_item);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P20C_QUEUE_TWO_CMD_DMA/PASS",
            $sformatf("P20C two-command queue auto-drain completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d SQ_entries=2 CQ_entries=2",
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
