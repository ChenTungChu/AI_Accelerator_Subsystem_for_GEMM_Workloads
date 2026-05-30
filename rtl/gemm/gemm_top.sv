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
    parameter int GEMM_A_ROW_CACHE_MAX_K  = 4,

    // P7 safe parameter patch.
    // Default-off so the current P6 baseline behavior is unchanged.
    parameter bit GEMM_ENABLE_PACKED_A_ROW_PRELOAD = 1'b0,

    // P10 K-tiling parameterization.
    // Default-off so the pre-P10 baseline behavior is unchanged.
    parameter bit GEMM_ENABLE_K_TILING = 1'b0,
    parameter int GEMM_K_TILE_SIZE     = 8,

    // P11 N-dimension/output-column tiling parameterization.
    // Default-off so the current P10 baseline behavior is unchanged.
    // When enabled and the job exceeds the effective N tile size, P11D
    // schedules output-column tiles on top of the P10 row-accumulator
    // K-tile datapath.
    parameter bit GEMM_ENABLE_N_TILING = 1'b0,
    parameter int GEMM_N_TILE_SIZE     = 8,

    // P12 M-dimension/multi-row tiling parameterization.
    // Default-off so the current P11 baseline behavior is unchanged.
    // P12D enables a conservative cache-backed multi-row tile scheduler
    // when GEMM_ENABLE_M_TILING=1 and the job exceeds the effective M
    // tile size.
    parameter bit GEMM_ENABLE_M_TILING = 1'b0,
    parameter int GEMM_M_TILE_SIZE     = 2
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

    typedef enum logic [5:0] {
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

        S_AROW_PACK_INIT,
        S_AROW_PACK_READ,
        S_AROW_PACK_WAIT,
        S_AROW_PACK_NEXT,

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

        S_KTILE_ACCUM_N,
        S_KTILE_WRITE_ROW,
        S_KTILE_WAIT_ROW_WRITE,

        S_NEXT,
        S_DONE
    } gemm_state_e;

    localparam int A_BYTES = (A_DATA_WIDTH + 7) / 8;
    localparam int B_BYTES = (B_DATA_WIDTH + 7) / 8;
    localparam int C_BYTES = (ACC_WIDTH    + 7) / 8;

    // P8C true 4-lane MAC policy:
    //   - GEMM_MAC_LANES=1 uses the existing single-lane datapath.
    //   - GEMM_MAC_LANES=2 uses the existing 2-lane datapath.
    //   - GEMM_MAC_LANES=4 enables the cache-backed true 4-lane datapath.
    //
    // The first P8C implementation keeps the true 4-lane datapath cache-backed:
    // if GEMM_MAC_LANES=4 is requested but the current job is not using both
    // A-row cache and B-cache, the runtime lane selector falls back to the
    // already-validated 2-lane/scalar path for correctness.
    localparam int GEMM_MAC_LANES_EFFECTIVE =
        (GEMM_MAC_LANES == 4) ? 4 :
        (GEMM_MAC_LANES == 2) ? 2 :
                                1;

    localparam int GEMM_K_TILE_SIZE_LIMIT_B =
        (GEMM_K_TILE_SIZE < GEMM_B_CACHE_MAX_K) ? GEMM_K_TILE_SIZE : GEMM_B_CACHE_MAX_K;

    localparam int GEMM_K_TILE_SIZE_EFFECTIVE =
        (GEMM_K_TILE_SIZE_LIMIT_B < GEMM_A_ROW_CACHE_MAX_K) ?
            GEMM_K_TILE_SIZE_LIMIT_B :
            GEMM_A_ROW_CACHE_MAX_K;

    // P11D N-tiling effective output-column tile size.
    // The active N tile must fit the B-cache N dimension and the row
    // accumulator width.
    localparam int GEMM_N_TILE_SIZE_EFFECTIVE =
        (GEMM_N_TILE_SIZE < GEMM_B_CACHE_MAX_N) ?
            GEMM_N_TILE_SIZE :
            GEMM_B_CACHE_MAX_N;

    // P12D M-tiling effective multi-row tile size.
    // The first multi-row scheduler keeps the tile size equal to the
    // parameterized value and uses a local M-tile accumulator array.
    localparam int GEMM_M_TILE_SIZE_EFFECTIVE = GEMM_M_TILE_SIZE;

`ifndef SYNTHESIS
    initial begin
        if ((GEMM_MAC_LANES != 1) &&
            (GEMM_MAC_LANES != 2) &&
            (GEMM_MAC_LANES != 4)) begin
            $fatal(1,
                "Unsupported GEMM_MAC_LANES=%0d. Supported values are 1, 2, and 4.",
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

        if (GEMM_K_TILE_SIZE <= 0) begin
            $fatal(1,
                "Unsupported GEMM_K_TILE_SIZE=%0d. Must be > 0.",
                GEMM_K_TILE_SIZE
            );
        end

        if (GEMM_K_TILE_SIZE_EFFECTIVE <= 0) begin
            $fatal(1,
                "Unsupported GEMM_K_TILE_SIZE_EFFECTIVE=%0d. Check GEMM_K_TILE_SIZE, GEMM_B_CACHE_MAX_K, and GEMM_A_ROW_CACHE_MAX_K.",
                GEMM_K_TILE_SIZE_EFFECTIVE
            );
        end

        if (GEMM_N_TILE_SIZE <= 0) begin
            $fatal(1,
                "Unsupported GEMM_N_TILE_SIZE=%0d. Must be > 0.",
                GEMM_N_TILE_SIZE
            );
        end

        if (GEMM_N_TILE_SIZE_EFFECTIVE <= 0) begin
            $fatal(1,
                "Unsupported GEMM_N_TILE_SIZE_EFFECTIVE=%0d. Check GEMM_N_TILE_SIZE and GEMM_B_CACHE_MAX_N.",
                GEMM_N_TILE_SIZE_EFFECTIVE
            );
        end

        if (GEMM_M_TILE_SIZE <= 0) begin
            $fatal(1,
                "Unsupported GEMM_M_TILE_SIZE=%0d. Must be > 0.",
                GEMM_M_TILE_SIZE
            );
        end

        if (GEMM_M_TILE_SIZE_EFFECTIVE <= 0) begin
            $fatal(1,
                "Unsupported GEMM_M_TILE_SIZE_EFFECTIVE=%0d. Check GEMM_M_TILE_SIZE.",
                GEMM_M_TILE_SIZE_EFFECTIVE
            );
        end
    end
`endif

