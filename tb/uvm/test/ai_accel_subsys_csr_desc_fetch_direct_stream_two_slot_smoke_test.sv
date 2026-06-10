// File: tb/uvm/test/ai_accel_subsys_csr_desc_fetch_direct_stream_two_slot_smoke_test.sv
// ============================================================
// P17F CSR descriptor-fetch -> P16 Direct Stream recipe bridge smoke
//
// Scope:
//   - Reuses the existing CSR UVM top and run_uvm.tcl flow.
//   - Prepares A/B payloads in the existing descriptor/source memory
//     model used by the Direct Stream AXI read responder.
//   - Writes two memory-resident descriptors into the same source
//     memory model.
//   - Issues CSR_DESC_FETCH_COMMAND.START_FETCH.
//   - The P17 bridge launches the existing P16 recipe sequencer from
//     the fetched snapshot.
//   - The existing P16/P15 path dispatches:
//       slot0: DIRECT_STREAM preload A/B -> GEMM -> HOST_READBACK
//       slot1: DIRECT_STREAM preload A/B -> GEMM -> DMA_STORE
//   - Final DMA destination C is compared against the software
//     reference.
//
// This is a P17 frontend representative.  It intentionally validates
// the descriptor-fetch path with Direct Stream because that path must
// propagate INPUT_MODE=DIRECT_STREAM through P16/P15 so the P15 worker
// forces GEMM_INPUT_STREAM_MODE=1 and routes A/B through the operand
// buffer while keeping C write/store scratchpad-backed.
// ============================================================

