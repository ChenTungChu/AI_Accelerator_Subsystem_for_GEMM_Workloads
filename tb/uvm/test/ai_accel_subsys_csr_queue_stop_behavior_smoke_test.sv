// File: tb/uvm/test/ai_accel_subsys_csr_queue_stop_behavior_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_STOP_BEHAVIOR_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_STOP_BEHAVIOR_SMOKE_TEST_SV

// ============================================================
// P20F stop-after-this / STOP_QUEUE behavior smoke
//
// Scope:
//   - Programs two valid SQ command entries and enables
//     RUN_UNTIL_EMPTY.
//   - Case 1 validates CMD_CONTROL.STOP_AFTER_THIS:
//       SQ[0] has STOP_AFTER_THIS=1, SQ[1] is valid.
//       The queue must execute SQ[0], write CQ[0], advance
//       SQ_HEAD/CQ_TAIL to 1, and must not auto-continue to SQ[1].
//   - Case 2 validates CSR_QUEUE_COMMAND.STOP_QUEUE:
//       SQ[0] and SQ[1] are both normal commands.
//       The host writes one START_QUEUE and then STOP_QUEUE.
//       The queue must gracefully finish SQ[0], write CQ[0], advance
//       SQ_HEAD/CQ_TAIL to 1, and must not auto-continue to SQ[1].
//   - Both cases verify that the second CQ slot remains invalid and
//     that the final DMA result from the executed command is correct.
//
// P20F remains single-active-command.  It does not add cancellation,
// preemption, interrupt delivery, multi-outstanding execution, or any
// BRAM / GEMM / DMA / frontend datapath change.
// ============================================================

