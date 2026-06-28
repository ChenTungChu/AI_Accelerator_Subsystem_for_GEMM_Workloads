// File: tb/uvm/test/ai_accel_subsys_csr_driver_abi_cold_boot_first_command_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_DRIVER_ABI_COLD_BOOT_FIRST_COMMAND_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_DRIVER_ABI_COLD_BOOT_FIRST_COMMAND_SMOKE_TEST_SV

// ============================================================
// P30D driver ABI cold-boot / first-command smoke
//
// Scope:
//   - Reuses the validated P19-P29 queue / event / guard /
//     telemetry runtime stack.
//   - Uses the P30C driver-facing helper API rather than manually
//     spelling out each low-level CSR operation in the test body.
//   - Validates the cold boot -> guard setup -> queue setup -> event
//     arm -> telemetry enable -> first SQ command -> START_QUEUE ->
//     event wait -> CQ consume -> W1C / re-arm -> telemetry sample
//     software-facing ABI sequence.
//   - Keeps the command model single-active and in-order.
//
// P30D does not change RTL, CSR map, SQ/CQ entry format, descriptor
// format, completion record format, event bits, telemetry counters,
// BRAM, GEMM, DMA, AXI-Stream, Direct Stream datapath behavior,
// UVM top selection, or sim flow.
// ============================================================

