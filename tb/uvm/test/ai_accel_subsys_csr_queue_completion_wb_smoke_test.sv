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
// P19E remains single-outstanding.  It does not add interrupts or
// multi-outstanding command execution.
//
// CODE-COV-C1.2-G7-Z4-B reuses the existing TB-only P18 BRESP fault
// injection interface to prove queue-owned completion-writeback error
// propagation, pointer non-commit behavior, sticky cleanup, and recovery.
// No RTL, BRAM, CSR-map, or standalone test flow changes are required.
//
// CODE-COV-C1.2-G7-Z4-C2-B adds legal queue-control timing probes for:
//   - completion commit while QUEUE_ENABLE is deasserted (line 1192),
//   - same-edge commit / QUEUE_ENABLE clear (line 1287), and
//   - same-edge commit / RUN_UNTIL_EMPTY clear (line 1287).
// The same-edge cases use the architectural AXI-Lite CSR bus; no force,
// deposit, hierarchical state mutation, or RTL modification is used.
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

    // CODE-COV-C1.2-G7-Z4-B queue-owned P18 error propagation target.
    localparam int unsigned G7_Z4_B_QUEUE_COMP_WB_ERROR_BIT = 4;
    localparam int unsigned G7_Z4_B_P18_BRESP_ERROR_BIT     = 0;

    // CODE-COV-C1.2-G7-Z4-C2-B control-window probes.
    // This probe intentionally varies only bit0 ENABLE and bit1 RUN_UNTIL_EMPTY.
    // It preserves the existing P19E test policy: STOP_ON_ERROR(bit2)=1 and bits3/4=0.
    localparam logic [31:0] G7_Z4_C2_B_CTRL_ENABLE_RUE      = 32'h0000_0007;
    localparam logic [31:0] G7_Z4_C2_B_CTRL_DISABLE_RUE     = 32'h0000_0006;
    localparam logic [31:0] G7_Z4_C2_B_CTRL_ENABLE_NO_RUE   = 32'h0000_0005;
    localparam logic [31:0] G7_Z4_C2_B_CTRL_DISABLE_NO_RUE  = 32'h0000_0004;

    // R1 stimulus correction: P19E_CMD_CONTROL=0x00000303 carries
    // STOP_AFTER_THIS.  Auto-continue coverage probes require the
    // architecturally normal continue-capable command form with that
    // bit clear, while preserving the remaining command policy bits.
    localparam logic [31:0] G7_Z4_C2_B_CMD_CONTROL_CONTINUE = 32'h0000_0103;

    localparam logic [31:0] G7_Z4_C2_B_TAG_ENABLE_AT_COMMIT = 32'hD19E_C2B1;
    localparam logic [31:0] G7_Z4_C2_B_TAG_ENABLE_COLLISION = 32'hD19E_C2B2;
    localparam logic [31:0] G7_Z4_C2_B_TAG_RUE_COLLISION    = 32'hD19E_C2B3;

    virtual comp_wb_inject_if comp_wb_inject_vif;

    function new(string name = "ai_accel_subsys_csr_queue_completion_wb_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual comp_wb_inject_if)::get(
                this, "", "comp_wb_inject_vif", comp_wb_inject_vif)) begin
            `uvm_fatal("G7_Z4_B/NO_COMP_WB_INJECT_VIF",
                "comp_wb_inject_vif not found in UVM config DB")
        end
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

    task automatic g7_z4b_poll_queue_owned_completion_wb_error(
        input int unsigned timeout_cycles
    );
        logic [31:0] comp_status;
        logic [31:0] comp_done_status;
        logic [31:0] comp_error_status;
        logic [31:0] comp_reject_status;
        logic [31:0] queue_status;
        logic [31:0] queue_error_status;
        logic [31:0] queue_reject_status;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_STATUS, comp_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_DONE_STATUS, comp_done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_ERROR_STATUS, comp_error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_REJECT_STATUS, comp_reject_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, queue_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, queue_error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, queue_reject_status);

            if (comp_reject_status != 32'h0000_0000) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_B/UNEXPECTED_P18_REJECT",
                    $sformatf("Queue-owned BRESP-error probe unexpectedly produced P18 reject: comp_status=0x%08h comp_error=0x%08h comp_reject=0x%08h queue_error=0x%08h queue_reject=0x%08h",
                        comp_status,
                        comp_error_status,
                        comp_reject_status,
                        queue_error_status,
                        queue_reject_status))
            end

            if (queue_reject_status != 32'h0000_0000) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_B/UNEXPECTED_QUEUE_REJECT",
                    $sformatf("Queue-owned BRESP-error probe unexpectedly produced queue reject: queue_status=0x%08h queue_error=0x%08h queue_reject=0x%08h comp_error=0x%08h",
                        queue_status,
                        queue_error_status,
                        queue_reject_status,
                        comp_error_status))
            end

            if (comp_error_status[G7_Z4_B_P18_BRESP_ERROR_BIT] &&
                queue_error_status[G7_Z4_B_QUEUE_COMP_WB_ERROR_BIT]) begin
                if ((comp_error_status & ~(32'h1 << G7_Z4_B_P18_BRESP_ERROR_BIT)) != 32'h0000_0000) begin
                    `uvm_fatal("CODE_COV_C1P2_G7_Z4_B/UNEXPECTED_P18_ERROR_BITS",
                        $sformatf("Expected only P18 BRESP error bit %0d, got comp_error=0x%08h",
                            G7_Z4_B_P18_BRESP_ERROR_BIT,
                            comp_error_status))
                end

                if ((queue_error_status & ~(32'h1 << G7_Z4_B_QUEUE_COMP_WB_ERROR_BIT)) != 32'h0000_0000) begin
                    `uvm_fatal("CODE_COV_C1P2_G7_Z4_B/UNEXPECTED_QUEUE_ERROR_BITS",
                        $sformatf("Expected only queue COMPLETION_WB_ERROR bit %0d, got queue_error=0x%08h",
                            G7_Z4_B_QUEUE_COMP_WB_ERROR_BIT,
                            queue_error_status))
                end

                if (comp_done_status != 32'h0000_0000) begin
                    `uvm_fatal("CODE_COV_C1P2_G7_Z4_B/UNEXPECTED_P18_DONE",
                        $sformatf("P18 DONE must remain clear on injected BRESP failure: done=0x%08h error=0x%08h",
                            comp_done_status,
                            comp_error_status))
                end

                `uvm_info("CODE_COV_C1P2_G7_Z4_B/ERROR_PROP_PASS",
                    $sformatf("Queue-owned P18 BRESP error propagated after %0d poll(s): comp_status=0x%08h comp_error=0x%08h queue_status=0x%08h queue_error=0x%08h",
                        cnt,
                        comp_status,
                        comp_error_status,
                        queue_status,
                        queue_error_status),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_B/ERROR_PROP_TIMEOUT",
                    $sformatf("Timed out waiting for queue-owned P18 BRESP error propagation: comp_status=0x%08h comp_done=0x%08h comp_error=0x%08h comp_reject=0x%08h queue_status=0x%08h queue_error=0x%08h queue_reject=0x%08h",
                        comp_status,
                        comp_done_status,
                        comp_error_status,
                        comp_reject_status,
                        queue_status,
                        queue_error_status,
                        queue_reject_status))
            end
        end
    end
    endtask

    task automatic g7_z4b_check_error_no_cq_commit();
        logic [31:0] sq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
        logic [31:0] commit_word;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL, cq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);
        commit_word = read_queue_comp_word(16'h00);

        if ((sq_head !== 32'h0000_0000) ||
            (cq_tail !== 32'h0000_0000) ||
            (cq_occ  !== 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_B/POINTER_COMMIT_ON_ERROR",
                $sformatf("Queue pointers must not advance on P18 error: SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h",
                    sq_head,
                    cq_tail,
                    cq_occ))
        end

        if (commit_word !== 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_B/CQ_COMMIT_ON_ERROR",
                $sformatf("CQ VALID/commit word must remain zero after first-beat BRESP failure, got 0x%08h",
                    commit_word))
        end

        `uvm_info("CODE_COV_C1P2_G7_Z4_B/NO_COMMIT_PASS",
            $sformatf("Injected P18 error suppressed CQ commit and pointer advance: SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h commit=0x%08h",
                sq_head,
                cq_tail,
                cq_occ,
                commit_word),
            UVM_MEDIUM)
    end
    endtask

    task automatic g7_z4b_verify_cleanup();
        logic [31:0] comp_error_status;
        logic [31:0] comp_reject_status;
        logic [31:0] queue_error_status;
        logic [31:0] queue_reject_status;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_ERROR_STATUS, comp_error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_REJECT_STATUS, comp_reject_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, queue_error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, queue_reject_status);

        if ((comp_error_status != 32'h0000_0000) ||
            (comp_reject_status != 32'h0000_0000) ||
            (queue_error_status != 32'h0000_0000) ||
            (queue_reject_status != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_B/CLEANUP_FAILED",
                $sformatf("Sticky cleanup failed: comp_error=0x%08h comp_reject=0x%08h queue_error=0x%08h queue_reject=0x%08h",
                    comp_error_status,
                    comp_reject_status,
                    queue_error_status,
                    queue_reject_status))
        end

        `uvm_info("CODE_COV_C1P2_G7_Z4_B/CLEANUP_PASS",
            "P18 and queue error/reject sticky state cleared after injected queue-owned completion error",
            UVM_MEDIUM)
    end
    endtask

    task automatic g7_z4b_queue_owned_completion_wb_bresp_error_probe();
    begin
        `uvm_info("CODE_COV_C1P2_G7_Z4_B/START",
            "Starting legal queue-owned P18 BRESP-error propagation probe",
            UVM_MEDIUM)

        comp_wb_inject_vif.clear();
        repeat (2) @(posedge csr_vif.clk);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();

        csr_program_completion_wb();
        csr_program_queue();
        csr_check_recipe_idle_ready("before G7-Z4-B queue-owned P18 error probe");

        // Relative write beat 0 is the first queue-owned completion-memory
        // AW after arming.  The integrated responder accepts AW/W and returns
        // SLVERR without modifying completion memory for that beat.
        comp_wb_inject_vif.set_bresp_error(1'b1, 0);
        repeat (2) @(posedge csr_vif.clk);

        `uvm_info("CODE_COV_C1P2_G7_Z4_B/INJECT_ARMED",
            "Armed completion-memory SLVERR on relative queue-owned P18 write beat 0",
            UVM_MEDIUM)

        csr_start_queue();
        g7_z4b_poll_queue_owned_completion_wb_error(done_timeout_cycles * 3);

        comp_wb_inject_vif.clear();
        repeat (2) @(posedge csr_vif.clk);
        g7_z4b_check_error_no_cq_commit();

        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_clear_sticky_status();
        repeat (5) @(posedge csr_vif.clk);

        g7_z4b_verify_cleanup();
        csr_check_recipe_idle_ready("after G7-Z4-B queue-owned P18 error cleanup");
    end
    endtask

    // ============================================================
    // CODE-COV-C1.2-G7-Z4-C2-B
    // Queue auto-continue control-window constructive probes
    // ============================================================

    task automatic g7_z4_c2b_program_sq_command_entry(
        input int unsigned entry_index,
        input logic [31:0] command_tag
    );
        int unsigned base;
    begin
        if (entry_index >= P19E_QUEUE_DEPTH) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/BAD_SQ_INDEX",
                $sformatf("SQ entry index %0d exceeds queue depth %0d",
                    entry_index, P19E_QUEUE_DEPTH))
        end

        base = P19E_SQ_BASE + (entry_index * P19E_ENTRY_STRIDE);

        write_src_word_le(base + 16'h00, G7_Z4_C2_B_CMD_CONTROL_CONTINUE);
        write_src_word_le(base + 16'h04, command_tag);
        write_src_word_le(base + 16'h08, 32'(P17D_DESC_BASE));
        write_src_word_le(base + 16'h0C, 32'h0000_0002);
        write_src_word_le(base + 16'h10, 32'(P17D_DESC_STRIDE));
        write_src_word_le(base + 16'h14, P19E_COMP_FLAGS);
        write_src_word_le(base + 16'h18, 32'h0000_0000);

        for (int unsigned w = 7; w < 16; w++) begin
            write_src_word_le(base + (w * 4), 32'h0000_0000);
        end

        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_B/SQ_PROGRAM",
            $sformatf("Programmed continue-capable follow-up SQ[%0d] at 0x%08h tag=0x%08h control=0x%08h",
                entry_index, base, command_tag, G7_Z4_C2_B_CMD_CONTROL_CONTINUE),
            UVM_MEDIUM)
    end
    endtask

    task automatic g7_z4_c2b_clear_command_sticky(input string tag);
    begin
        csr_completion_wb_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_clear_sticky_status();
        csr_queue_clear_sticky_status();
        repeat (5) @(posedge csr_vif.clk);

        csr_check_recipe_idle_ready($sformatf("G7-Z4-C2-B cleanup: %s", tag));
    end
    endtask

    task automatic g7_z4_c2b_poll_queue_validated_tag(
        input logic [31:0] expected_tag,
        input int unsigned timeout_cycles,
        input string       tag
    );
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] last_tag;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS,
                done_status
            );
            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,
                error_status
            );
            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS,
                reject_status
            );

            if ((error_status != 32'h0000_0000) ||
                (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/QUEUE_FAIL",
                    $sformatf("%s: queue error/reject while waiting validation: error=0x%08h reject=0x%08h",
                        tag, error_status, reject_status))
            end

            if (done_status[3]) begin
                csr.read32_expect_okay(
                    ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG,
                    last_tag
                );
                if (last_tag !== expected_tag) begin
                    `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/TAG_MISMATCH",
                        $sformatf("%s: expected last tag=0x%08h got=0x%08h",
                            tag, expected_tag, last_tag))
                end

                `uvm_info("CODE_COV_C1P2_G7_Z4_C2_B/VALIDATED",
                    $sformatf("%s: queue command validated tag=0x%08h after %0d poll(s)",
                        tag, last_tag, cnt),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/VALIDATE_TIMEOUT",
                    $sformatf("%s: timeout waiting queue validation tag=0x%08h",
                        tag, expected_tag))
            end
        end
    end
    endtask

    task automatic g7_z4_c2b_wait_completion_wb_busy(
        input int unsigned timeout_cycles,
        input string       tag
    );
        bit seen;
    begin
        seen = 1'b0;
        fork : wait_p18_busy_fork
            begin
                wait (p17d_ctrl_vif.completion_wb_busy_obs === 1'b1);
                seen = 1'b1;
            end
            begin
                repeat (timeout_cycles) @(posedge csr_vif.clk);
            end
        join_any
        disable wait_p18_busy_fork;

        if (!seen) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/P18_BUSY_TIMEOUT",
                $sformatf("%s: timeout waiting for queue-owned P18 busy", tag))
        end

        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_B/P18_BUSY",
            $sformatf("%s: observed queue-owned P18 busy", tag),
            UVM_LOW)
    end
    endtask

    task automatic g7_z4_c2b_wait_commit_pulse(
        input int unsigned timeout_cycles,
        input string       tag
    );
        bit seen;
    begin
        seen = 1'b0;
        fork : wait_commit_fork
            begin
                wait (p17d_ctrl_vif.queue_completion_commit_pulse_obs === 1'b1);
                seen = 1'b1;
            end
            begin
                repeat (timeout_cycles) @(posedge csr_vif.clk);
            end
        join_any
        disable wait_commit_fork;

        if (!seen) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/COMMIT_TIMEOUT",
                $sformatf("%s: timeout waiting queue completion commit pulse", tag))
        end
    end
    endtask

    // Drive one ordinary AXI-Lite CSR write so its write_apply edge is the
    // exact dma_clk edge on which the queue wrapper consumes the already-high
    // completion commit pulse.  This is architectural bus stimulus, not a
    // direct DUT-state mutation.
    task automatic g7_z4_c2b_write_queue_control_on_commit(
        input logic [31:0] control_value,
        input logic        expected_enable,
        input logic        expected_rue,
        input string       tag
    );
        bit commit_seen;
    begin
        commit_seen = 1'b0;
        fork : arm_commit_collision_fork
            begin
                wait (p17d_ctrl_vif.queue_completion_commit_pulse_obs === 1'b1);
                commit_seen = 1'b1;
            end
            begin
                repeat (done_timeout_cycles * 2) @(posedge csr_vif.clk);
            end
        join_any
        disable arm_commit_collision_fork;

        if (!commit_seen) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/COLLISION_COMMIT_TIMEOUT",
                $sformatf("%s: commit pulse never arrived", tag))
        end

        // Commit is a full-cycle combinational pulse.  Stage AW/W at the
        // intervening falling edge so the next rising edge simultaneously
        // samples commit in the queue wrapper and applies CSR_QUEUE_CONTROL.
        @(negedge csr_vif.clk);

        if (p17d_ctrl_vif.queue_completion_commit_pulse_obs !== 1'b1) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/COMMIT_WINDOW_LOST",
                $sformatf("%s: commit pulse dropped before collision write could be staged", tag))
        end

        if ((csr_vif.awvalid !== 1'b0) ||
            (csr_vif.wvalid  !== 1'b0) ||
            (csr_vif.bvalid  !== 1'b0)) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/CSR_BUS_NOT_IDLE",
                $sformatf("%s: CSR write channel not idle before collision write: AWVALID=%0b WVALID=%0b BVALID=%0b",
                    tag, csr_vif.awvalid, csr_vif.wvalid, csr_vif.bvalid))
        end

        csr_vif.awaddr  = ai_accel_csr_access_helper::CSR_QUEUE_CONTROL;
        csr_vif.awvalid = 1'b1;
        csr_vif.wdata   = control_value;
        csr_vif.wstrb   = '1;
        csr_vif.wvalid  = 1'b1;
        csr_vif.bready  = 1'b1;

        #1ps;
        if ((csr_vif.awready !== 1'b1) || (csr_vif.wready !== 1'b1)) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/CSR_NOT_READY",
                $sformatf("%s: CSR_QUEUE_CONTROL collision write not accepted on next edge: AWREADY=%0b WREADY=%0b",
                    tag, csr_vif.awready, csr_vif.wready))
        end

        @(posedge csr_vif.clk);
        #1ps;
        csr_vif.awvalid = 1'b0;
        csr_vif.wvalid  = 1'b0;

        // This is the exact post-edge state required by the line-1287 FEC
        // target: pending was created from OLD enabled/RUE state while the
        // architectural CSR write installed the NEW control state.
        if (p17d_ctrl_vif.queue_auto_continue_pending_obs !== 1'b1) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/PENDING_NOT_SET",
                $sformatf("%s: expected auto-continue pending=1 immediately after commit/control collision", tag))
        end
        if (p17d_ctrl_vif.queue_enable_obs !== expected_enable) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/ENABLE_STATE",
                $sformatf("%s: expected queue_enable=%0b got=%0b",
                    tag, expected_enable, p17d_ctrl_vif.queue_enable_obs))
        end
        if (p17d_ctrl_vif.queue_run_until_empty_obs !== expected_rue) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/RUE_STATE",
                $sformatf("%s: expected run_until_empty=%0b got=%0b",
                    tag, expected_rue, p17d_ctrl_vif.queue_run_until_empty_obs))
        end
        if (p17d_ctrl_vif.queue_busy_obs !== 1'b0) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/QUEUE_BUSY_STATE",
                $sformatf("%s: expected raw queue controller idle at auto-continue boundary, queue_busy=%0b",
                    tag, p17d_ctrl_vif.queue_busy_obs))
        end

        if (csr_vif.bvalid !== 1'b1) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/NO_BVALID",
                $sformatf("%s: CSR_QUEUE_CONTROL collision write did not produce BVALID", tag))
        end
        if (csr_vif.bresp !== 2'b00) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/BRESP",
                $sformatf("%s: CSR_QUEUE_CONTROL collision write BRESP=%0b expected OKAY", tag, csr_vif.bresp))
        end

        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_B/COLLISION_STATE_PASS",
            $sformatf("%s: post-edge pending=1 enable=%0b RUE=%0b busy=0",
                tag, expected_enable, expected_rue),
            UVM_MEDIUM)

        // Consume the normal AXI-Lite write response.
        @(posedge csr_vif.clk);
        #1ps;
        csr_vif.bready = 1'b0;
    end
    endtask

    task automatic g7_z4_c2b_expect_pointers(
        input logic [31:0] expected_sq_head,
        input logic [31:0] expected_cq_tail,
        input string       tag
    );
        logic [31:0] sq_head;
        logic [31:0] cq_tail;
        logic [31:0] queue_error;
        logic [31:0] queue_reject;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL, cq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, queue_error);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, queue_reject);

        if ((sq_head !== expected_sq_head) || (cq_tail !== expected_cq_tail)) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/POINTER_MISMATCH",
                $sformatf("%s: expected SQ_HEAD/CQ_TAIL=%0d/%0d got=%0d/%0d",
                    tag, expected_sq_head, expected_cq_tail, sq_head, cq_tail))
        end
        if ((queue_error != 32'h0000_0000) || (queue_reject != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/QUEUE_STICKY",
                $sformatf("%s: unexpected queue error/reject after legal probe: error=0x%08h reject=0x%08h",
                    tag, queue_error, queue_reject))
        end

        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_B/POINTER_PASS",
            $sformatf("%s: SQ_HEAD=%0d CQ_TAIL=%0d", tag, sq_head, cq_tail),
            UVM_LOW)
    end
    endtask

    task automatic g7_z4_c2b_queue_control_window_probe();
    begin
        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_B/START",
            "Starting queue auto-continue control-window constructive probe",
            UVM_MEDIUM)

        // The original P19E success path already committed SQ/CQ index 0.
        // Add three legal ring entries and publish tail=4.  The queue
        // controller uses modulo-depth indices while host pointers remain
        // monotonic, so the next commands are SQ indices 1, 2, and 3.
        g7_z4_c2b_program_sq_command_entry(1, G7_Z4_C2_B_TAG_ENABLE_AT_COMMIT);
        g7_z4_c2b_program_sq_command_entry(2, G7_Z4_C2_B_TAG_ENABLE_COLLISION);
        g7_z4_c2b_program_sq_command_entry(3, G7_Z4_C2_B_TAG_RUE_COLLISION);
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,
            32'h0000_0004
        );

        // --------------------------------------------------------
        // Probe 1: line1192 csr_queue_enable=0 decisive term.
        // Let queue-owned P18 start first, then legally disable the queue
        // while the 16-word completion record is still in flight.  P18
        // ownership remains active, so the eventual commit is genuine;
        // only auto-continue admission is disabled at commit time.
        // --------------------------------------------------------
        g7_z4_c2b_clear_command_sticky("before line1192 enable-low probe");
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_CONTROL,
            G7_Z4_C2_B_CTRL_ENABLE_RUE
        );
        csr_start_queue();
        g7_z4_c2b_poll_queue_validated_tag(
            G7_Z4_C2_B_TAG_ENABLE_AT_COMMIT,
            done_timeout_cycles,
            "line1192 enable-low"
        );
        g7_z4_c2b_wait_completion_wb_busy(
            done_timeout_cycles * 2,
            "line1192 enable-low"
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_CONTROL,
            G7_Z4_C2_B_CTRL_DISABLE_RUE
        );
        if ((p17d_ctrl_vif.queue_enable_obs !== 1'b0) ||
            (p17d_ctrl_vif.queue_run_until_empty_obs !== 1'b1)) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/LINE1192_CONTROL",
                $sformatf("Expected enable/RUE=0/1 before commit, got=%0b/%0b",
                    p17d_ctrl_vif.queue_enable_obs,
                    p17d_ctrl_vif.queue_run_until_empty_obs))
        end

        g7_z4_c2b_wait_commit_pulse(done_timeout_cycles, "line1192 enable-low");
        if (p17d_ctrl_vif.queue_enable_obs !== 1'b0) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/LINE1192_ENABLE_NOT_LOW",
                "Queue enable was not low while completion commit pulse was asserted")
        end
        @(posedge csr_vif.clk);
        repeat (2) @(posedge csr_vif.clk);
        g7_z4_c2b_expect_pointers(32'd2, 32'd2, "line1192 enable-low");
        expect_queue_comp_word(P19E_ENTRY_STRIDE + 16'h00,
                               EXP_COMMIT_SUCCESS,
                               "C2-B line1192 CQ[1] commit");
        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_B/LINE1192_PASS",
            "Legal completion commit observed with QUEUE_ENABLE=0",
            UVM_MEDIUM)

        // --------------------------------------------------------
        // Probe 2: line1287 csr_queue_enable=0 decisive term.
        // The queue wrapper samples OLD enable/RUE=1/1 and sets pending on
        // the same edge that the AXI-Lite write installs NEW enable/RUE=0/1.
        // --------------------------------------------------------
        g7_z4_c2b_clear_command_sticky("before line1287 enable collision");
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_CONTROL,
            G7_Z4_C2_B_CTRL_ENABLE_RUE
        );
        csr_start_queue();
        g7_z4_c2b_poll_queue_validated_tag(
            G7_Z4_C2_B_TAG_ENABLE_COLLISION,
            done_timeout_cycles,
            "line1287 enable collision"
        );
        g7_z4_c2b_write_queue_control_on_commit(
            G7_Z4_C2_B_CTRL_DISABLE_RUE,
            1'b0,
            1'b1,
            "line1287 enable collision"
        );
        repeat (2) @(posedge csr_vif.clk);
        if (p17d_ctrl_vif.queue_auto_continue_pending_obs !== 1'b0) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/ENABLE_PENDING_NOT_CLEARED",
                "Auto-continue pending did not clear after QUEUE_ENABLE=0")
        end
        g7_z4_c2b_expect_pointers(32'd3, 32'd3, "line1287 enable collision");
        expect_queue_comp_word((2 * P19E_ENTRY_STRIDE) + 16'h00,
                               EXP_COMMIT_SUCCESS,
                               "C2-B line1287 enable CQ[2] commit");
        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_B/LINE1287_ENABLE_PASS",
            "Same-edge commit / QUEUE_ENABLE clear produced pending=1, enable=0, RUE=1, busy=0",
            UVM_MEDIUM)

        // --------------------------------------------------------
        // Probe 3: line1287 RUN_UNTIL_EMPTY=0 decisive term.
        // Same collision mechanism, but keep ENABLE=1 and clear only RUE.
        // Pending remains parked (no auto-start) until the test disables
        // the queue for one clean cycle to retire it.
        // --------------------------------------------------------
        g7_z4_c2b_clear_command_sticky("before line1287 RUE collision");
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_CONTROL,
            G7_Z4_C2_B_CTRL_ENABLE_RUE
        );
        csr_start_queue();
        g7_z4_c2b_poll_queue_validated_tag(
            G7_Z4_C2_B_TAG_RUE_COLLISION,
            done_timeout_cycles,
            "line1287 RUE collision"
        );
        g7_z4_c2b_write_queue_control_on_commit(
            G7_Z4_C2_B_CTRL_ENABLE_NO_RUE,
            1'b1,
            1'b0,
            "line1287 RUE collision"
        );
        g7_z4_c2b_expect_pointers(32'd4, 32'd4, "line1287 RUE collision");
        expect_queue_comp_word((3 * P19E_ENTRY_STRIDE) + 16'h00,
                               EXP_COMMIT_SUCCESS,
                               "C2-B line1287 RUE CQ[3] commit");
        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_B/LINE1287_RUE_PASS",
            "Same-edge commit / RUN_UNTIL_EMPTY clear produced pending=1, enable=1, RUE=0, busy=0",
            UVM_MEDIUM)

        // With RUE=0 the pending latch is intentionally parked.  Disable
        // the queue through the normal CSR path, allow the wrapper's
        // !csr_queue_enable cleanup term to clear pending, then restore the
        // original P19E control policy (ENABLE + STOP_ON_ERROR, RUE=0).
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_CONTROL,
            G7_Z4_C2_B_CTRL_DISABLE_NO_RUE
        );
        repeat (2) @(posedge csr_vif.clk);
        if (p17d_ctrl_vif.queue_auto_continue_pending_obs !== 1'b0) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Z4_C2_B/RUE_PENDING_NOT_CLEARED",
                "Auto-continue pending did not clear after cleanup disable")
        end
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_CONTROL,
            G7_Z4_C2_B_CTRL_ENABLE_NO_RUE
        );

        g7_z4_c2b_clear_command_sticky("after C2-B control-window probes");

        `uvm_info("CODE_COV_C1P2_G7_Z4_C2_B/PASS",
            "Queue control-window constructive probe completed: line1192 enable-low + line1287 enable/RUE same-edge collisions",
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
        int unsigned             c1p3_b1_aw_first_before;
        int unsigned             c1p3_b1_w_first_before;
        int unsigned             c1p3_b1_aw_first_after;
        int unsigned             c1p3_b1_w_first_after;
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

        // CODE-COV-C1.2-G7-Z4-B: create one legal queue-owned P18 BRESP
        // failure, verify queue-level propagation/no CQ commit, clean it,
        // then run the original P19E success path unchanged as recovery.
        g7_z4b_queue_owned_completion_wb_bresp_error_probe();

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();

        csr_program_completion_wb();
        csr_program_queue();

        // CODE-COV-C1.3-B1: use the existing normal queue-owned completion
        // success path to prove that the completion master tolerates legal
        // independent AW/W acceptance.  Relative completion write beat 0 is
        // AW-first; relative beat 1 is W-first.
        comp_wb_inject_vif.clear();
        repeat (2) @(posedge csr_vif.clk);
        c1p3_b1_aw_first_before = comp_wb_inject_vif.aw_first_observed_count;
        c1p3_b1_w_first_before  = comp_wb_inject_vif.w_first_observed_count;
        comp_wb_inject_vif.set_aw_w_backpressure(1'b1, 0, 1);
        repeat (2) @(posedge csr_vif.clk);

        csr_check_recipe_idle_ready("before queue START");
        csr_start_queue();

        csr_poll_queue_validated(done_timeout_cycles);
        csr_poll_desc_fetch_done(done_timeout_cycles);
        csr_poll_recipe_done(done_timeout_cycles * 2);
        csr_poll_completion_wb_done(done_timeout_cycles);
        csr_check_recipe_perf_snapshot(profile_item);

        comp_wb_inject_vif.set_aw_w_backpressure(1'b0, -1, -1);
        repeat (2) @(posedge csr_vif.clk);
        c1p3_b1_aw_first_after = comp_wb_inject_vif.aw_first_observed_count;
        c1p3_b1_w_first_after  = comp_wb_inject_vif.w_first_observed_count;

        if (c1p3_b1_aw_first_after <= c1p3_b1_aw_first_before) begin
            `uvm_fatal("CODE_COV_C1P3_B1_COMP/AW_FIRST_NOT_OBSERVED",
                $sformatf("Completion AW-first injection was not observed: before=%0d after=%0d",
                    c1p3_b1_aw_first_before, c1p3_b1_aw_first_after))
        end

        if (c1p3_b1_w_first_after <= c1p3_b1_w_first_before) begin
            `uvm_fatal("CODE_COV_C1P3_B1_COMP/W_FIRST_NOT_OBSERVED",
                $sformatf("Completion W-first injection was not observed: before=%0d after=%0d",
                    c1p3_b1_w_first_before, c1p3_b1_w_first_after))
        end

        `uvm_info("CODE_COV_C1P3_B1_COMP/AW_FIRST_PASS",
            $sformatf("Completion AW-first handshake observed: %0d -> %0d",
                c1p3_b1_aw_first_before, c1p3_b1_aw_first_after),
            UVM_MEDIUM)
        `uvm_info("CODE_COV_C1P3_B1_COMP/W_FIRST_PASS",
            $sformatf("Completion W-first handshake observed: %0d -> %0d",
                c1p3_b1_w_first_before, c1p3_b1_w_first_after),
            UVM_MEDIUM)
        `uvm_info("CODE_COV_C1P3_B1_COMP/PASS",
            "Completion writeback independent AW/W ordering robustness probes PASS",
            UVM_MEDIUM)

        repeat (5) @(posedge csr_vif.clk);

        check_queue_completion_record(profile_item);
        check_queue_pointers_after_completion();

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        // CODE-COV-C1.2-G7-Z4-C2-B: after the original P19E recovery
        // has proven the normal queue-owned completion path, reuse the
        // remaining three ring entries for legal queue-control timing
        // probes.  No existing success-path expectation is weakened.
        g7_z4_c2b_queue_control_window_probe();

        `uvm_info("CODE_COV_C1P2_G7_Z4_B/RECOVERY_PASS",
            "Normal queue-owned P18 CQ writeback completed successfully after injected BRESP error cleanup",
            UVM_MEDIUM)

        `uvm_info("CODE_COV_C1P2_G7_Z4_B/PASS",
            "Queue-owned completion-writeback ERROR propagation / no-commit / cleanup / recovery probe PASS",
            UVM_MEDIUM)

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
