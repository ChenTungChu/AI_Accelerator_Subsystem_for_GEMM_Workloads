// File: rtl/csr/ai_accel_csr_regs.sv

`ifndef AI_ACCEL_CSR_REGS_SV
`define AI_ACCEL_CSR_REGS_SV

module ai_accel_csr_regs #(
    parameter int ADDR_WIDTH      = 32,
    parameter int GEMM_DIM_WIDTH  = 8,
    parameter int CSR_ADDR_WIDTH  = 12,
    parameter int CSR_DATA_WIDTH  = 32,

    parameter logic [31:0] CSR_VERSION_VALUE = 32'h0001_0014
)(
    input  logic clk,
    input  logic rst_n,

    axi_lite_if.slave csr_if,

    // ------------------------------------------------------------
    // GEMM control/config outputs
    // ------------------------------------------------------------
    output logic                  acc_start_pulse,
    output logic                  gemm_input_stream_mode,
    output logic                  accumulate_enable,

    output logic [ADDR_WIDTH-1:0] base_addr_a,
    output logic [ADDR_WIDTH-1:0] base_addr_b,
    output logic [ADDR_WIDTH-1:0] base_addr_c,

    output logic [GEMM_DIM_WIDTH-1:0] dim_m,
    output logic [GEMM_DIM_WIDTH-1:0] dim_n,
    output logic [GEMM_DIM_WIDTH-1:0] dim_k,

    // ------------------------------------------------------------
    // DMA load control/config outputs
    // ------------------------------------------------------------
    output logic                  dma_load_start_pulse,
    output logic [ADDR_WIDTH-1:0] dma_src_base_addr,
    output logic [ADDR_WIDTH-1:0] dma_dst_base_addr,
    output logic [31:0]           dma_load_beats,

    // ------------------------------------------------------------
    // AXI-Stream preload control/config outputs
    // ------------------------------------------------------------
    output logic                  axis_load_start_pulse,
    output logic [ADDR_WIDTH-1:0] axis_src_base_addr,
    output logic [ADDR_WIDTH-1:0] axis_dst_base_addr,
    output logic [31:0]           axis_load_beats,

    // ------------------------------------------------------------
    // Direct Stream preload control/config outputs
    // ------------------------------------------------------------
    output logic                  ds_load_start_pulse,
    output logic [ADDR_WIDTH-1:0] ds_src_base_addr,
    output logic [ADDR_WIDTH-1:0] ds_dst_base_addr,
    output logic [31:0]           ds_load_beats,
    output logic                  ds_operand_sel,

    // ------------------------------------------------------------
    // DMA store control/config outputs
    // ------------------------------------------------------------
    output logic                  dma_store_start_pulse,
    output logic [ADDR_WIDTH-1:0] dma_store_src_base_addr,
    output logic [ADDR_WIDTH-1:0] dma_store_dst_base_addr,
    output logic [31:0]           dma_store_byte_count,

    // ------------------------------------------------------------
    // Live status inputs from the existing subsystem
    // ------------------------------------------------------------
    input  logic acc_busy,
    input  logic acc_done,

    input  logic dma_load_busy,
    input  logic dma_load_done,
    input  logic dma_load_error,

    input  logic axis_load_busy,
    input  logic axis_load_done,
    input  logic axis_load_error,

    input  logic ds_load_busy,
    input  logic ds_load_done,
    input  logic ds_load_error,

    input  logic dma_store_busy,
    input  logic dma_store_done,
    input  logic dma_store_error,

    // ------------------------------------------------------------
    // GEMM performance counter inputs
    //
    // The existing subsystem keeps these values stable after GEMM
    // done until the next accepted GEMM start.  This CSR block
    // captures them into readable snapshot registers on acc_done.
    // ------------------------------------------------------------
    input  logic [31:0] gemm_perf_busy_cycles,
    input  logic [31:0] gemm_perf_mac_count,
    input  logic [31:0] gemm_perf_output_count
);

    localparam int STRB_WIDTH = CSR_DATA_WIDTH / 8;

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    // ------------------------------------------------------------
    // Register offsets
    // ------------------------------------------------------------
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_VERSION_ADDR              = 12'h000;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_COMMAND_ADDR              = 12'h004;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_STATUS_ADDR               = 12'h008;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DONE_STATUS_ADDR          = 12'h00C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_ERROR_STATUS_ADDR         = 12'h010;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_MODE_ADDR                 = 12'h014;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_CMD_REJECT_STATUS_ADDR    = 12'h018;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RESERVED_01C_ADDR         = 12'h01C;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_BASE_ADDR_A_ADDR          = 12'h020;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_BASE_ADDR_B_ADDR          = 12'h024;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_BASE_ADDR_C_ADDR          = 12'h028;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DIM_M_ADDR                = 12'h02C;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DIM_N_ADDR                = 12'h030;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DIM_K_ADDR                = 12'h034;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RESERVED_038_ADDR         = 12'h038;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RESERVED_03C_ADDR         = 12'h03C;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DMA_LOAD_SRC_BASE_ADDR    = 12'h040;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DMA_LOAD_DST_BASE_ADDR    = 12'h044;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DMA_LOAD_BEATS_ADDR       = 12'h048;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RESERVED_04C_ADDR         = 12'h04C;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_AXIS_SRC_BASE_ADDR        = 12'h050;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_AXIS_DST_BASE_ADDR        = 12'h054;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_AXIS_LOAD_BEATS_ADDR      = 12'h058;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RESERVED_05C_ADDR         = 12'h05C;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DS_SRC_BASE_ADDR          = 12'h060;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DS_DST_BASE_ADDR          = 12'h064;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DS_LOAD_BEATS_ADDR        = 12'h068;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DS_CONTROL_ADDR           = 12'h06C;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DMA_STORE_SRC_BASE_ADDR   = 12'h070;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DMA_STORE_DST_BASE_ADDR   = 12'h074;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_DMA_STORE_BYTE_COUNT_ADDR = 12'h078;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RESERVED_07C_ADDR         = 12'h07C;

    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_PERF_BUSY_CYCLES_ADDR     = 12'h080;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_PERF_MAC_COUNT_ADDR       = 12'h084;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_PERF_OUTPUT_COUNT_ADDR    = 12'h088;
    localparam logic [CSR_ADDR_WIDTH-1:0] CSR_RESERVED_08C_ADDR         = 12'h08C;

    // ------------------------------------------------------------
    // Command bits
    // ------------------------------------------------------------
    localparam int CMD_START_GEMM_BIT      = 0;
    localparam int CMD_START_DMA_LOAD_BIT  = 1;
    localparam int CMD_START_AXIS_LOAD_BIT = 2;
    localparam int CMD_START_DS_LOAD_BIT   = 3;
    localparam int CMD_START_DMA_STORE_BIT = 4;
    localparam int CMD_CLEAR_DONE_BIT      = 8;
    localparam int CMD_CLEAR_ERROR_BIT     = 9;
    localparam int CMD_CLEAR_PERF_BIT      = 10;

    localparam logic [31:0] CMD_START_MASK = 32'h0000_001F;

    // ------------------------------------------------------------
    // Sticky status bit positions
    // ------------------------------------------------------------
    localparam int DONE_GEMM_BIT      = 0;
    localparam int DONE_DMA_LOAD_BIT  = 1;
    localparam int DONE_AXIS_LOAD_BIT = 2;
    localparam int DONE_DS_LOAD_BIT   = 3;
    localparam int DONE_DMA_STORE_BIT = 4;

    localparam int ERR_DMA_LOAD_BIT   = 0;
    localparam int ERR_AXIS_LOAD_BIT  = 1;
    localparam int ERR_DS_LOAD_BIT    = 2;
    localparam int ERR_DMA_STORE_BIT  = 3;
    localparam int ERR_GEMM_RSVD_BIT  = 4;

    localparam int REJ_GEMM_BUSY_BIT      = 0;
    localparam int REJ_DMA_LOAD_BUSY_BIT  = 1;
    localparam int REJ_AXIS_BUSY_BIT      = 2;
    localparam int REJ_DS_BUSY_BIT        = 3;
    localparam int REJ_DMA_STORE_BUSY_BIT = 4;
    localparam int REJ_UNSUPPORTED_BIT    = 8;
    localparam int REJ_ZERO_LENGTH_BIT    = 9;

    // ------------------------------------------------------------
    // AXI-Lite transaction state
    // ------------------------------------------------------------
    logic [CSR_ADDR_WIDTH-1:0] awaddr_q;
    logic                      awaddr_valid_q;

    logic [31:0]               wdata_q;
    logic [STRB_WIDTH-1:0]     wstrb_q;
    logic                      wdata_valid_q;

    logic                      bvalid_q;
    logic [1:0]                bresp_q;

    logic                      rvalid_q;
    logic [31:0]               rdata_q;
    logic [1:0]                rresp_q;

    logic aw_fire;
    logic w_fire;
    logic b_fire;
    logic ar_fire;
    logic r_fire;

    logic write_apply;
    logic [CSR_ADDR_WIDTH-1:0] write_addr;
    logic [31:0]               write_data;
    logic [STRB_WIDTH-1:0]     write_strb;

    logic write_addr_valid;
    logic read_addr_valid;

    logic [31:0] read_data_comb;

    // ------------------------------------------------------------
    // CSR storage registers
    // ------------------------------------------------------------
    logic [31:0] mode_q;

    logic [31:0] base_addr_a_q;
    logic [31:0] base_addr_b_q;
    logic [31:0] base_addr_c_q;

    logic [31:0] dim_m_q;
    logic [31:0] dim_n_q;
    logic [31:0] dim_k_q;

    logic [31:0] dma_load_src_base_q;
    logic [31:0] dma_load_dst_base_q;
    logic [31:0] dma_load_beats_q;

    logic [31:0] axis_src_base_q;
    logic [31:0] axis_dst_base_q;
    logic [31:0] axis_load_beats_q;

    logic [31:0] ds_src_base_q;
    logic [31:0] ds_dst_base_q;
    logic [31:0] ds_load_beats_q;
    logic [31:0] ds_control_q;

    logic [31:0] dma_store_src_base_q;
    logic [31:0] dma_store_dst_base_q;
    logic [31:0] dma_store_byte_count_q;

    logic [31:0] done_status_q;
    logic [31:0] error_status_q;
    logic [31:0] reject_status_q;

    logic [31:0] perf_busy_cycles_q;
    logic [31:0] perf_mac_count_q;
    logic [31:0] perf_output_count_q;

    // ------------------------------------------------------------
    // Internal command decode helpers
    // ------------------------------------------------------------
    logic [31:0] command_masked;
    logic [31:0] start_bits;
    logic        command_has_active_strobe;
    logic        command_has_start;
    logic        command_multi_start;
    logic        command_unsupported_combo;

    logic [31:0] status_read_data;

    // ------------------------------------------------------------
    // Parameter sanity
    // ------------------------------------------------------------
    function automatic bit is_power_of_two(input int value);
        return (value > 0) && ((value & (value - 1)) == 0);
    endfunction

