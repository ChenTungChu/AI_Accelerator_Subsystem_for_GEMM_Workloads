// File: tb/uvm/test/ai_accel_subsys_csr_job_dma_load_store_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_JOB_DMA_LOAD_STORE_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_JOB_DMA_LOAD_STORE_SMOKE_TEST_SV

// ------------------------------------------------------------
// CSR job-level DMA load + GEMM + DMA store representative smoke
//
// Scope:
//   - preload A/B into the DMA source memory model
//   - program one P15 CSR job descriptor
//   - issue CSR_JOB_COMMAND.START_JOB once
//   - let ai_accel_job_sequencer run DMA load A, DMA load B,
//     GEMM, and DMA store automatically
//   - poll job-level sticky done/error/reject registers
//   - compare destination memory against the software reference
//
// This focused job-level test intentionally bypasses the legacy
// sideband driver/scoreboard launch path and does not issue P14
// micro-operation START_* commands directly.
// ------------------------------------------------------------

class ai_accel_subsys_csr_job_dma_load_store_smoke_test extends ai_accel_subsys_csr_dma_load_store_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_job_dma_load_store_smoke_test)

    localparam logic [31:0] JOB_MODE_DMA_LOAD_DMA_STORE = 32'h0000_0005;

    localparam logic [3:0] JOB_STATE_DONE  = 4'd13;
    localparam logic [3:0] JOB_STATE_ERROR = 4'd14;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_csr_job_dma_load_store_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Job status helpers
    // ------------------------------------------------------------
    task automatic csr_job_clear_sticky_status();
        logic [31:0] clear_cmd;
    begin
        clear_cmd = 32'h0000_0000;
        clear_cmd[ai_accel_csr_access_helper::JOB_CMD_CLEAR_DONE]  = 1'b1;
        clear_cmd[ai_accel_csr_access_helper::JOB_CMD_CLEAR_ERROR] = 1'b1;
        clear_cmd[ai_accel_csr_access_helper::JOB_CMD_CLEAR_PERF]  = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_COMMAND,
            clear_cmd
        );
    end
    endtask

    task automatic csr_check_job_idle_ready(input string tag);
        logic [31:0] job_status;
        logic [31:0] job_error;
        logic [31:0] job_reject;
    begin
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_STATUS,
            job_status
        );

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_ERROR_STATUS,
            job_error
        );

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS,
            job_reject
        );

        if (job_error != 32'h0000_0000) begin
            `uvm_fatal("CSR_JOB_DMA_SMOKE/JOB_ERROR_PRE",
                $sformatf("%s: CSR_JOB_ERROR_STATUS is nonzero before START_JOB: 0x%08h",
                    tag, job_error))
        end

        if (job_reject != 32'h0000_0000) begin
            `uvm_fatal("CSR_JOB_DMA_SMOKE/JOB_REJECT_PRE",
                $sformatf("%s: CSR_JOB_REJECT_STATUS is nonzero before START_JOB: 0x%08h",
                    tag, job_reject))
        end

        if (!job_status[3]) begin
            `uvm_fatal("CSR_JOB_DMA_SMOKE/NOT_READY",
                $sformatf("%s: CSR_JOB_STATUS.JOB_ACCEPT_READY is low: 0x%08h",
                    tag, job_status))
        end
    end
    endtask

    // ------------------------------------------------------------
    // Job descriptor programming
    // ------------------------------------------------------------
    task automatic csr_write_job_descriptor(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
        int unsigned a_beats;
        int unsigned b_beats;
    begin
        a_beats = bytes_to_beats(a_bytes);
        b_beats = bytes_to_beats(b_bytes);

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_MODE,
            JOB_MODE_DMA_LOAD_DMA_STORE
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
            DMA_SRC_A_BASE
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
            DMA_SRC_B_BASE
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
            DMA_DST_C_BASE
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_STORE_BYTE_COUNT,
            32'(c_bytes)
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_JOB_MODE,
            JOB_MODE_DMA_LOAD_DMA_STORE,
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

        `uvm_info("CSR_JOB_DMA_SMOKE",
            $sformatf("Programmed CSR job descriptor: case_id=%0d mode=0x%08h A src=0x%08h dst=0x%08h beats=%0d B src=0x%08h dst=0x%08h beats=%0d C src=0x%08h dst=0x%08h bytes=%0d dim=(%0d,%0d,%0d)",
                profile_item.case_id,
                JOB_MODE_DMA_LOAD_DMA_STORE,
                DMA_SRC_A_BASE,
                profile_item.base_addr_a,
                a_beats,
                DMA_SRC_B_BASE,
                profile_item.base_addr_b,
                b_beats,
                profile_item.base_addr_c,
                DMA_DST_C_BASE,
                c_bytes,
                profile_item.dim_m,
                profile_item.dim_n,
                profile_item.dim_k),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_start_job();
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::JOB_CMD_START] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_COMMAND,
            cmd
        );

        `uvm_info("CSR_JOB_DMA_SMOKE",
            "Issued CSR_JOB_COMMAND.START_JOB",
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_poll_job_done(input int unsigned timeout_cycles);
        logic [31:0] job_status;
        logic [31:0] job_done_status;
        logic [31:0] job_error_status;
        logic [31:0] job_reject_status;
        logic [31:0] job_state;
        int unsigned cnt;
    begin
        cnt = 0;

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

            if (job_error_status != 32'h0000_0000) begin
                `uvm_fatal("CSR_JOB_DMA_SMOKE/JOB_ERROR_STATUS",
                    $sformatf("CSR_JOB_ERROR_STATUS became nonzero: 0x%08h state=0x%08h status=0x%08h",
                        job_error_status, job_state, job_status))
            end

            if (job_reject_status != 32'h0000_0000) begin
                `uvm_fatal("CSR_JOB_DMA_SMOKE/JOB_REJECT_STATUS",
                    $sformatf("CSR_JOB_REJECT_STATUS became nonzero: 0x%08h state=0x%08h status=0x%08h",
                        job_reject_status, job_state, job_status))
            end

            if (job_state[3:0] == JOB_STATE_ERROR) begin
                `uvm_fatal("CSR_JOB_DMA_SMOKE/JOB_ERROR_STATE",
                    $sformatf("CSR_JOB_STATE reached ERROR without sticky error: state=0x%08h status=0x%08h done=0x%08h",
                        job_state, job_status, job_done_status))
            end

            if (job_done_status[ai_accel_csr_access_helper::JOB_DONE]) begin
                if (!job_done_status[ai_accel_csr_access_helper::JOB_GEMM_DONE]) begin
                    `uvm_fatal("CSR_JOB_DMA_SMOKE/NO_GEMM_DONE",
                        $sformatf("JOB_DONE set without JOB_GEMM_DONE: DONE_STATUS=0x%08h",
                            job_done_status))
                end

                if (!job_done_status[ai_accel_csr_access_helper::JOB_STORE_DONE]) begin
                    `uvm_fatal("CSR_JOB_DMA_SMOKE/NO_STORE_DONE",
                        $sformatf("JOB_DONE set without JOB_STORE_DONE: DONE_STATUS=0x%08h",
                            job_done_status))
                end

                if (job_state[3:0] != JOB_STATE_DONE) begin
                    `uvm_fatal("CSR_JOB_DMA_SMOKE/BAD_DONE_STATE",
                        $sformatf("JOB_DONE set but CSR_JOB_STATE is not DONE: state=0x%08h done=0x%08h",
                            job_state, job_done_status))
                end

                `uvm_info("CSR_JOB_DMA_SMOKE",
                    $sformatf("Observed CSR job done after %0d poll cycle(s): JOB_DONE_STATUS=0x%08h JOB_STATE=0x%08h",
                        cnt, job_done_status, job_state),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("CSR_JOB_DMA_SMOKE/JOB_TIMEOUT",
                    $sformatf("Timed out waiting for CSR job done after %0d cycles; status=0x%08h done=0x%08h error=0x%08h reject=0x%08h state=0x%08h",
                        timeout_cycles,
                        job_status,
                        job_done_status,
                        job_error_status,
                        job_reject_status,
                        job_state))
            end
        end
    end
    endtask

    task automatic csr_check_job_perf_snapshot(
        input ai_accel_subsys_seq_item profile_item
    );
        logic [31:0] busy_cycles;
        logic [31:0] mac_count;
        logic [31:0] output_count;
        int unsigned expected_macs;
        int unsigned expected_outputs;
    begin
        expected_macs    = int'(profile_item.dim_m) * int'(profile_item.dim_n) * int'(profile_item.dim_k);
        expected_outputs = int'(profile_item.dim_m) * int'(profile_item.dim_n);

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_PERF_BUSY_CYCLES,
            busy_cycles
        );

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_PERF_MAC_COUNT,
            mac_count
        );

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_PERF_OUTPUT_COUNT,
            output_count
        );

        if (busy_cycles == 32'h0000_0000) begin
            `uvm_fatal("CSR_JOB_DMA_SMOKE/PERF_BUSY_ZERO",
                "CSR_JOB_PERF_BUSY_CYCLES stayed zero after completed job")
        end

        if (mac_count != 32'(expected_macs)) begin
            `uvm_fatal("CSR_JOB_DMA_SMOKE/PERF_MAC",
                $sformatf("CSR_JOB_PERF_MAC_COUNT mismatch: expected=%0d actual=%0d",
                    expected_macs, mac_count))
        end

        if (output_count != 32'(expected_outputs)) begin
            `uvm_fatal("CSR_JOB_DMA_SMOKE/PERF_OUTPUT",
                $sformatf("CSR_JOB_PERF_OUTPUT_COUNT mismatch: expected=%0d actual=%0d",
                    expected_outputs, output_count))
        end

        `uvm_info("CSR_JOB_DMA_SMOKE",
            $sformatf("CSR job perf snapshot PASS: busy_cycles=%0d mac_count=%0d output_count=%0d",
                busy_cycles, mac_count, output_count),
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

        `uvm_info("CSR_JOB_DMA_SMOKE",
            "Starting CSR job-level DMA load + GEMM + DMA store smoke test",
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
            `uvm_fatal("CSR_JOB_DMA_SMOKE/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(), c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_check_job_idle_ready("before START_JOB");

        csr_write_job_descriptor(
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

        `uvm_info("CSR_JOB_DMA_SMOKE",
            $sformatf("CSR job-level DMA load + GEMM + DMA store smoke completed: CASE_ID=%0d test_kind=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
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
