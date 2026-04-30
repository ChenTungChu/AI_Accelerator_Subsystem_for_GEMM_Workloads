// File: tb/dma/axi_mm2s_dma_to_loader_to_adapter_tb_top.sv
`ifndef AXI_MM2S_DMA_TO_LOADER_TO_ADAPTER_TB_TOP_SV
`define AXI_MM2S_DMA_TO_LOADER_TO_ADAPTER_TB_TOP_SV

`timescale 1ns/1ps

module axi_mm2s_dma_to_loader_to_adapter_tb_top;

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    localparam int ADDR_WIDTH   = 32;
    localparam int DATA_WIDTH   = 64;
    localparam int AXI_ID_WIDTH = 4;

    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam int BEAT_ADDR_LSB  = (BYTES_PER_BEAT <= 1) ? 0 : $clog2(BYTES_PER_BEAT);

    localparam int SRC_MEM_DEPTH_WORDS = 1024;
    localparam int DST_MEM_DEPTH_WORDS = 2048;

    localparam int READ_LATENCY_CYCLES = 2;

    localparam int LOADER_CAPTURE_DEPTH      = 1024;
    localparam int LOADER_CAPTURE_ADDR_WIDTH = (LOADER_CAPTURE_DEPTH <= 1) ? 1 : $clog2(LOADER_CAPTURE_DEPTH);

    localparam logic [AXI_ID_WIDTH-1:0] AXI_DMA_ARID     = '0;
    localparam logic [AXI_ID_WIDTH-1:0] AXI_ADAPTER_AWID = '0;

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;
    localparam logic [DATA_WIDTH/8-1:0] FULL_STRB = {DATA_WIDTH/8{1'b1}};

    // ------------------------------------------------------------
    // Clock / Reset
    // ------------------------------------------------------------
    logic clk;
    logic rst_n;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------
    // DMA control / status
    // ------------------------------------------------------------
    logic                  dma_start;
    logic [ADDR_WIDTH-1:0] dma_src_addr;
    logic [31:0]           dma_xfer_len_beats;

    logic                  dma_busy;
    logic                  dma_done;
    logic                  dma_error;

    // ------------------------------------------------------------
    // DMA AXI-MM source-side signals
    // ------------------------------------------------------------
    logic [AXI_ID_WIDTH-1:0] dma_awid;
    logic [ADDR_WIDTH-1:0]   dma_awaddr;
    logic [7:0]              dma_awlen;
    logic [2:0]              dma_awsize;
    logic [1:0]              dma_awburst;
    logic                    dma_awvalid;
    logic                    dma_awready;

    logic [DATA_WIDTH-1:0]   dma_wdata;
    logic [DATA_WIDTH/8-1:0] dma_wstrb;
    logic                    dma_wlast;
    logic                    dma_wvalid;
    logic                    dma_wready;

    logic [AXI_ID_WIDTH-1:0] dma_bid;
    logic [1:0]              dma_bresp;
    logic                    dma_bvalid;
    logic                    dma_bready;

    logic [AXI_ID_WIDTH-1:0] dma_arid;
    logic [ADDR_WIDTH-1:0]   dma_araddr;
    logic [7:0]              dma_arlen;
    logic [2:0]              dma_arsize;
    logic [1:0]              dma_arburst;
    logic                    dma_arvalid;
    logic                    dma_arready;

    logic [AXI_ID_WIDTH-1:0] dma_rid;
    logic [DATA_WIDTH-1:0]   dma_rdata;
    logic [1:0]              dma_rresp;
    logic                    dma_rlast;
    logic                    dma_rvalid;
    logic                    dma_rready;

    // ------------------------------------------------------------
    // AXIS wires: DMA -> Loader
    // ------------------------------------------------------------
    logic [DATA_WIDTH-1:0] axis_tdata;
    logic                  axis_tvalid;
    logic                  axis_tready;
    logic                  axis_tlast;

    // ------------------------------------------------------------
    // Loader control / status
    // ------------------------------------------------------------
    logic                  loader_start;
    logic [ADDR_WIDTH-1:0] loader_dst_base_addr;
    logic [31:0]           loader_expected_beats;

    logic                  loader_busy;
    logic                  loader_done;
    logic                  loader_error;

    logic                  loader_wr_valid;
    logic                  loader_wr_ready;
    logic [ADDR_WIDTH-1:0] loader_wr_addr;
    logic [DATA_WIDTH-1:0] loader_wr_data;
    logic [DATA_WIDTH/8-1:0] loader_wr_strb;
    logic                  loader_wr_last;

    logic                  loader_rd_en;
    logic [LOADER_CAPTURE_ADDR_WIDTH-1:0] loader_rd_addr;
    logic [DATA_WIDTH-1:0] loader_rd_data;

    logic [31:0]           loader_accepted_beats;
    logic [31:0]           loader_written_beats;
    logic                  loader_tlast_seen;

    // ------------------------------------------------------------
    // Adapter status
    // ------------------------------------------------------------
    logic                  adapter_busy;
    logic                  adapter_done;
    logic                  adapter_error;
    logic [31:0]           adapter_accepted_beats;
    logic [31:0]           adapter_committed_beats;
    logic                  adapter_last_beat_seen;

    // ------------------------------------------------------------
    // Adapter AXI-MM write-master signals toward scratchpad slave
    // ------------------------------------------------------------
    logic [AXI_ID_WIDTH-1:0] adp_awid;
    logic [ADDR_WIDTH-1:0]   adp_awaddr;
    logic [7:0]              adp_awlen;
    logic [2:0]              adp_awsize;
    logic [1:0]              adp_awburst;
    logic                    adp_awvalid;
    logic                    adp_awready;

    logic [DATA_WIDTH-1:0]   adp_wdata;
    logic [DATA_WIDTH/8-1:0] adp_wstrb;
    logic                    adp_wlast;
    logic                    adp_wvalid;
    logic                    adp_wready;

    logic [AXI_ID_WIDTH-1:0] adp_bid;
    logic [1:0]              adp_bresp;
    logic                    adp_bvalid;
    logic                    adp_bready;

    logic [AXI_ID_WIDTH-1:0] adp_arid;
    logic [ADDR_WIDTH-1:0]   adp_araddr;
    logic [7:0]              adp_arlen;
    logic [2:0]              adp_arsize;
    logic [1:0]              adp_arburst;
    logic                    adp_arvalid;
    logic                    adp_arready;

    logic [AXI_ID_WIDTH-1:0] adp_rid;
    logic [DATA_WIDTH-1:0]   adp_rdata;
    logic [1:0]              adp_rresp;
    logic                    adp_rlast;
    logic                    adp_rvalid;
    logic                    adp_rready;

    // ------------------------------------------------------------
    // DUTs
    // ------------------------------------------------------------
    axi_mm2s_dma #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .AXI_ID_WIDTH (AXI_ID_WIDTH),
        .AXI_ARID     (AXI_DMA_ARID)
    ) u_dma (
        .clk            (clk),
        .rst_n          (rst_n),

        .start          (dma_start),
        .src_addr       (dma_src_addr),
        .xfer_len_beats (dma_xfer_len_beats),

        .busy           (dma_busy),
        .done           (dma_done),
        .error          (dma_error),

        .m_axi_awid     (dma_awid),
        .m_axi_awaddr   (dma_awaddr),
        .m_axi_awlen    (dma_awlen),
        .m_axi_awsize   (dma_awsize),
        .m_axi_awburst  (dma_awburst),
        .m_axi_awvalid  (dma_awvalid),
        .m_axi_awready  (dma_awready),

        .m_axi_wdata    (dma_wdata),
        .m_axi_wstrb    (dma_wstrb),
        .m_axi_wlast    (dma_wlast),
        .m_axi_wvalid   (dma_wvalid),
        .m_axi_wready   (dma_wready),

        .m_axi_bid      (dma_bid),
        .m_axi_bresp    (dma_bresp),
        .m_axi_bvalid   (dma_bvalid),
        .m_axi_bready   (dma_bready),

        .m_axi_arid     (dma_arid),
        .m_axi_araddr   (dma_araddr),
        .m_axi_arlen    (dma_arlen),
        .m_axi_arsize   (dma_arsize),
        .m_axi_arburst  (dma_arburst),
        .m_axi_arvalid  (dma_arvalid),
        .m_axi_arready  (dma_arready),

        .m_axi_rid      (dma_rid),
        .m_axi_rdata    (dma_rdata),
        .m_axi_rresp    (dma_rresp),
        .m_axi_rlast    (dma_rlast),
        .m_axi_rvalid   (dma_rvalid),
        .m_axi_rready   (dma_rready),

        .m_axis_tdata   (axis_tdata),
        .m_axis_tvalid  (axis_tvalid),
        .m_axis_tready  (axis_tready),
        .m_axis_tlast   (axis_tlast)
    );

    axi_stream_loader #(
        .ADDR_WIDTH         (ADDR_WIDTH),
        .DATA_WIDTH         (DATA_WIDTH),
        .CAPTURE_DEPTH      (LOADER_CAPTURE_DEPTH),
        .CAPTURE_ADDR_WIDTH (LOADER_CAPTURE_ADDR_WIDTH)
    ) u_loader (
        .clk               (clk),
        .rst_n             (rst_n),

        .start             (loader_start),
        .dst_base_addr     (loader_dst_base_addr),
        .expected_beats    (loader_expected_beats),

        .busy              (loader_busy),
        .done              (loader_done),
        .error             (loader_error),

        .s_axis_tdata      (axis_tdata),
        .s_axis_tvalid     (axis_tvalid),
        .s_axis_tready     (axis_tready),
        .s_axis_tlast      (axis_tlast),

        .wr_valid          (loader_wr_valid),
        .wr_ready          (loader_wr_ready),
        .wr_addr           (loader_wr_addr),
        .wr_data           (loader_wr_data),
        .wr_strb           (loader_wr_strb),
        .wr_last           (loader_wr_last),

        .rd_en             (loader_rd_en),
        .rd_addr           (loader_rd_addr),
        .rd_data           (loader_rd_data),

        .accepted_beats    (loader_accepted_beats),
        .written_beats     (loader_written_beats),
        .tlast_seen        (loader_tlast_seen)
    );

    dma_scratchpad_write_adapter #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .AXI_ID_WIDTH (AXI_ID_WIDTH),
        .AXI_AWID     (AXI_ADAPTER_AWID)
    ) u_adapter (
        .clk             (clk),
        .rst_n           (rst_n),

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

        .m_axi_awid      (adp_awid),
        .m_axi_awaddr    (adp_awaddr),
        .m_axi_awlen     (adp_awlen),
        .m_axi_awsize    (adp_awsize),
        .m_axi_awburst   (adp_awburst),
        .m_axi_awvalid   (adp_awvalid),
        .m_axi_awready   (adp_awready),

        .m_axi_wdata     (adp_wdata),
        .m_axi_wstrb     (adp_wstrb),
        .m_axi_wlast     (adp_wlast),
        .m_axi_wvalid    (adp_wvalid),
        .m_axi_wready    (adp_wready),

        .m_axi_bid       (adp_bid),
        .m_axi_bresp     (adp_bresp),
        .m_axi_bvalid    (adp_bvalid),
        .m_axi_bready    (adp_bready),

        .m_axi_arid      (adp_arid),
        .m_axi_araddr    (adp_araddr),
        .m_axi_arlen     (adp_arlen),
        .m_axi_arsize    (adp_arsize),
        .m_axi_arburst   (adp_arburst),
        .m_axi_arvalid   (adp_arvalid),
        .m_axi_arready   (adp_arready),

        .m_axi_rid       (adp_rid),
        .m_axi_rdata     (adp_rdata),
        .m_axi_rresp     (adp_rresp),
        .m_axi_rlast     (adp_rlast),
        .m_axi_rvalid    (adp_rvalid),
        .m_axi_rready    (adp_rready)
    );

    // ------------------------------------------------------------
    // Source / destination memory models
    // ------------------------------------------------------------
    logic [DATA_WIDTH-1:0] src_mem_model [0:SRC_MEM_DEPTH_WORDS-1];
    logic [DATA_WIDTH-1:0] dst_mem_model [0:DST_MEM_DEPTH_WORDS-1];

    // ------------------------------------------------------------
    // DMA read responder state
    // ------------------------------------------------------------
    logic                    rd_pending_valid;
    logic [ADDR_WIDTH-1:0]   rd_pending_addr;
    logic [AXI_ID_WIDTH-1:0] rd_pending_id;
    int unsigned             rd_pending_delay;

    logic [DATA_WIDTH-1:0]   dma_s_rdata;
    logic [AXI_ID_WIDTH-1:0] dma_s_rid;
    logic [1:0]              dma_s_rresp;
    logic                    dma_s_rlast;
    logic                    dma_s_rvalid;

    logic                    inject_dma_rresp_error;

    int unsigned             total_dma_ar_handshakes;
    int unsigned             total_dma_r_handshakes;

    // ------------------------------------------------------------
    // Adapter write-side slave model control knobs
    // ------------------------------------------------------------
    logic awready_ctrl;
    logic wready_ctrl;
    int unsigned b_latency_cycles;
    int signed   inject_bresp_error_beat;
    logic [AXI_ID_WIDTH-1:0] bad_bid_value;
    int signed   inject_bid_mismatch_beat;

    // ------------------------------------------------------------
    // Adapter write-side slave model internal state
    // ------------------------------------------------------------
    logic                    seen_aw_for_curr;
    logic                    seen_w_for_curr;

    logic [ADDR_WIDTH-1:0]   curr_awaddr;
    logic [DATA_WIDTH-1:0]   curr_wdata;
    logic [DATA_WIDTH/8-1:0] curr_wstrb;

    logic [ADDR_WIDTH-1:0]   sched_awaddr;
    logic [DATA_WIDTH-1:0]   sched_wdata;
    logic [DATA_WIDTH/8-1:0] sched_wstrb;

    logic                    b_pending_valid;
    int unsigned             b_pending_delay;
    logic [1:0]              b_pending_resp;
    logic [AXI_ID_WIDTH-1:0] b_pending_id;
    logic [ADDR_WIDTH-1:0]   b_pending_addr;
    logic [DATA_WIDTH-1:0]   b_pending_data;
    logic [DATA_WIDTH/8-1:0] b_pending_strb;

    int unsigned             total_adapter_aw_handshakes;
    int unsigned             total_adapter_w_handshakes;
    int unsigned             total_adapter_b_handshakes;
    int unsigned             scheduled_b_count;

    // ------------------------------------------------------------
    // Expected / actual write sequences
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] expected_wr_addr_q[$];
    logic [DATA_WIDTH-1:0] expected_wr_data_q[$];
    bit                    expected_wr_last_q[$];

    logic [ADDR_WIDTH-1:0] actual_wr_addr_q[$];
    logic [DATA_WIDTH-1:0] actual_wr_data_q[$];
    bit                    actual_wr_last_q[$];

    // ------------------------------------------------------------
    // Handshake helpers
    // ------------------------------------------------------------
    logic dma_ar_fire;
    logic dma_r_fire;

    logic adp_aw_fire;
    logic adp_w_fire;
    logic adp_b_fire;

    always_comb begin
        dma_ar_fire = dma_arvalid && dma_arready;
        dma_r_fire  = dma_rvalid  && dma_rready;

        adp_aw_fire = adp_awvalid && adp_awready;
        adp_w_fire  = adp_wvalid  && adp_wready;
        adp_b_fire  = adp_bvalid  && adp_bready;
    end

    always_comb begin
        sched_awaddr = adp_aw_fire ? adp_awaddr : curr_awaddr;
        sched_wdata  = adp_w_fire  ? adp_wdata  : curr_wdata;
        sched_wstrb  = adp_w_fire  ? adp_wstrb  : curr_wstrb;
    end

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------
    function automatic int unsigned word_index_from_addr(
        input logic [ADDR_WIDTH-1:0] addr
    );
        return int'(addr >> BEAT_ADDR_LSB);
    endfunction

    function automatic logic [DATA_WIDTH-1:0] make_test_word(
        input int unsigned seed
    );
        logic [31:0] lo;
        logic [31:0] hi;
    begin
        lo = 32'hB000_0000 + seed;
        hi = 32'hC000_0000 + seed;
        return {hi, lo};
    end
    endfunction

    task automatic clear_src_mem();
        int i;
    begin
        for (i = 0; i < SRC_MEM_DEPTH_WORDS; i++) begin
            src_mem_model[i] = '0;
        end
    end
    endtask

    task automatic clear_dst_mem();
        int i;
    begin
        for (i = 0; i < DST_MEM_DEPTH_WORDS; i++) begin
            dst_mem_model[i] = '0;
        end
    end
    endtask

    task automatic clear_expected_and_actual();
    begin
        expected_wr_addr_q.delete();
        expected_wr_data_q.delete();
        expected_wr_last_q.delete();

        actual_wr_addr_q.delete();
        actual_wr_data_q.delete();
        actual_wr_last_q.delete();
    end
    endtask

    task automatic init_tb_outputs();
    begin
        dma_start              = 1'b0;
        dma_src_addr           = '0;
        dma_xfer_len_beats     = '0;

        loader_start           = 1'b0;
        loader_dst_base_addr   = '0;
        loader_expected_beats  = '0;

        loader_rd_en           = 1'b0;
        loader_rd_addr         = '0;

        inject_dma_rresp_error = 1'b0;

        awready_ctrl            = 1'b1;
        wready_ctrl             = 1'b1;
        b_latency_cycles        = 1;
        inject_bresp_error_beat = -1;
        inject_bid_mismatch_beat= -1;
        bad_bid_value           = {AXI_ID_WIDTH{1'b1}};
    end
    endtask

    task automatic apply_reset(int unsigned hold_cycles = 5);
    begin
        rst_n = 1'b0;
        init_tb_outputs();
        clear_expected_and_actual();

        repeat (hold_cycles) @(posedge clk);

        rst_n = 1'b1;
        repeat (2) @(posedge clk);
    end
    endtask

    task automatic preload_src_words(
        input logic [ADDR_WIDTH-1:0] base_addr,
        input int unsigned           beat_count,
        input int unsigned           seed_base
    );
        int unsigned i;
        int unsigned idx;
    begin
        for (i = 0; i < beat_count; i++) begin
            idx = word_index_from_addr(base_addr) + i;

            if (idx >= SRC_MEM_DEPTH_WORDS) begin
                $fatal(1, "[DMA2L2A_TB] preload_src_words out of range: idx=%0d depth=%0d",
                    idx, SRC_MEM_DEPTH_WORDS);
            end

            src_mem_model[idx] = make_test_word(seed_base + i);
        end
    end
    endtask

    task automatic build_expected_write_sequence_from_src(
        input logic [ADDR_WIDTH-1:0] src_base_addr,
        input logic [ADDR_WIDTH-1:0] dst_base_addr,
        input int unsigned           beat_count
    );
        int unsigned i;
        int unsigned idx;
    begin
        expected_wr_addr_q.delete();
        expected_wr_data_q.delete();
        expected_wr_last_q.delete();

        for (i = 0; i < beat_count; i++) begin
            idx = word_index_from_addr(src_base_addr) + i;

            if (idx >= SRC_MEM_DEPTH_WORDS) begin
                $fatal(1, "[DMA2L2A_TB] build_expected_write_sequence_from_src out of range: idx=%0d depth=%0d",
                    idx, SRC_MEM_DEPTH_WORDS);
            end

            expected_wr_addr_q.push_back(dst_base_addr + ADDR_WIDTH'(i * BYTES_PER_BEAT));
            expected_wr_data_q.push_back(src_mem_model[idx]);
            expected_wr_last_q.push_back(i == (beat_count - 1));
        end
    end
    endtask

    task automatic launch_loader(
        input logic [ADDR_WIDTH-1:0] dst_addr,
        input logic [31:0]           exp_beats
    );
    begin
        loader_dst_base_addr  = dst_addr;
        loader_expected_beats = exp_beats;
        loader_start          = 1'b1;
        @(posedge clk);
        loader_start          = 1'b0;
    end
    endtask

    task automatic launch_dma(
        input logic [ADDR_WIDTH-1:0] src_addr,
        input logic [31:0]           len_beats
    );
    begin
        dma_src_addr       = src_addr;
        dma_xfer_len_beats = len_beats;
        dma_start          = 1'b1;
        @(posedge clk);
        dma_start          = 1'b0;
    end
    endtask

    task automatic launch_pair(
        input logic [ADDR_WIDTH-1:0] src_addr,
        input logic [31:0]           dma_len_beats,
        input logic [ADDR_WIDTH-1:0] dst_addr,
        input logic [31:0]           loader_exp_beats
    );
    begin
        launch_loader(dst_addr, loader_exp_beats);
        @(posedge clk);
        launch_dma(src_addr, dma_len_beats);
    end
    endtask

    task automatic wait_done_triplet_or_timeout(
        input int unsigned timeout_cycles,
        input string       tag
    );
        int unsigned i;
        bit dma_done_seen;
        bit loader_done_seen;
        bit adapter_done_seen;
    begin
        dma_done_seen     = 1'b0;
        loader_done_seen  = 1'b0;
        adapter_done_seen = 1'b0;

        for (i = 0; i < timeout_cycles; i++) begin
            @(posedge clk);

            if (dma_done)     dma_done_seen     = 1'b1;
            if (loader_done)  loader_done_seen  = 1'b1;
            if (adapter_done) adapter_done_seen = 1'b1;

            if (dma_done_seen && loader_done_seen && adapter_done_seen) begin
                return;
            end
        end

        $fatal(1, "[DMA2L2A_TB][%s] Timeout waiting for dma/loader/adapter done after %0d cycles",
            tag, timeout_cycles);
    end
    endtask

    task automatic check_busy_clears(
        input string tag
    );
    begin
        @(posedge clk);

        if (dma_busy !== 1'b0) begin
            $fatal(1, "[DMA2L2A_TB][%s] dma_busy did not clear after done", tag);
        end

        if (loader_busy !== 1'b0) begin
            $fatal(1, "[DMA2L2A_TB][%s] loader_busy did not clear after done", tag);
        end

        if (adapter_busy !== 1'b0) begin
            $fatal(1, "[DMA2L2A_TB][%s] adapter_busy did not clear after done", tag);
        end
    end
    endtask

    task automatic expect_dma_ar_count_delta(
        input int unsigned ar_before,
        input int unsigned exp_delta,
        input string       tag
    );
        int unsigned delta;
    begin
        delta = total_dma_ar_handshakes - ar_before;
        if (delta != exp_delta) begin
            $fatal(1, "[DMA2L2A_TB][%s] DMA AR delta mismatch: got=%0d exp=%0d",
                tag, delta, exp_delta);
        end
    end
    endtask

    task automatic compare_actual_write_sequence(
        input string tag
    );
        int unsigned i;
    begin
        if (actual_wr_addr_q.size() != expected_wr_addr_q.size()) begin
            $fatal(1, "[DMA2L2A_TB][%s] Write count mismatch: got=%0d exp=%0d",
                tag, actual_wr_addr_q.size(), expected_wr_addr_q.size());
        end

        if (actual_wr_data_q.size() != expected_wr_data_q.size()) begin
            $fatal(1, "[DMA2L2A_TB][%s] Data count mismatch: got=%0d exp=%0d",
                tag, actual_wr_data_q.size(), expected_wr_data_q.size());
        end

        if (actual_wr_last_q.size() != expected_wr_last_q.size()) begin
            $fatal(1, "[DMA2L2A_TB][%s] Last count mismatch: got=%0d exp=%0d",
                tag, actual_wr_last_q.size(), expected_wr_last_q.size());
        end

        for (i = 0; i < expected_wr_addr_q.size(); i++) begin
            if (actual_wr_addr_q[i] !== expected_wr_addr_q[i]) begin
                $fatal(1, "[DMA2L2A_TB][%s] AWADDR mismatch at beat %0d: got=0x%08h exp=0x%08h",
                    tag, i, actual_wr_addr_q[i], expected_wr_addr_q[i]);
            end

            if (actual_wr_data_q[i] !== expected_wr_data_q[i]) begin
                $fatal(1, "[DMA2L2A_TB][%s] WDATA mismatch at beat %0d: got=0x%016h exp=0x%016h",
                    tag, i, actual_wr_data_q[i], expected_wr_data_q[i]);
            end

            if (actual_wr_last_q[i] !== 1'b1) begin
                $fatal(1, "[DMA2L2A_TB][%s] WLAST expected 1 at beat %0d", tag, i);
            end
        end
    end
    endtask

    task automatic compare_loader_readback_against_expected(
        input int unsigned beat_count,
        input string       tag
    );
        int unsigned i;
    begin
        loader_rd_en = 1'b1;

        for (i = 0; i < beat_count; i++) begin
            loader_rd_addr = i[LOADER_CAPTURE_ADDR_WIDTH-1:0];
            #1;
            if (loader_rd_data !== expected_wr_data_q[i]) begin
                $fatal(1, "[DMA2L2A_TB][%s] Loader readback mismatch at beat %0d: got=0x%016h exp=0x%016h",
                    tag, i, loader_rd_data, expected_wr_data_q[i]);
            end
        end

        loader_rd_en   = 1'b0;
        loader_rd_addr = '0;
    end
    endtask

    task automatic compare_dst_mem_against_expected(
        input int unsigned beat_count,
        input string       tag
    );
        int unsigned i;
        int unsigned idx;
    begin
        for (i = 0; i < beat_count; i++) begin
            idx = word_index_from_addr(expected_wr_addr_q[i]);

            if (idx >= DST_MEM_DEPTH_WORDS) begin
                $fatal(1, "[DMA2L2A_TB][%s] dst mem compare out of range: idx=%0d depth=%0d",
                    tag, idx, DST_MEM_DEPTH_WORDS);
            end

            if (dst_mem_model[idx] !== expected_wr_data_q[i]) begin
                $fatal(1, "[DMA2L2A_TB][%s] DST mem mismatch at beat %0d: got=0x%016h exp=0x%016h",
                    tag, i, dst_mem_model[idx], expected_wr_data_q[i]);
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // DMA source-side AXI read slave
    // ------------------------------------------------------------
    assign dma_awready = 1'b0;
    assign dma_wready  = 1'b0;
    assign dma_bid     = '0;
    assign dma_bresp   = '0;
    assign dma_bvalid  = 1'b0;

    assign dma_arready = rst_n && !rd_pending_valid && !dma_s_rvalid;

    assign dma_rid     = dma_s_rid;
    assign dma_rdata   = dma_s_rdata;
    assign dma_rresp   = dma_s_rresp;
    assign dma_rlast   = dma_s_rlast;
    assign dma_rvalid  = dma_s_rvalid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_pending_valid        <= 1'b0;
            rd_pending_addr         <= '0;
            rd_pending_id           <= '0;
            rd_pending_delay        <= 0;

            dma_s_rdata             <= '0;
            dma_s_rid               <= '0;
            dma_s_rresp             <= AXI_RESP_OKAY;
            dma_s_rlast             <= 1'b0;
            dma_s_rvalid            <= 1'b0;

            total_dma_ar_handshakes <= 0;
            total_dma_r_handshakes  <= 0;
        end
        else begin
            if (dma_ar_fire) begin
                rd_pending_valid        <= 1'b1;
                rd_pending_addr         <= dma_araddr;
                rd_pending_id           <= dma_arid;
                rd_pending_delay        <= READ_LATENCY_CYCLES;
                total_dma_ar_handshakes <= total_dma_ar_handshakes + 1;
            end
            else if (rd_pending_valid && (rd_pending_delay != 0)) begin
                rd_pending_delay <= rd_pending_delay - 1;
            end

            if (dma_r_fire) begin
                dma_s_rvalid           <= 1'b0;
                dma_s_rlast            <= 1'b0;
                dma_s_rresp            <= AXI_RESP_OKAY;
                dma_s_rdata            <= '0;
                dma_s_rid              <= '0;
                total_dma_r_handshakes <= total_dma_r_handshakes + 1;
            end

            if (!dma_s_rvalid && rd_pending_valid && (rd_pending_delay == 0)) begin
                int unsigned idx;

                idx = word_index_from_addr(rd_pending_addr);
                if (idx >= SRC_MEM_DEPTH_WORDS) begin
                    $fatal(1, "[DMA2L2A_TB] DMA read out of range: addr=0x%08h idx=%0d depth=%0d",
                        rd_pending_addr, idx, SRC_MEM_DEPTH_WORDS);
                end

                dma_s_rvalid <= 1'b1;
                dma_s_rid    <= rd_pending_id;
                dma_s_rdata  <= src_mem_model[idx];
                dma_s_rresp  <= inject_dma_rresp_error ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
                dma_s_rlast  <= 1'b1;

                rd_pending_valid <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------
    // Adapter downstream AXI write slave
    // ------------------------------------------------------------
    assign adp_awready = rst_n && awready_ctrl && !adp_bvalid;
    assign adp_wready  = rst_n && wready_ctrl  && !adp_bvalid;

    assign adp_arready = 1'b0;
    assign adp_rid     = '0;
    assign adp_rdata   = '0;
    assign adp_rresp   = '0;
    assign adp_rlast   = 1'b0;
    assign adp_rvalid  = 1'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seen_aw_for_curr           <= 1'b0;
            seen_w_for_curr            <= 1'b0;

            curr_awaddr                <= '0;
            curr_wdata                 <= '0;
            curr_wstrb                 <= '0;

            b_pending_valid            <= 1'b0;
            b_pending_delay            <= 0;
            b_pending_resp             <= AXI_RESP_OKAY;
            b_pending_id               <= AXI_ADAPTER_AWID;
            b_pending_addr             <= '0;
            b_pending_data             <= '0;
            b_pending_strb             <= '0;

            adp_bvalid                 <= 1'b0;
            adp_bresp                  <= AXI_RESP_OKAY;
            adp_bid                    <= AXI_ADAPTER_AWID;

            total_adapter_aw_handshakes<= 0;
            total_adapter_w_handshakes <= 0;
            total_adapter_b_handshakes <= 0;
            scheduled_b_count          <= 0;
        end
        else begin
            if (adp_aw_fire) begin
                seen_aw_for_curr <= 1'b1;
                curr_awaddr      <= adp_awaddr;
                total_adapter_aw_handshakes <= total_adapter_aw_handshakes + 1;
            end

            if (adp_w_fire) begin
                seen_w_for_curr <= 1'b1;
                curr_wdata      <= adp_wdata;
                curr_wstrb      <= adp_wstrb;
                total_adapter_w_handshakes <= total_adapter_w_handshakes + 1;
            end

            if (adp_b_fire) begin
                int unsigned idx;
                int unsigned b;

                if (adp_bresp == AXI_RESP_OKAY) begin
                    idx = word_index_from_addr(b_pending_addr);
                    if (idx >= DST_MEM_DEPTH_WORDS) begin
                        $fatal(1, "[DMA2L2A_TB] Adapter write out of range: addr=0x%08h idx=%0d depth=%0d",
                            b_pending_addr, idx, DST_MEM_DEPTH_WORDS);
                    end

                    for (b = 0; b < BYTES_PER_BEAT; b++) begin
                        if (b_pending_strb[b]) begin
                            dst_mem_model[idx][8*b +: 8] <= b_pending_data[8*b +: 8];
                        end
                    end
                end

                adp_bvalid <= 1'b0;
                adp_bresp  <= AXI_RESP_OKAY;
                adp_bid    <= AXI_ADAPTER_AWID;

                total_adapter_b_handshakes <= total_adapter_b_handshakes + 1;
            end

            if (!adp_bvalid && !b_pending_valid &&
                (seen_aw_for_curr || adp_aw_fire) &&
                (seen_w_for_curr  || adp_w_fire)) begin

                int unsigned next_b_index;

                next_b_index = scheduled_b_count + 1;
                scheduled_b_count <= next_b_index;

                b_pending_valid <= 1'b1;
                b_pending_delay <= b_latency_cycles;
                b_pending_addr  <= sched_awaddr;
                b_pending_data  <= sched_wdata;
                b_pending_strb  <= sched_wstrb;

                if (inject_bresp_error_beat == next_b_index) begin
                    b_pending_resp <= AXI_RESP_SLVERR;
                end
                else begin
                    b_pending_resp <= AXI_RESP_OKAY;
                end

                if (inject_bid_mismatch_beat == next_b_index) begin
                    b_pending_id <= bad_bid_value;
                end
                else begin
                    b_pending_id <= AXI_ADAPTER_AWID;
                end

                seen_aw_for_curr <= 1'b0;
                seen_w_for_curr  <= 1'b0;
            end
            else if (b_pending_valid && (b_pending_delay != 0)) begin
                b_pending_delay <= b_pending_delay - 1;
            end

            if (!adp_bvalid && b_pending_valid && (b_pending_delay == 0)) begin
                adp_bvalid      <= 1'b1;
                adp_bresp       <= b_pending_resp;
                adp_bid         <= b_pending_id;
                b_pending_valid <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------
    // Capture actual adapter write sequence
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            actual_wr_addr_q.delete();
            actual_wr_data_q.delete();
            actual_wr_last_q.delete();
        end
        else begin
            if (adp_aw_fire) begin
                if (adp_awid !== AXI_ADAPTER_AWID) begin
                    $fatal(1, "[DMA2L2A_TB] AWID mismatch: got=0x%0h exp=0x%0h",
                        adp_awid, AXI_ADAPTER_AWID);
                end

                if (adp_awlen !== 8'd0) begin
                    $fatal(1, "[DMA2L2A_TB] AWLEN mismatch: got=%0d exp=0", adp_awlen);
                end

                if (adp_awburst !== 2'b01) begin
                    $fatal(1, "[DMA2L2A_TB] AWBURST mismatch: got=0x%0h exp=INCR", adp_awburst);
                end

                actual_wr_addr_q.push_back(adp_awaddr);
            end

            if (adp_w_fire) begin
                if (adp_wstrb !== FULL_STRB) begin
                    $fatal(1, "[DMA2L2A_TB] WSTRB mismatch: got=0x%0h exp=0x%0h",
                        adp_wstrb, FULL_STRB);
                end

                actual_wr_data_q.push_back(adp_wdata);
                actual_wr_last_q.push_back(adp_wlast);
            end
        end
    end

    // ------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------
    task automatic run_exact_length_success_test();
        logic [ADDR_WIDTH-1:0] src_base;
        logic [ADDR_WIDTH-1:0] dst_base;
        int unsigned           ar_before;
    begin
        $display("[DMA2L2A_TB] --------------------------------------------------");
        $display("[DMA2L2A_TB] TEST 1: exact-length success");
        $display("[DMA2L2A_TB] --------------------------------------------------");

        apply_reset();
        clear_src_mem();
        clear_dst_mem();

        src_base = 32'h0000_0100;
        dst_base = 32'h0000_1000;

        preload_src_words(src_base, 4, 16'h0010);
        build_expected_write_sequence_from_src(src_base, dst_base, 4);

        ar_before = total_dma_ar_handshakes;

        launch_pair(src_base, 4, dst_base, 4);
        wait_done_triplet_or_timeout(500, "exact_length_success");
        check_busy_clears("exact_length_success");

        if (dma_error !== 1'b0) begin
            $fatal(1, "[DMA2L2A_TB][exact_length_success] dma_error asserted unexpectedly");
        end

        if (loader_error !== 1'b0) begin
            $fatal(1, "[DMA2L2A_TB][exact_length_success] loader_error asserted unexpectedly");
        end

        if (adapter_error !== 1'b0) begin
            $fatal(1, "[DMA2L2A_TB][exact_length_success] adapter_error asserted unexpectedly");
        end

        if (loader_accepted_beats != 32'd4 || loader_written_beats != 32'd4) begin
            $fatal(1, "[DMA2L2A_TB][exact_length_success] loader beat counters mismatch");
        end

        if (adapter_accepted_beats != 32'd4 || adapter_committed_beats != 32'd4) begin
            $fatal(1, "[DMA2L2A_TB][exact_length_success] adapter beat counters mismatch");
        end

        if (loader_tlast_seen !== 1'b1 || adapter_last_beat_seen !== 1'b1) begin
            $fatal(1, "[DMA2L2A_TB][exact_length_success] last/tlast seen mismatch");
        end

        expect_dma_ar_count_delta(ar_before, 4, "exact_length_success");
        compare_actual_write_sequence("exact_length_success");
        compare_loader_readback_against_expected(4, "exact_length_success");
        compare_dst_mem_against_expected(4, "exact_length_success");

        $display("[DMA2L2A_TB] PASS: exact-length success");
    end
    endtask

    task automatic run_capture_until_tlast_test();
        logic [ADDR_WIDTH-1:0] src_base;
        logic [ADDR_WIDTH-1:0] dst_base;
        int unsigned           ar_before;
    begin
        $display("[DMA2L2A_TB] --------------------------------------------------");
        $display("[DMA2L2A_TB] TEST 2: capture-until-tlast mode");
        $display("[DMA2L2A_TB] --------------------------------------------------");

        apply_reset();
        clear_src_mem();
        clear_dst_mem();

        src_base = 32'h0000_0200;
        dst_base = 32'h0000_1100;

        preload_src_words(src_base, 3, 16'h0100);
        build_expected_write_sequence_from_src(src_base, dst_base, 3);

        ar_before = total_dma_ar_handshakes;

        launch_pair(src_base, 3, dst_base, 0);
        wait_done_triplet_or_timeout(500, "capture_until_tlast");
        check_busy_clears("capture_until_tlast");

        if (dma_error !== 1'b0 || loader_error !== 1'b0 || adapter_error !== 1'b0) begin
            $fatal(1, "[DMA2L2A_TB][capture_until_tlast] unexpected error on dma/loader/adapter");
        end

        if (loader_accepted_beats != 32'd3 || loader_written_beats != 32'd3) begin
            $fatal(1, "[DMA2L2A_TB][capture_until_tlast] loader beat counters mismatch");
        end

        if (adapter_accepted_beats != 32'd3 || adapter_committed_beats != 32'd3) begin
            $fatal(1, "[DMA2L2A_TB][capture_until_tlast] adapter beat counters mismatch");
        end

        expect_dma_ar_count_delta(ar_before, 3, "capture_until_tlast");
        compare_actual_write_sequence("capture_until_tlast");
        compare_loader_readback_against_expected(3, "capture_until_tlast");
        compare_dst_mem_against_expected(3, "capture_until_tlast");

        $display("[DMA2L2A_TB] PASS: capture-until-tlast mode");
    end
    endtask

    task automatic run_write_side_backpressure_test();
        logic [ADDR_WIDTH-1:0] src_base;
        logic [ADDR_WIDTH-1:0] dst_base;
        int unsigned           ar_before;
    begin
        $display("[DMA2L2A_TB] --------------------------------------------------");
        $display("[DMA2L2A_TB] TEST 3: write-side backpressure");
        $display("[DMA2L2A_TB] --------------------------------------------------");

        apply_reset();
        clear_src_mem();
        clear_dst_mem();

        src_base = 32'h0000_0300;
        dst_base = 32'h0000_1200;

        preload_src_words(src_base, 4, 16'h0200);
        build_expected_write_sequence_from_src(src_base, dst_base, 4);

        ar_before = total_dma_ar_handshakes;

        fork
            begin
                awready_ctrl     = 1'b1;
                wready_ctrl      = 1'b1;
                b_latency_cycles = 3;

                wait (adapter_busy === 1'b1);

                repeat (2) @(posedge clk);
                awready_ctrl = 1'b0;
                repeat (2) @(posedge clk);
                awready_ctrl = 1'b1;

                repeat (1) @(posedge clk);
                wready_ctrl = 1'b0;
                repeat (3) @(posedge clk);
                wready_ctrl = 1'b1;
            end
        join_none

        launch_pair(src_base, 4, dst_base, 4);
        wait_done_triplet_or_timeout(800, "write_side_backpressure");
        check_busy_clears("write_side_backpressure");

        if (dma_error !== 1'b0 || loader_error !== 1'b0 || adapter_error !== 1'b0) begin
            $fatal(1, "[DMA2L2A_TB][write_side_backpressure] unexpected error on dma/loader/adapter");
        end

        if (loader_accepted_beats != 32'd4 || loader_written_beats != 32'd4) begin
            $fatal(1, "[DMA2L2A_TB][write_side_backpressure] loader beat counters mismatch");
        end

        if (adapter_accepted_beats != 32'd4 || adapter_committed_beats != 32'd4) begin
            $fatal(1, "[DMA2L2A_TB][write_side_backpressure] adapter beat counters mismatch");
        end

        expect_dma_ar_count_delta(ar_before, 4, "write_side_backpressure");
        compare_actual_write_sequence("write_side_backpressure");
        compare_loader_readback_against_expected(4, "write_side_backpressure");
        compare_dst_mem_against_expected(4, "write_side_backpressure");

        $display("[DMA2L2A_TB] PASS: write-side backpressure");
    end
    endtask

    task automatic run_adapter_bresp_error_test();
        logic [ADDR_WIDTH-1:0] src_base;
        logic [ADDR_WIDTH-1:0] dst_base;
        int unsigned           ar_before;
    begin
        $display("[DMA2L2A_TB] --------------------------------------------------");
        $display("[DMA2L2A_TB] TEST 4: adapter BRESP error");
        $display("[DMA2L2A_TB] --------------------------------------------------");

        apply_reset();
        clear_src_mem();
        clear_dst_mem();

        src_base = 32'h0000_0400;
        dst_base = 32'h0000_1300;

        preload_src_words(src_base, 3, 16'h0300);
        build_expected_write_sequence_from_src(src_base, dst_base, 3);

        ar_before = total_dma_ar_handshakes;
        inject_bresp_error_beat = 2;

        launch_pair(src_base, 3, dst_base, 3);
        wait_done_triplet_or_timeout(600, "adapter_bresp_error");
        check_busy_clears("adapter_bresp_error");

        if (dma_error !== 1'b0) begin
            $fatal(1, "[DMA2L2A_TB][adapter_bresp_error] dma_error asserted unexpectedly");
        end

        if (loader_error !== 1'b0) begin
            $fatal(1, "[DMA2L2A_TB][adapter_bresp_error] loader_error asserted unexpectedly");
        end

        if (adapter_error !== 1'b1) begin
            $fatal(1, "[DMA2L2A_TB][adapter_bresp_error] adapter_error expected 1");
        end

        if (loader_accepted_beats != 32'd3 || loader_written_beats != 32'd3) begin
            $fatal(1, "[DMA2L2A_TB][adapter_bresp_error] loader beat counters mismatch");
        end

        if (adapter_accepted_beats != 32'd3 || adapter_committed_beats != 32'd3) begin
            $fatal(1, "[DMA2L2A_TB][adapter_bresp_error] adapter beat counters mismatch");
        end

        expect_dma_ar_count_delta(ar_before, 3, "adapter_bresp_error");
        compare_actual_write_sequence("adapter_bresp_error");
        compare_loader_readback_against_expected(3, "adapter_bresp_error");

        $display("[DMA2L2A_TB] PASS: adapter BRESP error");
    end
    endtask

    task automatic run_loader_longer_than_actual_mismatch_test();
        logic [ADDR_WIDTH-1:0] src_base;
        logic [ADDR_WIDTH-1:0] dst_base;
        int unsigned           ar_before;
    begin
        $display("[DMA2L2A_TB] --------------------------------------------------");
        $display("[DMA2L2A_TB] TEST 5: loader expected-beats longer-than-actual");
        $display("[DMA2L2A_TB] --------------------------------------------------");

        apply_reset();
        clear_src_mem();
        clear_dst_mem();

        src_base = 32'h0000_0500;
        dst_base = 32'h0000_1400;

        preload_src_words(src_base, 4, 16'h0400);
        build_expected_write_sequence_from_src(src_base, dst_base, 4);

        ar_before = total_dma_ar_handshakes;

        launch_pair(src_base, 4, dst_base, 5);
        wait_done_triplet_or_timeout(600, "loader_longer_than_actual");
        check_busy_clears("loader_longer_than_actual");

        if (dma_error !== 1'b0) begin
            $fatal(1, "[DMA2L2A_TB][loader_longer_than_actual] dma_error asserted unexpectedly");
        end

        if (loader_error !== 1'b1) begin
            $fatal(1, "[DMA2L2A_TB][loader_longer_than_actual] loader_error expected 1");
        end

        if (adapter_error !== 1'b0) begin
            $fatal(1, "[DMA2L2A_TB][loader_longer_than_actual] adapter_error asserted unexpectedly");
        end

        if (loader_accepted_beats != 32'd4 || loader_written_beats != 32'd4) begin
            $fatal(1, "[DMA2L2A_TB][loader_longer_than_actual] loader beat counters mismatch");
        end

        if (adapter_accepted_beats != 32'd4 || adapter_committed_beats != 32'd4) begin
            $fatal(1, "[DMA2L2A_TB][loader_longer_than_actual] adapter beat counters mismatch");
        end

        expect_dma_ar_count_delta(ar_before, 4, "loader_longer_than_actual");
        compare_actual_write_sequence("loader_longer_than_actual");
        compare_loader_readback_against_expected(4, "loader_longer_than_actual");
        compare_dst_mem_against_expected(4, "loader_longer_than_actual");

        $display("[DMA2L2A_TB] PASS: loader expected-beats longer-than-actual");
    end
    endtask

    // ------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------
    initial begin
        init_tb_outputs();
        clear_src_mem();
        clear_dst_mem();
        clear_expected_and_actual();

        run_exact_length_success_test();
        run_capture_until_tlast_test();
        run_write_side_backpressure_test();
        run_adapter_bresp_error_test();
        run_loader_longer_than_actual_mismatch_test();

        $display("");
        $display("[DMA2L2A_TB] =====================================================");
        $display("[DMA2L2A_TB] All DMA->Loader->Adapter integration tests PASSED");
        $display("[DMA2L2A_TB] =====================================================");
        $display("");

        #20;
        $finish;
    end

endmodule

`endif