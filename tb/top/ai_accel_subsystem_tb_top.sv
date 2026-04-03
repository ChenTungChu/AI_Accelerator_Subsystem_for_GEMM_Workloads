// File: tb/top/ai_accel_subsystem_tb_top.sv

`timescale 1ns/1ps

module ai_accel_subsystem_tb_top;

    // ============================================================
    // Parameters
    // ============================================================
    localparam int ADDR_WIDTH      = 32;
    localparam int DATA_WIDTH      = 64;
    localparam int ID_WIDTH        = 4;
    localparam int DEPTH_WORDS     = 1024;

    localparam int GEMM_A_WIDTH    = 8;
    localparam int GEMM_B_WIDTH    = 8;
    localparam int GEMM_ACC_WIDTH  = 32;
    localparam int GEMM_DIM_WIDTH  = 8;

    localparam int M_DIM           = 4;
    localparam int N_DIM           = 4;
    localparam int K_DIM           = 4;

    localparam int BYTE_PER_WORD   = DATA_WIDTH / 8;
    localparam int WORD_LSB_W      = (BYTE_PER_WORD > 1) ? $clog2(BYTE_PER_WORD) : 1;

    localparam logic [ADDR_WIDTH-1:0] BASE_A = 32'h0000;
    localparam logic [ADDR_WIDTH-1:0] BASE_B = 32'h0100;
    localparam logic [ADDR_WIDTH-1:0] BASE_C = 32'h0200;

    int CASE_ID;

    // ============================================================
    // Clocks / resets
    // ============================================================
    logic dma_clk;
    logic dma_rst_n;
    logic core_clk;
    logic core_rst_n;

    // ============================================================
    // Control
    // ============================================================
    logic                      acc_start;
    logic                      acc_busy;
    logic                      acc_done;

    logic [ADDR_WIDTH-1:0]     base_addr_a;
    logic [ADDR_WIDTH-1:0]     base_addr_b;
    logic [ADDR_WIDTH-1:0]     base_addr_c;

    logic [GEMM_DIM_WIDTH-1:0] dim_m;
    logic [GEMM_DIM_WIDTH-1:0] dim_n;
    logic [GEMM_DIM_WIDTH-1:0] dim_k;

    // ============================================================
    // External AXI-MM host interface (Port0)
    // ============================================================
    axi_mm_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .HAS_BURST  (1)
    ) axi0_if (
        .clk   (dma_clk),
        .rst_n (dma_rst_n)
    );

    // ============================================================
    // DUT
    // ============================================================
    ai_accel_subsystem #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .DATA_WIDTH      (DATA_WIDTH),
        .ID_WIDTH        (ID_WIDTH),
        .DEPTH_WORDS     (DEPTH_WORDS),
        .GEMM_A_WIDTH    (GEMM_A_WIDTH),
        .GEMM_B_WIDTH    (GEMM_B_WIDTH),
        .GEMM_ACC_WIDTH  (GEMM_ACC_WIDTH),
        .GEMM_DIM_WIDTH  (GEMM_DIM_WIDTH)
    ) dut (
        .dma_clk     (dma_clk),
        .dma_rst_n   (dma_rst_n),
        .core_clk    (core_clk),
        .core_rst_n  (core_rst_n),

        .axi0_if     (axi0_if),

        .acc_start   (acc_start),
        .acc_busy    (acc_busy),
        .acc_done    (acc_done),

        .base_addr_a (base_addr_a),
        .base_addr_b (base_addr_b),
        .base_addr_c (base_addr_c),

        .dim_m       (dim_m),
        .dim_n       (dim_n),
        .dim_k       (dim_k)
    );

    // BRAM observation interface ready
    initial begin
        force dut.apply_if.ready  = 1'b1;
        force dut.commit_if.ready = 1'b1;
    end

    // ============================================================
    // Clock generation
    // ============================================================
    initial begin
        dma_clk = 1'b0;
        forever #5 dma_clk = ~dma_clk;
    end

    initial begin
        core_clk = 1'b0;
        forever #7 core_clk = ~core_clk;
    end

    // ============================================================
    // Reset / default signal init
    // ============================================================
    initial begin
        dma_rst_n   = 1'b0;
        core_rst_n  = 1'b0;

        acc_start   = 1'b0;

        base_addr_a = BASE_A;
        base_addr_b = BASE_B;
        base_addr_c = BASE_C;

        dim_m       = M_DIM;
        dim_n       = N_DIM;
        dim_k       = K_DIM;

        axi0_if.awid    = '0;
        axi0_if.awaddr  = '0;
        axi0_if.awlen   = '0;
        axi0_if.awsize  = '0;
        axi0_if.awburst = '0;
        axi0_if.awvalid = 1'b0;

        axi0_if.wdata   = '0;
        axi0_if.wstrb   = '0;
        axi0_if.wlast   = 1'b0;
        axi0_if.wvalid  = 1'b0;

        axi0_if.bready  = 1'b0;

        axi0_if.arid    = '0;
        axi0_if.araddr  = '0;
        axi0_if.arlen   = '0;
        axi0_if.arsize  = '0;
        axi0_if.arburst = '0;
        axi0_if.arvalid = 1'b0;

        axi0_if.rready  = 1'b0;

        repeat (5) @(posedge dma_clk);
        dma_rst_n = 1'b1;

        repeat (5) @(posedge core_clk);
        core_rst_n = 1'b1;
    end

    // ============================================================
    // AXI host helper tasks
    // ============================================================
    task automatic host_axi_write_word(
        input logic [ADDR_WIDTH-1:0]      addr,
        input logic [DATA_WIDTH-1:0]      data,
        input logic [BYTE_PER_WORD-1:0]   strb
    );
    begin
        @(posedge dma_clk);
        axi0_if.awid    <= '0;
        axi0_if.awaddr  <= addr;
        axi0_if.awlen   <= 8'd0;
        axi0_if.awsize  <= WORD_LSB_W[2:0];
        axi0_if.awburst <= 2'b01;
        axi0_if.awvalid <= 1'b1;

        do @(posedge dma_clk); while (!axi0_if.awready);
        axi0_if.awvalid <= 1'b0;

        axi0_if.wdata   <= data;
        axi0_if.wstrb   <= strb;
        axi0_if.wlast   <= 1'b1;
        axi0_if.wvalid  <= 1'b1;

        do @(posedge dma_clk); while (!axi0_if.wready);
        axi0_if.wvalid  <= 1'b0;
        axi0_if.wlast   <= 1'b0;
        axi0_if.wdata   <= '0;
        axi0_if.wstrb   <= '0;

        axi0_if.bready  <= 1'b1;
        do @(posedge dma_clk); while (!axi0_if.bvalid);
        @(posedge dma_clk);
        axi0_if.bready  <= 1'b0;
    end
    endtask

    task automatic host_axi_read_word(
        input  logic [ADDR_WIDTH-1:0]     addr,
        output logic [DATA_WIDTH-1:0]     data
    );
    begin
        @(posedge dma_clk);
        axi0_if.arid    <= '0;
        axi0_if.araddr  <= addr;
        axi0_if.arlen   <= 8'd0;
        axi0_if.arsize  <= WORD_LSB_W[2:0];
        axi0_if.arburst <= 2'b01;
        axi0_if.arvalid <= 1'b1;

        do @(posedge dma_clk); while (!axi0_if.arready);
        axi0_if.arvalid <= 1'b0;

        axi0_if.rready  <= 1'b1;
        do @(posedge dma_clk); while (!axi0_if.rvalid);

        data = axi0_if.rdata;

        @(posedge dma_clk);
        axi0_if.rready <= 1'b0;
    end
    endtask

    task automatic host_write_u8(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [7:0]            value
    );
        logic [ADDR_WIDTH-1:0]    aligned_addr;
        logic [WORD_LSB_W-1:0]    byte_offset;
        logic [DATA_WIDTH-1:0]    data_word;
        logic [BYTE_PER_WORD-1:0] strb_word;
    begin
        aligned_addr = {addr[ADDR_WIDTH-1:WORD_LSB_W], {WORD_LSB_W{1'b0}}};
        byte_offset  = addr[WORD_LSB_W-1:0];

        data_word = {{(DATA_WIDTH-8){1'b0}}, value} << (byte_offset * 8);
        strb_word = {{(BYTE_PER_WORD-1){1'b0}}, 1'b1} << byte_offset;

        host_axi_write_word(aligned_addr, data_word, strb_word);
    end
    endtask

    task automatic host_write_u32(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [31:0]           value
    );
        logic [ADDR_WIDTH-1:0]    aligned_addr;
        logic [WORD_LSB_W-1:0]    byte_offset;
        logic [DATA_WIDTH-1:0]    data_word;
        logic [BYTE_PER_WORD-1:0] strb_word;
    begin
        aligned_addr = {addr[ADDR_WIDTH-1:WORD_LSB_W], {WORD_LSB_W{1'b0}}};
        byte_offset  = addr[WORD_LSB_W-1:0];

        data_word = {{(DATA_WIDTH-32){1'b0}}, value} << (byte_offset * 8);
        strb_word = {{(BYTE_PER_WORD-4){1'b0}}, 4'b1111} << byte_offset;

        host_axi_write_word(aligned_addr, data_word, strb_word);
    end
    endtask

    task automatic host_read_u32(
        input  logic [ADDR_WIDTH-1:0] addr,
        output logic [31:0]           value
    );
        logic [ADDR_WIDTH-1:0] aligned_addr;
        logic [WORD_LSB_W-1:0] byte_offset;
        logic [DATA_WIDTH-1:0] data_word;
    begin
        aligned_addr = {addr[ADDR_WIDTH-1:WORD_LSB_W], {WORD_LSB_W{1'b0}}};
        byte_offset  = addr[WORD_LSB_W-1:0];

        host_axi_read_word(aligned_addr, data_word);
        value = data_word >> (byte_offset * 8);
    end
    endtask

    task automatic start_accel();
    begin
        @(posedge dma_clk);
        acc_start <= 1'b1;
        @(posedge dma_clk);
        acc_start <= 1'b0;
    end
    endtask

    task automatic wait_done();
        int timeout;
    begin
        timeout = 0;
        while (acc_done !== 1'b1) begin
            @(posedge core_clk);
            timeout++;
            if (timeout > 20000) begin
                $fatal(1, "[TIMEOUT] wait_done timeout");
            end
        end
        $display("[INFO] acc_done observed.");
    end
    endtask

`include "../test/4x4_fixed_dimension_baseline_test.sv"
`include "../test/variable_dimension_smoke_test.sv"
`include "../test/back_to_back_run_smoke_test.sv"
`include "../test/reset_recovery_smoke_test.sv"

    // ============================================================
    // Main sequence
    // ============================================================
    initial begin
        if (!$value$plusargs("CASE=%d", CASE_ID)) begin
            CASE_ID = 0;
        end

        wait(dma_rst_n === 1'b1);
        wait(core_rst_n === 1'b1);

        repeat (5) @(posedge dma_clk);

        if (CASE_ID == 300) begin
            run_reset_recovery_smoke_test();
        end 
        else if (CASE_ID == 200) begin
            run_back_to_back_run_smoke_test();
        end
        else if ((CASE_ID >= 100) && (CASE_ID <= 105)) begin
            run_variable_dimension_smoke_test(CASE_ID);
        end
        else begin
            run_4x4_fixed_dimension_baseline_test(CASE_ID);
        end

        repeat (10) @(posedge dma_clk);
        $finish;
    end

endmodule