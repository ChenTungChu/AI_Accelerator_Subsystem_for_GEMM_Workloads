// File: tb/dma/axi_mm2s_dma_to_loader_tb_top.sv
`ifndef AXI_MM2S_DMA_TO_LOADER_TB_TOP_SV
`define AXI_MM2S_DMA_TO_LOADER_TB_TOP_SV

`timescale 1ns/1ps

module axi_mm2s_dma_to_loader_tb_top;

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    localparam int ADDR_WIDTH          = 32;
    localparam int DATA_WIDTH          = 64;
    localparam int AXI_ID_WIDTH        = 4;
    localparam int BYTES_PER_BEAT      = DATA_WIDTH / 8;
    localparam int BEAT_ADDR_LSB       = (BYTES_PER_BEAT <= 1) ? 0 : $clog2(BYTES_PER_BEAT);

    localparam int MEM_DEPTH_WORDS     = 1024;
    localparam int READ_LATENCY_CYCLES = 2;

    localparam int LOADER_CAPTURE_DEPTH      = 1024;
    localparam int LOADER_CAPTURE_ADDR_WIDTH = (LOADER_CAPTURE_DEPTH <= 1) ? 1 : $clog2(LOADER_CAPTURE_DEPTH);

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
    // AXI-MM wires for DMA
    // ------------------------------------------------------------
    logic [AXI_ID_WIDTH-1:0] m_axi_awid;
    logic [ADDR_WIDTH-1:0]   m_axi_awaddr;
    logic [7:0]              m_axi_awlen;
    logic [2:0]              m_axi_awsize;
    logic [1:0]              m_axi_awburst;
    logic                    m_axi_awvalid;
    logic                    m_axi_awready;

    logic [DATA_WIDTH-1:0]   m_axi_wdata;
    logic [DATA_WIDTH/8-1:0] m_axi_wstrb;
    logic                    m_axi_wlast;
    logic                    m_axi_wvalid;
    logic                    m_axi_wready;

    logic [AXI_ID_WIDTH-1:0] m_axi_bid;
    logic [1:0]              m_axi_bresp;
    logic                    m_axi_bvalid;
    logic                    m_axi_bready;

    logic [AXI_ID_WIDTH-1:0] m_axi_arid;
    logic [ADDR_WIDTH-1:0]   m_axi_araddr;
    logic [7:0]              m_axi_arlen;
    logic [2:0]              m_axi_arsize;
    logic [1:0]              m_axi_arburst;
    logic                    m_axi_arvalid;
    logic                    m_axi_arready;

    logic [AXI_ID_WIDTH-1:0] m_axi_rid;
    logic [DATA_WIDTH-1:0]   m_axi_rdata;
    logic [1:0]              m_axi_rresp;
    logic                    m_axi_rlast;
    logic                    m_axi_rvalid;
    logic                    m_axi_rready;

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
    // DUTs
    // ------------------------------------------------------------
    axi_mm2s_dma #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .AXI_ID_WIDTH (AXI_ID_WIDTH),
        .AXI_ARID     ('0)
    ) u_dma (
        .clk            (clk),
        .rst_n          (rst_n),

        .start          (dma_start),
        .src_addr       (dma_src_addr),
        .xfer_len_beats (dma_xfer_len_beats),

        .busy           (dma_busy),
        .done           (dma_done),
        .error          (dma_error),

        .m_axi_awid     (m_axi_awid),
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),

        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),

        .m_axi_bid      (m_axi_bid),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready),

        .m_axi_arid     (m_axi_arid),
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arlen    (m_axi_arlen),
        .m_axi_arsize   (m_axi_arsize),
        .m_axi_arburst  (m_axi_arburst),
        .m_axi_arvalid  (m_axi_arvalid),
        .m_axi_arready  (m_axi_arready),

        .m_axi_rid      (m_axi_rid),
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_rvalid   (m_axi_rvalid),
        .m_axi_rready   (m_axi_rready),

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

    // ------------------------------------------------------------
    // Memory model for DMA source side
    // ------------------------------------------------------------
    logic [DATA_WIDTH-1:0] mem_model [0:MEM_DEPTH_WORDS-1];

    // ------------------------------------------------------------
    // AXI-MM read responder state
    // ------------------------------------------------------------
    logic                    rd_pending_valid;
    logic [ADDR_WIDTH-1:0]   rd_pending_addr;
    logic [AXI_ID_WIDTH-1:0] rd_pending_id;
    int unsigned             rd_pending_delay;

    logic [DATA_WIDTH-1:0]   s_rdata;
    logic [AXI_ID_WIDTH-1:0] s_rid;
    logic [1:0]              s_rresp;
    logic                    s_rlast;
    logic                    s_rvalid;

    logic                    inject_rresp_error;

    int unsigned             total_ar_handshakes;
    int unsigned             total_r_handshakes;
    int unsigned             total_loader_wr_handshakes;

    // ------------------------------------------------------------
    // Expected / actual write sequence
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] expected_wr_addr_q[$];
    logic [DATA_WIDTH-1:0] expected_wr_data_q[$];
    bit                    expected_wr_last_q[$];

    logic [ADDR_WIDTH-1:0] actual_wr_addr_q[$];
    logic [DATA_WIDTH-1:0] actual_wr_data_q[$];
    bit                    actual_wr_last_q[$];

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
        lo = 32'h7000_0000 + seed;
        hi = 32'h8000_0000 + seed;
        return {hi, lo};
    end
    endfunction

    task automatic clear_mem_model();
        int i;
    begin
        for (i = 0; i < MEM_DEPTH_WORDS; i++) begin
            mem_model[i] = '0;
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
        dma_start            = 1'b0;
        dma_src_addr         = '0;
        dma_xfer_len_beats   = '0;

        loader_start         = 1'b0;
        loader_dst_base_addr = '0;
        loader_expected_beats = '0;

        loader_wr_ready      = 1'b1;

        loader_rd_en         = 1'b0;
        loader_rd_addr       = '0;

        inject_rresp_error   = 1'b0;
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
        input logic [ADDR_WIDTH-1:0] src_base_addr,
        input int unsigned           beat_count,
        input int unsigned           seed_base
    );
        int unsigned i;
        int unsigned idx;
    begin
        for (i = 0; i < beat_count; i++) begin
            idx = word_index_from_addr(src_base_addr) + i;

            if (idx >= MEM_DEPTH_WORDS) begin
                $fatal(1, "[DMA2LDR_TB] preload_src_words out of range: idx=%0d depth=%0d",
                    idx, MEM_DEPTH_WORDS);
            end

            mem_model[idx] = make_test_word(seed_base + i);
        end
    end
    endtask

    task automatic build_expected_write_sequence_from_mem(
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

            if (idx >= MEM_DEPTH_WORDS) begin
                $fatal(1, "[DMA2LDR_TB] build_expected_write_sequence_from_mem out of range: idx=%0d depth=%0d",
                    idx, MEM_DEPTH_WORDS);
            end

            expected_wr_addr_q.push_back(dst_base_addr + ADDR_WIDTH'(i * BYTES_PER_BEAT));
            expected_wr_data_q.push_back(mem_model[idx]);
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
        input logic [31:0]           len_beats,
        input logic [ADDR_WIDTH-1:0] dst_addr,
        input logic [31:0]           exp_beats
    );
    begin
        launch_loader(dst_addr, exp_beats);
        @(posedge clk);
        launch_dma(src_addr, len_beats);
    end
    endtask

    task automatic wait_done_pair_or_timeout(
        input int unsigned timeout_cycles,
        input string       tag
    );
        int unsigned i;
        bit dma_done_seen;
        bit loader_done_seen;
    begin
        dma_done_seen    = 1'b0;
        loader_done_seen = 1'b0;

        for (i = 0; i < timeout_cycles; i++) begin
            @(posedge clk);

            if (dma_done === 1'b1) begin
                dma_done_seen = 1'b1;
            end

            if (loader_done === 1'b1) begin
                loader_done_seen = 1'b1;
            end

            if (dma_done_seen && loader_done_seen) begin
                return;
            end
        end

        $fatal(1, "[DMA2LDR_TB][%s] Timeout waiting for dma_done / loader_done after %0d cycles",
            tag, timeout_cycles);
    end
    endtask

    task automatic check_busy_clears(
        input string tag
    );
    begin
        @(posedge clk);

        if (dma_busy !== 1'b0) begin
            $fatal(1, "[DMA2LDR_TB][%s] dma_busy did not clear after done", tag);
        end

        if (loader_busy !== 1'b0) begin
            $fatal(1, "[DMA2LDR_TB][%s] loader_busy did not clear after done", tag);
        end
    end
    endtask

    task automatic expect_ar_count_delta(
        input int unsigned ar_before,
        input int unsigned exp_delta,
        input string       tag
    );
        int unsigned delta;
    begin
        delta = total_ar_handshakes - ar_before;
        if (delta != exp_delta) begin
            $fatal(1, "[DMA2LDR_TB][%s] AR handshake delta mismatch: got=%0d exp=%0d",
                tag, delta, exp_delta);
        end
    end
    endtask

    task automatic compare_write_sequence(
        input string tag
    );
        int unsigned i;
    begin
        if (actual_wr_addr_q.size() != expected_wr_addr_q.size()) begin
            $fatal(1, "[DMA2LDR_TB][%s] Write count mismatch: got=%0d exp=%0d",
                tag, actual_wr_addr_q.size(), expected_wr_addr_q.size());
        end

        if (actual_wr_data_q.size() != expected_wr_data_q.size()) begin
            $fatal(1, "[DMA2LDR_TB][%s] Data count mismatch: got=%0d exp=%0d",
                tag, actual_wr_data_q.size(), expected_wr_data_q.size());
        end

        if (actual_wr_last_q.size() != expected_wr_last_q.size()) begin
            $fatal(1, "[DMA2LDR_TB][%s] Last count mismatch: got=%0d exp=%0d",
                tag, actual_wr_last_q.size(), expected_wr_last_q.size());
        end

        for (i = 0; i < expected_wr_addr_q.size(); i++) begin
            if (actual_wr_addr_q[i] !== expected_wr_addr_q[i]) begin
                $fatal(1, "[DMA2LDR_TB][%s] wr_addr mismatch at beat %0d: got=0x%08h exp=0x%08h",
                    tag, i, actual_wr_addr_q[i], expected_wr_addr_q[i]);
            end

            if (actual_wr_data_q[i] !== expected_wr_data_q[i]) begin
                $fatal(1, "[DMA2LDR_TB][%s] wr_data mismatch at beat %0d: got=0x%016h exp=0x%016h",
                    tag, i, actual_wr_data_q[i], expected_wr_data_q[i]);
            end

            if (actual_wr_last_q[i] !== expected_wr_last_q[i]) begin
                $fatal(1, "[DMA2LDR_TB][%s] wr_last mismatch at beat %0d: got=%0b exp=%0b",
                    tag, i, actual_wr_last_q[i], expected_wr_last_q[i]);
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
                $fatal(1, "[DMA2LDR_TB][%s] Loader readback mismatch at beat %0d: got=0x%016h exp=0x%016h",
                    tag, i, loader_rd_data, expected_wr_data_q[i]);
            end
        end

        loader_rd_en   = 1'b0;
        loader_rd_addr = '0;
    end
    endtask

    // ------------------------------------------------------------
    // AXI slave tie-offs / responses
    // ------------------------------------------------------------
    assign m_axi_awready = 1'b0;
    assign m_axi_wready  = 1'b0;
    assign m_axi_bid     = '0;
    assign m_axi_bresp   = '0;
    assign m_axi_bvalid  = 1'b0;

    assign m_axi_arready = rst_n && !rd_pending_valid && !s_rvalid;

    assign m_axi_rid     = s_rid;
    assign m_axi_rdata   = s_rdata;
    assign m_axi_rresp   = s_rresp;
    assign m_axi_rlast   = s_rlast;
    assign m_axi_rvalid  = s_rvalid;

    // ------------------------------------------------------------
    // AXI-MM read responder
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_pending_valid     <= 1'b0;
            rd_pending_addr      <= '0;
            rd_pending_id        <= '0;
            rd_pending_delay     <= 0;

            s_rdata              <= '0;
            s_rid                <= '0;
            s_rresp              <= AXI_RESP_OKAY;
            s_rlast              <= 1'b0;
            s_rvalid             <= 1'b0;

            total_ar_handshakes  <= 0;
            total_r_handshakes   <= 0;
        end
        else begin
            if (m_axi_arvalid && m_axi_arready) begin
                rd_pending_valid    <= 1'b1;
                rd_pending_addr     <= m_axi_araddr;
                rd_pending_id       <= m_axi_arid;
                rd_pending_delay    <= READ_LATENCY_CYCLES;

                total_ar_handshakes <= total_ar_handshakes + 1;
            end
            else if (rd_pending_valid && (rd_pending_delay != 0)) begin
                rd_pending_delay <= rd_pending_delay - 1;
            end

            if (s_rvalid && m_axi_rready) begin
                s_rvalid <= 1'b0;
                s_rlast  <= 1'b0;
                s_rresp  <= AXI_RESP_OKAY;
                s_rdata  <= '0;
                s_rid    <= '0;

                total_r_handshakes <= total_r_handshakes + 1;
            end

            if (!s_rvalid && rd_pending_valid && (rd_pending_delay == 0)) begin
                int unsigned idx;

                idx = word_index_from_addr(rd_pending_addr);
                if (idx >= MEM_DEPTH_WORDS) begin
                    $fatal(1, "[DMA2LDR_TB] Read responder out of range: addr=0x%08h idx=%0d depth=%0d",
                        rd_pending_addr, idx, MEM_DEPTH_WORDS);
                end

                s_rvalid <= 1'b1;
                s_rid    <= rd_pending_id;
                s_rdata  <= mem_model[idx];
                s_rresp  <= inject_rresp_error ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
                s_rlast  <= 1'b1;

                rd_pending_valid <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------
    // Capture actual loader writes
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            actual_wr_addr_q.delete();
            actual_wr_data_q.delete();
            actual_wr_last_q.delete();
            total_loader_wr_handshakes <= 0;
        end
        else begin
            if (loader_wr_valid && loader_wr_ready) begin
                if (loader_wr_strb !== FULL_STRB) begin
                    $fatal(1, "[DMA2LDR_TB] loader_wr_strb mismatch: got=0x%0h exp=0x%0h",
                        loader_wr_strb, FULL_STRB);
                end

                actual_wr_addr_q.push_back(loader_wr_addr);
                actual_wr_data_q.push_back(loader_wr_data);
                actual_wr_last_q.push_back(loader_wr_last);

                total_loader_wr_handshakes <= total_loader_wr_handshakes + 1;
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
        $display("[DMA2LDR_TB] --------------------------------------------------");
        $display("[DMA2LDR_TB] TEST 1: exact-length success");
        $display("[DMA2LDR_TB] --------------------------------------------------");

        apply_reset();
        clear_mem_model();

        src_base = 32'h0000_0100;
        dst_base = 32'h0000_1000;

        preload_src_words(src_base, 4, 16'h0010);
        build_expected_write_sequence_from_mem(src_base, dst_base, 4);

        ar_before = total_ar_handshakes;

        launch_pair(src_base, 4, dst_base, 4);
        wait_done_pair_or_timeout(300, "exact_length_success");
        check_busy_clears("exact_length_success");

        if (dma_error !== 1'b0) begin
            $fatal(1, "[DMA2LDR_TB][exact_length_success] dma_error asserted unexpectedly");
        end

        if (loader_error !== 1'b0) begin
            $fatal(1, "[DMA2LDR_TB][exact_length_success] loader_error asserted unexpectedly");
        end

        if (loader_accepted_beats != 32'd4) begin
            $fatal(1, "[DMA2LDR_TB][exact_length_success] loader_accepted_beats mismatch: got=%0d exp=4",
                loader_accepted_beats);
        end

        if (loader_written_beats != 32'd4) begin
            $fatal(1, "[DMA2LDR_TB][exact_length_success] loader_written_beats mismatch: got=%0d exp=4",
                loader_written_beats);
        end

        if (loader_tlast_seen !== 1'b1) begin
            $fatal(1, "[DMA2LDR_TB][exact_length_success] loader_tlast_seen expected 1");
        end

        expect_ar_count_delta(ar_before, 4, "exact_length_success");
        compare_write_sequence("exact_length_success");
        compare_loader_readback_against_expected(4, "exact_length_success");

        $display("[DMA2LDR_TB] PASS: exact-length success");
    end
    endtask

    task automatic run_capture_until_tlast_test();
        logic [ADDR_WIDTH-1:0] src_base;
        logic [ADDR_WIDTH-1:0] dst_base;
        int unsigned           ar_before;
    begin
        $display("[DMA2LDR_TB] --------------------------------------------------");
        $display("[DMA2LDR_TB] TEST 2: capture-until-tlast mode");
        $display("[DMA2LDR_TB] --------------------------------------------------");

        apply_reset();
        clear_mem_model();

        src_base = 32'h0000_0200;
        dst_base = 32'h0000_1100;

        preload_src_words(src_base, 3, 16'h0100);
        build_expected_write_sequence_from_mem(src_base, dst_base, 3);

        ar_before = total_ar_handshakes;

        launch_pair(src_base, 3, dst_base, 0);
        wait_done_pair_or_timeout(300, "capture_until_tlast");
        check_busy_clears("capture_until_tlast");

        if (dma_error !== 1'b0) begin
            $fatal(1, "[DMA2LDR_TB][capture_until_tlast] dma_error asserted unexpectedly");
        end

        if (loader_error !== 1'b0) begin
            $fatal(1, "[DMA2LDR_TB][capture_until_tlast] loader_error asserted unexpectedly");
        end

        if (loader_accepted_beats != 32'd3) begin
            $fatal(1, "[DMA2LDR_TB][capture_until_tlast] loader_accepted_beats mismatch: got=%0d exp=3",
                loader_accepted_beats);
        end

        if (loader_written_beats != 32'd3) begin
            $fatal(1, "[DMA2LDR_TB][capture_until_tlast] loader_written_beats mismatch: got=%0d exp=3",
                loader_written_beats);
        end

        if (loader_tlast_seen !== 1'b1) begin
            $fatal(1, "[DMA2LDR_TB][capture_until_tlast] loader_tlast_seen expected 1");
        end

        expect_ar_count_delta(ar_before, 3, "capture_until_tlast");
        compare_write_sequence("capture_until_tlast");
        compare_loader_readback_against_expected(3, "capture_until_tlast");

        $display("[DMA2LDR_TB] PASS: capture-until-tlast mode");
    end
    endtask

    task automatic run_loader_write_backpressure_test();
        logic [ADDR_WIDTH-1:0] src_base;
        logic [ADDR_WIDTH-1:0] dst_base;
        int unsigned           ar_before;
    begin
        $display("[DMA2LDR_TB] --------------------------------------------------");
        $display("[DMA2LDR_TB] TEST 3: loader write-side backpressure");
        $display("[DMA2LDR_TB] --------------------------------------------------");

        apply_reset();
        clear_mem_model();

        src_base = 32'h0000_0300;
        dst_base = 32'h0000_1200;

        preload_src_words(src_base, 4, 16'h0200);
        build_expected_write_sequence_from_mem(src_base, dst_base, 4);

        ar_before = total_ar_handshakes;

        fork
            begin
                loader_wr_ready = 1'b1;
                wait (loader_wr_valid === 1'b1);

                @(posedge clk);
                loader_wr_ready = 1'b0;
                repeat (3) @(posedge clk);
                loader_wr_ready = 1'b1;

                repeat (1) @(posedge clk);
                loader_wr_ready = 1'b0;
                repeat (2) @(posedge clk);
                loader_wr_ready = 1'b1;
            end
        join_none

        launch_pair(src_base, 4, dst_base, 4);
        wait_done_pair_or_timeout(500, "loader_write_backpressure");
        check_busy_clears("loader_write_backpressure");

        if (dma_error !== 1'b0) begin
            $fatal(1, "[DMA2LDR_TB][loader_write_backpressure] dma_error asserted unexpectedly");
        end

        if (loader_error !== 1'b0) begin
            $fatal(1, "[DMA2LDR_TB][loader_write_backpressure] loader_error asserted unexpectedly");
        end

        if (loader_accepted_beats != 32'd4) begin
            $fatal(1, "[DMA2LDR_TB][loader_write_backpressure] loader_accepted_beats mismatch: got=%0d exp=4",
                loader_accepted_beats);
        end

        if (loader_written_beats != 32'd4) begin
            $fatal(1, "[DMA2LDR_TB][loader_write_backpressure] loader_written_beats mismatch: got=%0d exp=4",
                loader_written_beats);
        end

        expect_ar_count_delta(ar_before, 4, "loader_write_backpressure");
        compare_write_sequence("loader_write_backpressure");
        compare_loader_readback_against_expected(4, "loader_write_backpressure");

        $display("[DMA2LDR_TB] PASS: loader write-side backpressure");
    end
    endtask

    task automatic run_loader_longer_than_actual_mismatch_test();
        logic [ADDR_WIDTH-1:0] src_base;
        logic [ADDR_WIDTH-1:0] dst_base;
        int unsigned           ar_before;
    begin
        $display("[DMA2LDR_TB] --------------------------------------------------");
        $display("[DMA2LDR_TB] TEST 4: loader expected-beats longer-than-actual");
        $display("[DMA2LDR_TB] --------------------------------------------------");

        apply_reset();
        clear_mem_model();

        src_base = 32'h0000_0400;
        dst_base = 32'h0000_1300;

        preload_src_words(src_base, 4, 16'h0300);
        build_expected_write_sequence_from_mem(src_base, dst_base, 4);

        ar_before = total_ar_handshakes;

        // DMA sends 4 beats with TLAST on beat 4.
        // Loader expects 5, so it should flag mismatch on TLAST arrival.
        launch_pair(src_base, 4, dst_base, 5);
        wait_done_pair_or_timeout(300, "loader_longer_than_actual");
        check_busy_clears("loader_longer_than_actual");

        if (dma_error !== 1'b0) begin
            $fatal(1, "[DMA2LDR_TB][loader_longer_than_actual] dma_error asserted unexpectedly");
        end

        if (loader_error !== 1'b1) begin
            $fatal(1, "[DMA2LDR_TB][loader_longer_than_actual] loader_error expected 1");
        end

        if (loader_accepted_beats != 32'd4) begin
            $fatal(1, "[DMA2LDR_TB][loader_longer_than_actual] loader_accepted_beats mismatch: got=%0d exp=4",
                loader_accepted_beats);
        end

        if (loader_written_beats != 32'd4) begin
            $fatal(1, "[DMA2LDR_TB][loader_longer_than_actual] loader_written_beats mismatch: got=%0d exp=4",
                loader_written_beats);
        end

        if (loader_tlast_seen !== 1'b1) begin
            $fatal(1, "[DMA2LDR_TB][loader_longer_than_actual] loader_tlast_seen expected 1");
        end

        expect_ar_count_delta(ar_before, 4, "loader_longer_than_actual");
        compare_write_sequence("loader_longer_than_actual");
        compare_loader_readback_against_expected(4, "loader_longer_than_actual");

        $display("[DMA2LDR_TB] PASS: loader expected-beats longer-than-actual");
    end
    endtask

    // ------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------
    initial begin
        init_tb_outputs();
        clear_mem_model();
        clear_expected_and_actual();

        run_exact_length_success_test();
        run_capture_until_tlast_test();
        run_loader_write_backpressure_test();
        run_loader_longer_than_actual_mismatch_test();

        $display("");
        $display("[DMA2LDR_TB] ==================================================");
        $display("[DMA2LDR_TB] All DMA-to-loader integration smoke tests PASSED");
        $display("[DMA2LDR_TB] ==================================================");
        $display("");

        #20;
        $finish;
    end

endmodule

`endif