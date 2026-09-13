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
    // CODE-COV-C1.2-G7-L2 targeted operand-buffer overflow probe
    //
    // The operand buffer is 1024 bytes per operand and the Direct
    // Stream write path is 64 bits / 8 bytes per beat.  129 beats
    // therefore makes the final beat the first out-of-range write.
    //
    // This probe is intentionally manual-only because the RTL
    // simulation diagnostic emits $error for the expected overflow.
    // Standard regression behavior is unchanged unless the plusarg
    // below is explicitly supplied to the simulator.
    // ------------------------------------------------------------
    localparam int unsigned G7_L2_OPERAND_BUFFER_BYTES = 1024;
    localparam int unsigned G7_L2_OVERFLOW_BEATS =
        (G7_L2_OPERAND_BUFFER_BYTES / BYTES_PER_BEAT) + 1;
    localparam int unsigned G7_L2_OVERFLOW_BYTES =
        G7_L2_OVERFLOW_BEATS * BYTES_PER_BEAT;

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G8-A-R1 operand-buffer tail-read repair validation
    //
    // G7-L3-A proved that a legal final int8 A element could be rejected
    // solely because its 32-bit read container straddled the 1024-byte
    // operand-buffer tail.  M=7, N=1, K=146 keeps the original boundary:
    //
    //   A bytes        = 7 * 146 = 1022
    //   A padded bytes = round_up(1022, 8) = 1024
    //   final A offset = (6 * 146) + 145 = 1021
    //
    // Post-repair, a read is legal when its START byte is in range; upper
    // container lanes beyond the physical buffer tail are zero-filled by
    // gemm_operand_buffer.  The final A element is deliberately changed from
    // 1 to a nonzero marker so the final C result proves that the tail byte
    // participated in the GEMM rather than being silently substituted by 0.
    //
    // Manual enable:
    //   +CODE_COV_G8_A_R1_TAIL_READ
    //
    // The historical +CODE_COV_G7_L3A_TAIL_READ plusarg is retained as a
    // compatibility alias, but now validates repaired behavior instead of an
    // expected read error.
    // ------------------------------------------------------------
    localparam int unsigned G7_L3A_DIM_M = 7;
    localparam int unsigned G7_L3A_DIM_N = 1;
    localparam int unsigned G7_L3A_DIM_K = 146;

    localparam int unsigned G7_L3A_A_BYTES =
        G7_L3A_DIM_M * G7_L3A_DIM_K;
    localparam int unsigned G7_L3A_B_BYTES =
        G7_L3A_DIM_K * G7_L3A_DIM_N;

    localparam int unsigned G7_L3A_A_PADDED_BYTES =
        ((G7_L3A_A_BYTES + BYTES_PER_BEAT - 1) / BYTES_PER_BEAT) * BYTES_PER_BEAT;
    localparam int unsigned G7_L3A_B_PADDED_BYTES =
        ((G7_L3A_B_BYTES + BYTES_PER_BEAT - 1) / BYTES_PER_BEAT) * BYTES_PER_BEAT;

    localparam int unsigned G7_L3A_A_BEATS =
        G7_L3A_A_PADDED_BYTES / BYTES_PER_BEAT;
    localparam int unsigned G7_L3A_B_BEATS =
        G7_L3A_B_PADDED_BYTES / BYTES_PER_BEAT;

    localparam logic [31:0] G7_L3A_SRC_A_BASE = 32'h0000_0000;
    localparam logic [31:0] G7_L3A_SRC_B_BASE = 32'h0000_0400;

    localparam logic [31:0] G7_L3A_BASE_A = 32'h0000_0000;
    localparam logic [31:0] G7_L3A_BASE_B = 32'h0000_0800;
    localparam logic [31:0] G7_L3A_BASE_C = 32'h0000_1000;

    localparam logic [7:0] G8_R1_TAIL_MARKER = 8'h07;

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G7-M2 targeted write-adapter address-wrap probe
    //
    // The Direct Stream launch contract checks nonzero beats, alignment,
    // and operand selection, but it does not reject a transfer whose
    // logical destination range wraps the 32-bit address space.
    //
    // With a 64-bit / 8-byte write beat:
    //
    //   dst_base = 0xFFFF_FFF8
    //   beats    = 2
    //
    // Beat 0:
    //   wr_addr = 0xFFFF_FFF8
    //   local   = 0
    //   translation valid
    //
    // Beat 1:
    //   wr_addr wraps to 0x0000_0000
    //   wr_addr < operand_base_addr
    //   addr_not_underflow = 0
    //   translation invalid -> accept-and-drop
    //
    // This probe is manual-only because
    // gemm_operand_buffer_write_adapter intentionally emits a simulation
    // $error when drop_fire is observed.
    // ------------------------------------------------------------
    localparam logic [31:0] G7_M2_SRC_BASE      = 32'h0000_0000;
    localparam logic [31:0] G7_M2_WRAP_DST_BASE = 32'hFFFF_FFF8;
    localparam int unsigned G7_M2_WRAP_BEATS     = 2;
    localparam int unsigned G7_M2_WRAP_BYTES =
        G7_M2_WRAP_BEATS * BYTES_PER_BEAT;

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G8-A-R2 Direct Stream operand-readiness repair validation
    //
    // Historical G7-N2 proved that P14 START_GEMM could accept Direct Stream
    // mode before either operand had completed preload.  The router then
    // returned synthetic zero-data responses for the invalid operand reads,
    // allowing GEMM to reach DONE without a host-visible error.
    //
    // R2 changes the contract at the command-acceptance boundary:
    //
    //   Direct Stream mode + A/B not ready
    //     -> no GEMM launch
    //     -> CSR_CMD_REJECT_STATUS[5]
    //
    // This probe must execute before any Direct Stream A/B preload in the
    // CASE_ID=102 carrier.  The normal representative flow later preloads A/B
    // and proves that the synchronized readiness gate does not false-reject a
    // legal launch.
    //
    // Manual enable:
    //   +CODE_COV_G8_A_R2_NO_PRELOAD_REJECT
    //
    // The historical +CODE_COV_G7_N2_NO_PRELOAD_INVALID_READ plusarg is
    // retained as a compatibility alias, but now validates repaired rejection
    // behavior rather than intentionally running the invalid-read path.
    // ------------------------------------------------------------
    localparam int unsigned G7_N2_DIM_M = 1;
    localparam int unsigned G7_N2_DIM_N = 1;
    localparam int unsigned G7_N2_DIM_K = 1;

    localparam logic [31:0] G7_N2_BASE_A = 32'h0000_0000;
    localparam logic [31:0] G7_N2_BASE_B = 32'h0000_0100;
    localparam logic [31:0] G7_N2_BASE_C = 32'h0000_0300;

    localparam int unsigned G8_R2_REJ_GEMM_OPERAND_NOT_READY_BIT = 5;
    localparam logic [31:0] G8_R2_REJ_GEMM_OPERAND_NOT_READY_MASK =
        (32'h0000_0001 << G8_R2_REJ_GEMM_OPERAND_NOT_READY_BIT);

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G8-A-R3-B
    // Direct-Stream committed-extent / capacity prelaunch validation
    //
    // R3-B converts the former Pass 4-B runtime-gap probes into pre-launch
    // rejection checks.  A/B can both report completed/loaded, yet the
    // committed preload extent can still be smaller than the footprint
    // required by the selected GEMM dimensions.  The same launch guard also
    // rejects dimension footprints beyond the physical 1024-byte A/B buffers.
    //
    // This R3-B suite is part of the existing CASE_ID=102 carrier so the
    // repaired P14 extent/capacity paths remain represented in the normal
    // 150-test full-regression UCDB without adding a new regression item.
    //
    // Required P14 precedence:
    //   busy -> zero dimension -> not-ready(bit5) -> extent(bit6) -> launch
    // ------------------------------------------------------------
    localparam int unsigned G8_P4B_OPERAND_BUFFER_BYTES = 1024;

    localparam int unsigned G8_R3_REJ_GEMM_OPERAND_EXTENT_BIT = 6;
    localparam logic [31:0] G8_R3_REJ_GEMM_OPERAND_EXTENT_MASK =
        (32'h0000_0001 << G8_R3_REJ_GEMM_OPERAND_EXTENT_BIT);

    // Successful, but intentionally undersized, preload.
    localparam int unsigned G8_P4B_SHORT_DIM_M = 1;
    localparam int unsigned G8_P4B_SHORT_DIM_N = 1;
    localparam int unsigned G8_P4B_SHORT_DIM_K = 16;
    localparam int unsigned G8_P4B_SHORT_REQUIRED_A_BYTES =
        G8_P4B_SHORT_DIM_M * G8_P4B_SHORT_DIM_K;
    localparam int unsigned G8_P4B_SHORT_REQUIRED_B_BYTES =
        G8_P4B_SHORT_DIM_K * G8_P4B_SHORT_DIM_N;
    localparam int unsigned G8_P4B_SHORT_PRELOAD_BYTES = 8;

    localparam logic [31:0] G8_P4B_SHORT_SRC_A_BASE = 32'h0000_0000;
    localparam logic [31:0] G8_P4B_SHORT_SRC_B_BASE = 32'h0000_0100;
    localparam logic [31:0] G8_P4B_SHORT_BASE_A     = 32'h0000_0000;
    localparam logic [31:0] G8_P4B_SHORT_BASE_B     = 32'h0000_0100;
    localparam logic [31:0] G8_P4B_SHORT_BASE_C     = 32'h0000_0200;

    // A footprint exceeds physical capacity while B remains sufficient.
    localparam int unsigned G8_P4B_CAP_DIM_M = 7;
    localparam int unsigned G8_P4B_CAP_DIM_N = 1;
    localparam int unsigned G8_P4B_CAP_DIM_K = 147;
    localparam int unsigned G8_P4B_CAP_REQUIRED_A_BYTES =
        G8_P4B_CAP_DIM_M * G8_P4B_CAP_DIM_K;
    localparam int unsigned G8_P4B_CAP_REQUIRED_B_BYTES =
        G8_P4B_CAP_DIM_K * G8_P4B_CAP_DIM_N;
    localparam int unsigned G8_P4B_CAP_A_PRELOAD_BYTES =
        G8_P4B_OPERAND_BUFFER_BYTES;
    localparam int unsigned G8_P4B_CAP_B_PADDED_BYTES =
        ((G8_P4B_CAP_REQUIRED_B_BYTES + BYTES_PER_BEAT - 1) / BYTES_PER_BEAT) *
        BYTES_PER_BEAT;

    // Symmetric B footprint exceeds physical capacity while A is sufficient.
    localparam int unsigned G8_P4B_BCAP_DIM_M = 1;
    localparam int unsigned G8_P4B_BCAP_DIM_N = 7;
    localparam int unsigned G8_P4B_BCAP_DIM_K = 147;
    localparam int unsigned G8_P4B_BCAP_REQUIRED_A_BYTES =
        G8_P4B_BCAP_DIM_M * G8_P4B_BCAP_DIM_K;
    localparam int unsigned G8_P4B_BCAP_REQUIRED_B_BYTES =
        G8_P4B_BCAP_DIM_K * G8_P4B_BCAP_DIM_N;
    localparam int unsigned G8_P4B_BCAP_A_PADDED_BYTES =
        ((G8_P4B_BCAP_REQUIRED_A_BYTES + BYTES_PER_BEAT - 1) / BYTES_PER_BEAT) *
        BYTES_PER_BEAT;
    localparam int unsigned G8_P4B_BCAP_B_PRELOAD_BYTES =
        G8_P4B_OPERAND_BUFFER_BYTES;

    // Exact-capacity positive boundary: A footprint is exactly 1024 bytes.
    localparam int unsigned G8_P4B_EXACT_DIM_M = 8;
    localparam int unsigned G8_P4B_EXACT_DIM_N = 1;
    localparam int unsigned G8_P4B_EXACT_DIM_K = 128;
    localparam int unsigned G8_P4B_EXACT_REQUIRED_A_BYTES =
        G8_P4B_EXACT_DIM_M * G8_P4B_EXACT_DIM_K;
    localparam int unsigned G8_P4B_EXACT_REQUIRED_B_BYTES =
        G8_P4B_EXACT_DIM_K * G8_P4B_EXACT_DIM_N;

    localparam logic [31:0] G8_P4B_CAP_SRC_A_BASE = 32'h0000_0000;
    localparam logic [31:0] G8_P4B_CAP_SRC_B_BASE = 32'h0000_0400;
    localparam logic [31:0] G8_P4B_CAP_BASE_A     = 32'h0000_0000;
    localparam logic [31:0] G8_P4B_CAP_BASE_B     = 32'h0000_0800;
    localparam logic [31:0] G8_P4B_CAP_BASE_C     = 32'h0000_0200;

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

    task automatic prepare_g7_l2_overflow_source(
        input logic [31:0] base_addr,
        input logic [7:0]  seed,
        input string       tag
    );
        int unsigned i;
        logic [7:0] byte_value;
    begin
        for (i = 0; i < G7_L2_OVERFLOW_BYTES; i++) begin
            byte_value = seed + i;
            vif.dma_src_mem_write_byte(
                base_addr + 32'(i),
                byte_value
            );
        end

        `uvm_info("CODE_COV_C1_2G7_L2/SRC",
            $sformatf("Prepared %s overflow source: base=0x%08h bytes=%0d beats=%0d",
                tag, base_addr, G7_L2_OVERFLOW_BYTES, G7_L2_OVERFLOW_BEATS),
            UVM_MEDIUM)
    end
    endtask

    task automatic prepare_g7_l3a_tail_read_source();
        int unsigned i;
        logic [7:0] byte_value;
    begin
        vif.dma_src_mem_clear();
        vif.dma_dst_mem_clear();

        vif.dma_src_set_rresp_error(1'b0, -1);
        vif.axis_src_set_rresp_error(1'b0, -1);
        vif.ds_src_set_rresp_error(1'b0, -1);
        vif.dma_dst_set_bresp_error(1'b0, -1);

        // Use deterministic nonzero operand data for the real matrix
        // footprint and zero-fill only the stream-beat padding bytes.
        // The final real A byte is a distinct marker.  With B all ones this
        // makes the final output row differ from the first six rows, proving
        // that the legal tail byte was actually consumed by GEMM.
        for (i = 0; i < G7_L3A_A_PADDED_BYTES; i++) begin
            if (i >= G7_L3A_A_BYTES) begin
                byte_value = 8'h00;
            end
            else if (i == (G7_L3A_A_BYTES - 1)) begin
                byte_value = G8_R1_TAIL_MARKER;
            end
            else begin
                byte_value = 8'h01;
            end

            vif.dma_src_mem_write_byte(
                G7_L3A_SRC_A_BASE + 32'(i),
                byte_value
            );
        end

        for (i = 0; i < G7_L3A_B_PADDED_BYTES; i++) begin
            byte_value = (i < G7_L3A_B_BYTES) ? 8'h01 : 8'h00;
            vif.dma_src_mem_write_byte(
                G7_L3A_SRC_B_BASE + 32'(i),
                byte_value
            );
        end

        `uvm_info("CODE_COV_C1_2G7_L3A/SRC",
            $sformatf("Prepared tail-read source payloads: A src=0x%08h actual=%0d padded=%0d beats=%0d, B src=0x%08h actual=%0d padded=%0d beats=%0d",
                G7_L3A_SRC_A_BASE,
                G7_L3A_A_BYTES,
                G7_L3A_A_PADDED_BYTES,
                G7_L3A_A_BEATS,
                G7_L3A_SRC_B_BASE,
                G7_L3A_B_BYTES,
                G7_L3A_B_PADDED_BYTES,
                G7_L3A_B_BEATS),
            UVM_MEDIUM)
    end
    endtask

    task automatic prepare_g8_a_pass4b_short_source();
        int unsigned i;
    begin
        vif.dma_src_mem_clear();
        vif.dma_dst_mem_clear();

        vif.dma_src_set_rresp_error(1'b0, -1);
        vif.axis_src_set_rresp_error(1'b0, -1);
        vif.ds_src_set_rresp_error(1'b0, -1);
        vif.dma_dst_set_bresp_error(1'b0, -1);

        for (i = 0; i < G8_P4B_SHORT_PRELOAD_BYTES; i++) begin
            vif.dma_src_mem_write_byte(
                G8_P4B_SHORT_SRC_A_BASE + 32'(i),
                8'h01
            );
            vif.dma_src_mem_write_byte(
                G8_P4B_SHORT_SRC_B_BASE + 32'(i),
                8'h01
            );
        end

        `uvm_info("CODE_COV_C1_2G8_A_PASS4B/SHORT_SRC",
            $sformatf("Prepared undersized Direct-Stream payloads: A=%0d/%0d required bytes, B=%0d/%0d required bytes, all loaded bytes=1",
                G8_P4B_SHORT_PRELOAD_BYTES,
                G8_P4B_SHORT_REQUIRED_A_BYTES,
                G8_P4B_SHORT_PRELOAD_BYTES,
                G8_P4B_SHORT_REQUIRED_B_BYTES),
            UVM_MEDIUM)
    end
    endtask

    task automatic prepare_g8_a_pass4b_capacity_source();
        int unsigned i;
    begin
        vif.dma_src_mem_clear();
        vif.dma_dst_mem_clear();

        vif.dma_src_set_rresp_error(1'b0, -1);
        vif.axis_src_set_rresp_error(1'b0, -1);
        vif.ds_src_set_rresp_error(1'b0, -1);
        vif.dma_dst_set_bresp_error(1'b0, -1);

        // Populate the entire legal physical source footprint for both
        // operands.  Individual subcases choose how many bytes/beats to
        // commit, so the probe varies only the architectural extent and not
        // source-memory availability.
        for (i = 0; i < G8_P4B_OPERAND_BUFFER_BYTES; i++) begin
            vif.dma_src_mem_write_byte(
                G8_P4B_CAP_SRC_A_BASE + 32'(i),
                8'h01
            );
            vif.dma_src_mem_write_byte(
                G8_P4B_CAP_SRC_B_BASE + 32'(i),
                8'h01
            );
        end

        `uvm_info("CODE_COV_C1_2G8_A_R3_B/CAP_SRC",
            $sformatf("Prepared full legal source backing for A/B: %0d bytes per operand",
                G8_P4B_OPERAND_BUFFER_BYTES),
            UVM_MEDIUM)
    end
    endtask

    task automatic prepare_g7_m2_wrap_source();
        int unsigned i;
        logic [7:0] byte_value;
    begin
        // D2 intentionally injects a Direct Stream source error earlier in
        // this carrier.  Explicitly return every source/destination error
        // model to its normal state before the M2 address-wrap probe.
        vif.dma_src_set_rresp_error(1'b0, -1);
        vif.axis_src_set_rresp_error(1'b0, -1);
        vif.ds_src_set_rresp_error(1'b0, -1);
        vif.dma_dst_set_bresp_error(1'b0, -1);

        for (i = 0; i < G7_M2_WRAP_BYTES; i++) begin
            byte_value = 8'hC0 + i[7:0];
            vif.dma_src_mem_write_byte(
                G7_M2_SRC_BASE + 32'(i),
                byte_value
            );
        end

        `uvm_info("CODE_COV_C1_2G7_M2/SRC",
            $sformatf("Prepared address-wrap source payload: src=0x%08h bytes=%0d beats=%0d",
                G7_M2_SRC_BASE,
                G7_M2_WRAP_BYTES,
                G7_M2_WRAP_BEATS),
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
    // CODE-COV-C1.2-G7-L2 operand-buffer write-overflow probe
    //
    // This task intentionally drives one beat beyond the selected
    // operand-buffer capacity.  The expected P14 Direct Stream error
    // is checked architecturally.  The gemm_operand_buffer simulation
    // diagnostic is intentionally NOT suppressed or downgraded.
    // ------------------------------------------------------------
    task automatic run_g7_l2_ds_operand_overflow_probe(
        input logic [31:0] src_base,
        input logic [31:0] dst_base,
        input logic        operand_sel,
        input string       tag
    );
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] expected_error;
        logic [31:0] expected_done;
        int unsigned cnt;
    begin
        expected_error = 32'h0000_0001 << 2;
        expected_done  = 32'h0000_0001 << ai_accel_csr_access_helper::DONE_DS_LOAD;

        csr_clear_sticky_status();
        repeat (2) @(posedge csr_vif.clk);

        csr_write_ds_load_config(
            src_base,
            dst_base,
            G7_L2_OVERFLOW_BEATS,
            operand_sel,
            {"G7_L2_", tag, "_OVERFLOW"}
        );

        `uvm_info("CODE_COV_C1_2G7_L2/START",
            $sformatf("Starting %s operand-buffer overflow probe: operand=%0d dst=0x%08h beats=%0d first_overflow_byte=%0d",
                tag, operand_sel, dst_base, G7_L2_OVERFLOW_BEATS, G7_L2_OPERAND_BUFFER_BYTES),
            UVM_MEDIUM)

        csr_start_ds_load({"G7_L2_", tag, "_OVERFLOW"});

        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);

            if (reject_status != 32'h0000_0000) begin
                `uvm_fatal("CODE_COV_C1_2G7_L2/REJECT",
                    $sformatf("%s overflow probe was unexpectedly rejected: reject=0x%08h status=0x%08h",
                        tag, reject_status, status))
            end

            if ((error_status != 32'h0000_0000) &&
                (error_status != expected_error)) begin
                `uvm_fatal("CODE_COV_C1_2G7_L2/BAD_ERROR",
                    $sformatf("%s overflow probe observed unexpected P14 error bits: expected=0x%08h actual=0x%08h",
                        tag, expected_error, error_status))
            end

            if (error_status == expected_error) begin
                break;
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1_2G7_L2/ERROR_TIMEOUT",
                    $sformatf("Timed out waiting for %s operand-buffer overflow to propagate after %0d cycles",
                        tag, done_timeout_cycles))
            end
        end

        // Wait for the failed Direct Stream transaction to retire before
        // attempting recovery.  At this point the CSR sticky error is still
        // asserted because the lower operand-buffer error source is sticky.
        cnt = 0;
        while (status[C1D1_P14_STATUS_DS_LOAD_BUSY]) begin
            @(posedge csr_vif.clk);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            cnt++;

            if (cnt > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1_2G7_L2/BUSY_TIMEOUT",
                    $sformatf("%s Direct Stream engine remained busy after operand-buffer overflow", tag))
            end
        end

        // Clear only DONE before re-arm.  Do not W1C ERROR yet because the
        // lower operand-buffer sticky source is still asserted.
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DONE_STATUS,
            expected_done
        );

        // Mirror the proven D2 recovery ordering.  The next same-operand
        // Direct Stream start reaches C_START, which asserts
        // operand_buf_clear_status plus clear_a/clear_b.  Only after that
        // lower source is cleared is it safe to W1C CSR_ERROR_STATUS.
        csr_write_ds_load_config(
            src_base,
            dst_base,
            1,
            operand_sel,
            {"G7_L2_", tag, "_RECOVERY"}
        );
        csr_start_ds_load({"G7_L2_", tag, "_RECOVERY"});

        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);

            if (reject_status != 32'h0000_0000) begin
                `uvm_fatal("CODE_COV_C1_2G7_L2/RECOVERY_REJECT",
                    $sformatf("%s overflow recovery start was rejected: reject=0x%08h status=0x%08h",
                        tag, reject_status, status))
            end

            if (status[C1D1_P14_STATUS_DS_LOAD_BUSY] ||
                ((done_status & expected_done) != 32'h0000_0000)) begin
                break;
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1_2G7_L2/RECOVERY_START_TIMEOUT",
                    $sformatf("%s overflow recovery never became active or completed", tag))
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

        if ((error_status != 32'h0000_0000) ||
            (reject_status != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1_2G7_L2/CLEAR",
                $sformatf("%s overflow/recovery sticky cleanup failed: error=0x%08h reject=0x%08h",
                    tag, error_status, reject_status))
        end

        csr_poll_done_bit(
            done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_DS_LOAD,
            {"G7_L2_", tag, "_RECOVERY"}
        );
        csr_clear_sticky_status();

        `uvm_info("CODE_COV_C1_2G7_L2/EXPECTED_ERROR_PASS",
            $sformatf("%s operand-buffer overflow propagated and recovered as expected: operand=%0d beats=%0d P14_ERROR=0x%08h",
                tag, operand_sel, G7_L2_OVERFLOW_BEATS, expected_error),
            UVM_MEDIUM)
    end
    endtask

    task automatic run_g7_l2_write_overflow_probes(
        input ai_accel_subsys_seq_item profile_item,
        input int signed               a_flat[],
        input int signed               b_flat[]
    );
    begin
        `uvm_info("CODE_COV_C1_2G7_L2",
            $sformatf("Manual targeted probe enabled: operand_buffer_bytes=%0d bytes_per_beat=%0d overflow_beats=%0d. Expected RTL $error diagnostics are intentionally preserved.",
                G7_L2_OPERAND_BUFFER_BYTES, BYTES_PER_BEAT, G7_L2_OVERFLOW_BEATS),
            UVM_MEDIUM)

        prepare_g7_l2_overflow_source(DS_SRC_A_BASE, 8'hA0, "A");
        run_g7_l2_ds_operand_overflow_probe(
            DS_SRC_A_BASE,
            profile_item.base_addr_a,
            OPERAND_A,
            "A"
        );

        prepare_g7_l2_overflow_source(DS_SRC_B_BASE, 8'hB0, "B");
        run_g7_l2_ds_operand_overflow_probe(
            DS_SRC_B_BASE,
            profile_item.base_addr_b,
            OPERAND_B,
            "B"
        );

        // The synthetic 1032-byte sources overlap the normal compact
        // payload regions.  Restore the original A/B source payloads so
        // the representative GEMM + DMA-store flow below remains unchanged.
        prepare_direct_stream_source_and_destination(a_flat, b_flat);

        `uvm_info("CODE_COV_C1_2G7_L2/PASS",
            "A/B 129-beat operand-buffer overflow, architectural error propagation, cleanup, and recovery probes completed",
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G8-A-R2 no-preload rejection validation
    // ------------------------------------------------------------
    task automatic run_g8_a_r2_no_preload_reject_probe();
        ai_accel_subsys_seq_item g8_r2_profile;
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] reject_after_clear;
    begin
        g8_r2_profile = ai_accel_subsys_seq_item::type_id::create("g8_r2_profile");

        g8_r2_profile.case_id           = selected_case_id;
        g8_r2_profile.base_addr_a       = G7_N2_BASE_A;
        g8_r2_profile.base_addr_b       = G7_N2_BASE_B;
        g8_r2_profile.base_addr_c       = G7_N2_BASE_C;
        g8_r2_profile.dim_m             = G7_N2_DIM_M;
        g8_r2_profile.dim_n             = G7_N2_DIM_N;
        g8_r2_profile.dim_k             = G7_N2_DIM_K;
        g8_r2_profile.accumulate_enable = 1'b0;

        `uvm_info("CODE_COV_C1_2G8_A_R2/START",
            $sformatf("Post-repair no-preload rejection probe: Direct Stream mode, dim=(%0d,%0d,%0d), A=0x%08h, B=0x%08h, C=0x%08h. No A/B preload is issued before START_GEMM.",
                G7_N2_DIM_M,
                G7_N2_DIM_N,
                G7_N2_DIM_K,
                G7_N2_BASE_A,
                G7_N2_BASE_B,
                G7_N2_BASE_C),
            UVM_MEDIUM)

        // Clear only software-visible sticky state.  The operand buffer is
        // still at reset readiness 0 because no Direct Stream preload command
        // has run in this carrier.
        csr_clear_sticky_status();
        repeat (2) @(posedge csr_vif.clk);

        csr_write_direct_stream_gemm_config(g8_r2_profile);
        csr_start_gemm();

        // Give the old buggy acceptance path ample time to launch and complete
        // a 1x1x1 GEMM.  Post-repair there must be no launch at all.
        repeat (128) @(posedge csr_vif.clk);

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_STATUS,
            status
        );
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

        if (reject_status != G8_R2_REJ_GEMM_OPERAND_NOT_READY_MASK) begin
            `uvm_fatal("CODE_COV_C1_2G8_A_R2/REJECT_MISMATCH",
                $sformatf("Expected only GEMM_OPERAND_NOT_READY_REJECT bit %0d (0x%08h), observed reject=0x%08h status=0x%08h done=0x%08h error=0x%08h",
                    G8_R2_REJ_GEMM_OPERAND_NOT_READY_BIT,
                    G8_R2_REJ_GEMM_OPERAND_NOT_READY_MASK,
                    reject_status,
                    status,
                    done_status,
                    error_status))
        end

        if (done_status != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1_2G8_A_R2/UNEXPECTED_DONE",
                $sformatf("No-preload START_GEMM must not launch or complete: DONE_STATUS=0x%08h",
                    done_status))
        end

        if (error_status != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1_2G8_A_R2/UNEXPECTED_ERROR",
                $sformatf("Operand readiness is a pre-launch reject, not CSR_ERROR_STATUS: ERROR_STATUS=0x%08h",
                    error_status))
        end

        if (status[0] || status[8] || status[12] || !status[13]) begin
            `uvm_fatal("CODE_COV_C1_2G8_A_R2/STATUS_MISMATCH",
                $sformatf("Rejected no-preload GEMM must remain idle with ANY_ERROR from reject only: STATUS=0x%08h",
                    status))
        end

        `uvm_info("CODE_COV_C1_2G8_A_R2/REJECT_PASS",
            $sformatf("No-preload Direct-Stream START_GEMM rejected before launch: STATUS=0x%08h DONE=0x%08h ERROR=0x%08h REJECT=0x%08h",
                status,
                done_status,
                error_status,
                reject_status),
            UVM_MEDIUM)

        csr_clear_sticky_status();
        repeat (2) @(posedge csr_vif.clk);

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS,
            reject_after_clear
        );

        if (reject_after_clear != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1_2G8_A_R2/CLEAR_FAIL",
                $sformatf("CLEAR_ERROR did not clear operand-readiness reject: REJECT_STATUS=0x%08h",
                    reject_after_clear))
        end

        `uvm_info("CODE_COV_C1_2G8_A_R2/CLEAR_PASS",
            "Operand-readiness reject cleared; normal A/B preload + GEMM recovery will be validated by the representative flow",
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G7-M2 write-adapter address-wrap constructive probe
    // ------------------------------------------------------------
    task automatic run_g7_m2_address_wrap_translation_drop_probe(
        input ai_accel_subsys_seq_item profile_item,
        input int signed               normal_a_flat[],
        input int signed               normal_b_flat[]
    );
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] expected_error;
        logic [31:0] expected_done;
        int unsigned cnt;
    begin
        expected_error = 32'h0000_0001 << 2;
        expected_done  = 32'h0000_0001 << ai_accel_csr_access_helper::DONE_DS_LOAD;

        `uvm_info("CODE_COV_C1_2G7_M2",
            $sformatf("Manual targeted address-wrap probe enabled: src=0x%08h dst=0x%08h beats=%0d beat_bytes=%0d. Beat1 is expected to wrap to 0x00000000 and trigger adapter accept-and-drop. Expected RTL $error diagnostic is intentionally preserved.",
                G7_M2_SRC_BASE,
                G7_M2_WRAP_DST_BASE,
                G7_M2_WRAP_BEATS,
                BYTES_PER_BEAT),
            UVM_MEDIUM)

        prepare_g7_m2_wrap_source();

        csr_clear_sticky_status();
        repeat (2) @(posedge csr_vif.clk);

        csr_write_ds_load_config(
            G7_M2_SRC_BASE,
            G7_M2_WRAP_DST_BASE,
            G7_M2_WRAP_BEATS,
            OPERAND_A,
            "G7_M2_ADDR_WRAP_DROP"
        );

        `uvm_info("CODE_COV_C1_2G7_M2/START",
            $sformatf("Starting accepted Direct Stream address-wrap transfer: beat0 dst=0x%08h beat1 dst=0x00000000 operand=A",
                G7_M2_WRAP_DST_BASE),
            UVM_MEDIUM)

        csr_start_ds_load("G7_M2_ADDR_WRAP_DROP");

        // Wait for the adapter/core-side translation error to propagate into
        // the architectural Direct Stream P14 error bit.  This proves the
        // transaction was accepted by the frontend and failed downstream,
        // rather than being rejected by launch prevalidation.
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);

            if (reject_status != 32'h0000_0000) begin
                `uvm_fatal("CODE_COV_C1_2G7_M2/REJECT",
                    $sformatf("Address-wrap probe was unexpectedly rejected: reject=0x%08h status=0x%08h",
                        reject_status, status))
            end

            if ((error_status != 32'h0000_0000) &&
                (error_status != expected_error)) begin
                `uvm_fatal("CODE_COV_C1_2G7_M2/BAD_ERROR",
                    $sformatf("Address-wrap probe observed unexpected P14 error bits: expected=0x%08h actual=0x%08h",
                        expected_error, error_status))
            end

            if (error_status == expected_error) begin
                break;
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1_2G7_M2/ERROR_TIMEOUT",
                    $sformatf("Timed out waiting for address-wrap translation drop to propagate after %0d cycles",
                        done_timeout_cycles))
            end
        end

        // Let the failed transaction retire completely.  Keep ERROR sticky
        // asserted until the same-operand recovery start has cleared the
        // adapter's lower-level sticky error source.
        cnt = 0;
        while (status[C1D1_P14_STATUS_DS_LOAD_BUSY]) begin
            @(posedge csr_vif.clk);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            cnt++;

            if (cnt > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1_2G7_M2/BUSY_TIMEOUT",
                    "Direct Stream engine remained busy after address-wrap translation drop")
            end
        end

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DONE_STATUS,
            expected_done
        );

        // Same ordering proven by D2 and G7-L2:
        //   1) launch a clean same-operand Direct Stream recovery
        //   2) wait until it is active or already complete
        //   3) only then W1C P14 ERROR_STATUS
        //
        // C_START asserts adapter_clear_status and clears the selected
        // operand-buffer status before the recovery loader runs.
        csr_write_ds_load_config(
            G7_M2_SRC_BASE,
            profile_item.base_addr_a,
            1,
            OPERAND_A,
            "G7_M2_ADDR_WRAP_RECOVERY"
        );
        csr_start_ds_load("G7_M2_ADDR_WRAP_RECOVERY");

        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);

            if (reject_status != 32'h0000_0000) begin
                `uvm_fatal("CODE_COV_C1_2G7_M2/RECOVERY_REJECT",
                    $sformatf("Address-wrap recovery start was rejected: reject=0x%08h status=0x%08h",
                        reject_status, status))
            end

            if (status[C1D1_P14_STATUS_DS_LOAD_BUSY] ||
                ((done_status & expected_done) != 32'h0000_0000)) begin
                break;
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1_2G7_M2/RECOVERY_START_TIMEOUT",
                    "Address-wrap recovery never became active or completed")
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

        if ((error_status != 32'h0000_0000) ||
            (reject_status != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1_2G7_M2/CLEAR",
                $sformatf("Address-wrap/recovery sticky cleanup failed: error=0x%08h reject=0x%08h",
                    error_status, reject_status))
        end

        csr_poll_done_bit(
            done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_DS_LOAD,
            "G7_M2_ADDR_WRAP_RECOVERY"
        );
        csr_clear_sticky_status();

        // The M2 source payload overwrote the normal compact CASE_ID=102 A
        // source region.  Restore the representative smoke payload before
        // returning to the normal flow below.
        prepare_direct_stream_source_and_destination(
            normal_a_flat,
            normal_b_flat
        );

        `uvm_info("CODE_COV_C1_2G7_M2/EXPECTED_ERROR_PASS",
            $sformatf("Address-wrap translation drop propagated and recovered as expected: dst_base=0x%08h beats=%0d expected_wrapped_addr=0x00000000 P14_ERROR=0x%08h",
                G7_M2_WRAP_DST_BASE,
                G7_M2_WRAP_BEATS,
                expected_error),
            UVM_MEDIUM)

        `uvm_info("CODE_COV_C1_2G7_M2/PASS",
            "Write-adapter address-wrap accept-and-drop constructive probe completed; normal CASE_ID=102 source payloads restored",
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G8-A-R1 operand-buffer tail-read repair validation
    // ------------------------------------------------------------
    task automatic run_g8_a_r1_tail_read_repair_probe(
        input int signed normal_a_flat[],
        input int signed normal_b_flat[]
    );
        ai_accel_subsys_seq_item g8_r1_profile;
        int signed               expected_c[];
        int signed               actual_c[];
        int unsigned             c_elems;
        int unsigned             c_bytes;
        int unsigned             i;
        logic [31:0]             error_status;
        logic [31:0]             reject_status;
    begin
        g8_r1_profile = ai_accel_subsys_seq_item::type_id::create("g8_r1_profile");

        g8_r1_profile.case_id            = selected_case_id;
        g8_r1_profile.base_addr_a        = G7_L3A_BASE_A;
        g8_r1_profile.base_addr_b        = G7_L3A_BASE_B;
        g8_r1_profile.base_addr_c        = G7_L3A_BASE_C;
        g8_r1_profile.dim_m              = G7_L3A_DIM_M;
        g8_r1_profile.dim_n              = G7_L3A_DIM_N;
        g8_r1_profile.dim_k              = G7_L3A_DIM_K;
        g8_r1_profile.accumulate_enable  = 1'b0;

        c_elems = G7_L3A_DIM_M * G7_L3A_DIM_N;
        c_bytes = c_elems * 4;

        expected_c = new[c_elems];
        for (i = 0; i < c_elems; i++) begin
            expected_c[i] = G7_L3A_DIM_K;
        end

        // Rows 0..5 are all ones.  Row 6 has 145 ones plus the distinct
        // tail marker, while B is all ones.
        expected_c[c_elems - 1] =
            (G7_L3A_DIM_K - 1) + int'(G8_R1_TAIL_MARKER);

        `uvm_info("CODE_COV_C1_2G8_A_R1/START",
            $sformatf("Post-repair legal tail-read validation: dim=(%0d,%0d,%0d) A_bytes=%0d A_padded=%0d A_beats=%0d final_A_offset=%0d tail_marker=%0d B_bytes=%0d B_padded=%0d B_beats=%0d",
                G7_L3A_DIM_M,
                G7_L3A_DIM_N,
                G7_L3A_DIM_K,
                G7_L3A_A_BYTES,
                G7_L3A_A_PADDED_BYTES,
                G7_L3A_A_BEATS,
                G7_L3A_A_BYTES - 1,
                G8_R1_TAIL_MARKER,
                G7_L3A_B_BYTES,
                G7_L3A_B_PADDED_BYTES,
                G7_L3A_B_BEATS),
            UVM_MEDIUM)

        prepare_g7_l3a_tail_read_source();

        // Both preloads are legal.  A occupies exactly the full 1024-byte
        // physical operand-buffer footprint after stream-beat padding.
        run_one_ds_load(
            G7_L3A_SRC_A_BASE,
            G7_L3A_BASE_A,
            G7_L3A_A_BYTES,
            OPERAND_A,
            "G8_R1_A"
        );

        run_one_ds_load(
            G7_L3A_SRC_B_BASE,
            G7_L3A_BASE_B,
            G7_L3A_B_BYTES,
            OPERAND_B,
            "G8_R1_B"
        );

        csr_clear_sticky_status();
        csr_write_direct_stream_gemm_config(g8_r1_profile);

        `uvm_info("CODE_COV_C1_2G8_A_R1/TAIL_CONTRACT",
            $sformatf("Final legal A read starts at absolute=0x%08h local_offset=%0d; 32-bit container spans local bytes [%0d..%0d], with out-of-range upper lane(s) required to zero-fill rather than raise read_error",
                G7_L3A_BASE_A + G7_L3A_A_BYTES - 1,
                G7_L3A_A_BYTES - 1,
                G7_L3A_A_BYTES - 1,
                (G7_L3A_A_BYTES - 1) + 3),
            UVM_MEDIUM)

        csr_start_gemm();
        csr_poll_gemm_done(done_timeout_cycles);
        csr_check_perf_snapshot();

        // There must be no host-visible command/reject error for this legal
        // job.  The result-sensitive tail marker plus the final C compare below
        // provides the architectural proof that the old zero-substitution bug
        // is gone.
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);

        if ((error_status != 32'h0000_0000) ||
            (reject_status != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1_2G8_A_R1/STATUS",
                $sformatf("Legal tail-read GEMM produced unexpected host-visible status: error=0x%08h reject=0x%08h",
                    error_status, reject_status))
        end

        run_dma_store(
            G7_L3A_BASE_C,
            DMA_DST_C_BASE,
            c_bytes
        );

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("CODE_COV_C1_2G8_A_R1/GOLDEN_PASS",
            $sformatf("Tail-read GEMM golden compare PASS: C_words=%0d rows0-5=%0d final_row=%0d (145 ones + tail marker %0d)",
                c_elems,
                G7_L3A_DIM_K,
                expected_c[c_elems - 1],
                G8_R1_TAIL_MARKER),
            UVM_MEDIUM)

        // The manual source payloads overwrite the normal CASE_ID=102 source
        // regions.  Restore them so the representative smoke flow below remains
        // an independent post-repair recovery check.
        prepare_direct_stream_source_and_destination(
            normal_a_flat,
            normal_b_flat
        );

        csr_clear_sticky_status();

        `uvm_info("CODE_COV_C1_2G8_A_R1/PASS",
            "Operand-buffer legal tail-read repair validation PASS; normal CASE_ID=102 source payloads restored for post-probe recovery",
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G8-A Pass 4-B
    // Direct-Stream operand length / capacity prelaunch constructive probe
    // ------------------------------------------------------------
    task automatic check_g8_r3_extent_reject(
        input string                    tag,
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned              required_a_bytes,
        input int unsigned              committed_a_bytes,
        input int unsigned              required_b_bytes,
        input int unsigned              committed_b_bytes
    );
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] reject_after_clear;
        logic [31:0] mac_before;
        logic [31:0] mac_after;
    begin
        csr_clear_sticky_status();
        repeat (2) @(posedge csr_vif.clk);

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_PERF_MAC_COUNT,
            mac_before
        );

        csr_write_direct_stream_gemm_config(profile_item);
        csr_start_gemm();

        // The prelaunch guard must reject immediately.  Keep a generous
        // observation window so the historical buggy path would have time to
        // enter busy or complete a small GEMM.
        repeat (128) @(posedge csr_vif.clk);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DONE_STATUS, done_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_PERF_MAC_COUNT, mac_after);

        if (reject_status != G8_R3_REJ_GEMM_OPERAND_EXTENT_MASK) begin
            `uvm_fatal("CODE_COV_C1_2G8_A_R3_B/REJECT_MISMATCH",
                $sformatf("%s: expected only GEMM_OPERAND_EXTENT_REJECT bit %0d (0x%08h), got reject=0x%08h status=0x%08h done=0x%08h error=0x%08h",
                    tag,
                    G8_R3_REJ_GEMM_OPERAND_EXTENT_BIT,
                    G8_R3_REJ_GEMM_OPERAND_EXTENT_MASK,
                    reject_status,
                    status,
                    done_status,
                    error_status))
        end

        if (reject_status[G8_R2_REJ_GEMM_OPERAND_NOT_READY_BIT]) begin
            `uvm_fatal("CODE_COV_C1_2G8_A_R3_B/PRECEDENCE",
                $sformatf("%s: bit5 NOT_READY must remain clear after successful A/B preload; reject=0x%08h",
                    tag, reject_status))
        end

        if (done_status != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1_2G8_A_R3_B/UNEXPECTED_DONE",
                $sformatf("%s: extent-rejected GEMM must not complete: DONE=0x%08h",
                    tag, done_status))
        end

        if (error_status != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1_2G8_A_R3_B/UNEXPECTED_ERROR",
                $sformatf("%s: extent failure is a prelaunch reject, not CSR_ERROR_STATUS: ERROR=0x%08h",
                    tag, error_status))
        end

        if (status[0] || status[8] || status[12] || !status[13]) begin
            `uvm_fatal("CODE_COV_C1_2G8_A_R3_B/STATUS_MISMATCH",
                $sformatf("%s: rejected GEMM must stay idle with ANY_ERROR from reject only: STATUS=0x%08h",
                    tag, status))
        end

        if (mac_after != mac_before) begin
            `uvm_fatal("CODE_COV_C1_2G8_A_R3_B/MAC_ACTIVITY",
                $sformatf("%s: extent-rejected GEMM changed MAC count: before=%0d after=%0d",
                    tag, mac_before, mac_after))
        end

        `uvm_info("CODE_COV_C1_2G8_A_R3_B/EXTENT_REJECT_PASS",
            $sformatf("%s: prelaunch extent rejection PASS; A required/committed=%0d/%0d bytes, B required/committed=%0d/%0d bytes, REJECT=0x%08h, MAC=%0d",
                tag,
                required_a_bytes,
                committed_a_bytes,
                required_b_bytes,
                committed_b_bytes,
                reject_status,
                mac_after),
            UVM_MEDIUM)

        csr_clear_sticky_status();
        repeat (2) @(posedge csr_vif.clk);
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS,
            reject_after_clear
        );

        if (reject_after_clear != 32'h0000_0000) begin
            `uvm_fatal("CODE_COV_C1_2G8_A_R3_B/CLEAR_FAIL",
                $sformatf("%s: CLEAR_ERROR did not clear extent reject: 0x%08h",
                    tag, reject_after_clear))
        end
    end
    endtask

    task automatic run_g8_a_pass4b_length_capacity_probe(
        input int signed normal_a_flat[],
        input int signed normal_b_flat[]
    );
        ai_accel_subsys_seq_item short_profile;
        ai_accel_subsys_seq_item cap_a_profile;
        ai_accel_subsys_seq_item cap_b_profile;
        ai_accel_subsys_seq_item exact_profile;
        int signed               actual_c[];
        int signed               expected_c[];
        int unsigned             i;
        logic [31:0]             error_status;
        logic [31:0]             reject_status;
    begin
        short_profile = ai_accel_subsys_seq_item::type_id::create("g8_r3_short_profile");
        short_profile.case_id           = selected_case_id;
        short_profile.base_addr_a       = G8_P4B_SHORT_BASE_A;
        short_profile.base_addr_b       = G8_P4B_SHORT_BASE_B;
        short_profile.base_addr_c       = G8_P4B_SHORT_BASE_C;
        short_profile.dim_m             = G8_P4B_SHORT_DIM_M;
        short_profile.dim_n             = G8_P4B_SHORT_DIM_N;
        short_profile.dim_k             = G8_P4B_SHORT_DIM_K;
        short_profile.accumulate_enable = 1'b0;

        cap_a_profile = ai_accel_subsys_seq_item::type_id::create("g8_r3_cap_a_profile");
        cap_a_profile.case_id           = selected_case_id;
        cap_a_profile.base_addr_a       = G8_P4B_CAP_BASE_A;
        cap_a_profile.base_addr_b       = G8_P4B_CAP_BASE_B;
        cap_a_profile.base_addr_c       = G8_P4B_CAP_BASE_C;
        cap_a_profile.dim_m             = G8_P4B_CAP_DIM_M;
        cap_a_profile.dim_n             = G8_P4B_CAP_DIM_N;
        cap_a_profile.dim_k             = G8_P4B_CAP_DIM_K;
        cap_a_profile.accumulate_enable = 1'b0;

        cap_b_profile = ai_accel_subsys_seq_item::type_id::create("g8_r3_cap_b_profile");
        cap_b_profile.case_id           = selected_case_id;
        cap_b_profile.base_addr_a       = G8_P4B_CAP_BASE_A;
        cap_b_profile.base_addr_b       = G8_P4B_CAP_BASE_B;
        cap_b_profile.base_addr_c       = G8_P4B_CAP_BASE_C;
        cap_b_profile.dim_m             = G8_P4B_BCAP_DIM_M;
        cap_b_profile.dim_n             = G8_P4B_BCAP_DIM_N;
        cap_b_profile.dim_k             = G8_P4B_BCAP_DIM_K;
        cap_b_profile.accumulate_enable = 1'b0;

        exact_profile = ai_accel_subsys_seq_item::type_id::create("g8_r3_exact_profile");
        exact_profile.case_id           = selected_case_id;
        exact_profile.base_addr_a       = G8_P4B_CAP_BASE_A;
        exact_profile.base_addr_b       = G8_P4B_CAP_BASE_B;
        exact_profile.base_addr_c       = G8_P4B_CAP_BASE_C;
        exact_profile.dim_m             = G8_P4B_EXACT_DIM_M;
        exact_profile.dim_n             = G8_P4B_EXACT_DIM_N;
        exact_profile.dim_k             = G8_P4B_EXACT_DIM_K;
        exact_profile.accumulate_enable = 1'b0;

        `uvm_info("CODE_COV_C1_2G8_A_R3_B/START",
            "Starting Direct-Stream committed-extent/capacity prelaunch validation",
            UVM_MEDIUM)

        // --------------------------------------------------------
        // 1) Both preloads complete, but both committed extents are short.
        //    This proves R2 boolean readiness is true while R3 extent fails.
        // --------------------------------------------------------
        prepare_g8_a_pass4b_short_source();
        run_one_ds_load(
            G8_P4B_SHORT_SRC_A_BASE,
            G8_P4B_SHORT_BASE_A,
            G8_P4B_SHORT_PRELOAD_BYTES,
            OPERAND_A,
            "G8_R3_SHORT_A"
        );
        run_one_ds_load(
            G8_P4B_SHORT_SRC_B_BASE,
            G8_P4B_SHORT_BASE_B,
            G8_P4B_SHORT_PRELOAD_BYTES,
            OPERAND_B,
            "G8_R3_SHORT_B"
        );
        check_g8_r3_extent_reject(
            "UNDERSIZED_AB",
            short_profile,
            G8_P4B_SHORT_REQUIRED_A_BYTES,
            G8_P4B_SHORT_PRELOAD_BYTES,
            G8_P4B_SHORT_REQUIRED_B_BYTES,
            G8_P4B_SHORT_PRELOAD_BYTES
        );
        `uvm_info("CODE_COV_C1_2G8_A_R3_B/UNDERSIZED_PASS",
            "Successful-but-undersized A/B preloads were rejected before GEMM launch",
            UVM_MEDIUM)

        // --------------------------------------------------------
        // 2) A required footprint is 1029 bytes (> 1024 capacity).
        //    A is fully committed to exactly 1024 bytes; B is sufficient.
        // --------------------------------------------------------
        prepare_g8_a_pass4b_capacity_source();
        run_one_ds_load(
            G8_P4B_CAP_SRC_A_BASE,
            G8_P4B_CAP_BASE_A,
            G8_P4B_CAP_A_PRELOAD_BYTES,
            OPERAND_A,
            "G8_R3_A_CAP_A"
        );
        run_one_ds_load(
            G8_P4B_CAP_SRC_B_BASE,
            G8_P4B_CAP_BASE_B,
            G8_P4B_CAP_B_PADDED_BYTES,
            OPERAND_B,
            "G8_R3_A_CAP_B"
        );
        check_g8_r3_extent_reject(
            "A_OVER_CAPACITY",
            cap_a_profile,
            G8_P4B_CAP_REQUIRED_A_BYTES,
            G8_P4B_CAP_A_PRELOAD_BYTES,
            G8_P4B_CAP_REQUIRED_B_BYTES,
            G8_P4B_CAP_B_PADDED_BYTES
        );
        `uvm_info("CODE_COV_C1_2G8_A_R3_B/A_CAPACITY_PASS",
            "A dimension footprint beyond 1024-byte physical capacity was rejected before GEMM launch",
            UVM_MEDIUM)

        // --------------------------------------------------------
        // 3) Symmetric B capacity proof.
        // --------------------------------------------------------
        prepare_g8_a_pass4b_capacity_source();
        run_one_ds_load(
            G8_P4B_CAP_SRC_A_BASE,
            G8_P4B_CAP_BASE_A,
            G8_P4B_BCAP_A_PADDED_BYTES,
            OPERAND_A,
            "G8_R3_B_CAP_A"
        );
        run_one_ds_load(
            G8_P4B_CAP_SRC_B_BASE,
            G8_P4B_CAP_BASE_B,
            G8_P4B_BCAP_B_PRELOAD_BYTES,
            OPERAND_B,
            "G8_R3_B_CAP_B"
        );
        check_g8_r3_extent_reject(
            "B_OVER_CAPACITY",
            cap_b_profile,
            G8_P4B_BCAP_REQUIRED_A_BYTES,
            G8_P4B_BCAP_A_PADDED_BYTES,
            G8_P4B_BCAP_REQUIRED_B_BYTES,
            G8_P4B_BCAP_B_PRELOAD_BYTES
        );
        `uvm_info("CODE_COV_C1_2G8_A_R3_B/B_CAPACITY_PASS",
            "B dimension footprint beyond 1024-byte physical capacity was rejected before GEMM launch",
            UVM_MEDIUM)

        // --------------------------------------------------------
        // 4) Exact-capacity positive boundary.  A consumes exactly 1024
        //    bytes and B consumes 128 bytes.  Both source payloads are ones,
        //    so every C output must equal K=128.
        // --------------------------------------------------------
        prepare_g8_a_pass4b_capacity_source();
        run_one_ds_load(
            G8_P4B_CAP_SRC_A_BASE,
            G8_P4B_CAP_BASE_A,
            G8_P4B_EXACT_REQUIRED_A_BYTES,
            OPERAND_A,
            "G8_R3_EXACT_A"
        );
        run_one_ds_load(
            G8_P4B_CAP_SRC_B_BASE,
            G8_P4B_CAP_BASE_B,
            G8_P4B_EXACT_REQUIRED_B_BYTES,
            OPERAND_B,
            "G8_R3_EXACT_B"
        );

        csr_clear_sticky_status();
        csr_write_direct_stream_gemm_config(exact_profile);
        csr_start_gemm();
        csr_poll_gemm_done(done_timeout_cycles);
        csr_check_perf_snapshot();

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);
        if ((error_status != 32'h0000_0000) ||
            (reject_status != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1_2G8_A_R3_B/EXACT_STATUS",
                $sformatf("Exact-capacity legal GEMM was rejected/errored: ERROR=0x%08h REJECT=0x%08h",
                    error_status, reject_status))
        end

        vif.dma_dst_mem_clear();
        run_dma_store(
            G8_P4B_CAP_BASE_C,
            DMA_DST_C_BASE,
            G8_P4B_EXACT_DIM_M * G8_P4B_EXACT_DIM_N * 4
        );
        collect_dma_destination_c(
            G8_P4B_EXACT_DIM_M * G8_P4B_EXACT_DIM_N,
            actual_c
        );

        expected_c = new[G8_P4B_EXACT_DIM_M * G8_P4B_EXACT_DIM_N];
        for (i = 0; i < expected_c.size(); i++) begin
            expected_c[i] = G8_P4B_EXACT_DIM_K;
        end
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("CODE_COV_C1_2G8_A_R3_B/EXACT_CAPACITY_PASS",
            $sformatf("Exact-capacity legal Direct-Stream GEMM accepted and golden PASS: A=%0d bytes B=%0d bytes C_words=%0d",
                G8_P4B_EXACT_REQUIRED_A_BYTES,
                G8_P4B_EXACT_REQUIRED_B_BYTES,
                expected_c.size()),
            UVM_MEDIUM)

        // Restore normal CASE_ID=102 source payloads.  R1 legal-tail and the
        // normal representative flow execute later and independently prove
        // that R3 does not over-reject legal padded tails or ordinary jobs.
        prepare_direct_stream_source_and_destination(
            normal_a_flat,
            normal_b_flat
        );
        csr_clear_sticky_status();

        `uvm_info("CODE_COV_C1_2G8_A_R3_B/P14_PASS",
            "P14 extent suite PASS: undersized reject, A/B capacity reject, exact-capacity accept/golden; normal source restored",
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
        bit                      g8_r2_probe_enabled;
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

        g8_r2_probe_enabled =
            (get_type_name() == "ai_accel_subsys_csr_direct_stream_load_store_smoke_test") &&
            (selected_case_id == 102) &&
            ($test$plusargs("CODE_COV_G8_A_R2_NO_PRELOAD_REJECT") ||
             $test$plusargs("CODE_COV_G7_N2_NO_PRELOAD_INVALID_READ"));

        if ((get_type_name() == "ai_accel_subsys_csr_direct_stream_load_store_smoke_test") &&
            (selected_case_id == 102)) begin
            if (g8_r2_probe_enabled) begin
                run_g8_a_r2_no_preload_reject_probe();
            end

            run_g8_a_pass4b_length_capacity_probe(
                a_flat,
                b_flat
            );

            run_d1_ds_reject_probes(profile_item.base_addr_a);
            run_d2_ds_error_probe(profile_item.base_addr_a, a_flat.size());

            if ($test$plusargs("CODE_COV_G7_L2_WRITE_OVERFLOW")) begin
                run_g7_l2_write_overflow_probes(
                    profile_item,
                    a_flat,
                    b_flat
                );
            end

            if ($test$plusargs("CODE_COV_G8_A_R1_TAIL_READ") ||
                $test$plusargs("CODE_COV_G7_L3A_TAIL_READ")) begin
                run_g8_a_r1_tail_read_repair_probe(
                    a_flat,
                    b_flat
                );
            end

            if ($test$plusargs("CODE_COV_G7_M2_ADDR_WRAP_DROP")) begin
                run_g7_m2_address_wrap_translation_drop_probe(
                    profile_item,
                    a_flat,
                    b_flat
                );
            end
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

        if (g8_r2_probe_enabled) begin
            `uvm_info("CODE_COV_C1_2G8_A_R2/RECOVERY_PASS",
                "After operand-readiness reject and clear, normal A/B preloads completed and the legal Direct-Stream GEMM + DMA-store golden compare passed",
                UVM_MEDIUM)
            `uvm_info("CODE_COV_C1_2G8_A_R2/PASS",
                "Direct-Stream operand-readiness pre-launch rejection and legal recovery validation PASS",
                UVM_MEDIUM)
        end

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
