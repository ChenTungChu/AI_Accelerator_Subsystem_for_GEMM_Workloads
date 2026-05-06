// File: rtl/subsystem/scratchpad_port1_owner_mux.sv

`ifndef SCRATCHPAD_PORT1_OWNER_MUX_SV
`define SCRATCHPAD_PORT1_OWNER_MUX_SV

module scratchpad_port1_owner_mux #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 4
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // ------------------------------------------------------------
    // Owner activity
    //
    // stream_load_active:
    //   Asserted while AXI-Stream preload owns scratchpad Port1.
    //   This should remain high until the stream preload path has
    //   completed all pending scratchpad writes and write responses.
    //
    // gemm_active:
    //   Observational/debug input from GEMM side.
    //   Used only for illegal overlap detection.
    // ------------------------------------------------------------
    input  logic                    stream_load_active,
    input  logic                    gemm_active,

    output logic                    owner_stream,
    output logic                    owner_gemm,
    output logic                    illegal_overlap,

    // ============================================================
    // STREAM_LOAD owner input
    //
    // Source:
    //   axis_scratchpad_write_adapter
    //
    // V1 stream preload only uses AXI write channels.
    // ============================================================

    // STREAM AW
    input  logic [ID_WIDTH-1:0]     stream_awid,
    input  logic [ADDR_WIDTH-1:0]   stream_awaddr,
    input  logic [7:0]              stream_awlen,
    input  logic [2:0]              stream_awsize,
    input  logic [1:0]              stream_awburst,
    input  logic                    stream_awvalid,
    output logic                    stream_awready,

    // STREAM W
    input  logic [DATA_WIDTH-1:0]   stream_wdata,
    input  logic [DATA_WIDTH/8-1:0] stream_wstrb,
    input  logic                    stream_wlast,
    input  logic                    stream_wvalid,
    output logic                    stream_wready,

    // STREAM B
    output logic [ID_WIDTH-1:0]     stream_bid,
    output logic [1:0]              stream_bresp,
    output logic                    stream_bvalid,
    input  logic                    stream_bready,

    // ============================================================
    // GEMM owner input
    //
    // Source:
    //   existing GEMM scratchpad adapter
    //
    // GEMM may use both read and write channels.
    // ============================================================

    // GEMM AW
    input  logic [ID_WIDTH-1:0]     gemm_awid,
    input  logic [ADDR_WIDTH-1:0]   gemm_awaddr,
    input  logic [7:0]              gemm_awlen,
    input  logic [2:0]              gemm_awsize,
    input  logic [1:0]              gemm_awburst,
    input  logic                    gemm_awvalid,
    output logic                    gemm_awready,

    // GEMM W
    input  logic [DATA_WIDTH-1:0]   gemm_wdata,
    input  logic [DATA_WIDTH/8-1:0] gemm_wstrb,
    input  logic                    gemm_wlast,
    input  logic                    gemm_wvalid,
    output logic                    gemm_wready,

    // GEMM B
    output logic [ID_WIDTH-1:0]     gemm_bid,
    output logic [1:0]              gemm_bresp,
    output logic                    gemm_bvalid,
    input  logic                    gemm_bready,

    // GEMM AR
    input  logic [ID_WIDTH-1:0]     gemm_arid,
    input  logic [ADDR_WIDTH-1:0]   gemm_araddr,
    input  logic [7:0]              gemm_arlen,
    input  logic [2:0]              gemm_arsize,
    input  logic [1:0]              gemm_arburst,
    input  logic                    gemm_arvalid,
    output logic                    gemm_arready,

    // GEMM R
    output logic [ID_WIDTH-1:0]     gemm_rid,
    output logic [DATA_WIDTH-1:0]   gemm_rdata,
    output logic [1:0]              gemm_rresp,
    output logic                    gemm_rlast,
    output logic                    gemm_rvalid,
    input  logic                    gemm_rready,

    // ============================================================
    // Scratchpad Port1 AXI-MM output
    //
    // Target:
    //   axi_mm_dual_port_bram Port1
    // ============================================================

    // P1 AW
    output logic [ID_WIDTH-1:0]     p1_awid,
    output logic [ADDR_WIDTH-1:0]   p1_awaddr,
    output logic [7:0]              p1_awlen,
    output logic [2:0]              p1_awsize,
    output logic [1:0]              p1_awburst,
    output logic                    p1_awvalid,
    input  logic                    p1_awready,

    // P1 W
    output logic [DATA_WIDTH-1:0]   p1_wdata,
    output logic [DATA_WIDTH/8-1:0] p1_wstrb,
    output logic                    p1_wlast,
    output logic                    p1_wvalid,
    input  logic                    p1_wready,

    // P1 B
    input  logic [ID_WIDTH-1:0]     p1_bid,
    input  logic [1:0]              p1_bresp,
    input  logic                    p1_bvalid,
    output logic                    p1_bready,

    // P1 AR
    output logic [ID_WIDTH-1:0]     p1_arid,
    output logic [ADDR_WIDTH-1:0]   p1_araddr,
    output logic [7:0]              p1_arlen,
    output logic [2:0]              p1_arsize,
    output logic [1:0]              p1_arburst,
    output logic                    p1_arvalid,
    input  logic                    p1_arready,

    // P1 R
    input  logic [ID_WIDTH-1:0]     p1_rid,
    input  logic [DATA_WIDTH-1:0]   p1_rdata,
    input  logic [1:0]              p1_rresp,
    input  logic                    p1_rlast,
    input  logic                    p1_rvalid,
    output logic                    p1_rready
);

    // ------------------------------------------------------------
    // Owner select
    //
    // V1 policy:
    //   stream_load_active == 1 -> STREAM_LOAD owns Port1
    //   otherwise               -> GEMM owns Port1
    //
    // GEMM start should be blocked at a higher control level while
    // stream_load_active is high.
    // ------------------------------------------------------------
    always_comb begin
        owner_stream    = stream_load_active;
        owner_gemm      = !stream_load_active;
        illegal_overlap = stream_load_active && gemm_active;
    end

    // ------------------------------------------------------------
    // Forward path: owners -> Port1
    // ------------------------------------------------------------
    always_comb begin
        // Defaults
        p1_awid    = '0;
        p1_awaddr  = '0;
        p1_awlen   = '0;
        p1_awsize  = '0;
        p1_awburst = '0;
        p1_awvalid = 1'b0;

        p1_wdata   = '0;
        p1_wstrb   = '0;
        p1_wlast   = 1'b0;
        p1_wvalid  = 1'b0;

        p1_bready  = 1'b0;

        p1_arid    = '0;
        p1_araddr  = '0;
        p1_arlen   = '0;
        p1_arsize  = '0;
        p1_arburst = '0;
        p1_arvalid = 1'b0;

        p1_rready  = 1'b0;

        if (owner_stream) begin
            // STREAM_LOAD write path
            p1_awid    = stream_awid;
            p1_awaddr  = stream_awaddr;
            p1_awlen   = stream_awlen;
            p1_awsize  = stream_awsize;
            p1_awburst = stream_awburst;
            p1_awvalid = stream_awvalid;

            p1_wdata   = stream_wdata;
            p1_wstrb   = stream_wstrb;
            p1_wlast   = stream_wlast;
            p1_wvalid  = stream_wvalid;

            p1_bready  = stream_bready;

            // Stream preload does not use read channel in V1.
            p1_arid    = '0;
            p1_araddr  = '0;
            p1_arlen   = '0;
            p1_arsize  = '0;
            p1_arburst = '0;
            p1_arvalid = 1'b0;

            p1_rready  = 1'b0;
        end
        else begin
            // GEMM read/write path
            p1_awid    = gemm_awid;
            p1_awaddr  = gemm_awaddr;
            p1_awlen   = gemm_awlen;
            p1_awsize  = gemm_awsize;
            p1_awburst = gemm_awburst;
            p1_awvalid = gemm_awvalid;

            p1_wdata   = gemm_wdata;
            p1_wstrb   = gemm_wstrb;
            p1_wlast   = gemm_wlast;
            p1_wvalid  = gemm_wvalid;

            p1_bready  = gemm_bready;

            p1_arid    = gemm_arid;
            p1_araddr  = gemm_araddr;
            p1_arlen   = gemm_arlen;
            p1_arsize  = gemm_arsize;
            p1_arburst = gemm_arburst;
            p1_arvalid = gemm_arvalid;

            p1_rready  = gemm_rready;
        end
    end

    // ------------------------------------------------------------
    // Return path: Port1 -> owners
    // ------------------------------------------------------------
    always_comb begin
        // Defaults to inactive for non-owner
        stream_awready = 1'b0;
        stream_wready  = 1'b0;
        stream_bid     = '0;
        stream_bresp   = '0;
        stream_bvalid  = 1'b0;

        gemm_awready   = 1'b0;
        gemm_wready    = 1'b0;
        gemm_bid       = '0;
        gemm_bresp     = '0;
        gemm_bvalid    = 1'b0;
        gemm_arready   = 1'b0;
        gemm_rid       = '0;
        gemm_rdata     = '0;
        gemm_rresp     = '0;
        gemm_rlast     = 1'b0;
        gemm_rvalid    = 1'b0;

        if (owner_stream) begin
            // STREAM_LOAD receives write responses.
            stream_awready = p1_awready;
            stream_wready  = p1_wready;
            stream_bid     = p1_bid;
            stream_bresp   = p1_bresp;
            stream_bvalid  = p1_bvalid;

            // GEMM is blocked while stream preload owns Port1.
            gemm_awready   = 1'b0;
            gemm_wready    = 1'b0;
            gemm_bvalid    = 1'b0;
            gemm_arready   = 1'b0;
            gemm_rvalid    = 1'b0;
        end
        else begin
            // GEMM receives read/write responses.
            gemm_awready   = p1_awready;
            gemm_wready    = p1_wready;
            gemm_bid       = p1_bid;
            gemm_bresp     = p1_bresp;
            gemm_bvalid    = p1_bvalid;

            gemm_arready   = p1_arready;
            gemm_rid       = p1_rid;
            gemm_rdata     = p1_rdata;
            gemm_rresp     = p1_rresp;
            gemm_rlast     = p1_rlast;
            gemm_rvalid    = p1_rvalid;

            // STREAM_LOAD is blocked when GEMM owns Port1.
            stream_awready = 1'b0;
            stream_wready  = 1'b0;
            stream_bvalid  = 1'b0;
        end
    end

`ifndef SYNTHESIS
    // ------------------------------------------------------------
    // Simulation-only overlap warning
    //
    // This should not fire in valid sequencing:
    //   stream preload must complete before GEMM starts.
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // no-op
        end
        else begin
            if (illegal_overlap) begin
                $error(
                    "[scratchpad_port1_owner_mux] Illegal overlap: stream_load_active=1 while gemm_active=1"
                );
            end
        end
    end
`endif

endmodule

`endif