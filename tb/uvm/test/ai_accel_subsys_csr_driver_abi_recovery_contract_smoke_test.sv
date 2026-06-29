// File: tb/uvm/test/ai_accel_subsys_csr_driver_abi_recovery_contract_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_DRIVER_ABI_RECOVERY_CONTRACT_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_DRIVER_ABI_RECOVERY_CONTRACT_SMOKE_TEST_SV

// ============================================================
// P30F driver ABI recovery contract smoke
//
// Scope:
//   - Reuses the validated P19-P29 queue / event / guard /
//     telemetry runtime stack.
//   - Builds on the P30C driver-facing helper API and the P30D/P30E
//     software-style bring-up / steady-state flows.
//   - Validates representative driver recovery contracts:
//       * CQ-full backpressure recovery through CQ_HEAD advancement
//       * command-timeout error cleanup / reinit / known-good restart
//       * memory-guard descriptor-range reject cleanup / known-good restart
//   - Confirms P29 telemetry observes the recovery conditions while
//     preserving the single-active, in-order queue execution model.
//
// P30F does not change RTL, CSR map, SQ/CQ entry format, descriptor
// format, completion record format, event bits, telemetry counters,
// BRAM, GEMM, DMA, AXI-Stream, Direct Stream datapath behavior,
// UVM top selection, or sim flow.
// ============================================================

