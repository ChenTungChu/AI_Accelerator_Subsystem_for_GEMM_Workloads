// File: tb/uvm/test/ai_accel_subsys_csr_mem_guard_sq_desc_range_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_MEM_GUARD_SQ_DESC_RANGE_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_MEM_GUARD_SQ_DESC_RANGE_SMOKE_TEST_SV

// ============================================================
// P27D memory guard SQ / descriptor range validation smoke
//
// Scope:
//   - Enables the P27B memory guard CSR window through the P27C
//     host-runtime helper API.
//   - Runs one valid SQ + descriptor command to prove that enabled
//     SQ/CQ/DESC checks preserve the normal queue path.
//   - Shrinks the SQ guard range so the next START_QUEUE is rejected
//     before the SQ command fetch AXI read can be issued.
//   - Restores SQ/CQ guard ranges and shrinks the descriptor guard
//     range so the fetched SQ command is rejected before P17 descriptor
//     fetch launch.
//   - Clears guard / queue / event sticky state with the P26 lifecycle
//     cleanup policy and proves a known-good recovery command completes.
//
// P27D does not change SQ/CQ entry format, descriptor format,
// completion record format, event bit allocation, BRAM, GEMM, DMA,
// AXI-Stream, or Direct Stream datapath behavior.
// ============================================================

