// File: rtl/subsystem/axis_async_fifo.sv

`ifndef AXIS_ASYNC_FIFO_SV
`define AXIS_ASYNC_FIFO_SV

module axis_async_fifo #(
    parameter int DATA_WIDTH      = 64,
    parameter int FIFO_DEPTH      = 16,
    parameter int FIFO_ADDR_WIDTH = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH)
)(
    // ------------------------------------------------------------
    // Source / write-side clock domain
    //
    // Expected owner:
    //   dma_clk domain
    // ------------------------------------------------------------
    input  logic                     s_axis_aclk,
    input  logic                     s_axis_aresetn,

    input  logic [DATA_WIDTH-1:0]    s_axis_tdata,
    input  logic                     s_axis_tvalid,
    output logic                     s_axis_tready,
    input  logic                     s_axis_tlast,

    // ------------------------------------------------------------
    // Destination / read-side clock domain
    //
    // Expected owner:
    //   core_clk domain
    // ------------------------------------------------------------
    input  logic                     m_axis_aclk,
    input  logic                     m_axis_aresetn,

    output logic [DATA_WIDTH-1:0]    m_axis_tdata,
    output logic                     m_axis_tvalid,
    input  logic                     m_axis_tready,
    output logic                     m_axis_tlast,

    // ------------------------------------------------------------
    // Status / debug
    //
    // Notes:
    //   s_axis_* status is synchronous to s_axis_aclk.
    //   m_axis_* status is synchronous to m_axis_aclk.
    // ------------------------------------------------------------
    output logic                     s_axis_full,
    output logic [FIFO_ADDR_WIDTH:0] s_axis_wr_level,
    output logic                     s_axis_accept_pulse,

    output logic                     m_axis_empty,
    output logic [FIFO_ADDR_WIDTH:0] m_axis_rd_level,
    output logic                     m_axis_accept_pulse
);

    localparam int PAYLOAD_WIDTH = DATA_WIDTH + 1;
    localparam int PTR_WIDTH     = FIFO_ADDR_WIDTH + 1;

    // ------------------------------------------------------------
    // FIFO storage
    //
    // Payload format:
    //   {tlast, tdata}
    // ------------------------------------------------------------
    logic [PAYLOAD_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    // ------------------------------------------------------------
    // Write-domain pointers
    // ------------------------------------------------------------
    logic [PTR_WIDTH-1:0] wr_bin_q;
    logic [PTR_WIDTH-1:0] wr_bin_n;

    logic [PTR_WIDTH-1:0] wr_gray_q;
    logic [PTR_WIDTH-1:0] wr_gray_n;

    logic                 wr_full_q;
    logic                 wr_full_n;

    // Read pointer synchronized into write domain
    logic [PTR_WIDTH-1:0] rd_gray_sync_w1;
    logic [PTR_WIDTH-1:0] rd_gray_sync_w2;
    logic [PTR_WIDTH-1:0] rd_gray_sync_w2_inv;
    logic [PTR_WIDTH-1:0] rd_bin_sync_w;

    // ------------------------------------------------------------
    // Read-domain pointers
    // ------------------------------------------------------------
    logic [PTR_WIDTH-1:0] rd_bin_q;
    logic [PTR_WIDTH-1:0] rd_bin_n;

    logic [PTR_WIDTH-1:0] rd_gray_q;
    logic [PTR_WIDTH-1:0] rd_gray_n;

    logic                 rd_empty_q;
    logic                 rd_empty_n;

    // Write pointer synchronized into read domain
    logic [PTR_WIDTH-1:0] wr_gray_sync_r1;
    logic [PTR_WIDTH-1:0] wr_gray_sync_r2;
    logic [PTR_WIDTH-1:0] wr_bin_sync_r;

    // ------------------------------------------------------------
    // Handshake
    // ------------------------------------------------------------
    logic wr_fire;
    logic rd_fire;

    logic [PAYLOAD_WIDTH-1:0] rd_payload;

    // ------------------------------------------------------------
    // Utility functions
    // ------------------------------------------------------------
    function automatic bit is_power_of_two(input int value);
        return (value > 0) && ((value & (value - 1)) == 0);
    endfunction

    function automatic logic [PTR_WIDTH-1:0] bin2gray(
        input logic [PTR_WIDTH-1:0] bin
    );
        return (bin >> 1) ^ bin;
    endfunction

    function automatic logic [PTR_WIDTH-1:0] gray2bin(
        input logic [PTR_WIDTH-1:0] gray
    );
        logic [PTR_WIDTH-1:0] bin;
        int i;
    begin
        bin[PTR_WIDTH-1] = gray[PTR_WIDTH-1];

        for (i = PTR_WIDTH - 2; i >= 0; i--) begin
            bin[i] = bin[i + 1] ^ gray[i];
        end

        return bin;
    end
    endfunction

    initial begin
        if (DATA_WIDTH <= 0) begin
            $fatal(1, "axis_async_fifo: DATA_WIDTH must be > 0");
        end

        if (FIFO_DEPTH < 2) begin
            $fatal(1, "axis_async_fifo: FIFO_DEPTH must be >= 2");
        end

        if (!is_power_of_two(FIFO_DEPTH)) begin
            $fatal(1, "axis_async_fifo: FIFO_DEPTH must be a power of two");
        end

        if ((1 << FIFO_ADDR_WIDTH) != FIFO_DEPTH) begin
            $fatal(1,
                "axis_async_fifo: FIFO_ADDR_WIDTH does not match FIFO_DEPTH"
            );
        end
    end

    // ------------------------------------------------------------
    // AXI-Stream handshake
    // ------------------------------------------------------------
    always_comb begin
        s_axis_tready       = !wr_full_q;
        m_axis_tvalid       = !rd_empty_q;

        wr_fire             = s_axis_tvalid && s_axis_tready;
        rd_fire             = m_axis_tvalid && m_axis_tready;

        s_axis_full         = wr_full_q;
        m_axis_empty        = rd_empty_q;

        s_axis_accept_pulse = wr_fire;
        m_axis_accept_pulse = rd_fire;
    end

    // ------------------------------------------------------------
    // Read payload
    //
    // The output is valid only when m_axis_tvalid is high.
    // ------------------------------------------------------------
    always_comb begin
        rd_payload   = mem[rd_bin_q[FIFO_ADDR_WIDTH-1:0]];

        m_axis_tdata = rd_payload[DATA_WIDTH-1:0];
        m_axis_tlast = rd_payload[DATA_WIDTH];
    end

    // ------------------------------------------------------------
    // Write-domain next pointer / full calculation
    // ------------------------------------------------------------
    always_comb begin
        wr_bin_n = wr_bin_q;

        if (wr_fire) begin
            wr_bin_n = wr_bin_q + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
        end

        wr_gray_n = bin2gray(wr_bin_n);

        rd_gray_sync_w2_inv = rd_gray_sync_w2;
        rd_gray_sync_w2_inv[PTR_WIDTH-1] = ~rd_gray_sync_w2[PTR_WIDTH-1];
        rd_gray_sync_w2_inv[PTR_WIDTH-2] = ~rd_gray_sync_w2[PTR_WIDTH-2];

        wr_full_n = (wr_gray_n == rd_gray_sync_w2_inv);
    end

    // ------------------------------------------------------------
    // Read-domain next pointer / empty calculation
    // ------------------------------------------------------------
    always_comb begin
        rd_bin_n = rd_bin_q;

        if (rd_fire) begin
            rd_bin_n = rd_bin_q + {{(PTR_WIDTH-1){1'b0}}, 1'b1};
        end

        rd_gray_n  = bin2gray(rd_bin_n);
        rd_empty_n = (rd_gray_n == wr_gray_sync_r2);
    end

    // ------------------------------------------------------------
    // Synchronized level estimates
    //
    // These are debug/status values, not exact same-cycle global counts.
    // ------------------------------------------------------------
    always_comb begin
        rd_bin_sync_w   = gray2bin(rd_gray_sync_w2);
        wr_bin_sync_r   = gray2bin(wr_gray_sync_r2);

        s_axis_wr_level = wr_bin_q - rd_bin_sync_w;
        m_axis_rd_level = wr_bin_sync_r - rd_bin_q;
    end

    // ------------------------------------------------------------
    // Write clock domain
    // ------------------------------------------------------------
    always_ff @(posedge s_axis_aclk or negedge s_axis_aresetn) begin
        if (!s_axis_aresetn) begin
            wr_bin_q        <= '0;
            wr_gray_q       <= '0;
            wr_full_q       <= 1'b0;

            rd_gray_sync_w1 <= '0;
            rd_gray_sync_w2 <= '0;
        end
        else begin
            // Synchronize read pointer into write clock domain
            rd_gray_sync_w1 <= rd_gray_q;
            rd_gray_sync_w2 <= rd_gray_sync_w1;

            // Write payload when accepted
            if (wr_fire) begin
                mem[wr_bin_q[FIFO_ADDR_WIDTH-1:0]] <= {
                    s_axis_tlast,
                    s_axis_tdata
                };
            end

            wr_bin_q  <= wr_bin_n;
            wr_gray_q <= wr_gray_n;
            wr_full_q <= wr_full_n;
        end
    end

    // ------------------------------------------------------------
    // Read clock domain
    // ------------------------------------------------------------
    always_ff @(posedge m_axis_aclk or negedge m_axis_aresetn) begin
        if (!m_axis_aresetn) begin
            rd_bin_q        <= '0;
            rd_gray_q       <= '0;
            rd_empty_q      <= 1'b1;

            wr_gray_sync_r1 <= '0;
            wr_gray_sync_r2 <= '0;
        end
        else begin
            // Synchronize write pointer into read clock domain
            wr_gray_sync_r1 <= wr_gray_q;
            wr_gray_sync_r2 <= wr_gray_sync_r1;

            rd_bin_q   <= rd_bin_n;
            rd_gray_q  <= rd_gray_n;
            rd_empty_q <= rd_empty_n;
        end
    end

endmodule

`endif