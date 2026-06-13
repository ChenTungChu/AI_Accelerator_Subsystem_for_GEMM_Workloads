// File: tb/uvm/test/ai_accel_subsys_csr_queue_runtime_doorbell_mixed_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_QUEUE_RUNTIME_DOORBELL_MIXED_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_QUEUE_RUNTIME_DOORBELL_MIXED_SMOKE_TEST_SV

// ============================================================
// P21D runtime doorbell / append-while-active mixed queue smoke
//
// Scope:
//   - Publishes one DMA descriptor-recipe SQ command before START_QUEUE.
//   - Issues one START_QUEUE kick with RUN_UNTIL_EMPTY=1.
//   - While SQ[0] is active, the host appends SQ[1] as a Direct Stream
//     descriptor-recipe command and updates CSR_SQ_TAIL from 1 to 2.
//   - Verifies the queue controller observes the live SQ_TAIL value only
//     at the command boundary, continues into the mixed Direct Stream
//     command without a second START_QUEUE kick, and drains both commands
//     in order.
//   - Verifies CQ[0] and CQ[1] completion records and compares the final
//     Direct Stream command's DMA-store result against the software model.
//
// P21D does not add multi-outstanding execution, out-of-order completion,
// interrupts, or any BRAM / GEMM / DMA / frontend datapath change.  It
// validates runtime doorbell semantics across mixed command profiles on top
// of the P20 single-active-command auto-drain path.
// ============================================================

