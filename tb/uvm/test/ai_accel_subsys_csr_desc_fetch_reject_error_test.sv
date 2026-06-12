// File: tb/uvm/test/ai_accel_subsys_csr_desc_fetch_reject_error_test.sv
// ============================================================
// P17G CSR descriptor-fetch reject / busy / malformed descriptor test
//
// Scope:
//   - Reuses the existing CSR UVM top and run_uvm.tcl flow.
//   - Does not add a standalone descriptor-fetch testbench or run script.
//   - Validates START_FETCH command rejects, malformed descriptor errors,
//     descriptor AXI RRESP propagation, manual command interlocks while
//     descriptor fetch is active, and sticky clear / retry recovery.
//
// The final recovery step launches a valid descriptor-fetch two-slot DMA
// recipe and compares the DMA destination C result against the software
// reference.
// ============================================================

`ifndef AI_ACCEL_SUBSYS_CSR_DESC_FETCH_REJECT_ERROR_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_DESC_FETCH_REJECT_ERROR_TEST_SV

class ai_accel_subsys_csr_desc_fetch_reject_error_test
    extends ai_accel_subsys_csr_desc_fetch_dma_two_slot_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_desc_fetch_reject_error_test)

    localparam int unsigned P17G_DESC_BASE          = 32'h0000_0A00;
    localparam int unsigned P17G_DESC_STRIDE        = 32'h0000_0080;
    localparam int unsigned P17G_BAD_DESC_BASE      = 32'h0000_0C00;

    localparam logic [31:0] DESC_FETCH_STATUS_BUSY  = 32'h0000_0001;
    localparam logic [31:0] DESC_FETCH_STATUS_DONE  = 32'h0000_0002;
    localparam logic [31:0] DESC_FETCH_STATUS_ERR   = 32'h0000_0004;

    virtual desc_src_inject_if desc_src_inject_vif;

    function new(string name = "ai_accel_subsys_csr_desc_fetch_reject_error_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual desc_src_inject_if)::get(
                this,
                "",
                "desc_src_inject_vif",
                desc_src_inject_vif
            )) begin
            `uvm_fatal("NO_DESC_SRC_INJECT_VIF",
                "Missing descriptor-source injection virtual interface")
        end
    endfunction

    function automatic logic [31:0] bit_mask(input int bit_idx);
        return (32'h0000_0001 << bit_idx);
    endfunction

    task automatic clear_all_control_status();
    begin
        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
    end
    endtask

    task automatic csr_start_desc_fetch_raw(
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
    end
    endtask

    task automatic wait_desc_fetch_busy(input string tag, input int unsigned timeout_cycles = 100);
        logic [31:0] status;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_STATUS, status);
            if (status & DESC_FETCH_STATUS_BUSY) begin
                `uvm_info("P17G_DESC_FETCH_REJ", $sformatf("%s: descriptor fetch busy observed, status=0x%08h", tag, status), UVM_LOW)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P17G_DESC_FETCH_REJ/BUSY_TIMEOUT",
                    $sformatf("%s: timed out waiting for DESC_FETCH_STATUS.BUSY, last status=0x%08h", tag, status))
            end
        end
    end
    endtask

    task automatic wait_recipe_busy(input string tag, input int unsigned timeout_cycles = 500);
        logic [31:0] status;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_STATUS, status);
            if (status[0]) begin
                `uvm_info("P17G_DESC_FETCH_REJ", $sformatf("%s: recipe busy observed, status=0x%08h", tag, status), UVM_LOW)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P17G_DESC_FETCH_REJ/RECIPE_BUSY_TIMEOUT",
                    $sformatf("%s: timed out waiting for CSR_RECIPE_STATUS.BUSY, last status=0x%08h", tag, status))
            end
        end
    end
    endtask

    task automatic expect_desc_fetch_reject(
        input string       tag,
        input logic [31:0] expected_mask,
        input int unsigned timeout_cycles = 100
    );
        logic [31:0] status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_REJECT_STATUS, reject_status);

            if ((reject_status & expected_mask) == expected_mask) begin
                `uvm_info("P17G_DESC_FETCH_REJ/PASS",
                    $sformatf("%s: observed descriptor-fetch reject mask=0x%08h status=0x%08h reject=0x%08h",
                        tag, expected_mask, status, reject_status),
                    UVM_MEDIUM)
                return;
            end

            if (error_status != 32'h0000_0000) begin
                `uvm_fatal("P17G_DESC_FETCH_REJ/UNEXPECTED_ERROR",
                    $sformatf("%s: expected reject mask=0x%08h but ERROR_STATUS became 0x%08h; status=0x%08h reject=0x%08h",
                        tag, expected_mask, error_status, status, reject_status))
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P17G_DESC_FETCH_REJ/REJECT_TIMEOUT",
                    $sformatf("%s: timed out waiting for reject mask=0x%08h; last status=0x%08h reject=0x%08h error=0x%08h",
                        tag, expected_mask, status, reject_status, error_status))
            end
        end
    end
    endtask

    task automatic expect_desc_fetch_error(
        input string       tag,
        input logic [31:0] expected_error_mask,
        input int unsigned timeout_cycles = 1000
    );
        logic [31:0] status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DESC_FETCH_REJECT_STATUS, reject_status);

            if ((error_status & expected_error_mask) == expected_error_mask) begin
                `uvm_info("P17G_DESC_FETCH_ERR/PASS",
                    $sformatf("%s: observed descriptor-fetch error mask=0x%08h status=0x%08h error=0x%08h reject=0x%08h",
                        tag, expected_error_mask, status, error_status, reject_status),
                    UVM_MEDIUM)
                return;
            end

            if (reject_status != 32'h0000_0000) begin
                `uvm_fatal("P17G_DESC_FETCH_ERR/UNEXPECTED_REJECT",
                    $sformatf("%s: expected error mask=0x%08h but REJECT_STATUS became 0x%08h; status=0x%08h error=0x%08h",
                        tag, expected_error_mask, reject_status, status, error_status))
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P17G_DESC_FETCH_ERR/ERROR_TIMEOUT",
                    $sformatf("%s: timed out waiting for error mask=0x%08h; last status=0x%08h error=0x%08h reject=0x%08h",
                        tag, expected_error_mask, status, error_status, reject_status))
            end
        end
    end
    endtask

    task automatic expect_nonzero_csr(
        input logic [11:0] addr,
        input string       tag
    );
        logic [31:0] data;
    begin
        csr.read32_expect_okay(addr, data);
        if (data == 32'h0000_0000) begin
            `uvm_fatal("P17G_DESC_FETCH_REJ/ZERO_STATUS",
                $sformatf("%s: expected nonzero status at CSR addr=0x%03h", tag, addr))
        end
        `uvm_info("P17G_DESC_FETCH_REJ/PASS",
            $sformatf("%s: observed nonzero CSR status addr=0x%03h data=0x%08h", tag, addr, data),
            UVM_MEDIUM)
    end
    endtask

    task automatic program_good_two_slot_descriptors(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
    begin
        program_memory_descriptor(
            P17G_DESC_BASE + (0 * P17G_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            32'hD17A_0000
        );

        program_memory_descriptor(
            P17G_DESC_BASE + (1 * P17G_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            32'hD17A_0001
        );
    end
    endtask

    task automatic program_single_descriptor(
        input ai_accel_subsys_seq_item profile_item,
        input logic [31:0]             slot_control,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes,
        input logic [31:0]             user_tag
    );
    begin
        program_memory_descriptor(
            P17G_BAD_DESC_BASE,
            slot_control,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            user_tag
        );
    end
    endtask

    task automatic run_start_reject_case(
        input string       tag,
        input int unsigned desc_base,
        input int unsigned desc_count,
        input int unsigned desc_stride,
        input logic [31:0] expected_reject_mask
    );
    begin
        csr_desc_fetch_clear_sticky_status();
        csr_start_desc_fetch_raw(desc_base, desc_count, desc_stride);
        expect_desc_fetch_reject(tag, expected_reject_mask);
        csr_desc_fetch_clear_sticky_status();
    end
    endtask

    task automatic run_malformed_descriptor_case(
        input string                   tag,
        input ai_accel_subsys_seq_item profile_item,
        input logic [31:0]             slot_control,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes,
        input int unsigned             override_word_idx,
        input logic [31:0]             override_value,
        input logic [31:0]             expected_error_mask
    );
    begin
        csr_desc_fetch_clear_sticky_status();
        program_single_descriptor(profile_item, slot_control, a_bytes, b_bytes, c_bytes, 32'hD17B_0000);
        write_desc_word(P17G_BAD_DESC_BASE, override_word_idx, override_value);

        csr_start_desc_fetch_raw(P17G_BAD_DESC_BASE, 1, P17G_DESC_STRIDE);
        expect_desc_fetch_error(tag, expected_error_mask);
        csr_desc_fetch_clear_sticky_status();
    end
    endtask

    task automatic run_desc_rresp_error_case(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
    begin
        csr_desc_fetch_clear_sticky_status();
        program_single_descriptor(profile_item, SLOT0_CONTROL_DMA_HOST_READBACK, a_bytes, b_bytes, c_bytes, 32'hD17C_0000);

        desc_src_inject_vif.set_rresp_error(1'b1, 0);
        csr_start_desc_fetch_raw(P17G_BAD_DESC_BASE, 1, P17G_DESC_STRIDE);
        expect_desc_fetch_error(
            "descriptor AXI RRESP error propagation",
            bit_mask(ai_accel_csr_access_helper::DESC_FETCH_ERR_AXI_RRESP)
        );
        desc_src_inject_vif.set_rresp_error(1'b0, -1);
        csr_desc_fetch_clear_sticky_status();
    end
    endtask

    task automatic run_start_fetch_while_fetch_busy(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
    begin
        clear_all_control_status();
        program_good_two_slot_descriptors(profile_item, a_bytes, b_bytes, c_bytes);

        csr_start_desc_fetch_raw(P17G_DESC_BASE, 2, P17G_DESC_STRIDE);
        wait_desc_fetch_busy("START_FETCH while fetch_busy setup");

        csr_start_desc_fetch_raw(P17G_DESC_BASE, 2, P17G_DESC_STRIDE);
        expect_desc_fetch_reject(
            "START_FETCH while fetch_busy",
            bit_mask(ai_accel_csr_access_helper::DESC_FETCH_REJ_BUSY)
        );

        // Clear only the command-level reject; the accepted in-flight fetch
        // must continue and launch its recipe normally.
        csr_desc_fetch_clear_sticky_status();
        csr_poll_desc_fetch_done(done_timeout_cycles);
        csr_poll_recipe_done(done_timeout_cycles * 2);
        csr_check_recipe_perf_snapshot(profile_item);
    end
    endtask

    task automatic run_manual_start_while_fetch_busy(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
        logic [31:0] cmd;
    begin
        clear_all_control_status();
        program_good_two_slot_descriptors(profile_item, a_bytes, b_bytes, c_bytes);

        csr_start_desc_fetch_raw(P17G_DESC_BASE, 2, P17G_DESC_STRIDE);
        wait_desc_fetch_busy("manual START_* while fetch_busy setup");

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_START_GEMM] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMMAND, cmd);

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::JOB_CMD_START] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_COMMAND, cmd);

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::RECIPE_CMD_START] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_COMMAND, cmd);

        expect_nonzero_csr(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS,
            "P14 START_GEMM while fetch_busy reject");
        expect_nonzero_csr(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS,
            "P15 START_JOB while fetch_busy reject");
        expect_nonzero_csr(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS,
            "P16 START_RECIPE while fetch_busy reject");

        // Clear manual-command rejects so the accepted descriptor-fetch recipe
        // can be checked using the existing strict P16 recipe checker.
        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();

        csr_poll_desc_fetch_done(done_timeout_cycles);
        csr_poll_recipe_done(done_timeout_cycles * 2);
        csr_check_recipe_perf_snapshot(profile_item);
    end
    endtask

    task automatic run_start_fetch_while_recipe_busy(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
    begin
        clear_all_control_status();
        program_good_two_slot_descriptors(profile_item, a_bytes, b_bytes, c_bytes);

        csr_start_desc_fetch_raw(P17G_DESC_BASE, 2, P17G_DESC_STRIDE);
        csr_poll_desc_fetch_done(done_timeout_cycles);
        wait_recipe_busy("START_FETCH while recipe_busy setup");

        csr_start_desc_fetch_raw(P17G_DESC_BASE, 2, P17G_DESC_STRIDE);
        expect_desc_fetch_reject(
            "START_FETCH while recipe_busy",
            bit_mask(ai_accel_csr_access_helper::DESC_FETCH_REJ_BUSY)
        );

        csr_desc_fetch_clear_sticky_status();
        csr_poll_recipe_done(done_timeout_cycles * 2);
        csr_check_recipe_perf_snapshot(profile_item);
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
        logic [31:0]             desc_invalid_mask;
    begin
        phase.raise_objection(this);

        `uvm_info("P17G_DESC_FETCH_REJ/START",
            "Starting P17G CSR descriptor-fetch reject/error handling test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);
        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P17G_DESC_FETCH_REJ/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(), c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);
        clear_all_control_status();

        // --------------------------------------------------------
        // START_FETCH acceptance rejects.
        // --------------------------------------------------------
        run_start_reject_case(
            "DESC_COUNT=0 reject",
            P17G_DESC_BASE,
            0,
            P17G_DESC_STRIDE,
            bit_mask(ai_accel_csr_access_helper::DESC_FETCH_REJ_ZERO_COUNT)
        );

        run_start_reject_case(
            "DESC_COUNT > queue depth reject",
            P17G_DESC_BASE,
            5,
            P17G_DESC_STRIDE,
            bit_mask(ai_accel_csr_access_helper::DESC_FETCH_REJ_COUNT_RANGE)
        );

        run_start_reject_case(
            "unaligned descriptor base reject",
            P17G_DESC_BASE + 2,
            1,
            P17G_DESC_STRIDE,
            bit_mask(ai_accel_csr_access_helper::DESC_FETCH_REJ_BASE_ALIGN)
        );

        run_start_reject_case(
            "unaligned descriptor stride reject",
            P17G_DESC_BASE,
            1,
            P17G_DESC_STRIDE + 4,
            bit_mask(ai_accel_csr_access_helper::DESC_FETCH_REJ_STRIDE_ALIGN)
        );

        run_start_reject_case(
            "too-small descriptor stride reject",
            P17G_DESC_BASE,
            1,
            64,
            bit_mask(ai_accel_csr_access_helper::DESC_FETCH_REJ_STRIDE_SMALL)
        );

        // --------------------------------------------------------
        // Malformed descriptor accepted-fetch errors.
        // --------------------------------------------------------
        desc_invalid_mask = bit_mask(ai_accel_csr_access_helper::DESC_FETCH_ERR_DESC_INVALID);

        run_malformed_descriptor_case(
            "descriptor valid bit missing",
            profile_item,
            32'h0000_0002,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            DESC_WORD_CONTROL,
            32'h0000_0002,
            desc_invalid_mask | bit_mask(ai_accel_csr_access_helper::DESC_FETCH_DESCERR_VALID)
        );

        run_malformed_descriptor_case(
            "descriptor unsupported output mode",
            profile_item,
            32'h0000_0013,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            DESC_WORD_CONTROL,
            32'h0000_0013,
            desc_invalid_mask | bit_mask(ai_accel_csr_access_helper::DESC_FETCH_DESCERR_OUT_MODE)
        );

        run_malformed_descriptor_case(
            "descriptor zero dimension",
            profile_item,
            SLOT0_CONTROL_DMA_HOST_READBACK,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            DESC_WORD_DIM_M,
            32'h0000_0000,
            desc_invalid_mask | bit_mask(ai_accel_csr_access_helper::DESC_FETCH_DESCERR_DIM_ZERO)
        );

        run_malformed_descriptor_case(
            "descriptor zero A preload length",
            profile_item,
            SLOT0_CONTROL_DMA_HOST_READBACK,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            DESC_WORD_A_LOAD_BEATS,
            32'h0000_0000,
            desc_invalid_mask | bit_mask(ai_accel_csr_access_helper::DESC_FETCH_DESCERR_A_ZERO)
        );

        run_malformed_descriptor_case(
            "descriptor zero B preload length",
            profile_item,
            SLOT0_CONTROL_DMA_HOST_READBACK,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            DESC_WORD_B_LOAD_BEATS,
            32'h0000_0000,
            desc_invalid_mask | bit_mask(ai_accel_csr_access_helper::DESC_FETCH_DESCERR_B_ZERO)
        );

        run_malformed_descriptor_case(
            "descriptor zero DMA store byte_count",
            profile_item,
            SLOT1_CONTROL_DMA_DMA_STORE,
            a_flat.size(),
            b_flat.size(),
            c_bytes,
            DESC_WORD_STORE_BYTE_COUNT,
            32'h0000_0000,
            desc_invalid_mask | bit_mask(ai_accel_csr_access_helper::DESC_FETCH_DESCERR_STORE_ZERO)
        );

        // --------------------------------------------------------
        // Descriptor AXI response error propagation.
        // --------------------------------------------------------
        run_desc_rresp_error_case(profile_item, a_flat.size(), b_flat.size(), c_bytes);

        // --------------------------------------------------------
        // Busy and manual-command interlocks.
        // --------------------------------------------------------
        run_start_fetch_while_fetch_busy(profile_item, a_flat.size(), b_flat.size(), c_bytes);
        run_manual_start_while_fetch_busy(profile_item, a_flat.size(), b_flat.size(), c_bytes);
        run_start_fetch_while_recipe_busy(profile_item, a_flat.size(), b_flat.size(), c_bytes);

        // --------------------------------------------------------
        // Sticky clear / retry recovery with a clean valid fetch+recipe.
        // --------------------------------------------------------
        clear_all_control_status();
        program_good_two_slot_descriptors(profile_item, a_flat.size(), b_flat.size(), c_bytes);
        csr_check_recipe_idle_ready("before final P17G recovery START_FETCH");
        csr_start_desc_fetch_raw(P17G_DESC_BASE, 2, P17G_DESC_STRIDE);
        csr_poll_desc_fetch_done(done_timeout_cycles);
        csr_poll_recipe_done(done_timeout_cycles * 2);
        csr_check_recipe_perf_snapshot(profile_item);

        repeat (5) @(posedge csr_vif.clk);
        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P17G_DESC_FETCH_REJ/PASS",
            $sformatf("P17G descriptor-fetch reject/error handling completed: CASE_ID=%0d C_words=%0d",
                selected_case_id,
                c_elems),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
