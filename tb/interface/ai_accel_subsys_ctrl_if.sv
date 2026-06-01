// File: tb/interface/ai_accel_subsys_ctrl_if.sv

`ifndef AI_ACCEL_SUBSYS_CTRL_IF_SV
`define AI_ACCEL_SUBSYS_CTRL_IF_SV

interface ai_accel_subsys_ctrl_if #(
    parameter int ADDR_WIDTH        = 32,
    parameter int DIM_WIDTH         = 8,
    parameter int DMA_SRC_MEM_BYTES = 4096,
    parameter int DMA_DST_MEM_BYTES = 4096
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
    // ------------------------------------------------------------
    logic                  dma_load_start;
    logic [ADDR_WIDTH-1:0] dma_src_base_addr;
    logic [ADDR_WIDTH-1:0] dma_dst_base_addr;
    logic [31:0]           dma_load_beats;

    logic                  dma_load_busy;
    logic                  dma_load_done;
    logic                  dma_load_error;

    // ------------------------------------------------------------
    // DMA store / S2MM control / status
    // ------------------------------------------------------------
    logic                  dma_store_start;
    logic [ADDR_WIDTH-1:0] dma_store_src_base_addr;
    logic [ADDR_WIDTH-1:0] dma_store_dst_base_addr;
    logic [31:0]           dma_store_byte_count;

    logic                  dma_store_busy;
    logic                  dma_store_done;
    logic                  dma_store_error;

    // ------------------------------------------------------------
    // AXI-Stream preload control / status
    //
    // V1 Option A:
    //   AXI source -> MM2S -> AXIS FIFO -> stream loader
    //   -> scratchpad Port1 preload A/B
    // ------------------------------------------------------------
    logic                  axis_load_start;
    logic [ADDR_WIDTH-1:0] axis_src_base_addr;
    logic [ADDR_WIDTH-1:0] axis_dst_base_addr;
    logic [31:0]           axis_load_beats;

    logic                  axis_load_busy;
    logic                  axis_load_done;
    logic                  axis_load_error;

    // ------------------------------------------------------------
    // Direct-stream GEMM operand preload control / status
    //
    // Direct Stream B1:
    //   AXI source -> MM2S -> AXIS FIFO -> stream loader
    //   -> operand buffer A/B
    //
    // ds_operand_sel:
    //   0 = operand A
    //   1 = operand B
    //
    // ds_dst_base_addr:
    //   logical operand base address. The direct-stream write
    //   adapter converts stream-loader wr_addr into local operand
    //   buffer offset by subtracting this base address.
    // ------------------------------------------------------------
    logic                  gemm_input_stream_mode;

    logic                  ds_load_start;
    logic [ADDR_WIDTH-1:0] ds_src_base_addr;
    logic [ADDR_WIDTH-1:0] ds_dst_base_addr;
    logic [31:0]           ds_load_beats;
    logic                  ds_operand_sel;

    logic                  ds_load_busy;
    logic                  ds_load_done;
    logic                  ds_load_error;

    // ------------------------------------------------------------
    // Accelerator control / status
    // ------------------------------------------------------------
    logic acc_start;
    logic acc_busy;
    logic acc_done;

    // ------------------------------------------------------------
    // GEMM performance counters
    //
    // Core-clock-domain snapshots from gemm_top.
    // Counters clear on accepted GEMM start and remain stable
    // after GEMM done until the next accepted start.
    // ------------------------------------------------------------
    logic [31:0] gemm_perf_busy_cycles;
    logic [31:0] gemm_perf_mac_count;
    logic [31:0] gemm_perf_output_count;

    // ------------------------------------------------------------
    // Runtime configuration
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] base_addr_a;
    logic [ADDR_WIDTH-1:0] base_addr_b;
    logic [ADDR_WIDTH-1:0] base_addr_c;

    logic [DIM_WIDTH-1:0]  dim_m;
    logic [DIM_WIDTH-1:0]  dim_n;
    logic [DIM_WIDTH-1:0]  dim_k;

    // C RMW accumulation runtime control bit.
    // When GEMM_ENABLE_C_RMW_ACCUM=1 in the DUT, this bit selects
    // whether the current GEMM job overwrites C or accumulates into
    // the existing C contents.
    logic                  accumulate_enable;

    // ------------------------------------------------------------
    // DMA / AXIS / Direct-stream source memory model storage
    //
    // Shared by:
    //   - DMA load source responder
    //   - AXI-Stream preload source responder
    //   - Direct-stream preload source responder
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
    // DMA source RRESP error injection control
    // ------------------------------------------------------------
    logic      dma_src_inject_rresp_error;
    int signed dma_src_inject_rresp_error_beat;

    task automatic dma_src_set_rresp_error(
        input bit        enable,
        input int signed beat_index
    );
    begin
        dma_src_inject_rresp_error      = enable;
        dma_src_inject_rresp_error_beat = beat_index;
    end
    endtask

    // ------------------------------------------------------------
    // AXI-Stream preload source RRESP error injection control
    // ------------------------------------------------------------
    logic      axis_src_inject_rresp_error;
    int signed axis_src_inject_rresp_error_beat;

    task automatic axis_src_set_rresp_error(
        input bit        enable,
        input int signed beat_index
    );
    begin
        axis_src_inject_rresp_error      = enable;
        axis_src_inject_rresp_error_beat = beat_index;
    end
    endtask

    // ------------------------------------------------------------
    // Direct-stream preload source RRESP error injection control
    //
    // Separate from DMA load and AXIS preload injection controls so
    // direct-stream error tests can be isolated.
    // ------------------------------------------------------------
    logic      ds_src_inject_rresp_error;
    int signed ds_src_inject_rresp_error_beat;

    task automatic ds_src_set_rresp_error(
        input bit        enable,
        input int signed beat_index
    );
    begin
        ds_src_inject_rresp_error      = enable;
        ds_src_inject_rresp_error_beat = beat_index;
    end
    endtask

    // ------------------------------------------------------------
    // DMA destination memory model storage
    // ------------------------------------------------------------
    logic [7:0] dma_dst_mem [0:DMA_DST_MEM_BYTES-1];

    function automatic int unsigned dma_dst_byte_index(
        input logic [ADDR_WIDTH-1:0] addr
    );
        return int'(addr);
    endfunction

    task automatic dma_dst_mem_clear();
        int unsigned i;
    begin
        for (i = 0; i < DMA_DST_MEM_BYTES; i++) begin
            dma_dst_mem[i] = 8'h00;
        end
    end
    endtask

    task automatic dma_dst_mem_write_byte(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [7:0]            data
    );
        int unsigned idx;
    begin
        idx = dma_dst_byte_index(addr);

        if (idx >= DMA_DST_MEM_BYTES) begin
            $fatal(1,
                "[CTRL_IF_DMA_DST] dma_dst_mem_write_byte out of range: addr=0x%08h idx=%0d depth=%0d",
                addr, idx, DMA_DST_MEM_BYTES
            );
        end

        dma_dst_mem[idx] = data;
    end
    endtask

    function automatic logic [7:0] dma_dst_mem_read_byte(
        input logic [ADDR_WIDTH-1:0] addr
    );
        int unsigned idx;
    begin
        idx = dma_dst_byte_index(addr);

        if (idx >= DMA_DST_MEM_BYTES) begin
            $fatal(1,
                "[CTRL_IF_DMA_DST] dma_dst_mem_read_byte out of range: addr=0x%08h idx=%0d depth=%0d",
                addr, idx, DMA_DST_MEM_BYTES
            );
        end

        return dma_dst_mem[idx];
    end
    endfunction

    function automatic logic [31:0] dma_dst_mem_read_word32(
        input logic [ADDR_WIDTH-1:0] addr
    );
        int unsigned idx;
        logic [31:0] data;
    begin
        idx = dma_dst_byte_index(addr);

        if ((idx + 4) > DMA_DST_MEM_BYTES) begin
            $fatal(1,
                "[CTRL_IF_DMA_DST] dma_dst_mem_read_word32 out of range: addr=0x%08h idx=%0d depth=%0d",
                addr, idx, DMA_DST_MEM_BYTES
            );
        end

        data = '0;
        data[7:0]   = dma_dst_mem[idx + 0];
        data[15:8]  = dma_dst_mem[idx + 1];
        data[23:16] = dma_dst_mem[idx + 2];
        data[31:24] = dma_dst_mem[idx + 3];

        return data;
    end
    endfunction

    function automatic int signed dma_dst_mem_read_s32(
        input logic [ADDR_WIDTH-1:0] addr
    );
        logic signed [31:0] data_s32;
    begin
        data_s32 = dma_dst_mem_read_word32(addr);
        return int'(data_s32);
    end
    endfunction

    task automatic dma_dst_mem_read_s32_array(
        input  logic [ADDR_WIDTH-1:0] base_addr,
        input  int unsigned           word_count,
        output int signed             values[]
    );
        int unsigned i;
    begin
        values = new[word_count];

        for (i = 0; i < word_count; i++) begin
            values[i] = dma_dst_mem_read_s32(base_addr + ADDR_WIDTH'(i * 4));
        end
    end
    endtask

    // ------------------------------------------------------------
    // DMA destination BRESP error injection control
    // ------------------------------------------------------------
    logic      dma_dst_inject_bresp_error;
    int signed dma_dst_inject_bresp_error_beat;

    task automatic dma_dst_set_bresp_error(
        input bit        enable,
        input int signed beat_index
    );
    begin
        dma_dst_inject_bresp_error      = enable;
        dma_dst_inject_bresp_error_beat = beat_index;
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

        // DMA store control
        output dma_store_start;
        output dma_store_src_base_addr;
        output dma_store_dst_base_addr;
        output dma_store_byte_count;

        input  dma_store_busy;
        input  dma_store_done;
        input  dma_store_error;

        // AXI-Stream preload control
        output axis_load_start;
        output axis_src_base_addr;
        output axis_dst_base_addr;
        output axis_load_beats;

        input  axis_load_busy;
        input  axis_load_done;
        input  axis_load_error;

        // Direct-stream control
        output gemm_input_stream_mode;

        output ds_load_start;
        output ds_src_base_addr;
        output ds_dst_base_addr;
        output ds_load_beats;
        output ds_operand_sel;

        input  ds_load_busy;
        input  ds_load_done;
        input  ds_load_error;

        // Accelerator control
        output acc_start;

        output base_addr_a;
        output base_addr_b;
        output base_addr_c;

        output dim_m;
        output dim_n;
        output dim_k;

        // C RMW accumulation runtime control
        output accumulate_enable;

        // Reset override control
        output tb_reset_override_en;
        output tb_dma_rst_n_override;
        output tb_core_rst_n_override;

        // Reset/status observation
        input  dma_rst_n;
        input  core_rst_n;

        input  acc_busy;
        input  acc_done;

        input  gemm_perf_busy_cycles;
        input  gemm_perf_mac_count;
        input  gemm_perf_output_count;
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

        // DMA store observation
        input dma_store_start;
        input dma_store_src_base_addr;
        input dma_store_dst_base_addr;
        input dma_store_byte_count;

        input dma_store_busy;
        input dma_store_done;
        input dma_store_error;

        // AXI-Stream preload observation
        input axis_load_start;
        input axis_src_base_addr;
        input axis_dst_base_addr;
        input axis_load_beats;

        input axis_load_busy;
        input axis_load_done;
        input axis_load_error;

        // Direct-stream observation
        input gemm_input_stream_mode;

        input ds_load_start;
        input ds_src_base_addr;
        input ds_dst_base_addr;
        input ds_load_beats;
        input ds_operand_sel;

        input ds_load_busy;
        input ds_load_done;
        input ds_load_error;

        // Accelerator observation
        input acc_start;
        input acc_busy;
        input acc_done;

        input gemm_perf_busy_cycles;
        input gemm_perf_mac_count;
        input gemm_perf_output_count;

        input base_addr_a;
        input base_addr_b;
        input base_addr_c;

        input dim_m;
        input dim_n;
        input dim_k;

        // C RMW accumulation runtime control observation
        input accumulate_enable;

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