class ai_accel_subsys_csr_queue_runtime_doorbell_mixed_smoke_test
    extends ai_accel_subsys_csr_queue_mixed_dma_ds_c_rmw_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_queue_runtime_doorbell_mixed_smoke_test)

    localparam int unsigned P21D_SQ_BASE      = 32'h0000_0D00;
    localparam int unsigned P21D_CQ_BASE      = 32'h0000_0E00;
    localparam int unsigned P21D_QUEUE_DEPTH  = 4;
    localparam int unsigned P21D_ENTRY_STRIDE = 32'h0000_0040;

    localparam int unsigned P21D_DMA_DESC_BASE = 32'h0000_0300;
    localparam int unsigned P21D_DS_DESC_BASE  = 32'h0000_0500;
    localparam int unsigned P21D_DESC_STRIDE   = 32'h0000_0080;

    // VALID=1, OPCODE=0x01, ENABLE_COMPLETION=1.
    // STOP_AFTER_THIS is intentionally 0 for runtime live-service continuation.
    localparam logic [31:0] P21D_CMD_CONTROL = 32'h0000_0103;
    localparam logic [31:0] P21D_CMD_DMA_TAG = 32'hD21D_0000;
    localparam logic [31:0] P21D_CMD_DS_TAG  = 32'hD21D_0001;
    localparam logic [31:0] P21D_COMP_FLAGS  = 32'h0000_0001;

    localparam logic [31:0] P21D_DMA_TAG0 = 32'hD21D_1000;
    localparam logic [31:0] P21D_DMA_TAG1 = 32'hD21D_1001;
    localparam logic [31:0] P21D_DS_TAG0  = 32'hD21D_2000;
    localparam logic [31:0] P21D_DS_TAG1  = 32'hD21D_2001;

    localparam logic [31:0] P21D_SLOT0_CONTROL_DMA_HOST_READBACK = 32'h0000_0003;
    localparam logic [31:0] P21D_SLOT1_CONTROL_DMA_DMA_STORE     = 32'h0000_000B;
    localparam logic [31:0] P21D_SLOT0_CONTROL_DS_HOST_READBACK  = 32'h0000_0007;
    localparam logic [31:0] P21D_SLOT1_CONTROL_DS_DMA_STORE      = 32'h0000_000F;

    localparam logic [31:0] P21D_SRC_A_BASE     = 32'h0000_0000;
    localparam logic [31:0] P21D_SRC_B_BASE     = 32'h0000_0100;
    localparam logic [31:0] P21D_DMA_DST_C_BASE = 32'h0000_0000;

    localparam int unsigned P21D_NORMAL_CASE_ID = 102;

    localparam logic [31:0] P21D_EXP_COMMIT_SUCCESS = 32'h0100_1803;
    localparam logic [31:0] P21D_EXP_STATUS_FLAGS   = 32'h0000_003F;
    localparam logic [31:0] P21D_EXP_COUNTS         = 32'h0002_0202;
    localparam logic [31:0] P21D_EXP_DESC_DONE      = 32'h0000_0003;
    localparam logic [31:0] P21D_EXP_ZERO           = 32'h0000_0000;
    localparam logic [31:0] P21D_EXP_RECIPE_DONE    = 32'h0000_0007;
    localparam logic [31:0] P21D_EXP_SLOT_MASKS     = 32'h0000_0003;

    function new(string name = "ai_accel_subsys_csr_queue_runtime_doorbell_mixed_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function automatic int unsigned p21d_bytes_to_beats(input int unsigned byte_count);
    begin
        p21d_bytes_to_beats = (byte_count + 7) / 8;
    end
    endfunction

    task automatic p21d_write_u8_payload_to_src(input logic [31:0] base_addr,
                                                input int signed payload[]);
    begin
        for (int unsigned i = 0; i < payload.size(); i++) begin
            vif.dma_src_mem[base_addr + i] = payload[i][7:0];
        end
    end
    endtask

    task automatic p21d_write_src_word_le(input int unsigned byte_addr,
                                          input logic [31:0] value);
    begin
        vif.dma_src_mem[byte_addr + 0] = value[7:0];
        vif.dma_src_mem[byte_addr + 1] = value[15:8];
        vif.dma_src_mem[byte_addr + 2] = value[23:16];
        vif.dma_src_mem[byte_addr + 3] = value[31:24];
    end
    endtask

    task automatic p21d_write_desc_word(input int unsigned desc_base,
                                        input int unsigned word_idx,
                                        input logic [31:0] value);
    begin
        p21d_write_src_word_le(desc_base + (word_idx * 4), value);
    end
    endtask

    task automatic p21d_program_one_sq_command_entry(input int unsigned sq_slot,
                                                     input logic [31:0] cmd_tag,
                                                     input int unsigned desc_base);
        int unsigned base;
    begin
        base = P21D_SQ_BASE + (sq_slot * P21D_ENTRY_STRIDE);

        // Payload words first; command commit/control word last.
        p21d_write_src_word_le(base + 16'h04, cmd_tag);
        p21d_write_src_word_le(base + 16'h08, 32'(desc_base));
        p21d_write_src_word_le(base + 16'h0C, 32'h0000_0002);
        p21d_write_src_word_le(base + 16'h10, 32'(P21D_DESC_STRIDE));
        p21d_write_src_word_le(base + 16'h14, P21D_COMP_FLAGS);
        p21d_write_src_word_le(base + 16'h18, 32'h0000_0000);

        for (int unsigned w = 7; w < 16; w++) begin
            p21d_write_src_word_le(base + (w * 4), 32'h0000_0000);
        end

        p21d_write_src_word_le(base + 16'h00, P21D_CMD_CONTROL);

        `uvm_info("P21D_QUEUE/SQ",
            $sformatf("Programmed SQ[%0d] command entry at 0x%08h control=0x%08h tag=0x%08h desc_base=0x%08h count=2 stride=0x%08h comp_flags=0x%08h",
                sq_slot,
                base,
                P21D_CMD_CONTROL,
                cmd_tag,
                desc_base,
                P21D_DESC_STRIDE,
                P21D_COMP_FLAGS),
            UVM_MEDIUM)
    end
    endtask

    task automatic p21d_program_dma_descriptor(
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
        a_beats = p21d_bytes_to_beats(a_bytes);
        b_beats = p21d_bytes_to_beats(b_bytes);

        p21d_write_desc_word(desc_base, DESC_WORD_CONTROL,          slot_control);
        p21d_write_desc_word(desc_base, DESC_WORD_BASE_ADDR_A,      profile_item.base_addr_a);
        p21d_write_desc_word(desc_base, DESC_WORD_BASE_ADDR_B,      profile_item.base_addr_b);
        p21d_write_desc_word(desc_base, DESC_WORD_BASE_ADDR_C,      profile_item.base_addr_c);
        p21d_write_desc_word(desc_base, DESC_WORD_DIM_M,            32'(profile_item.dim_m));
        p21d_write_desc_word(desc_base, DESC_WORD_DIM_N,            32'(profile_item.dim_n));
        p21d_write_desc_word(desc_base, DESC_WORD_DIM_K,            32'(profile_item.dim_k));

        p21d_write_desc_word(desc_base, DESC_WORD_A_SRC_BASE,       P21D_SRC_A_BASE);
        p21d_write_desc_word(desc_base, DESC_WORD_A_DST_BASE,       profile_item.base_addr_a);
        p21d_write_desc_word(desc_base, DESC_WORD_A_LOAD_BEATS,     32'(a_beats));

        p21d_write_desc_word(desc_base, DESC_WORD_B_SRC_BASE,       P21D_SRC_B_BASE);
        p21d_write_desc_word(desc_base, DESC_WORD_B_DST_BASE,       profile_item.base_addr_b);
        p21d_write_desc_word(desc_base, DESC_WORD_B_LOAD_BEATS,     32'(b_beats));

        p21d_write_desc_word(desc_base, DESC_WORD_STORE_SRC_BASE,   profile_item.base_addr_c);
        p21d_write_desc_word(desc_base, DESC_WORD_STORE_DST_BASE,   P21D_DMA_DST_C_BASE);
        p21d_write_desc_word(desc_base, DESC_WORD_STORE_BYTE_COUNT, 32'(c_bytes));
        p21d_write_desc_word(desc_base, DESC_WORD_USER_TAG,         user_tag);

        `uvm_info("P21D_DESC/DMA",
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

    task automatic p21d_program_direct_stream_descriptor(
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
        a_beats = p21d_bytes_to_beats(a_bytes);
        b_beats = p21d_bytes_to_beats(b_bytes);

        p21d_write_desc_word(desc_base, DESC_WORD_CONTROL,          slot_control);
        p21d_write_desc_word(desc_base, DESC_WORD_BASE_ADDR_A,      profile_item.base_addr_a);
        p21d_write_desc_word(desc_base, DESC_WORD_BASE_ADDR_B,      profile_item.base_addr_b);
        p21d_write_desc_word(desc_base, DESC_WORD_BASE_ADDR_C,      profile_item.base_addr_c);
        p21d_write_desc_word(desc_base, DESC_WORD_DIM_M,            32'(profile_item.dim_m));
        p21d_write_desc_word(desc_base, DESC_WORD_DIM_N,            32'(profile_item.dim_n));
        p21d_write_desc_word(desc_base, DESC_WORD_DIM_K,            32'(profile_item.dim_k));

        p21d_write_desc_word(desc_base, DESC_WORD_A_SRC_BASE,       P21D_SRC_A_BASE);
        p21d_write_desc_word(desc_base, DESC_WORD_A_DST_BASE,       profile_item.base_addr_a);
        p21d_write_desc_word(desc_base, DESC_WORD_A_LOAD_BEATS,     32'(a_beats));

        p21d_write_desc_word(desc_base, DESC_WORD_B_SRC_BASE,       P21D_SRC_B_BASE);
        p21d_write_desc_word(desc_base, DESC_WORD_B_DST_BASE,       profile_item.base_addr_b);
        p21d_write_desc_word(desc_base, DESC_WORD_B_LOAD_BEATS,     32'(b_beats));

        p21d_write_desc_word(desc_base, DESC_WORD_STORE_SRC_BASE,   profile_item.base_addr_c);
        p21d_write_desc_word(desc_base, DESC_WORD_STORE_DST_BASE,   P21D_DMA_DST_C_BASE);
        p21d_write_desc_word(desc_base, DESC_WORD_STORE_BYTE_COUNT, 32'(c_bytes));
        p21d_write_desc_word(desc_base, DESC_WORD_USER_TAG,         user_tag);

        `uvm_info("P21D_DESC/DS",
            $sformatf("Programmed Direct Stream descriptor at 0x%08h: control=0x%08h A src=0x%08h bytes=%0d B src=0x%08h bytes=%0d C dst=0x%08h bytes=%0d tag=0x%08h dim=(%0d,%0d,%0d)",
                desc_base,
                slot_control,
                P21D_SRC_A_BASE,
                a_bytes,
                P21D_SRC_B_BASE,
                b_bytes,
                P21D_DMA_DST_C_BASE,
                c_bytes,
                user_tag,
                profile_item.dim_m,
                profile_item.dim_n,
                profile_item.dim_k),
            UVM_MEDIUM)
    end
    endtask

    task automatic p21d_prepare_normal_source_and_dst(input int signed normal_a[],
                                                      input int signed normal_b[]);
    begin
        vif.dma_src_mem_clear();
        vif.dma_dst_mem_clear();

        vif.dma_src_set_rresp_error(1'b0, -1);
        vif.axis_src_set_rresp_error(1'b0, -1);
        vif.ds_src_set_rresp_error(1'b0, -1);
        vif.dma_dst_set_bresp_error(1'b0, -1);

        p21d_write_u8_payload_to_src(P21D_SRC_A_BASE, normal_a);
        p21d_write_u8_payload_to_src(P21D_SRC_B_BASE, normal_b);

        `uvm_info("P21D_MEM/PREP",
            $sformatf("Prepared mixed runtime-doorbell source memory: A=0x%08h bytes=%0d B=0x%08h bytes=%0d result_dst=0x%08h CQ=0x%08h",
                P21D_SRC_A_BASE,
                normal_a.size(),
                P21D_SRC_B_BASE,
                normal_b.size(),
                P21D_DMA_DST_C_BASE,
                P21D_CQ_BASE),
            UVM_MEDIUM)
    end
    endtask

    task automatic p21d_clear_cq_memory();
    begin
        for (int unsigned i = 0; i < (2 * P21D_ENTRY_STRIDE); i++) begin
            vif.dma_dst_mem[P21D_CQ_BASE + i] = 8'h00;
        end
    end
    endtask

    task automatic p21d_program_dma_descriptor_table(input ai_accel_subsys_seq_item normal_item,
                                                     input int unsigned normal_a_bytes,
                                                     input int unsigned normal_b_bytes,
                                                     input int unsigned normal_c_bytes);
    begin
        p21d_program_dma_descriptor(
            P21D_DMA_DESC_BASE + (0 * P21D_DESC_STRIDE),
            P21D_SLOT0_CONTROL_DMA_HOST_READBACK,
            normal_item,
            normal_a_bytes,
            normal_b_bytes,
            normal_c_bytes,
            P21D_DMA_TAG0
        );

        p21d_program_dma_descriptor(
            P21D_DMA_DESC_BASE + (1 * P21D_DESC_STRIDE),
            P21D_SLOT1_CONTROL_DMA_DMA_STORE,
            normal_item,
            normal_a_bytes,
            normal_b_bytes,
            normal_c_bytes,
            P21D_DMA_TAG1
        );
    end
    endtask

    task automatic p21d_program_ds_descriptor_table(input ai_accel_subsys_seq_item normal_item,
                                                    input int unsigned normal_a_bytes,
                                                    input int unsigned normal_b_bytes,
                                                    input int unsigned normal_c_bytes);
    begin
        p21d_program_direct_stream_descriptor(
            P21D_DS_DESC_BASE + (0 * P21D_DESC_STRIDE),
            P21D_SLOT0_CONTROL_DS_HOST_READBACK,
            normal_item,
            normal_a_bytes,
            normal_b_bytes,
            normal_c_bytes,
            P21D_DS_TAG0
        );

        p21d_program_direct_stream_descriptor(
            P21D_DS_DESC_BASE + (1 * P21D_DESC_STRIDE),
            P21D_SLOT1_CONTROL_DS_DMA_STORE,
            normal_item,
            normal_a_bytes,
            normal_b_bytes,
            normal_c_bytes,
            P21D_DS_TAG1
        );
    end
    endtask

    task automatic p21d_csr_clear_completion_wb();
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

    task automatic p21d_csr_program_completion_wb();
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_COMPLETION_WB_BASE_ADDR,
            32'(P21D_CQ_BASE)
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_COMPLETION_WB_CONTROL,
            32'h0000_0001
        );
    end
    endtask

    task automatic p21d_csr_clear_queue();
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

    task automatic p21d_csr_program_queue_initial_one_visible();
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE,   32'(P21D_SQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH,  32'(P21D_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,   32'h0000_0001);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, 32'(P21D_ENTRY_STRIDE));

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE,   32'(P21D_CQ_BASE));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH,  32'(P21D_QUEUE_DEPTH));
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,   32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, 32'(P21D_ENTRY_STRIDE));

        // bit0 QUEUE_ENABLE, bit1 RUN_UNTIL_EMPTY, bit2 STOP_ON_ERROR.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CONTROL, 32'h0000_0007);

        `uvm_info("P21D_QUEUE/CFG",
            "Programmed mixed live-service queue with initial SQ_HEAD=0 SQ_TAIL=1 CQ_HEAD=0 CQ_TAIL=0",
            UVM_MEDIUM)
    end
    endtask

    task automatic p21d_start_queue_once();
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_START] = 1'b1;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_COMMAND,
            cmd
        );

        `uvm_info("P21D_QUEUE/START", "Issued one CSR_QUEUE_COMMAND.START_QUEUE kick with only DMA SQ[0] visible", UVM_MEDIUM)
    end
    endtask

    task automatic p21d_wait_for_queue_active_before_doorbell(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] sq_head;
        logic [31:0] cq_tail;
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

            if ((error_status != 32'h0000_0000) ||
                (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P21D_QUEUE/ERROR_BEFORE_DOORBELL",
                    $sformatf("Queue failed before mixed runtime doorbell: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail))
            end

            if (status[0] && (sq_head == 32'h0000_0000) && (cq_tail == 32'h0000_0000)) begin
                `uvm_info("P21D_QUEUE/ACTIVE",
                    $sformatf("Queue is active before mixed runtime doorbell: status=0x%08h done=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h",
                        status,
                        done_status,
                        sq_head,
                        cq_tail),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P21D_QUEUE/ACTIVE_TIMEOUT",
                    $sformatf("Timed out waiting for queue active before mixed runtime doorbell: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail))
            end
        end
    end
    endtask

    task automatic p21d_append_ds_sq1_while_active();
        logic [31:0] status_before;
        logic [31:0] sq_tail_after;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status_before);
        if (!status_before[0]) begin
            `uvm_fatal("P21D_QUEUE/NOT_BUSY_AT_APPEND",
                $sformatf("Expected queue_busy=1 before mixed runtime doorbell append, status=0x%08h",
                    status_before))
        end

        p21d_program_one_sq_command_entry(1, P21D_CMD_DS_TAG, P21D_DS_DESC_BASE);

        // Runtime doorbell: host-owned SQ_TAIL moves while queue_busy=1.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL, 32'h0000_0002);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL, sq_tail_after);

        if (sq_tail_after !== 32'h0000_0002) begin
            `uvm_fatal("P21D_QUEUE/SQ_TAIL_DOORBELL_FAIL",
                $sformatf("Expected SQ_TAIL=2 after mixed runtime doorbell, got 0x%08h", sq_tail_after))
        end

        `uvm_info("P21D_QUEUE/DOORBELL",
            $sformatf("Mixed runtime doorbell issued while queue_busy=1: appended Direct Stream SQ[1], updated SQ_TAIL 1->2, status_before=0x%08h",
                status_before),
            UVM_MEDIUM)
    end
    endtask

    task automatic p21d_poll_mixed_runtime_queue_drained(input int unsigned timeout_cycles);
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
                `uvm_fatal("P21D_QUEUE/ERROR",
                    $sformatf("Queue failed during mixed runtime-doorbell drain: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail))
            end

            if ((sq_head == 32'h0000_0002) &&
                (cq_tail == 32'h0000_0002) &&
                (cq_occ  == 32'h0000_0002) &&
                done_status[1]) begin
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);
                if (last_tag !== P21D_CMD_DS_TAG) begin
                    `uvm_fatal("P21D_QUEUE/BAD_LAST_TAG",
                        $sformatf("Expected last accepted command tag=0x%08h got=0x%08h",
                            P21D_CMD_DS_TAG,
                            last_tag))
                end

                `uvm_info("P21D_QUEUE/DRAINED",
                    $sformatf("Mixed runtime-doorbell queue service completed after %0d poll(s): status=0x%08h done=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h last_tag=0x%08h",
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
                `uvm_fatal("P21D_QUEUE/TIMEOUT",
                    $sformatf("Timed out waiting for mixed runtime-doorbell queue drain: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h",
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

    function automatic logic [31:0] p21d_read_cq_word(input int unsigned cq_slot,
                                                      input int unsigned byte_offset);
        int unsigned idx;
        logic [31:0] value;
    begin
        idx = P21D_CQ_BASE + (cq_slot * P21D_ENTRY_STRIDE) + byte_offset;
        value = 32'h0000_0000;
        value[7:0]   = vif.dma_dst_mem[idx + 0];
        value[15:8]  = vif.dma_dst_mem[idx + 1];
        value[23:16] = vif.dma_dst_mem[idx + 2];
        value[31:24] = vif.dma_dst_mem[idx + 3];
        return value;
    end
    endfunction

    task automatic p21d_expect_cq_word(input int unsigned cq_slot,
                                       input int unsigned byte_offset,
                                       input logic [31:0] expected,
                                       input string name);
        logic [31:0] actual;
    begin
        actual = p21d_read_cq_word(cq_slot, byte_offset);
        if (actual !== expected) begin
            `uvm_fatal("P21D_CQ_WB/RECORD_MISMATCH",
                $sformatf("CQ[%0d] %s mismatch at +0x%02x: actual=0x%08h expected=0x%08h",
                    cq_slot,
                    name,
                    byte_offset,
                    actual,
                    expected))
        end

        `uvm_info("P21D_CQ_WB/CHECK",
            $sformatf("CQ[%0d] %s PASS at +0x%02x: 0x%08h",
                cq_slot,
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic p21d_expect_cq_word_nonzero(input int unsigned cq_slot,
                                               input int unsigned byte_offset,
                                               input string name);
        logic [31:0] actual;
    begin
        actual = p21d_read_cq_word(cq_slot, byte_offset);
        if (actual == 32'h0000_0000) begin
            `uvm_fatal("P21D_CQ_WB/RECORD_ZERO",
                $sformatf("CQ[%0d] %s unexpectedly zero at +0x%02x",
                    cq_slot,
                    name,
                    byte_offset))
        end

        `uvm_info("P21D_CQ_WB/CHECK",
            $sformatf("CQ[%0d] %s nonzero PASS at +0x%02x: 0x%08h",
                cq_slot,
                name,
                byte_offset,
                actual),
            UVM_LOW)
    end
    endtask

    task automatic p21d_check_one_cq_record(input int unsigned cq_slot,
                                            input logic [31:0] first_desc_tag,
                                            input logic [31:0] last_desc_tag,
                                            input int unsigned expected_macs,
                                            input int unsigned expected_outputs);
    begin
        p21d_expect_cq_word(cq_slot, 16'h00, P21D_EXP_COMMIT_SUCCESS, "word0 commit");
        p21d_expect_cq_word(cq_slot, 16'h04, P21D_EXP_STATUS_FLAGS,   "word1 status_flags");
        p21d_expect_cq_word(cq_slot, 16'h08, first_desc_tag,          "word2 first_user_tag");
        p21d_expect_cq_word(cq_slot, 16'h0C, last_desc_tag,           "word3 last_user_tag");
        p21d_expect_cq_word(cq_slot, 16'h10, P21D_EXP_COUNTS,         "word4 counts");
        p21d_expect_cq_word(cq_slot, 16'h14, P21D_EXP_DESC_DONE,      "word5 desc_fetch_done_status");
        p21d_expect_cq_word(cq_slot, 16'h18, P21D_EXP_ZERO,           "word6 desc_fetch_error_status");
        p21d_expect_cq_word(cq_slot, 16'h1C, P21D_EXP_ZERO,           "word7 desc_fetch_reject_status");
        p21d_expect_cq_word(cq_slot, 16'h20, P21D_EXP_RECIPE_DONE,    "word8 recipe_done_status");
        p21d_expect_cq_word(cq_slot, 16'h24, P21D_EXP_ZERO,           "word9 recipe_error_status");
        p21d_expect_cq_word(cq_slot, 16'h28, P21D_EXP_ZERO,           "word10 recipe_reject_status");
        p21d_expect_cq_word(cq_slot, 16'h2C, P21D_EXP_SLOT_MASKS,     "word11 slot_mask_summary");
        p21d_expect_cq_word_nonzero(cq_slot, 16'h30,                 "word12 perf_busy_cycles");
        p21d_expect_cq_word(cq_slot, 16'h34, 32'(expected_macs),      "word13 perf_mac_count");
        p21d_expect_cq_word(cq_slot, 16'h38, 32'(expected_outputs),   "word14 perf_output_count");
        p21d_expect_cq_word(cq_slot, 16'h3C, P21D_EXP_ZERO,           "word15 error_detail");
    end
    endtask

    task automatic p21d_check_cq_records(input ai_accel_subsys_seq_item normal_item);
        int unsigned normal_macs;
        int unsigned normal_outputs;
    begin
        normal_macs    = 2 * int'(normal_item.dim_m) * int'(normal_item.dim_n) * int'(normal_item.dim_k);
        normal_outputs = 2 * int'(normal_item.dim_m) * int'(normal_item.dim_n);

        p21d_check_one_cq_record(0, P21D_DMA_TAG0, P21D_DMA_TAG1, normal_macs, normal_outputs);
        p21d_check_one_cq_record(1, P21D_DS_TAG0,  P21D_DS_TAG1,  normal_macs, normal_outputs);
    end
    endtask

    task run_phase(uvm_phase phase);
        ai_accel_subsys_seq_item normal_item;
        int signed               normal_a[];
        int signed               normal_b[];
        int signed               expected_c[];
        int signed               actual_c[];
        int unsigned             c_elems;
        int unsigned             c_bytes;
    begin
        phase.raise_objection(this);

        `uvm_info("P21D_RUNTIME_DOORBELL_MIXED/START",
            "Starting P21D append-while-active mixed DMA + Direct Stream queue smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        case_helper.build_variable_case_payload(
            P21D_NORMAL_CASE_ID,
            normal_item,
            normal_a,
            normal_b,
            expected_c
        );

        c_elems = int'(normal_item.dim_m) * int'(normal_item.dim_n);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P21D_RUNTIME_DOORBELL_MIXED/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        `uvm_info("P21D_RUNTIME_DOORBELL_MIXED",
            $sformatf("Built mixed runtime-doorbell payload: normal CASE_ID=%0d dim=(%0d,%0d,%0d) A_bytes=%0d B_bytes=%0d C_words=%0d",
                P21D_NORMAL_CASE_ID,
                normal_item.dim_m,
                normal_item.dim_n,
                normal_item.dim_k,
                normal_a.size(),
                normal_b.size(),
                c_elems),
            UVM_MEDIUM)

        p21d_prepare_normal_source_and_dst(normal_a, normal_b);
        p21d_clear_cq_memory();

        p21d_program_dma_descriptor_table(
            normal_item,
            normal_a.size(),
            normal_b.size(),
            c_bytes
        );

        p21d_program_ds_descriptor_table(
            normal_item,
            normal_a.size(),
            normal_b.size(),
            c_bytes
        );

        // Only the DMA command is visible before START_QUEUE.  The Direct
        // Stream command is appended while the queue is actively servicing
        // SQ[0].
        p21d_program_one_sq_command_entry(0, P21D_CMD_DMA_TAG, P21D_DMA_DESC_BASE);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        p21d_csr_clear_completion_wb();
        p21d_csr_clear_queue();

        p21d_csr_program_completion_wb();
        p21d_csr_program_queue_initial_one_visible();

        csr_check_recipe_idle_ready("before P21D mixed queue START");
        p21d_start_queue_once();

        p21d_wait_for_queue_active_before_doorbell(done_timeout_cycles);
        p21d_append_ds_sq1_while_active();

        p21d_poll_mixed_runtime_queue_drained(done_timeout_cycles * 6);

        repeat (5) @(posedge csr_vif.clk);

        p21d_check_cq_records(normal_item);

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("P21D_RUNTIME_DOORBELL_MIXED/PASS",
            $sformatf("P21D mixed runtime doorbell queue service completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d SQ[0]=DMA SQ[1]=DirectStream CQ_entries=2",
                P21D_NORMAL_CASE_ID,
                normal_a.size(),
                normal_b.size(),
                c_elems),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