class ai_accel_subsys_csr_driver_abi_recovery_contract_smoke_test
    extends ai_accel_subsys_csr_queue_lifecycle_timeout_error_reinit_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_driver_abi_recovery_contract_smoke_test)

    localparam int unsigned P30F_SQ_BASE         = 32'h0000_0900;
    localparam int unsigned P30F_CQ_BASE         = 32'h0000_0A00;
    localparam int unsigned P30F_QUEUE_DEPTH     = 4;
    localparam int unsigned P30F_CQ_FULL_DEPTH   = 1;

    // Keep all software-visible runtime objects inside the validated
    // scratchpad address aperture used by the P17-P29 CSR queue tests.
    // The descriptor tables occupy [0x300,0x900); SQ uses [0x900,0xA00)
    // and CQ uses [0xA00,0xB00), avoiding overlap while staying below
    // the 0x1000 local memory boundary.

    localparam int unsigned P30F_DESC_STRIDE     = 32'h0000_0080;
    localparam int unsigned P30F_DESC_REGION     = 32'h0000_0100;

    localparam int unsigned P30F_CQFULL_DESC0    = 32'h0000_0300;
    localparam int unsigned P30F_CQFULL_DESC1    = 32'h0000_0400;
    localparam int unsigned P30F_TIMEOUT_DESC    = 32'h0000_0500;
    localparam int unsigned P30F_TIMEOUT_REC_DESC= 32'h0000_0600;
    localparam int unsigned P30F_GUARD_BAD_DESC  = 32'h0000_0700;
    localparam int unsigned P30F_GUARD_REC_DESC  = 32'h0000_0800;

    localparam logic [31:0] P30F_CQFULL_CMD0_TAG     = 32'hD30F_0000;
    localparam logic [31:0] P30F_CQFULL_CMD1_TAG     = 32'hD30F_0001;
    localparam logic [31:0] P30F_TIMEOUT_CMD_TAG     = 32'hD30F_0010;
    localparam logic [31:0] P30F_TIMEOUT_REC_CMD_TAG = 32'hD30F_0011;
    localparam logic [31:0] P30F_GUARD_BAD_CMD_TAG   = 32'hD30F_0020;
    localparam logic [31:0] P30F_GUARD_REC_CMD_TAG   = 32'hD30F_0021;

    localparam logic [31:0] P30F_CQFULL0_TAG0        = 32'hD30F_1000;
    localparam logic [31:0] P30F_CQFULL0_TAG1        = 32'hD30F_1001;
    localparam logic [31:0] P30F_CQFULL1_TAG0        = 32'hD30F_1100;
    localparam logic [31:0] P30F_CQFULL1_TAG1        = 32'hD30F_1101;
    localparam logic [31:0] P30F_TIMEOUT_TAG0        = 32'hD30F_2000;
    localparam logic [31:0] P30F_TIMEOUT_TAG1        = 32'hD30F_2001;
    localparam logic [31:0] P30F_TIMEOUT_REC_TAG0    = 32'hD30F_2100;
    localparam logic [31:0] P30F_TIMEOUT_REC_TAG1    = 32'hD30F_2101;
    localparam logic [31:0] P30F_GUARD_BAD_TAG0      = 32'hD30F_3000;
    localparam logic [31:0] P30F_GUARD_BAD_TAG1      = 32'hD30F_3001;
    localparam logic [31:0] P30F_GUARD_REC_TAG0      = 32'hD30F_3100;
    localparam logic [31:0] P30F_GUARD_REC_TAG1      = 32'hD30F_3101;

    // Keep the timeout intentionally shorter than the normal two-slot
    // descriptor/recipe path so the P24 watchdog recovery contract is hit.
    localparam logic [31:0] P30F_SHORT_TIMEOUT_CYCLES = 32'h0000_0020;

    function new(string name = "ai_accel_subsys_csr_driver_abi_recovery_contract_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p30f_expect_eq32(input string       name,
                                    input logic [31:0] actual,
                                    input logic [31:0] expected);
    begin
        if (actual !== expected) begin
            `uvm_fatal("P30F_ABI/MISMATCH",
                $sformatf("%s mismatch: actual=0x%08h expected=0x%08h",
                    name,
                    actual,
                    expected))
        end

        `uvm_info("P30F_ABI/CHECK",
            $sformatf("%s PASS: 0x%08h", name, actual),
            UVM_LOW)
    end
    endtask

    task automatic p30f_expect_zero32(input string       name,
                                      input logic [31:0] actual);
    begin
        p30f_expect_eq32(name, actual, 32'h0000_0000);
    end
    endtask

    task automatic p30f_expect_nonzero32(input string       name,
                                         input logic [31:0] actual);
    begin
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P30F_ABI/ZERO",
                $sformatf("%s unexpectedly zero", name))
        end

        `uvm_info("P30F_ABI/CHECK",
            $sformatf("%s nonzero PASS: 0x%08h", name, actual),
            UVM_LOW)
    end
    endtask

    task automatic p30f_expect_at_least(input string       name,
                                        input logic [31:0] actual,
                                        input logic [31:0] minimum);
    begin
        if (actual < minimum) begin
            `uvm_fatal("P30F_ABI/TOO_SMALL",
                $sformatf("%s too small: actual=%0d minimum=%0d",
                    name,
                    actual,
                    minimum))
        end

        `uvm_info("P30F_ABI/CHECK",
            $sformatf("%s >= %0d PASS: actual=%0d", name, minimum, actual),
            UVM_LOW)
    end
    endtask

    task automatic p30f_make_queue_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input  int unsigned cq_depth
    );
    begin
        rt.make_default_queue_cfg(
            cfg,
            32'(P30F_SQ_BASE),
            32'(P30F_CQ_BASE),
            32'(P30F_QUEUE_DEPTH),
            1'b1
        );
        cfg.cq_depth = 32'(cq_depth);
    end
    endtask

    task automatic p30f_make_cmd(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd,
        input  logic [31:0] desc_base,
        input  logic [31:0] user_tag,
        input  logic [31:0] timeout_cycles = 32'h0000_0000
    );
    begin
        rt.make_fetch_recipe_cmd(
            cmd,
            desc_base,
            32'h0000_0002,
            32'(P30F_DESC_STRIDE),
            user_tag,
            1'b1,
            1'b0
        );
        cmd.timeout_cycles = timeout_cycles;
    end
    endtask

    task automatic p30f_make_guard_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        input  ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t queue_cfg,
        input  logic [31:0] desc_base,
        input  logic [31:0] desc_size_bytes,
        output ai_accel_event_driven_host_runtime_stress_helper::p27_guard_cfg_t guard_cfg
    );
        logic [31:0] guard_control;
    begin
        guard_control = rt.host_rt_mem_guard_control_value(
            1'b1, // guard_enable
            1'b1, // strict_reject_enable
            1'b1, // SQ check
            1'b1, // CQ check
            1'b1, // descriptor check
            1'b1, // source check
            1'b1, // destination check
            1'b1  // write CQ error if safe
        );

        rt.host_rt_mem_guard_default_cfg_from_queue(
            queue_cfg,
            desc_base,
            desc_size_bytes,
            32'h0000_0000,
            32'h0000_2000,
            32'h0000_0000,
            32'h0000_2000,
            guard_control,
            guard_cfg
        );
    end
    endtask

    task automatic p30f_make_event_mod_cfg(
        output ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_cfg_t event_mod_cfg,
        input  logic [31:0] event_mask
    );
    begin
        event_mod_cfg.mod_control       = 32'h0000_0000;
        event_mod_cfg.event_enable_mask = event_mask;
        event_mod_cfg.event_control     = 32'h0000_0005;
        event_mod_cfg.cq_threshold      = 32'h0000_0000;
        event_mod_cfg.timer_limit       = 32'h0000_0000;
    end
    endtask

    task automatic p30f_make_abi_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        input  ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t queue_cfg,
        input  ai_accel_event_driven_host_runtime_stress_helper::p27_guard_cfg_t guard_cfg,
        input  logic [31:0] event_mask,
        output ai_accel_event_driven_host_runtime_stress_helper::p30_driver_runtime_abi_cfg_t abi_cfg
    );
        ai_accel_event_driven_host_runtime_stress_helper::p28_event_mod_cfg_t event_mod_cfg;
    begin
        p30f_make_event_mod_cfg(event_mod_cfg, event_mask);
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
    end
    endtask

    task automatic p30f_program_descriptor_table(
        input ai_accel_subsys_seq_item profile_item,
        input logic [31:0] desc_base,
        input logic [31:0] tag0,
        input logic [31:0] tag1,
        input int unsigned a_bytes,
        input int unsigned b_bytes,
        input int unsigned c_bytes
    );
    begin
        p25c_program_descriptor_table(
            desc_base,
            tag0,
            tag1,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes
        );
    end
    endtask

    task automatic p30f_check_timeout_snapshot(
        input ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t snap,
        input string label
    );
    begin
        if ((snap.event_snap.pending & (32'h1 << ai_accel_csr_access_helper::P22_EVENT_QUEUE_ERROR)) == 32'h0000_0000) begin
            `uvm_fatal("P30F_ABI/TIMEOUT_EVENT_MISSING",
                $sformatf("%s: expected QUEUE_ERROR_EVENT pending, pending=0x%08h status=0x%08h",
                    label,
                    snap.event_snap.pending,
                    snap.event_snap.status))
        end

        if (!snap.queue_status[2]) begin
            `uvm_fatal("P30F_ABI/TIMEOUT_STATUS_MISSING",
                $sformatf("%s: expected QUEUE_STATUS.QUEUE_ERROR, status=0x%08h error=0x%08h reject=0x%08h",
                    label,
                    snap.queue_status,
                    snap.queue_error_status,
                    snap.queue_reject_status))
        end

        if (!snap.queue_error_status[6]) begin
            `uvm_fatal("P30F_ABI/TIMEOUT_BIT_MISSING",
                $sformatf("%s: expected CSR_QUEUE_ERROR_STATUS[6] COMMAND_TIMEOUT_ERROR, error=0x%08h detail=0x%08h tag=0x%08h",
                    label,
                    snap.queue_error_status,
                    snap.error_detail,
                    snap.last_cmd_tag))
        end

        if (snap.last_cmd_tag !== P30F_TIMEOUT_CMD_TAG) begin
            `uvm_fatal("P30F_ABI/TIMEOUT_TAG_MISMATCH",
                $sformatf("%s: timeout tag mismatch actual=0x%08h expected=0x%08h",
                    label,
                    snap.last_cmd_tag,
                    P30F_TIMEOUT_CMD_TAG))
        end

        `uvm_info("P30F_ABI/TIMEOUT_OBSERVED",
            $sformatf("%s: timeout observed pending=0x%08h error=0x%08h detail=0x%08h SQ(h/t)=%0d/%0d CQ(h/t)=%0d/%0d",
                label,
                snap.event_snap.pending,
                snap.queue_error_status,
                snap.error_detail,
                snap.sq_head,
                snap.sq_tail,
                snap.cq_head,
                snap.cq_tail),
            UVM_MEDIUM)
    end
    endtask


    // P30F recovery contract note:
    //   The validated P26 helper resets queue pointers through
    //   RESET_QUEUE_POINTERS.  P30F is driver-ABI recovery validation, not
    //   pointer-reset policy validation.  For timeout / guard discard paths,
    //   use an idle-time discard cleanup that clears sticky state, recycles
    //   SQ/CQ memory, reprograms the queue window, and re-arms events without
    //   waiting on RESET_QUEUE_POINTERS.  This mirrors the P30B software
    //   contract: error recovery may reinitialize the idle queue context before
    //   submitting a known-good command.
    task automatic p30f_cleanup_error_discard_no_ptr_reset(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        input  ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input  logic [31:0] event_enable_mask,
        output ai_accel_event_driven_host_runtime_stress_helper::p26_lifecycle_snapshot_t error_snap,
        input  bit consume_visible_cq = 1'b1,
        input  bit recycle_memory = 1'b1,
        input  bit clear_lower_sticky = 1'b1,
        input  string label = "p30f_cleanup_error_discard_no_ptr_reset"
    );
    begin
        rt.host_rt_lifecycle_wait_idle({label, " wait_idle"}, 200000, 1'b1);
        rt.host_rt_lifecycle_capture_error_snapshot(error_snap, {label, " error_snapshot"}, 1'b1);

        if (consume_visible_cq) begin
            rt.host_rt_lifecycle_consume_visible_cq(cfg, error_snap, 1'b1, {label, " consume_cq"});
        end

        rt.host_rt_lifecycle_clear_all_events_and_counters({label, " event_clear"});
        rt.host_rt_lifecycle_clear_queue_all_sticky(1'b1, {label, " queue_clear"});
        if (clear_lower_sticky) begin
            rt.host_rt_lifecycle_clear_lower_sticky({label, " lower_clear"});
        end

        if (recycle_memory) begin
            rt.host_rt_lifecycle_recycle_sq_slots(cfg, 0, cfg.sq_depth, {label, " recycle_sq"});
            rt.host_rt_lifecycle_recycle_cq_slots(cfg, 0, cfg.cq_depth, {label, " recycle_cq"});
        end

        rt.program_queue(cfg);
        rt.host_rt_lifecycle_rearm_events(event_enable_mask, 1'b1, 32'h0000_0000, 1'b1, {label, " event_rearm"});
        rt.host_rt_lifecycle_check_clean_idle({label, " clean_check"}, 1'b1, 1'b1, 1'b0);

        `uvm_info("P30F_ABI/ERROR_DISCARD_NO_RESET_PASS",
            $sformatf("%s: error discard cleanup PASS without RESET_QUEUE_POINTERS SQ(base=0x%08h depth=%0d h/t=%0d/%0d) CQ(base=0x%08h depth=%0d h/t=%0d/%0d)",
                label,
                cfg.sq_base,
                cfg.sq_depth,
                cfg.sq_head,
                cfg.sq_tail,
                cfg.cq_base,
                cfg.cq_depth,
                cfg.cq_head,
                cfg.cq_tail),
            UVM_MEDIUM)
    end
    endtask

    task automatic p30f_check_recovery_telemetry(
        input ai_accel_event_driven_host_runtime_stress_helper::p29_runtime_telem_snapshot_t snap
    );
    begin
        p30f_expect_eq32("CSR_TELEM_VERSION", snap.version, ai_accel_csr_access_helper::TELEM_VERSION_RESET);

        if (!snap.status[ai_accel_csr_access_helper::TELEM_STATUS_ENABLED] ||
            !snap.status[ai_accel_csr_access_helper::TELEM_STATUS_CYCLE_ENABLED] ||
            !snap.status[ai_accel_csr_access_helper::TELEM_STATUS_HOST_CQ_CONSUME_ENABLED] ||
            !snap.status[ai_accel_csr_access_helper::TELEM_STATUS_EVENT_EFF_ENABLED]) begin
            `uvm_fatal("P30F_ABI/TELEM_STATUS",
                $sformatf("Telemetry enable/status bits are not all set: status=0x%08h control=0x%08h",
                    snap.status,
                    snap.control))
        end

        p30f_expect_eq32("telemetry control", snap.control, ai_accel_csr_access_helper::TELEM_ENABLE_ALL_VALUE);

        p30f_expect_at_least("queue_start_count",         snap.queue_start_count,        32'h0000_0005);
        p30f_expect_at_least("sq_accept_count",           snap.sq_accept_count,          32'h0000_0004);
        p30f_expect_at_least("cmd_complete_count",        snap.cmd_complete_count,       32'h0000_0003);
        p30f_expect_at_least("cq_commit_count",           snap.cq_commit_count,          32'h0000_0003);
        p30f_expect_at_least("queue_drained_count",       snap.queue_drained_count,      32'h0000_0003);
        p30f_expect_at_least("queue_error_count",         snap.queue_error_count,        32'h0000_0002);

        p30f_expect_at_least("cq_head_update_count",      snap.cq_head_update_count,     32'h0000_0003);
        p30f_expect_at_least("cq_consumed_count",         snap.cq_consumed_count,        32'h0000_0003);
        p30f_expect_at_least("max_cq_batch_size",         snap.max_cq_batch_size,        32'h0000_0001);

        p30f_expect_nonzero32("event_capture_count",      snap.event_capture_count);
        p30f_expect_nonzero32("irq_eligible_count",       snap.irq_eligible_count);
        p30f_expect_nonzero32("completion_event_count",   snap.completion_event_count);

        p30f_expect_nonzero32("cq_full_stall_count",      snap.cq_full_stall_count);
        p30f_expect_nonzero32("cq_space_recovered_count", snap.cq_space_recovered_count);
        p30f_expect_nonzero32("timeout_error_count",      snap.timeout_error_count);
        p30f_expect_nonzero32("mem_guard_error_count",    snap.mem_guard_error_count);
        p30f_expect_zero32("stop_queue_request_count",    snap.stop_queue_request_count);

        p30f_expect_nonzero32("queue_enabled_cycles",     snap.queue_enabled_cycles);
        p30f_expect_nonzero32("queue_busy_cycles",        snap.queue_busy_cycles);
        p30f_expect_nonzero32("queue_idle_cycles",        snap.queue_idle_cycles);
        p30f_expect_nonzero32("queue_stalled_cycles",     snap.queue_stalled_cycles);
        p30f_expect_nonzero32("cq_full_stall_cycles",     snap.cq_full_stall_cycles);

        `uvm_info("P30F_ABI/TELEMETRY_PASS",
            $sformatf("Recovery telemetry PASS: start=%0d accept=%0d complete=%0d cq_commit=%0d errors=%0d cq_full=%0d recovered=%0d timeout=%0d guard=%0d cq_updates=%0d cq_consumed=%0d cycles(stall/cqfull)=%0d/%0d",
                snap.queue_start_count,
                snap.sq_accept_count,
                snap.cmd_complete_count,
                snap.cq_commit_count,
                snap.queue_error_count,
                snap.cq_full_stall_count,
                snap.cq_space_recovered_count,
                snap.timeout_error_count,
                snap.mem_guard_error_count,
                snap.cq_head_update_count,
                snap.cq_consumed_count,
                snap.queue_stalled_cycles,
                snap.cq_full_stall_cycles),
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
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg_cq_full;
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg_normal;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd0;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd1;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t timeout_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t timeout_recovery_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t guard_bad_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t guard_recovery_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec0;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec1;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t event_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t stall_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t recovered_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t drained_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t timeout_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t good_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t guard_error_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p26_lifecycle_snapshot_t error_lifecycle_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p27_guard_cfg_t guard_cq_full;
        ai_accel_event_driven_host_runtime_stress_helper::p27_guard_cfg_t guard_good;
        ai_accel_event_driven_host_runtime_stress_helper::p27_guard_cfg_t guard_bad;
        ai_accel_event_driven_host_runtime_stress_helper::p30_driver_runtime_abi_cfg_t abi_cq_full;
        ai_accel_event_driven_host_runtime_stress_helper::p30_driver_runtime_abi_cfg_t abi_normal;
        ai_accel_event_driven_host_runtime_stress_helper::p29_runtime_telem_snapshot_t telem_snap;

        logic [31:0] completion_event_mask;
        logic [31:0] recovery_event_mask;
        logic [31:0] error_event_mask;
        logic [31:0] cq_full_event_mask;
        logic [31:0] cq_space_event_mask;
        logic [31:0] ack_mask;
        logic [31:0] guard_error_mask;
    begin
        phase.raise_objection(this);

        `uvm_info("P30F_ABI/START",
            "Starting P30F driver ABI recovery contract smoke test",
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
            `uvm_fatal("P30F_ABI/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        p30f_program_descriptor_table(profile_item, P30F_CQFULL_DESC0,     P30F_CQFULL0_TAG0,     P30F_CQFULL0_TAG1,     a_flat.size(), b_flat.size(), c_bytes);
        p30f_program_descriptor_table(profile_item, P30F_CQFULL_DESC1,     P30F_CQFULL1_TAG0,     P30F_CQFULL1_TAG1,     a_flat.size(), b_flat.size(), c_bytes);
        p30f_program_descriptor_table(profile_item, P30F_TIMEOUT_DESC,     P30F_TIMEOUT_TAG0,     P30F_TIMEOUT_TAG1,     a_flat.size(), b_flat.size(), c_bytes);
        p30f_program_descriptor_table(profile_item, P30F_TIMEOUT_REC_DESC, P30F_TIMEOUT_REC_TAG0, P30F_TIMEOUT_REC_TAG1, a_flat.size(), b_flat.size(), c_bytes);
        p30f_program_descriptor_table(profile_item, P30F_GUARD_BAD_DESC,   P30F_GUARD_BAD_TAG0,   P30F_GUARD_BAD_TAG1,   a_flat.size(), b_flat.size(), c_bytes);
        p30f_program_descriptor_table(profile_item, P30F_GUARD_REC_DESC,   P30F_GUARD_REC_TAG0,   P30F_GUARD_REC_TAG1,   a_flat.size(), b_flat.size(), c_bytes);

        p30f_make_queue_cfg(rt, cfg_cq_full, P30F_CQ_FULL_DEPTH);
        p30f_make_queue_cfg(rt, cfg_normal,  P30F_QUEUE_DEPTH);

        completion_event_mask = rt.queue_completion_event_mask() |
                                rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);
        error_event_mask      = rt.queue_error_event_mask();
        recovery_event_mask   = completion_event_mask | error_event_mask |
                                rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_FULL_STALL) |
                                rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_SPACE_RECOVERED);
        cq_full_event_mask    = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_FULL_STALL);
        cq_space_event_mask   = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_SPACE_RECOVERED);

        p30f_make_guard_cfg(rt, cfg_cq_full, 32'(P30F_CQFULL_DESC0), 32'h0000_0600, guard_cq_full);
        p30f_make_guard_cfg(rt, cfg_normal,  32'(P30F_CQFULL_DESC0), 32'h0000_0600, guard_good);
        p30f_make_guard_cfg(rt, cfg_normal,  32'(P30F_CQFULL_DESC0), 32'h0000_0400, guard_bad);

        p30f_make_abi_cfg(rt, cfg_cq_full, guard_cq_full, recovery_event_mask, abi_cq_full);
        p30f_make_abi_cfg(rt, cfg_normal,  guard_good,    recovery_event_mask, abi_normal);

        // The CQ-full phase is intentionally a pure queue backpressure
        // recovery check.  Keep the P27 memory guard disabled for this
        // first phase so guard diagnostics cannot convert a CQ-space
        // exercise into QUEUE_ERROR_EVENT before CQ_FULL_STALL_EVENT.
        // The memory-guard recovery contract is validated explicitly in
        // the final P30F phase below.
        abi_cq_full.enable_guard = 1'b0;

        p30f_make_cmd(rt, cmd0,                 32'(P30F_CQFULL_DESC0),     P30F_CQFULL_CMD0_TAG,     32'h0000_0000);
        p30f_make_cmd(rt, cmd1,                 32'(P30F_CQFULL_DESC1),     P30F_CQFULL_CMD1_TAG,     32'h0000_0000);
        p30f_make_cmd(rt, timeout_cmd,          32'(P30F_TIMEOUT_DESC),     P30F_TIMEOUT_CMD_TAG,     P30F_SHORT_TIMEOUT_CYCLES);
        p30f_make_cmd(rt, timeout_recovery_cmd, 32'(P30F_TIMEOUT_REC_DESC), P30F_TIMEOUT_REC_CMD_TAG, 32'h0000_0000);
        p30f_make_cmd(rt, guard_bad_cmd,        32'(P30F_GUARD_BAD_DESC),   P30F_GUARD_BAD_CMD_TAG,   32'h0000_0000);
        p30f_make_cmd(rt, guard_recovery_cmd,   32'(P30F_GUARD_REC_DESC),   P30F_GUARD_REC_CMD_TAG,   32'h0000_0000);

        csr_program_completion_wb();

        rt.host_rt_abi_cold_boot_init(abi_cq_full, "P30F cold boot init");
        rt.host_rt_telem_check_selected_zero("P30F after cold boot telemetry clear");

        `uvm_info("P30F_ABI/COLD_BOOT_PASS",
            $sformatf("P30F cold boot recovery ABI init PASS: SQ=0x%08h CQ=0x%08h event_mask=0x%08h telemetry enabled, CQ-full phase guard disabled",
                cfg_cq_full.sq_base,
                cfg_cq_full.cq_base,
                recovery_event_mask),
            UVM_MEDIUM)

        // --------------------------------------------------------
        // Phase 1: CQ-full recovery through host CQ consumption.
        // --------------------------------------------------------
        // Publish the two initial SQ entries with one SQ_TAIL update,
        // matching the already-validated P29F CQ-full live-service path.
        // This keeps the phase focused on command-boundary CQ-full
        // recovery instead of exercising multiple idle-time tail writes.
        rt.write_sq_command(cfg_cq_full, 0, cmd0, 1'b1);
        rt.write_sq_command(cfg_cq_full, 1, cmd1, 1'b1);
        rt.ring_sq_tail(32'h0000_0002);
        `uvm_info("P30_ABI/SUBMIT",
            "P30F CQ-full phase submitted two SQ commands and published SQ_TAIL=2",
            UVM_MEDIUM)
        rt.host_rt_abi_start_queue("P30F CQ-full phase START_QUEUE");

        rt.wait_for_progress_event(
            cq_full_event_mask,
            stall_snap,
            "P30F CQ-full stall event wait",
            done_timeout_cycles * 16,
            1'b1
        );

        rt.host_rt_abi_consume_one_cq(abi_cq_full, 0, rec0, 1'b1, "P30F CQ-full phase consume first CQ");
        check_p23d_cq_record(0, rec0, profile_item, P30F_CQFULL0_TAG0, P30F_CQFULL0_TAG1);

        `uvm_info("P30F_ABI/CQ_FULL_STALL_PASS",
            $sformatf("CQ-full recovery phase observed CQ_FULL_STALL_EVENT and consumed CQ[0]: pending=0x%08h",
                stall_snap.event_snap.pending),
            UVM_MEDIUM)

        rt.wait_for_progress_event(
            cq_space_event_mask,
            recovered_snap,
            "P30F CQ-space recovered event wait",
            done_timeout_cycles * 8,
            1'b1
        );

        `uvm_info("P30F_ABI/CQ_SPACE_RECOVERY_PASS",
            $sformatf("CQ-space recovery event observed: pending=0x%08h CQ(h/t/occ/space)=%0d/%0d/%0d/%0d",
                recovered_snap.event_snap.pending,
                recovered_snap.cq_head,
                recovered_snap.cq_tail,
                recovered_snap.cq_occupancy,
                recovered_snap.cq_space),
            UVM_MEDIUM)

        rt.wait_for_progress_event(
            rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED),
            drained_snap,
            "P30F CQ-full phase drained event wait",
            done_timeout_cycles * 16,
            1'b1
        );

        rt.host_rt_abi_consume_one_cq(abi_cq_full, 1, rec1, 1'b1, "P30F CQ-full phase consume second CQ");
        check_p23d_cq_record(1, rec1, profile_item, P30F_CQFULL1_TAG0, P30F_CQFULL1_TAG1);

        rt.read_runtime_snapshot(good_snap);
        ack_mask = good_snap.event_snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.host_rt_abi_ack_and_rearm(abi_cq_full, ack_mask, "P30F CQ-full phase final ack/re-arm");

        rt.host_rt_lifecycle_cleanup_drained(
            cfg_cq_full,
            recovery_event_mask,
            1'b0,
            1'b0,
            1'b1,
            "P30F CQ-full phase drained cleanup"
        );

        `uvm_info("P30F_ABI/CQ_FULL_RECOVERY_PASS",
            "CQ-full driver recovery contract PASS: host consumed CQ space, queue recovered, second command completed",
            UVM_MEDIUM)

        // --------------------------------------------------------
        // Phase 2: Timeout recovery through session-discard cleanup
        // and known-good restart.
        // --------------------------------------------------------
        rt.host_rt_lifecycle_init_session(
            cfg_normal,
            recovery_event_mask,
            1'b1,
            1'b1,
            "P30F timeout phase init"
        );
        rt.host_rt_mem_guard_program_regions(guard_good, "P30F timeout phase guard program");
        rt.host_rt_lifecycle_rearm_events(recovery_event_mask, 1'b1, 32'h0000_0000, 1'b1, "P30F timeout phase event rearm");

        rt.host_rt_abi_submit_command(abi_normal, 0, timeout_cmd, 32'h0000_0001, "P30F timeout phase submit timeout command");
        rt.host_rt_abi_start_queue("P30F timeout phase START_QUEUE");

        rt.wait_for_progress_event(
            error_event_mask,
            timeout_snap,
            "P30F timeout error event wait",
            done_timeout_cycles * 12,
            1'b1
        );
        p30f_check_timeout_snapshot(timeout_snap, "P30F timeout error event");

        p30f_cleanup_error_discard_no_ptr_reset(
            rt,
            cfg_normal,
            recovery_event_mask,
            error_lifecycle_snap,
            1'b1,
            1'b1,
            1'b1,
            "P30F timeout error discard cleanup"
        );

        p26f_finalize_error_discard_after_lower_quiesce(
            rt,
            cfg_normal,
            recovery_event_mask,
            "P30F timeout lower-path quiesce"
        );

        rt.deterministic_gap(9, "P30F timeout recovery gap before known-good command");
        rt.host_rt_mem_guard_program_regions(guard_good, "P30F timeout recovery guard reprogram");

        rt.host_rt_abi_submit_command(abi_normal, 0, timeout_recovery_cmd, 32'h0000_0001, "P30F timeout recovery submit known-good command");
        rt.host_rt_abi_start_queue("P30F timeout recovery START_QUEUE");
        rt.wait_for_progress_event(
            completion_event_mask,
            good_snap,
            "P30F timeout recovery known-good event wait",
            done_timeout_cycles * 12,
            1'b1
        );
        p25c_check_event_snapshot("P30F timeout recovery known-good event", good_snap, completion_event_mask);
        event_snap = good_snap.event_snap;

        rt.host_rt_abi_consume_one_cq(abi_normal, 0, rec0, 1'b1, "P30F timeout recovery consume CQ");
        check_p23d_cq_record(0, rec0, profile_item, P30F_TIMEOUT_REC_TAG0, P30F_TIMEOUT_REC_TAG1);
        ack_mask = event_snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.host_rt_abi_ack_and_rearm(abi_normal, ack_mask, "P30F timeout recovery ack/re-arm");

        rt.host_rt_lifecycle_cleanup_drained(
            cfg_normal,
            recovery_event_mask,
            1'b0,
            1'b0,
            1'b1,
            "P30F timeout recovery drained cleanup"
        );

        `uvm_info("P30F_ABI/TIMEOUT_RECOVERY_PASS",
            $sformatf("Timeout driver recovery contract PASS: timeout tag=0x%08h recovery tag=0x%08h",
                P30F_TIMEOUT_CMD_TAG,
                P30F_TIMEOUT_REC_CMD_TAG),
            UVM_MEDIUM)

        // --------------------------------------------------------
        // Phase 3: Memory-guard descriptor-range reject recovery.
        // --------------------------------------------------------
        rt.host_rt_lifecycle_init_session(
            cfg_normal,
            recovery_event_mask,
            1'b1,
            1'b1,
            "P30F guard phase init"
        );
        rt.host_rt_mem_guard_program_regions(guard_bad, "P30F guard phase intentionally narrow descriptor region");
        rt.host_rt_lifecycle_rearm_events(recovery_event_mask, 1'b1, 32'h0000_0000, 1'b1, "P30F guard phase event rearm");

        rt.host_rt_abi_submit_command(abi_normal, 0, guard_bad_cmd, 32'h0000_0001, "P30F guard phase submit invalid descriptor command");
        rt.host_rt_abi_start_queue("P30F guard phase START_QUEUE");

        rt.wait_for_progress_event(
            error_event_mask,
            guard_error_snap,
            "P30F memory-guard error event wait",
            done_timeout_cycles * 8,
            1'b1
        );

        guard_error_mask = (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_ANY) |
                           (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_DESC_RANGE);
        rt.host_rt_mem_guard_expect_error(
            guard_error_mask,
            32'(ai_accel_csr_access_helper::P27_GUARD_DOMAIN_DESC),
            ai_accel_csr_access_helper::P27_DETAIL_DESC_RANGE,
            "P30F memory-guard descriptor reject"
        );

        p30f_cleanup_error_discard_no_ptr_reset(
            rt,
            cfg_normal,
            recovery_event_mask,
            error_lifecycle_snap,
            1'b1,
            1'b1,
            1'b1,
            "P30F guard error discard cleanup"
        );

        rt.host_rt_mem_guard_program_regions(guard_good, "P30F guard recovery valid guard reprogram");
        rt.host_rt_lifecycle_rearm_events(recovery_event_mask, 1'b1, 32'h0000_0000, 1'b1, "P30F guard recovery event rearm");

        rt.host_rt_abi_submit_command(abi_normal, 0, guard_recovery_cmd, 32'h0000_0001, "P30F guard recovery submit known-good command");
        rt.host_rt_abi_start_queue("P30F guard recovery START_QUEUE");
        rt.wait_for_progress_event(
            completion_event_mask,
            good_snap,
            "P30F guard recovery known-good event wait",
            done_timeout_cycles * 12,
            1'b1
        );
        p25c_check_event_snapshot("P30F guard recovery known-good event", good_snap, completion_event_mask);
        event_snap = good_snap.event_snap;

        rt.host_rt_abi_consume_one_cq(abi_normal, 0, rec1, 1'b1, "P30F guard recovery consume CQ");
        check_p23d_cq_record(0, rec1, profile_item, P30F_GUARD_REC_TAG0, P30F_GUARD_REC_TAG1);
        ack_mask = event_snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.host_rt_abi_ack_and_rearm(abi_normal, ack_mask, "P30F guard recovery ack/re-arm");

        rt.host_rt_lifecycle_cleanup_drained(
            cfg_normal,
            recovery_event_mask,
            1'b0,
            1'b0,
            1'b1,
            "P30F guard recovery drained cleanup"
        );

        `uvm_info("P30F_ABI/GUARD_RECOVERY_PASS",
            $sformatf("Memory-guard driver recovery contract PASS: rejected desc_base=0x%08h, recovery desc_base=0x%08h",
                P30F_GUARD_BAD_DESC,
                P30F_GUARD_REC_DESC),
            UVM_MEDIUM)

        // The guard-reject phase intentionally leaves the P27 guard
        // diagnostic registers sticky so software can inspect the rejected
        // descriptor address / domain / detail.  After the recovery command
        // has completed and the queue is drained, clear those guard sticky
        // diagnostics before running the final clean check.  This keeps
        // P30F aligned with the driver ABI contract: observe the guard
        // error, recover with a known-good command, then explicitly retire
        // the stale guard diagnostic state.
        rt.host_rt_mem_guard_clear_all("P30F final guard sticky clear");
        `uvm_info("P30F_ABI/GUARD_STICKY_CLEAR_PASS",
            "P30F final guard sticky diagnostics cleared before clean check",
            UVM_MEDIUM)

        rt.host_rt_mem_guard_check_clean("P30F final guard clean", 1'b1, 1'b1);
        rt.host_rt_abi_sample_telemetry(telem_snap, "P30F telemetry sample");
        p30f_check_recovery_telemetry(telem_snap);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P30F_ABI/PASS",
            $sformatf("P30F driver ABI recovery contract PASS: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d recovery_paths={cq_full,timeout,mem_guard} event_mask=0x%08h",
                selected_case_id,
                a_flat.size(),
                b_flat.size(),
                c_elems,
                recovery_event_mask),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
