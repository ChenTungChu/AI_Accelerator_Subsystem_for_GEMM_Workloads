// File: tb/uvm/test/ai_accel_subsys_csr_completion_wb_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_COMPLETION_WB_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_COMPLETION_WB_SMOKE_TEST_SV

// ------------------------------------------------------------
// P18D CSR-triggered completion writeback smoke
//
// Scope:
//   - programs the P18 completion-writeback CSR window
//   - issues START_COMPLETION_WB
//   - lets ai_accel_completion_wb_engine write one 64-byte record
//   - checks the final VALID commit word is written last-visible
//     in host-visible completion memory
//
// This test intentionally does not launch P17/P16/P15 yet.  It is
// a standalone CSR plumbing smoke for the P18 writeback path.
// ------------------------------------------------------------

class ai_accel_subsys_csr_completion_wb_smoke_test extends uvm_test;
    `uvm_component_utils(ai_accel_subsys_csr_completion_wb_smoke_test)

    typedef virtual axi_lite_if #(
        .ADDR_WIDTH (12),
        .DATA_WIDTH (32)
    ) csr_vif_t;

    virtual ai_accel_subsys_ctrl_if vif;
    csr_vif_t                       csr_vif;
    ai_accel_csr_access_helper      csr;

    localparam int unsigned COMP_BASE_ADDR      = 32'h0000_0300;
    localparam logic [31:0] EXP_STATUS_FLAGS    = 32'h0000_00A5;
    localparam logic [31:0] EXP_USER_TAG        = 32'hD18D_0001;
    localparam logic [31:0] EXP_COUNTS          = 32'h0002_0202; // completed/fetched/programmed = 2/2/2
    localparam logic [31:0] EXP_RECIPE_DONE     = 32'h0000_0007;
    localparam logic [31:0] EXP_RECIPE_ERROR    = 32'h0000_0000;
    localparam logic [31:0] EXP_RECIPE_REJECT   = 32'h0000_0000;
    localparam logic [31:0] EXP_PERF_MAC_COUNT  = 32'h0000_0020;
    localparam logic [31:0] EXP_ERROR_DETAIL    = 32'h0000_0000;

    function new(string name = "ai_accel_subsys_csr_completion_wb_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("P18D_COMP_WB/NOVIF", "virtual interface ai_accel_subsys_ctrl_if is not set")
        end

        if (!uvm_config_db#(csr_vif_t)::get(this, "", "csr_vif", csr_vif)) begin
            `uvm_fatal("P18D_COMP_WB/NOCSRVIF", "csr_vif is not set")
        end

        csr = ai_accel_csr_access_helper::type_id::create("csr");
        csr.set_vif(csr_vif);
    endfunction

    function automatic logic [31:0] read_comp_word(input int unsigned byte_offset);
        int unsigned idx;
        logic [31:0] value;
    begin
        idx = COMP_BASE_ADDR + byte_offset;
        value = 32'h0000_0000;
        value[7:0]   = vif.dma_dst_mem[idx + 0];
        value[15:8]  = vif.dma_dst_mem[idx + 1];
        value[23:16] = vif.dma_dst_mem[idx + 2];
        value[31:24] = vif.dma_dst_mem[idx + 3];
        return value;
    end
    endfunction

    task automatic wait_completion_done(input int unsigned timeout_cycles = 500);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_REJECT_STATUS, reject_status);

            if (done_status[0]) begin
                if (error_status != 32'h0000_0000) begin
                    `uvm_fatal("P18D_COMP_WB/ERROR_STATUS", $sformatf("Unexpected completion WB error_status=0x%08h status=0x%08h", error_status, status))
                end
                if (reject_status != 32'h0000_0000) begin
                    `uvm_fatal("P18D_COMP_WB/REJECT_STATUS", $sformatf("Unexpected completion WB reject_status=0x%08h status=0x%08h", reject_status, status))
                end
                `uvm_info("P18D_COMP_WB", $sformatf("Completion writeback done after %0d poll(s): status=0x%08h done=0x%08h", cnt, status, done_status), UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P18D_COMP_WB/TIMEOUT", $sformatf("Timed out waiting for completion WB done; status=0x%08h done=0x%08h error=0x%08h reject=0x%08h", status, done_status, error_status, reject_status))
            end
        end
    end
    endtask

    task automatic expect_comp_word(input int unsigned byte_offset,
                                    input logic [31:0] expected,
                                    input string name);
        logic [31:0] actual;
    begin
        actual = read_comp_word(byte_offset);
        if (actual !== expected) begin
            `uvm_fatal("P18D_COMP_WB/RECORD_MISMATCH",
                $sformatf("%s mismatch at +0x%02x: actual=0x%08h expected=0x%08h",
                    name, byte_offset, actual, expected))
        end
        `uvm_info("P18D_COMP_WB/CHECK",
            $sformatf("%s PASS at +0x%02x: 0x%08h", name, byte_offset, actual),
            UVM_LOW)
    end
    endtask

    task run_phase(uvm_phase phase);
        logic [31:0] cmd;
        logic [31:0] commit_word;
    begin
        phase.raise_objection(this);

        `uvm_info("P18D_COMP_WB", "Starting P18D CSR completion writeback smoke test", UVM_MEDIUM)

        repeat (10) @(posedge csr_vif.clk);

        vif.dma_dst_mem_clear();

        // Clear any sticky status left by reset-time or earlier debug activity.
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::COMP_WB_CMD_CLEAR_DONE]  = 1'b1;
        cmd[ai_accel_csr_access_helper::COMP_WB_CMD_CLEAR_ERROR] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_COMMAND, cmd);

        csr.expect_read32(ai_accel_csr_access_helper::CSR_COMPLETION_WB_VERSION, 32'h0001_0018, "CSR_COMPLETION_WB_VERSION");

        // Program standalone payload snapshot.
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_BASE_ADDR, COMP_BASE_ADDR);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_CONTROL, 32'h0000_0003); // enable + overall_done
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_STATUS_FLAGS, EXP_STATUS_FLAGS);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_USER_TAG, EXP_USER_TAG);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_COUNTS, EXP_COUNTS);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_RECIPE_DONE, EXP_RECIPE_DONE);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_RECIPE_ERROR, EXP_RECIPE_ERROR);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_RECIPE_REJECT, EXP_RECIPE_REJECT);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_PERF_MAC_COUNT, EXP_PERF_MAC_COUNT);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_ERROR_DETAIL, EXP_ERROR_DETAIL);

        // Read back CSR payload registers before START_COMPLETION_WB.
        // This catches CSR-map/plumbing mistakes before checking memory.
        csr.expect_read32(ai_accel_csr_access_helper::CSR_COMPLETION_WB_STATUS_FLAGS, EXP_STATUS_FLAGS, "CSR_COMPLETION_WB_STATUS_FLAGS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_COMPLETION_WB_USER_TAG, EXP_USER_TAG, "CSR_COMPLETION_WB_USER_TAG");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_COMPLETION_WB_COUNTS, EXP_COUNTS, "CSR_COMPLETION_WB_COUNTS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_COMPLETION_WB_RECIPE_DONE, EXP_RECIPE_DONE, "CSR_COMPLETION_WB_RECIPE_DONE");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_COMPLETION_WB_RECIPE_ERROR, EXP_RECIPE_ERROR, "CSR_COMPLETION_WB_RECIPE_ERROR");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_COMPLETION_WB_RECIPE_REJECT, EXP_RECIPE_REJECT, "CSR_COMPLETION_WB_RECIPE_REJECT");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_COMPLETION_WB_PERF_MAC_COUNT, EXP_PERF_MAC_COUNT, "CSR_COMPLETION_WB_PERF_MAC_COUNT");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_COMPLETION_WB_ERROR_DETAIL, EXP_ERROR_DETAIL, "CSR_COMPLETION_WB_ERROR_DETAIL");

        // Start writeback.
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::COMP_WB_CMD_START] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_COMPLETION_WB_COMMAND, cmd);

        wait_completion_done();

        repeat (5) @(posedge csr_vif.clk);

        commit_word = {8'h01, 8'h00, 8'h18, 4'h0, 1'b0, 1'b0, 1'b1, 1'b1};

        expect_comp_word(16'h00, commit_word, "word0 commit");
        expect_comp_word(16'h04, EXP_STATUS_FLAGS, "word1 status_flags");
        expect_comp_word(16'h08, EXP_USER_TAG, "word2 first_user_tag");
        expect_comp_word(16'h0C, EXP_USER_TAG, "word3 last_user_tag");
        expect_comp_word(16'h10, EXP_COUNTS, "word4 counts");
        expect_comp_word(16'h20, EXP_RECIPE_DONE, "word8 recipe_done_status");
        expect_comp_word(16'h24, EXP_RECIPE_ERROR, "word9 recipe_error_status");
        expect_comp_word(16'h28, EXP_RECIPE_REJECT, "word10 recipe_reject_status");
        expect_comp_word(16'h34, EXP_PERF_MAC_COUNT, "word13 perf_mac_count");
        expect_comp_word(16'h3C, EXP_ERROR_DETAIL, "word15 error_detail");

        `uvm_info("P18D_COMP_WB", "P18D CSR completion writeback smoke completed", UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask
endclass

`endif
