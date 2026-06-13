// File: tb/uvm/test/ai_accel_subsys_csr_queue_stop_live_service_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_STOP_LIVE_SERVICE_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_STOP_LIVE_SERVICE_SMOKE_TEST_SV

// ============================================================
// P21F STOP_QUEUE during live queue service smoke
//
// Scope:
//   - Programs one valid SQ command entry and publishes only
//     SQ_TAIL=1 before START_QUEUE.
//   - Issues one host START_QUEUE kick with RUN_UNTIL_EMPTY=1.
//   - While the queue controller is busy on SQ[0], the host writes
//     SQ[1], updates CSR_SQ_TAIL from 1 to 2, and writes
//     CSR_QUEUE_COMMAND.STOP_QUEUE.
//   - Verifies STOP_QUEUE is graceful: the active SQ[0] command is
//     allowed to complete and commit CQ[0], but the runtime-appended
//     SQ[1] command is not consumed by the same live-service session.
//   - Verifies a later START_QUEUE kick can consume the still-pending
//     SQ[1] command and commit CQ[1].
//
// P21F does not add hard abort, cancellation, multi-outstanding
// execution, out-of-order completion, interrupts, or any BRAM / GEMM /
// DMA / frontend datapath change.  It validates STOP_QUEUE as a
// command-boundary live-service stop request on top of the P21 runtime
// doorbell policy.
// ============================================================