class ai_accel_subsys_csr_driver_abi_cold_boot_first_command_smoke_test
    extends ai_accel_subsys_csr_event_driven_multi_command_queue_drain_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_driver_abi_cold_boot_first_command_smoke_test)

    localparam int unsigned P30D_SQ_BASE     = 32'h0000_0700;
    localparam int unsigned P30D_CQ_BASE     = 32'h0000_0800;
    localparam int unsigned P30D_QUEUE_DEPTH = 4;

    localparam int unsigned P30D_DESC_BASE   = 32'h0000_0300;
    localparam int unsigned P30D_DESC_STRIDE = 32'h0000_0080;

    localparam logic [31:0] P30D_CMD_TAG     = 32'hD30D_0000;
    localparam logic [31:0] P30D_DESC_TAG0   = 32'hD30D_1000;
    localparam logic [31:0] P30D_DESC_TAG1   = 32'hD30D_1001;

    function new(string name = "ai_accel_subsys_csr_driver_abi_cold_boot_first_command_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p30d_expect_eq32(input string       name,
                                    input logic [31:0] actual,
                                    input logic [31:0] expected);
    begin
        if (actual !== expected) begin
            `uvm_fatal("P30D_ABI/MISMATCH",
                $sformatf("%s mismatch: actual=0x%08h expected=0x%08h",
                    name,
                    actual,
                    expected))
        end

        `uvm_info("P30D_ABI/CHECK",
            $sformatf("%s PASS: 0x%08h", name, actual),
            UVM_LOW)
    end
    endtask

    task automatic p30d_expect_zero32(input string       name,
                                      input logic [31:0] actual);
    begin
        p30d_expect_eq32(name, actual, 32'h0000_0000);
    end
    endtask

    task automatic p30d_expect_nonzero32(input string       name,
                                         input logic [31:0] actual);
    begin
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P30D_ABI/ZERO",
                $sformatf("%s unexpectedly zero", name))
        end

        `uvm_info("P30D_ABI/CHECK",
            $sformatf("%s nonzero PASS: 0x%08h", name, actual),
            UVM_LOW)
    end
    endtask

    task automatic p30d_expect_at_least(input string       name,
                                        input logic [31:0] actual,
                                        input logic [31:0] minimum);
    begin
        if (actual < minimum) begin
            `uvm_fatal("P30D_ABI/TOO_SMALL",
                $sformatf("%s too small: actual=%0d minimum=%0d",
                    name,
                    actual,
                    minimum))
        end

        `uvm_info("P30D_ABI/CHECK",
            $sformatf("%s >= %0d PASS: actual=%0d", name, minimum, actual),
            UVM_LOW)
    end
    endtask

    task automatic p30d_program_descriptor_table(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
    begin
        program_memory_descriptor(
            P30D_DESC_BASE + (0 * P30D_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            P30D_DESC_TAG0
        );

        program_memory_descriptor(
            P30D_DESC_BASE + (1 * P30D_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            P30D_DESC_TAG1
        );
    end
    endtask

    task automatic p30d_check_event_snapshot_before_ack(
        input ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t snap,
        input logic [31:0] required_mask
    );
    begin
        if ((snap.pending & required_mask) !== required_mask) begin
            `uvm_fatal("P30D_ABI/EVENT_MISSING",
                $sformatf("Required event bits missing before ack: pending=0x%08h required=0x%08h",
                    snap.pending,
                    required_mask))
        end

        if (!snap.status[ai_accel_csr_access_helper::EVENT_STATUS_PENDING_NONZERO]) begin
            `uvm_fatal("P30D_ABI/EVENT_STATUS",
                $sformatf("EVENT_STATUS.PENDING_NONZERO not set before ack: status=0x%08h pending=0x%08h",
                    snap.status,
                    snap.pending))
        end

        if (!snap.status[ai_accel_csr_access_helper::EVENT_STATUS_EVENT_IRQ_OUT]) begin
            `uvm_fatal("P30D_ABI/EVENT_IRQ",
                $sformatf("EVENT_STATUS.EVENT_IRQ_OUT not set before ack: status=0x%08h pending=0x%08h",
                    snap.status,
                    snap.pending))
        end

        p30d_expect_nonzero32("EVENT_COUNT after first command",     snap.event_count);
        p30d_expect_nonzero32("EVENT_IRQ_COUNT after first command", snap.irq_count);

        `uvm_info("P30D_ABI/EVENT_PASS",
            $sformatf("First-command event wait PASS: pending=0x%08h required=0x%08h status=0x%08h last_cause=0x%08h count=%0d irq_count=%0d snapshot0=0x%08h snapshot1=0x%08h",
                snap.pending,
                required_mask,
                snap.status,
                snap.last_cause,
                snap.event_count,
                snap.irq_count,
                snap.snapshot0,
                snap.snapshot1),
            UVM_MEDIUM)
    end
    endtask

    task automatic p30d_check_queue_state_after_consume(input logic [31:0] ack_mask);
        logic [31:0] queue_status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] sq_head;
        logic [31:0] sq_tail;
        logic [31:0] cq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
        logic [31:0] last_tag;
        logic [31:0] event_pending;
        logic [31:0] event_status;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS,        queue_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS,   done_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,  error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,       sq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,       sq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,       cq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,       cq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY,  cq_occ);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG,  last_tag);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_PENDING,       event_pending);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_STATUS,        event_status);

        p30d_expect_eq32("SQ_HEAD after first command", sq_head, 32'h0000_0001);
        p30d_expect_eq32("SQ_TAIL after first command", sq_tail, 32'h0000_0001);
        p30d_expect_eq32("CQ_HEAD after consume",       cq_head, 32'h0000_0001);
        p30d_expect_eq32("CQ_TAIL after first command", cq_tail, 32'h0000_0001);
        p30d_expect_eq32("CQ_OCC after consume",        cq_occ,  32'h0000_0000);
        p30d_expect_eq32("QUEUE_LAST_CMD_TAG",          last_tag, P30D_CMD_TAG);
        p30d_expect_zero32("QUEUE_ERROR_STATUS",        error_status);
        p30d_expect_zero32("QUEUE_REJECT_STATUS",       reject_status);

        if (queue_status[0]) begin
            `uvm_fatal("P30D_ABI/QUEUE_BUSY",
                $sformatf("Queue still busy after first command consume: status=0x%08h", queue_status))
        end

        if (!done_status[1] || !done_status[2]) begin
            `uvm_fatal("P30D_ABI/DONE_STATUS",
                $sformatf("Expected QUEUE_DRAINED and COMMAND_COMPLETED sticky bits set, done_status=0x%08h",
                    done_status))
        end

        if ((event_pending & ack_mask) != 32'h0000_0000) begin
            `uvm_fatal("P30D_ABI/EVENT_ACK_FAIL",
                $sformatf("Acked event bits still pending: pending=0x%08h ack_mask=0x%08h",
                    event_pending,
                    ack_mask))
        end

        if ((event_status & 32'h0000_0007) != 32'h0000_0000) begin
            `uvm_fatal("P30D_ABI/IRQ_STILL_SET",
                $sformatf("Pending/eligible/IRQ status bits still set after ack: status=0x%08h",
                    event_status))
        end

        `uvm_info("P30D_ABI/QUEUE_STATE_PASS",
            $sformatf("First-command queue state PASS: status=0x%08h done=0x%08h SQ(h/t)=%0d/%0d CQ(h/t/occ)=%0d/%0d/%0d event_pending=0x%08h",
                queue_status,
                done_status,
                sq_head,
                sq_tail,
                cq_head,
                cq_tail,
                cq_occ,
                event_pending),
            UVM_MEDIUM)
    end
    endtask

    task automatic p30d_check_telemetry(
        input ai_accel_event_driven_host_runtime_stress_helper::p29_runtime_telem_snapshot_t snap
    );
    begin
        p30d_expect_eq32("CSR_TELEM_VERSION", snap.version, ai_accel_csr_access_helper::TELEM_VERSION_RESET);

        if (!snap.status[ai_accel_csr_access_helper::TELEM_STATUS_ENABLED] ||
            !snap.status[ai_accel_csr_access_helper::TELEM_STATUS_CYCLE_ENABLED] ||
            !snap.status[ai_accel_csr_access_helper::TELEM_STATUS_HOST_CQ_CONSUME_ENABLED] ||
            !snap.status[ai_accel_csr_access_helper::TELEM_STATUS_EVENT_EFF_ENABLED]) begin
            `uvm_fatal("P30D_ABI/TELEM_STATUS",
                $sformatf("Telemetry enable/status bits are not all set: status=0x%08h control=0x%08h",
                    snap.status,
                    snap.control))
        end

        p30d_expect_eq32("telemetry control",       snap.control,              ai_accel_csr_access_helper::TELEM_ENABLE_ALL_VALUE);
        p30d_expect_eq32("queue_start_count",      snap.queue_start_count,    32'h0000_0001);
        p30d_expect_at_least("sq_accept_count",    snap.sq_accept_count,      32'h0000_0001);
        p30d_expect_at_least("cmd_complete_count", snap.cmd_complete_count,   32'h0000_0001);
        p30d_expect_eq32("cq_commit_count",        snap.cq_commit_count,      32'h0000_0001);
        p30d_expect_nonzero32("queue_drained_count", snap.queue_drained_count);
        p30d_expect_zero32("queue_error_count",    snap.queue_error_count);

        p30d_expect_at_least("cq_head_update_count", snap.cq_head_update_count, 32'h0000_0001);
        p30d_expect_eq32("cq_consumed_count",        snap.cq_consumed_count,    32'h0000_0001);
        p30d_expect_at_least("max_cq_batch_size",    snap.max_cq_batch_size,    32'h0000_0001);

        p30d_expect_nonzero32("event_capture_count",    snap.event_capture_count);
        p30d_expect_nonzero32("irq_eligible_count",     snap.irq_eligible_count);
        p30d_expect_nonzero32("completion_event_count", snap.completion_event_count);

        p30d_expect_zero32("coalesced_release_count",     snap.coalesced_release_count);
        p30d_expect_zero32("threshold_release_count",     snap.threshold_release_count);
        p30d_expect_zero32("timer_release_count",         snap.timer_release_count);
        p30d_expect_zero32("cq_full_stall_count",         snap.cq_full_stall_count);
        p30d_expect_zero32("cq_space_recovered_count",    snap.cq_space_recovered_count);
        p30d_expect_zero32("timeout_error_count",         snap.timeout_error_count);
        p30d_expect_zero32("mem_guard_error_count",       snap.mem_guard_error_count);
        p30d_expect_zero32("stop_queue_request_count",    snap.stop_queue_request_count);

        p30d_expect_nonzero32("queue_enabled_cycles", snap.queue_enabled_cycles);
        p30d_expect_nonzero32("queue_busy_cycles",    snap.queue_busy_cycles);
        p30d_expect_nonzero32("queue_idle_cycles",    snap.queue_idle_cycles);

        `uvm_info("P30D_ABI/TELEMETRY_PASS",
            $sformatf("First-command telemetry PASS: start=%0d sq_accept=%0d complete=%0d cq_commit=%0d cq_update=%0d cq_consumed=%0d event=%0d irq=%0d cycles(en/busy/idle)=%0d/%0d/%0d",
                snap.queue_start_count,
                snap.sq_accept_count,
                snap.cmd_complete_count,
                snap.cq_commit_count,
                snap.cq_head_update_count,
                snap.cq_consumed_count,
                snap.event_capture_count,
                snap.irq_eligible_count,
                snap.queue_enabled_cycles,
                snap.queue_busy_cycles,
                snap.queue_idle_cycles),
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
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t queue_cfg;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t event_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p27_guard_cfg_t guard_cfg;
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_cfg_t event_mod_cfg;
        ai_accel_event_driven_host_runtime_stress_helper::p30_driver_runtime_abi_cfg_t abi_cfg;
        ai_accel_event_driven_host_runtime_stress_helper::p29_runtime_telem_snapshot_t telem_snap;

        logic [31:0] event_mask;
        logic [31:0] ack_mask;
        logic [31:0] guard_control;
    begin
        phase.raise_objection(this);

        `uvm_info("P30D_ABI/START",
            "Starting P30D driver ABI cold-boot / first-command smoke test",
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
            `uvm_fatal("P30D_ABI/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);
        p30d_program_descriptor_table(
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        rt.make_default_queue_cfg(
            queue_cfg,
            32'(P30D_SQ_BASE),
            32'(P30D_CQ_BASE),
            32'(P30D_QUEUE_DEPTH),
            1'b1
        );

        rt.make_fetch_recipe_cmd(
            cmd,
            32'(P30D_DESC_BASE),
            32'h0000_0002,
            32'(P30D_DESC_STRIDE),
            P30D_CMD_TAG,
            1'b1,
            1'b0
        );

        event_mask = rt.queue_completion_event_mask() |
                     rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);

        guard_control = rt.host_rt_mem_guard_control_value(
            1'b1, // guard_enable
            1'b1, // strict_reject_enable
            1'b1, // SQ check
            1'b1, // CQ check
            1'b1, // descriptor check
            1'b0, // source check deferred to P30F-style recovery validation
            1'b0, // destination check deferred to P30F-style recovery validation
            1'b1  // write CQ error if safe
        );

        rt.host_rt_mem_guard_default_cfg_from_queue(
            queue_cfg,
            32'(P30D_DESC_BASE),
            32'(2 * P30D_DESC_STRIDE),
            32'h0000_0000,
            32'h0000_2000,
            32'h0000_0000,
            32'h0000_2000,
            guard_control,
            guard_cfg
        );

        event_mod_cfg.mod_control       = 32'h0000_0000;
        event_mod_cfg.event_enable_mask = event_mask;
        event_mod_cfg.event_control     = 32'h0000_0005;
        event_mod_cfg.cq_threshold      = 32'h0000_0000;
        event_mod_cfg.timer_limit       = 32'h0000_0000;

        rt.host_rt_abi_default_cfg(
            abi_cfg,
            queue_cfg,
            event_mask,
            guard_cfg,
            event_mod_cfg,
            1'b1,
            1'b0,
            1'b1,
            ai_accel_csr_access_helper::TELEM_ENABLE_ALL_VALUE,
            1'b1,
            1'b1
        );

        csr_program_completion_wb();

        rt.host_rt_abi_cold_boot_init(abi_cfg, "P30D cold boot init");
        rt.host_rt_telem_check_selected_zero("P30D after cold boot telemetry clear");

        `uvm_info("P30D_ABI/COLD_BOOT_PASS",
            $sformatf("Cold boot ABI init PASS: guard enabled, queue programmed, events armed, telemetry enabled SQ=0x%08h CQ=0x%08h event_mask=0x%08h",
                queue_cfg.sq_base,
                queue_cfg.cq_base,
                event_mask),
            UVM_MEDIUM)

        rt.host_rt_abi_submit_command(abi_cfg, 0, cmd, 32'h0000_0001, "P30D submit first SQ command");
        rt.host_rt_abi_start_queue("P30D START_QUEUE first command");

        rt.wait_events(event_mask, event_snap, done_timeout_cycles * 8, 1'b1);
        p30d_check_event_snapshot_before_ack(event_snap, event_mask);

        rt.host_rt_abi_consume_one_cq(abi_cfg, 0, rec, 1'b1, "P30D consume first CQ");
        check_p23d_cq_record(0, rec, profile_item, P30D_DESC_TAG0, P30D_DESC_TAG1);

        ack_mask = event_snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.host_rt_abi_ack_and_rearm(abi_cfg, ack_mask, "P30D ack/re-arm after first command");

        p30d_check_queue_state_after_consume(ack_mask);
        rt.host_rt_mem_guard_check_clean("P30D post-run guard clean", 1'b1, 1'b1);

        rt.host_rt_abi_sample_telemetry(telem_snap, "P30D telemetry sample");
        p30d_check_telemetry(telem_snap);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P30D_ABI/PASS",
            $sformatf("P30D driver ABI cold boot first-command PASS: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d SQ_entries=1 CQ_entries=1 event_mask=0x%08h ack_mask=0x%08h",
                selected_case_id,
                a_flat.size(),
                b_flat.size(),
                c_elems,
                event_mask,
                ack_mask),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
