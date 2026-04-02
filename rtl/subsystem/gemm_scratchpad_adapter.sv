// File: rtl/subsystem/gemm_scratchpad_adapter.sv
`ifndef GEMM_SCRATCHPAD_ADAPTER_SV
`define GEMM_SCRATCHPAD_ADAPTER_SV

module gemm_scratchpad_adapter #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 4
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // ------------------------------------------------------------
    // GEMM local memory interface
    // ------------------------------------------------------------
    input  logic                  mem_rd_en,
    input  logic [ADDR_WIDTH-1:0] mem_rd_addr,
    output logic [31:0]           mem_rd_data,
    output logic                  mem_rd_valid,

    input  logic                  mem_wr_en,
    input  logic [ADDR_WIDTH-1:0] mem_wr_addr,
    input  logic [31:0]           mem_wr_data,
    input  logic [3:0]            mem_wr_strb,

    // NEW:
    // Adapter accepts a new local request only when idle
    output logic                  mem_req_ready,

    // ------------------------------------------------------------
    // Adapter status
    // ------------------------------------------------------------
    output logic                  busy,
    output logic                  done,

    // ------------------------------------------------------------
    // Scratchpad AXI-MM interface
    // Adapter acts as AXI master
    // ------------------------------------------------------------
    axi_mm_if.mp_master           axi_if
);

    // ============================================================
    // Local parameters
    // ============================================================
    localparam int BYTE_PER_WORD = DATA_WIDTH / 8;
    localparam int WORD_LSB_W    = (BYTE_PER_WORD > 1) ? $clog2(BYTE_PER_WORD) : 1;
    localparam int AXI_SIZE      = (BYTE_PER_WORD > 1) ? $clog2(BYTE_PER_WORD) : 0;

    typedef enum logic [2:0] {
        S_IDLE,
        S_RD_ADDR,
        S_RD_DATA,
        S_RD_RETURN,
        S_WR_ADDR,
        S_WR_DATA,
        S_WR_RESP,
        S_DONE
    } state_e;

    // ============================================================
    // State / request holding
    // ============================================================
    state_e                       state_q, state_d;

    logic                         req_is_read_q, req_is_read_d;
    logic [ADDR_WIDTH-1:0]        req_addr_q, req_addr_d;
    logic [31:0]                  req_wr_data_q, req_wr_data_d;
    logic [3:0]                   req_wr_strb_q, req_wr_strb_d;

    logic [DATA_WIDTH-1:0]        rdata_word_q, rdata_word_d;

    logic                         busy_d, done_d;
    logic [31:0]                  mem_rd_data_d;
    logic                         mem_rd_valid_d;

    // ============================================================
    // Address / byte-lane helpers
    // ============================================================
    logic [WORD_LSB_W-1:0]        byte_offset;
    logic [ADDR_WIDTH-1:0]        aligned_addr;

    logic [DATA_WIDTH-1:0]        shifted_wdata;
    logic [BYTE_PER_WORD-1:0]     shifted_wstrb;

    logic [7:0]                   extracted_byte;

    assign byte_offset  = req_addr_q[WORD_LSB_W-1:0];
    assign aligned_addr = {req_addr_q[ADDR_WIDTH-1:WORD_LSB_W], {WORD_LSB_W{1'b0}}};

    assign shifted_wdata = {{(DATA_WIDTH-32){1'b0}}, req_wr_data_q} << (byte_offset * 8);
    assign shifted_wstrb = {{(BYTE_PER_WORD-4){1'b0}}, req_wr_strb_q} << byte_offset;

    assign extracted_byte = rdata_word_q >> (byte_offset * 8);

    // Adapter can accept a new request only when idle
    assign mem_req_ready = (state_q == S_IDLE);

    // ============================================================
    // Combinational FSM / outputs
    // ============================================================
    always @* begin
        // --------------------------------------------------------
        // defaults
        // --------------------------------------------------------
        state_d        = state_q;

        req_is_read_d  = req_is_read_q;
        req_addr_d     = req_addr_q;
        req_wr_data_d  = req_wr_data_q;
        req_wr_strb_d  = req_wr_strb_q;
        rdata_word_d   = rdata_word_q;

        busy_d         = busy;
        done_d         = 1'b0;

        mem_rd_data_d  = mem_rd_data;
        mem_rd_valid_d = 1'b0;

        // --------------------------------------------------------
        // AXI defaults
        // --------------------------------------------------------
        axi_if.awid    = '0;
        axi_if.awaddr  = aligned_addr;
        axi_if.awlen   = 8'd0;      // single beat
        axi_if.awsize  = AXI_SIZE[2:0];
        axi_if.awburst = 2'b01;     // INCR
        axi_if.awvalid = 1'b0;

        axi_if.wdata   = shifted_wdata;
        axi_if.wstrb   = shifted_wstrb;
        axi_if.wlast   = 1'b1;
        axi_if.wvalid  = 1'b0;

        axi_if.bready  = 1'b0;

        axi_if.arid    = '0;
        axi_if.araddr  = aligned_addr;
        axi_if.arlen   = 8'd0;      // single beat
        axi_if.arsize  = AXI_SIZE[2:0];
        axi_if.arburst = 2'b01;     // INCR
        axi_if.arvalid = 1'b0;

        axi_if.rready  = 1'b0;

        case (state_q)

            // ====================================================
            // IDLE
            // Priority: read first if both come together
            // Accept one new request only in this state
            // ====================================================
            S_IDLE: begin
                busy_d = 1'b0;

                if (mem_rd_en) begin
                    req_is_read_d  = 1'b1;
                    req_addr_d     = mem_rd_addr;
                    req_wr_data_d  = '0;
                    req_wr_strb_d  = '0;
                    rdata_word_d   = '0;
                    busy_d         = 1'b1;
                    state_d        = S_RD_ADDR;
                end
                else if (mem_wr_en) begin
                    req_is_read_d  = 1'b0;
                    req_addr_d     = mem_wr_addr;
                    req_wr_data_d  = mem_wr_data;
                    req_wr_strb_d  = mem_wr_strb;
                    rdata_word_d   = '0;
                    busy_d         = 1'b1;
                    state_d        = S_WR_ADDR;
                end
            end

            // ====================================================
            // READ: send AR
            // ====================================================
            S_RD_ADDR: begin
                axi_if.arvalid = 1'b1;
                if (axi_if.arready) begin
                    state_d = S_RD_DATA;
                end
            end

            // ====================================================
            // READ: wait R
            // ====================================================
            S_RD_DATA: begin
                axi_if.rready = 1'b1;
                if (axi_if.rvalid) begin
                    rdata_word_d = axi_if.rdata;
                    state_d      = S_RD_RETURN;
                end
            end

            // ====================================================
            // Return selected byte in mem_rd_data[7:0]
            // ====================================================
            S_RD_RETURN: begin
                mem_rd_data_d  = {24'd0, extracted_byte};
                mem_rd_valid_d = 1'b1;
                state_d        = S_DONE;
            end

            // ====================================================
            // WRITE: send AW
            // ====================================================
            S_WR_ADDR: begin
                axi_if.awvalid = 1'b1;
                if (axi_if.awready) begin
                    state_d = S_WR_DATA;
                end
            end

            // ====================================================
            // WRITE: send W
            // ====================================================
            S_WR_DATA: begin
                axi_if.wvalid = 1'b1;
                if (axi_if.wready) begin
                    state_d = S_WR_RESP;
                end
            end

            // ====================================================
            // WRITE: wait B
            // ====================================================
            S_WR_RESP: begin
                axi_if.bready = 1'b1;
                if (axi_if.bvalid) begin
                    state_d = S_DONE;
                end
            end

            // ====================================================
            // DONE pulse
            // ====================================================
            S_DONE: begin
                busy_d  = 1'b0;
                done_d  = 1'b1;
                state_d = S_IDLE;
            end

            default: begin
                state_d = S_IDLE;
                busy_d  = 1'b0;
                done_d  = 1'b0;
            end
        endcase
    end

    // ============================================================
    // Sequential
    // ============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q       <= S_IDLE;

            req_is_read_q <= 1'b0;
            req_addr_q    <= '0;
            req_wr_data_q <= '0;
            req_wr_strb_q <= '0;
            rdata_word_q  <= '0;

            busy          <= 1'b0;
            done          <= 1'b0;

            mem_rd_data   <= '0;
            mem_rd_valid  <= 1'b0;
        end
        else begin
            state_q       <= state_d;

            req_is_read_q <= req_is_read_d;
            req_addr_q    <= req_addr_d;
            req_wr_data_q <= req_wr_data_d;
            req_wr_strb_q <= req_wr_strb_d;
            rdata_word_q  <= rdata_word_d;

            busy          <= busy_d;
            done          <= done_d;

            mem_rd_data   <= mem_rd_data_d;
            mem_rd_valid  <= mem_rd_valid_d;
        end
    end

endmodule

`endif