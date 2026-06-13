// File: tb/uvm/test/ai_accel_subsys_csr_queue_wraparound_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_WRAPAROUND_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_WRAPAROUND_SMOKE_TEST_SV

// ============================================================
// P20E SQ/CQ wrap-around representative smoke
//
// Scope:
//   - Programs two valid 64-byte SQ command entries at wrapped
//     physical positions SQ[3] and SQ[0].
//   - Programs monotonic queue pointers so SQ_HEAD=3 and SQ_TAIL=5.
//   - Programs completion pointers so CQ_HEAD=3 and CQ_TAIL=3.
//   - Enables RUN_UNTIL_EMPTY in CSR_QUEUE_CONTROL.
//   - Issues one host START_QUEUE kick.
//   - Verifies the wrapper drains both commands in order while using
//     physical index wrap:
//       SQ counter 3 -> SQ[3] -> execute -> CQ[3]
//       SQ counter 4 -> SQ[0] -> execute -> CQ[0]
//   - Verifies SQ_HEAD and CQ_TAIL advance to 5 and CQ occupancy is 2.
//   - Verifies completion records are committed at CQ[3] and CQ[0].
//   - Verifies non-touched CQ[1] and CQ[2] remain invalid.
//
// P20E does not add multi-outstanding execution, out-of-order
// completion, interrupts, or any BRAM / GEMM / DMA / frontend datapath
// change.  It validates monotonic head/tail counters plus physical ring
// indexing on top of the P20C wrapper-level auto-continue policy.
// ============================================================