`ifndef SYNTHESIS
    initial begin
        if (CSR_DATA_WIDTH != 32) begin
            $fatal(1, "ai_accel_csr_regs: CSR_DATA_WIDTH must be 32");
        end

        if (STRB_WIDTH != 4) begin
            $fatal(1, "ai_accel_csr_regs: STRB_WIDTH must be 4");
        end

        if (CSR_ADDR_WIDTH < 12) begin
            $fatal(1, "ai_accel_csr_regs: CSR_ADDR_WIDTH must be at least 12");
        end

        if (ADDR_WIDTH > 32) begin
            $fatal(1, "ai_accel_csr_regs: ADDR_WIDTH above 32 is not supported by 32-bit CSR registers");
        end

        if (GEMM_DIM_WIDTH > 32) begin
            $fatal(1, "ai_accel_csr_regs: GEMM_DIM_WIDTH above 32 is not supported by 32-bit CSR registers");
        end

        if (!is_power_of_two(STRB_WIDTH)) begin
            $fatal(1, "ai_accel_csr_regs: STRB_WIDTH must be a power of two");
        end
    end
`endif

    // ------------------------------------------------------------
    // Byte-strobe helpers
    // ------------------------------------------------------------
    function automatic logic [31:0] strobe_to_mask(
        input logic [STRB_WIDTH-1:0] strb
    );
        logic [31:0] mask;
        int unsigned i;
    begin
        mask = 32'h0000_0000;

        for (i = 0; i < STRB_WIDTH; i++) begin
            if (strb[i]) begin
                mask[(i * 8) +: 8] = 8'hFF;
            end
        end

        return mask;
    end
    endfunction

    function automatic logic [31:0] apply_wstrb32(
        input logic [31:0]           old_value,
        input logic [31:0]           new_value,
        input logic [STRB_WIDTH-1:0] strb
    );
        logic [31:0] mask;
    begin
        mask = strobe_to_mask(strb);
        return (old_value & ~mask) | (new_value & mask);
    end
    endfunction

    function automatic bit csr_addr_is_valid(
        input logic [CSR_ADDR_WIDTH-1:0] addr
    );
    begin
        unique case (addr)
            CSR_VERSION_ADDR,
            CSR_COMMAND_ADDR,
            CSR_STATUS_ADDR,
            CSR_DONE_STATUS_ADDR,
            CSR_ERROR_STATUS_ADDR,
            CSR_MODE_ADDR,
            CSR_CMD_REJECT_STATUS_ADDR,
            CSR_RESERVED_01C_ADDR,

            CSR_BASE_ADDR_A_ADDR,
            CSR_BASE_ADDR_B_ADDR,
            CSR_BASE_ADDR_C_ADDR,
            CSR_DIM_M_ADDR,
            CSR_DIM_N_ADDR,
            CSR_DIM_K_ADDR,
            CSR_RESERVED_038_ADDR,
            CSR_RESERVED_03C_ADDR,

            CSR_DMA_LOAD_SRC_BASE_ADDR,
            CSR_DMA_LOAD_DST_BASE_ADDR,
            CSR_DMA_LOAD_BEATS_ADDR,
            CSR_RESERVED_04C_ADDR,

            CSR_AXIS_SRC_BASE_ADDR,
            CSR_AXIS_DST_BASE_ADDR,
            CSR_AXIS_LOAD_BEATS_ADDR,
            CSR_RESERVED_05C_ADDR,

            CSR_DS_SRC_BASE_ADDR,
            CSR_DS_DST_BASE_ADDR,
            CSR_DS_LOAD_BEATS_ADDR,
            CSR_DS_CONTROL_ADDR,

            CSR_DMA_STORE_SRC_BASE_ADDR,
            CSR_DMA_STORE_DST_BASE_ADDR,
            CSR_DMA_STORE_BYTE_COUNT_ADDR,
            CSR_RESERVED_07C_ADDR,

            CSR_PERF_BUSY_CYCLES_ADDR,
            CSR_PERF_MAC_COUNT_ADDR,
            CSR_PERF_OUTPUT_COUNT_ADDR,
            CSR_RESERVED_08C_ADDR: begin
                return 1'b1;
            end

            default: begin
                return 1'b0;
            end
        endcase
    end
    endfunction

    function automatic logic [31:0] csr_read_data(
        input logic [CSR_ADDR_WIDTH-1:0] addr
    );
    begin
        unique case (addr)
            CSR_VERSION_ADDR: begin
                return CSR_VERSION_VALUE;
            end

            CSR_COMMAND_ADDR: begin
                return 32'h0000_0000;
            end

            CSR_STATUS_ADDR: begin
                return status_read_data;
            end

            CSR_DONE_STATUS_ADDR: begin
                return done_status_q;
            end

            CSR_ERROR_STATUS_ADDR: begin
                return error_status_q;
            end

            CSR_MODE_ADDR: begin
                return mode_q;
            end

            CSR_CMD_REJECT_STATUS_ADDR: begin
                return reject_status_q;
            end

            CSR_BASE_ADDR_A_ADDR: begin
                return base_addr_a_q;
            end

            CSR_BASE_ADDR_B_ADDR: begin
                return base_addr_b_q;
            end

            CSR_BASE_ADDR_C_ADDR: begin
                return base_addr_c_q;
            end

            CSR_DIM_M_ADDR: begin
                return dim_m_q;
            end

            CSR_DIM_N_ADDR: begin
                return dim_n_q;
            end

            CSR_DIM_K_ADDR: begin
                return dim_k_q;
            end

            CSR_DMA_LOAD_SRC_BASE_ADDR: begin
                return dma_load_src_base_q;
            end

            CSR_DMA_LOAD_DST_BASE_ADDR: begin
                return dma_load_dst_base_q;
            end

            CSR_DMA_LOAD_BEATS_ADDR: begin
                return dma_load_beats_q;
            end

            CSR_AXIS_SRC_BASE_ADDR: begin
                return axis_src_base_q;
            end

            CSR_AXIS_DST_BASE_ADDR: begin
                return axis_dst_base_q;
            end

            CSR_AXIS_LOAD_BEATS_ADDR: begin
                return axis_load_beats_q;
            end

            CSR_DS_SRC_BASE_ADDR: begin
                return ds_src_base_q;
            end

            CSR_DS_DST_BASE_ADDR: begin
                return ds_dst_base_q;
            end

            CSR_DS_LOAD_BEATS_ADDR: begin
                return ds_load_beats_q;
            end

            CSR_DS_CONTROL_ADDR: begin
                return ds_control_q;
            end

            CSR_DMA_STORE_SRC_BASE_ADDR: begin
                return dma_store_src_base_q;
            end

            CSR_DMA_STORE_DST_BASE_ADDR: begin
                return dma_store_dst_base_q;
            end

            CSR_DMA_STORE_BYTE_COUNT_ADDR: begin
                return dma_store_byte_count_q;
            end

            CSR_PERF_BUSY_CYCLES_ADDR: begin
                return perf_busy_cycles_q;
            end

            CSR_PERF_MAC_COUNT_ADDR: begin
                return perf_mac_count_q;
            end

            CSR_PERF_OUTPUT_COUNT_ADDR: begin
                return perf_output_count_q;
            end

            default: begin
                return 32'h0000_0000;
            end
        endcase
    end
    endfunction

    function automatic logic [31:0] count_start_bits(
        input logic [31:0] value
    );
        logic [31:0] cnt;
        int unsigned i;
    begin
        cnt = 32'd0;

        for (i = 0; i < 5; i++) begin
            if (value[i]) begin
                cnt = cnt + 32'd1;
            end
        end

        return cnt;
    end
    endfunction

    // ------------------------------------------------------------
    // Live status readback composition
    // ------------------------------------------------------------
    always_comb begin
        status_read_data = 32'h0000_0000;

        status_read_data[0]  = acc_busy;
        status_read_data[1]  = dma_load_busy;
        status_read_data[2]  = axis_load_busy;
        status_read_data[3]  = ds_load_busy;
        status_read_data[4]  = dma_store_busy;

        status_read_data[8]  = acc_busy        |
                               dma_load_busy   |
                               axis_load_busy  |
                               ds_load_busy    |
                               dma_store_busy;

        status_read_data[12] = |done_status_q;
        status_read_data[13] = (|error_status_q) | (|reject_status_q);
        status_read_data[16] = 1'b1;
    end

    // ------------------------------------------------------------
    // AXI-Lite handshake outputs
    // ------------------------------------------------------------
    assign csr_if.awready = !awaddr_valid_q && !bvalid_q;
    assign csr_if.wready  = !wdata_valid_q  && !bvalid_q;
    assign csr_if.bvalid  = bvalid_q;
    assign csr_if.bresp   = bresp_q;

    assign csr_if.arready = !rvalid_q;
    assign csr_if.rvalid  = rvalid_q;
    assign csr_if.rdata   = rdata_q;
    assign csr_if.rresp   = rresp_q;

    always_comb begin
        aw_fire = csr_if.awvalid && csr_if.awready;
        w_fire  = csr_if.wvalid  && csr_if.wready;
        b_fire  = csr_if.bvalid  && csr_if.bready;
        ar_fire = csr_if.arvalid && csr_if.arready;
        r_fire  = csr_if.rvalid  && csr_if.rready;

        write_addr  = aw_fire ? csr_if.awaddr : awaddr_q;
        write_data  = w_fire  ? csr_if.wdata  : wdata_q;
        write_strb  = w_fire  ? csr_if.wstrb  : wstrb_q;

        write_apply = !bvalid_q &&
                      (awaddr_valid_q || aw_fire) &&
                      (wdata_valid_q  || w_fire);

        write_addr_valid = csr_addr_is_valid(write_addr);
        read_addr_valid  = csr_addr_is_valid(csr_if.araddr);
        read_data_comb   = csr_read_data(csr_if.araddr);
    end

    // ------------------------------------------------------------
    // Command decode helpers for the current write transaction
    // ------------------------------------------------------------
    always_comb begin
        command_has_active_strobe = |write_strb;
        command_masked            = write_data & strobe_to_mask(write_strb);
        start_bits                = command_masked & CMD_START_MASK;
        command_has_start         = |start_bits;
        command_multi_start       = (count_start_bits(start_bits) > 32'd1);

        command_unsupported_combo = command_multi_start ||
                                    (command_has_start &&
                                     command_masked[CMD_CLEAR_ERROR_BIT] &&
                                     ((|error_status_q) || (|reject_status_q)));
    end

    // ------------------------------------------------------------
    // CSR storage and AXI-Lite transaction state
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awaddr_q        <= '0;
            awaddr_valid_q  <= 1'b0;

            wdata_q         <= 32'h0000_0000;
            wstrb_q         <= '0;
            wdata_valid_q   <= 1'b0;

            bvalid_q        <= 1'b0;
            bresp_q         <= AXI_RESP_OKAY;

            rvalid_q        <= 1'b0;
            rdata_q         <= 32'h0000_0000;
            rresp_q         <= AXI_RESP_OKAY;

            mode_q          <= 32'h0000_0000;

            base_addr_a_q   <= 32'h0000_0000;
            base_addr_b_q   <= 32'h0000_0100;
            base_addr_c_q   <= 32'h0000_0200;

            dim_m_q         <= 32'h0000_0004;
            dim_n_q         <= 32'h0000_0004;
            dim_k_q         <= 32'h0000_0004;

            dma_load_src_base_q    <= 32'h0000_0000;
            dma_load_dst_base_q    <= 32'h0000_0000;
            dma_load_beats_q       <= 32'h0000_0000;

            axis_src_base_q        <= 32'h0000_0000;
            axis_dst_base_q        <= 32'h0000_0000;
            axis_load_beats_q      <= 32'h0000_0000;

            ds_src_base_q          <= 32'h0000_0000;
            ds_dst_base_q          <= 32'h0000_0000;
            ds_load_beats_q        <= 32'h0000_0000;
            ds_control_q           <= 32'h0000_0000;

            dma_store_src_base_q   <= 32'h0000_0000;
            dma_store_dst_base_q   <= 32'h0000_0000;
            dma_store_byte_count_q <= 32'h0000_0000;

            done_status_q          <= 32'h0000_0000;
            error_status_q         <= 32'h0000_0000;
            reject_status_q        <= 32'h0000_0000;

            perf_busy_cycles_q     <= 32'h0000_0000;
            perf_mac_count_q       <= 32'h0000_0000;
            perf_output_count_q    <= 32'h0000_0000;

            acc_start_pulse        <= 1'b0;
            dma_load_start_pulse   <= 1'b0;
            axis_load_start_pulse  <= 1'b0;
            ds_load_start_pulse    <= 1'b0;
            dma_store_start_pulse  <= 1'b0;
        end
        else begin
            acc_start_pulse       <= 1'b0;
            dma_load_start_pulse  <= 1'b0;
            axis_load_start_pulse <= 1'b0;
            ds_load_start_pulse   <= 1'b0;
            dma_store_start_pulse <= 1'b0;

            // Sticky completion and error capture.
            if (acc_done) begin
                done_status_q[DONE_GEMM_BIT] <= 1'b1;

                perf_busy_cycles_q  <= gemm_perf_busy_cycles;
                perf_mac_count_q    <= gemm_perf_mac_count;
                perf_output_count_q <= gemm_perf_output_count;
            end

            if (dma_load_done) begin
                done_status_q[DONE_DMA_LOAD_BIT] <= 1'b1;
            end

            if (axis_load_done) begin
                done_status_q[DONE_AXIS_LOAD_BIT] <= 1'b1;
            end

            if (ds_load_done) begin
                done_status_q[DONE_DS_LOAD_BIT] <= 1'b1;
            end

            if (dma_store_done) begin
                done_status_q[DONE_DMA_STORE_BIT] <= 1'b1;
            end

            if (dma_load_error) begin
                error_status_q[ERR_DMA_LOAD_BIT] <= 1'b1;
            end

            if (axis_load_error) begin
                error_status_q[ERR_AXIS_LOAD_BIT] <= 1'b1;
            end

            if (ds_load_error) begin
                error_status_q[ERR_DS_LOAD_BIT] <= 1'b1;
            end

            if (dma_store_error) begin
                error_status_q[ERR_DMA_STORE_BIT] <= 1'b1;
            end

            // Capture write address/data channels independently.
            if (aw_fire && !write_apply) begin
                awaddr_q       <= csr_if.awaddr;
                awaddr_valid_q <= 1'b1;
            end
            else if (write_apply) begin
                awaddr_valid_q <= 1'b0;
            end

            if (w_fire && !write_apply) begin
                wdata_q       <= csr_if.wdata;
                wstrb_q       <= csr_if.wstrb;
                wdata_valid_q <= 1'b1;
            end
            else if (write_apply) begin
                wdata_valid_q <= 1'b0;
            end

            if (b_fire) begin
                bvalid_q <= 1'b0;
            end

            if (write_apply) begin
                bvalid_q <= 1'b1;
                bresp_q  <= write_addr_valid ? AXI_RESP_OKAY : AXI_RESP_SLVERR;

                if (write_addr_valid && (|write_strb)) begin
                    unique case (write_addr)
                        CSR_COMMAND_ADDR: begin
                            if (command_has_active_strobe) begin
                                if (command_unsupported_combo) begin
                                    reject_status_q[REJ_UNSUPPORTED_BIT] <= 1'b1;
                                end
                                else begin
                                    if (command_masked[CMD_CLEAR_DONE_BIT]) begin
                                        done_status_q <= 32'h0000_0000;
                                    end

                                    if (command_masked[CMD_CLEAR_ERROR_BIT]) begin
                                        error_status_q  <= 32'h0000_0000;
                                        reject_status_q <= 32'h0000_0000;
                                    end

                                    if (command_masked[CMD_CLEAR_PERF_BIT]) begin
                                        perf_busy_cycles_q  <= 32'h0000_0000;
                                        perf_mac_count_q    <= 32'h0000_0000;
                                        perf_output_count_q <= 32'h0000_0000;
                                    end

                                    if (command_masked[CMD_START_GEMM_BIT]) begin
                                        if (acc_busy || axis_load_busy || ds_load_busy) begin
                                            reject_status_q[REJ_GEMM_BUSY_BIT] <= 1'b1;
                                        end
                                        else if ((dim_m_q == 32'h0000_0000) ||
                                                 (dim_n_q == 32'h0000_0000) ||
                                                 (dim_k_q == 32'h0000_0000)) begin
                                            reject_status_q[REJ_ZERO_LENGTH_BIT] <= 1'b1;
                                        end
                                        else begin
                                            acc_start_pulse <= 1'b1;
                                        end
                                    end

                                    if (command_masked[CMD_START_DMA_LOAD_BIT]) begin
                                        if (dma_load_busy || dma_store_busy) begin
                                            reject_status_q[REJ_DMA_LOAD_BUSY_BIT] <= 1'b1;
                                        end
                                        else if (dma_load_beats_q == 32'h0000_0000) begin
                                            reject_status_q[REJ_ZERO_LENGTH_BIT] <= 1'b1;
                                        end
                                        else begin
                                            dma_load_start_pulse <= 1'b1;
                                        end
                                    end

                                    if (command_masked[CMD_START_AXIS_LOAD_BIT]) begin
                                        if (axis_load_busy || acc_busy) begin
                                            reject_status_q[REJ_AXIS_BUSY_BIT] <= 1'b1;
                                        end
                                        else if (axis_load_beats_q == 32'h0000_0000) begin
                                            reject_status_q[REJ_ZERO_LENGTH_BIT] <= 1'b1;
                                        end
                                        else begin
                                            axis_load_start_pulse <= 1'b1;
                                        end
                                    end

                                    if (command_masked[CMD_START_DS_LOAD_BIT]) begin
                                        if (ds_load_busy || acc_busy) begin
                                            reject_status_q[REJ_DS_BUSY_BIT] <= 1'b1;
                                        end
                                        else if (ds_load_beats_q == 32'h0000_0000) begin
                                            reject_status_q[REJ_ZERO_LENGTH_BIT] <= 1'b1;
                                        end
                                        else begin
                                            ds_load_start_pulse <= 1'b1;
                                        end
                                    end

                                    if (command_masked[CMD_START_DMA_STORE_BIT]) begin
                                        if (dma_store_busy || dma_load_busy) begin
                                            reject_status_q[REJ_DMA_STORE_BUSY_BIT] <= 1'b1;
                                        end
                                        else if (dma_store_byte_count_q == 32'h0000_0000) begin
                                            reject_status_q[REJ_ZERO_LENGTH_BIT] <= 1'b1;
                                        end
                                        else begin
                                            dma_store_start_pulse <= 1'b1;
                                        end
                                    end
                                end
                            end
                        end

                        CSR_DONE_STATUS_ADDR: begin
                            done_status_q <= done_status_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                        end

                        CSR_ERROR_STATUS_ADDR: begin
                            error_status_q <= error_status_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                        end

                        CSR_MODE_ADDR: begin
                            mode_q <= apply_wstrb32(mode_q, write_data, write_strb) &
                                      32'h0000_0003;
                        end

                        CSR_CMD_REJECT_STATUS_ADDR: begin
                            reject_status_q <= reject_status_q & ~apply_wstrb32(
                                32'h0000_0000,
                                write_data,
                                write_strb
                            );
                        end

                        CSR_BASE_ADDR_A_ADDR: begin
                            base_addr_a_q <= apply_wstrb32(base_addr_a_q, write_data, write_strb);
                        end

                        CSR_BASE_ADDR_B_ADDR: begin
                            base_addr_b_q <= apply_wstrb32(base_addr_b_q, write_data, write_strb);
                        end

                        CSR_BASE_ADDR_C_ADDR: begin
                            base_addr_c_q <= apply_wstrb32(base_addr_c_q, write_data, write_strb);
                        end

                        CSR_DIM_M_ADDR: begin
                            dim_m_q <= apply_wstrb32(dim_m_q, write_data, write_strb);
                        end

                        CSR_DIM_N_ADDR: begin
                            dim_n_q <= apply_wstrb32(dim_n_q, write_data, write_strb);
                        end

                        CSR_DIM_K_ADDR: begin
                            dim_k_q <= apply_wstrb32(dim_k_q, write_data, write_strb);
                        end

                        CSR_DMA_LOAD_SRC_BASE_ADDR: begin
                            dma_load_src_base_q <= apply_wstrb32(dma_load_src_base_q, write_data, write_strb);
                        end

                        CSR_DMA_LOAD_DST_BASE_ADDR: begin
                            dma_load_dst_base_q <= apply_wstrb32(dma_load_dst_base_q, write_data, write_strb);
                        end

                        CSR_DMA_LOAD_BEATS_ADDR: begin
                            dma_load_beats_q <= apply_wstrb32(dma_load_beats_q, write_data, write_strb);
                        end

                        CSR_AXIS_SRC_BASE_ADDR: begin
                            axis_src_base_q <= apply_wstrb32(axis_src_base_q, write_data, write_strb);
                        end

                        CSR_AXIS_DST_BASE_ADDR: begin
                            axis_dst_base_q <= apply_wstrb32(axis_dst_base_q, write_data, write_strb);
                        end

                        CSR_AXIS_LOAD_BEATS_ADDR: begin
                            axis_load_beats_q <= apply_wstrb32(axis_load_beats_q, write_data, write_strb);
                        end

                        CSR_DS_SRC_BASE_ADDR: begin
                            ds_src_base_q <= apply_wstrb32(ds_src_base_q, write_data, write_strb);
                        end

                        CSR_DS_DST_BASE_ADDR: begin
                            ds_dst_base_q <= apply_wstrb32(ds_dst_base_q, write_data, write_strb);
                        end

                        CSR_DS_LOAD_BEATS_ADDR: begin
                            ds_load_beats_q <= apply_wstrb32(ds_load_beats_q, write_data, write_strb);
                        end

                        CSR_DS_CONTROL_ADDR: begin
                            ds_control_q <= apply_wstrb32(ds_control_q, write_data, write_strb) &
                                            32'h0000_0001;
                        end

                        CSR_DMA_STORE_SRC_BASE_ADDR: begin
                            dma_store_src_base_q <= apply_wstrb32(dma_store_src_base_q, write_data, write_strb);
                        end

                        CSR_DMA_STORE_DST_BASE_ADDR: begin
                            dma_store_dst_base_q <= apply_wstrb32(dma_store_dst_base_q, write_data, write_strb);
                        end

                        CSR_DMA_STORE_BYTE_COUNT_ADDR: begin
                            dma_store_byte_count_q <= apply_wstrb32(dma_store_byte_count_q, write_data, write_strb);
                        end

                        default: begin
                            // RO and reserved registers ignore valid writes.
                        end
                    endcase
                end
            end

            if (r_fire) begin
                rvalid_q <= 1'b0;
            end

            if (ar_fire) begin
                rvalid_q <= 1'b1;
                rresp_q  <= read_addr_valid ? AXI_RESP_OKAY : AXI_RESP_SLVERR;
                rdata_q  <= read_addr_valid ? read_data_comb : 32'h0000_0000;
            end
        end
    end

    // ------------------------------------------------------------
    // Sideband output mapping
    // ------------------------------------------------------------
    assign gemm_input_stream_mode = mode_q[0];
    assign accumulate_enable      = mode_q[1];

    assign base_addr_a = base_addr_a_q[ADDR_WIDTH-1:0];
    assign base_addr_b = base_addr_b_q[ADDR_WIDTH-1:0];
    assign base_addr_c = base_addr_c_q[ADDR_WIDTH-1:0];

    assign dim_m = dim_m_q[GEMM_DIM_WIDTH-1:0];
    assign dim_n = dim_n_q[GEMM_DIM_WIDTH-1:0];
    assign dim_k = dim_k_q[GEMM_DIM_WIDTH-1:0];

    assign dma_src_base_addr = dma_load_src_base_q[ADDR_WIDTH-1:0];
    assign dma_dst_base_addr = dma_load_dst_base_q[ADDR_WIDTH-1:0];
    assign dma_load_beats    = dma_load_beats_q;

    assign axis_src_base_addr = axis_src_base_q[ADDR_WIDTH-1:0];
    assign axis_dst_base_addr = axis_dst_base_q[ADDR_WIDTH-1:0];
    assign axis_load_beats    = axis_load_beats_q;

    assign ds_src_base_addr = ds_src_base_q[ADDR_WIDTH-1:0];
    assign ds_dst_base_addr = ds_dst_base_q[ADDR_WIDTH-1:0];
    assign ds_load_beats    = ds_load_beats_q;
    assign ds_operand_sel   = ds_control_q[0];

    assign dma_store_src_base_addr = dma_store_src_base_q[ADDR_WIDTH-1:0];
    assign dma_store_dst_base_addr = dma_store_dst_base_q[ADDR_WIDTH-1:0];
    assign dma_store_byte_count    = dma_store_byte_count_q;

endmodule

`endif
