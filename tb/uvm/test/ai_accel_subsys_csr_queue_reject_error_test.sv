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
//   - Validates CQ-full stall and recovery by host CQ_HEAD update.
//   - After CQ-full recovery, reuses the P19E end-to-end flow and
//     confirms the completion record is written into the CQ slot.
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

    localparam logic [31:0] P19F_CMD_CONTROL  = 32'h0000_0303;
    localparam logic [31:0] P19F_CMD_TAG      = 32'hD19F_0000;
    localparam logic [31:0] P19F_COMP_FLAGS   = 32'h0000_0001;

    localparam int Q_DONE_DRAINED             = 1;
    localparam int Q_DONE_CMD_FETCHED         = 2;
    localparam int Q_DONE_CMD_VALIDATED       = 3;

    localparam int Q_REJ_QUEUE_DISABLED       = 1;
    localparam int Q_REJ_INVALID_CFG          = 2;
    localparam int Q_REJ_BAD_POINTER          = 3;

    localparam int Q_ERR_BAD_POINTER          = 3;

    localparam logic [31:0] ERR_DISABLED      = 32'h0000_0001;
    localparam logic [31:0] ERR_INVALID_CFG   = 32'h0000_0002;
    localparam logic [31:0] ERR_BAD_POINTER   = 32'h0000_0003;

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

    task automatic p19f_program_base_queue(input logic [31:0] sq_head,
                                           input logic [31:0] sq_tail,
                                           input logic [31:0] cq_head,
                                           input logic [31:0] cq_tail,
                                           input logic [31:0] sq_depth,
                                           input logic [31:0] cq_depth,
                                           input logic [31:0] control_value);
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE,   32'(P19F_SQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH,  sq_depth);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,   sq_head);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,   sq_tail);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, 32'(P19F_ENTRY_STRIDE));

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE,   32'(P19F_CQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH,  cq_depth);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,   cq_head);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,   cq_tail);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, 32'(P19F_ENTRY_STRIDE));

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CONTROL, control_value);
    end
    endtask

    task automatic p19f_program_valid_sq_command_entry();
        int unsigned base;
    begin
        base = P19F_SQ_BASE;

        write_src_word_le(base + 16'h00, P19F_CMD_CONTROL);
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
            $sformatf("Programmed valid SQ command entry at 0x%08h control=0x%08h tag=0x%08h desc_base=0x%08h count=2 stride=0x%08h comp_flags=0x%08h",
                P19F_SQ_BASE,
                P19F_CMD_CONTROL,
                P19F_CMD_TAG,
                P17D_DESC_BASE,
                P17D_DESC_STRIDE,
                P19F_COMP_FLAGS),
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

    task automatic p19f_case_disabled_reject();
    begin
        p19f_program_base_queue(32'd0, 32'd1, 32'd0, 32'd0,
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
    begin
        p19f_program_base_queue(32'd0, 32'd1, 32'd0, 32'd0,
                                32'(P19F_QUEUE_DEPTH), 32'(P19F_QUEUE_DEPTH),
                                32'h0000_0005);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, 32'h0000_0020);
        p19f_start_queue();
        p19f_expect_queue_reject("invalid config reject",
                                  Q_REJ_INVALID_CFG,
                                  ERR_INVALID_CFG,
                                  1'b0,
                                  0);
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
        p19f_program_base_queue(32'd0, 32'd0, 32'd0, 32'd0,
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
        p19f_program_base_queue(32'd0, 32'd3, 32'd0, 32'd0,
                                32'd2, 32'(P19F_QUEUE_DEPTH),
                                32'h0000_0005);
        p19f_start_queue();
        p19f_expect_queue_reject("bad SQ pointer reject",
                                  Q_REJ_BAD_POINTER,
                                  ERR_BAD_POINTER,
                                  1'b1,
                                  Q_ERR_BAD_POINTER);
        p19f_direct_queue_error_clear("bad SQ pointer reject");
        p19f_clear_queue_sticky_and_wait_idle();

        // CQ occupancy = CQ_TAIL - CQ_HEAD = 3, but CQ_DEPTH = 2.
        p19f_program_base_queue(32'd0, 32'd1, 32'd0, 32'd3,
                                32'(P19F_QUEUE_DEPTH), 32'd2,
                                32'h0000_0005);
        p19f_start_queue();
        p19f_expect_queue_reject("bad CQ pointer reject",
                                  Q_REJ_BAD_POINTER,
                                  ERR_BAD_POINTER,
                                  1'b1,
                                  Q_ERR_BAD_POINTER);
        p19f_clear_queue_sticky_and_wait_idle();
    end
    endtask

    task automatic p19f_wait_cq_full_stall(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);

            if ((error_status != 32'h0000_0000) || (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P19F_QUEUE/FULL_ERROR",
                    $sformatf("CQ full should stall, not reject: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status))
            end

            if (status[4]) begin
                if (done_status[Q_DONE_CMD_FETCHED] || done_status[Q_DONE_CMD_VALIDATED]) begin
                    `uvm_fatal("P19F_QUEUE/FULL_FETCHED",
                        $sformatf("CQ full stall unexpectedly fetched command: status=0x%08h done=0x%08h",
                            status,
                            done_status))
                end

                `uvm_info("P19F_QUEUE/FULL_STALL_PASS",
                    $sformatf("CQ full stall observed: status=0x%08h done=0x%08h", status, done_status),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P19F_QUEUE/FULL_TIMEOUT",
                    $sformatf("Timed out waiting for CQ full stall: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status))
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

    task automatic p19f_case_cq_full_stall_then_recover(input ai_accel_subsys_seq_item profile_item);
    begin
        p19f_clear_queue_sticky_and_wait_idle();
        csr_desc_fetch_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();

        // CQ depth 1 and CQ_HEAD=0/CQ_TAIL=1 makes the CQ full.
        // After the stall is observed, the host advances CQ_HEAD to 1,
        // freeing exactly one CQ slot.  The same in-flight queue start
        // should then fetch and validate the SQ command.
        p19f_program_base_queue(32'd0, 32'd1, 32'd0, 32'd1,
                                32'(P19F_QUEUE_DEPTH), 32'd1,
                                32'h0000_0005);
        p19f_start_queue();
        p19f_wait_cq_full_stall(40);

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD, 32'h0000_0001);
        `uvm_info("P19F_QUEUE/FULL_RECOVER", "Advanced CSR_QUEUE_CQ_HEAD to free one CQ slot", UVM_MEDIUM)

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

        if (sq_head !== 32'h0000_0001) begin
            `uvm_fatal("P19F_QUEUE/BAD_SQ_HEAD",
                $sformatf("Expected SQ_HEAD=1 after recovered completion, got 0x%08h", sq_head))
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
            "Starting P19F queue reject / empty / full / bad-pointer handling test",
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

        p19f_program_valid_sq_command_entry();

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_program_completion_wb();

        p19f_case_disabled_reject();
        p19f_case_invalid_cfg_reject();
        p19f_case_empty_drained();
        p19f_case_bad_pointer_reject();
        p19f_case_cq_full_stall_then_recover(profile_item);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P19F_QUEUE_REJECT_ERROR/PASS",
            $sformatf("P19F queue reject/empty/full/bad-pointer handling completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
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

