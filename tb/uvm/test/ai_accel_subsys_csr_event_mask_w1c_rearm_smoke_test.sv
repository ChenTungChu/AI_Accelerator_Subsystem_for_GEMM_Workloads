// ============================================================
// File: tb/uvm/test/ai_accel_subsys_csr_event_mask_w1c_rearm_smoke_test.sv
// Purpose:
//   P22F integrated Event CSR smoke for mask, W1C clear, and
//   re-arm behavior.
//
// Scope:
//   - Runs on the existing ai_accel_subsys_csr_uvm_top.
//   - Uses the existing AXI-Lite CSR access helper.
//   - Does not instantiate a standalone event CSR block.
//   - Does not require a standalone event inject interface.
//   - Uses CSR_EVENT_COMMAND.FORCE_TEST_EVENT as a deterministic
//     event source so the test is isolated to interrupt-lite CSR
//     mask / clear / re-arm semantics.
// ============================================================

`ifndef AI_ACCEL_SUBSYS_CSR_EVENT_MASK_W1C_REARM_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_EVENT_MASK_W1C_REARM_SMOKE_TEST_SV

class ai_accel_subsys_csr_event_mask_w1c_rearm_smoke_test extends uvm_test;
    `uvm_component_utils(ai_accel_subsys_csr_event_mask_w1c_rearm_smoke_test)

    typedef virtual axi_lite_if #(
        .ADDR_WIDTH (12),
        .DATA_WIDTH (32)
    ) csr_vif_t;

    localparam logic [11:0] CSR_EVENT_COMMAND      = 12'h604;
    localparam logic [11:0] CSR_EVENT_STATUS       = 12'h608;
    localparam logic [11:0] CSR_EVENT_PENDING      = 12'h60C;
    localparam logic [11:0] CSR_EVENT_ENABLE       = 12'h610;
    localparam logic [11:0] CSR_EVENT_CONTROL      = 12'h614;
    localparam logic [11:0] CSR_EVENT_LAST_CAUSE   = 12'h618;
    localparam logic [11:0] CSR_EVENT_COUNT        = 12'h61C;
    localparam logic [11:0] CSR_EVENT_IRQ_COUNT    = 12'h62C;

    localparam int EVENT_CMD_CLEAR_PENDING  = 0;
    localparam int EVENT_CMD_FORCE_TEST     = 1;
    localparam int EVENT_CMD_CLEAR_COUNTERS = 8;

    localparam int EVENT_CONTROL_GLOBAL_IRQ_ENABLE = 0;
    localparam int EVENT_CONTROL_CAPTURE_SNAPSHOT  = 2;
    localparam int EVENT_CONTROL_COUNT_TEST_EVENTS = 3;

    localparam int P22_EVENT_TEST = 10;

    localparam logic [31:0] EVENT_TEST_MASK = (32'h1 << P22_EVENT_TEST);

    csr_vif_t csr_vif;
    ai_accel_csr_access_helper csr;

    function new(string name = "ai_accel_subsys_csr_event_mask_w1c_rearm_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(csr_vif_t)::get(this, "", "csr_vif", csr_vif)) begin
            `uvm_fatal("P22F_EVENT/NOCSRVIF", "csr_vif was not provided")
        end

        csr = ai_accel_csr_access_helper::type_id::create("csr");
        csr.set_vif(csr_vif);
    endfunction

    task automatic write32_ok(input logic [11:0] addr, input logic [31:0] data);
    begin
        csr.write32_expect_okay(addr, data, 4'hF);
    end
    endtask

    task automatic expect_read32(input logic [11:0] addr,
                                 input logic [31:0] expected,
                                 input string       what);
        logic [31:0] data;
    begin
        csr.read32_expect_okay(addr, data);
        if (data !== expected) begin
            `uvm_fatal("P22F_EVENT/RD_MISMATCH",
                $sformatf("%s addr=0x%03h expected=0x%08h actual=0x%08h",
                    what, addr, expected, data))
        end
        `uvm_info("P22F_EVENT/CHECK",
            $sformatf("%s PASS: addr=0x%03h data=0x%08h", what, addr, data),
            UVM_LOW)
    end
    endtask

    task automatic expect_bits_set(input logic [11:0] addr,
                                   input logic [31:0] set_mask,
                                   input string       what);
        logic [31:0] data;
    begin
        csr.read32_expect_okay(addr, data);
        if ((data & set_mask) !== set_mask) begin
            `uvm_fatal("P22F_EVENT/BITS_NOT_SET",
                $sformatf("%s addr=0x%03h mask=0x%08h actual=0x%08h",
                    what, addr, set_mask, data))
        end
        `uvm_info("P22F_EVENT/CHECK",
            $sformatf("%s PASS: addr=0x%03h mask=0x%08h actual=0x%08h",
                what, addr, set_mask, data),
            UVM_LOW)
    end
    endtask

    task automatic expect_bits_clear(input logic [11:0] addr,
                                     input logic [31:0] clear_mask,
                                     input string       what);
        logic [31:0] data;
    begin
        csr.read32_expect_okay(addr, data);
        if ((data & clear_mask) !== 32'h0000_0000) begin
            `uvm_fatal("P22F_EVENT/BITS_NOT_CLEAR",
                $sformatf("%s addr=0x%03h mask=0x%08h actual=0x%08h",
                    what, addr, clear_mask, data))
        end
        `uvm_info("P22F_EVENT/CHECK",
            $sformatf("%s PASS: addr=0x%03h mask=0x%08h actual=0x%08h",
                what, addr, clear_mask, data),
            UVM_LOW)
    end
    endtask

    task automatic force_test_event(input string what);
    begin
        write32_ok(CSR_EVENT_COMMAND, (32'h1 << EVENT_CMD_FORCE_TEST));
        `uvm_info("P22F_EVENT/FORCE", $sformatf("Forced TEST_EVENT: %s", what), UVM_LOW)
    end
    endtask

    task automatic clear_pending_and_counters(input string what);
    begin
        write32_ok(CSR_EVENT_COMMAND,
                   (32'h1 << EVENT_CMD_CLEAR_PENDING) |
                   (32'h1 << EVENT_CMD_CLEAR_COUNTERS));
        expect_read32(CSR_EVENT_PENDING,   32'h0000_0000, {what, ": pending clear"});
        expect_read32(CSR_EVENT_COUNT,     32'h0000_0000, {what, ": event count clear"});
        expect_read32(CSR_EVENT_IRQ_COUNT, 32'h0000_0000, {what, ": irq count clear"});
        expect_read32(CSR_EVENT_LAST_CAUSE,32'h0000_0000, {what, ": last cause clear"});
    end
    endtask

    task run_phase(uvm_phase phase);
        logic [31:0] status_word;
    begin
        phase.raise_objection(this);

        `uvm_info("P22F_EVENT/START",
            "Starting P22F Event mask / W1C clear / re-arm smoke on ai_accel_subsys_csr_uvm_top",
            UVM_LOW)

        csr.init_bus();
        csr.wait_reset_release();

        // Known baseline: no enabled event, no global IRQ, snapshot capture left on.
        write32_ok(CSR_EVENT_ENABLE,  32'h0000_0000);
        write32_ok(CSR_EVENT_CONTROL, (32'h1 << EVENT_CONTROL_CAPTURE_SNAPSHOT));
        clear_pending_and_counters("initialization");
        expect_bits_clear(CSR_EVENT_STATUS, 32'h0000_0047,
            "initial status has no pending, no enabled-pending, no irq, no TEST_EVENT");

        // ------------------------------------------------------------
        // Masked capture: a disabled event must still become pending,
        // but must not assert IRQ summary or increment IRQ counter.
        // ------------------------------------------------------------
        force_test_event("masked capture with EVENT_ENABLE=0 and GLOBAL_IRQ_ENABLE=0");
        expect_read32(CSR_EVENT_PENDING, EVENT_TEST_MASK,
            "masked TEST_EVENT captured into pending");
        expect_bits_set(CSR_EVENT_STATUS, 32'h0000_0041,
            "masked TEST_EVENT sets pending-any and test-event status");
        expect_bits_clear(CSR_EVENT_STATUS, 32'h0000_000E,
            "masked TEST_EVENT keeps enabled-pending, irq summary, and global-enable status clear");
        expect_read32(CSR_EVENT_COUNT,     32'h0000_0000,
            "masked TEST_EVENT not counted while COUNT_TEST_EVENTS=0");
        expect_read32(CSR_EVENT_IRQ_COUNT, 32'h0000_0000,
            "masked TEST_EVENT does not increment IRQ counter");

        // Late mask enable should expose the already-pending event as enabled-pending,
        // but IRQ summary must remain low until global IRQ is enabled.
        write32_ok(CSR_EVENT_ENABLE, EVENT_TEST_MASK);
        expect_read32(CSR_EVENT_PENDING, EVENT_TEST_MASK,
            "late enable preserves pending TEST_EVENT");
        expect_bits_set(CSR_EVENT_STATUS, 32'h0000_0043,
            "late enable sets enabled-pending for already-pending TEST_EVENT");
        expect_bits_clear(CSR_EVENT_STATUS, 32'h0000_000C,
            "late enable without global IRQ keeps irq summary low");
        expect_read32(CSR_EVENT_IRQ_COUNT, 32'h0000_0000,
            "late enable alone does not increment IRQ counter");

        // Global IRQ enable turns the already-pending enabled event into a level IRQ.
        write32_ok(CSR_EVENT_CONTROL,
                   (32'h1 << EVENT_CONTROL_GLOBAL_IRQ_ENABLE) |
                   (32'h1 << EVENT_CONTROL_CAPTURE_SNAPSHOT));
        expect_bits_set(CSR_EVENT_STATUS, 32'h0000_004F,
            "late global IRQ enable asserts level IRQ for already-pending TEST_EVENT");
        expect_read32(CSR_EVENT_IRQ_COUNT, 32'h0000_0000,
            "late global IRQ enable does not back-count old pending event");

        // Mask disable while pending must suppress IRQ but must not clear pending.
        write32_ok(CSR_EVENT_ENABLE, 32'h0000_0000);
        expect_read32(CSR_EVENT_PENDING, EVENT_TEST_MASK,
            "mask disable preserves pending TEST_EVENT");
        expect_bits_set(CSR_EVENT_STATUS, 32'h0000_0049,
            "mask disable keeps pending/test/global status");
        expect_bits_clear(CSR_EVENT_STATUS, 32'h0000_0006,
            "mask disable suppresses enabled-pending and irq summary");

        // Re-enable mask should re-assert level IRQ from the still-pending event.
        write32_ok(CSR_EVENT_ENABLE, EVENT_TEST_MASK);
        expect_bits_set(CSR_EVENT_STATUS, 32'h0000_004F,
            "mask re-enable reasserts level IRQ for still-pending TEST_EVENT");

        // W1C with an invalid bit must not clear valid pending bits.
        write32_ok(CSR_EVENT_PENDING, 32'h8000_0000);
        expect_read32(CSR_EVENT_PENDING, EVENT_TEST_MASK,
            "invalid W1C bit does not clear valid TEST_EVENT pending");

        // W1C clear must deassert pending and IRQ summary while preserving global-enable status.
        write32_ok(CSR_EVENT_PENDING, EVENT_TEST_MASK);
        expect_read32(CSR_EVENT_PENDING, 32'h0000_0000,
            "W1C clears TEST_EVENT pending");
        expect_bits_clear(CSR_EVENT_STATUS, 32'h0000_0047,
            "W1C deasserts pending/irq/test status");
        expect_bits_set(CSR_EVENT_STATUS, 32'h0000_0008,
            "W1C preserves global IRQ enable status bit");

        // ------------------------------------------------------------
        // Re-arm proof: after W1C clear, the same event source must be
        // able to set pending and IRQ summary again on a new source pulse.
        // COUNT_TEST_EVENTS is enabled here to also prove repeated source
        // pulses are counted once per re-armed event.
        // ------------------------------------------------------------
        write32_ok(CSR_EVENT_CONTROL,
                   (32'h1 << EVENT_CONTROL_GLOBAL_IRQ_ENABLE) |
                   (32'h1 << EVENT_CONTROL_CAPTURE_SNAPSHOT)  |
                   (32'h1 << EVENT_CONTROL_COUNT_TEST_EVENTS));
        clear_pending_and_counters("before re-arm sequence");
        write32_ok(CSR_EVENT_ENABLE, EVENT_TEST_MASK);

        force_test_event("re-arm pulse 0 after W1C baseline");
        expect_read32(CSR_EVENT_PENDING, EVENT_TEST_MASK,
            "re-arm pulse 0 sets TEST_EVENT pending");
        expect_bits_set(CSR_EVENT_STATUS, 32'h0000_004F,
            "re-arm pulse 0 asserts IRQ summary");
        expect_read32(CSR_EVENT_COUNT,     32'h0000_0001,
            "re-arm pulse 0 increments event count");
        expect_read32(CSR_EVENT_IRQ_COUNT, 32'h0000_0001,
            "re-arm pulse 0 increments IRQ count");

        write32_ok(CSR_EVENT_PENDING, EVENT_TEST_MASK);
        expect_read32(CSR_EVENT_PENDING, 32'h0000_0000,
            "re-arm pulse 0 W1C clear");
        expect_bits_clear(CSR_EVENT_STATUS, 32'h0000_0047,
            "re-arm pulse 0 W1C deasserts event status");

        force_test_event("re-arm pulse 1 after W1C clear");
        expect_read32(CSR_EVENT_PENDING, EVENT_TEST_MASK,
            "re-arm pulse 1 sets TEST_EVENT pending again");
        expect_bits_set(CSR_EVENT_STATUS, 32'h0000_004F,
            "re-arm pulse 1 asserts IRQ summary again");
        expect_read32(CSR_EVENT_COUNT,     32'h0000_0002,
            "re-arm pulse 1 increments event count again");
        expect_read32(CSR_EVENT_IRQ_COUNT, 32'h0000_0002,
            "re-arm pulse 1 increments IRQ count again");

        // CLEAR_PENDING command is an alternate all-event clear path; it should
        // also allow a subsequent event to re-arm.
        write32_ok(CSR_EVENT_COMMAND, (32'h1 << EVENT_CMD_CLEAR_PENDING));
        expect_read32(CSR_EVENT_PENDING, 32'h0000_0000,
            "CLEAR_PENDING command clears TEST_EVENT pending");
        expect_bits_clear(CSR_EVENT_STATUS, 32'h0000_0047,
            "CLEAR_PENDING command deasserts event status");

        force_test_event("re-arm pulse 2 after CLEAR_PENDING command");
        expect_read32(CSR_EVENT_PENDING, EVENT_TEST_MASK,
            "re-arm pulse 2 sets TEST_EVENT pending after CLEAR_PENDING");
        expect_bits_set(CSR_EVENT_STATUS, 32'h0000_004F,
            "re-arm pulse 2 asserts IRQ summary after CLEAR_PENDING");
        expect_read32(CSR_EVENT_COUNT,     32'h0000_0003,
            "re-arm pulse 2 increments event count after CLEAR_PENDING");
        expect_read32(CSR_EVENT_IRQ_COUNT, 32'h0000_0003,
            "re-arm pulse 2 increments IRQ count after CLEAR_PENDING");

        clear_pending_and_counters("final cleanup");
        csr.read32_expect_okay(CSR_EVENT_STATUS, status_word);
        if ((status_word & 32'h0000_0047) != 32'h0000_0000) begin
            `uvm_fatal("P22F_EVENT/FINAL_STATUS_STUCK",
                $sformatf("Expected final event bits clear, status=0x%08h", status_word))
        end

        `uvm_info("P22F_EVENT/PASS",
            "P22F Event mask / W1C clear / re-arm smoke completed: masked capture, late enable, mask suppress/re-enable, invalid W1C ignore, W1C clear, CLEAR_PENDING, and repeated re-arm all passed",
            UVM_LOW)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
