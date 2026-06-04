// File: tb/uvm/test/ai_accel_subsys_csr_recipe_c_rmw_two_slot_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_RECIPE_C_RMW_TWO_SLOT_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_RECIPE_C_RMW_TWO_SLOT_SMOKE_TEST_SV

// ------------------------------------------------------------
// CSR recipe-level C RMW two-slot smoke
//
// Scope:
//   - build a P13 C read-modify-write partial-K recipe
//   - program two P16 recipe descriptor slots
//   - issue CSR_RECIPE_COMMAND.START_RECIPE once
//   - let ai_accel_recipe_sequencer dispatch slot0 then slot1
//     through the existing P15 single-job worker
//   - slot0 runs DMA load A/B -> GEMM, accumulate_enable=0,
//     HOST_READBACK output mode so C remains in scratchpad
//   - slot1 runs DMA load A/B -> GEMM, accumulate_enable=1,
//     DMA_STORE output mode so final accumulated C is stored out
//   - poll recipe-level sticky done/error/reject registers
//   - check recipe-level per-slot masks and accumulated perf
//   - compare destination memory against the full-K software reference
//
// This P16D smoke proves that the P16 recipe runner can convert a
// software-launched P13 two-job partial-K accumulation recipe into one
// hardware START_RECIPE transaction.
// ------------------------------------------------------------

