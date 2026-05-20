// File: rtl/gemm/gemm_top.sv
`ifndef GEMM_TOP_SV
`define GEMM_TOP_SV

module gemm_top #(
    parameter int ADDR_WIDTH   = 32,
    parameter int A_DATA_WIDTH = 8,
    parameter int B_DATA_WIDTH = 8,
    parameter int ACC_WIDTH    = 32,
    parameter int DIM_WIDTH    = 8,
    parameter int GEMM_MAC_LANES = 1,

    parameter bit GEMM_ENABLE_B_CACHE = 1'b0,
    parameter int GEMM_B_CACHE_MAX_K  = 4,
    parameter int GEMM_B_CACHE_MAX_N  = 4,

    // P5 packed B-cache preload.
    // Default-off so the current baseline behavior is unchanged unless explicitly enabled.
    parameter bit GEMM_ENABLE_PACKED_BCACHE_PRELOAD = 1'b0,

    // P6 safe parameter patch.
    // Default-off so the current P5 baseline behavior is unchanged.
    parameter bit GEMM_ENABLE_A_ROW_CACHE = 1'b0,
    parameter int GEMM_A_ROW_CACHE_MAX_K  = 4
)(
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic                     start,
    output logic                     busy,
    output logic                     done,

    input  logic [ADDR_WIDTH-1:0]    base_addr_a,
    input  logic [ADDR_WIDTH-1:0]    base_addr_b,
    input  logic [ADDR_WIDTH-1:0]    base_addr_c,

    input  logic [DIM_WIDTH-1:0]     dim_m,
    input  logic [DIM_WIDTH-1:0]     dim_n,
    input  logic [DIM_WIDTH-1:0]     dim_k,

    // Local memory request acceptance
    input  logic                     mem_req_ready,

    // Local memory write completion
    // This should pulse when the adapter has completed the accepted write.
    input  logic                     mem_wr_done,

    output logic                     mem_rd_en,
    output logic [ADDR_WIDTH-1:0]    mem_rd_addr,
    input  logic [31:0]              mem_rd_data,
    input  logic                     mem_rd_valid,

    output logic                     mem_wr_en,
    output logic [ADDR_WIDTH-1:0]    mem_wr_addr,
    output logic [31:0]              mem_wr_data,
    output logic [3:0]               mem_wr_strb,

    output logic [31:0]              gemm_perf_busy_cycles,
    output logic [31:0]              gemm_perf_mac_count,
    output logic [31:0]              gemm_perf_output_count
);

    typedef enum logic [4:0] {
        S_IDLE,

        S_BCACHE_INIT,
        S_BCACHE_READ,
        S_BCACHE_WAIT,
        S_BCACHE_NEXT,

        S_BCACHE_PACK_INIT,
        S_BCACHE_PACK_READ,
        S_BCACHE_PACK_WAIT,
        S_BCACHE_PACK_NEXT,

        S_AROW_INIT,
        S_AROW_READ,
        S_AROW_WAIT,
        S_AROW_NEXT,

        S_READ_A,
        S_WAIT_A,
        S_READ_B,
        S_WAIT_B,

        S_READ_A1,
        S_WAIT_A1,
        S_READ_B1,
        S_WAIT_B1,

        S_MAC,
        S_WRITE_C,
        S_WAIT_C_WRITE,
        S_NEXT,
        S_DONE
    } gemm_state_e;

    localparam int A_BYTES = (A_DATA_WIDTH + 7) / 8;
    localparam int B_BYTES = (B_DATA_WIDTH + 7) / 8;
    localparam int C_BYTES = (ACC_WIDTH    + 7) / 8;