class ai_accel_subsys_csr_mem_guard_sq_desc_range_smoke_test
    extends ai_accel_subsys_csr_queue_lifecycle_drained_reinit_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_mem_guard_sq_desc_range_smoke_test)

    localparam int unsigned P27D_SQ_BASE     = 32'h0000_0D00;
    localparam int unsigned P27D_CQ_BASE     = 32'h0000_0E00;
    localparam int unsigned P27D_QUEUE_DEPTH = 4;

    localparam int unsigned P27D_DESC_BASE0  = 32'h0000_0300;
    localparam int unsigned P27D_DESC_BASE1  = 32'h0000_0400;
    localparam int unsigned P27D_DESC_STRIDE = 32'h0000_0080;

    localparam logic [31:0] P27D_BASELINE_CMD_TAG = 32'hD27D_0000;
    localparam logic [31:0] P27D_BAD_SQ_CMD_TAG   = 32'hD27D_0001;
    localparam logic [31:0] P27D_BAD_DESC_CMD_TAG = 32'hD27D_0002;
    localparam logic [31:0] P27D_RECOVERY_CMD_TAG       = 32'hD27D_0003;
    localparam logic [31:0] P27D_ADDR_OVERFLOW_CMD_TAG  = 32'hD27D_00A1;
    localparam logic [31:0] P27D_SPAN_OVERFLOW_CMD_TAG  = 32'hD27D_00A2;

    localparam logic [31:0] P27D_DESC0_TAG0 = 32'hD27D_1000;
    localparam logic [31:0] P27D_DESC0_TAG1 = 32'hD27D_1001;
    localparam logic [31:0] P27D_DESC1_TAG0 = 32'hD27D_2000;
    localparam logic [31:0] P27D_DESC1_TAG1 = 32'hD27D_2001;

    function new(string name = "ai_accel_subsys_csr_mem_guard_sq_desc_range_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p27d_make_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg
    );
    begin
        rt.make_default_queue_cfg(
            cfg,
            32'(P27D_SQ_BASE),
            32'(P27D_CQ_BASE),
            32'(P27D_QUEUE_DEPTH),
            1'b1
        );
    end
    endtask

    task automatic p27d_make_cmd(
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
            32'(P27D_DESC_STRIDE),
            user_tag,
            1'b1,
            1'b0
        );
        cmd.timeout_cycles = 32'h0000_0000;
    end
    endtask

    task automatic p27d_make_guard_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        input  ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input  logic [31:0] sq_limit_override,
        input  logic [31:0] desc_base,
        input  logic [31:0] desc_limit,
        output ai_accel_event_driven_host_runtime_stress_helper::p27_guard_cfg_t guard_cfg
    );
        logic [31:0] control;
        logic [31:0] sq_size_bytes;
        logic [31:0] cq_size_bytes;
    begin
        control = rt.host_rt_mem_guard_control_value(
            1'b1, // guard_enable
            1'b1, // strict_reject_enable
            1'b1, // SQ check
            1'b1, // CQ check
            1'b1, // descriptor check
            1'b0, // source check deferred to P27E
            1'b0, // destination check deferred to P27E
            1'b1  // write CQ error if safe
        );

        sq_size_bytes = cfg.sq_depth * cfg.sq_stride;
        cq_size_bytes = cfg.cq_depth * cfg.cq_stride;

        guard_cfg.control    = control;
        guard_cfg.sq_base    = cfg.sq_base;
        guard_cfg.sq_limit   = (sq_limit_override != 32'h0000_0000) ?
                               sq_limit_override :
                               rt.host_rt_mem_guard_span_limit(cfg.sq_base, sq_size_bytes);
        guard_cfg.cq_base    = cfg.cq_base;
        guard_cfg.cq_limit   = rt.host_rt_mem_guard_span_limit(cfg.cq_base, cq_size_bytes);
        guard_cfg.desc_base  = desc_base;
        guard_cfg.desc_limit = desc_limit;
        guard_cfg.src_base   = 32'h0000_0000;
        guard_cfg.src_limit  = 32'h0000_2000;
        guard_cfg.dst_base   = 32'h0000_0000;
        guard_cfg.dst_limit  = 32'h0000_2000;
    end
    endtask

    task automatic p27d_cleanup_after_guard_error(
        input ai_accel_event_driven_host_runtime_stress_helper rt,
        ref   ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input string label
    );
        ai_accel_event_driven_host_runtime_stress_helper::p26_lifecycle_snapshot_t snap;
    begin
        rt.host_rt_lifecycle_wait_idle(
            {label, " wait_idle"},
            ai_accel_event_driven_host_runtime_stress_helper::P26_DEFAULT_LIFECYCLE_TIMEOUT_CYCLES,
            1'b1
        );

        rt.host_rt_lifecycle_capture_snapshot(snap, {label, " snapshot"}, 1'b1);

        // No completion commit is expected for the P27D negative cases.
        // Align host-owned pointers back to the hardware-owned epoch.
        cfg.sq_head = snap.sq_head;
        cfg.sq_tail = snap.sq_head;
        cfg.cq_head = snap.cq_tail;
        cfg.cq_tail = snap.cq_tail;

        rt.host_rt_mem_guard_clear_for_reuse(1'b1, 1'b1, {label, " clear_for_reuse"});
        rt.host_rt_lifecycle_clear_queue_all_sticky(1'b1, {label, " queue_clear_all"});
        rt.host_rt_lifecycle_clear_lower_sticky({label, " lower_clear"});
        rt.host_rt_lifecycle_recycle_sq_slots(cfg, 0, cfg.sq_depth, {label, " recycle_sq"});
        rt.host_rt_lifecycle_recycle_cq_slots(cfg, 0, cfg.cq_depth, {label, " recycle_cq"});
        rt.program_queue(cfg);
        rt.host_rt_lifecycle_check_clean_idle({label, " clean_idle"}, 1'b0, 1'b1, 1'b0);

        `uvm_info("P27D_GUARD/CLEANUP_PASS",
            $sformatf("%s: guard error cleanup PASS SQ(h/t)=%0d/%0d CQ(h/t)=%0d/%0d",
                label,
                cfg.sq_head,
                cfg.sq_tail,
                cfg.cq_head,
                cfg.cq_tail),
            UVM_MEDIUM)
    end
    endtask

    task automatic p27d_run_guard_negative_case(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        ref    ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input  ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd,
        input  int unsigned sq_idx,
        input  logic [31:0] next_tail,
        input  logic [31:0] required_error_mask,
        input  logic [31:0] expected_domain,
        input  logic [7:0]  expected_detail,
        input  string       pass_id,
        input  string       label
    );
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t snap;
        logic [31:0] event_mask;
    begin
        event_mask = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_ERROR);

        // Negative guard cases intentionally wait on QUEUE_ERROR_EVENT.
        // Re-arm the event CSR with the error bit enabled before START_QUEUE;
        // the normal drained-session cleanup path leaves only completion /
        // drained / CQ-not-empty events armed, which would capture the pending
        // error event without asserting event_irq.
        rt.host_rt_lifecycle_rearm_events(
            event_mask,
            1'b1,
            32'h0000_0000,
            1'b1,
            {label, " event_rearm"}
        );

        rt.submit_command_and_doorbell(cfg, sq_idx, cmd, next_tail);
        rt.start_queue();

        rt.wait_for_progress_event(
            event_mask,
            snap,
            {label, " event wait"},
            ai_accel_event_driven_host_runtime_stress_helper::P27_DEFAULT_GUARD_TIMEOUT_CYCLES,
            1'b1
        );
        p25c_check_event_snapshot(label, snap, event_mask);

        if (!snap.queue_status[2]) begin
            `uvm_fatal("P27D_GUARD/NO_QUEUE_ERROR_STATUS",
                $sformatf("%s: expected QUEUE_STATUS.QUEUE_ERROR, status=0x%08h error=0x%08h",
                    label,
                    snap.queue_status,
                    snap.queue_error_status))
        end

        rt.host_rt_mem_guard_expect_error(
            required_error_mask,
            expected_domain,
            expected_detail,
            {label, " expected_error"}
        );

        `uvm_info(pass_id,
            $sformatf("%s: expected memory guard reject observed domain=%s detail=%s pending=0x%08h queue_error=0x%08h",
                label,
                rt.host_rt_mem_guard_domain_name(expected_domain),
                rt.host_rt_mem_guard_detail_name(expected_detail),
                snap.event_snap.pending,
                snap.queue_error_status),
            UVM_MEDIUM)

        p27d_cleanup_after_guard_error(rt, cfg, label);
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
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t baseline_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t bad_sq_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t bad_desc_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t recovery_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t addr_overflow_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t span_overflow_cmd;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t baseline_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t recovery_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p27_guard_cfg_t guard_cfg;

        logic [31:0] event_mask;
        logic [31:0] valid_desc_limit;
        logic [31:0] bad_sq_limit;
        logic [31:0] bad_desc_limit;
    begin
        phase.raise_objection(this);

        `uvm_info("P27D_GUARD/START",
            "Starting P27D SQ / descriptor memory guard range validation smoke test",
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

        prepare_dma_source_and_destination(a_flat, b_flat);

        p25c_program_descriptor_table(
            P27D_DESC_BASE0,
            P27D_DESC0_TAG0,
            P27D_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p25c_program_descriptor_table(
            P27D_DESC_BASE1,
            P27D_DESC1_TAG0,
            P27D_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p27d_make_cfg(rt, cfg);
        p27d_make_cmd(rt, baseline_cmd, 32'(P27D_DESC_BASE0), P27D_BASELINE_CMD_TAG);
        p27d_make_cmd(rt, bad_sq_cmd,   32'(P27D_DESC_BASE0), P27D_BAD_SQ_CMD_TAG);
        p27d_make_cmd(rt, bad_desc_cmd, 32'(P27D_DESC_BASE1), P27D_BAD_DESC_CMD_TAG);
        p27d_make_cmd(rt, recovery_cmd, 32'(P27D_DESC_BASE1), P27D_RECOVERY_CMD_TAG);
        p27d_make_cmd(rt, addr_overflow_cmd, 32'hFFFF_FF80, P27D_ADDR_OVERFLOW_CMD_TAG);
        p27d_make_cmd(rt, span_overflow_cmd, 32'(P27D_DESC_BASE0), P27D_SPAN_OVERFLOW_CMD_TAG);

        // Keep both commands architecturally valid so the memory guard,
        // rather than the SQ validation chain, owns the disposition.
        addr_overflow_cmd.desc_count  = 32'h0000_0002;
        addr_overflow_cmd.desc_stride = 32'h0000_0080;

        span_overflow_cmd.desc_count  = 32'h0000_0004;
        span_overflow_cmd.desc_stride = 32'h4000_0000;

        event_mask = rt.queue_completion_event_mask() |
                     rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);

        valid_desc_limit = rt.host_rt_mem_guard_span_limit(
            32'(P27D_DESC_BASE0),
            32'h0000_0200
        );
        bad_sq_limit = cfg.sq_base + 32'h0000_0020;
        bad_desc_limit = 32'(P27D_DESC_BASE0 + 32'h0000_0080);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_program_completion_wb();

        p27d_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'(P27D_DESC_BASE0), valid_desc_limit, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "P27D valid baseline guard cfg");
        rt.host_rt_mem_guard_check_clean("P27D initial guard clean", 1'b1, 1'b0);

        rt.host_rt_lifecycle_init_session(
            cfg,
            event_mask,
            1'b1,
            1'b1,
            "P27D initial lifecycle init"
        );

        p26d_run_drained_session_without_cleanup(
            rt,
            cfg,
            baseline_cmd,
            profile_item,
            P27D_DESC0_TAG0,
            P27D_DESC0_TAG1,
            0,
            "P27D valid baseline",
            baseline_snap
        );

        p26d_cleanup_drained_and_require_clean(
            rt,
            cfg,
            event_mask,
            "P27D valid baseline cleanup"
        );

        p26d_set_cfg_epoch(cfg, 1);
        rt.host_rt_mem_guard_check_clean("P27D after valid baseline guard clean", 1'b1, 1'b1);

        `uvm_info("P27D_GUARD/VALID_BASELINE_PASS",
            "P27D valid SQ/CQ/DESC guard baseline command completed normally",
            UVM_MEDIUM)

        // SQ range negative: the current SQ entry itself is outside the
        // allowed SQ guard span, so no SQ AXI read should be issued.
        p27d_make_guard_cfg(rt, cfg, bad_sq_limit, 32'(P27D_DESC_BASE0), valid_desc_limit, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "P27D SQ range reject guard cfg");

        p27d_run_guard_negative_case(
            rt,
            cfg,
            bad_sq_cmd,
            1,
            32'h0000_0002,
            32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_SQ_RANGE,
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_SQ,
            ai_accel_csr_access_helper::P27_DETAIL_SQ_RANGE,
            "P27D_GUARD/SQ_RANGE_REJECT_PASS",
            "P27D SQ range reject"
        );

        // Descriptor range negative: SQ is safe, but the fetched command's
        // descriptor table base/count/stride span is outside DESC range, so
        // the queue must reject before launching P17 descriptor fetch.
        p27d_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'(P27D_DESC_BASE0), bad_desc_limit, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "P27D descriptor range reject guard cfg");

        p27d_run_guard_negative_case(
            rt,
            cfg,
            bad_desc_cmd,
            1,
            32'h0000_0002,
            32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_DESC_RANGE,
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_DESC,
            ai_accel_csr_access_helper::P27_DETAIL_DESC_RANGE,
            "P27D_GUARD/DESC_RANGE_REJECT_PASS",
            "P27D descriptor range reject"
        );

        // Address/end-address overflow: the descriptor base is aligned
        // and the command validates, but base + span exceeds 32 bits.
        p27d_make_guard_cfg(
            rt,
            cfg,
            32'h0000_0000,
            32'hFFFF_F000,
            32'hFFFF_FFFF,
            guard_cfg
        );
        rt.host_rt_mem_guard_program_regions(
            guard_cfg,
            "P27D descriptor address overflow guard cfg"
        );

        p27d_run_guard_negative_case(
            rt,
            cfg,
            addr_overflow_cmd,
            1,
            32'h0000_0002,
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_DESC_RANGE) |
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_ADDR_OVERFLOW),
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_DESC,
            ai_accel_csr_access_helper::P27_DETAIL_ADDR_OVERFLOW,
            "CODE_COV_C1_2G7_A2/DESC_ADDR_OVERFLOW_PASS",
            "P27D descriptor address overflow"
        );

        // 4 * 0x40000000 overflows the 32-bit descriptor span.  The lower
        // word is zero, and the explicit 64-bit overflow override must
        // classify the failure as ADDR_OVERFLOW rather than SPAN_CONFIG.
        p27d_make_guard_cfg(
            rt,
            cfg,
            32'h0000_0000,
            32'h0000_0000,
            32'hFFFF_FFFF,
            guard_cfg
        );
        rt.host_rt_mem_guard_program_regions(
            guard_cfg,
            "P27D descriptor span multiplication overflow guard cfg"
        );

        p27d_run_guard_negative_case(
            rt,
            cfg,
            span_overflow_cmd,
            1,
            32'h0000_0002,
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_DESC_RANGE) |
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_ADDR_OVERFLOW),
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_DESC,
            ai_accel_csr_access_helper::P27_DETAIL_ADDR_OVERFLOW,
            "CODE_COV_C1_2G7_A2/DESC_SPAN_OVERFLOW_PASS",
            "P27D descriptor span multiplication overflow"
        );

        `uvm_info("CODE_COV_C1_2G7_A2/GUARD_OVERFLOW_MATRIX_PASS",
            "Descriptor address-end and 64-bit span multiplication overflow vectors PASS",
            UVM_MEDIUM)

        // Known-good recovery after the range and overflow guard rejects.
        p27d_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'(P27D_DESC_BASE0), valid_desc_limit, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "P27D recovery valid guard cfg");
        rt.host_rt_mem_guard_check_clean("P27D recovery guard clean", 1'b1, 1'b1);

        rt.host_rt_lifecycle_init_session(
            cfg,
            event_mask,
            1'b1,
            1'b1,
            "P27D recovery lifecycle init"
        );

        p26d_run_drained_session_without_cleanup(
            rt,
            cfg,
            recovery_cmd,
            profile_item,
            P27D_DESC1_TAG0,
            P27D_DESC1_TAG1,
            1,
            "P27D recovery command",
            recovery_snap
        );

        p26d_cleanup_drained_and_require_clean(
            rt,
            cfg,
            event_mask,
            "P27D recovery final cleanup"
        );

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        rt.host_rt_mem_guard_check_clean("P27D final guard clean", 1'b1, 1'b1);
        rt.host_rt_lifecycle_check_clean_idle("P27D final lifecycle clean idle", 1'b0, 1'b1, 1'b0);

        `uvm_info("P27D_GUARD/RECOVERY_PASS",
            "P27D known-good command completed after SQ, descriptor-range, and descriptor-overflow guard rejects",
            UVM_MEDIUM)

        `uvm_info("P27D_GUARD/PASS",
            $sformatf("P27D SQ / descriptor memory guard validation PASS: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
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
