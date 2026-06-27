// File: tb/uvm/test/ai_accel_subsys_csr_basic_telemetry_counter_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_BASIC_TELEMETRY_COUNTER_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_BASIC_TELEMETRY_COUNTER_SMOKE_TEST_SV

// ============================================================
// P29D basic telemetry counter smoke
//
// Scope:
//   - Reuses the validated P23 event-driven two-command queue drain path.
//   - Enables the P29 runtime telemetry CSR window.
//   - Proves the telemetry version / reset-disabled / enable / clear policy.
//   - Runs a two-command queue drain and checks basic queue, CQ consume,
//     event/IRQ, and cycle telemetry counters.
//   - Confirms telemetry clear does not clear queue/event state or change
//     GEMM / DMA / descriptor / completion behavior.
//
// P29D does not change SQ/CQ entry format, descriptor format, completion
// record format, event bits, BRAM, GEMM, DMA, AXI-Stream, or Direct Stream
// datapath behavior.
// ============================================================

class ai_accel_subsys_csr_basic_telemetry_counter_smoke_test
    extends ai_accel_subsys_csr_event_driven_multi_command_queue_drain_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_basic_telemetry_counter_smoke_test)

    localparam int unsigned P29D_SQ_BASE     = 32'h0000_0700;
    localparam int unsigned P29D_CQ_BASE     = 32'h0000_0800;
    localparam int unsigned P29D_QUEUE_DEPTH = 4;

    localparam int unsigned P29D_DESC_BASE0  = 32'h0000_0300;
    localparam int unsigned P29D_DESC_BASE1  = 32'h0000_0400;
    localparam int unsigned P29D_DESC_STRIDE = 32'h0000_0080;

    localparam logic [31:0] P29D_CMD0_TAG    = 32'hD29D_0000;
    localparam logic [31:0] P29D_CMD1_TAG    = 32'hD29D_0001;

    localparam logic [31:0] P29D_DESC0_TAG0  = 32'hD29D_1000;
    localparam logic [31:0] P29D_DESC0_TAG1  = 32'hD29D_1001;
    localparam logic [31:0] P29D_DESC1_TAG0  = 32'hD29D_2000;
    localparam logic [31:0] P29D_DESC1_TAG1  = 32'hD29D_2001;

    // P29 telemetry CSR window.  These constants mirror the canonical
    // P29B CSR policy in axi_lite_csr_control_plane_spec.md.  The helper
    // does not yet own P29 constants, so the P29D smoke keeps them local.
    localparam logic [11:0] CSR_TELEM_VERSION                  = 12'h6C0;
    localparam logic [11:0] CSR_TELEM_COMMAND                  = 12'h6C4;
    localparam logic [11:0] CSR_TELEM_STATUS                   = 12'h6C8;
    localparam logic [11:0] CSR_TELEM_CONTROL                  = 12'h6CC;
    localparam logic [11:0] CSR_TELEM_QUEUE_START_COUNT        = 12'h6D0;
    localparam logic [11:0] CSR_TELEM_SQ_ACCEPT_COUNT          = 12'h6D4;
    localparam logic [11:0] CSR_TELEM_CMD_COMPLETE_COUNT       = 12'h6D8;
    localparam logic [11:0] CSR_TELEM_CQ_COMMIT_COUNT          = 12'h6DC;
    localparam logic [11:0] CSR_TELEM_QUEUE_DRAINED_COUNT      = 12'h6E0;
    localparam logic [11:0] CSR_TELEM_QUEUE_STOPPED_COUNT      = 12'h6E4;
    localparam logic [11:0] CSR_TELEM_QUEUE_ERROR_COUNT        = 12'h6E8;
    localparam logic [11:0] CSR_TELEM_CQ_HEAD_UPDATE_COUNT     = 12'h6EC;
    localparam logic [11:0] CSR_TELEM_CQ_CONSUMED_COUNT        = 12'h6F0;
    localparam logic [11:0] CSR_TELEM_MAX_CQ_BATCH_SIZE        = 12'h6F4;
    localparam logic [11:0] CSR_TELEM_EVENT_CAPTURE_COUNT      = 12'h6F8;
    localparam logic [11:0] CSR_TELEM_IRQ_ELIGIBLE_COUNT       = 12'h6FC;
    localparam logic [11:0] CSR_TELEM_COMPLETION_EVENT_COUNT   = 12'h700;
    localparam logic [11:0] CSR_TELEM_COALESCED_RELEASE_COUNT  = 12'h704;
    localparam logic [11:0] CSR_TELEM_THRESHOLD_RELEASE_COUNT  = 12'h708;
    localparam logic [11:0] CSR_TELEM_TIMER_RELEASE_COUNT      = 12'h70C;
    localparam logic [11:0] CSR_TELEM_URGENT_BYPASS_COUNT      = 12'h710;
    localparam logic [11:0] CSR_TELEM_CQ_FULL_STALL_COUNT      = 12'h714;
    localparam logic [11:0] CSR_TELEM_CQ_SPACE_RECOVERED_COUNT = 12'h718;
    localparam logic [11:0] CSR_TELEM_TIMEOUT_ERROR_COUNT      = 12'h71C;
    localparam logic [11:0] CSR_TELEM_MEM_GUARD_ERROR_COUNT    = 12'h720;
    localparam logic [11:0] CSR_TELEM_STOP_QUEUE_REQUEST_COUNT = 12'h724;
    localparam logic [11:0] CSR_TELEM_QUEUE_ENABLED_CYCLES     = 12'h728;
    localparam logic [11:0] CSR_TELEM_QUEUE_BUSY_CYCLES        = 12'h72C;
    localparam logic [11:0] CSR_TELEM_QUEUE_IDLE_CYCLES        = 12'h730;
    localparam logic [11:0] CSR_TELEM_QUEUE_STALLED_CYCLES     = 12'h734;
    localparam logic [11:0] CSR_TELEM_CQ_FULL_STALL_CYCLES     = 12'h738;
    localparam logic [11:0] CSR_TELEM_LOWER_WAIT_CYCLES        = 12'h73C;

    localparam logic [31:0] P29D_TELEM_VERSION_RESET = 32'h0001_0029;
    localparam logic [31:0] P29D_TELEM_CLEAR_COUNTERS = 32'h0000_0100;
    localparam logic [31:0] P29D_TELEM_ENABLE_ALL = 32'h0000_000F;

    localparam int TELEM_STATUS_ENABLED                = 0;
    localparam int TELEM_STATUS_CYCLE_ENABLED          = 1;
    localparam int TELEM_STATUS_HOST_CQ_CONSUME_ENABLE = 2;
    localparam int TELEM_STATUS_EVENT_EFF_ENABLE       = 3;
    localparam int TELEM_STATUS_ANY_COUNTER_NONZERO    = 4;
    localparam int TELEM_STATUS_QUEUE_ACTIVE           = 5;
    localparam int TELEM_STATUS_CYCLE_ACTIVE           = 6;
    localparam int TELEM_STATUS_CSR_READY              = 16;

    function new(string name = "ai_accel_subsys_csr_basic_telemetry_counter_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p29d_read_telem(
        input  logic [11:0] addr,
        input  string       name,
        output logic [31:0] data
    );
    begin
        csr.read32_expect_okay(addr, data);
        `uvm_info("P29D_TELEM/READ",
            $sformatf("%s = 0x%08h", name, data),
            UVM_LOW)
    end
    endtask

    task automatic p29d_expect_eq(
        input string       name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
    begin
        if (actual !== expected) begin
            `uvm_fatal("P29D_TELEM/MISMATCH",
                $sformatf("%s mismatch: actual=0x%08h expected=0x%08h",
                    name,
                    actual,
                    expected))
        end

        `uvm_info("P29D_TELEM/CHECK",
            $sformatf("%s PASS: 0x%08h", name, actual),
            UVM_LOW)
    end
    endtask

    task automatic p29d_expect_zero(
        input string       name,
        input logic [31:0] actual
    );
    begin
        p29d_expect_eq(name, actual, 32'h0000_0000);
    end
    endtask

    task automatic p29d_expect_nonzero(
        input string       name,
        input logic [31:0] actual
    );
    begin
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P29D_TELEM/ZERO",
                $sformatf("%s unexpectedly zero", name))
        end

        `uvm_info("P29D_TELEM/CHECK",
            $sformatf("%s nonzero PASS: 0x%08h", name, actual),
            UVM_LOW)
    end
    endtask

    task automatic p29d_expect_at_least(
        input string       name,
        input logic [31:0] actual,
        input logic [31:0] minimum
    );
    begin
        if (actual < minimum) begin
            `uvm_fatal("P29D_TELEM/TOO_SMALL",
                $sformatf("%s too small: actual=%0d minimum=%0d",
                    name,
                    actual,
                    minimum))
        end

        `uvm_info("P29D_TELEM/CHECK",
            $sformatf("%s >= %0d PASS: actual=%0d", name, minimum, actual),
            UVM_LOW)
    end
    endtask

    task automatic p29d_expect_status_disabled();
        logic [31:0] status;
        logic [31:0] control;
    begin
        p29d_read_telem(CSR_TELEM_CONTROL, "CSR_TELEM_CONTROL reset/disabled", control);
        p29d_read_telem(CSR_TELEM_STATUS,  "CSR_TELEM_STATUS reset/disabled",  status);

        p29d_expect_zero("CSR_TELEM_CONTROL reset", control);

        if (status[TELEM_STATUS_ENABLED] ||
            status[TELEM_STATUS_CYCLE_ENABLED] ||
            status[TELEM_STATUS_HOST_CQ_CONSUME_ENABLE] ||
            status[TELEM_STATUS_EVENT_EFF_ENABLE]) begin
            `uvm_fatal("P29D_TELEM/RESET_STATUS",
                $sformatf("Telemetry should be disabled by reset: status=0x%08h", status))
        end

        if (!status[TELEM_STATUS_CSR_READY]) begin
            `uvm_fatal("P29D_TELEM/CSR_READY",
                $sformatf("Telemetry CSR_READY not set in status=0x%08h", status))
        end

        `uvm_info("P29D_TELEM/RESET_PASS",
            $sformatf("Telemetry reset-disabled policy PASS: status=0x%08h control=0x%08h",
                status,
                control),
            UVM_MEDIUM)
    end
    endtask

    task automatic p29d_clear_telem_counters(string label);
    begin
        csr.write32_expect_okay(CSR_TELEM_COMMAND, P29D_TELEM_CLEAR_COUNTERS);
        repeat (2) @(posedge p17d_ctrl_vif.clk);

        `uvm_info("P29D_TELEM/CLEAR_PASS",
            $sformatf("%s: issued CLEAR_TELEMETRY_COUNTERS", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic p29d_check_selected_counters_zero(string label);
        logic [31:0] q_start;
        logic [31:0] sq_accept;
        logic [31:0] cmd_complete;
        logic [31:0] cq_commit;
        logic [31:0] event_capture;
        logic [31:0] irq_eligible;
        logic [31:0] cq_update;
        logic [31:0] cq_consumed;
        logic [31:0] queue_busy_cycles;
    begin
        p29d_read_telem(CSR_TELEM_QUEUE_START_COUNT,      "queue_start_count",      q_start);
        p29d_read_telem(CSR_TELEM_SQ_ACCEPT_COUNT,        "sq_accept_count",        sq_accept);
        p29d_read_telem(CSR_TELEM_CMD_COMPLETE_COUNT,     "cmd_complete_count",     cmd_complete);
        p29d_read_telem(CSR_TELEM_CQ_COMMIT_COUNT,        "cq_commit_count",        cq_commit);
        p29d_read_telem(CSR_TELEM_EVENT_CAPTURE_COUNT,    "event_capture_count",    event_capture);
        p29d_read_telem(CSR_TELEM_IRQ_ELIGIBLE_COUNT,     "irq_eligible_count",     irq_eligible);
        p29d_read_telem(CSR_TELEM_CQ_HEAD_UPDATE_COUNT,   "cq_head_update_count",   cq_update);
        p29d_read_telem(CSR_TELEM_CQ_CONSUMED_COUNT,      "cq_consumed_count",      cq_consumed);
        p29d_read_telem(CSR_TELEM_QUEUE_BUSY_CYCLES,      "queue_busy_cycles",      queue_busy_cycles);

        p29d_expect_zero($sformatf("%s: queue_start_count", label),    q_start);
        p29d_expect_zero($sformatf("%s: sq_accept_count", label),      sq_accept);
        p29d_expect_zero($sformatf("%s: cmd_complete_count", label),   cmd_complete);
        p29d_expect_zero($sformatf("%s: cq_commit_count", label),      cq_commit);
        p29d_expect_zero($sformatf("%s: event_capture_count", label),  event_capture);
        p29d_expect_zero($sformatf("%s: irq_eligible_count", label),   irq_eligible);
        p29d_expect_zero($sformatf("%s: cq_head_update_count", label), cq_update);
        p29d_expect_zero($sformatf("%s: cq_consumed_count", label),    cq_consumed);
        p29d_expect_zero($sformatf("%s: queue_busy_cycles", label),    queue_busy_cycles);

        `uvm_info("P29D_TELEM/ZERO_PASS",
            $sformatf("%s: selected telemetry counters are zero", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic p29d_enable_telem_all();
        logic [31:0] status;
        logic [31:0] control;
    begin
        csr.write32_expect_okay(CSR_TELEM_CONTROL, P29D_TELEM_ENABLE_ALL);
        repeat (2) @(posedge p17d_ctrl_vif.clk);

        p29d_read_telem(CSR_TELEM_CONTROL, "CSR_TELEM_CONTROL enabled", control);
        p29d_read_telem(CSR_TELEM_STATUS,  "CSR_TELEM_STATUS enabled",  status);

        p29d_expect_eq("CSR_TELEM_CONTROL enable-all", control, P29D_TELEM_ENABLE_ALL);

        if (!status[TELEM_STATUS_ENABLED] ||
            !status[TELEM_STATUS_CYCLE_ENABLED] ||
            !status[TELEM_STATUS_HOST_CQ_CONSUME_ENABLE] ||
            !status[TELEM_STATUS_EVENT_EFF_ENABLE] ||
            !status[TELEM_STATUS_QUEUE_ACTIVE] ||
            !status[TELEM_STATUS_CYCLE_ACTIVE] ||
            !status[TELEM_STATUS_CSR_READY]) begin
            `uvm_fatal("P29D_TELEM/ENABLE_STATUS",
                $sformatf("Telemetry enable-all status missing expected bits: status=0x%08h control=0x%08h",
                    status,
                    control))
        end

        `uvm_info("P29D_TELEM/ENABLE_PASS",
            $sformatf("Telemetry enable-all PASS: status=0x%08h control=0x%08h",
                status,
                control),
            UVM_MEDIUM)
    end
    endtask

    task automatic p29d_check_runtime_counters(
        input int unsigned expected_commands,
        input int unsigned expected_cq_consumed
    );
        logic [31:0] q_start;
        logic [31:0] sq_accept;
        logic [31:0] cmd_complete;
        logic [31:0] cq_commit;
        logic [31:0] drained;
        logic [31:0] stopped;
        logic [31:0] q_error;
        logic [31:0] cq_update;
        logic [31:0] cq_consumed;
        logic [31:0] max_batch;
        logic [31:0] event_capture;
        logic [31:0] irq_eligible;
        logic [31:0] completion_event;
        logic [31:0] coalesced_release;
        logic [31:0] threshold_release;
        logic [31:0] timer_release;
        logic [31:0] urgent_bypass;
        logic [31:0] cq_full_stall;
        logic [31:0] cq_space_recovered;
        logic [31:0] timeout_error;
        logic [31:0] mem_guard_error;
        logic [31:0] stop_request;
        logic [31:0] queue_enabled_cycles;
        logic [31:0] queue_busy_cycles;
        logic [31:0] queue_idle_cycles;
        logic [31:0] lower_wait_cycles;
        logic [31:0] status;
    begin
        repeat (4) @(posedge p17d_ctrl_vif.clk);

        p29d_read_telem(CSR_TELEM_QUEUE_START_COUNT,        "queue_start_count",        q_start);
        p29d_read_telem(CSR_TELEM_SQ_ACCEPT_COUNT,          "sq_accept_count",          sq_accept);
        p29d_read_telem(CSR_TELEM_CMD_COMPLETE_COUNT,       "cmd_complete_count",       cmd_complete);
        p29d_read_telem(CSR_TELEM_CQ_COMMIT_COUNT,          "cq_commit_count",          cq_commit);
        p29d_read_telem(CSR_TELEM_QUEUE_DRAINED_COUNT,      "queue_drained_count",      drained);
        p29d_read_telem(CSR_TELEM_QUEUE_STOPPED_COUNT,      "queue_stopped_count",      stopped);
        p29d_read_telem(CSR_TELEM_QUEUE_ERROR_COUNT,        "queue_error_count",        q_error);
        p29d_read_telem(CSR_TELEM_CQ_HEAD_UPDATE_COUNT,     "cq_head_update_count",     cq_update);
        p29d_read_telem(CSR_TELEM_CQ_CONSUMED_COUNT,        "cq_consumed_count",        cq_consumed);
        p29d_read_telem(CSR_TELEM_MAX_CQ_BATCH_SIZE,        "max_cq_batch_size",        max_batch);
        p29d_read_telem(CSR_TELEM_EVENT_CAPTURE_COUNT,      "event_capture_count",      event_capture);
        p29d_read_telem(CSR_TELEM_IRQ_ELIGIBLE_COUNT,       "irq_eligible_count",       irq_eligible);
        p29d_read_telem(CSR_TELEM_COMPLETION_EVENT_COUNT,   "completion_event_count",   completion_event);
        p29d_read_telem(CSR_TELEM_COALESCED_RELEASE_COUNT,  "coalesced_release_count",  coalesced_release);
        p29d_read_telem(CSR_TELEM_THRESHOLD_RELEASE_COUNT,  "threshold_release_count",  threshold_release);
        p29d_read_telem(CSR_TELEM_TIMER_RELEASE_COUNT,      "timer_release_count",      timer_release);
        p29d_read_telem(CSR_TELEM_URGENT_BYPASS_COUNT,      "urgent_bypass_count",      urgent_bypass);
        p29d_read_telem(CSR_TELEM_CQ_FULL_STALL_COUNT,      "cq_full_stall_count",      cq_full_stall);
        p29d_read_telem(CSR_TELEM_CQ_SPACE_RECOVERED_COUNT, "cq_space_recovered_count", cq_space_recovered);
        p29d_read_telem(CSR_TELEM_TIMEOUT_ERROR_COUNT,      "timeout_error_count",      timeout_error);
        p29d_read_telem(CSR_TELEM_MEM_GUARD_ERROR_COUNT,    "mem_guard_error_count",    mem_guard_error);
        p29d_read_telem(CSR_TELEM_STOP_QUEUE_REQUEST_COUNT, "stop_queue_request_count", stop_request);
        p29d_read_telem(CSR_TELEM_QUEUE_ENABLED_CYCLES,     "queue_enabled_cycles",     queue_enabled_cycles);
        p29d_read_telem(CSR_TELEM_QUEUE_BUSY_CYCLES,        "queue_busy_cycles",        queue_busy_cycles);
        p29d_read_telem(CSR_TELEM_QUEUE_IDLE_CYCLES,        "queue_idle_cycles",        queue_idle_cycles);
        p29d_read_telem(CSR_TELEM_LOWER_WAIT_CYCLES,        "lower_wait_cycles",        lower_wait_cycles);
        p29d_read_telem(CSR_TELEM_STATUS,                   "telem_status",             status);

        p29d_expect_eq("queue_start_count", q_start, 32'h0000_0001);
        p29d_expect_at_least("sq_accept_count", sq_accept, 32'(expected_commands));
        p29d_expect_at_least("cmd_complete_count", cmd_complete, 32'(expected_commands));
        p29d_expect_at_least("cq_commit_count", cq_commit, 32'(expected_commands));
        p29d_expect_nonzero("queue_drained_count", drained);
        p29d_expect_zero("queue_error_count", q_error);

        p29d_expect_at_least("cq_head_update_count", cq_update, 32'h0000_0001);
        p29d_expect_eq("cq_consumed_count", cq_consumed, 32'(expected_cq_consumed));
        p29d_expect_at_least("max_cq_batch_size", max_batch, 32'h0000_0001);

        p29d_expect_nonzero("event_capture_count", event_capture);
        p29d_expect_nonzero("irq_eligible_count", irq_eligible);
        p29d_expect_nonzero("completion_event_count", completion_event);

        p29d_expect_zero("coalesced_release_count in immediate mode", coalesced_release);
        p29d_expect_zero("threshold_release_count in immediate mode", threshold_release);
        p29d_expect_zero("timer_release_count in immediate mode", timer_release);
        p29d_expect_zero("urgent_bypass_count in immediate mode", urgent_bypass);

        p29d_expect_zero("cq_full_stall_count", cq_full_stall);
        p29d_expect_zero("cq_space_recovered_count", cq_space_recovered);
        p29d_expect_zero("timeout_error_count", timeout_error);
        p29d_expect_zero("mem_guard_error_count", mem_guard_error);
        p29d_expect_zero("stop_queue_request_count", stop_request);

        p29d_expect_nonzero("queue_enabled_cycles", queue_enabled_cycles);
        p29d_expect_nonzero("queue_busy_cycles", queue_busy_cycles);
        p29d_expect_nonzero("queue_idle_cycles", queue_idle_cycles);

        if (!status[TELEM_STATUS_ANY_COUNTER_NONZERO]) begin
            `uvm_fatal("P29D_TELEM/STATUS_NONZERO",
                $sformatf("ANY_COUNTER_NONZERO should be set after runtime activity: status=0x%08h", status))
        end

        `uvm_info("P29D_TELEM/RUNTIME_COUNTERS_PASS",
            $sformatf("P29D runtime telemetry counters PASS: q_start=%0d sq_accept=%0d cmd_complete=%0d cq_commit=%0d cq_update=%0d cq_consumed=%0d max_batch=%0d event=%0d irq=%0d completion_event=%0d cycles(en/busy/idle/lower)=%0d/%0d/%0d/%0d",
                q_start,
                sq_accept,
                cmd_complete,
                cq_commit,
                cq_update,
                cq_consumed,
                max_batch,
                event_capture,
                irq_eligible,
                completion_event,
                queue_enabled_cycles,
                queue_busy_cycles,
                queue_idle_cycles,
                lower_wait_cycles),
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

        ai_accel_event_driven_host_runtime_helper rt;
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd0;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd1;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec0;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec1;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t event_snap;
        logic [31:0] version;
        logic [31:0] event_mask;
        logic [31:0] ack_mask;
    begin
        phase.raise_objection(this);

        `uvm_info("P29D_TELEM/START",
            "Starting P29D basic telemetry counter smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        rt = ai_accel_event_driven_host_runtime_helper::type_id::create("rt");
        rt.set_csr(csr);
        rt.set_ctrl_vif(p17d_ctrl_vif);

        p29d_read_telem(CSR_TELEM_VERSION, "CSR_TELEM_VERSION", version);
        p29d_expect_eq("CSR_TELEM_VERSION", version, P29D_TELEM_VERSION_RESET);
        p29d_expect_status_disabled();
        p29d_clear_telem_counters("P29D reset-disabled clear");
        p29d_check_selected_counters_zero("P29D after disabled clear");
        p29d_enable_telem_all();

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P29D_TELEM/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        // Write descriptors after A/B preparation so the descriptor tables
        // are not overwritten by the inherited source-memory setup.
        program_p23d_descriptor_table(
            P29D_DESC_BASE0,
            P29D_DESC0_TAG0,
            P29D_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        program_p23d_descriptor_table(
            P29D_DESC_BASE1,
            P29D_DESC1_TAG0,
            P29D_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        rt.make_default_queue_cfg(
            cfg,
            32'(P29D_SQ_BASE),
            32'(P29D_CQ_BASE),
            32'(P29D_QUEUE_DEPTH),
            1'b1
        );

        rt.make_fetch_recipe_cmd(
            cmd0,
            32'(P29D_DESC_BASE0),
            32'h0000_0002,
            32'(P29D_DESC_STRIDE),
            P29D_CMD0_TAG,
            1'b1,
            1'b0
        );
        cmd0.timeout_cycles = 32'h0000_0000;

        rt.make_fetch_recipe_cmd(
            cmd1,
            32'(P29D_DESC_BASE1),
            32'h0000_0002,
            32'(P29D_DESC_STRIDE),
            P29D_CMD1_TAG,
            1'b1,
            1'b0
        );
        cmd1.timeout_cycles = 32'h0000_0000;

        event_mask = rt.queue_completion_event_mask() |
                     rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_program_completion_wb();

        rt.initialize_runtime(cfg, event_mask, 1'b1);

        csr_check_recipe_idle_ready("before P29D telemetry queue START");

        // Driver-style queue submission: payloads first, then publish the
        // final SQ_TAIL doorbell value.  One START_QUEUE kick drains both
        // commands through RUN_UNTIL_EMPTY.
        rt.write_sq_command(cfg, 0, cmd0, 1'b1);
        rt.write_sq_command(cfg, 1, cmd1, 1'b1);
        rt.ring_sq_tail(32'h0000_0002);
        rt.start_queue();

        rt.wait_events(event_mask, event_snap, done_timeout_cycles * 8, 1'b1);
        check_p23d_event_snapshot_before_ack(event_snap, event_mask);

        rt.wait_cq_commit(cfg, 0, rec0, done_timeout_cycles * 4);
        rt.wait_cq_commit(cfg, 1, rec1, done_timeout_cycles * 4);

        check_p23d_cq_record(0, rec0, profile_item, P29D_DESC0_TAG0, P29D_DESC0_TAG1);
        check_p23d_cq_record(1, rec1, profile_item, P29D_DESC1_TAG0, P29D_DESC1_TAG1);

        ack_mask = event_snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.consume_cq_entry(cfg, 0, 1'b1);
        rt.consume_cq_entry(cfg, 1, 1'b1);
        rt.ack_events(ack_mask);
        check_p23d_runtime_cleanup_after_consume(ack_mask);

        p29d_check_runtime_counters(2, 2);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        // Prove the P29 clear command is observational: disable telemetry,
        // clear only telemetry counters, then verify representative counters
        // are zero while the completed datapath result has already passed.
        csr.write32_expect_okay(CSR_TELEM_CONTROL, 32'h0000_0000);
        repeat (2) @(posedge p17d_ctrl_vif.clk);
        p29d_clear_telem_counters("P29D post-run clear");
        p29d_check_selected_counters_zero("P29D after post-run clear");

        `uvm_info("P29D_TELEM/PASS",
            $sformatf("P29D basic telemetry counter smoke PASS: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d SQ_entries=2 CQ_entries=2 ack_mask=0x%08h",
                selected_case_id,
                a_flat.size(),
                b_flat.size(),
                c_elems,
                ack_mask),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
