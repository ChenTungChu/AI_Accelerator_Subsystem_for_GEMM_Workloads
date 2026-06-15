// File: tb/uvm/test/ai_accel_subsys_csr_event_driven_stop_timeout_recovery_stress_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_EVENT_DRIVEN_STOP_TIMEOUT_RECOVERY_STRESS_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_EVENT_DRIVEN_STOP_TIMEOUT_RECOVERY_STRESS_TEST_SV

// ============================================================
// P25E event-driven STOP / timeout / recovery mixed stress
//
// Scope:
//   - Reuses the validated P23F STOP_QUEUE live-service scenario to
//     prove that a runtime append can be held pending by STOP_QUEUE,
//     then restarted and completed by the host.
//   - Reuses the validated P24F event-driven timeout recovery scenario
//     to prove that a later watchdog timeout raises QUEUE_ERROR_EVENT,
//     can be cleaned by the host, and does not prevent a post-timeout
//     command from completing normally.
//   - Runs both scenarios back-to-back in one UVM test so P22 event
//     clear/re-arm, queue sticky cleanup, CQ consumption, and runtime
//     reuse are validated across mixed terminal conditions.
//
// This is UVM/helper-only validation.  It does not add RTL, CSR map
// changes, SQ/CQ format changes, descriptor-format changes, completion
// record changes, event bits, standalone tops, or datapath changes.
// ============================================================

class ai_accel_subsys_csr_event_driven_stop_timeout_recovery_stress_test
    extends ai_accel_subsys_csr_queue_timeout_recovery_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_event_driven_stop_timeout_recovery_stress_test)

    function new(string name = "ai_accel_subsys_csr_event_driven_stop_timeout_recovery_stress_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic p25e_program_mixed_descriptors(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
    begin
        // STOP_QUEUE phase uses the already-validated P23F stop/restart
        // descriptor tables.
        program_p23f_descriptor_table(
            P23F_STOP_DESC0_BASE,
            P23F_STOP_DESC0_TAG0,
            P23F_STOP_DESC0_TAG1,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes
        );

        program_p23f_descriptor_table(
            P23F_STOP_DESC1_BASE,
            P23F_STOP_DESC1_TAG0,
            P23F_STOP_DESC1_TAG1,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes
        );

        // Timeout phase uses the already-validated P24F timeout/recovery
        // descriptor tables.
        program_p24d_descriptor_table(
            P24F_TIMEOUT_DESC_BASE,
            P24F_TIMEOUT_DESC_TAG0,
            P24F_TIMEOUT_DESC_TAG1,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes
        );

        program_p24d_descriptor_table(
            P24F_RECOVERY_DESC_BASE,
            P24F_RECOVERY_DESC_TAG0,
            P24F_RECOVERY_DESC_TAG1,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes
        );
    end
    endtask

    task automatic p25e_case_stop_then_timeout_recovery(
        input ai_accel_event_driven_host_runtime_stress_helper rt,
        input ai_accel_subsys_seq_item                         profile_item,
        input int unsigned                                     c_elems,
        input int signed                                       expected_c[]
    );
        int signed actual_c[];
    begin
        `uvm_info("P25E_HOST_RT/MIXED_START",
            "Starting mixed STOP_QUEUE then timeout/recovery runtime stress sequence",
            UVM_MEDIUM)

        // ------------------------------------------------------------
        // Phase 1: clean STOP_QUEUE terminal behavior and restart of a
        // pending appended SQ entry.
        // ------------------------------------------------------------
        p23f_case_stop_queue(rt, profile_item);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P25E_HOST_RT/STOP_PASS",
            "P25E STOP_QUEUE phase PASS: runtime append stayed pending until host restart, CQ records consumed, events cleaned, result compare passed",
            UVM_MEDIUM)

        // ------------------------------------------------------------
        // Phase 2: watchdog timeout, QUEUE_ERROR_EVENT handling, sticky
        // cleanup, event re-arm, and post-timeout valid command recovery.
        // ------------------------------------------------------------
        p24f_case_timeout_then_recover(rt, profile_item);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P25E_HOST_RT/TIMEOUT_RECOVERY_PASS",
            "P25E timeout/recovery phase PASS: timeout event handled, queue cleaned, recovery command completed, result compare passed",
            UVM_MEDIUM)
    end
    endtask

    task run_phase(uvm_phase phase);
        ai_accel_subsys_seq_item profile_item;
        int signed               a_flat[];
        int signed               b_flat[];
        int signed               expected_c[];
        int unsigned             c_elems;
        int unsigned             c_bytes;

        ai_accel_event_driven_host_runtime_stress_helper rt;
    begin
        phase.raise_objection(this);

        `uvm_info("P25E_HOST_RT/START",
            "Starting P25E STOP / timeout / recovery mixed runtime stress smoke test",
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
            `uvm_fatal("P25E_HOST_RT/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        p25e_program_mixed_descriptors(
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_program_completion_wb();

        rt.require_event_clean("P25E initial event state");
        rt.wait_queue_reusable("P25E initial reusable state", done_timeout_cycles * 2);

        p25e_case_stop_then_timeout_recovery(
            rt,
            profile_item,
            c_elems,
            expected_c
        );

        rt.require_event_clean("P25E final event state");
        rt.wait_queue_reusable("P25E final reusable state", done_timeout_cycles * 2);
        rt.require_no_queue_error("P25E final queue error/reject state");

        `uvm_info("P25E_HOST_RT/PASS",
            $sformatf("P25E STOP / timeout / recovery mixed runtime stress PASS: CASE_ID=%0d timeout_cycles=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
                selected_case_id,
                P24F_SHORT_TIMEOUT_CYCLES,
                a_flat.size(),
                b_flat.size(),
                c_elems),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
