// File: tb/dma/axi_mm2s_dma_tb_top.sv
`ifndef AXI_MM2S_DMA_TB_TOP_SV
`define AXI_MM2S_DMA_TB_TOP_SV

`timescale 1ns/1ps

module axi_mm2s_dma_tb_top;

    localparam int ADDR_WIDTH          = 32;
    localparam int DATA_WIDTH          = 64;
    localparam int AXI_ID_WIDTH        = 4;
    localparam int BYTES_PER_BEAT      = DATA_WIDTH / 8;
    localparam int BEAT_ADDR_LSB       = (BYTES_PER_BEAT <= 1) ? 0 : $clog2(BYTES_PER_BEAT);
    localparam int MEM_DEPTH_WORDS     = 1024;
    localparam int READ_LATENCY_CYCLES = 2;

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    logic clk;
    logic rst_n;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------
    // DMA control
    // ------------------------------------------------------------
    logic                  start;
    logic [ADDR_WIDTH-1:0] src_addr;
    logic [31:0]           xfer_len_beats;

    logic                  busy;
    logic                  done;
    logic                  error;

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
    // AXIS sink side
    // ------------------------------------------------------------
    logic [DATA_WIDTH-1:0] m_axis_tdata;
    logic                  m_axis_tvalid;
    logic                  m_axis_tready;
    logic                  m_axis_tlast;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    axi_mm2s_dma #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .AXI_ID_WIDTH (AXI_ID_WIDTH),
        .AXI_ARID     ('0)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),
        .src_addr       (src_addr),
        .xfer_len_beats (xfer_len_beats),
        .busy           (busy),
        .done           (done),
        .error          (error),

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

        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast)
    );

    // ------------------------------------------------------------
    // Memory model
    // ------------------------------------------------------------
    logic [DATA_WIDTH-1:0] mem_model [0:MEM_DEPTH_WORDS-1];

    logic                  rd_pending_valid;
    logic [ADDR_WIDTH-1:0] rd_pending_addr;
    logic [AXI_ID_WIDTH-1:0] rd_pending_id;
    int unsigned           rd_pending_delay;

    logic [DATA_WIDTH-1:0] s_rdata;
    logic [AXI_ID_WIDTH-1:0] s_rid;
    logic [1:0]            s_rresp;
    logic                  s_rlast;
    logic                  s_rvalid;

    logic                  inject_rresp_error;

    int unsigned           total_ar_handshakes;
    int unsigned           total_r_handshakes;

    logic [DATA_WIDTH-1:0] captured_data_q[$];
    bit                    captured_last_q[$];

    logic [DATA_WIDTH-1:0] expected_data_q[$];
    bit                    expected_last_q[$];

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
        lo = 32'h1000_0000 + seed;
        hi = 32'h2000_0000 + seed;
        return {hi, lo};
    end
    endfunction

    task automatic clear_expected_and_captured();
    begin
        expected_data_q.delete();
        expected_last_q.delete();
        captured_data_q.delete();
        captured_last_q.delete();
    end
    endtask

    task automatic clear_mem_model();
        int i;
    begin
        for (i = 0; i < MEM_DEPTH_WORDS; i++) begin
            mem_model[i] = '0;
        end
    end
    endtask

    task automatic init_tb_outputs();
    begin
        start             = 1'b0;
        src_addr          = '0;
        xfer_len_beats    = '0;
        m_axis_tready     = 1'b1;
        inject_rresp_error = 1'b0;
    end
    endtask

    task automatic apply_reset(int unsigned hold_cycles = 5);
    begin
        rst_n = 1'b0;
        init_tb_outputs();
        clear_expected_and_captured();

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
                $fatal(1, "[TB] preload_words out of range: idx=%0d depth=%0d",
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
        expected_data_q.delete();
        expected_last_q.delete();

        for (i = 0; i < beat_count; i++) begin
            idx = word_index_from_addr(base_addr) + i;

            if (idx >= MEM_DEPTH_WORDS) begin
                $fatal(1, "[TB] build_expected_from_mem out of range: idx=%0d depth=%0d",
                    idx, MEM_DEPTH_WORDS);
            end

            expected_data_q.push_back(mem_model[idx]);
            expected_last_q.push_back(i == (beat_count - 1));
        end
    end
    endtask

    task automatic launch_dma(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [31:0]           len_beats
    );
    begin
        src_addr       = addr;
        xfer_len_beats = len_beats;
        start          = 1'b1;
        @(posedge clk);
        start          = 1'b0;
    end
    endtask

    task automatic wait_done_or_timeout(
        input int unsigned timeout_cycles,
        input string       tag
    );
        int unsigned i;
    begin
        for (i = 0; i < timeout_cycles; i++) begin
            @(posedge clk);
            if (done === 1'b1) begin
                return;
            end
        end

        $fatal(1, "[TB][%s] Timeout waiting for done after %0d cycles",
            tag, timeout_cycles);
    end
    endtask

    task automatic check_busy_clears(
        input string tag
    );
    begin
        @(posedge clk);
        if (busy !== 1'b0) begin
            $fatal(1, "[TB][%s] busy did not clear after done pulse", tag);
        end
    end
    endtask

    task automatic compare_axis_capture(
        input string tag
    );
        int unsigned i;
    begin
        if (captured_data_q.size() != expected_data_q.size()) begin
            $fatal(1, "[TB][%s] Captured size mismatch: got=%0d exp=%0d",
                tag, captured_data_q.size(), expected_data_q.size());
        end

        if (captured_last_q.size() != expected_last_q.size()) begin
            $fatal(1, "[TB][%s] Captured last-flag size mismatch: got=%0d exp=%0d",
                tag, captured_last_q.size(), expected_last_q.size());
        end

        for (i = 0; i < expected_data_q.size(); i++) begin
            if (captured_data_q[i] !== expected_data_q[i]) begin
                $fatal(1, "[TB][%s] Data mismatch at beat %0d: got=0x%016h exp=0x%016h",
                    tag, i, captured_data_q[i], expected_data_q[i]);
            end

            if (captured_last_q[i] !== expected_last_q[i]) begin
                $fatal(1, "[TB][%s] TLAST mismatch at beat %0d: got=%0b exp=%0b",
                    tag, i, captured_last_q[i], expected_last_q[i]);
            end
        end
    end
    endtask

    task automatic expect_no_axis_output(
        input string tag
    );
    begin
        if (captured_data_q.size() != 0) begin
            $fatal(1, "[TB][%s] Unexpected AXIS output observed: beats=%0d",
                tag, captured_data_q.size());
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
            $fatal(1, "[TB][%s] AR handshake delta mismatch: got=%0d exp=%0d",
                tag, delta, exp_delta);
        end
    end
    endtask

    // ------------------------------------------------------------
    // Slave tie-offs / responses
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
            rd_pending_valid   <= 1'b0;
            rd_pending_addr    <= '0;
            rd_pending_id      <= '0;
            rd_pending_delay   <= 0;

            s_rdata            <= '0;
            s_rid              <= '0;
            s_rresp            <= AXI_RESP_OKAY;
            s_rlast            <= 1'b0;
            s_rvalid           <= 1'b0;

            total_ar_handshakes <= 0;
            total_r_handshakes  <= 0;
        end
        else begin
            if (m_axi_arvalid && m_axi_arready) begin
                rd_pending_valid <= 1'b1;
                rd_pending_addr  <= m_axi_araddr;
                rd_pending_id    <= m_axi_arid;
                rd_pending_delay <= READ_LATENCY_CYCLES;

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
                    $fatal(1, "[TB] Read responder out of range: addr=0x%08h idx=%0d depth=%0d",
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
    // AXIS capture
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            captured_data_q.delete();
            captured_last_q.delete();
        end
        else begin
            if (m_axis_tvalid && m_axis_tready) begin
                captured_data_q.push_back(m_axis_tdata);
                captured_last_q.push_back(m_axis_tlast);
            end
        end
    end

    task automatic run_basic_transfer_test();
        logic [ADDR_WIDTH-1:0] base_addr;
        int unsigned           ar_before;
    begin
        $display("[TB] --------------------------------------------------");
        $display("[TB] TEST 1: basic transfer");
        $display("[TB] --------------------------------------------------");

        apply_reset();
        clear_mem_model();

        base_addr = 32'h0000_0100;

        preload_words(base_addr, 4, 16'h0010);
        build_expected_from_mem(base_addr, 4);

        ar_before = total_ar_handshakes;

        m_axis_tready = 1'b1;
        launch_dma(base_addr, 4);
        wait_done_or_timeout(200, "basic_transfer");
        check_busy_clears("basic_transfer");

        if (error !== 1'b0) begin
            $fatal(1, "[TB][basic_transfer] error asserted unexpectedly");
        end

        expect_ar_count_delta(ar_before, 4, "basic_transfer");
        compare_axis_capture("basic_transfer");

        $display("[TB] PASS: basic transfer");
    end
    endtask

    task automatic run_backpressure_test();
        logic [ADDR_WIDTH-1:0] base_addr;
        int unsigned           ar_before;
    begin
        $display("[TB] --------------------------------------------------");
        $display("[TB] TEST 2: stream backpressure");
        $display("[TB] --------------------------------------------------");

        apply_reset();
        clear_mem_model();

        base_addr = 32'h0000_0200;

        preload_words(base_addr, 3, 16'h0100);
        build_expected_from_mem(base_addr, 3);

        ar_before = total_ar_handshakes;

        fork
            begin
                m_axis_tready = 1'b1;
                wait (busy === 1'b1);

                repeat (2) @(posedge clk);
                m_axis_tready = 1'b0;
                repeat (3) @(posedge clk);
                m_axis_tready = 1'b1;

                repeat (1) @(posedge clk);
                m_axis_tready = 1'b0;
                repeat (2) @(posedge clk);
                m_axis_tready = 1'b1;
            end
        join_none

        launch_dma(base_addr, 3);
        wait_done_or_timeout(300, "backpressure");
        check_busy_clears("backpressure");

        if (error !== 1'b0) begin
            $fatal(1, "[TB][backpressure] error asserted unexpectedly");
        end

        expect_ar_count_delta(ar_before, 3, "backpressure");
        compare_axis_capture("backpressure");

        $display("[TB] PASS: stream backpressure");
    end
    endtask

    task automatic run_invalid_zero_len_test();
        int unsigned ar_before;
    begin
        $display("[TB] --------------------------------------------------");
        $display("[TB] TEST 3: invalid launch (zero length)");
        $display("[TB] --------------------------------------------------");

        apply_reset();
        clear_mem_model();

        ar_before = total_ar_handshakes;

        launch_dma(32'h0000_0100, 0);
        wait_done_or_timeout(20, "invalid_zero_len");
        check_busy_clears("invalid_zero_len");

        if (error !== 1'b1) begin
            $fatal(1, "[TB][invalid_zero_len] expected error=1");
        end

        expect_ar_count_delta(ar_before, 0, "invalid_zero_len");
        expect_no_axis_output("invalid_zero_len");

        $display("[TB] PASS: invalid zero length");
    end
    endtask

    task automatic run_invalid_unaligned_addr_test();
        int unsigned ar_before;
        logic [ADDR_WIDTH-1:0] bad_addr;
    begin
        $display("[TB] --------------------------------------------------");
        $display("[TB] TEST 4: invalid launch (unaligned address)");
        $display("[TB] --------------------------------------------------");

        apply_reset();
        clear_mem_model();

        bad_addr  = 32'h0000_0104;
        ar_before = total_ar_handshakes;

        launch_dma(bad_addr, 2);
        wait_done_or_timeout(20, "invalid_unaligned");
        check_busy_clears("invalid_unaligned");

        if (error !== 1'b1) begin
            $fatal(1, "[TB][invalid_unaligned] expected error=1");
        end

        expect_ar_count_delta(ar_before, 0, "invalid_unaligned");
        expect_no_axis_output("invalid_unaligned");

        $display("[TB] PASS: invalid unaligned address");
    end
    endtask

    task automatic run_rresp_error_test();
        logic [ADDR_WIDTH-1:0] base_addr;
        int unsigned           ar_before;
    begin
        $display("[TB] --------------------------------------------------");
        $display("[TB] TEST 5: read response error");
        $display("[TB] --------------------------------------------------");

        apply_reset();
        clear_mem_model();

        base_addr = 32'h0000_0300;

        preload_words(base_addr, 2, 16'h0200);
        clear_expected_and_captured();

        ar_before = total_ar_handshakes;

        inject_rresp_error = 1'b1;
        launch_dma(base_addr, 2);
        wait_done_or_timeout(100, "rresp_error");
        check_busy_clears("rresp_error");
        inject_rresp_error = 1'b0;

        if (error !== 1'b1) begin
            $fatal(1, "[TB][rresp_error] expected error=1");
        end

        expect_ar_count_delta(ar_before, 1, "rresp_error");
        expect_no_axis_output("rresp_error");

        $display("[TB] PASS: read response error");
    end
    endtask

    initial begin
        init_tb_outputs();
        clear_mem_model();
        clear_expected_and_captured();

        run_basic_transfer_test();
        run_backpressure_test();
        run_invalid_zero_len_test();
        run_invalid_unaligned_addr_test();
        run_rresp_error_test();

        $display("");
        $display("[TB] ================================================");
        $display("[TB] All axi_mm2s_dma smoke tests PASSED");
        $display("[TB] ================================================");
        $display("");

        #20;
        $finish;
    end

endmodule

`endif