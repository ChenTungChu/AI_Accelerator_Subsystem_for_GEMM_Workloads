// File: tb/uvm/test/ai_accel_subsys_csr_direct_stream_load_store_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_DIRECT_STREAM_LOAD_STORE_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_DIRECT_STREAM_LOAD_STORE_SMOKE_TEST_SV

// ------------------------------------------------------------
// CSR-controlled Direct Stream preload + GEMM + DMA store representative smoke
//
// Scope:
//   - preload A/B into the shared source memory model
//   - use CSR START_DS_LOAD to copy A into the GEMM operand buffer
//   - use CSR START_DS_LOAD to copy B into the GEMM operand buffer
//   - use CSR START_GEMM with GEMM_INPUT_STREAM_MODE=1
//   - use CSR START_DMA_STORE to move C into the destination memory model
//   - compare destination memory against the software reference directly
//
// This focused CSR test intentionally bypasses the legacy sideband
// driver/scoreboard launch path.  Pass/fail is determined by CSR
// command/status sequencing and the final DMA destination memory compare.
// ------------------------------------------------------------

class ai_accel_subsys_csr_direct_stream_load_store_smoke_test extends ai_accel_subsys_csr_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_direct_stream_load_store_smoke_test)

    localparam int unsigned BYTES_PER_BEAT = 8;

    localparam logic OPERAND_A = 1'b0;
    localparam logic OPERAND_B = 1'b1;

    localparam logic [31:0] DS_SRC_A_BASE  = 32'h0000_0000;
    localparam logic [31:0] DS_SRC_B_BASE  = 32'h0000_0100;
    localparam logic [31:0] DMA_DST_C_BASE = 32'h0000_0000;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_csr_direct_stream_load_store_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Size helpers
    // ------------------------------------------------------------
    function automatic int unsigned bytes_to_beats(input int unsigned byte_count);
        if (byte_count == 0) begin
            `uvm_fatal("CSR_DS_SMOKE/ZERO_BYTES",
                "Attempted to convert zero byte_count to Direct Stream preload beats")
        end

        return (byte_count + BYTES_PER_BEAT - 1) / BYTES_PER_BEAT;
    endfunction

    function automatic int unsigned c_word_count(input ai_accel_subsys_seq_item profile_item);
        return int'(profile_item.dim_m) * int'(profile_item.dim_n);
    endfunction

    // ------------------------------------------------------------
    // Case payload builder
    // ------------------------------------------------------------
    task automatic build_selected_payload(
        output ai_accel_subsys_seq_item profile_item,
        output int signed               a_flat[],
        output int signed               b_flat[],
        output int signed               expected_c[]
    );
    begin
        case (selected_test_kind)
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE: begin
                case_helper.build_fixed_case_payload(
                    selected_case_id,
                    profile_item,
                    a_flat,
                    b_flat,
                    expected_c
                );
            end

            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE: begin
                case_helper.build_variable_case_payload(
                    selected_case_id,
                    profile_item,
                    a_flat,
                    b_flat,
                    expected_c
                );
            end

            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE: begin
                case_helper.build_configurable_base_case_payload(
                    selected_case_id,
                    profile_item,
                    a_flat,
                    b_flat,
                    expected_c
                );
            end

            default: begin
                `uvm_fatal("CSR_DS_SMOKE/BAD_KIND",
                    $sformatf("Unsupported CSR Direct Stream load-store smoke test_kind=%0d CASE_ID=%0d",
                        selected_test_kind, selected_case_id))
            end
        endcase
    end
    endtask

    // ------------------------------------------------------------
    // Source/destination memory model preparation
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

    task automatic prepare_direct_stream_source_and_destination(
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

        write_u8_payload_to_shared_src(DS_SRC_A_BASE, a_flat);
        write_u8_payload_to_shared_src(DS_SRC_B_BASE, b_flat);

        `uvm_info("CSR_DS_SMOKE",
            $sformatf("Prepared Direct Stream source payloads: A src=0x%08h bytes=%0d, B src=0x%08h bytes=%0d, dst C base=0x%08h",
                DS_SRC_A_BASE,
                a_flat.size(),
                DS_SRC_B_BASE,
                b_flat.size(),
                DMA_DST_C_BASE),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Generic CSR done polling for non-GEMM operations
    // ------------------------------------------------------------
    task automatic csr_poll_done_bit(
        input int unsigned timeout_cycles,
        input int unsigned done_bit,
        input string       tag
    );
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_DONE_STATUS,
                done_status
            );

            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_ERROR_STATUS,
                error_status
            );

            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS,
                reject_status
            );

            if (error_status != 32'h0000_0000) begin
                `uvm_fatal("CSR_DS_SMOKE/ERROR_STATUS",
                    $sformatf("%s: CSR_ERROR_STATUS became nonzero: 0x%08h",
                        tag, error_status))
            end

            if (reject_status != 32'h0000_0000) begin
                `uvm_fatal("CSR_DS_SMOKE/REJECT_STATUS",
                    $sformatf("%s: CSR_CMD_REJECT_STATUS became nonzero: 0x%08h",
                        tag, reject_status))
            end

            if (done_status[done_bit]) begin
                `uvm_info("CSR_DS_SMOKE",
                    $sformatf("Observed CSR %s done after %0d poll cycle(s): DONE_STATUS=0x%08h",
                        tag, cnt, done_status),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("CSR_DS_SMOKE/DONE_TIMEOUT",
                    $sformatf("Timed out waiting for CSR %s done after %0d cycles",
                        tag, timeout_cycles))
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // CSR Direct Stream preload command sequence
    // ------------------------------------------------------------
    task automatic csr_write_ds_load_config(
        input logic [31:0] src_base,
        input logic [31:0] dst_base,
        input int unsigned beats,
        input logic        operand_sel,
        input string       tag
    );
        logic [31:0] ds_control;
    begin
        ds_control = 32'h0000_0000;
        ds_control[0] = operand_sel;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DS_SRC_BASE,
            src_base
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DS_DST_BASE,
            dst_base
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DS_LOAD_BEATS,
            32'(beats)
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DS_CONTROL,
            ds_control
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DS_SRC_BASE,
            src_base,
            {tag, " CSR_DS_SRC_BASE"}
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DS_DST_BASE,
            dst_base,
            {tag, " CSR_DS_DST_BASE"}
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DS_LOAD_BEATS,
            32'(beats),
            {tag, " CSR_DS_LOAD_BEATS"}
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DS_CONTROL,
            ds_control,
            {tag, " CSR_DS_CONTROL"}
        );

        `uvm_info("CSR_DS_SMOKE",
            $sformatf("Programmed CSR Direct Stream preload %s: operand=%0d src=0x%08h dst=0x%08h beats=%0d",
                tag, operand_sel, src_base, dst_base, beats),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_start_ds_load(input string tag);
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_START_DS_LOAD] = 1'b1;
        csr.issue_command(cmd);

        `uvm_info("CSR_DS_SMOKE",
            $sformatf("Issued CSR START_DS_LOAD command for %s", tag),
            UVM_MEDIUM)
    end
    endtask

    task automatic run_one_ds_load(
        input logic [31:0] src_base,
        input logic [31:0] dst_base,
        input int unsigned byte_count,
        input logic        operand_sel,
        input string       tag
    );
        int unsigned beats;
    begin
        beats = bytes_to_beats(byte_count);

        csr_clear_sticky_status();
        csr_write_ds_load_config(src_base, dst_base, beats, operand_sel, tag);
        csr_start_ds_load(tag);
        csr_poll_done_bit(
            done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_DS_LOAD,
            {"DS_LOAD_", tag}
        );

        repeat (2) @(posedge csr_vif.clk);
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.1-D1 P14 Direct-Stream reject probes
    // ------------------------------------------------------------
    task automatic run_d1_ds_reject_probes(
        input logic [31:0] dst_base
    );
    begin
        csr_clear_sticky_status();

        csr_write_ds_load_config(DS_SRC_A_BASE, dst_base, 0, OPERAND_A, "D1_ZERO_DS");
        csr_start_ds_load("D1_ZERO_DS");
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_p14_reject_bit(C1D1_P14_REJ_ZERO_LENGTH,
            "START_DS_LOAD with zero beats");
        csr_clear_p14_reject_status("after zero-beat Direct Stream load reject");

        csr_write_ds_load_config(DS_SRC_A_BASE, dst_base, 8, OPERAND_A, "D1_BUSY_DS");
        csr_start_ds_load("D1_BUSY_DS");
        csr_wait_p14_status_bit(C1D1_P14_STATUS_DS_LOAD_BUSY,
            done_timeout_cycles, "Direct Stream load before busy-start reject");
        csr_start_ds_load("D1_BUSY_DS_SECOND_START");
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_p14_reject_bit(C1D1_P14_REJ_DS_BUSY,
            "START_DS_LOAD while Direct Stream load busy");
        csr_clear_p14_reject_status("after Direct Stream busy reject");
        csr_poll_done_bit(done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_DS_LOAD,
            "D1_DS_BUSY_OWNER");

        csr_clear_sticky_status();
        `uvm_info("CODE_COV_C1D1/P14_DS_REJECT_PASS",
            "P14 Direct-Stream zero-length and genuine-busy reject probes PASS",
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.1-D2 P14 genuine Direct-Stream source error propagation
    // ------------------------------------------------------------
    task automatic run_d2_ds_error_probe(
        input logic [31:0] dst_base,
        input int unsigned byte_count
    );
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] expected_error;
        logic [31:0] expected_done;
        int unsigned beats;
        int unsigned cnt;
    begin
        beats          = bytes_to_beats(byte_count);
        expected_error = 32'h0000_0001 << 2;
        expected_done  = 32'h0000_0001 << ai_accel_csr_access_helper::DONE_DS_LOAD;

        csr_clear_sticky_status();
        repeat (2) @(posedge csr_vif.clk);

        vif.ds_src_set_rresp_error(1'b1, 0);
        csr_write_ds_load_config(DS_SRC_A_BASE, dst_base, beats, OPERAND_A, "D2_DS_ERROR");
        csr_start_ds_load("D2_DS_ERROR");

        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);

            if (reject_status != 32'h0000_0000) begin
                vif.ds_src_set_rresp_error(1'b0, -1);
                `uvm_fatal("CODE_COV_C1D2/P14_DS_REJECT",
                    $sformatf("Unexpected P14 reject during genuine Direct-Stream RRESP error probe: reject=0x%08h status=0x%08h",
                        reject_status, status))
            end

            if ((error_status != 32'h0000_0000) && (error_status != expected_error)) begin
                vif.ds_src_set_rresp_error(1'b0, -1);
                `uvm_fatal("CODE_COV_C1D2/P14_DS_BAD_ERROR",
                    $sformatf("Unexpected P14 error bits during Direct-Stream RRESP probe: expected=0x%08h actual=0x%08h",
                        expected_error, error_status))
            end

            if (error_status == expected_error) begin
                break;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > done_timeout_cycles) begin
                vif.ds_src_set_rresp_error(1'b0, -1);
                `uvm_fatal("CODE_COV_C1D2/P14_DS_TIMEOUT",
                    $sformatf("Timed out waiting for P14 Direct-Stream error after %0d cycles", done_timeout_cycles))
            end
        end

        vif.ds_src_set_rresp_error(1'b0, -1);

        cnt = 0;
        while (status[C1D1_P14_STATUS_DS_LOAD_BUSY]) begin
            @(posedge csr_vif.clk);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            cnt++;
            if (cnt > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1D2/P14_DS_BUSY_TIMEOUT",
                    "Direct-Stream load engine remained busy after genuine RRESP error")
            end
        end

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DONE_STATUS,
            expected_done
        );

        csr_write_ds_load_config(DS_SRC_A_BASE, dst_base, beats, OPERAND_A, "D2_DS_RECOVERY");
        csr_start_ds_load("D2_DS_RECOVERY");

        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);

            if (reject_status != 32'h0000_0000) begin
                `uvm_fatal("CODE_COV_C1D2/P14_DS_RECOVERY_REJECT",
                    $sformatf("Recovery Direct-Stream start was rejected: reject=0x%08h status=0x%08h",
                        reject_status, status))
            end

            if (status[C1D1_P14_STATUS_DS_LOAD_BUSY] ||
                ((done_status & expected_done) != 32'h0000_0000)) begin
                break;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1D2/P14_DS_RECOVERY_START_TIMEOUT",
                    "Recovery Direct-Stream operation never became active or completed")
            end
        end

        repeat (2) @(posedge csr_vif.clk);
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_ERROR_STATUS,
            expected_error
        );
        repeat (2) @(posedge csr_vif.clk);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);
        if ((error_status != 32'h0000_0000) || (reject_status != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1D2/P14_DS_CLEAR",
                $sformatf("P14 sticky cleanup failed after Direct-Stream recovery re-arm: error=0x%08h reject=0x%08h",
                    error_status, reject_status))
        end

        csr_poll_done_bit(
            done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_DS_LOAD,
            "D2_DS_RECOVERY"
        );
        csr_clear_sticky_status();

        `uvm_info("CODE_COV_C1D2/P14_DS_ERROR_PASS",
            $sformatf("Genuine Direct-Stream source RRESP error propagated to P14 ERROR_STATUS and recovered: observed=0x%08h post_rearm_clear=0x%08h",
                expected_error, error_status),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // CSR GEMM config in Direct Stream input mode
    // ------------------------------------------------------------
    task automatic csr_write_direct_stream_gemm_config(
        input ai_accel_subsys_seq_item profile_item
    );
        logic [31:0] mode_value;
    begin
        mode_value = 32'h0000_0000;
        mode_value[0] = 1'b1;  // Direct Stream A/B operand-buffer input path
        mode_value[1] = profile_item.accumulate_enable;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MODE,
            mode_value
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_A,
            profile_item.base_addr_a
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_B,
            profile_item.base_addr_b
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_C,
            profile_item.base_addr_c
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DIM_M,
            32'(profile_item.dim_m)
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DIM_N,
            32'(profile_item.dim_n)
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DIM_K,
            32'(profile_item.dim_k)
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_MODE,
            mode_value,
            "CSR_MODE"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_A,
            profile_item.base_addr_a,
            "CSR_BASE_ADDR_A"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_B,
            profile_item.base_addr_b,
            "CSR_BASE_ADDR_B"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_C,
            profile_item.base_addr_c,
            "CSR_BASE_ADDR_C"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DIM_M,
            32'(profile_item.dim_m),
            "CSR_DIM_M"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DIM_N,
            32'(profile_item.dim_n),
            "CSR_DIM_N"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DIM_K,
            32'(profile_item.dim_k),
            "CSR_DIM_K"
        );

        `uvm_info("CSR_DS_SMOKE",
            $sformatf("Programmed CSR Direct Stream GEMM config: case_id=%0d base_a=0x%08h base_b=0x%08h base_c=0x%08h dim=(%0d,%0d,%0d) mode=0x%08h",
                profile_item.case_id,
                profile_item.base_addr_a,
                profile_item.base_addr_b,
                profile_item.base_addr_c,
                profile_item.dim_m,
                profile_item.dim_n,
                profile_item.dim_k,
                mode_value),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // CSR DMA store command sequence
    // ------------------------------------------------------------
    task automatic csr_write_dma_store_config(
        input logic [31:0] src_base,
        input logic [31:0] dst_base,
        input int unsigned byte_count
    );
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DMA_STORE_SRC_BASE,
            src_base
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DMA_STORE_DST_BASE,
            dst_base
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DMA_STORE_BYTE_COUNT,
            32'(byte_count)
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DMA_STORE_SRC_BASE,
            src_base,
            "CSR_DMA_STORE_SRC_BASE"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DMA_STORE_DST_BASE,
            dst_base,
            "CSR_DMA_STORE_DST_BASE"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DMA_STORE_BYTE_COUNT,
            32'(byte_count),
            "CSR_DMA_STORE_BYTE_COUNT"
        );

        `uvm_info("CSR_DS_SMOKE",
            $sformatf("Programmed CSR DMA store: src=0x%08h dst=0x%08h bytes=%0d",
                src_base, dst_base, byte_count),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_start_dma_store();
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_START_DMA_STORE] = 1'b1;
        csr.issue_command(cmd);

        `uvm_info("CSR_DS_SMOKE",
            "Issued CSR START_DMA_STORE command",
            UVM_MEDIUM)
    end
    endtask

    task automatic run_dma_store(
        input logic [31:0] src_base,
        input logic [31:0] dst_base,
        input int unsigned byte_count
    );
    begin
        csr_clear_sticky_status();
        csr_write_dma_store_config(src_base, dst_base, byte_count);
        csr_start_dma_store();
        csr_poll_done_bit(
            done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_DMA_STORE,
            "DMA_STORE_C"
        );

        repeat (5) @(posedge csr_vif.clk);
    end
    endtask

    // ------------------------------------------------------------
    // Destination-memory result collection
    // ------------------------------------------------------------
    task automatic collect_dma_destination_c(
        input  int unsigned c_elems,
        output int signed   actual_c[]
    );
    begin
        vif.dma_dst_mem_read_s32_array(
            DMA_DST_C_BASE,
            c_elems,
            actual_c
        );

        `uvm_info("CSR_DS_SMOKE",
            $sformatf("Collected C result from DMA destination memory: base=0x%08h words=%0d",
                DMA_DST_C_BASE, c_elems),
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

        `uvm_info("CSR_DS_SMOKE",
            "Starting CSR-controlled Direct Stream preload + GEMM + DMA store smoke test",
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
            `uvm_fatal("CSR_DS_SMOKE/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(), c_elems))
        end

        prepare_direct_stream_source_and_destination(a_flat, b_flat);

        if ((get_type_name() == "ai_accel_subsys_csr_direct_stream_load_store_smoke_test") &&
            (selected_case_id == 102)) begin
            run_d1_ds_reject_probes(profile_item.base_addr_a);
            run_d2_ds_error_probe(profile_item.base_addr_a, a_flat.size());
        end

        run_one_ds_load(
            DS_SRC_A_BASE,
            profile_item.base_addr_a,
            a_flat.size(),
            OPERAND_A,
            "A"
        );

        run_one_ds_load(
            DS_SRC_B_BASE,
            profile_item.base_addr_b,
            b_flat.size(),
            OPERAND_B,
            "B"
        );

        csr_clear_sticky_status();
        csr_write_direct_stream_gemm_config(profile_item);
        csr_start_gemm();
        csr_poll_gemm_done(done_timeout_cycles);
        csr_check_perf_snapshot();

        run_dma_store(
            profile_item.base_addr_c,
            DMA_DST_C_BASE,
            c_bytes
        );

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("CSR_DS_SMOKE",
            $sformatf("CSR-controlled Direct Stream preload + GEMM + DMA store smoke completed: CASE_ID=%0d test_kind=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
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
