// File: rtl/subsystem/axis_preload_engine.sv

`ifndef AXIS_PRELOAD_ENGINE_SV
`define AXIS_PRELOAD_ENGINE_SV

module axis_preload_engine #(
    parameter int ADDR_WIDTH        = 32,
    parameter int DATA_WIDTH        = 64,
    parameter int ID_WIDTH          = 4,

    parameter int AXIS_FIFO_DEPTH   = 16,
    parameter int AXIS_FIFO_AW      = (AXIS_FIFO_DEPTH <= 2) ? 1 : $clog2(AXIS_FIFO_DEPTH),

    parameter int CAPTURE_DEPTH     = 1024,
    parameter int CAPTURE_AW        = (CAPTURE_DEPTH <= 1) ? 1 : $clog2(CAPTURE_DEPTH),

    parameter logic [ID_WIDTH-1:0] AXI_SRC_ARID = '0,
    parameter logic [ID_WIDTH-1:0] AXI_SP_AWID  = '0
)(
    // ============================================================
    // DMA/source clock domain
    // ============================================================
    input  logic                     dma_clk,
    input  logic                     dma_rst_n,

    // ============================================================
    // Core/scratchpad clock domain
    // ============================================================
    input  logic                     core_clk,
    input  logic                     core_rst_n,

    // ============================================================
    // Control interface, dma_clk domain
    //
    // AXI-Stream preload moves a linear DATA_WIDTH-beat payload from
    // source memory into scratchpad through the core-clock stream loader.
    // It is used for A/B preload; C writeback and C RMW remain on the
    // normal GEMM scratchpad path.
    // ============================================================
    input  logic                     axis_load_start,
    input  logic [ADDR_WIDTH-1:0]    axis_src_base_addr,
    input  logic [ADDR_WIDTH-1:0]    axis_dst_base_addr,
    input  logic [31:0]              axis_load_beats,

    output logic                     axis_load_busy,
    output logic                     axis_load_done,
    output logic                     axis_load_error,

    // ============================================================
    // AXI-MM source read master port, dma_clk domain
    //
    // Target:
    //   external/source memory model
    // ============================================================
    output logic [ID_WIDTH-1:0]      axis_src_axi_arid,
    output logic [ADDR_WIDTH-1:0]    axis_src_axi_araddr,
    output logic [7:0]               axis_src_axi_arlen,
    output logic [2:0]               axis_src_axi_arsize,
    output logic [1:0]               axis_src_axi_arburst,
    output logic                     axis_src_axi_arvalid,
    input  logic                     axis_src_axi_arready,

    input  logic [ID_WIDTH-1:0]      axis_src_axi_rid,
    input  logic [DATA_WIDTH-1:0]    axis_src_axi_rdata,
    input  logic [1:0]               axis_src_axi_rresp,
    input  logic                     axis_src_axi_rlast,
    input  logic                     axis_src_axi_rvalid,
    output logic                     axis_src_axi_rready,

    // ============================================================
    // Scratchpad Port1 write master side, core_clk domain
    //
    // Drives the STREAM_LOAD input of scratchpad_port1_owner_mux while
    // AXI-Stream preload is active. GEMM may use Port1 again only after
    // stream_load_active deasserts.
    // ============================================================
    output logic [ID_WIDTH-1:0]      sp_axi_awid,
    output logic [ADDR_WIDTH-1:0]    sp_axi_awaddr,
    output logic [7:0]               sp_axi_awlen,
    output logic [2:0]               sp_axi_awsize,
    output logic [1:0]               sp_axi_awburst,
    output logic                     sp_axi_awvalid,
    input  logic                     sp_axi_awready,

    output logic [DATA_WIDTH-1:0]    sp_axi_wdata,
    output logic [DATA_WIDTH/8-1:0]  sp_axi_wstrb,
    output logic                     sp_axi_wlast,
    output logic                     sp_axi_wvalid,
    input  logic                     sp_axi_wready,

    input  logic [ID_WIDTH-1:0]      sp_axi_bid,
    input  logic [1:0]               sp_axi_bresp,
    input  logic                     sp_axi_bvalid,
    output logic                     sp_axi_bready,

    // ============================================================
    // Core-domain owner/activity indication
    //
    // stream_load_active covers the loader-start and write-drain window
    // so Port1 ownership is assigned before the first stream write.
    // ============================================================
    output logic                     stream_load_active,

    // ============================================================
    // Debug/status
    //
    // Domain notes:
    //   axis_fifo_full          : dma_clk domain
    //   axis_fifo_empty         : core_clk domain
    //   loader_* counters       : core_clk domain
    //   adapter_* counters      : core_clk domain
    // ============================================================
    output logic                     axis_fifo_full,
    output logic                     axis_fifo_empty,
    output logic [AXIS_FIFO_AW:0]    axis_fifo_wr_level,
    output logic [AXIS_FIFO_AW:0]    axis_fifo_rd_level,

    output logic [31:0]              loader_accepted_beats,
    output logic [31:0]              loader_written_beats,
    output logic                     loader_tlast_seen,

    output logic [31:0]              adapter_accepted_writes,
    output logic [31:0]              adapter_completed_writes
);

    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam int BEAT_ADDR_LSB  = (BYTES_PER_BEAT <= 1) ? 0 : $clog2(BYTES_PER_BEAT);

    // ============================================================
    // DMA-domain FSM
    // ============================================================
    typedef enum logic [2:0] {
        D_IDLE        = 3'd0,
        D_REQ_CORE    = 3'd1,
        D_RUN_MM2S    = 3'd2,
        D_WAIT_CORE   = 3'd3,
        D_DONE_PULSE  = 3'd4
    } dma_state_e;

    dma_state_e dma_state, dma_state_n;

    logic [ADDR_WIDTH-1:0] src_addr_dma_q;
    logic [ADDR_WIDTH-1:0] dst_addr_dma_q;
    logic [31:0]           beats_dma_q;

    logic                  dma_error_q;
    logic                  start_while_busy_error_q;
    logic                  mm2s_error_seen_q;

    // DMA -> core request toggle
    logic                  core_req_toggle_dma_q;

    // core -> DMA acknowledgement/done synchronization
    logic                  core_ack_toggle_core_q;
    logic                  core_done_toggle_core_q;
    logic                  core_error_core_q;

    logic                  core_ack_sync_d1;
    logic                  core_ack_sync_d2;
    logic                  core_done_sync_d1;
    logic                  core_done_sync_d2;
    logic                  core_error_sync_d1;
    logic                  core_error_sync_d2;

    logic                  core_ack_seen_dma_q;
    logic                  core_done_seen_dma_q;

    logic                  mm2s_start_pulse;
    logic                  mm2s_busy;
    logic                  mm2s_done;
    logic                  mm2s_error;

    // Poison beat injection.
    // If MM2S fails before normal TLAST delivery, inject one zero TLAST
    // beat so the core-side loader can terminate instead of hanging.
    logic                  poison_valid_q;
    logic                  poison_sent_q;

    // ============================================================
    // Core-domain FSM
    // ============================================================
    typedef enum logic [2:0] {
        C_IDLE        = 3'd0,
        C_START       = 3'd1,
        C_ACTIVE      = 3'd2,
        C_DONE_PULSE  = 3'd3
    } core_state_e;

    core_state_e core_state, core_state_n;

    logic                  core_req_sync_c1;
    logic                  core_req_sync_c2;
    logic                  core_req_seen_core_q;
    logic                  core_req_event;

    logic [ADDR_WIDTH-1:0] dst_addr_core_q;
    logic [31:0]           beats_core_q;

    logic                  loader_start_pulse;
    logic                  loader_done;
    logic                  loader_error;

    logic                  loader_done_seen_q;
    logic                  loader_error_seen_q;

    logic                  adapter_clear_status;
    logic                  adapter_busy;
    logic                  adapter_write_done;
    logic                  adapter_write_done_last;
    logic                  adapter_write_error;
    logic                  adapter_error;

    // ============================================================
    // AXI-Stream wires
    // ============================================================
    logic [DATA_WIDTH-1:0] mm2s_axis_tdata;
    logic                  mm2s_axis_tvalid;
    logic                  mm2s_axis_tready;
    logic                  mm2s_axis_tlast;

    logic [DATA_WIDTH-1:0] fifo_s_tdata;
    logic                  fifo_s_tvalid;
    logic                  fifo_s_tready;
    logic                  fifo_s_tlast;

    logic [DATA_WIDTH-1:0] fifo_m_tdata;
    logic                  fifo_m_tvalid;
    logic                  fifo_m_tready;
    logic                  fifo_m_tlast;

    logic                  fifo_s_accept_pulse;
    logic                  fifo_m_accept_pulse;

    // ============================================================
    // Loader -> scratchpad write adapter wires
    // ============================================================
    logic                     loader_wr_valid;
    logic                     loader_wr_ready;
    logic [ADDR_WIDTH-1:0]    loader_wr_addr;
    logic [DATA_WIDTH-1:0]    loader_wr_data;
    logic [DATA_WIDTH/8-1:0]  loader_wr_strb;
    logic                     loader_wr_last;

    // ============================================================
    // axi_mm2s_dma unused write-channel dummy wires
    // ============================================================
    logic [ID_WIDTH-1:0]      mm2s_awid_unused;
    logic [ADDR_WIDTH-1:0]    mm2s_awaddr_unused;
    logic [7:0]               mm2s_awlen_unused;
    logic [2:0]               mm2s_awsize_unused;
    logic [1:0]               mm2s_awburst_unused;
    logic                     mm2s_awvalid_unused;

    logic [DATA_WIDTH-1:0]    mm2s_wdata_unused;
    logic [DATA_WIDTH/8-1:0]  mm2s_wstrb_unused;
    logic                     mm2s_wlast_unused;
    logic                     mm2s_wvalid_unused;

    // ============================================================
    // Helpers
    // ============================================================
    function automatic bit is_power_of_two(input int value);
        return (value > 0) && ((value & (value - 1)) == 0);
    endfunction

    function automatic bit addr_is_aligned(
        input logic [ADDR_WIDTH-1:0] addr
    );
        if (BYTES_PER_BEAT <= 1) begin
            return 1'b1;
        end
        else begin
            return (addr[BEAT_ADDR_LSB-1:0] == '0);
        end
    endfunction

    function automatic bit launch_is_valid(
        input logic [ADDR_WIDTH-1:0] src_addr,
        input logic [ADDR_WIDTH-1:0] dst_addr,
        input logic [31:0]           beats
    );
        return (beats != 0) &&
               addr_is_aligned(src_addr) &&
               addr_is_aligned(dst_addr);
    endfunction

    initial begin
        if ((DATA_WIDTH % 8) != 0) begin
            $fatal(1,
                "axis_preload_engine: DATA_WIDTH must be byte-aligned"
            );
        end

        if (!is_power_of_two(BYTES_PER_BEAT)) begin
            $fatal(1,
                "axis_preload_engine: BYTES_PER_BEAT must be a power of two"
            );
        end
    end

    // ============================================================
    // Top-level status, dma_clk domain
    // ============================================================
    always_comb begin
        axis_load_busy = (dma_state == D_REQ_CORE)  ||
                         (dma_state == D_RUN_MM2S)  ||
                         (dma_state == D_WAIT_CORE);

        axis_load_done  = (dma_state == D_DONE_PULSE);
        axis_load_error = dma_error_q;
    end

    // ============================================================
    // DMA-domain next-state
    // ============================================================
    always_comb begin
        dma_state_n      = dma_state;
        mm2s_start_pulse = 1'b0;

        case (dma_state)
            D_IDLE: begin
                if (axis_load_start) begin
                    if (launch_is_valid(
                            axis_src_base_addr,
                            axis_dst_base_addr,
                            axis_load_beats
                        )) begin
                        dma_state_n = D_REQ_CORE;
                    end
                    else begin
                        dma_state_n = D_DONE_PULSE;
                    end
                end
            end

            D_REQ_CORE: begin
                if (core_ack_sync_d2 != core_ack_seen_dma_q) begin
                    mm2s_start_pulse = 1'b1;
                    dma_state_n      = D_RUN_MM2S;
                end
            end

            D_RUN_MM2S: begin
                if (mm2s_done) begin
                    dma_state_n = D_WAIT_CORE;
                end
            end

            D_WAIT_CORE: begin
                if (core_done_sync_d2 != core_done_seen_dma_q) begin
                    dma_state_n = D_DONE_PULSE;
                end
            end

            D_DONE_PULSE: begin
                dma_state_n = D_IDLE;
            end

            default: begin
                dma_state_n = D_IDLE;
            end
        endcase
    end

    // ============================================================
    // DMA-domain sequential logic
    // ============================================================
    always_ff @(posedge dma_clk or negedge dma_rst_n) begin
        if (!dma_rst_n) begin
            dma_state                 <= D_IDLE;

            src_addr_dma_q            <= '0;
            dst_addr_dma_q            <= '0;
            beats_dma_q               <= '0;

            dma_error_q               <= 1'b0;
            start_while_busy_error_q  <= 1'b0;
            mm2s_error_seen_q         <= 1'b0;

            core_req_toggle_dma_q     <= 1'b0;

            core_ack_sync_d1          <= 1'b0;
            core_ack_sync_d2          <= 1'b0;
            core_done_sync_d1         <= 1'b0;
            core_done_sync_d2         <= 1'b0;
            core_error_sync_d1        <= 1'b0;
            core_error_sync_d2        <= 1'b0;

            core_ack_seen_dma_q       <= 1'b0;
            core_done_seen_dma_q      <= 1'b0;

            poison_valid_q            <= 1'b0;
            poison_sent_q             <= 1'b0;
        end
        else begin
            dma_state <= dma_state_n;

            // Synchronize core-domain status back into dma_clk domain.
            core_ack_sync_d1   <= core_ack_toggle_core_q;
            core_ack_sync_d2   <= core_ack_sync_d1;

            core_done_sync_d1  <= core_done_toggle_core_q;
            core_done_sync_d2  <= core_done_sync_d1;

            core_error_sync_d1 <= core_error_core_q;
            core_error_sync_d2 <= core_error_sync_d1;

            // Default poison handling.
            if (poison_valid_q && fifo_s_tready) begin
                poison_valid_q <= 1'b0;
                poison_sent_q  <= 1'b1;
            end

            case (dma_state)
                D_IDLE: begin
                    poison_valid_q           <= 1'b0;
                    poison_sent_q            <= 1'b0;
                    start_while_busy_error_q <= 1'b0;
                    mm2s_error_seen_q        <= 1'b0;

                    if (axis_load_start) begin
                        src_addr_dma_q       <= axis_src_base_addr;
                        dst_addr_dma_q       <= axis_dst_base_addr;
                        beats_dma_q          <= axis_load_beats;

                        dma_error_q          <= 1'b0;
                        core_ack_seen_dma_q  <= core_ack_sync_d2;
                        core_done_seen_dma_q <= core_done_sync_d2;

                        if (launch_is_valid(
                                axis_src_base_addr,
                                axis_dst_base_addr,
                                axis_load_beats
                            )) begin
                            core_req_toggle_dma_q <= ~core_req_toggle_dma_q;
                        end
                        else begin
                            dma_error_q <= 1'b1;
                        end
                    end
                end

                D_REQ_CORE: begin
                    if (axis_load_start) begin
                        start_while_busy_error_q <= 1'b1;
                        dma_error_q              <= 1'b1;
                    end

                    if (core_ack_sync_d2 != core_ack_seen_dma_q) begin
                        core_ack_seen_dma_q <= core_ack_sync_d2;
                    end
                end

                D_RUN_MM2S: begin
                    if (axis_load_start) begin
                        start_while_busy_error_q <= 1'b1;
                        dma_error_q              <= 1'b1;
                    end

                    if (mm2s_done) begin
                        mm2s_error_seen_q <= mm2s_error;

                        if (mm2s_error) begin
                            dma_error_q <= 1'b1;

                            // Terminate the core-side loader with a
                            // synthetic TLAST beat so the job cannot hang
                            // waiting for TLAST after an MM2S-side error.
                            if (!poison_sent_q && !poison_valid_q) begin
                                poison_valid_q <= 1'b1;
                            end
                        end
                    end
                end

                D_WAIT_CORE: begin
                    if (axis_load_start) begin
                        start_while_busy_error_q <= 1'b1;
                        dma_error_q              <= 1'b1;
                    end

                    if (core_done_sync_d2 != core_done_seen_dma_q) begin
                        core_done_seen_dma_q <= core_done_sync_d2;

                        dma_error_q <= dma_error_q              ||
                                       mm2s_error_seen_q         ||
                                       start_while_busy_error_q  ||
                                       core_error_sync_d2;
                    end
                end

                D_DONE_PULSE: begin
                    // Hold result status for the done pulse.
                end

                default: begin
                    dma_state <= D_IDLE;
                end
            endcase
        end
    end

    // ============================================================
    // Core-domain request synchronization
    // ============================================================
    always_ff @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            core_req_sync_c1    <= 1'b0;
            core_req_sync_c2    <= 1'b0;
            core_req_seen_core_q <= 1'b0;
        end
        else begin
            core_req_sync_c1 <= core_req_toggle_dma_q;
            core_req_sync_c2 <= core_req_sync_c1;

            if (core_req_event) begin
                core_req_seen_core_q <= core_req_sync_c2;
            end
        end
    end

    always_comb begin
        core_req_event = (core_req_sync_c2 != core_req_seen_core_q);
    end

    // ============================================================
    // Core-domain next-state
    // ============================================================
    always_comb begin
        core_state_n          = core_state;
        loader_start_pulse    = 1'b0;
        adapter_clear_status  = 1'b0;

        case (core_state)
            C_IDLE: begin
                if (core_req_event) begin
                    // Config is latched in the sequential block on this
                    // same edge. Do not start loader until next cycle.
                    core_state_n = C_START;
                end
            end

            C_START: begin
                // Start one cycle after config latch so the loader samples
                // stable dst_addr_core_q / beats_core_q values.
                loader_start_pulse   = 1'b1;
                adapter_clear_status = 1'b1;
                core_state_n         = C_ACTIVE;
            end

            C_ACTIVE: begin
                if ((loader_done_seen_q || loader_done) && !adapter_busy) begin
                    core_state_n = C_DONE_PULSE;
                end
            end

            C_DONE_PULSE: begin
                core_state_n = C_IDLE;
            end

            default: begin
                core_state_n = C_IDLE;
            end
        endcase
    end

    // ============================================================
    // Core-domain sequential logic
    // ============================================================
    always_ff @(posedge core_clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
            core_state              <= C_IDLE;

            dst_addr_core_q         <= '0;
            beats_core_q            <= '0;

            loader_done_seen_q      <= 1'b0;
            loader_error_seen_q     <= 1'b0;

            core_ack_toggle_core_q  <= 1'b0;
            core_done_toggle_core_q <= 1'b0;
            core_error_core_q       <= 1'b0;
        end
        else begin
            core_state <= core_state_n;

            case (core_state)
                C_IDLE: begin
                    loader_done_seen_q  <= 1'b0;
                    loader_error_seen_q <= 1'b0;
                    core_error_core_q   <= 1'b0;

                    if (core_req_event) begin
                        // Latch config first.
                        dst_addr_core_q <= dst_addr_dma_q;
                        beats_core_q    <= beats_dma_q;

                        // Ack means the core side accepted the request.
                        // Loader starts one core_clk later in C_START.
                        core_ack_toggle_core_q <= ~core_ack_toggle_core_q;
                    end
                end

                C_START: begin
                    // Loader start pulse is generated combinationally
                    // in this state. No sequential action required.
                end

                C_ACTIVE: begin
                    if (loader_done) begin
                        loader_done_seen_q  <= 1'b1;
                        loader_error_seen_q <= loader_error_seen_q || loader_error;
                    end

                    if ((loader_done_seen_q || loader_done) && !adapter_busy) begin
                        core_error_core_q <= loader_error_seen_q ||
                                            loader_error        ||
                                            adapter_error;
                    end
                end

                C_DONE_PULSE: begin
                    core_done_toggle_core_q <= ~core_done_toggle_core_q;
                end

                default: begin
                    core_state <= C_IDLE;
                end
            endcase
        end
    end

    assign stream_load_active = (core_state == C_START) ||
                                (core_state == C_ACTIVE);


    // ============================================================
    // MM2S stream source selection
    //
    // Normal:
    //   axi_mm2s_dma stream output goes into FIFO.
    //
    // Error:
    //   if MM2S reports an error before the loader sees TLAST,
    //   inject one synthetic zero TLAST beat to terminate the loader.
    // ============================================================
    always_comb begin
        fifo_s_tdata  = poison_valid_q ? '0   : mm2s_axis_tdata;
        fifo_s_tlast  = poison_valid_q ? 1'b1 : mm2s_axis_tlast;
        fifo_s_tvalid = poison_valid_q ? 1'b1 : mm2s_axis_tvalid;

        mm2s_axis_tready = (!poison_valid_q) && fifo_s_tready;
    end

    // ============================================================
    // Submodule: AXI MM2S DMA
    // ============================================================
    axi_mm2s_dma #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .AXI_ID_WIDTH (ID_WIDTH),
        .AXI_ARID     (AXI_SRC_ARID)
    ) u_axi_mm2s_dma (
        .clk              (dma_clk),
        .rst_n            (dma_rst_n),

        .start            (mm2s_start_pulse),
        .src_addr         (src_addr_dma_q),
        .xfer_len_beats   (beats_dma_q),

        .busy             (mm2s_busy),
        .done             (mm2s_done),
        .error            (mm2s_error),

        // Unused write channels
        .m_axi_awid       (mm2s_awid_unused),
        .m_axi_awaddr     (mm2s_awaddr_unused),
        .m_axi_awlen      (mm2s_awlen_unused),
        .m_axi_awsize     (mm2s_awsize_unused),
        .m_axi_awburst    (mm2s_awburst_unused),
        .m_axi_awvalid    (mm2s_awvalid_unused),
        .m_axi_awready    (1'b1),

        .m_axi_wdata      (mm2s_wdata_unused),
        .m_axi_wstrb      (mm2s_wstrb_unused),
        .m_axi_wlast      (mm2s_wlast_unused),
        .m_axi_wvalid     (mm2s_wvalid_unused),
        .m_axi_wready     (1'b1),

        .m_axi_bid        ('0),
        .m_axi_bresp      (2'b00),
        .m_axi_bvalid     (1'b0),
        .m_axi_bready     (),

        // Read source AXI-MM
        .m_axi_arid       (axis_src_axi_arid),
        .m_axi_araddr     (axis_src_axi_araddr),
        .m_axi_arlen      (axis_src_axi_arlen),
        .m_axi_arsize     (axis_src_axi_arsize),
        .m_axi_arburst    (axis_src_axi_arburst),
        .m_axi_arvalid    (axis_src_axi_arvalid),
        .m_axi_arready    (axis_src_axi_arready),

        .m_axi_rid        (axis_src_axi_rid),
        .m_axi_rdata      (axis_src_axi_rdata),
        .m_axi_rresp      (axis_src_axi_rresp),
        .m_axi_rlast      (axis_src_axi_rlast),
        .m_axi_rvalid     (axis_src_axi_rvalid),
        .m_axi_rready     (axis_src_axi_rready),

        // AXI-Stream output
        .m_axis_tdata     (mm2s_axis_tdata),
        .m_axis_tvalid    (mm2s_axis_tvalid),
        .m_axis_tready    (mm2s_axis_tready),
        .m_axis_tlast     (mm2s_axis_tlast)
    );

    // ============================================================
    // Submodule: AXI-Stream async FIFO
    // ============================================================
    axis_async_fifo #(
        .DATA_WIDTH      (DATA_WIDTH),
        .FIFO_DEPTH      (AXIS_FIFO_DEPTH),
        .FIFO_ADDR_WIDTH (AXIS_FIFO_AW)
    ) u_axis_async_fifo (
        .s_axis_aclk          (dma_clk),
        .s_axis_aresetn       (dma_rst_n),

        .s_axis_tdata         (fifo_s_tdata),
        .s_axis_tvalid        (fifo_s_tvalid),
        .s_axis_tready        (fifo_s_tready),
        .s_axis_tlast         (fifo_s_tlast),

        .m_axis_aclk          (core_clk),
        .m_axis_aresetn       (core_rst_n),

        .m_axis_tdata         (fifo_m_tdata),
        .m_axis_tvalid        (fifo_m_tvalid),
        .m_axis_tready        (fifo_m_tready),
        .m_axis_tlast         (fifo_m_tlast),

        .s_axis_full          (axis_fifo_full),
        .s_axis_wr_level      (axis_fifo_wr_level),
        .s_axis_accept_pulse  (fifo_s_accept_pulse),

        .m_axis_empty         (axis_fifo_empty),
        .m_axis_rd_level      (axis_fifo_rd_level),
        .m_axis_accept_pulse  (fifo_m_accept_pulse)
    );

    // ============================================================
    // Submodule: AXI-Stream loader
    // ============================================================
    axi_stream_loader #(
        .ADDR_WIDTH         (ADDR_WIDTH),
        .DATA_WIDTH         (DATA_WIDTH),
        .CAPTURE_DEPTH      (CAPTURE_DEPTH),
        .CAPTURE_ADDR_WIDTH (CAPTURE_AW)
    ) u_axi_stream_loader (
        .clk             (core_clk),
        .rst_n           (core_rst_n),

        .start           (loader_start_pulse),
        .dst_base_addr   (dst_addr_core_q),
        .expected_beats  (beats_core_q),

        .busy            (),
        .done            (loader_done),
        .error           (loader_error),

        .s_axis_tdata    (fifo_m_tdata),
        .s_axis_tvalid   (fifo_m_tvalid),
        .s_axis_tready   (fifo_m_tready),
        .s_axis_tlast    (fifo_m_tlast),

        .wr_valid        (loader_wr_valid),
        .wr_ready        (loader_wr_ready),
        .wr_addr         (loader_wr_addr),
        .wr_data         (loader_wr_data),
        .wr_strb         (loader_wr_strb),
        .wr_last         (loader_wr_last),

        .rd_en           (1'b0),
        .rd_addr         ('0),
        .rd_data         (),

        .accepted_beats  (loader_accepted_beats),
        .written_beats   (loader_written_beats),
        .tlast_seen      (loader_tlast_seen)
    );

    // ============================================================
    // Submodule: scratchpad write adapter
    //
    // Converts linear stream-loader writes into single-beat AXI-MM
    // scratchpad writes. This adapter only handles preload writes.
    // ============================================================
    axis_scratchpad_write_adapter #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .AXI_AWID   (AXI_SP_AWID)
    ) u_axis_scratchpad_write_adapter (
        .clk              (core_clk),
        .rst_n            (core_rst_n),

        .clear_status     (adapter_clear_status),

        .wr_valid         (loader_wr_valid),
        .wr_ready         (loader_wr_ready),
        .wr_addr          (loader_wr_addr),
        .wr_data          (loader_wr_data),
        .wr_strb          (loader_wr_strb),
        .wr_last          (loader_wr_last),

        .m_axi_awid       (sp_axi_awid),
        .m_axi_awaddr     (sp_axi_awaddr),
        .m_axi_awlen      (sp_axi_awlen),
        .m_axi_awsize     (sp_axi_awsize),
        .m_axi_awburst    (sp_axi_awburst),
        .m_axi_awvalid    (sp_axi_awvalid),
        .m_axi_awready    (sp_axi_awready),

        .m_axi_wdata      (sp_axi_wdata),
        .m_axi_wstrb      (sp_axi_wstrb),
        .m_axi_wlast      (sp_axi_wlast),
        .m_axi_wvalid     (sp_axi_wvalid),
        .m_axi_wready     (sp_axi_wready),

        .m_axi_bid        (sp_axi_bid),
        .m_axi_bresp      (sp_axi_bresp),
        .m_axi_bvalid     (sp_axi_bvalid),
        .m_axi_bready     (sp_axi_bready),

        .busy             (adapter_busy),
        .write_done       (adapter_write_done),
        .write_done_last  (adapter_write_done_last),
        .write_error      (adapter_write_error),
        .error            (adapter_error),

        .accepted_writes  (adapter_accepted_writes),
        .completed_writes (adapter_completed_writes)
    );

endmodule

`endif