class ai_accel_subsys_csr_queue_stop_behavior_smoke_test
    extends ai_accel_subsys_csr_queue_completion_wb_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_stop_behavior_smoke_test)

    localparam int unsigned P20F_QUEUE_DEPTH  = 4;
    localparam int unsigned P20F_ENTRY_STRIDE = 32'h0000_0040;
    localparam int unsigned P20F_DESC_STRIDE  = 32'h0000_0080;

    localparam int unsigned P20F_SAT_DESC_BASE0 = 32'h0000_0300;
    localparam int unsigned P20F_SAT_DESC_BASE1 = 32'h0000_0400;
    localparam int unsigned P20F_SAT_SQ_BASE    = 32'h0000_0700;
    localparam int unsigned P20F_SAT_CQ_BASE    = 32'h0000_0800;

    localparam int unsigned P20F_STOP_DESC_BASE0 = 32'h0000_0500;
    localparam int unsigned P20F_STOP_DESC_BASE1 = 32'h0000_0600;
    localparam int unsigned P20F_STOP_SQ_BASE    = 32'h0000_0B00;
    localparam int unsigned P20F_STOP_CQ_BASE    = 32'h0000_0C00;

    // VALID=1, OPCODE=0x01, ENABLE_COMPLETION=1.
    localparam logic [31:0] P20F_CMD_CONTROL_NORMAL = 32'h0000_0103;
    // Same as NORMAL, with bit9 STOP_AFTER_THIS set.
    localparam logic [31:0] P20F_CMD_CONTROL_STOP_AFTER_THIS = 32'h0000_0303;
    localparam logic [31:0] P20F_COMP_FLAGS = 32'h0000_0001;

    localparam logic [31:0] P20F_SAT_CMD0_TAG  = 32'hD20F_0000;
    localparam logic [31:0] P20F_SAT_CMD1_TAG  = 32'hD20F_0001;
    localparam logic [31:0] P20F_SAT_DESC0_TAG0 = 32'hD20F_1000;
    localparam logic [31:0] P20F_SAT_DESC0_TAG1 = 32'hD20F_1001;
    localparam logic [31:0] P20F_SAT_DESC1_TAG0 = 32'hD20F_2000;
    localparam logic [31:0] P20F_SAT_DESC1_TAG1 = 32'hD20F_2001;

    localparam logic [31:0] P20F_STOP_CMD0_TAG  = 32'hD20F_3000;
    localparam logic [31:0] P20F_STOP_CMD1_TAG  = 32'hD20F_3001;
    localparam logic [31:0] P20F_STOP_DESC0_TAG0 = 32'hD20F_4000;
    localparam logic [31:0] P20F_STOP_DESC0_TAG1 = 32'hD20F_4001;
    localparam logic [31:0] P20F_STOP_DESC1_TAG0 = 32'hD20F_5000;
    localparam logic [31:0] P20F_STOP_DESC1_TAG1 = 32'hD20F_5001;

    localparam logic [31:0] P20F_EXP_COMMIT_SUCCESS = 32'h0100_1803;
    localparam logic [31:0] P20F_EXP_STATUS_FLAGS   = 32'h0000_003F;
    localparam logic [31:0] P20F_EXP_COUNTS         = 32'h0002_0202;
    localparam logic [31:0] P20F_EXP_DESC_DONE      = 32'h0000_0003;
    localparam logic [31:0] P20F_EXP_ZERO           = 32'h0000_0000;
    localparam logic [31:0] P20F_EXP_RECIPE_DONE    = 32'h0000_0007;
    localparam logic [31:0] P20F_EXP_SLOT_MASKS     = 32'h0000_0003;

    function new(string name = "ai_accel_subsys_csr_queue_stop_behavior_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p20f_clear_ring_memory(input int unsigned sq_base,
                                          input int unsigned cq_base);
    begin
        for (int unsigned i = 0; i < (P20F_QUEUE_DEPTH * P20F_ENTRY_STRIDE); i++) begin
            p17d_ctrl_vif.dma_src_mem[sq_base + i] = 8'h00;
            p17d_ctrl_vif.dma_dst_mem[cq_base + i] = 8'h00;
        end
    end
    endtask

    task automatic p20f_program_one_sq_command_entry(input int unsigned sq_base,
                                                     input int unsigned sq_slot,
                                                     input logic [31:0] cmd_control,
                                                     input logic [31:0] cmd_tag,
                                                     input int unsigned desc_base);
        int unsigned base;
    begin
        base = sq_base + (sq_slot * P20F_ENTRY_STRIDE);

        write_src_word_le(base + 16'h00, cmd_control);
        write_src_word_le(base + 16'h04, cmd_tag);
        write_src_word_le(base + 16'h08, 32'(desc_base));
        write_src_word_le(base + 16'h0C, 32'h0000_0002);
        write_src_word_le(base + 16'h10, 32'(P20F_DESC_STRIDE));
        write_src_word_le(base + 16'h14, P20F_COMP_FLAGS);
        write_src_word_le(base + 16'h18, 32'h0000_0000);

        for (int unsigned w = 7; w < 16; w++) begin
            write_src_word_le(base + (w * 4), 32'h0000_0000);
        end

        `uvm_info("P20F_QUEUE/SQ",
            $sformatf("Programmed SQ[%0d] command entry at 0x%08h control=0x%08h tag=0x%08h desc_base=0x%08h count=2 stride=0x%08h comp_flags=0x%08h",
                sq_slot,
                base,
                cmd_control,
                cmd_tag,
                desc_base,
                P20F_DESC_STRIDE,
                P20F_COMP_FLAGS),
            UVM_MEDIUM)
    end
    endtask

    task automatic p20f_program_two_sq_entries(input int unsigned sq_base,
                                               input logic [31:0] cmd0_control,
                                               input logic [31:0] cmd0_tag,
                                               input int unsigned desc_base0,
                                               input logic [31:0] cmd1_control,
                                               input logic [31:0] cmd1_tag,
                                               input int unsigned desc_base1);
    begin
        p20f_program_one_sq_command_entry(sq_base, 0, cmd0_control, cmd0_tag, desc_base0);
        p20f_program_one_sq_command_entry(sq_base, 1, cmd1_control, cmd1_tag, desc_base1);
    end
    endtask

    task automatic p20f_program_descriptor_table(input int unsigned desc_base,
                                                 input logic [31:0] first_tag,
                                                 input logic [31:0] second_tag,
                                                 input ai_accel_subsys_seq_item profile_item,
                                                 input int unsigned a_bytes,
                                                 input int unsigned b_bytes,
                                                 input int unsigned c_bytes);
    begin
        program_memory_descriptor(
            desc_base + (0 * P20F_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            first_tag
        );

        program_memory_descriptor(
            desc_base + (1 * P20F_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            second_tag
        );
    end
    endtask

    task automatic p20f_reset_queue_pointers(input string case_name);
        logic [31:0] cmd;
        logic [31:0] sq_head;
        logic [31:0] sq_tail;
        logic [31:0] cq_head;
        logic [31:0] cq_tail;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_RESET_POINTERS] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_COMMAND, cmd);
        repeat (3) @(posedge csr_vif.clk);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL, sq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD, cq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL, cq_tail);

        if ((sq_head != 32'h0000_0000) ||
            (sq_tail != 32'h0000_0000) ||
            (cq_head != 32'h0000_0000) ||
            (cq_tail != 32'h0000_0000)) begin
            `uvm_fatal("P20F_QUEUE/RESET_POINTERS",
                $sformatf("%s RESET_QUEUE_POINTERS failed: SQ_HEAD=0x%08h SQ_TAIL=0x%08h CQ_HEAD=0x%08h CQ_TAIL=0x%08h",
                    case_name,
                    sq_head,
                    sq_tail,
                    cq_head,
                    cq_tail))
        end

        `uvm_info("P20F_QUEUE/RESET_POINTERS",
            $sformatf("%s established legal zero queue counters through RESET_QUEUE_POINTERS", case_name),
            UVM_MEDIUM)
    end
    endtask

    task automatic p20f_csr_program_completion_wb(input int unsigned cq_base);
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_COMPLETION_WB_BASE_ADDR,
            32'(cq_base)
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_COMPLETION_WB_CONTROL,
            32'h0000_0001
        );
    end
    endtask

    task automatic p20f_csr_program_two_entry_queue(input int unsigned sq_base,
                                                    input int unsigned cq_base);
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE,   32'(sq_base));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH,  32'(P20F_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,   32'h0000_0002);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, 32'(P20F_ENTRY_STRIDE));

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE,   32'(cq_base));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH,  32'(P20F_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, 32'(P20F_ENTRY_STRIDE));

        // SQ_HEAD and CQ_TAIL are hardware-owned and remain at the zero value
        // established by p20f_reset_queue_pointers().
        // bit0 QUEUE_ENABLE, bit1 RUN_UNTIL_EMPTY, bit2 STOP_ON_ERROR
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CONTROL, 32'h0000_0007);
    end
    endtask

    task automatic p20f_start_queue_once(input string case_name);
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_START] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_COMMAND, cmd);
        `uvm_info("P20F_QUEUE/START", $sformatf("%s: issued one START_QUEUE", case_name), UVM_MEDIUM)
    end
    endtask

    task automatic p20f_request_stop_queue(input string case_name);
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_STOP] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_COMMAND, cmd);
        `uvm_info("P20F_QUEUE/STOP", $sformatf("%s: issued STOP_QUEUE request", case_name), UVM_MEDIUM)
    end
    endtask

    task automatic p20f_poll_one_command_stopped(input string case_name,
                                                 input logic [31:0] expected_last_tag,
                                                 input int unsigned timeout_cycles);
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
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);

            if ((error_status != 32'h0000_0000) || (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P20F_QUEUE/ERROR",
                    $sformatf("%s failed: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h last_tag=0x%08h",
                        case_name,
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        last_tag))
            end

            if ((sq_head == 32'h0000_0001) &&
                (cq_tail == 32'h0000_0001) &&
                (cq_occ  == 32'h0000_0001) &&
                (last_tag == expected_last_tag)) begin

                repeat (80) @(posedge csr_vif.clk);

                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head);
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL, cq_tail);
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);

                if ((sq_head !== 32'h0000_0001) ||
                    (cq_tail !== 32'h0000_0001) ||
                    (cq_occ  !== 32'h0000_0001) ||
                    (last_tag !== expected_last_tag)) begin
                    `uvm_fatal("P20F_QUEUE/AUTO_CONTINUED",
                        $sformatf("%s should have stopped after one command, but advanced: sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h last_tag=0x%08h expected_tag=0x%08h",
                            case_name,
                            sq_head,
                            cq_tail,
                            cq_occ,
                            last_tag,
                            expected_last_tag))
                end

                `uvm_info("P20F_QUEUE/STOPPED",
                    $sformatf("%s PASS: stopped after one command: status=0x%08h done=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h last_tag=0x%08h",
                        case_name,
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
                `uvm_fatal("P20F_QUEUE/TIMEOUT",
                    $sformatf("%s timed out waiting for graceful stop after one command: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h last_tag=0x%08h",
                        case_name,
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        last_tag))
            end
        end
    end
    endtask

    function automatic logic [31:0] p20f_read_cq_word(input int unsigned cq_base,
                                                      input int unsigned cq_slot,
                                                      input int unsigned byte_offset);
        int unsigned idx;
        logic [31:0] value;
    begin
        idx = cq_base + (cq_slot * P20F_ENTRY_STRIDE) + byte_offset;
        value = 32'h0000_0000;
        value[7:0]   = p17d_ctrl_vif.dma_dst_mem[idx + 0];
        value[15:8]  = p17d_ctrl_vif.dma_dst_mem[idx + 1];
        value[23:16] = p17d_ctrl_vif.dma_dst_mem[idx + 2];
        value[31:24] = p17d_ctrl_vif.dma_dst_mem[idx + 3];
        return value;
    end
    endfunction

    task automatic p20f_expect_cq_word(input int unsigned cq_base,
                                       input int unsigned cq_slot,
                                       input int unsigned byte_offset,
                                       input logic [31:0] expected,
                                       input string name);
        logic [31:0] actual;
    begin
        actual = p20f_read_cq_word(cq_base, cq_slot, byte_offset);
        if (actual !== expected) begin
            `uvm_fatal("P20F_CQ_WB/RECORD_MISMATCH",
                $sformatf("CQ base=0x%08h slot[%0d] %s mismatch at +0x%02x: actual=0x%08h expected=0x%08h",
                    cq_base,
                    cq_slot,
                    name,
                    byte_offset,
                    actual,
                    expected))
        end

        `uvm_info("P20F_CQ_WB/CHECK",
            $sformatf("CQ base=0x%08h slot[%0d] %s PASS at +0x%02x: 0x%08h",
                cq_base,
                cq_slot,
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic p20f_expect_cq_word_nonzero(input int unsigned cq_base,
                                               input int unsigned cq_slot,
                                               input int unsigned byte_offset,
                                               input string name);
        logic [31:0] actual;
    begin
        actual = p20f_read_cq_word(cq_base, cq_slot, byte_offset);
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P20F_CQ_WB/RECORD_ZERO",
                $sformatf("CQ base=0x%08h slot[%0d] %s unexpectedly zero at +0x%02x",
                    cq_base,
                    cq_slot,
                    name,
                    byte_offset))
        end

        `uvm_info("P20F_CQ_WB/CHECK",
            $sformatf("CQ base=0x%08h slot[%0d] %s nonzero PASS at +0x%02x: 0x%08h",
                cq_base,
                cq_slot,
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic p20f_expect_cq_slot_invalid(input int unsigned cq_base,
                                               input int unsigned cq_slot,
                                               input string case_name);
        logic [31:0] commit;
    begin
        commit = p20f_read_cq_word(cq_base, cq_slot, 16'h00);
        if (commit !== 32'h0000_0000) begin
            `uvm_fatal("P20F_CQ_WB/UNTOUCHED_SLOT",
                $sformatf("%s: CQ base=0x%08h slot[%0d] should remain invalid/untouched, but commit word is 0x%08h",
                    case_name,
                    cq_base,
                    cq_slot,
                    commit))
        end

        `uvm_info("P20F_CQ_WB/CHECK",
            $sformatf("%s: CQ base=0x%08h slot[%0d] untouched invalid slot PASS: commit=0x%08h",
                case_name,
                cq_base,
                cq_slot,
                commit),
            UVM_LOW)
    end
    endtask

    task automatic p20f_check_one_cq_record(input int unsigned cq_base,
                                            input int unsigned cq_slot,
                                            input logic [31:0] first_desc_tag,
                                            input logic [31:0] last_desc_tag,
                                            input ai_accel_subsys_seq_item profile_item,
                                            input string case_name);
        int unsigned expected_macs;
        int unsigned expected_outputs;
    begin
        expected_macs    = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n) * int'(profile_item.dim_k);
        expected_outputs = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n);

        p20f_expect_cq_word(cq_base, cq_slot, 16'h00, P20F_EXP_COMMIT_SUCCESS, "word0 commit");
        p20f_expect_cq_word(cq_base, cq_slot, 16'h04, P20F_EXP_STATUS_FLAGS,   "word1 status_flags");
        p20f_expect_cq_word(cq_base, cq_slot, 16'h08, first_desc_tag,           "word2 first_user_tag");
        p20f_expect_cq_word(cq_base, cq_slot, 16'h0C, last_desc_tag,            "word3 last_user_tag");
        p20f_expect_cq_word(cq_base, cq_slot, 16'h10, P20F_EXP_COUNTS,          "word4 counts");
        p20f_expect_cq_word(cq_base, cq_slot, 16'h14, P20F_EXP_DESC_DONE,       "word5 desc_fetch_done_status");
        p20f_expect_cq_word(cq_base, cq_slot, 16'h18, P20F_EXP_ZERO,            "word6 desc_fetch_error_status");
        p20f_expect_cq_word(cq_base, cq_slot, 16'h1C, P20F_EXP_ZERO,            "word7 desc_fetch_reject_status");
        p20f_expect_cq_word(cq_base, cq_slot, 16'h20, P20F_EXP_RECIPE_DONE,     "word8 recipe_done_status");
        p20f_expect_cq_word(cq_base, cq_slot, 16'h24, P20F_EXP_ZERO,            "word9 recipe_error_status");
        p20f_expect_cq_word(cq_base, cq_slot, 16'h28, P20F_EXP_ZERO,            "word10 recipe_reject_status");
        p20f_expect_cq_word(cq_base, cq_slot, 16'h2C, P20F_EXP_SLOT_MASKS,      "word11 slot_mask_summary");
        p20f_expect_cq_word_nonzero(cq_base, cq_slot, 16'h30,                  "word12 perf_busy_cycles");
        p20f_expect_cq_word(cq_base, cq_slot, 16'h34, 32'(expected_macs),       "word13 perf_mac_count");
        p20f_expect_cq_word(cq_base, cq_slot, 16'h38, 32'(expected_outputs),    "word14 perf_output_count");
        p20f_expect_cq_word(cq_base, cq_slot, 16'h3C, P20F_EXP_ZERO,            "word15 error_detail");

        `uvm_info("P20F_CQ_WB/CHECK",
            $sformatf("%s: checked committed CQ base=0x%08h slot[%0d] record",
                case_name,
                cq_base,
                cq_slot),
            UVM_LOW)
    end
    endtask

    task automatic p20f_prepare_descriptors_for_case(input int unsigned desc_base0,
                                                     input logic [31:0] desc0_tag0,
                                                     input logic [31:0] desc0_tag1,
                                                     input int unsigned desc_base1,
                                                     input logic [31:0] desc1_tag0,
                                                     input logic [31:0] desc1_tag1,
                                                     input ai_accel_subsys_seq_item profile_item,
                                                     input int unsigned a_bytes,
                                                     input int unsigned b_bytes,
                                                     input int unsigned c_bytes);
    begin
        p20f_program_descriptor_table(desc_base0, desc0_tag0, desc0_tag1,
                                      profile_item, a_bytes, b_bytes, c_bytes);
        p20f_program_descriptor_table(desc_base1, desc1_tag0, desc1_tag1,
                                      profile_item, a_bytes, b_bytes, c_bytes);
    end
    endtask

    task automatic p20f_case_stop_after_this(input ai_accel_subsys_seq_item profile_item,
                                             input int signed expected_c[]);
        int signed actual_c[];
        int unsigned c_elems;
    begin
        c_elems = c_word_count(profile_item);

        `uvm_info("P20F_CASE/STOP_AFTER_THIS",
            "Starting STOP_AFTER_THIS command-boundary stop case",
            UVM_MEDIUM)

        p20f_clear_ring_memory(P20F_SAT_SQ_BASE, P20F_SAT_CQ_BASE);
        p20f_program_two_sq_entries(
            P20F_SAT_SQ_BASE,
            P20F_CMD_CONTROL_STOP_AFTER_THIS,
            P20F_SAT_CMD0_TAG,
            P20F_SAT_DESC_BASE0,
            P20F_CMD_CONTROL_NORMAL,
            P20F_SAT_CMD1_TAG,
            P20F_SAT_DESC_BASE1
        );

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();

        p20f_reset_queue_pointers("STOP_AFTER_THIS");
        p20f_csr_program_completion_wb(P20F_SAT_CQ_BASE);
        p20f_csr_program_two_entry_queue(P20F_SAT_SQ_BASE, P20F_SAT_CQ_BASE);

        csr_check_recipe_idle_ready("before P20F STOP_AFTER_THIS START");
        p20f_start_queue_once("STOP_AFTER_THIS");
        p20f_poll_one_command_stopped("STOP_AFTER_THIS",
                                      P20F_SAT_CMD0_TAG,
                                      done_timeout_cycles * 4);

        p20f_check_one_cq_record(P20F_SAT_CQ_BASE, 0,
                                 P20F_SAT_DESC0_TAG0,
                                 P20F_SAT_DESC0_TAG1,
                                 profile_item,
                                 "STOP_AFTER_THIS");
        p20f_expect_cq_slot_invalid(P20F_SAT_CQ_BASE, 1, "STOP_AFTER_THIS");

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);
    end
    endtask

    task automatic p20f_case_stop_queue(input ai_accel_subsys_seq_item profile_item,
                                        input int signed expected_c[]);
        int signed actual_c[];
        int unsigned c_elems;
    begin
        c_elems = c_word_count(profile_item);

        `uvm_info("P20F_CASE/STOP_QUEUE",
            "Starting STOP_QUEUE graceful command-boundary stop case",
            UVM_MEDIUM)

        p20f_clear_ring_memory(P20F_STOP_SQ_BASE, P20F_STOP_CQ_BASE);
        p20f_program_two_sq_entries(
            P20F_STOP_SQ_BASE,
            P20F_CMD_CONTROL_NORMAL,
            P20F_STOP_CMD0_TAG,
            P20F_STOP_DESC_BASE0,
            P20F_CMD_CONTROL_NORMAL,
            P20F_STOP_CMD1_TAG,
            P20F_STOP_DESC_BASE1
        );

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();

        p20f_reset_queue_pointers("STOP_QUEUE");
        p20f_csr_program_completion_wb(P20F_STOP_CQ_BASE);
        p20f_csr_program_two_entry_queue(P20F_STOP_SQ_BASE, P20F_STOP_CQ_BASE);

        csr_check_recipe_idle_ready("before P20F STOP_QUEUE START");
        p20f_start_queue_once("STOP_QUEUE");

        // The STOP_QUEUE write is intentionally issued after the start but
        // before the first command is expected to complete.  The controller
        // must not cancel the active command; it should only suppress the
        // next internal auto-continue pulse after the CQ commit.
        repeat (8) @(posedge csr_vif.clk);
        p20f_request_stop_queue("STOP_QUEUE");

        p20f_poll_one_command_stopped("STOP_QUEUE",
                                      P20F_STOP_CMD0_TAG,
                                      done_timeout_cycles * 4);

        p20f_check_one_cq_record(P20F_STOP_CQ_BASE, 0,
                                 P20F_STOP_DESC0_TAG0,
                                 P20F_STOP_DESC0_TAG1,
                                 profile_item,
                                 "STOP_QUEUE");
        p20f_expect_cq_slot_invalid(P20F_STOP_CQ_BASE, 1, "STOP_QUEUE");

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);
    end
    endtask

    task run_phase(uvm_phase phase);
        ai_accel_subsys_seq_item profile_item;
        int signed               a_flat[];
        int signed               b_flat[];
        int signed               expected_c[];
        int unsigned             c_elems;
        int unsigned             c_bytes;
    begin
        phase.raise_objection(this);

        `uvm_info("P20F_QUEUE_STOP_BEHAVIOR/START",
            "Starting P20F stop-after-this / STOP_QUEUE behavior smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P20F_QUEUE_STOP/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        p20f_prepare_descriptors_for_case(
            P20F_SAT_DESC_BASE0,
            P20F_SAT_DESC0_TAG0,
            P20F_SAT_DESC0_TAG1,
            P20F_SAT_DESC_BASE1,
            P20F_SAT_DESC1_TAG0,
            P20F_SAT_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p20f_prepare_descriptors_for_case(
            P20F_STOP_DESC_BASE0,
            P20F_STOP_DESC0_TAG0,
            P20F_STOP_DESC0_TAG1,
            P20F_STOP_DESC_BASE1,
            P20F_STOP_DESC1_TAG0,
            P20F_STOP_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p20f_case_stop_after_this(profile_item, expected_c);
        p20f_case_stop_queue(profile_item, expected_c);

        `uvm_info("P20F_QUEUE_STOP_BEHAVIOR/PASS",
            $sformatf("P20F stop behavior completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d cases=STOP_AFTER_THIS,STOP_QUEUE",
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