class ai_accel_subsys_csr_queue_wraparound_smoke_test
    extends ai_accel_subsys_csr_queue_completion_wb_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_wraparound_smoke_test)

    localparam int unsigned P20E_SQ_BASE      = 32'h0000_0700;
    localparam int unsigned P20E_CQ_BASE      = 32'h0000_0800;
    localparam int unsigned P20E_QUEUE_DEPTH  = 4;
    localparam int unsigned P20E_ENTRY_STRIDE = 32'h0000_0040;

    localparam int unsigned P20E_DESC_BASE0   = 32'h0000_0300;
    localparam int unsigned P20E_DESC_BASE1   = 32'h0000_0400;
    localparam int unsigned P20E_DESC_STRIDE  = 32'h0000_0080;

    localparam int unsigned P20E_START_HEAD   = 3;
    localparam int unsigned P20E_START_TAIL   = 5;
    localparam int unsigned P20E_FINAL_HEAD   = 5;
    localparam int unsigned P20E_FINAL_TAIL   = 5;

    localparam int unsigned P20E_SQ_SLOT0     = 3;
    localparam int unsigned P20E_SQ_SLOT1     = 0;
    localparam int unsigned P20E_CQ_SLOT0     = 3;
    localparam int unsigned P20E_CQ_SLOT1     = 0;

    // VALID=1, OPCODE=0x01, ENABLE_COMPLETION=1.
    // STOP_AFTER_THIS must remain 0 for RUN_UNTIL_EMPTY auto-drain.
    localparam logic [31:0] P20E_CMD_CONTROL  = 32'h0000_0103;
    localparam logic [31:0] P20E_CMD0_TAG     = 32'hD20E_0000;
    localparam logic [31:0] P20E_CMD1_TAG     = 32'hD20E_0001;
    localparam logic [31:0] P20E_COMP_FLAGS   = 32'h0000_0001;

    localparam logic [31:0] P20E_DESC0_TAG0   = 32'hD20E_1000;
    localparam logic [31:0] P20E_DESC0_TAG1   = 32'hD20E_1001;
    localparam logic [31:0] P20E_DESC1_TAG0   = 32'hD20E_2000;
    localparam logic [31:0] P20E_DESC1_TAG1   = 32'hD20E_2001;

    localparam logic [31:0] P20E_EXP_COMMIT_SUCCESS = 32'h0100_1803;
    localparam logic [31:0] P20E_EXP_STATUS_FLAGS   = 32'h0000_003F;
    localparam logic [31:0] P20E_EXP_COUNTS         = 32'h0002_0202;
    localparam logic [31:0] P20E_EXP_DESC_DONE      = 32'h0000_0003;
    localparam logic [31:0] P20E_EXP_ZERO           = 32'h0000_0000;
    localparam logic [31:0] P20E_EXP_RECIPE_DONE    = 32'h0000_0007;
    localparam logic [31:0] P20E_EXP_SLOT_MASKS     = 32'h0000_0003;

    function new(string name = "ai_accel_subsys_csr_queue_wraparound_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p20e_program_one_sq_command_entry(input int unsigned sq_slot,
                                                     input logic [31:0] cmd_tag,
                                                     input int unsigned desc_base);
        int unsigned base;
    begin
        base = P20E_SQ_BASE + (sq_slot * P20E_ENTRY_STRIDE);

        write_src_word_le(base + 16'h00, P20E_CMD_CONTROL);
        write_src_word_le(base + 16'h04, cmd_tag);
        write_src_word_le(base + 16'h08, 32'(desc_base));
        write_src_word_le(base + 16'h0C, 32'h0000_0002);
        write_src_word_le(base + 16'h10, 32'(P20E_DESC_STRIDE));
        write_src_word_le(base + 16'h14, P20E_COMP_FLAGS);
        write_src_word_le(base + 16'h18, 32'h0000_0000);

        for (int unsigned w = 7; w < 16; w++) begin
            write_src_word_le(base + (w * 4), 32'h0000_0000);
        end

        `uvm_info("P20E_QUEUE/SQ",
            $sformatf("Programmed SQ physical slot[%0d] command entry at 0x%08h control=0x%08h tag=0x%08h desc_base=0x%08h count=2 stride=0x%08h comp_flags=0x%08h",
                sq_slot,
                base,
                P20E_CMD_CONTROL,
                cmd_tag,
                desc_base,
                P20E_DESC_STRIDE,
                P20E_COMP_FLAGS),
            UVM_MEDIUM)
    end
    endtask

    task automatic p20e_program_sq_command_entries();
    begin
        // Logical SQ counter 3 maps to physical SQ[3].
        // Logical SQ counter 4 wraps and maps to physical SQ[0].
        p20e_program_one_sq_command_entry(P20E_SQ_SLOT0, P20E_CMD0_TAG, P20E_DESC_BASE0);
        p20e_program_one_sq_command_entry(P20E_SQ_SLOT1, P20E_CMD1_TAG, P20E_DESC_BASE1);
    end
    endtask

    task automatic p20e_program_descriptor_table(input int unsigned desc_base,
                                                 input logic [31:0] first_tag,
                                                 input logic [31:0] second_tag,
                                                 input ai_accel_subsys_seq_item profile_item,
                                                 input int unsigned a_bytes,
                                                 input int unsigned b_bytes,
                                                 input int unsigned c_bytes);
    begin
        program_memory_descriptor(
            desc_base + (0 * P20E_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            first_tag
        );

        program_memory_descriptor(
            desc_base + (1 * P20E_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            second_tag
        );
    end
    endtask

    task automatic p20e_clear_ring_memory();
    begin
        for (int unsigned i = 0; i < (P20E_QUEUE_DEPTH * P20E_ENTRY_STRIDE); i++) begin
            p17d_ctrl_vif.dma_src_mem[P20E_SQ_BASE + i] = 8'h00;
            p17d_ctrl_vif.dma_dst_mem[P20E_CQ_BASE + i] = 8'h00;
        end
    end
    endtask

    task automatic p20e_csr_program_completion_wb();
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_COMPLETION_WB_BASE_ADDR,
            32'(P20E_CQ_BASE)
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_COMPLETION_WB_CONTROL,
            32'h0000_0001
        );
    end
    endtask

    task automatic p20e_csr_program_wrapped_queue();
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE,   32'(P20E_SQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH,  32'(P20E_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,   32'(P20E_START_HEAD));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,   32'(P20E_START_TAIL));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, 32'(P20E_ENTRY_STRIDE));

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE,   32'(P20E_CQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH,  32'(P20E_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,   32'(P20E_START_HEAD));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,   32'(P20E_START_HEAD));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, 32'(P20E_ENTRY_STRIDE));

        // bit0 QUEUE_ENABLE, bit1 RUN_UNTIL_EMPTY, bit2 STOP_ON_ERROR
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CONTROL, 32'h0000_0007);

        `uvm_info("P20E_QUEUE/CFG",
            $sformatf("Programmed wrapped queue: SQ_HEAD=%0d SQ_TAIL=%0d CQ_HEAD=%0d CQ_TAIL=%0d depth=%0d; expected SQ slots=%0d,%0d CQ slots=%0d,%0d",
                P20E_START_HEAD,
                P20E_START_TAIL,
                P20E_START_HEAD,
                P20E_START_HEAD,
                P20E_QUEUE_DEPTH,
                P20E_SQ_SLOT0,
                P20E_SQ_SLOT1,
                P20E_CQ_SLOT0,
                P20E_CQ_SLOT1),
            UVM_MEDIUM)
    end
    endtask

    task automatic p20e_start_queue_once();
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_START] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_COMMAND,
            cmd
        );

        `uvm_info("P20E_QUEUE/START", "Issued one CSR_QUEUE_COMMAND.START_QUEUE kick for wrap-around run", UVM_MEDIUM)
    end
    endtask

    task automatic p20e_poll_wrapped_queue_drained(input int unsigned timeout_cycles);
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
                `uvm_fatal("P20E_QUEUE/ERROR",
                    $sformatf("Queue failed during wrap-around drain: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail))
            end

            if ((sq_head == 32'(P20E_FINAL_HEAD)) &&
                (cq_tail == 32'(P20E_FINAL_TAIL)) &&
                (cq_occ  == 32'h0000_0002) &&
                done_status[1]) begin
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);
                if (last_tag !== P20E_CMD1_TAG) begin
                    `uvm_fatal("P20E_QUEUE/BAD_LAST_TAG",
                        $sformatf("Expected last accepted command tag=0x%08h got=0x%08h",
                            P20E_CMD1_TAG,
                            last_tag))
                end

                `uvm_info("P20E_QUEUE/DRAINED",
                    $sformatf("Wrapped two-command auto-drain completed after %0d poll(s): status=0x%08h done=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h last_tag=0x%08h",
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
                `uvm_fatal("P20E_QUEUE/TIMEOUT",
                    $sformatf("Timed out waiting for wrapped queue drain: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h",
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

    function automatic logic [31:0] p20e_read_cq_word(input int unsigned cq_slot,
                                                      input int unsigned byte_offset);
        int unsigned idx;
        logic [31:0] value;
    begin
        idx = P20E_CQ_BASE + (cq_slot * P20E_ENTRY_STRIDE) + byte_offset;
        value = 32'h0000_0000;
        value[7:0]   = p17d_ctrl_vif.dma_dst_mem[idx + 0];
        value[15:8]  = p17d_ctrl_vif.dma_dst_mem[idx + 1];
        value[23:16] = p17d_ctrl_vif.dma_dst_mem[idx + 2];
        value[31:24] = p17d_ctrl_vif.dma_dst_mem[idx + 3];
        return value;
    end
    endfunction

    task automatic p20e_expect_cq_word(input int unsigned cq_slot,
                                       input int unsigned byte_offset,
                                       input logic [31:0] expected,
                                       input string name);
        logic [31:0] actual;
    begin
        actual = p20e_read_cq_word(cq_slot, byte_offset);
        if (actual !== expected) begin
            `uvm_fatal("P20E_CQ_WB/RECORD_MISMATCH",
                $sformatf("CQ[%0d] %s mismatch at +0x%02x: actual=0x%08h expected=0x%08h",
                    cq_slot,
                    name,
                    byte_offset,
                    actual,
                    expected))
        end

        `uvm_info("P20E_CQ_WB/CHECK",
            $sformatf("CQ[%0d] %s PASS at +0x%02x: 0x%08h",
                cq_slot,
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic p20e_expect_cq_word_nonzero(input int unsigned cq_slot,
                                               input int unsigned byte_offset,
                                               input string name);
        logic [31:0] actual;
    begin
        actual = p20e_read_cq_word(cq_slot, byte_offset);
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P20E_CQ_WB/RECORD_ZERO",
                $sformatf("CQ[%0d] %s unexpectedly zero at +0x%02x",
                    cq_slot,
                    name,
                    byte_offset))
        end

        `uvm_info("P20E_CQ_WB/CHECK",
            $sformatf("CQ[%0d] %s nonzero PASS at +0x%02x: 0x%08h",
                cq_slot,
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic p20e_expect_cq_slot_invalid(input int unsigned cq_slot);
        logic [31:0] commit;
    begin
        commit = p20e_read_cq_word(cq_slot, 16'h00);
        if (commit !== 32'h0000_0000) begin
            `uvm_fatal("P20E_CQ_WB/UNTOUCHED_SLOT",
                $sformatf("CQ[%0d] should remain invalid/untouched, but commit word is 0x%08h",
                    cq_slot,
                    commit))
        end

        `uvm_info("P20E_CQ_WB/CHECK",
            $sformatf("CQ[%0d] untouched invalid slot PASS: commit=0x%08h",
                cq_slot,
                commit),
            UVM_LOW)
    end
    endtask

    task automatic p20e_check_one_cq_record(input int unsigned cq_slot,
                                            input logic [31:0] first_desc_tag,
                                            input logic [31:0] last_desc_tag,
                                            input ai_accel_subsys_seq_item profile_item);
        int unsigned expected_macs;
        int unsigned expected_outputs;
    begin
        expected_macs    = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n) * int'(profile_item.dim_k);
        expected_outputs = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n);

        p20e_expect_cq_word(cq_slot, 16'h00, P20E_EXP_COMMIT_SUCCESS, "word0 commit");
        p20e_expect_cq_word(cq_slot, 16'h04, P20E_EXP_STATUS_FLAGS,   "word1 status_flags");
        p20e_expect_cq_word(cq_slot, 16'h08, first_desc_tag,           "word2 first_user_tag");
        p20e_expect_cq_word(cq_slot, 16'h0C, last_desc_tag,            "word3 last_user_tag");
        p20e_expect_cq_word(cq_slot, 16'h10, P20E_EXP_COUNTS,          "word4 counts");
        p20e_expect_cq_word(cq_slot, 16'h14, P20E_EXP_DESC_DONE,       "word5 desc_fetch_done_status");
        p20e_expect_cq_word(cq_slot, 16'h18, P20E_EXP_ZERO,            "word6 desc_fetch_error_status");
        p20e_expect_cq_word(cq_slot, 16'h1C, P20E_EXP_ZERO,            "word7 desc_fetch_reject_status");
        p20e_expect_cq_word(cq_slot, 16'h20, P20E_EXP_RECIPE_DONE,     "word8 recipe_done_status");
        p20e_expect_cq_word(cq_slot, 16'h24, P20E_EXP_ZERO,            "word9 recipe_error_status");
        p20e_expect_cq_word(cq_slot, 16'h28, P20E_EXP_ZERO,            "word10 recipe_reject_status");
        p20e_expect_cq_word(cq_slot, 16'h2C, P20E_EXP_SLOT_MASKS,      "word11 slot_mask_summary");
        p20e_expect_cq_word_nonzero(cq_slot, 16'h30,                  "word12 perf_busy_cycles");
        p20e_expect_cq_word(cq_slot, 16'h34, 32'(expected_macs),       "word13 perf_mac_count");
        p20e_expect_cq_word(cq_slot, 16'h38, 32'(expected_outputs),    "word14 perf_output_count");
        p20e_expect_cq_word(cq_slot, 16'h3C, P20E_EXP_ZERO,            "word15 error_detail");
    end
    endtask

    task automatic p20e_check_wrapped_cq_records(input ai_accel_subsys_seq_item profile_item);
    begin
        // Logical completion counter 3 maps to physical CQ[3].
        // Logical completion counter 4 wraps and maps to physical CQ[0].
        p20e_check_one_cq_record(P20E_CQ_SLOT0, P20E_DESC0_TAG0, P20E_DESC0_TAG1, profile_item);
        p20e_check_one_cq_record(P20E_CQ_SLOT1, P20E_DESC1_TAG0, P20E_DESC1_TAG1, profile_item);

        p20e_expect_cq_slot_invalid(1);
        p20e_expect_cq_slot_invalid(2);
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

        `uvm_info("P20E_QUEUE_WRAPAROUND/START",
            "Starting P20E SQ/CQ wrap-around representative queue drain smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P20E_QUEUE_WRAP/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);
        p20e_clear_ring_memory();

        p20e_program_descriptor_table(
            P20E_DESC_BASE0,
            P20E_DESC0_TAG0,
            P20E_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p20e_program_descriptor_table(
            P20E_DESC_BASE1,
            P20E_DESC1_TAG0,
            P20E_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p20e_program_sq_command_entries();

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();

        p20e_csr_program_completion_wb();
        p20e_csr_program_wrapped_queue();

        csr_check_recipe_idle_ready("before P20E wrapped queue START");
        p20e_start_queue_once();

        p20e_poll_wrapped_queue_drained(done_timeout_cycles * 4);

        repeat (5) @(posedge csr_vif.clk);

        p20e_check_wrapped_cq_records(profile_item);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P20E_QUEUE_WRAPAROUND/PASS",
            $sformatf("P20E wrapped queue auto-drain completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d SQ_HEAD=%0d->%0d CQ_TAIL=%0d->%0d touched_CQ_slots=%0d,%0d",
                selected_case_id,
                a_flat.size(),
                b_flat.size(),
                c_elems,
                P20E_START_HEAD,
                P20E_FINAL_HEAD,
                P20E_START_HEAD,
                P20E_FINAL_TAIL,
                P20E_CQ_SLOT0,
                P20E_CQ_SLOT1),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