`ifndef SYNTHESIS
    initial begin
        $display("# [GEMM_TOP_CFG] GEMM_MAC_LANES=%0d GEMM_MAC_LANES_EFFECTIVE=%0d GEMM_ENABLE_B_CACHE=%0d GEMM_B_CACHE_MAX_K=%0d GEMM_B_CACHE_MAX_N=%0d GEMM_ENABLE_PACKED_BCACHE_PRELOAD=%0d GEMM_ENABLE_A_ROW_CACHE=%0d GEMM_A_ROW_CACHE_MAX_K=%0d GEMM_ENABLE_PACKED_A_ROW_PRELOAD=%0d GEMM_ENABLE_K_TILING=%0d GEMM_K_TILE_SIZE=%0d GEMM_K_TILE_SIZE_EFFECTIVE=%0d GEMM_ENABLE_N_TILING=%0d GEMM_N_TILE_SIZE=%0d GEMM_N_TILE_SIZE_EFFECTIVE=%0d GEMM_ENABLE_M_TILING=%0d GEMM_M_TILE_SIZE=%0d GEMM_M_TILE_SIZE_EFFECTIVE=%0d",
                 GEMM_MAC_LANES,
                 GEMM_MAC_LANES_EFFECTIVE,
                 GEMM_ENABLE_B_CACHE,
                 GEMM_B_CACHE_MAX_K,
                 GEMM_B_CACHE_MAX_N,
                 GEMM_ENABLE_PACKED_BCACHE_PRELOAD,
                 GEMM_ENABLE_A_ROW_CACHE,
                 GEMM_A_ROW_CACHE_MAX_K,
                 GEMM_ENABLE_PACKED_A_ROW_PRELOAD,
                 GEMM_ENABLE_K_TILING,
                 GEMM_K_TILE_SIZE,
                 GEMM_K_TILE_SIZE_EFFECTIVE,
                 GEMM_ENABLE_N_TILING,
                 GEMM_N_TILE_SIZE,
                 GEMM_N_TILE_SIZE_EFFECTIVE,
                 GEMM_ENABLE_M_TILING,
                 GEMM_M_TILE_SIZE,
                 GEMM_M_TILE_SIZE_EFFECTIVE);

        if (GEMM_MAC_LANES == 4) begin
            $display("# [GEMM_TOP_CFG] NOTE: GEMM_MAC_LANES=4 enables the P8C cache-backed true 4-lane MAC path when A-row cache and B-cache are active.");
        end

        if (GEMM_ENABLE_K_TILING) begin
            $display("# [GEMM_TOP_CFG] NOTE: GEMM_ENABLE_K_TILING=1 enables the P10D row-accumulator K-tiling path when K exceeds the effective tile size and N fits the B-cache.");
        end

        if (GEMM_ENABLE_N_TILING) begin
            $display("# [GEMM_TOP_CFG] NOTE: GEMM_ENABLE_N_TILING=1 enables the P11D output-column N-tile scheduler when N exceeds the effective tile size.");
        end

        if (GEMM_ENABLE_M_TILING) begin
            $display("# [GEMM_TOP_CFG] NOTE: GEMM_ENABLE_M_TILING=1 enables the P12D cache-backed multi-row tile scheduler when M exceeds the effective tile size.");
        end
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

    logic signed [A_DATA_WIDTH-1:0] a2_val_q, a2_val_d;
    logic signed [B_DATA_WIDTH-1:0] b2_val_q, b2_val_d;
    logic                           lane2_valid_q, lane2_valid_d;

    logic signed [A_DATA_WIDTH-1:0] a3_val_q, a3_val_d;
    logic signed [B_DATA_WIDTH-1:0] b3_val_q, b3_val_d;
    logic                           lane3_valid_q, lane3_valid_d;

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

    // P7 packed A-row preload state.
    // Used only when GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1 and
    // conservative alignment/dimension requirements are met.
    logic [DIM_WIDTH-1:0]           arow_pack_k_q, arow_pack_k_d;

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

    logic                           packed_a_row_preload_active_job_q;
    logic                           packed_a_row_preload_active_job_d;

    // P10D row-accumulator K-tiling state.
    // ktile_base_q is the global K index of the active tile.
    // ktile_len_q is the number of valid K entries in the active tile.
    logic                           k_tiling_active_job_q;
    logic                           k_tiling_active_job_d;
    logic [DIM_WIDTH-1:0]           ktile_base_q, ktile_base_d;
    logic [DIM_WIDTH-1:0]           ktile_len_q, ktile_len_d;

    // P11D output-column N-tiling state.
    // ntile_base_q is the global N index of the active output-column tile.
    // ntile_len_q is the number of valid N entries in the active tile.
    logic                           n_tiling_active_job_q;
    logic                           n_tiling_active_job_d;
    logic [DIM_WIDTH-1:0]           ntile_base_q, ntile_base_d;
    logic [DIM_WIDTH-1:0]           ntile_len_q, ntile_len_d;

    // P12D multi-row M-tiling state.
    // mtile_base_q is the global M index of the active output-row tile.
    // mtile_len_q is the number of valid M rows in the active tile.
    // mtile_row_q is the local row index inside the active M tile.
    logic                           m_tiling_active_job_q;
    logic                           m_tiling_active_job_d;
    logic [DIM_WIDTH-1:0]           mtile_base_q, mtile_base_d;
    logic [DIM_WIDTH-1:0]           mtile_len_q, mtile_len_d;
    logic [DIM_WIDTH-1:0]           mtile_row_q, mtile_row_d;

    logic                           tile_schedule_active_job;

    logic signed [ACC_WIDTH-1:0]    c_row_accum_q [0:GEMM_B_CACHE_MAX_N-1];
    logic signed [ACC_WIDTH-1:0]    c_row_accum_d [0:GEMM_B_CACHE_MAX_N-1];

    // P12D local M-tile accumulator storage.
    // Each row in the active M tile owns one N-tile row-accumulator vector.
    logic signed [ACC_WIDTH-1:0]    c_tile_accum_q [0:GEMM_M_TILE_SIZE-1][0:GEMM_B_CACHE_MAX_N-1];
    logic signed [ACC_WIDTH-1:0]    c_tile_accum_d [0:GEMM_M_TILE_SIZE-1][0:GEMM_B_CACHE_MAX_N-1];

    logic b_cache_dim_supported;
    logic b_cache_active_calc;
    logic packed_bcache_preload_calc;

    logic a_row_cache_dim_supported;
    logic a_row_cache_active_calc;
    logic packed_a_row_preload_calc;

    logic k_tiling_dim_supported;
    logic k_tiling_active_calc;

    logic n_tiling_dim_supported;
    logic n_tiling_active_calc;

    logic m_tiling_dim_supported;
    logic m_tiling_active_calc;

    logic tile_schedule_active_calc;

    logic [ADDR_WIDTH-1:0] bcache_total_bytes_calc;
    logic [ADDR_WIDTH-1:0] bpack_last_byte_addr_calc;
    logic [ADDR_WIDTH-1:0] bpack_start_addr_calc;
    logic [ADDR_WIDTH-1:0] bpack_end_addr_calc;

    function automatic logic [DIM_WIDTH-1:0] calc_ktile_len(
        input logic [DIM_WIDTH-1:0] base_k
    );
        int unsigned remaining;
        int unsigned tile_limit;
    begin
        tile_limit = GEMM_K_TILE_SIZE_EFFECTIVE;

        if (int'(dim_k) > int'(base_k)) begin
            remaining = int'(dim_k) - int'(base_k);
        end
        else begin
            remaining = 0;
        end

        if (remaining > tile_limit) begin
            calc_ktile_len = DIM_WIDTH'(tile_limit);
        end
        else begin
            calc_ktile_len = DIM_WIDTH'(remaining);
        end
    end
    endfunction

    function automatic logic [DIM_WIDTH-1:0] calc_ntile_len(
        input logic [DIM_WIDTH-1:0] base_n
    );
        int unsigned remaining;
        int unsigned tile_limit;
    begin
        tile_limit = GEMM_N_TILE_SIZE_EFFECTIVE;

        if (int'(dim_n) > int'(base_n)) begin
            remaining = int'(dim_n) - int'(base_n);
        end
        else begin
            remaining = 0;
        end

        if (remaining > tile_limit) begin
            calc_ntile_len = DIM_WIDTH'(tile_limit);
        end
        else begin
            calc_ntile_len = DIM_WIDTH'(remaining);
        end
    end
    endfunction

    function automatic logic [DIM_WIDTH-1:0] calc_mtile_len(
        input logic [DIM_WIDTH-1:0] base_m
    );
        int unsigned remaining;
        int unsigned tile_limit;
    begin
        tile_limit = GEMM_M_TILE_SIZE_EFFECTIVE;

        if (int'(dim_m) > int'(base_m)) begin
            remaining = int'(dim_m) - int'(base_m);
        end
        else begin
            remaining = 0;
        end

        if (remaining > tile_limit) begin
            calc_mtile_len = DIM_WIDTH'(tile_limit);
        end
        else begin
            calc_mtile_len = DIM_WIDTH'(remaining);
        end
    end
    endfunction

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

        // First P7 policy:
        // - packed A-row preload is optional and default-off
        // - packed A-row preload requires A-row cache to be active
        // - packed A-row preload only supports int8 A elements
        // - packed A-row preload requires base_addr_a to be 4-byte aligned
        // - packed A-row preload requires dim_k to be a multiple of 4
        // - unsupported cases automatically fall back to the P6 scalar A-row preload path
        packed_a_row_preload_calc =
            a_row_cache_active_calc &&
            GEMM_ENABLE_PACKED_A_ROW_PRELOAD &&
            (A_BYTES == 1) &&
            (base_addr_a[1:0] == 2'b00) &&
            (dim_k[1:0] == 2'b00);

        // P10D K-tiling policy:
        // - K-tiling is default-off and only activates when K exceeds the
        //   effective cache tile capacity.
        // - The first tiled path is cache-backed and row-accumulator based.
        // - Packed preloads may still be enabled for non-tiled P9/P10C cases,
        //   but the tiled path uses scalar tile preload for robust
        //   tail/alignment behavior.
        k_tiling_dim_supported =
            (dim_k != '0) &&
            (dim_n != '0) &&
            (int'(dim_k) > GEMM_K_TILE_SIZE_EFFECTIVE) &&
            (int'(dim_n) <= GEMM_B_CACHE_MAX_N) &&
            (GEMM_K_TILE_SIZE_EFFECTIVE <= GEMM_B_CACHE_MAX_K) &&
            (GEMM_K_TILE_SIZE_EFFECTIVE <= GEMM_A_ROW_CACHE_MAX_K);

        k_tiling_active_calc =
            GEMM_ENABLE_K_TILING &&
            GEMM_ENABLE_B_CACHE &&
            GEMM_ENABLE_A_ROW_CACHE &&
            (GEMM_MAC_LANES_EFFECTIVE == 4) &&
            (A_BYTES == 1) &&
            (B_BYTES == 1) &&
            k_tiling_dim_supported;

        // P11D N-tiling policy:
        // - N-tiling is default-off and only activates when N exceeds the
        //   effective output-column tile capacity.
        // - The first N-tiled path reuses the P10 row-accumulator scheduler.
        // - If K also exceeds the effective K tile size, GEMM_ENABLE_K_TILING
        //   must be enabled so K is tiled inside each N tile.
        // - Packed B/A preloads are intentionally bypassed for tiled jobs.
        n_tiling_dim_supported =
            (dim_k != '0) &&
            (dim_n != '0) &&
            (int'(dim_n) > GEMM_N_TILE_SIZE_EFFECTIVE) &&
            (GEMM_N_TILE_SIZE_EFFECTIVE <= GEMM_B_CACHE_MAX_N) &&
            (GEMM_K_TILE_SIZE_EFFECTIVE <= GEMM_B_CACHE_MAX_K) &&
            (GEMM_K_TILE_SIZE_EFFECTIVE <= GEMM_A_ROW_CACHE_MAX_K) &&
            ((int'(dim_k) <= GEMM_K_TILE_SIZE_EFFECTIVE) || GEMM_ENABLE_K_TILING);

        n_tiling_active_calc =
            GEMM_ENABLE_N_TILING &&
            GEMM_ENABLE_B_CACHE &&
            GEMM_ENABLE_A_ROW_CACHE &&
            (GEMM_MAC_LANES_EFFECTIVE == 4) &&
            (A_BYTES == 1) &&
            (B_BYTES == 1) &&
            n_tiling_dim_supported;

        // P12D M-tiling policy:
        // - M-tiling is default-off and only activates when M exceeds the
        //   effective output-row tile size.
        // - The first multi-row path is cache-backed and reuses one B tile
        //   across all rows in the active M tile.
        // - If K/N exceed their effective tile sizes, the P10/P11 K/N tile
        //   schedulers must also be enabled.
        // - Packed preloads are intentionally bypassed for tiled jobs.
        m_tiling_dim_supported =
            (dim_m != '0) &&
            (dim_k != '0) &&
            (dim_n != '0) &&
            (int'(dim_m) > GEMM_M_TILE_SIZE_EFFECTIVE) &&
            (GEMM_M_TILE_SIZE_EFFECTIVE > 0) &&
            (GEMM_N_TILE_SIZE_EFFECTIVE <= GEMM_B_CACHE_MAX_N) &&
            (GEMM_K_TILE_SIZE_EFFECTIVE <= GEMM_B_CACHE_MAX_K) &&
            (GEMM_K_TILE_SIZE_EFFECTIVE <= GEMM_A_ROW_CACHE_MAX_K) &&
            ((int'(dim_n) <= GEMM_N_TILE_SIZE_EFFECTIVE) || GEMM_ENABLE_N_TILING) &&
            ((int'(dim_k) <= GEMM_K_TILE_SIZE_EFFECTIVE) || GEMM_ENABLE_K_TILING);

        m_tiling_active_calc =
            GEMM_ENABLE_M_TILING &&
            GEMM_ENABLE_B_CACHE &&
            GEMM_ENABLE_A_ROW_CACHE &&
            (GEMM_MAC_LANES_EFFECTIVE == 4) &&
            (A_BYTES == 1) &&
            (B_BYTES == 1) &&
            m_tiling_dim_supported;

        tile_schedule_active_calc =
            k_tiling_active_calc ||
            n_tiling_active_calc ||
            m_tiling_active_calc;
    end

    logic [ADDR_WIDTH-1:0] bcache_tile_base_addr_calc;
    logic [DIM_WIDTH-1:0]    active_k_limit_calc;
    logic [DIM_WIDTH:0]      active_k_limit_ext;
    logic [DIM_WIDTH-1:0]    active_n_limit_calc;
    logic [DIM_WIDTH:0]      active_n_limit_ext;

    assign tile_schedule_active_job =
        k_tiling_active_job_q ||
        n_tiling_active_job_q ||
        m_tiling_active_job_q;

    assign active_k_limit_calc =
        tile_schedule_active_job ? ktile_len_q : dim_k;

    assign active_k_limit_ext = {1'b0, active_k_limit_calc};

    assign active_n_limit_calc =
        n_tiling_active_job_q ? ntile_len_q : dim_n;

    assign active_n_limit_ext = {1'b0, active_n_limit_calc};

    assign bcache_tile_base_addr_calc =
        base_addr_b + ((ktile_base_q * dim_n) + ntile_base_q) * B_BYTES;

    assign bcache_total_bytes_calc =
        int'(active_k_limit_calc) * int'(active_n_limit_calc) * B_BYTES;

    assign bpack_start_addr_calc =
        {bcache_tile_base_addr_calc[ADDR_WIDTH-1:2], 2'b00};

    assign bpack_last_byte_addr_calc =
        bcache_tile_base_addr_calc + bcache_total_bytes_calc - 1'b1;

    assign bpack_end_addr_calc =
        {bpack_last_byte_addr_calc[ADDR_WIDTH-1:2], 2'b00};

    logic [DIM_WIDTH:0]             k_idx_ext;
    logic [DIM_WIDTH:0]             dim_m_ext;
    logic [DIM_WIDTH:0]             dim_k_ext;
    logic [DIM_WIDTH:0]             dim_n_ext;
    logic [DIM_WIDTH:0]             k_idx_plus1_ext;
    logic [DIM_WIDTH:0]             k_idx_plus2_ext;
    logic [DIM_WIDTH:0]             k_idx_plus3_ext;
    logic [DIM_WIDTH:0]             k_idx_plus4_ext;

    logic [DIM_WIDTH-1:0]           k_idx_plus1;
    logic [DIM_WIDTH-1:0]           k_idx_plus2;
    logic [DIM_WIDTH-1:0]           k_idx_plus3;

    logic [2:0]                     active_mac_lanes_calc;
    logic                           lane1_valid_calc;
    logic                           lane2_valid_calc;
    logic                           lane3_valid_calc;
    logic                           lane2_last_k_group;
    logic                           lane4_last_k_group;

    assign k_idx_ext       = {1'b0, k_idx_q};
    assign dim_m_ext       = {1'b0, dim_m};
    assign dim_k_ext       = {1'b0, dim_k};
    assign dim_n_ext       = {1'b0, dim_n};
    assign k_idx_plus1_ext = k_idx_ext + 1;
    assign k_idx_plus2_ext = k_idx_ext + 2;
    assign k_idx_plus3_ext = k_idx_ext + 3;
    assign k_idx_plus4_ext = k_idx_ext + 4;
    assign k_idx_plus1     = k_idx_plus1_ext[DIM_WIDTH-1:0];
    assign k_idx_plus2     = k_idx_plus2_ext[DIM_WIDTH-1:0];
    assign k_idx_plus3     = k_idx_plus3_ext[DIM_WIDTH-1:0];

    // P8C runtime lane selection.
    // True 4-lane compute is cache-backed in this first implementation.
    always_comb begin
        if ((GEMM_MAC_LANES_EFFECTIVE == 4) &&
            a_row_cache_active_job_q &&
            b_cache_active_job_q) begin
            active_mac_lanes_calc = 3'd4;
        end
        else if (GEMM_MAC_LANES_EFFECTIVE >= 2) begin
            active_mac_lanes_calc = 3'd2;
        end
        else begin
            active_mac_lanes_calc = 3'd1;
        end
    end

    assign lane1_valid_calc =
        (active_mac_lanes_calc >= 3'd2) &&
        (k_idx_plus1_ext < active_k_limit_ext);

    assign lane2_valid_calc =
        (active_mac_lanes_calc >= 3'd4) &&
        (k_idx_plus2_ext < active_k_limit_ext);

    assign lane3_valid_calc =
        (active_mac_lanes_calc >= 3'd4) &&
        (k_idx_plus3_ext < active_k_limit_ext);

    assign lane2_last_k_group =
        (k_idx_plus2_ext >= active_k_limit_ext);

    assign lane4_last_k_group =
        (k_idx_plus4_ext >= active_k_limit_ext);

    logic signed [ACC_WIDTH-1:0]    lane0_product;
    logic signed [ACC_WIDTH-1:0]    lane1_product;
    logic signed [ACC_WIDTH-1:0]    lane2_product;
    logic signed [ACC_WIDTH-1:0]    lane3_product;
    logic signed [ACC_WIDTH-1:0]    mac_sum;

    assign lane0_product = $signed(a_val_q)  * $signed(b_val_q);
    assign lane1_product = $signed(a1_val_q) * $signed(b1_val_q);
    assign lane2_product = $signed(a2_val_q) * $signed(b2_val_q);
    assign lane3_product = $signed(a3_val_q) * $signed(b3_val_q);

    always_comb begin
        mac_sum = lane0_product;

        if (lane1_valid_q) begin
            mac_sum = mac_sum + lane1_product;
        end

        if (lane2_valid_q) begin
            mac_sum = mac_sum + lane2_product;
        end

        if (lane3_valid_q) begin
            mac_sum = mac_sum + lane3_product;
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
            ? (32'd1 +
               (lane1_valid_q ? 32'd1 : 32'd0) +
               (lane2_valid_q ? 32'd1 : 32'd0) +
               (lane3_valid_q ? 32'd1 : 32'd0))
            : 32'd0;

    // Count one output only when the C write has completed.
    assign output_commit =
        ((state_q == S_WAIT_C_WRITE) ||
         (state_q == S_KTILE_WAIT_ROW_WRITE)) &&
        mem_wr_done;

    logic [ADDR_WIDTH-1:0] a_addr_calc;
    logic [ADDR_WIDTH-1:0] arow_addr_calc;
    logic [ADDR_WIDTH-1:0] arow_pack_addr_calc;
    logic [ADDR_WIDTH-1:0] b_addr_calc;
    logic [ADDR_WIDTH-1:0] a1_addr_calc;
    logic [ADDR_WIDTH-1:0] b1_addr_calc;
    logic [ADDR_WIDTH-1:0] c_addr_calc;

    logic [ADDR_WIDTH-1:0] bcache_b_addr_calc;
    logic                  bcache_last_n;
    logic                  bcache_last_elem;
    logic                  arow_last_k;
    logic                  arow_pack_last_k;
    logic                  ktile_last_tile;
    logic                  ntile_last_tile;
    logic                  mtile_last_tile;
    logic                  mtile_last_row;

    logic [DIM_WIDTH:0]    arow_pack_k_plus4_ext;
    logic [DIM_WIDTH:0]    ktile_base_ext;
    logic [DIM_WIDTH:0]    ktile_len_ext;
    logic [DIM_WIDTH:0]    ktile_next_base_ext;
    logic [DIM_WIDTH:0]    ntile_base_ext;
    logic [DIM_WIDTH:0]    ntile_len_ext;
    logic [DIM_WIDTH:0]    ntile_next_base_ext;
    logic [DIM_WIDTH:0]    mtile_base_ext;
    logic [DIM_WIDTH:0]    mtile_len_ext;
    logic [DIM_WIDTH:0]    mtile_next_base_ext;
    logic [DIM_WIDTH:0]    mtile_row_ext;
    logic [DIM_WIDTH:0]    mtile_row_next_ext;

    logic [DIM_WIDTH-1:0]  global_k_idx;
    logic [DIM_WIDTH-1:0]  global_k_idx_plus1;
    logic [DIM_WIDTH-1:0]  global_bcache_k;
    logic [DIM_WIDTH-1:0]  global_bcache_n;
    logic [DIM_WIDTH-1:0]  global_arow_k;
    logic [DIM_WIDTH-1:0]  global_arow_pack_k;
    logic [DIM_WIDTH-1:0]  global_n_idx;

    assign global_k_idx =
        tile_schedule_active_job ? (ktile_base_q + k_idx_q) : k_idx_q;

    assign global_k_idx_plus1 =
        tile_schedule_active_job ? (ktile_base_q + k_idx_plus1) : k_idx_plus1;

    assign global_bcache_k =
        tile_schedule_active_job ? (ktile_base_q + bcache_k_q) : bcache_k_q;

    assign global_bcache_n =
        n_tiling_active_job_q ? (ntile_base_q + bcache_n_q) : bcache_n_q;

    assign global_arow_k =
        tile_schedule_active_job ? (ktile_base_q + arow_k_q) : arow_k_q;

    assign global_arow_pack_k =
        tile_schedule_active_job ? (ktile_base_q + arow_pack_k_q) : arow_pack_k_q;

    assign global_n_idx =
        n_tiling_active_job_q ? (ntile_base_q + n_idx_q) : n_idx_q;

    assign a_addr_calc =
        base_addr_a + ((m_idx_q * dim_k) + global_k_idx) * A_BYTES;

    assign arow_addr_calc =
        base_addr_a + ((m_idx_q * dim_k) + global_arow_k) * A_BYTES;

    assign arow_pack_addr_calc =
        base_addr_a + ((m_idx_q * dim_k) + global_arow_pack_k) * A_BYTES;

    assign b_addr_calc =
        base_addr_b + ((global_k_idx * dim_n) + global_n_idx) * B_BYTES;

    assign a1_addr_calc =
        base_addr_a + ((m_idx_q * dim_k) + global_k_idx_plus1) * A_BYTES;

    assign b1_addr_calc =
        base_addr_b + ((global_k_idx_plus1 * dim_n) + global_n_idx) * B_BYTES;

    assign bcache_b_addr_calc =
        base_addr_b + ((global_bcache_k * dim_n) + global_bcache_n) * B_BYTES;

    assign bcache_last_n =
        (bcache_n_q == (active_n_limit_calc - 1'b1));

    assign bcache_last_elem =
        (bcache_k_q == (active_k_limit_calc - 1'b1)) &&
        (bcache_n_q == (active_n_limit_calc - 1'b1));

    assign arow_last_k =
        (arow_k_q == (active_k_limit_calc - 1'b1));

    assign arow_pack_k_plus4_ext =
        {1'b0, arow_pack_k_q} + (DIM_WIDTH + 1)'(4);

    assign arow_pack_last_k =
        (arow_pack_k_plus4_ext >= active_k_limit_ext);

    assign ktile_base_ext      = {1'b0, ktile_base_q};
    assign ktile_len_ext       = {1'b0, ktile_len_q};
    assign ktile_next_base_ext = ktile_base_ext + ktile_len_ext;

    assign ktile_last_tile =
        (ktile_next_base_ext >= dim_k_ext);

    assign ntile_base_ext      = {1'b0, ntile_base_q};
    assign ntile_len_ext       = {1'b0, ntile_len_q};
    assign ntile_next_base_ext = ntile_base_ext + ntile_len_ext;

    assign ntile_last_tile =
        (ntile_next_base_ext >= dim_n_ext);

    assign mtile_base_ext      = {1'b0, mtile_base_q};
    assign mtile_len_ext       = {1'b0, mtile_len_q};
    assign mtile_next_base_ext = mtile_base_ext + mtile_len_ext;
    assign mtile_row_ext       = {1'b0, mtile_row_q};
    assign mtile_row_next_ext  = mtile_row_ext + 1;

    assign mtile_last_tile =
        (mtile_next_base_ext >= dim_m_ext);

    assign mtile_last_row =
        (mtile_row_next_ext >= mtile_len_ext);

    assign c_addr_calc =
        base_addr_c + ((m_idx_q * dim_n) + global_n_idx) * C_BYTES;

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
        a2_val_d      = a2_val_q;
        b2_val_d      = b2_val_q;
        lane2_valid_d = lane2_valid_q;
        a3_val_d      = a3_val_q;
        b3_val_d      = b3_val_q;
        lane3_valid_d = lane3_valid_q;

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
        arow_pack_k_d        = arow_pack_k_q;
        bcache_k_d            = bcache_k_q;
        bcache_n_d            = bcache_n_q;
        bpack_addr_d          = bpack_addr_q;
        bpack_end_addr_d      = bpack_end_addr_q;
        b_cache_active_job_d  = b_cache_active_job_q;
        a_row_cache_active_job_d = a_row_cache_active_job_q;
        packed_a_row_preload_active_job_d = packed_a_row_preload_active_job_q;
        k_tiling_active_job_d = k_tiling_active_job_q;
        ktile_base_d          = ktile_base_q;
        ktile_len_d           = ktile_len_q;
        n_tiling_active_job_d = n_tiling_active_job_q;
        ntile_base_d          = ntile_base_q;
        ntile_len_d           = ntile_len_q;
        m_tiling_active_job_d = m_tiling_active_job_q;
        mtile_base_d          = mtile_base_q;
        mtile_len_d           = mtile_len_q;
        mtile_row_d           = mtile_row_q;

        for (int cn = 0; cn < GEMM_B_CACHE_MAX_N; cn++) begin
            c_row_accum_d[cn] = c_row_accum_q[cn];
        end

        for (int mr = 0; mr < GEMM_M_TILE_SIZE; mr++) begin
            for (int cn = 0; cn < GEMM_B_CACHE_MAX_N; cn++) begin
                c_tile_accum_d[mr][cn] = c_tile_accum_q[mr][cn];
            end
        end

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
                    a2_val_d      = '0;
                    b2_val_d      = '0;
                    lane2_valid_d = 1'b0;
                    a3_val_d      = '0;
                    b3_val_d      = '0;
                    lane3_valid_d = 1'b0;

                    arow_k_d            = '0;
                    arow_pack_k_d       = '0;
                    bcache_k_d           = '0;
                    bcache_n_d           = '0;
                    bpack_addr_d         = '0;
                    bpack_end_addr_d     = '0;
                    k_tiling_active_job_d = k_tiling_active_calc;
                    n_tiling_active_job_d = n_tiling_active_calc;
                    m_tiling_active_job_d = m_tiling_active_calc;
                    ktile_base_d          = '0;
                    ktile_len_d           = tile_schedule_active_calc ? calc_ktile_len(DIM_WIDTH'(0)) : dim_k;
                    ntile_base_d          = '0;
                    ntile_len_d           = n_tiling_active_calc ? calc_ntile_len(DIM_WIDTH'(0)) : dim_n;
                    mtile_base_d          = '0;
                    mtile_len_d           = m_tiling_active_calc ? calc_mtile_len(DIM_WIDTH'(0)) : dim_m;
                    mtile_row_d           = '0;
                    b_cache_active_job_d  = b_cache_active_calc || tile_schedule_active_calc;
                    a_row_cache_active_job_d = a_row_cache_active_calc || tile_schedule_active_calc;
                    packed_a_row_preload_active_job_d = packed_a_row_preload_calc && !tile_schedule_active_calc;

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

                    for (int cn = 0; cn < GEMM_B_CACHE_MAX_N; cn++) begin
                        c_row_accum_d[cn] = '0;
                    end

                    for (int mr = 0; mr < GEMM_M_TILE_SIZE; mr++) begin
                        for (int cn = 0; cn < GEMM_B_CACHE_MAX_N; cn++) begin
                            c_tile_accum_d[mr][cn] = '0;
                        end
                    end

                    acc_d         = '0;
                    busy_d        = 1'b1;

                    if (tile_schedule_active_calc) begin
                        // P10D/P11D tiled paths use scalar tile preload in the first prototype.
                        state_d = S_BCACHE_INIT;
                    end
                    else if (b_cache_active_calc) begin
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

                        pack_linear_idx = int'(bpack_addr_q - bcache_tile_base_addr_calc) + bl;

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
            //
            // P7 packed A-row preload path
            //
            // First implementation policy:
            //   - active only when A-row cache is active
            //   - requires GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
            //   - requires int8 A elements
            //   - requires base_addr_a to be 4-byte aligned
            //   - requires dim_k to be a multiple of 4
            //   - unsupported cases fall back to the scalar P6 preload path
            // ----------------------------------------------------
            S_AROW_INIT: begin
                arow_k_d      = '0;
                arow_pack_k_d = '0;

                if (packed_a_row_preload_active_job_q) begin
                    state_d = S_AROW_PACK_INIT;
                end
                else begin
                    state_d = S_AROW_READ;
                end
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

            S_AROW_PACK_INIT: begin
                arow_pack_k_d = '0;
                state_d       = S_AROW_PACK_READ;
            end

            S_AROW_PACK_READ: begin
                mem_rd_addr_d = arow_pack_addr_calc;

                if (mem_req_ready) begin
                    mem_rd_en_d = 1'b1;
                    state_d     = S_AROW_PACK_WAIT;
                end
            end

            S_AROW_PACK_WAIT: begin
                if (mem_rd_valid) begin
                    for (int al = 0; al < 4; al++) begin
                        int unsigned arow_pack_idx;

                        arow_pack_idx = int'(arow_pack_k_q) + al;

                        if ((arow_pack_idx < int'(dim_k)) &&
                            (arow_pack_idx < GEMM_A_ROW_CACHE_MAX_K)) begin
                            a_row_cache_d[arow_pack_idx] =
                                mem_rd_data[(8 * al) +: A_DATA_WIDTH];
                        end
                    end

                    state_d = S_AROW_PACK_NEXT;
                end
            end

            S_AROW_PACK_NEXT: begin
                if (arow_pack_last_k) begin
                    arow_pack_k_d = '0;
                    state_d       = S_READ_A;
                end
                else begin
                    arow_pack_k_d = arow_pack_k_q + DIM_WIDTH'(4);
                    state_d       = S_AROW_PACK_READ;
                end
            end

            S_READ_A: begin
                if (a_row_cache_active_job_q) begin
                    a_val_d  = a_row_cache_q[int'(k_idx_q)];
                    b_val_d  = b_cache_q[int'(k_idx_q)][int'(n_idx_q)];

                    if (lane1_valid_calc) begin
                        lane1_valid_d = 1'b1;
                        a1_val_d      = a_row_cache_q[int'(k_idx_plus1)];
                        b1_val_d      = b_cache_q[int'(k_idx_plus1)][int'(n_idx_q)];
                    end
                    else begin
                        lane1_valid_d = 1'b0;
                        a1_val_d      = '0;
                        b1_val_d      = '0;
                    end

                    if (lane2_valid_calc) begin
                        lane2_valid_d = 1'b1;
                        a2_val_d      = a_row_cache_q[int'(k_idx_plus2)];
                        b2_val_d      = b_cache_q[int'(k_idx_plus2)][int'(n_idx_q)];
                    end
                    else begin
                        lane2_valid_d = 1'b0;
                        a2_val_d      = '0;
                        b2_val_d      = '0;
                    end

                    if (lane3_valid_calc) begin
                        lane3_valid_d = 1'b1;
                        a3_val_d      = a_row_cache_q[int'(k_idx_plus3)];
                        b3_val_d      = b_cache_q[int'(k_idx_plus3)][int'(n_idx_q)];
                    end
                    else begin
                        lane3_valid_d = 1'b0;
                        a3_val_d      = '0;
                        b3_val_d      = '0;
                    end

                    state_d = S_MAC;
                end
                else begin
                    lane2_valid_d = 1'b0;
                    a2_val_d      = '0;
                    b2_val_d      = '0;
                    lane3_valid_d = 1'b0;
                    a3_val_d      = '0;
                    b3_val_d      = '0;

                    mem_rd_addr_d = a_addr_calc;

                    if (mem_req_ready) begin
                        mem_rd_en_d = 1'b1;
                        state_d     = S_WAIT_A;
                    end
                end
            end

            S_WAIT_A: begin
                if (mem_rd_valid) begin
                    a_val_d       = mem_rd_data[A_DATA_WIDTH-1:0];
                    lane2_valid_d = 1'b0;
                    a2_val_d      = '0;
                    b2_val_d      = '0;
                    lane3_valid_d = 1'b0;
                    a3_val_d      = '0;
                    b3_val_d      = '0;

                    if (b_cache_active_job_q) begin
                        b_val_d = b_cache_q[int'(k_idx_q)][int'(n_idx_q)];

                        if (lane1_valid_calc) begin
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
                    b_val_d       = mem_rd_data[B_DATA_WIDTH-1:0];
                    lane2_valid_d = 1'b0;
                    a2_val_d      = '0;
                    b2_val_d      = '0;
                    lane3_valid_d = 1'b0;
                    a3_val_d      = '0;
                    b3_val_d      = '0;

                    if (lane1_valid_calc) begin
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

                if (active_mac_lanes_calc >= 3'd4) begin
                    if (lane4_last_k_group) begin
                        if (tile_schedule_active_job) begin
                            state_d = S_KTILE_ACCUM_N;
                        end
                        else begin
                            state_d = S_WRITE_C;
                        end
                    end
                    else begin
                        k_idx_d = k_idx_q + DIM_WIDTH'(4);
                        state_d = S_READ_A;
                    end
                end
                else if (active_mac_lanes_calc >= 3'd2) begin
                    if (lane2_last_k_group) begin
                        if (tile_schedule_active_job) begin
                            state_d = S_KTILE_ACCUM_N;
                        end
                        else begin
                            state_d = S_WRITE_C;
                        end
                    end
                    else begin
                        k_idx_d = k_idx_q + DIM_WIDTH'(2);
                        state_d = S_READ_A;
                    end
                end
                else begin
                    if (k_idx_q == (active_k_limit_calc - 1)) begin
                        if (tile_schedule_active_job) begin
                            state_d = S_KTILE_ACCUM_N;
                        end
                        else begin
                            state_d = S_WRITE_C;
                        end
                    end
                    else begin
                        k_idx_d = k_idx_q + 1'b1;
                        state_d = S_READ_A;
                    end
                end
            end

            // ----------------------------------------------------
            // P10D/P11D row-accumulator tiled path
            //
            // At this point acc_q contains the completed tile partial from
            // the previous S_MAC cycle.
            // Store the completed tile partial for the current local-n into
            // c_row_accum[local_n].  Final C is written only after all K
            // tiles for the active output-column tile have been accumulated.
            // ----------------------------------------------------
            S_KTILE_ACCUM_N: begin
                if (m_tiling_active_job_q) begin
                    c_tile_accum_d[int'(mtile_row_q)][int'(n_idx_q)] =
                        c_tile_accum_q[int'(mtile_row_q)][int'(n_idx_q)] + acc_q;
                end
                else begin
                    c_row_accum_d[int'(n_idx_q)] =
                        c_row_accum_q[int'(n_idx_q)] + acc_q;
                end

                acc_d         = '0;
                k_idx_d       = '0;
                a1_val_d      = '0;
                b1_val_d      = '0;
                lane1_valid_d = 1'b0;
                a2_val_d      = '0;
                b2_val_d      = '0;
                lane2_valid_d = 1'b0;
                a3_val_d      = '0;
                b3_val_d      = '0;
                lane3_valid_d = 1'b0;

                if (n_idx_q == (active_n_limit_calc - 1'b1)) begin
                    n_idx_d = '0;

                    if (m_tiling_active_job_q) begin
                        if (!mtile_last_row) begin
                            // Keep the current B tile resident and compute the
                            // next row in the active M tile.
                            mtile_row_d   = mtile_row_q + 1'b1;
                            m_idx_d       = mtile_base_q + mtile_row_next_ext[DIM_WIDTH-1:0];
                            arow_k_d      = '0;
                            arow_pack_k_d = '0;
                            state_d       = S_AROW_INIT;
                        end
                        else if (ktile_last_tile) begin
                            // All rows in the M tile have consumed the final
                            // K tile.  Write the completed MxN output tile.
                            mtile_row_d = '0;
                            m_idx_d     = mtile_base_q;
                            state_d     = S_KTILE_WRITE_ROW;
                        end
                        else begin
                            // Advance to the next K tile for the same M/N tile.
                            ktile_base_d  = ktile_base_q + ktile_len_q;
                            ktile_len_d   = calc_ktile_len(ktile_base_q + ktile_len_q);
                            mtile_row_d   = '0;
                            m_idx_d       = mtile_base_q;
                            bcache_k_d    = '0;
                            bcache_n_d    = '0;
                            arow_k_d      = '0;
                            arow_pack_k_d = '0;
                            state_d       = S_BCACHE_INIT;
                        end
                    end
                    else if (ktile_last_tile) begin
                        state_d = S_KTILE_WRITE_ROW;
                    end
                    else begin
                        ktile_base_d = ktile_base_q + ktile_len_q;
                        ktile_len_d  = calc_ktile_len(ktile_base_q + ktile_len_q);
                        bcache_k_d   = '0;
                        bcache_n_d   = '0;
                        arow_k_d     = '0;
                        arow_pack_k_d = '0;
                        state_d      = S_BCACHE_INIT;
                    end
                end
                else begin
                    n_idx_d = n_idx_q + 1'b1;
                    state_d = S_READ_A;
                end
            end

            S_KTILE_WRITE_ROW: begin
                mem_wr_addr_d = c_addr_calc;
                mem_wr_data_d = m_tiling_active_job_q ?
                    c_tile_accum_q[int'(mtile_row_q)][int'(n_idx_q)] :
                    c_row_accum_q[int'(n_idx_q)];
                mem_wr_strb_d = 4'b1111;

                if (mem_req_ready) begin
                    mem_wr_en_d = 1'b1;
                    state_d     = S_KTILE_WAIT_ROW_WRITE;
                end
            end

            S_KTILE_WAIT_ROW_WRITE: begin
                if (mem_wr_done) begin
                    if (m_tiling_active_job_q) begin
                        if (n_idx_q != (active_n_limit_calc - 1'b1)) begin
                            n_idx_d = n_idx_q + 1'b1;
                            state_d = S_KTILE_WRITE_ROW;
                        end
                        else if (!mtile_last_row) begin
                            n_idx_d     = '0;
                            mtile_row_d = mtile_row_q + 1'b1;
                            m_idx_d     = mtile_base_q + mtile_row_next_ext[DIM_WIDTH-1:0];
                            state_d     = S_KTILE_WRITE_ROW;
                        end
                        else begin
                            n_idx_d     = '0;
                            mtile_row_d = '0;
                            m_idx_d     = mtile_base_q;

                            if (n_tiling_active_job_q && !ntile_last_tile) begin
                                // Advance to the next output-column tile for
                                // the same M tile.
                                ntile_base_d = ntile_base_q + ntile_len_q;
                                ntile_len_d  = calc_ntile_len(ntile_base_q + ntile_len_q);
                                k_idx_d      = '0;
                                ktile_base_d = '0;
                                ktile_len_d  = calc_ktile_len(DIM_WIDTH'(0));
                                bcache_k_d   = '0;
                                bcache_n_d   = '0;
                                arow_k_d     = '0;
                                arow_pack_k_d = '0;

                                for (int mr = 0; mr < GEMM_M_TILE_SIZE; mr++) begin
                                    for (int cn = 0; cn < GEMM_B_CACHE_MAX_N; cn++) begin
                                        c_tile_accum_d[mr][cn] = '0;
                                    end
                                end

                                state_d = S_BCACHE_INIT;
                            end
                            else if (mtile_last_tile) begin
                                state_d = S_DONE;
                            end
                            else begin
                                // Advance to the next output-row tile.
                                mtile_base_d = mtile_base_q + mtile_len_q;
                                mtile_len_d  = calc_mtile_len(mtile_base_q + mtile_len_q);
                                m_idx_d      = mtile_base_q + mtile_len_q;
                                k_idx_d      = '0;
                                ktile_base_d = '0;
                                ktile_len_d  = calc_ktile_len(DIM_WIDTH'(0));
                                ntile_base_d = '0;
                                ntile_len_d  = n_tiling_active_job_q ? calc_ntile_len(DIM_WIDTH'(0)) : dim_n;
                                bcache_k_d   = '0;
                                bcache_n_d   = '0;
                                arow_k_d     = '0;
                                arow_pack_k_d = '0;

                                for (int mr = 0; mr < GEMM_M_TILE_SIZE; mr++) begin
                                    for (int cn = 0; cn < GEMM_B_CACHE_MAX_N; cn++) begin
                                        c_tile_accum_d[mr][cn] = '0;
                                    end
                                end

                                state_d = S_BCACHE_INIT;
                            end
                        end
                    end
                    else if (n_idx_q == (active_n_limit_calc - 1'b1)) begin
                        n_idx_d = '0;

                        if (n_tiling_active_job_q && !ntile_last_tile) begin
                            // Advance to the next output-column tile for the same row.
                            ntile_base_d = ntile_base_q + ntile_len_q;
                            ntile_len_d  = calc_ntile_len(ntile_base_q + ntile_len_q);
                            k_idx_d      = '0;
                            ktile_base_d = '0;
                            ktile_len_d  = calc_ktile_len(DIM_WIDTH'(0));
                            bcache_k_d   = '0;
                            bcache_n_d   = '0;
                            arow_k_d     = '0;
                            arow_pack_k_d = '0;

                            for (int cn = 0; cn < GEMM_B_CACHE_MAX_N; cn++) begin
                                c_row_accum_d[cn] = '0;
                            end

                            state_d = S_BCACHE_INIT;
                        end
                        else if (m_idx_q == (dim_m - 1'b1)) begin
                            state_d = S_DONE;
                        end
                        else begin
                            m_idx_d      = m_idx_q + 1'b1;
                            k_idx_d      = '0;
                            ktile_base_d = '0;
                            ktile_len_d  = calc_ktile_len(DIM_WIDTH'(0));
                            ntile_base_d = '0;
                            ntile_len_d  = n_tiling_active_job_q ? calc_ntile_len(DIM_WIDTH'(0)) : dim_n;
                            bcache_k_d   = '0;
                            bcache_n_d   = '0;
                            arow_k_d     = '0;
                            arow_pack_k_d = '0;

                            for (int cn = 0; cn < GEMM_B_CACHE_MAX_N; cn++) begin
                                c_row_accum_d[cn] = '0;
                            end

                            state_d = S_BCACHE_INIT;
                        end
                    end
                    else begin
                        n_idx_d = n_idx_q + 1'b1;
                        state_d = S_KTILE_WRITE_ROW;
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
                a2_val_d      = '0;
                b2_val_d      = '0;
                lane2_valid_d = 1'b0;
                a3_val_d      = '0;
                b3_val_d      = '0;
                lane3_valid_d = 1'b0;

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
                lane2_valid_d            = 1'b0;
                lane3_valid_d            = 1'b0;
                b_cache_active_job_d     = 1'b0;
                a_row_cache_active_job_d = 1'b0;
                packed_a_row_preload_active_job_d = 1'b0;
                k_tiling_active_job_d = 1'b0;
                ktile_base_d = '0;
                ktile_len_d  = '0;
                n_tiling_active_job_d = 1'b0;
                ntile_base_d = '0;
                ntile_len_d  = '0;
                m_tiling_active_job_d = 1'b0;
                mtile_base_d = '0;
                mtile_len_d  = '0;
                mtile_row_d  = '0;
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
            a2_val_q     <= '0;
            b2_val_q     <= '0;
            lane2_valid_q<= 1'b0;
            a3_val_q     <= '0;
            b3_val_q     <= '0;
            lane3_valid_q<= 1'b0;

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
            arow_pack_k_q       <= '0;
            bcache_k_q           <= '0;
            bcache_n_q           <= '0;
            bpack_addr_q         <= '0;
            bpack_end_addr_q     <= '0;
            b_cache_active_job_q <= 1'b0;
            a_row_cache_active_job_q <= 1'b0;
            packed_a_row_preload_active_job_q <= 1'b0;
            k_tiling_active_job_q <= 1'b0;
            ktile_base_q          <= '0;
            ktile_len_q           <= '0;
            n_tiling_active_job_q <= 1'b0;
            ntile_base_q          <= '0;
            ntile_len_q           <= '0;
            m_tiling_active_job_q <= 1'b0;
            mtile_base_q          <= '0;
            mtile_len_q           <= '0;
            mtile_row_q           <= '0;

            for (int cn = 0; cn < GEMM_B_CACHE_MAX_N; cn++) begin
                c_row_accum_q[cn] <= '0;
            end

            for (int mr = 0; mr < GEMM_M_TILE_SIZE; mr++) begin
                for (int cn = 0; cn < GEMM_B_CACHE_MAX_N; cn++) begin
                    c_tile_accum_q[mr][cn] <= '0;
                end
            end

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
            a2_val_q     <= a2_val_d;
            b2_val_q     <= b2_val_d;
            lane2_valid_q<= lane2_valid_d;
            a3_val_q     <= a3_val_d;
            b3_val_q     <= b3_val_d;
            lane3_valid_q<= lane3_valid_d;

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
            arow_pack_k_q       <= arow_pack_k_d;
            bcache_k_q           <= bcache_k_d;
            bcache_n_q           <= bcache_n_d;
            bpack_addr_q         <= bpack_addr_d;
            bpack_end_addr_q     <= bpack_end_addr_d;
            b_cache_active_job_q <= b_cache_active_job_d;
            a_row_cache_active_job_q <= a_row_cache_active_job_d;
            packed_a_row_preload_active_job_q <= packed_a_row_preload_active_job_d;
            k_tiling_active_job_q <= k_tiling_active_job_d;
            ktile_base_q          <= ktile_base_d;
            ktile_len_q           <= ktile_len_d;
            n_tiling_active_job_q <= n_tiling_active_job_d;
            ntile_base_q          <= ntile_base_d;
            ntile_len_q           <= ntile_len_d;
            m_tiling_active_job_q <= m_tiling_active_job_d;
            mtile_base_q          <= mtile_base_d;
            mtile_len_q           <= mtile_len_d;
            mtile_row_q           <= mtile_row_d;

            for (int cn = 0; cn < GEMM_B_CACHE_MAX_N; cn++) begin
                c_row_accum_q[cn] <= c_row_accum_d[cn];
            end

            for (int mr = 0; mr < GEMM_M_TILE_SIZE; mr++) begin
                for (int cn = 0; cn < GEMM_B_CACHE_MAX_N; cn++) begin
                    c_tile_accum_q[mr][cn] <= c_tile_accum_d[mr][cn];
                end
            end

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