// File: tb/uvm/test/ai_accel_subsys_csr_desc_fetch_dma_two_slot_smoke_test.sv
// ============================================================
// P17D CSR descriptor-fetch -> P16 recipe bridge smoke test
//
// Scope:
//   - Reuses the existing CSR UVM top and run_uvm.tcl flow.
//   - Prepares A/B payloads in the existing DMA source memory.
//   - Writes two memory-resident descriptors into the descriptor
//     table region of the same source memory model.
//   - Issues CSR_DESC_FETCH_COMMAND.START_FETCH.
//   - P17D bridge launches the existing P16 recipe sequencer after
//     descriptor fetch completes and the fetched snapshot is valid.
//   - The existing P16/P15 path dispatches:
//       slot0: DMA_LOAD -> GEMM -> HOST_READBACK
//       slot1: DMA_LOAD -> GEMM -> DMA_STORE
//   - Final DMA destination C is compared against the software
//     reference.
//
// This test intentionally validates the fetched-descriptor bridge
// without adding a standalone desc_fetch TB or a new run script.
// ============================================================

`ifndef AI_ACCEL_SUBSYS_CSR_DESC_FETCH_DMA_TWO_SLOT_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_DESC_FETCH_DMA_TWO_SLOT_SMOKE_TEST_SV

class ai_accel_subsys_csr_desc_fetch_dma_two_slot_smoke_test
    extends ai_accel_subsys_csr_recipe_dma_two_slot_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_desc_fetch_dma_two_slot_smoke_test)

    typedef virtual ai_accel_subsys_ctrl_if #(
        .ADDR_WIDTH        (32),
        .DIM_WIDTH         (8),
        .DMA_SRC_MEM_BYTES (4096),
        .DMA_DST_MEM_BYTES (4096)
    ) ctrl_vif_t;

    localparam int unsigned DESC_WORD_CONTROL          = 0;
    localparam int unsigned DESC_WORD_BASE_ADDR_A      = 1;
    localparam int unsigned DESC_WORD_BASE_ADDR_B      = 2;
    localparam int unsigned DESC_WORD_BASE_ADDR_C      = 3;
    localparam int unsigned DESC_WORD_DIM_M            = 4;
    localparam int unsigned DESC_WORD_DIM_N            = 5;
    localparam int unsigned DESC_WORD_DIM_K            = 6;
    localparam int unsigned DESC_WORD_A_SRC_BASE       = 7;
    localparam int unsigned DESC_WORD_A_DST_BASE       = 8;
    localparam int unsigned DESC_WORD_A_LOAD_BEATS     = 9;
    localparam int unsigned DESC_WORD_B_SRC_BASE       = 10;
    localparam int unsigned DESC_WORD_B_DST_BASE       = 11;
    localparam int unsigned DESC_WORD_B_LOAD_BEATS     = 12;
    localparam int unsigned DESC_WORD_STORE_SRC_BASE   = 13;
    localparam int unsigned DESC_WORD_STORE_DST_BASE   = 14;
    localparam int unsigned DESC_WORD_STORE_BYTE_COUNT = 15;
    localparam int unsigned DESC_WORD_USER_TAG         = 16;

    localparam logic [31:0] SLOT0_CONTROL_DMA_HOST_READBACK = 32'h0000_0003;
    localparam logic [31:0] SLOT1_CONTROL_DMA_DMA_STORE     = 32'h0000_000B;

    localparam logic [31:0] DESC_FETCH_STATUS_DONE_BIT      = 32'h0000_0002;
    localparam logic [31:0] DESC_FETCH_STATUS_ERR_BIT       = 32'h0000_0004;

    localparam int unsigned P17D_DESC_BASE                  = 32'h0000_0300;
    localparam int unsigned P17D_DESC_STRIDE                = 32'h0000_0080;

    localparam logic [31:0] P17D_DMA_SRC_A_BASE             = 32'h0000_0000;
    localparam logic [31:0] P17D_DMA_SRC_B_BASE             = 32'h0000_0100;
    localparam logic [31:0] P17D_DMA_DST_C_BASE             = 32'h0000_0000;

    ctrl_vif_t p17d_ctrl_vif;

    function new(string name = "ai_accel_subsys_csr_desc_fetch_dma_two_slot_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(ctrl_vif_t)::get(this, "", "vif", p17d_ctrl_vif)) begin
            `uvm_fatal("P17D_DESC_FETCH_DMA/NOVIF", "control vif not found")
        end
    endfunction

    task automatic write_src_word_le(
        input int unsigned byte_addr,
        input logic [31:0] value
    );
    begin
        p17d_ctrl_vif.dma_src_mem[byte_addr + 0] = value[7:0];
        p17d_ctrl_vif.dma_src_mem[byte_addr + 1] = value[15:8];
        p17d_ctrl_vif.dma_src_mem[byte_addr + 2] = value[23:16];
        p17d_ctrl_vif.dma_src_mem[byte_addr + 3] = value[31:24];
    end
    endtask

    task automatic write_desc_word(
        input int unsigned desc_base,
        input int unsigned word_idx,
        input logic [31:0] value
    );
    begin
        write_src_word_le(desc_base + (word_idx * 4), value);
    end
    endtask

    task automatic program_memory_descriptor(
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

        write_desc_word(desc_base, DESC_WORD_A_SRC_BASE,       P17D_DMA_SRC_A_BASE);
        write_desc_word(desc_base, DESC_WORD_A_DST_BASE,       profile_item.base_addr_a);
        write_desc_word(desc_base, DESC_WORD_A_LOAD_BEATS,     32'(a_beats));

        write_desc_word(desc_base, DESC_WORD_B_SRC_BASE,       P17D_DMA_SRC_B_BASE);
        write_desc_word(desc_base, DESC_WORD_B_DST_BASE,       profile_item.base_addr_b);
        write_desc_word(desc_base, DESC_WORD_B_LOAD_BEATS,     32'(b_beats));

        write_desc_word(desc_base, DESC_WORD_STORE_SRC_BASE,   profile_item.base_addr_c);
        write_desc_word(desc_base, DESC_WORD_STORE_DST_BASE,   P17D_DMA_DST_C_BASE);
        write_desc_word(desc_base, DESC_WORD_STORE_BYTE_COUNT, 32'(c_bytes));
        write_desc_word(desc_base, DESC_WORD_USER_TAG,         user_tag);

        `uvm_info("P17D_DESC_FETCH_DMA",
            $sformatf("Programmed memory descriptor at 0x%08h: control=0x%08h A_bytes=%0d B_bytes=%0d C_bytes=%0d tag=0x%08h dim=(%0d,%0d,%0d)",
                desc_base,
                slot_control,
                a_bytes,
                b_bytes,
                c_bytes,
                user_tag,
                profile_item.dim_m,
                profile_item.dim_n,
                profile_item.dim_k),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_desc_fetch_clear_sticky_status();
        logic [31:0] clear_cmd;
    begin
        clear_cmd = 32'h0000_0000;
        clear_cmd[ai_accel_csr_access_helper::DESC_FETCH_CMD_CLEAR_DONE]  = 1'b1;
        clear_cmd[ai_accel_csr_access_helper::DESC_FETCH_CMD_CLEAR_ERROR] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DESC_FETCH_COMMAND,
            clear_cmd
        );
    end
    endtask

    task automatic csr_start_desc_fetch_recipe(
        input int unsigned desc_base,
        input int unsigned desc_count,
        input int unsigned desc_stride
    );
        logic [31:0] cmd;
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DESC_FETCH_BASE_ADDR,
            32'(desc_base)
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DESC_FETCH_COUNT,
            32'(desc_count)
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DESC_FETCH_STRIDE_BYTES,
            32'(desc_stride)
        );

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::DESC_FETCH_CMD_START] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DESC_FETCH_COMMAND,
            cmd
        );

        `uvm_info("P17D_DESC_FETCH_DMA",
            $sformatf("Issued CSR_DESC_FETCH_COMMAND.START_FETCH base=0x%08h count=%0d stride=0x%0h",
                desc_base,
                desc_count,
                desc_stride),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_poll_desc_fetch_done(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] fetched_count;
        logic [31:0] snapshot_status;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_REJECT_STATUS, reject_status);

            if ((status & DESC_FETCH_STATUS_ERR_BIT) ||
                (error_status != 32'h0000_0000) ||
                (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P17D_DESC_FETCH_DMA/FETCH_ERR",
                    $sformatf("Descriptor fetch failed: status=0x%08h error=0x%08h reject=0x%08h",
                        status,
                        error_status,
                        reject_status))
            end

            if (status & DESC_FETCH_STATUS_DONE_BIT) begin
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_DONE_STATUS, done_status);
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_FETCHED_COUNT, fetched_count);
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_SNAPSHOT_STATUS, snapshot_status);

                if (done_status[1:0] != 2'b11) begin
                    `uvm_fatal("P17D_DESC_FETCH_DMA/BAD_FETCH_DONE",
                        $sformatf("Expected DESC_FETCH_DONE_STATUS[1:0]=2'b11, got 0x%08h",
                            done_status))
                end

                if (fetched_count[3:0] != 4'd2) begin
                    `uvm_fatal("P17D_DESC_FETCH_DMA/BAD_FETCH_COUNT",
                        $sformatf("Expected fetched_count=2, got 0x%08h",
                            fetched_count))
                end

                if ((snapshot_status[0] != 1'b1) ||
                    (snapshot_status[7:4] != 4'd2) ||
                    (snapshot_status[11:8] != 4'd2)) begin
                    `uvm_fatal("P17D_DESC_FETCH_DMA/BAD_SNAPSHOT_STATUS",
                        $sformatf("Unexpected snapshot status=0x%08h",
                            snapshot_status))
                end

                `uvm_info("P17D_DESC_FETCH_DMA/FETCH_DONE",
                    $sformatf("Descriptor fetch done after %0d poll(s): status=0x%08h done=0x%08h snapshot=0x%08h",
                        cnt,
                        status,
                        done_status,
                        snapshot_status),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("P17D_DESC_FETCH_DMA/FETCH_TIMEOUT",
                    $sformatf("Timed out waiting for descriptor fetch done after %0d cycles; last status=0x%08h error=0x%08h reject=0x%08h",
                        timeout_cycles,
                        status,
                        error_status,
                        reject_status))
            end
        end
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

        `uvm_info("P17D_DESC_FETCH_DMA/START",
            "Starting P17D CSR descriptor-fetch DMA two-slot recipe smoke test",
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
            `uvm_fatal("P17D_DESC_FETCH_DMA/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(), c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        // Write descriptors after A/B preparation so the descriptor
        // table is not overwritten by the inherited source-memory setup.
        program_memory_descriptor(
            P17D_DESC_BASE + (0 * P17D_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            32'hD17D_0000
        );

        program_memory_descriptor(
            P17D_DESC_BASE + (1 * P17D_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            32'hD17D_0001
        );

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_check_recipe_idle_ready("before descriptor fetch START");

        csr_start_desc_fetch_recipe(P17D_DESC_BASE, 2, P17D_DESC_STRIDE);
        csr_poll_desc_fetch_done(done_timeout_cycles);

        // P17D bridge should have launched the existing P16 recipe path
        // from the fetched snapshot.  Reuse the P16 recipe checker.
        csr_poll_recipe_done(done_timeout_cycles * 2);
        csr_check_recipe_perf_snapshot(profile_item);

        repeat (5) @(posedge csr_vif.clk);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P17D_DESC_FETCH_DMA/PASS",
            $sformatf("P17D descriptor-fetch DMA two-slot recipe completed: CASE_ID=%0d test_kind=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
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
