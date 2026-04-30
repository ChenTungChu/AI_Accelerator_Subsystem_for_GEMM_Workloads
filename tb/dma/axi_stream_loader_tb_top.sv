// File: tb/dma/axi_stream_loader_tb_top.sv
`ifndef AXI_STREAM_LOADER_TB_TOP_SV
`define AXI_STREAM_LOADER_TB_TOP_SV

`timescale 1ns/1ps

module axi_stream_loader_tb_top;

    // ------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------
    localparam int ADDR_WIDTH         = 32;
    localparam int DATA_WIDTH         = 64;
    localparam int BYTES_PER_BEAT     = DATA_WIDTH / 8;
    localparam int BEAT_ADDR_LSB      = (BYTES_PER_BEAT <= 1) ? 0 : $clog2(BYTES_PER_BEAT);

    localparam int CAPTURE_DEPTH      = 1024;
    localparam int CAPTURE_ADDR_WIDTH = (CAPTURE_DEPTH <= 1) ? 1 : $clog2(CAPTURE_DEPTH);

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
    // Loader control
    // ------------------------------------------------------------
    logic                  start;
    logic [ADDR_WIDTH-1:0] dst_base_addr;
    logic [31:0]           expected_beats;

    logic                  busy;
    logic                  done;
    logic                  error;

    // ------------------------------------------------------------
    // AXIS source (TB drives into DUT)
    // ------------------------------------------------------------
    logic [DATA_WIDTH-1:0] s_axis_tdata;
    logic                  s_axis_tvalid;
    logic                  s_axis_tready;
    logic                  s_axis_tlast;

    // ------------------------------------------------------------
    // Linear write-request output
    // ------------------------------------------------------------
    logic                  wr_valid;
    logic                  wr_ready;
    logic [ADDR_WIDTH-1:0] wr_addr;
    logic [DATA_WIDTH-1:0] wr_data;
    logic [DATA_WIDTH/8-1:0] wr_strb;
    logic                  wr_last;

    // ------------------------------------------------------------
    // Debug / readback
    // ------------------------------------------------------------
    logic                          rd_en;
    logic [CAPTURE_ADDR_WIDTH-1:0] rd_addr;
    logic [DATA_WIDTH-1:0]         rd_data;

    logic [31:0]                   accepted_beats;
    logic [31:0]                   written_beats;
    logic                          tlast_seen;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    axi_stream_loader #(
        .ADDR_WIDTH        (ADDR_WIDTH),
        .DATA_WIDTH        (DATA_WIDTH)
    ) dut (
        .clk               (clk),
        .rst_n             (rst_n),

        .start             (start),
        .dst_base_addr     (dst_base_addr),
        .expected_beats    (expected_beats),

        .busy              (busy),
        .done              (done),
        .error             (error),

        .s_axis_tdata      (s_axis_tdata),
        .s_axis_tvalid     (s_axis_tvalid),
        .s_axis_tready     (s_axis_tready),
        .s_axis_tlast      (s_axis_tlast),

        .wr_valid          (wr_valid),
        .wr_ready          (wr_ready),
        .wr_addr           (wr_addr),
        .wr_data           (wr_data),
        .wr_strb           (wr_strb),
        .wr_last           (wr_last),

        .accepted_beats    (accepted_beats),
        .written_beats     (written_beats),
        .tlast_seen        (tlast_seen),

        .rd_en             (rd_en),
        .rd_addr           (rd_addr),
        .rd_data           (rd_data)
    );

    // ------------------------------------------------------------
    // Expected / Actual queues
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0]   expected_addr_q[$];
    logic [DATA_WIDTH-1:0]   expected_data_q[$];
    bit                      expected_last_q[$];

    logic [ADDR_WIDTH-1:0]   actual_addr_q[$];
    logic [DATA_WIDTH-1:0]   actual_data_q[$];
    bit                      actual_last_q[$];

    int unsigned             total_wr_handshakes;

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------
    function automatic logic [DATA_WIDTH-1:0] make_test_word(
        input int unsigned seed
    );
        logic [31:0] lo;
        logic [31:0] hi;
    begin
        lo = 32'h5000_0000 + seed;
        hi = 32'h6000_0000 + seed;
        return {hi, lo};
    end
    endfunction

    task automatic clear_expected_and_actual();
    begin
        expected_addr_q.delete();
        expected_data_q.delete();
        expected_last_q.delete();

        actual_addr_q.delete();
        actual_data_q.delete();
        actual_last_q.delete();
    end
    endtask

    task automatic init_tb_outputs();
    begin
        start          = 1'b0;
        dst_base_addr  = '0;
        expected_beats = '0;

        s_axis_tdata   = '0;
        s_axis_tvalid  = 1'b0;
        s_axis_tlast   = 1'b0;

        wr_ready       = 1'b1;

        rd_en          = 1'b0;
        rd_addr        = '0;
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

    task automatic launch_loader(
        input logic [ADDR_WIDTH-1:0] base_addr,
        input logic [31:0]           exp_beats
    );
    begin
        dst_base_addr  = base_addr;
        expected_beats = exp_beats;
        start          = 1'b1;
        @(posedge clk);
        start          = 1'b0;
    end
    endtask

    task automatic build_expected_write_sequence(
        input logic [ADDR_WIDTH-1:0] base_addr,
        input int unsigned           beat_count,
        input int unsigned           seed_base,
        input int signed             last_index
    );
        int unsigned i;
    begin
        expected_addr_q.delete();
        expected_data_q.delete();
        expected_last_q.delete();

        for (i = 0; i < beat_count; i++) begin
            expected_addr_q.push_back(base_addr + ADDR_WIDTH'(i * BYTES_PER_BEAT));
            expected_data_q.push_back(make_test_word(seed_base + i));
            expected_last_q.push_back((last_index >= 0) && (i == last_index));
        end
    end
    endtask

    task automatic drive_axis_sequence(
        input int unsigned beat_count,
        input int unsigned seed_base,
        input int signed   last_index
    );
        int unsigned i;
    begin
        for (i = 0; i < beat_count; i++) begin
            s_axis_tdata  = make_test_word(seed_base + i);
            s_axis_tlast  = ((last_index >= 0) && (i == last_index));
            s_axis_tvalid = 1'b1;

            while (1) begin
                @(posedge clk);
                if (s_axis_tvalid && s_axis_tready) begin
                    break;
                end
            end
        end

        s_axis_tvalid = 1'b0;
        s_axis_tdata  = '0;
        s_axis_tlast  = 1'b0;
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

        $fatal(1, "[LOADER_TB][%s] Timeout waiting for done after %0d cycles",
            tag, timeout_cycles);
    end
    endtask

    task automatic check_busy_clears(
        input string tag
    );
    begin
        @(posedge clk);
        if (busy !== 1'b0) begin
            $fatal(1, "[LOADER_TB][%s] busy did not clear after done pulse", tag);
        end
    end
    endtask

    task automatic compare_write_sequence(
        input string tag
    );
        int unsigned i;
    begin
        if (actual_addr_q.size() != expected_addr_q.size()) begin
            $fatal(1, "[LOADER_TB][%s] Write count mismatch: got=%0d exp=%0d",
                tag, actual_addr_q.size(), expected_addr_q.size());
        end

        if (actual_data_q.size() != expected_data_q.size()) begin
            $fatal(1, "[LOADER_TB][%s] Data count mismatch: got=%0d exp=%0d",
                tag, actual_data_q.size(), expected_data_q.size());
        end

        if (actual_last_q.size() != expected_last_q.size()) begin
            $fatal(1, "[LOADER_TB][%s] Last-flag count mismatch: got=%0d exp=%0d",
                tag, actual_last_q.size(), expected_last_q.size());
        end

        for (i = 0; i < expected_addr_q.size(); i++) begin
            if (actual_addr_q[i] !== expected_addr_q[i]) begin
                $fatal(1, "[LOADER_TB][%s] wr_addr mismatch at beat %0d: got=0x%08h exp=0x%08h",
                    tag, i, actual_addr_q[i], expected_addr_q[i]);
            end

            if (actual_data_q[i] !== expected_data_q[i]) begin
                $fatal(1, "[LOADER_TB][%s] wr_data mismatch at beat %0d: got=0x%016h exp=0x%016h",
                    tag, i, actual_data_q[i], expected_data_q[i]);
            end

            if (actual_last_q[i] !== expected_last_q[i]) begin
                $fatal(1, "[LOADER_TB][%s] wr_last mismatch at beat %0d: got=%0b exp=%0b",
                    tag, i, actual_last_q[i], expected_last_q[i]);
            end
        end
    end
    endtask

    task automatic expect_no_writes(
        input string tag
    );
    begin
        if (actual_addr_q.size() != 0) begin
            $fatal(1, "[LOADER_TB][%s] Unexpected writes observed: count=%0d",
                tag, actual_addr_q.size());
        end
    end
    endtask

    task automatic compare_readback_against_expected(
        input int unsigned beat_count,
        input string       tag
    );
        int unsigned i;
    begin
        rd_en = 1'b1;

        for (i = 0; i < beat_count; i++) begin
            rd_addr = i[CAPTURE_ADDR_WIDTH-1:0];
            #1;
            if (rd_data !== expected_data_q[i]) begin
                $fatal(1, "[LOADER_TB][%s] Readback mismatch at beat %0d: got=0x%016h exp=0x%016h",
                    tag, i, rd_data, expected_data_q[i]);
            end
        end

        rd_en   = 1'b0;
        rd_addr = '0;
    end
    endtask

    // ------------------------------------------------------------
    // Capture actual writes
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            actual_addr_q.delete();
            actual_data_q.delete();
            actual_last_q.delete();
            total_wr_handshakes <= 0;
        end
        else begin
            if (wr_valid && wr_ready) begin
                if (wr_strb !== FULL_STRB) begin
                    $fatal(1, "[LOADER_TB] wr_strb mismatch: got=0x%0h exp=0x%0h",
                        wr_strb, FULL_STRB);
                end

                actual_addr_q.push_back(wr_addr);
                actual_data_q.push_back(wr_data);
                actual_last_q.push_back(wr_last);

                total_wr_handshakes <= total_wr_handshakes + 1;
            end
        end
    end

    // ------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------
    task automatic run_exact_length_success_test();
        logic [ADDR_WIDTH-1:0] base_addr;
    begin
        $display("[LOADER_TB] --------------------------------------------------");
        $display("[LOADER_TB] TEST 1: exact-length success");
        $display("[LOADER_TB] --------------------------------------------------");

        apply_reset();

        base_addr = 32'h0000_0100;
        build_expected_write_sequence(base_addr, 4, 16'h0010, 3);

        launch_loader(base_addr, 4);
        drive_axis_sequence(4, 16'h0010, 3);
        wait_done_or_timeout(200, "exact_length_success");
        check_busy_clears("exact_length_success");

        if (error !== 1'b0) begin
            $fatal(1, "[LOADER_TB][exact_length_success] error asserted unexpectedly");
        end

        if (accepted_beats != 32'd4) begin
            $fatal(1, "[LOADER_TB][exact_length_success] accepted_beats mismatch: got=%0d exp=4",
                accepted_beats);
        end

        if (written_beats != 32'd4) begin
            $fatal(1, "[LOADER_TB][exact_length_success] written_beats mismatch: got=%0d exp=4",
                written_beats);
        end

        if (tlast_seen !== 1'b1) begin
            $fatal(1, "[LOADER_TB][exact_length_success] tlast_seen expected 1");
        end

        compare_write_sequence("exact_length_success");
        compare_readback_against_expected(4, "exact_length_success");

        $display("[LOADER_TB] PASS: exact-length success");
    end
    endtask

    task automatic run_capture_until_tlast_test();
        logic [ADDR_WIDTH-1:0] base_addr;
    begin
        $display("[LOADER_TB] --------------------------------------------------");
        $display("[LOADER_TB] TEST 2: capture-until-tlast mode");
        $display("[LOADER_TB] --------------------------------------------------");

        apply_reset();

        base_addr = 32'h0000_0200;
        build_expected_write_sequence(base_addr, 3, 16'h0100, 2);

        launch_loader(base_addr, 0);
        drive_axis_sequence(3, 16'h0100, 2);
        wait_done_or_timeout(200, "capture_until_tlast");
        check_busy_clears("capture_until_tlast");

        if (error !== 1'b0) begin
            $fatal(1, "[LOADER_TB][capture_until_tlast] error asserted unexpectedly");
        end

        if (accepted_beats != 32'd3) begin
            $fatal(1, "[LOADER_TB][capture_until_tlast] accepted_beats mismatch: got=%0d exp=3",
                accepted_beats);
        end

        if (written_beats != 32'd3) begin
            $fatal(1, "[LOADER_TB][capture_until_tlast] written_beats mismatch: got=%0d exp=3",
                written_beats);
        end

        if (tlast_seen !== 1'b1) begin
            $fatal(1, "[LOADER_TB][capture_until_tlast] tlast_seen expected 1");
        end

        compare_write_sequence("capture_until_tlast");
        compare_readback_against_expected(3, "capture_until_tlast");

        $display("[LOADER_TB] PASS: capture-until-tlast mode");
    end
    endtask

    task automatic run_write_backpressure_test();
        logic [ADDR_WIDTH-1:0] base_addr;
    begin
        $display("[LOADER_TB] --------------------------------------------------");
        $display("[LOADER_TB] TEST 3: write-side backpressure");
        $display("[LOADER_TB] --------------------------------------------------");

        apply_reset();

        base_addr = 32'h0000_0300;
        build_expected_write_sequence(base_addr, 4, 16'h0200, 3);

        fork
            begin
                wr_ready = 1'b1;
                wait (busy === 1'b1);

                repeat (2) @(posedge clk);
                wr_ready = 1'b0;
                repeat (3) @(posedge clk);
                wr_ready = 1'b1;

                repeat (1) @(posedge clk);
                wr_ready = 1'b0;
                repeat (2) @(posedge clk);
                wr_ready = 1'b1;
            end
        join_none

        launch_loader(base_addr, 4);
        drive_axis_sequence(4, 16'h0200, 3);
        wait_done_or_timeout(300, "write_backpressure");
        check_busy_clears("write_backpressure");

        if (error !== 1'b0) begin
            $fatal(1, "[LOADER_TB][write_backpressure] error asserted unexpectedly");
        end

        if (accepted_beats != 32'd4) begin
            $fatal(1, "[LOADER_TB][write_backpressure] accepted_beats mismatch: got=%0d exp=4",
                accepted_beats);
        end

        if (written_beats != 32'd4) begin
            $fatal(1, "[LOADER_TB][write_backpressure] written_beats mismatch: got=%0d exp=4",
                written_beats);
        end

        compare_write_sequence("write_backpressure");
        compare_readback_against_expected(4, "write_backpressure");

        $display("[LOADER_TB] PASS: write-side backpressure");
    end
    endtask

    task automatic run_invalid_unaligned_addr_test();
        logic [ADDR_WIDTH-1:0] bad_addr;
    begin
        $display("[LOADER_TB] --------------------------------------------------");
        $display("[LOADER_TB] TEST 4: invalid unaligned destination");
        $display("[LOADER_TB] --------------------------------------------------");

        apply_reset();

        bad_addr = 32'h0000_0104; // unaligned for DATA_WIDTH=64

        launch_loader(bad_addr, 2);
        wait_done_or_timeout(20, "invalid_unaligned_addr");
        check_busy_clears("invalid_unaligned_addr");

        if (error !== 1'b1) begin
            $fatal(1, "[LOADER_TB][invalid_unaligned_addr] expected error=1");
        end

        if (accepted_beats != 32'd0) begin
            $fatal(1, "[LOADER_TB][invalid_unaligned_addr] accepted_beats expected 0, got=%0d",
                accepted_beats);
        end

        if (written_beats != 32'd0) begin
            $fatal(1, "[LOADER_TB][invalid_unaligned_addr] written_beats expected 0, got=%0d",
                written_beats);
        end

        expect_no_writes("invalid_unaligned_addr");

        $display("[LOADER_TB] PASS: invalid unaligned destination");
    end
    endtask

    task automatic run_shorter_than_expected_mismatch_test();
        logic [ADDR_WIDTH-1:0] base_addr;
    begin
        $display("[LOADER_TB] --------------------------------------------------");
        $display("[LOADER_TB] TEST 5: shorter-than-expected mismatch");
        $display("[LOADER_TB] --------------------------------------------------");

        apply_reset();

        base_addr = 32'h0000_0400;
        build_expected_write_sequence(base_addr, 4, 16'h0300, 3);

        // expected_beats = 5, but TLAST comes on beat 4
        launch_loader(base_addr, 5);
        drive_axis_sequence(4, 16'h0300, 3);
        wait_done_or_timeout(200, "shorter_than_expected");
        check_busy_clears("shorter_than_expected");

        if (error !== 1'b1) begin
            $fatal(1, "[LOADER_TB][shorter_than_expected] expected error=1");
        end

        if (accepted_beats != 32'd4) begin
            $fatal(1, "[LOADER_TB][shorter_than_expected] accepted_beats mismatch: got=%0d exp=4",
                accepted_beats);
        end

        if (written_beats != 32'd4) begin
            $fatal(1, "[LOADER_TB][shorter_than_expected] written_beats mismatch: got=%0d exp=4",
                written_beats);
        end

        if (tlast_seen !== 1'b1) begin
            $fatal(1, "[LOADER_TB][shorter_than_expected] tlast_seen expected 1");
        end

        compare_write_sequence("shorter_than_expected");
        compare_readback_against_expected(4, "shorter_than_expected");

        $display("[LOADER_TB] PASS: shorter-than-expected mismatch");
    end
    endtask

    task automatic run_missing_tlast_at_expected_end_test();
        logic [ADDR_WIDTH-1:0] base_addr;
    begin
        $display("[LOADER_TB] --------------------------------------------------");
        $display("[LOADER_TB] TEST 6: missing TLAST at expected end");
        $display("[LOADER_TB] --------------------------------------------------");

        apply_reset();

        base_addr = 32'h0000_0500;
        build_expected_write_sequence(base_addr, 4, 16'h0400, -1);

        // expected_beats = 4, but beat 4 arrives without TLAST
        launch_loader(base_addr, 4);
        drive_axis_sequence(4, 16'h0400, -1);
        wait_done_or_timeout(200, "missing_tlast_at_expected_end");
        check_busy_clears("missing_tlast_at_expected_end");

        if (error !== 1'b1) begin
            $fatal(1, "[LOADER_TB][missing_tlast_at_expected_end] expected error=1");
        end

        if (accepted_beats != 32'd4) begin
            $fatal(1, "[LOADER_TB][missing_tlast_at_expected_end] accepted_beats mismatch: got=%0d exp=4",
                accepted_beats);
        end

        if (written_beats != 32'd4) begin
            $fatal(1, "[LOADER_TB][missing_tlast_at_expected_end] written_beats mismatch: got=%0d exp=4",
                written_beats);
        end

        if (tlast_seen !== 1'b0) begin
            $fatal(1, "[LOADER_TB][missing_tlast_at_expected_end] tlast_seen expected 0");
        end

        compare_write_sequence("missing_tlast_at_expected_end");
        compare_readback_against_expected(4, "missing_tlast_at_expected_end");

        $display("[LOADER_TB] PASS: missing TLAST at expected end");
    end
    endtask

    // ------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------
    initial begin
        init_tb_outputs();
        clear_expected_and_actual();

        run_exact_length_success_test();
        run_capture_until_tlast_test();
        run_write_backpressure_test();
        run_invalid_unaligned_addr_test();
        run_shorter_than_expected_mismatch_test();
        run_missing_tlast_at_expected_end_test();

        $display("");
        $display("[LOADER_TB] ================================================");
        $display("[LOADER_TB] All axi_stream_loader smoke tests PASSED");
        $display("[LOADER_TB] ================================================");
        $display("");

        #20;
        $finish;
    end

endmodule

`endif