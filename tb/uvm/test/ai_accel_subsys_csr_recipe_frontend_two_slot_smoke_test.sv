// File: tb/uvm/test/ai_accel_subsys_csr_recipe_frontend_two_slot_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_RECIPE_FRONTEND_TWO_SLOT_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_RECIPE_FRONTEND_TWO_SLOT_SMOKE_TEST_SV

// ------------------------------------------------------------
// CSR recipe-level frontend-mode two-slot smoke tests
//
// Scope:
//   - preload A/B into the shared source memory model used by
//     the CSR UVM top's AXI-Stream and Direct Stream responders
//   - program two P16 recipe descriptor slots
//   - select AXI-Stream or Direct Stream input mode through each
//     slot's SLOT_CONTROL.INPUT_MODE field
//   - issue CSR_RECIPE_COMMAND.START_RECIPE once
//   - let ai_accel_recipe_sequencer dispatch slot0 then slot1
//     through the existing P15 single-job worker
//   - slot0 runs frontend preload A/B -> GEMM -> HOST_READBACK
//   - slot1 runs frontend preload A/B -> GEMM -> DMA store
//   - poll recipe-level sticky done/error/reject registers
//   - check recipe-level per-slot masks and accumulated perf
//   - compare destination memory against the software reference
//
// These P16E tests intentionally validate that the P16 recipe
// runner can reuse the P15 frontend-mode worker path for non-DMA
// input modes.  C RMW accumulation is covered separately by P16D.
// ------------------------------------------------------------

class ai_accel_subsys_csr_recipe_frontend_two_slot_smoke_base extends ai_accel_subsys_csr_recipe_dma_two_slot_smoke_test;

    localparam logic [31:0] SLOT0_CONTROL_AXIS_HOST_READBACK = 32'h0000_0005;
    localparam logic [31:0] SLOT1_CONTROL_AXIS_DMA_STORE     = 32'h0000_000D;
    localparam logic [31:0] SLOT0_CONTROL_DS_HOST_READBACK   = 32'h0000_0007;
    localparam logic [31:0] SLOT1_CONTROL_DS_DMA_STORE       = 32'h0000_000F;

    localparam logic [31:0] FRONTEND_SRC_A_BASE = 32'h0000_0000;
    localparam logic [31:0] FRONTEND_SRC_B_BASE = 32'h0000_0100;
    localparam logic [31:0] FRONTEND_DST_C_BASE = 32'h0000_0000;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_csr_recipe_frontend_two_slot_smoke_base",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Frontend selection hooks
    // ------------------------------------------------------------
    virtual function automatic logic [31:0] get_slot0_control();
        return SLOT0_CONTROL_AXIS_HOST_READBACK;
    endfunction

    virtual function automatic logic [31:0] get_slot1_control();
        return SLOT1_CONTROL_AXIS_DMA_STORE;
    endfunction

    virtual function automatic string get_frontend_name();
        return "AXI-Stream";
    endfunction

    virtual function automatic string get_frontend_tag();
        return "AXIS";
    endfunction

    virtual function automatic logic [31:0] get_user_tag_base();
        return 32'h0000_16E0;
    endfunction

    // ------------------------------------------------------------
    // Source/destination memory model preparation
    //
    // The AXI-Stream and Direct Stream source responders in the CSR
    // UVM top intentionally share ctrl_if.dma_src_mem[] as backing
    // storage.  This mirrors the P14F/P15E frontend-mode tests.
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

    task automatic prepare_recipe_frontend_source_and_destination(
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

        write_u8_payload_to_shared_src(FRONTEND_SRC_A_BASE, a_flat);
        write_u8_payload_to_shared_src(FRONTEND_SRC_B_BASE, b_flat);

        `uvm_info("P16E_RECIPE_FE",
            $sformatf("Prepared %s recipe source payloads: A src=0x%08h bytes=%0d, B src=0x%08h bytes=%0d, dst C base=0x%08h",
                get_frontend_name(),
                FRONTEND_SRC_A_BASE,
                a_flat.size(),
                FRONTEND_SRC_B_BASE,
                b_flat.size(),
                FRONTEND_DST_C_BASE),
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
        logic [31:0]             user_tag_base;
    begin
        phase.raise_objection(this);

        `uvm_info("P16E_RECIPE_FE",
            $sformatf("Starting CSR recipe-level %s two-slot smoke test",
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
            `uvm_fatal("P16E_RECIPE_FE/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(), c_elems))
        end

        prepare_recipe_frontend_source_and_destination(a_flat, b_flat);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_check_recipe_idle_ready("before START_RECIPE");

        user_tag_base = get_user_tag_base();

        csr_write_recipe_slot(
            0,
            get_slot0_control(),
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            user_tag_base
        );

        csr_write_recipe_slot(
            1,
            get_slot1_control(),
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            user_tag_base + 32'd1
        );

        csr_write_recipe_control();
        csr_start_recipe();
        csr_poll_recipe_done(done_timeout_cycles * 2);
        csr_check_recipe_perf_snapshot(profile_item);

        repeat (5) @(posedge csr_vif.clk);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P16E_RECIPE_FE",
            $sformatf("CSR recipe-level %s two-slot smoke completed: CASE_ID=%0d test_kind=%0d slots=2 A_bytes=%0d B_bytes=%0d C_words=%0d",
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

class ai_accel_subsys_csr_recipe_axis_stream_two_slot_smoke_test extends ai_accel_subsys_csr_recipe_frontend_two_slot_smoke_base;
    `uvm_component_utils(ai_accel_subsys_csr_recipe_axis_stream_two_slot_smoke_test)

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_csr_recipe_axis_stream_two_slot_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function automatic logic [31:0] get_slot0_control();
        return SLOT0_CONTROL_AXIS_HOST_READBACK;
    endfunction

    virtual function automatic logic [31:0] get_slot1_control();
        return SLOT1_CONTROL_AXIS_DMA_STORE;
    endfunction

    virtual function automatic string get_frontend_name();
        return "AXI-Stream";
    endfunction

    virtual function automatic string get_frontend_tag();
        return "AXIS";
    endfunction

    virtual function automatic logic [31:0] get_user_tag_base();
        return 32'h0000_16E0;
    endfunction

endclass

class ai_accel_subsys_csr_recipe_direct_stream_two_slot_smoke_test extends ai_accel_subsys_csr_recipe_frontend_two_slot_smoke_base;
    `uvm_component_utils(ai_accel_subsys_csr_recipe_direct_stream_two_slot_smoke_test)

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_csr_recipe_direct_stream_two_slot_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function automatic logic [31:0] get_slot0_control();
        return SLOT0_CONTROL_DS_HOST_READBACK;
    endfunction

    virtual function automatic logic [31:0] get_slot1_control();
        return SLOT1_CONTROL_DS_DMA_STORE;
    endfunction

    virtual function automatic string get_frontend_name();
        return "Direct Stream";
    endfunction

    virtual function automatic string get_frontend_tag();
        return "DS";
    endfunction

    virtual function automatic logic [31:0] get_user_tag_base();
        return 32'h0000_16E2;
    endfunction

endclass

`endif
