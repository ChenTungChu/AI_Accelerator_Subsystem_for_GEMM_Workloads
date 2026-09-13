// File: tb/uvm/test/ai_accel_subsys_csr_job_frontend_mode_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_JOB_FRONTEND_MODE_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_JOB_FRONTEND_MODE_SMOKE_TEST_SV

// ------------------------------------------------------------
// CSR job-level frontend-mode representative smoke tests
//
// Scope:
//   - preload A/B into the shared source memory model
//   - program one P15 CSR job descriptor
//   - select AXI-Stream or Direct Stream input mode through
//     CSR_JOB_MODE[1:0]
//   - issue CSR_JOB_COMMAND.START_JOB once
//   - let ai_accel_job_sequencer run preload A, preload B,
//     GEMM, and DMA store automatically
//   - poll job-level sticky done/error/reject registers
//   - compare destination memory against the software reference
//
// These focused job-level tests intentionally bypass the legacy
// sideband driver/scoreboard launch path and do not issue P14
// micro-operation START_* commands directly.
// ------------------------------------------------------------

class ai_accel_subsys_csr_job_frontend_mode_smoke_base extends ai_accel_subsys_csr_job_dma_load_store_smoke_test;

    localparam logic [31:0] JOB_MODE_AXIS_LOAD_DMA_STORE = 32'h0000_0006;
    localparam logic [31:0] JOB_MODE_DS_LOAD_DMA_STORE   = 32'h0000_0007;

    localparam logic [31:0] JOB_SRC_A_BASE = 32'h0000_0000;
    localparam logic [31:0] JOB_SRC_B_BASE = 32'h0000_0100;
    localparam logic [31:0] JOB_DST_C_BASE = 32'h0000_0000;


    // ------------------------------------------------------------
    // CODE-COV-C1.2-G8-A-R3-B
    // Direct-Stream job-path committed-extent negative proof.
    //
    // The existing Direct-Stream regression class executes this preflight
    // before its normal positive CASE_ID=102 flow.  Keeping the proof inside
    // the existing carrier preserves the 150-test regression inventory while
    // ensuring the shared-launch reject / sequencer-error path is represented
    // in the merged full-regression UCDB.
    // ------------------------------------------------------------
    localparam int unsigned G8_R3_JOB_DIM_M = 1;
    localparam int unsigned G8_R3_JOB_DIM_N = 1;
    localparam int unsigned G8_R3_JOB_DIM_K = 16;
    localparam int unsigned G8_R3_JOB_PRELOAD_BYTES = 8;
    localparam logic [31:0] G8_R3_JOB_SEQUENCE_ERROR_MASK = 32'h0000_0100;
    localparam logic [31:0] G8_R3_JOB_STATE_ERROR = 32'h0000_000E;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_csr_job_frontend_mode_smoke_base",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Frontend selection hooks
    // ------------------------------------------------------------
    virtual function automatic logic [31:0] get_job_mode_value();
        return JOB_MODE_AXIS_LOAD_DMA_STORE;
    endfunction

    virtual function automatic string get_frontend_name();
        return "AXI-Stream";
    endfunction

    virtual function automatic string get_frontend_tag();
        return "AXIS";
    endfunction

    // ------------------------------------------------------------
    // Source/destination memory model preparation
    //
    // The AXI-Stream and Direct Stream source responders in the CSR
    // UVM top intentionally share ctrl_if.dma_src_mem[] as backing
    // storage.  This mirrors the P14F representative tests.
    // ------------------------------------------------------------
    task automatic write_u8_payload_to_shared_src(
        input logic [31:0] base_addr,
        input int signed   payload[]
    );
        int unsigned i;
        logic [7:0] byte_value;
    begin
        for (i = 0; i < payload.size(); i++) begin
            byte_value = payload[i][7:0];
            vif.dma_src_mem_write_byte(
                base_addr + 32'(i),
                byte_value
            );
        end
    end
    endtask

    task automatic prepare_frontend_source_and_destination(
        input int signed a_flat[],
        input int signed b_flat[]
    );
    begin
        vif.dma_src_mem_clear();
        vif.dma_dst_mem_clear();

        vif.dma_src_set_rresp_error(1'b0, -1);
        vif.axis_src_set_rresp_error(1'b0, -1);
        vif.ds_src_set_rresp_error(1'b0, -1);
        vif.dma_dst_set_bresp_error(1'b0, -1);

        write_u8_payload_to_shared_src(JOB_SRC_A_BASE, a_flat);
        write_u8_payload_to_shared_src(JOB_SRC_B_BASE, b_flat);

        `uvm_info("CSR_JOB_FE_SMOKE",
            $sformatf("Prepared %s job source payloads: A src=0x%08h bytes=%0d, B src=0x%08h bytes=%0d, dst C base=0x%08h",
                get_frontend_name(),
                JOB_SRC_A_BASE,
                a_flat.size(),
                JOB_SRC_B_BASE,
                b_flat.size(),
                JOB_DST_C_BASE),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Job descriptor programming
    // ------------------------------------------------------------
    task automatic csr_write_frontend_job_descriptor(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
        int unsigned a_beats;
        int unsigned b_beats;
        logic [31:0] mode_value;
    begin
        a_beats   = bytes_to_beats(a_bytes);
        b_beats   = bytes_to_beats(b_bytes);
        mode_value = get_job_mode_value();

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_MODE,
            mode_value
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_BASE_ADDR_A,
            profile_item.base_addr_a
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_BASE_ADDR_B,
            profile_item.base_addr_b
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_BASE_ADDR_C,
            profile_item.base_addr_c
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_DIM_M,
            32'(profile_item.dim_m)
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_DIM_N,
            32'(profile_item.dim_n)
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_DIM_K,
            32'(profile_item.dim_k)
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_A_SRC_BASE,
            JOB_SRC_A_BASE
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_A_DST_BASE,
            profile_item.base_addr_a
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_A_LOAD_BEATS,
            32'(a_beats)
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_B_SRC_BASE,
            JOB_SRC_B_BASE
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_B_DST_BASE,
            profile_item.base_addr_b
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_B_LOAD_BEATS,
            32'(b_beats)
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_STORE_SRC_BASE,
            profile_item.base_addr_c
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_STORE_DST_BASE,
            JOB_DST_C_BASE
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_STORE_BYTE_COUNT,
            32'(c_bytes)
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_JOB_MODE,
            mode_value,
            "CSR_JOB_MODE"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_JOB_BASE_ADDR_A,
            profile_item.base_addr_a,
            "CSR_JOB_BASE_ADDR_A"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_JOB_BASE_ADDR_B,
            profile_item.base_addr_b,
            "CSR_JOB_BASE_ADDR_B"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_JOB_BASE_ADDR_C,
            profile_item.base_addr_c,
            "CSR_JOB_BASE_ADDR_C"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_JOB_DIM_M,
            32'(profile_item.dim_m),
            "CSR_JOB_DIM_M"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_JOB_DIM_N,
            32'(profile_item.dim_n),
            "CSR_JOB_DIM_N"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_JOB_DIM_K,
            32'(profile_item.dim_k),
            "CSR_JOB_DIM_K"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_JOB_A_LOAD_BEATS,
            32'(a_beats),
            "CSR_JOB_A_LOAD_BEATS"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_JOB_B_LOAD_BEATS,
            32'(b_beats),
            "CSR_JOB_B_LOAD_BEATS"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_JOB_STORE_BYTE_COUNT,
            32'(c_bytes),
            "CSR_JOB_STORE_BYTE_COUNT"
        );

        `uvm_info("CSR_JOB_FE_SMOKE",
            $sformatf("Programmed CSR %s job descriptor: case_id=%0d mode=0x%08h A src=0x%08h dst=0x%08h beats=%0d B src=0x%08h dst=0x%08h beats=%0d C src=0x%08h dst=0x%08h bytes=%0d dim=(%0d,%0d,%0d)",
                get_frontend_name(),
                profile_item.case_id,
                mode_value,
                JOB_SRC_A_BASE,
                profile_item.base_addr_a,
                a_beats,
                JOB_SRC_B_BASE,
                profile_item.base_addr_b,
                b_beats,
                profile_item.base_addr_c,
                JOB_DST_C_BASE,
                c_bytes,
                profile_item.dim_m,
                profile_item.dim_n,
                profile_item.dim_k),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G8-A-R3-B
    // P15 Direct-Stream undersized-extent shared-launch rejection proof
    // ------------------------------------------------------------
    task automatic run_g8_r3_direct_stream_extent_reject_probe();
        ai_accel_subsys_seq_item profile_item;
        int signed               a_flat[];
        int signed               b_flat[];
        logic [31:0]             job_status;
        logic [31:0]             job_done_status;
        logic [31:0]             job_error_status;
        logic [31:0]             job_reject_status;
        logic [31:0]             job_state;
        logic [31:0]             job_mac_count;
        int unsigned             poll_count;
        int unsigned             i;
    begin
        `uvm_info("CODE_COV_C1P2_G8_A_R3_B/P15_START",
            "Starting P15 Direct-Stream undersized-extent shared-launch rejection proof",
            UVM_MEDIUM)

        profile_item = ai_accel_subsys_seq_item::type_id::create("g8_r3_job_extent_profile");
        profile_item.case_id            = selected_case_id;
        profile_item.base_addr_a        = 32'h0000_0000;
        profile_item.base_addr_b        = 32'h0000_0100;
        profile_item.base_addr_c        = 32'h0000_0200;
        profile_item.dim_m              = G8_R3_JOB_DIM_M;
        profile_item.dim_n              = G8_R3_JOB_DIM_N;
        profile_item.dim_k              = G8_R3_JOB_DIM_K;
        profile_item.accumulate_enable  = 1'b0;

        a_flat = new[G8_R3_JOB_PRELOAD_BYTES];
        b_flat = new[G8_R3_JOB_PRELOAD_BYTES];
        for (i = 0; i < G8_R3_JOB_PRELOAD_BYTES; i++) begin
            a_flat[i] = 1;
            b_flat[i] = 1;
        end

        prepare_frontend_source_and_destination(a_flat, b_flat);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_check_job_idle_ready("before R3-B P15 extent-negative START_JOB");

        csr_write_frontend_job_descriptor(
            profile_item,
            G8_R3_JOB_PRELOAD_BYTES,
            G8_R3_JOB_PRELOAD_BYTES,
            4
        );

        csr_start_job();

        poll_count = 0;
        forever begin
            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_JOB_STATUS,
                job_status
            );
            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_JOB_DONE_STATUS,
                job_done_status
            );
            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_JOB_ERROR_STATUS,
                job_error_status
            );
            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS,
                job_reject_status
            );
            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_JOB_STATE,
                job_state
            );

            if (job_reject_status != 32'h0000_0000) begin
                `uvm_fatal("CODE_COV_C1P2_G8_A_R3_B/P15_UNEXPECTED_REJECT",
                    $sformatf("P15 job was rejected before reaching the shared GEMM guard: reject=0x%08h state=0x%08h",
                        job_reject_status, job_state))
            end

            if (job_done_status != 32'h0000_0000) begin
                `uvm_fatal("CODE_COV_C1P2_G8_A_R3_B/P15_UNEXPECTED_DONE",
                    $sformatf("Undersized P15 Direct-Stream job must not reach JOB_DONE: done=0x%08h state=0x%08h",
                        job_done_status, job_state))
            end

            if (job_error_status[8]) begin
                break;
            end

            @(posedge csr_vif.clk);
            poll_count++;
            if (poll_count > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1P2_G8_A_R3_B/P15_TIMEOUT",
                    $sformatf("P15 shared launch rejection did not terminate the job; possible GEMM_WAIT hang. status=0x%08h error=0x%08h state=0x%08h polls=%0d",
                        job_status, job_error_status, job_state, poll_count))
            end
        end

        repeat (2) @(posedge csr_vif.clk);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_STATUS, job_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_DONE_STATUS, job_done_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_ERROR_STATUS, job_error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS, job_reject_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_STATE, job_state);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_PERF_MAC_COUNT, job_mac_count);

        if (job_error_status != G8_R3_JOB_SEQUENCE_ERROR_MASK) begin
            `uvm_fatal("CODE_COV_C1P2_G8_A_R3_B/P15_ERROR_MISMATCH",
                $sformatf("Expected only P15 JOB_SEQUENCE_ERROR bit8 after shared extent rejection: error=0x%08h",
                    job_error_status))
        end

        if (job_reject_status != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1P2_G8_A_R3_B/P15_REJECT_MISMATCH",
                $sformatf("Shared actual-state guard is a post-START_JOB sequence failure, not a P15 descriptor reject: reject=0x%08h",
                    job_reject_status))
        end

        if (job_done_status != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1P2_G8_A_R3_B/P15_DONE_MISMATCH",
                $sformatf("No P15 done bits may assert for extent-rejected GEMM: done=0x%08h",
                    job_done_status))
        end

        if (job_status[0]) begin
            `uvm_fatal("CODE_COV_C1P2_G8_A_R3_B/P15_BUSY_STUCK",
                $sformatf("P15 job remained busy after shared extent rejection: status=0x%08h state=0x%08h",
                    job_status, job_state))
        end

        if (!job_status[2] || (job_state != G8_R3_JOB_STATE_ERROR)) begin
            `uvm_fatal("CODE_COV_C1P2_G8_A_R3_B/P15_TERMINAL_STATE",
                $sformatf("Expected terminal JOB_ERROR state with error summary set: status=0x%08h state=0x%08h",
                    job_status, job_state))
        end

        if (job_mac_count != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1P2_G8_A_R3_B/P15_MAC_ACTIVITY",
                $sformatf("Extent-rejected P15 job must not execute GEMM MACs: job_mac_count=%0d",
                    job_mac_count))
        end

        `uvm_info("CODE_COV_C1P2_G8_A_R3_B/P15_EXTENT_REJECT_PASS",
            $sformatf("P15 undersized A/B preloads completed, shared GEMM launch guard rejected the request, sequencer terminated with sequence-error bit8, and no GEMM MAC activity occurred (polls=%0d)",
                poll_count),
            UVM_MEDIUM)

        csr_job_clear_sticky_status();
        repeat (2) @(posedge csr_vif.clk);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_ERROR_STATUS, job_error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS, job_reject_status);

        if ((job_error_status != 32'h0000_0000) ||
            (job_reject_status != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1P2_G8_A_R3_B/P15_CLEAR_FAIL",
                $sformatf("P15 sticky clear failed after extent rejection: error=0x%08h reject=0x%08h",
                    job_error_status, job_reject_status))
        end

        csr_check_job_idle_ready("after R3-B P15 extent-reject clear");

        `uvm_info("CODE_COV_C1P2_G8_A_R3_B/P15_PASS",
            "P15 Direct-Stream extent-negative shared-guard proof PASS; proceeding to normal positive job",
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ai_accel_subsys_seq_item profile_item;
        int signed               a_flat[];
        int signed               b_flat[];
        int signed               expected_c[];
        int signed               actual_c[];
        int unsigned             c_elems;
        int unsigned             c_bytes;
    begin
        phase.raise_objection(this);

        `uvm_info("CSR_JOB_FE_SMOKE",
            $sformatf("Starting CSR job-level %s preload + GEMM + DMA store smoke test",
                get_frontend_name()),
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        if (get_job_mode_value() == JOB_MODE_DS_LOAD_DMA_STORE) begin
            run_g8_r3_direct_stream_extent_reject_probe();
        end

        build_selected_payload(
            profile_item,
            a_flat,
            b_flat,
            expected_c
        );

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("CSR_JOB_FE_SMOKE/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(), c_elems))
        end

        prepare_frontend_source_and_destination(a_flat, b_flat);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_check_job_idle_ready("before START_JOB");

        csr_write_frontend_job_descriptor(
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        csr_start_job();
        csr_poll_job_done(done_timeout_cycles);
        csr_check_job_perf_snapshot(profile_item);

        repeat (5) @(posedge csr_vif.clk);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("CSR_JOB_FE_SMOKE",
            $sformatf("CSR job-level %s preload + GEMM + DMA store smoke completed: CASE_ID=%0d test_kind=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
                get_frontend_name(),
                selected_case_id,
                selected_test_kind,
                a_flat.size(),
                b_flat.size(),
                c_elems),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

class ai_accel_subsys_csr_job_axis_stream_load_store_smoke_test extends ai_accel_subsys_csr_job_frontend_mode_smoke_base;
    `uvm_component_utils(ai_accel_subsys_csr_job_axis_stream_load_store_smoke_test)

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_csr_job_axis_stream_load_store_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function automatic logic [31:0] get_job_mode_value();
        return JOB_MODE_AXIS_LOAD_DMA_STORE;
    endfunction

    virtual function automatic string get_frontend_name();
        return "AXI-Stream";
    endfunction

    virtual function automatic string get_frontend_tag();
        return "AXIS";
    endfunction

endclass

class ai_accel_subsys_csr_job_direct_stream_load_store_smoke_test extends ai_accel_subsys_csr_job_frontend_mode_smoke_base;
    `uvm_component_utils(ai_accel_subsys_csr_job_direct_stream_load_store_smoke_test)

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_csr_job_direct_stream_load_store_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function automatic logic [31:0] get_job_mode_value();
        return JOB_MODE_DS_LOAD_DMA_STORE;
    endfunction

    virtual function automatic string get_frontend_name();
        return "Direct Stream";
    endfunction

    virtual function automatic string get_frontend_tag();
        return "DS";
    endfunction

endclass


`endif
