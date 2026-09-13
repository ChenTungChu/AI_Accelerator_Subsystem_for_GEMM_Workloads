// File: tb/uvm/test/ai_accel_subsys_csr_dma_load_store_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_DMA_LOAD_STORE_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_DMA_LOAD_STORE_SMOKE_TEST_SV

// ------------------------------------------------------------
// CSR-controlled DMA load + GEMM + DMA store representative smoke
//
// Scope:
//   - preload A/B into the DMA source memory model
//   - use CSR START_DMA_LOAD to copy A into scratchpad
//   - use CSR START_DMA_LOAD to copy B into scratchpad
//   - use CSR START_GEMM to launch host-primary scratchpad GEMM
//   - use CSR START_DMA_STORE to move C into the destination memory model
//   - compare destination memory against the software reference directly
//
// This focused CSR test intentionally bypasses the legacy sideband
// driver/scoreboard launch path.  Pass/fail is determined by CSR
// command/status sequencing and the final DMA destination memory compare.
// ------------------------------------------------------------

class ai_accel_subsys_csr_dma_load_store_smoke_test extends ai_accel_subsys_csr_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_dma_load_store_smoke_test)

    localparam int unsigned BYTES_PER_BEAT = 8;

    localparam logic [31:0] DMA_SRC_A_BASE = 32'h0000_0000;
    localparam logic [31:0] DMA_SRC_B_BASE = 32'h0000_0100;
    localparam logic [31:0] DMA_DST_C_BASE = 32'h0000_0000;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_csr_dma_load_store_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Size helpers
    // ------------------------------------------------------------
    function automatic int unsigned bytes_to_beats(input int unsigned byte_count);
        if (byte_count == 0) begin
            `uvm_fatal("CSR_DMA_SMOKE/ZERO_BYTES",
                "Attempted to convert zero byte_count to DMA beats")
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
                `uvm_fatal("CSR_DMA_SMOKE/BAD_KIND",
                    $sformatf("Unsupported CSR DMA load-store smoke test_kind=%0d CASE_ID=%0d",
                        selected_test_kind, selected_case_id))
            end
        endcase
    end
    endtask

    // ------------------------------------------------------------
    // Source/destination memory model preparation
    // ------------------------------------------------------------
    task automatic write_u8_payload_to_dma_src(
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

    task automatic prepare_dma_source_and_destination(
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
        vif.dma_dst_set_aw_w_backpressure(1'b0, -1, -1);

        write_u8_payload_to_dma_src(DMA_SRC_A_BASE, a_flat);
        write_u8_payload_to_dma_src(DMA_SRC_B_BASE, b_flat);

        `uvm_info("CSR_DMA_SMOKE",
            $sformatf("Prepared DMA source payloads: A src=0x%08h bytes=%0d, B src=0x%08h bytes=%0d, dst C base=0x%08h",
                DMA_SRC_A_BASE,
                a_flat.size(),
                DMA_SRC_B_BASE,
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
                `uvm_fatal("CSR_DMA_SMOKE/ERROR_STATUS",
                    $sformatf("%s: CSR_ERROR_STATUS became nonzero: 0x%08h",
                        tag, error_status))
            end

            if (reject_status != 32'h0000_0000) begin
                `uvm_fatal("CSR_DMA_SMOKE/REJECT_STATUS",
                    $sformatf("%s: CSR_CMD_REJECT_STATUS became nonzero: 0x%08h",
                        tag, reject_status))
            end

            if (done_status[done_bit]) begin
                `uvm_info("CSR_DMA_SMOKE",
                    $sformatf("Observed CSR %s done after %0d poll cycle(s): DONE_STATUS=0x%08h",
                        tag, cnt, done_status),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("CSR_DMA_SMOKE/DONE_TIMEOUT",
                    $sformatf("Timed out waiting for CSR %s done after %0d cycles",
                        tag, timeout_cycles))
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // CSR DMA load command sequence
    // ------------------------------------------------------------
    task automatic csr_write_dma_load_config(
        input logic [31:0] src_base,
        input logic [31:0] dst_base,
        input int unsigned beats,
        input string       tag
    );
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DMA_LOAD_SRC_BASE,
            src_base
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DMA_LOAD_DST_BASE,
            dst_base
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DMA_LOAD_BEATS,
            32'(beats)
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DMA_LOAD_SRC_BASE,
            src_base,
            {tag, " CSR_DMA_LOAD_SRC_BASE"}
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DMA_LOAD_DST_BASE,
            dst_base,
            {tag, " CSR_DMA_LOAD_DST_BASE"}
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DMA_LOAD_BEATS,
            32'(beats),
            {tag, " CSR_DMA_LOAD_BEATS"}
        );

        `uvm_info("CSR_DMA_SMOKE",
            $sformatf("Programmed CSR DMA load %s: src=0x%08h dst=0x%08h beats=%0d",
                tag, src_base, dst_base, beats),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_start_dma_load(input string tag);
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_START_DMA_LOAD] = 1'b1;
        csr.issue_command(cmd);

        `uvm_info("CSR_DMA_SMOKE",
            $sformatf("Issued CSR START_DMA_LOAD command for %s", tag),
            UVM_MEDIUM)
    end
    endtask

    task automatic run_one_dma_load(
        input logic [31:0] src_base,
        input logic [31:0] dst_base,
        input int unsigned byte_count,
        input string       tag
    );
        int unsigned beats;
    begin
        beats = bytes_to_beats(byte_count);

        csr_clear_sticky_status();
        csr_write_dma_load_config(src_base, dst_base, beats, tag);
        csr_start_dma_load(tag);
        csr_poll_done_bit(
            done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_DMA_LOAD,
            {"DMA_LOAD_", tag}
        );

        repeat (2) @(posedge csr_vif.clk);
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

        `uvm_info("CSR_DMA_SMOKE",
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

        `uvm_info("CSR_DMA_SMOKE",
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
    // CODE-COV-C1.2-G7-V4-B DMA-store destination AW/W
    // independent-handshake / backpressure probe
    //
    // Relative destination beats:
    //   beat 0 -> AW-first  (WREADY held low until AW is accepted)
    //   beat 1 -> W-first   (AWREADY held low until W is accepted)
    // ------------------------------------------------------------
    task automatic run_g7_v4_dma_store_aw_w_backpressure_probe(
        input logic [31:0] src_base,
        input logic [31:0] dst_base,
        input int unsigned byte_count
    );
        int unsigned aw_first_before;
        int unsigned w_first_before;
        int unsigned aw_first_after;
        int unsigned w_first_after;
    begin
        if (bytes_to_beats(byte_count) < 2) begin
            `uvm_fatal("CODE_COV_C1P2_G7_V4/TOO_SHORT",
                $sformatf("G7-V4 requires at least two DMA-store destination beats, got byte_count=%0d beats=%0d",
                    byte_count, bytes_to_beats(byte_count)))
        end

        aw_first_before = vif.dma_dst_aw_first_observed_count;
        w_first_before  = vif.dma_dst_w_first_observed_count;

        vif.dma_dst_set_aw_w_backpressure(
            1'b1,
            0,
            1
        );

        // Allow the responder to capture its transaction-relative
        // AW/W base counters before issuing START_DMA_STORE.
        repeat (2) @(posedge csr_vif.clk);

        `uvm_info("CODE_COV_C1P2_G7_V4/START",
            $sformatf("Starting DMA-store AW/W backpressure probe: src=0x%08h dst=0x%08h bytes=%0d beat0=AW-first beat1=W-first",
                src_base, dst_base, byte_count),
            UVM_MEDIUM)

        run_dma_store(src_base, dst_base, byte_count);

        vif.dma_dst_set_aw_w_backpressure(1'b0, -1, -1);
        repeat (2) @(posedge csr_vif.clk);

        aw_first_after = vif.dma_dst_aw_first_observed_count;
        w_first_after  = vif.dma_dst_w_first_observed_count;

        if (aw_first_after <= aw_first_before) begin
            `uvm_fatal("CODE_COV_C1P2_G7_V4/AW_FIRST_MISS",
                $sformatf("DMA destination AW-first ordering was not observed: before=%0d after=%0d",
                    aw_first_before, aw_first_after))
        end

        if (w_first_after <= w_first_before) begin
            `uvm_fatal("CODE_COV_C1P2_G7_V4/W_FIRST_MISS",
                $sformatf("DMA destination W-first ordering was not observed: before=%0d after=%0d",
                    w_first_before, w_first_after))
        end

        `uvm_info("CODE_COV_C1P2_G7_V4/PASS",
            $sformatf("DMA-store destination independent-handshake probe PASS: AW-first delta=%0d W-first delta=%0d",
                aw_first_after - aw_first_before,
                w_first_after - w_first_before),
            UVM_MEDIUM)
    end
    endtask


    // ------------------------------------------------------------
    // CODE-COV-C1.2-G7-Y1 DMA load/store cross-owner
    // mutual-exclusion constructive validation
    //
    // Exercise both legal frontend rejection directions without
    // intentionally creating the illegal simultaneous-busy state:
    //
    //   START_DMA_LOAD
    //     -> immediately START_DMA_STORE
    //     -> REJ_DMA_STORE_BUSY
    //
    //   START_DMA_STORE
    //     -> immediately START_DMA_LOAD
    //     -> REJ_DMA_LOAD_BUSY
    //
    // No busy poll or inserted delay is allowed between the first
    // accepted START and the adjacent cross-owner START.  This keeps
    // the probe focused on the accepted-start -> busy-visibility
    // reservation window while continuously checking that the two
    // DMA owners never become busy at the same time.
    // ------------------------------------------------------------
    task automatic run_g7_y1_dma_load_store_cross_owner_reject_probe(
        input logic [31:0] scratchpad_c_base
    );
        bit load_busy_seen;
        bit store_busy_seen;
        bit overlap_seen;
        bit monitor_done;
    begin
        `uvm_info("CODE_COV_C1P2_G7_Y1/START",
            "Starting DMA load/store cross-owner mutual-exclusion probe",
            UVM_MEDIUM)

        // --------------------------------------------------------
        // Probe A:
        //   DMA Load owns Port0.
        //   Adjacent START_DMA_STORE must be rejected.
        // --------------------------------------------------------
        csr_clear_sticky_status();

        csr_write_dma_load_config(
            DMA_SRC_A_BASE,
            32'h0000_0000,
            8,
            "G7_Y1_LOAD_OWNER"
        );

        csr_write_dma_store_config(
            scratchpad_c_base,
            DMA_DST_C_BASE,
            64
        );

        load_busy_seen  = 1'b0;
        store_busy_seen = 1'b0;
        overlap_seen    = 1'b0;
        monitor_done    = 1'b0;

        fork
            begin : g7_y1_load_owner_monitor
                while (!monitor_done) begin
                    @(posedge csr_vif.clk);

                    if (vif.dma_load_busy) begin
                        load_busy_seen = 1'b1;
                    end

                    if (vif.dma_store_busy) begin
                        store_busy_seen = 1'b1;
                    end

                    if (vif.dma_load_busy && vif.dma_store_busy) begin
                        overlap_seen = 1'b1;
                    end
                end
            end

            begin : g7_y1_load_owner_sequence
                csr_start_dma_load("G7_Y1_LOAD_OWNER");

                `uvm_info("CODE_COV_C1P2_G7_Y1/LOAD_OWNER_START",
                    "START_DMA_LOAD write completed; issuing START_DMA_STORE immediately with no busy poll or inserted delay",
                    UVM_MEDIUM)

                csr_start_dma_store();

                repeat (2) @(posedge csr_vif.clk);

                csr_expect_p14_reject_bit(
                    C1D1_P14_REJ_DMA_STORE_BUSY,
                    "G7-Y1 START_DMA_STORE while DMA load owns Port0"
                );

                csr_clear_p14_reject_status(
                    "after G7-Y1 LOAD-owner blocks STORE reject"
                );

                csr_poll_done_bit(
                    done_timeout_cycles,
                    ai_accel_csr_access_helper::DONE_DMA_LOAD,
                    "G7_Y1_DMA_LOAD_OWNER"
                );

                repeat (2) @(posedge csr_vif.clk);
                monitor_done = 1'b1;
            end
        join

        if (!load_busy_seen) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y1/LOAD_OWNER_NOT_BUSY",
                "DMA load owner was never observed busy during LOAD->STORE cross-owner probe")
        end

        if (store_busy_seen) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y1/STORE_LAUNCHED",
                "DMA store became busy even though adjacent START_DMA_STORE was required to be rejected")
        end

        if (overlap_seen) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y1/OVERLAP_LOAD_OWNER",
                "Observed illegal simultaneous DMA load/store busy during LOAD->STORE probe")
        end

        `uvm_info("CODE_COV_C1P2_G7_Y1/LOAD_BLOCKS_STORE_PASS",
            $sformatf("Adjacent START_DMA_STORE rejected with REJ_DMA_STORE_BUSY: dma_load_busy_seen=%0d dma_store_busy_seen=%0d overlap_seen=%0d",
                load_busy_seen,
                store_busy_seen,
                overlap_seen),
            UVM_MEDIUM)

        // --------------------------------------------------------
        // Probe B:
        //   DMA Store owns Port0.
        //   Adjacent START_DMA_LOAD must be rejected.
        // --------------------------------------------------------
        csr_clear_sticky_status();

        csr_write_dma_load_config(
            DMA_SRC_A_BASE,
            32'h0000_0000,
            8,
            "G7_Y1_ADJACENT_LOAD"
        );

        csr_write_dma_store_config(
            scratchpad_c_base,
            DMA_DST_C_BASE,
            64
        );

        load_busy_seen  = 1'b0;
        store_busy_seen = 1'b0;
        overlap_seen    = 1'b0;
        monitor_done    = 1'b0;

        fork
            begin : g7_y1_store_owner_monitor
                while (!monitor_done) begin
                    @(posedge csr_vif.clk);

                    if (vif.dma_load_busy) begin
                        load_busy_seen = 1'b1;
                    end

                    if (vif.dma_store_busy) begin
                        store_busy_seen = 1'b1;
                    end

                    if (vif.dma_load_busy && vif.dma_store_busy) begin
                        overlap_seen = 1'b1;
                    end
                end
            end

            begin : g7_y1_store_owner_sequence
                csr_start_dma_store();

                `uvm_info("CODE_COV_C1P2_G7_Y1/STORE_OWNER_START",
                    "START_DMA_STORE write completed; issuing START_DMA_LOAD immediately with no busy poll or inserted delay",
                    UVM_MEDIUM)

                csr_start_dma_load("G7_Y1_ADJACENT_LOAD");

                repeat (2) @(posedge csr_vif.clk);

                csr_expect_p14_reject_bit(
                    C1D1_P14_REJ_DMA_LOAD_BUSY,
                    "G7-Y1 START_DMA_LOAD while DMA store owns Port0"
                );

                csr_clear_p14_reject_status(
                    "after G7-Y1 STORE-owner blocks LOAD reject"
                );

                csr_poll_done_bit(
                    done_timeout_cycles,
                    ai_accel_csr_access_helper::DONE_DMA_STORE,
                    "G7_Y1_DMA_STORE_OWNER"
                );

                repeat (2) @(posedge csr_vif.clk);
                monitor_done = 1'b1;
            end
        join

        if (!store_busy_seen) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y1/STORE_OWNER_NOT_BUSY",
                "DMA store owner was never observed busy during STORE->LOAD cross-owner probe")
        end

        if (load_busy_seen) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y1/LOAD_LAUNCHED",
                "DMA load became busy even though adjacent START_DMA_LOAD was required to be rejected")
        end

        if (overlap_seen) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y1/OVERLAP_STORE_OWNER",
                "Observed illegal simultaneous DMA load/store busy during STORE->LOAD probe")
        end

        `uvm_info("CODE_COV_C1P2_G7_Y1/STORE_BLOCKS_LOAD_PASS",
            $sformatf("Adjacent START_DMA_LOAD rejected with REJ_DMA_LOAD_BUSY: dma_store_busy_seen=%0d dma_load_busy_seen=%0d overlap_seen=%0d",
                store_busy_seen,
                load_busy_seen,
                overlap_seen),
            UVM_MEDIUM)

        csr_clear_sticky_status();

        `uvm_info("CODE_COV_C1P2_G7_Y1/PASS",
            "DMA load/store cross-owner mutual exclusion PASS",
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.1-D1 P14 DMA reject probes
    // ------------------------------------------------------------
    task automatic run_d1_dma_load_store_reject_probes(
        input logic [31:0] scratchpad_c_base
    );
    begin
        csr_clear_sticky_status();

        // Zero-length DMA load reject.
        csr_write_dma_load_config(DMA_SRC_A_BASE, 32'h0000_0000, 0, "D1_ZERO_LOAD");
        csr_start_dma_load("D1_ZERO_LOAD");
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_p14_reject_bit(C1D1_P14_REJ_ZERO_LENGTH,
            "START_DMA_LOAD with zero beats");
        csr_clear_p14_reject_status("after zero-beat DMA load reject");

        // Accepted DMA load remains active while a second START is rejected.
        csr_write_dma_load_config(DMA_SRC_A_BASE, 32'h0000_0000, 8, "D1_BUSY_LOAD");
        csr_start_dma_load("D1_BUSY_LOAD");
        csr_wait_p14_status_bit(C1D1_P14_STATUS_DMA_LOAD_BUSY,
            done_timeout_cycles, "DMA load before busy-start reject");
        csr_start_dma_load("D1_BUSY_LOAD_SECOND_START");
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_p14_reject_bit(C1D1_P14_REJ_DMA_LOAD_BUSY,
            "START_DMA_LOAD while DMA load busy");
        csr_clear_p14_reject_status("after DMA load busy reject");
        csr_poll_done_bit(done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_DMA_LOAD,
            "D1_DMA_LOAD_BUSY_OWNER");

        csr_clear_sticky_status();

        // Zero-length DMA store reject.
        csr_write_dma_store_config(scratchpad_c_base, DMA_DST_C_BASE, 0);
        csr_start_dma_store();
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_p14_reject_bit(C1D1_P14_REJ_ZERO_LENGTH,
            "START_DMA_STORE with zero byte count");
        csr_clear_p14_reject_status("after zero-byte DMA store reject");

        // Accepted DMA store remains active while a second START is rejected.
        csr_write_dma_store_config(scratchpad_c_base, DMA_DST_C_BASE, 64);
        csr_start_dma_store();
        csr_wait_p14_status_bit(C1D1_P14_STATUS_DMA_STORE_BUSY,
            done_timeout_cycles, "DMA store before busy-start reject");
        csr_start_dma_store();
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_p14_reject_bit(C1D1_P14_REJ_DMA_STORE_BUSY,
            "START_DMA_STORE while DMA store busy");
        csr_clear_p14_reject_status("after DMA store busy reject");
        csr_poll_done_bit(done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_DMA_STORE,
            "D1_DMA_STORE_BUSY_OWNER");

        csr_clear_sticky_status();
        `uvm_info("CODE_COV_C1D1/P14_DMA_REJECT_PASS",
            "P14 DMA load/store zero-length and genuine-busy reject probes PASS",
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.1-D2 P14 genuine DMA-store error propagation
    // ------------------------------------------------------------
    task automatic run_d2_dma_store_error_probe(
        input logic [31:0] scratchpad_c_base,
        input int unsigned byte_count
    );
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] expected_error;
        logic [31:0] expected_done;
        int unsigned cnt;
    begin
        expected_error = 32'h0000_0001 << 3;
        expected_done  = 32'h0000_0001 << ai_accel_csr_access_helper::DONE_DMA_STORE;

        csr_clear_sticky_status();
        repeat (2) @(posedge csr_vif.clk);

        vif.dma_dst_set_bresp_error(1'b1, 0);
        csr_write_dma_store_config(scratchpad_c_base, DMA_DST_C_BASE, byte_count);
        csr_start_dma_store();

        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);

            if (reject_status != 32'h0000_0000) begin
                vif.dma_dst_set_bresp_error(1'b0, -1);
                `uvm_fatal("CODE_COV_C1D2/P14_DMA_STORE_REJECT",
                    $sformatf("Unexpected P14 reject during genuine DMA-store BRESP error probe: reject=0x%08h status=0x%08h",
                        reject_status, status))
            end

            if ((error_status != 32'h0000_0000) && (error_status != expected_error)) begin
                vif.dma_dst_set_bresp_error(1'b0, -1);
                `uvm_fatal("CODE_COV_C1D2/P14_DMA_STORE_BAD_ERROR",
                    $sformatf("Unexpected P14 error bits during DMA-store BRESP probe: expected=0x%08h actual=0x%08h",
                        expected_error, error_status))
            end

            if (error_status == expected_error) begin
                break;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > done_timeout_cycles) begin
                vif.dma_dst_set_bresp_error(1'b0, -1);
                `uvm_fatal("CODE_COV_C1D2/P14_DMA_STORE_TIMEOUT",
                    $sformatf("Timed out waiting for P14 DMA-store error after %0d cycles", done_timeout_cycles))
            end
        end

        vif.dma_dst_set_bresp_error(1'b0, -1);

        cnt = 0;
        while (status[C1D1_P14_STATUS_DMA_STORE_BUSY]) begin
            @(posedge csr_vif.clk);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            cnt++;
            if (cnt > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1D2/P14_DMA_STORE_BUSY_TIMEOUT",
                    "DMA-store engine remained busy after genuine BRESP error")
            end
        end

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DONE_STATUS,
            expected_done
        );

        // dma_store_engine intentionally holds store_error through DONE/IDLE
        // and clears it only on the next accepted store_start.
        csr_write_dma_store_config(scratchpad_c_base, DMA_DST_C_BASE, byte_count);
        csr_start_dma_store();

        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);

            if (reject_status != 32'h0000_0000) begin
                `uvm_fatal("CODE_COV_C1D2/P14_DMA_STORE_RECOVERY_REJECT",
                    $sformatf("Recovery DMA-store start was rejected: reject=0x%08h status=0x%08h",
                        reject_status, status))
            end

            if (status[C1D1_P14_STATUS_DMA_STORE_BUSY] ||
                ((done_status & expected_done) != 32'h0000_0000)) begin
                break;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1D2/P14_DMA_STORE_RECOVERY_START_TIMEOUT",
                    "Recovery DMA-store operation never became active or completed")
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
            `uvm_fatal("CODE_COV_C1D2/P14_DMA_STORE_CLEAR",
                $sformatf("P14 sticky cleanup failed after DMA-store recovery re-arm: error=0x%08h reject=0x%08h",
                    error_status, reject_status))
        end

        csr_poll_done_bit(
            done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_DMA_STORE,
            "D2_DMA_STORE_RECOVERY"
        );
        csr_clear_sticky_status();

        `uvm_info("CODE_COV_C1D2/P14_DMA_STORE_ERROR_PASS",
            $sformatf("Genuine DMA-store BRESP error propagated to P14 ERROR_STATUS and recovered: observed=0x%08h post_rearm_clear=0x%08h",
                expected_error, error_status),
            UVM_MEDIUM)
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

        `uvm_info("CSR_DMA_SMOKE",
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

        `uvm_info("CSR_DMA_SMOKE",
            "Starting CSR-controlled DMA load + GEMM + DMA store smoke test",
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
            `uvm_fatal("CSR_DMA_SMOKE/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(), c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        if ((get_type_name() == "ai_accel_subsys_csr_dma_load_store_smoke_test") &&
            (selected_case_id == 102)) begin
            run_d1_dma_load_store_reject_probes(profile_item.base_addr_c);
            run_g7_y1_dma_load_store_cross_owner_reject_probe(profile_item.base_addr_c);
            run_d2_dma_store_error_probe(profile_item.base_addr_c, c_bytes);
        end

        run_one_dma_load(
            DMA_SRC_A_BASE,
            profile_item.base_addr_a,
            a_flat.size(),
            "A"
        );

        run_one_dma_load(
            DMA_SRC_B_BASE,
            profile_item.base_addr_b,
            b_flat.size(),
            "B"
        );

        csr_clear_sticky_status();
        csr_write_gemm_config(profile_item);
        csr_start_gemm();
        csr_poll_gemm_done(done_timeout_cycles);
        csr_check_perf_snapshot();

        if ((get_type_name() == "ai_accel_subsys_csr_dma_load_store_smoke_test") &&
            (selected_case_id == 102)) begin
            run_g7_v4_dma_store_aw_w_backpressure_probe(
                profile_item.base_addr_c,
                DMA_DST_C_BASE,
                c_bytes
            );
        end
        else begin
            run_dma_store(
                profile_item.base_addr_c,
                DMA_DST_C_BASE,
                c_bytes
            );
        end

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("CSR_DMA_SMOKE",
            $sformatf("CSR-controlled DMA load + GEMM + DMA store smoke completed: CASE_ID=%0d test_kind=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
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
