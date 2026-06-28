// File: tb/uvm/test/ai_accel_subsys_csr_stall_recovery_telemetry_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_STALL_RECOVERY_TELEMETRY_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_STALL_RECOVERY_TELEMETRY_SMOKE_TEST_SV

// ============================================================
// P29F stall / recovery telemetry smoke
//
// Scope:
//   - Reuses the validated P21/P23 event-driven CQ-full recovery path.
//   - Enables P29 runtime telemetry before a two-command queue session.
//   - Programs CQ depth to one entry so the first committed CQ record
//     intentionally stalls the second command at a command boundary.
//   - Host consumes CQ[0], advances CQ_HEAD, observes CQ-space recovery,
//     then lets the second command complete.
//   - Confirms telemetry observes CQ-full stall count/cycles,
//     CQ-space-recovered count, host CQ consumption, normal completion,
//     and clean recovery without queue error / timeout / guard failure.
//
// P29F does not change RTL, SQ/CQ entry format, descriptor format,
// completion record format, event bits, BRAM, GEMM, DMA, AXI-Stream,
// or Direct Stream datapath behavior.
// ============================================================

class ai_accel_subsys_csr_stall_recovery_telemetry_smoke_test
    extends ai_accel_subsys_csr_event_driven_multi_command_queue_drain_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_stall_recovery_telemetry_smoke_test)

    localparam int unsigned P29F_SQ_BASE     = 32'h0000_0700;
    localparam int unsigned P29F_CQ_BASE     = 32'h0000_0800;
    localparam int unsigned P29F_SQ_DEPTH    = 4;
    localparam int unsigned P29F_CQ_DEPTH    = 1;

    localparam int unsigned P29F_DESC_BASE0  = 32'h0000_0300;
    localparam int unsigned P29F_DESC_BASE1  = 32'h0000_0400;
    localparam int unsigned P29F_DESC_STRIDE = 32'h0000_0080;

    localparam logic [31:0] P29F_CMD0_TAG    = 32'hD29F_0000;
    localparam logic [31:0] P29F_CMD1_TAG    = 32'hD29F_0001;

    localparam logic [31:0] P29F_DESC0_TAG0  = 32'hD29F_1000;
    localparam logic [31:0] P29F_DESC0_TAG1  = 32'hD29F_1001;
    localparam logic [31:0] P29F_DESC1_TAG0  = 32'hD29F_2000;
    localparam logic [31:0] P29F_DESC1_TAG1  = 32'hD29F_2001;

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

    localparam logic [31:0] P29F_TELEM_VERSION_RESET   = 32'h0001_0029;
    localparam logic [31:0] P29F_TELEM_CLEAR_COUNTERS  = 32'h0000_0100;
    localparam logic [31:0] P29F_TELEM_ENABLE_ALL      = 32'h0000_000F;

    localparam int TELEM_STATUS_ENABLED                = 0;
    localparam int TELEM_STATUS_CYCLE_ENABLED          = 1;
    localparam int TELEM_STATUS_HOST_CQ_CONSUME_ENABLE = 2;
    localparam int TELEM_STATUS_EVENT_EFF_ENABLE       = 3;
    localparam int TELEM_STATUS_CSR_READY              = 16;

    function new(string name = "ai_accel_subsys_csr_stall_recovery_telemetry_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p29f_make_cq_full_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg
    );
    begin
        rt.make_default_queue_cfg(
            cfg,
            32'(P29F_SQ_BASE),
            32'(P29F_CQ_BASE),
            32'(P29F_SQ_DEPTH),
            1'b1
        );

        // P29F intentionally makes CQ depth smaller than SQ depth.  The
        // first completion fills CQ[0], the second command stalls at the
        // command boundary until the host advances CQ_HEAD.
        cfg.cq_depth = 32'(P29F_CQ_DEPTH);
    end
    endtask

    task automatic p29f_make_cmd(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd,
        input  logic [31:0] desc_base,
        input  logic [31:0] user_tag
    );
    begin
        rt.make_fetch_recipe_cmd(
            cmd,
            desc_base,
            32'h0000_0002,
            32'(P29F_DESC_STRIDE),
            user_tag,
            1'b1,
            1'b0
        );
        cmd.timeout_cycles = 32'h0000_0000;
    end
    endtask

    task automatic p29f_read_telem(
        input  logic [11:0] addr,
        input  string       name,
        output logic [31:0] value
    );
    begin
        csr.read32_expect_okay(addr, value);
        `uvm_info("P29F_TELEM/READ",
            $sformatf("%s = 0x%08h", name, value),
            UVM_LOW)
    end
    endtask

    task automatic p29f_expect_eq(
        input string       name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
    begin
        if (actual !== expected) begin
            `uvm_fatal("P29F_TELEM/MISMATCH",
                $sformatf("%s mismatch: actual=0x%08h expected=0x%08h",
                    name,
                    actual,
                    expected))
        end

        `uvm_info("P29F_TELEM/CHECK",
            $sformatf("%s PASS: 0x%08h", name, actual),
            UVM_LOW)
    end
    endtask

    task automatic p29f_expect_zero(
        input string       name,
        input logic [31:0] actual
    );
    begin
        p29f_expect_eq(name, actual, 32'h0000_0000);
    end
    endtask

    task automatic p29f_expect_nonzero(
        input string       name,
        input logic [31:0] actual
    );
    begin
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P29F_TELEM/ZERO",
                $sformatf("%s unexpectedly zero", name))
        end

        `uvm_info("P29F_TELEM/CHECK",
            $sformatf("%s nonzero PASS: 0x%08h", name, actual),
            UVM_LOW)
    end
    endtask

    task automatic p29f_expect_at_least(
        input string       name,
        input logic [31:0] actual,
        input logic [31:0] minimum
    );
    begin
        if (actual < minimum) begin
            `uvm_fatal("P29F_TELEM/TOO_SMALL",
                $sformatf("%s too small: actual=%0d minimum=%0d",
                    name,
                    actual,
                    minimum))
        end

        `uvm_info("P29F_TELEM/CHECK",
            $sformatf("%s >= %0d PASS: actual=%0d", name, minimum, actual),
            UVM_LOW)
    end
    endtask

    task automatic p29f_clear_telem_counters(string label);
    begin
        csr.write32_expect_okay(CSR_TELEM_COMMAND, P29F_TELEM_CLEAR_COUNTERS);
        repeat (2) @(posedge p17d_ctrl_vif.clk);

        `uvm_info("P29F_TELEM/CLEAR_PASS",
            $sformatf("%s: issued CLEAR_TELEMETRY_COUNTERS", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic p29f_enable_telem_all();
        logic [31:0] status;
        logic [31:0] control;
    begin
        csr.write32_expect_okay(CSR_TELEM_CONTROL, P29F_TELEM_ENABLE_ALL);
        repeat (2) @(posedge p17d_ctrl_vif.clk);

        p29f_read_telem(CSR_TELEM_CONTROL, "CSR_TELEM_CONTROL enabled", control);
        p29f_read_telem(CSR_TELEM_STATUS,  "CSR_TELEM_STATUS enabled",  status);

        p29f_expect_eq("CSR_TELEM_CONTROL enable-all", control, P29F_TELEM_ENABLE_ALL);

        if (!status[TELEM_STATUS_ENABLED] ||
            !status[TELEM_STATUS_CYCLE_ENABLED] ||
            !status[TELEM_STATUS_HOST_CQ_CONSUME_ENABLE] ||
            !status[TELEM_STATUS_EVENT_EFF_ENABLE] ||
            !status[TELEM_STATUS_CSR_READY]) begin
            `uvm_fatal("P29F_TELEM/ENABLE_STATUS",
                $sformatf("Telemetry enable/status mismatch status=0x%08h control=0x%08h",
                    status,
                    control))
        end

        `uvm_info("P29F_TELEM/ENABLE_PASS",
            $sformatf("Telemetry enable-all PASS: status=0x%08h control=0x%08h",
                status,
                control),
            UVM_MEDIUM)
    end
    endtask

    task automatic p29f_check_counters_zero(string label);
        logic [31:0] queue_start;
        logic [31:0] sq_accept;
        logic [31:0] cmd_complete;
        logic [31:0] cq_commit;
        logic [31:0] cq_full_stall;
        logic [31:0] cq_space_recovered;
        logic [31:0] cq_head_update;
        logic [31:0] cq_consumed;
        logic [31:0] queue_stalled_cycles;
        logic [31:0] cq_full_stall_cycles;
    begin
        p29f_read_telem(CSR_TELEM_QUEUE_START_COUNT,        "queue_start_count",        queue_start);
        p29f_read_telem(CSR_TELEM_SQ_ACCEPT_COUNT,          "sq_accept_count",          sq_accept);
        p29f_read_telem(CSR_TELEM_CMD_COMPLETE_COUNT,       "cmd_complete_count",       cmd_complete);
        p29f_read_telem(CSR_TELEM_CQ_COMMIT_COUNT,          "cq_commit_count",          cq_commit);
        p29f_read_telem(CSR_TELEM_CQ_FULL_STALL_COUNT,      "cq_full_stall_count",      cq_full_stall);
        p29f_read_telem(CSR_TELEM_CQ_SPACE_RECOVERED_COUNT, "cq_space_recovered_count", cq_space_recovered);
        p29f_read_telem(CSR_TELEM_CQ_HEAD_UPDATE_COUNT,     "cq_head_update_count",     cq_head_update);
        p29f_read_telem(CSR_TELEM_CQ_CONSUMED_COUNT,        "cq_consumed_count",        cq_consumed);
        p29f_read_telem(CSR_TELEM_QUEUE_STALLED_CYCLES,     "queue_stalled_cycles",     queue_stalled_cycles);
        p29f_read_telem(CSR_TELEM_CQ_FULL_STALL_CYCLES,     "cq_full_stall_cycles",     cq_full_stall_cycles);

        p29f_expect_zero({label, ": queue_start_count"},        queue_start);
        p29f_expect_zero({label, ": sq_accept_count"},          sq_accept);
        p29f_expect_zero({label, ": cmd_complete_count"},       cmd_complete);
        p29f_expect_zero({label, ": cq_commit_count"},          cq_commit);
        p29f_expect_zero({label, ": cq_full_stall_count"},      cq_full_stall);
        p29f_expect_zero({label, ": cq_space_recovered_count"}, cq_space_recovered);
        p29f_expect_zero({label, ": cq_head_update_count"},     cq_head_update);
        p29f_expect_zero({label, ": cq_consumed_count"},        cq_consumed);
        p29f_expect_zero({label, ": queue_stalled_cycles"},     queue_stalled_cycles);
        p29f_expect_zero({label, ": cq_full_stall_cycles"},     cq_full_stall_cycles);

        `uvm_info("P29F_TELEM/ZERO_PASS",
            $sformatf("%s: selected telemetry counters are zero", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic p29f_check_stall_recovery_counters();
        logic [31:0] queue_start;
        logic [31:0] sq_accept;
        logic [31:0] cmd_complete;
        logic [31:0] cq_commit;
        logic [31:0] queue_drained;
        logic [31:0] queue_error;
        logic [31:0] cq_head_update;
        logic [31:0] cq_consumed;
        logic [31:0] max_batch;
        logic [31:0] event_capture;
        logic [31:0] irq_eligible;
        logic [31:0] completion_event;
        logic [31:0] coalesced_release;
        logic [31:0] threshold_release;
        logic [31:0] timer_release;
        logic [31:0] cq_full_stall;
        logic [31:0] cq_space_recovered;
        logic [31:0] timeout_error;
        logic [31:0] mem_guard_error;
        logic [31:0] stop_queue_request;
        logic [31:0] queue_enabled_cycles;
        logic [31:0] queue_busy_cycles;
        logic [31:0] queue_idle_cycles;
        logic [31:0] queue_stalled_cycles;
        logic [31:0] cq_full_stall_cycles;
        logic [31:0] lower_wait_cycles;
    begin
        p29f_read_telem(CSR_TELEM_QUEUE_START_COUNT,        "queue_start_count",        queue_start);
        p29f_read_telem(CSR_TELEM_SQ_ACCEPT_COUNT,          "sq_accept_count",          sq_accept);
        p29f_read_telem(CSR_TELEM_CMD_COMPLETE_COUNT,       "cmd_complete_count",       cmd_complete);
        p29f_read_telem(CSR_TELEM_CQ_COMMIT_COUNT,          "cq_commit_count",          cq_commit);
        p29f_read_telem(CSR_TELEM_QUEUE_DRAINED_COUNT,      "queue_drained_count",      queue_drained);
        p29f_read_telem(CSR_TELEM_QUEUE_ERROR_COUNT,        "queue_error_count",        queue_error);
        p29f_read_telem(CSR_TELEM_CQ_HEAD_UPDATE_COUNT,     "cq_head_update_count",     cq_head_update);
        p29f_read_telem(CSR_TELEM_CQ_CONSUMED_COUNT,        "cq_consumed_count",        cq_consumed);
        p29f_read_telem(CSR_TELEM_MAX_CQ_BATCH_SIZE,        "max_cq_batch_size",        max_batch);
        p29f_read_telem(CSR_TELEM_EVENT_CAPTURE_COUNT,      "event_capture_count",      event_capture);
        p29f_read_telem(CSR_TELEM_IRQ_ELIGIBLE_COUNT,       "irq_eligible_count",       irq_eligible);
        p29f_read_telem(CSR_TELEM_COMPLETION_EVENT_COUNT,   "completion_event_count",   completion_event);
        p29f_read_telem(CSR_TELEM_COALESCED_RELEASE_COUNT,  "coalesced_release_count",  coalesced_release);
        p29f_read_telem(CSR_TELEM_THRESHOLD_RELEASE_COUNT,  "threshold_release_count",  threshold_release);
        p29f_read_telem(CSR_TELEM_TIMER_RELEASE_COUNT,      "timer_release_count",      timer_release);
        p29f_read_telem(CSR_TELEM_CQ_FULL_STALL_COUNT,      "cq_full_stall_count",      cq_full_stall);
        p29f_read_telem(CSR_TELEM_CQ_SPACE_RECOVERED_COUNT, "cq_space_recovered_count", cq_space_recovered);
        p29f_read_telem(CSR_TELEM_TIMEOUT_ERROR_COUNT,      "timeout_error_count",      timeout_error);
        p29f_read_telem(CSR_TELEM_MEM_GUARD_ERROR_COUNT,    "mem_guard_error_count",    mem_guard_error);
        p29f_read_telem(CSR_TELEM_STOP_QUEUE_REQUEST_COUNT, "stop_queue_request_count", stop_queue_request);
        p29f_read_telem(CSR_TELEM_QUEUE_ENABLED_CYCLES,     "queue_enabled_cycles",     queue_enabled_cycles);
        p29f_read_telem(CSR_TELEM_QUEUE_BUSY_CYCLES,        "queue_busy_cycles",        queue_busy_cycles);
        p29f_read_telem(CSR_TELEM_QUEUE_IDLE_CYCLES,        "queue_idle_cycles",        queue_idle_cycles);
        p29f_read_telem(CSR_TELEM_QUEUE_STALLED_CYCLES,     "queue_stalled_cycles",     queue_stalled_cycles);
        p29f_read_telem(CSR_TELEM_CQ_FULL_STALL_CYCLES,     "cq_full_stall_cycles",     cq_full_stall_cycles);
        p29f_read_telem(CSR_TELEM_LOWER_WAIT_CYCLES,        "lower_wait_cycles",        lower_wait_cycles);

        p29f_expect_eq("queue_start_count", queue_start, 32'h0000_0001);
        p29f_expect_at_least("sq_accept_count", sq_accept, 32'h0000_0002);
        p29f_expect_at_least("cmd_complete_count", cmd_complete, 32'h0000_0002);
        p29f_expect_eq("cq_commit_count", cq_commit, 32'h0000_0002);
        p29f_expect_nonzero("queue_drained_count", queue_drained);
        p29f_expect_zero("queue_error_count", queue_error);

        p29f_expect_at_least("cq_head_update_count", cq_head_update, 32'h0000_0002);
        p29f_expect_eq("cq_consumed_count", cq_consumed, 32'h0000_0002);
        p29f_expect_at_least("max_cq_batch_size", max_batch, 32'h0000_0001);

        p29f_expect_nonzero("event_capture_count", event_capture);
        p29f_expect_nonzero("irq_eligible_count", irq_eligible);
        p29f_expect_nonzero("completion_event_count", completion_event);

        p29f_expect_zero("coalesced_release_count in immediate stall/recovery case", coalesced_release);
        p29f_expect_zero("threshold_release_count in immediate stall/recovery case", threshold_release);
        p29f_expect_zero("timer_release_count in immediate stall/recovery case", timer_release);

        p29f_expect_nonzero("cq_full_stall_count", cq_full_stall);
        p29f_expect_nonzero("cq_space_recovered_count", cq_space_recovered);
        p29f_expect_zero("timeout_error_count", timeout_error);
        p29f_expect_zero("mem_guard_error_count", mem_guard_error);
        p29f_expect_zero("stop_queue_request_count", stop_queue_request);

        p29f_expect_nonzero("queue_enabled_cycles", queue_enabled_cycles);
        p29f_expect_nonzero("queue_busy_cycles", queue_busy_cycles);
        p29f_expect_nonzero("queue_idle_cycles", queue_idle_cycles);
        p29f_expect_nonzero("queue_stalled_cycles", queue_stalled_cycles);
        p29f_expect_nonzero("cq_full_stall_cycles", cq_full_stall_cycles);

        `uvm_info("P29F_TELEM/STALL_COUNTERS_PASS",
            $sformatf("P29F stall telemetry counters PASS: cq_full_stall=%0d recovered=%0d stall_cycles=%0d cq_full_cycles=%0d",
                cq_full_stall,
                cq_space_recovered,
                queue_stalled_cycles,
                cq_full_stall_cycles),
            UVM_MEDIUM)

        `uvm_info("P29F_TELEM/RECOVERY_COUNTERS_PASS",
            $sformatf("P29F recovery telemetry counters PASS: start=%0d sq_accept=%0d complete=%0d cq_commit=%0d cq_updates=%0d cq_consumed=%0d cycles(en/busy/idle/lower)=%0d/%0d/%0d/%0d",
                queue_start,
                sq_accept,
                cmd_complete,
                cq_commit,
                cq_head_update,
                cq_consumed,
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

        ai_accel_event_driven_host_runtime_stress_helper rt;
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd0;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd1;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec0;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec1;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t stall_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t recovered_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t drained_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t final_snap;

        logic [31:0] version;
        logic [31:0] event_mask;
        logic [31:0] cq_full_event_mask;
        logic [31:0] cq_space_event_mask;
        logic [31:0] drained_event_mask;
    begin
        phase.raise_objection(this);

        `uvm_info("P29F_TELEM/START",
            "Starting P29F stall / recovery telemetry smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        rt = ai_accel_event_driven_host_runtime_stress_helper::type_id::create("rt");
        rt.set_csr(csr);
        rt.set_ctrl_vif(p17d_ctrl_vif);

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P29F_TELEM/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        program_p23d_descriptor_table(
            P29F_DESC_BASE0,
            P29F_DESC0_TAG0,
            P29F_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        program_p23d_descriptor_table(
            P29F_DESC_BASE1,
            P29F_DESC1_TAG0,
            P29F_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p29f_make_cq_full_cfg(rt, cfg);
        p29f_make_cmd(rt, cmd0, 32'(P29F_DESC_BASE0), P29F_CMD0_TAG);
        p29f_make_cmd(rt, cmd1, 32'(P29F_DESC_BASE1), P29F_CMD1_TAG);

        event_mask = rt.queue_completion_event_mask() |
                     rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED) |
                     rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_FULL_STALL) |
                     rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_SPACE_RECOVERED);
        cq_full_event_mask  = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_FULL_STALL);
        cq_space_event_mask = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_SPACE_RECOVERED);
        drained_event_mask  = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_program_completion_wb();

        p29f_read_telem(CSR_TELEM_VERSION, "CSR_TELEM_VERSION", version);
        p29f_expect_eq("CSR_TELEM_VERSION", version, P29F_TELEM_VERSION_RESET);

        p29f_clear_telem_counters("P29F pre-run clear");
        p29f_check_counters_zero("P29F after pre-run clear");
        p29f_enable_telem_all();

        rt.host_rt_lifecycle_init_session(
            cfg,
            event_mask,
            1'b1,
            1'b1,
            "P29F CQ-full telemetry init"
        );

        rt.write_sq_command(cfg, 0, cmd0, 1'b1);
        rt.write_sq_command(cfg, 1, cmd1, 1'b1);
        rt.ring_sq_tail(32'h0000_0002);
        rt.start_queue();

        rt.wait_for_progress_event(
            cq_full_event_mask,
            stall_snap,
            "P29F CQ-full stall event wait",
            done_timeout_cycles * 16,
            1'b1
        );

        if (stall_snap.cq_occupancy != 32'h0000_0001 ||
            stall_snap.cq_space     != 32'h0000_0000) begin
            `uvm_fatal("P29F_TELEM/CQ_FULL_STATE",
                $sformatf("Unexpected CQ-full snapshot: CQ_OCC=%0d CQ_SPACE=%0d SQ(h/t)=%0d/%0d CQ(h/t)=%0d/%0d pending=0x%08h",
                    stall_snap.cq_occupancy,
                    stall_snap.cq_space,
                    stall_snap.sq_head,
                    stall_snap.sq_tail,
                    stall_snap.cq_head,
                    stall_snap.cq_tail,
                    stall_snap.event_snap.pending))
        end

        rt.wait_and_check_cq_record(
            cfg,
            0,
            P29F_DESC0_TAG0,
            P29F_DESC0_TAG1,
            rec0,
            "P29F first CQ before CQ-full recovery",
            done_timeout_cycles * 4
        );
        check_p23d_cq_record(0, rec0, profile_item, P29F_DESC0_TAG0, P29F_DESC0_TAG1);

        rt.consume_cq_entry(cfg, 0, 1'b1);

        `uvm_info("P29F_TELEM/CQ_FULL_STALL_PASS",
            $sformatf("P29F CQ-full stall observed and first CQ consumed: pending=0x%08h CQ_HEAD 0->1",
                stall_snap.event_snap.pending),
            UVM_MEDIUM)

        rt.wait_for_progress_event(
            cq_space_event_mask,
            recovered_snap,
            "P29F CQ-space recovered event wait",
            done_timeout_cycles * 8,
            1'b1
        );

        `uvm_info("P29F_TELEM/CQ_SPACE_RECOVERY_PASS",
            $sformatf("P29F CQ-space recovery event observed: pending=0x%08h SQ(h/t)=%0d/%0d CQ(h/t/occ/space)=%0d/%0d/%0d/%0d",
                recovered_snap.event_snap.pending,
                recovered_snap.sq_head,
                recovered_snap.sq_tail,
                recovered_snap.cq_head,
                recovered_snap.cq_tail,
                recovered_snap.cq_occupancy,
                recovered_snap.cq_space),
            UVM_MEDIUM)

        rt.wait_for_progress_event(
            drained_event_mask,
            drained_snap,
            "P29F final drained event wait",
            done_timeout_cycles * 16,
            1'b1
        );

        rt.wait_and_check_cq_record(
            cfg,
            1,
            P29F_DESC1_TAG0,
            P29F_DESC1_TAG1,
            rec1,
            "P29F second CQ after CQ-space recovery",
            done_timeout_cycles * 4
        );
        check_p23d_cq_record(1, rec1, profile_item, P29F_DESC1_TAG0, P29F_DESC1_TAG1);

        rt.consume_cq_entry(cfg, 1, 1'b1);
        repeat (4) @(posedge p17d_ctrl_vif.clk);

        rt.read_runtime_snapshot(final_snap);
        rt.ack_events(final_snap.event_snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK);
        repeat (2) @(posedge p17d_ctrl_vif.clk);
        rt.clear_queue_sticky();

        if ((final_snap.queue_error_status != 32'h0000_0000) ||
            (final_snap.queue_reject_status != 32'h0000_0000)) begin
            `uvm_fatal("P29F_TELEM/QUEUE_ERROR",
                $sformatf("Unexpected queue error/reject after CQ-full recovery: error=0x%08h reject=0x%08h status=0x%08h",
                    final_snap.queue_error_status,
                    final_snap.queue_reject_status,
                    final_snap.queue_status))
        end

        `uvm_info("P29F_TELEM/RECOVERY_PASS",
            $sformatf("P29F second command completed after CQ-space recovery: SQ(h/t)=%0d/%0d CQ(h/t)=%0d/%0d pending=0x%08h",
                final_snap.sq_head,
                final_snap.sq_tail,
                final_snap.cq_head,
                final_snap.cq_tail,
                final_snap.event_snap.pending),
            UVM_MEDIUM)

        p29f_check_stall_recovery_counters();

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        p29f_clear_telem_counters("P29F post-run clear");
        p29f_check_counters_zero("P29F after post-run clear");
        csr.write32_expect_okay(CSR_TELEM_CONTROL, 32'h0000_0000);

        `uvm_info("P29F_TELEM/PASS",
            $sformatf("P29F stall / recovery telemetry PASS: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d SQ_entries=2 CQ_depth=1",
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
