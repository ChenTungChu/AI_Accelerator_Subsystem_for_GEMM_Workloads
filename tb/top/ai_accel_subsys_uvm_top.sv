// File: tb/top/ai_accel_subsys_uvm_top.sv
`timescale 1ns/1ps

module ai_accel_subsys_uvm_top;

    import uvm_pkg::*;
    import ai_accel_subsys_uvm_pkg::*;
    `include "uvm_macros.svh"

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

    localparam int BYTES_PER_BEAT  = DATA_WIDTH / 8;

    // DMA source memory model used by subsystem-level DMA load tests.
    // Byte-addressed so A/B payloads can be packed naturally.
    localparam int DMA_SRC_MEM_BYTES = 4096;
    localparam int DMA_SRC_READ_LATENCY_CYCLES = 2;

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    // ============================================================
    // Virtual interface typedefs for UVM config_db handoff
    // ============================================================
    typedef virtual ai_accel_subsys_ctrl_if #(
        .ADDR_WIDTH        (ADDR_WIDTH),
        .DIM_WIDTH         (GEMM_DIM_WIDTH),
        .DMA_SRC_MEM_BYTES (DMA_SRC_MEM_BYTES)
    ) ctrl_vif_t;

    typedef virtual axi_mm_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .HAS_BURST  (1)
    ) axi0_vif_t;

    // ============================================================
    // Clocks / resets
    // ============================================================
    logic dma_clk;
    logic core_clk;

    // POR resets
    logic dma_rst_n_por;
    logic core_rst_n_por;

    // Final resets feeding DUT / interfaces
    logic dma_rst_n;
    logic core_rst_n;

    // ============================================================
    // DUT control / status
    // ============================================================
    logic acc_busy;
    logic acc_done;

    // ============================================================
    // DMA load status wires
    //
    // Control is driven through ctrl_if:
    //   ctrl_if.dma_load_start
    //   ctrl_if.dma_src_base_addr
    //   ctrl_if.dma_dst_base_addr
    //   ctrl_if.dma_load_beats
    // ============================================================
    logic dma_load_busy;
    logic dma_load_done;
    logic dma_load_error;

    // ============================================================
    // DMA source AXI-MM read port
    // ============================================================
    logic [ID_WIDTH-1:0]   dma_src_axi_arid;
    logic [ADDR_WIDTH-1:0] dma_src_axi_araddr;
    logic [7:0]            dma_src_axi_arlen;
    logic [2:0]            dma_src_axi_arsize;
    logic [1:0]            dma_src_axi_arburst;
    logic                  dma_src_axi_arvalid;
    logic                  dma_src_axi_arready;

    logic [ID_WIDTH-1:0]   dma_src_axi_rid;
    logic [DATA_WIDTH-1:0] dma_src_axi_rdata;
    logic [1:0]            dma_src_axi_rresp;
    logic                  dma_src_axi_rlast;
    logic                  dma_src_axi_rvalid;
    logic                  dma_src_axi_rready;

    // ============================================================
    // DMA source memory responder model state
    //
    // Actual byte storage lives inside ctrl_if.dma_src_mem[].
    // UVM tests preload it through virtual interface tasks.
    // ============================================================
    logic                  dma_src_rd_pending_valid;
    logic [ADDR_WIDTH-1:0] dma_src_rd_pending_addr;
    logic [ID_WIDTH-1:0]   dma_src_rd_pending_id;
    int unsigned           dma_src_rd_pending_delay;

    logic [ID_WIDTH-1:0]   dma_src_rid_q;
    logic [DATA_WIDTH-1:0] dma_src_rdata_q;
    logic [1:0]            dma_src_rresp_q;
    logic                  dma_src_rlast_q;
    logic                  dma_src_rvalid_q;

    logic                  dma_src_inject_rresp_error;
    int signed             dma_src_inject_rresp_error_beat;
    int unsigned           dma_src_ar_count;
    int unsigned           dma_src_r_count;

    wire dma_src_ar_fire = dma_src_axi_arvalid && dma_src_axi_arready;
    wire dma_src_r_fire  = dma_src_axi_rvalid  && dma_src_axi_rready;

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
    // UVM control/config interface
    // ============================================================
    ai_accel_subsys_ctrl_if #(
        .ADDR_WIDTH        (ADDR_WIDTH),
        .DIM_WIDTH         (GEMM_DIM_WIDTH),
        .DMA_SRC_MEM_BYTES (DMA_SRC_MEM_BYTES)
    ) ctrl_if (
        .clk (dma_clk)
    );

    // ============================================================
    // Final reset mux
    // ============================================================
    assign dma_rst_n  = (ctrl_if.tb_reset_override_en) ?
                        ctrl_if.tb_dma_rst_n_override  :
                        dma_rst_n_por;

    assign core_rst_n = (ctrl_if.tb_reset_override_en) ?
                        ctrl_if.tb_core_rst_n_override :
                        core_rst_n_por;

    // ============================================================
    // DMA source AXI read response model connections
    // ============================================================
    assign dma_src_axi_arready = dma_rst_n &&
                                 !dma_src_rd_pending_valid &&
                                 !dma_src_rvalid_q;

    assign dma_src_axi_rid     = dma_src_rid_q;
    assign dma_src_axi_rdata   = dma_src_rdata_q;
    assign dma_src_axi_rresp   = dma_src_rresp_q;
    assign dma_src_axi_rlast   = dma_src_rlast_q;
    assign dma_src_axi_rvalid  = dma_src_rvalid_q;

    // ============================================================
    // DMA source memory helper functions
    // ============================================================
    function automatic int unsigned dma_src_byte_index(
        input logic [ADDR_WIDTH-1:0] addr
    );
        return int'(addr);
    endfunction

    function automatic logic [DATA_WIDTH-1:0] dma_src_pack_word(
        input logic [ADDR_WIDTH-1:0] addr
    );
        logic [DATA_WIDTH-1:0] word;
        int unsigned base_idx;
        int unsigned lane;
    begin
        word     = '0;
        base_idx = dma_src_byte_index(addr);

        for (lane = 0; lane < BYTES_PER_BEAT; lane++) begin
            if ((base_idx + lane) < DMA_SRC_MEM_BYTES) begin
                word[8*lane +: 8] = ctrl_if.dma_src_mem[base_idx + lane];
            end
        end

        return word;
    end
    endfunction

    task automatic dma_src_set_rresp_error(
        input bit        enable,
        input int signed beat_index
    );
    begin
        dma_src_inject_rresp_error      = enable;
        dma_src_inject_rresp_error_beat = beat_index;
    end
    endtask

    // ============================================================
    // DMA source AXI read responder
    //
    // v1 assumptions:
    //   - single outstanding read
    //   - single-beat AR only, ARLEN must be 0
    //   - byte-addressed source memory
    // ============================================================
    always_ff @(posedge dma_clk or negedge dma_rst_n) begin
        if (!dma_rst_n) begin
            dma_src_rd_pending_valid <= 1'b0;
            dma_src_rd_pending_addr  <= '0;
            dma_src_rd_pending_id    <= '0;
            dma_src_rd_pending_delay <= 0;

            dma_src_rid_q            <= '0;
            dma_src_rdata_q          <= '0;
            dma_src_rresp_q          <= AXI_RESP_OKAY;
            dma_src_rlast_q          <= 1'b0;
            dma_src_rvalid_q         <= 1'b0;

            dma_src_ar_count         <= 0;
            dma_src_r_count          <= 0;
        end
        else begin
            if (dma_src_ar_fire) begin
                int unsigned ar_base_idx;

                ar_base_idx = dma_src_byte_index(dma_src_axi_araddr);

                if (dma_src_axi_arlen !== 8'd0) begin
                    $fatal(1,
                        "[UVM_TOP_DMA_SRC] Unsupported DMA source ARLEN=%0d, expected 0",
                        dma_src_axi_arlen
                    );
                end

                if ((ar_base_idx + BYTES_PER_BEAT) > DMA_SRC_MEM_BYTES) begin
                    $fatal(1,
                        "[UVM_TOP_DMA_SRC] DMA source read out of range: addr=0x%08h idx=%0d depth=%0d",
                        dma_src_axi_araddr, ar_base_idx, DMA_SRC_MEM_BYTES
                    );
                end

                dma_src_rd_pending_valid <= 1'b1;
                dma_src_rd_pending_addr  <= dma_src_axi_araddr;
                dma_src_rd_pending_id    <= dma_src_axi_arid;
                dma_src_rd_pending_delay <= DMA_SRC_READ_LATENCY_CYCLES;

                dma_src_ar_count         <= dma_src_ar_count + 1;
            end
            else if (dma_src_rd_pending_valid && (dma_src_rd_pending_delay != 0)) begin
                dma_src_rd_pending_delay <= dma_src_rd_pending_delay - 1;
            end

            if (dma_src_r_fire) begin
                dma_src_rvalid_q <= 1'b0;
                dma_src_rlast_q  <= 1'b0;
                dma_src_rresp_q  <= AXI_RESP_OKAY;
                dma_src_rdata_q  <= '0;
                dma_src_rid_q    <= '0;

                dma_src_r_count  <= dma_src_r_count + 1;
            end

            if (!dma_src_rvalid_q &&
                dma_src_rd_pending_valid &&
                (dma_src_rd_pending_delay == 0)) begin

                dma_src_rvalid_q <= 1'b1;
                dma_src_rlast_q  <= 1'b1;
                dma_src_rid_q    <= dma_src_rd_pending_id;
                dma_src_rdata_q  <= dma_src_pack_word(dma_src_rd_pending_addr);

                if (dma_src_inject_rresp_error &&
                    (dma_src_inject_rresp_error_beat >= 0) &&
                    (int'(dma_src_ar_count) == dma_src_inject_rresp_error_beat)) begin
                    dma_src_rresp_q <= AXI_RESP_SLVERR;
                end
                else begin
                    dma_src_rresp_q <= AXI_RESP_OKAY;
                end

                dma_src_rd_pending_valid <= 1'b0;
            end
        end
    end

    // ============================================================
    // DUT
    // ============================================================
    ai_accel_subsys #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .DATA_WIDTH      (DATA_WIDTH),
        .ID_WIDTH        (ID_WIDTH),
        .DEPTH_WORDS     (DEPTH_WORDS),
        .GEMM_A_WIDTH    (GEMM_A_WIDTH),
        .GEMM_B_WIDTH    (GEMM_B_WIDTH),
        .GEMM_ACC_WIDTH  (GEMM_ACC_WIDTH),
        .GEMM_DIM_WIDTH  (GEMM_DIM_WIDTH)
    ) dut (
        .dma_clk              (dma_clk),
        .dma_rst_n            (dma_rst_n),
        .core_clk             (core_clk),
        .core_rst_n           (core_rst_n),

        .axi0_if              (axi0_if),

        // DMA load control through ctrl_if
        .dma_load_start       (ctrl_if.dma_load_start),
        .dma_src_base_addr    (ctrl_if.dma_src_base_addr),
        .dma_dst_base_addr    (ctrl_if.dma_dst_base_addr),
        .dma_load_beats       (ctrl_if.dma_load_beats),

        .dma_load_busy        (dma_load_busy),
        .dma_load_done        (dma_load_done),
        .dma_load_error       (dma_load_error),

        // DMA source AXI-MM read master port
        .dma_src_axi_arid     (dma_src_axi_arid),
        .dma_src_axi_araddr   (dma_src_axi_araddr),
        .dma_src_axi_arlen    (dma_src_axi_arlen),
        .dma_src_axi_arsize   (dma_src_axi_arsize),
        .dma_src_axi_arburst  (dma_src_axi_arburst),
        .dma_src_axi_arvalid  (dma_src_axi_arvalid),
        .dma_src_axi_arready  (dma_src_axi_arready),

        .dma_src_axi_rid      (dma_src_axi_rid),
        .dma_src_axi_rdata    (dma_src_axi_rdata),
        .dma_src_axi_rresp    (dma_src_axi_rresp),
        .dma_src_axi_rlast    (dma_src_axi_rlast),
        .dma_src_axi_rvalid   (dma_src_axi_rvalid),
        .dma_src_axi_rready   (dma_src_axi_rready),

        // Accelerator control
        .acc_start            (ctrl_if.acc_start),
        .acc_busy             (acc_busy),
        .acc_done             (acc_done),

        .base_addr_a          (ctrl_if.base_addr_a),
        .base_addr_b          (ctrl_if.base_addr_b),
        .base_addr_c          (ctrl_if.base_addr_c),

        .dim_m                (ctrl_if.dim_m),
        .dim_n                (ctrl_if.dim_n),
        .dim_k                (ctrl_if.dim_k)
    );

    // ============================================================
    // Connect DUT status/reset observation into ctrl_if
    // ============================================================
    assign ctrl_if.dma_rst_n  = dma_rst_n;
    assign ctrl_if.core_rst_n = core_rst_n;

    assign ctrl_if.acc_busy   = acc_busy;
    assign ctrl_if.acc_done   = acc_done;

    assign ctrl_if.dma_load_busy  = dma_load_busy;
    assign ctrl_if.dma_load_done  = dma_load_done;
    assign ctrl_if.dma_load_error = dma_load_error;

    // ============================================================
    // BRAM observation interface ready
    // ============================================================
    initial begin
        force dut.apply_if.ready  = 1'b1;
        force dut.commit_if.ready = 1'b1;
    end

    // ============================================================
    // Clock generation
    // ============================================================
    initial begin
        dma_clk = 1'b0;
        forever #5 dma_clk = ~dma_clk;      // 100 MHz
    end

    initial begin
        core_clk = 1'b0;
        forever #7 core_clk = ~core_clk;    // ~71.4 MHz
    end

    // ============================================================
    // POR reset generation
    // ============================================================
    initial begin
        dma_rst_n_por  = 1'b0;
        core_rst_n_por = 1'b0;

        repeat (5) @(posedge dma_clk);
        dma_rst_n_por = 1'b1;

        repeat (5) @(posedge core_clk);
        core_rst_n_por = 1'b1;
    end

    // ============================================================
    // Default idle values
    // ============================================================
    initial begin
        // ctrl_if defaults
        ctrl_if.acc_start   = 1'b0;
        ctrl_if.base_addr_a = '0;
        ctrl_if.base_addr_b = '0;
        ctrl_if.base_addr_c = '0;
        ctrl_if.dim_m       = '0;
        ctrl_if.dim_n       = '0;
        ctrl_if.dim_k       = '0;

        // DMA load defaults
        ctrl_if.dma_load_start    = 1'b0;
        ctrl_if.dma_src_base_addr = '0;
        ctrl_if.dma_dst_base_addr = '0;
        ctrl_if.dma_load_beats    = '0;

        // reset override defaults
        ctrl_if.tb_reset_override_en   = 1'b0;
        ctrl_if.tb_dma_rst_n_override  = 1'b1;
        ctrl_if.tb_core_rst_n_override = 1'b1;

        // DMA source memory model defaults
        ctrl_if.dma_src_mem_clear();
        dma_src_set_rresp_error(1'b0, -1);

        // axi0_if idle defaults
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
    end

    // ============================================================
    // UVM hookup
    // ============================================================
    initial begin
        uvm_config_db#(ctrl_vif_t)::set(
            null, "*", "vif", ctrl_if
        );

        uvm_config_db#(axi0_vif_t)::set(
            null, "*", "axi0_vif", axi0_if
        );

        run_test();
    end

endmodule