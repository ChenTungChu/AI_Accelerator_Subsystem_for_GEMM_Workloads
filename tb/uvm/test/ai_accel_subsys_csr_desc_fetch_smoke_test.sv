// File: tb/uvm/test/ai_accel_subsys_csr_desc_fetch_smoke_test.sv
// ============================================================
// P17C CSR descriptor-fetch smoke test
//
// Scope:
//   - Uses the existing CSR UVM top and run_uvm.tcl flow.
//   - Prepares a two-descriptor table in the existing source
//     memory model.
//   - Programs the P17 descriptor-fetch CSR window.
//   - Issues START_FETCH and checks CSR-visible fetch completion.
//
// This test intentionally does not start the P16 recipe sequencer.
// P17D will bridge the fetched snapshot into the recipe start path.
// ============================================================

`ifndef AI_ACCEL_SUBSYS_CSR_DESC_FETCH_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_DESC_FETCH_SMOKE_TEST_SV

class ai_accel_subsys_csr_desc_fetch_smoke_test extends uvm_test;
    `uvm_component_utils(ai_accel_subsys_csr_desc_fetch_smoke_test)

    typedef virtual axi_lite_if #(
        .ADDR_WIDTH (12),
        .DATA_WIDTH (32)
    ) csr_vif_t;

    typedef virtual ai_accel_subsys_ctrl_if #(
        .ADDR_WIDTH        (32),
        .DIM_WIDTH         (8),
        .DMA_SRC_MEM_BYTES (4096),
        .DMA_DST_MEM_BYTES (4096)
    ) ctrl_vif_t;

    localparam int unsigned DESC_WORD_CONTROL          = 0;
    localparam int unsigned DESC_WORD_BASE_ADDR_A      = 1;
    localparam int unsigned DESC_WORD_BASE_ADDR_B      = 2;
    localparam int unsigned DESC_WORD_BASE_ADDR_C      = 3;
    localparam int unsigned DESC_WORD_DIM_M            = 4;
    localparam int unsigned DESC_WORD_DIM_N            = 5;
    localparam int unsigned DESC_WORD_DIM_K            = 6;
    localparam int unsigned DESC_WORD_A_SRC_BASE       = 7;
    localparam int unsigned DESC_WORD_A_DST_BASE       = 8;
    localparam int unsigned DESC_WORD_A_LOAD_BEATS     = 9;
    localparam int unsigned DESC_WORD_B_SRC_BASE       = 10;
    localparam int unsigned DESC_WORD_B_DST_BASE       = 11;
    localparam int unsigned DESC_WORD_B_LOAD_BEATS     = 12;
    localparam int unsigned DESC_WORD_STORE_SRC_BASE   = 13;
    localparam int unsigned DESC_WORD_STORE_DST_BASE   = 14;
    localparam int unsigned DESC_WORD_STORE_BYTE_COUNT = 15;
    localparam int unsigned DESC_WORD_USER_TAG         = 16;

    localparam logic [31:0] SLOT_CTRL_VALID            = 32'h0000_0001;
    localparam logic [31:0] SLOT_CTRL_INPUT_DMA_LOAD   = 32'h0000_0002;
    localparam logic [31:0] SLOT_CTRL_OUTPUT_DMA_STORE = 32'h0000_0008;

    localparam logic [31:0] DESC_FETCH_STATUS_DONE_BIT = 32'h0000_0002;
    localparam logic [31:0] DESC_FETCH_STATUS_ERR_BIT  = 32'h0000_0004;

    csr_vif_t csr_vif;
    ctrl_vif_t ctrl_vif;
    ai_accel_csr_access_helper csr;

    function new(string name = "ai_accel_subsys_csr_desc_fetch_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(csr_vif_t)::get(this, "", "csr_vif", csr_vif)) begin
            `uvm_fatal("P17C_DESC_FETCH/NOCSRVIF", "csr_vif not found")
        end

        if (!uvm_config_db#(ctrl_vif_t)::get(this, "", "vif", ctrl_vif)) begin
            `uvm_fatal("P17C_DESC_FETCH/NOCTRLVIF", "control vif not found")
        end

        csr = ai_accel_csr_access_helper::type_id::create("csr");
        csr.set_vif(csr_vif);
    endfunction

    task automatic write_src_word_le(
        input int unsigned byte_addr,
        input logic [31:0] value
    );
    begin
        ctrl_vif.dma_src_mem[byte_addr + 0] = value[7:0];
        ctrl_vif.dma_src_mem[byte_addr + 1] = value[15:8];
        ctrl_vif.dma_src_mem[byte_addr + 2] = value[23:16];
        ctrl_vif.dma_src_mem[byte_addr + 3] = value[31:24];
    end
    endtask

    task automatic write_desc_word(
        input int unsigned desc_base,
        input int unsigned word_idx,
        input logic [31:0] value
    );
    begin
        write_src_word_le(desc_base + (word_idx * 4), value);
    end
    endtask

    task automatic program_descriptor(
        input int unsigned desc_base,
        input logic [31:0] control,
        input logic [31:0] user_tag
    );
    begin
        write_desc_word(desc_base, DESC_WORD_CONTROL,          control);
        write_desc_word(desc_base, DESC_WORD_BASE_ADDR_A,      32'h0000_0000);
        write_desc_word(desc_base, DESC_WORD_BASE_ADDR_B,      32'h0000_0100);
        write_desc_word(desc_base, DESC_WORD_BASE_ADDR_C,      32'h0000_0200);
        write_desc_word(desc_base, DESC_WORD_DIM_M,            32'd4);
        write_desc_word(desc_base, DESC_WORD_DIM_N,            32'd4);
        write_desc_word(desc_base, DESC_WORD_DIM_K,            32'd4);
        write_desc_word(desc_base, DESC_WORD_A_SRC_BASE,       32'h0000_0000);
        write_desc_word(desc_base, DESC_WORD_A_DST_BASE,       32'h0000_0000);
        write_desc_word(desc_base, DESC_WORD_A_LOAD_BEATS,     32'd1);
        write_desc_word(desc_base, DESC_WORD_B_SRC_BASE,       32'h0000_0100);
        write_desc_word(desc_base, DESC_WORD_B_DST_BASE,       32'h0000_0100);
        write_desc_word(desc_base, DESC_WORD_B_LOAD_BEATS,     32'd1);
        write_desc_word(desc_base, DESC_WORD_STORE_SRC_BASE,   32'h0000_0200);
        write_desc_word(desc_base, DESC_WORD_STORE_DST_BASE,   32'h0000_0000);
        write_desc_word(desc_base, DESC_WORD_STORE_BYTE_COUNT, 32'd64);
        write_desc_word(desc_base, DESC_WORD_USER_TAG,         user_tag);
    end
    endtask

    task automatic poll_fetch_done();
        logic [31:0] status;
        int unsigned poll;
    begin
        status = 32'h0;
        for (poll = 0; poll < 2000; poll++) begin
            csr.read32_expect_okay(csr.CSR_DESC_FETCH_STATUS, status);

            if (status & DESC_FETCH_STATUS_ERR_BIT) begin
                `uvm_fatal("P17C_DESC_FETCH/ERR",
                    $sformatf("Descriptor fetch reported error status=0x%08h", status))
            end

            if (status & DESC_FETCH_STATUS_DONE_BIT) begin
                `uvm_info("P17C_DESC_FETCH/DONE",
                    $sformatf("Descriptor fetch done after %0d poll(s), status=0x%08h", poll, status),
                    UVM_LOW)
                return;
            end

            @(posedge csr_vif.clk);
        end

        `uvm_fatal("P17C_DESC_FETCH/TIMEOUT", "Timed out waiting for descriptor fetch done")
    end
    endtask

    task run_phase(uvm_phase phase);
        logic [31:0] data;
        int unsigned desc_base;
        int unsigned desc_stride;
    begin
        phase.raise_objection(this);

        desc_base   = 32'h0000_0300;
        desc_stride = 32'h0000_0080;

        `uvm_info("P17C_DESC_FETCH/START", "Starting P17C CSR descriptor-fetch smoke test", UVM_LOW)

        csr.init_bus();
        csr.wait_reset_release();

        ctrl_vif.dma_src_mem_clear();

        // Descriptor 0: HOST_PRELOADED + HOST_READBACK valid descriptor.
        program_descriptor(desc_base + (0 * desc_stride),
                           SLOT_CTRL_VALID,
                           32'hD17C_0000);

        // Descriptor 1: DMA_LOAD + DMA_STORE valid descriptor.
        program_descriptor(desc_base + (1 * desc_stride),
                           SLOT_CTRL_VALID | SLOT_CTRL_INPUT_DMA_LOAD | SLOT_CTRL_OUTPUT_DMA_STORE,
                           32'hD17C_0001);

        csr.read32_expect_okay(csr.CSR_DESC_FETCH_VERSION, data);
        if (data !== 32'h0001_0017) begin
            `uvm_fatal("P17C_DESC_FETCH/VERSION",
                $sformatf("Unexpected descriptor-fetch version: 0x%08h", data))
        end

        csr.write32_expect_okay(csr.CSR_DESC_FETCH_BASE_ADDR,    desc_base[31:0]);
        csr.write32_expect_okay(csr.CSR_DESC_FETCH_COUNT,        32'd2);
        csr.write32_expect_okay(csr.CSR_DESC_FETCH_STRIDE_BYTES, desc_stride[31:0]);

        csr.issue_command(32'h0000_0001, csr.CSR_DESC_FETCH_COMMAND);

        poll_fetch_done();

        csr.read32_expect_okay(csr.CSR_DESC_FETCH_DONE_STATUS, data);
        if (data[1:0] !== 2'b11) begin
            `uvm_fatal("P17C_DESC_FETCH/DONE_STATUS",
                $sformatf("Expected DONE_STATUS[1:0]=2'b11, got 0x%08h", data))
        end

        csr.read32_expect_okay(csr.CSR_DESC_FETCH_ERROR_STATUS, data);
        if (data !== 32'h0000_0000) begin
            `uvm_fatal("P17C_DESC_FETCH/ERROR_STATUS",
                $sformatf("Expected ERROR_STATUS=0, got 0x%08h", data))
        end

        csr.read32_expect_okay(csr.CSR_DESC_FETCH_REJECT_STATUS, data);
        if (data !== 32'h0000_0000) begin
            `uvm_fatal("P17C_DESC_FETCH/REJECT_STATUS",
                $sformatf("Expected REJECT_STATUS=0, got 0x%08h", data))
        end

        csr.read32_expect_okay(csr.CSR_DESC_FETCH_FETCHED_COUNT, data);
        if (data[3:0] !== 4'd2) begin
            `uvm_fatal("P17C_DESC_FETCH/FETCHED_COUNT",
                $sformatf("Expected FETCHED_COUNT=2, got 0x%08h", data))
        end

        csr.read32_expect_okay(csr.CSR_DESC_FETCH_SNAPSHOT_STATUS, data);
        if ((data[0] !== 1'b1) || (data[7:4] !== 4'd2) || (data[11:8] !== 4'd2)) begin
            `uvm_fatal("P17C_DESC_FETCH/SNAPSHOT",
                $sformatf("Unexpected SNAPSHOT_STATUS=0x%08h", data))
        end

        `uvm_info("P17C_DESC_FETCH/PASS", "P17C CSR descriptor-fetch smoke completed", UVM_LOW)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
