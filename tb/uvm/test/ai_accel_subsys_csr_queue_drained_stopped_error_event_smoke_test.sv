// File: tb/uvm/test/ai_accel_subsys_csr_queue_drained_stopped_error_event_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_DRAINED_STOPPED_ERROR_EVENT_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_DRAINED_STOPPED_ERROR_EVENT_SMOKE_TEST_SV

// ============================================================
// P22E queue drained / stopped / error event smoke
//
// Scope:
//   - Reuses the existing P19/P20 queue controller paths.
//   - Enables P22 event bits for queue terminal conditions:
//       * QUEUE_DRAINED_EVENT
//       * QUEUE_STOPPED_EVENT
//       * QUEUE_ERROR_EVENT
//   - Verifies that real queue drain / stop / validation-error paths
//     raise event pending, event status / irq summary, last-cause,
//     snapshots, and counters.
//
// This remains integrated into ai_accel_subsys_csr_uvm_top.  It does
// not add a standalone event CSR block, standalone event top, or
// separate event injection interface.
// ============================================================

class ai_accel_subsys_csr_queue_drained_stopped_error_event_smoke_test
    extends ai_accel_subsys_csr_queue_stop_behavior_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_drained_stopped_error_event_smoke_test)

    localparam logic [31:0] P22E_EVENT_QUEUE_DRAINED_MASK = 32'h0000_0002;
    localparam logic [31:0] P22E_EVENT_QUEUE_STOPPED_MASK = 32'h0000_0004;
    localparam logic [31:0] P22E_EVENT_QUEUE_ERROR_MASK   = 32'h0000_0008;

    localparam logic [31:0] P22E_EVENT_CMD_CLEAR_ALL      = 32'h0000_0101;
    localparam logic [31:0] P22E_EVENT_CONTROL_IRQ_SNAP   = 32'h0000_0005;

    localparam int unsigned P22E_QUEUE_DEPTH              = 4;
    localparam int unsigned P22E_ENTRY_STRIDE             = 32'h0000_0040;

    localparam int unsigned P22E_DRAIN_SQ_BASE            = 32'h0000_0900;
    localparam int unsigned P22E_DRAIN_CQ_BASE            = 32'h0000_0A00;

    localparam int unsigned P22E_ERR_SQ_BASE              = 32'h0000_0900;
    localparam int unsigned P22E_ERR_CQ_BASE              = 32'h0000_0A00;
    localparam logic [31:0] P22E_ERR_CMD_TAG              = 32'hD22E_E000;

    // Mirrors the P20F STOP_QUEUE descriptor locations/tags so that the
    // inherited P20F STOP_QUEUE case can be reused without changing the
    // queue execution semantics.
    localparam int unsigned P22E_STOP_DESC_BASE0          = 32'h0000_0500;
    localparam int unsigned P22E_STOP_DESC_BASE1          = 32'h0000_0600;
    localparam int unsigned P22E_STOP_DESC_STRIDE         = 32'h0000_0080;
    localparam logic [31:0] P22E_STOP_DESC0_TAG0          = 32'hD20F_4000;
    localparam logic [31:0] P22E_STOP_DESC0_TAG1          = 32'hD20F_4001;
    localparam logic [31:0] P22E_STOP_DESC1_TAG0          = 32'hD20F_5000;
    localparam logic [31:0] P22E_STOP_DESC1_TAG1          = 32'hD20F_5001;

    localparam int Q_DONE_DRAINED                         = 1;

    function new(string name = "ai_accel_subsys_csr_queue_drained_stopped_error_event_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p22e_clear_ring_memory(input int unsigned sq_base,
                                          input int unsigned cq_base);
    begin
        for (int unsigned i = 0; i < (P22E_QUEUE_DEPTH * P22E_ENTRY_STRIDE); i++) begin
            p17d_ctrl_vif.dma_src_mem[sq_base + i] = 8'h00;
            p17d_ctrl_vif.dma_dst_mem[cq_base + i] = 8'h00;
        end
    end
    endtask

    task automatic p22e_event_clear_all(input string where = "");
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_PENDING,
            ai_accel_csr_access_helper::EVENT_VALID_MASK
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_COMMAND,
            P22E_EVENT_CMD_CLEAR_ALL
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_ENABLE,
            32'h0000_0000
        );

        `uvm_info("P22E_EVENT/CLR",
            $sformatf("Cleared P22 event pending/counters%s%s",
                (where.len() == 0) ? "" : " at ",
                where),
            UVM_LOW)
    end
    endtask

    task automatic p22e_event_enable(input logic [31:0] enable_mask,
                                     input string       case_name);
    begin
        p22e_event_clear_all(case_name);

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_CQ_THRESHOLD,
            32'h0000_0000
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_ENABLE,
            enable_mask & ai_accel_csr_access_helper::EVENT_VALID_MASK
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_CONTROL,
            P22E_EVENT_CONTROL_IRQ_SNAP
        );

        `uvm_info("P22E_EVENT/CFG",
            $sformatf("%s: enabled event_mask=0x%08h control=0x%08h",
                case_name,
                enable_mask,
                P22E_EVENT_CONTROL_IRQ_SNAP),
            UVM_MEDIUM)
    end
    endtask

    task automatic p22e_expect_event_mask(input logic [31:0] mask,
                                          input string       name);
        logic [31:0] pending;
        logic [31:0] status;
        logic [31:0] last_cause;
        logic [31:0] event_count;
        logic [31:0] irq_count;
        logic [31:0] snapshot0;
        logic [31:0] snapshot1;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_PENDING,    pending);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_STATUS,     status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_LAST_CAUSE, last_cause);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_COUNT,      event_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_IRQ_COUNT,  irq_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_SNAPSHOT0,  snapshot0);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_SNAPSHOT1,  snapshot1);

        if ((pending & mask) !== mask) begin
            `uvm_fatal("P22E_EVENT/MASK_MISSING",
                $sformatf("%s missing: pending=0x%08h mask=0x%08h status=0x%08h last_cause=0x%08h",
                    name,
                    pending,
                    mask,
                    status,
                    last_cause))
        end

        // CSR_EVENT_STATUS bits expected for enabled queue-class events:
        //   [0] any pending
        //   [1] any enabled pending
        //   [2] event_irq level summary
        //   [3] global IRQ enable
        //   [4] queue/CQ-class pending summary
        if ((status & 32'h0000_001F) !== 32'h0000_001F) begin
            `uvm_fatal("P22E_EVENT/BAD_STATUS",
                $sformatf("%s bad status: status=0x%08h pending=0x%08h mask=0x%08h",
                    name,
                    status,
                    pending,
                    mask))
        end

        if (last_cause == 32'h0000_0000) begin
            `uvm_fatal("P22E_EVENT/LAST_CAUSE_ZERO",
                $sformatf("%s expected nonzero EVENT_LAST_CAUSE", name))
        end

        if (event_count == 32'h0000_0000) begin
            `uvm_fatal("P22E_EVENT/COUNT_ZERO",
                $sformatf("%s expected EVENT_COUNT to increment", name))
        end

        if (irq_count == 32'h0000_0000) begin
            `uvm_fatal("P22E_EVENT/IRQ_COUNT_ZERO",
                $sformatf("%s expected EVENT_IRQ_COUNT to increment", name))
        end

        `uvm_info("P22E_EVENT/CHECK",
            $sformatf("%s PASS: pending=0x%08h status=0x%08h last_cause=0x%08h event_count=%0d irq_count=%0d snapshot0=0x%08h snapshot1=0x%08h",
                name,
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

    task automatic p22e_event_clear_and_expect_clear(input logic [31:0] mask,
                                                     input string       name);
        logic [31:0] pending;
        logic [31:0] status;
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_PENDING,
            ai_accel_csr_access_helper::EVENT_VALID_MASK
        );

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_PENDING, pending);
        if ((pending & mask) !== 32'h0000_0000) begin
            `uvm_fatal("P22E_EVENT/CLEAR_FAIL",
                $sformatf("%s pending bits still set after W1C: pending=0x%08h mask=0x%08h",
                    name,
                    pending,
                    mask))
        end

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_STATUS, status);
        if ((status & 32'h0000_0007) !== 32'h0000_0000) begin
            `uvm_fatal("P22E_EVENT/STATUS_CLEAR_FAIL",
                $sformatf("%s status pending/irq bits still set after W1C: status=0x%08h",
                    name,
                    status))
        end

        `uvm_info("P22E_EVENT/CHECK",
            $sformatf("%s W1C clear PASS: pending=0x%08h status=0x%08h",
                name,
                pending,
                status),
            UVM_LOW)
    end
    endtask

    task automatic p22e_program_queue(input int unsigned sq_base,
                                      input int unsigned cq_base,
                                      input logic [31:0] sq_head,
                                      input logic [31:0] sq_tail,
                                      input logic [31:0] cq_head,
                                      input logic [31:0] cq_tail,
                                      input logic [31:0] sq_depth,
                                      input logic [31:0] cq_depth,
                                      input logic [31:0] control_value);
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE,   32'(sq_base));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH,  sq_depth);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,   sq_head);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,   sq_tail);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, 32'(P22E_ENTRY_STRIDE));

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE,   32'(cq_base));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH,  cq_depth);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,   cq_head);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,   cq_tail);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, 32'(P22E_ENTRY_STRIDE));

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CONTROL, control_value);
    end
    endtask

    task automatic p22e_start_queue_once(input string case_name);
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_START] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_COMMAND, cmd);
        `uvm_info("P22E_QUEUE/START", $sformatf("%s: issued START_QUEUE", case_name), UVM_MEDIUM)
    end
    endtask

    task automatic p22e_poll_empty_drained(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS,        status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS,   done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,  error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);

            if ((error_status != 32'h0000_0000) || (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P22E_QUEUE/DRAIN_ERROR",
                    $sformatf("Empty SQ should drain without error: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status))
            end

            if (done_status[Q_DONE_DRAINED]) begin
                `uvm_info("P22E_QUEUE/DRAINED",
                    $sformatf("Empty SQ drained: status=0x%08h done=0x%08h", status, done_status),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P22E_QUEUE/DRAIN_TIMEOUT",
                    $sformatf("Timed out waiting for empty SQ drained: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status))
            end
        end
    end
    endtask

    task automatic p22e_program_invalid_sq_entry();
        int unsigned base;
    begin
        base = P22E_ERR_SQ_BASE;

        write_src_word_le(base + 16'h00, 32'h0000_0000); // invalid: VALID bit clear / unsupported command
        write_src_word_le(base + 16'h04, P22E_ERR_CMD_TAG);
        write_src_word_le(base + 16'h08, 32'h0000_0300);
        write_src_word_le(base + 16'h0C, 32'h0000_0001);
        write_src_word_le(base + 16'h10, 32'h0000_0080);
        write_src_word_le(base + 16'h14, 32'h0000_0000);
        write_src_word_le(base + 16'h18, 32'h0000_0000);

        for (int unsigned w = 7; w < 16; w++) begin
            write_src_word_le(base + (w * 4), 32'h0000_0000);
        end

        `uvm_info("P22E_QUEUE/ERR_SQ",
            $sformatf("Programmed invalid SQ command at 0x%08h control=0x00000000 tag=0x%08h",
                base,
                P22E_ERR_CMD_TAG),
            UVM_MEDIUM)
    end
    endtask

    task automatic p22e_poll_queue_error(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] detail;
        logic [31:0] last_tag;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS,        status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS,   done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,  error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_DETAIL,  detail);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG,  last_tag);

            if (error_status != 32'h0000_0000) begin
                `uvm_info("P22E_QUEUE/ERROR",
                    $sformatf("Queue validation error observed: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h detail=0x%08h last_tag=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        detail,
                        last_tag),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P22E_QUEUE/ERROR_TIMEOUT",
                    $sformatf("Timed out waiting for queue validation error: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h detail=0x%08h last_tag=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        detail,
                        last_tag))
            end
        end
    end
    endtask

    task automatic p22e_case_empty_drained_event();
    begin
        `uvm_info("P22E_CASE/DRAINED",
            "Starting empty-SQ QUEUE_DRAINED_EVENT case",
            UVM_MEDIUM)

        p22e_clear_ring_memory(P22E_DRAIN_SQ_BASE, P22E_DRAIN_CQ_BASE);
        csr_queue_clear_sticky_status();
        p22e_event_enable(P22E_EVENT_QUEUE_DRAINED_MASK, "empty drained");

        // bit0 QUEUE_ENABLE, bit2 STOP_ON_ERROR.  Empty SQ should drain
        // cleanly without fetching a command.
        p22e_program_queue(P22E_DRAIN_SQ_BASE,
                           P22E_DRAIN_CQ_BASE,
                           32'h0000_0000,
                           32'h0000_0000,
                           32'h0000_0000,
                           32'h0000_0000,
                           32'(P22E_QUEUE_DEPTH),
                           32'(P22E_QUEUE_DEPTH),
                           32'h0000_0005);

        p22e_start_queue_once("empty drained");
        p22e_poll_empty_drained(80);

        repeat (5) @(posedge csr_vif.clk);
        p22e_expect_event_mask(P22E_EVENT_QUEUE_DRAINED_MASK, "QUEUE_DRAINED_EVENT");
        p22e_event_clear_and_expect_clear(P22E_EVENT_QUEUE_DRAINED_MASK, "QUEUE_DRAINED_EVENT");
        csr_queue_clear_sticky_status();
    end
    endtask

    task automatic p22e_case_stop_event(input ai_accel_subsys_seq_item profile_item,
                                        input int signed expected_c[]);
    begin
        `uvm_info("P22E_CASE/STOPPED",
            "Starting STOP_QUEUE QUEUE_STOPPED_EVENT case",
            UVM_MEDIUM)

        p22e_event_enable(P22E_EVENT_QUEUE_STOPPED_MASK, "STOP_QUEUE stopped");

        p20f_case_stop_queue(profile_item, expected_c);

        repeat (5) @(posedge csr_vif.clk);
        p22e_expect_event_mask(P22E_EVENT_QUEUE_STOPPED_MASK, "QUEUE_STOPPED_EVENT");
        p22e_event_clear_and_expect_clear(P22E_EVENT_QUEUE_STOPPED_MASK, "QUEUE_STOPPED_EVENT");
        csr_queue_clear_sticky_status();
    end
    endtask

    task automatic p22e_case_queue_error_event();
    begin
        `uvm_info("P22E_CASE/ERROR",
            "Starting invalid SQ command QUEUE_ERROR_EVENT case",
            UVM_MEDIUM)

        p22e_clear_ring_memory(P22E_ERR_SQ_BASE, P22E_ERR_CQ_BASE);
        p22e_program_invalid_sq_entry();

        csr_queue_clear_sticky_status();
        p22e_event_enable(P22E_EVENT_QUEUE_ERROR_MASK, "invalid SQ command error");

        // bit0 QUEUE_ENABLE, bit2 STOP_ON_ERROR.  SQ has one entry but the
        // command control word is intentionally invalid, so the existing
        // queue validation path must raise a real queue_error_pulse.
        p22e_program_queue(P22E_ERR_SQ_BASE,
                           P22E_ERR_CQ_BASE,
                           32'h0000_0000,
                           32'h0000_0001,
                           32'h0000_0000,
                           32'h0000_0000,
                           32'(P22E_QUEUE_DEPTH),
                           32'(P22E_QUEUE_DEPTH),
                           32'h0000_0005);

        p22e_start_queue_once("invalid SQ command error");
        p22e_poll_queue_error(120);

        repeat (5) @(posedge csr_vif.clk);
        p22e_expect_event_mask(P22E_EVENT_QUEUE_ERROR_MASK, "QUEUE_ERROR_EVENT");
        p22e_event_clear_and_expect_clear(P22E_EVENT_QUEUE_ERROR_MASK, "QUEUE_ERROR_EVENT");
        csr_queue_clear_sticky_status();
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

        `uvm_info("P22E_QUEUE_EVENT/START",
            "Starting P22E queue drained / stopped / error event smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P22E_QUEUE_EVENT/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        // Preload the descriptor tables needed by the inherited P20F STOP_QUEUE case.
        program_memory_descriptor(
            P22E_STOP_DESC_BASE0 + (0 * P22E_STOP_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            P22E_STOP_DESC0_TAG0
        );

        program_memory_descriptor(
            P22E_STOP_DESC_BASE0 + (1 * P22E_STOP_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            P22E_STOP_DESC0_TAG1
        );

        program_memory_descriptor(
            P22E_STOP_DESC_BASE1 + (0 * P22E_STOP_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            P22E_STOP_DESC1_TAG0
        );

        program_memory_descriptor(
            P22E_STOP_DESC_BASE1 + (1 * P22E_STOP_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            P22E_STOP_DESC1_TAG1
        );

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();
        p22e_event_clear_all("initialization");

        p22e_case_empty_drained_event();
        p22e_case_stop_event(profile_item, expected_c);
        p22e_case_queue_error_event();

        `uvm_info("P22E_QUEUE_EVENT/PASS",
            $sformatf("P22E queue terminal event smoke completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d checked=drained,stopped,error",
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
