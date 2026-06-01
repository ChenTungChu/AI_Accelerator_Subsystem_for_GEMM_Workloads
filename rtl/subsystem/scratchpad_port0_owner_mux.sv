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
    // Legacy naming:
    //   select_dma = DMA_LOAD owner select
    //
    // Owner policy:
    //   select_dma       = 0, select_dma_store = 0 -> HOST owns Port0
    //   select_dma       = 1, select_dma_store = 0 -> DMA_LOAD owns Port0
    //   select_dma       = 0, select_dma_store = 1 -> DMA_STORE owns Port0
    //   select_dma       = 1, select_dma_store = 1 -> illegal, Port0 held inactive
    //
    // Rules:
    //   - No arbitration / outstanding tracking is done here.
    //   - Owner select must only change when Port0 is idle.
    //   - Host traffic must not be issued while DMA load/store owns Port0.
    //
    // P13 note:
    //   DMA_STORE may be used after a C RMW accumulation sequence, but this
    //   mux only sees the final store transaction. It does not participate
    //   in GEMM partial accumulation.
    // ------------------------------------------------------------
    input  logic select_dma,
    input  logic select_dma_store = 1'b0,

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
    // DMA_LOAD:
    //   - uses AW/W/B channels
    //   - read channel is disabled
    //   - intended for A/B preload into scratchpad before GEMM starts
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
    input  logic                     dma_bready,

    // ------------------------------------------------------------
    // DMA store engine scratchpad read-side master
    //
    // DMA_STORE:
    //   - uses AR/R channels
    //   - write channel is disabled
    //   - intended for final C export after GEMM completion
    //
    // Default values keep legacy top-level instantiations safe until
    // ai_accel_subsys.sv is updated to connect the store path.
    // ------------------------------------------------------------
    input  logic [ID_WIDTH-1:0]      dma_store_arid    = '0,
    input  logic [ADDR_WIDTH-1:0]    dma_store_araddr  = '0,
    input  logic [7:0]               dma_store_arlen   = '0,
    input  logic [2:0]               dma_store_arsize  = '0,
    input  logic [1:0]               dma_store_arburst = '0,
    input  logic                     dma_store_arvalid = 1'b0,
    output logic                     dma_store_arready,

    output logic [ID_WIDTH-1:0]      dma_store_rid,
    output logic [DATA_WIDTH-1:0]    dma_store_rdata,
    output logic [1:0]               dma_store_rresp,
    output logic                     dma_store_rlast,
    output logic                     dma_store_rvalid,
    input  logic                     dma_store_rready  = 1'b0
);

    // ============================================================
    // Owner decode
    // ============================================================
    logic owner_host;
    logic owner_dma_load;
    logic owner_dma_store;
    logic owner_illegal;

    assign owner_illegal   =  select_dma &&  select_dma_store;
    assign owner_host      = !select_dma && !select_dma_store;
    assign owner_dma_load  =  select_dma && !select_dma_store;
    assign owner_dma_store = !select_dma &&  select_dma_store;

    // ============================================================
    // BRAM-facing request mux
    //
    // The mux is intentionally simple and phase-based:
    //   HOST      : full external AXI0 access
    //   DMA_LOAD  : write-only scratchpad preload
    //   DMA_STORE : read-only scratchpad export
    // ============================================================

    // ------------------------------------------------------------
    // Write address channel
    //
    // HOST      : host AW -> BRAM
    // DMA_LOAD  : dma load AW -> BRAM
    // DMA_STORE : write channel disabled
    // ILLEGAL   : write channel disabled
    // ------------------------------------------------------------
    assign bram_axi_if.awid =
        owner_dma_load ? dma_awid :
        owner_host     ? host_axi_if.awid :
                         '0;

    assign bram_axi_if.awaddr =
        owner_dma_load ? dma_awaddr :
        owner_host     ? host_axi_if.awaddr :
                         '0;

    assign bram_axi_if.awlen =
        owner_dma_load ? dma_awlen :
        owner_host     ? host_axi_if.awlen :
                         '0;

    assign bram_axi_if.awsize =
        owner_dma_load ? dma_awsize :
        owner_host     ? host_axi_if.awsize :
                         '0;

    assign bram_axi_if.awburst =
        owner_dma_load ? dma_awburst :
        owner_host     ? host_axi_if.awburst :
                         '0;

    assign bram_axi_if.awvalid =
        owner_dma_load ? dma_awvalid :
        owner_host     ? host_axi_if.awvalid :
                         1'b0;

    // ------------------------------------------------------------
    // Write data channel
    // ------------------------------------------------------------
    assign bram_axi_if.wdata =
        owner_dma_load ? dma_wdata :
        owner_host     ? host_axi_if.wdata :
                         '0;

    assign bram_axi_if.wstrb =
        owner_dma_load ? dma_wstrb :
        owner_host     ? host_axi_if.wstrb :
                         '0;

    assign bram_axi_if.wlast =
        owner_dma_load ? dma_wlast :
        owner_host     ? host_axi_if.wlast :
                         1'b0;

    assign bram_axi_if.wvalid =
        owner_dma_load ? dma_wvalid :
        owner_host     ? host_axi_if.wvalid :
                         1'b0;

    // ------------------------------------------------------------
    // Write response ready
    // ------------------------------------------------------------
    assign bram_axi_if.bready =
        owner_dma_load ? dma_bready :
        owner_host     ? host_axi_if.bready :
                         1'b0;

    // ------------------------------------------------------------
    // Read address channel
    //
    // HOST      : host AR -> BRAM
    // DMA_LOAD  : read channel disabled
    // DMA_STORE : store AR -> BRAM
    // ILLEGAL   : read channel disabled
    // ------------------------------------------------------------
    assign bram_axi_if.arid =
        owner_dma_store ? dma_store_arid :
        owner_host      ? host_axi_if.arid :
                          '0;

    assign bram_axi_if.araddr =
        owner_dma_store ? dma_store_araddr :
        owner_host      ? host_axi_if.araddr :
                          '0;

    assign bram_axi_if.arlen =
        owner_dma_store ? dma_store_arlen :
        owner_host      ? host_axi_if.arlen :
                          '0;

    assign bram_axi_if.arsize =
        owner_dma_store ? dma_store_arsize :
        owner_host      ? host_axi_if.arsize :
                          '0;

    assign bram_axi_if.arburst =
        owner_dma_store ? dma_store_arburst :
        owner_host      ? host_axi_if.arburst :
                          '0;

    assign bram_axi_if.arvalid =
        owner_dma_store ? dma_store_arvalid :
        owner_host      ? host_axi_if.arvalid :
                          1'b0;

    // ------------------------------------------------------------
    // Read response ready
    // ------------------------------------------------------------
    assign bram_axi_if.rready =
        owner_dma_store ? dma_store_rready :
        owner_host      ? host_axi_if.rready :
                          1'b0;

    // ============================================================
    // Host-facing response path
    // ============================================================

    // ------------------------------------------------------------
    // Write address/data ready back to host
    // ------------------------------------------------------------
    assign host_axi_if.awready = owner_host ? bram_axi_if.awready : 1'b0;
    assign host_axi_if.wready  = owner_host ? bram_axi_if.wready  : 1'b0;

    // ------------------------------------------------------------
    // Write response back to host
    // ------------------------------------------------------------
    assign host_axi_if.bid     = owner_host ? bram_axi_if.bid    : '0;
    assign host_axi_if.bresp   = owner_host ? bram_axi_if.bresp  : '0;
    assign host_axi_if.bvalid  = owner_host ? bram_axi_if.bvalid : 1'b0;

    // ------------------------------------------------------------
    // Read address ready back to host
    // ------------------------------------------------------------
    assign host_axi_if.arready = owner_host ? bram_axi_if.arready : 1'b0;

    // ------------------------------------------------------------
    // Read response back to host
    // ------------------------------------------------------------
    assign host_axi_if.rid     = owner_host ? bram_axi_if.rid    : '0;
    assign host_axi_if.rdata   = owner_host ? bram_axi_if.rdata  : '0;
    assign host_axi_if.rresp   = owner_host ? bram_axi_if.rresp  : '0;
    assign host_axi_if.rlast   = owner_host ? bram_axi_if.rlast  : 1'b0;
    assign host_axi_if.rvalid  = owner_host ? bram_axi_if.rvalid : 1'b0;

    // ============================================================
    // DMA_LOAD-facing response path
    // ============================================================

    // ------------------------------------------------------------
    // Write address/data ready back to DMA load engine
    // ------------------------------------------------------------
    assign dma_awready = owner_dma_load ? bram_axi_if.awready : 1'b0;
    assign dma_wready  = owner_dma_load ? bram_axi_if.wready  : 1'b0;

    // ------------------------------------------------------------
    // Write response back to DMA load engine
    // ------------------------------------------------------------
    assign dma_bid     = owner_dma_load ? bram_axi_if.bid    : '0;
    assign dma_bresp   = owner_dma_load ? bram_axi_if.bresp  : '0;
    assign dma_bvalid  = owner_dma_load ? bram_axi_if.bvalid : 1'b0;

    // ============================================================
    // DMA_STORE-facing response path
    // ============================================================

    // ------------------------------------------------------------
    // Read address ready back to DMA store engine
    // ------------------------------------------------------------
    assign dma_store_arready = owner_dma_store ? bram_axi_if.arready : 1'b0;

    // ------------------------------------------------------------
    // Read response back to DMA store engine
    // ------------------------------------------------------------
    assign dma_store_rid     = owner_dma_store ? bram_axi_if.rid    : '0;
    assign dma_store_rdata   = owner_dma_store ? bram_axi_if.rdata  : '0;
    assign dma_store_rresp   = owner_dma_store ? bram_axi_if.rresp  : '0;
    assign dma_store_rlast   = owner_dma_store ? bram_axi_if.rlast  : 1'b0;
    assign dma_store_rvalid  = owner_dma_store ? bram_axi_if.rvalid : 1'b0;

    // ============================================================
    // Simulation-only illegal owner check
    // ============================================================
`ifndef SYNTHESIS
    always_comb begin
        if (owner_illegal) begin
            $error(
                "scratchpad_port0_owner_mux: illegal owner select: select_dma=1 and select_dma_store=1"
            );
        end
    end
`endif

endmodule

`endif