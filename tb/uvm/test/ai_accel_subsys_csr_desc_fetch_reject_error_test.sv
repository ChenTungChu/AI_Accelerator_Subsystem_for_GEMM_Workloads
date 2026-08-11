// File: tb/uvm/test/ai_accel_subsys_csr_desc_fetch_reject_error_test.sv
// ============================================================
// P17G CSR descriptor-fetch reject / busy / malformed descriptor test
//
// Scope:
//   - Reuses the existing CSR UVM top and run_uvm.tcl flow.
//   - Does not add a standalone descriptor-fetch testbench or run script.
//   - Validates START_FETCH command rejects, malformed descriptor errors,
//     descriptor AXI RRESP / RLAST propagation, manual command interlocks
//     while descriptor fetch is active, and sticky clear / retry recovery.
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

    // ai_accel_desc_fetch_engine ERROR_AXI_RLAST_BIT.
    localparam int DESC_FETCH_ERR_AXI_RLAST_BIT = 1;

    localparam int unsigned C1_2C2_A1_GUARD_P14 = 0;
    localparam int unsigned C1_2C2_A1_GUARD_P15 = 1;
    localparam int unsigned C1_2C2_A1_GUARD_P16 = 2;
    localparam int unsigned C1_2C2_A1_GUARD_P17 = 3;

    localparam int unsigned C1_2C2_A1_P14_REJ_UNSUPPORTED_BIT = 8;

    // CODE-COV-C1.2-D3-A1 descriptor-fetch effective-dimension probe.
    // The project configuration uses GEMM_DIM_WIDTH=8, so 0x00000100 is
    // nonzero in descriptor memory but zero after the effective-width slice.
    localparam logic [31:0] C1_2D3_A1_HOST_PRELOADED_CONTROL = 32'h0000_0001;
    localparam logic [31:0] C1_2D3_A1_EFFECTIVE_ZERO_DIM     = 32'h0000_0100;

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

    // ------------------------------------------------------------
    // CODE-COV-C1.1-C direct status-clear helpers
    // ------------------------------------------------------------
    task automatic p17g_direct_status_clear_expect_zero(
        input logic [11:0] addr,
        input string       tag
    );
        logic [31:0] before_status;
        logic [31:0] after_status;
        logic [31:0] expected_after;
    begin
        csr.read32_expect_okay(addr, before_status);
        if (before_status == 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1C/P17_CLEAR_PRE",
                $sformatf("%s: expected nonzero descriptor-fetch status at addr=0x%03h",
                    tag, addr))
        end

        // P17 direct DONE/ERROR/REJECT status writes are architectural clear
        // requests; use the observed nonzero value rather than a coverage-only
        // arbitrary pattern.
        //
        // DESC_FETCH_DONE_STATUS is a composite readback:
        //   bit[0] = fetch_done
        //   bit[1] = fetched_snapshot_valid
        // CLEAR_DONE intentionally clears only fetch_done.  The fetched
        // snapshot remains valid until a new accepted fetch invalidates it.
        expected_after = 32'h0000_0000;
        if (addr == ai_accel_csr_access_helper::CSR_DESC_FETCH_DONE_STATUS) begin
            if (!before_status[0]) begin
                `uvm_fatal("CODE_COV_C1C/P17_CLEAR_PRE",
                    $sformatf("%s: expected DONE bit set before direct DONE clear, before=0x%08h",
                        tag, before_status))
            end
            expected_after = before_status & 32'hFFFF_FFFE;
        end

        csr.write32_expect_okay(addr, before_status);
        repeat (4) @(posedge csr_vif.clk);
        csr.read32_expect_okay(addr, after_status);

        if (after_status != expected_after) begin
            `uvm_fatal("CODE_COV_C1C/P17_CLEAR",
                $sformatf("%s: direct status clear failed addr=0x%03h before=0x%08h after=0x%08h expected_after=0x%08h",
                    tag, addr, before_status, after_status, expected_after))
        end

        `uvm_info("CODE_COV_C1C/P17_DIRECT_CLEAR_PASS",
            $sformatf("%s: direct status clear PASS addr=0x%03h before=0x%08h after=0x%08h",
                tag, addr, before_status, after_status),
            UVM_MEDIUM)
    end
    endtask

    task automatic p17g_direct_p14_reject_w1c_expect_zero(input string tag);
        logic [31:0] before_status;
        logic [31:0] after_status;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, before_status);
        if (before_status == 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1C/P14_REJECT_PRE",
                $sformatf("%s: expected nonzero P14 CMD_REJECT_STATUS", tag))
        end

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, before_status);
        repeat (2) @(posedge csr_vif.clk);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, after_status);

        if ((after_status & before_status) != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1C/P14_REJECT_W1C",
                $sformatf("%s: P14 CMD_REJECT direct W1C failed before=0x%08h after=0x%08h",
                    tag, before_status, after_status))
        end

        `uvm_info("CODE_COV_C1C/P14_REJECT_W1C_PASS",
            $sformatf("%s: P14 CMD_REJECT direct W1C PASS before=0x%08h after=0x%08h",
                tag, before_status, after_status),
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
        input logic [31:0] expected_reject_mask,
        input bit          use_direct_clear = 1'b0
    );
    begin
        csr_desc_fetch_clear_sticky_status();
        csr_start_desc_fetch_raw(desc_base, desc_count, desc_stride);
        expect_desc_fetch_reject(tag, expected_reject_mask);
        if (use_direct_clear) begin
            p17g_direct_status_clear_expect_zero(
                ai_accel_csr_access_helper::CSR_DESC_FETCH_REJECT_STATUS,
                $sformatf("%s direct REJECT clear", tag)
            );
        end
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
        input logic [31:0]             expected_error_mask,
        input bit                      use_direct_clear = 1'b0
    );
    begin
        csr_desc_fetch_clear_sticky_status();
        program_single_descriptor(profile_item, slot_control, a_bytes, b_bytes, c_bytes, 32'hD17B_0000);
        write_desc_word(P17G_BAD_DESC_BASE, override_word_idx, override_value);

        csr_start_desc_fetch_raw(P17G_BAD_DESC_BASE, 1, P17G_DESC_STRIDE);
        expect_desc_fetch_error(tag, expected_error_mask);
        if (use_direct_clear) begin
            p17g_direct_status_clear_expect_zero(
                ai_accel_csr_access_helper::CSR_DESC_FETCH_ERROR_STATUS,
                $sformatf("%s direct ERROR clear", tag)
            );
        end
        csr_desc_fetch_clear_sticky_status();
    end
    endtask

    task automatic run_c1_2d3_a1_effective_dimension_case(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
        logic [31:0] expected_error_mask;
        logic [31:0] error_status;
        logic [31:0] done_status;
        logic [31:0] recipe_status;
        logic [31:0] recipe_state;
        bit          auto_recipe_start_seen;
    begin
        clear_all_control_status();
        program_single_descriptor(
            profile_item,
            C1_2D3_A1_HOST_PRELOADED_CONTROL,
            a_bytes,
            b_bytes,
            c_bytes,
            32'hD17D_0000
        );
        write_desc_word(
            P17G_BAD_DESC_BASE,
            DESC_WORD_DIM_M,
            C1_2D3_A1_EFFECTIVE_ZERO_DIM
        );

        expected_error_mask =
            bit_mask(ai_accel_csr_access_helper::DESC_FETCH_ERR_DESC_INVALID) |
            bit_mask(ai_accel_csr_access_helper::DESC_FETCH_DESCERR_DIM_ZERO);
        auto_recipe_start_seen = 1'b0;

        fork : c1_2d3_a1_effective_dim_watch
            begin
                forever begin
                    @(posedge csr_vif.clk);
                    if (vif.desc_fetch_recipe_start_pulse_obs) begin
                        auto_recipe_start_seen = 1'b1;
                    end
                end
            end

            begin
                csr_start_desc_fetch_raw(
                    P17G_BAD_DESC_BASE,
                    1,
                    P17G_DESC_STRIDE
                );
                expect_desc_fetch_error(
                    "descriptor effective-width zero dimension",
                    expected_error_mask
                );
            end
        join_any
        disable c1_2d3_a1_effective_dim_watch;

        repeat (3) @(posedge csr_vif.clk);
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_DESC_FETCH_ERROR_STATUS,
            error_status
        );
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_DESC_FETCH_DONE_STATUS,
            done_status
        );
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_RECIPE_STATUS,
            recipe_status
        );
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_RECIPE_STATE,
            recipe_state
        );

        if (error_status != expected_error_mask) begin
            `uvm_fatal("CODE_COV_C1_2D3_A1/ERROR_STATUS_MISMATCH",
                $sformatf("Expected exact descriptor error=0x%08h actual=0x%08h",
                    expected_error_mask,
                    error_status))
        end

        if (done_status != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1_2D3_A1/SNAPSHOT_NOT_BLOCKED",
                $sformatf("Effective-zero descriptor produced DONE/snapshot status=0x%08h",
                    done_status))
        end

        if (auto_recipe_start_seen) begin
            `uvm_fatal("CODE_COV_C1_2D3_A1/AUTO_RECIPE_LAUNCH",
                "Effective-zero descriptor generated an automatic recipe-start pulse")
        end

        if (recipe_status[0] || (recipe_state[3:0] != 4'h0)) begin
            `uvm_fatal("CODE_COV_C1_2D3_A1/RECIPE_NOT_IDLE",
                $sformatf("Recipe sequencer was not held in IDLE: status=0x%08h state=0x%08h",
                    recipe_status,
                    recipe_state))
        end

        `uvm_info("CODE_COV_C1_2D3_A1/EFFECTIVE_DIM_REJECT_PASS",
            $sformatf("DIM_M=0x%08h rejected in descriptor fetch: error=0x%08h done/snapshot=0x%08h recipe_state=0x%08h",
                C1_2D3_A1_EFFECTIVE_ZERO_DIM,
                error_status,
                done_status,
                recipe_state),
            UVM_MEDIUM)

        clear_all_control_status();
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

    // CODE-COV-C1.2-B: genuine descriptor-source protocol error.
    // Return one OKAY read response with RLAST low so the descriptor-fetch
    // engine takes its dedicated ERROR_AXI_RLAST path without force or
    // hierarchical internal-state injection.
    task automatic run_desc_rlast_error_case(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
    begin
        csr_desc_fetch_clear_sticky_status();
        program_single_descriptor(profile_item, SLOT0_CONTROL_DMA_HOST_READBACK, a_bytes, b_bytes, c_bytes, 32'hD17C_0001);

        desc_src_inject_vif.clear();
        desc_src_inject_vif.set_rlast_error(1'b1, 0);
        csr_start_desc_fetch_raw(P17G_BAD_DESC_BASE, 1, P17G_DESC_STRIDE);
        expect_desc_fetch_error(
            "descriptor AXI missing-RLAST error propagation",
            bit_mask(DESC_FETCH_ERR_AXI_RLAST_BIT)
        );
        desc_src_inject_vif.clear();
        csr_desc_fetch_clear_sticky_status();
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.2-C2-A1 descriptor-to-recipe ownership handoff
    // ------------------------------------------------------------
    task automatic c1_2c2_a1_write_and_read_during_handoff(
        input logic [11:0] command_addr,
        input logic [31:0] command_data,
        input logic [11:0] status_addr,
        input int unsigned guard_kind,
        input string       tag,
        output logic [31:0] status_data
    );
        bit          handoff_seen;
        bit          ar_done;
        bit          r_done;
        int unsigned timeout_count;
    begin
        handoff_seen = 1'b0;
        status_data  = 32'h0000_0000;

        fork : c1_2c2_a1_wait_handoff
            begin
                @(posedge vif.desc_fetch_recipe_start_pulse_obs);
                handoff_seen = 1'b1;
            end

            begin
                repeat (done_timeout_cycles) @(posedge csr_vif.clk);
            end
        join_any
        disable c1_2c2_a1_wait_handoff;

        if (!handoff_seen) begin
            `uvm_fatal("CODE_COV_C1_2C2_A1/HANDOFF_TIMEOUT",
                $sformatf("%s: timed out waiting for descriptor-to-recipe handoff pulse", tag))
        end

        // This is the exact pre-recipe-busy bridge window identified by the
        // C1.2-C2-A source audit.  Raw fetch_busy and recipe_busy are both
        // low, while the extended launch-ownership signal must stay high.
        if (vif.desc_fetch_busy_obs !== 1'b0) begin
            `uvm_fatal("CODE_COV_C1_2C2_A1/RAW_BUSY_HIGH",
                $sformatf("%s: expected raw descriptor fetch busy low during handoff", tag))
        end
        if (vif.recipe_busy_obs !== 1'b0) begin
            `uvm_fatal("CODE_COV_C1_2C2_A1/RECIPE_BUSY_EARLY",
                $sformatf("%s: expected recipe busy low before the handoff pulse is sampled", tag))
        end
        if (vif.desc_fetch_launch_ownership_obs !== 1'b1) begin
            `uvm_fatal("CODE_COV_C1_2C2_A1/OWNERSHIP_GAP",
                $sformatf("%s: descriptor launch ownership dropped during the handoff pulse", tag))
        end

        `uvm_info("CODE_COV_C1_2C2_A1/HANDOFF_WINDOW",
            $sformatf("%s: observed raw_busy=0 recipe_busy=0 launch_ownership=1", tag),
            UVM_MEDIUM)

        // Drive a complete AXI-Lite write on the next falling edge so both
        // write channels are stable before the clock edge that samples the
        // one-cycle handoff ownership condition.
        @(negedge csr_vif.clk);
        csr_vif.awaddr  <= command_addr;
        csr_vif.awvalid <= 1'b1;
        csr_vif.wdata   <= command_data;
        csr_vif.wstrb   <= '1;
        csr_vif.wvalid  <= 1'b1;
        csr_vif.bready  <= 1'b1;

        // The CSR bus is idle before this probe, so both channels must be
        // accepted on the immediately following edge.  Requiring this exact
        // edge prevents the probe from silently slipping into recipe_busy.
        @(posedge csr_vif.clk);
        if (!(csr_vif.awvalid && csr_vif.awready &&
              csr_vif.wvalid  && csr_vif.wready)) begin
            `uvm_fatal("CODE_COV_C1_2C2_A1/WRITE_HANDSHAKE_MISSED",
                $sformatf("%s: AW/W were not both accepted on the handoff edge", tag))
        end
        csr_vif.awvalid <= 1'b0;
        csr_vif.wvalid  <= 1'b0;

        // Sample the registered launch result half a cycle after write_apply.
        // P14/P15/P16 launch pulses must remain low.  A P17 command pulse may
        // be generated by the CSR block, but top-level ownership must prevent
        // it from reaching the descriptor-fetch engine.
        @(negedge csr_vif.clk);
        case (guard_kind)
            C1_2C2_A1_GUARD_P14: begin
                if (vif.csr_dma_load_start_pulse_obs !== 1'b0) begin
                    `uvm_fatal("CODE_COV_C1_2C2_A1/P14_LAUNCH_ESCAPED",
                        $sformatf("%s: P14 DMA-load start pulse escaped during handoff", tag))
                end
            end

            C1_2C2_A1_GUARD_P15: begin
                if (vif.csr_job_start_pulse_obs !== 1'b0) begin
                    `uvm_fatal("CODE_COV_C1_2C2_A1/P15_LAUNCH_ESCAPED",
                        $sformatf("%s: P15 job start pulse escaped during handoff", tag))
                end
            end

            C1_2C2_A1_GUARD_P16: begin
                if (vif.csr_recipe_start_pulse_obs !== 1'b0) begin
                    `uvm_fatal("CODE_COV_C1_2C2_A1/P16_LAUNCH_ESCAPED",
                        $sformatf("%s: manual P16 recipe start pulse escaped during handoff", tag))
                end
            end

            C1_2C2_A1_GUARD_P17: begin
                if (vif.csr_desc_fetch_start_pulse_obs !== 1'b1) begin
                    `uvm_fatal("CODE_COV_C1_2C2_A1/P17_COMMAND_NOT_SEEN",
                        $sformatf("%s: expected the raw CSR P17 start command pulse", tag))
                end
                if (vif.desc_fetch_start_to_engine_obs !== 1'b0) begin
                    `uvm_fatal("CODE_COV_C1_2C2_A1/P17_LAUNCH_ESCAPED",
                        $sformatf("%s: second descriptor-fetch start reached the engine during handoff", tag))
                end
            end

            default: begin
                `uvm_fatal("CODE_COV_C1_2C2_A1/BAD_GUARD_KIND",
                    $sformatf("%s: unsupported handoff guard kind=%0d", tag, guard_kind))
            end
        endcase

        // Consume the write response one cycle after write_apply.  The P17
        // external reject is also registered on this edge because the raw CSR
        // descriptor-start pulse is itself produced by the preceding edge.
        @(posedge csr_vif.clk);
        if (!(csr_vif.bvalid && csr_vif.bready)) begin
            `uvm_fatal("CODE_COV_C1_2C2_A1/BRESP_TIMEOUT",
                $sformatf("%s: expected command write response after handoff write", tag))
        end
        if (csr_vif.bresp != 2'b00) begin
            `uvm_fatal("CODE_COV_C1_2C2_A1/BRESP",
                $sformatf("%s: command write BRESP was 0x%0h", tag, csr_vif.bresp))
        end
        csr_vif.bready <= 1'b0;

        // Read the software-visible reject CSR on the following half cycle.
        // This is early enough to precede the fetched recipe's normal sticky
        // clears, while allowing the top-level P17 external reject to settle.
        @(negedge csr_vif.clk);
        csr_vif.araddr  <= status_addr;
        csr_vif.arvalid <= 1'b1;
        csr_vif.rready  <= 1'b1;

        ar_done = 1'b0;
        r_done  = 1'b0;
        timeout_count = 0;
        while (!(ar_done && r_done)) begin
            @(posedge csr_vif.clk);

            if (!ar_done && csr_vif.arvalid && csr_vif.arready) begin
                ar_done = 1'b1;
                csr_vif.arvalid <= 1'b0;
            end

            if (!r_done && csr_vif.rvalid && csr_vif.rready) begin
                if (csr_vif.rresp != 2'b00) begin
                    `uvm_fatal("CODE_COV_C1_2C2_A1/RRESP",
                        $sformatf("%s: reject-status read RRESP was 0x%0h", tag, csr_vif.rresp))
                end
                status_data = csr_vif.rdata;
                r_done = 1'b1;
                csr_vif.rready <= 1'b0;
            end

            timeout_count++;
            if (timeout_count > 20) begin
                `uvm_fatal("CODE_COV_C1_2C2_A1/RESPONSE_TIMEOUT",
                    $sformatf("%s: timed out waiting for reject-status read response", tag))
            end
        end

        @(negedge csr_vif.clk);
    end
    endtask

    task automatic run_c1_2c2_a1_handoff_guard_case(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes,
        input logic [11:0]             command_addr,
        input logic [31:0]             command_data,
        input logic [11:0]             status_addr,
        input logic [31:0]             expected_reject,
        input int unsigned             guard_kind,
        input string                   tag
    );
        logic [31:0] observed_reject;
    begin
        clear_all_control_status();
        program_good_two_slot_descriptors(profile_item, a_bytes, b_bytes, c_bytes);
        csr_check_recipe_idle_ready({tag, " prestart"});

        fork
            begin
                csr_start_desc_fetch_raw(P17G_DESC_BASE, 2, P17G_DESC_STRIDE);
            end

            begin
                c1_2c2_a1_write_and_read_during_handoff(
                    command_addr,
                    command_data,
                    status_addr,
                    guard_kind,
                    tag,
                    observed_reject
                );
            end
        join

        if (observed_reject != expected_reject) begin
            `uvm_fatal("CODE_COV_C1_2C2_A1/REJECT_MISMATCH",
                $sformatf("%s: expected reject=0x%08h actual=0x%08h",
                    tag, expected_reject, observed_reject))
        end

        `uvm_info("CODE_COV_C1_2C2_A1/HANDOFF_REJECT_PASS",
            $sformatf("%s: exact handoff launch blocked and software-visible reject=0x%08h",
                tag, observed_reject),
            UVM_MEDIUM)

        // Remove only the interlock status before the already-launched fetched
        // recipe reaches its normal strict completion checker.
        case (guard_kind)
            C1_2C2_A1_GUARD_P14: csr_clear_sticky_status();
            C1_2C2_A1_GUARD_P15: csr_job_clear_sticky_status();
            C1_2C2_A1_GUARD_P16: csr_recipe_clear_sticky_status();
            C1_2C2_A1_GUARD_P17: csr_desc_fetch_clear_sticky_status();
            default: begin end
        endcase

        csr_poll_recipe_done(done_timeout_cycles * 2);
        csr_check_recipe_perf_snapshot(profile_item);
    end
    endtask

    task automatic run_c1_2c2_a1_handoff_guard_suite(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
        logic [31:0] command_data;
    begin
        command_data = 32'h0000_0000;
        command_data[ai_accel_csr_access_helper::CMD_START_DMA_LOAD] = 1'b1;
        run_c1_2c2_a1_handoff_guard_case(
            profile_item, a_bytes, b_bytes, c_bytes,
            ai_accel_csr_access_helper::CSR_COMMAND,
            command_data,
            ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS,
            bit_mask(C1_2C2_A1_P14_REJ_UNSUPPORTED_BIT),
            C1_2C2_A1_GUARD_P14,
            "C1_2C2_A1_P14_HANDOFF"
        );

        command_data = 32'h0000_0000;
        command_data[ai_accel_csr_access_helper::JOB_CMD_START] = 1'b1;
        run_c1_2c2_a1_handoff_guard_case(
            profile_item, a_bytes, b_bytes, c_bytes,
            ai_accel_csr_access_helper::CSR_JOB_COMMAND,
            command_data,
            ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS,
            bit_mask(ai_accel_csr_access_helper::JOB_REJ_MANUAL_CMD),
            C1_2C2_A1_GUARD_P15,
            "C1_2C2_A1_P15_HANDOFF"
        );

        command_data = 32'h0000_0000;
        command_data[ai_accel_csr_access_helper::RECIPE_CMD_START] = 1'b1;
        run_c1_2c2_a1_handoff_guard_case(
            profile_item, a_bytes, b_bytes, c_bytes,
            ai_accel_csr_access_helper::CSR_RECIPE_COMMAND,
            command_data,
            ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS,
            bit_mask(ai_accel_csr_access_helper::RECIPE_REJ_MANUAL_CMD),
            C1_2C2_A1_GUARD_P16,
            "C1_2C2_A1_P16_HANDOFF"
        );

        command_data = 32'h0000_0000;
        command_data[ai_accel_csr_access_helper::DESC_FETCH_CMD_START] = 1'b1;
        run_c1_2c2_a1_handoff_guard_case(
            profile_item, a_bytes, b_bytes, c_bytes,
            ai_accel_csr_access_helper::CSR_DESC_FETCH_COMMAND,
            command_data,
            ai_accel_csr_access_helper::CSR_DESC_FETCH_REJECT_STATUS,
            bit_mask(ai_accel_csr_access_helper::DESC_FETCH_REJ_BUSY),
            C1_2C2_A1_GUARD_P17,
            "C1_2C2_A1_P17_HANDOFF"
        );

        clear_all_control_status();

        `uvm_info("CODE_COV_C1_2C2_A1/HANDOFF_SUITE_PASS",
            "Descriptor-to-recipe handoff guards PASS for P14, P15, P16, and P17 launches",
            UVM_MEDIUM)
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

        p17g_direct_p14_reject_w1c_expect_zero(
            "P14 START_GEMM while descriptor fetch busy"
        );

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
        desc_src_inject_vif.clear();

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
            bit_mask(ai_accel_csr_access_helper::DESC_FETCH_REJ_ZERO_COUNT),
            1'b1
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
            desc_invalid_mask | bit_mask(ai_accel_csr_access_helper::DESC_FETCH_DESCERR_VALID),
            1'b1
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

        run_c1_2d3_a1_effective_dimension_case(
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
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
        run_desc_rlast_error_case(profile_item, a_flat.size(), b_flat.size(), c_bytes);

        // --------------------------------------------------------
        // Busy and manual-command interlocks.
        // --------------------------------------------------------
        run_start_fetch_while_fetch_busy(profile_item, a_flat.size(), b_flat.size(), c_bytes);
        run_manual_start_while_fetch_busy(profile_item, a_flat.size(), b_flat.size(), c_bytes);
        run_start_fetch_while_recipe_busy(profile_item, a_flat.size(), b_flat.size(), c_bytes);

        // Exact descriptor-fetch done -> recipe start ownership handoff.
        run_c1_2c2_a1_handoff_guard_suite(
            profile_item,
            a_flat.size(),
            b_flat.size(),
            c_bytes
        );

        // --------------------------------------------------------
        // Sticky clear / retry recovery with a clean valid fetch+recipe.
        // --------------------------------------------------------
        clear_all_control_status();
        program_good_two_slot_descriptors(profile_item, a_flat.size(), b_flat.size(), c_bytes);
        csr_check_recipe_idle_ready("before final P17G recovery START_FETCH");
        csr_start_desc_fetch_raw(P17G_DESC_BASE, 2, P17G_DESC_STRIDE);
        csr_poll_desc_fetch_done(done_timeout_cycles);
        csr_poll_recipe_done(done_timeout_cycles * 2);
        p17g_direct_status_clear_expect_zero(
            ai_accel_csr_access_helper::CSR_DESC_FETCH_DONE_STATUS,
            "final valid descriptor fetch DONE clear"
        );
        csr_check_recipe_perf_snapshot(profile_item);

        repeat (5) @(posedge csr_vif.clk);
        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);
        desc_src_inject_vif.clear();

        `uvm_info("CODE_COV_C1_2D3_A1/RECOVERY_PASS",
            "Valid descriptor-fetch automatic recipe completed after effective-dimension reject",
            UVM_MEDIUM)

        `uvm_info("CODE_COV_C1_2D3_A1/SUITE_PASS",
            "Descriptor-fetch effective-dimension validation fix probes PASS",
            UVM_MEDIUM)

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
