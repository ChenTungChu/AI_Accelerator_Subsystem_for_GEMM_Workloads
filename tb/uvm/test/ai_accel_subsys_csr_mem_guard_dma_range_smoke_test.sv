// File: tb/uvm/test/ai_accel_subsys_csr_mem_guard_dma_range_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_MEM_GUARD_DMA_RANGE_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_MEM_GUARD_DMA_RANGE_SMOKE_TEST_SV

// ============================================================
// P27E memory guard DMA source / destination range validation smoke
//
// Scope:
//   - Extends the P27D SQ/DESC guard validation to descriptor-payload
//     source and destination memory ranges.
//   - Runs one valid SQ + descriptor + source + destination guarded
//     command to prove that enabled SRC/DST checks preserve the normal
//     queue path.
//   - Shrinks the source-memory guard range so descriptor payload
//     validation rejects before any lower-level preload read can launch.
//   - Restores source range and shrinks the destination-memory guard
//     range so descriptor payload validation rejects before any lower-level
//     DMA store write can launch.
//   - Clears guard / queue / event sticky state with the P26 lifecycle
//     cleanup policy and proves a known-good recovery command completes.
//
// P27E does not change SQ/CQ entry format, descriptor format,
// completion record format, event bit allocation, BRAM, GEMM, DMA,
// AXI-Stream, or Direct Stream datapath behavior.
// ============================================================

