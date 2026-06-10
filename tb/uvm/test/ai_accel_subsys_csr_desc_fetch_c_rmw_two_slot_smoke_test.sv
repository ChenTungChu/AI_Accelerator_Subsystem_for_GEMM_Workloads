// File: tb/uvm/test/ai_accel_subsys_csr_desc_fetch_c_rmw_two_slot_smoke_test.sv
// ============================================================
// P17E CSR descriptor-fetch -> P16 C RMW recipe bridge smoke
//
// Scope:
//   - Reuses the existing CSR UVM top and run_uvm.tcl flow.
//   - Builds a P13 C read-modify-write partial-K recipe.
//   - Writes two memory-resident descriptors into the descriptor
//     table region of the existing source memory model.
//   - Issues CSR_DESC_FETCH_COMMAND.START_FETCH.
//   - P17 bridge launches the existing P16 recipe sequencer from
//     the fetched snapshot.
//   - The existing P16/P15 path dispatches:
//       slot0: DMA_LOAD -> GEMM -> HOST_READBACK, accumulate=0
//       slot1: DMA_LOAD -> GEMM -> DMA_STORE,    accumulate=1
//   - Final accumulated C is compared against the full-K software
//     reference in DMA destination memory.
//
// This test intentionally validates the fetched-descriptor bridge
// with the existing P13/P16 C RMW recipe flow, without adding a
// standalone desc_fetch TB or a new run script.
// ============================================================

