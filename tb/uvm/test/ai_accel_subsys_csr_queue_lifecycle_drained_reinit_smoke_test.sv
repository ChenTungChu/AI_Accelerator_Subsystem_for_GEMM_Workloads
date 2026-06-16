// File: tb/uvm/test/ai_accel_subsys_csr_queue_lifecycle_drained_reinit_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_LIFECYCLE_DRAINED_REINIT_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_LIFECYCLE_DRAINED_REINIT_SMOKE_TEST_SV

// ============================================================
// P26D queue lifecycle drained-session cleanup + reinit smoke
//
// Scope:
//   - Reuses the P26C lifecycle helper extension.
//   - Runs a normal RUN_UNTIL_EMPTY queue session to drained.
//   - Leaves the produced CQ record and event pending bits for the
//     lifecycle helper to consume / clear / recycle.
//   - Uses pointer-preserving lifecycle cleanup for the first P26D
//     smoke because the current RTL owns SQ_HEAD/CQ_TAIL as monotonic
//     counters and does not require them to return to zero between
//     clean drained sessions.
//   - Reinitializes the same SQ/CQ context at the next monotonic
//     pointer epoch and runs a second valid command without a full reset.
//
// This is UVM/helper-only validation.  It does not add RTL, CSR map
// changes, SQ/CQ format changes, descriptor-format changes, completion
// record changes, event bits, standalone tops, or datapath changes.
// ============================================================

