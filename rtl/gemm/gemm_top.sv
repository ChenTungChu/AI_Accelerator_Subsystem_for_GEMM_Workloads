// File: rtl/gemm/gemm_top.sv
`ifndef GEMM_TOP_SV
`define GEMM_TOP_SV

module gemm_top #(
    parameter int ADDR_WIDTH   = 32,
    parameter int A_DATA_WIDTH = 8,     // A/B element width
    parameter int B_DATA_WIDTH = 8,
    parameter int ACC_WIDTH    = 32,    // accumulation / C width
    parameter int DIM_WIDTH    = 8,     // M/N/K register width
    parameter int GEMM_MAC_LANES = 1,   // GEMM MAC lane count

    parameter bit GEMM_ENABLE_B_CACHE = 1'b0,
    parameter int GEMM_B_CACHE_MAX_K  = 4,
    parameter int GEMM_B_CACHE_MAX_N  = 4
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // -------------------------------------------------------------------------
    // Control
    // -------------------------------------------------------------------------
    input  logic                     start,
    output logic                     busy,
    output logic                     done,

    // -------------------------------------------------------------------------
    // Configuration
    // -------------------------------------------------------------------------
    input  logic [ADDR_WIDTH-1:0]    base_addr_a,
    input  logic [ADDR_WIDTH-1:0]    base_addr_b,
    input  logic [ADDR_WIDTH-1:0]    base_addr_c,

    input  logic [DIM_WIDTH-1:0]     dim_m,
    input  logic [DIM_WIDTH-1:0]     dim_n,
    input  logic [DIM_WIDTH-1:0]     dim_k,

    // -------------------------------------------------------------------------
    // Local memory interface
    // -------------------------------------------------------------------------
    // Request can be accepted only when adapter is ready
    input  logic                     mem_req_ready,

    // Read channel
    output logic                     mem_rd_en,
    output logic [ADDR_WIDTH-1:0]    mem_rd_addr,
    input  logic [31:0]              mem_rd_data,
    input  logic                     mem_rd_valid,

    // Write channel
    output logic                     mem_wr_en,
    output logic [ADDR_WIDTH-1:0]    mem_wr_addr,
    output logic [31:0]              mem_wr_data,
    output logic [3:0]               mem_wr_strb,

    // -------------------------------------------------------------------------
    // Performance counters
    //
    // Passive debug/status only. These counters must not feed back into
    // control decisions.
    //
    // Counter clear policy:
    //   - reset
    //   - accepted start in S_IDLE
    //
    // Snapshot policy:
    //   - values remain stable after done until next accepted start
    // -------------------------------------------------------------------------
    output logic [31:0]              gemm_perf_busy_cycles,
    output logic [31:0]              gemm_perf_mac_count,
    output logic [31:0]              gemm_perf_output_count
);

    // -------------------------------------------------------------------------
    // Local parameters / typedef
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        S_IDLE,
        S_READ_A,
        S_WAIT_A,
        S_READ_B,
        S_WAIT_B,

        // 2-lane mode only:
        // lane0 uses the original A/B read states.
        // lane1 uses these additional A1/B1 states.
        S_READ_A1,
        S_WAIT_A1,
        S_READ_B1,
        S_WAIT_B1,

        S_MAC,
        S_WRITE_C,
        S_NEXT,
        S_DONE
    } gemm_state_e;

    localparam int A_BYTES = (A_DATA_WIDTH + 7) / 8;   // currently 1
    localparam int B_BYTES = (B_DATA_WIDTH + 7) / 8;   // currently 1
    localparam int C_BYTES = (ACC_WIDTH    + 7) / 8;   // currently 4

    // -------------------------------------------------------------------------
    // Parameter guard
    // -------------------------------------------------------------------------
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
    end
`endif

`ifndef SYNTHESIS
    initial begin
        $display("# [GEMM_TOP_CFG] GEMM_MAC_LANES=%0d GEMM_ENABLE_B_CACHE=%0d GEMM_B_CACHE_MAX_K=%0d GEMM_B_CACHE_MAX_N=%0d",
                 GEMM_MAC_LANES,
                 GEMM_ENABLE_B_CACHE,
                 GEMM_B_CACHE_MAX_K,
                 GEMM_B_CACHE_MAX_N);
    end
