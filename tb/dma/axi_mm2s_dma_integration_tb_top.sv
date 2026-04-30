// File: tb/dma/axi_mm2s_dma_integration_tb_top.sv
`ifndef AXI_MM2S_DMA_INTEGRATION_TB_TOP_SV
`define AXI_MM2S_DMA_INTEGRATION_TB_TOP_SV

`timescale 1ns/1ps

module axi_mm2s_dma_integration_tb_top;

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

    localparam int SINK_CAPTURE_DEPTH  = 1024;
    localparam int SINK_ADDR_WIDTH     = (SINK_CAPTURE_DEPTH <= 1) ? 1 : $clog2(SINK_CAPTURE_DEPTH);

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

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
    // DMA control
    // ------------------------------------------------------------
    logic                  dma_start;
    logic [ADDR_WIDTH-1:0] dma_src_addr;
    logic [31:0]           dma_xfer_len_beats;

    logic                  dma_busy;
    logic                  dma_done;
    logic                  dma_error;

    // ------------------------------------------------------------
    // AXI-MM wires
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
    // AXIS wires: DMA -> Sink
    // ------------------------------------------------------------
    logic [DATA_WIDTH-1:0] axis_tdata;
    logic                  axis_tvalid;
    logic                  axis_tready;
    logic                  axis_tlast;

    // ------------------------------------------------------------
    // Sink control / status
    // ------------------------------------------------------------
    logic                        sink_start;
    logic [31:0]                 sink_expected_beats;

    logic                        sink_busy;
    logic                        sink_done;
    logic                        sink_error;

    logic                        sink_rd_en;
    logic [SINK_ADDR_WIDTH-1:0]  sink_rd_addr;
    logic [DATA_WIDTH-1:0]       sink_rd_data;

    logic [31:0]                 sink_captured_beats;
    logic                        sink_tlast_seen;

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

    axi_mm2s_dma_sink #(
        .DATA_WIDTH         (DATA_WIDTH),
        .CAPTURE_DEPTH      (SINK_CAPTURE_DEPTH),
        .CAPTURE_ADDR_WIDTH (SINK_ADDR_WIDTH)
    ) u_sink (
        .clk             (clk),
        .rst_n           (rst_n),

        .start           (sink_start),
        .expected_beats  (sink_expected_beats),

        .busy            (sink_busy),
        .done            (sink_done),
        .error           (sink_error),

        .s_axis_tdata    (axis_tdata),
        .s_axis_tvalid   (axis_tvalid),
        .s_axis_tready   (axis_tready),
        .s_axis_tlast    (axis_tlast),

        .rd_en           (sink_rd_en),
        .rd_addr         (sink_rd_addr),
        .rd_data         (sink_rd_data),

        .captured_beats  (sink_captured_beats),
        .tlast_seen      (sink_tlast_seen)
    );

    // ------------------------------------------------------------
    // Simple memory model
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

    // ------------------------------------------------------------
    // Expected payload storage
    // ------------------------------------------------------------
    logic [DATA_WIDTH-1:0] expected_data_q[$];
    bit                    expected_last_q[$];

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
        lo = 32'h3000_0000 + seed;
        hi = 32'h4000_0000 + seed;
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

    task automatic clear_expected();
    begin
        expected_data_q.delete();
        expected_last_q.delete();
    end
    endtask

    task automatic init_tb_outputs();
    begin
        dma_start           = 1'b0;
        dma_src_addr        = '0;
        dma_xfer_len_beats  = '0;

        sink_start          = 1'b0;
        sink_expected_beats = '0;

        sink_rd_en          = 1'b0;
        sink_rd_addr        = '0;

        inject_rresp_error  = 1'b0;
    end
    endtask

    task automatic apply_reset(int unsigned hold_cycles = 5);
    begin
        rst_n = 1'b0;
        init_tb_outputs();
        clear_expected();

        repeat (hold_cycles) @(posedge clk);

        rst_n = 1'b1;
        repeat (2) @(posedge clk);
    end
    endtask

    task automatic preload_words(
        input logic [ADDR_WIDTH-1:0] base_addr,
        input int unsigned           beat_count,
        input int unsigned           seed_base
    );
        int unsigned i;
        int unsigned idx;
    begin
        for (i = 0; i < beat_count; i++) begin
            idx = word_index_from_addr(base_addr) + i;

            if (idx >= MEM_DEPTH_WORDS) begin
                $fatal(1, "[INT_TB] preload_words out of range: idx=%0d depth=%0d",
                    idx, MEM_DEPTH_WORDS);
            end

            mem_model[idx] = make_test_word(seed_base + i);
        end
    end
    endtask

    task automatic build_expected_from_mem(
        input logic [ADDR_WIDTH-1:0] base_addr,
        input int unsigned           beat_count
    );
        int unsigned i;
        int unsigned idx;
    begin
        clear_expected();

        for (i = 0; i < beat_count; i++) begin
            idx = word_index_from_addr(base_addr) + i;

            if (idx >= MEM_DEPTH_WORDS) begin
                $fatal(1, "[INT_TB] build_expected_from_mem out of range: idx=%0d depth=%0d",
                    idx, MEM_DEPTH_WORDS);
            end

            expected_data_q.push_back(mem_model[idx]);
            expected_last_q.push_back(i == (beat_count - 1));
        end
    end
    endtask

    task automatic launch_sink(
        input logic [31:0] exp_beats
    );
    begin
        sink_expected_beats = exp_beats;
        sink_start          = 1'b1;
        @(posedge clk);
        sink_start          = 1'b0;
    end
    endtask

    task automatic launch_dma(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [31:0]           len_beats
    );
    begin
        dma_src_addr       = addr;
        dma_xfer_len_beats = len_beats;
        dma_start          = 1'b1;
        @(posedge clk);
        dma_start          = 1'b0;
    end
    endtask

    task automatic launch_pair(
        input logic [31:0]           sink_exp_beats,
        input logic [ADDR_WIDTH-1:0] dma_addr,
        input logic [31:0]           dma_len_beats
    );
    begin
        launch_sink(sink_exp_beats);
        @(posedge clk);
        launch_dma(dma_addr, dma_len_beats);
    end
    endtask

    task automatic wait_done_pair_or_timeout(
        input int unsigned timeout_cycles,
        input string       tag
    );
        int unsigned i;
        bit dma_done_seen;
        bit sink_done_seen;
    begin
        dma_done_seen  = 1'b0;
        sink_done_seen = 1'b0;

        for (i = 0; i < timeout_cycles; i++) begin
            @(posedge clk);

            if (dma_done === 1'b1) begin
                dma_done_seen = 1'b1;
            end

            if (sink_done === 1'b1) begin
                sink_done_seen = 1'b1;
            end

            if (dma_done_seen && sink_done_seen) begin
                return;
            end
        end

        $fatal(1, "[INT_TB][%s] Timeout waiting for dma_done/sink_done after %0d cycles",
            tag, timeout_cycles);
    end
    endtask

    task automatic check_busy_clears(
        input string tag
    );
    begin
        @(posedge clk);

        if (dma_busy !== 1'b0) begin
            $fatal(1, "[INT_TB][%s] dma_busy did not clear after done", tag);
        end

        if (sink_busy !== 1'b0) begin
            $fatal(1, "[INT_TB][%s] sink_busy did not clear after done", tag);
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
            $fatal(1, "[INT_TB][%s] AR handshake delta mismatch: got=%0d exp=%0d",
                tag, delta, exp_delta);
        end
    end
    endtask

    task automatic compare_sink_readback(
        input int unsigned beat_count,
        input string       tag
    );
        int unsigned i;
    begin
        if (expected_data_q.size() != beat_count) begin
            $fatal(1, "[INT_TB][%s] expected_data_q size mismatch: got=%0d exp=%0d",
                tag, expected_data_q.size(), beat_count);
        end

        sink_rd_en = 1'b1;

        for (i = 0; i < beat_count; i++) begin
            sink_rd_addr = i[SINK_ADDR_WIDTH-1:0];
            #1;
            if (sink_rd_data !== expected_data_q[i]) begin
                $fatal(1, "[INT_TB][%s] Sink readback mismatch at beat %0d: got=0x%016h exp=0x%016h",
                    tag, i, sink_rd_data, expected_data_q[i]);
            end
        end

        sink_rd_en   = 1'b0;
        sink_rd_addr = '0;
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
            rd_pending_valid    <= 1'b0;
            rd_pending_addr     <= '0;
            rd_pending_id       <= '0;
            rd_pending_delay    <= 0;

            s_rdata             <= '0;
            s_rid               <= '0;
            s_rresp             <= AXI_RESP_OKAY;
            s_rlast             <= 1'b0;
            s_rvalid            <= 1'b0;

            total_ar_handshakes <= 0;
            total_r_handshakes  <= 0;
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
                    $fatal(1, "[INT_TB] Read responder out of range: addr=0x%08h idx=%0d depth=%0d",
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
    // Tests
    // ------------------------------------------------------------
    task automatic run_exact_length_success_test();
        logic [ADDR_WIDTH-1:0] base_addr;
        int unsigned           ar_before;
    begin
        $display("[INT_TB] --------------------------------------------------");
        $display("[INT_TB] TEST 1: exact-length success");
        $display("[INT_TB] --------------------------------------------------");

        apply_reset();
        clear_mem_model();

        base_addr = 32'h0000_0100;

        preload_words(base_addr, 4, 16'h0010);
        build_expected_from_mem(base_addr, 4);

        ar_before = total_ar_handshakes;

        launch_pair(4, base_addr, 4);
        wait_done_pair_or_timeout(300, "exact_length_success");
        check_busy_clears("exact_length_success");

        if (dma_error !== 1'b0) begin
            $fatal(1, "[INT_TB][exact_length_success] dma_error asserted unexpectedly");
        end

        if (sink_error !== 1'b0) begin
            $fatal(1, "[INT_TB][exact_length_success] sink_error asserted unexpectedly");
        end

        if (sink_captured_beats != 32'd4) begin
            $fatal(1, "[INT_TB][exact_length_success] sink_captured_beats mismatch: got=%0d exp=4",
                sink_captured_beats);
        end

        if (sink_tlast_seen !== 1'b1) begin
            $fatal(1, "[INT_TB][exact_length_success] sink_tlast_seen expected 1");
        end

        expect_ar_count_delta(ar_before, 4, "exact_length_success");
        compare_sink_readback(4, "exact_length_success");

        $display("[INT_TB] PASS: exact-length success");
    end
    endtask

    task automatic run_capture_until_tlast_test();
        logic [ADDR_WIDTH-1:0] base_addr;
        int unsigned           ar_before;
    begin
        $display("[INT_TB] --------------------------------------------------");
        $display("[INT_TB] TEST 2: capture-until-tlast mode");
        $display("[INT_TB] --------------------------------------------------");

        apply_reset();
        clear_mem_model();

        base_addr = 32'h0000_0200;

        preload_words(base_addr, 3, 16'h0100);
        build_expected_from_mem(base_addr, 3);

        ar_before = total_ar_handshakes;

        launch_pair(0, base_addr, 3);
        wait_done_pair_or_timeout(300, "capture_until_tlast");
        check_busy_clears("capture_until_tlast");

        if (dma_error !== 1'b0) begin
            $fatal(1, "[INT_TB][capture_until_tlast] dma_error asserted unexpectedly");
        end

        if (sink_error !== 1'b0) begin
            $fatal(1, "[INT_TB][capture_until_tlast] sink_error asserted unexpectedly");
        end

        if (sink_captured_beats != 32'd3) begin
            $fatal(1, "[INT_TB][capture_until_tlast] sink_captured_beats mismatch: got=%0d exp=3",
                sink_captured_beats);
        end

        if (sink_tlast_seen !== 1'b1) begin
            $fatal(1, "[INT_TB][capture_until_tlast] sink_tlast_seen expected 1");
        end

        expect_ar_count_delta(ar_before, 3, "capture_until_tlast");
        compare_sink_readback(3, "capture_until_tlast");

        $display("[INT_TB] PASS: capture-until-tlast mode");
    end
    endtask

    task automatic run_longer_expected_mismatch_test();
        logic [ADDR_WIDTH-1:0] base_addr;
        int unsigned           ar_before;
    begin
        $display("[INT_TB] --------------------------------------------------");
        $display("[INT_TB] TEST 3: sink expected-beats longer-than-actual");
        $display("[INT_TB] --------------------------------------------------");

        apply_reset();
        clear_mem_model();

        base_addr = 32'h0000_0300;

        preload_words(base_addr, 4, 16'h0200);
        build_expected_from_mem(base_addr, 4);

        ar_before = total_ar_handshakes;

        // sink expects 5, but DMA only sends 4 with TLAST on beat 4
        launch_pair(5, base_addr, 4);
        wait_done_pair_or_timeout(300, "longer_expected_mismatch");
        check_busy_clears("longer_expected_mismatch");

        if (dma_error !== 1'b0) begin
            $fatal(1, "[INT_TB][longer_expected_mismatch] dma_error asserted unexpectedly");
        end

        if (sink_error !== 1'b1) begin
            $fatal(1, "[INT_TB][longer_expected_mismatch] sink_error expected 1");
        end

        if (sink_captured_beats != 32'd4) begin
            $fatal(1, "[INT_TB][longer_expected_mismatch] sink_captured_beats mismatch: got=%0d exp=4",
                sink_captured_beats);
        end

        if (sink_tlast_seen !== 1'b1) begin
            $fatal(1, "[INT_TB][longer_expected_mismatch] sink_tlast_seen expected 1");
        end

        expect_ar_count_delta(ar_before, 4, "longer_expected_mismatch");
        compare_sink_readback(4, "longer_expected_mismatch");

        $display("[INT_TB] PASS: sink expected-beats longer-than-actual");
    end
    endtask

    // ------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------
    initial begin
        init_tb_outputs();
        clear_mem_model();
        clear_expected();

        run_exact_length_success_test();
        run_capture_until_tlast_test();
        run_longer_expected_mismatch_test();

        $display("");
        $display("[INT_TB] ==================================================");
        $display("[INT_TB] All DMA integration smoke tests PASSED");
        $display("[INT_TB] ==================================================");
        $display("");

        #20;
        $finish;
    end

endmodule

`endif