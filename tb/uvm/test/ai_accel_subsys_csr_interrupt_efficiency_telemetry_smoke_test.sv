// File: tb/uvm/test/ai_accel_subsys_csr_interrupt_efficiency_telemetry_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_INTERRUPT_EFFICIENCY_TELEMETRY_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_INTERRUPT_EFFICIENCY_TELEMETRY_SMOKE_TEST_SV

// ============================================================
// P29E interrupt efficiency / coalescing telemetry smoke
//
// Scope:
//   - Reuses the validated P28D CQ-threshold interrupt moderation path.
//   - Enables P29 telemetry before a two-command coalesced CQ session.
//   - Confirms two CQ commits are represented by fewer IRQ-eligible
//     notification releases when threshold moderation is enabled.
//   - Confirms telemetry observes coalesced / threshold releases and the
//     host batch CQ consume size.
//
// P29E does not change RTL, SQ/CQ entry format, descriptor format,
// completion record format, BRAM, GEMM, DMA, AXI-Stream, or Direct Stream
// datapath behavior.
// ============================================================

class ai_accel_subsys_csr_interrupt_efficiency_telemetry_smoke_test
    extends ai_accel_subsys_csr_event_mod_cq_threshold_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_interrupt_efficiency_telemetry_smoke_test)

    localparam int unsigned P29E_SQ_BASE     = 32'h0000_0700;
    localparam int unsigned P29E_CQ_BASE     = 32'h0000_0800;
    localparam int unsigned P29E_QUEUE_DEPTH = 4;

    localparam int unsigned P29E_DESC_BASE0  = 32'h0000_0300;
    localparam int unsigned P29E_DESC_BASE1  = 32'h0000_0400;
    localparam int unsigned P29E_DESC_STRIDE = 32'h0000_0080;

    localparam logic [31:0] P29E_CMD0_TAG    = 32'hD29E_0000;
    localparam logic [31:0] P29E_CMD1_TAG    = 32'hD29E_0001;

    localparam logic [31:0] P29E_DESC0_TAG0  = 32'hD29E_1000;
    localparam logic [31:0] P29E_DESC0_TAG1  = 32'hD29E_1001;
    localparam logic [31:0] P29E_DESC1_TAG0  = 32'hD29E_2000;
    localparam logic [31:0] P29E_DESC1_TAG1  = 32'hD29E_2001;

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
    localparam logic [11:0] CSR_TELEM_LOWER_WAIT_CYCLES        = 12'h73C;

    localparam logic [31:0] P29E_TELEM_VERSION_RESET   = 32'h0001_0029;
    localparam logic [31:0] P29E_TELEM_CLEAR_COUNTERS  = 32'h0000_0100;
    localparam logic [31:0] P29E_TELEM_ENABLE_ALL      = 32'h0000_000F;

    localparam int TELEM_STATUS_ENABLED                = 0;
    localparam int TELEM_STATUS_CYCLE_ENABLED          = 1;
    localparam int TELEM_STATUS_HOST_CQ_CONSUME_ENABLE = 2;
    localparam int TELEM_STATUS_EVENT_EFF_ENABLE       = 3;
    localparam int TELEM_STATUS_CSR_READY              = 16;

    function new(string name = "ai_accel_subsys_csr_interrupt_efficiency_telemetry_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p29e_make_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg
    );
    begin
        rt.make_default_queue_cfg(
            cfg,
            32'(P29E_SQ_BASE),
            32'(P29E_CQ_BASE),
            32'(P29E_QUEUE_DEPTH),
            1'b1
        );
    end
    endtask

    task automatic p29e_make_cmd(
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
            32'(P29E_DESC_STRIDE),
            user_tag,
            1'b1,
            1'b0
        );
        cmd.timeout_cycles = 32'h0000_0000;
    end
    endtask

    task automatic p29e_read_telem(
        input  logic [11:0] addr,
        input  string       name,
        output logic [31:0] value
    );
    begin
        csr.read32_expect_okay(addr, value);
        `uvm_info("P29E_TELEM/READ",
            $sformatf("%s = 0x%08h", name, value),
            UVM_LOW)
    end
    endtask

    task automatic p29e_expect_eq(
        input string       name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
    begin
        if (actual !== expected) begin
            `uvm_fatal("P29E_TELEM/MISMATCH",
                $sformatf("%s mismatch: actual=0x%08h expected=0x%08h",
                    name,
                    actual,
                    expected))
        end

        `uvm_info("P29E_TELEM/CHECK",
            $sformatf("%s PASS: 0x%08h", name, actual),
            UVM_LOW)
    end
    endtask

    task automatic p29e_expect_zero(
        input string       name,
        input logic [31:0] actual
    );
    begin
        p29e_expect_eq(name, actual, 32'h0000_0000);
    end
    endtask

    task automatic p29e_expect_nonzero(
        input string       name,
        input logic [31:0] actual
    );
    begin
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P29E_TELEM/ZERO",
                $sformatf("%s unexpectedly zero", name))
        end

        `uvm_info("P29E_TELEM/CHECK",
            $sformatf("%s nonzero PASS: 0x%08h", name, actual),
            UVM_LOW)
    end
    endtask

    task automatic p29e_expect_at_least(
        input string       name,
        input logic [31:0] actual,
        input logic [31:0] minimum
    );
    begin
        if (actual < minimum) begin
            `uvm_fatal("P29E_TELEM/TOO_SMALL",
                $sformatf("%s too small: actual=%0d minimum=%0d",
                    name,
                    actual,
                    minimum))
        end

        `uvm_info("P29E_TELEM/CHECK",
            $sformatf("%s >= %0d PASS: actual=%0d", name, minimum, actual),
            UVM_LOW)
    end
    endtask

    task automatic p29e_expect_less_than(
        input string       name,
        input logic [31:0] actual,
        input logic [31:0] limit
    );
    begin
        if (actual >= limit) begin
            `uvm_fatal("P29E_TELEM/NOT_REDUCED",
                $sformatf("%s not reduced: actual=%0d limit=%0d",
                    name,
                    actual,
                    limit))
        end

        `uvm_info("P29E_TELEM/CHECK",
            $sformatf("%s < %0d PASS: actual=%0d", name, limit, actual),
            UVM_LOW)
    end
    endtask

    task automatic p29e_clear_telem_counters(string label);
    begin
        csr.write32_expect_okay(CSR_TELEM_COMMAND, P29E_TELEM_CLEAR_COUNTERS);
        repeat (2) @(posedge p17d_ctrl_vif.clk);

        `uvm_info("P29E_TELEM/CLEAR_PASS",
            $sformatf("%s: issued CLEAR_TELEMETRY_COUNTERS", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic p29e_enable_telem_all();
        logic [31:0] status;
        logic [31:0] control;
    begin
        csr.write32_expect_okay(CSR_TELEM_CONTROL, P29E_TELEM_ENABLE_ALL);
        repeat (2) @(posedge p17d_ctrl_vif.clk);

        p29e_read_telem(CSR_TELEM_CONTROL, "CSR_TELEM_CONTROL enabled", control);
        p29e_read_telem(CSR_TELEM_STATUS,  "CSR_TELEM_STATUS enabled",  status);

        p29e_expect_eq("CSR_TELEM_CONTROL enable-all", control, P29E_TELEM_ENABLE_ALL);

        if (!status[TELEM_STATUS_ENABLED] ||
            !status[TELEM_STATUS_CYCLE_ENABLED] ||
            !status[TELEM_STATUS_HOST_CQ_CONSUME_ENABLE] ||
            !status[TELEM_STATUS_EVENT_EFF_ENABLE] ||
            !status[TELEM_STATUS_CSR_READY]) begin
            `uvm_fatal("P29E_TELEM/ENABLE_STATUS",
                $sformatf("Telemetry enable/status mismatch status=0x%08h control=0x%08h",
                    status,
                    control))
        end

        `uvm_info("P29E_TELEM/ENABLE_PASS",
            $sformatf("Telemetry enable-all PASS: status=0x%08h control=0x%08h",
                status,
                control),
            UVM_MEDIUM)
    end
    endtask

    task automatic p29e_check_counters_zero(string label);
        logic [31:0] q_start;
        logic [31:0] sq_accept;
        logic [31:0] cmd_complete;
        logic [31:0] cq_commit;
        logic [31:0] coalesced_release;
        logic [31:0] threshold_release;
        logic [31:0] irq_eligible;
        logic [31:0] max_batch;
    begin
        p29e_read_telem(CSR_TELEM_QUEUE_START_COUNT,       "queue_start_count",       q_start);
        p29e_read_telem(CSR_TELEM_SQ_ACCEPT_COUNT,         "sq_accept_count",         sq_accept);
        p29e_read_telem(CSR_TELEM_CMD_COMPLETE_COUNT,      "cmd_complete_count",      cmd_complete);
        p29e_read_telem(CSR_TELEM_CQ_COMMIT_COUNT,         "cq_commit_count",         cq_commit);
        p29e_read_telem(CSR_TELEM_COALESCED_RELEASE_COUNT, "coalesced_release_count", coalesced_release);
        p29e_read_telem(CSR_TELEM_THRESHOLD_RELEASE_COUNT, "threshold_release_count", threshold_release);
        p29e_read_telem(CSR_TELEM_IRQ_ELIGIBLE_COUNT,      "irq_eligible_count",      irq_eligible);
        p29e_read_telem(CSR_TELEM_MAX_CQ_BATCH_SIZE,       "max_cq_batch_size",       max_batch);

        p29e_expect_zero($sformatf("%s: queue_start_count",       label), q_start);
        p29e_expect_zero($sformatf("%s: sq_accept_count",         label), sq_accept);
        p29e_expect_zero($sformatf("%s: cmd_complete_count",      label), cmd_complete);
        p29e_expect_zero($sformatf("%s: cq_commit_count",         label), cq_commit);
        p29e_expect_zero($sformatf("%s: coalesced_release_count", label), coalesced_release);
        p29e_expect_zero($sformatf("%s: threshold_release_count", label), threshold_release);
        p29e_expect_zero($sformatf("%s: irq_eligible_count",      label), irq_eligible);
        p29e_expect_zero($sformatf("%s: max_cq_batch_size",       label), max_batch);

        `uvm_info("P29E_TELEM/ZERO_PASS",
            $sformatf("%s: selected telemetry counters are zero", label),
            UVM_MEDIUM)
    end
    endtask

    task automatic p29e_check_interrupt_efficiency(
        input ai_accel_event_driven_host_runtime_stress_helper::p28_cq_batch_result_t batch_result,
        input ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t threshold_snap
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
        logic [7:0]  mod_threshold_release_count;
    begin
        p29e_read_telem(CSR_TELEM_QUEUE_START_COUNT,        "queue_start_count",        q_start);
        p29e_read_telem(CSR_TELEM_SQ_ACCEPT_COUNT,          "sq_accept_count",          sq_accept);
        p29e_read_telem(CSR_TELEM_CMD_COMPLETE_COUNT,       "cmd_complete_count",       cmd_complete);
        p29e_read_telem(CSR_TELEM_CQ_COMMIT_COUNT,          "cq_commit_count",          cq_commit);
        p29e_read_telem(CSR_TELEM_QUEUE_DRAINED_COUNT,      "queue_drained_count",      drained);
        p29e_read_telem(CSR_TELEM_QUEUE_STOPPED_COUNT,      "queue_stopped_count",      stopped);
        p29e_read_telem(CSR_TELEM_QUEUE_ERROR_COUNT,        "queue_error_count",        q_error);
        p29e_read_telem(CSR_TELEM_CQ_HEAD_UPDATE_COUNT,     "cq_head_update_count",     cq_update);
        p29e_read_telem(CSR_TELEM_CQ_CONSUMED_COUNT,        "cq_consumed_count",        cq_consumed);
        p29e_read_telem(CSR_TELEM_MAX_CQ_BATCH_SIZE,        "max_cq_batch_size",        max_batch);
        p29e_read_telem(CSR_TELEM_EVENT_CAPTURE_COUNT,      "event_capture_count",      event_capture);
        p29e_read_telem(CSR_TELEM_IRQ_ELIGIBLE_COUNT,       "irq_eligible_count",       irq_eligible);
        p29e_read_telem(CSR_TELEM_COMPLETION_EVENT_COUNT,   "completion_event_count",   completion_event);
        p29e_read_telem(CSR_TELEM_COALESCED_RELEASE_COUNT,  "coalesced_release_count",  coalesced_release);
        p29e_read_telem(CSR_TELEM_THRESHOLD_RELEASE_COUNT,  "threshold_release_count",  threshold_release);
        p29e_read_telem(CSR_TELEM_TIMER_RELEASE_COUNT,      "timer_release_count",      timer_release);
        p29e_read_telem(CSR_TELEM_URGENT_BYPASS_COUNT,      "urgent_bypass_count",      urgent_bypass);
        p29e_read_telem(CSR_TELEM_CQ_FULL_STALL_COUNT,      "cq_full_stall_count",      cq_full_stall);
        p29e_read_telem(CSR_TELEM_CQ_SPACE_RECOVERED_COUNT, "cq_space_recovered_count", cq_space_recovered);
        p29e_read_telem(CSR_TELEM_TIMEOUT_ERROR_COUNT,      "timeout_error_count",      timeout_error);
        p29e_read_telem(CSR_TELEM_MEM_GUARD_ERROR_COUNT,    "mem_guard_error_count",    mem_guard_error);
        p29e_read_telem(CSR_TELEM_STOP_QUEUE_REQUEST_COUNT, "stop_queue_request_count", stop_request);
        p29e_read_telem(CSR_TELEM_QUEUE_ENABLED_CYCLES,     "queue_enabled_cycles",     queue_enabled_cycles);
        p29e_read_telem(CSR_TELEM_QUEUE_BUSY_CYCLES,        "queue_busy_cycles",        queue_busy_cycles);
        p29e_read_telem(CSR_TELEM_QUEUE_IDLE_CYCLES,        "queue_idle_cycles",        queue_idle_cycles);
        p29e_read_telem(CSR_TELEM_LOWER_WAIT_CYCLES,        "lower_wait_cycles",        lower_wait_cycles);

        p29e_expect_eq("queue_start_count", q_start, 32'h0000_0001);
        p29e_expect_at_least("sq_accept_count", sq_accept, 32'h0000_0002);
        p29e_expect_at_least("cmd_complete_count", cmd_complete, 32'h0000_0002);
        p29e_expect_eq("cq_commit_count", cq_commit, 32'h0000_0002);
        p29e_expect_nonzero("queue_drained_count", drained);
        p29e_expect_zero("queue_error_count", q_error);

        p29e_expect_eq("cq_head_update_count", cq_update, 32'h0000_0001);
        p29e_expect_eq("cq_consumed_count", cq_consumed, 32'h0000_0002);
        p29e_expect_at_least("max_cq_batch_size", max_batch, 32'h0000_0002);

        p29e_expect_nonzero("event_capture_count", event_capture);
        p29e_expect_nonzero("irq_eligible_count", irq_eligible);
        p29e_expect_less_than("irq_eligible_count versus CQ commits", irq_eligible, cq_commit);
        p29e_expect_nonzero("completion_event_count", completion_event);

        p29e_expect_nonzero("coalesced_release_count", coalesced_release);
        p29e_expect_nonzero("threshold_release_count", threshold_release);
        p29e_expect_zero("timer_release_count in threshold-only case", timer_release);

        p29e_expect_zero("cq_full_stall_count", cq_full_stall);
        p29e_expect_zero("cq_space_recovered_count", cq_space_recovered);
        p29e_expect_zero("timeout_error_count", timeout_error);
        p29e_expect_zero("mem_guard_error_count", mem_guard_error);
        p29e_expect_zero("stop_queue_request_count", stop_request);

        p29e_expect_nonzero("queue_enabled_cycles", queue_enabled_cycles);
        p29e_expect_nonzero("queue_busy_cycles", queue_busy_cycles);
        p29e_expect_nonzero("queue_idle_cycles", queue_idle_cycles);

        mod_threshold_release_count = threshold_snap.mod_debug[23:16];
        if (mod_threshold_release_count == 8'h00) begin
            `uvm_fatal("P29E_TELEM/MOD_THRESHOLD_ZERO",
                $sformatf("P28 moderation threshold debug counter is zero: mod_debug=0x%08h",
                    threshold_snap.mod_debug))
        end

        `uvm_info("P29E_TELEM/COALESCING_COUNTERS_PASS",
            $sformatf("P29E coalescing counters PASS: cq_commit=%0d irq_eligible=%0d completion_event=%0d coalesced=%0d threshold=%0d timer=%0d urgent=%0d max_batch=%0d stopped=%0d cycles(en/busy/idle/lower)=%0d/%0d/%0d/%0d",
                cq_commit,
                irq_eligible,
                completion_event,
                coalesced_release,
                threshold_release,
                timer_release,
                urgent_bypass,
                max_batch,
                stopped,
                queue_enabled_cycles,
                queue_busy_cycles,
                queue_idle_cycles,
                lower_wait_cycles),
            UVM_MEDIUM)

        if (batch_result.consumed_count != 32'h0000_0002) begin
            `uvm_fatal("P29E_TELEM/BATCH_RESULT",
                $sformatf("Batch result consumed_count mismatch actual=%0d expected=2",
                    batch_result.consumed_count))
        end

        `uvm_info("P29E_TELEM/IRQ_REDUCTION_PASS",
            $sformatf("P29E IRQ reduction PASS: CQ commits=%0d IRQ-eligible captures=%0d max_batch=%0d threshold_release_count=%0d",
                cq_commit,
                irq_eligible,
                max_batch,
                threshold_release),
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
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_cfg_t mod_cfg;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t threshold_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_snapshot_t rearm_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p28_cq_batch_result_t batch_result;

        logic [31:0] version;
        logic [31:0] completion_event_mask;
        logic [31:0] threshold_required_mask;
        logic [31:0] ack_mask;
        logic [7:0]  threshold_release_count;
        logic [7:0]  threshold_release_cause;
    begin
        phase.raise_objection(this);

        `uvm_info("P29E_TELEM/START",
            "Starting P29E interrupt efficiency / coalescing telemetry smoke test",
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
            `uvm_fatal("P29E_TELEM/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        program_p23d_descriptor_table(
            P29E_DESC_BASE0,
            P29E_DESC0_TAG0,
            P29E_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        program_p23d_descriptor_table(
            P29E_DESC_BASE1,
            P29E_DESC1_TAG0,
            P29E_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p29e_make_cfg(rt, cfg);
        p29e_make_cmd(rt, cmd0, 32'(P29E_DESC_BASE0), P29E_CMD0_TAG);
        p29e_make_cmd(rt, cmd1, 32'(P29E_DESC_BASE1), P29E_CMD1_TAG);

        completion_event_mask = rt.host_rt_event_mod_completion_mask(
            1'b1, // QUEUE_COMMAND_COMPLETED_EVENT
            1'b1, // CQ_NOT_EMPTY_EVENT
            1'b1, // CQ_THRESHOLD_EVENT
            1'b0  // timer event disabled in threshold-efficiency case
        );

        threshold_required_mask = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_NOT_EMPTY) |
                                  rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_THRESHOLD);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_program_completion_wb();

        p29e_read_telem(CSR_TELEM_VERSION, "CSR_TELEM_VERSION", version);
        p29e_expect_eq("CSR_TELEM_VERSION", version, P29E_TELEM_VERSION_RESET);

        p29e_clear_telem_counters("P29E pre-run clear");
        p29e_check_counters_zero("P29E after pre-run clear");
        p29e_enable_telem_all();

        rt.host_rt_lifecycle_init_session(
            cfg,
            completion_event_mask,
            1'b1,
            1'b1,
            "P29E coalescing telemetry init"
        );

        rt.host_rt_event_mod_default_cfg(
            mod_cfg,
            1'b1, // moderation_enable
            1'b1, // cq_threshold_enable
            1'b0, // moderation_timer_enable
            1'b1, // retrigger_on_nonempty
            32'h0000_0002,
            32'h0000_0000,
            completion_event_mask,
            1'b1,
            1'b1
        );
        rt.host_rt_event_mod_program(mod_cfg, "P29E threshold moderation cfg");

        rt.write_sq_command(cfg, 0, cmd0, 1'b1);
        rt.write_sq_command(cfg, 1, cmd1, 1'b1);
        rt.ring_sq_tail(32'h0000_0002);
        rt.start_queue();

        rt.host_rt_event_mod_wait_notification(
            threshold_required_mask,
            threshold_snap,
            "P29E wait threshold notification",
            done_timeout_cycles * 8,
            1'b1
        );

        rt.host_rt_event_mod_expect_pending(
            threshold_snap,
            threshold_required_mask,
            32'h0000_0000,
            "P29E threshold pending check"
        );

        threshold_release_count = rt.host_rt_event_mod_debug_threshold_count(threshold_snap.mod_debug);
        threshold_release_cause = rt.host_rt_event_mod_debug_release_cause(threshold_snap.mod_debug);
        if (threshold_release_count == 0) begin
            `uvm_fatal("P29E_TELEM/THRESHOLD_RELEASE",
                $sformatf("P29E threshold release counter did not increment: mod_debug=0x%08h release=%s(0x%02h)",
                    threshold_snap.mod_debug,
                    rt.host_rt_event_mod_release_name(threshold_release_cause),
                    threshold_release_cause))
        end

        rt.host_rt_event_mod_expect_cq_occupancy(
            threshold_snap,
            2,
            2,
            "P29E threshold CQ occupancy"
        );

        `uvm_info("P29E_TELEM/THRESHOLD_RELEASE_PASS",
            $sformatf("P29E threshold moderation release observed: threshold_count=%0d release=%s(0x%02h) pending=0x%08h mod_debug=0x%08h",
                threshold_release_count,
                rt.host_rt_event_mod_release_name(threshold_release_cause),
                threshold_release_cause,
                threshold_snap.event_pending,
                threshold_snap.mod_debug),
            UVM_MEDIUM)

        rt.host_rt_event_mod_consume_cq_batch(
            cfg,
            threshold_snap,
            0,
            batch_result,
            2,
            1'b1,
            "P29E threshold telemetry batch consume",
            done_timeout_cycles * 4
        );

        if (batch_result.first_user_tag !== P29E_DESC0_TAG0) begin
            `uvm_fatal("P29E_TELEM/BATCH_FIRST_TAG",
                $sformatf("First batch CQ first_user_tag mismatch actual=0x%08h expected=0x%08h",
                    batch_result.first_user_tag,
                    P29E_DESC0_TAG0))
        end
        if (batch_result.last_user_tag !== P29E_DESC1_TAG1) begin
            `uvm_fatal("P29E_TELEM/BATCH_LAST_TAG",
                $sformatf("Last batch CQ last_user_tag mismatch actual=0x%08h expected=0x%08h",
                    batch_result.last_user_tag,
                    P29E_DESC1_TAG1))
        end

        `uvm_info("P29E_TELEM/BATCH_COUNTERS_PASS",
            $sformatf("P29E batch consume PASS: consumed=%0d CQ_HEAD %0d->%0d first_tag=0x%08h last_tag=0x%08h",
                batch_result.consumed_count,
                batch_result.start_cq_head,
                batch_result.final_cq_head,
                batch_result.first_user_tag,
                batch_result.last_user_tag),
            UVM_MEDIUM)

        ack_mask = threshold_snap.event_pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.host_rt_event_mod_ack_and_rearm(
            ack_mask,
            completion_event_mask,
            32'h0000_0002,
            1'b1,
            1'b1,
            "P29E threshold telemetry ack/rearm"
        );
        rt.host_rt_event_mod_capture_snapshot(rearm_snap);
        rt.host_rt_event_mod_log_snapshot("P29E post-rearm", rearm_snap, UVM_MEDIUM);
        p28d_check_rearm_clean(rearm_snap, ack_mask, "P29E post-batch rearm clean");

        p29e_check_interrupt_efficiency(batch_result, threshold_snap);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        p29e_clear_telem_counters("P29E post-run clear");
        p29e_check_counters_zero("P29E after post-run clear");
        csr.write32_expect_okay(CSR_TELEM_CONTROL, 32'h0000_0000);

        `uvm_info("P29E_TELEM/PASS",
            $sformatf("P29E interrupt efficiency / coalescing telemetry PASS: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d threshold=2 batch_consumed=%0d ack_mask=0x%08h",
                selected_case_id,
                a_flat.size(),
                b_flat.size(),
                c_elems,
                batch_result.consumed_count,
                ack_mask),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