`ifndef AI_ACCEL_SUBSYS_CSR_DESC_FETCH_C_RMW_TWO_SLOT_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_DESC_FETCH_C_RMW_TWO_SLOT_SMOKE_TEST_SV

class ai_accel_subsys_csr_desc_fetch_c_rmw_two_slot_smoke_test
    extends ai_accel_subsys_csr_recipe_c_rmw_two_slot_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_desc_fetch_c_rmw_two_slot_smoke_test)

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

    localparam logic [31:0] DESC_FETCH_STATUS_DONE_BIT = 32'h0000_0002;
    localparam logic [31:0] DESC_FETCH_STATUS_ERR_BIT  = 32'h0000_0004;

    // Keep the descriptor table away from the C RMW A/B source payloads.
    // The inherited C RMW source layout uses 0x000, 0x100, 0x200, and
    // 0x300 for slot0/slot1 A/B payloads, so P17E starts descriptors at 0x800.
    localparam int unsigned P17E_DESC_BASE             = 32'h0000_0800;
    localparam int unsigned P17E_DESC_STRIDE           = 32'h0000_0080;

    function new(string name = "ai_accel_subsys_csr_desc_fetch_c_rmw_two_slot_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic write_src_word_le(
        input int unsigned byte_addr,
        input logic [31:0] value
    );
    begin
        vif.dma_src_mem[byte_addr + 0] = value[7:0];
        vif.dma_src_mem[byte_addr + 1] = value[15:8];
        vif.dma_src_mem[byte_addr + 2] = value[23:16];
        vif.dma_src_mem[byte_addr + 3] = value[31:24];
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

    task automatic program_memory_c_rmw_descriptor(
        input int unsigned             desc_base,
        input logic [31:0]             slot_control,
        input ai_accel_subsys_seq_item job_item,
        input logic [31:0]             a_src_base,
        input logic [31:0]             b_src_base,
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
        write_desc_word(desc_base, DESC_WORD_BASE_ADDR_A,      job_item.base_addr_a);
        write_desc_word(desc_base, DESC_WORD_BASE_ADDR_B,      job_item.base_addr_b);
        write_desc_word(desc_base, DESC_WORD_BASE_ADDR_C,      job_item.base_addr_c);
        write_desc_word(desc_base, DESC_WORD_DIM_M,            32'(job_item.dim_m));
        write_desc_word(desc_base, DESC_WORD_DIM_N,            32'(job_item.dim_n));
        write_desc_word(desc_base, DESC_WORD_DIM_K,            32'(job_item.dim_k));

        write_desc_word(desc_base, DESC_WORD_A_SRC_BASE,       a_src_base);
        write_desc_word(desc_base, DESC_WORD_A_DST_BASE,       job_item.base_addr_a);
        write_desc_word(desc_base, DESC_WORD_A_LOAD_BEATS,     32'(a_beats));

        write_desc_word(desc_base, DESC_WORD_B_SRC_BASE,       b_src_base);
        write_desc_word(desc_base, DESC_WORD_B_DST_BASE,       job_item.base_addr_b);
        write_desc_word(desc_base, DESC_WORD_B_LOAD_BEATS,     32'(b_beats));

        write_desc_word(desc_base, DESC_WORD_STORE_SRC_BASE,   job_item.base_addr_c);
        write_desc_word(desc_base, DESC_WORD_STORE_DST_BASE,   P16D_DMA_DST_C_BASE);
        write_desc_word(desc_base, DESC_WORD_STORE_BYTE_COUNT, 32'(c_bytes));
        write_desc_word(desc_base, DESC_WORD_USER_TAG,         user_tag);

        `uvm_info("P17E_DESC_FETCH_C_RMW",
            $sformatf("Programmed memory C RMW descriptor at 0x%08h: control=0x%08h accum=%0d A src=0x%08h bytes=%0d B src=0x%08h bytes=%0d C dst=0x%08h bytes=%0d tag=0x%08h dim=(%0d,%0d,%0d)",
                desc_base,
                slot_control,
                job_item.accumulate_enable,
                a_src_base,
                a_bytes,
                b_src_base,
                b_bytes,
                P16D_DMA_DST_C_BASE,
                c_bytes,
                user_tag,
                job_item.dim_m,
                job_item.dim_n,
                job_item.dim_k),
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

        `uvm_info("P17E_DESC_FETCH_C_RMW",
            $sformatf("Issued CSR_DESC_FETCH_COMMAND.START_FETCH for C RMW recipe base=0x%08h count=%0d stride=0x%0h",
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
                `uvm_fatal("P17E_DESC_FETCH_C_RMW/FETCH_ERR",
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
                    `uvm_fatal("P17E_DESC_FETCH_C_RMW/BAD_FETCH_DONE",
                        $sformatf("Expected DESC_FETCH_DONE_STATUS[1:0]=2'b11, got 0x%08h",
                            done_status))
                end

                if (fetched_count[3:0] != 4'd2) begin
                    `uvm_fatal("P17E_DESC_FETCH_C_RMW/BAD_FETCH_COUNT",
                        $sformatf("Expected fetched_count=2, got 0x%08h",
                            fetched_count))
                end

                if ((snapshot_status[0] != 1'b1) ||
                    (snapshot_status[7:4] != 4'd2) ||
                    (snapshot_status[11:8] != 4'd2)) begin
                    `uvm_fatal("P17E_DESC_FETCH_C_RMW/BAD_SNAPSHOT_STATUS",
                        $sformatf("Unexpected snapshot status=0x%08h",
                            snapshot_status))
                end

                `uvm_info("P17E_DESC_FETCH_C_RMW/FETCH_DONE",
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
                `uvm_fatal("P17E_DESC_FETCH_C_RMW/FETCH_TIMEOUT",
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
        ai_accel_subsys_seq_item recipe_item;
        ai_accel_subsys_seq_item job0_item;
        ai_accel_subsys_seq_item job1_item;
        int signed               a_full[];
        int signed               b_full[];
        int signed               a0_part[];
        int signed               b0_part[];
        int signed               a1_part[];
        int signed               b1_part[];
        int signed               expected_final_c[];
        int signed               expected_job0_partial_c[];
        int signed               expected_job0_accum_c[];
        int signed               expected_job1_partial_c[];
        int signed               expected_job1_accum_c[];
        int signed               actual_c[];
        int unsigned             c_elems;
        int unsigned             c_bytes;
        int unsigned             job_count;
    begin
        phase.raise_objection(this);

        `uvm_info("P17E_DESC_FETCH_C_RMW/START",
            "Starting P17E CSR descriptor-fetch C RMW two-slot recipe smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        if (!case_helper.is_c_rmw_accum_recipe_case(selected_case_id)) begin
            `uvm_fatal("P17E_DESC_FETCH_C_RMW/BAD_CASE",
                $sformatf("Unsupported P17E C RMW recipe CASE_ID=%0d", selected_case_id))
        end

        case_helper.build_c_rmw_accum_recipe_expected_payload(
            selected_case_id,
            recipe_item,
            a_full,
            b_full,
            expected_final_c
        );

        job_count = case_helper.get_c_rmw_accum_recipe_job_count(selected_case_id);
        if (job_count != 2) begin
            `uvm_fatal("P17E_DESC_FETCH_C_RMW/BAD_JOB_COUNT",
                $sformatf("P17E expects exactly two jobs, but CASE_ID=%0d has job_count=%0d",
                    selected_case_id,
                    job_count))
        end

        case_helper.build_c_rmw_accum_job_payload(
            selected_case_id,
            0,
            job0_item,
            a0_part,
            b0_part,
            expected_job0_partial_c,
            expected_job0_accum_c
        );

        case_helper.build_c_rmw_accum_job_payload(
            selected_case_id,
            1,
            job1_item,
            a1_part,
            b1_part,
            expected_job1_partial_c,
            expected_job1_accum_c
        );

        if (job0_item.accumulate_enable != 1'b0) begin
            `uvm_fatal("P17E_DESC_FETCH_C_RMW/JOB0_ACCUM",
                "job0 must use accumulate_enable=0")
        end

        if (job1_item.accumulate_enable != 1'b1) begin
            `uvm_fatal("P17E_DESC_FETCH_C_RMW/JOB1_ACCUM",
                "job1 must use accumulate_enable=1")
        end

        c_elems = int'(recipe_item.dim_m) * int'(recipe_item.dim_n);
        c_bytes = c_elems * 4;

        if (expected_final_c.size() != c_elems) begin
            `uvm_fatal("P17E_DESC_FETCH_C_RMW/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_final_c.size=%0d c_elems=%0d",
                    expected_final_c.size(),
                    c_elems))
        end

        if (expected_job1_accum_c.size() != expected_final_c.size()) begin
            `uvm_fatal("P17E_DESC_FETCH_C_RMW/ACCUM_SIZE",
                $sformatf("Accumulated final C size mismatch: job1_accum=%0d full_final=%0d",
                    expected_job1_accum_c.size(),
                    expected_final_c.size()))
        end

        compare_result_vectors(expected_final_c, expected_job1_accum_c);

        `uvm_info("P17E_DESC_FETCH_C_RMW",
            $sformatf("Built descriptor-fetch C RMW recipe CASE_ID=%0d dim=(%0d,%0d,%0d) job0_k=%0d accum=%0d job1_k=%0d accum=%0d full_A=%0d full_B=%0d C_words=%0d",
                selected_case_id,
                recipe_item.dim_m,
                recipe_item.dim_n,
                recipe_item.dim_k,
                job0_item.dim_k,
                job0_item.accumulate_enable,
                job1_item.dim_k,
                job1_item.accumulate_enable,
                a_full.size(),
                b_full.size(),
                c_elems),
            UVM_MEDIUM)

        prepare_c_rmw_recipe_dma_sources(a0_part, b0_part, a1_part, b1_part);

        // Write descriptors after A/B preparation so the descriptor
        // table is not overwritten by the inherited source-memory setup.
        program_memory_c_rmw_descriptor(
            P17E_DESC_BASE + (0 * P17E_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            job0_item,
            SLOT0_DMA_SRC_A_BASE,
            SLOT0_DMA_SRC_B_BASE,
            a0_part.size(),
            b0_part.size(),
            c_bytes,
            32'hD17E_0000
        );

        program_memory_c_rmw_descriptor(
            P17E_DESC_BASE + (1 * P17E_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE_ACCUM,
            job1_item,
            SLOT1_DMA_SRC_A_BASE,
            SLOT1_DMA_SRC_B_BASE,
            a1_part.size(),
            b1_part.size(),
            c_bytes,
            32'hD17E_0001
        );

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_check_recipe_idle_ready("before descriptor-fetch C RMW START");

        csr_start_desc_fetch_recipe(P17E_DESC_BASE, 2, P17E_DESC_STRIDE);
        csr_poll_desc_fetch_done(done_timeout_cycles);

        // P17 bridge should have launched the existing P16 recipe path
        // from the fetched C RMW descriptor snapshot. Reuse the P16D
        // recipe checker for C RMW accumulated performance semantics.
        csr_poll_recipe_done(done_timeout_cycles * 4);
        csr_check_c_rmw_recipe_perf_snapshot(recipe_item);

        repeat (5) @(posedge csr_vif.clk);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_final_c, actual_c);

        `uvm_info("P17E_DESC_FETCH_C_RMW/PASS",
            $sformatf("P17E descriptor-fetch C RMW two-slot recipe completed: CASE_ID=%0d slots=2 dim=(%0d,%0d,%0d) job0_k=%0d job1_k=%0d C_words=%0d",
                selected_case_id,
                recipe_item.dim_m,
                recipe_item.dim_n,
                recipe_item.dim_k,
                job0_item.dim_k,
                job1_item.dim_k,
                c_elems),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
