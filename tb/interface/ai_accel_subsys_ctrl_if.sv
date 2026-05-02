// File: tb/interface/ai_accel_subsys_ctrl_if.sv

`ifndef AI_ACCEL_SUBSYS_CTRL_IF_SV
`define AI_ACCEL_SUBSYS_CTRL_IF_SV

interface ai_accel_subsys_ctrl_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DIM_WIDTH  = 8,
    parameter int DMA_SRC_MEM_BYTES = 4096
)(
    input logic clk
);

    // ------------------------------------------------------------
    // Reset/status observation
    // ------------------------------------------------------------
    logic dma_rst_n;
    logic core_rst_n;

    // ------------------------------------------------------------
    // Testbench reset override control
    // ------------------------------------------------------------
    logic tb_reset_override_en;
    logic tb_dma_rst_n_override;
    logic tb_core_rst_n_override;

    // ------------------------------------------------------------
    // DMA load control / status
    //
    // v1 usage:
    //   1. Test drives dma_load_start for one dma_clk cycle.
    //   2. Test waits for dma_load_done.
    //   3. Test checks dma_load_error.
    //   4. Then test launches acc_start.
    // ------------------------------------------------------------
    logic                  dma_load_start;
    logic [ADDR_WIDTH-1:0] dma_src_base_addr;
    logic [ADDR_WIDTH-1:0] dma_dst_base_addr;
    logic [31:0]           dma_load_beats;

    logic                  dma_load_busy;
    logic                  dma_load_done;
    logic                  dma_load_error;

    // ------------------------------------------------------------
    // Accelerator control / status
    // ------------------------------------------------------------
    logic acc_start;
    logic acc_busy;
    logic acc_done;

    // ------------------------------------------------------------
    // Runtime configuration
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] base_addr_a;
    logic [ADDR_WIDTH-1:0] base_addr_b;
    logic [ADDR_WIDTH-1:0] base_addr_c;

    logic [DIM_WIDTH-1:0]  dim_m;
    logic [DIM_WIDTH-1:0]  dim_n;
    logic [DIM_WIDTH-1:0]  dim_k;


    // ------------------------------------------------------------
    // DMA source memory model storage
    //
    // Used by subsystem-level DMA load tests.
    // The responder in ai_accel_subsys_uvm_top reads from this array.
    // UVM tests preload this array through virtual interface tasks.
    // ------------------------------------------------------------
    logic [7:0] dma_src_mem [0:DMA_SRC_MEM_BYTES-1];

    function automatic int unsigned dma_src_byte_index(
        input logic [ADDR_WIDTH-1:0] addr
    );
        return int'(addr);
    endfunction

    task automatic dma_src_mem_clear();
        int unsigned i;
    begin
        for (i = 0; i < DMA_SRC_MEM_BYTES; i++) begin
            dma_src_mem[i] = 8'h00;
        end
    end
    endtask

    task automatic dma_src_mem_write_byte(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [7:0]            data
    );
        int unsigned idx;
    begin
        idx = dma_src_byte_index(addr);

        if (idx >= DMA_SRC_MEM_BYTES) begin
            $fatal(1,
                "[CTRL_IF_DMA_SRC] dma_src_mem_write_byte out of range: addr=0x%08h idx=%0d depth=%0d",
                addr, idx, DMA_SRC_MEM_BYTES
            );
        end

        dma_src_mem[idx] = data;
    end
    endtask

    task automatic dma_src_mem_write_word64(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [63:0]           data
    );
        int unsigned lane;
        int unsigned idx;
    begin
        idx = dma_src_byte_index(addr);

        if ((idx + 8) > DMA_SRC_MEM_BYTES) begin
            $fatal(1,
                "[CTRL_IF_DMA_SRC] dma_src_mem_write_word64 out of range: addr=0x%08h idx=%0d depth=%0d",
                addr, idx, DMA_SRC_MEM_BYTES
            );
        end

        for (lane = 0; lane < 8; lane++) begin
            dma_src_mem[idx + lane] = data[8*lane +: 8];
        end
    end
    endtask

    // ------------------------------------------------------------
    // Driver clocking block
    // ------------------------------------------------------------
    clocking cb_drv @(posedge clk);
        // DMA load control
        output dma_load_start;
        output dma_src_base_addr;
        output dma_dst_base_addr;
        output dma_load_beats;

        input  dma_load_busy;
        input  dma_load_done;
        input  dma_load_error;

        // Accelerator control
        output acc_start;

        output base_addr_a;
        output base_addr_b;
        output base_addr_c;

        output dim_m;
        output dim_n;
        output dim_k;

        // Reset override control
        output tb_reset_override_en;
        output tb_dma_rst_n_override;
        output tb_core_rst_n_override;

        // Reset/status observation
        input  dma_rst_n;
        input  core_rst_n;

        input  acc_busy;
        input  acc_done;
    endclocking

    // ------------------------------------------------------------
    // Monitor clocking block
    // ------------------------------------------------------------
    clocking cb_mon @(posedge clk);
        input dma_rst_n;
        input core_rst_n;

        // DMA load observation
        input dma_load_start;
        input dma_src_base_addr;
        input dma_dst_base_addr;
        input dma_load_beats;

        input dma_load_busy;
        input dma_load_done;
        input dma_load_error;

        // Accelerator observation
        input acc_start;
        input acc_busy;
        input acc_done;

        input base_addr_a;
        input base_addr_b;
        input base_addr_c;

        input dim_m;
        input dim_n;
        input dim_k;

        input tb_reset_override_en;
        input tb_dma_rst_n_override;
        input tb_core_rst_n_override;
    endclocking

    // ------------------------------------------------------------
    // Modports
    // ------------------------------------------------------------
    modport drv (
        clocking cb_drv
    );

    modport mon (
        clocking cb_mon
    );

endinterface

`endif