// File: tb/uvm/test/ai_accel_subsys_csr_queue_cq_full_live_recovery_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_CQ_FULL_LIVE_RECOVERY_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_CQ_FULL_LIVE_RECOVERY_SMOKE_TEST_SV

// ============================================================
// P21E CQ-full stall + host CQ_HEAD recovery during live service
//
// Scope:
//   - Publishes one DMA descriptor-recipe SQ command before START_QUEUE.
//   - Issues one START_QUEUE kick with RUN_UNTIL_EMPTY=1 and CQ_DEPTH=1.
//   - While SQ[0] is active, the host appends SQ[1] and updates
//     CSR_SQ_TAIL from 1 to 2.
//   - After SQ[0] commits CQ[0], the CQ becomes full.  The queue must
//     stall at the command boundary without consuming SQ[1].
//   - The host consumes CQ[0] by advancing CSR_CQ_HEAD from 0 to 1 while
//     the queue service session is still active.
//   - The queue then resumes without a second START_QUEUE kick, consumes
//     SQ[1], writes the next completion into the reused physical CQ[0]
//     slot, and drains cleanly.
//
// P21E does not add multi-outstanding execution, out-of-order completion,
// interrupts, or any BRAM / GEMM / DMA / frontend datapath change.  It
// validates live CQ_HEAD recovery and command-boundary CQ backpressure on
// top of the P20/P21 single-active-command queue service path.
// ============================================================

