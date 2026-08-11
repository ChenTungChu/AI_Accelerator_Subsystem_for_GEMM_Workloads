// File: tb/uvm/test/ai_accel_subsys_csr_queue_reject_error_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_REJECT_ERROR_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_REJECT_ERROR_TEST_SV

// ============================================================
// P19F queue reject / empty / full / bad-pointer handling test
//
// Scope:
//   - Validates queue-disabled reject.
//   - Validates invalid queue configuration reject.
//   - Validates empty SQ drain behavior.
//   - Validates bad SQ/CQ pointer occupancy reject.
//   - Validates canonical SQ_HEAD/CQ_TAIL hardware ownership.
//   - Validates natural CQ-full stall and recovery by host CQ_HEAD update.
//   - Validates START_QUEUE busy/sticky/underlying-busy policy.
//   - Validates busy queue-configuration write rejection and retention.
//   - Validates that queue activity blocks manual P14/P15/P16/P17/P18 starts.
//   - After CQ-full recovery, reuses the P19E end-to-end flow and
//     confirms the completion record is written into the CQ slot.
//   - Confirms a manual P15 job can run after queue ownership ends.
//
// P19F remains single-outstanding.  It does not add interrupts,
// multi-outstanding execution, or out-of-order completion.
// ============================================================

class ai_accel_subsys_csr_queue_reject_error_test
    extends ai_accel_subsys_csr_queue_completion_wb_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_reject_error_test)

    localparam int unsigned P19F_SQ_BASE      = 32'h0000_0700;
    localparam int unsigned P19F_CQ_BASE      = 32'h0000_0800;
    localparam int unsigned P19F_QUEUE_DEPTH  = 4;
    localparam int unsigned P19F_ENTRY_STRIDE = 32'h0000_0040;

    // Entry 0 must allow RUN_UNTIL_EMPTY auto-continue so its natural
    // completion can expose a CQ-full boundary before entry 1.
    // Entry 1 stops the two-command targeted flow after recovery.
    localparam logic [31:0] P19F_CMD_CONTROL_CONTINUE = 32'h0000_0103;
    localparam logic [31:0] P19F_CMD_CONTROL_STOP     = 32'h0000_0303;
    localparam logic [31:0] P19F_CMD_TAG      = 32'hD19F_0000;
    localparam logic [31:0] P19F_COMP_FLAGS   = 32'h0000_0001;

    localparam int Q_DONE_DRAINED             = 1;
    localparam int Q_DONE_CMD_FETCHED         = 2;
    localparam int Q_DONE_CMD_VALIDATED       = 3;

    localparam int Q_REJ_QUEUE_BUSY           = 0;
    localparam int Q_REJ_QUEUE_DISABLED       = 1;
    localparam int Q_REJ_INVALID_CFG          = 2;
    localparam int Q_REJ_UNDERLYING_BUSY      = 3;
    localparam int Q_REJ_STICKY_ERROR         = 4;
    localparam int Q_REJ_RESET_POINTERS_BUSY  = 6;
    localparam int Q_REJ_CONFIG_WRITE_BUSY    = 7;

    localparam int Q_ERR_CMD_FETCH            = 0;
    localparam int Q_ERR_CMD_VALIDATION       = 1;
    localparam int Q_ERR_BAD_POINTER          = 5;
    localparam int Q_ERR_CONFIG_WRITE_BUSY    = 7;

    localparam int P14_REJ_QUEUE_OWNER        = 8;
    localparam int P16_REJ_MANUAL_CMD         = 7;
    localparam int P17_REJ_BUSY               = 0;
    localparam int P18_REJ_ENGINE             = 0;

    localparam logic [31:0] ERR_DISABLED        = 32'h0000_0001;
    localparam logic [31:0] ERR_INVALID_CFG     = 32'h0000_0002;
    localparam logic [31:0] ERR_BAD_POINTER     = 32'h0000_0003;
    localparam logic [31:0] ERR_UNDERLYING_BUSY = 32'h0000_0004;
    localparam logic [31:0] ERR_AR_RRESP         = 32'h0000_0101;
    localparam logic [31:0] ERR_AR_EARLY_RLAST   = 32'h0000_0102;
    localparam logic [31:0] ERR_AR_MISSING_RLAST = 32'h0000_0103;
    localparam logic [31:0] ERR_CMD_BAD_OPCODE       = 32'h0000_0202;
    localparam logic [31:0] ERR_CMD_NO_COMPLETION    = 32'h0000_0203;
    localparam logic [31:0] ERR_CMD_RSVD_BITS        = 32'h0000_0204;
    localparam logic [31:0] ERR_CMD_DESC_UNALIGNED   = 32'h0000_0205;
    localparam logic [31:0] ERR_CMD_DESC_COUNT_RANGE = 32'h0000_0207;
    localparam logic [31:0] ERR_CMD_STRIDE_UNALIGNED = 32'h0000_0209;

    function new(string name = "ai_accel_subsys_csr_queue_reject_error_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p19f_start_queue();
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_START] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_COMMAND, cmd);
        `uvm_info("P19F_QUEUE/START", "Issued CSR_QUEUE_COMMAND.START_QUEUE", UVM_MEDIUM)
    end
    endtask

    task automatic p19f_clear_queue_sticky_and_wait_idle();
        logic [31:0] cmd;
        logic [31:0] state;
        int unsigned cnt;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_CLEAR_DONE]  = 1'b1;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_CLEAR_ERROR] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_COMMAND, cmd);

        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATE, state);
            if (state == 32'h0000_0000) begin
                return;
            end
            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > 20) begin
                `uvm_fatal("P19F_QUEUE/CLEAR_TIMEOUT",
                    $sformatf("Timed out waiting for queue state to return idle, state=0x%08h", state))
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.1-C direct queue status clear helpers
    // ------------------------------------------------------------
    task automatic p19f_direct_queue_done_clear(input string tag);
        logic [31:0] before_status;
        logic [31:0] after_status;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS, before_status);
        if (before_status == 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1C/P19_DONE_PRE",
                $sformatf("%s: expected nonzero queue DONE_STATUS", tag))
        end

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS, before_status);
        repeat (3) @(posedge csr_vif.clk);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS, after_status);
        if (after_status != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1C/P19_DONE_CLEAR",
                $sformatf("%s: queue DONE direct clear failed before=0x%08h after=0x%08h",
                    tag, before_status, after_status))
        end

        `uvm_info("CODE_COV_C1C/P19_DONE_CLEAR_PASS",
            $sformatf("%s: queue DONE direct clear PASS before=0x%08h", tag, before_status),
            UVM_MEDIUM)
    end
    endtask

    task automatic p19f_direct_queue_reject_clear(input string tag);
        logic [31:0] reject_before;
        logic [31:0] reject_after;
        logic [31:0] error_after;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_before);
        if (reject_before == 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1C/P19_REJECT_PRE",
                $sformatf("%s: expected nonzero queue REJECT_STATUS", tag))
        end

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_before);
        repeat (3) @(posedge csr_vif.clk);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_after);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_after);

        if ((reject_after != 32'h0000_0000) || (error_after != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1C/P19_REJECT_CLEAR",
                $sformatf("%s: queue REJECT direct clear failed reject 0x%08h->0x%08h error_after=0x%08h",
                    tag, reject_before, reject_after, error_after))
        end

        `uvm_info("CODE_COV_C1C/P19_REJECT_CLEAR_PASS",
            $sformatf("%s: queue REJECT direct clear PASS before=0x%08h", tag, reject_before),
            UVM_MEDIUM)
    end
    endtask

    task automatic p19f_direct_queue_error_clear(input string tag);
        logic [31:0] error_before;
        logic [31:0] error_after;
        logic [31:0] reject_after;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_before);
        if (error_before == 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1C/P19_ERROR_PRE",
                $sformatf("%s: expected nonzero queue ERROR_STATUS", tag))
        end

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_before);
        repeat (3) @(posedge csr_vif.clk);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_after);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_after);

        // ERROR_STATUS and REJECT_STATUS share the architectural queue error
        // clear pulse, so both must be drained by this direct status write.
        if ((error_after != 32'h0000_0000) || (reject_after != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1C/P19_ERROR_CLEAR",
                $sformatf("%s: queue ERROR direct clear failed error 0x%08h->0x%08h reject_after=0x%08h",
                    tag, error_before, error_after, reject_after))
        end

        `uvm_info("CODE_COV_C1C/P19_ERROR_CLEAR_PASS",
            $sformatf("%s: queue ERROR direct clear PASS before=0x%08h", tag, error_before),
            UVM_MEDIUM)
    end
    endtask

    task automatic p19f_reset_queue_pointers();
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
        if ((sq_head != 32'h0000_0000) || (sq_tail != 32'h0000_0000) ||
            (cq_head != 32'h0000_0000) || (cq_tail != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1_2G7_A1/RESET_POINTERS",
                $sformatf("RESET_QUEUE_POINTERS failed: SQ_HEAD=0x%08h SQ_TAIL=0x%08h CQ_HEAD=0x%08h CQ_TAIL=0x%08h",
                    sq_head, sq_tail, cq_head, cq_tail))
        end
    end
    endtask

    task automatic p19f_program_base_queue(input logic [31:0] sq_tail,
                                           input logic [31:0] cq_head,
                                           input logic [31:0] sq_depth,
                                           input logic [31:0] cq_depth,
                                           input logic [31:0] control_value);
    begin
        p19f_reset_queue_pointers();

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE,   32'(P19F_SQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH,  sq_depth);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,   sq_tail);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, 32'(P19F_ENTRY_STRIDE));

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE,   32'(P19F_CQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH,  cq_depth);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,   cq_head);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, 32'(P19F_ENTRY_STRIDE));

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CONTROL, control_value);
    end
    endtask

    task automatic p19f_program_valid_sq_command_entry(input int unsigned entry_index,
                                                         input logic [31:0] control_value);
        int unsigned base;
    begin
        base = P19F_SQ_BASE + (entry_index * P19F_ENTRY_STRIDE);

        write_src_word_le(base + 16'h00, control_value);
        write_src_word_le(base + 16'h04, P19F_CMD_TAG);
        write_src_word_le(base + 16'h08, 32'(P17D_DESC_BASE));
        write_src_word_le(base + 16'h0C, 32'h0000_0002);
        write_src_word_le(base + 16'h10, 32'(P17D_DESC_STRIDE));
        write_src_word_le(base + 16'h14, P19F_COMP_FLAGS);
        write_src_word_le(base + 16'h18, 32'h0000_0000);

        for (int unsigned w = 7; w < 16; w++) begin
            write_src_word_le(base + (w * 4), 32'h0000_0000);
        end

        `uvm_info("P19F_QUEUE/SQ",
            $sformatf("Programmed valid SQ command entry[%0d] at 0x%08h control=0x%08h tag=0x%08h desc_base=0x%08h count=2 stride=0x%08h comp_flags=0x%08h",
                entry_index,
                base,
                control_value,
                P19F_CMD_TAG,
                P17D_DESC_BASE,
                P17D_DESC_STRIDE,
                P19F_COMP_FLAGS),
            UVM_MEDIUM)
    end
    endtask

    task automatic p19f_program_sq_command_entry(
        input int unsigned entry_index,
        input logic [31:0] control_value,
        input logic [31:0] desc_base,
        input logic [31:0] desc_count,
        input logic [31:0] desc_stride,
        input logic [31:0] user_tag
    );
        int unsigned base;
    begin
        base = P19F_SQ_BASE + (entry_index * P19F_ENTRY_STRIDE);

        write_src_word_le(base + 16'h00, control_value);
        write_src_word_le(base + 16'h04, user_tag);
        write_src_word_le(base + 16'h08, desc_base);
        write_src_word_le(base + 16'h0C, desc_count);
        write_src_word_le(base + 16'h10, desc_stride);
        write_src_word_le(base + 16'h14, P19F_COMP_FLAGS);
        write_src_word_le(base + 16'h18, 32'h0000_0000);

        for (int unsigned w = 7; w < 16; w++) begin
            write_src_word_le(base + (w * 4), 32'h0000_0000);
        end

        `uvm_info("CODE_COV_C1_2G7_A2/SQ_VECTOR",
            $sformatf("Programmed SQ[%0d] control=0x%08h desc_base=0x%08h count=%0d stride=0x%08h tag=0x%08h",
                entry_index,
                control_value,
                desc_base,
                desc_count,
                desc_stride,
                user_tag),
            UVM_MEDIUM)
    end
    endtask

    task automatic p19f_expect_queue_reject(input string case_name,
                                            input int reject_bit,
                                            input logic [31:0] expected_detail,
                                            input bit expect_error_bit,
                                            input int error_bit);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] detail;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_DETAIL, detail);

            if (reject_status[reject_bit]) begin
                if (detail !== expected_detail) begin
                    `uvm_fatal("P19F_QUEUE/BAD_DETAIL",
                        $sformatf("%s expected detail=0x%08h got=0x%08h status=0x%08h done=0x%08h error=0x%08h reject=0x%08h",
                            case_name,
                            expected_detail,
                            detail,
                            status,
                            done_status,
                            error_status,
                            reject_status))
                end

                if (expect_error_bit && !error_status[error_bit]) begin
                    `uvm_fatal("P19F_QUEUE/MISSING_ERROR_BIT",
                        $sformatf("%s expected error_status[%0d] set, error=0x%08h reject=0x%08h",
                            case_name,
                            error_bit,
                            error_status,
                            reject_status))
                end

                `uvm_info("P19F_QUEUE/REJECT_PASS",
                    $sformatf("%s PASS: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h detail=0x%08h",
                        case_name,
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        detail),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > 40) begin
                `uvm_fatal("P19F_QUEUE/REJECT_TIMEOUT",
                    $sformatf("%s timed out waiting for reject bit %0d: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h detail=0x%08h",
                        case_name,
                        reject_bit,
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        detail))
            end
        end
    end
    endtask

    task automatic p19f_expect_queue_error(
        input string       case_name,
        input int          error_bit,
        input logic [31:0] expected_detail,
        input bit          expect_cmd_fetched,
        input bit          expect_cmd_validated
    );
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] detail;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_DETAIL, detail);

            if (error_status[error_bit]) begin
                if (detail !== expected_detail) begin
                    `uvm_fatal("CODE_COV_C1_2G7_A2/ERROR_DETAIL",
                        $sformatf("%s expected detail=0x%08h got=0x%08h status=0x%08h done=0x%08h error=0x%08h reject=0x%08h",
                            case_name,
                            expected_detail,
                            detail,
                            status,
                            done_status,
                            error_status,
                            reject_status))
                end

                if (reject_status != 32'h0000_0000) begin
                    `uvm_fatal("CODE_COV_C1_2G7_A2/UNEXPECTED_REJECT",
                        $sformatf("%s expected error-only disposition, reject=0x%08h",
                            case_name, reject_status))
                end

                if (done_status[Q_DONE_CMD_FETCHED] !== expect_cmd_fetched) begin
                    `uvm_fatal("CODE_COV_C1_2G7_A2/FETCHED_STATE",
                        $sformatf("%s expected CMD_FETCHED=%0d got done=0x%08h",
                            case_name, expect_cmd_fetched, done_status))
                end

                if (done_status[Q_DONE_CMD_VALIDATED] !== expect_cmd_validated) begin
                    `uvm_fatal("CODE_COV_C1_2G7_A2/VALIDATED_STATE",
                        $sformatf("%s expected CMD_VALIDATED=%0d got done=0x%08h",
                            case_name, expect_cmd_validated, done_status))
                end

                `uvm_info("CODE_COV_C1_2G7_A2/QUEUE_ERROR_PASS",
                    $sformatf("%s PASS: status=0x%08h done=0x%08h error=0x%08h detail=0x%08h",
                        case_name,
                        status,
                        done_status,
                        error_status,
                        detail),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > 160) begin
                `uvm_fatal("CODE_COV_C1_2G7_A2/ERROR_TIMEOUT",
                    $sformatf("%s timed out: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h detail=0x%08h",
                        case_name,
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        detail))
            end
        end
    end
    endtask

    task automatic p19f_case_hardware_owned_pointer_writes_ignored();
        logic [31:0] sq_head;
        logic [31:0] cq_tail;
        logic [31:0] error_status;
        logic [31:0] reject_status;
    begin
        p19f_program_base_queue(32'd0, 32'd0,
                                32'(P19F_QUEUE_DEPTH), 32'(P19F_QUEUE_DEPTH),
                                32'h0000_0005);

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, 32'h0000_0005);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL, 32'h0000_0007);
        repeat (3) @(posedge csr_vif.clk);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL, cq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);

        if ((sq_head != 32'h0000_0000) || (cq_tail != 32'h0000_0000) ||
            (error_status != 32'h0000_0000) || (reject_status != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1_2G7_A1/RO_POINTER",
                $sformatf("Hardware-owned pointer write policy failed: SQ_HEAD=0x%08h CQ_TAIL=0x%08h error=0x%08h reject=0x%08h",
                    sq_head, cq_tail, error_status, reject_status))
        end

        `uvm_info("CODE_COV_C1_2G7_A1/RO_POINTER_PASS",
            "Host writes to hardware-owned SQ_HEAD and CQ_TAIL were ignored with no sticky error",
            UVM_MEDIUM)
    end
    endtask

    task automatic p19f_case_disabled_reject();
    begin
        p19f_program_base_queue(32'd1, 32'd0,
                                32'(P19F_QUEUE_DEPTH), 32'(P19F_QUEUE_DEPTH),
                                32'h0000_0000);
        p19f_start_queue();
        p19f_expect_queue_reject("disabled queue reject",
                                  Q_REJ_QUEUE_DISABLED,
                                  ERR_DISABLED,
                                  1'b0,
                                  0);
        p19f_direct_queue_reject_clear("disabled queue reject");
        p19f_clear_queue_sticky_and_wait_idle();
    end
    endtask

    task automatic p19f_case_invalid_cfg_reject();
        logic [31:0] cmd;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        int unsigned cnt;
    begin
        p19f_program_base_queue(32'd1, 32'd0,
                                32'(P19F_QUEUE_DEPTH), 32'(P19F_QUEUE_DEPTH),
                                32'h0000_0005);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, 32'h0000_0020);
        p19f_start_queue();
        p19f_expect_queue_reject("invalid config reject",
                                  Q_REJ_INVALID_CFG,
                                  ERR_INVALID_CFG,
                                  1'b0,
                                  0);

        // START_QUEUE without clearing the existing queue error/reject state
        // must be rejected at the CSR acceptance boundary with sticky bit 4.
        p19f_start_queue();
        p19f_expect_queue_reject("sticky-error START_QUEUE reject",
                                  Q_REJ_STICKY_ERROR,
                                  ERR_INVALID_CFG,
                                  1'b0,
                                  0);
        // Repair the idle configuration and empty the SQ, then prove that
        // CLEAR_QUEUE_ERROR + START_QUEUE in one write is serialized into
        // a clean restart after the Q_ERROR state is cleared.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, 32'(P19F_ENTRY_STRIDE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL, 32'h0000_0000);
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_CLEAR_ERROR] = 1'b1;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_START]       = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_COMMAND, cmd);

        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
            if (done_status[Q_DONE_DRAINED]) begin
                if ((error_status != 32'h0000_0000) || (reject_status != 32'h0000_0000)) begin
                    `uvm_fatal("CODE_COV_C1_2G7_A1/CLEAR_START_STATUS",
                        $sformatf("Combined clear+start drained with sticky status still set: done=0x%08h error=0x%08h reject=0x%08h",
                            done_status, error_status, reject_status))
                end
                break;
            end
            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > 40) begin
                `uvm_fatal("CODE_COV_C1_2G7_A1/CLEAR_START_TIMEOUT",
                    $sformatf("Timed out waiting for combined clear+start empty drain: done=0x%08h error=0x%08h reject=0x%08h",
                        done_status, error_status, reject_status))
            end
        end

        `uvm_info("CODE_COV_C1_2G7_A1/CLEAR_START_RESTART_PASS",
            "Combined CLEAR_QUEUE_ERROR + START_QUEUE cleared sticky status and restarted from Q_IDLE",
            UVM_MEDIUM)
        p19f_direct_queue_done_clear("combined clear+start empty restart");
        p19f_clear_queue_sticky_and_wait_idle();
    end
    endtask

    task automatic p19f_case_empty_drained();
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        int unsigned cnt;
    begin
        p19f_program_base_queue(32'd0, 32'd0,
                                32'(P19F_QUEUE_DEPTH), 32'(P19F_QUEUE_DEPTH),
                                32'h0000_0005);
        p19f_start_queue();

        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);

            if ((error_status != 32'h0000_0000) || (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P19F_QUEUE/EMPTY_ERROR",
                    $sformatf("Empty queue should drain without error: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status))
            end

            if (done_status[Q_DONE_DRAINED]) begin
                if (done_status[Q_DONE_CMD_FETCHED] || done_status[Q_DONE_CMD_VALIDATED]) begin
                    `uvm_fatal("P19F_QUEUE/EMPTY_FETCHED",
                        $sformatf("Empty queue unexpectedly fetched command: done=0x%08h", done_status))
                end

                `uvm_info("P19F_QUEUE/EMPTY_PASS",
                    $sformatf("empty SQ drain PASS: status=0x%08h done=0x%08h", status, done_status),
                    UVM_MEDIUM)
                p19f_direct_queue_done_clear("empty SQ drained");
                p19f_clear_queue_sticky_and_wait_idle();
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > 40) begin
                `uvm_fatal("P19F_QUEUE/EMPTY_TIMEOUT",
                    $sformatf("Timed out waiting for empty queue drain: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status))
            end
        end
    end
    endtask

    task automatic p19f_case_bad_pointer_reject();
    begin
        // SQ occupancy = SQ_TAIL - SQ_HEAD = 3, but SQ_DEPTH = 2.
        p19f_program_base_queue(32'd3, 32'd0,
                                32'd2, 32'(P19F_QUEUE_DEPTH),
                                32'h0000_0005);
        p19f_start_queue();
        p19f_expect_queue_reject("bad SQ pointer reject",
                                  Q_REJ_INVALID_CFG,
                                  ERR_BAD_POINTER,
                                  1'b1,
                                  Q_ERR_BAD_POINTER);
        p19f_direct_queue_error_clear("bad SQ pointer reject");
        p19f_clear_queue_sticky_and_wait_idle();

        // CQ occupancy underflows because host CQ_HEAD=1 while hardware CQ_TAIL=0.
        p19f_program_base_queue(32'd1, 32'd1,
                                32'(P19F_QUEUE_DEPTH), 32'd2,
                                32'h0000_0005);
        p19f_start_queue();
        p19f_expect_queue_reject("bad CQ pointer reject",
                                  Q_REJ_INVALID_CFG,
                                  ERR_BAD_POINTER,
                                  1'b1,
                                  Q_ERR_BAD_POINTER);
        p19f_clear_queue_sticky_and_wait_idle();
    end
    endtask

    task automatic p19f_run_validation_error_vector(
        input string       case_name,
        input logic [31:0] control_value,
        input logic [31:0] desc_base,
        input logic [31:0] desc_count,
        input logic [31:0] desc_stride,
        input logic [31:0] expected_detail,
        input logic [31:0] user_tag
    );
    begin
        p19f_clear_queue_sticky_and_wait_idle();
        p19f_program_sq_command_entry(
            0,
            control_value,
            desc_base,
            desc_count,
            desc_stride,
            user_tag
        );
        p19f_program_base_queue(
            32'd1,
            32'd0,
            32'(P19F_QUEUE_DEPTH),
            32'(P19F_QUEUE_DEPTH),
            32'h0000_0005
        );
        p19f_start_queue();
        p19f_expect_queue_error(
            case_name,
            Q_ERR_CMD_VALIDATION,
            expected_detail,
            1'b1,
            1'b0
        );
        p19f_direct_queue_error_clear(case_name);
        p19f_clear_queue_sticky_and_wait_idle();
    end
    endtask

    task automatic p19f_case_validation_error_matrix();
    begin
        p19f_run_validation_error_vector(
            "bad opcode",
            32'h0000_0105,
            32'(P17D_DESC_BASE),
            32'h0000_0002,
            32'(P17D_DESC_STRIDE),
            ERR_CMD_BAD_OPCODE,
            32'hD19F_A201
        );

        p19f_run_validation_error_vector(
            "completion disabled",
            32'h0000_0003,
            32'(P17D_DESC_BASE),
            32'h0000_0002,
            32'(P17D_DESC_STRIDE),
            ERR_CMD_NO_COMPLETION,
            32'hD19F_A202
        );

        p19f_run_validation_error_vector(
            "reserved control bits",
            32'h0000_0503,
            32'(P17D_DESC_BASE),
            32'h0000_0002,
            32'(P17D_DESC_STRIDE),
            ERR_CMD_RSVD_BITS,
            32'hD19F_A203
        );

        p19f_run_validation_error_vector(
            "unaligned descriptor base",
            P19F_CMD_CONTROL_CONTINUE,
            32'(P17D_DESC_BASE + 4),
            32'h0000_0002,
            32'(P17D_DESC_STRIDE),
            ERR_CMD_DESC_UNALIGNED,
            32'hD19F_A204
        );

        p19f_run_validation_error_vector(
            "descriptor count range",
            P19F_CMD_CONTROL_CONTINUE,
            32'(P17D_DESC_BASE),
            32'h0000_0005,
            32'(P17D_DESC_STRIDE),
            ERR_CMD_DESC_COUNT_RANGE,
            32'hD19F_A205
        );

        p19f_run_validation_error_vector(
            "unaligned descriptor stride",
            P19F_CMD_CONTROL_CONTINUE,
            32'(P17D_DESC_BASE),
            32'h0000_0002,
            32'h0000_0084,
            ERR_CMD_STRIDE_UNALIGNED,
            32'hD19F_A206
        );

        `uvm_info("CODE_COV_C1_2G7_A2/VALIDATION_MATRIX_PASS",
            "Six current-source SQ command validation miss vectors PASS",
            UVM_MEDIUM)
    end
    endtask

    task automatic p19f_run_cmd_protocol_fault(
        input string       case_name,
        input int unsigned fault_kind,
        input int signed   beat_index,
        input logic [31:0] expected_detail
    );
    begin
        p17d_ctrl_vif.cmd_src_clear_faults();

        case (fault_kind)
            0: p17d_ctrl_vif.cmd_src_set_rresp_error(1'b1, beat_index);
            1: p17d_ctrl_vif.cmd_src_set_early_rlast(1'b1, beat_index);
            2: p17d_ctrl_vif.cmd_src_set_missing_rlast(1'b1, beat_index);
            default: begin
                `uvm_fatal("CODE_COV_C1_2G7_A2/BAD_FAULT_KIND",
                    $sformatf("%s unsupported command-source fault kind=%0d",
                        case_name, fault_kind))
            end
        endcase

        p19f_clear_queue_sticky_and_wait_idle();
        p19f_program_valid_sq_command_entry(0, P19F_CMD_CONTROL_CONTINUE);
        p19f_program_base_queue(
            32'd1,
            32'd0,
            32'(P19F_QUEUE_DEPTH),
            32'(P19F_QUEUE_DEPTH),
            32'h0000_0005
        );
        p19f_start_queue();
        p19f_expect_queue_error(
            case_name,
            Q_ERR_CMD_FETCH,
            expected_detail,
            1'b0,
            1'b0
        );

        p17d_ctrl_vif.cmd_src_clear_faults();
        repeat (3) @(posedge csr_vif.clk);
        p19f_direct_queue_error_clear(case_name);
        p19f_clear_queue_sticky_and_wait_idle();
    end
    endtask

    task automatic p19f_case_command_protocol_error_matrix();
    begin
        p19f_run_cmd_protocol_fault(
            "command RRESP error",
            0,
            2,
            ERR_AR_RRESP
        );
        p19f_run_cmd_protocol_fault(
            "command early RLAST",
            1,
            2,
            ERR_AR_EARLY_RLAST
        );
        p19f_run_cmd_protocol_fault(
            "command missing final RLAST",
            2,
            7,
            ERR_AR_MISSING_RLAST
        );

        p17d_ctrl_vif.cmd_src_clear_faults();

        `uvm_info("CODE_COV_C1_2G7_A2/CMD_PROTOCOL_MATRIX_PASS",
            "Command-source RRESP, early-RLAST, and missing-final-RLAST vectors PASS",
            UVM_MEDIUM)
    end
    endtask

    task automatic p19f_prepare_cq_full_hold();
    begin
        p19f_clear_queue_sticky_and_wait_idle();
        csr_desc_fetch_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();

        p19f_program_valid_sq_command_entry(0, P19F_CMD_CONTROL_CONTINUE);
        p19f_program_valid_sq_command_entry(1, P19F_CMD_CONTROL_STOP);

        p19f_program_base_queue(
            32'd2,
            32'd0,
            32'(P19F_QUEUE_DEPTH),
            32'd1,
            32'h0000_0007
        );
        p19f_start_queue();
        p19f_wait_cq_full_stall(done_timeout_cycles * 4);
    end
    endtask

    task automatic p19f_case_disable_during_check_ready();
    begin
        p19f_prepare_cq_full_hold();

        // QUEUE_CONTROL is intentionally live while queue ownership is
        // active.  Clear ENABLE while the controller is held in
        // Q_CHECK_READY by a real CQ-full condition.
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_CONTROL,
            32'h0000_0006
        );

        p19f_expect_queue_reject(
            "Q_CHECK_READY queue disable",
            Q_REJ_QUEUE_DISABLED,
            ERR_DISABLED,
            1'b0,
            0
        );

        p19f_direct_queue_reject_clear("Q_CHECK_READY queue disable");
        p19f_clear_queue_sticky_and_wait_idle();

        `uvm_info("CODE_COV_C1_2G7_A2/CHECK_READY_DISABLE_PASS",
            "Q_CHECK_READY live queue-disable revalidation PASS",
            UVM_MEDIUM)
    end
    endtask

    task automatic p19f_case_bad_live_pointer_during_check_ready();
    begin
        p19f_prepare_cq_full_hold();

        // At this boundary SQ_HEAD=1 and SQ_DEPTH=4.  Publishing SQ_TAIL=6
        // creates live occupancy 5 and must be rejected by the
        // Q_CHECK_READY pointer revalidation path.
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,
            32'h0000_0006
        );

        p19f_expect_queue_reject(
            "Q_CHECK_READY bad live SQ pointer",
            Q_REJ_INVALID_CFG,
            ERR_BAD_POINTER,
            1'b1,
            Q_ERR_BAD_POINTER
        );

        p19f_direct_queue_error_clear("Q_CHECK_READY bad live SQ pointer");
        p19f_clear_queue_sticky_and_wait_idle();

        `uvm_info("CODE_COV_C1_2G7_A2/CHECK_READY_POINTER_PASS",
            "Q_CHECK_READY live pointer corruption detection PASS",
            UVM_MEDIUM)
    end
    endtask

    task automatic p19f_wait_one_completion_epoch(
        input int unsigned timeout_cycles
    );
        logic [31:0] status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] sq_head;
        logic [31:0] cq_tail;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL, cq_tail);

            if ((error_status != 32'h0000_0000) ||
                (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("CODE_COV_C1_2G7_A2/RUN_UNTIL_ERROR",
                    $sformatf("RUN_UNTIL_EMPTY no-stop-on-error flow failed: status=0x%08h error=0x%08h reject=0x%08h SQ_HEAD=%0d CQ_TAIL=%0d",
                        status, error_status, reject_status, sq_head, cq_tail))
            end

            if ((sq_head == 32'h0000_0001) &&
                (cq_tail == 32'h0000_0001)) begin
                `uvm_info("CODE_COV_C1_2G7_A2/RUN_UNTIL_EMPTY_PASS",
                    $sformatf("RUN_UNTIL_EMPTY with STOP_ON_ERROR=0 completed: status=0x%08h SQ_HEAD=%0d CQ_TAIL=%0d",
                        status, sq_head, cq_tail),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1_2G7_A2/RUN_UNTIL_TIMEOUT",
                    $sformatf("Timed out waiting for one completion epoch: status=0x%08h error=0x%08h reject=0x%08h SQ_HEAD=%0d CQ_TAIL=%0d",
                        status, error_status, reject_status, sq_head, cq_tail))
            end
        end
    end
    endtask

    task automatic p19f_case_run_until_empty_without_stop_on_error();
    begin
        p19f_clear_queue_sticky_and_wait_idle();
        csr_desc_fetch_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();

        p19f_program_valid_sq_command_entry(0, P19F_CMD_CONTROL_CONTINUE);
        p19f_program_base_queue(
            32'd1,
            32'd0,
            32'(P19F_QUEUE_DEPTH),
            32'(P19F_QUEUE_DEPTH),
            32'h0000_0003
        );
        p19f_start_queue();
        p19f_wait_one_completion_epoch(done_timeout_cycles * 4);

        p19f_clear_queue_sticky_and_wait_idle();
        csr_desc_fetch_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();

        `uvm_info("CODE_COV_C1_2G7_A2/PRESENT_TRUE_PATH_PASS",
            "Q_PRESENT RUN_UNTIL_EMPTY && !STOP_AFTER && !REJECT && !STOP_ON_ERROR path PASS",
            UVM_MEDIUM)
    end
    endtask

    task automatic p19f_wait_cq_full_stall(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] state;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] error_detail;
        logic [31:0] last_tag;
        logic [31:0] sq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
        int unsigned cnt;
        bit ownership_seen;
    begin
        cnt = 0;
        ownership_seen = 1'b0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATE, state);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_DETAIL, error_detail);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL, cq_tail);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);

            if (status[0]) begin
                ownership_seen = 1'b1;
            end else if (ownership_seen && !status[4]) begin
                `uvm_fatal("CODE_COV_C1_2G7_A1/OWNERSHIP_GAP",
                    $sformatf("CSR-visible queue ownership dropped before automatic CQ-full boundary: status=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h",
                        status, sq_head, cq_tail))
            end

            if ((error_status != 32'h0000_0000) || (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P19F_QUEUE/FULL_ERROR",
                    $sformatf("Natural CQ full should stall, not reject: status=0x%08h state=0x%08h done=0x%08h error=0x%08h reject=0x%08h detail=0x%08h last_tag=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h",
                        status, state, done_status, error_status, reject_status, error_detail, last_tag,
                        sq_head, cq_tail, cq_occ))
            end

            if (status[4] && (sq_head == 32'h0000_0001) &&
                (cq_tail == 32'h0000_0001) && (cq_occ == 32'h0000_0001)) begin
                if (!status[0] || (status[11:8] != 4'h0)) begin
                    `uvm_fatal("P19F_QUEUE/FULL_OWNER",
                        $sformatf("Expected queue-only CQ-full ownership window: status=0x%08h", status))
                end

                `uvm_info("P19F_QUEUE/FULL_STALL_PASS",
                    $sformatf("Natural CQ-full stall observed after first completion: status=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h",
                        status, sq_head, cq_tail, cq_occ),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P19F_QUEUE/FULL_TIMEOUT",
                    $sformatf("Timed out waiting for natural CQ-full stall: status=0x%08h state=0x%08h done=0x%08h error=0x%08h reject=0x%08h detail=0x%08h last_tag=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h",
                        status, state, done_status, error_status, reject_status, error_detail, last_tag,
                        sq_head, cq_tail, cq_occ))
            end
        end
    end
    endtask

    task automatic p19f_poll_queue_validated(input int unsigned timeout_cycles);
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

            if ((error_status != 32'h0000_0000) || (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P19F_QUEUE/ERROR",
                    $sformatf("Queue command failed: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status))
            end

            if (done_status[Q_DONE_CMD_VALIDATED]) begin
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);
                if (last_tag !== P19F_CMD_TAG) begin
                    `uvm_fatal("P19F_QUEUE/BAD_TAG",
                        $sformatf("Expected last command tag=0x%08h got=0x%08h", P19F_CMD_TAG, last_tag))
                end

                `uvm_info("P19F_QUEUE/VALIDATED",
                    $sformatf("Queue command fetched/validated after CQ space recovery: status=0x%08h done=0x%08h tag=0x%08h",
                        status,
                        done_status,
                        last_tag),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P19F_QUEUE/TIMEOUT",
                    $sformatf("Timed out waiting for queue command validated: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status))
            end
        end
    end
    endtask

    task automatic c1_2d5_a1_expect_manual_job_reject_while_queue_busy();
        logic [31:0] queue_status_before;
        logic [31:0] queue_status_after;
        logic [31:0] job_status_before;
        logic [31:0] job_status_after;
        logic [31:0] job_done_status;
        logic [31:0] job_error_status;
        logic [31:0] job_reject_status;
        logic [31:0] job_state;
        logic [31:0] expected_reject;
    begin
        expected_reject = 32'h0000_0000;
        expected_reject[ai_accel_csr_access_helper::JOB_REJ_MANUAL_CMD] = 1'b1;

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_STATUS,
            queue_status_before
        );
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_STATUS,
            job_status_before
        );

        if (!queue_status_before[0] || !queue_status_before[4]) begin
            `uvm_fatal("CODE_COV_C1_2D5_A1/QUEUE_WINDOW",
                $sformatf("Expected queue_busy + CQ-full stall before manual START_JOB: queue_status=0x%08h",
                    queue_status_before))
        end

        // Bits [11:8] mirror descriptor-fetch, recipe, job, and P14
        // micro-op activity. Keep all lower owners idle so queue_busy is
        // the unique reason the manual P15 command must be rejected.
        if (queue_status_before[11:8] != 4'h0) begin
            `uvm_fatal("CODE_COV_C1_2D5_A1/LOWER_OWNER_ACTIVE",
                $sformatf("Expected lower stack idle during CQ-full ownership probe: queue_status=0x%08h",
                    queue_status_before))
        end

        if (job_status_before[0] || job_status_before[3]) begin
            `uvm_fatal("CODE_COV_C1_2D5_A1/JOB_READY_POLICY",
                $sformatf("Expected JOB_BUSY=0 and JOB_ACCEPT_READY=0 while queue owns stack: job_status=0x%08h queue_status=0x%08h",
                    job_status_before,
                    queue_status_before))
        end

        csr_start_job();
        repeat (3) @(posedge csr_vif.clk);

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_STATUS,
            queue_status_after
        );
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_STATUS,
            job_status_after
        );
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_DONE_STATUS,
            job_done_status
        );
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_ERROR_STATUS,
            job_error_status
        );
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS,
            job_reject_status
        );
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_STATE,
            job_state
        );

        if (job_reject_status !== expected_reject) begin
            `uvm_fatal("CODE_COV_C1_2D5_A1/REJECT_MISMATCH",
                $sformatf("Expected exact queue-owner manual-job reject=0x%08h actual=0x%08h job_status=0x%08h state=0x%08h",
                    expected_reject,
                    job_reject_status,
                    job_status_after,
                    job_state))
        end

        if (job_status_after[0] ||
            (job_state[3:0] != 4'h0) ||
            (job_done_status != 32'h0000_0000) ||
            (job_error_status != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1_2D5_A1/MANUAL_JOB_STARTED",
                $sformatf("Manual P15 job was not fully blocked: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h state=0x%08h",
                    job_status_after,
                    job_done_status,
                    job_error_status,
                    job_reject_status,
                    job_state))
        end

        if (!queue_status_after[0] || !queue_status_after[4]) begin
            `uvm_fatal("CODE_COV_C1_2D5_A1/QUEUE_DISTURBED",
                $sformatf("Rejected manual job disturbed queue CQ-full ownership: before=0x%08h after=0x%08h",
                    queue_status_before,
                    queue_status_after))
        end

        `uvm_info("CODE_COV_C1_2D5_A1/QUEUE_BUSY_REJECT_PASS",
            $sformatf("queue_busy uniquely blocked manual P15 START_JOB: queue_status=0x%08h job_status=0x%08h reject=0x%08h state=0x%08h",
                queue_status_after,
                job_status_after,
                job_reject_status,
                job_state),
            UVM_MEDIUM)

        csr_job_clear_sticky_status();
        repeat (3) @(posedge csr_vif.clk);
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS,
            job_reject_status
        );
        if (job_reject_status != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1_2D5_A1/REJECT_CLEAR",
                $sformatf("Failed to clear queue-owner manual-job reject: 0x%08h",
                    job_reject_status))
        end
    end
    endtask

    task automatic p19f_expect_cq_full_ownership(input string tag);
        logic [31:0] queue_status;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, queue_status);
        if (!queue_status[0] || !queue_status[4] || (queue_status[11:8] != 4'h0)) begin
            `uvm_fatal("CODE_COV_C1_2G7_A1/CQ_FULL_OWNER",
                $sformatf("%s: expected queue_busy + CQ-full with lower stack idle, status=0x%08h",
                    tag, queue_status))
        end
    end
    endtask

    task automatic p19f_probe_busy_config_write_policy();
        logic [31:0] sq_base_before;
        logic [31:0] sq_depth_before;
        logic [31:0] sq_stride_before;
        logic [31:0] cq_base_before;
        logic [31:0] cq_depth_before;
        logic [31:0] cq_stride_before;
        logic [31:0] value_after;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] expected_error;
        logic [31:0] expected_reject;
    begin
        p19f_expect_cq_full_ownership("before busy config-write policy probe");

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE, sq_base_before);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH, sq_depth_before);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, sq_stride_before);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE, cq_base_before);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH, cq_depth_before);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, cq_stride_before);

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE,   sq_base_before + 32'h0000_1000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH,  sq_depth_before + 32'h0000_0004);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, sq_stride_before + 32'h0000_0040);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE,   cq_base_before + 32'h0000_1000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH,  cq_depth_before + 32'h0000_0001);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, cq_stride_before + 32'h0000_0040);
        repeat (3) @(posedge csr_vif.clk);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE, value_after);
        if (value_after !== sq_base_before) begin
            `uvm_fatal("CODE_COV_C1_2G7_A1/SQ_BASE_MUTATED", "SQ_BASE changed while queue busy")
        end
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH, value_after);
        if (value_after !== sq_depth_before) begin
            `uvm_fatal("CODE_COV_C1_2G7_A1/SQ_DEPTH_MUTATED", "SQ_DEPTH changed while queue busy")
        end
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, value_after);
        if (value_after !== sq_stride_before) begin
            `uvm_fatal("CODE_COV_C1_2G7_A1/SQ_STRIDE_MUTATED", "SQ_STRIDE changed while queue busy")
        end
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE, value_after);
        if (value_after !== cq_base_before) begin
            `uvm_fatal("CODE_COV_C1_2G7_A1/CQ_BASE_MUTATED", "CQ_BASE changed while queue busy")
        end
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH, value_after);
        if (value_after !== cq_depth_before) begin
            `uvm_fatal("CODE_COV_C1_2G7_A1/CQ_DEPTH_MUTATED", "CQ_DEPTH changed while queue busy")
        end
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, value_after);
        if (value_after !== cq_stride_before) begin
            `uvm_fatal("CODE_COV_C1_2G7_A1/CQ_STRIDE_MUTATED", "CQ_STRIDE changed while queue busy")
        end

        expected_error = 32'h0000_0000;
        expected_error[Q_ERR_CONFIG_WRITE_BUSY] = 1'b1;
        expected_reject = 32'h0000_0000;
        expected_reject[Q_REJ_CONFIG_WRITE_BUSY] = 1'b1;
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
        if ((error_status !== expected_error) || (reject_status !== expected_reject)) begin
            `uvm_fatal("CODE_COV_C1_2G7_A1/CONFIG_BUSY_STATUS",
                $sformatf("Expected exact config-write-busy error/reject 0x%08h/0x%08h, got 0x%08h/0x%08h",
                    expected_error, expected_reject, error_status, reject_status))
        end

        `uvm_info("CODE_COV_C1_2G7_A1/BUSY_CONFIG_WRITE_PASS",
            "All six queue base/depth/stride writes were ignored while busy and exact bit7 error/reject was reported",
            UVM_MEDIUM)
        p19f_direct_queue_error_clear("busy queue config-write reject");
        p19f_expect_cq_full_ownership("after busy config-write status clear");
    end
    endtask

    task automatic p19f_probe_queue_command_policy_while_busy();
        logic [31:0] cmd;
        logic [31:0] reject_status;
        logic [31:0] expected_reject;
        logic [31:0] sq_head_before;
        logic [31:0] cq_tail_before;
        logic [31:0] sq_head_after;
        logic [31:0] cq_tail_after;
    begin
        p19f_expect_cq_full_ownership("before busy queue-command probes");

        p19f_start_queue();
        repeat (3) @(posedge csr_vif.clk);
        expected_reject = 32'h0000_0000;
        expected_reject[Q_REJ_QUEUE_BUSY] = 1'b1;
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
        if (reject_status !== expected_reject) begin
            `uvm_fatal("CODE_COV_C1_2G7_A1/START_BUSY_REJECT",
                $sformatf("Expected exact START_QUEUE busy reject=0x%08h got=0x%08h",
                    expected_reject, reject_status))
        end
        p19f_direct_queue_reject_clear("START_QUEUE while queue busy");

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head_before);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL, cq_tail_before);
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_RESET_POINTERS] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_COMMAND, cmd);
        repeat (3) @(posedge csr_vif.clk);
        expected_reject = 32'h0000_0000;
        expected_reject[Q_REJ_RESET_POINTERS_BUSY] = 1'b1;
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head_after);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL, cq_tail_after);
        if ((reject_status !== expected_reject) ||
            (sq_head_after !== sq_head_before) || (cq_tail_after !== cq_tail_before)) begin
            `uvm_fatal("CODE_COV_C1_2G7_A1/RESET_BUSY_REJECT",
                $sformatf("RESET_POINTERS busy policy failed: reject=0x%08h expected=0x%08h SQ_HEAD 0x%08h->0x%08h CQ_TAIL 0x%08h->0x%08h",
                    reject_status, expected_reject,
                    sq_head_before, sq_head_after, cq_tail_before, cq_tail_after))
        end
        p19f_direct_queue_reject_clear("RESET_QUEUE_POINTERS while queue busy");

        `uvm_info("CODE_COV_C1_2G7_A1/BUSY_QUEUE_COMMAND_PASS",
            "START_QUEUE and RESET_QUEUE_POINTERS were rejected while queue busy without disturbing hardware pointers",
            UVM_MEDIUM)
        p19f_expect_cq_full_ownership("after busy queue-command probes");
    end
    endtask

    task automatic p19f_probe_manual_lower_stack_ownership();
        logic [31:0] cmd;
        logic [31:0] status;
        logic [31:0] reject_status;
        logic [31:0] expected_reject;
    begin
        p19f_expect_cq_full_ownership("before manual lower-stack ownership probes");

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        repeat (3) @(posedge csr_vif.clk);

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_START_GEMM] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMMAND, cmd);
        repeat (3) @(posedge csr_vif.clk);
        expected_reject = 32'h0000_0000;
        expected_reject[P14_REJ_QUEUE_OWNER] = 1'b1;
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);
        if (reject_status !== expected_reject) begin
            `uvm_fatal("CODE_COV_C1_2G7_A1/P14_OWNER",
                $sformatf("Expected exact P14 queue-owner reject=0x%08h got=0x%08h",
                    expected_reject, reject_status))
        end
        csr_clear_sticky_status();

        c1_2d5_a1_expect_manual_job_reject_while_queue_busy();

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::RECIPE_CMD_START] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_COMMAND, cmd);
        repeat (3) @(posedge csr_vif.clk);
        expected_reject = 32'h0000_0000;
        expected_reject[P16_REJ_MANUAL_CMD] = 1'b1;
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS, reject_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_STATUS, status);
        if ((reject_status !== expected_reject) || status[0]) begin
            `uvm_fatal("CODE_COV_C1_2G7_A1/P16_OWNER",
                $sformatf("P16 queue-owner reject mismatch: status=0x%08h reject=0x%08h expected=0x%08h",
                    status, reject_status, expected_reject))
        end
        csr_recipe_clear_sticky_status();

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::DESC_FETCH_CMD_START] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_COMMAND, cmd);
        repeat (3) @(posedge csr_vif.clk);
        expected_reject = 32'h0000_0000;
        expected_reject[P17_REJ_BUSY] = 1'b1;
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_REJECT_STATUS, reject_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_STATUS, status);
        if ((reject_status !== expected_reject) || status[0]) begin
            `uvm_fatal("CODE_COV_C1_2G7_A1/P17_OWNER",
                $sformatf("P17 queue-owner reject mismatch: status=0x%08h reject=0x%08h expected=0x%08h",
                    status, reject_status, expected_reject))
        end
        csr_desc_fetch_clear_sticky_status();

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::COMP_WB_CMD_START] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_COMMAND, cmd);
        repeat (3) @(posedge csr_vif.clk);
        expected_reject = 32'h0000_0000;
        expected_reject[P18_REJ_ENGINE] = 1'b1;
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_REJECT_STATUS, reject_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_STATUS, status);
        if ((reject_status !== expected_reject) || status[0]) begin
            `uvm_fatal("CODE_COV_C1_2G7_A1/P18_OWNER",
                $sformatf("P18 queue-owner reject mismatch: status=0x%08h reject=0x%08h expected=0x%08h",
                    status, reject_status, expected_reject))
        end
        csr_completion_wb_clear_sticky_status();
        repeat (3) @(posedge csr_vif.clk);

        p19f_expect_cq_full_ownership("after manual lower-stack ownership probes");
        `uvm_info("CODE_COV_C1_2G7_A1/LOWER_STACK_OWNERSHIP_PASS",
            "Queue ownership blocked manual P14/P15/P16/P17/P18 starts while all lower engines remained idle",
            UVM_MEDIUM)
    end
    endtask

    task automatic p19f_wait_job_busy(input int unsigned timeout_cycles);
        logic [31:0] status;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_STATUS, status);
            if (status[0]) return;
            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1_2G7_A1/JOB_BUSY_TIMEOUT",
                    $sformatf("Timed out waiting for manual job busy, status=0x%08h", status))
            end
        end
    end
    endtask

    task automatic p19f_case_start_queue_underlying_busy(input ai_accel_subsys_seq_item profile_item);
    begin
        p19f_clear_queue_sticky_and_wait_idle();
        p19f_program_base_queue(32'd1, 32'd0,
                                32'(P19F_QUEUE_DEPTH), 32'(P19F_QUEUE_DEPTH),
                                32'h0000_0005);
        csr_job_clear_sticky_status();
        csr_start_job();
        p19f_wait_job_busy(done_timeout_cycles);

        p19f_start_queue();
        p19f_expect_queue_reject("START_QUEUE underlying-busy reject",
                                  Q_REJ_UNDERLYING_BUSY,
                                  ERR_UNDERLYING_BUSY,
                                  1'b0,
                                  0);

        csr_poll_job_done(done_timeout_cycles);
        csr_check_job_perf_snapshot(profile_item);
        p19f_direct_queue_reject_clear("START_QUEUE underlying-busy reject");
        p19f_clear_queue_sticky_and_wait_idle();
        csr_job_clear_sticky_status();

        `uvm_info("CODE_COV_C1_2G7_A1/UNDERLYING_BUSY_REJECT_PASS",
            "START_QUEUE was rejected with exact underlying-busy policy while a legal manual P15 job remained undisturbed",
            UVM_MEDIUM)
    end
    endtask

    task automatic p19f_case_cq_full_stall_then_recover(input ai_accel_subsys_seq_item profile_item);
    begin
        p19f_clear_queue_sticky_and_wait_idle();
        csr_desc_fetch_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();

        // Two SQ entries plus CQ depth 1 create a natural CQ-full boundary:
        // command 0 completes and advances hardware SQ_HEAD/CQ_TAIL to 1,
        // then command 1 remains pending in Q_CHECK_READY until the host
        // consumes the first CQ entry by advancing CQ_HEAD.
        p19f_program_base_queue(32'd2, 32'd0,
                                32'(P19F_QUEUE_DEPTH), 32'd1,
                                32'h0000_0007);
        p19f_start_queue();
        p19f_wait_cq_full_stall(done_timeout_cycles * 4);

        p19f_probe_busy_config_write_policy();
        p19f_probe_queue_command_policy_while_busy();
        p19f_probe_manual_lower_stack_ownership();

        // Remove first-command sticky evidence so all following polls prove
        // the second command executes only after CQ space is released.
        p19f_direct_queue_done_clear("first queue completion before CQ recovery");
        csr_desc_fetch_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        repeat (3) @(posedge csr_vif.clk);

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD, 32'h0000_0001);
        `uvm_info("P19F_QUEUE/FULL_RECOVER", "Advanced host-owned CSR_QUEUE_CQ_HEAD to free one CQ slot", UVM_MEDIUM)

        p19f_poll_queue_validated(done_timeout_cycles);
        csr_poll_desc_fetch_done(done_timeout_cycles);
        csr_poll_recipe_done(done_timeout_cycles * 2);
        csr_poll_completion_wb_done(done_timeout_cycles);
        csr_check_recipe_perf_snapshot(profile_item);

        repeat (5) @(posedge csr_vif.clk);
        check_queue_completion_record(profile_item);
        p19f_check_queue_pointers_after_recovered_completion();
    end
    endtask

    task automatic p19f_check_queue_pointers_after_recovered_completion();
        logic [31:0] sq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL, cq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);

        if (sq_head !== 32'h0000_0002) begin
            `uvm_fatal("P19F_QUEUE/BAD_SQ_HEAD",
                $sformatf("Expected SQ_HEAD=2 after two natural completions, got 0x%08h", sq_head))
        end

        if (cq_tail !== 32'h0000_0002) begin
            `uvm_fatal("P19F_QUEUE/BAD_CQ_TAIL",
                $sformatf("Expected CQ_TAIL=2 after recovered completion, got 0x%08h", cq_tail))
        end

        if (cq_occ !== 32'h0000_0001) begin
            `uvm_fatal("P19F_QUEUE/BAD_CQ_OCC",
                $sformatf("Expected CQ occupancy=1 after recovered completion, got 0x%08h", cq_occ))
        end

        `uvm_info("P19F_QUEUE/POINTERS",
            $sformatf("Recovered CQ full flow pointer check PASS: SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h",
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

        `uvm_info("P19F_QUEUE_REJECT_ERROR/START",
            "Starting P19F/G7-A1 policy retention plus G7-A2 reachable queue coverage reconciliation test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P19F_QUEUE_REJECT_ERROR/EXPECTED_SIZE",
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

        p19f_program_valid_sq_command_entry(0, P19F_CMD_CONTROL_CONTINUE);
        p19f_program_valid_sq_command_entry(1, P19F_CMD_CONTROL_STOP);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_program_completion_wb();

        p19f_case_hardware_owned_pointer_writes_ignored();
        p19f_case_disabled_reject();
        p19f_case_invalid_cfg_reject();
        p19f_case_empty_drained();
        p19f_case_bad_pointer_reject();

        // CODE-COV-C1.2-G7-A2 current-source reachable miss matrix.
        p19f_case_validation_error_matrix();
        p19f_case_command_protocol_error_matrix();
        p19f_case_disable_during_check_ready();
        p19f_case_bad_live_pointer_during_check_ready();
        p19f_case_run_until_empty_without_stop_on_error();

        csr_job_clear_sticky_status();
        csr_write_job_descriptor(
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );
        csr_check_job_idle_ready(
            "before G7-A1 underlying-busy and queue-active ownership probes"
        );

        p19f_case_start_queue_underlying_busy(profile_item);

        // Restore deterministic source/destination contents after the manual
        // underlying-busy retention job.  The preload helper may refresh the
        // shared backing memory, so re-establish the descriptor and SQ images
        // immediately before the natural two-command queue flow.
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

        p19f_program_valid_sq_command_entry(0, P19F_CMD_CONTROL_CONTINUE);
        p19f_program_valid_sq_command_entry(1, P19F_CMD_CONTROL_STOP);

        csr_write_job_descriptor(
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );
        p19f_case_cq_full_stall_then_recover(profile_item);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("CODE_COV_C1_2D5_A1/QUEUE_FLOW_RETENTION_PASS",
            "Queue command, automatic recipe, completion writeback, and result compare completed after rejected manual P15 launch",
            UVM_MEDIUM)

        // Release queue ownership, clear lower-level sticky state, then prove
        // that a normal manual P15 job is accepted again.
        p19f_clear_queue_sticky_and_wait_idle();
        csr_desc_fetch_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_job_clear_sticky_status();
        repeat (3) @(posedge csr_vif.clk);

        prepare_dma_source_and_destination(a_flat, b_flat);
        csr_write_job_descriptor(
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );
        csr_check_job_idle_ready(
            "after C1.2-D5-A1 queue ownership release"
        );
        csr_start_job();
        csr_poll_job_done(done_timeout_cycles);
        csr_check_job_perf_snapshot(profile_item);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("CODE_COV_C1_2D5_A1/MANUAL_JOB_RECOVERY_PASS",
            "Manual P15 job completed after queue ownership ended",
            UVM_MEDIUM)

        `uvm_info("CODE_COV_C1_2D5_A1/SUITE_PASS",
            "Queue-active manual P15 ownership guard and post-queue recovery PASS",
            UVM_MEDIUM)

        `uvm_info("CODE_COV_C1_2G7_A1/SUITE_PASS",
            "Queue acceptance, configuration locking, pointer ownership, lower-stack ownership, and recovery policy PASS",
            UVM_MEDIUM)

        `uvm_info("P19F_QUEUE_REJECT_ERROR/PASS",
            $sformatf("P19F queue policy plus G7-A2 validation/protocol/revalidation coverage completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
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