`ifndef AI_ACCEL_SUBSYS_CSR_DESC_FETCH_DIRECT_STREAM_TWO_SLOT_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_DESC_FETCH_DIRECT_STREAM_TWO_SLOT_SMOKE_TEST_SV

class ai_accel_subsys_csr_desc_fetch_direct_stream_two_slot_smoke_test
    extends ai_accel_subsys_csr_desc_fetch_dma_two_slot_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_desc_fetch_direct_stream_two_slot_smoke_test)

    // SLOT_CONTROL format mirrors the P16 slot descriptor:
    //   bit0    VALID
    //   bits2:1 INPUT_MODE, 3 = DIRECT_STREAM
    //   bits4:3 OUTPUT_MODE, 0 = HOST_READBACK, 1 = DMA_STORE
    //   bit5    ACCUMULATE_ENABLE
    localparam logic [31:0] SLOT0_CONTROL_DS_HOST_READBACK = 32'h0000_0007;
    localparam logic [31:0] SLOT1_CONTROL_DS_DMA_STORE     = 32'h0000_000F;

    // Keep the descriptor table away from the standard A/B source
    // payloads used by inherited source-memory setup.
    localparam int unsigned P17F_DESC_BASE                 = 32'h0000_0600;
    localparam int unsigned P17F_DESC_STRIDE               = 32'h0000_0080;

    localparam logic [31:0] P17F_DS_SRC_A_BASE             = 32'h0000_0000;
    localparam logic [31:0] P17F_DS_SRC_B_BASE             = 32'h0000_0100;
    localparam logic [31:0] P17F_DMA_DST_C_BASE            = 32'h0000_0000;

    function new(string name = "ai_accel_subsys_csr_desc_fetch_direct_stream_two_slot_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic program_memory_direct_stream_descriptor(
        input int unsigned             desc_base,
        input logic [31:0]             slot_control,
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes,
        input logic [31:0]             user_tag
    );
        int unsigned a_beats;
        int unsigned b_beats;
    begin
        a_beats = bytes_to_beats(a_bytes);
        b_beats = bytes_to_beats(b_bytes);

        write_desc_word(desc_base, DESC_WORD_CONTROL,          slot_control);
        write_desc_word(desc_base, DESC_WORD_BASE_ADDR_A,      profile_item.base_addr_a);
        write_desc_word(desc_base, DESC_WORD_BASE_ADDR_B,      profile_item.base_addr_b);
        write_desc_word(desc_base, DESC_WORD_BASE_ADDR_C,      profile_item.base_addr_c);
        write_desc_word(desc_base, DESC_WORD_DIM_M,            32'(profile_item.dim_m));
        write_desc_word(desc_base, DESC_WORD_DIM_N,            32'(profile_item.dim_n));
        write_desc_word(desc_base, DESC_WORD_DIM_K,            32'(profile_item.dim_k));

        // Direct Stream source responder uses the existing source-memory
        // byte array.  The destination/base fields are passed through to
        // the Direct Stream preload engine and remain aligned with the
        // logical GEMM A/B base addresses used by the operand-buffer router.
        write_desc_word(desc_base, DESC_WORD_A_SRC_BASE,       P17F_DS_SRC_A_BASE);
        write_desc_word(desc_base, DESC_WORD_A_DST_BASE,       profile_item.base_addr_a);
        write_desc_word(desc_base, DESC_WORD_A_LOAD_BEATS,     32'(a_beats));

        write_desc_word(desc_base, DESC_WORD_B_SRC_BASE,       P17F_DS_SRC_B_BASE);
        write_desc_word(desc_base, DESC_WORD_B_DST_BASE,       profile_item.base_addr_b);
        write_desc_word(desc_base, DESC_WORD_B_LOAD_BEATS,     32'(b_beats));

        write_desc_word(desc_base, DESC_WORD_STORE_SRC_BASE,   profile_item.base_addr_c);
        write_desc_word(desc_base, DESC_WORD_STORE_DST_BASE,   P17F_DMA_DST_C_BASE);
        write_desc_word(desc_base, DESC_WORD_STORE_BYTE_COUNT, 32'(c_bytes));
        write_desc_word(desc_base, DESC_WORD_USER_TAG,         user_tag);

        `uvm_info("P17F_DESC_FETCH_DS",
            $sformatf("Programmed memory Direct Stream descriptor at 0x%08h: control=0x%08h A src=0x%08h bytes=%0d B src=0x%08h bytes=%0d C dst=0x%08h bytes=%0d tag=0x%08h dim=(%0d,%0d,%0d)",
                desc_base,
                slot_control,
                P17F_DS_SRC_A_BASE,
                a_bytes,
                P17F_DS_SRC_B_BASE,
                b_bytes,
                P17F_DMA_DST_C_BASE,
                c_bytes,
                user_tag,
                profile_item.dim_m,
                profile_item.dim_n,
                profile_item.dim_k),
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
    begin
        phase.raise_objection(this);

        `uvm_info("P17F_DESC_FETCH_DS/START",
            "Starting P17F CSR descriptor-fetch Direct Stream two-slot recipe smoke test",
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
            `uvm_fatal("P17F_DESC_FETCH_DS/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(), c_elems))
        end

        // The inherited helper writes A/B into the common byte-addressed
        // source memory and clears destination/error-injection state.  The
        // Direct Stream responder reads from this same source-memory array.
        prepare_dma_source_and_destination(a_flat, b_flat);

        // Write descriptors after A/B preparation so source-memory setup
        // does not overwrite the descriptor table.
        program_memory_direct_stream_descriptor(
            P17F_DESC_BASE + (0 * P17F_DESC_STRIDE),
            SLOT0_CONTROL_DS_HOST_READBACK,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            32'hD17F_0000
        );

        program_memory_direct_stream_descriptor(
            P17F_DESC_BASE + (1 * P17F_DESC_STRIDE),
            SLOT1_CONTROL_DS_DMA_STORE,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            32'hD17F_0001
        );

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_check_recipe_idle_ready("before Direct Stream descriptor fetch START");

        csr_start_desc_fetch_recipe(P17F_DESC_BASE, 2, P17F_DESC_STRIDE);
        csr_poll_desc_fetch_done(done_timeout_cycles);

        // P17F bridge should have launched the existing P16 recipe path
        // from the fetched Direct Stream snapshot.  Reuse the P16 recipe
        // checker and perf checks.
        csr_poll_recipe_done(done_timeout_cycles * 2);
        csr_check_recipe_perf_snapshot(profile_item);

        repeat (5) @(posedge csr_vif.clk);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P17F_DESC_FETCH_DS/PASS",
            $sformatf("P17F descriptor-fetch Direct Stream two-slot recipe completed: CASE_ID=%0d test_kind=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
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

`endif
