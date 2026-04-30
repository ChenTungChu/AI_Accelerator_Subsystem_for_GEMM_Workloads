// File: tb/dma/dma_load_engine_tb_top.sv
`ifndef DMA_LOAD_ENGINE_TB_TOP_SV
`define DMA_LOAD_ENGINE_TB_TOP_SV

`timescale 1ns/1ps

module dma_load_engine_tb_top;

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

    localparam logic [AXI_ID_WIDTH-1:0] DMA_ARID     = '0;
    localparam logic [AXI_ID_WIDTH-1:0] ADAPTER_AWID = '0;

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
    // Engine control / status
    // ------------------------------------------------------------
    logic                  load_start;
    logic [ADDR_WIDTH-1:0] src_base_addr;
    logic [ADDR_WIDTH-1:0] dst_base_addr;
    logic [31:0]           load_beats;

    logic                  load_busy;
    logic                  load_done;
    logic                  load_error;

    logic [31:0]           loader_accepted_beats;
    logic [31:0]           loader_written_beats;
    logic                  loader_tlast_seen;

    logic [31:0]           adapter_accepted_beats;
    logic [31:0]           adapter_committed_beats;
    logic                  adapter_last_beat_seen;

    logic                  dma_done_seen;
    logic                  loader_done_seen;
    logic                  adapter_done_seen;

    // ------------------------------------------------------------
    // Source AXI-MM read side
    // ------------------------------------------------------------
    logic [AXI_ID_WIDTH-1:0] src_axi_arid;
    logic [ADDR_WIDTH-1:0]   src_axi_araddr;
    logic [7:0]              src_axi_arlen;
    logic [2:0]              src_axi_arsize;
    logic [1:0]              src_axi_arburst;
    logic                    src_axi_arvalid;
    logic                    src_axi_arready;

    logic [AXI_ID_WIDTH-1:0] src_axi_rid;
    logic [DATA_WIDTH-1:0]   src_axi_rdata;
    logic [1:0]              src_axi_rresp;
    logic                    src_axi_rlast;
    logic                    src_axi_rvalid;
    logic                    src_axi_rready;

    // ------------------------------------------------------------
    // Destination scratchpad AXI-MM write side
    // ------------------------------------------------------------
    logic [AXI_ID_WIDTH-1:0] spad_axi_awid;
    logic [ADDR_WIDTH-1:0]   spad_axi_awaddr;
    logic [7:0]              spad_axi_awlen;
    logic [2:0]              spad_axi_awsize;
    logic [1:0]              spad_axi_awburst;
    logic                    spad_axi_awvalid;
    logic                    spad_axi_awready;

    logic [DATA_WIDTH-1:0]   spad_axi_wdata;
    logic [DATA_WIDTH/8-1:0] spad_axi_wstrb;
    logic                    spad_axi_wlast;
    logic                    spad_axi_wvalid;
    logic                    spad_axi_wready;

    logic [AXI_ID_WIDTH-1:0] spad_axi_bid;
    logic [1:0]              spad_axi_bresp;
    logic                    spad_axi_bvalid;
    logic                    spad_axi_bready;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    dma_load_engine #(
        .ADDR_WIDTH   (ADDR_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .AXI_ID_WIDTH (AXI_ID_WIDTH),
        .DMA_ARID     (DMA_ARID),
        .ADAPTER_AWID (ADAPTER_AWID)
    ) dut (
        .clk                    (clk),
        .rst_n                  (rst_n),

        .load_start             (load_start),
        .src_base_addr          (src_base_addr),
        .dst_base_addr          (dst_base_addr),
        .load_beats             (load_beats),

        .load_busy              (load_busy),
        .load_done              (load_done),
        .load_error             (load_error),

        .loader_accepted_beats  (loader_accepted_beats),
        .loader_written_beats   (loader_written_beats),
        .loader_tlast_seen      (loader_tlast_seen),

        .adapter_accepted_beats (adapter_accepted_beats),
        .adapter_committed_beats(adapter_committed_beats),
        .adapter_last_beat_seen (adapter_last_beat_seen),

        .dma_done_seen          (dma_done_seen),
        .loader_done_seen       (loader_done_seen),
        .adapter_done_seen      (adapter_done_seen),

        .src_axi_arid           (src_axi_arid),
        .src_axi_araddr         (src_axi_araddr),
        .src_axi_arlen          (src_axi_arlen),
        .src_axi_arsize         (src_axi_arsize),
        .src_axi_arburst        (src_axi_arburst),
        .src_axi_arvalid        (src_axi_arvalid),
        .src_axi_arready        (src_axi_arready),

        .src_axi_rid            (src_axi_rid),
        .src_axi_rdata          (src_axi_rdata),
        .src_axi_rresp          (src_axi_rresp),
        .src_axi_rlast          (src_axi_rlast),
        .src_axi_rvalid         (src_axi_rvalid),
        .src_axi_rready         (src_axi_rready),

        .spad_axi_awid          (spad_axi_awid),
        .spad_axi_awaddr        (spad_axi_awaddr),
        .spad_axi_awlen         (spad_axi_awlen),
        .spad_axi_awsize        (spad_axi_awsize),
        .spad_axi_awburst       (spad_axi_awburst),
        .spad_axi_awvalid       (spad_axi_awvalid),
        .spad_axi_awready       (spad_axi_awready),

        .spad_axi_wdata         (spad_axi_wdata),
        .spad_axi_wstrb         (spad_axi_wstrb),
        .spad_axi_wlast         (spad_axi_wlast),
        .spad_axi_wvalid        (spad_axi_wvalid),
        .spad_axi_wready        (spad_axi_wready),

        .spad_axi_bid           (spad_axi_bid),
        .spad_axi_bresp         (spad_axi_bresp),
        .spad_axi_bvalid        (spad_axi_bvalid),
        .spad_axi_bready        (spad_axi_bready)
    );

    // ------------------------------------------------------------
    // Memory models
    // ------------------------------------------------------------
    logic [DATA_WIDTH-1:0] src_mem_model [0:SRC_MEM_DEPTH_WORDS-1];
    logic [DATA_WIDTH-1:0] dst_mem_model [0:DST_MEM_DEPTH_WORDS-1];

    // ------------------------------------------------------------
    // Source AXI read responder state
    // ------------------------------------------------------------
    logic                    rd_pending_valid;
    logic [ADDR_WIDTH-1:0]   rd_pending_addr;
    logic [AXI_ID_WIDTH-1:0] rd_pending_id;
    int unsigned             rd_pending_delay;

    logic [DATA_WIDTH-1:0]   src_s_rdata;
    logic [AXI_ID_WIDTH-1:0] src_s_rid;
    logic [1:0]              src_s_rresp;
    logic                    src_s_rlast;
    logic                    src_s_rvalid;

    logic                    inject_src_rresp_error;

    int unsigned             total_src_ar_handshakes;
    int unsigned             total_src_r_handshakes;

    // ------------------------------------------------------------
    // Destination AXI write slave model knobs
    // ------------------------------------------------------------
    logic awready_ctrl;
    logic wready_ctrl;

    int unsigned b_latency_cycles;
    int signed   inject_bresp_error_beat;
    int signed   inject_bid_mismatch_beat;
    logic [AXI_ID_WIDTH-1:0] bad_bid_value;

    // ------------------------------------------------------------
    // Destination AXI write slave model state
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

    int unsigned             total_spad_aw_handshakes;
    int unsigned             total_spad_w_handshakes;
    int unsigned             total_spad_b_handshakes;
    int unsigned             scheduled_b_count;

    // ------------------------------------------------------------
    // Expected / actual write sequences
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] expected_wr_addr_q[$];
    logic [DATA_WIDTH-1:0] expected_wr_data_q[$];

    logic [ADDR_WIDTH-1:0] actual_wr_addr_q[$];
    logic [DATA_WIDTH-1:0] actual_wr_data_q[$];
    bit                    actual_wr_last_q[$];

    // ------------------------------------------------------------
    // Handshake helpers
    // ------------------------------------------------------------
    logic src_ar_fire;
    logic src_r_fire;

    logic spad_aw_fire;
    logic spad_w_fire;
    logic spad_b_fire;

    always_comb begin
        src_ar_fire  = src_axi_arvalid  && src_axi_arready;
        src_r_fire   = src_axi_rvalid   && src_axi_rready;

        spad_aw_fire = spad_axi_awvalid && spad_axi_awready;
        spad_w_fire  = spad_axi_wvalid  && spad_axi_wready;
        spad_b_fire  = spad_axi_bvalid  && spad_axi_bready;
    end

    always_comb begin
        sched_awaddr = spad_aw_fire ? spad_axi_awaddr : curr_awaddr;
        sched_wdata  = spad_w_fire  ? spad_axi_wdata  : curr_wdata;
        sched_wstrb  = spad_w_fire  ? spad_axi_wstrb  : curr_wstrb;
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
        lo = 32'hD000_0000 + seed;
        hi = 32'hE000_0000 + seed;
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

        actual_wr_addr_q.delete();
        actual_wr_data_q.delete();
        actual_wr_last_q.delete();
    end
    endtask

    task automatic init_tb_outputs();
    begin
        load_start   = 1'b0;
        src_base_addr = '0;
        dst_base_addr = '0;
        load_beats    = '0;

        inject_src_rresp_error = 1'b0;

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
                $fatal(1, "[LOAD_ENGINE_TB] preload_src_words out of range: idx=%0d depth=%0d",
                    idx, SRC_MEM_DEPTH_WORDS);
            end

            src_mem_model[idx] = make_test_word(seed_base + i);
        end
    end
    endtask

    task automatic build_expected_write_sequence_from_src(
        input logic [ADDR_WIDTH-1:0] src_base,
        input logic [ADDR_WIDTH-1:0] dst_base,
        input int unsigned           beat_count
    );
        int unsigned i;
        int unsigned idx;
    begin
        expected_wr_addr_q.delete();
        expected_wr_data_q.delete();

        for (i = 0; i < beat_count; i++) begin
            idx = word_index_from_addr(src_base) + i;

            if (idx >= SRC_MEM_DEPTH_WORDS) begin
                $fatal(1, "[LOAD_ENGINE_TB] build_expected out of range: idx=%0d depth=%0d",
                    idx, SRC_MEM_DEPTH_WORDS);
            end

            expected_wr_addr_q.push_back(dst_base + ADDR_WIDTH'(i * BYTES_PER_BEAT));
            expected_wr_data_q.push_back(src_mem_model[idx]);
        end
    end
    endtask

    task automatic launch_load(
        input logic [ADDR_WIDTH-1:0] src_addr,
        input logic [ADDR_WIDTH-1:0] dst_addr,
        input logic [31:0]           beats
    );
    begin
        src_base_addr = src_addr;
        dst_base_addr = dst_addr;
        load_beats    = beats;
        load_start    = 1'b1;
        @(posedge clk);
        load_start    = 1'b0;
    end
    endtask

    task automatic wait_load_done_or_timeout(
        input int unsigned timeout_cycles,
        input string       tag
    );
        int unsigned i;
    begin
        for (i = 0; i < timeout_cycles; i++) begin
            #1;
            if (load_done === 1'b1) begin
                return;
            end

            @(posedge clk);
            if (load_done === 1'b1) begin
                return;
            end
        end

        $fatal(1, "[LOAD_ENGINE_TB][%s] Timeout waiting for load_done after %0d cycles",
            tag, timeout_cycles);
    end
    endtask

    task automatic check_busy_clears(
        input string tag
    );
    begin
        @(posedge clk);
        if (load_busy !== 1'b0) begin
            $fatal(1, "[LOAD_ENGINE_TB][%s] load_busy did not clear after load_done", tag);
        end
    end
    endtask

    task automatic expect_axi_count_delta(
        input int unsigned ar_before,
        input int unsigned aw_before,
        input int unsigned w_before,
        input int unsigned b_before,
        input int unsigned exp_ar_delta,
        input int unsigned exp_aw_delta,
        input int unsigned exp_w_delta,
        input int unsigned exp_b_delta,
        input string       tag
    );
        int unsigned ar_delta;
        int unsigned aw_delta;
        int unsigned w_delta;
        int unsigned b_delta;
    begin
        ar_delta = total_src_ar_handshakes  - ar_before;
        aw_delta = total_spad_aw_handshakes - aw_before;
        w_delta  = total_spad_w_handshakes  - w_before;
        b_delta  = total_spad_b_handshakes  - b_before;

        if (ar_delta != exp_ar_delta) begin
            $fatal(1, "[LOAD_ENGINE_TB][%s] AR delta mismatch: got=%0d exp=%0d",
                tag, ar_delta, exp_ar_delta);
        end

        if (aw_delta != exp_aw_delta) begin
            $fatal(1, "[LOAD_ENGINE_TB][%s] AW delta mismatch: got=%0d exp=%0d",
                tag, aw_delta, exp_aw_delta);
        end

        if (w_delta != exp_w_delta) begin
            $fatal(1, "[LOAD_ENGINE_TB][%s] W delta mismatch: got=%0d exp=%0d",
                tag, w_delta, exp_w_delta);
        end

        if (b_delta != exp_b_delta) begin
            $fatal(1, "[LOAD_ENGINE_TB][%s] B delta mismatch: got=%0d exp=%0d",
                tag, b_delta, exp_b_delta);
        end
    end
    endtask

    task automatic compare_actual_write_sequence(
        input string tag
    );
        int unsigned i;
    begin
        if (actual_wr_addr_q.size() != expected_wr_addr_q.size()) begin
            $fatal(1, "[LOAD_ENGINE_TB][%s] AW count mismatch: got=%0d exp=%0d",
                tag, actual_wr_addr_q.size(), expected_wr_addr_q.size());
        end

        if (actual_wr_data_q.size() != expected_wr_data_q.size()) begin
            $fatal(1, "[LOAD_ENGINE_TB][%s] W count mismatch: got=%0d exp=%0d",
                tag, actual_wr_data_q.size(), expected_wr_data_q.size());
        end

        for (i = 0; i < expected_wr_addr_q.size(); i++) begin
            if (actual_wr_addr_q[i] !== expected_wr_addr_q[i]) begin
                $fatal(1, "[LOAD_ENGINE_TB][%s] AWADDR mismatch at beat %0d: got=0x%08h exp=0x%08h",
                    tag, i, actual_wr_addr_q[i], expected_wr_addr_q[i]);
            end

            if (actual_wr_data_q[i] !== expected_wr_data_q[i]) begin
                $fatal(1, "[LOAD_ENGINE_TB][%s] WDATA mismatch at beat %0d: got=0x%016h exp=0x%016h",
                    tag, i, actual_wr_data_q[i], expected_wr_data_q[i]);
            end

            if (actual_wr_last_q[i] !== 1'b1) begin
                $fatal(1, "[LOAD_ENGINE_TB][%s] WLAST expected 1 at beat %0d",
                    tag, i);
            end
        end
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
                $fatal(1, "[LOAD_ENGINE_TB][%s] dst mem compare out of range: idx=%0d depth=%0d",
                    tag, idx, DST_MEM_DEPTH_WORDS);
            end

            if (dst_mem_model[idx] !== expected_wr_data_q[i]) begin
                $fatal(1, "[LOAD_ENGINE_TB][%s] DST mem mismatch at beat %0d: got=0x%016h exp=0x%016h",
                    tag, i, dst_mem_model[idx], expected_wr_data_q[i]);
            end
        end
    end
    endtask

    task automatic expect_no_writes(
        input string tag
    );
    begin
        if (actual_wr_addr_q.size() != 0) begin
            $fatal(1, "[LOAD_ENGINE_TB][%s] Unexpected AW writes observed: count=%0d",
                tag, actual_wr_addr_q.size());
        end

        if (actual_wr_data_q.size() != 0) begin
            $fatal(1, "[LOAD_ENGINE_TB][%s] Unexpected W writes observed: count=%0d",
                tag, actual_wr_data_q.size());
        end
    end
    endtask

    // ------------------------------------------------------------
    // Source AXI read slave model
    // ------------------------------------------------------------
    assign src_axi_arready = rst_n && !rd_pending_valid && !src_s_rvalid;

    assign src_axi_rid     = src_s_rid;
    assign src_axi_rdata   = src_s_rdata;
    assign src_axi_rresp   = src_s_rresp;
    assign src_axi_rlast   = src_s_rlast;
    assign src_axi_rvalid  = src_s_rvalid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_pending_valid       <= 1'b0;
            rd_pending_addr        <= '0;
            rd_pending_id          <= '0;
            rd_pending_delay       <= 0;

            src_s_rdata            <= '0;
            src_s_rid              <= '0;
            src_s_rresp            <= AXI_RESP_OKAY;
            src_s_rlast            <= 1'b0;
            src_s_rvalid           <= 1'b0;

            total_src_ar_handshakes <= 0;
            total_src_r_handshakes  <= 0;
        end
        else begin
            if (src_ar_fire) begin
                if (src_axi_arid !== DMA_ARID) begin
                    $fatal(1, "[LOAD_ENGINE_TB] ARID mismatch: got=0x%0h exp=0x%0h",
                        src_axi_arid, DMA_ARID);
                end

                if (src_axi_arlen !== 8'd0) begin
                    $fatal(1, "[LOAD_ENGINE_TB] ARLEN mismatch: got=%0d exp=0",
                        src_axi_arlen);
                end

                rd_pending_valid        <= 1'b1;
                rd_pending_addr         <= src_axi_araddr;
                rd_pending_id           <= src_axi_arid;
                rd_pending_delay        <= READ_LATENCY_CYCLES;
                total_src_ar_handshakes <= total_src_ar_handshakes + 1;
            end
            else if (rd_pending_valid && (rd_pending_delay != 0)) begin
                rd_pending_delay <= rd_pending_delay - 1;
            end

            if (src_r_fire) begin
                src_s_rvalid           <= 1'b0;
                src_s_rlast            <= 1'b0;
                src_s_rresp            <= AXI_RESP_OKAY;
                src_s_rdata            <= '0;
                src_s_rid              <= '0;
                total_src_r_handshakes <= total_src_r_handshakes + 1;
            end

            if (!src_s_rvalid && rd_pending_valid && (rd_pending_delay == 0)) begin
                int unsigned idx;

                idx = word_index_from_addr(rd_pending_addr);
                if (idx >= SRC_MEM_DEPTH_WORDS) begin
                    $fatal(1, "[LOAD_ENGINE_TB] Source read out of range: addr=0x%08h idx=%0d depth=%0d",
                        rd_pending_addr, idx, SRC_MEM_DEPTH_WORDS);
                end

                src_s_rvalid <= 1'b1;
                src_s_rid    <= rd_pending_id;
                src_s_rdata  <= src_mem_model[idx];
                src_s_rresp  <= inject_src_rresp_error ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
                src_s_rlast  <= 1'b1;

                rd_pending_valid <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------
    // Destination AXI write slave model
    // ------------------------------------------------------------
    assign spad_axi_awready = rst_n && awready_ctrl && !spad_axi_bvalid;
    assign spad_axi_wready  = rst_n && wready_ctrl  && !spad_axi_bvalid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seen_aw_for_curr <= 1'b0;
            seen_w_for_curr  <= 1'b0;

            curr_awaddr      <= '0;
            curr_wdata       <= '0;
            curr_wstrb       <= '0;

            b_pending_valid  <= 1'b0;
            b_pending_delay  <= 0;
            b_pending_resp   <= AXI_RESP_OKAY;
            b_pending_id     <= ADAPTER_AWID;
            b_pending_addr   <= '0;
            b_pending_data   <= '0;
            b_pending_strb   <= '0;

            spad_axi_bvalid  <= 1'b0;
            spad_axi_bresp   <= AXI_RESP_OKAY;
            spad_axi_bid     <= ADAPTER_AWID;

            total_spad_aw_handshakes <= 0;
            total_spad_w_handshakes  <= 0;
            total_spad_b_handshakes  <= 0;
            scheduled_b_count        <= 0;
        end
        else begin
            if (spad_aw_fire) begin
                if (spad_axi_awid !== ADAPTER_AWID) begin
                    $fatal(1, "[LOAD_ENGINE_TB] AWID mismatch: got=0x%0h exp=0x%0h",
                        spad_axi_awid, ADAPTER_AWID);
                end

                if (spad_axi_awlen !== 8'd0) begin
                    $fatal(1, "[LOAD_ENGINE_TB] AWLEN mismatch: got=%0d exp=0",
                        spad_axi_awlen);
                end

                if (spad_axi_awburst !== 2'b01) begin
                    $fatal(1, "[LOAD_ENGINE_TB] AWBURST mismatch: got=0x%0h exp=INCR",
                        spad_axi_awburst);
                end

                seen_aw_for_curr <= 1'b1;
                curr_awaddr      <= spad_axi_awaddr;
                total_spad_aw_handshakes <= total_spad_aw_handshakes + 1;

                actual_wr_addr_q.push_back(spad_axi_awaddr);
            end

            if (spad_w_fire) begin
                if (spad_axi_wstrb !== FULL_STRB) begin
                    $fatal(1, "[LOAD_ENGINE_TB] WSTRB mismatch: got=0x%0h exp=0x%0h",
                        spad_axi_wstrb, FULL_STRB);
                end

                if (spad_axi_wlast !== 1'b1) begin
                    $fatal(1, "[LOAD_ENGINE_TB] WLAST expected 1 for single-beat write");
                end

                seen_w_for_curr <= 1'b1;
                curr_wdata      <= spad_axi_wdata;
                curr_wstrb      <= spad_axi_wstrb;
                total_spad_w_handshakes <= total_spad_w_handshakes + 1;

                actual_wr_data_q.push_back(spad_axi_wdata);
                actual_wr_last_q.push_back(spad_axi_wlast);
            end

            if (spad_b_fire) begin
                int unsigned idx;
                int unsigned b;

                if (spad_axi_bresp == AXI_RESP_OKAY) begin
                    idx = word_index_from_addr(b_pending_addr);

                    if (idx >= DST_MEM_DEPTH_WORDS) begin
                        $fatal(1, "[LOAD_ENGINE_TB] Destination write out of range: addr=0x%08h idx=%0d depth=%0d",
                            b_pending_addr, idx, DST_MEM_DEPTH_WORDS);
                    end

                    for (b = 0; b < BYTES_PER_BEAT; b++) begin
                        if (b_pending_strb[b]) begin
                            dst_mem_model[idx][8*b +: 8] <= b_pending_data[8*b +: 8];
                        end
                    end
                end

                spad_axi_bvalid <= 1'b0;
                spad_axi_bresp  <= AXI_RESP_OKAY;
                spad_axi_bid    <= ADAPTER_AWID;

                total_spad_b_handshakes <= total_spad_b_handshakes + 1;
            end

            if (!spad_axi_bvalid && !b_pending_valid &&
                (seen_aw_for_curr || spad_aw_fire) &&
                (seen_w_for_curr  || spad_w_fire)) begin

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
                    b_pending_id <= ADAPTER_AWID;
                end

                seen_aw_for_curr <= 1'b0;
                seen_w_for_curr  <= 1'b0;
            end
            else if (b_pending_valid && (b_pending_delay != 0)) begin
                b_pending_delay <= b_pending_delay - 1;
            end

            if (!spad_axi_bvalid && b_pending_valid && (b_pending_delay == 0)) begin
                spad_axi_bvalid <= 1'b1;
                spad_axi_bresp  <= b_pending_resp;
                spad_axi_bid    <= b_pending_id;

                b_pending_valid <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------
    task automatic run_exact_length_success_test();
        logic [ADDR_WIDTH-1:0] src_base;
        logic [ADDR_WIDTH-1:0] dst_base;
        int unsigned ar_before;
        int unsigned aw_before;
        int unsigned w_before;
        int unsigned b_before;
    begin
        $display("[LOAD_ENGINE_TB] --------------------------------------------------");
        $display("[LOAD_ENGINE_TB] TEST 1: exact-length load success");
        $display("[LOAD_ENGINE_TB] --------------------------------------------------");

        apply_reset();
        clear_src_mem();
        clear_dst_mem();

        src_base = 32'h0000_0100;
        dst_base = 32'h0000_1000;

        preload_src_words(src_base, 4, 16'h0010);
        build_expected_write_sequence_from_src(src_base, dst_base, 4);

        ar_before = total_src_ar_handshakes;
        aw_before = total_spad_aw_handshakes;
        w_before  = total_spad_w_handshakes;
        b_before  = total_spad_b_handshakes;

        launch_load(src_base, dst_base, 4);
        wait_load_done_or_timeout(600, "exact_length_success");
        check_busy_clears("exact_length_success");

        if (load_error !== 1'b0) begin
            $fatal(1, "[LOAD_ENGINE_TB][exact_length_success] load_error asserted unexpectedly");
        end

        if (loader_accepted_beats != 32'd4 || loader_written_beats != 32'd4) begin
            $fatal(1, "[LOAD_ENGINE_TB][exact_length_success] loader counters mismatch");
        end

        if (adapter_accepted_beats != 32'd4 || adapter_committed_beats != 32'd4) begin
            $fatal(1, "[LOAD_ENGINE_TB][exact_length_success] adapter counters mismatch");
        end

        if (loader_tlast_seen !== 1'b1 || adapter_last_beat_seen !== 1'b1) begin
            $fatal(1, "[LOAD_ENGINE_TB][exact_length_success] last/tlast seen mismatch");
        end

        expect_axi_count_delta(ar_before, aw_before, w_before, b_before, 4, 4, 4, 4, "exact_length_success");
        compare_actual_write_sequence("exact_length_success");
        compare_dst_mem_against_expected(4, "exact_length_success");

        $display("[LOAD_ENGINE_TB] PASS: exact-length load success");
    end
    endtask

    task automatic run_write_side_backpressure_test();
        logic [ADDR_WIDTH-1:0] src_base;
        logic [ADDR_WIDTH-1:0] dst_base;
        int unsigned ar_before;
        int unsigned aw_before;
        int unsigned w_before;
        int unsigned b_before;
    begin
        $display("[LOAD_ENGINE_TB] --------------------------------------------------");
        $display("[LOAD_ENGINE_TB] TEST 2: write-side backpressure");
        $display("[LOAD_ENGINE_TB] --------------------------------------------------");

        apply_reset();
        clear_src_mem();
        clear_dst_mem();

        src_base = 32'h0000_0200;
        dst_base = 32'h0000_1100;

        preload_src_words(src_base, 4, 16'h0100);
        build_expected_write_sequence_from_src(src_base, dst_base, 4);

        ar_before = total_src_ar_handshakes;
        aw_before = total_spad_aw_handshakes;
        w_before  = total_spad_w_handshakes;
        b_before  = total_spad_b_handshakes;

        fork
            begin
                awready_ctrl     = 1'b1;
                wready_ctrl      = 1'b1;
                b_latency_cycles = 3;

                wait (load_busy === 1'b1);

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

        launch_load(src_base, dst_base, 4);
        wait_load_done_or_timeout(900, "write_side_backpressure");
        check_busy_clears("write_side_backpressure");

        if (load_error !== 1'b0) begin
            $fatal(1, "[LOAD_ENGINE_TB][write_side_backpressure] load_error asserted unexpectedly");
        end

        if (loader_accepted_beats != 32'd4 || loader_written_beats != 32'd4) begin
            $fatal(1, "[LOAD_ENGINE_TB][write_side_backpressure] loader counters mismatch");
        end

        if (adapter_accepted_beats != 32'd4 || adapter_committed_beats != 32'd4) begin
            $fatal(1, "[LOAD_ENGINE_TB][write_side_backpressure] adapter counters mismatch");
        end

        expect_axi_count_delta(ar_before, aw_before, w_before, b_before, 4, 4, 4, 4, "write_side_backpressure");
        compare_actual_write_sequence("write_side_backpressure");
        compare_dst_mem_against_expected(4, "write_side_backpressure");

        $display("[LOAD_ENGINE_TB] PASS: write-side backpressure");
    end
    endtask

    task automatic run_bresp_error_test();
        logic [ADDR_WIDTH-1:0] src_base;
        logic [ADDR_WIDTH-1:0] dst_base;
        int unsigned ar_before;
        int unsigned aw_before;
        int unsigned w_before;
        int unsigned b_before;
    begin
        $display("[LOAD_ENGINE_TB] --------------------------------------------------");
        $display("[LOAD_ENGINE_TB] TEST 3: adapter BRESP error");
        $display("[LOAD_ENGINE_TB] --------------------------------------------------");

        apply_reset();
        clear_src_mem();
        clear_dst_mem();

        src_base = 32'h0000_0300;
        dst_base = 32'h0000_1200;

        preload_src_words(src_base, 3, 16'h0200);
        build_expected_write_sequence_from_src(src_base, dst_base, 3);

        ar_before = total_src_ar_handshakes;
        aw_before = total_spad_aw_handshakes;
        w_before  = total_spad_w_handshakes;
        b_before  = total_spad_b_handshakes;

        inject_bresp_error_beat = 2;

        launch_load(src_base, dst_base, 3);
        wait_load_done_or_timeout(700, "bresp_error");
        check_busy_clears("bresp_error");

        if (load_error !== 1'b1) begin
            $fatal(1, "[LOAD_ENGINE_TB][bresp_error] expected load_error=1");
        end

        if (loader_accepted_beats != 32'd3 || loader_written_beats != 32'd3) begin
            $fatal(1, "[LOAD_ENGINE_TB][bresp_error] loader counters mismatch");
        end

        if (adapter_accepted_beats != 32'd3 || adapter_committed_beats != 32'd3) begin
            $fatal(1, "[LOAD_ENGINE_TB][bresp_error] adapter counters mismatch");
        end

        expect_axi_count_delta(ar_before, aw_before, w_before, b_before, 3, 3, 3, 3, "bresp_error");
        compare_actual_write_sequence("bresp_error");

        $display("[LOAD_ENGINE_TB] PASS: adapter BRESP error");
    end
    endtask

    task automatic run_invalid_zero_length_test();
        int unsigned ar_before;
        int unsigned aw_before;
        int unsigned w_before;
        int unsigned b_before;
    begin
        $display("[LOAD_ENGINE_TB] --------------------------------------------------");
        $display("[LOAD_ENGINE_TB] TEST 4: invalid zero load_beats");
        $display("[LOAD_ENGINE_TB] --------------------------------------------------");

        apply_reset();
        clear_src_mem();
        clear_dst_mem();

        ar_before = total_src_ar_handshakes;
        aw_before = total_spad_aw_handshakes;
        w_before  = total_spad_w_handshakes;
        b_before  = total_spad_b_handshakes;

        launch_load(32'h0000_0100, 32'h0000_1000, 0);
        wait_load_done_or_timeout(30, "invalid_zero_length");
        check_busy_clears("invalid_zero_length");

        if (load_error !== 1'b1) begin
            $fatal(1, "[LOAD_ENGINE_TB][invalid_zero_length] expected load_error=1");
        end

        expect_axi_count_delta(ar_before, aw_before, w_before, b_before, 0, 0, 0, 0, "invalid_zero_length");
        expect_no_writes("invalid_zero_length");

        $display("[LOAD_ENGINE_TB] PASS: invalid zero load_beats");
    end
    endtask

    task automatic run_invalid_unaligned_src_test();
        int unsigned ar_before;
        int unsigned aw_before;
        int unsigned w_before;
        int unsigned b_before;
    begin
        $display("[LOAD_ENGINE_TB] --------------------------------------------------");
        $display("[LOAD_ENGINE_TB] TEST 5: invalid unaligned src address");
        $display("[LOAD_ENGINE_TB] --------------------------------------------------");

        apply_reset();
        clear_src_mem();
        clear_dst_mem();

        ar_before = total_src_ar_handshakes;
        aw_before = total_spad_aw_handshakes;
        w_before  = total_spad_w_handshakes;
        b_before  = total_spad_b_handshakes;

        launch_load(32'h0000_0104, 32'h0000_1000, 2);
        wait_load_done_or_timeout(30, "invalid_unaligned_src");
        check_busy_clears("invalid_unaligned_src");

        if (load_error !== 1'b1) begin
            $fatal(1, "[LOAD_ENGINE_TB][invalid_unaligned_src] expected load_error=1");
        end

        expect_axi_count_delta(ar_before, aw_before, w_before, b_before, 0, 0, 0, 0, "invalid_unaligned_src");
        expect_no_writes("invalid_unaligned_src");

        $display("[LOAD_ENGINE_TB] PASS: invalid unaligned src address");
    end
    endtask

    task automatic run_invalid_unaligned_dst_test();
        int unsigned ar_before;
        int unsigned aw_before;
        int unsigned w_before;
        int unsigned b_before;
    begin
        $display("[LOAD_ENGINE_TB] --------------------------------------------------");
        $display("[LOAD_ENGINE_TB] TEST 6: invalid unaligned dst address");
        $display("[LOAD_ENGINE_TB] --------------------------------------------------");

        apply_reset();
        clear_src_mem();
        clear_dst_mem();

        ar_before = total_src_ar_handshakes;
        aw_before = total_spad_aw_handshakes;
        w_before  = total_spad_w_handshakes;
        b_before  = total_spad_b_handshakes;

        launch_load(32'h0000_0100, 32'h0000_1004, 2);
        wait_load_done_or_timeout(30, "invalid_unaligned_dst");
        check_busy_clears("invalid_unaligned_dst");

        if (load_error !== 1'b1) begin
            $fatal(1, "[LOAD_ENGINE_TB][invalid_unaligned_dst] expected load_error=1");
        end

        expect_axi_count_delta(ar_before, aw_before, w_before, b_before, 0, 0, 0, 0, "invalid_unaligned_dst");
        expect_no_writes("invalid_unaligned_dst");

        $display("[LOAD_ENGINE_TB] PASS: invalid unaligned dst address");
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
        run_write_side_backpressure_test();
        run_bresp_error_test();
        run_invalid_zero_length_test();
        run_invalid_unaligned_src_test();
        run_invalid_unaligned_dst_test();

        $display("");
        $display("[LOAD_ENGINE_TB] ================================================");
        $display("[LOAD_ENGINE_TB] All dma_load_engine smoke tests PASSED");
        $display("[LOAD_ENGINE_TB] ================================================");
        $display("");

        #20;
        $finish;
    end

endmodule

`endif