`endif

    // -------------------------------------------------------------------------
    // Registers
    // -------------------------------------------------------------------------
    gemm_state_e                    state_q, state_d;

    logic [DIM_WIDTH-1:0]           m_idx_q, m_idx_d;
    logic [DIM_WIDTH-1:0]           n_idx_q, n_idx_d;
    logic [DIM_WIDTH-1:0]           k_idx_q, k_idx_d;

    // lane0 operands
    logic signed [A_DATA_WIDTH-1:0] a_val_q, a_val_d;
    logic signed [B_DATA_WIDTH-1:0] b_val_q, b_val_d;

    // lane1 operands, only used when GEMM_MAC_LANES=2
    logic signed [A_DATA_WIDTH-1:0] a1_val_q, a1_val_d;
    logic signed [B_DATA_WIDTH-1:0] b1_val_q, b1_val_d;
    logic                           lane1_valid_q, lane1_valid_d;

    logic signed [ACC_WIDTH-1:0]    acc_q, acc_d;

    logic                           busy_d;
    logic                           done_d;

    // Read / Write outputs
    logic                           mem_rd_en_d;
    logic [ADDR_WIDTH-1:0]          mem_rd_addr_d;
    logic                           mem_wr_en_d;
    logic [ADDR_WIDTH-1:0]          mem_wr_addr_d;
    logic [31:0]                    mem_wr_data_d;
    logic [3:0]                     mem_wr_strb_d;

    // -------------------------------------------------------------------------
    // P4 B-cache storage / helper state
    //
    // P4C-1 only adds storage and preload index registers.
    // These signals are not used to alter the FSM yet.
    //
    // Later patches will use:
    //   - b_cache_active_job_q
    //   - bcache_k_q / bcache_n_q
    //   - b_cache_q[k][n]
    //
    // Current behavior remains identical when GEMM_ENABLE_B_CACHE=0.
    // -------------------------------------------------------------------------
    logic signed [B_DATA_WIDTH-1:0] b_cache_q [0:GEMM_B_CACHE_MAX_K-1][0:GEMM_B_CACHE_MAX_N-1];
    logic signed [B_DATA_WIDTH-1:0] b_cache_d [0:GEMM_B_CACHE_MAX_K-1][0:GEMM_B_CACHE_MAX_N-1];

    logic [DIM_WIDTH-1:0]           bcache_k_q, bcache_k_d;
    logic [DIM_WIDTH-1:0]           bcache_n_q, bcache_n_d;

    logic                           b_cache_active_job_q;
    logic                           b_cache_active_job_d;

    // -------------------------------------------------------------------------
    // P4 B-cache helper signals
    //
    // b_cache_dim_supported:
    //   Current first B-cache prototype only supports bounded K/N.
    //
    // b_cache_active_calc:
    //   Combinational eligibility based on current configuration.
    //
    // b_cache_active_job_q:
    //   Latched at accepted start in P4C-1, but not used to control FSM yet.
    // -------------------------------------------------------------------------
    logic b_cache_dim_supported;
    logic b_cache_active_calc;

    always_comb begin
        b_cache_dim_supported =
            (int'(dim_k) <= GEMM_B_CACHE_MAX_K) &&
            (int'(dim_n) <= GEMM_B_CACHE_MAX_N);

        b_cache_active_calc =
            GEMM_ENABLE_B_CACHE && b_cache_dim_supported;
    end

    // -------------------------------------------------------------------------
    // K helper signals
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // MAC helper signals
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // Performance counter helper events
    // -------------------------------------------------------------------------
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

    // One C output is committed when WRITE_C request is accepted.
    assign output_commit =
        (state_q == S_WRITE_C) && mem_req_ready;

    // -------------------------------------------------------------------------
    // Address helper signals
    // -------------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] a_addr_calc;
    logic [ADDR_WIDTH-1:0] b_addr_calc;
    logic [ADDR_WIDTH-1:0] a1_addr_calc;
    logic [ADDR_WIDTH-1:0] b1_addr_calc;
    logic [ADDR_WIDTH-1:0] c_addr_calc;

    // A[m][k] row-major, 1 byte/element
    // addr = base_a + (m * K + k)
    assign a_addr_calc =
        base_addr_a + ((m_idx_q * dim_k) + k_idx_q) * A_BYTES;

    // B[k][n] row-major, 1 byte/element
    // addr = base_b + (k * N + n)
    assign b_addr_calc =
        base_addr_b + ((k_idx_q * dim_n) + n_idx_q) * B_BYTES;

    // A[m][k+1], only used when lane1_valid_calc/lane1_valid_q is true
    assign a1_addr_calc =
        base_addr_a + ((m_idx_q * dim_k) + k_idx_plus1) * A_BYTES;

    // B[k+1][n], only used when lane1_valid_calc/lane1_valid_q is true
    assign b1_addr_calc =
        base_addr_b + ((k_idx_plus1 * dim_n) + n_idx_q) * B_BYTES;

    // C[m][n] row-major, 4 bytes/element
    // addr = base_c + (m * N + n) * 4
    assign c_addr_calc =
        base_addr_c + ((m_idx_q * dim_n) + n_idx_q) * C_BYTES;

    // -------------------------------------------------------------------------
    // Combinational FSM
    // -------------------------------------------------------------------------
    always_comb begin
        // Default
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
        done_d        = 1'b0;   // done pulse style

        mem_rd_en_d   = 1'b0;
        mem_rd_addr_d = mem_rd_addr;

        mem_wr_en_d   = 1'b0;
        mem_wr_addr_d = mem_wr_addr;
        mem_wr_data_d = mem_wr_data;
        mem_wr_strb_d = 4'b0000;

        bcache_k_d            = bcache_k_q;
        bcache_n_d            = bcache_n_q;
        b_cache_active_job_d  = b_cache_active_job_q;

        for (int bk = 0; bk < GEMM_B_CACHE_MAX_K; bk++) begin
            for (int bn = 0; bn < GEMM_B_CACHE_MAX_N; bn++) begin
                b_cache_d[bk][bn] = b_cache_q[bk][bn];
            end
        end        

        case (state_q)

            // IDLE
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

                    bcache_k_d           = '0;
                    bcache_n_d           = '0;
                    b_cache_active_job_d = b_cache_active_calc;                    

                    acc_d         = '0;
                    busy_d        = 1'b1;
                    state_d       = S_READ_A;
                end
            end

            // READ A lane0
            // Hold here until adapter can accept the request
            S_READ_A: begin
                mem_rd_addr_d = a_addr_calc;

                if (mem_req_ready) begin
                    mem_rd_en_d = 1'b1;
                    state_d     = S_WAIT_A;
                end
            end

            // WAIT A lane0
            S_WAIT_A: begin
                if (mem_rd_valid) begin
                    a_val_d = mem_rd_data[A_DATA_WIDTH-1:0];
                    state_d = S_READ_B;
                end
            end

            // READ B lane0
            // Hold here until adapter can accept the request
            S_READ_B: begin
                mem_rd_addr_d = b_addr_calc;

                if (mem_req_ready) begin
                    mem_rd_en_d = 1'b1;
                    state_d     = S_WAIT_B;
                end
            end

            // WAIT B lane0
            S_WAIT_B: begin
                if (mem_rd_valid) begin
                    b_val_d = mem_rd_data[B_DATA_WIDTH-1:0];

                    // In 2-lane mode, fetch lane1 only if k+1 is legal.
                    // In single-lane mode, this always goes directly to S_MAC.
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

            // READ A lane1
            // Only reached in GEMM_MAC_LANES=2 when lane1 is valid.
            S_READ_A1: begin
                mem_rd_addr_d = a1_addr_calc;

                if (mem_req_ready) begin
                    mem_rd_en_d = 1'b1;
                    state_d     = S_WAIT_A1;
                end
            end

            // WAIT A lane1
            S_WAIT_A1: begin
                if (mem_rd_valid) begin
                    a1_val_d = mem_rd_data[A_DATA_WIDTH-1:0];
                    state_d  = S_READ_B1;
                end
            end

            // READ B lane1
            S_READ_B1: begin
                mem_rd_addr_d = b1_addr_calc;

                if (mem_req_ready) begin
                    mem_rd_en_d = 1'b1;
                    state_d     = S_WAIT_B1;
                end
            end

            // WAIT B lane1
            S_WAIT_B1: begin
                if (mem_rd_valid) begin
                    b1_val_d = mem_rd_data[B_DATA_WIDTH-1:0];
                    state_d  = S_MAC;
                end
            end

            // MAC
            //
            // GEMM_MAC_LANES=1:
            //   acc += A[m][k] * B[k][n]
            //
            // GEMM_MAC_LANES=2:
            //   acc += A[m][k+0] * B[k+0][n]
            //   acc += A[m][k+1] * B[k+1][n], if lane1_valid_q
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

            // WRITE C
            // Hold here until adapter can accept the request
            S_WRITE_C: begin
                mem_wr_addr_d = c_addr_calc;
                mem_wr_data_d = acc_q;
                mem_wr_strb_d = 4'b1111;

                if (mem_req_ready) begin
                    mem_wr_en_d = 1'b1;
                    state_d     = S_NEXT;
                end
            end

            // NEXT
            // Move to next (m,n)
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
                        state_d = S_READ_A;
                    end
                end
                else begin
                    n_idx_d = n_idx_q + 1'b1;
                    state_d = S_READ_A;
                end
            end

            // DONE
            S_DONE: begin
                busy_d = 1'b0;
                done_d = 1'b1;

                // wait start deassert, avoid repeated auto-restart
                if (!start) begin
                    state_d = S_IDLE;
                end
            end

            default: begin
                state_d       = S_IDLE;
                busy_d        = 1'b0;
                done_d        = 1'b0;
                lane1_valid_d = 1'b0;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Sequential
    // -------------------------------------------------------------------------
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

            bcache_k_q           <= '0;
            bcache_n_q           <= '0;
            b_cache_active_job_q <= 1'b0;

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

            bcache_k_q           <= bcache_k_d;
            bcache_n_q           <= bcache_n_d;
            b_cache_active_job_q <= b_cache_active_job_d;

            for (int bk = 0; bk < GEMM_B_CACHE_MAX_K; bk++) begin
                for (int bn = 0; bn < GEMM_B_CACHE_MAX_N; bn++) begin
                    b_cache_q[bk][bn] <= b_cache_d[bk][bn];
                end
            end            

            // -------------------------------------------------------------
            // Passive performance counters
            //
            // Clear when a new job is accepted. This gives each job its own
            // snapshot. After done, values remain stable until the next job.
            //
            // In 2-lane mode, mac_count increments by the number of logical
            // valid MAC lanes committed in S_MAC, not merely by one S_MAC
            // state execution.
            // -------------------------------------------------------------
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