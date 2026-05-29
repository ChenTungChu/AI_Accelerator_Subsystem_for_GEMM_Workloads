// File: tb/uvm/test/ai_accel_subsys_dma_store_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_DMA_STORE_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_DMA_STORE_SMOKE_TEST_SV

class ai_accel_subsys_dma_store_smoke_test extends uvm_test;

    `uvm_component_utils(ai_accel_subsys_dma_store_smoke_test)

    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 64;
    localparam int ID_WIDTH   = 4;
    localparam int DIM_WIDTH  = 8;

    localparam int DMA_SRC_MEM_BYTES = 4096;
    localparam int DMA_DST_MEM_BYTES = 4096;
    localparam int BYTES_PER_BEAT    = DATA_WIDTH / 8;

    // Default preserves the historical DMA-store smoke timeout.
    // Long-running P11D/P11E focused runs may override this with
    // +SMOKE_DONE_TIMEOUT_CYCLES=<cycles> or
    // +DMA_STORE_DONE_TIMEOUT_CYCLES=<cycles>.
    localparam int unsigned DEFAULT_GEMM_DONE_TIMEOUT_CYCLES = 30000;

    localparam logic [1:0] AXI_RESP_OKAY  = 2'b00;
    localparam logic [1:0] AXI_BURST_INCR = 2'b01;

    typedef virtual ai_accel_subsys_ctrl_if #(
        .ADDR_WIDTH        (ADDR_WIDTH),
        .DIM_WIDTH         (DIM_WIDTH),
        .DMA_SRC_MEM_BYTES (DMA_SRC_MEM_BYTES),
        .DMA_DST_MEM_BYTES (DMA_DST_MEM_BYTES)
    ) ctrl_vif_t;

    typedef virtual axi_mm_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .HAS_BURST  (1)
    ) axi0_vif_t;

    ai_accel_subsys_env env;

    ctrl_vif_t vif;
    axi0_vif_t axi0_vif;

    int unsigned case_id;
    int unsigned run_all;

    bit enable_result_check;

    int unsigned gemm_done_timeout_cycles;

    logic [ADDR_WIDTH-1:0] base_a;
    logic [ADDR_WIDTH-1:0] base_b;
    logic [ADDR_WIDTH-1:0] base_c;

    logic [ADDR_WIDTH-1:0] dma_src_a;
    logic [ADDR_WIDTH-1:0] dma_src_b;
    logic [ADDR_WIDTH-1:0] dma_store_dst_base;

    int unsigned dim_m_i;
    int unsigned dim_n_i;
    int unsigned dim_k_i;

    int unsigned a_bytes;
    int unsigned b_bytes;
    int unsigned c_words;
    int unsigned c_bytes;

    logic [7:0]  a_payload  [0:63];
    logic [7:0]  b_payload  [0:255];
    logic [31:0] expected_c [0:63];

    function new(string name = "ai_accel_subsys_dma_store_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function automatic ai_accel_subsys_seq_item::test_kind_e infer_test_kind(
        input int unsigned cid
    );
        if (cid <= 99) begin
            return ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE;
        end
        else if ((cid >= 100) && (cid <= 202)) begin
            return ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE;
        end
        else if ((cid >= 400) && (cid <= 499)) begin
            return ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE;
        end
        else begin
            `uvm_fatal("DMA_STORE_SMOKE/BADCASE",
                $sformatf("Unsupported CASE_ID=%0d", cid))
            return ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE;
        end
    endfunction

    function automatic string build_test_name(
        input int unsigned cid,
        input ai_accel_subsys_seq_item::test_kind_e kind
    );
        case (kind)
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE:
                return $sformatf("dma_store_fixed_baseline_case_%0d", cid);

            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE:
                return $sformatf("dma_store_variable_dim_case_%0d", cid);

            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE:
                return $sformatf("dma_store_config_base_case_%0d", cid);

            default:
                return $sformatf("dma_store_case_%0d_kind_%0d", cid, kind);
        endcase
    endfunction

    function void parse_result_check_enable();
        int unsigned tmp;
    begin
        enable_result_check = 1'b0;

        if ($value$plusargs("ENABLE_RESULT_CHECK=%d", tmp)) begin
            enable_result_check = (tmp != 0);
        end

        `uvm_info("DMA_STORE_SMOKE",
            $sformatf("enable_result_check=%0d", enable_result_check),
            UVM_MEDIUM)
    end
    endfunction

    // ------------------------------------------------------------
    // Parse GEMM done timeout
    //
    // Default:
    //   DEFAULT_GEMM_DONE_TIMEOUT_CYCLES
    //
    // Overrides:
    //   +DMA_STORE_DONE_TIMEOUT_CYCLES=<cycles>
    //       dedicated DMA-store/frontend timeout knob
    //
    //   +SMOKE_DONE_TIMEOUT_CYCLES=<cycles>
    //       shared focused-run timeout knob used by P11D/P11E
    //
    // Priority:
    //   DMA_STORE_DONE_TIMEOUT_CYCLES overrides SMOKE_DONE_TIMEOUT_CYCLES.
    // ------------------------------------------------------------
    function void parse_gemm_done_timeout_cycles();
        int unsigned tmp;
        string       source;
    begin
        gemm_done_timeout_cycles = DEFAULT_GEMM_DONE_TIMEOUT_CYCLES;
        source                   = "default";

        if ($value$plusargs("SMOKE_DONE_TIMEOUT_CYCLES=%d", tmp)) begin
            if (tmp == 0) begin
                `uvm_warning("DMA_STORE_SMOKE/BAD_SMOKE_TIMEOUT",
                    "SMOKE_DONE_TIMEOUT_CYCLES=0 is invalid; using default GEMM done timeout")
            end
            else begin
                gemm_done_timeout_cycles = tmp;
                source                   = "SMOKE_DONE_TIMEOUT_CYCLES";
            end
        end

        if ($value$plusargs("DMA_STORE_DONE_TIMEOUT_CYCLES=%d", tmp)) begin
            if (tmp == 0) begin
                `uvm_warning("DMA_STORE_SMOKE/BAD_DMA_TIMEOUT",
                    "DMA_STORE_DONE_TIMEOUT_CYCLES=0 is invalid; keeping previously selected GEMM done timeout")
            end
            else begin
                gemm_done_timeout_cycles = tmp;
                source                   = "DMA_STORE_DONE_TIMEOUT_CYCLES";
            end
        end

        `uvm_info("DMA_STORE_SMOKE",
            $sformatf("gemm_done_timeout_cycles=%0d source=%s",
                gemm_done_timeout_cycles, source),
            UVM_MEDIUM)
    end
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(ctrl_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("DMA_STORE_SMOKE", "Failed to get ctrl vif from config_db")
        end

        if (!uvm_config_db#(axi0_vif_t)::get(this, "", "axi0_vif", axi0_vif)) begin
            `uvm_fatal("DMA_STORE_SMOKE", "Failed to get axi0_vif from config_db")
        end

        if (!$value$plusargs("CASE_ID=%0d", case_id)) begin
            case_id = 100;
        end

        if (!$value$plusargs("RUN_ALL=%0d", run_all)) begin
            run_all = 0;
        end

        parse_result_check_enable();
        parse_gemm_done_timeout_cycles();

        uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::set(
            this, "env", "vif", vif);

        uvm_config_db#(axi0_vif_t)::set(
            this, "env", "axi0_vif", axi0_vif);

        uvm_config_db#(uvm_active_passive_enum)::set(
            this, "env", "host_is_active", UVM_PASSIVE);

        uvm_config_db#(bit)::set(
            this, "env", "host_traffic_check_enable", 1'b0);

        uvm_config_db#(bit)::set(
            this, "env", "host_traffic_strict_check_enable", 1'b0);

        uvm_config_db#(bit)::set(
            this, "env.scoreboard", "result_check_enable", enable_result_check);

        env = ai_accel_subsys_env::type_id::create("env", this);
    endfunction

    function automatic int unsigned ceil_div(
        input int unsigned value,
        input int unsigned divisor
    );
        if (value == 0) begin
            return 0;
        end

        return (value + divisor - 1) / divisor;
    endfunction

    function automatic logic [DATA_WIDTH/8-1:0] full_strb();
        return {DATA_WIDTH/8{1'b1}};
    endfunction

    function automatic bit addr_is_beat_aligned(
        input logic [ADDR_WIDTH-1:0] addr
    );
        return (addr % BYTES_PER_BEAT) == 0;
    endfunction

    task automatic clear_payload_arrays();
        int unsigned i;
    begin
        for (i = 0; i < 64; i++) begin
            a_payload[i]  = 8'h00;
            expected_c[i] = 32'h0000_0000;
        end

        for (i = 0; i < 256; i++) begin
            b_payload[i]  = 8'h00;
        end
    end
    endtask

    task automatic build_expected_result_vector(
        output int signed expected_dyn[]
    );
        int unsigned i;
    begin
        expected_dyn = new[c_words];

        for (i = 0; i < c_words; i++) begin
            expected_dyn[i] = $signed(expected_c[i]);
        end
    end
    endtask

    task automatic configure_case(input int unsigned cid);
        int unsigned i;
    begin
        clear_payload_arrays();

        dma_src_a = 32'h0000_0000;
        dma_src_b = 32'h0000_0100;

        base_a = 32'h0000_0000;
        base_b = 32'h0000_0100;
        base_c = 32'h0000_0200;

        dma_store_dst_base = 32'h0000_0000;

        case (cid)
            100: begin
                dim_m_i = 1;
                dim_n_i = 1;
                dim_k_i = 1;

                a_bytes = 1;
                b_bytes = 1;
                c_words = 1;

                a_payload[0] = 8'd3;
                b_payload[0] = 8'd5;
            end

            101: begin
                dim_m_i = 2;
                dim_n_i = 2;
                dim_k_i = 2;

                a_bytes = 4;
                b_bytes = 4;
                c_words = 4;

                a_payload[0] = 8'd1;
                a_payload[1] = 8'd2;
                a_payload[2] = 8'd3;
                a_payload[3] = 8'd4;

                b_payload[0] = 8'd5;
                b_payload[1] = 8'd6;
                b_payload[2] = 8'd7;
                b_payload[3] = 8'd8;
            end

            105: begin
                dim_m_i = 2;
                dim_n_i = 3;
                dim_k_i = 4;

                a_bytes = 8;
                b_bytes = 12;
                c_words = 6;

                for (i = 0; i < a_bytes; i++) begin
                    a_payload[i] = i + 1;
                end

                for (i = 0; i < b_bytes; i++) begin
                    b_payload[i] = i + 1;
                end
            end

            190: begin
                // P9G large-dimension path case: M=1, N=8, K=8.
                // This fills an 8x8 B tile while keeping C output small.
                dim_m_i = 1;
                dim_n_i = 8;
                dim_k_i = 8;

                a_bytes = 8;
                b_bytes = 64;
                c_words = 8;

                for (i = 0; i < a_bytes; i++) begin
                    a_payload[i] = (i % 8) + 1;
                end

                for (i = 0; i < b_bytes; i++) begin
                    b_payload[i] = ((i * 3) % 13) + 1;
                end
            end

            191: begin
                // P9G large-dimension path case: M=2, N=8, K=8.
                // This validates two A rows and B-cache reuse at N/K=8.
                dim_m_i = 2;
                dim_n_i = 8;
                dim_k_i = 8;

                a_bytes = 16;
                b_bytes = 64;
                c_words = 16;

                for (i = 0; i < a_bytes; i++) begin
                    a_payload[i] = ((i * 5) % 11) + 1;
                end

                for (i = 0; i < b_bytes; i++) begin
                    b_payload[i] = ((i * 3) % 13) + 1;
                end
            end

            192: begin
                // P9G large/tail-dimension path case: M=3, N=5, K=7.
                // N and K are intentionally not multiples of four.
                dim_m_i = 3;
                dim_n_i = 5;
                dim_k_i = 7;

                a_bytes = 21;
                b_bytes = 35;
                c_words = 15;

                for (i = 0; i < a_bytes; i++) begin
                    a_payload[i] = ((i * 2) % 9) + 1;
                end

                for (i = 0; i < b_bytes; i++) begin
                    b_payload[i] = ((i * 3) % 7) + 1;
                end
            end

            193: begin
                // P10C/P10D K-tiling representative case: M=1, N=4, K=16.
                // Two full K=8 tiles, small C output.
                dim_m_i = 1;
                dim_n_i = 4;
                dim_k_i = 16;

                a_bytes = 16;
                b_bytes = 64;
                c_words = 4;

                for (i = 0; i < a_bytes; i++) begin
                    a_payload[i] = ((i * 5) % 11) + 1;
                end

                for (i = 0; i < b_bytes; i++) begin
                    b_payload[i] = ((i * 3) % 13) + 1;
                end
            end

            194: begin
                // P10C/P10D K-tiling representative case: M=2, N=4, K=16.
                // Two A rows and two full K=8 tiles.
                dim_m_i = 2;
                dim_n_i = 4;
                dim_k_i = 16;

                a_bytes = 32;
                b_bytes = 64;
                c_words = 8;

                for (i = 0; i < a_bytes; i++) begin
                    a_payload[i] = ((i * 5) % 11) + 1;
                end

                for (i = 0; i < b_bytes; i++) begin
                    b_payload[i] = ((i * 3) % 13) + 1;
                end
            end

            195: begin
                // P10E frontend compatibility representative case: M=4, N=4, K=16.
                // Exactly two full K=8 tiles; A/B payloads are both 64 bytes.
                dim_m_i = 4;
                dim_n_i = 4;
                dim_k_i = 16;

                a_bytes = 64;
                b_bytes = 64;
                c_words = 16;

                for (i = 0; i < a_bytes; i++) begin
                    a_payload[i] = ((i * 5) % 11) + 1;
                end

                for (i = 0; i < b_bytes; i++) begin
                    b_payload[i] = ((i * 3) % 13) + 1;
                end
            end

            196: begin
                // P10C/P10D K-tiling tail case: M=3, N=5, K=9.
                // Exercises a full K=8 tile plus a K=1 tail tile.
                dim_m_i = 3;
                dim_n_i = 5;
                dim_k_i = 9;

                a_bytes = 27;
                b_bytes = 45;
                c_words = 15;

                for (i = 0; i < a_bytes; i++) begin
                    a_payload[i] = ((i * 2) % 9) + 1;
                end

                for (i = 0; i < b_bytes; i++) begin
                    b_payload[i] = ((i * 3) % 7) + 1;
                end
            end

            197: begin
                // P10C/P10D K-tiling tail case: M=4, N=4, K=12.
                // Exercises a full K=8 tile plus a K=4 tail tile.
                dim_m_i = 4;
                dim_n_i = 4;
                dim_k_i = 12;

                a_bytes = 48;
                b_bytes = 48;
                c_words = 16;

                for (i = 0; i < a_bytes; i++) begin
                    a_payload[i] = ((i * 5) % 11) + 1;
                end

                for (i = 0; i < b_bytes; i++) begin
                    b_payload[i] = ((i * 3) % 13) + 1;
                end
            end

            198: begin
                // P11C N-tiling first software-reference case: M=1, N=16, K=8.
                // N exceeds B-cache max-N=8; K still fits one K tile.
                dim_m_i = 1;
                dim_n_i = 16;
                dim_k_i = 8;

                a_bytes = 8;
                b_bytes = 128;
                c_words = 16;

                for (i = 0; i < a_bytes; i++) begin
                    a_payload[i] = (((i + 1) * 2) % 11) + 1;
                end

                for (i = 0; i < b_bytes; i++) begin
                    b_payload[i] = (((i + 3) * 5) % 17) + 1;
                end
            end

            199: begin
                // P11C N-tiling multi-row case: M=2, N=16, K=8.
                // N exceeds B-cache max-N=8; two A rows reuse the B payload.
                dim_m_i = 2;
                dim_n_i = 16;
                dim_k_i = 8;

                a_bytes = 16;
                b_bytes = 128;
                c_words = 32;

                for (i = 0; i < a_bytes; i++) begin
                    a_payload[i] = (((i + 2) * 3) % 13) + 1;
                end

                for (i = 0; i < b_bytes; i++) begin
                    b_payload[i] = (((i + 5) * 7) % 19) + 1;
                end
            end

            200: begin
                // P11C representative N+K tiling case: M=4, N=16, K=16.
                // N and K both exceed one cache8 tile; C has 64 output words.
                dim_m_i = 4;
                dim_n_i = 16;
                dim_k_i = 16;

                a_bytes = 64;
                b_bytes = 256;
                c_words = 64;

                for (i = 0; i < a_bytes; i++) begin
                    a_payload[i] = (((i + 1) * 5) % 17) + 1;
                end

                for (i = 0; i < b_bytes; i++) begin
                    b_payload[i] = (((i + 2) * 3) % 23) + 1;
                end
            end

            201: begin
                // P11C irregular N/K tail case: M=3, N=9, K=9.
                // N tile split is 8+1 and K tile split is 8+1.
                dim_m_i = 3;
                dim_n_i = 9;
                dim_k_i = 9;

                a_bytes = 27;
                b_bytes = 81;
                c_words = 27;

                for (i = 0; i < a_bytes; i++) begin
                    a_payload[i] = (((i + 3) * 2) % 11) + 1;
                end

                for (i = 0; i < b_bytes; i++) begin
                    b_payload[i] = (((i + 4) * 5) % 13) + 1;
                end
            end

            202: begin
                // P11C N-tail + K-tiling case: M=4, N=12, K=16.
                // N tile split is 8+4 and K tile split is 8+8.
                dim_m_i = 4;
                dim_n_i = 12;
                dim_k_i = 16;

                a_bytes = 64;
                b_bytes = 192;
                c_words = 48;

                for (i = 0; i < a_bytes; i++) begin
                    a_payload[i] = (((i + 4) * 3) % 19) + 1;
                end

                for (i = 0; i < b_bytes; i++) begin
                    b_payload[i] = (((i + 6) * 5) % 17) + 1;
                end
            end

            5, 400, 401, 402, 403: begin
                dim_m_i = 4;
                dim_n_i = 4;
                dim_k_i = 4;

                a_bytes = 16;
                b_bytes = 16;
                c_words = 16;

                case (cid)
                    5, 400: begin
                        base_a = 32'h0000_0000;
                        base_b = 32'h0000_0100;
                        base_c = 32'h0000_0200;
                    end

                    401: begin
                        base_a = 32'h0000_0040;
                        base_b = 32'h0000_0140;
                        base_c = 32'h0000_0240;
                    end

                    402: begin
                        base_a = 32'h0000_0080;
                        base_b = 32'h0000_0180;
                        base_c = 32'h0000_0280;
                    end

                    403: begin
                        base_a = 32'h0000_0020;
                        base_b = 32'h0000_0060;
                        base_c = 32'h0000_00a0;
                    end

                    default: begin
                    end
                endcase

                for (i = 0; i < a_bytes; i++) begin
                    a_payload[i] = (i % 8) + 1;
                end

                for (i = 0; i < b_bytes; i++) begin
                    b_payload[i] = ((i * 3) % 11) + 1;
                end
            end

            default: begin
                `uvm_fatal("DMA_STORE_SMOKE",
                    $sformatf("Unsupported CASE_ID=%0d. Supported: 5, 100, 101, 105, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 400, 401, 402, 403", cid))
            end
        endcase

        c_bytes = c_words * 4;

        if (!addr_is_beat_aligned(base_c)) begin
            `uvm_fatal("DMA_STORE_SMOKE",
                $sformatf("base_c must be DATA_WIDTH-byte aligned for v1 S2MM. base_c=0x%08h",
                    base_c))
        end

        if (!addr_is_beat_aligned(dma_store_dst_base)) begin
            `uvm_fatal("DMA_STORE_SMOKE",
                $sformatf("dma_store_dst_base must be DATA_WIDTH-byte aligned for v1 S2MM. dst=0x%08h",
                    dma_store_dst_base))
        end

        compute_expected_c();

        `uvm_info("DMA_STORE_SMOKE",
            $sformatf("Configured CASE_ID=%0d dim=(%0d,%0d,%0d) A=0x%08h B=0x%08h C=0x%08h S2MM_DST=0x%08h A_bytes=%0d B_bytes=%0d C_words=%0d C_bytes=%0d",
                cid,
                dim_m_i, dim_n_i, dim_k_i,
                base_a, base_b, base_c, dma_store_dst_base,
                a_bytes, b_bytes, c_words, c_bytes),
            UVM_MEDIUM)
    end
    endtask

    task automatic compute_expected_c();
        int unsigned r;
        int unsigned c;
        int unsigned kk;
        int signed sum;
        int signed aa;
        int signed bb;
        int unsigned a_idx;
        int unsigned b_idx;
        int unsigned c_idx;
    begin
        for (r = 0; r < dim_m_i; r++) begin
            for (c = 0; c < dim_n_i; c++) begin
                sum = 0;

                for (kk = 0; kk < dim_k_i; kk++) begin
                    a_idx = r * dim_k_i + kk;
                    b_idx = kk * dim_n_i + c;

                    aa = $signed(a_payload[a_idx]);
                    bb = $signed(b_payload[b_idx]);

                    sum += aa * bb;
                end

                c_idx = r * dim_n_i + c;
                expected_c[c_idx] = sum;
            end
        end
    end
    endtask

    task automatic publish_result_to_scoreboard(
        input int unsigned cid,
        input int signed   expected_dyn[],
        input int signed   actual_dyn[]
    );
        ai_accel_subsys_seq_item::test_kind_e kind;
        string test_name;
    begin
        if (!enable_result_check) begin
            return;
        end

        if (env == null) begin
            `uvm_fatal("DMA_STORE_SMOKE/NOENV",
                "env is null in publish_result_to_scoreboard()")
        end

        if (env.result_bridge == null) begin
            `uvm_fatal("DMA_STORE_SMOKE/NOBRIDGE",
                "env.result_bridge is null in publish_result_to_scoreboard()")
        end

        kind      = infer_test_kind(cid);
        test_name = build_test_name(cid, kind);

        `uvm_info("DMA_STORE_SMOKE",
            $sformatf("Publishing DMA-store result payload: case_id=%0d test_kind=%0d C_words=%0d",
                cid, kind, expected_dyn.size()),
            UVM_MEDIUM)

        env.result_bridge.publish_case_result(
            cid,
            kind,
            test_name,

            base_a,
            base_b,
            base_c,

            dim_m_i[DIM_WIDTH-1:0],
            dim_n_i[DIM_WIDTH-1:0],
            dim_k_i[DIM_WIDTH-1:0],

            expected_dyn,
            actual_dyn
        );
    end
    endtask

    task automatic set_monitor_case_context(input int unsigned cid);
        ai_accel_subsys_seq_item::test_kind_e kind;
    begin
        kind = infer_test_kind(cid);

        if (env != null &&
            env.agent != null &&
            env.agent.monitor != null) begin

            env.agent.monitor.set_case_context(cid, kind);
        end
    end
    endtask

    task automatic clear_monitor_case_context();
    begin
        if (env != null &&
            env.agent != null &&
            env.agent.monitor != null) begin

            env.agent.monitor.clear_case_context();
        end
    end
    endtask

    task automatic wait_for_reset_release();
        `uvm_info("DMA_STORE_SMOKE", "Waiting for reset release", UVM_MEDIUM)

        do begin
            @(vif.cb_drv);
        end while ((vif.cb_drv.dma_rst_n !== 1'b1) ||
                   (vif.cb_drv.core_rst_n !== 1'b1));

        repeat (5) @(vif.cb_drv);

        `uvm_info("DMA_STORE_SMOKE", "Reset released", UVM_MEDIUM)
    endtask

    task automatic init_ctrl_outputs();
        @(vif.cb_drv);

        vif.cb_drv.acc_start <= 1'b0;

        vif.cb_drv.base_addr_a <= '0;
        vif.cb_drv.base_addr_b <= '0;
        vif.cb_drv.base_addr_c <= '0;

        vif.cb_drv.dim_m <= '0;
        vif.cb_drv.dim_n <= '0;
        vif.cb_drv.dim_k <= '0;

        vif.cb_drv.dma_load_start    <= 1'b0;
        vif.cb_drv.dma_src_base_addr <= '0;
        vif.cb_drv.dma_dst_base_addr <= '0;
        vif.cb_drv.dma_load_beats    <= '0;

        vif.cb_drv.dma_store_start         <= 1'b0;
        vif.cb_drv.dma_store_src_base_addr <= '0;
        vif.cb_drv.dma_store_dst_base_addr <= '0;
        vif.cb_drv.dma_store_byte_count    <= '0;

        vif.cb_drv.tb_reset_override_en   <= 1'b0;
        vif.cb_drv.tb_dma_rst_n_override  <= 1'b1;
        vif.cb_drv.tb_core_rst_n_override <= 1'b1;

        vif.dma_src_set_rresp_error(1'b0, -1);
        vif.dma_dst_set_bresp_error(1'b0, -1);
    endtask

    task automatic init_axi0_outputs();
        @(posedge axi0_vif.clk);

        axi0_vif.awid    <= '0;
        axi0_vif.awaddr  <= '0;
        axi0_vif.awlen   <= '0;
        axi0_vif.awsize  <= '0;
        axi0_vif.awburst <= '0;
        axi0_vif.awvalid <= 1'b0;

        axi0_vif.wdata   <= '0;
        axi0_vif.wstrb   <= '0;
        axi0_vif.wlast   <= 1'b0;
        axi0_vif.wvalid  <= 1'b0;

        axi0_vif.bready  <= 1'b0;

        axi0_vif.arid    <= '0;
        axi0_vif.araddr  <= '0;
        axi0_vif.arlen   <= '0;
        axi0_vif.arsize  <= '0;
        axi0_vif.arburst <= '0;
        axi0_vif.arvalid <= 1'b0;

        axi0_vif.rready  <= 1'b0;
    endtask

    task automatic axi0_write64(
        input logic [ADDR_WIDTH-1:0]   addr,
        input logic [DATA_WIDTH-1:0]   data,
        input logic [DATA_WIDTH/8-1:0] strb
    );
        bit aw_done;
        bit w_done;
        int unsigned timeout;

        aw_done = 0;
        w_done  = 0;
        timeout = 0;

        @(posedge axi0_vif.clk);

        axi0_vif.awid    <= '0;
        axi0_vif.awaddr  <= addr;
        axi0_vif.awlen   <= 8'd0;
        axi0_vif.awsize  <= 3'd3;
        axi0_vif.awburst <= AXI_BURST_INCR;
        axi0_vif.awvalid <= 1'b1;

        axi0_vif.wdata   <= data;
        axi0_vif.wstrb   <= strb;
        axi0_vif.wlast   <= 1'b1;
        axi0_vif.wvalid  <= 1'b1;

        axi0_vif.bready  <= 1'b1;

        while (!(aw_done && w_done)) begin
            @(posedge axi0_vif.clk);

            if (!aw_done && axi0_vif.awvalid && axi0_vif.awready) begin
                aw_done = 1;
                axi0_vif.awvalid <= 1'b0;
            end

            if (!w_done && axi0_vif.wvalid && axi0_vif.wready) begin
                w_done = 1;
                axi0_vif.wvalid <= 1'b0;
            end

            timeout++;
            if (timeout > 2000) begin
                `uvm_fatal("DMA_STORE_SMOKE",
                    $sformatf("AXI0 write timeout waiting AW/W handshake addr=0x%08h", addr))
            end
        end

        timeout = 0;
        while (!(axi0_vif.bvalid && axi0_vif.bready)) begin
            @(posedge axi0_vif.clk);
            timeout++;

            if (timeout > 2000) begin
                `uvm_fatal("DMA_STORE_SMOKE",
                    $sformatf("AXI0 write timeout waiting B response addr=0x%08h", addr))
            end
        end

        if (axi0_vif.bresp !== AXI_RESP_OKAY) begin
            `uvm_fatal("DMA_STORE_SMOKE",
                $sformatf("AXI0 write BRESP error addr=0x%08h bresp=0x%0h",
                    addr, axi0_vif.bresp))
        end

        @(posedge axi0_vif.clk);
        axi0_vif.bready  <= 1'b0;
        axi0_vif.wlast   <= 1'b0;
        axi0_vif.wstrb   <= '0;
        axi0_vif.wdata   <= '0;
        axi0_vif.awaddr  <= '0;
    endtask

    task automatic clear_c_region();
        int unsigned total_c_bytes;
        int unsigned beat_count;
        int unsigned i;
        logic [ADDR_WIDTH-1:0] addr;
    begin
        total_c_bytes = c_words * 4;
        beat_count    = ceil_div(total_c_bytes, BYTES_PER_BEAT);

        `uvm_info("DMA_STORE_SMOKE",
            $sformatf("Clearing C via AXI0: base_c=0x%08h words=%0d beats=%0d",
                base_c, c_words, beat_count),
            UVM_MEDIUM)

        for (i = 0; i < beat_count; i++) begin
            addr = base_c + ADDR_WIDTH'(i * BYTES_PER_BEAT);
            axi0_write64(addr, 64'h0000_0000_0000_0000, full_strb());
        end
    end
    endtask

    task automatic clear_dma_destination_memory();
    begin
        `uvm_info("DMA_STORE_SMOKE",
            "Clearing DMA destination memory",
            UVM_MEDIUM)

        vif.dma_dst_mem_clear();
        vif.dma_dst_set_bresp_error(1'b0, -1);
    end
    endtask

    task automatic preload_dma_source_memory();
        int unsigned i;
    begin
        `uvm_info("DMA_STORE_SMOKE",
            $sformatf("Preloading DMA source memory: A src=0x%08h bytes=%0d, B src=0x%08h bytes=%0d",
                dma_src_a, a_bytes, dma_src_b, b_bytes),
            UVM_MEDIUM)

        vif.dma_src_mem_clear();

        for (i = 0; i < a_bytes; i++) begin
            vif.dma_src_mem_write_byte(dma_src_a + ADDR_WIDTH'(i), a_payload[i]);
        end

        for (i = 0; i < b_bytes; i++) begin
            vif.dma_src_mem_write_byte(dma_src_b + ADDR_WIDTH'(i), b_payload[i]);
        end
    end
    endtask

    task automatic run_dma_load(
        input string                  tag,
        input logic [ADDR_WIDTH-1:0]  src_addr,
        input logic [ADDR_WIDTH-1:0]  dst_addr,
        input int unsigned            byte_count
    );
        int unsigned timeout;
        int unsigned beats;
        bit done_seen;

        timeout   = 0;
        done_seen = 0;
        beats     = ceil_div(byte_count, BYTES_PER_BEAT);

        if (beats == 0) begin
            `uvm_fatal("DMA_STORE_SMOKE",
                $sformatf("Invalid zero-beat DMA load for %s", tag))
        end

        `uvm_info("DMA_STORE_SMOKE",
            $sformatf("Starting DMA load %s: src=0x%08h dst=0x%08h bytes=%0d beats=%0d",
                tag, src_addr, dst_addr, byte_count, beats),
            UVM_MEDIUM)

        @(vif.cb_drv);
        vif.cb_drv.dma_src_base_addr <= src_addr;
        vif.cb_drv.dma_dst_base_addr <= dst_addr;
        vif.cb_drv.dma_load_beats    <= beats[31:0];
        vif.cb_drv.dma_load_start    <= 1'b1;

        @(vif.cb_drv);
        vif.cb_drv.dma_load_start    <= 1'b0;

        while (!done_seen) begin
            @(vif.cb_drv);

            if (vif.cb_drv.dma_load_done === 1'b1) begin
                done_seen = 1;
            end

            timeout++;
            if (timeout > 10000) begin
                `uvm_fatal("DMA_STORE_SMOKE",
                    $sformatf("Timeout waiting for DMA load done: %s", tag))
            end
        end

        if (vif.cb_drv.dma_load_error !== 1'b0) begin
            `uvm_fatal("DMA_STORE_SMOKE",
                $sformatf("DMA load reported error: %s", tag))
        end

        repeat (5) @(vif.cb_drv);

        if (vif.cb_drv.dma_load_busy !== 1'b0) begin
            `uvm_fatal("DMA_STORE_SMOKE",
                $sformatf("DMA load busy did not clear after done: %s", tag))
        end

        `uvm_info("DMA_STORE_SMOKE",
            $sformatf("Completed DMA load %s", tag),
            UVM_MEDIUM)
    endtask

    task automatic run_gemm(input int unsigned cid);
        int unsigned timeout;
        bit done_seen;

        timeout   = 0;
        done_seen = 0;

        set_monitor_case_context(cid);

        `uvm_info("DMA_STORE_SMOKE",
            $sformatf("Starting GEMM after DMA-loaded A/B: case_id=%0d dim=(%0d,%0d,%0d)",
                cid, dim_m_i, dim_n_i, dim_k_i),
            UVM_MEDIUM)

        @(vif.cb_drv);
        vif.cb_drv.base_addr_a <= base_a;
        vif.cb_drv.base_addr_b <= base_b;
        vif.cb_drv.base_addr_c <= base_c;
        vif.cb_drv.dim_m       <= dim_m_i[DIM_WIDTH-1:0];
        vif.cb_drv.dim_n       <= dim_n_i[DIM_WIDTH-1:0];
        vif.cb_drv.dim_k       <= dim_k_i[DIM_WIDTH-1:0];

        repeat (2) @(vif.cb_drv);

        vif.cb_drv.acc_start <= 1'b1;
        @(vif.cb_drv);
        vif.cb_drv.acc_start <= 1'b0;

        while (!done_seen) begin
            @(vif.cb_drv);

            if (vif.cb_drv.acc_done === 1'b1) begin
                done_seen = 1;
            end

            timeout++;
            if (timeout > gemm_done_timeout_cycles) begin
                `uvm_fatal("DMA_STORE_SMOKE",
                    $sformatf("Timeout waiting for acc_done after %0d cycles",
                        gemm_done_timeout_cycles))
            end
        end

        repeat (5) @(vif.cb_drv);

        `uvm_info("DMA_STORE_SMOKE", "GEMM completed", UVM_MEDIUM)
    endtask

    task automatic run_dma_store_c();
        int unsigned timeout;
        bit done_seen;

        timeout   = 0;
        done_seen = 0;

        if (c_bytes == 0) begin
            `uvm_fatal("DMA_STORE_SMOKE", "Invalid zero-byte DMA store")
        end

        `uvm_info("DMA_STORE_SMOKE",
            $sformatf("Starting DMA store C: src=0x%08h dst=0x%08h bytes=%0d",
                base_c, dma_store_dst_base, c_bytes),
            UVM_MEDIUM)

        @(vif.cb_drv);
        vif.cb_drv.dma_store_src_base_addr <= base_c;
        vif.cb_drv.dma_store_dst_base_addr <= dma_store_dst_base;
        vif.cb_drv.dma_store_byte_count    <= c_bytes[31:0];
        vif.cb_drv.dma_store_start         <= 1'b1;

        @(vif.cb_drv);
        vif.cb_drv.dma_store_start         <= 1'b0;

        while (!done_seen) begin
            @(vif.cb_drv);

            if (vif.cb_drv.dma_store_done === 1'b1) begin
                done_seen = 1;
            end

            timeout++;
            if (timeout > 10000) begin
                `uvm_fatal("DMA_STORE_SMOKE",
                    "Timeout waiting for DMA store done")
            end
        end

        if (vif.cb_drv.dma_store_error !== 1'b0) begin
            `uvm_fatal("DMA_STORE_SMOKE",
                "DMA store reported error")
        end

        repeat (5) @(vif.cb_drv);

        if (vif.cb_drv.dma_store_busy !== 1'b0) begin
            `uvm_fatal("DMA_STORE_SMOKE",
                "DMA store busy did not clear after done")
        end

        `uvm_info("DMA_STORE_SMOKE",
            "Completed DMA store C",
            UVM_MEDIUM)
    endtask

    task automatic read_dst_and_compare_c(
        output int signed actual_dyn[]
    );
        int unsigned c_idx;
        logic [ADDR_WIDTH-1:0] addr;
        logic [31:0] got_c;
    begin
        actual_dyn = new[c_words];

        `uvm_info("DMA_STORE_SMOKE",
            $sformatf("Reading DMA destination memory: dst_base=0x%08h words=%0d",
                dma_store_dst_base, c_words),
            UVM_MEDIUM)

        for (c_idx = 0; c_idx < c_words; c_idx++) begin
            addr  = dma_store_dst_base + ADDR_WIDTH'(c_idx * 4);
            got_c = vif.dma_dst_mem_read_word32(addr);

            actual_dyn[c_idx] = $signed(got_c);

            `uvm_info("DMA_STORE_SMOKE",
                $sformatf("DST_C[%0d] readback: got=%0d expected=%0d raw=0x%08h",
                    c_idx,
                    actual_dyn[c_idx],
                    $signed(expected_c[c_idx]),
                    got_c),
                UVM_MEDIUM)

            if (got_c !== expected_c[c_idx]) begin
                `uvm_fatal("DMA_STORE_SMOKE",
                    $sformatf("DST_C[%0d] mismatch: got=0x%08h expected=0x%08h",
                        c_idx, got_c, expected_c[c_idx]))
            end
        end

        `uvm_info("DMA_STORE_SMOKE",
            $sformatf("PASS: DMA-store GEMM CASE_ID=%0d dim=(%0d,%0d,%0d) C_words=%0d",
                case_id, dim_m_i, dim_n_i, dim_k_i, c_words),
            UVM_LOW)
    end
    endtask

    task automatic run_one_case(input int unsigned cid);
        int signed expected_dyn[];
        int signed actual_dyn[];
    begin
        case_id = cid;
        configure_case(case_id);

        clear_c_region();
        clear_dma_destination_memory();
        preload_dma_source_memory();

        run_dma_load("A", dma_src_a, base_a, a_bytes);
        run_dma_load("B", dma_src_b, base_b, b_bytes);

        run_gemm(case_id);

        run_dma_store_c();
        read_dst_and_compare_c(actual_dyn);

        if (enable_result_check) begin
            build_expected_result_vector(expected_dyn);
            publish_result_to_scoreboard(case_id, expected_dyn, actual_dyn);
        end

        clear_monitor_case_context();

        `uvm_info("DMA_STORE_SMOKE",
            $sformatf("Completed CASE_ID=%0d", cid),
            UVM_LOW)
    end
    endtask

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        `uvm_info("DMA_STORE_SMOKE", "Starting ai_accel_subsys_dma_store_smoke_test", UVM_LOW)

        init_ctrl_outputs();
        init_axi0_outputs();

        wait_for_reset_release();

        if (run_all != 0) begin
            run_one_case(100);
            repeat (10) @(vif.cb_drv);

            run_one_case(101);
            repeat (10) @(vif.cb_drv);

            run_one_case(105);
            repeat (10) @(vif.cb_drv);

            run_one_case(5);
            repeat (10) @(vif.cb_drv);

            run_one_case(400);
            repeat (10) @(vif.cb_drv);

            run_one_case(401);
            repeat (10) @(vif.cb_drv);

            run_one_case(402);
            repeat (10) @(vif.cb_drv);

            run_one_case(403);
        end
        else begin
            run_one_case(case_id);
        end

        `uvm_info("DMA_STORE_SMOKE", "ai_accel_subsys_dma_store_smoke_test completed", UVM_LOW)

        phase.drop_objection(this);
    endtask

endclass

`endif
