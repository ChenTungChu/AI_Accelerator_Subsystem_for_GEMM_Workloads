// File: rtl/gemm/gemm_top.sv
`ifndef GEMM_TOP_SV
`define GEMM_TOP_SV

module gemm_top #(
    parameter int ADDR_WIDTH   = 32,
    parameter int A_DATA_WIDTH = 8,     // A/B element width
    parameter int B_DATA_WIDTH = 8,
    parameter int ACC_WIDTH    = 32,    // accumulation / C width
    parameter int DIM_WIDTH    = 8,     // M/N/K register width

    // ------------------------------------------------------------
    // GEMM MAC lane count
    //
    // P2A:
    //   Only GEMM_MAC_LANES=1 is functionally active.
    //   GEMM_MAC_LANES=2 will be enabled in the next patch.
    //
    // Default must remain 1 to preserve the existing 35/35
    // regression baseline.
    // ------------------------------------------------------------
    parameter int GEMM_MAC_LANES = 1
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
    input  logic [31:0]              mem_rd_data,   // v1: use 32-bit read data bus
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
        S_MAC,
        S_WRITE_C,
        S_NEXT,
        S_DONE
    } gemm_state_e;

    localparam int A_BYTES   = (A_DATA_WIDTH + 7) / 8;   // currently 1
    localparam int B_BYTES   = (B_DATA_WIDTH + 7) / 8;   // currently 1
    localparam int C_BYTES   = (ACC_WIDTH    + 7) / 8;   // currently 4

    // -------------------------------------------------------------------------
    // Parameter guard
    //
    // P2A only enables the parameterized baseline. The RTL behavior is still
    // the original single-lane GEMM when GEMM_MAC_LANES=1.
    //
    // GEMM_MAC_LANES=2 is reserved for the next patch.
    // -------------------------------------------------------------------------
    `ifndef SYNTHESIS
        initial begin
            if ((GEMM_MAC_LANES != 1) && (GEMM_MAC_LANES != 2)) begin
                $fatal(1,
                    "Unsupported GEMM_MAC_LANES=%0d. Supported values are 1 and 2.",
                    GEMM_MAC_LANES
                );
            end
        end
    `endif


    // -------------------------------------------------------------------------
    // Registers
    // -------------------------------------------------------------------------
    gemm_state_e                    state_q, state_d;

    logic [DIM_WIDTH-1:0]           m_idx_q, m_idx_d;
    logic [DIM_WIDTH-1:0]           n_idx_q, n_idx_d;
    logic [DIM_WIDTH-1:0]           k_idx_q, k_idx_d;

    logic signed [A_DATA_WIDTH-1:0] a_val_q, a_val_d;
    logic signed [B_DATA_WIDTH-1:0] b_val_q, b_val_d;

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
    // Performance counter helper events
    // -------------------------------------------------------------------------
    logic                           start_accept;
    logic                           mac_commit;
    logic                           output_commit;

    assign start_accept = (state_q == S_IDLE) && start;
    assign mac_commit   = (state_q == S_MAC);

    // One C output is committed when WRITE_C request is accepted.
    assign output_commit =
        (state_q == S_WRITE_C) && mem_req_ready;

    // -------------------------------------------------------------------------
    // Address helper signals
    // -------------------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] a_addr_calc;
    logic [ADDR_WIDTH-1:0] b_addr_calc;
    logic [ADDR_WIDTH-1:0] c_addr_calc;

    // A[m][k] row-major, 1 byte/element
    // addr = base_a + (m * K + k)
    assign a_addr_calc = base_addr_a + ((m_idx_q * dim_k) + k_idx_q) * A_BYTES;

    // B[k][n] row-major, 1 byte/element
    // addr = base_b + (k * N + n)
    assign b_addr_calc = base_addr_b + ((k_idx_q * dim_n) + n_idx_q) * B_BYTES;

    // C[m][n] row-major, 4 bytes/element
    // addr = base_c + (m * N + n) * 4
    assign c_addr_calc = base_addr_c + ((m_idx_q * dim_n) + n_idx_q) * C_BYTES;

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
        acc_d         = acc_q;

        busy_d        = busy;
        done_d        = 1'b0;   // done pulse style

        mem_rd_en_d   = 1'b0;
        mem_rd_addr_d = mem_rd_addr;

        mem_wr_en_d   = 1'b0;
        mem_wr_addr_d = mem_wr_addr;
        mem_wr_data_d = mem_wr_data;
        mem_wr_strb_d = 4'b0000;

        case (state_q)

            // IDLE
            S_IDLE: begin
                busy_d = 1'b0;
                if (start) begin
                    m_idx_d = '0;
                    n_idx_d = '0;
                    k_idx_d = '0;
                    acc_d   = '0;
                    busy_d  = 1'b1;
                    state_d = S_READ_A;
                end
            end

            // READ A
            // Hold here until adapter can accept the request
            S_READ_A: begin
                mem_rd_addr_d = a_addr_calc;
                if (mem_req_ready) begin
                    mem_rd_en_d = 1'b1;
                    state_d     = S_WAIT_A;
                end
            end

            // WAIT A
            S_WAIT_A: begin
                if (mem_rd_valid) begin
                    a_val_d = mem_rd_data[A_DATA_WIDTH-1:0];
                    state_d = S_READ_B;
                end
            end

            // READ B
            // Hold here until adapter can accept the request
            S_READ_B: begin
                mem_rd_addr_d = b_addr_calc;
                if (mem_req_ready) begin
                    mem_rd_en_d = 1'b1;
                    state_d     = S_WAIT_B;
                end
            end

            // WAIT B
            S_WAIT_B: begin
                if (mem_rd_valid) begin
                    b_val_d = mem_rd_data[B_DATA_WIDTH-1:0];
                    state_d = S_MAC;
                end
            end

            // MAC
            // acc += A[m][k] * B[k][n]
            S_MAC: begin
                acc_d = acc_q + (a_val_q * b_val_q);

                if (k_idx_q == (dim_k - 1)) begin
                    state_d = S_WRITE_C;
                end
                else begin
                    k_idx_d = k_idx_q + 1'b1;
                    state_d = S_READ_A;
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
                k_idx_d = '0;
                acc_d   = '0;

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
                state_d = S_IDLE;
                busy_d  = 1'b0;
                done_d  = 1'b0;
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
            acc_q        <= '0;

            busy         <= 1'b0;
            done         <= 1'b0;

            mem_rd_en    <= 1'b0;
            mem_rd_addr  <= '0;

            mem_wr_en    <= 1'b0;
            mem_wr_addr  <= '0;
            mem_wr_data  <= '0;
            mem_wr_strb  <= '0;

            gemm_perf_busy_cycles <= '0;
            gemm_perf_mac_count   <= '0;
            gemm_perf_output_count<= '0;
        end
        else begin
            state_q      <= state_d;

            m_idx_q      <= m_idx_d;
            n_idx_q      <= n_idx_d;
            k_idx_q      <= k_idx_d;

            a_val_q      <= a_val_d;
            b_val_q      <= b_val_d;
            acc_q        <= acc_d;

            busy         <= busy_d;
            done         <= done_d;

            mem_rd_en    <= mem_rd_en_d;
            mem_rd_addr  <= mem_rd_addr_d;

            mem_wr_en    <= mem_wr_en_d;
            mem_wr_addr  <= mem_wr_addr_d;
            mem_wr_data  <= mem_wr_data_d;
            mem_wr_strb  <= mem_wr_strb_d;

            // -------------------------------------------------------------
            // Passive performance counters
            //
            // Clear when a new job is accepted. This gives each job its own
            // snapshot. After done, values remain stable until the next job.
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
                    gemm_perf_mac_count <= gemm_perf_mac_count + 32'd1;
                end

                if (output_commit) begin
                    gemm_perf_output_count <= gemm_perf_output_count + 32'd1;
                end
            end
        end
    end

endmodule

`endif