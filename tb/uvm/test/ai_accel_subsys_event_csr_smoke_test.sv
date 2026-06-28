// File: tb/uvm/test/ai_accel_subsys_event_csr_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_EVENT_CSR_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_EVENT_CSR_SMOKE_TEST_SV

// ============================================================
// P22C integrated Event CSR smoke
//
// This test intentionally runs on the existing CSR subsystem top:
//
//   UVM_TOP  = ai_accel_subsys_csr_uvm_top
//   UVM_TEST = ai_accel_subsys_event_csr_smoke_test
//
// There is no standalone event CSR block, no standalone event inject
// interface, and no standalone UVM top.  P22C extends the existing
// ai_accel_csr_regs 0x600-0x63C window and proves the software-visible
// interrupt-lite event CSRs through the same AXI-Lite helper used by the
// rest of the CSR tests.
// ============================================================

class ai_accel_subsys_event_csr_smoke_test extends uvm_test;
    `uvm_component_utils(ai_accel_subsys_event_csr_smoke_test)

    typedef virtual axi_lite_if #(
        .ADDR_WIDTH (12),
        .DATA_WIDTH (32)
    ) csr_vif_t;

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    localparam logic [11:0] CSR_EVENT_VERSION      = 12'h600;
    localparam logic [11:0] CSR_EVENT_COMMAND      = 12'h604;
    localparam logic [11:0] CSR_EVENT_STATUS       = 12'h608;
    localparam logic [11:0] CSR_EVENT_PENDING      = 12'h60C;
    localparam logic [11:0] CSR_EVENT_ENABLE       = 12'h610;
    localparam logic [11:0] CSR_EVENT_CONTROL      = 12'h614;
    localparam logic [11:0] CSR_EVENT_LAST_CAUSE   = 12'h618;
    localparam logic [11:0] CSR_EVENT_COUNT        = 12'h61C;
    localparam logic [11:0] CSR_EVENT_SNAPSHOT0    = 12'h620;
    localparam logic [11:0] CSR_EVENT_SNAPSHOT1    = 12'h624;
    localparam logic [11:0] CSR_EVENT_CQ_THRESHOLD = 12'h628;
    localparam logic [11:0] CSR_EVENT_IRQ_COUNT    = 12'h62C;

    // P27 memory guard CSRs occupy 0x640-0x6BC and P29 runtime
    // telemetry CSRs occupy 0x6C0-0x73C.  The event-window invalid-
    // address probe must stay beyond all allocated CSR windows.
    localparam logic [11:0] CSR_EVENT_INVALID_ADDR = 12'h740;

    localparam int EVENT_CMD_CLEAR_PENDING  = 0;
    localparam int EVENT_CMD_FORCE_TEST     = 1;
    localparam int EVENT_CMD_CLEAR_COUNTERS = 8;

    localparam int EVENT_CONTROL_GLOBAL_IRQ_ENABLE = 0;
    localparam int EVENT_CONTROL_CAPTURE_SNAPSHOT  = 2;
    localparam int EVENT_CONTROL_COUNT_TEST_EVENTS = 3;

    localparam int P22_EVENT_TEST = 10;

    csr_vif_t csr_vif;
    ai_accel_csr_access_helper csr;

    function new(string name = "ai_accel_subsys_event_csr_smoke_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(csr_vif_t)::get(this, "", "csr_vif", csr_vif)) begin
            `uvm_fatal("P22C_EVENT_CSR/NOCSRVIF", "csr_vif was not provided")
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
            `uvm_fatal("P22C_EVENT_CSR/RD_MISMATCH",
                $sformatf("%s addr=0x%03h expected=0x%08h actual=0x%08h",
                    what, addr, expected, data))
        end
        `uvm_info("P22C_EVENT_CSR/CHECK",
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
            `uvm_fatal("P22C_EVENT_CSR/BITS_NOT_SET",
                $sformatf("%s addr=0x%03h mask=0x%08h actual=0x%08h",
                    what, addr, set_mask, data))
        end
        `uvm_info("P22C_EVENT_CSR/CHECK",
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
            `uvm_fatal("P22C_EVENT_CSR/BITS_NOT_CLEAR",
                $sformatf("%s addr=0x%03h mask=0x%08h actual=0x%08h",
                    what, addr, clear_mask, data))
        end
        `uvm_info("P22C_EVENT_CSR/CHECK",
            $sformatf("%s PASS: addr=0x%03h mask=0x%08h actual=0x%08h",
                what, addr, clear_mask, data),
            UVM_LOW)
    end
    endtask

    task run_phase(uvm_phase phase);
        logic [31:0] data;
        logic [1:0]  resp;
        logic [31:0] status_word;
        logic [31:0] expected_cause;
    begin
        phase.raise_objection(this);

        `uvm_info("P22C_EVENT_CSR/START",
            "Starting P22C integrated Event CSR smoke on ai_accel_subsys_csr_uvm_top",
            UVM_LOW)

        csr.init_bus();
        csr.wait_reset_release();

        // Reset defaults and address decode.
        expect_read32(CSR_EVENT_VERSION,   32'h0001_0022, "EVENT_VERSION reset");
        expect_read32(CSR_EVENT_COMMAND,   32'h0000_0000, "EVENT_COMMAND reads zero");
        expect_read32(CSR_EVENT_STATUS,    32'h0000_0000, "EVENT_STATUS reset");
        expect_read32(CSR_EVENT_PENDING,   32'h0000_0000, "EVENT_PENDING reset");
        expect_read32(CSR_EVENT_ENABLE,    32'h0000_0000, "EVENT_ENABLE reset");
        expect_read32(CSR_EVENT_CONTROL,   32'h0000_0004, "EVENT_CONTROL reset");
        expect_read32(CSR_EVENT_COUNT,     32'h0000_0000, "EVENT_COUNT reset");
        expect_read32(CSR_EVENT_IRQ_COUNT, 32'h0000_0000, "EVENT_IRQ_COUNT reset");

        csr.read32(CSR_EVENT_INVALID_ADDR, data, resp);
        if (resp != AXI_RESP_SLVERR) begin
            `uvm_fatal("P22C_EVENT_CSR/BAD_READ_RESP",
                $sformatf("Expected SLVERR for invalid event read, got resp=%0b data=0x%08h", resp, data))
        end

        csr.write32(CSR_EVENT_INVALID_ADDR, 32'hCAFE_0022, 4'hF, resp);
        if (resp != AXI_RESP_SLVERR) begin
            `uvm_fatal("P22C_EVENT_CSR/BAD_WRITE_RESP",
                $sformatf("Expected SLVERR for invalid event write, got resp=%0b", resp))
        end

        // TEST_EVENT capture without IRQ enable.
        write32_ok(CSR_EVENT_COMMAND, (32'h1 << EVENT_CMD_FORCE_TEST));
        expect_read32(CSR_EVENT_PENDING, 32'h0000_0400, "TEST_EVENT pending captured with IRQ disabled");
        expect_bits_set(CSR_EVENT_STATUS, 32'h0000_0041, "pending and test-event status set");
        expect_bits_clear(CSR_EVENT_STATUS, 32'h0000_0006, "IRQ summary remains clear while event disabled");
        expect_read32(CSR_EVENT_COUNT, 32'h0000_0000, "TEST_EVENT not counted when COUNT_TEST_EVENTS=0");

        expected_cause = {8'h00, 8'h00, 8'h06, 8'h0A};
        expect_read32(CSR_EVENT_LAST_CAUSE, expected_cause, "last cause software TEST_EVENT");

        // Enable TEST_EVENT and global IRQ; already-pending event should assert level IRQ.
        write32_ok(CSR_EVENT_ENABLE,  (32'h1 << P22_EVENT_TEST));
        write32_ok(CSR_EVENT_CONTROL,
                   (32'h1 << EVENT_CONTROL_GLOBAL_IRQ_ENABLE) |
                   (32'h1 << EVENT_CONTROL_CAPTURE_SNAPSHOT)  |
                   (32'h1 << EVENT_CONTROL_COUNT_TEST_EVENTS));
        expect_bits_set(CSR_EVENT_STATUS, 32'h0000_0047, "level IRQ summary asserted after enabling pending TEST_EVENT");

        // W1C clear should deassert IRQ summary.
        write32_ok(CSR_EVENT_PENDING, (32'h1 << P22_EVENT_TEST));
        expect_read32(CSR_EVENT_PENDING, 32'h0000_0000, "TEST_EVENT pending W1C clear");
        expect_bits_clear(CSR_EVENT_STATUS, 32'h0000_0047, "event status clear after W1C");

        // Counter clear and counted TEST_EVENT when enabled.
        write32_ok(CSR_EVENT_COMMAND, (32'h1 << EVENT_CMD_CLEAR_COUNTERS));
        expect_read32(CSR_EVENT_COUNT,     32'h0000_0000, "event count cleared");
        expect_read32(CSR_EVENT_IRQ_COUNT, 32'h0000_0000, "irq count cleared");
        expect_read32(CSR_EVENT_LAST_CAUSE,32'h0000_0000, "last cause cleared");

        write32_ok(CSR_EVENT_COMMAND, (32'h1 << EVENT_CMD_FORCE_TEST));
        expect_read32(CSR_EVENT_PENDING,   32'h0000_0400, "second TEST_EVENT pending");
        expect_read32(CSR_EVENT_COUNT,     32'h0000_0001, "TEST_EVENT counted when COUNT_TEST_EVENTS=1");
        expect_read32(CSR_EVENT_IRQ_COUNT, 32'h0000_0001, "IRQ count increments for enabled TEST_EVENT");
        expect_bits_set(CSR_EVENT_STATUS, 32'h0000_0047, "second TEST_EVENT IRQ status set");

        // Threshold register is RW storage in P22C.  Real queue-driven threshold
        // event proof is intentionally left for P22D/P22E integration tests.
        write32_ok(CSR_EVENT_CQ_THRESHOLD, 32'h0000_0002);
        expect_read32(CSR_EVENT_CQ_THRESHOLD, 32'h0000_0002, "CQ threshold RW storage");

        // CLEAR_PENDING command and final clear.
        write32_ok(CSR_EVENT_COMMAND,
                   (32'h1 << EVENT_CMD_CLEAR_PENDING) |
                   (32'h1 << EVENT_CMD_CLEAR_COUNTERS));
        expect_read32(CSR_EVENT_PENDING,   32'h0000_0000, "final pending clear");
        expect_read32(CSR_EVENT_COUNT,     32'h0000_0000, "final event count clear");
        expect_read32(CSR_EVENT_IRQ_COUNT, 32'h0000_0000, "final irq count clear");
        expect_read32(CSR_EVENT_LAST_CAUSE,32'h0000_0000, "final last cause clear");
        expect_read32(CSR_EVENT_SNAPSHOT0, 32'h0000_0000, "final snapshot0 clear");
        expect_read32(CSR_EVENT_SNAPSHOT1, 32'h0000_0000, "final snapshot1 clear");

        csr.read32_expect_okay(CSR_EVENT_STATUS, status_word);
        if (status_word[2] !== 1'b0) begin
            `uvm_fatal("P22C_EVENT_CSR/FINAL_IRQ_STUCK",
                $sformatf("Expected final IRQ summary low, status=0x%08h", status_word))
        end

        `uvm_info("P22C_EVENT_CSR/PASS",
            "P22C integrated Event CSR smoke completed: event window reset/readback, TEST_EVENT, mask/global IRQ summary, W1C/CLEAR_PENDING, counters, threshold RW, and P29-aware invalid-address SLVERR all passed",
            UVM_LOW)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
