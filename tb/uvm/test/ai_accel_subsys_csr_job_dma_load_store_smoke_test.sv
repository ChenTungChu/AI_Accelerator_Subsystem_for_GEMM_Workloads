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
    localparam logic [31:0] JOB_MODE_AXIS_DMA_STORE     = 32'h0000_0006;
    localparam logic [31:0] JOB_MODE_DS_DMA_STORE       = 32'h0000_0007;

    localparam int unsigned C1D2_P14_ERR_AXIS_LOAD  = 1;
    localparam int unsigned C1D2_P14_ERR_DS_LOAD    = 2;
    localparam int unsigned C1D2_P14_ERR_DMA_STORE  = 3;
    localparam int unsigned C1D2_JOB_ERR_AXIS_LOAD  = 1;
    localparam int unsigned C1D2_JOB_ERR_DS_LOAD    = 2;
    localparam int unsigned C1D2_JOB_ERR_DMA_STORE  = 3;

    localparam int unsigned C1D2_P14_STATUS_AXIS_LOAD_BUSY = 2;
    localparam int unsigned C1D2_P14_STATUS_DS_LOAD_BUSY   = 3;
    localparam int unsigned C1D2_P14_STATUS_DMA_STORE_BUSY = 4;

    localparam int unsigned C1_2C_P14_ERR_DMA_LOAD          = 0;
    localparam int unsigned C1_2C_JOB_ERR_DMA_LOAD          = 0;
    localparam int unsigned C1_2C_P14_STATUS_DMA_LOAD_BUSY  = 1;

    localparam int unsigned C1_2C_B_FAULT_DMA_LOAD = 0;
    localparam int unsigned C1_2C_B_FAULT_AXIS     = 1;
    localparam int unsigned C1_2C_B_FAULT_DS       = 2;

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
    task automatic csr_write_job_descriptor_mode(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes,
        input logic [31:0]             job_mode_value
    );
        int unsigned a_beats;
        int unsigned b_beats;
    begin
        a_beats = bytes_to_beats(a_bytes);
        b_beats = bytes_to_beats(b_bytes);

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_JOB_MODE,
            job_mode_value
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
            job_mode_value,
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
                job_mode_value,
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


    // Preserve the original test API for all existing derived users.
    task automatic csr_write_job_descriptor(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
    begin
        csr_write_job_descriptor_mode(
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            JOB_MODE_DMA_LOAD_DMA_STORE
        );
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

    // ------------------------------------------------------------
    // CODE-COV-C1.1-D2 P15 genuine worker-error propagation
    // ------------------------------------------------------------
    task automatic csr_poll_d2_job_error(
        input int unsigned timeout_cycles,
        input int unsigned job_error_bit,
        input int unsigned p14_error_bit,
        input string       tag,
        output logic [31:0] observed_job_error,
        output logic [31:0] observed_p14_error
    );
        logic [31:0] job_status;
        logic [31:0] job_reject;
        logic [31:0] job_state;
        logic [31:0] p14_reject;
        logic [31:0] expected_job_error;
        logic [31:0] expected_p14_error;
        int unsigned cnt;
    begin
        expected_job_error = 32'h0000_0001 << job_error_bit;
        expected_p14_error = 32'h0000_0001 << p14_error_bit;
        observed_job_error = 32'h0000_0000;
        observed_p14_error = 32'h0000_0000;
        cnt = 0;

        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_STATUS, job_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_ERROR_STATUS, observed_job_error);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS, job_reject);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_STATE, job_state);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, observed_p14_error);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, p14_reject);

            if ((job_reject != 32'h0000_0000) || (p14_reject != 32'h0000_0000)) begin
                `uvm_fatal("CODE_COV_C1D2/P15_UNEXPECTED_REJECT",
                    $sformatf("%s: unexpected reject during genuine worker error: job_reject=0x%08h p14_reject=0x%08h state=0x%08h",
                        tag, job_reject, p14_reject, job_state))
            end

            if ((observed_job_error != 32'h0000_0000) &&
                (observed_job_error != expected_job_error)) begin
                `uvm_fatal("CODE_COV_C1D2/P15_BAD_JOB_ERROR",
                    $sformatf("%s: unexpected JOB_ERROR_STATUS: expected=0x%08h actual=0x%08h state=0x%08h",
                        tag, expected_job_error, observed_job_error, job_state))
            end

            if ((observed_p14_error != 32'h0000_0000) &&
                (observed_p14_error != expected_p14_error)) begin
                `uvm_fatal("CODE_COV_C1D2/P15_BAD_P14_ERROR",
                    $sformatf("%s: unexpected P14 ERROR_STATUS: expected=0x%08h actual=0x%08h state=0x%08h",
                        tag, expected_p14_error, observed_p14_error, job_state))
            end

            if ((observed_job_error == expected_job_error) &&
                (observed_p14_error == expected_p14_error)) begin
                if (job_state[3:0] != JOB_STATE_ERROR) begin
                    `uvm_fatal("CODE_COV_C1D2/P15_BAD_ERROR_STATE",
                        $sformatf("%s: sticky worker error observed but JOB_STATE is not ERROR: state=0x%08h status=0x%08h",
                            tag, job_state, job_status))
                end
                if (job_status[0]) begin
                    `uvm_fatal("CODE_COV_C1D2/P15_BUSY_IN_ERROR",
                        $sformatf("%s: JOB_STATUS.BUSY remained set in ERROR state: status=0x%08h state=0x%08h",
                            tag, job_status, job_state))
                end
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1D2/P15_ERROR_TIMEOUT",
                    $sformatf("%s: timeout waiting for job/P14 error propagation after %0d cycles; job_error=0x%08h p14_error=0x%08h state=0x%08h",
                        tag, timeout_cycles, observed_job_error, observed_p14_error, job_state))
            end
        end
    end
    endtask

    task automatic csr_wait_d2_job_idle_ready(
        input int unsigned timeout_cycles,
        input string       tag
    );
        logic [31:0] job_status;
        logic [31:0] job_error;
        logic [31:0] job_reject;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_STATUS, job_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_ERROR_STATUS, job_error);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS, job_reject);

            if ((job_error != 32'h0000_0000) || (job_reject != 32'h0000_0000)) begin
                `uvm_fatal("CODE_COV_C1D2/P15_IDLE_STICKY",
                    $sformatf("%s: sticky job status remained while waiting for JOB_ACCEPT_READY: error=0x%08h reject=0x%08h status=0x%08h",
                        tag, job_error, job_reject, job_status))
            end

            if (job_status[3]) begin
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1D2/P15_IDLE_TIMEOUT",
                    $sformatf("%s: timeout waiting for JOB_ACCEPT_READY after %0d cycles; status=0x%08h",
                        tag, timeout_cycles, job_status))
            end
        end
    end
    endtask

    task automatic csr_clear_d2_job_error_for_recovery(
        input string       tag,
        input logic [31:0] expected_p14_error
    );
        logic [31:0] job_error;
        logic [31:0] job_reject;
        logic [31:0] p14_error;
        logic [31:0] p14_reject;
    begin
        // The P15 error outputs are one-cycle pulses and JOB_CLEAR_ERROR also
        // moves the sequencer from ERROR back to IDLE.  The underlying P14
        // worker error, however, is level-held until that worker is started
        // again, so do not require P14 ERROR_STATUS to clear yet.
        csr_job_clear_sticky_status();
        repeat (3) @(posedge csr_vif.clk);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_ERROR_STATUS, job_error);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS, job_reject);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, p14_error);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, p14_reject);

        if ((job_error != 32'h0000_0000) || (job_reject != 32'h0000_0000) ||
            (p14_reject != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1D2/P15_JOB_CLEAR",
                $sformatf("%s: P15 cleanup failed before recovery: job_error=0x%08h job_reject=0x%08h p14_reject=0x%08h",
                    tag, job_error, job_reject, p14_reject))
        end

        if (p14_error != expected_p14_error) begin
            `uvm_fatal("CODE_COV_C1D2/P15_P14_HOLD",
                $sformatf("%s: expected underlying P14 worker error to remain level-held until re-arm: expected=0x%08h actual=0x%08h",
                    tag, expected_p14_error, p14_error))
        end

        csr_wait_d2_job_idle_ready(done_timeout_cycles, {tag, " post-job-clear"});
    end
    endtask

    task automatic run_d2_p14_worker_rearm(
        input ai_accel_subsys_seq_item profile_item,
        input int signed               a_flat[],
        input int unsigned             c_bytes,
        input int unsigned             p14_error_bit,
        input int unsigned             worker_busy_bit,
        input string                   tag
    );
        int unsigned a_beats;
        int unsigned cnt;
        logic [31:0] cmd;
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] p14_error;
        logic [31:0] p14_reject;
        logic [31:0] expected_p14_error;
    begin
        a_beats            = bytes_to_beats(a_flat.size());
        expected_p14_error = 32'h0000_0001 << p14_error_bit;

        // A worker-level P14 error remains asserted until that worker accepts
        // a new start.  Starting the same worker through P15 is not a safe
        // re-arm path: on the first WAIT cycle the job sequencer can sample
        // the old level-held error in the same cycle that the worker consumes
        // its start pulse.  Re-arm the worker through the existing idle P14
        // debug/control path first, then launch the clean P15 recovery job.
        //
        // Clear only stale DONE/REJECT state before the P14 re-arm.  Keep the
        // genuine P14 ERROR sticky set until after the worker has accepted the
        // new start so the test proves source-drain/re-arm semantics.
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DONE_STATUS,
            32'hFFFF_FFFF
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS,
            32'hFFFF_FFFF
        );
        repeat (2) @(posedge csr_vif.clk);

        case (worker_busy_bit)
            C1_2C_P14_STATUS_DMA_LOAD_BUSY: begin
                csr_write_dma_load_config(
                    DMA_SRC_A_BASE,
                    profile_item.base_addr_a,
                    a_beats,
                    {tag, " DMA_LOAD_REARM"}
                );
                csr_start_dma_load({tag, " DMA_LOAD_REARM"});
            end

            C1D2_P14_STATUS_AXIS_LOAD_BUSY: begin
                csr.write32_expect_okay(
                    ai_accel_csr_access_helper::CSR_AXIS_SRC_BASE,
                    DMA_SRC_A_BASE
                );
                csr.write32_expect_okay(
                    ai_accel_csr_access_helper::CSR_AXIS_DST_BASE,
                    profile_item.base_addr_a
                );
                csr.write32_expect_okay(
                    ai_accel_csr_access_helper::CSR_AXIS_LOAD_BEATS,
                    32'(a_beats)
                );

                cmd = 32'h0000_0000;
                cmd[ai_accel_csr_access_helper::CMD_START_AXIS_LOAD] = 1'b1;
                csr.issue_command(cmd);
            end

            C1D2_P14_STATUS_DS_LOAD_BUSY: begin
                csr.write32_expect_okay(
                    ai_accel_csr_access_helper::CSR_DS_SRC_BASE,
                    DMA_SRC_A_BASE
                );
                csr.write32_expect_okay(
                    ai_accel_csr_access_helper::CSR_DS_DST_BASE,
                    profile_item.base_addr_a
                );
                csr.write32_expect_okay(
                    ai_accel_csr_access_helper::CSR_DS_LOAD_BEATS,
                    32'(a_beats)
                );
                csr.write32_expect_okay(
                    ai_accel_csr_access_helper::CSR_DS_CONTROL,
                    32'h0000_0000
                );

                cmd = 32'h0000_0000;
                cmd[ai_accel_csr_access_helper::CMD_START_DS_LOAD] = 1'b1;
                csr.issue_command(cmd);
            end

            C1D2_P14_STATUS_DMA_STORE_BUSY: begin
                csr_write_dma_store_config(
                    profile_item.base_addr_c,
                    DMA_DST_C_BASE,
                    c_bytes
                );
                csr_start_dma_store();
            end

            default: begin
                `uvm_fatal("CODE_COV_C1D2/P15_BAD_REARM_WORKER",
                    $sformatf("%s: unsupported P14 worker busy bit %0d for recovery re-arm",
                        tag, worker_busy_bit))
            end
        endcase

        // The P14 re-arm command must be accepted.  Since one-beat AXIS/DS
        // operations may finish before software observes BUSY, accept either
        // BUSY or the matching DONE bit as proof that the worker consumed the
        // new start.  DONE and BUSY use the same P14 bit number for these
        // four workers (DMA-load=1, AXIS=2, DS=3, DMA-store=4).
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, p14_reject);

            if (p14_reject != 32'h0000_0000) begin
                `uvm_fatal("CODE_COV_C1D2/P15_P14_REARM_REJECT",
                    $sformatf("%s: P14 worker re-arm command rejected: status=0x%08h done=0x%08h reject=0x%08h",
                        tag, status, done_status, p14_reject))
            end

            if (status[worker_busy_bit] || done_status[worker_busy_bit]) begin
                break;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1D2/P15_P14_REARM_TIMEOUT",
                    $sformatf("%s: timeout waiting for P14 worker %0d to consume recovery start",
                        tag, worker_busy_bit))
            end
        end

        repeat (2) @(posedge csr_vif.clk);

        // The accepted P14 start has now cleared the worker-level source error.
        // Clear the matching CSR sticky bit and prove it stays low.
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_ERROR_STATUS,
            expected_p14_error
        );
        repeat (2) @(posedge csr_vif.clk);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, p14_error);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, p14_reject);
        if ((p14_error != 32'h0000_0000) || (p14_reject != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1D2/P15_P14_REARM_CLEAR",
                $sformatf("%s: P14 sticky error did not clear after standalone worker re-arm: error=0x%08h reject=0x%08h",
                    tag, p14_error, p14_reject))
        end

        csr_poll_done_bit(
            done_timeout_cycles,
            worker_busy_bit,
            {tag, " P14_REARM"}
        );

        // Drain the temporary P14 DONE state before the actual P15 recovery
        // job so the recovery starts from a clean architectural baseline.
        csr_clear_sticky_status();
        repeat (2) @(posedge csr_vif.clk);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, p14_error);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, p14_reject);
        if ((p14_error != 32'h0000_0000) || (p14_reject != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1D2/P15_P14_REARM_FINAL",
                $sformatf("%s: P14 state not clean after standalone worker re-arm: error=0x%08h reject=0x%08h",
                    tag, p14_error, p14_reject))
        end

        `uvm_info("CODE_COV_C1D2/P15_P14_REARM_PASS",
            $sformatf("%s: standalone P14 worker re-arm PASS for worker bit %0d, cleared error=0x%08h",
                tag, worker_busy_bit, expected_p14_error),
            UVM_MEDIUM)
    end
    endtask

    task automatic run_d2_recovery_job(
        input ai_accel_subsys_seq_item profile_item,
        input int signed               a_flat[],
        input int signed               b_flat[],
        input int signed               expected_c[],
        input int unsigned             c_bytes,
        input logic [31:0]             job_mode_value,
        input int unsigned             p14_error_bit,
        input int unsigned             worker_busy_bit,
        input string                   tag
    );
        int signed   actual_c[];
        int unsigned c_elems;
        logic [31:0] job_error;
        logic [31:0] job_reject;
        logic [31:0] p14_error;
        logic [31:0] p14_reject;
    begin
        c_elems = c_word_count(profile_item);

        prepare_dma_source_and_destination(a_flat, b_flat);
        csr_wait_d2_job_idle_ready(done_timeout_cycles, {tag, " recovery pre-rearm"});

        // First clear the level-held lower worker error through the idle P14
        // control path.  Only after that source is clean is it safe to start a
        // new P15 job using the same worker.
        run_d2_p14_worker_rearm(
            profile_item,
            a_flat,
            c_bytes,
            p14_error_bit,
            worker_busy_bit,
            tag
        );

        csr_wait_d2_job_idle_ready(done_timeout_cycles, {tag, " recovery prestart"});
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_ERROR_STATUS, job_error);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS, job_reject);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, p14_error);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, p14_reject);
        if ((job_error != 32'h0000_0000) || (job_reject != 32'h0000_0000) ||
            (p14_error != 32'h0000_0000) || (p14_reject != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1D2/P15_RECOVERY_PRESTART",
                $sformatf("%s: sticky state not clean before P15 recovery job: job_error=0x%08h job_reject=0x%08h p14_error=0x%08h p14_reject=0x%08h",
                    tag, job_error, job_reject, p14_error, p14_reject))
        end

        csr_write_job_descriptor_mode(
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            job_mode_value
        );
        csr_start_job();
        csr_poll_job_done(done_timeout_cycles);
        csr_check_job_perf_snapshot(profile_item);

        repeat (5) @(posedge csr_vif.clk);
        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        csr_job_clear_sticky_status();
        csr_clear_sticky_status();
        repeat (2) @(posedge csr_vif.clk);
        csr_wait_d2_job_idle_ready(done_timeout_cycles, {tag, " recovery complete"});
    end
    endtask

    task automatic run_d2_job_error_probe(
        input ai_accel_subsys_seq_item profile_item,
        input int signed               a_flat[],
        input int signed               b_flat[],
        input int signed               expected_c[],
        input int unsigned             c_bytes,
        input logic [31:0]             job_mode_value,
        input int unsigned             job_error_bit,
        input int unsigned             p14_error_bit,
        input int unsigned             fault_kind,
        input string                   tag
    );
        logic [31:0] observed_job_error;
        logic [31:0] observed_p14_error;
        logic [31:0] expected_p14_error;
        int unsigned worker_busy_bit;
    begin
        expected_p14_error = 32'h0000_0001 << p14_error_bit;

        prepare_dma_source_and_destination(a_flat, b_flat);
        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        repeat (2) @(posedge csr_vif.clk);
        csr_wait_d2_job_idle_ready(done_timeout_cycles, {tag, " prestart"});

        csr_write_job_descriptor_mode(
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            job_mode_value
        );

        case (fault_kind)
            0: begin
                vif.axis_src_set_rresp_error(1'b1, 0);
                worker_busy_bit = C1D2_P14_STATUS_AXIS_LOAD_BUSY;
            end
            1: begin
                vif.ds_src_set_rresp_error(1'b1, 0);
                worker_busy_bit = C1D2_P14_STATUS_DS_LOAD_BUSY;
            end
            2: begin
                vif.dma_dst_set_bresp_error(1'b1, 0);
                worker_busy_bit = C1D2_P14_STATUS_DMA_STORE_BUSY;
            end
            default: `uvm_fatal("CODE_COV_C1D2/P15_BAD_FAULT_KIND",
                $sformatf("%s: unsupported D2 fault_kind=%0d", tag, fault_kind))
        endcase

        csr_start_job();
        csr_poll_d2_job_error(
            done_timeout_cycles,
            job_error_bit,
            p14_error_bit,
            tag,
            observed_job_error,
            observed_p14_error
        );

        case (fault_kind)
            0: vif.axis_src_set_rresp_error(1'b0, -1);
            1: vif.ds_src_set_rresp_error(1'b0, -1);
            2: vif.dma_dst_set_bresp_error(1'b0, -1);
            default: begin end
        endcase

        csr_clear_d2_job_error_for_recovery(tag, expected_p14_error);
        run_d2_recovery_job(
            profile_item,
            a_flat,
            b_flat,
            expected_c,
            c_bytes,
            job_mode_value,
            p14_error_bit,
            worker_busy_bit,
            tag
        );

        case (fault_kind)
            0: `uvm_info("CODE_COV_C1D2/P15_AXIS_ERROR_PASS",
                    $sformatf("Genuine AXI-Stream worker error propagated through P14/P15 and recovered: p14=0x%08h job=0x%08h",
                        observed_p14_error, observed_job_error), UVM_MEDIUM)
            1: `uvm_info("CODE_COV_C1D2/P15_DS_ERROR_PASS",
                    $sformatf("Genuine Direct-Stream worker error propagated through P14/P15 and recovered: p14=0x%08h job=0x%08h",
                        observed_p14_error, observed_job_error), UVM_MEDIUM)
            2: `uvm_info("CODE_COV_C1D2/P15_DMA_STORE_ERROR_PASS",
                    $sformatf("Genuine DMA-store worker error propagated through P14/P15 and recovered: p14=0x%08h job=0x%08h",
                        observed_p14_error, observed_job_error), UVM_MEDIUM)
            default: begin end
        endcase
    end
    endtask


    // ------------------------------------------------------------
    // CODE-COV-C1.2-C P15 B-preload genuine worker-error propagation
    // ------------------------------------------------------------
    task automatic arm_c1_2c_b_preload_fault_after_a_done(
        input int unsigned fault_kind,
        input string       tag
    );
    begin
        case (fault_kind)
            C1_2C_B_FAULT_DMA_LOAD: begin
                @(posedge vif.dma_load_done);
                vif.dma_src_set_rresp_error(1'b1, 0);
            end

            C1_2C_B_FAULT_AXIS: begin
                @(posedge vif.axis_load_done);
                vif.axis_src_set_rresp_error(1'b1, 0);
            end

            C1_2C_B_FAULT_DS: begin
                @(posedge vif.ds_load_done);
                vif.ds_src_set_rresp_error(1'b1, 0);
            end

            default: begin
                `uvm_fatal("CODE_COV_C1_2C/P15_BAD_B_FAULT_KIND",
                    $sformatf("%s: unsupported C1.2-C B-preload fault_kind=%0d",
                        tag, fault_kind))
            end
        endcase

        `uvm_info("CODE_COV_C1_2C/P15_B_FAULT_ARMED",
            $sformatf("%s: armed relative beat-0 source RRESP error after A-preload completion",
                tag),
            UVM_MEDIUM)
    end
    endtask

    task automatic clear_c1_2c_b_preload_fault(
        input int unsigned fault_kind,
        input string       tag
    );
    begin
        case (fault_kind)
            C1_2C_B_FAULT_DMA_LOAD: vif.dma_src_set_rresp_error(1'b0, -1);
            C1_2C_B_FAULT_AXIS:     vif.axis_src_set_rresp_error(1'b0, -1);
            C1_2C_B_FAULT_DS:       vif.ds_src_set_rresp_error(1'b0, -1);

            default: begin
                `uvm_fatal("CODE_COV_C1_2C/P15_BAD_B_CLEAR_KIND",
                    $sformatf("%s: unsupported C1.2-C B-preload clear fault_kind=%0d",
                        tag, fault_kind))
            end
        endcase
    end
    endtask

    task automatic run_c1_2c_b_preload_error_probe(
        input ai_accel_subsys_seq_item profile_item,
        input int signed               a_flat[],
        input int signed               b_flat[],
        input int signed               expected_c[],
        input int unsigned             c_bytes,
        input logic [31:0]             job_mode_value,
        input int unsigned             job_error_bit,
        input int unsigned             p14_error_bit,
        input int unsigned             worker_busy_bit,
        input int unsigned             fault_kind,
        input string                   tag
    );
        logic [31:0] observed_job_error;
        logic [31:0] observed_p14_error;
        logic [31:0] expected_p14_error;
    begin
        expected_p14_error = 32'h0000_0001 << p14_error_bit;

        prepare_dma_source_and_destination(a_flat, b_flat);
        csr_clear_sticky_status();
        csr_job_clear_sticky_status();

        // Start every probe from a known fault-disabled interface state.
        vif.dma_src_set_rresp_error(1'b0, -1);
        vif.axis_src_set_rresp_error(1'b0, -1);
        vif.ds_src_set_rresp_error(1'b0, -1);

        repeat (2) @(posedge csr_vif.clk);
        csr_wait_d2_job_idle_ready(done_timeout_cycles, {tag, " prestart"});

        csr_write_job_descriptor_mode(
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            job_mode_value
        );

        // The observer is active before START_JOB.  It waits for the genuine
        // A-worker DONE edge, then enables relative beat-0 injection while the
        // sequencer is still traversing LOAD_B_SETUP/LOAD_B_START.  This keeps
        // A preload clean and targets only the B preload transaction.
        fork
            begin
                arm_c1_2c_b_preload_fault_after_a_done(fault_kind, tag);
            end

            begin
                csr_start_job();
            end
        join

        csr_poll_d2_job_error(
            done_timeout_cycles,
            job_error_bit,
            p14_error_bit,
            tag,
            observed_job_error,
            observed_p14_error
        );

        clear_c1_2c_b_preload_fault(fault_kind, tag);

        csr_clear_d2_job_error_for_recovery(tag, expected_p14_error);
        run_d2_recovery_job(
            profile_item,
            a_flat,
            b_flat,
            expected_c,
            c_bytes,
            job_mode_value,
            p14_error_bit,
            worker_busy_bit,
            tag
        );

        case (fault_kind)
            C1_2C_B_FAULT_DMA_LOAD: begin
                `uvm_info("CODE_COV_C1_2C/P15_DMA_B_ERROR_PASS",
                    $sformatf("Genuine DMA B-preload error propagated through P14/P15 and recovered: p14=0x%08h job=0x%08h",
                        observed_p14_error, observed_job_error),
                    UVM_MEDIUM)
            end

            C1_2C_B_FAULT_AXIS: begin
                `uvm_info("CODE_COV_C1_2C/P15_AXIS_B_ERROR_PASS",
                    $sformatf("Genuine AXI-Stream B-preload error propagated through P14/P15 and recovered: p14=0x%08h job=0x%08h",
                        observed_p14_error, observed_job_error),
                    UVM_MEDIUM)
            end

            C1_2C_B_FAULT_DS: begin
                `uvm_info("CODE_COV_C1_2C/P15_DS_B_ERROR_PASS",
                    $sformatf("Genuine Direct-Stream B-preload error propagated through P14/P15 and recovered: p14=0x%08h job=0x%08h",
                        observed_p14_error, observed_job_error),
                    UVM_MEDIUM)
            end

            default: begin end
        endcase
    end
    endtask

    task automatic run_c1_2c_b_preload_error_probes(
        input ai_accel_subsys_seq_item profile_item,
        input int signed               a_flat[],
        input int signed               b_flat[],
        input int signed               expected_c[],
        input int unsigned             c_bytes
    );
    begin
        run_c1_2c_b_preload_error_probe(
            profile_item, a_flat, b_flat, expected_c, c_bytes,
            JOB_MODE_DMA_LOAD_DMA_STORE,
            C1_2C_JOB_ERR_DMA_LOAD,
            C1_2C_P14_ERR_DMA_LOAD,
            C1_2C_P14_STATUS_DMA_LOAD_BUSY,
            C1_2C_B_FAULT_DMA_LOAD,
            "C1_2C_JOB_DMA_B_ERROR"
        );

        run_c1_2c_b_preload_error_probe(
            profile_item, a_flat, b_flat, expected_c, c_bytes,
            JOB_MODE_AXIS_DMA_STORE,
            C1D2_JOB_ERR_AXIS_LOAD,
            C1D2_P14_ERR_AXIS_LOAD,
            C1D2_P14_STATUS_AXIS_LOAD_BUSY,
            C1_2C_B_FAULT_AXIS,
            "C1_2C_JOB_AXIS_B_ERROR"
        );

        run_c1_2c_b_preload_error_probe(
            profile_item, a_flat, b_flat, expected_c, c_bytes,
            JOB_MODE_DS_DMA_STORE,
            C1D2_JOB_ERR_DS_LOAD,
            C1D2_P14_ERR_DS_LOAD,
            C1D2_P14_STATUS_DS_LOAD_BUSY,
            C1_2C_B_FAULT_DS,
            "C1_2C_JOB_DS_B_ERROR"
        );

        // Restore the representative smoke-test memory/fault baseline before
        // the unchanged final DMA job.
        vif.dma_src_set_rresp_error(1'b0, -1);
        vif.axis_src_set_rresp_error(1'b0, -1);
        vif.ds_src_set_rresp_error(1'b0, -1);
        prepare_dma_source_and_destination(a_flat, b_flat);
        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        repeat (2) @(posedge csr_vif.clk);

        `uvm_info("CODE_COV_C1_2C/P15_B_ERROR_SUITE_PASS",
            "P15 DMA, AXI-Stream, and Direct-Stream B-preload genuine worker-error propagation/recovery probes PASS",
            UVM_MEDIUM)
    end
    endtask

    task automatic run_d2_genuine_error_probes(
        input ai_accel_subsys_seq_item profile_item,
        input int signed               a_flat[],
        input int signed               b_flat[],
        input int signed               expected_c[],
        input int unsigned             c_bytes
    );
    begin
        run_d2_job_error_probe(
            profile_item, a_flat, b_flat, expected_c, c_bytes,
            JOB_MODE_AXIS_DMA_STORE,
            C1D2_JOB_ERR_AXIS_LOAD,
            C1D2_P14_ERR_AXIS_LOAD,
            0,
            "D2_JOB_AXIS_ERROR"
        );

        run_d2_job_error_probe(
            profile_item, a_flat, b_flat, expected_c, c_bytes,
            JOB_MODE_DS_DMA_STORE,
            C1D2_JOB_ERR_DS_LOAD,
            C1D2_P14_ERR_DS_LOAD,
            1,
            "D2_JOB_DS_ERROR"
        );

        run_d2_job_error_probe(
            profile_item, a_flat, b_flat, expected_c, c_bytes,
            JOB_MODE_DMA_LOAD_DMA_STORE,
            C1D2_JOB_ERR_DMA_STORE,
            C1D2_P14_ERR_DMA_STORE,
            2,
            "D2_JOB_DMA_STORE_ERROR"
        );

        // Restore the exact original smoke-test memory/fault baseline before
        // running the unchanged representative DMA job below.
        prepare_dma_source_and_destination(a_flat, b_flat);
        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        repeat (2) @(posedge csr_vif.clk);

        `uvm_info("CODE_COV_C1D2/P15_GENUINE_ERROR_SUITE_PASS",
            "P15 AXI-Stream, Direct-Stream, and DMA-store genuine worker-error propagation/recovery probes PASS",
            UVM_MEDIUM)
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

        if ((get_type_name() == "ai_accel_subsys_csr_job_dma_load_store_smoke_test") &&
            (selected_case_id == 102)) begin
            run_d2_genuine_error_probes(
                profile_item,
                a_flat,
                b_flat,
                expected_c,
                c_bytes
            );

            run_c1_2c_b_preload_error_probes(
                profile_item,
                a_flat,
                b_flat,
                expected_c,
                c_bytes
            );
        end

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
