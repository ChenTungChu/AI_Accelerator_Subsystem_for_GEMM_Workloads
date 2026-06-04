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
