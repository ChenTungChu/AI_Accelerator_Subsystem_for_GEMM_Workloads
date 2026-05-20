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

    parameter  int GEMM_MAC_LANES  = 1;

    parameter  bit GEMM_ENABLE_B_CACHE = 1'b0;

    // P5 packed B-cache preload.
    // Default-off so the current baseline behavior is unchanged unless explicitly enabled.
    parameter  bit GEMM_ENABLE_PACKED_BCACHE_PRELOAD = 1'b0;

    // P6 safe parameter patch.
    // Default-off so the current P5 baseline behavior is unchanged.
    parameter  bit GEMM_ENABLE_A_ROW_CACHE = 1'b0;
    parameter  int GEMM_A_ROW_CACHE_MAX_K  = 4;

    // P7 safe parameter patch.
    // Default-off so the current P6 baseline behavior is unchanged.
    parameter  bit GEMM_ENABLE_PACKED_A_ROW_PRELOAD = 1'b0;

    localparam int BYTES_PER_BEAT  = DATA_WIDTH / 8;

    // DMA / AXIS source memory model.
    // Byte-addressed so A/B payloads can be packed naturally.
    localparam int DMA_SRC_MEM_BYTES = 4096;
    localparam int DMA_SRC_READ_LATENCY_CYCLES  = 2;
    localparam int AXIS_SRC_READ_LATENCY_CYCLES = 2;
    localparam int DS_SRC_READ_LATENCY_CYCLES   = 2;

    // DMA destination memory model used by subsystem-level DMA store tests.
    // Byte-addressed so C payloads can be checked naturally.
    localparam int DMA_DST_MEM_BYTES = 4096;
    localparam int DMA_DST_WRITE_RESP_LATENCY_CYCLES = 1;

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    // ============================================================
    // Virtual interface typedefs for UVM config_db handoff
    // ============================================================
    typedef virtual ai_accel_subsys_ctrl_if #(
        .ADDR_WIDTH        (ADDR_WIDTH),
        .DIM_WIDTH         (GEMM_DIM_WIDTH),
        .DMA_SRC_MEM_BYTES (DMA_SRC_MEM_BYTES),
        .DMA_DST_MEM_BYTES (DMA_DST_MEM_BYTES)
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

    real dma_clk_period_ns;
    real core_clk_period_ns;

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
    // GEMM performance counter wires
    // ============================================================
    logic [31:0] gemm_perf_busy_cycles;
    logic [31:0] gemm_perf_mac_count;
    logic [31:0] gemm_perf_output_count;

    // ============================================================
    // DMA load status wires
    // ============================================================
    logic dma_load_busy;
    logic dma_load_done;
    logic dma_load_error;

    // ============================================================
    // DMA store status wires
    // ============================================================
    logic dma_store_busy;
    logic dma_store_done;
    logic dma_store_error;

    // ============================================================
    // AXI-Stream preload status wires
    // ============================================================
    logic axis_load_busy;
    logic axis_load_done;
    logic axis_load_error;

    // ============================================================
    // Direct-stream preload status wires
    // ============================================================
    logic ds_load_busy;
    logic ds_load_done;
    logic ds_load_error;

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
    // ============================================================
    logic                  dma_src_rd_pending_valid;
    logic [ADDR_WIDTH-1:0] dma_src_rd_pending_addr;
    logic [ID_WIDTH-1:0]   dma_src_rd_pending_id;
    int unsigned           dma_src_rd_pending_delay;
    int unsigned           dma_src_rd_pending_beat_idx;

    logic                  dma_src_inject_enable_q;
    int unsigned           dma_src_inject_base_ar_count;

    logic [ID_WIDTH-1:0]   dma_src_rid_q;
    logic [DATA_WIDTH-1:0] dma_src_rdata_q;
    logic [1:0]            dma_src_rresp_q;
    logic                  dma_src_rlast_q;
    logic                  dma_src_rvalid_q;

    int unsigned           dma_src_ar_count;
    int unsigned           dma_src_r_count;

    wire dma_src_ar_fire = dma_src_axi_arvalid && dma_src_axi_arready;
    wire dma_src_r_fire  = dma_src_axi_rvalid  && dma_src_axi_rready;

    // ============================================================
    // AXI-Stream preload source AXI-MM read port
    // ============================================================
    logic [ID_WIDTH-1:0]   axis_src_axi_arid;
    logic [ADDR_WIDTH-1:0] axis_src_axi_araddr;
    logic [7:0]            axis_src_axi_arlen;
    logic [2:0]            axis_src_axi_arsize;
    logic [1:0]            axis_src_axi_arburst;
    logic                  axis_src_axi_arvalid;
    logic                  axis_src_axi_arready;

    logic [ID_WIDTH-1:0]   axis_src_axi_rid;
    logic [DATA_WIDTH-1:0] axis_src_axi_rdata;
    logic [1:0]            axis_src_axi_rresp;
    logic                  axis_src_axi_rlast;
    logic                  axis_src_axi_rvalid;
    logic                  axis_src_axi_rready;

    // ============================================================
    // AXIS source memory responder model state
    //
    // Storage is shared with DMA source:
    //   ctrl_if.dma_src_mem[]
    //
    // Error injection is independent:
    //   ctrl_if.axis_src_inject_rresp_error
    // ============================================================
    logic                  axis_src_rd_pending_valid;
    logic [ADDR_WIDTH-1:0] axis_src_rd_pending_addr;
    logic [ID_WIDTH-1:0]   axis_src_rd_pending_id;
    int unsigned           axis_src_rd_pending_delay;
    int unsigned           axis_src_rd_pending_beat_idx;

    logic                  axis_src_inject_enable_q;
    int unsigned           axis_src_inject_base_ar_count;

    logic [ID_WIDTH-1:0]   axis_src_rid_q;
    logic [DATA_WIDTH-1:0] axis_src_rdata_q;
    logic [1:0]            axis_src_rresp_q;
    logic                  axis_src_rlast_q;
    logic                  axis_src_rvalid_q;

    int unsigned           axis_src_ar_count;
    int unsigned           axis_src_r_count;

    wire axis_src_ar_fire = axis_src_axi_arvalid && axis_src_axi_arready;
    wire axis_src_r_fire  = axis_src_axi_rvalid  && axis_src_axi_rready;

    // ============================================================
    // Direct-stream preload source AXI-MM read port
    // ============================================================
    logic [ID_WIDTH-1:0]   ds_src_axi_arid;
    logic [ADDR_WIDTH-1:0] ds_src_axi_araddr;
    logic [7:0]            ds_src_axi_arlen;
    logic [2:0]            ds_src_axi_arsize;
    logic [1:0]            ds_src_axi_arburst;
    logic                  ds_src_axi_arvalid;
    logic                  ds_src_axi_arready;

    logic [ID_WIDTH-1:0]   ds_src_axi_rid;
    logic [DATA_WIDTH-1:0] ds_src_axi_rdata;
    logic [1:0]            ds_src_axi_rresp;
    logic                  ds_src_axi_rlast;
    logic                  ds_src_axi_rvalid;
    logic                  ds_src_axi_rready;

    // ============================================================
    // Direct-stream source memory responder model state
    //
    // Storage is shared with DMA/AXIS source:
    //   ctrl_if.dma_src_mem[]
    //
    // Error injection is independent:
    //   ctrl_if.ds_src_inject_rresp_error
    // ============================================================
    logic                  ds_src_rd_pending_valid;
    logic [ADDR_WIDTH-1:0] ds_src_rd_pending_addr;
    logic [ID_WIDTH-1:0]   ds_src_rd_pending_id;
    int unsigned           ds_src_rd_pending_delay;
    int unsigned           ds_src_rd_pending_beat_idx;

    logic                  ds_src_inject_enable_q;
    int unsigned           ds_src_inject_base_ar_count;

    logic [ID_WIDTH-1:0]   ds_src_rid_q;
    logic [DATA_WIDTH-1:0] ds_src_rdata_q;
    logic [1:0]            ds_src_rresp_q;
    logic                  ds_src_rlast_q;
    logic                  ds_src_rvalid_q;

    int unsigned           ds_src_ar_count;
    int unsigned           ds_src_r_count;

    wire ds_src_ar_fire = ds_src_axi_arvalid && ds_src_axi_arready;
    wire ds_src_r_fire  = ds_src_axi_rvalid  && ds_src_axi_rready;

    // ============================================================
    // DMA destination AXI-MM write port
    // ============================================================
    logic [ID_WIDTH-1:0]       dma_dst_axi_awid;
    logic [ADDR_WIDTH-1:0]     dma_dst_axi_awaddr;
    logic [7:0]                dma_dst_axi_awlen;
    logic [2:0]                dma_dst_axi_awsize;
    logic [1:0]                dma_dst_axi_awburst;
    logic                      dma_dst_axi_awvalid;
    logic                      dma_dst_axi_awready;

    logic [DATA_WIDTH-1:0]     dma_dst_axi_wdata;
    logic [DATA_WIDTH/8-1:0]   dma_dst_axi_wstrb;
    logic                      dma_dst_axi_wlast;
    logic                      dma_dst_axi_wvalid;
    logic                      dma_dst_axi_wready;

    logic [ID_WIDTH-1:0]       dma_dst_axi_bid;
    logic [1:0]                dma_dst_axi_bresp;
    logic                      dma_dst_axi_bvalid;
    logic                      dma_dst_axi_bready;

    // ============================================================
    // DMA destination memory write responder model state
    // ============================================================
    logic                      dma_dst_aw_pending_valid;
    logic [ID_WIDTH-1:0]       dma_dst_aw_pending_id;
    logic [ADDR_WIDTH-1:0]     dma_dst_aw_pending_addr;
    int unsigned               dma_dst_aw_pending_beat_idx;

    logic                      dma_dst_w_pending_valid;
    logic [DATA_WIDTH-1:0]     dma_dst_w_pending_data;
    logic [DATA_WIDTH/8-1:0]   dma_dst_w_pending_strb;
    logic                      dma_dst_w_pending_last;

    logic [ID_WIDTH-1:0]       dma_dst_bid_q;
    logic [1:0]                dma_dst_bresp_q;
    logic                      dma_dst_bvalid_q;
    int unsigned               dma_dst_b_delay_q;

    logic                      dma_dst_inject_enable_q;
    int unsigned               dma_dst_inject_base_aw_count;

    int unsigned               dma_dst_aw_count;
    int unsigned               dma_dst_w_count;
    int unsigned               dma_dst_b_count;

    wire dma_dst_aw_fire = dma_dst_axi_awvalid && dma_dst_axi_awready;
    wire dma_dst_w_fire  = dma_dst_axi_wvalid  && dma_dst_axi_wready;
    wire dma_dst_b_fire  = dma_dst_axi_bvalid  && dma_dst_axi_bready;

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
        .DMA_SRC_MEM_BYTES (DMA_SRC_MEM_BYTES),
        .DMA_DST_MEM_BYTES (DMA_DST_MEM_BYTES)
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
    // AXIS source AXI read response model connections
    // ============================================================
    assign axis_src_axi_arready = dma_rst_n &&
                                  !axis_src_rd_pending_valid &&
                                  !axis_src_rvalid_q;

    assign axis_src_axi_rid     = axis_src_rid_q;
    assign axis_src_axi_rdata   = axis_src_rdata_q;
    assign axis_src_axi_rresp   = axis_src_rresp_q;
    assign axis_src_axi_rlast   = axis_src_rlast_q;
    assign axis_src_axi_rvalid  = axis_src_rvalid_q;

    // ============================================================
    // Direct-stream source AXI read response model connections
    // ============================================================
    assign ds_src_axi_arready = dma_rst_n &&
                                !ds_src_rd_pending_valid &&
                                !ds_src_rvalid_q;

    assign ds_src_axi_rid     = ds_src_rid_q;
    assign ds_src_axi_rdata   = ds_src_rdata_q;
    assign ds_src_axi_rresp   = ds_src_rresp_q;
    assign ds_src_axi_rlast   = ds_src_rlast_q;
    assign ds_src_axi_rvalid  = ds_src_rvalid_q;    

    // ============================================================
    // DMA destination AXI write response model connections
    //
    // v1 assumptions:
    //   - single outstanding write
    //   - single-beat AW only, AWLEN must be 0
    //   - AW and W may handshake in either order
    //   - WSTRB controls byte writes
    // ============================================================
    assign dma_dst_axi_awready = dma_rst_n &&
                                 !dma_dst_aw_pending_valid &&
                                 !dma_dst_bvalid_q;

    assign dma_dst_axi_wready  = dma_rst_n &&
                                 !dma_dst_w_pending_valid &&
                                 !dma_dst_bvalid_q;

    assign dma_dst_axi_bid     = dma_dst_bid_q;
    assign dma_dst_axi_bresp   = dma_dst_bresp_q;
    assign dma_dst_axi_bvalid  = dma_dst_bvalid_q;

    // ============================================================
    // Shared source memory helper functions
    // ============================================================
    function automatic int unsigned src_byte_index(
        input logic [ADDR_WIDTH-1:0] addr
    );
        return int'(addr);
    endfunction

    function automatic logic [DATA_WIDTH-1:0] src_pack_word(
        input logic [ADDR_WIDTH-1:0] addr
    );
        logic [DATA_WIDTH-1:0] word;
        int unsigned base_idx;
        int unsigned lane;
    begin
        word     = '0;
        base_idx = src_byte_index(addr);

        for (lane = 0; lane < BYTES_PER_BEAT; lane++) begin
            if ((base_idx + lane) < DMA_SRC_MEM_BYTES) begin
                word[8*lane +: 8] = ctrl_if.dma_src_mem[base_idx + lane];
            end
        end

        return word;
    end
    endfunction

    // ============================================================
    // DMA destination memory helper tasks/functions
    // ============================================================
    function automatic int unsigned dma_dst_byte_index(
        input logic [ADDR_WIDTH-1:0] addr
    );
        return int'(addr);
    endfunction

    function automatic logic [1:0] dma_dst_next_bresp(
        input int unsigned aw_beat_idx
    );
        int signed rel_beat;
    begin
        if (aw_beat_idx >= dma_dst_inject_base_aw_count) begin
            rel_beat = int'(aw_beat_idx - dma_dst_inject_base_aw_count);
        end
        else begin
            rel_beat = -1;
        end

        if (ctrl_if.dma_dst_inject_bresp_error &&
            (ctrl_if.dma_dst_inject_bresp_error_beat >= 0) &&
            (rel_beat == ctrl_if.dma_dst_inject_bresp_error_beat)) begin
            return AXI_RESP_SLVERR;
        end

        return AXI_RESP_OKAY;
    end
    endfunction

    task automatic dma_dst_apply_write(
        input logic [ADDR_WIDTH-1:0]   addr,
        input logic [DATA_WIDTH-1:0]   data,
        input logic [DATA_WIDTH/8-1:0] strb
    );
        int unsigned base_idx;
        int unsigned lane;
    begin
        base_idx = dma_dst_byte_index(addr);

        if ((base_idx + BYTES_PER_BEAT) > DMA_DST_MEM_BYTES) begin
            $fatal(1,
                "[UVM_TOP_DMA_DST] DMA destination write out of range: addr=0x%08h idx=%0d depth=%0d",
                addr, base_idx, DMA_DST_MEM_BYTES
            );
        end

        for (lane = 0; lane < BYTES_PER_BEAT; lane++) begin
            if (strb[lane]) begin
                ctrl_if.dma_dst_mem[base_idx + lane] = data[8*lane +: 8];
            end
        end
    end
    endtask

    // ============================================================
    // DMA source AXI read responder
    // ============================================================
    always_ff @(posedge dma_clk or negedge dma_rst_n) begin
        if (!dma_rst_n) begin
            dma_src_rd_pending_valid      <= 1'b0;
            dma_src_rd_pending_addr       <= '0;
            dma_src_rd_pending_id         <= '0;
            dma_src_rd_pending_delay      <= 0;
            dma_src_rd_pending_beat_idx   <= 0;

            dma_src_inject_enable_q       <= 1'b0;
            dma_src_inject_base_ar_count  <= 0;

            dma_src_rid_q                 <= '0;
            dma_src_rdata_q               <= '0;
            dma_src_rresp_q               <= AXI_RESP_OKAY;
            dma_src_rlast_q               <= 1'b0;
            dma_src_rvalid_q              <= 1'b0;

            dma_src_ar_count              <= 0;
            dma_src_r_count               <= 0;
        end
        else begin
            dma_src_inject_enable_q <= ctrl_if.dma_src_inject_rresp_error;

            if (ctrl_if.dma_src_inject_rresp_error &&
                !dma_src_inject_enable_q) begin
                dma_src_inject_base_ar_count <= dma_src_ar_count;
            end

            if (dma_src_ar_fire) begin
                int unsigned ar_base_idx;

                ar_base_idx = src_byte_index(dma_src_axi_araddr);

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

                dma_src_rd_pending_valid    <= 1'b1;
                dma_src_rd_pending_addr     <= dma_src_axi_araddr;
                dma_src_rd_pending_id       <= dma_src_axi_arid;
                dma_src_rd_pending_delay    <= DMA_SRC_READ_LATENCY_CYCLES;
                dma_src_rd_pending_beat_idx <= dma_src_ar_count;

                dma_src_ar_count            <= dma_src_ar_count + 1;
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
                dma_src_rdata_q  <= src_pack_word(dma_src_rd_pending_addr);

                if (ctrl_if.dma_src_inject_rresp_error &&
                    (ctrl_if.dma_src_inject_rresp_error_beat >= 0) &&
                    (dma_src_rd_pending_beat_idx >= dma_src_inject_base_ar_count) &&
                    (int'(dma_src_rd_pending_beat_idx - dma_src_inject_base_ar_count) ==
                        ctrl_if.dma_src_inject_rresp_error_beat)) begin

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
    // AXIS source AXI read responder
    //
    // v1 assumptions:
    //   - single outstanding read
    //   - single-beat AR only, ARLEN must be 0
    //   - byte-addressed source memory
    //   - uses ctrl_if.dma_src_mem[] as source storage
    // ============================================================
    always_ff @(posedge dma_clk or negedge dma_rst_n) begin
        if (!dma_rst_n) begin
            axis_src_rd_pending_valid      <= 1'b0;
            axis_src_rd_pending_addr       <= '0;
            axis_src_rd_pending_id         <= '0;
            axis_src_rd_pending_delay      <= 0;
            axis_src_rd_pending_beat_idx   <= 0;

            axis_src_inject_enable_q       <= 1'b0;
            axis_src_inject_base_ar_count  <= 0;

            axis_src_rid_q                 <= '0;
            axis_src_rdata_q               <= '0;
            axis_src_rresp_q               <= AXI_RESP_OKAY;
            axis_src_rlast_q               <= 1'b0;
            axis_src_rvalid_q              <= 1'b0;

            axis_src_ar_count              <= 0;
            axis_src_r_count               <= 0;
        end
        else begin
            axis_src_inject_enable_q <= ctrl_if.axis_src_inject_rresp_error;

            if (ctrl_if.axis_src_inject_rresp_error &&
                !axis_src_inject_enable_q) begin
                axis_src_inject_base_ar_count <= axis_src_ar_count;
            end

            if (axis_src_ar_fire) begin
                int unsigned ar_base_idx;

                ar_base_idx = src_byte_index(axis_src_axi_araddr);

                if (axis_src_axi_arlen !== 8'd0) begin
                    $fatal(1,
                        "[UVM_TOP_AXIS_SRC] Unsupported AXIS source ARLEN=%0d, expected 0",
                        axis_src_axi_arlen
                    );
                end

                if ((ar_base_idx + BYTES_PER_BEAT) > DMA_SRC_MEM_BYTES) begin
                    $fatal(1,
                        "[UVM_TOP_AXIS_SRC] AXIS source read out of range: addr=0x%08h idx=%0d depth=%0d",
                        axis_src_axi_araddr, ar_base_idx, DMA_SRC_MEM_BYTES
                    );
                end

                axis_src_rd_pending_valid    <= 1'b1;
                axis_src_rd_pending_addr     <= axis_src_axi_araddr;
                axis_src_rd_pending_id       <= axis_src_axi_arid;
                axis_src_rd_pending_delay    <= AXIS_SRC_READ_LATENCY_CYCLES;
                axis_src_rd_pending_beat_idx <= axis_src_ar_count;

                axis_src_ar_count            <= axis_src_ar_count + 1;
            end
            else if (axis_src_rd_pending_valid && (axis_src_rd_pending_delay != 0)) begin
                axis_src_rd_pending_delay <= axis_src_rd_pending_delay - 1;
            end

            if (axis_src_r_fire) begin
                axis_src_rvalid_q <= 1'b0;
                axis_src_rlast_q  <= 1'b0;
                axis_src_rresp_q  <= AXI_RESP_OKAY;
                axis_src_rdata_q  <= '0;
                axis_src_rid_q    <= '0;

                axis_src_r_count  <= axis_src_r_count + 1;
            end

            if (!axis_src_rvalid_q &&
                axis_src_rd_pending_valid &&
                (axis_src_rd_pending_delay == 0)) begin

                axis_src_rvalid_q <= 1'b1;
                axis_src_rlast_q  <= 1'b1;
                axis_src_rid_q    <= axis_src_rd_pending_id;
                axis_src_rdata_q  <= src_pack_word(axis_src_rd_pending_addr);

                if (ctrl_if.axis_src_inject_rresp_error &&
                    (ctrl_if.axis_src_inject_rresp_error_beat >= 0) &&
                    (axis_src_rd_pending_beat_idx >= axis_src_inject_base_ar_count) &&
                    (int'(axis_src_rd_pending_beat_idx - axis_src_inject_base_ar_count) ==
                        ctrl_if.axis_src_inject_rresp_error_beat)) begin

                    axis_src_rresp_q <= AXI_RESP_SLVERR;
                end
                else begin
                    axis_src_rresp_q <= AXI_RESP_OKAY;
                end

                axis_src_rd_pending_valid <= 1'b0;
            end
        end
    end

    // ============================================================
    // Direct-stream source AXI read responder
    //
    // v1 assumptions:
    //   - single outstanding read
    //   - single-beat AR only, ARLEN must be 0
    //   - byte-addressed source memory
    //   - uses ctrl_if.dma_src_mem[] as source storage
    //   - independent RRESP injection through ds_src_set_rresp_error()
    // ============================================================
    always_ff @(posedge dma_clk or negedge dma_rst_n) begin
        if (!dma_rst_n) begin
            ds_src_rd_pending_valid      <= 1'b0;
            ds_src_rd_pending_addr       <= '0;
            ds_src_rd_pending_id         <= '0;
            ds_src_rd_pending_delay      <= 0;
            ds_src_rd_pending_beat_idx   <= 0;

            ds_src_inject_enable_q       <= 1'b0;
            ds_src_inject_base_ar_count  <= 0;

            ds_src_rid_q                 <= '0;
            ds_src_rdata_q               <= '0;
            ds_src_rresp_q               <= AXI_RESP_OKAY;
            ds_src_rlast_q               <= 1'b0;
            ds_src_rvalid_q              <= 1'b0;

            ds_src_ar_count              <= 0;
            ds_src_r_count               <= 0;
        end
        else begin
            ds_src_inject_enable_q <= ctrl_if.ds_src_inject_rresp_error;

            if (ctrl_if.ds_src_inject_rresp_error &&
                !ds_src_inject_enable_q) begin
                ds_src_inject_base_ar_count <= ds_src_ar_count;
            end

            if (ds_src_ar_fire) begin
                int unsigned ar_base_idx;

                ar_base_idx = src_byte_index(ds_src_axi_araddr);

                if (ds_src_axi_arlen !== 8'd0) begin
                    $fatal(1,
                        "[UVM_TOP_DS_SRC] Unsupported direct-stream source ARLEN=%0d, expected 0",
                        ds_src_axi_arlen
                    );
                end

                if ((ar_base_idx + BYTES_PER_BEAT) > DMA_SRC_MEM_BYTES) begin
                    $fatal(1,
                        "[UVM_TOP_DS_SRC] Direct-stream source read out of range: addr=0x%08h idx=%0d depth=%0d",
                        ds_src_axi_araddr, ar_base_idx, DMA_SRC_MEM_BYTES
                    );
                end

                ds_src_rd_pending_valid    <= 1'b1;
                ds_src_rd_pending_addr     <= ds_src_axi_araddr;
                ds_src_rd_pending_id       <= ds_src_axi_arid;
                ds_src_rd_pending_delay    <= DS_SRC_READ_LATENCY_CYCLES;
                ds_src_rd_pending_beat_idx <= ds_src_ar_count;

                ds_src_ar_count            <= ds_src_ar_count + 1;
            end
            else if (ds_src_rd_pending_valid && (ds_src_rd_pending_delay != 0)) begin
                ds_src_rd_pending_delay <= ds_src_rd_pending_delay - 1;
            end

            if (ds_src_r_fire) begin
                ds_src_rvalid_q <= 1'b0;
                ds_src_rlast_q  <= 1'b0;
                ds_src_rresp_q  <= AXI_RESP_OKAY;
                ds_src_rdata_q  <= '0;
                ds_src_rid_q    <= '0;

                ds_src_r_count  <= ds_src_r_count + 1;
            end

            if (!ds_src_rvalid_q &&
                ds_src_rd_pending_valid &&
                (ds_src_rd_pending_delay == 0)) begin

                ds_src_rvalid_q <= 1'b1;
                ds_src_rlast_q  <= 1'b1;
                ds_src_rid_q    <= ds_src_rd_pending_id;
                ds_src_rdata_q  <= src_pack_word(ds_src_rd_pending_addr);

                if (ctrl_if.ds_src_inject_rresp_error &&
                    (ctrl_if.ds_src_inject_rresp_error_beat >= 0) &&
                    (ds_src_rd_pending_beat_idx >= ds_src_inject_base_ar_count) &&
                    (int'(ds_src_rd_pending_beat_idx - ds_src_inject_base_ar_count) ==
                        ctrl_if.ds_src_inject_rresp_error_beat)) begin

                    ds_src_rresp_q <= AXI_RESP_SLVERR;
                end
                else begin
                    ds_src_rresp_q <= AXI_RESP_OKAY;
                end

                ds_src_rd_pending_valid <= 1'b0;
            end
        end
    end

    // ============================================================
    // DMA destination AXI write responder
    // ============================================================
    always_ff @(posedge dma_clk or negedge dma_rst_n) begin
        if (!dma_rst_n) begin
            dma_dst_aw_pending_valid       <= 1'b0;
            dma_dst_aw_pending_id          <= '0;
            dma_dst_aw_pending_addr        <= '0;
            dma_dst_aw_pending_beat_idx    <= 0;

            dma_dst_w_pending_valid        <= 1'b0;
            dma_dst_w_pending_data         <= '0;
            dma_dst_w_pending_strb         <= '0;
            dma_dst_w_pending_last         <= 1'b0;

            dma_dst_bid_q                  <= '0;
            dma_dst_bresp_q                <= AXI_RESP_OKAY;
            dma_dst_bvalid_q               <= 1'b0;
            dma_dst_b_delay_q              <= 0;

            dma_dst_inject_enable_q        <= 1'b0;
            dma_dst_inject_base_aw_count   <= 0;

            dma_dst_aw_count               <= 0;
            dma_dst_w_count                <= 0;
            dma_dst_b_count                <= 0;
        end
        else begin
            dma_dst_inject_enable_q <= ctrl_if.dma_dst_inject_bresp_error;

            if (ctrl_if.dma_dst_inject_bresp_error &&
                !dma_dst_inject_enable_q) begin
                dma_dst_inject_base_aw_count <= dma_dst_aw_count;
            end

            if (dma_dst_aw_fire) begin
                int unsigned aw_base_idx;

                aw_base_idx = dma_dst_byte_index(dma_dst_axi_awaddr);

                if (dma_dst_axi_awlen !== 8'd0) begin
                    $fatal(1,
                        "[UVM_TOP_DMA_DST] Unsupported DMA destination AWLEN=%0d, expected 0",
                        dma_dst_axi_awlen
                    );
                end

                if ((aw_base_idx + BYTES_PER_BEAT) > DMA_DST_MEM_BYTES) begin
                    $fatal(1,
                        "[UVM_TOP_DMA_DST] DMA destination AW out of range: addr=0x%08h idx=%0d depth=%0d",
                        dma_dst_axi_awaddr, aw_base_idx, DMA_DST_MEM_BYTES
                    );
                end

                dma_dst_aw_pending_valid    <= 1'b1;
                dma_dst_aw_pending_id       <= dma_dst_axi_awid;
                dma_dst_aw_pending_addr     <= dma_dst_axi_awaddr;
                dma_dst_aw_pending_beat_idx <= dma_dst_aw_count;

                dma_dst_aw_count            <= dma_dst_aw_count + 1;
            end

            if (dma_dst_w_fire) begin
                if (dma_dst_axi_wlast !== 1'b1) begin
                    $fatal(1,
                        "[UVM_TOP_DMA_DST] Unsupported DMA destination WLAST=0, expected single-beat WLAST=1"
                    );
                end

                dma_dst_w_pending_valid <= 1'b1;
                dma_dst_w_pending_data  <= dma_dst_axi_wdata;
                dma_dst_w_pending_strb  <= dma_dst_axi_wstrb;
                dma_dst_w_pending_last  <= dma_dst_axi_wlast;

                dma_dst_w_count         <= dma_dst_w_count + 1;
            end

            if (dma_dst_b_fire) begin
                dma_dst_bvalid_q <= 1'b0;
                dma_dst_bresp_q  <= AXI_RESP_OKAY;
                dma_dst_bid_q    <= '0;

                dma_dst_b_count  <= dma_dst_b_count + 1;
            end

            if (!dma_dst_bvalid_q) begin
                logic aw_valid_now;
                logic [ID_WIDTH-1:0] aw_id_now;
                logic [ADDR_WIDTH-1:0] aw_addr_now;
                int unsigned aw_beat_idx_now;

                logic w_valid_now;
                logic [DATA_WIDTH-1:0] w_data_now;
                logic [DATA_WIDTH/8-1:0] w_strb_now;

                aw_valid_now     = dma_dst_aw_pending_valid || dma_dst_aw_fire;
                aw_id_now        = dma_dst_aw_fire ? dma_dst_axi_awid   : dma_dst_aw_pending_id;
                aw_addr_now      = dma_dst_aw_fire ? dma_dst_axi_awaddr : dma_dst_aw_pending_addr;
                aw_beat_idx_now  = dma_dst_aw_fire ? dma_dst_aw_count   : dma_dst_aw_pending_beat_idx;

                w_valid_now      = dma_dst_w_pending_valid || dma_dst_w_fire;
                w_data_now       = dma_dst_w_fire ? dma_dst_axi_wdata : dma_dst_w_pending_data;
                w_strb_now       = dma_dst_w_fire ? dma_dst_axi_wstrb : dma_dst_w_pending_strb;

                if (aw_valid_now && w_valid_now) begin
                    if (dma_dst_b_delay_q < DMA_DST_WRITE_RESP_LATENCY_CYCLES) begin
                        dma_dst_b_delay_q <= dma_dst_b_delay_q + 1;
                    end
                    else begin
                        dma_dst_apply_write(
                            aw_addr_now,
                            w_data_now,
                            w_strb_now
                        );

                        dma_dst_bid_q    <= aw_id_now;
                        dma_dst_bresp_q  <= dma_dst_next_bresp(aw_beat_idx_now);
                        dma_dst_bvalid_q <= 1'b1;

                        dma_dst_aw_pending_valid    <= 1'b0;
                        dma_dst_aw_pending_id       <= '0;
                        dma_dst_aw_pending_addr     <= '0;
                        dma_dst_aw_pending_beat_idx <= 0;

                        dma_dst_w_pending_valid <= 1'b0;
                        dma_dst_w_pending_data  <= '0;
                        dma_dst_w_pending_strb  <= '0;
                        dma_dst_w_pending_last  <= 1'b0;

                        dma_dst_b_delay_q <= 0;
                    end
                end
                else begin
                    dma_dst_b_delay_q <= 0;
                end
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
        .GEMM_DIM_WIDTH  (GEMM_DIM_WIDTH),
        .GEMM_MAC_LANES  (GEMM_MAC_LANES),
        .GEMM_ENABLE_B_CACHE (GEMM_ENABLE_B_CACHE),
        .GEMM_ENABLE_PACKED_BCACHE_PRELOAD (GEMM_ENABLE_PACKED_BCACHE_PRELOAD),
        .GEMM_ENABLE_A_ROW_CACHE (GEMM_ENABLE_A_ROW_CACHE),
        .GEMM_A_ROW_CACHE_MAX_K (GEMM_A_ROW_CACHE_MAX_K),
        .GEMM_ENABLE_PACKED_A_ROW_PRELOAD (GEMM_ENABLE_PACKED_A_ROW_PRELOAD)
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

        // DMA store control through ctrl_if
        .dma_store_start          (ctrl_if.dma_store_start),
        .dma_store_src_base_addr  (ctrl_if.dma_store_src_base_addr),
        .dma_store_dst_base_addr  (ctrl_if.dma_store_dst_base_addr),
        .dma_store_byte_count     (ctrl_if.dma_store_byte_count),

        .dma_store_busy           (dma_store_busy),
        .dma_store_done           (dma_store_done),
        .dma_store_error          (dma_store_error),

        // AXI-Stream preload control through ctrl_if
        .axis_load_start          (ctrl_if.axis_load_start),
        .axis_src_base_addr       (ctrl_if.axis_src_base_addr),
        .axis_dst_base_addr       (ctrl_if.axis_dst_base_addr),
        .axis_load_beats          (ctrl_if.axis_load_beats),

        .axis_load_busy           (axis_load_busy),
        .axis_load_done           (axis_load_done),
        .axis_load_error          (axis_load_error),

        // Direct-stream preload control through ctrl_if
        .ds_load_start           (ctrl_if.ds_load_start),
        .ds_src_base_addr        (ctrl_if.ds_src_base_addr),
        .ds_dst_base_addr        (ctrl_if.ds_dst_base_addr),
        .ds_load_beats           (ctrl_if.ds_load_beats),
        .ds_operand_sel          (ctrl_if.ds_operand_sel),

        .ds_load_busy            (ds_load_busy),
        .ds_load_done            (ds_load_done),
        .ds_load_error           (ds_load_error),

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

        // AXI-Stream preload source AXI-MM read master port
        .axis_src_axi_arid    (axis_src_axi_arid),
        .axis_src_axi_araddr  (axis_src_axi_araddr),
        .axis_src_axi_arlen   (axis_src_axi_arlen),
        .axis_src_axi_arsize  (axis_src_axi_arsize),
        .axis_src_axi_arburst (axis_src_axi_arburst),
        .axis_src_axi_arvalid (axis_src_axi_arvalid),
        .axis_src_axi_arready (axis_src_axi_arready),

        .axis_src_axi_rid     (axis_src_axi_rid),
        .axis_src_axi_rdata   (axis_src_axi_rdata),
        .axis_src_axi_rresp   (axis_src_axi_rresp),
        .axis_src_axi_rlast   (axis_src_axi_rlast),
        .axis_src_axi_rvalid  (axis_src_axi_rvalid),
        .axis_src_axi_rready  (axis_src_axi_rready),

        // Direct-stream preload source AXI-MM read master port
        .ds_src_axi_arid     (ds_src_axi_arid),
        .ds_src_axi_araddr   (ds_src_axi_araddr),
        .ds_src_axi_arlen    (ds_src_axi_arlen),
        .ds_src_axi_arsize   (ds_src_axi_arsize),
        .ds_src_axi_arburst  (ds_src_axi_arburst),
        .ds_src_axi_arvalid  (ds_src_axi_arvalid),
        .ds_src_axi_arready  (ds_src_axi_arready),

        .ds_src_axi_rid      (ds_src_axi_rid),
        .ds_src_axi_rdata    (ds_src_axi_rdata),
        .ds_src_axi_rresp    (ds_src_axi_rresp),
        .ds_src_axi_rlast    (ds_src_axi_rlast),
        .ds_src_axi_rvalid   (ds_src_axi_rvalid),
        .ds_src_axi_rready   (ds_src_axi_rready),

        // DMA destination AXI-MM write master port
        .dma_dst_axi_awid     (dma_dst_axi_awid),
        .dma_dst_axi_awaddr   (dma_dst_axi_awaddr),
        .dma_dst_axi_awlen    (dma_dst_axi_awlen),
        .dma_dst_axi_awsize   (dma_dst_axi_awsize),
        .dma_dst_axi_awburst  (dma_dst_axi_awburst),
        .dma_dst_axi_awvalid  (dma_dst_axi_awvalid),
        .dma_dst_axi_awready  (dma_dst_axi_awready),

        .dma_dst_axi_wdata    (dma_dst_axi_wdata),
        .dma_dst_axi_wstrb    (dma_dst_axi_wstrb),
        .dma_dst_axi_wlast    (dma_dst_axi_wlast),
        .dma_dst_axi_wvalid   (dma_dst_axi_wvalid),
        .dma_dst_axi_wready   (dma_dst_axi_wready),

        .dma_dst_axi_bid      (dma_dst_axi_bid),
        .dma_dst_axi_bresp    (dma_dst_axi_bresp),
        .dma_dst_axi_bvalid   (dma_dst_axi_bvalid),
        .dma_dst_axi_bready   (dma_dst_axi_bready),

        // Accelerator control
        .gemm_input_stream_mode (ctrl_if.gemm_input_stream_mode),

        .acc_start              (ctrl_if.acc_start),
        .acc_busy               (acc_busy),
        .acc_done               (acc_done),

        .base_addr_a            (ctrl_if.base_addr_a),
        .base_addr_b            (ctrl_if.base_addr_b),
        .base_addr_c            (ctrl_if.base_addr_c),

        .dim_m                  (ctrl_if.dim_m),
        .dim_n                  (ctrl_if.dim_n),
        .dim_k                  (ctrl_if.dim_k),

        // GEMM performance counters
        .gemm_perf_busy_cycles  (gemm_perf_busy_cycles),
        .gemm_perf_mac_count    (gemm_perf_mac_count),
        .gemm_perf_output_count (gemm_perf_output_count)        
    );

    // ============================================================
    // Connect DUT status/reset observation into ctrl_if
    // ============================================================
    assign ctrl_if.dma_rst_n  = dma_rst_n;
    assign ctrl_if.core_rst_n = core_rst_n;

    assign ctrl_if.acc_busy   = acc_busy;
    assign ctrl_if.acc_done   = acc_done;

    assign ctrl_if.gemm_perf_busy_cycles  = gemm_perf_busy_cycles;
    assign ctrl_if.gemm_perf_mac_count    = gemm_perf_mac_count;
    assign ctrl_if.gemm_perf_output_count = gemm_perf_output_count;

    assign ctrl_if.dma_load_busy  = dma_load_busy;
    assign ctrl_if.dma_load_done  = dma_load_done;
    assign ctrl_if.dma_load_error = dma_load_error;

    assign ctrl_if.dma_store_busy  = dma_store_busy;
    assign ctrl_if.dma_store_done  = dma_store_done;
    assign ctrl_if.dma_store_error = dma_store_error;

    assign ctrl_if.axis_load_busy  = axis_load_busy;
    assign ctrl_if.axis_load_done  = axis_load_done;
    assign ctrl_if.axis_load_error = axis_load_error;

    assign ctrl_if.ds_load_busy  = ds_load_busy;
    assign ctrl_if.ds_load_done  = ds_load_done;
    assign ctrl_if.ds_load_error = ds_load_error;


    // ============================================================
    // GEMM config display
    // ============================================================
    initial begin
        $display("# [UVM_TOP_CFG] GEMM_MAC_LANES=%0d GEMM_ENABLE_B_CACHE=%0d GEMM_ENABLE_PACKED_BCACHE_PRELOAD=%0d GEMM_ENABLE_A_ROW_CACHE=%0d GEMM_A_ROW_CACHE_MAX_K=%0d GEMM_ENABLE_PACKED_A_ROW_PRELOAD=%0d",
                GEMM_MAC_LANES,
                GEMM_ENABLE_B_CACHE,
                GEMM_ENABLE_PACKED_BCACHE_PRELOAD,
                GEMM_ENABLE_A_ROW_CACHE,
                GEMM_A_ROW_CACHE_MAX_K,
                GEMM_ENABLE_PACKED_A_ROW_PRELOAD);
    end

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
        dma_clk_period_ns  = 10.0;
        core_clk_period_ns = 14.0;

        void'($value$plusargs("DMA_CLK_PERIOD_NS=%f",  dma_clk_period_ns));
        void'($value$plusargs("CORE_CLK_PERIOD_NS=%f", core_clk_period_ns));

        if (dma_clk_period_ns <= 0.0) begin
            $fatal(1,
                "[UVM_TOP_CLK] Invalid DMA_CLK_PERIOD_NS=%0.3f",
                dma_clk_period_ns
            );
        end

        if (core_clk_period_ns <= 0.0) begin
            $fatal(1,
                "[UVM_TOP_CLK] Invalid CORE_CLK_PERIOD_NS=%0.3f",
                core_clk_period_ns
            );
        end

        $display("[UVM_TOP_CLK] dma_clk_period_ns=%0.3f core_clk_period_ns=%0.3f",
            dma_clk_period_ns,
            core_clk_period_ns
        );

        dma_clk  = 1'b0;
        core_clk = 1'b0;

        fork
            forever #(dma_clk_period_ns  / 2.0) dma_clk  = ~dma_clk;
            forever #(core_clk_period_ns / 2.0) core_clk = ~core_clk;
        join
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
        ctrl_if.gemm_input_stream_mode = 1'b0;

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

        // DMA store defaults
        ctrl_if.dma_store_start         = 1'b0;
        ctrl_if.dma_store_src_base_addr = '0;
        ctrl_if.dma_store_dst_base_addr = '0;
        ctrl_if.dma_store_byte_count    = '0;

        // AXI-Stream preload defaults
        ctrl_if.axis_load_start    = 1'b0;
        ctrl_if.axis_src_base_addr = '0;
        ctrl_if.axis_dst_base_addr = '0;
        ctrl_if.axis_load_beats    = '0;

        // Direct-stream preload defaults
        ctrl_if.ds_load_start    = 1'b0;
        ctrl_if.ds_src_base_addr = '0;
        ctrl_if.ds_dst_base_addr = '0;
        ctrl_if.ds_load_beats    = '0;
        ctrl_if.ds_operand_sel   = 1'b0;

        // reset override defaults
        ctrl_if.tb_reset_override_en   = 1'b0;
        ctrl_if.tb_dma_rst_n_override  = 1'b1;
        ctrl_if.tb_core_rst_n_override = 1'b1;

        // source memory model defaults
        ctrl_if.dma_src_mem_clear();
        ctrl_if.dma_src_set_rresp_error(1'b0, -1);
        ctrl_if.axis_src_set_rresp_error(1'b0, -1);
        
        ctrl_if.ds_src_set_rresp_error(1'b0, -1);

        // DMA destination memory model defaults
        ctrl_if.dma_dst_mem_clear();
        ctrl_if.dma_dst_set_bresp_error(1'b0, -1);

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