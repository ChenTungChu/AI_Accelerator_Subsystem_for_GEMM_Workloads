// File: rtl/interface/axi_lite_if.sv

`ifndef AXI_LITE_IF_SV
`define AXI_LITE_IF_SV

interface axi_lite_if #(
    parameter int ADDR_WIDTH = 12,
    parameter int DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n
);

    localparam int STRB_WIDTH = DATA_WIDTH / 8;

    // ------------------------------------------------------------
    // Write address channel
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [2:0]            awprot;
    logic                  awvalid;
    logic                  awready;

    // ------------------------------------------------------------
    // Write data channel
    // ------------------------------------------------------------
    logic [DATA_WIDTH-1:0] wdata;
    logic [STRB_WIDTH-1:0] wstrb;
    logic                  wvalid;
    logic                  wready;

    // ------------------------------------------------------------
    // Write response channel
    // ------------------------------------------------------------
    logic [1:0]            bresp;
    logic                  bvalid;
    logic                  bready;

    // ------------------------------------------------------------
    // Read address channel
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] araddr;
    logic [2:0]            arprot;
    logic                  arvalid;
    logic                  arready;

    // ------------------------------------------------------------
    // Read data channel
    // ------------------------------------------------------------
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rvalid;
    logic                  rready;

    // ------------------------------------------------------------
    // Master modport
    // ------------------------------------------------------------
    modport master (
        output awaddr,
        output awprot,
        output awvalid,
        input  awready,

        output wdata,
        output wstrb,
        output wvalid,
        input  wready,

        input  bresp,
        input  bvalid,
        output bready,

        output araddr,
        output arprot,
        output arvalid,
        input  arready,

        input  rdata,
        input  rresp,
        input  rvalid,
        output rready
    );

    // ------------------------------------------------------------
    // Slave modport
    // ------------------------------------------------------------
    modport slave (
        input  awaddr,
        input  awprot,
        input  awvalid,
        output awready,

        input  wdata,
        input  wstrb,
        input  wvalid,
        output wready,

        output bresp,
        output bvalid,
        input  bready,

        input  araddr,
        input  arprot,
        input  arvalid,
        output arready,

        output rdata,
        output rresp,
        output rvalid,
        input  rready
    );

    // ------------------------------------------------------------
    // Passive monitor modport
    // ------------------------------------------------------------
    modport monitor (
        input awaddr,
        input awprot,
        input awvalid,
        input awready,

        input wdata,
        input wstrb,
        input wvalid,
        input wready,

        input bresp,
        input bvalid,
        input bready,

        input araddr,
        input arprot,
        input arvalid,
        input arready,

        input rdata,
        input rresp,
        input rvalid,
        input rready
    );

`ifndef SYNTHESIS
    initial begin
        if ((DATA_WIDTH % 8) != 0) begin
            $fatal(1, "axi_lite_if: DATA_WIDTH must be byte-aligned");
        end

        if (ADDR_WIDTH <= 0) begin
            $fatal(1, "axi_lite_if: ADDR_WIDTH must be greater than zero");
        end
    end
`endif

endinterface

`endif
