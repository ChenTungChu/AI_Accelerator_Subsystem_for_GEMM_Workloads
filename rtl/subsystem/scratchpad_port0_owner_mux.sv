// File: rtl/subsystem/scratchpad_port0_owner_mux.sv
`ifndef SCRATCHPAD_PORT0_OWNER_MUX_SV
`define SCRATCHPAD_PORT0_OWNER_MUX_SV

module scratchpad_port0_owner_mux #(
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 64,
    parameter int ID_WIDTH     = 4
)(
    // ------------------------------------------------------------
    // Owner select
    //
    // select_dma = 0:
    //   external host axi0_if owns BRAM Port0
    //
    // select_dma = 1:
    //   DMA load engine write path owns BRAM Port0
    //
    // v1 rule:
    //   select_dma must only change when Port0 is idle.
    //   No arbitration / outstanding tracking is done here.
    // ------------------------------------------------------------
    input  logic select_dma,

    // ------------------------------------------------------------
    // Host-side AXI-MM interface
    //   Mux behaves as a slave toward the external host.
    // ------------------------------------------------------------
    axi_mm_if.mp_slave host_axi_if,

    // ------------------------------------------------------------
    // BRAM-side AXI-MM interface
    //   Mux behaves as a master toward BRAM Port0.
    // ------------------------------------------------------------
    axi_mm_if.mp_master bram_axi_if,

    // ------------------------------------------------------------
    // DMA load engine scratchpad write-side master
    //
    // v1:
    //   - write channel only
    //   - read channel disabled while DMA owns Port0
    // ------------------------------------------------------------
    input  logic [ID_WIDTH-1:0]      dma_awid,
    input  logic [ADDR_WIDTH-1:0]    dma_awaddr,
    input  logic [7:0]               dma_awlen,
    input  logic [2:0]               dma_awsize,
    input  logic [1:0]               dma_awburst,
    input  logic                     dma_awvalid,
    output logic                     dma_awready,

    input  logic [DATA_WIDTH-1:0]    dma_wdata,
    input  logic [DATA_WIDTH/8-1:0]  dma_wstrb,
    input  logic                     dma_wlast,
    input  logic                     dma_wvalid,
    output logic                     dma_wready,

    output logic [ID_WIDTH-1:0]      dma_bid,
    output logic [1:0]               dma_bresp,
    output logic                     dma_bvalid,
    input  logic                     dma_bready
);

    // ============================================================
    // BRAM-facing request mux
    // ============================================================

    // ------------------------------------------------------------
    // Write address channel
    // ------------------------------------------------------------
    assign bram_axi_if.awid    = select_dma ? dma_awid    : host_axi_if.awid;
    assign bram_axi_if.awaddr  = select_dma ? dma_awaddr  : host_axi_if.awaddr;
    assign bram_axi_if.awlen   = select_dma ? dma_awlen   : host_axi_if.awlen;
    assign bram_axi_if.awsize  = select_dma ? dma_awsize  : host_axi_if.awsize;
    assign bram_axi_if.awburst = select_dma ? dma_awburst : host_axi_if.awburst;
    assign bram_axi_if.awvalid = select_dma ? dma_awvalid : host_axi_if.awvalid;

    // ------------------------------------------------------------
    // Write data channel
    // ------------------------------------------------------------
    assign bram_axi_if.wdata   = select_dma ? dma_wdata   : host_axi_if.wdata;
    assign bram_axi_if.wstrb   = select_dma ? dma_wstrb   : host_axi_if.wstrb;
    assign bram_axi_if.wlast   = select_dma ? dma_wlast   : host_axi_if.wlast;
    assign bram_axi_if.wvalid  = select_dma ? dma_wvalid  : host_axi_if.wvalid;

    // ------------------------------------------------------------
    // Write response ready
    // ------------------------------------------------------------
    assign bram_axi_if.bready  = select_dma ? dma_bready  : host_axi_if.bready;

    // ------------------------------------------------------------
    // Read address channel
    //
    // DMA load v1 does not use Port0 read path.
    // During DMA ownership, read channel is held inactive.
    // ------------------------------------------------------------
    assign bram_axi_if.arid    = select_dma ? '0 : host_axi_if.arid;
    assign bram_axi_if.araddr  = select_dma ? '0 : host_axi_if.araddr;
    assign bram_axi_if.arlen   = select_dma ? '0 : host_axi_if.arlen;
    assign bram_axi_if.arsize  = select_dma ? '0 : host_axi_if.arsize;
    assign bram_axi_if.arburst = select_dma ? '0 : host_axi_if.arburst;
    assign bram_axi_if.arvalid = select_dma ? 1'b0 : host_axi_if.arvalid;

    // ------------------------------------------------------------
    // Read response ready
    // ------------------------------------------------------------
    assign bram_axi_if.rready  = select_dma ? 1'b0 : host_axi_if.rready;

    // ============================================================
    // Host-facing response path
    // ============================================================

    // ------------------------------------------------------------
    // Write address/data ready back to host
    // ------------------------------------------------------------
    assign host_axi_if.awready = select_dma ? 1'b0 : bram_axi_if.awready;
    assign host_axi_if.wready  = select_dma ? 1'b0 : bram_axi_if.wready;

    // ------------------------------------------------------------
    // Write response back to host
    // ------------------------------------------------------------
    assign host_axi_if.bid     = select_dma ? '0   : bram_axi_if.bid;
    assign host_axi_if.bresp   = select_dma ? '0   : bram_axi_if.bresp;
    assign host_axi_if.bvalid  = select_dma ? 1'b0 : bram_axi_if.bvalid;

    // ------------------------------------------------------------
    // Read address ready back to host
    // ------------------------------------------------------------
    assign host_axi_if.arready = select_dma ? 1'b0 : bram_axi_if.arready;

    // ------------------------------------------------------------
    // Read response back to host
    // ------------------------------------------------------------
    assign host_axi_if.rid     = select_dma ? '0   : bram_axi_if.rid;
    assign host_axi_if.rdata   = select_dma ? '0   : bram_axi_if.rdata;
    assign host_axi_if.rresp   = select_dma ? '0   : bram_axi_if.rresp;
    assign host_axi_if.rlast   = select_dma ? 1'b0 : bram_axi_if.rlast;
    assign host_axi_if.rvalid  = select_dma ? 1'b0 : bram_axi_if.rvalid;

    // ============================================================
    // DMA-facing response path
    // ============================================================

    // ------------------------------------------------------------
    // Write address/data ready back to DMA
    // ------------------------------------------------------------
    assign dma_awready = select_dma ? bram_axi_if.awready : 1'b0;
    assign dma_wready  = select_dma ? bram_axi_if.wready  : 1'b0;

    // ------------------------------------------------------------
    // Write response back to DMA
    // ------------------------------------------------------------
    assign dma_bid     = select_dma ? bram_axi_if.bid    : '0;
    assign dma_bresp   = select_dma ? bram_axi_if.bresp  : '0;
    assign dma_bvalid  = select_dma ? bram_axi_if.bvalid : 1'b0;

endmodule

`endif