class ai_accel_subsys_csr_recipe_c_rmw_two_slot_smoke_test extends ai_accel_subsys_csr_recipe_dma_two_slot_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_recipe_c_rmw_two_slot_smoke_test)

    localparam logic [31:0] SLOT0_CONTROL_DMA_HOST_READBACK      = 32'h0000_0003;
    localparam logic [31:0] SLOT1_CONTROL_DMA_DMA_STORE_ACCUM    = 32'h0000_002B;
    localparam logic [31:0] RECIPE_CONTROL_TWO_SLOTS_C_RMW       = 32'h0000_0702;

    localparam logic [31:0] SLOT0_DMA_SRC_A_BASE = 32'h0000_0000;
    localparam logic [31:0] SLOT0_DMA_SRC_B_BASE = 32'h0000_0100;
    localparam logic [31:0] SLOT1_DMA_SRC_A_BASE = 32'h0000_0200;
    localparam logic [31:0] SLOT1_DMA_SRC_B_BASE = 32'h0000_0300;
    localparam logic [31:0] P16D_DMA_DST_C_BASE  = 32'h0000_0000;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_csr_recipe_c_rmw_two_slot_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    //
    // This test intentionally bypasses ai_accel_subsys_smoke_test's
    // CASE_ID decoder because P13/P16 C RMW recipe CASE_ID values are
    // 208..212.  The base smoke decoder is for single-job host-primary
    // cases only.
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        int unsigned tmp;
    begin
        if (!uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::get(
                this, "", "vif", vif)) begin
            `uvm_fatal("P16D_C_RMW/NOVIF",
                "virtual interface ai_accel_subsys_ctrl_if is not set")
        end

        if (!uvm_config_db#(axi0_vif_t)::get(this, "", "axi0_vif", axi0_vif)) begin
            `uvm_fatal("P16D_C_RMW/NOAXIVIF",
                "axi0_vif is not set")
        end

        if (!uvm_config_db#(csr_vif_t)::get(this, "", "csr_vif", csr_vif)) begin
            `uvm_fatal("P16D_C_RMW/NOCSRVIF",
                "csr_vif is not set")
        end

        selected_case_id = 208;
        if ($value$plusargs("CASE_ID=%d", tmp)) begin
            if (tmp != 0) begin
                selected_case_id = tmp;
            end
        end

        selected_test_kind = ai_accel_subsys_seq_item::TEST_KIND_C_RMW_ACCUM_RECIPE;

        parse_done_timeout_cycles();

        enable_result_check       = 1'b1;
        force_helper_mem_path     = 1'b0;
        use_host_agent_clear_c    = 1'b0;
        use_host_agent_readback_c = 1'b0;
        use_host_agent_preload_ab = 1'b0;

        `uvm_info("SMOKE_TEST",
            $sformatf("Selected CASE_ID=%0d, inferred test_kind=%0d",
                selected_case_id, selected_test_kind),
            UVM_MEDIUM)

        `uvm_info("SMOKE_TEST",
            $sformatf("enable_result_check=%0d", enable_result_check),
            UVM_MEDIUM)

        `uvm_info("SMOKE_TEST",
            $sformatf("force_helper_mem_path=%0d", force_helper_mem_path),
            UVM_MEDIUM)

        `uvm_info("SMOKE_TEST",
            $sformatf("use_host_agent_clear_c=%0d", use_host_agent_clear_c),
            UVM_MEDIUM)

        `uvm_info("SMOKE_TEST",
            $sformatf("use_host_agent_readback_c=%0d", use_host_agent_readback_c),
            UVM_MEDIUM)

        `uvm_info("SMOKE_TEST",
            $sformatf("use_host_agent_preload_ab=%0d", use_host_agent_preload_ab),
            UVM_MEDIUM)

        uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::set(
            this, "env", "vif", vif);

        uvm_config_db#(axi0_vif_t)::set(
            this, "env", "axi0_vif", axi0_vif);

        uvm_config_db#(int unsigned)::set(
            this, "env.agent.monitor", "selected_case_id", selected_case_id);

        uvm_config_db#(ai_accel_subsys_seq_item::test_kind_e)::set(
            this, "env.agent.monitor", "selected_test_kind", selected_test_kind);

        uvm_config_db#(uvm_active_passive_enum)::set(
            this, "env", "host_is_active", UVM_ACTIVE);

        uvm_config_db#(bit)::set(
            this, "env.scoreboard", "result_check_enable", 1'b0);

        uvm_config_db#(bit)::set(
            this, "env.host_traffic_checker", "enable_check", 1'b0);

        uvm_config_db#(bit)::set(
            this, "env.host_traffic_checker", "strict_check_enable", 1'b0);

        env = ai_accel_subsys_env::type_id::create("env", this);

        case_helper     = ai_accel_subsys_case_helper    ::type_id::create("case_helper");
        axi_host_helper = ai_accel_subsys_axi_host_helper::type_id::create("axi_host_helper");
        csr             = ai_accel_csr_access_helper     ::type_id::create("csr");

        axi_host_helper.set_vif(axi0_vif);
        csr.set_vif(csr_vif);

        apply_csr_focused_report_policy();
    end
    endfunction

    // ------------------------------------------------------------
    // Source/destination memory model preparation
    // ------------------------------------------------------------
    task automatic prepare_c_rmw_recipe_dma_sources(
        input int signed a0_flat[],
        input int signed b0_flat[],
        input int signed a1_flat[],
        input int signed b1_flat[]
    );
    begin
        vif.dma_src_mem_clear();
        vif.dma_dst_mem_clear();

        vif.dma_src_set_rresp_error(1'b0, -1);
        vif.axis_src_set_rresp_error(1'b0, -1);
        vif.ds_src_set_rresp_error(1'b0, -1);
        vif.dma_dst_set_bresp_error(1'b0, -1);

        write_u8_payload_to_dma_src(SLOT0_DMA_SRC_A_BASE, a0_flat);
        write_u8_payload_to_dma_src(SLOT0_DMA_SRC_B_BASE, b0_flat);
        write_u8_payload_to_dma_src(SLOT1_DMA_SRC_A_BASE, a1_flat);
        write_u8_payload_to_dma_src(SLOT1_DMA_SRC_B_BASE, b1_flat);

        `uvm_info("P16D_C_RMW",
            $sformatf("Prepared C RMW recipe DMA sources: slot0 A=0x%08h bytes=%0d B=0x%08h bytes=%0d; slot1 A=0x%08h bytes=%0d B=0x%08h bytes=%0d; dst C=0x%08h",
                SLOT0_DMA_SRC_A_BASE,
                a0_flat.size(),
                SLOT0_DMA_SRC_B_BASE,
                b0_flat.size(),
                SLOT1_DMA_SRC_A_BASE,
                a1_flat.size(),
                SLOT1_DMA_SRC_B_BASE,
                b1_flat.size(),
                P16D_DMA_DST_C_BASE),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // P16 recipe slot writer with per-slot source addresses.
    // ------------------------------------------------------------
    task automatic csr_write_c_rmw_recipe_slot(
        input int unsigned             slot_idx,
        input logic [31:0]             slot_control,
        input ai_accel_subsys_seq_item job_item,
        input logic [31:0]             a_src_base,
        input logic [31:0]             b_src_base,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes,
        input logic [31:0]             user_tag
    );
        logic [11:0] slot_base;
        int unsigned a_beats;
        int unsigned b_beats;
    begin
        slot_base = csr.recipe_slot_addr(slot_idx, 7'h00);
        a_beats  = bytes_to_beats(a_bytes);
        b_beats  = bytes_to_beats(b_bytes);

        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_CONTROL, slot_control);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_BASE_ADDR_A, job_item.base_addr_a);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_BASE_ADDR_B, job_item.base_addr_b);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_BASE_ADDR_C, job_item.base_addr_c);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_DIM_M, 32'(job_item.dim_m));
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_DIM_N, 32'(job_item.dim_n));
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_DIM_K, 32'(job_item.dim_k));

        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_A_SRC_BASE, a_src_base);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_A_DST_BASE, job_item.base_addr_a);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_A_LOAD_BEATS, 32'(a_beats));

        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_B_SRC_BASE, b_src_base);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_B_DST_BASE, job_item.base_addr_b);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_B_LOAD_BEATS, 32'(b_beats));

        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_STORE_SRC_BASE, job_item.base_addr_c);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_STORE_DST_BASE, P16D_DMA_DST_C_BASE);
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_STORE_BYTE_COUNT, 32'(c_bytes));
        csr.write32_expect_okay(slot_base + ai_accel_csr_access_helper::SLOT_USER_TAG, user_tag);

        csr.expect_read32(slot_base + ai_accel_csr_access_helper::SLOT_CONTROL, slot_control, "SLOT_CONTROL");
        csr.expect_read32(slot_base + ai_accel_csr_access_helper::SLOT_DIM_M, 32'(job_item.dim_m), "SLOT_DIM_M");
        csr.expect_read32(slot_base + ai_accel_csr_access_helper::SLOT_DIM_N, 32'(job_item.dim_n), "SLOT_DIM_N");
        csr.expect_read32(slot_base + ai_accel_csr_access_helper::SLOT_DIM_K, 32'(job_item.dim_k), "SLOT_DIM_K");
        csr.expect_read32(slot_base + ai_accel_csr_access_helper::SLOT_A_LOAD_BEATS, 32'(a_beats), "SLOT_A_LOAD_BEATS");
        csr.expect_read32(slot_base + ai_accel_csr_access_helper::SLOT_B_LOAD_BEATS, 32'(b_beats), "SLOT_B_LOAD_BEATS");
        csr.expect_read32(slot_base + ai_accel_csr_access_helper::SLOT_STORE_BYTE_COUNT, 32'(c_bytes), "SLOT_STORE_BYTE_COUNT");

        `uvm_info("P16D_C_RMW",
            $sformatf("Programmed C RMW recipe slot%0d: control=0x%08h accum=%0d A src=0x%08h dst=0x%08h beats=%0d B src=0x%08h dst=0x%08h beats=%0d C src=0x%08h dst=0x%08h bytes=%0d tag=0x%08h dim=(%0d,%0d,%0d)",
                slot_idx,
                slot_control,
                job_item.accumulate_enable,
                a_src_base,
                job_item.base_addr_a,
                a_beats,
                b_src_base,
                job_item.base_addr_b,
                b_beats,
                job_item.base_addr_c,
                P16D_DMA_DST_C_BASE,
                c_bytes,
                user_tag,
                job_item.dim_m,
                job_item.dim_n,
                job_item.dim_k),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_write_c_rmw_recipe_control();
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_RECIPE_CONTROL,
            RECIPE_CONTROL_TWO_SLOTS_C_RMW
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_RECIPE_CONTROL,
            RECIPE_CONTROL_TWO_SLOTS_C_RMW,
            "CSR_RECIPE_CONTROL"
        );
    end
    endtask

    task automatic csr_check_c_rmw_recipe_perf_snapshot(
        input ai_accel_subsys_seq_item recipe_item
    );
        logic [31:0] busy_cycles;
        logic [31:0] mac_count;
        logic [31:0] output_count;
        int unsigned expected_macs;
        int unsigned expected_outputs;
    begin
        expected_macs    = int'(recipe_item.dim_m) * int'(recipe_item.dim_n) * int'(recipe_item.dim_k);
        expected_outputs = 2 * int'(recipe_item.dim_m) * int'(recipe_item.dim_n);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_PERF_BUSY_CYCLES, busy_cycles);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_PERF_MAC_COUNT, mac_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_PERF_OUTPUT_COUNT, output_count);

        if (busy_cycles == 32'h0000_0000) begin
            `uvm_fatal("P16D_C_RMW/PERF_BUSY_ZERO",
                "CSR_RECIPE_PERF_BUSY_CYCLES stayed zero after completed C RMW recipe")
        end

        if (mac_count != 32'(expected_macs)) begin
            `uvm_fatal("P16D_C_RMW/PERF_MAC",
                $sformatf("CSR_RECIPE_PERF_MAC_COUNT mismatch: expected=%0d actual=%0d",
                    expected_macs,
                    mac_count))
        end

        if (output_count != 32'(expected_outputs)) begin
            `uvm_fatal("P16D_C_RMW/PERF_OUTPUT",
                $sformatf("CSR_RECIPE_PERF_OUTPUT_COUNT mismatch: expected=%0d actual=%0d",
                    expected_outputs,
                    output_count))
        end

        `uvm_info("P16D_C_RMW",
            $sformatf("CSR C RMW recipe perf snapshot PASS: busy_cycles=%0d mac_count=%0d output_count=%0d",
                busy_cycles,
                mac_count,
                output_count),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Run phase
    // ------------------------------------------------------------
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

        `uvm_info("P16D_C_RMW",
            "Starting CSR recipe-level C RMW two-slot smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        if (!case_helper.is_c_rmw_accum_recipe_case(selected_case_id)) begin
            `uvm_fatal("P16D_C_RMW/BAD_CASE",
                $sformatf("Unsupported P16D C RMW recipe CASE_ID=%0d", selected_case_id))
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
            `uvm_fatal("P16D_C_RMW/BAD_JOB_COUNT",
                $sformatf("P16D expects exactly two jobs, but CASE_ID=%0d has job_count=%0d",
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
            `uvm_fatal("P16D_C_RMW/JOB0_ACCUM",
                "job0 must use accumulate_enable=0")
        end

        if (job1_item.accumulate_enable != 1'b1) begin
            `uvm_fatal("P16D_C_RMW/JOB1_ACCUM",
                "job1 must use accumulate_enable=1")
        end

        c_elems = int'(recipe_item.dim_m) * int'(recipe_item.dim_n);
        c_bytes = c_elems * 4;

        if (expected_final_c.size() != c_elems) begin
            `uvm_fatal("P16D_C_RMW/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_final_c.size=%0d c_elems=%0d",
                    expected_final_c.size(),
                    c_elems))
        end

        if (expected_job1_accum_c.size() != expected_final_c.size()) begin
            `uvm_fatal("P16D_C_RMW/ACCUM_SIZE",
                $sformatf("Accumulated final C size mismatch: job1_accum=%0d full_final=%0d",
                    expected_job1_accum_c.size(),
                    expected_final_c.size()))
        end

        compare_result_vectors(expected_final_c, expected_job1_accum_c);

        `uvm_info("P16D_C_RMW",
            $sformatf("Built C RMW recipe CASE_ID=%0d dim=(%0d,%0d,%0d) job0_k=%0d accum=%0d job1_k=%0d accum=%0d full_A=%0d full_B=%0d C_words=%0d",
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

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_check_recipe_idle_ready("before C RMW START_RECIPE");

        csr_write_c_rmw_recipe_slot(
            0,
            SLOT0_CONTROL_DMA_HOST_READBACK,
            job0_item,
            SLOT0_DMA_SRC_A_BASE,
            SLOT0_DMA_SRC_B_BASE,
            a0_part.size(),
            b0_part.size(),
            c_bytes,
            32'h0000_16D0
        );

        csr_write_c_rmw_recipe_slot(
            1,
            SLOT1_CONTROL_DMA_DMA_STORE_ACCUM,
            job1_item,
            SLOT1_DMA_SRC_A_BASE,
            SLOT1_DMA_SRC_B_BASE,
            a1_part.size(),
            b1_part.size(),
            c_bytes,
            32'h0000_16D1
        );

        csr_write_c_rmw_recipe_control();
        csr_start_recipe();
        csr_poll_recipe_done(done_timeout_cycles * 4);
        csr_check_c_rmw_recipe_perf_snapshot(recipe_item);

        repeat (5) @(posedge csr_vif.clk);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_final_c, actual_c);

        `uvm_info("P16D_C_RMW",
            $sformatf("CSR recipe-level C RMW two-slot smoke completed: CASE_ID=%0d slots=2 dim=(%0d,%0d,%0d) job0_k=%0d job1_k=%0d C_words=%0d",
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
