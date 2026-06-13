// File: tb/uvm/test/ai_accel_subsys_csr_queue_mixed_dma_ds_c_rmw_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_MIXED_DMA_DS_C_RMW_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_MIXED_DMA_DS_C_RMW_SMOKE_TEST_SV

// ============================================================
// P20D mixed three-command queue drain smoke
//
// Scope:
//   - Programs three valid 64-byte SQ command entries.
//   - Enables RUN_UNTIL_EMPTY in CSR_QUEUE_CONTROL.
//   - Issues one host START_QUEUE kick.
//   - Verifies the wrapper drains three different command profiles
//     in order while preserving the existing single-active-command
//     execution model:
//       SQ[0] -> DMA descriptor recipe        -> CQ[0]
//       SQ[1] -> Direct Stream descriptor recipe -> CQ[1]
//       SQ[2] -> C RMW descriptor recipe      -> CQ[2]
//   - Verifies all three CQ completion records are committed.
//   - Verifies SQ_HEAD and CQ_TAIL advance to three and the queue
//     reaches drained status.
//   - Compares the final C RMW command result against the full-K
//     software reference.
//
// P20D does not add multi-outstanding execution, out-of-order
// completion, interrupts, or any BRAM / GEMM / DMA / frontend datapath
// change.  It validates mixed in-order auto-drain on top of the P20C
// wrapper-level auto-continue policy.
// ============================================================

