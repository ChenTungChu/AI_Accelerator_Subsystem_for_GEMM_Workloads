// File: tb/uvm/test/ai_accel_subsys_csr_job_reject_error_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_JOB_REJECT_ERROR_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_JOB_REJECT_ERROR_TEST_SV

// ------------------------------------------------------------
// P15D CSR job-level reject / busy / clear handling smoke
//
// Scope:
//   - validates CSR_JOB_COMMAND.START_JOB reject conditions
//   - validates sticky reject reporting and CLEAR_ERROR behavior
//   - validates START_JOB while job_busy rejection
//   - validates P14 manual micro-op START_* rejection while a P15 job
//     owns the subsystem
//   - completes one valid job after injecting benign reject attempts
//   - validates CLEAR_DONE / CLEAR_ERROR / CLEAR_PERF cleanup
//
// This test intentionally focuses on job-level control-plane corner
// behavior.  It does not modify the datapath, BRAM, GEMM core, or
// DMA engines.
// ------------------------------------------------------------

class ai_accel_subsys_csr_job_reject_error_test extends ai_accel_subsys_csr_job_dma_load_store_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_job_reject_error_test)

    localparam logic [31:0] P15D_JOB_MODE_DMA_LOAD_DMA_STORE       = 32'h0000_0005;
    localparam logic [31:0] P15D_JOB_MODE_UNSUPPORTED_OUTPUT_MODE  = 32'h0000_0009;

    localparam logic [3:0] P15D_JOB_STATE_IDLE  = 4'd0;
    localparam logic [3:0] P15D_JOB_STATE_DONE  = 4'd13;
    localparam logic [3:0] P15D_JOB_STATE_ERROR = 4'd14;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_csr_job_reject_error_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Small assertion helpers
    // ------------------------------------------------------------
    task automatic csr_read_job_sticky(
        output logic [31:0] done_status,
        output logic [31:0] error_status,
        output logic [31:0] reject_status,
        output logic [31:0] state
    );
    begin
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_DONE_STATUS,
            done_status
        );

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_ERROR_STATUS,
            error_status
        );

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS,
            reject_status
        );

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_STATE,
            state
        );
    end
    endtask

    task automatic csr_expect_reject_bit(
        input int unsigned bit_idx,
        input string       tag
    );
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] state;
    begin
        csr_read_job_sticky(done_status, error_status, reject_status, state);

        if (!reject_status[bit_idx]) begin
            `uvm_fatal("CSR_JOB_REJECT/NO_BIT",
                $sformatf("%s: expected reject bit %0d, reject=0x%08h done=0x%08h error=0x%08h state=0x%08h",
                    tag, bit_idx, reject_status, done_status, error_status, state))
        end

        if (error_status != 32'h0000_0000) begin
            `uvm_fatal("CSR_JOB_REJECT/UNEXPECTED_ERROR",
                $sformatf("%s: CSR_JOB_ERROR_STATUS unexpectedly nonzero: error=0x%08h reject=0x%08h state=0x%08h",
                    tag, error_status, reject_status, state))
        end

        `uvm_info("CSR_JOB_REJECT",
            $sformatf("%s: observed expected reject bit %0d, reject=0x%08h state=0x%08h",
                tag, bit_idx, reject_status, state),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_clear_job_sticky_and_expect_idle(input string tag);
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] state;
        logic [31:0] busy_cycles;
        logic [31:0] mac_count;
        logic [31:0] output_count;
        logic [31:0] job_status;
    begin
        csr_job_clear_sticky_status();

        repeat (3) @(posedge csr_vif.clk);

        csr_read_job_sticky(done_status, error_status, reject_status, state);

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_STATUS,
            job_status
        );

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

        if (done_status != 32'h0000_0000) begin
            `uvm_fatal("CSR_JOB_REJECT/CLEAR_DONE",
                $sformatf("%s: done status did not clear: 0x%08h", tag, done_status))
        end

        if (error_status != 32'h0000_0000) begin
            `uvm_fatal("CSR_JOB_REJECT/CLEAR_ERROR",
                $sformatf("%s: error status did not clear: 0x%08h", tag, error_status))
        end

        if (reject_status != 32'h0000_0000) begin
            `uvm_fatal("CSR_JOB_REJECT/CLEAR_REJECT",
                $sformatf("%s: reject status did not clear: 0x%08h", tag, reject_status))
        end

        if (state[3:0] != P15D_JOB_STATE_IDLE) begin
            `uvm_fatal("CSR_JOB_REJECT/CLEAR_STATE",
                $sformatf("%s: expected IDLE after clear, state=0x%08h", tag, state))
        end

        if (job_status[0]) begin
            `uvm_fatal("CSR_JOB_REJECT/CLEAR_BUSY",
                $sformatf("%s: job still busy after clear, status=0x%08h", tag, job_status))
        end

        if ((busy_cycles != 32'h0000_0000) ||
            (mac_count    != 32'h0000_0000) ||
            (output_count != 32'h0000_0000)) begin
            `uvm_fatal("CSR_JOB_REJECT/CLEAR_PERF",
                $sformatf("%s: perf snapshot did not clear: busy=%0d mac=%0d output=%0d",
                    tag, busy_cycles, mac_count, output_count))
        end

        `uvm_info("CSR_JOB_REJECT",
            $sformatf("%s: job sticky status/perf cleared and state returned to IDLE", tag),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_start_expect_reject(
        input int unsigned expected_reject_bit,
        input string       tag
    );
        logic [31:0] cmd;
        logic [31:0] job_status;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::JOB_CMD_START] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_COMMAND,
            cmd
        );

        repeat (2) @(posedge csr_vif.clk);

        csr_expect_reject_bit(expected_reject_bit, tag);

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_STATUS,
            job_status
        );

        if (job_status[0]) begin
            `uvm_fatal("CSR_JOB_REJECT/STARTED_ON_REJECT",
                $sformatf("%s: job became busy even though START_JOB was expected to reject, status=0x%08h",
                    tag, job_status))
        end
    end
    endtask

    task automatic csr_wait_for_job_busy(input int unsigned timeout_cycles);
        logic [31:0] job_status;
        logic [31:0] job_done_status;
        logic [31:0] job_error_status;
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
                ai_accel_csr_access_helper::CSR_JOB_STATE,
                job_state
            );

            if (job_status[0]) begin
                `uvm_info("CSR_JOB_REJECT",
                    $sformatf("Observed job busy before reject injection: status=0x%08h state=0x%08h", job_status, job_state),
                    UVM_MEDIUM)
                return;
            end

            if (job_done_status[ai_accel_csr_access_helper::JOB_DONE]) begin
                `uvm_fatal("CSR_JOB_REJECT/BUSY_WAIT_DONE",
                    $sformatf("Job completed before busy reject could be injected: done=0x%08h status=0x%08h state=0x%08h",
                        job_done_status, job_status, job_state))
            end

            if (job_error_status != 32'h0000_0000) begin
                `uvm_fatal("CSR_JOB_REJECT/BUSY_WAIT_ERROR",
                    $sformatf("Job error before busy reject injection: error=0x%08h status=0x%08h state=0x%08h",
                        job_error_status, job_status, job_state))
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("CSR_JOB_REJECT/BUSY_TIMEOUT",
                    $sformatf("Timed out waiting for job busy: status=0x%08h done=0x%08h error=0x%08h state=0x%08h",
                        job_status, job_done_status, job_error_status, job_state))
            end
        end
    end
    endtask

    task automatic csr_poll_job_done_allow_reject(input int unsigned timeout_cycles);
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
                `uvm_fatal("CSR_JOB_REJECT/JOB_ERROR_STATUS",
                    $sformatf("CSR_JOB_ERROR_STATUS became nonzero: error=0x%08h reject=0x%08h state=0x%08h status=0x%08h",
                        job_error_status, job_reject_status, job_state, job_status))
            end

            if (job_state[3:0] == P15D_JOB_STATE_ERROR) begin
                `uvm_fatal("CSR_JOB_REJECT/JOB_ERROR_STATE",
                    $sformatf("CSR_JOB_STATE reached ERROR: state=0x%08h error=0x%08h reject=0x%08h status=0x%08h",
                        job_state, job_error_status, job_reject_status, job_status))
            end

            if (job_done_status[ai_accel_csr_access_helper::JOB_DONE]) begin
                if (!job_done_status[ai_accel_csr_access_helper::JOB_GEMM_DONE]) begin
                    `uvm_fatal("CSR_JOB_REJECT/NO_GEMM_DONE",
                        $sformatf("JOB_DONE set without JOB_GEMM_DONE: done=0x%08h", job_done_status))
                end

                if (!job_done_status[ai_accel_csr_access_helper::JOB_STORE_DONE]) begin
                    `uvm_fatal("CSR_JOB_REJECT/NO_STORE_DONE",
                        $sformatf("JOB_DONE set without JOB_STORE_DONE: done=0x%08h", job_done_status))
                end

                if (job_state[3:0] != P15D_JOB_STATE_DONE) begin
                    `uvm_fatal("CSR_JOB_REJECT/BAD_DONE_STATE",
                        $sformatf("JOB_DONE set but state is not DONE: done=0x%08h state=0x%08h",
                            job_done_status, job_state))
                end

                `uvm_info("CSR_JOB_REJECT",
                    $sformatf("Observed job completion after reject injection: done=0x%08h reject=0x%08h state=0x%08h polls=%0d",
                        job_done_status, job_reject_status, job_state, cnt),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("CSR_JOB_REJECT/JOB_TIMEOUT",
                    $sformatf("Timed out waiting for job done: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h state=0x%08h",
                        job_status, job_done_status, job_error_status, job_reject_status, job_state))
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // Descriptor reject recipes
    // ------------------------------------------------------------
    task automatic run_descriptor_reject_checks(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
        logic [31:0] cmd;
    begin
        csr_write_job_descriptor(profile_item, a_bytes, b_bytes, c_bytes);

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_DIM_M,
            32'h0000_0000
        );
        csr_start_expect_reject(
            ai_accel_csr_access_helper::JOB_REJ_ZERO_DIM,
            "zero-dimension descriptor"
        );

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::JOB_CMD_START]       = 1'b1;
        cmd[ai_accel_csr_access_helper::JOB_CMD_CLEAR_ERROR] = 1'b1;
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_COMMAND,
            cmd
        );
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_reject_bit(
            ai_accel_csr_access_helper::JOB_REJ_UNSUPPORTED_COMBO,
            "START_JOB plus CLEAR_ERROR while reject sticky"
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_DIM_M,
            32'(profile_item.dim_m)
        );
        csr_clear_job_sticky_and_expect_idle("after zero-dimension / unsupported-combo reject");

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_A_LOAD_BEATS,
            32'h0000_0000
        );
        csr_start_expect_reject(
            ai_accel_csr_access_helper::JOB_REJ_ZERO_A_LENGTH,
            "zero A load length descriptor"
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_A_LOAD_BEATS,
            32'(bytes_to_beats(a_bytes))
        );
        csr_clear_job_sticky_and_expect_idle("after zero A length reject");

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_B_LOAD_BEATS,
            32'h0000_0000
        );
        csr_start_expect_reject(
            ai_accel_csr_access_helper::JOB_REJ_ZERO_B_LENGTH,
            "zero B load length descriptor"
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_B_LOAD_BEATS,
            32'(bytes_to_beats(b_bytes))
        );
        csr_clear_job_sticky_and_expect_idle("after zero B length reject");

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_STORE_BYTE_COUNT,
            32'h0000_0000
        );
        csr_start_expect_reject(
            ai_accel_csr_access_helper::JOB_REJ_ZERO_STORE_LEN,
            "zero store length descriptor"
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_STORE_BYTE_COUNT,
            32'(c_bytes)
        );
        csr_clear_job_sticky_and_expect_idle("after zero store length reject");

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_MODE,
            P15D_JOB_MODE_UNSUPPORTED_OUTPUT_MODE
        );
        csr_start_expect_reject(
            ai_accel_csr_access_helper::JOB_REJ_UNSUPPORTED,
            "unsupported job output mode descriptor"
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_MODE,
            P15D_JOB_MODE_DMA_LOAD_DMA_STORE
        );
        csr_clear_job_sticky_and_expect_idle("after unsupported mode reject");
    end
    endtask

    // ------------------------------------------------------------
    // Busy and manual micro-op reject recipe
    // ------------------------------------------------------------
    task automatic run_busy_reject_and_valid_completion(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes,
        output int signed              actual_c[]
    );
        logic [31:0] cmd;
        int unsigned c_elems;
    begin
        c_elems = c_word_count(profile_item);

        csr_write_job_descriptor(profile_item, a_bytes, b_bytes, c_bytes);
        csr_check_job_idle_ready("before busy reject valid START_JOB");

        csr_start_job();
        csr_wait_for_job_busy(done_timeout_cycles);

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::JOB_CMD_START] = 1'b1;
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_COMMAND,
            cmd
        );
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_reject_bit(
            ai_accel_csr_access_helper::JOB_REJ_BUSY,
            "START_JOB while job_busy"
        );

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_START_GEMM] = 1'b1;
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_COMMAND,
            cmd
        );
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_reject_bit(
            ai_accel_csr_access_helper::JOB_REJ_MANUAL_CMD,
            "P14 manual START_GEMM while P15 job_busy"
        );

        csr_poll_job_done_allow_reject(done_timeout_cycles);
        csr_check_job_perf_snapshot(profile_item);

        repeat (5) @(posedge csr_vif.clk);
        collect_dma_destination_c(c_elems, actual_c);

        csr_clear_job_sticky_and_expect_idle("after completed job with busy/manual rejects");
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

        `uvm_info("CSR_JOB_REJECT",
            "Starting P15D CSR job reject / busy / clear handling smoke test",
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
            `uvm_fatal("CSR_JOB_REJECT/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(), c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_check_job_idle_ready("initial P15D state");

        run_descriptor_reject_checks(
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        run_busy_reject_and_valid_completion(
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            actual_c
        );

        compare_result_vectors(expected_c, actual_c);

        `uvm_info("CSR_JOB_REJECT",
            $sformatf("P15D CSR job reject / busy / clear handling smoke completed: CASE_ID=%0d test_kind=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
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
