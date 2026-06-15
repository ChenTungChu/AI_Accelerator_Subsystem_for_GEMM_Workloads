// File: tb/uvm/test/ai_accel_subsys_csr_event_driven_multi_session_stress_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_EVENT_DRIVEN_MULTI_SESSION_STRESS_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_EVENT_DRIVEN_MULTI_SESSION_STRESS_TEST_SV

// ============================================================
// P25C event-driven multi-session runtime stress smoke
//
// Scope:
//   - Reuses the validated P23 event-driven host runtime model.
//   - Uses the P25B stress helper extension for reusable snapshots,
//     runtime re-arm, event cleanup, pointer checks, and CQ consume.
//   - Runs several back-to-back queue runtime sessions without reset:
//       session0: one command, single-command service
//       session1: two commands, RUN_UNTIL_EMPTY drain
//       session2: one command, single-command service after re-arm
//   - Validates that queue sticky state, event pending bits, CQ memory,
//     SQ/CQ pointers, and DMA result comparison remain clean across
//     repeated event-driven sessions.
//
// This is UVM/helper-only validation.  It does not add RTL, CSR map
// changes, SQ/CQ format changes, descriptor-format changes, completion
// record changes, event bits, standalone tops, or datapath changes.
// ============================================================

class ai_accel_subsys_csr_event_driven_multi_session_stress_test
    extends ai_accel_subsys_csr_event_driven_multi_command_queue_drain_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_event_driven_multi_session_stress_test)

    localparam int unsigned P25C_SQ_BASE     = 32'h0000_0D00;
    localparam int unsigned P25C_CQ_BASE     = 32'h0000_0E00;
    localparam int unsigned P25C_QUEUE_DEPTH = 4;

    localparam int unsigned P25C_DESC_BASE0  = 32'h0000_0300;
    localparam int unsigned P25C_DESC_BASE1  = 32'h0000_0400;
    localparam int unsigned P25C_DESC_BASE2  = 32'h0000_0500;
    localparam int unsigned P25C_DESC_BASE3  = 32'h0000_0600;
    localparam int unsigned P25C_DESC_STRIDE = 32'h0000_0080;

    localparam logic [31:0] P25C_CMD0_TAG    = 32'hD25C_0000;
    localparam logic [31:0] P25C_CMD1_TAG    = 32'hD25C_0001;
    localparam logic [31:0] P25C_CMD2_TAG    = 32'hD25C_0002;
    localparam logic [31:0] P25C_CMD3_TAG    = 32'hD25C_0003;

    localparam logic [31:0] P25C_DESC0_TAG0  = 32'hD25C_1000;
    localparam logic [31:0] P25C_DESC0_TAG1  = 32'hD25C_1001;
    localparam logic [31:0] P25C_DESC1_TAG0  = 32'hD25C_2000;
    localparam logic [31:0] P25C_DESC1_TAG1  = 32'hD25C_2001;
    localparam logic [31:0] P25C_DESC2_TAG0  = 32'hD25C_3000;
    localparam logic [31:0] P25C_DESC2_TAG1  = 32'hD25C_3001;
    localparam logic [31:0] P25C_DESC3_TAG0  = 32'hD25C_4000;
    localparam logic [31:0] P25C_DESC3_TAG1  = 32'hD25C_4001;

    function new(string name = "ai_accel_subsys_csr_event_driven_multi_session_stress_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p25c_program_descriptor_table(
        input int unsigned             desc_base,
        input logic [31:0]             first_tag,
        input logic [31:0]             second_tag,
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
    begin
        program_memory_descriptor(
            desc_base + (0 * P25C_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            first_tag
        );

        program_memory_descriptor(
            desc_base + (1 * P25C_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            second_tag
        );
    end
    endtask

    task automatic p25c_make_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input  bit run_until_empty
    );
    begin
        rt.make_default_queue_cfg(
            cfg,
            32'(P25C_SQ_BASE),
            32'(P25C_CQ_BASE),
            32'(P25C_QUEUE_DEPTH),
            run_until_empty
        );
    end
    endtask

    task automatic p25c_make_cmd(
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
            32'(P25C_DESC_STRIDE),
            user_tag,
            1'b1,
            1'b0
        );

        // P25C is a normal-progress multi-session stress test.  Timeout
        // recovery is covered by P24F and mixed timeout stress is reserved
        // for P25E.
        cmd.timeout_cycles = 32'h0000_0000;
    end
    endtask

    task automatic p25c_check_event_snapshot(
        input string label,
        input ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t snap,
        input logic [31:0] required_mask
    );
    begin
        if ((snap.event_snap.pending & required_mask) !== required_mask) begin
            `uvm_fatal("P25C_HOST_RT/EVENT_MISSING",
                $sformatf("%s: required event bits missing pending=0x%08h required=0x%08h",
                    label,
                    snap.event_snap.pending,
                    required_mask))
        end

        if ((snap.event_snap.status & 32'h0000_0007) == 32'h0000_0000) begin
            `uvm_fatal("P25C_HOST_RT/EVENT_STATUS",
                $sformatf("%s: expected pending/eligible/IRQ event status before ack, status=0x%08h",
                    label,
                    snap.event_snap.status))
        end

        if (snap.event_snap.event_count == 32'h0000_0000) begin
            `uvm_fatal("P25C_HOST_RT/EVENT_COUNT",
                $sformatf("%s: expected EVENT_COUNT to increment", label))
        end

        if (snap.event_snap.irq_count == 32'h0000_0000) begin
            `uvm_fatal("P25C_HOST_RT/IRQ_COUNT",
                $sformatf("%s: expected IRQ_COUNT to increment for enabled events", label))
        end

        `uvm_info("P25C_HOST_RT/EVENT",
            $sformatf("%s: event snapshot PASS pending=0x%08h required=0x%08h status=0x%08h last_cause=0x%08h event_count=%0d irq_count=%0d snapshot0=0x%08h snapshot1=0x%08h",
                label,
                snap.event_snap.pending,
                required_mask,
                snap.event_snap.status,
                snap.event_snap.last_cause,
                snap.event_snap.event_count,
                snap.event_snap.irq_count,
                snap.event_snap.snapshot0,
                snap.event_snap.snapshot1),
            UVM_MEDIUM)
    end
    endtask

    task automatic p25c_single_command_session(
        input ai_accel_event_driven_host_runtime_stress_helper rt,
        input ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd,
        input ai_accel_subsys_seq_item profile_item,
        input logic [31:0] first_desc_tag,
        input logic [31:0] last_desc_tag,
        input string label
    );
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t snap;
        logic [31:0] event_mask;
    begin
        event_mask = rt.queue_completion_event_mask();

        rt.clear_and_rearm_runtime(cfg, event_mask, 1'b1, label);
        csr_check_recipe_idle_ready($sformatf("%s before START_QUEUE", label));

        rt.submit_command_and_doorbell(cfg, 0, cmd, 32'h0000_0001);
        rt.start_queue();

        rt.wait_for_progress_event(event_mask, snap, $sformatf("%s event wait", label), done_timeout_cycles * 8, 1'b1);
        p25c_check_event_snapshot(label, snap, event_mask);

        rt.wait_and_check_cq_record(
            cfg,
            0,
            first_desc_tag,
            last_desc_tag,
            rec,
            $sformatf("%s CQ[0]", label),
            done_timeout_cycles * 4
        );
        check_p23d_cq_record(0, rec, profile_item, first_desc_tag, last_desc_tag);

        rt.require_queue_pointers($sformatf("%s pointers before consume", label),
            32'h0000_0001,
            32'h0000_0000,
            32'h0000_0001,
            32'h0000_0001);

        rt.consume_cq_entry(cfg, 0, 1'b1);
        rt.event_ack_and_require_clean(snap, $sformatf("%s event cleanup", label));
        rt.wait_queue_reusable($sformatf("%s reusable", label));
        rt.require_no_queue_error($sformatf("%s no queue error", label));
        rt.require_queue_pointers($sformatf("%s pointers after consume", label),
            32'h0000_0001,
            32'h0000_0001,
            32'h0000_0001,
            32'h0000_0000);

        `uvm_info("P25C_HOST_RT/SESSION_PASS",
            $sformatf("%s: single-command session PASS cmd_tag=0x%08h desc_tags=0x%08h/0x%08h",
                label,
                cmd.user_tag,
                first_desc_tag,
                last_desc_tag),
            UVM_MEDIUM)
    end
    endtask

    task automatic p25c_two_command_drain_session(
        input ai_accel_event_driven_host_runtime_stress_helper rt,
        input ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd0,
        input ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd1,
        input ai_accel_subsys_seq_item profile_item,
        input logic [31:0] first_desc0_tag,
        input logic [31:0] last_desc0_tag,
        input logic [31:0] first_desc1_tag,
        input logic [31:0] last_desc1_tag,
        input string label
    );
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec0;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec1;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t snap;
        logic [31:0] event_mask;
    begin
        event_mask = rt.queue_completion_event_mask() |
                     rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);

        rt.clear_and_rearm_runtime(cfg, event_mask, 1'b1, label);
        csr_check_recipe_idle_ready($sformatf("%s before START_QUEUE", label));

        rt.write_sq_command(cfg, 0, cmd0, 1'b1);
        rt.write_sq_command(cfg, 1, cmd1, 1'b1);
        rt.ring_sq_tail(32'h0000_0002);
        rt.start_queue();

        rt.wait_for_progress_event(event_mask, snap, $sformatf("%s event wait", label), done_timeout_cycles * 12, 1'b1);
        p25c_check_event_snapshot(label, snap, event_mask);

        rt.wait_and_check_cq_record(
            cfg,
            0,
            first_desc0_tag,
            last_desc0_tag,
            rec0,
            $sformatf("%s CQ[0]", label),
            done_timeout_cycles * 4
        );
        rt.wait_and_check_cq_record(
            cfg,
            1,
            first_desc1_tag,
            last_desc1_tag,
            rec1,
            $sformatf("%s CQ[1]", label),
            done_timeout_cycles * 4
        );

        check_p23d_cq_record(0, rec0, profile_item, first_desc0_tag, last_desc0_tag);
        check_p23d_cq_record(1, rec1, profile_item, first_desc1_tag, last_desc1_tag);

        rt.require_queue_pointers($sformatf("%s pointers before consume", label),
            32'h0000_0002,
            32'h0000_0000,
            32'h0000_0002,
            32'h0000_0002);

        rt.consume_cq_range(cfg, 0, 2, 1'b1, $sformatf("%s consume CQ[0:1]", label));
        rt.event_ack_and_require_clean(snap, $sformatf("%s event cleanup", label));
        rt.wait_queue_reusable($sformatf("%s reusable", label));
        rt.require_no_queue_error($sformatf("%s no queue error", label));
        rt.require_queue_pointers($sformatf("%s pointers after consume", label),
            32'h0000_0002,
            32'h0000_0002,
            32'h0000_0002,
            32'h0000_0000);

        `uvm_info("P25C_HOST_RT/SESSION_PASS",
            $sformatf("%s: two-command drain session PASS cmd_tags=0x%08h/0x%08h desc0=0x%08h/0x%08h desc1=0x%08h/0x%08h",
                label,
                cmd0.user_tag,
                cmd1.user_tag,
                first_desc0_tag,
                last_desc0_tag,
                first_desc1_tag,
                last_desc1_tag),
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
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg_single;
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg_drain;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd0;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd1;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd2;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd3;
    begin
        phase.raise_objection(this);

        `uvm_info("P25C_HOST_RT/START",
            "Starting P25C event-driven multi-session runtime stress smoke test",
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
            `uvm_fatal("P25C_HOST_RT/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        // Write descriptor tables after source/destination preparation so
        // descriptor memory is not overwritten by inherited source setup.
        p25c_program_descriptor_table(
            P25C_DESC_BASE0,
            P25C_DESC0_TAG0,
            P25C_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p25c_program_descriptor_table(
            P25C_DESC_BASE1,
            P25C_DESC1_TAG0,
            P25C_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p25c_program_descriptor_table(
            P25C_DESC_BASE2,
            P25C_DESC2_TAG0,
            P25C_DESC2_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p25c_program_descriptor_table(
            P25C_DESC_BASE3,
            P25C_DESC3_TAG0,
            P25C_DESC3_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p25c_make_cfg(rt, cfg_single, 1'b0);
        p25c_make_cfg(rt, cfg_drain,  1'b1);

        p25c_make_cmd(rt, cmd0, 32'(P25C_DESC_BASE0), P25C_CMD0_TAG);
        p25c_make_cmd(rt, cmd1, 32'(P25C_DESC_BASE1), P25C_CMD1_TAG);
        p25c_make_cmd(rt, cmd2, 32'(P25C_DESC_BASE2), P25C_CMD2_TAG);
        p25c_make_cmd(rt, cmd3, 32'(P25C_DESC_BASE3), P25C_CMD3_TAG);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_program_completion_wb();

        rt.require_event_clean("P25C initial event state");
        rt.wait_queue_reusable("P25C initial reusable state");

        p25c_single_command_session(
            rt,
            cfg_single,
            cmd0,
            profile_item,
            P25C_DESC0_TAG0,
            P25C_DESC0_TAG1,
            "P25C session0 single-command"
        );

        rt.deterministic_gap(7, "P25C gap after session0");

        p25c_two_command_drain_session(
            rt,
            cfg_drain,
            cmd1,
            cmd2,
            profile_item,
            P25C_DESC1_TAG0,
            P25C_DESC1_TAG1,
            P25C_DESC2_TAG0,
            P25C_DESC2_TAG1,
            "P25C session1 two-command drain"
        );

        rt.deterministic_gap(11, "P25C gap after session1");

        p25c_single_command_session(
            rt,
            cfg_single,
            cmd3,
            profile_item,
            P25C_DESC3_TAG0,
            P25C_DESC3_TAG1,
            "P25C session2 single-command re-arm"
        );

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P25C_HOST_RT/PASS",
            $sformatf("P25C multi-session runtime stress PASS: CASE_ID=%0d sessions=3 commands=4 A_bytes=%0d B_bytes=%0d C_words=%0d",
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