class ai_accel_subsys_csr_queue_cq_full_live_recovery_smoke_test
    extends ai_accel_subsys_csr_queue_runtime_doorbell_dma_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_cq_full_live_recovery_smoke_test)

    localparam int unsigned P21E_SQ_BASE       = 32'h0000_0F00;
    localparam int unsigned P21E_CQ_BASE       = 32'h0000_0E00;
    localparam int unsigned P21E_SQ_DEPTH      = 4;
    localparam int unsigned P21E_CQ_DEPTH      = 1;
    localparam int unsigned P21E_ENTRY_STRIDE  = 32'h0000_0040;

    localparam int unsigned P21E_DESC_BASE0    = 32'h0000_0300;
    localparam int unsigned P21E_DESC_BASE1    = 32'h0000_0400;
    localparam int unsigned P21E_DESC_STRIDE   = 32'h0000_0080;

    // VALID=1, OPCODE=0x01, ENABLE_COMPLETION=1.
    // STOP_AFTER_THIS is intentionally 0.  CQ full is the only expected
    // command-boundary stop/stall condition before host CQ_HEAD recovery.
    localparam logic [31:0] P21E_CMD_CONTROL   = 32'h0000_0103;
    localparam logic [31:0] P21E_CMD0_TAG      = 32'hD21E_0000;
    localparam logic [31:0] P21E_CMD1_TAG      = 32'hD21E_0001;
    localparam logic [31:0] P21E_COMP_FLAGS    = 32'h0000_0001;

    localparam logic [31:0] P21E_DESC0_TAG0    = 32'hD21E_1000;
    localparam logic [31:0] P21E_DESC0_TAG1    = 32'hD21E_1001;
    localparam logic [31:0] P21E_DESC1_TAG0    = 32'hD21E_2000;
    localparam logic [31:0] P21E_DESC1_TAG1    = 32'hD21E_2001;

    localparam logic [31:0] P21E_EXP_COMMIT_SUCCESS = 32'h0100_1803;
    localparam logic [31:0] P21E_EXP_STATUS_FLAGS   = 32'h0000_003F;
    localparam logic [31:0] P21E_EXP_COUNTS         = 32'h0002_0202;
    localparam logic [31:0] P21E_EXP_DESC_DONE      = 32'h0000_0003;
    localparam logic [31:0] P21E_EXP_ZERO           = 32'h0000_0000;
    localparam logic [31:0] P21E_EXP_RECIPE_DONE    = 32'h0000_0007;
    localparam logic [31:0] P21E_EXP_SLOT_MASKS     = 32'h0000_0003;

    function new(string name = "ai_accel_subsys_csr_queue_cq_full_live_recovery_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p21e_program_one_sq_command_entry(input int unsigned sq_slot,
                                                     input logic [31:0] cmd_tag,
                                                     input int unsigned desc_base);
        int unsigned base;
    begin
        base = P21E_SQ_BASE + (sq_slot * P21E_ENTRY_STRIDE);

        // Payload words first; command commit/control word last.
        write_src_word_le(base + 16'h04, cmd_tag);
        write_src_word_le(base + 16'h08, 32'(desc_base));
        write_src_word_le(base + 16'h0C, 32'h0000_0002);
        write_src_word_le(base + 16'h10, 32'(P21E_DESC_STRIDE));
        write_src_word_le(base + 16'h14, P21E_COMP_FLAGS);
        write_src_word_le(base + 16'h18, 32'h0000_0000);

        for (int unsigned w = 7; w < 16; w++) begin
            write_src_word_le(base + (w * 4), 32'h0000_0000);
        end

        write_src_word_le(base + 16'h00, P21E_CMD_CONTROL);

        `uvm_info("P21E_QUEUE/SQ",
            $sformatf("Programmed SQ[%0d] command entry at 0x%08h control=0x%08h tag=0x%08h desc_base=0x%08h count=2 stride=0x%08h comp_flags=0x%08h",
                sq_slot,
                base,
                P21E_CMD_CONTROL,
                cmd_tag,
                desc_base,
                P21E_DESC_STRIDE,
                P21E_COMP_FLAGS),
            UVM_MEDIUM)
    end
    endtask

    task automatic p21e_program_descriptor_table(input int unsigned desc_base,
                                                 input logic [31:0] first_tag,
                                                 input logic [31:0] second_tag,
                                                 input ai_accel_subsys_seq_item profile_item,
                                                 input int unsigned a_bytes,
                                                 input int unsigned b_bytes,
                                                 input int unsigned c_bytes);
    begin
        program_memory_descriptor(
            desc_base + (0 * P21E_DESC_STRIDE),
            32'h0000_0003,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            first_tag
        );

        program_memory_descriptor(
            desc_base + (1 * P21E_DESC_STRIDE),
            32'h0000_000B,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            second_tag
        );
    end
    endtask

    task automatic p21e_clear_cq_memory();
    begin
        for (int unsigned i = 0; i < P21E_ENTRY_STRIDE; i++) begin
            p17d_ctrl_vif.dma_dst_mem[P21E_CQ_BASE + i] = 8'h00;
        end
    end
    endtask

    task automatic p21e_csr_program_queue_initial_one_visible_cq_depth1();
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE,   32'(P21E_SQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH,  32'(P21E_SQ_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,   32'h0000_0001);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, 32'(P21E_ENTRY_STRIDE));

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE,   32'(P21E_CQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH,  32'(P21E_CQ_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, 32'(P21E_ENTRY_STRIDE));

        // bit0 QUEUE_ENABLE, bit1 RUN_UNTIL_EMPTY, bit2 STOP_ON_ERROR.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CONTROL, 32'h0000_0007);

        `uvm_info("P21E_QUEUE/CFG",
            "Programmed live-service queue with SQ_HEAD=0 SQ_TAIL=1 CQ_HEAD=0 CQ_TAIL=0 CQ_DEPTH=1",
            UVM_MEDIUM)
    end
    endtask

    task automatic p21e_start_queue_once();
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_START] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_COMMAND,
            cmd
        );

        `uvm_info("P21E_QUEUE/START", "Issued one CSR_QUEUE_COMMAND.START_QUEUE kick with only SQ[0] visible and CQ_DEPTH=1", UVM_MEDIUM)
    end
    endtask

    task automatic p21e_wait_for_queue_active_before_doorbell(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] sq_head;
        logic [31:0] cq_tail;
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

            if ((error_status != 32'h0000_0000) ||
                (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P21E_QUEUE/ERROR_BEFORE_DOORBELL",
                    $sformatf("Queue failed before CQ-full recovery doorbell: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail))
            end

            if (status[0] && (sq_head == 32'h0000_0000) && (cq_tail == 32'h0000_0000)) begin
                `uvm_info("P21E_QUEUE/ACTIVE",
                    $sformatf("Queue is active before SQ runtime append: status=0x%08h done=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h",
                        status,
                        done_status,
                        sq_head,
                        cq_tail),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P21E_QUEUE/ACTIVE_TIMEOUT",
                    $sformatf("Timed out waiting for queue active before SQ runtime append: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail))
            end
        end
    end
    endtask

    task automatic p21e_append_sq1_while_active();
        logic [31:0] status_before;
        logic [31:0] sq_tail_after;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status_before);
        if (!status_before[0]) begin
            `uvm_fatal("P21E_QUEUE/NOT_BUSY_AT_APPEND",
                $sformatf("Expected queue_busy=1 before SQ runtime append, status=0x%08h",
                    status_before))
        end

        p21e_program_one_sq_command_entry(1, P21E_CMD1_TAG, P21E_DESC_BASE1);

        // Runtime doorbell: host-owned SQ_TAIL moves while queue_busy=1.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL, 32'h0000_0002);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL, sq_tail_after);

        if (sq_tail_after !== 32'h0000_0002) begin
            `uvm_fatal("P21E_QUEUE/SQ_TAIL_DOORBELL_FAIL",
                $sformatf("Expected SQ_TAIL=2 after runtime append, got 0x%08h", sq_tail_after))
        end

        `uvm_info("P21E_QUEUE/SQ_DOORBELL",
            $sformatf("Runtime SQ doorbell issued while queue_busy=1: wrote SQ[1], updated SQ_TAIL 1->2, status_before=0x%08h",
                status_before),
            UVM_MEDIUM)
    end
    endtask

    function automatic logic [31:0] p21e_read_cq_word(input int unsigned byte_offset);
        int unsigned idx;
        logic [31:0] value;
    begin
        idx = P21E_CQ_BASE + byte_offset;
        value = 32'h0000_0000;
        value[7:0]   = p17d_ctrl_vif.dma_dst_mem[idx + 0];
        value[15:8]  = p17d_ctrl_vif.dma_dst_mem[idx + 1];
        value[23:16] = p17d_ctrl_vif.dma_dst_mem[idx + 2];
        value[31:24] = p17d_ctrl_vif.dma_dst_mem[idx + 3];
        return value;
    end
    endfunction

    task automatic p21e_expect_cq_word(input int unsigned byte_offset,
                                       input logic [31:0] expected,
                                       input string name);
        logic [31:0] actual;
    begin
        actual = p21e_read_cq_word(byte_offset);
        if (actual !== expected) begin
            `uvm_fatal("P21E_CQ_WB/RECORD_MISMATCH",
                $sformatf("CQ[0] %s mismatch at +0x%02x: actual=0x%08h expected=0x%08h",
                    name,
                    byte_offset,
                    actual,
                    expected))
        end

        `uvm_info("P21E_CQ_WB/CHECK",
            $sformatf("CQ[0] %s PASS at +0x%02x: 0x%08h",
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic p21e_expect_cq_word_nonzero(input int unsigned byte_offset,
                                               input string name);
        logic [31:0] actual;
    begin
        actual = p21e_read_cq_word(byte_offset);
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P21E_CQ_WB/RECORD_ZERO",
                $sformatf("CQ[0] %s unexpectedly zero at +0x%02x",
                    name,
                    byte_offset))
        end

        `uvm_info("P21E_CQ_WB/CHECK",
            $sformatf("CQ[0] %s nonzero PASS at +0x%02x: 0x%08h",
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic p21e_check_physical_cq0_record(input string case_name,
                                                  input logic [31:0] first_desc_tag,
                                                  input logic [31:0] last_desc_tag,
                                                  input ai_accel_subsys_seq_item profile_item);
        int unsigned expected_macs;
        int unsigned expected_outputs;
    begin
        expected_macs    = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n) * int'(profile_item.dim_k);
        expected_outputs = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n);

        p21e_expect_cq_word(16'h00, P21E_EXP_COMMIT_SUCCESS, "word0 commit");
        p21e_expect_cq_word(16'h04, P21E_EXP_STATUS_FLAGS,   "word1 status_flags");
        p21e_expect_cq_word(16'h08, first_desc_tag,           "word2 first_user_tag");
        p21e_expect_cq_word(16'h0C, last_desc_tag,            "word3 last_user_tag");
        p21e_expect_cq_word(16'h10, P21E_EXP_COUNTS,          "word4 counts");
        p21e_expect_cq_word(16'h14, P21E_EXP_DESC_DONE,       "word5 desc_fetch_done_status");
        p21e_expect_cq_word(16'h18, P21E_EXP_ZERO,            "word6 desc_fetch_error_status");
        p21e_expect_cq_word(16'h1C, P21E_EXP_ZERO,            "word7 desc_fetch_reject_status");
        p21e_expect_cq_word(16'h20, P21E_EXP_RECIPE_DONE,     "word8 recipe_done_status");
        p21e_expect_cq_word(16'h24, P21E_EXP_ZERO,            "word9 recipe_error_status");
        p21e_expect_cq_word(16'h28, P21E_EXP_ZERO,            "word10 recipe_reject_status");
        p21e_expect_cq_word(16'h2C, P21E_EXP_SLOT_MASKS,      "word11 slot_mask_summary");
        p21e_expect_cq_word_nonzero(16'h30,                  "word12 perf_busy_cycles");
        p21e_expect_cq_word(16'h34, 32'(expected_macs),       "word13 perf_mac_count");
        p21e_expect_cq_word(16'h38, 32'(expected_outputs),    "word14 perf_output_count");
        p21e_expect_cq_word(16'h3C, P21E_EXP_ZERO,            "word15 error_detail");

        `uvm_info("P21E_CQ_WB/CHECK",
            $sformatf("%s: checked physical CQ[0] record first_tag=0x%08h last_tag=0x%08h",
                case_name,
                first_desc_tag,
                last_desc_tag),
            UVM_MEDIUM)
    end
    endtask

    task automatic p21e_wait_cq_full_after_first_completion(input ai_accel_subsys_seq_item profile_item,
                                                            input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] sq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
        logic [31:0] cq_space;
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
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_SPACE, cq_space);

            if ((error_status != 32'h0000_0000) ||
                (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P21E_QUEUE/CQ_FULL_ERROR",
                    $sformatf("CQ full should stall, not error/reject: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h cq_space=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        cq_space))
            end

            if ((sq_head == 32'h0000_0001) &&
                (cq_tail == 32'h0000_0001) &&
                (cq_occ  == 32'h0000_0001) &&
                (cq_space == 32'h0000_0000)) begin
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);
                if (last_tag !== P21E_CMD0_TAG) begin
                    `uvm_fatal("P21E_QUEUE/BAD_STALL_LAST_TAG",
                        $sformatf("Expected last accepted command tag to remain SQ[0]=0x%08h during CQ full stall, got=0x%08h",
                            P21E_CMD0_TAG,
                            last_tag))
                end

                if (!status[0]) begin
                    `uvm_fatal("P21E_QUEUE/NOT_BUSY_ON_CQ_FULL",
                        $sformatf("Expected queue_busy=1 while stalled on CQ full with SQ[1] pending: status=0x%08h done=0x%08h",
                            status,
                            done_status))
                end

                `uvm_info("P21E_QUEUE/CQ_FULL_STALL",
                    $sformatf("CQ full command-boundary stall observed after first completion: status=0x%08h done=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h CQ_SPACE=0x%08h last_tag=0x%08h",
                        status,
                        done_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        cq_space,
                        last_tag),
                    UVM_MEDIUM)

                p21e_check_physical_cq0_record("before CQ_HEAD recovery / first completion",
                                               P21E_DESC0_TAG0,
                                               P21E_DESC0_TAG1,
                                               profile_item);
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P21E_QUEUE/CQ_FULL_TIMEOUT",
                    $sformatf("Timed out waiting for CQ full stall after first completion: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h cq_space=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        cq_space))
            end
        end
    end
    endtask

    task automatic p21e_advance_cq_head_while_stalled();
        logic [31:0] status_before;
        logic [31:0] cq_head_after;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status_before);
        if (!status_before[0]) begin
            `uvm_fatal("P21E_QUEUE/NOT_BUSY_AT_CQ_HEAD",
                $sformatf("Expected queue_busy=1 before CQ_HEAD recovery update, status=0x%08h",
                    status_before))
        end

        // Host consumes CQ[0] and advances the host-owned CQ_HEAD while the
        // same queue service session remains active/stalled.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD, 32'h0000_0001);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD, cq_head_after);

        if (cq_head_after !== 32'h0000_0001) begin
            `uvm_fatal("P21E_QUEUE/CQ_HEAD_RECOVERY_FAIL",
                $sformatf("Expected CQ_HEAD=1 after host recovery update, got 0x%08h", cq_head_after))
        end

        `uvm_info("P21E_QUEUE/CQ_HEAD_RECOVER",
            $sformatf("Host advanced CQ_HEAD 0->1 while queue was stalled on CQ full, status_before=0x%08h",
                status_before),
            UVM_MEDIUM)
    end
    endtask

    task automatic p21e_poll_final_drained_after_recovery(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] sq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
        logic [31:0] cq_space;
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
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_SPACE, cq_space);

            if ((error_status != 32'h0000_0000) ||
                (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P21E_QUEUE/ERROR_AFTER_CQ_HEAD",
                    $sformatf("Queue failed after host CQ_HEAD recovery: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h cq_space=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        cq_space))
            end

            if ((sq_head == 32'h0000_0002) &&
                (cq_tail == 32'h0000_0002) &&
                (cq_occ  == 32'h0000_0001) &&
                done_status[1]) begin
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);
                if (last_tag !== P21E_CMD1_TAG) begin
                    `uvm_fatal("P21E_QUEUE/BAD_FINAL_LAST_TAG",
                        $sformatf("Expected last accepted command tag=0x%08h after CQ_HEAD recovery, got=0x%08h",
                            P21E_CMD1_TAG,
                            last_tag))
                end

                `uvm_info("P21E_QUEUE/DRAINED",
                    $sformatf("CQ-head recovery live-service drain completed after %0d poll(s): status=0x%08h done=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h CQ_SPACE=0x%08h last_tag=0x%08h",
                        cnt,
                        status,
                        done_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        cq_space,
                        last_tag),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P21E_QUEUE/TIMEOUT_AFTER_CQ_HEAD",
                    $sformatf("Timed out waiting for queue to resume/drain after CQ_HEAD recovery: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h cq_space=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        cq_space))
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

        `uvm_info("P21E_CQ_FULL_LIVE_RECOVERY/START",
            "Starting P21E CQ-full stall + host CQ_HEAD recovery during live queue service smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P21E_CQ_FULL_LIVE_RECOVERY/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);
        p21e_clear_cq_memory();

        p21e_program_descriptor_table(
            P21E_DESC_BASE0,
            P21E_DESC0_TAG0,
            P21E_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p21e_program_descriptor_table(
            P21E_DESC_BASE1,
            P21E_DESC1_TAG0,
            P21E_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        // Only SQ[0] is visible before START_QUEUE.  SQ[1] is written and
        // published while the queue is servicing SQ[0].  CQ_DEPTH=1 then
        // forces a command-boundary CQ-full stall after the first completion.
        p21e_program_one_sq_command_entry(0, P21E_CMD0_TAG, P21E_DESC_BASE0);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();

        csr_program_completion_wb();
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_BASE_ADDR, 32'(P21E_CQ_BASE));
        p21e_csr_program_queue_initial_one_visible_cq_depth1();

        csr_check_recipe_idle_ready("before P21E queue START");
        p21e_start_queue_once();

        p21e_wait_for_queue_active_before_doorbell(done_timeout_cycles);
        p21e_append_sq1_while_active();

        p21e_wait_cq_full_after_first_completion(profile_item, done_timeout_cycles * 4);
        p21e_advance_cq_head_while_stalled();
        p21e_poll_final_drained_after_recovery(done_timeout_cycles * 4);

        repeat (5) @(posedge csr_vif.clk);

        // With CQ_DEPTH=1, SQ[1]'s completion reuses physical CQ[0] after
        // the host advances CQ_HEAD.  The pre-recovery first CQ[0] record was
        // checked before CQ_HEAD was advanced; this check verifies the final
        // overwritten CQ[0] record belongs to SQ[1].
        p21e_check_physical_cq0_record("after CQ_HEAD recovery / second completion",
                                       P21E_DESC1_TAG0,
                                       P21E_DESC1_TAG1,
                                       profile_item);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P21E_CQ_FULL_LIVE_RECOVERY/PASS",
            $sformatf("P21E CQ-full live-service recovery completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d SQ_TAIL 1->2 CQ_DEPTH=1 CQ_HEAD 0->1 final SQ_HEAD=2 CQ_TAIL=2",
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
