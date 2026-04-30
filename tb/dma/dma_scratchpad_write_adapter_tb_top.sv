// File: tb/dma/dma_scratchpad_write_adapter_tb_top.sv
`ifndef DMA_SCRATCHPAD_WRITE_ADAPTER_TB_TOP_SV
`define DMA_SCRATCHPAD_WRITE_ADAPTER_TB_TOP_SV

`timescale 1ns/1ps

module dma_scratchpad_write_adapter_tb_top;

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    localparam int ADDR_WIDTH   = 32;
    localparam int DATA_WIDTH   = 64;
    localparam int AXI_ID_WIDTH = 4;

    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;

    localparam logic [AXI_ID_WIDTH-1:0] AXI_AWID = '0;
    localparam logic [1:0] AXI_RESP_OKAY  = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR= 2'b10;
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
    // Upstream source -> adapter
    // ------------------------------------------------------------
    logic                     src_wr_valid;
    logic                     src_wr_ready;
    logic [ADDR_WIDTH-1:0]    src_wr_addr;
    logic [DATA_WIDTH-1:0]    src_wr_data;
    logic [DATA_WIDTH/8-1:0]  src_wr_strb;
    logic                     src_wr_last;

    // ------------------------------------------------------------
    // Adapter status
    // ------------------------------------------------------------
    logic                     busy;
    logic                     done;
    logic                     error;
    logic [31:0]              accepted_beats;
    logic [31:0]              committed_beats;
    logic                     last_beat_seen;

    // ------------------------------------------------------------
    // AXI-MM write master toward scratchpad
    // ------------------------------------------------------------
    logic [AXI_ID_WIDTH-1:0]  m_axi_awid;
    logic [ADDR_WIDTH-1:0]    m_axi_awaddr;
    logic [7:0]               m_axi_awlen;
    logic [2:0]               m_axi_awsize;
    logic [1:0]               m_axi_awburst;
    logic                     m_axi_awvalid;
    logic                     m_axi_awready;

    logic [DATA_WIDTH-1:0]    m_axi_wdata;
    logic [DATA_WIDTH/8-1:0]  m_axi_wstrb;
    logic                     m_axi_wlast;
    logic                     m_axi_wvalid;
    logic                     m_axi_wready;

    logic [AXI_ID_WIDTH-1:0]  m_axi_bid;
    logic [1:0]               m_axi_bresp;
    logic                     m_axi_bvalid;
    logic                     m_axi_bready;

    // ------------------------------------------------------------
    // AXI-MM read channel (unused)
    // ------------------------------------------------------------
    logic [AXI_ID_WIDTH-1:0]  m_axi_arid;
    logic [ADDR_WIDTH-1:0]    m_axi_araddr;
    logic [7:0]               m_axi_arlen;
    logic [2:0]               m_axi_arsize;
    logic [1:0]               m_axi_arburst;
    logic                     m_axi_arvalid;
    logic                     m_axi_arready;

    logic [AXI_ID_WIDTH-1:0]  m_axi_rid;
    logic [DATA_WIDTH-1:0]    m_axi_rdata;
    logic [1:0]               m_axi_rresp;
    logic                     m_axi_rlast;
    logic                     m_axi_rvalid;
    logic                     m_axi_rready;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    dma_scratchpad_write_adapter #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .AXI_ID_WIDTH (AXI_ID_WIDTH),
        .AXI_AWID     (AXI_AWID)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),

        .src_wr_valid    (src_wr_valid),
        .src_wr_ready    (src_wr_ready),
        .src_wr_addr     (src_wr_addr),
        .src_wr_data     (src_wr_data),
        .src_wr_strb     (src_wr_strb),
        .src_wr_last     (src_wr_last),

        .busy            (busy),
        .done            (done),
        .error           (error),
        .accepted_beats  (accepted_beats),
        .committed_beats (committed_beats),
        .last_beat_seen  (last_beat_seen),

        .m_axi_awid      (m_axi_awid),
        .m_axi_awaddr    (m_axi_awaddr),
        .m_axi_awlen     (m_axi_awlen),
        .m_axi_awsize    (m_axi_awsize),
        .m_axi_awburst   (m_axi_awburst),
        .m_axi_awvalid   (m_axi_awvalid),
        .m_axi_awready   (m_axi_awready),

        .m_axi_wdata     (m_axi_wdata),
        .m_axi_wstrb     (m_axi_wstrb),
        .m_axi_wlast     (m_axi_wlast),
        .m_axi_wvalid    (m_axi_wvalid),
        .m_axi_wready    (m_axi_wready),

        .m_axi_bid       (m_axi_bid),
        .m_axi_bresp     (m_axi_bresp),
        .m_axi_bvalid    (m_axi_bvalid),
        .m_axi_bready    (m_axi_bready),

        .m_axi_arid      (m_axi_arid),
        .m_axi_araddr    (m_axi_araddr),
        .m_axi_arlen     (m_axi_arlen),
        .m_axi_arsize    (m_axi_arsize),
        .m_axi_arburst   (m_axi_arburst),
        .m_axi_arvalid   (m_axi_arvalid),
        .m_axi_arready   (m_axi_arready),

        .m_axi_rid       (m_axi_rid),
        .m_axi_rdata     (m_axi_rdata),
        .m_axi_rresp     (m_axi_rresp),
        .m_axi_rlast     (m_axi_rlast),
        .m_axi_rvalid    (m_axi_rvalid),
        .m_axi_rready    (m_axi_rready)
    );

    // ------------------------------------------------------------
    // Expected / actual tracking
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0]   expected_addr_q[$];
    logic [DATA_WIDTH-1:0]   expected_data_q[$];
    logic [DATA_WIDTH/8-1:0] expected_strb_q[$];
    bit                      expected_src_last_q[$];

    logic [ADDR_WIDTH-1:0]   actual_aw_addr_q[$];
    logic [DATA_WIDTH-1:0]   actual_w_data_q[$];
    logic [DATA_WIDTH/8-1:0] actual_w_strb_q[$];
    bit                      actual_w_last_q[$];

    int unsigned total_src_handshakes;
    int unsigned total_aw_handshakes;
    int unsigned total_w_handshakes;
    int unsigned total_b_handshakes;

    // ------------------------------------------------------------
    // AXI slave model control knobs
    // ------------------------------------------------------------
    logic awready_ctrl;
    logic wready_ctrl;

    int unsigned b_latency_cycles;
    int signed   inject_bresp_error_beat;
    int signed   inject_bid_mismatch_beat;
    logic [AXI_ID_WIDTH-1:0] bad_bid_value;

    // ------------------------------------------------------------
    // AXI slave model internal state
    // ------------------------------------------------------------
    logic                    seen_aw_for_curr;
    logic                    seen_w_for_curr;
    logic                    b_pending_valid;
    int unsigned             b_pending_delay;
    logic [1:0]              b_pending_resp;
    logic [AXI_ID_WIDTH-1:0] b_pending_id;
    int unsigned             scheduled_b_count;

    // ------------------------------------------------------------
    // Handshake helpers
    // ------------------------------------------------------------
    logic src_fire;
    logic aw_fire;
    logic w_fire;
    logic b_fire;

    always_comb begin
        src_fire = src_wr_valid && src_wr_ready;
        aw_fire  = m_axi_awvalid && m_axi_awready;
        w_fire   = m_axi_wvalid  && m_axi_wready;
        b_fire   = m_axi_bvalid  && m_axi_bready;
    end

    // ------------------------------------------------------------
    // Tie off unused read channel
    // ------------------------------------------------------------
    assign m_axi_arready = 1'b0;
    assign m_axi_rid     = '0;
    assign m_axi_rdata   = '0;
    assign m_axi_rresp   = '0;
    assign m_axi_rlast   = 1'b0;
    assign m_axi_rvalid  = 1'b0;

    // ------------------------------------------------------------
    // Drive AXI write response channel toward DUT
    // ------------------------------------------------------------
    assign m_axi_awready = rst_n && awready_ctrl && !m_axi_bvalid;
    assign m_axi_wready  = rst_n && wready_ctrl  && !m_axi_bvalid;

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------
    function automatic logic [DATA_WIDTH-1:0] make_test_word(
        input int unsigned seed
    );
        logic [31:0] lo;
        logic [31:0] hi;
    begin
        lo = 32'h9000_0000 + seed;
        hi = 32'hA000_0000 + seed;
        return {hi, lo};
    end
    endfunction

    task automatic clear_expected_and_actual();
    begin
        expected_addr_q.delete();
        expected_data_q.delete();
        expected_strb_q.delete();
        expected_src_last_q.delete();

        actual_aw_addr_q.delete();
        actual_w_data_q.delete();
        actual_w_strb_q.delete();
        actual_w_last_q.delete();
    end
    endtask

    task automatic init_tb_outputs();
    begin
        src_wr_valid = 1'b0;
        src_wr_addr  = '0;
        src_wr_data  = '0;
        src_wr_strb  = '0;
        src_wr_last  = 1'b0;

        awready_ctrl = 1'b1;
        wready_ctrl  = 1'b1;

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

    task automatic build_expected_sequence(
        input logic [ADDR_WIDTH-1:0] base_addr,
        input int unsigned           beat_count,
        input int unsigned           seed_base
    );
        int unsigned i;
    begin
        expected_addr_q.delete();
        expected_data_q.delete();
        expected_strb_q.delete();
        expected_src_last_q.delete();

        for (i = 0; i < beat_count; i++) begin
            expected_addr_q.push_back(base_addr + ADDR_WIDTH'(i * BYTES_PER_BEAT));
            expected_data_q.push_back(make_test_word(seed_base + i));
            expected_strb_q.push_back(FULL_STRB);
            expected_src_last_q.push_back(i == (beat_count - 1));
        end
    end
    endtask

    task automatic drive_src_sequence(
        input logic [ADDR_WIDTH-1:0] base_addr,
        input int unsigned           beat_count,
        input int unsigned           seed_base
    );
        int unsigned i;
    begin
        for (i = 0; i < beat_count; i++) begin
            src_wr_addr  = base_addr + ADDR_WIDTH'(i * BYTES_PER_BEAT);
            src_wr_data  = make_test_word(seed_base + i);
            src_wr_strb  = FULL_STRB;
            src_wr_last  = (i == (beat_count - 1));
            src_wr_valid = 1'b1;

            while (1) begin
                @(posedge clk);
                if (src_wr_valid && src_wr_ready) begin
                    break;
                end
            end
        end

        src_wr_valid = 1'b0;
        src_wr_addr  = '0;
        src_wr_data  = '0;
        src_wr_strb  = '0;
        src_wr_last  = 1'b0;
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

        $fatal(1, "[ADAPTER_TB][%s] Timeout waiting for done after %0d cycles",
            tag, timeout_cycles);
    end
    endtask

    task automatic check_busy_clears(
        input string tag
    );
    begin
        @(posedge clk);
        if (busy !== 1'b0) begin
            $fatal(1, "[ADAPTER_TB][%s] busy did not clear after done pulse", tag);
        end
    end
    endtask

    task automatic compare_axi_write_sequence(
        input string tag
    );
        int unsigned i;
    begin
        if (actual_aw_addr_q.size() != expected_addr_q.size()) begin
            $fatal(1, "[ADAPTER_TB][%s] AW count mismatch: got=%0d exp=%0d",
                tag, actual_aw_addr_q.size(), expected_addr_q.size());
        end

        if (actual_w_data_q.size() != expected_data_q.size()) begin
            $fatal(1, "[ADAPTER_TB][%s] W count mismatch: got=%0d exp=%0d",
                tag, actual_w_data_q.size(), expected_data_q.size());
        end

        if (actual_w_strb_q.size() != expected_strb_q.size()) begin
            $fatal(1, "[ADAPTER_TB][%s] WSTRB count mismatch: got=%0d exp=%0d",
                tag, actual_w_strb_q.size(), expected_strb_q.size());
        end

        if (actual_w_last_q.size() != expected_src_last_q.size()) begin
            $fatal(1, "[ADAPTER_TB][%s] WLAST count mismatch: got=%0d exp=%0d",
                tag, actual_w_last_q.size(), expected_src_last_q.size());
        end

        for (i = 0; i < expected_addr_q.size(); i++) begin
            if (actual_aw_addr_q[i] !== expected_addr_q[i]) begin
                $fatal(1, "[ADAPTER_TB][%s] AWADDR mismatch at beat %0d: got=0x%08h exp=0x%08h",
                    tag, i, actual_aw_addr_q[i], expected_addr_q[i]);
            end

            if (actual_w_data_q[i] !== expected_data_q[i]) begin
                $fatal(1, "[ADAPTER_TB][%s] WDATA mismatch at beat %0d: got=0x%016h exp=0x%016h",
                    tag, i, actual_w_data_q[i], expected_data_q[i]);
            end

            if (actual_w_strb_q[i] !== expected_strb_q[i]) begin
                $fatal(1, "[ADAPTER_TB][%s] WSTRB mismatch at beat %0d: got=0x%0h exp=0x%0h",
                    tag, i, actual_w_strb_q[i], expected_strb_q[i]);
            end

            if (actual_w_last_q[i] !== 1'b1) begin
                $fatal(1, "[ADAPTER_TB][%s] WLAST expected 1 on every single-beat write, mismatch at beat %0d",
                    tag, i);
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // Capture actual source handshakes
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            total_src_handshakes <= 0;
        end
        else begin
            if (src_fire) begin
                total_src_handshakes <= total_src_handshakes + 1;
            end
        end
    end

    // ------------------------------------------------------------
    // Capture actual AW / W handshakes
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            actual_aw_addr_q.delete();
            actual_w_data_q.delete();
            actual_w_strb_q.delete();
            actual_w_last_q.delete();

            total_aw_handshakes <= 0;
            total_w_handshakes  <= 0;
        end
        else begin
            if (aw_fire) begin
                if (m_axi_awid !== AXI_AWID) begin
                    $fatal(1, "[ADAPTER_TB] AWID mismatch: got=0x%0h exp=0x%0h",
                        m_axi_awid, AXI_AWID);
                end

                if (m_axi_awlen !== 8'd0) begin
                    $fatal(1, "[ADAPTER_TB] AWLEN mismatch: got=%0d exp=0", m_axi_awlen);
                end

                if (m_axi_awburst !== 2'b01) begin
                    $fatal(1, "[ADAPTER_TB] AWBURST mismatch: got=0x%0h exp=INCR", m_axi_awburst);
                end

                actual_aw_addr_q.push_back(m_axi_awaddr);
                total_aw_handshakes <= total_aw_handshakes + 1;
            end

            if (w_fire) begin
                actual_w_data_q.push_back(m_axi_wdata);
                actual_w_strb_q.push_back(m_axi_wstrb);
                actual_w_last_q.push_back(m_axi_wlast);
                total_w_handshakes <= total_w_handshakes + 1;
            end
        end
    end

    // ------------------------------------------------------------
    // Simple AXI write-response model
    //   - one outstanding write at a time
    //   - schedule B only after both AW and W seen
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seen_aw_for_curr  <= 1'b0;
            seen_w_for_curr   <= 1'b0;

            b_pending_valid   <= 1'b0;
            b_pending_delay   <= 0;
            b_pending_resp    <= AXI_RESP_OKAY;
            b_pending_id      <= AXI_AWID;

            m_axi_bvalid      <= 1'b0;
            m_axi_bresp       <= AXI_RESP_OKAY;
            m_axi_bid         <= AXI_AWID;

            total_b_handshakes<= 0;
            scheduled_b_count <= 0;
        end
        else begin
            // Default: hold current B channel state

            // Record AW/W handshakes for current write
            if (aw_fire) begin
                seen_aw_for_curr <= 1'b1;
            end

            if (w_fire) begin
                seen_w_for_curr <= 1'b1;
            end

            // B handshake completes current write response
            if (b_fire) begin
                m_axi_bvalid       <= 1'b0;
                m_axi_bresp        <= AXI_RESP_OKAY;
                m_axi_bid          <= AXI_AWID;
                total_b_handshakes <= total_b_handshakes + 1;
            end

            // Schedule response once both AW and W have been accepted
            if (!m_axi_bvalid && !b_pending_valid &&
                (seen_aw_for_curr || aw_fire) &&
                (seen_w_for_curr  || w_fire)) begin

                int unsigned next_b_index;

                next_b_index = scheduled_b_count + 1;
                scheduled_b_count <= next_b_index;

                b_pending_valid <= 1'b1;
                b_pending_delay <= b_latency_cycles;

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
                    b_pending_id <= AXI_AWID;
                end

                seen_aw_for_curr <= 1'b0;
                seen_w_for_curr  <= 1'b0;
            end
            else if (b_pending_valid && (b_pending_delay != 0)) begin
                b_pending_delay <= b_pending_delay - 1;
            end

            // Drive BVALID after pending delay expires
            if (!m_axi_bvalid && b_pending_valid && (b_pending_delay == 0)) begin
                m_axi_bvalid    <= 1'b1;
                m_axi_bresp     <= b_pending_resp;
                m_axi_bid       <= b_pending_id;
                b_pending_valid <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------
    task automatic run_exact_length_success_test();
        logic [ADDR_WIDTH-1:0] base_addr;
    begin
        $display("[ADAPTER_TB] --------------------------------------------------");
        $display("[ADAPTER_TB] TEST 1: exact-length success");
        $display("[ADAPTER_TB] --------------------------------------------------");

        apply_reset();

        base_addr = 32'h0000_1000;
        build_expected_sequence(base_addr, 4, 16'h0010);

        drive_src_sequence(base_addr, 4, 16'h0010);
        wait_done_or_timeout(300, "exact_length_success");
        check_busy_clears("exact_length_success");

        if (error !== 1'b0) begin
            $fatal(1, "[ADAPTER_TB][exact_length_success] error asserted unexpectedly");
        end

        if (accepted_beats != 32'd4) begin
            $fatal(1, "[ADAPTER_TB][exact_length_success] accepted_beats mismatch: got=%0d exp=4",
                accepted_beats);
        end

        if (committed_beats != 32'd4) begin
            $fatal(1, "[ADAPTER_TB][exact_length_success] committed_beats mismatch: got=%0d exp=4",
                committed_beats);
        end

        if (last_beat_seen !== 1'b1) begin
            $fatal(1, "[ADAPTER_TB][exact_length_success] last_beat_seen expected 1");
        end

        compare_axi_write_sequence("exact_length_success");

        $display("[ADAPTER_TB] PASS: exact-length success");
    end
    endtask

    task automatic run_write_backpressure_test();
        logic [ADDR_WIDTH-1:0] base_addr;
    begin
        $display("[ADAPTER_TB] --------------------------------------------------");
        $display("[ADAPTER_TB] TEST 2: write-side backpressure");
        $display("[ADAPTER_TB] --------------------------------------------------");

        apply_reset();

        base_addr = 32'h0000_2000;
        build_expected_sequence(base_addr, 4, 16'h0100);

        fork
            begin
                awready_ctrl = 1'b1;
                wready_ctrl  = 1'b1;

                wait (busy === 1'b1);

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

        b_latency_cycles = 2;

        drive_src_sequence(base_addr, 4, 16'h0100);
        wait_done_or_timeout(500, "write_backpressure");
        check_busy_clears("write_backpressure");

        if (error !== 1'b0) begin
            $fatal(1, "[ADAPTER_TB][write_backpressure] error asserted unexpectedly");
        end

        if (accepted_beats != 32'd4) begin
            $fatal(1, "[ADAPTER_TB][write_backpressure] accepted_beats mismatch: got=%0d exp=4",
                accepted_beats);
        end

        if (committed_beats != 32'd4) begin
            $fatal(1, "[ADAPTER_TB][write_backpressure] committed_beats mismatch: got=%0d exp=4",
                committed_beats);
        end

        compare_axi_write_sequence("write_backpressure");

        $display("[ADAPTER_TB] PASS: write-side backpressure");
    end
    endtask

    task automatic run_bresp_error_test();
        logic [ADDR_WIDTH-1:0] base_addr;
    begin
        $display("[ADAPTER_TB] --------------------------------------------------");
        $display("[ADAPTER_TB] TEST 3: BRESP error");
        $display("[ADAPTER_TB] --------------------------------------------------");

        apply_reset();

        base_addr = 32'h0000_3000;
        build_expected_sequence(base_addr, 3, 16'h0200);

        inject_bresp_error_beat = 2;

        drive_src_sequence(base_addr, 3, 16'h0200);
        wait_done_or_timeout(400, "bresp_error");
        check_busy_clears("bresp_error");

        if (error !== 1'b1) begin
            $fatal(1, "[ADAPTER_TB][bresp_error] expected error=1");
        end

        if (accepted_beats != 32'd3) begin
            $fatal(1, "[ADAPTER_TB][bresp_error] accepted_beats mismatch: got=%0d exp=3",
                accepted_beats);
        end

        if (committed_beats != 32'd3) begin
            $fatal(1, "[ADAPTER_TB][bresp_error] committed_beats mismatch: got=%0d exp=3",
                committed_beats);
        end

        if (last_beat_seen !== 1'b1) begin
            $fatal(1, "[ADAPTER_TB][bresp_error] last_beat_seen expected 1");
        end

        compare_axi_write_sequence("bresp_error");

        $display("[ADAPTER_TB] PASS: BRESP error");
    end
    endtask

    task automatic run_bid_mismatch_test();
        logic [ADDR_WIDTH-1:0] base_addr;
    begin
        $display("[ADAPTER_TB] --------------------------------------------------");
        $display("[ADAPTER_TB] TEST 4: BID mismatch");
        $display("[ADAPTER_TB] --------------------------------------------------");

        apply_reset();

        base_addr = 32'h0000_4000;
        build_expected_sequence(base_addr, 2, 16'h0300);

        inject_bid_mismatch_beat = 2;
        bad_bid_value            = {AXI_ID_WIDTH{1'b1}};

        drive_src_sequence(base_addr, 2, 16'h0300);
        wait_done_or_timeout(300, "bid_mismatch");
        check_busy_clears("bid_mismatch");

        if (error !== 1'b1) begin
            $fatal(1, "[ADAPTER_TB][bid_mismatch] expected error=1");
        end

        if (accepted_beats != 32'd2) begin
            $fatal(1, "[ADAPTER_TB][bid_mismatch] accepted_beats mismatch: got=%0d exp=2",
                accepted_beats);
        end

        if (committed_beats != 32'd2) begin
            $fatal(1, "[ADAPTER_TB][bid_mismatch] committed_beats mismatch: got=%0d exp=2",
                committed_beats);
        end

        compare_axi_write_sequence("bid_mismatch");

        $display("[ADAPTER_TB] PASS: BID mismatch");
    end
    endtask

    task automatic run_done_after_final_b_test();
        logic [ADDR_WIDTH-1:0] base_addr;
        int unsigned i;
    begin
        $display("[ADAPTER_TB] --------------------------------------------------");
        $display("[ADAPTER_TB] TEST 5: done after final B");
        $display("[ADAPTER_TB] --------------------------------------------------");

        apply_reset();

        base_addr = 32'h0000_5000;
        build_expected_sequence(base_addr, 2, 16'h0400);

        // Make final B clearly delayed so we can check done stays low
        b_latency_cycles = 4;

        fork
            drive_src_sequence(base_addr, 2, 16'h0400);
        join_none

        // Wait until both writes have already issued on AW/W side
        for (i = 0; i < 200; i++) begin
            @(posedge clk);
            if ((total_aw_handshakes >= 2) && (total_w_handshakes >= 2) && (total_b_handshakes == 1)) begin
                break;
            end
        end

        if (!((total_aw_handshakes >= 2) && (total_w_handshakes >= 2) && (total_b_handshakes == 1))) begin
            $fatal(1, "[ADAPTER_TB][done_after_final_b] Did not reach expected pre-final-B state");
        end

        // While waiting for final B, done must remain low
        repeat (2) begin
            @(posedge clk);
            if (done !== 1'b0) begin
                $fatal(1, "[ADAPTER_TB][done_after_final_b] done asserted before final B handshake");
            end
        end

        wait_done_or_timeout(300, "done_after_final_b");
        check_busy_clears("done_after_final_b");

        if (error !== 1'b0) begin
            $fatal(1, "[ADAPTER_TB][done_after_final_b] error asserted unexpectedly");
        end

        if (committed_beats != 32'd2) begin
            $fatal(1, "[ADAPTER_TB][done_after_final_b] committed_beats mismatch: got=%0d exp=2",
                committed_beats);
        end

        compare_axi_write_sequence("done_after_final_b");

        $display("[ADAPTER_TB] PASS: done after final B");
    end
    endtask

    // ------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------
    initial begin
        init_tb_outputs();
        clear_expected_and_actual();

        run_exact_length_success_test();
        run_write_backpressure_test();
        run_bresp_error_test();
        run_bid_mismatch_test();
        run_done_after_final_b_test();

        $display("");
        $display("[ADAPTER_TB] =================================================");
        $display("[ADAPTER_TB] All dma_scratchpad_write_adapter smoke tests PASSED");
        $display("[ADAPTER_TB] =================================================");
        $display("");

        #20;
        $finish;
    end

endmodule

`endif