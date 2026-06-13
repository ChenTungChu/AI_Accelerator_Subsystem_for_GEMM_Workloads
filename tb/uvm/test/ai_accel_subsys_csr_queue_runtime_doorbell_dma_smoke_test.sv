// File: tb/uvm/test/ai_accel_subsys_csr_queue_runtime_doorbell_dma_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_RUNTIME_DOORBELL_DMA_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_RUNTIME_DOORBELL_DMA_SMOKE_TEST_SV

// ============================================================
// P21C runtime doorbell / append-while-active DMA queue smoke
//
// Scope:
//   - Programs one valid SQ command entry and publishes only
//     SQ_TAIL=1 before START_QUEUE.
//   - Issues one host START_QUEUE kick with RUN_UNTIL_EMPTY=1.
//   - While the queue controller is busy on SQ[0], the host writes
//     SQ[1] and updates CSR_SQ_TAIL from 1 to 2.
//   - Verifies the queue controller observes the live SQ_TAIL value
//     only at the command boundary, continues to SQ[1] without a
//     second START_QUEUE kick, and drains both commands in order.
//   - Verifies two CQ completion records are committed at CQ[0]
//     and CQ[1].
//
// P21C does not add multi-outstanding execution, out-of-order
// completion, interrupts, or any BRAM / GEMM / DMA / frontend datapath
// change.  It validates runtime doorbell semantics on top of the
// P20 single-active-command auto-drain path.
// ============================================================