`ifndef SYNTHESIS
    initial begin
        if ((GEMM_MAC_LANES != 1) && (GEMM_MAC_LANES != 2)) begin
            $fatal(1,
                "Unsupported GEMM_MAC_LANES=%0d. Supported values are 1 and 2.",
                GEMM_MAC_LANES
            );
        end

        if (GEMM_B_CACHE_MAX_K <= 0) begin
            $fatal(1,
                "Unsupported GEMM_B_CACHE_MAX_K=%0d. Must be > 0.",
                GEMM_B_CACHE_MAX_K
            );
        end

        if (GEMM_B_CACHE_MAX_N <= 0) begin
            $fatal(1,
                "Unsupported GEMM_B_CACHE_MAX_N=%0d. Must be > 0.",
                GEMM_B_CACHE_MAX_N
            );
        end

        if (GEMM_A_ROW_CACHE_MAX_K <= 0) begin
            $fatal(1,
                "Unsupported GEMM_A_ROW_CACHE_MAX_K=%0d. Must be > 0.",
                GEMM_A_ROW_CACHE_MAX_K
            );
        end
    end
`endif

`ifndef SYNTHESIS
    initial begin
        $display("# [GEMM_TOP_CFG] GEMM_MAC_LANES=%0d GEMM_ENABLE_B_CACHE=%0d GEMM_B_CACHE_MAX_K=%0d GEMM_B_CACHE_MAX_N=%0d GEMM_ENABLE_PACKED_BCACHE_PRELOAD=%0d GEMM_ENABLE_A_ROW_CACHE=%0d GEMM_A_ROW_CACHE_MAX_K=%0d",
                 GEMM_MAC_LANES,
                 GEMM_ENABLE_B_CACHE,
                 GEMM_B_CACHE_MAX_K,
                 GEMM_B_CACHE_MAX_N,
                 GEMM_ENABLE_PACKED_BCACHE_PRELOAD,
                 GEMM_ENABLE_A_ROW_CACHE,
                 GEMM_A_ROW_CACHE_MAX_K);
    end
`endif

    gemm_state_e                    state_q, state_d;

    logic [DIM_WIDTH-1:0]           m_idx_q, m_idx_d;
    logic [DIM_WIDTH-1:0]           n_idx_q, n_idx_d;
    logic [DIM_WIDTH-1:0]           k_idx_q, k_idx_d;

    logic signed [A_DATA_WIDTH-1:0] a_val_q, a_val_d;
    logic signed [B_DATA_WIDTH-1:0] b_val_q, b_val_d;

    logic signed [A_DATA_WIDTH-1:0] a1_val_q, a1_val_d;
    logic signed [B_DATA_WIDTH-1:0] b1_val_q, b1_val_d;
    logic                           lane1_valid_q, lane1_valid_d;

    logic signed [ACC_WIDTH-1:0]    acc_q, acc_d;

    logic                           busy_d;
    logic                           done_d;

    logic                           mem_rd_en_d;
    logic [ADDR_WIDTH-1:0]          mem_rd_addr_d;

    logic                           mem_wr_en_d;
    logic [ADDR_WIDTH-1:0]          mem_wr_addr_d;
    logic [31:0]                    mem_wr_data_d;
    logic [3:0]                     mem_wr_strb_d;

    logic signed [B_DATA_WIDTH-1:0] b_cache_q [0:GEMM_B_CACHE_MAX_K-1][0:GEMM_B_CACHE_MAX_N-1];
    logic signed [B_DATA_WIDTH-1:0] b_cache_d [0:GEMM_B_CACHE_MAX_K-1][0:GEMM_B_CACHE_MAX_N-1];

    // P6 scalar A-row cache.
    // Used only when GEMM_ENABLE_A_ROW_CACHE=1, B-cache is active, and dim_k fits.
    logic signed [A_DATA_WIDTH-1:0] a_row_cache_q [0:GEMM_A_ROW_CACHE_MAX_K-1];
    logic signed [A_DATA_WIDTH-1:0] a_row_cache_d [0:GEMM_A_ROW_CACHE_MAX_K-1];

    logic [DIM_WIDTH-1:0]           arow_k_q, arow_k_d;

    logic [DIM_WIDTH-1:0]           bcache_k_q, bcache_k_d;
    logic [DIM_WIDTH-1:0]           bcache_n_q, bcache_n_d;

    // P5 packed B-cache preload state.
    // Used only when GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1 and base_addr_b is 4-byte aligned.
    logic [ADDR_WIDTH-1:0]          bpack_addr_q, bpack_addr_d;
    logic [ADDR_WIDTH-1:0]          bpack_end_addr_q, bpack_end_addr_d;

    logic                           b_cache_active_job_q;
    logic                           b_cache_active_job_d;

    logic                           a_row_cache_active_job_q;
    logic                           a_row_cache_active_job_d;

    logic b_cache_dim_supported;
    logic b_cache_active_calc;
    logic packed_bcache_preload_calc;

    logic a_row_cache_dim_supported;
    logic a_row_cache_active_calc;

    logic [ADDR_WIDTH-1:0] bcache_total_bytes_calc;
    logic [ADDR_WIDTH-1:0] bpack_last_byte_addr_calc;
    logic [ADDR_WIDTH-1:0] bpack_start_addr_calc;
    logic [ADDR_WIDTH-1:0] bpack_end_addr_calc;

    always_comb begin
        b_cache_dim_supported =
            (dim_k != '0) &&
            (dim_n != '0) &&
            (int'(dim_k) <= GEMM_B_CACHE_MAX_K) &&
            (int'(dim_n) <= GEMM_B_CACHE_MAX_N);

        b_cache_active_calc =
            GEMM_ENABLE_B_CACHE && b_cache_dim_supported;

        // First P5 policy:
        // - packed B-cache preload is optional and default-off
        // - packed preload only supports int8 B elements
        // - packed preload only activates when base_addr_b is 4-byte aligned
        // - unaligned B bases automatically fall back to the scalar P4 preload path
        packed_bcache_preload_calc =
            b_cache_active_calc &&
            GEMM_ENABLE_PACKED_BCACHE_PRELOAD &&
            (B_BYTES == 1) &&
            (base_addr_b[1:0] == 2'b00);

        // First P6 policy:
        // - A-row cache is optional and default-off
        // - A-row cache requires B-cache for the first implementation
        // - A-row cache only supports scalar int8 A preload in P6C
        // - unsupported dimensions automatically fall back to the P5 path
        a_row_cache_dim_supported =
            (dim_k != '0) &&
            (int'(dim_k) <= GEMM_A_ROW_CACHE_MAX_K);

        a_row_cache_active_calc =
            GEMM_ENABLE_A_ROW_CACHE &&
            b_cache_active_calc &&
            a_row_cache_dim_supported &&
            (A_BYTES == 1);
    end

    assign bcache_total_bytes_calc =
        int'(dim_k) * int'(dim_n) * B_BYTES;

    assign bpack_start_addr_calc =
        {base_addr_b[ADDR_WIDTH-1:2], 2'b00};

    assign bpack_last_byte_addr_calc =
        base_addr_b + bcache_total_bytes_calc - 1'b1;

    assign bpack_end_addr_calc =
        {bpack_last_byte_addr_calc[ADDR_WIDTH-1:2], 2'b00};

    logic [DIM_WIDTH:0]             k_idx_ext;
    logic [DIM_WIDTH:0]             dim_k_ext;
    logic [DIM_WIDTH:0]             k_idx_plus1_ext;
    logic [DIM_WIDTH:0]             k_idx_plus2_ext;

    logic [DIM_WIDTH-1:0]           k_idx_plus1;
    logic                           lane1_valid_calc;
    logic                           lane2_last_k_group;

    assign k_idx_ext       = {1'b0, k_idx_q};
    assign dim_k_ext       = {1'b0, dim_k};
    assign k_idx_plus1_ext = k_idx_ext + 1;
    assign k_idx_plus2_ext = k_idx_ext + 2;
    assign k_idx_plus1     = k_idx_plus1_ext[DIM_WIDTH-1:0];

    assign lane1_valid_calc =
        (GEMM_MAC_LANES == 2) &&
        (k_idx_plus1_ext < dim_k_ext);

    assign lane2_last_k_group =
        (k_idx_plus2_ext >= dim_k_ext);

    logic signed [ACC_WIDTH-1:0]    lane0_product;
    logic signed [ACC_WIDTH-1:0]    lane1_product;
    logic signed [ACC_WIDTH-1:0]    mac_sum;

    assign lane0_product = $signed(a_val_q)  * $signed(b_val_q);
    assign lane1_product = $signed(a1_val_q) * $signed(b1_val_q);

    always_comb begin
        mac_sum = lane0_product;

        if ((GEMM_MAC_LANES == 2) && lane1_valid_q) begin
            mac_sum = lane0_product + lane1_product;
        end
    end

    logic                           start_accept;
    logic                           mac_commit;
    logic                           output_commit;
    logic [31:0]                    mac_commit_count;

    assign start_accept = (state_q == S_IDLE) && start;
    assign mac_commit   = (state_q == S_MAC);

    assign mac_commit_count =
        mac_commit
            ? (((GEMM_MAC_LANES == 2) && lane1_valid_q) ? 32'd2 : 32'd1)
            : 32'd0;

    // Count one output only when the C write has completed.
    assign output_commit =
        (state_q == S_WAIT_C_WRITE) && mem_wr_done;

    logic [ADDR_WIDTH-1:0] a_addr_calc;
    logic [ADDR_WIDTH-1:0] arow_addr_calc;
    logic [ADDR_WIDTH-1:0] b_addr_calc;
    logic [ADDR_WIDTH-1:0] a1_addr_calc;
    logic [ADDR_WIDTH-1:0] b1_addr_calc;
    logic [ADDR_WIDTH-1:0] c_addr_calc;

    logic [ADDR_WIDTH-1:0] bcache_b_addr_calc;
    logic                  bcache_last_n;
    logic                  bcache_last_elem;
    logic                  arow_last_k;

    assign a_addr_calc =
        base_addr_a + ((m_idx_q * dim_k) + k_idx_q) * A_BYTES;

    assign arow_addr_calc =
        base_addr_a + ((m_idx_q * dim_k) + arow_k_q) * A_BYTES;

    assign b_addr_calc =
        base_addr_b + ((k_idx_q * dim_n) + n_idx_q) * B_BYTES;

    assign a1_addr_calc =
        base_addr_a + ((m_idx_q * dim_k) + k_idx_plus1) * A_BYTES;

    assign b1_addr_calc =
        base_addr_b + ((k_idx_plus1 * dim_n) + n_idx_q) * B_BYTES;

    assign bcache_b_addr_calc =
        base_addr_b + ((bcache_k_q * dim_n) + bcache_n_q) * B_BYTES;

    assign bcache_last_n =
        (bcache_n_q == (dim_n - 1'b1));

    assign bcache_last_elem =
        (bcache_k_q == (dim_k - 1'b1)) &&
        (bcache_n_q == (dim_n - 1'b1));

    assign arow_last_k =
        (arow_k_q == (dim_k - 1'b1));

    assign c_addr_calc =
        base_addr_c + ((m_idx_q * dim_n) + n_idx_q) * C_BYTES;

    always_comb begin
        state_d       = state_q;

        m_idx_d       = m_idx_q;
        n_idx_d       = n_idx_q;
        k_idx_d       = k_idx_q;

        a_val_d       = a_val_q;
        b_val_d       = b_val_q;
        a1_val_d      = a1_val_q;
        b1_val_d      = b1_val_q;
        lane1_valid_d = lane1_valid_q;

        acc_d         = acc_q;

        busy_d        = busy;
        done_d        = 1'b0;

        mem_rd_en_d   = 1'b0;
        mem_rd_addr_d = mem_rd_addr;

        mem_wr_en_d   = 1'b0;
        mem_wr_addr_d = mem_wr_addr;
        mem_wr_data_d = mem_wr_data;
        mem_wr_strb_d = 4'b0000;

        arow_k_d             = arow_k_q;
        bcache_k_d            = bcache_k_q;
        bcache_n_d            = bcache_n_q;
        bpack_addr_d          = bpack_addr_q;
        bpack_end_addr_d      = bpack_end_addr_q;
        b_cache_active_job_d  = b_cache_active_job_q;
        a_row_cache_active_job_d = a_row_cache_active_job_q;

        for (int ak = 0; ak < GEMM_A_ROW_CACHE_MAX_K; ak++) begin
            a_row_cache_d[ak] = a_row_cache_q[ak];
        end

        for (int bk = 0; bk < GEMM_B_CACHE_MAX_K; bk++) begin
            for (int bn = 0; bn < GEMM_B_CACHE_MAX_N; bn++) begin
                b_cache_d[bk][bn] = b_cache_q[bk][bn];
            end
        end

        case (state_q)

            S_IDLE: begin
                busy_d = 1'b0;

                if (start) begin
                    m_idx_d       = '0;
                    n_idx_d       = '0;
                    k_idx_d       = '0;

                    a_val_d       = '0;
                    b_val_d       = '0;
                    a1_val_d      = '0;
                    b1_val_d      = '0;
                    lane1_valid_d = 1'b0;

                    arow_k_d            = '0;
                    bcache_k_d           = '0;
                    bcache_n_d           = '0;
                    bpack_addr_d         = '0;
                    bpack_end_addr_d     = '0;
                    b_cache_active_job_d = b_cache_active_calc;
                    a_row_cache_active_job_d = a_row_cache_active_calc;

                    // Defensive job-local cache cleanup.
                    // Current preload should overwrite all used entries, but clearing
                    // avoids stale entries if later patches add partial-valid behavior.
                    for (int ak = 0; ak < GEMM_A_ROW_CACHE_MAX_K; ak++) begin
                        a_row_cache_d[ak] = '0;
                    end

                    for (int bk = 0; bk < GEMM_B_CACHE_MAX_K; bk++) begin
                        for (int bn = 0; bn < GEMM_B_CACHE_MAX_N; bn++) begin
                            b_cache_d[bk][bn] = '0;
                        end
                    end

                    acc_d         = '0;
                    busy_d        = 1'b1;

                    if (b_cache_active_calc) begin
                        if (packed_bcache_preload_calc) begin
                            state_d = S_BCACHE_PACK_INIT;
                        end
                        else begin
                            state_d = S_BCACHE_INIT;
                        end
                    end
                    else begin
                        state_d = S_READ_A;
                    end
                end
            end

            S_BCACHE_INIT: begin
                bcache_k_d = '0;
                bcache_n_d = '0;
                state_d    = S_BCACHE_READ;
            end

            S_BCACHE_READ: begin
                mem_rd_addr_d = bcache_b_addr_calc;

                if (mem_req_ready) begin
                    mem_rd_en_d = 1'b1;
                    state_d     = S_BCACHE_WAIT;
                end
            end

            S_BCACHE_WAIT: begin
                if (mem_rd_valid) begin
                    b_cache_d[int'(bcache_k_q)][int'(bcache_n_q)] =
                        mem_rd_data[B_DATA_WIDTH-1:0];

                    state_d = S_BCACHE_NEXT;
                end
            end

            S_BCACHE_NEXT: begin
                if (bcache_last_elem) begin
                    bcache_k_d = '0;
                    bcache_n_d = '0;

                    if (a_row_cache_active_job_q) begin
                        state_d = S_AROW_INIT;
                    end
                    else begin
                        state_d = S_READ_A;
                    end
                end
                else if (bcache_last_n) begin
                    bcache_n_d = '0;
                    bcache_k_d = bcache_k_q + 1'b1;
                    state_d    = S_BCACHE_READ;
                end
                else begin
                    bcache_n_d = bcache_n_q + 1'b1;
                    state_d    = S_BCACHE_READ;
                end
            end

            // ----------------------------------------------------
            // P5 packed B-cache preload path
            //
            // First implementation policy:
            //   - active only for 4-byte aligned base_addr_b
            //   - unaligned base_addr_b falls back to scalar preload
            //   - unpacks up to four int8 B elements per 32-bit read
            // ----------------------------------------------------
            S_BCACHE_PACK_INIT: begin
                bpack_addr_d     = bpack_start_addr_calc;
                bpack_end_addr_d = bpack_end_addr_calc;
                state_d          = S_BCACHE_PACK_READ;
            end

            S_BCACHE_PACK_READ: begin
                mem_rd_addr_d = bpack_addr_q;

                if (mem_req_ready) begin
                    mem_rd_en_d = 1'b1;
                    state_d     = S_BCACHE_PACK_WAIT;
                end
            end

            S_BCACHE_PACK_WAIT: begin
                if (mem_rd_valid) begin
                    for (int bl = 0; bl < 4; bl++) begin
                        int unsigned pack_linear_idx;
                        int unsigned pack_bk;
                        int unsigned pack_bn;

                        pack_linear_idx = int'(bpack_addr_q - base_addr_b) + bl;

                        if (pack_linear_idx < int'(dim_k) * int'(dim_n)) begin
                            pack_bk = pack_linear_idx / int'(dim_n);
                            pack_bn = pack_linear_idx % int'(dim_n);

                            if ((pack_bk < GEMM_B_CACHE_MAX_K) &&
                                (pack_bn < GEMM_B_CACHE_MAX_N)) begin
                                b_cache_d[pack_bk][pack_bn] =
                                    mem_rd_data[(8 * bl) +: B_DATA_WIDTH];
                            end
                        end
                    end

                    state_d = S_BCACHE_PACK_NEXT;
                end
            end

            S_BCACHE_PACK_NEXT: begin
                if (bpack_addr_q == bpack_end_addr_q) begin
                    bpack_addr_d     = '0;
                    bpack_end_addr_d = '0;

                    if (a_row_cache_active_job_q) begin
                        state_d = S_AROW_INIT;
                    end
                    else begin
                        state_d = S_READ_A;
                    end
                end
                else begin
                    bpack_addr_d = bpack_addr_q + ADDR_WIDTH'(4);
                    state_d      = S_BCACHE_PACK_READ;
                end
            end

            // ----------------------------------------------------
            // P6 scalar A-row cache preload path
            //
            // First implementation policy:
            //   - active only when B-cache is also active
            //   - scalar int8 A-row preload only
            //   - one cache fill per output row m
            // ----------------------------------------------------
            S_AROW_INIT: begin
                arow_k_d = '0;
                state_d  = S_AROW_READ;
            end

            S_AROW_READ: begin
                mem_rd_addr_d = arow_addr_calc;

                if (mem_req_ready) begin
                    mem_rd_en_d = 1'b1;
                    state_d     = S_AROW_WAIT;
                end
            end

            S_AROW_WAIT: begin
                if (mem_rd_valid) begin
                    if (int'(arow_k_q) < GEMM_A_ROW_CACHE_MAX_K) begin
                        a_row_cache_d[int'(arow_k_q)] =
                            mem_rd_data[A_DATA_WIDTH-1:0];
                    end

                    state_d = S_AROW_NEXT;
                end
            end

            S_AROW_NEXT: begin
                if (arow_last_k) begin
                    arow_k_d = '0;
                    state_d  = S_READ_A;
                end
                else begin
                    arow_k_d = arow_k_q + 1'b1;
                    state_d  = S_AROW_READ;
                end
            end

            S_READ_A: begin
                if (a_row_cache_active_job_q) begin
                    a_val_d  = a_row_cache_q[int'(k_idx_q)];
                    b_val_d  = b_cache_q[int'(k_idx_q)][int'(n_idx_q)];

                    if ((GEMM_MAC_LANES == 2) && lane1_valid_calc) begin
                        lane1_valid_d = 1'b1;
                        a1_val_d      = a_row_cache_q[int'(k_idx_plus1)];
                        b1_val_d      = b_cache_q[int'(k_idx_plus1)][int'(n_idx_q)];
                    end
                    else begin
                        lane1_valid_d = 1'b0;
                        a1_val_d      = '0;
                        b1_val_d      = '0;
                    end

                    state_d = S_MAC;
                end
                else begin
                    mem_rd_addr_d = a_addr_calc;

                    if (mem_req_ready) begin
                        mem_rd_en_d = 1'b1;
                        state_d     = S_WAIT_A;
                    end
                end
            end

            S_WAIT_A: begin
                if (mem_rd_valid) begin
                    a_val_d = mem_rd_data[A_DATA_WIDTH-1:0];

                    if (b_cache_active_job_q) begin
                        b_val_d = b_cache_q[int'(k_idx_q)][int'(n_idx_q)];

                        if ((GEMM_MAC_LANES == 2) && lane1_valid_calc) begin
                            lane1_valid_d = 1'b1;
                            state_d       = S_READ_A1;
                        end
                        else begin
                            lane1_valid_d = 1'b0;
                            state_d       = S_MAC;
                        end
                    end
                    else begin
                        state_d = S_READ_B;
                    end
                end
            end

            S_READ_B: begin
                mem_rd_addr_d = b_addr_calc;

                if (mem_req_ready) begin
                    mem_rd_en_d = 1'b1;
                    state_d     = S_WAIT_B;
                end
            end

            S_WAIT_B: begin
                if (mem_rd_valid) begin
                    b_val_d = mem_rd_data[B_DATA_WIDTH-1:0];

                    if ((GEMM_MAC_LANES == 2) && lane1_valid_calc) begin
                        lane1_valid_d = 1'b1;
                        state_d       = S_READ_A1;
                    end
                    else begin
                        lane1_valid_d = 1'b0;
                        state_d       = S_MAC;
                    end
                end
            end

            S_READ_A1: begin
                mem_rd_addr_d = a1_addr_calc;

                if (mem_req_ready) begin
                    mem_rd_en_d = 1'b1;
                    state_d     = S_WAIT_A1;
                end
            end

            S_WAIT_A1: begin
                if (mem_rd_valid) begin
                    a1_val_d = mem_rd_data[A_DATA_WIDTH-1:0];

                    if (b_cache_active_job_q) begin
                        b1_val_d = b_cache_q[int'(k_idx_plus1)][int'(n_idx_q)];
                        state_d  = S_MAC;
                    end
                    else begin
                        state_d = S_READ_B1;
                    end
                end
            end

            S_READ_B1: begin
                mem_rd_addr_d = b1_addr_calc;

                if (mem_req_ready) begin
                    mem_rd_en_d = 1'b1;
                    state_d     = S_WAIT_B1;
                end
            end

            S_WAIT_B1: begin
                if (mem_rd_valid) begin
                    b1_val_d = mem_rd_data[B_DATA_WIDTH-1:0];
                    state_d  = S_MAC;
                end
            end

            S_MAC: begin
                acc_d = acc_q + mac_sum;

                if (GEMM_MAC_LANES == 2) begin
                    if (lane2_last_k_group) begin
                        state_d = S_WRITE_C;
                    end
                    else begin
                        k_idx_d = k_idx_q + 2;
                        state_d = S_READ_A;
                    end
                end
                else begin
                    if (k_idx_q == (dim_k - 1)) begin
                        state_d = S_WRITE_C;
                    end
                    else begin
                        k_idx_d = k_idx_q + 1'b1;
                        state_d = S_READ_A;
                    end
                end
            end

            S_WRITE_C: begin
                mem_wr_addr_d = c_addr_calc;
                mem_wr_data_d = acc_q;
                mem_wr_strb_d = 4'b1111;

                if (mem_req_ready) begin
                    mem_wr_en_d = 1'b1;
                    state_d     = S_WAIT_C_WRITE;
                end
            end

            S_WAIT_C_WRITE: begin
                if (mem_wr_done) begin
                    state_d = S_NEXT;
                end
            end

            S_NEXT: begin
                k_idx_d       = '0;
                acc_d         = '0;
                a1_val_d      = '0;
                b1_val_d      = '0;
                lane1_valid_d = 1'b0;

                if (n_idx_q == (dim_n - 1)) begin
                    n_idx_d = '0;

                    if (m_idx_q == (dim_m - 1)) begin
                        state_d = S_DONE;
                    end
                    else begin
                        m_idx_d = m_idx_q + 1'b1;

                        if (a_row_cache_active_job_q) begin
                            state_d = S_AROW_INIT;
                        end
                        else begin
                            state_d = S_READ_A;
                        end
                    end
                end
                else begin
                    n_idx_d = n_idx_q + 1'b1;
                    state_d = S_READ_A;
                end
            end

            S_DONE: begin
                busy_d = 1'b0;
                done_d = 1'b1;

                if (!start) begin
                    state_d = S_IDLE;
                end
            end

            default: begin
                state_d              = S_IDLE;
                busy_d               = 1'b0;
                done_d               = 1'b0;
                lane1_valid_d            = 1'b0;
                b_cache_active_job_d     = 1'b0;
                a_row_cache_active_job_d = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q      <= S_IDLE;

            m_idx_q      <= '0;
            n_idx_q      <= '0;
            k_idx_q      <= '0;

            a_val_q      <= '0;
            b_val_q      <= '0;
            a1_val_q     <= '0;
            b1_val_q     <= '0;
            lane1_valid_q<= 1'b0;

            acc_q        <= '0;

            busy         <= 1'b0;
            done         <= 1'b0;

            mem_rd_en    <= 1'b0;
            mem_rd_addr  <= '0;

            mem_wr_en    <= 1'b0;
            mem_wr_addr  <= '0;
            mem_wr_data  <= '0;
            mem_wr_strb  <= '0;

            arow_k_q            <= '0;
            bcache_k_q           <= '0;
            bcache_n_q           <= '0;
            bpack_addr_q         <= '0;
            bpack_end_addr_q     <= '0;
            b_cache_active_job_q <= 1'b0;
            a_row_cache_active_job_q <= 1'b0;

            for (int ak = 0; ak < GEMM_A_ROW_CACHE_MAX_K; ak++) begin
                a_row_cache_q[ak] <= '0;
            end

            for (int bk = 0; bk < GEMM_B_CACHE_MAX_K; bk++) begin
                for (int bn = 0; bn < GEMM_B_CACHE_MAX_N; bn++) begin
                    b_cache_q[bk][bn] <= '0;
                end
            end

            gemm_perf_busy_cycles  <= '0;
            gemm_perf_mac_count    <= '0;
            gemm_perf_output_count <= '0;
        end
        else begin
            state_q      <= state_d;

            m_idx_q      <= m_idx_d;
            n_idx_q      <= n_idx_d;
            k_idx_q      <= k_idx_d;

            a_val_q      <= a_val_d;
            b_val_q      <= b_val_d;
            a1_val_q     <= a1_val_d;
            b1_val_q     <= b1_val_d;
            lane1_valid_q<= lane1_valid_d;

            acc_q        <= acc_d;

            busy         <= busy_d;
            done         <= done_d;

            mem_rd_en    <= mem_rd_en_d;
            mem_rd_addr  <= mem_rd_addr_d;

            mem_wr_en    <= mem_wr_en_d;
            mem_wr_addr  <= mem_wr_addr_d;
            mem_wr_data  <= mem_wr_data_d;
            mem_wr_strb  <= mem_wr_strb_d;

            arow_k_q            <= arow_k_d;
            bcache_k_q           <= bcache_k_d;
            bcache_n_q           <= bcache_n_d;
            bpack_addr_q         <= bpack_addr_d;
            bpack_end_addr_q     <= bpack_end_addr_d;
            b_cache_active_job_q <= b_cache_active_job_d;
            a_row_cache_active_job_q <= a_row_cache_active_job_d;

            for (int ak = 0; ak < GEMM_A_ROW_CACHE_MAX_K; ak++) begin
                a_row_cache_q[ak] <= a_row_cache_d[ak];
            end

            for (int bk = 0; bk < GEMM_B_CACHE_MAX_K; bk++) begin
                for (int bn = 0; bn < GEMM_B_CACHE_MAX_N; bn++) begin
                    b_cache_q[bk][bn] <= b_cache_d[bk][bn];
                end
            end

            if (start_accept) begin
                gemm_perf_busy_cycles  <= '0;
                gemm_perf_mac_count    <= '0;
                gemm_perf_output_count <= '0;
            end
            else begin
                if (busy) begin
                    gemm_perf_busy_cycles <= gemm_perf_busy_cycles + 32'd1;
                end

                if (mac_commit) begin
                    gemm_perf_mac_count <= gemm_perf_mac_count + mac_commit_count;
                end

                if (output_commit) begin
                    gemm_perf_output_count <= gemm_perf_output_count + 32'd1;
                end
            end
        end
    end

endmodule

`endif