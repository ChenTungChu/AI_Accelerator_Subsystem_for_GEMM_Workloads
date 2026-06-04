// File: tb/uvm/test/ai_accel_csr_regs_smoke_test.sv

`ifndef AI_ACCEL_CSR_REGS_SMOKE_TEST_SV
`define AI_ACCEL_CSR_REGS_SMOKE_TEST_SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "ai_accel_csr_access_helper.sv"

class ai_accel_csr_regs_smoke_test extends uvm_test;
    `uvm_component_utils(ai_accel_csr_regs_smoke_test)

    typedef virtual axi_lite_if #(
        .ADDR_WIDTH (12),
        .DATA_WIDTH (32)
    ) csr_vif_t;

    typedef virtual ai_accel_csr_status_if #(
        .DATA_WIDTH (32)
    ) status_vif_t;

    localparam logic [31:0] CSR_VERSION_VALUE        = 32'h0001_0014;
    localparam logic [31:0] CSR_JOB_VERSION_VALUE    = 32'h0001_0015;
    localparam logic [31:0] CSR_RECIPE_VERSION_VALUE = 32'h0001_0016;
    localparam logic [1:0]  AXI_RESP_SLVERR   = 2'b10;

    csr_vif_t                    csr_vif;
    status_vif_t                 status_vif;
    ai_accel_csr_access_helper   csr;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_csr_regs_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(csr_vif_t)::get(this, "", "csr_vif", csr_vif)) begin
            `uvm_fatal("CSR_SMOKE/NOCSRVIF",
                "csr_vif was not provided through uvm_config_db")
        end

        if (!uvm_config_db#(status_vif_t)::get(this, "", "status_vif", status_vif)) begin
            `uvm_fatal("CSR_SMOKE/NOSTATUSVIF",
                "status_vif was not provided through uvm_config_db")
        end

        csr = ai_accel_csr_access_helper::type_id::create("csr");
        csr.set_vif(csr_vif);
    endfunction

    // ------------------------------------------------------------
    // Basic CSR reset/default checks
    // ------------------------------------------------------------
    task automatic check_reset_defaults();
    begin
        csr.expect_read32(ai_accel_csr_access_helper::CSR_VERSION,             CSR_VERSION_VALUE, "CSR_VERSION");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_COMMAND,             32'h0000_0000,    "CSR_COMMAND");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_STATUS,              32'h0001_0000,    "CSR_STATUS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DONE_STATUS,         32'h0000_0000,    "CSR_DONE_STATUS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_ERROR_STATUS,        32'h0000_0000,    "CSR_ERROR_STATUS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_MODE,                32'h0000_0000,    "CSR_MODE");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS,   32'h0000_0000,    "CSR_CMD_REJECT_STATUS");

        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_VERSION,         CSR_JOB_VERSION_VALUE, "CSR_JOB_VERSION");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_COMMAND,         32'h0000_0000,    "CSR_JOB_COMMAND");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_STATUS,          32'h0001_0008,    "CSR_JOB_STATUS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_DONE_STATUS,     32'h0000_0000,    "CSR_JOB_DONE_STATUS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_ERROR_STATUS,    32'h0000_0000,    "CSR_JOB_ERROR_STATUS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_MODE,            32'h0000_0004,    "CSR_JOB_MODE");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS,   32'h0000_0000,    "CSR_JOB_REJECT_STATUS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_STATE,           32'h0000_0000,    "CSR_JOB_STATE");

        csr.expect_read32(ai_accel_csr_access_helper::CSR_BASE_ADDR_A,         32'h0000_0000,    "CSR_BASE_ADDR_A");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_BASE_ADDR_B,         32'h0000_0100,    "CSR_BASE_ADDR_B");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_BASE_ADDR_C,         32'h0000_0200,    "CSR_BASE_ADDR_C");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DIM_M,               32'h0000_0004,    "CSR_DIM_M");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DIM_N,               32'h0000_0004,    "CSR_DIM_N");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DIM_K,               32'h0000_0004,    "CSR_DIM_K");

        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_BASE_ADDR_A,      32'h0000_0000,    "CSR_JOB_BASE_ADDR_A");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_BASE_ADDR_B,      32'h0000_0100,    "CSR_JOB_BASE_ADDR_B");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_BASE_ADDR_C,      32'h0000_0200,    "CSR_JOB_BASE_ADDR_C");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_DIM_M,            32'h0000_0004,    "CSR_JOB_DIM_M");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_DIM_N,            32'h0000_0004,    "CSR_JOB_DIM_N");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_DIM_K,            32'h0000_0004,    "CSR_JOB_DIM_K");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_A_SRC_BASE,       32'h0000_0000,    "CSR_JOB_A_SRC_BASE");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_A_DST_BASE,       32'h0000_0000,    "CSR_JOB_A_DST_BASE");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_A_LOAD_BEATS,     32'h0000_0000,    "CSR_JOB_A_LOAD_BEATS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_B_SRC_BASE,       32'h0000_0100,    "CSR_JOB_B_SRC_BASE");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_B_DST_BASE,       32'h0000_0100,    "CSR_JOB_B_DST_BASE");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_B_LOAD_BEATS,     32'h0000_0000,    "CSR_JOB_B_LOAD_BEATS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_STORE_SRC_BASE,   32'h0000_0200,    "CSR_JOB_STORE_SRC_BASE");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_STORE_DST_BASE,   32'h0000_0000,    "CSR_JOB_STORE_DST_BASE");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_STORE_BYTE_COUNT, 32'h0000_0000,    "CSR_JOB_STORE_BYTE_COUNT");

        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_VERSION,       CSR_RECIPE_VERSION_VALUE, "CSR_RECIPE_VERSION");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_COMMAND,       32'h0000_0000,    "CSR_RECIPE_COMMAND");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_STATUS,        32'h0001_0008,    "CSR_RECIPE_STATUS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_DONE_STATUS,   32'h0000_0000,    "CSR_RECIPE_DONE_STATUS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_ERROR_STATUS,  32'h0000_0000,    "CSR_RECIPE_ERROR_STATUS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_CONTROL,       32'h0000_0700,    "CSR_RECIPE_CONTROL");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS, 32'h0000_0000,    "CSR_RECIPE_REJECT_STATUS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_STATE,         32'h0000_0000,    "CSR_RECIPE_STATE");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_CURRENT_SLOT,  32'h0000_0000,    "CSR_RECIPE_CURRENT_SLOT");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_COMPLETED_COUNT, 32'h0000_0000,  "CSR_RECIPE_COMPLETED_COUNT");

        for (int unsigned slot_i = 0; slot_i < 4; slot_i++) begin
            csr.expect_read32(csr.recipe_slot_addr(slot_i, ai_accel_csr_access_helper::SLOT_CONTROL),
                32'h0000_0000, $sformatf("SLOT%0d_CONTROL", slot_i));
            csr.expect_read32(csr.recipe_slot_addr(slot_i, ai_accel_csr_access_helper::SLOT_BASE_ADDR_A),
                32'h0000_0000, $sformatf("SLOT%0d_BASE_A", slot_i));
            csr.expect_read32(csr.recipe_slot_addr(slot_i, ai_accel_csr_access_helper::SLOT_BASE_ADDR_B),
                32'h0000_0100, $sformatf("SLOT%0d_BASE_B", slot_i));
            csr.expect_read32(csr.recipe_slot_addr(slot_i, ai_accel_csr_access_helper::SLOT_BASE_ADDR_C),
                32'h0000_0200, $sformatf("SLOT%0d_BASE_C", slot_i));
            csr.expect_read32(csr.recipe_slot_addr(slot_i, ai_accel_csr_access_helper::SLOT_DIM_M),
                32'h0000_0004, $sformatf("SLOT%0d_DIM_M", slot_i));
            csr.expect_read32(csr.recipe_slot_addr(slot_i, ai_accel_csr_access_helper::SLOT_DIM_N),
                32'h0000_0004, $sformatf("SLOT%0d_DIM_N", slot_i));
            csr.expect_read32(csr.recipe_slot_addr(slot_i, ai_accel_csr_access_helper::SLOT_DIM_K),
                32'h0000_0004, $sformatf("SLOT%0d_DIM_K", slot_i));
        end
    end
    endtask

    // ------------------------------------------------------------
    // Read/write register checks
    // ------------------------------------------------------------
    task automatic check_rw_registers();
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_MODE, 32'hFFFF_FFFF);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_MODE, 32'h0000_0003, "CSR_MODE mask");

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_BASE_ADDR_A, 32'h1122_3344);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_BASE_ADDR_A, 32'h1122_3344, "BASE_A full write");

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_BASE_ADDR_A, 32'h0000_AA00, 4'b0010);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_BASE_ADDR_A, 32'h1122_AA44, "BASE_A byte strobe");

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_BASE_ADDR_B, 32'h0000_1400);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_BASE_ADDR_C, 32'h0000_2800);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DIM_M,       32'h0000_0005);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DIM_N,       32'h0000_0007);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DIM_K,       32'h0000_0009);

        csr.expect_read32(ai_accel_csr_access_helper::CSR_BASE_ADDR_B, 32'h0000_1400, "BASE_B");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_BASE_ADDR_C, 32'h0000_2800, "BASE_C");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DIM_M,       32'h0000_0005, "DIM_M");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DIM_N,       32'h0000_0007, "DIM_N");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DIM_K,       32'h0000_0009, "DIM_K");

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DMA_LOAD_SRC_BASE,    32'h0000_3000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DMA_LOAD_DST_BASE,    32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DMA_LOAD_BEATS,       32'h0000_0008);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_AXIS_SRC_BASE,        32'h0000_3400);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_AXIS_DST_BASE,        32'h0000_0100);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_AXIS_LOAD_BEATS,      32'h0000_0004);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DS_SRC_BASE,          32'h0000_3800);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DS_DST_BASE,          32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DS_LOAD_BEATS,        32'h0000_0002);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DS_CONTROL,           32'hFFFF_FFFF);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DMA_STORE_SRC_BASE,   32'h0000_0200);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DMA_STORE_DST_BASE,   32'h0000_3C00);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DMA_STORE_BYTE_COUNT, 32'h0000_0040);

        csr.expect_read32(ai_accel_csr_access_helper::CSR_DMA_LOAD_SRC_BASE,    32'h0000_3000, "DMA_LOAD_SRC");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DMA_LOAD_DST_BASE,    32'h0000_0000, "DMA_LOAD_DST");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DMA_LOAD_BEATS,       32'h0000_0008, "DMA_LOAD_BEATS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_AXIS_SRC_BASE,        32'h0000_3400, "AXIS_SRC");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_AXIS_DST_BASE,        32'h0000_0100, "AXIS_DST");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_AXIS_LOAD_BEATS,      32'h0000_0004, "AXIS_BEATS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DS_SRC_BASE,          32'h0000_3800, "DS_SRC");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DS_DST_BASE,          32'h0000_0000, "DS_DST");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DS_LOAD_BEATS,        32'h0000_0002, "DS_BEATS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DS_CONTROL,           32'h0000_0001, "DS_CONTROL mask");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DMA_STORE_SRC_BASE,   32'h0000_0200, "STORE_SRC");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DMA_STORE_DST_BASE,   32'h0000_3C00, "STORE_DST");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DMA_STORE_BYTE_COUNT, 32'h0000_0040, "STORE_BYTES");
    end
    endtask

    // ------------------------------------------------------------
    // P15 job descriptor read/write register checks
    // ------------------------------------------------------------
    task automatic check_job_rw_registers();
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_MODE, 32'hFFFF_FFFF);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_MODE, 32'h0000_003F, "CSR_JOB_MODE mask");

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_MODE, 32'h0000_0005);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_MODE, 32'h0000_0005, "CSR_JOB_MODE DMA load/store");

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_BASE_ADDR_A,      32'h0000_0400);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_BASE_ADDR_B,      32'h0000_0800);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_BASE_ADDR_C,      32'h0000_0C00);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_DIM_M,            32'h0000_0002);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_DIM_N,            32'h0000_0003);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_DIM_K,            32'h0000_0004);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_A_SRC_BASE,       32'h0000_1000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_A_DST_BASE,       32'h0000_0400);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_A_LOAD_BEATS,     32'h0000_0002);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_B_SRC_BASE,       32'h0000_1100);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_B_DST_BASE,       32'h0000_0800);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_B_LOAD_BEATS,     32'h0000_0003);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_STORE_SRC_BASE,   32'h0000_0C00);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_STORE_DST_BASE,   32'h0000_2000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_STORE_BYTE_COUNT, 32'h0000_0018);

        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_BASE_ADDR_A,      32'h0000_0400, "JOB_BASE_A");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_BASE_ADDR_B,      32'h0000_0800, "JOB_BASE_B");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_BASE_ADDR_C,      32'h0000_0C00, "JOB_BASE_C");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_DIM_M,            32'h0000_0002, "JOB_DIM_M");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_DIM_N,            32'h0000_0003, "JOB_DIM_N");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_DIM_K,            32'h0000_0004, "JOB_DIM_K");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_A_SRC_BASE,       32'h0000_1000, "JOB_A_SRC");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_A_DST_BASE,       32'h0000_0400, "JOB_A_DST");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_A_LOAD_BEATS,     32'h0000_0002, "JOB_A_BEATS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_B_SRC_BASE,       32'h0000_1100, "JOB_B_SRC");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_B_DST_BASE,       32'h0000_0800, "JOB_B_DST");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_B_LOAD_BEATS,     32'h0000_0003, "JOB_B_BEATS");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_STORE_SRC_BASE,   32'h0000_0C00, "JOB_STORE_SRC");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_STORE_DST_BASE,   32'h0000_2000, "JOB_STORE_DST");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_STORE_BYTE_COUNT, 32'h0000_0018, "JOB_STORE_BYTES");
    end
    endtask


    // ------------------------------------------------------------
    // P16 recipe control and descriptor-slot register checks
    // ------------------------------------------------------------
    task automatic check_recipe_rw_registers();
        logic [11:0] slot0;
        logic [11:0] slot1;
    begin
        slot0 = ai_accel_csr_access_helper::CSR_RECIPE_SLOT_BASE;
        slot1 = ai_accel_csr_access_helper::CSR_RECIPE_SLOT_BASE +
                ai_accel_csr_access_helper::CSR_RECIPE_SLOT_STRIDE;

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_CONTROL, 32'hFFFF_FFFF);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_CONTROL, 32'h0000_0FFF, "CSR_RECIPE_CONTROL mask");

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_CONTROL, 32'h0000_0702);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_CONTROL, 32'h0000_0702, "CSR_RECIPE_CONTROL count=2 start=0");

        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_CONTROL,          32'hFFFF_FFFF);
        csr.expect_read32(slot0 + ai_accel_csr_access_helper::SLOT_CONTROL,                32'h0000_007F, "SLOT0_CONTROL mask");

        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_CONTROL,          32'h0000_0003);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_BASE_ADDR_A,      32'h0000_0000);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_BASE_ADDR_B,      32'h0000_0100);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_BASE_ADDR_C,      32'h0000_0200);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_DIM_M,            32'h0000_0001);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_DIM_N,            32'h0000_0004);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_DIM_K,            32'h0000_0008);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_A_SRC_BASE,       32'h0000_1000);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_A_DST_BASE,       32'h0000_0000);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_A_LOAD_BEATS,     32'h0000_0001);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_B_SRC_BASE,       32'h0000_1100);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_B_DST_BASE,       32'h0000_0100);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_B_LOAD_BEATS,     32'h0000_0001);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_STORE_SRC_BASE,   32'h0000_0200);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_STORE_DST_BASE,   32'h0000_3000);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_STORE_BYTE_COUNT, 32'h0000_0000);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_USER_TAG,         32'h0000_A000);

        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_CONTROL,          32'h0000_002B);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_BASE_ADDR_A,      32'h0000_0000);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_BASE_ADDR_B,      32'h0000_0100);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_BASE_ADDR_C,      32'h0000_0200);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_DIM_M,            32'h0000_0001);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_DIM_N,            32'h0000_0004);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_DIM_K,            32'h0000_0008);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_A_SRC_BASE,       32'h0000_1200);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_A_DST_BASE,       32'h0000_0000);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_A_LOAD_BEATS,     32'h0000_0001);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_B_SRC_BASE,       32'h0000_1300);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_B_DST_BASE,       32'h0000_0100);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_B_LOAD_BEATS,     32'h0000_0001);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_STORE_SRC_BASE,   32'h0000_0200);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_STORE_DST_BASE,   32'h0000_3000);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_STORE_BYTE_COUNT, 32'h0000_0010);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_USER_TAG,         32'h0000_A001);

        csr.expect_read32(slot0 + ai_accel_csr_access_helper::SLOT_CONTROL,          32'h0000_0003, "SLOT0_CONTROL DMA/HOST");
        csr.expect_read32(slot0 + ai_accel_csr_access_helper::SLOT_DIM_K,            32'h0000_0008, "SLOT0_DIM_K");
        csr.expect_read32(slot0 + ai_accel_csr_access_helper::SLOT_A_SRC_BASE,       32'h0000_1000, "SLOT0_A_SRC");
        csr.expect_read32(slot0 + ai_accel_csr_access_helper::SLOT_B_SRC_BASE,       32'h0000_1100, "SLOT0_B_SRC");
        csr.expect_read32(slot0 + ai_accel_csr_access_helper::SLOT_STORE_BYTE_COUNT, 32'h0000_0000, "SLOT0_STORE_BYTES");
        csr.expect_read32(slot0 + ai_accel_csr_access_helper::SLOT_USER_TAG,         32'h0000_A000, "SLOT0_USER_TAG");

        csr.expect_read32(slot1 + ai_accel_csr_access_helper::SLOT_CONTROL,          32'h0000_002B, "SLOT1_CONTROL DMA/STORE/ACCUM");
        csr.expect_read32(slot1 + ai_accel_csr_access_helper::SLOT_A_SRC_BASE,       32'h0000_1200, "SLOT1_A_SRC");
        csr.expect_read32(slot1 + ai_accel_csr_access_helper::SLOT_B_SRC_BASE,       32'h0000_1300, "SLOT1_B_SRC");
        csr.expect_read32(slot1 + ai_accel_csr_access_helper::SLOT_STORE_BYTE_COUNT, 32'h0000_0010, "SLOT1_STORE_BYTES");
        csr.expect_read32(slot1 + ai_accel_csr_access_helper::SLOT_USER_TAG,         32'h0000_A001, "SLOT1_USER_TAG");
    end
    endtask

    // ------------------------------------------------------------
    // Invalid address response checks
    // ------------------------------------------------------------
    task automatic check_invalid_address_responses();
        logic [31:0] data;
        logic [1:0]  resp;
    begin
        csr.read32(12'h5FC, data, resp);
        if ((resp != AXI_RESP_SLVERR) || (data != 32'h0000_0000)) begin
            `uvm_fatal("CSR_SMOKE/BAD_INVALID_READ",
                $sformatf("Invalid read expected SLVERR/0, got resp=%0b data=0x%08h", resp, data))
        end

        csr.write32(12'h5FC, 32'hCAFE_BABE, 4'hF, resp);
        if (resp != AXI_RESP_SLVERR) begin
            `uvm_fatal("CSR_SMOKE/BAD_INVALID_WRITE",
                $sformatf("Invalid write expected SLVERR, got resp=%0b", resp))
        end
    end
    endtask

    // ------------------------------------------------------------
    // Sticky status / W1C clear checks
    // ------------------------------------------------------------
    task automatic check_sticky_status_and_perf();
    begin
        status_vif.pulse_acc_done(32'd17, 32'd64, 32'd4);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DONE_STATUS,       32'h0000_0001, "GEMM done sticky");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_PERF_BUSY_CYCLES,  32'd17,        "PERF_BUSY");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_PERF_MAC_COUNT,    32'd64,        "PERF_MAC");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_PERF_OUTPUT_COUNT, 32'd4,         "PERF_OUT");

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DONE_STATUS, 32'h0000_0001);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_DONE_STATUS, 32'h0000_0000, "clear GEMM done");

        status_vif.pulse_dma_load_done(1'b1);
        status_vif.pulse_axis_load_done(1'b1);
        status_vif.pulse_ds_load_done(1'b1);
        status_vif.pulse_dma_store_done(1'b1);

        csr.expect_read32(ai_accel_csr_access_helper::CSR_DONE_STATUS,  32'h0000_001E, "frontend done sticky");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_ERROR_STATUS, 32'h0000_000F, "frontend error sticky");

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DONE_STATUS,  32'h0000_001E);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, 32'h0000_000F);

        csr.expect_read32(ai_accel_csr_access_helper::CSR_DONE_STATUS,  32'h0000_0000, "clear frontend done");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_ERROR_STATUS, 32'h0000_0000, "clear frontend error");

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::CMD_CLEAR_PERF);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_PERF_BUSY_CYCLES,  32'h0000_0000, "clear PERF_BUSY");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_PERF_MAC_COUNT,    32'h0000_0000, "clear PERF_MAC");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_PERF_OUTPUT_COUNT, 32'h0000_0000, "clear PERF_OUT");
    end
    endtask

    // ------------------------------------------------------------
    // Command reject checks
    // ------------------------------------------------------------
    task automatic check_command_rejects();
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_DMA_LOAD_BEATS, 32'h0000_0000);
        csr.issue_command(32'h1 << ai_accel_csr_access_helper::CMD_START_DMA_LOAD);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS,
            32'h0000_0200,
            "zero-length DMA load reject");

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::CMD_CLEAR_ERROR);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS,
            32'h0000_0000,
            "clear reject status");

        csr.issue_command((32'h1 << ai_accel_csr_access_helper::CMD_START_GEMM) |
                          (32'h1 << ai_accel_csr_access_helper::CMD_START_DMA_LOAD));
        csr.expect_read32(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS,
            32'h0000_0100,
            "multi-start unsupported reject");

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::CMD_CLEAR_ERROR);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS,
            32'h0000_0000,
            "clear unsupported reject");
    end
    endtask

    // ------------------------------------------------------------
    // P15 job sticky status / performance snapshot checks
    // ------------------------------------------------------------
    task automatic check_job_sticky_status_and_perf();
    begin
        status_vif.pulse_job_gemm_done(32'd23, 32'd96, 32'd6);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_DONE_STATUS,      32'h0000_0002, "JOB_GEMM_DONE sticky");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_PERF_BUSY_CYCLES, 32'd23,        "JOB_PERF_BUSY");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_PERF_MAC_COUNT,   32'd96,        "JOB_PERF_MAC");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_PERF_OUTPUT_COUNT,32'd6,         "JOB_PERF_OUT");

        status_vif.pulse_job_done(1'b1);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_DONE_STATUS, 32'h0000_0007, "JOB done/store sticky");

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_DONE_STATUS, 32'h0000_0007);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_DONE_STATUS, 32'h0000_0000, "clear job done bits");

        status_vif.pulse_job_errors(1'b1, 1'b1, 1'b1, 1'b1, 1'b1);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_ERROR_STATUS, 32'h0000_010F, "JOB error sticky");

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_ERROR_STATUS, 32'h0000_010F);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_ERROR_STATUS, 32'h0000_0000, "clear job error bits");

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::JOB_CMD_CLEAR_PERF,
                          ai_accel_csr_access_helper::CSR_JOB_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_PERF_BUSY_CYCLES,  32'h0000_0000, "clear JOB_PERF_BUSY");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_PERF_MAC_COUNT,    32'h0000_0000, "clear JOB_PERF_MAC");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_PERF_OUTPUT_COUNT, 32'h0000_0000, "clear JOB_PERF_OUT");
    end
    endtask

    // ------------------------------------------------------------
    // P15 job command reject checks
    // ------------------------------------------------------------
    task automatic check_job_command_rejects();
    begin
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_MODE, 32'h0000_0004);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_STORE_BYTE_COUNT, 32'h0000_0000);
        csr.issue_command(32'h1 << ai_accel_csr_access_helper::JOB_CMD_START,
                          ai_accel_csr_access_helper::CSR_JOB_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS,
            32'h0000_0040,
            "zero store length job reject");

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::JOB_CMD_CLEAR_ERROR,
                          ai_accel_csr_access_helper::CSR_JOB_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS,
            32'h0000_0000,
            "clear job reject status");

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_MODE, 32'h0000_0008);
        csr.issue_command(32'h1 << ai_accel_csr_access_helper::JOB_CMD_START,
                          ai_accel_csr_access_helper::CSR_JOB_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS,
            32'h0000_0004,
            "unsupported job output mode reject");

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::JOB_CMD_CLEAR_ERROR,
                          ai_accel_csr_access_helper::CSR_JOB_COMMAND);

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_MODE, 32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_DIM_M, 32'h0000_0000);
        csr.issue_command(32'h1 << ai_accel_csr_access_helper::JOB_CMD_START,
                          ai_accel_csr_access_helper::CSR_JOB_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS,
            32'h0000_0008,
            "zero dimension job reject");

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::JOB_CMD_CLEAR_ERROR,
                          ai_accel_csr_access_helper::CSR_JOB_COMMAND);

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_JOB_DIM_M, 32'h0000_0002);
        @(posedge status_vif.clk);
        status_vif.acc_busy <= 1'b1;
        csr.issue_command(32'h1 << ai_accel_csr_access_helper::JOB_CMD_START,
                          ai_accel_csr_access_helper::CSR_JOB_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS,
            32'h0000_0002,
            "micro-op busy job reject");
        @(posedge status_vif.clk);
        status_vif.acc_busy <= 1'b0;

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::JOB_CMD_CLEAR_ERROR,
                          ai_accel_csr_access_helper::CSR_JOB_COMMAND);

        @(posedge status_vif.clk);
        status_vif.job_busy <= 1'b1;
        csr.issue_command(32'h1 << ai_accel_csr_access_helper::JOB_CMD_START,
                          ai_accel_csr_access_helper::CSR_JOB_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS,
            32'h0000_0001,
            "job busy reject");

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::CMD_START_GEMM);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS,
            32'h0000_0081,
            "manual P14 command during job reject");
        @(posedge status_vif.clk);
        status_vif.job_busy <= 1'b0;

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::JOB_CMD_CLEAR_ERROR,
                          ai_accel_csr_access_helper::CSR_JOB_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_REJECT_STATUS,
            32'h0000_0000,
            "clear job busy/manual reject");
    end
    endtask


    // ------------------------------------------------------------
    // P16 recipe sticky status / W1C clear checks
    // ------------------------------------------------------------
    task automatic check_recipe_sticky_status_and_perf();
    begin
        status_vif.pulse_recipe_done(32'h0000_0003, 32'd99, 32'd128, 32'd8);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_DONE_STATUS, 32'h0000_0007, "recipe done sticky");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_DONE_MASK, 32'h0000_0003, "slot done mask");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_PERF_BUSY_CYCLES, 32'd99, "recipe PERF_BUSY");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_PERF_MAC_COUNT, 32'd128, "recipe PERF_MAC");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_PERF_OUTPUT_COUNT, 32'd8, "recipe PERF_OUT");

        status_vif.pulse_recipe_error(32'h0000_0002, 32'h0000_0000);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_ERROR_STATUS, 32'h0000_0001, "recipe job error sticky");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_ERROR_MASK, 32'h0000_0002, "slot error mask");

        status_vif.pulse_recipe_reject(32'h0000_0004);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_ERROR_STATUS, 32'h0000_0003, "recipe job reject sticky");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_REJECT_MASK, 32'h0000_0004, "slot reject mask");

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_DONE_STATUS, 32'h0000_0007);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_ERROR_STATUS, 32'h0000_0003);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_DONE_MASK, 32'h0000_0003);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_ERROR_MASK, 32'h0000_0002);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_REJECT_MASK, 32'h0000_0004);

        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_DONE_STATUS, 32'h0000_0000, "clear recipe done");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_ERROR_STATUS, 32'h0000_0000, "clear recipe error");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_DONE_MASK, 32'h0000_0000, "clear slot done");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_ERROR_MASK, 32'h0000_0000, "clear slot error");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_SLOT_REJECT_MASK, 32'h0000_0000, "clear slot reject");

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::RECIPE_CMD_CLEAR_PERF,
            ai_accel_csr_access_helper::CSR_RECIPE_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_PERF_BUSY_CYCLES,  32'h0000_0000, "clear recipe PERF_BUSY");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_PERF_MAC_COUNT,    32'h0000_0000, "clear recipe PERF_MAC");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_PERF_OUTPUT_COUNT, 32'h0000_0000, "clear recipe PERF_OUT");
    end
    endtask

    // ------------------------------------------------------------
    // P16 recipe command reject checks
    // ------------------------------------------------------------
    task automatic check_recipe_command_rejects();
        logic [11:0] slot0;
        logic [11:0] slot1;
    begin
        slot0 = ai_accel_csr_access_helper::CSR_RECIPE_SLOT_BASE;
        slot1 = ai_accel_csr_access_helper::CSR_RECIPE_SLOT_BASE +
                ai_accel_csr_access_helper::CSR_RECIPE_SLOT_STRIDE;

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_CONTROL, 32'h0000_0700);
        csr.issue_command(32'h1 << ai_accel_csr_access_helper::RECIPE_CMD_START,
            ai_accel_csr_access_helper::CSR_RECIPE_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS,
            32'h0000_0008,
            "zero-count recipe reject");

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::RECIPE_CMD_CLEAR_ERROR,
            ai_accel_csr_access_helper::CSR_RECIPE_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS,
            32'h0000_0000,
            "clear recipe reject status");

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_CONTROL, 32'h0000_0705);
        csr.issue_command(32'h1 << ai_accel_csr_access_helper::RECIPE_CMD_START,
            ai_accel_csr_access_helper::CSR_RECIPE_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS,
            32'h0000_0010,
            "slot range recipe reject");

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::RECIPE_CMD_CLEAR_ERROR,
            ai_accel_csr_access_helper::CSR_RECIPE_COMMAND);

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_RECIPE_CONTROL, 32'h0000_0702);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_CONTROL, 32'h0000_0000);
        csr.write32_expect_okay(slot1 + ai_accel_csr_access_helper::SLOT_CONTROL, 32'h0000_002B);
        csr.issue_command(32'h1 << ai_accel_csr_access_helper::RECIPE_CMD_START,
            ai_accel_csr_access_helper::CSR_RECIPE_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS,
            32'h0000_0020,
            "invalid slot recipe reject");

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::RECIPE_CMD_CLEAR_ERROR,
            ai_accel_csr_access_helper::CSR_RECIPE_COMMAND);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_CONTROL, 32'h0000_0003);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_DIM_K,   32'h0000_0000);
        csr.issue_command(32'h1 << ai_accel_csr_access_helper::RECIPE_CMD_START,
            ai_accel_csr_access_helper::CSR_RECIPE_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS,
            32'h0000_0040,
            "descriptor recipe reject");

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::RECIPE_CMD_CLEAR_ERROR,
            ai_accel_csr_access_helper::CSR_RECIPE_COMMAND);
        csr.write32_expect_okay(slot0 + ai_accel_csr_access_helper::SLOT_DIM_K, 32'h0000_0008);

        @(posedge status_vif.clk);
        status_vif.recipe_busy <= 1'b1;
        csr.issue_command(32'h1 << ai_accel_csr_access_helper::RECIPE_CMD_START,
            ai_accel_csr_access_helper::CSR_RECIPE_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS,
            32'h0000_0001,
            "recipe busy reject");
        status_vif.recipe_busy <= 1'b0;

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::RECIPE_CMD_CLEAR_ERROR,
            ai_accel_csr_access_helper::CSR_RECIPE_COMMAND);

        @(posedge status_vif.clk);
        status_vif.recipe_busy <= 1'b1;
        csr.issue_command(32'h1 << ai_accel_csr_access_helper::CMD_START_GEMM);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS,
            32'h0000_0080,
            "P14 manual command during recipe reject");
        csr.issue_command(32'h1 << ai_accel_csr_access_helper::JOB_CMD_START,
            ai_accel_csr_access_helper::CSR_JOB_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS,
            32'h0000_0080,
            "P15 START_JOB during recipe reject sticky");
        status_vif.recipe_busy <= 1'b0;

        csr.issue_command(32'h1 << ai_accel_csr_access_helper::RECIPE_CMD_CLEAR_ERROR,
            ai_accel_csr_access_helper::CSR_RECIPE_COMMAND);
        csr.expect_read32(ai_accel_csr_access_helper::CSR_RECIPE_REJECT_STATUS,
            32'h0000_0000,
            "clear manual during recipe reject");
    end
    endtask

    // ------------------------------------------------------------
    // Live status readback checks
    // ------------------------------------------------------------
    task automatic check_live_status_bits();
    begin
        @(posedge status_vif.clk);
        status_vif.acc_busy       <= 1'b1;
        status_vif.dma_load_busy  <= 1'b1;
        status_vif.axis_load_busy <= 1'b1;
        status_vif.ds_load_busy   <= 1'b1;
        status_vif.dma_store_busy <= 1'b1;

        csr.expect_read32(ai_accel_csr_access_helper::CSR_STATUS, 32'h0001_011F, "all busy status bits");

        @(posedge status_vif.clk);
        status_vif.acc_busy       <= 1'b0;
        status_vif.dma_load_busy  <= 1'b0;
        status_vif.axis_load_busy <= 1'b0;
        status_vif.ds_load_busy   <= 1'b0;
        status_vif.dma_store_busy <= 1'b0;

        csr.expect_read32(ai_accel_csr_access_helper::CSR_STATUS, 32'h0001_0000, "idle status bits");

        @(posedge status_vif.clk);
        status_vif.job_busy <= 1'b1;
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_STATUS, 32'h0001_0001, "job busy status bit");

        @(posedge status_vif.clk);
        status_vif.job_busy <= 1'b0;
        status_vif.acc_busy <= 1'b1;
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_STATUS, 32'h0001_0100, "job micro-op busy status bit");

        @(posedge status_vif.clk);
        status_vif.acc_busy <= 1'b0;
        status_vif.job_state <= 32'h0000_0008;
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_STATE, 32'h0000_0008, "job state readback");
        csr.expect_read32(ai_accel_csr_access_helper::CSR_JOB_STATUS, 32'h0001_0008, "job idle accept-ready status");
    end
    endtask

    // ------------------------------------------------------------
    // Run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        status_vif.init_status_inputs();
        csr.init_bus();
        csr.wait_reset_release();

        check_reset_defaults();
        check_rw_registers();
        check_job_rw_registers();
        check_recipe_rw_registers();
        check_invalid_address_responses();
        check_sticky_status_and_perf();
        check_command_rejects();
        check_job_sticky_status_and_perf();
        check_job_command_rejects();
        check_recipe_sticky_status_and_perf();
        check_recipe_command_rejects();
        check_live_status_bits();

        `uvm_info("CSR_SMOKE",
            "Standalone CSR register access smoke completed",
            UVM_LOW)

        phase.drop_objection(this);
    endtask

endclass

`endif