class ai_accel_subsys_csr_queue_runtime_doorbell_dma_smoke_test
    extends ai_accel_subsys_csr_queue_completion_wb_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_runtime_doorbell_dma_smoke_test)

    localparam int unsigned P21C_SQ_BASE      = 32'h0000_0700;
    localparam int unsigned P21C_CQ_BASE      = 32'h0000_0800;
    localparam int unsigned P21C_QUEUE_DEPTH  = 4;
    localparam int unsigned P21C_ENTRY_STRIDE = 32'h0000_0040;

    localparam int unsigned P21C_DESC_BASE0   = 32'h0000_0300;
    localparam int unsigned P21C_DESC_BASE1   = 32'h0000_0400;
    localparam int unsigned P21C_DESC_STRIDE  = 32'h0000_0080;

    // VALID=1, OPCODE=0x01, ENABLE_COMPLETION=1.
    // STOP_AFTER_THIS is intentionally 0 for live service continuation.
    localparam logic [31:0] P21C_CMD_CONTROL  = 32'h0000_0103;
    localparam logic [31:0] P21C_CMD0_TAG     = 32'hD21C_0000;
    localparam logic [31:0] P21C_CMD1_TAG     = 32'hD21C_0001;
    localparam logic [31:0] P21C_COMP_FLAGS   = 32'h0000_0001;

    localparam logic [31:0] P21C_DESC0_TAG0   = 32'hD21C_1000;
    localparam logic [31:0] P21C_DESC0_TAG1   = 32'hD21C_1001;
    localparam logic [31:0] P21C_DESC1_TAG0   = 32'hD21C_2000;
    localparam logic [31:0] P21C_DESC1_TAG1   = 32'hD21C_2001;

    localparam logic [31:0] P21C_EXP_COMMIT_SUCCESS = 32'h0100_1803;
    localparam logic [31:0] P21C_EXP_STATUS_FLAGS   = 32'h0000_003F;
    localparam logic [31:0] P21C_EXP_COUNTS         = 32'h0002_0202;
    localparam logic [31:0] P21C_EXP_DESC_DONE      = 32'h0000_0003;
    localparam logic [31:0] P21C_EXP_ZERO           = 32'h0000_0000;
    localparam logic [31:0] P21C_EXP_RECIPE_DONE    = 32'h0000_0007;
    localparam logic [31:0] P21C_EXP_SLOT_MASKS     = 32'h0000_0003;

    function new(string name = "ai_accel_subsys_csr_queue_runtime_doorbell_dma_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic program_one_sq_command_entry(input int unsigned sq_slot,
                                                input logic [31:0] cmd_tag,
                                                input int unsigned desc_base);
        int unsigned base;
    begin
        base = P21C_SQ_BASE + (sq_slot * P21C_ENTRY_STRIDE);

        // In a real host flow, payload words are written before the commit
        // control word.  The byte-array memory model is deterministic, but
        // keep the same programming order to document the intended policy.
        write_src_word_le(base + 16'h04, cmd_tag);
        write_src_word_le(base + 16'h08, 32'(desc_base));
        write_src_word_le(base + 16'h0C, 32'h0000_0002);
        write_src_word_le(base + 16'h10, 32'(P21C_DESC_STRIDE));
        write_src_word_le(base + 16'h14, P21C_COMP_FLAGS);
        write_src_word_le(base + 16'h18, 32'h0000_0000);

        for (int unsigned w = 7; w < 16; w++) begin
            write_src_word_le(base + (w * 4), 32'h0000_0000);
        end

        // Commit word written last.
        write_src_word_le(base + 16'h00, P21C_CMD_CONTROL);

        `uvm_info("P21C_QUEUE/SQ",
            $sformatf("Programmed SQ[%0d] command entry at 0x%08h control=0x%08h tag=0x%08h desc_base=0x%08h count=2 stride=0x%08h comp_flags=0x%08h",
                sq_slot,
                base,
                P21C_CMD_CONTROL,
                cmd_tag,
                desc_base,
                P21C_DESC_STRIDE,
                P21C_COMP_FLAGS),
            UVM_MEDIUM)
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
            desc_base + (0 * P21C_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            first_tag
        );

        program_memory_descriptor(
            desc_base + (1 * P21C_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            second_tag
        );
    end
    endtask

    task automatic clear_p21c_cq_memory();
    begin
        for (int unsigned i = 0; i < (2 * P21C_ENTRY_STRIDE); i++) begin
            p17d_ctrl_vif.dma_dst_mem[P21C_CQ_BASE + i] = 8'h00;
        end
    end
    endtask

    task automatic csr_program_queue_initial_one_visible();
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE,   32'(P21C_SQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH,  32'(P21C_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,   32'h0000_0001);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, 32'(P21C_ENTRY_STRIDE));

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE,   32'(P21C_CQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH,  32'(P21C_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, 32'(P21C_ENTRY_STRIDE));

        // bit0 QUEUE_ENABLE, bit1 RUN_UNTIL_EMPTY, bit2 STOP_ON_ERROR.
        // Keep RUN_UNTIL_EMPTY enabled.  P21C proves the next SQ_TAIL value
        // is observed live at the command boundary rather than snapshotted
        // only at START_QUEUE time.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CONTROL, 32'h0000_0007);

        `uvm_info("P21C_QUEUE/CFG",
            "Programmed live-service queue with initial SQ_HEAD=0 SQ_TAIL=1 CQ_HEAD=0 CQ_TAIL=0",
            UVM_MEDIUM)
    end
    endtask

    task automatic p21c_start_queue_once();
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_START] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_COMMAND,
            cmd
        );

        `uvm_info("P21C_QUEUE/START", "Issued one CSR_QUEUE_COMMAND.START_QUEUE kick with only SQ[0] visible", UVM_MEDIUM)
    end
    endtask

    task automatic wait_for_queue_active_before_doorbell(input int unsigned timeout_cycles);
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
                `uvm_fatal("P21C_QUEUE/ERROR_BEFORE_DOORBELL",
                    $sformatf("Queue failed before runtime doorbell: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail))
            end

            if (status[0] && (sq_head == 32'h0000_0000) && (cq_tail == 32'h0000_0000)) begin
                `uvm_info("P21C_QUEUE/ACTIVE",
                    $sformatf("Queue is active before runtime doorbell: status=0x%08h done=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h",
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
                `uvm_fatal("P21C_QUEUE/ACTIVE_TIMEOUT",
                    $sformatf("Timed out waiting for queue active before runtime doorbell: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h",
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

    task automatic append_sq1_while_active();
        logic [31:0] status_before;
        logic [31:0] sq_tail_after;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status_before);
        if (!status_before[0]) begin
            `uvm_fatal("P21C_QUEUE/NOT_BUSY_AT_APPEND",
                $sformatf("Expected queue_busy=1 before runtime doorbell append, status=0x%08h",
                    status_before))
        end

        program_one_sq_command_entry(1, P21C_CMD1_TAG, P21C_DESC_BASE1);

        // Runtime doorbell: host-owned SQ_TAIL moves while queue_busy=1.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL, 32'h0000_0002);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL, sq_tail_after);

        if (sq_tail_after !== 32'h0000_0002) begin
            `uvm_fatal("P21C_QUEUE/SQ_TAIL_DOORBELL_FAIL",
                $sformatf("Expected SQ_TAIL=2 after runtime doorbell, got 0x%08h", sq_tail_after))
        end

        `uvm_info("P21C_QUEUE/DOORBELL",
            $sformatf("Runtime doorbell issued while queue_busy=1: wrote SQ[1], updated SQ_TAIL 1->2, status_before=0x%08h",
                status_before),
            UVM_MEDIUM)
    end
    endtask

    task automatic poll_runtime_doorbell_queue_drained(input int unsigned timeout_cycles);
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
                `uvm_fatal("P21C_QUEUE/ERROR",
                    $sformatf("Queue failed during runtime-doorbell drain: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h",
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
                if (last_tag !== P21C_CMD1_TAG) begin
                    `uvm_fatal("P21C_QUEUE/BAD_LAST_TAG",
                        $sformatf("Expected last accepted command tag=0x%08h got=0x%08h",
                            P21C_CMD1_TAG,
                            last_tag))
                end

                `uvm_info("P21C_QUEUE/DRAINED",
                    $sformatf("Runtime-doorbell queue service completed after %0d poll(s): status=0x%08h done=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h last_tag=0x%08h",
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
                `uvm_fatal("P21C_QUEUE/TIMEOUT",
                    $sformatf("Timed out waiting for runtime-doorbell queue drain: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h",
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

    function automatic logic [31:0] read_p21c_cq_word(input int unsigned cq_slot,
                                                      input int unsigned byte_offset);
        int unsigned idx;
        logic [31:0] value;
    begin
        idx = P21C_CQ_BASE + (cq_slot * P21C_ENTRY_STRIDE) + byte_offset;
        value = 32'h0000_0000;
        value[7:0]   = p17d_ctrl_vif.dma_dst_mem[idx + 0];
        value[15:8]  = p17d_ctrl_vif.dma_dst_mem[idx + 1];
        value[23:16] = p17d_ctrl_vif.dma_dst_mem[idx + 2];
        value[31:24] = p17d_ctrl_vif.dma_dst_mem[idx + 3];
        return value;
    end
    endfunction

    task automatic expect_p21c_cq_word(input int unsigned cq_slot,
                                       input int unsigned byte_offset,
                                       input logic [31:0] expected,
                                       input string name);
        logic [31:0] actual;
    begin
        actual = read_p21c_cq_word(cq_slot, byte_offset);
        if (actual !== expected) begin
            `uvm_fatal("P21C_CQ_WB/RECORD_MISMATCH",
                $sformatf("CQ[%0d] %s mismatch at +0x%02x: actual=0x%08h expected=0x%08h",
                    cq_slot,
                    name,
                    byte_offset,
                    actual,
                    expected))
        end

        `uvm_info("P21C_CQ_WB/CHECK",
            $sformatf("CQ[%0d] %s PASS at +0x%02x: 0x%08h",
                cq_slot,
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic expect_p21c_cq_word_nonzero(input int unsigned cq_slot,
                                               input int unsigned byte_offset,
                                               input string name);
        logic [31:0] actual;
    begin
        actual = read_p21c_cq_word(cq_slot, byte_offset);
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P21C_CQ_WB/RECORD_ZERO",
                $sformatf("CQ[%0d] %s unexpectedly zero at +0x%02x",
                    cq_slot,
                    name,
                    byte_offset))
        end

        `uvm_info("P21C_CQ_WB/CHECK",
            $sformatf("CQ[%0d] %s nonzero PASS at +0x%02x: 0x%08h",
                cq_slot,
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic check_one_p21c_cq_record(input int unsigned cq_slot,
                                            input logic [31:0] first_desc_tag,
                                            input logic [31:0] last_desc_tag,
                                            input ai_accel_subsys_seq_item profile_item);
        int unsigned expected_macs;
        int unsigned expected_outputs;
    begin
        expected_macs    = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n) * int'(profile_item.dim_k);
        expected_outputs = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n);

        expect_p21c_cq_word(cq_slot, 16'h00, P21C_EXP_COMMIT_SUCCESS, "word0 commit");
        expect_p21c_cq_word(cq_slot, 16'h04, P21C_EXP_STATUS_FLAGS,   "word1 status_flags");
        expect_p21c_cq_word(cq_slot, 16'h08, first_desc_tag,           "word2 first_user_tag");
        expect_p21c_cq_word(cq_slot, 16'h0C, last_desc_tag,            "word3 last_user_tag");
        expect_p21c_cq_word(cq_slot, 16'h10, P21C_EXP_COUNTS,          "word4 counts");
        expect_p21c_cq_word(cq_slot, 16'h14, P21C_EXP_DESC_DONE,       "word5 desc_fetch_done_status");
        expect_p21c_cq_word(cq_slot, 16'h18, P21C_EXP_ZERO,            "word6 desc_fetch_error_status");
        expect_p21c_cq_word(cq_slot, 16'h1C, P21C_EXP_ZERO,            "word7 desc_fetch_reject_status");
        expect_p21c_cq_word(cq_slot, 16'h20, P21C_EXP_RECIPE_DONE,     "word8 recipe_done_status");
        expect_p21c_cq_word(cq_slot, 16'h24, P21C_EXP_ZERO,            "word9 recipe_error_status");
        expect_p21c_cq_word(cq_slot, 16'h28, P21C_EXP_ZERO,            "word10 recipe_reject_status");
        expect_p21c_cq_word(cq_slot, 16'h2C, P21C_EXP_SLOT_MASKS,      "word11 slot_mask_summary");
        expect_p21c_cq_word_nonzero(cq_slot, 16'h30,                  "word12 perf_busy_cycles");
        expect_p21c_cq_word(cq_slot, 16'h34, 32'(expected_macs),       "word13 perf_mac_count");
        expect_p21c_cq_word(cq_slot, 16'h38, 32'(expected_outputs),    "word14 perf_output_count");
        expect_p21c_cq_word(cq_slot, 16'h3C, P21C_EXP_ZERO,            "word15 error_detail");
    end
    endtask

    task automatic check_p21c_cq_records(input ai_accel_subsys_seq_item profile_item);
    begin
        check_one_p21c_cq_record(0, P21C_DESC0_TAG0, P21C_DESC0_TAG1, profile_item);
        check_one_p21c_cq_record(1, P21C_DESC1_TAG0, P21C_DESC1_TAG1, profile_item);
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

        `uvm_info("P21C_RUNTIME_DOORBELL_DMA/START",
            "Starting P21C runtime doorbell append-while-active DMA queue smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P21C_RUNTIME_DOORBELL_DMA/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);
        clear_p21c_cq_memory();

        program_descriptor_table(
            P21C_DESC_BASE0,
            P21C_DESC0_TAG0,
            P21C_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        program_descriptor_table(
            P21C_DESC_BASE1,
            P21C_DESC1_TAG0,
            P21C_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        // Only SQ[0] is visible before START_QUEUE.  SQ[1] is written and
        // published while the queue is already servicing SQ[0].
        program_one_sq_command_entry(0, P21C_CMD0_TAG, P21C_DESC_BASE0);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();

        csr_program_completion_wb();
        csr_program_queue_initial_one_visible();

        csr_check_recipe_idle_ready("before P21C queue START");
        p21c_start_queue_once();

        wait_for_queue_active_before_doorbell(done_timeout_cycles);
        append_sq1_while_active();

        poll_runtime_doorbell_queue_drained(done_timeout_cycles * 4);

        repeat (5) @(posedge csr_vif.clk);

        check_p21c_cq_records(profile_item);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P21C_RUNTIME_DOORBELL_DMA/PASS",
            $sformatf("P21C runtime doorbell queue service completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d initial_SQ_TAIL=1 runtime_SQ_TAIL=2 CQ_entries=2",
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
