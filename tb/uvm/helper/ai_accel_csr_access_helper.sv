// File: tb/uvm/helper/ai_accel_csr_access_helper.sv

`ifndef AI_ACCEL_CSR_ACCESS_HELPER_SV
`define AI_ACCEL_CSR_ACCESS_HELPER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class ai_accel_csr_access_helper extends uvm_object;
    `uvm_object_utils(ai_accel_csr_access_helper)

    typedef virtual axi_lite_if #(
        .ADDR_WIDTH (12),
        .DATA_WIDTH (32)
    ) csr_vif_t;

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    // ------------------------------------------------------------
    // CSR address map
    // ------------------------------------------------------------
    localparam logic [11:0] CSR_VERSION              = 12'h000;
    localparam logic [11:0] CSR_COMMAND              = 12'h004;
    localparam logic [11:0] CSR_STATUS               = 12'h008;
    localparam logic [11:0] CSR_DONE_STATUS          = 12'h00C;
    localparam logic [11:0] CSR_ERROR_STATUS         = 12'h010;
    localparam logic [11:0] CSR_MODE                 = 12'h014;
    localparam logic [11:0] CSR_CMD_REJECT_STATUS    = 12'h018;

    localparam logic [11:0] CSR_BASE_ADDR_A          = 12'h020;
    localparam logic [11:0] CSR_BASE_ADDR_B          = 12'h024;
    localparam logic [11:0] CSR_BASE_ADDR_C          = 12'h028;
    localparam logic [11:0] CSR_DIM_M                = 12'h02C;
    localparam logic [11:0] CSR_DIM_N                = 12'h030;
    localparam logic [11:0] CSR_DIM_K                = 12'h034;

    localparam logic [11:0] CSR_DMA_LOAD_SRC_BASE    = 12'h040;
    localparam logic [11:0] CSR_DMA_LOAD_DST_BASE    = 12'h044;
    localparam logic [11:0] CSR_DMA_LOAD_BEATS       = 12'h048;

    localparam logic [11:0] CSR_AXIS_SRC_BASE        = 12'h050;
    localparam logic [11:0] CSR_AXIS_DST_BASE        = 12'h054;
    localparam logic [11:0] CSR_AXIS_LOAD_BEATS      = 12'h058;

    localparam logic [11:0] CSR_DS_SRC_BASE          = 12'h060;
    localparam logic [11:0] CSR_DS_DST_BASE          = 12'h064;
    localparam logic [11:0] CSR_DS_LOAD_BEATS        = 12'h068;
    localparam logic [11:0] CSR_DS_CONTROL           = 12'h06C;

    localparam logic [11:0] CSR_DMA_STORE_SRC_BASE   = 12'h070;
    localparam logic [11:0] CSR_DMA_STORE_DST_BASE   = 12'h074;
    localparam logic [11:0] CSR_DMA_STORE_BYTE_COUNT = 12'h078;

    localparam logic [11:0] CSR_PERF_BUSY_CYCLES     = 12'h080;
    localparam logic [11:0] CSR_PERF_MAC_COUNT       = 12'h084;
    localparam logic [11:0] CSR_PERF_OUTPUT_COUNT    = 12'h088;

    localparam logic [11:0] CSR_JOB_VERSION          = 12'h100;
    localparam logic [11:0] CSR_JOB_COMMAND          = 12'h104;
    localparam logic [11:0] CSR_JOB_STATUS           = 12'h108;
    localparam logic [11:0] CSR_JOB_DONE_STATUS      = 12'h10C;
    localparam logic [11:0] CSR_JOB_ERROR_STATUS     = 12'h110;
    localparam logic [11:0] CSR_JOB_MODE             = 12'h114;
    localparam logic [11:0] CSR_JOB_REJECT_STATUS    = 12'h118;
    localparam logic [11:0] CSR_JOB_STATE            = 12'h11C;

    localparam logic [11:0] CSR_JOB_BASE_ADDR_A      = 12'h120;
    localparam logic [11:0] CSR_JOB_BASE_ADDR_B      = 12'h124;
    localparam logic [11:0] CSR_JOB_BASE_ADDR_C      = 12'h128;
    localparam logic [11:0] CSR_JOB_DIM_M            = 12'h12C;
    localparam logic [11:0] CSR_JOB_DIM_N            = 12'h130;
    localparam logic [11:0] CSR_JOB_DIM_K            = 12'h134;

    localparam logic [11:0] CSR_JOB_A_SRC_BASE       = 12'h138;
    localparam logic [11:0] CSR_JOB_A_DST_BASE       = 12'h13C;
    localparam logic [11:0] CSR_JOB_A_LOAD_BEATS     = 12'h140;

    localparam logic [11:0] CSR_JOB_B_SRC_BASE       = 12'h148;
    localparam logic [11:0] CSR_JOB_B_DST_BASE       = 12'h14C;
    localparam logic [11:0] CSR_JOB_B_LOAD_BEATS     = 12'h150;

    localparam logic [11:0] CSR_JOB_STORE_SRC_BASE   = 12'h158;
    localparam logic [11:0] CSR_JOB_STORE_DST_BASE   = 12'h15C;
    localparam logic [11:0] CSR_JOB_STORE_BYTE_COUNT = 12'h160;

    localparam logic [11:0] CSR_JOB_PERF_BUSY_CYCLES = 12'h180;
    localparam logic [11:0] CSR_JOB_PERF_MAC_COUNT   = 12'h184;
    localparam logic [11:0] CSR_JOB_PERF_OUTPUT_COUNT= 12'h188;

    // ------------------------------------------------------------
    // Command bits
    // ------------------------------------------------------------
    localparam int CMD_START_GEMM      = 0;
    localparam int CMD_START_DMA_LOAD  = 1;
    localparam int CMD_START_AXIS_LOAD = 2;
    localparam int CMD_START_DS_LOAD   = 3;
    localparam int CMD_START_DMA_STORE = 4;
    localparam int CMD_CLEAR_DONE      = 8;
    localparam int CMD_CLEAR_ERROR     = 9;
    localparam int CMD_CLEAR_PERF      = 10;

    localparam int JOB_CMD_START       = 0;
    localparam int JOB_CMD_CLEAR_DONE  = 8;
    localparam int JOB_CMD_CLEAR_ERROR = 9;
    localparam int JOB_CMD_CLEAR_PERF  = 10;

    // ------------------------------------------------------------
    // Sticky status bits
    // ------------------------------------------------------------
    localparam int DONE_GEMM      = 0;
    localparam int DONE_DMA_LOAD  = 1;
    localparam int DONE_AXIS_LOAD = 2;
    localparam int DONE_DS_LOAD   = 3;
    localparam int DONE_DMA_STORE = 4;

    localparam int ERR_DMA_LOAD   = 0;
    localparam int ERR_AXIS_LOAD  = 1;
    localparam int ERR_DS_LOAD    = 2;
    localparam int ERR_DMA_STORE  = 3;

    localparam int REJ_UNSUPPORTED = 8;
    localparam int REJ_ZERO_LENGTH = 9;

    localparam int JOB_DONE       = 0;
    localparam int JOB_GEMM_DONE  = 1;
    localparam int JOB_STORE_DONE = 2;

    localparam int JOB_ERR_DMA_LOAD  = 0;
    localparam int JOB_ERR_AXIS_LOAD = 1;
    localparam int JOB_ERR_DS_LOAD   = 2;
    localparam int JOB_ERR_DMA_STORE = 3;
    localparam int JOB_ERR_SEQUENCE  = 8;

    localparam int JOB_REJ_BUSY           = 0;
    localparam int JOB_REJ_MICRO_OP_BUSY  = 1;
    localparam int JOB_REJ_UNSUPPORTED    = 2;
    localparam int JOB_REJ_ZERO_DIM       = 3;
    localparam int JOB_REJ_ZERO_A_LENGTH  = 4;
    localparam int JOB_REJ_ZERO_B_LENGTH  = 5;
    localparam int JOB_REJ_ZERO_STORE_LEN = 6;
    localparam int JOB_REJ_MANUAL_CMD     = 7;
    localparam int JOB_REJ_UNSUPPORTED_COMBO = 8;

    localparam int unsigned DEFAULT_TIMEOUT_CYCLES = 2000;

    csr_vif_t vif;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_csr_access_helper");
        super.new(name);
    endfunction

    // ------------------------------------------------------------
    // Virtual interface binding
    // ------------------------------------------------------------
    function void set_vif(csr_vif_t csr_vif);
        vif = csr_vif;
    endfunction

    function void check_vif();
        if (vif == null) begin
            `uvm_fatal("CSR_HELPER/NOVIF",
                "CSR AXI-Lite virtual interface is not bound")
        end
    endfunction

    // ------------------------------------------------------------
    // Bus initialization
    // ------------------------------------------------------------
    task automatic init_bus();
    begin
        check_vif();

        vif.awaddr  <= '0;
        vif.awprot  <= '0;
        vif.awvalid <= 1'b0;

        vif.wdata   <= '0;
        vif.wstrb   <= '0;
        vif.wvalid  <= 1'b0;

        vif.bready  <= 1'b0;

        vif.araddr  <= '0;
        vif.arprot  <= '0;
        vif.arvalid <= 1'b0;

        vif.rready  <= 1'b0;
    end
    endtask

    // ------------------------------------------------------------
    // Reset wait
    // ------------------------------------------------------------
    task automatic wait_reset_release();
    begin
        check_vif();

        @(posedge vif.clk);
        while (vif.rst_n !== 1'b1) begin
            @(posedge vif.clk);
        end
    end
    endtask

    // ------------------------------------------------------------
    // AXI-Lite write
    // ------------------------------------------------------------
    task automatic write32(
        input  logic [11:0] addr,
        input  logic [31:0] data,
        input  logic [3:0]  strb = 4'hF,
        output logic [1:0]  resp
    );
        bit aw_done;
        bit w_done;
        bit b_done;
        int unsigned cnt;
    begin
        wait_reset_release();

        aw_done = 1'b0;
        w_done  = 1'b0;
        b_done  = 1'b0;
        cnt     = 0;
        resp    = AXI_RESP_OKAY;

        @(posedge vif.clk);
        vif.awaddr  <= addr;
        vif.awprot  <= 3'b000;
        vif.awvalid <= 1'b1;

        vif.wdata   <= data;
        vif.wstrb   <= strb;
        vif.wvalid  <= 1'b1;

        vif.bready  <= 1'b1;

        while (!b_done) begin
            @(posedge vif.clk);

            if (!aw_done && vif.awvalid && vif.awready) begin
                aw_done     = 1'b1;
                vif.awvalid <= 1'b0;
            end

            if (!w_done && vif.wvalid && vif.wready) begin
                w_done     = 1'b1;
                vif.wvalid <= 1'b0;
            end

            if (vif.bvalid && vif.bready) begin
                resp       = vif.bresp;
                b_done     = 1'b1;
                vif.bready <= 1'b0;
            end

            cnt++;
            if (cnt > DEFAULT_TIMEOUT_CYCLES) begin
                `uvm_fatal("CSR_HELPER/WRITE_TIMEOUT",
                    $sformatf("AXI-Lite write timeout: addr=0x%03h data=0x%08h", addr, data))
            end
        end

        @(posedge vif.clk);
        vif.awaddr  <= '0;
        vif.awprot  <= '0;
        vif.wdata   <= '0;
        vif.wstrb   <= '0;
    end
    endtask

    // ------------------------------------------------------------
    // AXI-Lite read
    // ------------------------------------------------------------
    task automatic read32(
        input  logic [11:0] addr,
        output logic [31:0] data,
        output logic [1:0]  resp
    );
        bit ar_done;
        bit r_done;
        int unsigned cnt;
    begin
        wait_reset_release();

        ar_done = 1'b0;
        r_done  = 1'b0;
        cnt     = 0;
        data    = '0;
        resp    = AXI_RESP_OKAY;

        @(posedge vif.clk);
        vif.araddr  <= addr;
        vif.arprot  <= 3'b000;
        vif.arvalid <= 1'b1;
        vif.rready  <= 1'b1;

        while (!r_done) begin
            @(posedge vif.clk);

            if (!ar_done && vif.arvalid && vif.arready) begin
                ar_done     = 1'b1;
                vif.arvalid <= 1'b0;
            end

            if (vif.rvalid && vif.rready) begin
                data       = vif.rdata;
                resp       = vif.rresp;
                r_done     = 1'b1;
                vif.rready <= 1'b0;
            end

            cnt++;
            if (cnt > DEFAULT_TIMEOUT_CYCLES) begin
                `uvm_fatal("CSR_HELPER/READ_TIMEOUT",
                    $sformatf("AXI-Lite read timeout: addr=0x%03h", addr))
            end
        end

        @(posedge vif.clk);
        vif.araddr  <= '0;
        vif.arprot  <= '0;
    end
    endtask

    // ------------------------------------------------------------
    // Convenience checks
    // ------------------------------------------------------------
    task automatic write32_expect_okay(
        input logic [11:0] addr,
        input logic [31:0] data,
        input logic [3:0]  strb = 4'hF
    );
        logic [1:0] resp;
    begin
        write32(addr, data, strb, resp);
        if (resp != AXI_RESP_OKAY) begin
            `uvm_fatal("CSR_HELPER/WRITE_RESP",
                $sformatf("Expected OKAY write response at addr=0x%03h, got resp=%0b", addr, resp))
        end
    end
    endtask

    task automatic read32_expect_okay(
        input  logic [11:0] addr,
        output logic [31:0] data
    );
        logic [1:0] resp;
    begin
        read32(addr, data, resp);
        if (resp != AXI_RESP_OKAY) begin
            `uvm_fatal("CSR_HELPER/READ_RESP",
                $sformatf("Expected OKAY read response at addr=0x%03h, got resp=%0b", addr, resp))
        end
    end
    endtask

    task automatic expect_read32(
        input logic [11:0] addr,
        input logic [31:0] expected,
        input string       tag = ""
    );
        logic [31:0] data;
    begin
        read32_expect_okay(addr, data);
        if (data !== expected) begin
            `uvm_fatal("CSR_HELPER/RD_MISMATCH",
                $sformatf("%s addr=0x%03h expected=0x%08h actual=0x%08h",
                    tag, addr, expected, data))
        end
    end
    endtask

    task automatic issue_command(
        input logic [31:0] command_bits,
        input logic [11:0] command_addr = CSR_COMMAND
    );
    begin
        write32_expect_okay(command_addr, command_bits, 4'hF);
    end
    endtask

endclass

`endif