class ai_accel_subsys_csr_mem_guard_dma_range_smoke_test
    extends ai_accel_subsys_csr_queue_lifecycle_drained_reinit_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_mem_guard_dma_range_smoke_test)

    localparam int unsigned P27E_SQ_BASE     = 32'h0000_0D00;
    localparam int unsigned P27E_CQ_BASE     = 32'h0000_0E00;
    localparam int unsigned P27E_QUEUE_DEPTH = 4;

    localparam int unsigned P27E_DESC_BASE0  = 32'h0000_0300;
    localparam int unsigned P27E_DESC_BASE1  = 32'h0000_0400;
    localparam int unsigned P27E_DESC_STRIDE = 32'h0000_0080;

    localparam logic [31:0] P27E_BASELINE_CMD_TAG = 32'hD27E_0000;
    localparam logic [31:0] P27E_BAD_SRC_CMD_TAG  = 32'hD27E_0001;
    localparam logic [31:0] P27E_BAD_DST_CMD_TAG  = 32'hD27E_0002;
    localparam logic [31:0] P27E_RECOVERY_CMD_TAG = 32'hD27E_0003;

    // CODE-COV-C1.2-G7-G3 targeted payload-guard commands.
    // These remain legal queue commands; only the P27 guard configuration
    // or the memory-backed descriptor payload address is changed.
    localparam logic [31:0] G7_G3_BAD_B_SRC_CMD_TAG = 32'hD27E_0010;
    localparam logic [31:0] G7_G3_SPAN_CFG_CMD_TAG  = 32'hD27E_0011;
    localparam logic [31:0] G7_G3_OVERFLOW_CMD_TAG  = 32'hD27E_0012;

    localparam int unsigned G7_G3_DESC_WORD_A_SRC_BASE = 7;

    localparam logic [31:0] P27E_DESC0_TAG0 = 32'hD27E_1000;
    localparam logic [31:0] P27E_DESC0_TAG1 = 32'hD27E_1001;
    localparam logic [31:0] P27E_DESC1_TAG0 = 32'hD27E_2000;
    localparam logic [31:0] P27E_DESC1_TAG1 = 32'hD27E_2001;

    function new(string name = "ai_accel_subsys_csr_mem_guard_dma_range_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p27e_make_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg
    );
    begin
        rt.make_default_queue_cfg(
            cfg,
            32'(P27E_SQ_BASE),
            32'(P27E_CQ_BASE),
            32'(P27E_QUEUE_DEPTH),
            1'b1
        );
    end
    endtask

    task automatic p27e_make_cmd(
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
            32'(P27E_DESC_STRIDE),
            user_tag,
            1'b1,
            1'b0
        );
        cmd.timeout_cycles = 32'h0000_0000;
    end
    endtask

    task automatic p27e_make_guard_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        input  ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input  logic [31:0] src_limit_override,
        input  logic [31:0] dst_limit_override,
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
            1'b1, // source check
            1'b1, // destination check
            1'b1  // write CQ error if safe
        );

        sq_size_bytes = cfg.sq_depth * cfg.sq_stride;
        cq_size_bytes = cfg.cq_depth * cfg.cq_stride;

        guard_cfg.control    = control;
        guard_cfg.sq_base    = cfg.sq_base;
        guard_cfg.sq_limit   = rt.host_rt_mem_guard_span_limit(cfg.sq_base, sq_size_bytes);
        guard_cfg.cq_base    = cfg.cq_base;
        guard_cfg.cq_limit   = rt.host_rt_mem_guard_span_limit(cfg.cq_base, cq_size_bytes);
        guard_cfg.desc_base  = 32'(P27E_DESC_BASE0);
        guard_cfg.desc_limit = rt.host_rt_mem_guard_span_limit(32'(P27E_DESC_BASE0), 32'h0000_0200);
        guard_cfg.src_base   = 32'h0000_0000;
        guard_cfg.src_limit  = (src_limit_override != 32'h0000_0000) ?
                               src_limit_override :
                               32'h0000_2000;
        guard_cfg.dst_base   = 32'h0000_0000;
        guard_cfg.dst_limit  = (dst_limit_override != 32'h0000_0000) ?
                               dst_limit_override :
                               32'h0000_2000;
    end
    endtask

    task automatic p27e_cleanup_after_guard_error(
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

        // No completion commit is expected for the P27E negative cases.
        // Align host-owned pointers back to the hardware-owned monotonic epoch.
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

        `uvm_info("P27E_GUARD/CLEANUP_PASS",
            $sformatf("%s: guard error cleanup PASS SQ(h/t)=%0d/%0d CQ(h/t)=%0d/%0d",
                label,
                cfg.sq_head,
                cfg.sq_tail,
                cfg.cq_head,
                cfg.cq_tail),
            UVM_MEDIUM)
    end
    endtask

    task automatic p27e_run_guard_negative_case(
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
            `uvm_fatal("P27E_GUARD/NO_QUEUE_ERROR_STATUS",
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

        p27e_cleanup_after_guard_error(rt, cfg, label);
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
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t bad_src_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t bad_dst_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t recovery_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t g7_g3_bad_b_src_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t g7_g3_span_cfg_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t g7_g3_overflow_cmd;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t baseline_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t recovery_snap;
        ai_accel_event_driven_host_runtime_stress_helper::p27_guard_cfg_t guard_cfg;

        logic [31:0] event_mask;
        logic [31:0] bad_src_limit;
        logic [31:0] bad_dst_limit;
        logic [31:0] g7_g3_guard_control_readback;
    begin
        phase.raise_objection(this);

        `uvm_info("P27E_GUARD/START",
            "Starting P27E DMA source / destination memory guard range validation smoke test",
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
            P27E_DESC_BASE0,
            P27E_DESC0_TAG0,
            P27E_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p25c_program_descriptor_table(
            P27E_DESC_BASE1,
            P27E_DESC1_TAG0,
            P27E_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p27e_make_cfg(rt, cfg);
        p27e_make_cmd(rt, baseline_cmd,       32'(P27E_DESC_BASE0), P27E_BASELINE_CMD_TAG);
        p27e_make_cmd(rt, bad_src_cmd,        32'(P27E_DESC_BASE0), P27E_BAD_SRC_CMD_TAG);
        p27e_make_cmd(rt, bad_dst_cmd,        32'(P27E_DESC_BASE1), P27E_BAD_DST_CMD_TAG);
        p27e_make_cmd(rt, recovery_cmd,       32'(P27E_DESC_BASE1), P27E_RECOVERY_CMD_TAG);
        p27e_make_cmd(rt, g7_g3_bad_b_src_cmd,32'(P27E_DESC_BASE0), G7_G3_BAD_B_SRC_CMD_TAG);
        p27e_make_cmd(rt, g7_g3_span_cfg_cmd, 32'(P27E_DESC_BASE0), G7_G3_SPAN_CFG_CMD_TAG);
        p27e_make_cmd(rt, g7_g3_overflow_cmd, 32'(P27E_DESC_BASE0), G7_G3_OVERFLOW_CMD_TAG);

        event_mask = rt.queue_completion_event_mask() |
                     rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);

        // These intentionally cut the first descriptor payload range short.
        // The source limit blocks A/B preload source access.  The destination
        // limit blocks the DMA-store destination range used by slot1.
        bad_src_limit = 32'h0000_0004;
        bad_dst_limit = 32'h0000_0020;

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_program_completion_wb();

        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'h0000_0000, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "P27E valid baseline guard cfg");
        rt.host_rt_mem_guard_check_clean("P27E initial guard clean", 1'b1, 1'b0);

        rt.host_rt_lifecycle_init_session(
            cfg,
            event_mask,
            1'b1,
            1'b1,
            "P27E initial lifecycle init"
        );

        p26d_run_drained_session_without_cleanup(
            rt,
            cfg,
            baseline_cmd,
            profile_item,
            P27E_DESC0_TAG0,
            P27E_DESC0_TAG1,
            0,
            "P27E valid baseline",
            baseline_snap
        );

        p26d_cleanup_drained_and_require_clean(
            rt,
            cfg,
            event_mask,
            "P27E valid baseline cleanup"
        );

        p26d_set_cfg_epoch(cfg, 1);
        rt.host_rt_mem_guard_check_clean("P27E after valid baseline guard clean", 1'b1, 1'b1);

        `uvm_info("P27E_GUARD/VALID_BASELINE_PASS",
            "P27E valid SQ/CQ/DESC/SRC/DST guard baseline command completed normally",
            UVM_MEDIUM)

        // Source range negative: SQ and descriptor table are safe, but the
        // fetched descriptor payload source span is outside SRC range.  The
        // wrapper must reject before launching any lower-level preload read.
        p27e_make_guard_cfg(rt, cfg, bad_src_limit, 32'h0000_0000, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "P27E source range reject guard cfg");

        p27e_run_guard_negative_case(
            rt,
            cfg,
            bad_src_cmd,
            1,
            32'h0000_0002,
            32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_SRC_RANGE,
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_SRC,
            ai_accel_csr_access_helper::P27_DETAIL_SRC_RANGE,
            "P27E_GUARD/SRC_RANGE_REJECT_PASS",
            "P27E source range reject"
        );

        // Destination range negative: source range is valid again, but the
        // fetched descriptor payload store destination span is outside DST
        // range.  The wrapper must reject before any lower-level DMA store
        // write can launch.
        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, bad_dst_limit, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "P27E destination range reject guard cfg");

        p27e_run_guard_negative_case(
            rt,
            cfg,
            bad_dst_cmd,
            1,
            32'h0000_0002,
            32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_DST_RANGE,
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_DST,
            ai_accel_csr_access_helper::P27_DETAIL_DST_RANGE,
            "P27E_GUARD/DST_RANGE_REJECT_PASS",
            "P27E destination range reject"
        );

        // ------------------------------------------------------------
        // CODE-COV-C1.2-G7-G3-A
        //
        // 1) Keep slot0 A inside the source range while placing slot0 B
        //    exactly at the exclusive limit.  This reaches the genuine B
        //    source materialization path without altering RTL or forcing
        //    internal state.
        // ------------------------------------------------------------
        p27e_make_guard_cfg(rt, cfg, 32'h0000_0100, 32'h0000_0000, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "G7-G3 B-source range guard cfg");

        p27e_run_guard_negative_case(
            rt,
            cfg,
            g7_g3_bad_b_src_cmd,
            1,
            32'h0000_0002,
            32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_SRC_RANGE,
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_SRC,
            ai_accel_csr_access_helper::P27_DETAIL_SRC_RANGE,
            "CODE_COV_C1_2G7_G3/B_SRC_PASS",
            "G7-G3 B-source range reject"
        );

        // 2) A non-empty payload with BASE == LIMIT is a legal host
        //    misconfiguration and must report SPAN_CONFIG + BASE_LIMIT.
        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'h0000_0000, guard_cfg);
        guard_cfg.src_base  = 32'h0000_1000;
        guard_cfg.src_limit = 32'h0000_1000;
        rt.host_rt_mem_guard_program_regions(guard_cfg, "G7-G3 source BASE>=LIMIT guard cfg");

        p27e_run_guard_negative_case(
            rt,
            cfg,
            g7_g3_span_cfg_cmd,
            1,
            32'h0000_0002,
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_SRC_RANGE) |
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_BASE_LIMIT),
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_SRC,
            ai_accel_csr_access_helper::P27_DETAIL_SPAN_CONFIG,
            "CODE_COV_C1_2G7_G3/SPAN_CONFIG_PASS",
            "G7-G3 source span-config reject"
        );

        // 3) Move slot0 A to the top of the 32-bit address space.  The
        //    non-zero A transfer then crosses the 32-bit boundary and must
        //    report ADDR_OVERFLOW.  Restore the descriptor immediately after
        //    the negative case so later recovery remains the canonical table.
        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_G3_DESC_WORD_A_SRC_BASE,
            32'hFFFF_FFFC
        );

        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'h0000_0000, guard_cfg);
        rt.host_rt_mem_guard_program_regions(guard_cfg, "G7-G3 source overflow guard cfg");

        p27e_run_guard_negative_case(
            rt,
            cfg,
            g7_g3_overflow_cmd,
            1,
            32'h0000_0002,
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_SRC_RANGE) |
            (32'h0000_0001 << ai_accel_csr_access_helper::MEM_GUARD_ERR_ADDR_OVERFLOW),
            ai_accel_csr_access_helper::P27_GUARD_DOMAIN_SRC,
            ai_accel_csr_access_helper::P27_DETAIL_ADDR_OVERFLOW,
            "CODE_COV_C1_2G7_G3/OVERFLOW_PASS",
            "G7-G3 source address-overflow reject"
        );

        write_desc_word(
            P27E_DESC_BASE0 + (0 * P27E_DESC_STRIDE),
            G7_G3_DESC_WORD_A_SRC_BASE,
            32'h0000_0000
        );

        // Known-good recovery after the original and G7-G3 guard rejects.
        p27e_make_guard_cfg(rt, cfg, 32'h0000_0000, 32'h0000_0000, guard_cfg);
        guard_cfg.control = rt.host_rt_mem_guard_control_value(
            1'b1, // guard_enable
            1'b1, // strict_reject_enable
            1'b1, // SQ check
            1'b1, // CQ check
            1'b1, // descriptor check
            1'b1, // source check
            1'b0, // destination check: G7-G3 SRC-only success target
            1'b1  // write CQ error if safe
        );
        rt.host_rt_mem_guard_program_regions(guard_cfg, "P27E recovery SRC-only guard cfg");
        rt.host_rt_mem_guard_check_clean("P27E recovery guard clean", 1'b1, 1'b1);

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_MEM_GUARD_CONTROL,
            g7_g3_guard_control_readback
        );
        if (g7_g3_guard_control_readback !== guard_cfg.control) begin
            `uvm_fatal("CODE_COV_C1_2G7_G3/SRC_ONLY_CONTROL",
                $sformatf("SRC-only guard control readback mismatch: expected=0x%08h actual=0x%08h",
                    guard_cfg.control,
                    g7_g3_guard_control_readback))
        end

        rt.host_rt_lifecycle_init_session(
            cfg,
            event_mask,
            1'b1,
            1'b1,
            "P27E recovery lifecycle init"
        );

        p26d_run_drained_session_without_cleanup(
            rt,
            cfg,
            recovery_cmd,
            profile_item,
            P27E_DESC1_TAG0,
            P27E_DESC1_TAG1,
            1,
            "P27E recovery command",
            recovery_snap
        );

        p26d_cleanup_drained_and_require_clean(
            rt,
            cfg,
            event_mask,
            "P27E recovery final cleanup"
        );

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("CODE_COV_C1_2G7_G3/SRC_ONLY_PASS",
            $sformatf("SRC-only guarded recovery completed with DST check disabled: control=0x%08h",
                g7_g3_guard_control_readback),
            UVM_MEDIUM)

        rt.host_rt_mem_guard_check_clean("P27E final guard clean", 1'b1, 1'b1);
        rt.host_rt_lifecycle_check_clean_idle("P27E final lifecycle clean idle", 1'b0, 1'b1, 1'b0);

        `uvm_info("P27E_GUARD/RECOVERY_PASS",
            "P27E known-good command completed after source/destination and G7-G3 guard rejects",
            UVM_MEDIUM)

        `uvm_info("CODE_COV_C1_2G7_G3/PAYLOAD_GUARD_SUITE_PASS",
            "G7-G3 payload guard targeted suite completed: B-source, span-config, overflow, and SRC-only success",
            UVM_MEDIUM)

        `uvm_info("P27E_GUARD/PASS",
            $sformatf("P27E DMA source / destination memory guard validation PASS: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
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