class ai_accel_subsys_csr_queue_mixed_dma_ds_c_rmw_smoke_test
    extends ai_accel_subsys_csr_desc_fetch_c_rmw_two_slot_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_mixed_dma_ds_c_rmw_smoke_test)

    localparam int unsigned P20D_SQ_BASE      = 32'h0000_0B00;
    localparam int unsigned P20D_CQ_BASE      = 32'h0000_0800;
    localparam int unsigned P20D_QUEUE_DEPTH  = 4;
    localparam int unsigned P20D_ENTRY_STRIDE = 32'h0000_0040;

    localparam int unsigned P20D_DMA_DESC_BASE   = 32'h0000_0400;
    localparam int unsigned P20D_DS_DESC_BASE    = 32'h0000_0600;
    localparam int unsigned P20D_C_RMW_DESC_BASE = 32'h0000_0800;
    localparam int unsigned P20D_DESC_STRIDE     = 32'h0000_0080;

    // VALID=1, OPCODE=0x01, ENABLE_COMPLETION=1.
    // STOP_AFTER_THIS must remain 0 for RUN_UNTIL_EMPTY auto-drain.
    localparam logic [31:0] P20D_CMD_CONTROL      = 32'h0000_0103;
    localparam logic [31:0] P20D_CMD_DMA_TAG      = 32'hD20D_0000;
    localparam logic [31:0] P20D_CMD_DS_TAG       = 32'hD20D_0001;
    localparam logic [31:0] P20D_CMD_C_RMW_TAG    = 32'hD20D_0002;
    localparam logic [31:0] P20D_COMP_FLAGS       = 32'h0000_0001;

    localparam logic [31:0] P20D_DMA_TAG0         = 32'hD20D_1000;
    localparam logic [31:0] P20D_DMA_TAG1         = 32'hD20D_1001;
    localparam logic [31:0] P20D_DS_TAG0          = 32'hD20D_2000;
    localparam logic [31:0] P20D_DS_TAG1          = 32'hD20D_2001;
    localparam logic [31:0] P20D_C_RMW_TAG0       = 32'hD20D_3000;
    localparam logic [31:0] P20D_C_RMW_TAG1       = 32'hD20D_3001;

    localparam logic [31:0] P20D_SLOT0_CONTROL_DMA_HOST_READBACK   = 32'h0000_0003;
    localparam logic [31:0] P20D_SLOT1_CONTROL_DMA_DMA_STORE       = 32'h0000_000B;
    localparam logic [31:0] P20D_SLOT1_CONTROL_DMA_DMA_STORE_ACCUM = 32'h0000_002B;
    localparam logic [31:0] P20D_SLOT0_CONTROL_DS_HOST_READBACK    = 32'h0000_0007;
    localparam logic [31:0] P20D_SLOT1_CONTROL_DS_DMA_STORE        = 32'h0000_000F;

    localparam logic [31:0] P20D_SRC_A_BASE       = 32'h0000_0000;
    localparam logic [31:0] P20D_SRC_B_BASE       = 32'h0000_0100;
    localparam logic [31:0] P20D_C_RMW_SLOT0_A    = 32'h0000_0000;
    localparam logic [31:0] P20D_C_RMW_SLOT0_B    = 32'h0000_0100;
    localparam logic [31:0] P20D_C_RMW_SLOT1_A    = 32'h0000_0200;
    localparam logic [31:0] P20D_C_RMW_SLOT1_B    = 32'h0000_0300;
    localparam logic [31:0] P20D_DMA_DST_C_BASE   = 32'h0000_0000;

    localparam int unsigned P20D_NORMAL_CASE_ID   = 102;

    localparam logic [31:0] P20D_EXP_COMMIT_SUCCESS = 32'h0100_1803;
    localparam logic [31:0] P20D_EXP_STATUS_FLAGS   = 32'h0000_003F;
    localparam logic [31:0] P20D_EXP_COUNTS         = 32'h0002_0202;
    localparam logic [31:0] P20D_EXP_DESC_DONE      = 32'h0000_0003;
    localparam logic [31:0] P20D_EXP_ZERO           = 32'h0000_0000;
    localparam logic [31:0] P20D_EXP_RECIPE_DONE    = 32'h0000_0007;
    localparam logic [31:0] P20D_EXP_SLOT_MASKS     = 32'h0000_0003;

    function new(string name = "ai_accel_subsys_csr_queue_mixed_dma_ds_c_rmw_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function automatic int unsigned p20d_bytes_to_beats(input int unsigned byte_count);
    begin
        p20d_bytes_to_beats = (byte_count + 7) / 8;
    end
    endfunction

    task automatic p20d_write_u8_payload_to_src(input logic [31:0] base_addr,
                                                input int signed payload[]);
    begin
        for (int unsigned i = 0; i < payload.size(); i++) begin
            vif.dma_src_mem[base_addr + i] = payload[i][7:0];
        end
    end
    endtask

    task automatic p20d_write_src_word_le(input int unsigned byte_addr,
                                          input logic [31:0] value);
    begin
        vif.dma_src_mem[byte_addr + 0] = value[7:0];
        vif.dma_src_mem[byte_addr + 1] = value[15:8];
        vif.dma_src_mem[byte_addr + 2] = value[23:16];
        vif.dma_src_mem[byte_addr + 3] = value[31:24];
    end
    endtask

    task automatic p20d_write_desc_word(input int unsigned desc_base,
                                        input int unsigned word_idx,
                                        input logic [31:0] value);
    begin
        p20d_write_src_word_le(desc_base + (word_idx * 4), value);
    end
    endtask

    task automatic p20d_program_one_sq_command_entry(input int unsigned sq_slot,
                                                     input logic [31:0] cmd_tag,
                                                     input int unsigned desc_base);
        int unsigned base;
    begin
        base = P20D_SQ_BASE + (sq_slot * P20D_ENTRY_STRIDE);

        p20d_write_src_word_le(base + 16'h00, P20D_CMD_CONTROL);
        p20d_write_src_word_le(base + 16'h04, cmd_tag);
        p20d_write_src_word_le(base + 16'h08, 32'(desc_base));
        p20d_write_src_word_le(base + 16'h0C, 32'h0000_0002);
        p20d_write_src_word_le(base + 16'h10, 32'(P20D_DESC_STRIDE));
        p20d_write_src_word_le(base + 16'h14, P20D_COMP_FLAGS);
        p20d_write_src_word_le(base + 16'h18, 32'h0000_0000);

        for (int unsigned w = 7; w < 16; w++) begin
            p20d_write_src_word_le(base + (w * 4), 32'h0000_0000);
        end

        `uvm_info("P20D_QUEUE/SQ",
            $sformatf("Programmed SQ[%0d] command entry at 0x%08h control=0x%08h tag=0x%08h desc_base=0x%08h count=2 stride=0x%08h comp_flags=0x%08h",
                sq_slot,
                base,
                P20D_CMD_CONTROL,
                cmd_tag,
                desc_base,
                P20D_DESC_STRIDE,
                P20D_COMP_FLAGS),
            UVM_MEDIUM)
    end
    endtask

    task automatic p20d_program_sq_command_entries();
    begin
        p20d_program_one_sq_command_entry(0, P20D_CMD_DMA_TAG,   P20D_DMA_DESC_BASE);
        p20d_program_one_sq_command_entry(1, P20D_CMD_DS_TAG,    P20D_DS_DESC_BASE);
        p20d_program_one_sq_command_entry(2, P20D_CMD_C_RMW_TAG, P20D_C_RMW_DESC_BASE);
    end
    endtask

    task automatic p20d_program_dma_descriptor(
        input int unsigned             desc_base,
        input logic [31:0]             slot_control,
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes,
        input logic [31:0]             user_tag
    );
        int unsigned a_beats;
        int unsigned b_beats;
    begin
        a_beats = p20d_bytes_to_beats(a_bytes);
        b_beats = p20d_bytes_to_beats(b_bytes);

        p20d_write_desc_word(desc_base, DESC_WORD_CONTROL,          slot_control);
        p20d_write_desc_word(desc_base, DESC_WORD_BASE_ADDR_A,      profile_item.base_addr_a);
        p20d_write_desc_word(desc_base, DESC_WORD_BASE_ADDR_B,      profile_item.base_addr_b);
        p20d_write_desc_word(desc_base, DESC_WORD_BASE_ADDR_C,      profile_item.base_addr_c);
        p20d_write_desc_word(desc_base, DESC_WORD_DIM_M,            32'(profile_item.dim_m));
        p20d_write_desc_word(desc_base, DESC_WORD_DIM_N,            32'(profile_item.dim_n));
        p20d_write_desc_word(desc_base, DESC_WORD_DIM_K,            32'(profile_item.dim_k));

        p20d_write_desc_word(desc_base, DESC_WORD_A_SRC_BASE,       P20D_SRC_A_BASE);
        p20d_write_desc_word(desc_base, DESC_WORD_A_DST_BASE,       profile_item.base_addr_a);
        p20d_write_desc_word(desc_base, DESC_WORD_A_LOAD_BEATS,     32'(a_beats));

        p20d_write_desc_word(desc_base, DESC_WORD_B_SRC_BASE,       P20D_SRC_B_BASE);
        p20d_write_desc_word(desc_base, DESC_WORD_B_DST_BASE,       profile_item.base_addr_b);
        p20d_write_desc_word(desc_base, DESC_WORD_B_LOAD_BEATS,     32'(b_beats));

        p20d_write_desc_word(desc_base, DESC_WORD_STORE_SRC_BASE,   profile_item.base_addr_c);
        p20d_write_desc_word(desc_base, DESC_WORD_STORE_DST_BASE,   P20D_DMA_DST_C_BASE);
        p20d_write_desc_word(desc_base, DESC_WORD_STORE_BYTE_COUNT, 32'(c_bytes));
        p20d_write_desc_word(desc_base, DESC_WORD_USER_TAG,         user_tag);

        `uvm_info("P20D_DESC/DMA",
            $sformatf("Programmed DMA descriptor at 0x%08h: control=0x%08h A_bytes=%0d B_bytes=%0d C_bytes=%0d tag=0x%08h dim=(%0d,%0d,%0d)",
                desc_base,
                slot_control,
                a_bytes,
                b_bytes,
                c_bytes,
                user_tag,
                profile_item.dim_m,
                profile_item.dim_n,
                profile_item.dim_k),
            UVM_MEDIUM)
    end
    endtask

    task automatic p20d_program_direct_stream_descriptor(
        input int unsigned             desc_base,
        input logic [31:0]             slot_control,
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes,
        input logic [31:0]             user_tag
    );
        int unsigned a_beats;
        int unsigned b_beats;
    begin
        a_beats = p20d_bytes_to_beats(a_bytes);
        b_beats = p20d_bytes_to_beats(b_bytes);

        p20d_write_desc_word(desc_base, DESC_WORD_CONTROL,          slot_control);
        p20d_write_desc_word(desc_base, DESC_WORD_BASE_ADDR_A,      profile_item.base_addr_a);
        p20d_write_desc_word(desc_base, DESC_WORD_BASE_ADDR_B,      profile_item.base_addr_b);
        p20d_write_desc_word(desc_base, DESC_WORD_BASE_ADDR_C,      profile_item.base_addr_c);
        p20d_write_desc_word(desc_base, DESC_WORD_DIM_M,            32'(profile_item.dim_m));
        p20d_write_desc_word(desc_base, DESC_WORD_DIM_N,            32'(profile_item.dim_n));
        p20d_write_desc_word(desc_base, DESC_WORD_DIM_K,            32'(profile_item.dim_k));

        p20d_write_desc_word(desc_base, DESC_WORD_A_SRC_BASE,       P20D_SRC_A_BASE);
        p20d_write_desc_word(desc_base, DESC_WORD_A_DST_BASE,       profile_item.base_addr_a);
        p20d_write_desc_word(desc_base, DESC_WORD_A_LOAD_BEATS,     32'(a_beats));

        p20d_write_desc_word(desc_base, DESC_WORD_B_SRC_BASE,       P20D_SRC_B_BASE);
        p20d_write_desc_word(desc_base, DESC_WORD_B_DST_BASE,       profile_item.base_addr_b);
        p20d_write_desc_word(desc_base, DESC_WORD_B_LOAD_BEATS,     32'(b_beats));

        p20d_write_desc_word(desc_base, DESC_WORD_STORE_SRC_BASE,   profile_item.base_addr_c);
        p20d_write_desc_word(desc_base, DESC_WORD_STORE_DST_BASE,   P20D_DMA_DST_C_BASE);
        p20d_write_desc_word(desc_base, DESC_WORD_STORE_BYTE_COUNT, 32'(c_bytes));
        p20d_write_desc_word(desc_base, DESC_WORD_USER_TAG,         user_tag);

        `uvm_info("P20D_DESC/DS",
            $sformatf("Programmed Direct Stream descriptor at 0x%08h: control=0x%08h A src=0x%08h bytes=%0d B src=0x%08h bytes=%0d C dst=0x%08h bytes=%0d tag=0x%08h dim=(%0d,%0d,%0d)",
                desc_base,
                slot_control,
                P20D_SRC_A_BASE,
                a_bytes,
                P20D_SRC_B_BASE,
                b_bytes,
                P20D_DMA_DST_C_BASE,
                c_bytes,
                user_tag,
                profile_item.dim_m,
                profile_item.dim_n,
                profile_item.dim_k),
            UVM_MEDIUM)
    end
    endtask

    task automatic p20d_program_c_rmw_descriptor(
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
        a_beats = p20d_bytes_to_beats(a_bytes);
        b_beats = p20d_bytes_to_beats(b_bytes);

        p20d_write_desc_word(desc_base, DESC_WORD_CONTROL,          slot_control);
        p20d_write_desc_word(desc_base, DESC_WORD_BASE_ADDR_A,      job_item.base_addr_a);
        p20d_write_desc_word(desc_base, DESC_WORD_BASE_ADDR_B,      job_item.base_addr_b);
        p20d_write_desc_word(desc_base, DESC_WORD_BASE_ADDR_C,      job_item.base_addr_c);
        p20d_write_desc_word(desc_base, DESC_WORD_DIM_M,            32'(job_item.dim_m));
        p20d_write_desc_word(desc_base, DESC_WORD_DIM_N,            32'(job_item.dim_n));
        p20d_write_desc_word(desc_base, DESC_WORD_DIM_K,            32'(job_item.dim_k));

        p20d_write_desc_word(desc_base, DESC_WORD_A_SRC_BASE,       a_src_base);
        p20d_write_desc_word(desc_base, DESC_WORD_A_DST_BASE,       job_item.base_addr_a);
        p20d_write_desc_word(desc_base, DESC_WORD_A_LOAD_BEATS,     32'(a_beats));

        p20d_write_desc_word(desc_base, DESC_WORD_B_SRC_BASE,       b_src_base);
        p20d_write_desc_word(desc_base, DESC_WORD_B_DST_BASE,       job_item.base_addr_b);
        p20d_write_desc_word(desc_base, DESC_WORD_B_LOAD_BEATS,     32'(b_beats));

        p20d_write_desc_word(desc_base, DESC_WORD_STORE_SRC_BASE,   job_item.base_addr_c);
        p20d_write_desc_word(desc_base, DESC_WORD_STORE_DST_BASE,   P20D_DMA_DST_C_BASE);
        p20d_write_desc_word(desc_base, DESC_WORD_STORE_BYTE_COUNT, 32'(c_bytes));
        p20d_write_desc_word(desc_base, DESC_WORD_USER_TAG,         user_tag);

        `uvm_info("P20D_DESC/C_RMW",
            $sformatf("Programmed C RMW descriptor at 0x%08h: control=0x%08h accum=%0d A src=0x%08h bytes=%0d B src=0x%08h bytes=%0d C dst=0x%08h bytes=%0d tag=0x%08h dim=(%0d,%0d,%0d)",
                desc_base,
                slot_control,
                job_item.accumulate_enable,
                a_src_base,
                a_bytes,
                b_src_base,
                b_bytes,
                P20D_DMA_DST_C_BASE,
                c_bytes,
                user_tag,
                job_item.dim_m,
                job_item.dim_n,
                job_item.dim_k),
            UVM_MEDIUM)
    end
    endtask

    task automatic p20d_prepare_source_and_dst(
        input int signed c_rmw_a0[],
        input int signed c_rmw_b0[],
        input int signed c_rmw_a1[],
        input int signed c_rmw_b1[]
    );
    begin
        vif.dma_src_mem_clear();
        vif.dma_dst_mem_clear();

        vif.dma_src_set_rresp_error(1'b0, -1);
        vif.axis_src_set_rresp_error(1'b0, -1);
        vif.ds_src_set_rresp_error(1'b0, -1);
        vif.dma_dst_set_bresp_error(1'b0, -1);

        // The first two mixed commands are functional queue-drain
        // representatives.  They reuse the first source regions.  The
        // final C RMW command owns the result comparison and therefore
        // gets the canonical P13/P16 split-source layout.
        p20d_write_u8_payload_to_src(P20D_C_RMW_SLOT0_A, c_rmw_a0);
        p20d_write_u8_payload_to_src(P20D_C_RMW_SLOT0_B, c_rmw_b0);
        p20d_write_u8_payload_to_src(P20D_C_RMW_SLOT1_A, c_rmw_a1);
        p20d_write_u8_payload_to_src(P20D_C_RMW_SLOT1_B, c_rmw_b1);

        `uvm_info("P20D_MEM/PREP",
            $sformatf("Prepared mixed queue source memory: C_RMW slot0 A=0x%08h bytes=%0d B=0x%08h bytes=%0d; slot1 A=0x%08h bytes=%0d B=0x%08h bytes=%0d; result dst=0x%08h CQ=0x%08h",
                P20D_C_RMW_SLOT0_A,
                c_rmw_a0.size(),
                P20D_C_RMW_SLOT0_B,
                c_rmw_b0.size(),
                P20D_C_RMW_SLOT1_A,
                c_rmw_a1.size(),
                P20D_C_RMW_SLOT1_B,
                c_rmw_b1.size(),
                P20D_DMA_DST_C_BASE,
                P20D_CQ_BASE),
            UVM_MEDIUM)
    end
    endtask

    task automatic p20d_clear_cq_memory();
    begin
        for (int unsigned i = 0; i < (3 * P20D_ENTRY_STRIDE); i++) begin
            vif.dma_dst_mem[P20D_CQ_BASE + i] = 8'h00;
        end
    end
    endtask

    task automatic p20d_program_descriptor_tables(
        input ai_accel_subsys_seq_item normal_item,
        input int unsigned             normal_a_bytes,
        input int unsigned             normal_b_bytes,
        input int unsigned             normal_c_bytes,
        input ai_accel_subsys_seq_item job0_item,
        input ai_accel_subsys_seq_item job1_item,
        input int unsigned             job0_a_bytes,
        input int unsigned             job0_b_bytes,
        input int unsigned             job1_a_bytes,
        input int unsigned             job1_b_bytes,
        input int unsigned             c_rmw_c_bytes
    );
    begin
        p20d_program_dma_descriptor(
            P20D_DMA_DESC_BASE + (0 * P20D_DESC_STRIDE),
            P20D_SLOT0_CONTROL_DMA_HOST_READBACK,
            normal_item,
            normal_a_bytes,
            normal_b_bytes,
            normal_c_bytes,
            P20D_DMA_TAG0
        );

        p20d_program_dma_descriptor(
            P20D_DMA_DESC_BASE + (1 * P20D_DESC_STRIDE),
            P20D_SLOT1_CONTROL_DMA_DMA_STORE,
            normal_item,
            normal_a_bytes,
            normal_b_bytes,
            normal_c_bytes,
            P20D_DMA_TAG1
        );

        p20d_program_direct_stream_descriptor(
            P20D_DS_DESC_BASE + (0 * P20D_DESC_STRIDE),
            P20D_SLOT0_CONTROL_DS_HOST_READBACK,
            normal_item,
            normal_a_bytes,
            normal_b_bytes,
            normal_c_bytes,
            P20D_DS_TAG0
        );

        p20d_program_direct_stream_descriptor(
            P20D_DS_DESC_BASE + (1 * P20D_DESC_STRIDE),
            P20D_SLOT1_CONTROL_DS_DMA_STORE,
            normal_item,
            normal_a_bytes,
            normal_b_bytes,
            normal_c_bytes,
            P20D_DS_TAG1
        );

        p20d_program_c_rmw_descriptor(
            P20D_C_RMW_DESC_BASE + (0 * P20D_DESC_STRIDE),
            P20D_SLOT0_CONTROL_DMA_HOST_READBACK,
            job0_item,
            P20D_C_RMW_SLOT0_A,
            P20D_C_RMW_SLOT0_B,
            job0_a_bytes,
            job0_b_bytes,
            c_rmw_c_bytes,
            P20D_C_RMW_TAG0
        );

        p20d_program_c_rmw_descriptor(
            P20D_C_RMW_DESC_BASE + (1 * P20D_DESC_STRIDE),
            P20D_SLOT1_CONTROL_DMA_DMA_STORE_ACCUM,
            job1_item,
            P20D_C_RMW_SLOT1_A,
            P20D_C_RMW_SLOT1_B,
            job1_a_bytes,
            job1_b_bytes,
            c_rmw_c_bytes,
            P20D_C_RMW_TAG1
        );
    end
    endtask

    task automatic p20d_csr_clear_completion_wb();
        logic [31:0] clear_cmd;
    begin
        clear_cmd = 32'h0000_0000;
        clear_cmd[ai_accel_csr_access_helper::COMP_WB_CMD_CLEAR_DONE]  = 1'b1;
        clear_cmd[ai_accel_csr_access_helper::COMP_WB_CMD_CLEAR_ERROR] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_COMPLETION_WB_COMMAND,
            clear_cmd
        );
    end
    endtask

    task automatic p20d_csr_program_completion_wb();
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_COMPLETION_WB_BASE_ADDR,
            32'(P20D_CQ_BASE)
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_COMPLETION_WB_CONTROL,
            32'h0000_0001
        );
    end
    endtask

    task automatic p20d_csr_clear_queue();
        logic [31:0] clear_cmd;
    begin
        clear_cmd = 32'h0000_0000;
        clear_cmd[ai_accel_csr_access_helper::QUEUE_CMD_CLEAR_DONE]  = 1'b1;
        clear_cmd[ai_accel_csr_access_helper::QUEUE_CMD_CLEAR_ERROR] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_COMMAND,
            clear_cmd
        );
    end
    endtask

    task automatic p20d_csr_program_queue();
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE,   32'(P20D_SQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH,  32'(P20D_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,   32'h0000_0003);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, 32'(P20D_ENTRY_STRIDE));

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE,   32'(P20D_CQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH,  32'(P20D_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, 32'(P20D_ENTRY_STRIDE));

        // bit0 QUEUE_ENABLE, bit1 RUN_UNTIL_EMPTY, bit2 STOP_ON_ERROR
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CONTROL, 32'h0000_0007);
    end
    endtask

    task automatic p20d_start_queue_once();
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_START] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_COMMAND,
            cmd
        );

        `uvm_info("P20D_QUEUE/START", "Issued one CSR_QUEUE_COMMAND.START_QUEUE kick", UVM_MEDIUM)
    end
    endtask

    task automatic p20d_poll_three_command_queue_drained(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] sq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
        logic [31:0] last_tag;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD, sq_head);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL, cq_tail);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);

            if ((error_status != 32'h0000_0000) ||
                (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P20D_QUEUE/ERROR",
                    $sformatf("Queue failed during mixed three-command drain: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail))
            end

            if ((sq_head == 32'h0000_0003) &&
                (cq_tail == 32'h0000_0003) &&
                (cq_occ  == 32'h0000_0003) &&
                done_status[1]) begin
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);
                if (last_tag !== P20D_CMD_C_RMW_TAG) begin
                    `uvm_fatal("P20D_QUEUE/BAD_LAST_TAG",
                        $sformatf("Expected last accepted command tag=0x%08h got=0x%08h",
                            P20D_CMD_C_RMW_TAG,
                            last_tag))
                end

                `uvm_info("P20D_QUEUE/DRAINED",
                    $sformatf("Mixed three-command auto-drain completed after %0d poll(s): status=0x%08h done=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h last_tag=0x%08h",
                        cnt,
                        status,
                        done_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        last_tag),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P20D_QUEUE/TIMEOUT",
                    $sformatf("Timed out waiting for mixed three-command queue drain: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail,
                        cq_occ))
            end
        end
    end
    endtask

    function automatic logic [31:0] p20d_read_cq_word(input int unsigned cq_slot,
                                                      input int unsigned byte_offset);
        int unsigned idx;
        logic [31:0] value;
    begin
        idx = P20D_CQ_BASE + (cq_slot * P20D_ENTRY_STRIDE) + byte_offset;
        value = 32'h0000_0000;
        value[7:0]   = vif.dma_dst_mem[idx + 0];
        value[15:8]  = vif.dma_dst_mem[idx + 1];
        value[23:16] = vif.dma_dst_mem[idx + 2];
        value[31:24] = vif.dma_dst_mem[idx + 3];
        return value;
    end
    endfunction

    task automatic p20d_expect_cq_word(input int unsigned cq_slot,
                                       input int unsigned byte_offset,
                                       input logic [31:0] expected,
                                       input string name);
        logic [31:0] actual;
    begin
        actual = p20d_read_cq_word(cq_slot, byte_offset);
        if (actual !== expected) begin
            `uvm_fatal("P20D_CQ_WB/RECORD_MISMATCH",
                $sformatf("CQ[%0d] %s mismatch at +0x%02x: actual=0x%08h expected=0x%08h",
                    cq_slot,
                    name,
                    byte_offset,
                    actual,
                    expected))
        end

        `uvm_info("P20D_CQ_WB/CHECK",
            $sformatf("CQ[%0d] %s PASS at +0x%02x: 0x%08h",
                cq_slot,
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic p20d_expect_cq_word_nonzero(input int unsigned cq_slot,
                                               input int unsigned byte_offset,
                                               input string name);
        logic [31:0] actual;
    begin
        actual = p20d_read_cq_word(cq_slot, byte_offset);
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P20D_CQ_WB/RECORD_ZERO",
                $sformatf("CQ[%0d] %s unexpectedly zero at +0x%02x",
                    cq_slot,
                    name,
                    byte_offset))
        end

        `uvm_info("P20D_CQ_WB/CHECK",
            $sformatf("CQ[%0d] %s nonzero PASS at +0x%02x: 0x%08h",
                cq_slot,
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic p20d_check_one_cq_record(input int unsigned cq_slot,
                                            input logic [31:0] first_desc_tag,
                                            input logic [31:0] last_desc_tag,
                                            input int unsigned expected_macs,
                                            input int unsigned expected_outputs);
    begin
        p20d_expect_cq_word(cq_slot, 16'h00, P20D_EXP_COMMIT_SUCCESS, "word0 commit");
        p20d_expect_cq_word(cq_slot, 16'h04, P20D_EXP_STATUS_FLAGS,   "word1 status_flags");
        p20d_expect_cq_word(cq_slot, 16'h08, first_desc_tag,          "word2 first_user_tag");
        p20d_expect_cq_word(cq_slot, 16'h0C, last_desc_tag,           "word3 last_user_tag");
        p20d_expect_cq_word(cq_slot, 16'h10, P20D_EXP_COUNTS,         "word4 counts");
        p20d_expect_cq_word(cq_slot, 16'h14, P20D_EXP_DESC_DONE,      "word5 desc_fetch_done_status");
        p20d_expect_cq_word(cq_slot, 16'h18, P20D_EXP_ZERO,           "word6 desc_fetch_error_status");
        p20d_expect_cq_word(cq_slot, 16'h1C, P20D_EXP_ZERO,           "word7 desc_fetch_reject_status");
        p20d_expect_cq_word(cq_slot, 16'h20, P20D_EXP_RECIPE_DONE,    "word8 recipe_done_status");
        p20d_expect_cq_word(cq_slot, 16'h24, P20D_EXP_ZERO,           "word9 recipe_error_status");
        p20d_expect_cq_word(cq_slot, 16'h28, P20D_EXP_ZERO,           "word10 recipe_reject_status");
        p20d_expect_cq_word(cq_slot, 16'h2C, P20D_EXP_SLOT_MASKS,     "word11 slot_mask_summary");
        p20d_expect_cq_word_nonzero(cq_slot, 16'h30,                 "word12 perf_busy_cycles");
        p20d_expect_cq_word(cq_slot, 16'h34, 32'(expected_macs),      "word13 perf_mac_count");
        p20d_expect_cq_word(cq_slot, 16'h38, 32'(expected_outputs),   "word14 perf_output_count");
        p20d_expect_cq_word(cq_slot, 16'h3C, P20D_EXP_ZERO,           "word15 error_detail");
    end
    endtask

    task automatic p20d_check_cq_records(input ai_accel_subsys_seq_item normal_item,
                                         input ai_accel_subsys_seq_item c_rmw_recipe_item);
        int unsigned normal_macs;
        int unsigned normal_outputs;
        int unsigned c_rmw_macs;
        int unsigned c_rmw_outputs;
    begin
        normal_macs    = 2 * int'(normal_item.dim_m) * int'(normal_item.dim_n) * int'(normal_item.dim_k);
        normal_outputs = 2 * int'(normal_item.dim_m) * int'(normal_item.dim_n);

        c_rmw_macs    = int'(c_rmw_recipe_item.dim_m) * int'(c_rmw_recipe_item.dim_n) * int'(c_rmw_recipe_item.dim_k);
        c_rmw_outputs = 2 * int'(c_rmw_recipe_item.dim_m) * int'(c_rmw_recipe_item.dim_n);

        p20d_check_one_cq_record(0, P20D_DMA_TAG0,   P20D_DMA_TAG1,   normal_macs, normal_outputs);
        p20d_check_one_cq_record(1, P20D_DS_TAG0,    P20D_DS_TAG1,    normal_macs, normal_outputs);
        p20d_check_one_cq_record(2, P20D_C_RMW_TAG0, P20D_C_RMW_TAG1, c_rmw_macs, c_rmw_outputs);
    end
    endtask

    task run_phase(uvm_phase phase);
        ai_accel_subsys_seq_item normal_item;
        ai_accel_subsys_seq_item c_rmw_recipe_item;
        ai_accel_subsys_seq_item job0_item;
        ai_accel_subsys_seq_item job1_item;
        int signed               normal_a[];
        int signed               normal_b[];
        int signed               normal_expected_c[];
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
        int unsigned             normal_c_elems;
        int unsigned             normal_c_bytes;
        int unsigned             c_rmw_c_elems;
        int unsigned             c_rmw_c_bytes;
        int unsigned             job_count;
    begin
        phase.raise_objection(this);

        `uvm_info("P20D_QUEUE_MIXED_DMA_DS_C_RMW/START",
            "Starting P20D DMA + Direct Stream + C RMW mixed in-order queue drain smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        case_helper.build_variable_case_payload(
            P20D_NORMAL_CASE_ID,
            normal_item,
            normal_a,
            normal_b,
            normal_expected_c
        );

        normal_c_elems = int'(normal_item.dim_m) * int'(normal_item.dim_n);
        normal_c_bytes = normal_c_elems * 4;

        if (normal_expected_c.size() != normal_c_elems) begin
            `uvm_fatal("P20D_QUEUE_MIXED/NORMAL_EXPECTED_SIZE",
                $sformatf("Expected normal C size mismatch: expected=%0d elems=%0d",
                    normal_expected_c.size(),
                    normal_c_elems))
        end

        if (!case_helper.is_c_rmw_accum_recipe_case(selected_case_id)) begin
            `uvm_fatal("P20D_QUEUE_MIXED/BAD_CASE",
                $sformatf("Unsupported P20D C RMW recipe CASE_ID=%0d", selected_case_id))
        end

        case_helper.build_c_rmw_accum_recipe_expected_payload(
            selected_case_id,
            c_rmw_recipe_item,
            a_full,
            b_full,
            expected_final_c
        );

        job_count = case_helper.get_c_rmw_accum_recipe_job_count(selected_case_id);
        if (job_count != 2) begin
            `uvm_fatal("P20D_QUEUE_MIXED/BAD_JOB_COUNT",
                $sformatf("P20D expects exactly two C RMW jobs, but CASE_ID=%0d has job_count=%0d",
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
            `uvm_fatal("P20D_QUEUE_MIXED/JOB0_ACCUM", "job0 must use accumulate_enable=0")
        end

        if (job1_item.accumulate_enable != 1'b1) begin
            `uvm_fatal("P20D_QUEUE_MIXED/JOB1_ACCUM", "job1 must use accumulate_enable=1")
        end

        c_rmw_c_elems = int'(c_rmw_recipe_item.dim_m) * int'(c_rmw_recipe_item.dim_n);
        c_rmw_c_bytes = c_rmw_c_elems * 4;

        if (expected_final_c.size() != c_rmw_c_elems) begin
            `uvm_fatal("P20D_QUEUE_MIXED/C_RMW_EXPECTED_SIZE",
                $sformatf("Expected final C size mismatch: expected=%0d elems=%0d",
                    expected_final_c.size(),
                    c_rmw_c_elems))
        end

        if (expected_job1_accum_c.size() != expected_final_c.size()) begin
            `uvm_fatal("P20D_QUEUE_MIXED/ACCUM_SIZE",
                $sformatf("Accumulated final C size mismatch: job1_accum=%0d full_final=%0d",
                    expected_job1_accum_c.size(),
                    expected_final_c.size()))
        end

        compare_result_vectors(expected_final_c, expected_job1_accum_c);

        `uvm_info("P20D_QUEUE_MIXED",
            $sformatf("Built mixed queue payloads: normal CASE_ID=%0d dim=(%0d,%0d,%0d); C_RMW CASE_ID=%0d dim=(%0d,%0d,%0d) job0_k=%0d job1_k=%0d",
                P20D_NORMAL_CASE_ID,
                normal_item.dim_m,
                normal_item.dim_n,
                normal_item.dim_k,
                selected_case_id,
                c_rmw_recipe_item.dim_m,
                c_rmw_recipe_item.dim_n,
                c_rmw_recipe_item.dim_k,
                job0_item.dim_k,
                job1_item.dim_k),
            UVM_MEDIUM)

        p20d_prepare_source_and_dst(a0_part, b0_part, a1_part, b1_part);
        p20d_clear_cq_memory();

        p20d_program_descriptor_tables(
            normal_item,
            normal_a.size(),
            normal_b.size(),
            normal_c_bytes,
            job0_item,
            job1_item,
            a0_part.size(),
            b0_part.size(),
            a1_part.size(),
            b1_part.size(),
            c_rmw_c_bytes
        );

        p20d_program_sq_command_entries();

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        p20d_csr_clear_completion_wb();
        p20d_csr_clear_queue();

        p20d_csr_program_completion_wb();
        p20d_csr_program_queue();

        csr_check_recipe_idle_ready("before P20D mixed queue START");
        p20d_start_queue_once();

        p20d_poll_three_command_queue_drained(done_timeout_cycles * 8);

        repeat (5) @(posedge csr_vif.clk);

        p20d_check_cq_records(normal_item, c_rmw_recipe_item);

        collect_dma_destination_c(c_rmw_c_elems, actual_c);
        compare_result_vectors(expected_final_c, actual_c);

        `uvm_info("P20D_QUEUE_MIXED_DMA_DS_C_RMW/PASS",
            $sformatf("P20D mixed queue auto-drain completed: C_RMW CASE_ID=%0d normal_case=%0d C_words=%0d SQ_entries=3 CQ_entries=3",
                selected_case_id,
                P20D_NORMAL_CASE_ID,
                c_rmw_c_elems),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
