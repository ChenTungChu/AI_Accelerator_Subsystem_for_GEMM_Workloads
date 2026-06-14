// File: tb/uvm/test/ai_accel_subsys_csr_queue_completion_event_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_COMPLETION_EVENT_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_COMPLETION_EVENT_SMOKE_TEST_SV

// ============================================================
// P22D queue completion event smoke
//
// Scope:
//   - Reuses the existing P19E queue -> descriptor fetch -> CQ
//     completion writeback path.
//   - Enables the P22 event CSR bits for queue command completion
//     and CQ-not-empty notification.
//   - Verifies a real queue completion commit raises event pending,
//     event status / irq summary, last-cause, and event counters.
//
// This is intentionally integrated into ai_accel_subsys_csr_uvm_top.
// It does not add a standalone event CSR block, standalone event top,
// or separate event injection interface.
// ============================================================

class ai_accel_subsys_csr_queue_completion_event_smoke_test
    extends ai_accel_subsys_csr_queue_completion_wb_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_completion_event_smoke_test)

    localparam logic [31:0] P22D_EVENT_QUEUE_COMPLETED_MASK = 32'h0000_0001;
    localparam logic [31:0] P22D_EVENT_CQ_NOT_EMPTY_MASK    = 32'h0000_0010;
    localparam logic [31:0] P22D_EVENT_EXPECT_MASK          = 32'h0000_0011;

    localparam logic [31:0] P22D_EVENT_CMD_CLEAR_ALL        = 32'h0000_0101;
    localparam logic [31:0] P22D_EVENT_CONTROL_IRQ_SNAPSHOT = 32'h0000_0005;

    function new(string name = "ai_accel_subsys_csr_queue_completion_event_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic csr_event_clear_all(string where = "");
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_PENDING,
            ai_accel_csr_access_helper::EVENT_VALID_MASK
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_COMMAND,
            P22D_EVENT_CMD_CLEAR_ALL
        );

        `uvm_info("P22D_EVENT/CLR",
            $sformatf("Cleared P22 event pending/counters%s%s",
                (where.len() == 0) ? "" : " at ",
                where),
            UVM_LOW)
    end
    endtask

    task automatic csr_event_enable_queue_completion();
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_PENDING,
            ai_accel_csr_access_helper::EVENT_VALID_MASK
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_COMMAND,
            P22D_EVENT_CMD_CLEAR_ALL
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_CQ_THRESHOLD,
            32'h0000_0000
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_ENABLE,
            P22D_EVENT_EXPECT_MASK
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_CONTROL,
            P22D_EVENT_CONTROL_IRQ_SNAPSHOT
        );

        `uvm_info("P22D_EVENT/CFG",
            $sformatf("Enabled queue completion events: enable_mask=0x%08h control=0x%08h",
                P22D_EVENT_EXPECT_MASK,
                P22D_EVENT_CONTROL_IRQ_SNAPSHOT),
            UVM_MEDIUM)
    end
    endtask

    task automatic expect_event_mask_set(input logic [31:0] actual,
                                         input logic [31:0] mask,
                                         input string       name);
    begin
        if ((actual & mask) !== mask) begin
            `uvm_fatal("P22D_EVENT/MASK_MISSING",
                $sformatf("%s missing: actual=0x%08h mask=0x%08h",
                    name,
                    actual,
                    mask))
        end

        `uvm_info("P22D_EVENT/CHECK",
            $sformatf("%s PASS: actual=0x%08h mask=0x%08h",
                name,
                actual,
                mask),
            UVM_LOW)
    end
    endtask

    task automatic expect_event_mask_clear(input logic [31:0] actual,
                                           input logic [31:0] mask,
                                           input string       name);
    begin
        if ((actual & mask) !== 32'h0000_0000) begin
            `uvm_fatal("P22D_EVENT/MASK_STILL_SET",
                $sformatf("%s still set: actual=0x%08h mask=0x%08h",
                    name,
                    actual,
                    mask))
        end

        `uvm_info("P22D_EVENT/CHECK",
            $sformatf("%s clear PASS: actual=0x%08h mask=0x%08h",
                name,
                actual,
                mask),
            UVM_LOW)
    end
    endtask

    task automatic check_queue_completion_events();
        logic [31:0] pending;
        logic [31:0] status;
        logic [31:0] last_cause;
        logic [31:0] event_count;
        logic [31:0] irq_count;
        logic [31:0] snapshot0;
        logic [31:0] snapshot1;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_PENDING, pending);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_STATUS, status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_LAST_CAUSE, last_cause);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_COUNT, event_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_IRQ_COUNT, irq_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_SNAPSHOT0, snapshot0);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_SNAPSHOT1, snapshot1);

        expect_event_mask_set(
            pending,
            P22D_EVENT_QUEUE_COMPLETED_MASK,
            "QUEUE_COMMAND_COMPLETED_EVENT pending"
        );

        expect_event_mask_set(
            pending,
            P22D_EVENT_CQ_NOT_EMPTY_MASK,
            "CQ_NOT_EMPTY_EVENT pending"
        );

        // CSR_EVENT_STATUS bits:
        //   [0] any pending
        //   [1] any enabled pending
        //   [2] event_irq output summary
        //   [3] global IRQ enable
        //   [4] queue/CQ-class pending summary
        expect_event_mask_set(
            status,
            32'h0000_001F,
            "queue completion event status / irq summary"
        );

        if (last_cause == 32'h0000_0000) begin
            `uvm_fatal("P22D_EVENT/LAST_CAUSE",
                "Expected EVENT_LAST_CAUSE to capture at least one real queue event")
        end

        if (event_count == 32'h0000_0000) begin
            `uvm_fatal("P22D_EVENT/COUNT_ZERO",
                "Expected EVENT_COUNT to increment for real queue completion event")
        end

        if (irq_count == 32'h0000_0000) begin
            `uvm_fatal("P22D_EVENT/IRQ_COUNT_ZERO",
                "Expected EVENT_IRQ_COUNT to increment for enabled queue completion event")
        end

        `uvm_info("P22D_EVENT/CHECK",
            $sformatf("Queue completion event summary PASS: pending=0x%08h status=0x%08h last_cause=0x%08h event_count=%0d irq_count=%0d snapshot0=0x%08h snapshot1=0x%08h",
                pending,
                status,
                last_cause,
                event_count,
                irq_count,
                snapshot0,
                snapshot1),
            UVM_MEDIUM)
    end
    endtask

    task automatic clear_and_check_queue_completion_events();
        logic [31:0] pending;
        logic [31:0] status;
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_PENDING,
            ai_accel_csr_access_helper::EVENT_VALID_MASK
        );

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_PENDING, pending);
        expect_event_mask_clear(
            pending,
            P22D_EVENT_EXPECT_MASK,
            "queue completion event pending after W1C"
        );

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_STATUS, status);
        expect_event_mask_clear(
            status,
            32'h0000_0007,
            "event status pending/irq bits after W1C"
        );
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

        `uvm_info("P22D_QUEUE_EVENT/START",
            "Starting P22D queue completion event smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P22D_QUEUE_EVENT/EXPECTED_SIZE",
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
        csr_event_enable_queue_completion();

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
        check_queue_completion_events();
        clear_and_check_queue_completion_events();

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P22D_QUEUE_EVENT/PASS",
            $sformatf("P22D queue completion event smoke completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d event_mask=0x%08h",
                selected_case_id,
                a_flat.size(),
                b_flat.size(),
                c_elems,
                P22D_EVENT_EXPECT_MASK),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