class ai_accel_subsys_csr_queue_stop_live_service_smoke_test
    extends ai_accel_subsys_csr_queue_completion_wb_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_stop_live_service_smoke_test)

    localparam int unsigned P21F_SQ_BASE      = 32'h0000_0C00;
    localparam int unsigned P21F_CQ_BASE      = 32'h0000_0D00;
    localparam int unsigned P21F_QUEUE_DEPTH  = 4;
    localparam int unsigned P21F_ENTRY_STRIDE = 32'h0000_0040;

    localparam int unsigned P21F_DESC_BASE0   = 32'h0000_0300;
    localparam int unsigned P21F_DESC_BASE1   = 32'h0000_0400;
    localparam int unsigned P21F_DESC_STRIDE  = 32'h0000_0080;

    // VALID=1, OPCODE=0x01, ENABLE_COMPLETION=1.
    // STOP_AFTER_THIS is intentionally 0.  P21F validates the CSR-side
    // STOP_QUEUE request while the queue is actively servicing SQ[0].
    localparam logic [31:0] P21F_CMD_CONTROL  = 32'h0000_0103;
    localparam logic [31:0] P21F_CMD0_TAG     = 32'hD21F_0000;
    localparam logic [31:0] P21F_CMD1_TAG     = 32'hD21F_0001;
    localparam logic [31:0] P21F_COMP_FLAGS   = 32'h0000_0001;

    localparam logic [31:0] P21F_DESC0_TAG0   = 32'hD21F_1000;
    localparam logic [31:0] P21F_DESC0_TAG1   = 32'hD21F_1001;
    localparam logic [31:0] P21F_DESC1_TAG0   = 32'hD21F_2000;
    localparam logic [31:0] P21F_DESC1_TAG1   = 32'hD21F_2001;

    localparam logic [31:0] P21F_EXP_COMMIT_SUCCESS = 32'h0100_1803;
    localparam logic [31:0] P21F_EXP_STATUS_FLAGS   = 32'h0000_003F;
    localparam logic [31:0] P21F_EXP_COUNTS         = 32'h0002_0202;
    localparam logic [31:0] P21F_EXP_DESC_DONE      = 32'h0000_0003;
    localparam logic [31:0] P21F_EXP_ZERO           = 32'h0000_0000;
    localparam logic [31:0] P21F_EXP_RECIPE_DONE    = 32'h0000_0007;
    localparam logic [31:0] P21F_EXP_SLOT_MASKS     = 32'h0000_0003;

    function new(string name = "ai_accel_subsys_csr_queue_stop_live_service_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic program_one_sq_command_entry(input int unsigned sq_slot,
                                                input logic [31:0] cmd_tag,
                                                input int unsigned desc_base);
        int unsigned base;
    begin
        base = P21F_SQ_BASE + (sq_slot * P21F_ENTRY_STRIDE);

        write_src_word_le(base + 16'h04, cmd_tag);
        write_src_word_le(base + 16'h08, 32'(desc_base));
        write_src_word_le(base + 16'h0C, 32'h0000_0002);
        write_src_word_le(base + 16'h10, 32'(P21F_DESC_STRIDE));
        write_src_word_le(base + 16'h14, P21F_COMP_FLAGS);
        write_src_word_le(base + 16'h18, 32'h0000_0000);

        for (int unsigned w = 7; w < 16; w++) begin
            write_src_word_le(base + (w * 4), 32'h0000_0000);
        end

        // Host commit word written last.
        write_src_word_le(base + 16'h00, P21F_CMD_CONTROL);

        `uvm_info("P21F_QUEUE/SQ",
            $sformatf("Programmed SQ[%0d] command entry at 0x%08h control=0x%08h tag=0x%08h desc_base=0x%08h count=2 stride=0x%08h comp_flags=0x%08h",
                sq_slot,
                base,
                P21F_CMD_CONTROL,
                cmd_tag,
                desc_base,
                P21F_DESC_STRIDE,
                P21F_COMP_FLAGS),
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
            desc_base + (0 * P21F_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            first_tag
        );

        program_memory_descriptor(
            desc_base + (1 * P21F_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            second_tag
        );
    end
    endtask

    task automatic clear_p21f_cq_memory();
    begin
        for (int unsigned i = 0; i < (2 * P21F_ENTRY_STRIDE); i++) begin
            p17d_ctrl_vif.dma_dst_mem[P21F_CQ_BASE + i] = 8'h00;
        end
    end
    endtask

    task automatic csr_program_queue_initial_one_visible();
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE,   32'(P21F_SQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH,  32'(P21F_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,   32'h0000_0001);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, 32'(P21F_ENTRY_STRIDE));

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE,   32'(P21F_CQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH,  32'(P21F_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, 32'(P21F_ENTRY_STRIDE));

        // bit0 QUEUE_ENABLE, bit1 RUN_UNTIL_EMPTY, bit2 STOP_ON_ERROR.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CONTROL, 32'h0000_0007);

        `uvm_info("P21F_QUEUE/CFG",
            "Programmed live-service queue with initial SQ_HEAD=0 SQ_TAIL=1 CQ_HEAD=0 CQ_TAIL=0",
            UVM_MEDIUM)
    end
    endtask

    task automatic p21f_start_queue_once(input string phase_name);
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_START] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_COMMAND,
            cmd
        );

        `uvm_info("P21F_QUEUE/START",
            $sformatf("%s: issued one CSR_QUEUE_COMMAND.START_QUEUE kick", phase_name),
            UVM_MEDIUM)
    end
    endtask

    task automatic p21f_request_stop_queue(input string phase_name);
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_STOP] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_COMMAND,
            cmd
        );

        `uvm_info("P21F_QUEUE/STOP",
            $sformatf("%s: issued CSR_QUEUE_COMMAND.STOP_QUEUE request", phase_name),
            UVM_MEDIUM)
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
                `uvm_fatal("P21F_QUEUE/ERROR_BEFORE_DOORBELL",
                    $sformatf("Queue failed before runtime doorbell: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail))
            end

            if (status[0] && (sq_head == 32'h0000_0000) && (cq_tail == 32'h0000_0000)) begin
                `uvm_info("P21F_QUEUE/ACTIVE",
                    $sformatf("Queue is active before runtime doorbell + STOP_QUEUE: status=0x%08h done=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h",
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
                `uvm_fatal("P21F_QUEUE/ACTIVE_TIMEOUT",
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

    task automatic append_sq1_and_request_stop_while_active();
        logic [31:0] status_before;
        logic [31:0] sq_tail_after;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status_before);
        if (!status_before[0]) begin
            `uvm_fatal("P21F_QUEUE/NOT_BUSY_AT_APPEND",
                $sformatf("Expected queue_busy=1 before runtime doorbell append, status=0x%08h",
                    status_before))
        end

        program_one_sq_command_entry(1, P21F_CMD1_TAG, P21F_DESC_BASE1);

        // Runtime doorbell: host-owned SQ_TAIL moves while queue_busy=1.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL, 32'h0000_0002);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL, sq_tail_after);

        if (sq_tail_after !== 32'h0000_0002) begin
            `uvm_fatal("P21F_QUEUE/SQ_TAIL_DOORBELL_FAIL",
                $sformatf("Expected SQ_TAIL=2 after runtime doorbell, got 0x%08h", sq_tail_after))
        end

        // STOP_QUEUE is requested after SQ[1] is published but while SQ[0]
        // is still active.  The controller must finish SQ[0], commit CQ[0],
        // and then stop before consuming SQ[1].
        p21f_request_stop_queue("LIVE_STOP");

        `uvm_info("P21F_QUEUE/DOORBELL_STOP",
            $sformatf("Runtime SQ doorbell and STOP_QUEUE issued while queue_busy=1: wrote SQ[1], SQ_TAIL 1->2, status_before=0x%08h",
                status_before),
            UVM_MEDIUM)
    end
    endtask

    task automatic poll_live_service_stopped_after_first_command(input int unsigned timeout_cycles);
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

            if ((error_status != 32'h0000_0000) ||
                (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P21F_QUEUE/ERROR",
                    $sformatf("Queue failed during STOP_QUEUE live-service stop: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h last_tag=0x%08h",
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
                (last_tag == P21F_CMD0_TAG) &&
                done_status[3]) begin

                // Hold time proves the runtime-appended SQ[1] is not
                // consumed by the stopped live-service session.
                repeat (80) @(posedge csr_vif.clk);

                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head);
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL, cq_tail);
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);

                if ((sq_head !== 32'h0000_0001) ||
                    (cq_tail !== 32'h0000_0001) ||
                    (cq_occ  !== 32'h0000_0001) ||
                    (last_tag !== P21F_CMD0_TAG)) begin
                    `uvm_fatal("P21F_QUEUE/AUTO_CONTINUED_AFTER_STOP",
                        $sformatf("STOP_QUEUE failed to suppress live-service auto-continue: sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h last_tag=0x%08h",
                            sq_head,
                            cq_tail,
                            cq_occ,
                            last_tag))
                end

                `uvm_info("P21F_QUEUE/STOPPED",
                    $sformatf("STOP_QUEUE live-service stop observed after first command: status=0x%08h done=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h last_tag=0x%08h",
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
                `uvm_fatal("P21F_QUEUE/STOP_TIMEOUT",
                    $sformatf("Timed out waiting for STOP_QUEUE command-boundary stop: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h last_tag=0x%08h",
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

    task automatic poll_pending_sq1_drained_after_restart(input int unsigned timeout_cycles);
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

            if ((error_status != 32'h0000_0000) ||
                (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P21F_QUEUE/RESTART_ERROR",
                    $sformatf("Queue failed after restart for pending SQ[1]: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h last_tag=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        last_tag))
            end

            if ((sq_head == 32'h0000_0002) &&
                (cq_tail == 32'h0000_0002) &&
                (cq_occ  == 32'h0000_0002) &&
                (last_tag == P21F_CMD1_TAG) &&
                done_status[1]) begin
                `uvm_info("P21F_QUEUE/DRAINED_AFTER_RESTART",
                    $sformatf("Pending runtime-appended SQ[1] drained after second START_QUEUE: status=0x%08h done=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h last_tag=0x%08h",
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
                `uvm_fatal("P21F_QUEUE/RESTART_TIMEOUT",
                    $sformatf("Timed out waiting for pending SQ[1] after restart: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h last_tag=0x%08h",
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

    function automatic logic [31:0] read_p21f_cq_word(input int unsigned cq_slot,
                                                      input int unsigned byte_offset);
        int unsigned idx;
        logic [31:0] value;
    begin
        idx = P21F_CQ_BASE + (cq_slot * P21F_ENTRY_STRIDE) + byte_offset;
        value = 32'h0000_0000;
        value[7:0]   = p17d_ctrl_vif.dma_dst_mem[idx + 0];
        value[15:8]  = p17d_ctrl_vif.dma_dst_mem[idx + 1];
        value[23:16] = p17d_ctrl_vif.dma_dst_mem[idx + 2];
        value[31:24] = p17d_ctrl_vif.dma_dst_mem[idx + 3];
        return value;
    end
    endfunction

    task automatic expect_p21f_cq_word(input int unsigned cq_slot,
                                       input int unsigned byte_offset,
                                       input logic [31:0] expected,
                                       input string name);
        logic [31:0] actual;
    begin
        actual = read_p21f_cq_word(cq_slot, byte_offset);
        if (actual !== expected) begin
            `uvm_fatal("P21F_CQ_WB/RECORD_MISMATCH",
                $sformatf("CQ[%0d] %s mismatch at +0x%02x: actual=0x%08h expected=0x%08h",
                    cq_slot,
                    name,
                    byte_offset,
                    actual,
                    expected))
        end

        `uvm_info("P21F_CQ_WB/CHECK",
            $sformatf("CQ[%0d] %s PASS at +0x%02x: 0x%08h",
                cq_slot,
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic expect_p21f_cq_word_nonzero(input int unsigned cq_slot,
                                               input int unsigned byte_offset,
                                               input string name);
        logic [31:0] actual;
    begin
        actual = read_p21f_cq_word(cq_slot, byte_offset);
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P21F_CQ_WB/RECORD_ZERO",
                $sformatf("CQ[%0d] %s unexpectedly zero at +0x%02x",
                    cq_slot,
                    name,
                    byte_offset))
        end

        `uvm_info("P21F_CQ_WB/CHECK",
            $sformatf("CQ[%0d] %s nonzero PASS at +0x%02x: 0x%08h",
                cq_slot,
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic expect_p21f_cq_slot_invalid(input int unsigned cq_slot,
                                               input string phase_name);
        logic [31:0] commit_word;
    begin
        commit_word = read_p21f_cq_word(cq_slot, 16'h00);
        if (commit_word !== 32'h0000_0000) begin
            `uvm_fatal("P21F_CQ_WB/UNEXPECTED_CQ_COMMIT",
                $sformatf("%s: CQ[%0d] should remain invalid before restart, but word0=0x%08h",
                    phase_name,
                    cq_slot,
                    commit_word))
        end

        `uvm_info("P21F_CQ_WB/CHECK",
            $sformatf("%s: CQ[%0d] remains invalid before restart as expected", phase_name, cq_slot),
            UVM_LOW)
    end
    endtask

    task automatic check_one_p21f_cq_record(input int unsigned cq_slot,
                                            input logic [31:0] first_desc_tag,
                                            input logic [31:0] last_desc_tag,
                                            input ai_accel_subsys_seq_item profile_item);
        int unsigned expected_macs;
        int unsigned expected_outputs;
    begin
        expected_macs    = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n) * int'(profile_item.dim_k);
        expected_outputs = 2 * int'(profile_item.dim_m) * int'(profile_item.dim_n);

        expect_p21f_cq_word(cq_slot, 16'h00, P21F_EXP_COMMIT_SUCCESS, "word0 commit");
        expect_p21f_cq_word(cq_slot, 16'h04, P21F_EXP_STATUS_FLAGS,   "word1 status_flags");
        expect_p21f_cq_word(cq_slot, 16'h08, first_desc_tag,           "word2 first_user_tag");
        expect_p21f_cq_word(cq_slot, 16'h0C, last_desc_tag,            "word3 last_user_tag");
        expect_p21f_cq_word(cq_slot, 16'h10, P21F_EXP_COUNTS,          "word4 counts");
        expect_p21f_cq_word(cq_slot, 16'h14, P21F_EXP_DESC_DONE,       "word5 desc_fetch_done_status");
        expect_p21f_cq_word(cq_slot, 16'h18, P21F_EXP_ZERO,            "word6 desc_fetch_error_status");
        expect_p21f_cq_word(cq_slot, 16'h1C, P21F_EXP_ZERO,            "word7 desc_fetch_reject_status");
        expect_p21f_cq_word(cq_slot, 16'h20, P21F_EXP_RECIPE_DONE,     "word8 recipe_done_status");
        expect_p21f_cq_word(cq_slot, 16'h24, P21F_EXP_ZERO,            "word9 recipe_error_status");
        expect_p21f_cq_word(cq_slot, 16'h28, P21F_EXP_ZERO,            "word10 recipe_reject_status");
        expect_p21f_cq_word(cq_slot, 16'h2C, P21F_EXP_SLOT_MASKS,      "word11 slot_mask_summary");
        expect_p21f_cq_word_nonzero(cq_slot, 16'h30,                  "word12 perf_busy_cycles");
        expect_p21f_cq_word(cq_slot, 16'h34, 32'(expected_macs),       "word13 perf_mac_count");
        expect_p21f_cq_word(cq_slot, 16'h38, 32'(expected_outputs),    "word14 perf_output_count");
        expect_p21f_cq_word(cq_slot, 16'h3C, P21F_EXP_ZERO,            "word15 error_detail");
    end
    endtask

    task automatic check_p21f_cq_records(input ai_accel_subsys_seq_item profile_item);
    begin
        check_one_p21f_cq_record(0, P21F_DESC0_TAG0, P21F_DESC0_TAG1, profile_item);
        check_one_p21f_cq_record(1, P21F_DESC1_TAG0, P21F_DESC1_TAG1, profile_item);
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

        `uvm_info("P21F_STOP_LIVE_SERVICE/START",
            "Starting P21F STOP_QUEUE during live queue service smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P21F_STOP_LIVE_SERVICE/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);
        clear_p21f_cq_memory();

        program_descriptor_table(
            P21F_DESC_BASE0,
            P21F_DESC0_TAG0,
            P21F_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        program_descriptor_table(
            P21F_DESC_BASE1,
            P21F_DESC1_TAG0,
            P21F_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        // Only SQ[0] is visible before START_QUEUE.  SQ[1] is written and
        // published while the queue is already servicing SQ[0].  STOP_QUEUE
        // is then requested before SQ[0] completes.
        program_one_sq_command_entry(0, P21F_CMD0_TAG, P21F_DESC_BASE0);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();

        csr_program_completion_wb();
        csr_program_queue_initial_one_visible();

        csr_check_recipe_idle_ready("before P21F live-service START");
        p21f_start_queue_once("LIVE_STOP");

        wait_for_queue_active_before_doorbell(done_timeout_cycles);
        append_sq1_and_request_stop_while_active();

        poll_live_service_stopped_after_first_command(done_timeout_cycles * 4);
        repeat (5) @(posedge csr_vif.clk);

        check_one_p21f_cq_record(0, P21F_DESC0_TAG0, P21F_DESC0_TAG1, profile_item);
        expect_p21f_cq_slot_invalid(1, "LIVE_STOP");

        // Prove the runtime-appended SQ[1] was not dropped.  After clearing
        // sticky queue done state, a second START_QUEUE should consume the
        // still-pending SQ[1] and commit CQ[1].
        csr_queue_clear_sticky_status();
        p21f_start_queue_once("RESTART_PENDING_SQ1");
        poll_pending_sq1_drained_after_restart(done_timeout_cycles * 4);

        repeat (5) @(posedge csr_vif.clk);
        check_p21f_cq_records(profile_item);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P21F_STOP_LIVE_SERVICE/PASS",
            $sformatf("P21F STOP_QUEUE live-service behavior completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d runtime_SQ_TAIL=2 first_session_SQ_HEAD=1 final_SQ_HEAD=2 CQ_entries=2",
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