class ai_accel_subsys_csr_queue_lifecycle_drained_reinit_smoke_test
    extends ai_accel_subsys_csr_event_driven_multi_session_stress_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_lifecycle_drained_reinit_smoke_test)

    localparam int unsigned P26D_SQ_BASE     = 32'h0000_0D00;
    localparam int unsigned P26D_CQ_BASE     = 32'h0000_0E00;
    localparam int unsigned P26D_QUEUE_DEPTH = 4;

    localparam int unsigned P26D_DESC_BASE0  = 32'h0000_0300;
    localparam int unsigned P26D_DESC_BASE1  = 32'h0000_0400;
    localparam int unsigned P26D_DESC_STRIDE = 32'h0000_0080;

    localparam logic [31:0] P26D_CMD0_TAG    = 32'hD26D_0000;
    localparam logic [31:0] P26D_CMD1_TAG    = 32'hD26D_0001;

    localparam logic [31:0] P26D_DESC0_TAG0  = 32'hD26D_1000;
    localparam logic [31:0] P26D_DESC0_TAG1  = 32'hD26D_1001;
    localparam logic [31:0] P26D_DESC1_TAG0  = 32'hD26D_2000;
    localparam logic [31:0] P26D_DESC1_TAG1  = 32'hD26D_2001;

    localparam int unsigned P26D_QUEUE_DONE_DRAINED_BIT = 1;

    function new(string name = "ai_accel_subsys_csr_queue_lifecycle_drained_reinit_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p26d_make_cfg(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        output ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg
    );
    begin
        rt.make_default_queue_cfg(
            cfg,
            32'(P26D_SQ_BASE),
            32'(P26D_CQ_BASE),
            32'(P26D_QUEUE_DEPTH),
            1'b1  // RUN_UNTIL_EMPTY: one visible command reaches drained.
        );
    end
    endtask

    function automatic void p26d_set_cfg_epoch(
        ref ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input int unsigned epoch
    );
    begin
        // P26D keeps monotonic SQ/CQ counters instead of requiring a
        // zero-pointer reset.  Host-owned SQ_TAIL and CQ_HEAD are
        // reprogrammed to the same epoch, while hardware-owned SQ_HEAD
        // and CQ_TAIL are expected to already match after a clean drain
        // and CQ consumption.
        cfg.sq_head = 32'(epoch);
        cfg.sq_tail = 32'(epoch);
        cfg.cq_head = 32'(epoch);
        cfg.cq_tail = 32'(epoch);
    end
    endfunction

    task automatic p26d_make_cmd(
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
            32'(P26D_DESC_STRIDE),
            user_tag,
            1'b1,
            1'b0
        );

        // P26D validates normal drained-session lifecycle cleanup.
        // Timeout/error discard is reserved for P26F.
        cmd.timeout_cycles = 32'h0000_0000;
    end
    endtask

    task automatic p26d_run_drained_session_without_cleanup(
        input  ai_accel_event_driven_host_runtime_stress_helper rt,
        input  ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input  ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t cmd,
        input  ai_accel_subsys_seq_item profile_item,
        input  logic [31:0] first_desc_tag,
        input  logic [31:0] last_desc_tag,
        input  int unsigned cmd_counter,
        input  string label,
        output ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t terminal_snap
    );
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec;
        logic [31:0] event_mask;
        int unsigned sq_idx;
        int unsigned cq_idx;
        logic [31:0] next_tail;
    begin
        event_mask = rt.queue_completion_event_mask() |
                     rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);

        sq_idx    = cmd_counter % P26D_QUEUE_DEPTH;
        cq_idx    = cmd_counter % P26D_QUEUE_DEPTH;
        next_tail = 32'(cmd_counter + 1);

        csr_check_recipe_idle_ready($sformatf("%s before START_QUEUE", label));

        rt.submit_command_and_doorbell(cfg, sq_idx, cmd, next_tail);
        rt.start_queue();

        rt.wait_for_progress_event(
            event_mask,
            terminal_snap,
            $sformatf("%s event wait", label),
            done_timeout_cycles * 12,
            1'b1
        );
        p25c_check_event_snapshot(label, terminal_snap, event_mask);

        if (!terminal_snap.queue_done_status[P26D_QUEUE_DONE_DRAINED_BIT]) begin
            `uvm_fatal("P26D_LIFECYCLE/DRAINED_MISSING",
                $sformatf("%s: expected QUEUE_DRAINED sticky before cleanup, done=0x%08h status=0x%08h",
                    label,
                    terminal_snap.queue_done_status,
                    terminal_snap.queue_status))
        end

        rt.wait_and_check_cq_record(
            cfg,
            cq_idx,
            first_desc_tag,
            last_desc_tag,
            rec,
            $sformatf("%s CQ[%0d] before lifecycle cleanup", label, cq_idx),
            done_timeout_cycles * 4
        );
        check_p23d_cq_record(cq_idx, rec, profile_item, first_desc_tag, last_desc_tag);

        rt.require_queue_pointers($sformatf("%s pointers before lifecycle cleanup", label),
            next_tail,
            32'(cmd_counter),
            next_tail,
            32'h0000_0001);

        `uvm_info("P26D_LIFECYCLE/DRAINED_OBSERVED",
            $sformatf("%s: drained terminal state observed before cleanup cmd_counter=%0d sq_idx=%0d cq_idx=%0d cmd_tag=0x%08h desc_tags=0x%08h/0x%08h pending=0x%08h done=0x%08h",
                label,
                cmd_counter,
                sq_idx,
                cq_idx,
                cmd.user_tag,
                first_desc_tag,
                last_desc_tag,
                terminal_snap.event_snap.pending,
                terminal_snap.queue_done_status),
            UVM_MEDIUM)
    end
    endtask

    task automatic p26d_cleanup_drained_and_require_clean(
        input ai_accel_event_driven_host_runtime_stress_helper rt,
        input ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg,
        input logic [31:0] event_mask,
        input string label
    );
    begin
        rt.host_rt_lifecycle_cleanup_drained(
            cfg,
            event_mask,
            1'b0,  // reset_pointers: P26D uses pointer-preserving drained cleanup.
            1'b1,  // consume_visible_cq
            1'b1,  // recycle_memory
            label
        );

        rt.host_rt_lifecycle_check_clean_idle(
            $sformatf("%s clean pointer-preserving check", label),
            1'b0,  // queue done sticky must be clear after cleanup
            1'b1,  // event pending must be clean
            1'b0   // monotonic pointers may remain at the completed epoch
        );

        `uvm_info("P26D_LIFECYCLE/DRAINED_CLEANUP_PASS",
            $sformatf("%s: drained cleanup consumed CQ, cleared events/sticky status, recycled queue memory, and preserved a clean monotonic pointer epoch",
                label),
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
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t snap0;
        ai_accel_event_driven_host_runtime_stress_helper::p25_runtime_snapshot_t snap1;
        logic [31:0] event_mask;
    begin
        phase.raise_objection(this);

        `uvm_info("P26D_LIFECYCLE/START",
            "Starting P26D drained-session lifecycle cleanup + reinit smoke test",
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
            `uvm_fatal("P26D_LIFECYCLE/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        p25c_program_descriptor_table(
            P26D_DESC_BASE0,
            P26D_DESC0_TAG0,
            P26D_DESC0_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p25c_program_descriptor_table(
            P26D_DESC_BASE1,
            P26D_DESC1_TAG0,
            P26D_DESC1_TAG1,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        p26d_make_cfg(rt, cfg);
        p26d_make_cmd(rt, cmd0, 32'(P26D_DESC_BASE0), P26D_CMD0_TAG);
        p26d_make_cmd(rt, cmd1, 32'(P26D_DESC_BASE1), P26D_CMD1_TAG);

        event_mask = rt.queue_completion_event_mask() |
                     rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_program_completion_wb();

        rt.host_rt_lifecycle_init_session(
            cfg,
            event_mask,
            1'b1,
            1'b1,
            "P26D initial lifecycle init"
        );

        p26d_run_drained_session_without_cleanup(
            rt,
            cfg,
            cmd0,
            profile_item,
            P26D_DESC0_TAG0,
            P26D_DESC0_TAG1,
            0,
            "P26D session0 drained",
            snap0
        );

        p26d_cleanup_drained_and_require_clean(
            rt,
            cfg,
            event_mask,
            "P26D session0 drained cleanup"
        );

        p26d_set_cfg_epoch(cfg, 1);

        rt.deterministic_gap(9, "P26D gap after session0 cleanup");

        // Reinitialize a queue that has already been cleaned at monotonic
        // pointer epoch 1.  This intentionally exercises init idempotence
        // before the second command without relying on a full reset.
        rt.host_rt_lifecycle_init_session(
            cfg,
            event_mask,
            1'b1,
            1'b1,
            "P26D lifecycle reinit before session1"
        );

        `uvm_info("P26D_LIFECYCLE/REINIT_PASS",
            "P26D reinit after drained cleanup PASS: queue/event state is clean and ready for a second command",
            UVM_MEDIUM)

        p26d_run_drained_session_without_cleanup(
            rt,
            cfg,
            cmd1,
            profile_item,
            P26D_DESC1_TAG0,
            P26D_DESC1_TAG1,
            1,
            "P26D session1 after reinit",
            snap1
        );

        p26d_cleanup_drained_and_require_clean(
            rt,
            cfg,
            event_mask,
            "P26D session1 final drained cleanup"
        );

        p26d_set_cfg_epoch(cfg, 2);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        rt.host_rt_lifecycle_check_clean_idle(
            "P26D final clean idle state",
            1'b0,
            1'b1,
            1'b0
        );

        `uvm_info("P26D_LIFECYCLE/PASS",
            $sformatf("P26D drained-session cleanup + reinit PASS: CASE_ID=%0d commands=2 A_bytes=%0d B_bytes=%0d C_words=%0d",
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
