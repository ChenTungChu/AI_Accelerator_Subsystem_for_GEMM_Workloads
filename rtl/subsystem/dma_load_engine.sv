// File: rtl/subsystem/dma_load_engine.sv
`ifndef DMA_LOAD_ENGINE_SV
`define DMA_LOAD_ENGINE_SV

module dma_load_engine #(
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 64,
    parameter int AXI_ID_WIDTH = 4,

    parameter logic [AXI_ID_WIDTH-1:0] DMA_ARID     = '0,
    parameter logic [AXI_ID_WIDTH-1:0] ADAPTER_AWID = '0
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // ------------------------------------------------------------
    // Simple control interface
    //
    // Role:
    //   Move a compact A/B payload from source memory into the
    //   scratchpad through the DMA load path before GEMM starts.
    //
    // Behavior:
    //   - one load job at a time
    //   - load_beats must be non-zero
    //   - src_base_addr and dst_base_addr must be beat-aligned
    //   - loader starts first
    //   - DMA starts one cycle later
    //   - normal done after DMA, loader, and adapter all complete
    //   - terminal error aborts the load job and soft-resets
    //     the internal DMA/loader/adapter chain
    // ------------------------------------------------------------
    input  logic                     load_start,
    input  logic [ADDR_WIDTH-1:0]    src_base_addr,
    input  logic [ADDR_WIDTH-1:0]    dst_base_addr,
    input  logic [31:0]              load_beats,

    output logic                     load_busy,
    output logic                     load_done,
    output logic                     load_error,

    // ------------------------------------------------------------
    // Debug / status
    // ------------------------------------------------------------
    output logic [31:0]              loader_accepted_beats,
    output logic [31:0]              loader_written_beats,
    output logic                     loader_tlast_seen,

    output logic [31:0]              adapter_accepted_beats,
    output logic [31:0]              adapter_committed_beats,
    output logic                     adapter_last_beat_seen,

    output logic                     dma_done_seen,
    output logic                     loader_done_seen,
    output logic                     adapter_done_seen,

    // ------------------------------------------------------------
    // Source AXI-MM read master
    //
    // Reads the external/source-memory payload that will be written
    // into scratchpad as A or B preload data.
    // ------------------------------------------------------------
    output logic [AXI_ID_WIDTH-1:0]  src_axi_arid,
    output logic [ADDR_WIDTH-1:0]    src_axi_araddr,
    output logic [7:0]               src_axi_arlen,
    output logic [2:0]               src_axi_arsize,
    output logic [1:0]               src_axi_arburst,
    output logic                     src_axi_arvalid,
    input  logic                     src_axi_arready,

    input  logic [AXI_ID_WIDTH-1:0]  src_axi_rid,
    input  logic [DATA_WIDTH-1:0]    src_axi_rdata,
    input  logic [1:0]               src_axi_rresp,
    input  logic                     src_axi_rlast,
    input  logic                     src_axi_rvalid,
    output logic                     src_axi_rready,

    // ------------------------------------------------------------
    // Scratchpad AXI-MM write master
    //
    // Writes the loader output into scratchpad Port0 through the
    // Port0 owner mux while DMA_LOAD owns the port.
    // ------------------------------------------------------------
    output logic [AXI_ID_WIDTH-1:0]  spad_axi_awid,
    output logic [ADDR_WIDTH-1:0]    spad_axi_awaddr,
    output logic [7:0]               spad_axi_awlen,
    output logic [2:0]               spad_axi_awsize,
    output logic [1:0]               spad_axi_awburst,
    output logic                     spad_axi_awvalid,
    input  logic                     spad_axi_awready,

    output logic [DATA_WIDTH-1:0]    spad_axi_wdata,
    output logic [DATA_WIDTH/8-1:0]  spad_axi_wstrb,
    output logic                     spad_axi_wlast,
    output logic                     spad_axi_wvalid,
    input  logic                     spad_axi_wready,

    input  logic [AXI_ID_WIDTH-1:0]  spad_axi_bid,
    input  logic [1:0]               spad_axi_bresp,
    input  logic                     spad_axi_bvalid,
    output logic                     spad_axi_bready
);

    // ------------------------------------------------------------
    // Local parameters
    // ------------------------------------------------------------
    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam int BEAT_ADDR_LSB  = (BYTES_PER_BEAT <= 1) ? 0 : $clog2(BYTES_PER_BEAT);

    typedef enum logic [2:0] {
        S_IDLE         = 3'd0,
        S_START_LOADER = 3'd1,
        S_START_DMA    = 3'd2,
        S_WAIT_DONE    = 3'd3,
        S_ABORT_RESET  = 3'd4,
        S_DONE_PULSE   = 3'd5
    } state_e;

    state_e state, state_n;

    // ------------------------------------------------------------
    // Latched load parameters
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] src_base_addr_q;
    logic [ADDR_WIDTH-1:0] dst_base_addr_q;
    logic [31:0]           load_beats_q;

    // ------------------------------------------------------------
    // Internal control / reset
    // ------------------------------------------------------------
    logic dma_start;
    logic loader_start;

    logic sub_rst_n;

    logic dma_busy;
    logic dma_done;
    logic dma_error;

    logic loader_busy;
    logic loader_done;
    logic loader_error;

    logic adapter_busy;
    logic adapter_done;
    logic adapter_error;

    logic all_done_now;
    logic terminal_error_now;
    logic load_req_valid;

    // ------------------------------------------------------------
    // Internal AXI-Stream: DMA -> Loader
    //
    // This stream is local to the load engine. The top-level
    // AXI-Stream frontend uses axis_preload_engine instead.
    // ------------------------------------------------------------
    logic [DATA_WIDTH-1:0] axis_tdata;
    logic                  axis_tvalid;
    logic                  axis_tready;
    logic                  axis_tlast;

    // ------------------------------------------------------------
    // Loader -> scratchpad write adapter linear write request
    // ------------------------------------------------------------
    logic                     loader_wr_valid;
    logic                     loader_wr_ready;
    logic [ADDR_WIDTH-1:0]    loader_wr_addr;
    logic [DATA_WIDTH-1:0]    loader_wr_data;
    logic [DATA_WIDTH/8-1:0]  loader_wr_strb;
    logic                     loader_wr_last;

    // ------------------------------------------------------------
    // Unused DMA write-side wires
    // ------------------------------------------------------------
    logic [AXI_ID_WIDTH-1:0]  dma_unused_awid;
    logic [ADDR_WIDTH-1:0]    dma_unused_awaddr;
    logic [7:0]               dma_unused_awlen;
    logic [2:0]               dma_unused_awsize;
    logic [1:0]               dma_unused_awburst;
    logic                     dma_unused_awvalid;

    logic [DATA_WIDTH-1:0]    dma_unused_wdata;
    logic [DATA_WIDTH/8-1:0]  dma_unused_wstrb;
    logic                     dma_unused_wlast;
    logic                     dma_unused_wvalid;

    logic                     dma_unused_bready;

    // ------------------------------------------------------------
    // Unused adapter read-side wires
    // ------------------------------------------------------------
    logic [AXI_ID_WIDTH-1:0]  adapter_unused_arid;
    logic [ADDR_WIDTH-1:0]    adapter_unused_araddr;
    logic [7:0]               adapter_unused_arlen;
    logic [2:0]               adapter_unused_arsize;
    logic [1:0]               adapter_unused_arburst;
    logic                     adapter_unused_arvalid;
    logic                     adapter_unused_rready;

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------
    function automatic bit is_power_of_two(input int value);
        return (value > 0) && ((value & (value - 1)) == 0);
    endfunction

    function automatic bit addr_is_aligned(input logic [ADDR_WIDTH-1:0] addr);
        if (BYTES_PER_BEAT <= 1) begin
            return 1'b1;
        end
        else begin
            return (addr[BEAT_ADDR_LSB-1:0] == '0);
        end
    endfunction

    initial begin
        if ((DATA_WIDTH % 8) != 0) begin
            $fatal(1, "dma_load_engine: DATA_WIDTH must be byte-aligned");
        end

        if (!is_power_of_two(BYTES_PER_BEAT)) begin
            $fatal(1, "dma_load_engine: BYTES_PER_BEAT must be a power of two");
        end
    end

    always_comb begin
        load_req_valid =
            (load_beats != 0) &&
            addr_is_aligned(src_base_addr) &&
            addr_is_aligned(dst_base_addr);
    end

    // Internal soft reset:
    //   - normal system reset resets everything
    //   - S_ABORT_RESET gives the internal chain one-cycle reset
    //     after terminal error, allowing the next load job to recover
    assign sub_rst_n = rst_n && (state != S_ABORT_RESET);

    always_comb begin
        loader_start = (state == S_START_LOADER) && sub_rst_n;
        dma_start    = (state == S_START_DMA)    && sub_rst_n;
    end

    always_comb begin
        all_done_now =
            (dma_done_seen     || dma_done) &&
            (loader_done_seen  || loader_done) &&
            (adapter_done_seen || adapter_done);
    end

    always_comb begin
        terminal_error_now = dma_error | loader_error | adapter_error;
    end

    // ------------------------------------------------------------
    // Public status
    //
    // Important:
    //   Do not OR raw submodule busy into load_busy.
    //   On terminal error, a downstream block can be waiting forever
    //   for data that will never arrive. Wrapper ownership should be
    //   controlled by wrapper state, not stuck child busy.
    // ------------------------------------------------------------
    always_comb begin
        load_busy =
            (state == S_START_LOADER) ||
            (state == S_START_DMA)    ||
            (state == S_WAIT_DONE)    ||
            (state == S_ABORT_RESET);
    end

    always_comb begin
        load_done = (state == S_DONE_PULSE);
    end

    // ------------------------------------------------------------
    // Next-state logic
    // ------------------------------------------------------------
    always_comb begin
        state_n = state;

        case (state)
            S_IDLE: begin
                if (load_start) begin
                    if (load_req_valid) begin
                        state_n = S_START_LOADER;
                    end
                    else begin
                        state_n = S_DONE_PULSE;
                    end
                end
            end

            S_START_LOADER: begin
                state_n = S_START_DMA;
            end

            S_START_DMA: begin
                state_n = S_WAIT_DONE;
            end

            S_WAIT_DONE: begin
                if (terminal_error_now) begin
                    state_n = S_ABORT_RESET;
                end
                else if (all_done_now) begin
                    state_n = S_DONE_PULSE;
                end
            end

            S_ABORT_RESET: begin
                state_n = S_DONE_PULSE;
            end

            S_DONE_PULSE: begin
                state_n = S_IDLE;
            end

            default: begin
                state_n = S_IDLE;
            end
        endcase
    end

    // ------------------------------------------------------------
    // Sequential control / status
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= S_IDLE;

            src_base_addr_q    <= '0;
            dst_base_addr_q    <= '0;
            load_beats_q       <= '0;

            load_error         <= 1'b0;

            dma_done_seen      <= 1'b0;
            loader_done_seen   <= 1'b0;
            adapter_done_seen  <= 1'b0;
        end
        else begin
            state <= state_n;

            case (state)
                S_IDLE: begin
                    if (load_start) begin
                        src_base_addr_q   <= src_base_addr;
                        dst_base_addr_q   <= dst_base_addr;
                        load_beats_q      <= load_beats;

                        dma_done_seen     <= 1'b0;
                        loader_done_seen  <= 1'b0;
                        adapter_done_seen <= 1'b0;

                        load_error        <= 1'b0;

                        if (!load_req_valid) begin
                            load_error <= 1'b1;
                        end
                    end
                end

                S_START_LOADER: begin
                    // loader_start is generated combinationally
                end

                S_START_DMA: begin
                    // dma_start is generated combinationally
                end

                S_WAIT_DONE: begin
                    if (dma_done) begin
                        dma_done_seen <= 1'b1;
                    end

                    if (loader_done) begin
                        loader_done_seen <= 1'b1;
                    end

                    if (adapter_done) begin
                        adapter_done_seen <= 1'b1;
                    end

                    load_error <= load_error | dma_error | loader_error | adapter_error;
                end

                S_ABORT_RESET: begin
                    // Terminal error path. Keep load_error sticky and
                    // reset the child pipeline through sub_rst_n.
                    load_error <= 1'b1;
                end

                S_DONE_PULSE: begin
                    // Hold sticky load_error until next load_start
                end

                default: begin
                    // no-op
                end
            endcase
        end
    end

    // ------------------------------------------------------------
    // DMA: AXI-MM read -> AXI-Stream
    // ------------------------------------------------------------
    axi_mm2s_dma #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .AXI_ID_WIDTH (AXI_ID_WIDTH),
        .AXI_ARID     (DMA_ARID)
    ) u_dma (
        .clk            (clk),
        .rst_n          (sub_rst_n),

        .start          (dma_start),
        .src_addr       (src_base_addr_q),
        .xfer_len_beats (load_beats_q),

        .busy           (dma_busy),
        .done           (dma_done),
        .error          (dma_error),

        // unused write side
        .m_axi_awid     (dma_unused_awid),
        .m_axi_awaddr   (dma_unused_awaddr),
        .m_axi_awlen    (dma_unused_awlen),
        .m_axi_awsize   (dma_unused_awsize),
        .m_axi_awburst  (dma_unused_awburst),
        .m_axi_awvalid  (dma_unused_awvalid),
        .m_axi_awready  (1'b0),

        .m_axi_wdata    (dma_unused_wdata),
        .m_axi_wstrb    (dma_unused_wstrb),
        .m_axi_wlast    (dma_unused_wlast),
        .m_axi_wvalid   (dma_unused_wvalid),
        .m_axi_wready   (1'b0),

        .m_axi_bid      ('0),
        .m_axi_bresp    (2'b00),
        .m_axi_bvalid   (1'b0),
        .m_axi_bready   (dma_unused_bready),

        // exposed source read side
        .m_axi_arid     (src_axi_arid),
        .m_axi_araddr   (src_axi_araddr),
        .m_axi_arlen    (src_axi_arlen),
        .m_axi_arsize   (src_axi_arsize),
        .m_axi_arburst  (src_axi_arburst),
        .m_axi_arvalid  (src_axi_arvalid),
        .m_axi_arready  (src_axi_arready),

        .m_axi_rid      (src_axi_rid),
        .m_axi_rdata    (src_axi_rdata),
        .m_axi_rresp    (src_axi_rresp),
        .m_axi_rlast    (src_axi_rlast),
        .m_axi_rvalid   (src_axi_rvalid),
        .m_axi_rready   (src_axi_rready),

        // AXI-Stream output
        .m_axis_tdata   (axis_tdata),
        .m_axis_tvalid  (axis_tvalid),
        .m_axis_tready  (axis_tready),
        .m_axis_tlast   (axis_tlast)
    );

    // ------------------------------------------------------------
    // Loader: AXI-Stream -> linear write request
    // ------------------------------------------------------------
    axi_stream_loader #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_loader (
        .clk              (clk),
        .rst_n            (sub_rst_n),

        .start            (loader_start),
        .dst_base_addr    (dst_base_addr_q),
        .expected_beats   (load_beats_q),

        .busy             (loader_busy),
        .done             (loader_done),
        .error            (loader_error),

        .s_axis_tdata     (axis_tdata),
        .s_axis_tvalid    (axis_tvalid),
        .s_axis_tready    (axis_tready),
        .s_axis_tlast     (axis_tlast),

        .wr_valid         (loader_wr_valid),
        .wr_ready         (loader_wr_ready),
        .wr_addr          (loader_wr_addr),
        .wr_data          (loader_wr_data),
        .wr_strb          (loader_wr_strb),
        .wr_last          (loader_wr_last),

        .rd_en            (1'b0),
        .rd_addr          ('0),
        .rd_data          (),

        .accepted_beats   (loader_accepted_beats),
        .written_beats    (loader_written_beats),
        .tlast_seen       (loader_tlast_seen)
    );

    // ------------------------------------------------------------
    // Adapter: linear write request -> scratchpad AXI-MM write
    // ------------------------------------------------------------
    dma_scratchpad_write_adapter #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .AXI_ID_WIDTH (AXI_ID_WIDTH),
        .AXI_AWID     (ADAPTER_AWID)
    ) u_adapter (
        .clk             (clk),
        .rst_n           (sub_rst_n),

        .src_wr_valid    (loader_wr_valid),
        .src_wr_ready    (loader_wr_ready),
        .src_wr_addr     (loader_wr_addr),
        .src_wr_data     (loader_wr_data),
        .src_wr_strb     (loader_wr_strb),
        .src_wr_last     (loader_wr_last),

        .busy            (adapter_busy),
        .done            (adapter_done),
        .error           (adapter_error),
        .accepted_beats  (adapter_accepted_beats),
        .committed_beats (adapter_committed_beats),
        .last_beat_seen  (adapter_last_beat_seen),

        // exposed scratchpad write side
        .m_axi_awid      (spad_axi_awid),
        .m_axi_awaddr    (spad_axi_awaddr),
        .m_axi_awlen     (spad_axi_awlen),
        .m_axi_awsize    (spad_axi_awsize),
        .m_axi_awburst   (spad_axi_awburst),
        .m_axi_awvalid   (spad_axi_awvalid),
        .m_axi_awready   (spad_axi_awready),

        .m_axi_wdata     (spad_axi_wdata),
        .m_axi_wstrb     (spad_axi_wstrb),
        .m_axi_wlast     (spad_axi_wlast),
        .m_axi_wvalid    (spad_axi_wvalid),
        .m_axi_wready    (spad_axi_wready),

        .m_axi_bid       (spad_axi_bid),
        .m_axi_bresp     (spad_axi_bresp),
        .m_axi_bvalid    (spad_axi_bvalid),
        .m_axi_bready    (spad_axi_bready),

        // unused read side
        .m_axi_arid      (adapter_unused_arid),
        .m_axi_araddr    (adapter_unused_araddr),
        .m_axi_arlen     (adapter_unused_arlen),
        .m_axi_arsize    (adapter_unused_arsize),
        .m_axi_arburst   (adapter_unused_arburst),
        .m_axi_arvalid   (adapter_unused_arvalid),
        .m_axi_arready   (1'b0),

        .m_axi_rid       ('0),
        .m_axi_rdata     ('0),
        .m_axi_rresp     (2'b00),
        .m_axi_rlast     (1'b0),
        .m_axi_rvalid    (1'b0),
        .m_axi_rready    (adapter_unused_rready)
    );

endmodule

`endif