// File: rtl/subsystem/gemm_input_mem_router.sv

`ifndef GEMM_INPUT_MEM_ROUTER_SV
`define GEMM_INPUT_MEM_ROUTER_SV

module gemm_input_mem_router #(
    parameter int ADDR_WIDTH       = 32,
    parameter int LOCAL_DATA_WIDTH = 32
)(
    input  logic                              clk,
    input  logic                              rst_n,

    // ------------------------------------------------------------
    // Status clear
    // ------------------------------------------------------------
    input  logic                              clear_status,

    // ------------------------------------------------------------
    // Mode/config
    //
    // direct_stream_mode:
    //   0 = transparent scratchpad bypass mode
    //   1 = direct-stream operand-buffer mode
    // ------------------------------------------------------------
    input  logic                              direct_stream_mode,

    input  logic [ADDR_WIDTH-1:0]             base_addr_a,
    input  logic [ADDR_WIDTH-1:0]             base_addr_b,

    input  logic [31:0]                       a_region_bytes,
    input  logic [31:0]                       b_region_bytes,

    input  logic                              operand_a_loaded,
    input  logic                              operand_b_loaded,

    input  logic                              operand_buf_error,
    input  logic                              operand_buf_read_error_pulse,

    // ============================================================
    // GEMM local memory side
    // ============================================================
    output logic                              gemm_mem_req_ready,

    input  logic                              gemm_mem_rd_en,
    input  logic [ADDR_WIDTH-1:0]             gemm_mem_rd_addr,
    output logic [LOCAL_DATA_WIDTH-1:0]       gemm_mem_rd_data,
    output logic                              gemm_mem_rd_valid,

    input  logic                              gemm_mem_wr_en,
    input  logic [ADDR_WIDTH-1:0]             gemm_mem_wr_addr,
    input  logic [LOCAL_DATA_WIDTH-1:0]       gemm_mem_wr_data,
    input  logic [LOCAL_DATA_WIDTH/8-1:0]     gemm_mem_wr_strb,

    // ============================================================
    // Scratchpad adapter local-memory side
    // ============================================================
    input  logic                              sp_mem_req_ready,

    output logic                              sp_mem_rd_en,
    output logic [ADDR_WIDTH-1:0]             sp_mem_rd_addr,
    input  logic [LOCAL_DATA_WIDTH-1:0]       sp_mem_rd_data,
    input  logic                              sp_mem_rd_valid,

    output logic                              sp_mem_wr_en,
    output logic [ADDR_WIDTH-1:0]             sp_mem_wr_addr,
    output logic [LOCAL_DATA_WIDTH-1:0]       sp_mem_wr_data,
    output logic [LOCAL_DATA_WIDTH/8-1:0]     sp_mem_wr_strb,

    // ============================================================
    // Operand buffer read side
    // ============================================================
    output logic                              op_rd_valid,
    input  logic                              op_rd_ready,
    output logic                              op_rd_operand_sel,
    output logic [ADDR_WIDTH-1:0]             op_rd_addr,
    input  logic [LOCAL_DATA_WIDTH-1:0]       op_rd_data,
    input  logic                              op_rd_data_valid,

    // ------------------------------------------------------------
    // Status/debug
    // ------------------------------------------------------------
    output logic                              busy,

    output logic                              router_error_pulse,
    output logic                              error,

    output logic [31:0]                       op_read_count,
    output logic [31:0]                       sp_read_count,
    output logic [31:0]                       sp_write_count,
    output logic [31:0]                       invalid_read_count,
    output logic [31:0]                       simultaneous_req_count
);

    localparam int LOCAL_BYTES = LOCAL_DATA_WIDTH / 8;

    localparam logic OPERAND_A = 1'b0;
    localparam logic OPERAND_B = 1'b1;

    typedef enum logic [1:0] {
        RD_ROUTE_OP  = 2'd0,
        RD_ROUTE_ERR = 2'd1
    } ds_rd_route_e;

    // ------------------------------------------------------------
    // Region decode
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] a_region_bytes_ext;
    logic [ADDR_WIDTH-1:0] b_region_bytes_ext;

    logic [ADDR_WIDTH-1:0] a_region_end;
    logic [ADDR_WIDTH-1:0] b_region_end;
    logic [ADDR_WIDTH-1:0] rd_addr_end;

    logic                  rd_in_a_region;
    logic                  rd_in_b_region;

    logic [ADDR_WIDTH-1:0] rd_a_local_offset;
    logic [ADDR_WIDTH-1:0] rd_b_local_offset;

    ds_rd_route_e          ds_rd_route;
    logic                  ds_op_sel;
    logic [ADDR_WIDTH-1:0] ds_op_local_addr;

    logic                  ds_read_not_loaded;
    logic                  ds_read_outside_ab;

    // ------------------------------------------------------------
    // Direct-stream read pending tracking
    //
    // Important:
    //   These are only used when direct_stream_mode = 1.
    //   In scratchpad mode, this router is a transparent bypass.
    // ------------------------------------------------------------
    logic pending_op_read_q;
    logic pending_err_read_q;

    logic any_pending;
    logic any_req;
    logic req_fire;
    logic rd_req_fire;
    logic wr_req_fire;

    logic ds_read_ready;
    logic ds_write_ready;
    logic ds_ready_comb;

    logic router_error_pulse_q;

    // ------------------------------------------------------------
    // Parameter sanity
    // ------------------------------------------------------------
    initial begin
        if (ADDR_WIDTH <= 0) begin
            $fatal(1, "gemm_input_mem_router: ADDR_WIDTH must be > 0");
        end

        if (LOCAL_DATA_WIDTH <= 0 || (LOCAL_DATA_WIDTH % 8) != 0) begin
            $fatal(1,
                "gemm_input_mem_router: LOCAL_DATA_WIDTH must be positive and byte-aligned"
            );
        end
    end

    // ------------------------------------------------------------
    // Address decode
    // ------------------------------------------------------------
    always_comb begin
        a_region_bytes_ext = ADDR_WIDTH'(a_region_bytes);
        b_region_bytes_ext = ADDR_WIDTH'(b_region_bytes);

        a_region_end = base_addr_a + a_region_bytes_ext;
        b_region_end = base_addr_b + b_region_bytes_ext;

        rd_addr_end  = gemm_mem_rd_addr + ADDR_WIDTH'(LOCAL_BYTES);

        // GEMM operand reads use byte-addressed int8 element addresses.
        // The 32-bit rd_data is only a container; GEMM consumes the
        // selected low-byte operand value. Therefore routing should be
        // based on the read start address, not on the full 32-bit window.
        rd_in_a_region =
            (a_region_bytes != 0) &&
            (gemm_mem_rd_addr >= base_addr_a) &&
            (gemm_mem_rd_addr <  a_region_end);

        rd_in_b_region =
            (b_region_bytes != 0) &&
            (gemm_mem_rd_addr >= base_addr_b) &&
            (gemm_mem_rd_addr <  b_region_end);

        rd_a_local_offset = gemm_mem_rd_addr - base_addr_a;
        rd_b_local_offset = gemm_mem_rd_addr - base_addr_b;
    end

    // ------------------------------------------------------------
    // Direct-stream read route decode
    // ------------------------------------------------------------
    always_comb begin
        ds_rd_route        = RD_ROUTE_ERR;
        ds_op_sel          = OPERAND_A;
        ds_op_local_addr   = '0;

        ds_read_not_loaded = 1'b0;
        ds_read_outside_ab = 1'b0;

        if (rd_in_a_region) begin
            ds_op_sel        = OPERAND_A;
            ds_op_local_addr = rd_a_local_offset;

            if (operand_a_loaded) begin
                ds_rd_route = RD_ROUTE_OP;
            end
            else begin
                ds_rd_route        = RD_ROUTE_ERR;
                ds_read_not_loaded = 1'b1;
            end
        end
        else if (rd_in_b_region) begin
            ds_op_sel        = OPERAND_B;
            ds_op_local_addr = rd_b_local_offset;

            if (operand_b_loaded) begin
                ds_rd_route = RD_ROUTE_OP;
            end
            else begin
                ds_rd_route        = RD_ROUTE_ERR;
                ds_read_not_loaded = 1'b1;
            end
        end
        else begin
            ds_rd_route        = RD_ROUTE_ERR;
            ds_read_outside_ab = 1'b1;
        end
    end

    // ------------------------------------------------------------
    // Ready / request fire
    //
    // Critical compatibility rule:
    //
    //   direct_stream_mode = 0:
    //     fully transparent bypass to gemm_scratchpad_adapter.
    //
    //   direct_stream_mode = 1:
    //     A/B reads go to operand buffer.
    //     writes go to scratchpad adapter.
    // ------------------------------------------------------------
    always_comb begin
        any_pending = pending_op_read_q || pending_err_read_q;
        any_req     = gemm_mem_rd_en || gemm_mem_wr_en;

        ds_read_ready  = 1'b1;
        ds_write_ready = 1'b1;

        if (gemm_mem_rd_en) begin
            case (ds_rd_route)
                RD_ROUTE_OP:  ds_read_ready = op_rd_ready;
                RD_ROUTE_ERR: ds_read_ready = 1'b1;
                default:      ds_read_ready = 1'b1;
            endcase
        end

        if (gemm_mem_wr_en) begin
            ds_write_ready = sp_mem_req_ready;
        end

        if (!direct_stream_mode) begin
            gemm_mem_req_ready = sp_mem_req_ready;
        end
        else if (any_pending) begin
            gemm_mem_req_ready = 1'b0;
        end
        else begin
            // Allow read+write in the same cycle when they go to
            // different backends:
            //   read A/B -> operand buffer
            //   write C  -> scratchpad adapter
            gemm_mem_req_ready = ds_read_ready && ds_write_ready;
        end

        req_fire    = any_req && gemm_mem_req_ready;

        rd_req_fire = req_fire && gemm_mem_rd_en;
        wr_req_fire = req_fire && gemm_mem_wr_en;
    end

    // ------------------------------------------------------------
    // Scratchpad backend request generation
    //
    // scratchpad mode:
    //   transparent pass-through.
    //
    // direct-stream mode:
    //   only writes go to scratchpad.
    // ------------------------------------------------------------
    always_comb begin
        sp_mem_rd_en   = 1'b0;
        sp_mem_rd_addr = gemm_mem_rd_addr;

        sp_mem_wr_en   = 1'b0;
        sp_mem_wr_addr = gemm_mem_wr_addr;
        sp_mem_wr_data = gemm_mem_wr_data;
        sp_mem_wr_strb = gemm_mem_wr_strb;

        if (!direct_stream_mode) begin
            sp_mem_rd_en = gemm_mem_rd_en;
            sp_mem_wr_en = gemm_mem_wr_en;
        end
        else begin
            if (wr_req_fire) begin
                sp_mem_wr_en = 1'b1;
            end
        end
    end

    // ------------------------------------------------------------
    // Operand buffer request generation
    // ------------------------------------------------------------
    always_comb begin
        op_rd_valid       = 1'b0;
        op_rd_operand_sel = ds_op_sel;
        op_rd_addr        = ds_op_local_addr;

        if (direct_stream_mode &&
            rd_req_fire &&
            (ds_rd_route == RD_ROUTE_OP)) begin
            op_rd_valid = 1'b1;
        end
    end

    // ------------------------------------------------------------
    // GEMM read response mux
    //
    // scratchpad mode:
    //   transparent pass-through from scratchpad adapter.
    //
    // direct-stream mode:
    //   operand-buffer read response or synthetic zero response
    //   for invalid direct-stream read.
    // ------------------------------------------------------------
    always_comb begin
        if (!direct_stream_mode) begin
            gemm_mem_rd_data  = sp_mem_rd_data;
            gemm_mem_rd_valid = sp_mem_rd_valid;
        end
        else begin
            gemm_mem_rd_data  = '0;
            gemm_mem_rd_valid = 1'b0;

            if (pending_err_read_q) begin
                gemm_mem_rd_data  = '0;
                gemm_mem_rd_valid = 1'b1;
            end
            else if (pending_op_read_q && op_rd_data_valid) begin
                gemm_mem_rd_data  = op_rd_data;
                gemm_mem_rd_valid = 1'b1;
            end
        end
    end

    // ------------------------------------------------------------
    // Status outputs
    // ------------------------------------------------------------
    always_comb begin
        busy = direct_stream_mode && any_pending;

        router_error_pulse = router_error_pulse_q;
    end

    // ------------------------------------------------------------
    // Sequential control / status
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_op_read_q        <= 1'b0;
            pending_err_read_q       <= 1'b0;

            router_error_pulse_q     <= 1'b0;
            error                    <= 1'b0;

            op_read_count            <= '0;
            sp_read_count            <= '0;
            sp_write_count           <= '0;
            invalid_read_count       <= '0;
            simultaneous_req_count   <= '0;
        end
        else begin
            router_error_pulse_q <= 1'b0;

            if (clear_status) begin
                error                  <= 1'b0;
                op_read_count          <= '0;
                sp_read_count          <= '0;
                sp_write_count         <= '0;
                invalid_read_count     <= '0;
                simultaneous_req_count <= '0;
            end

            // If mode is scratchpad bypass, do not keep stale
            // direct-stream pending state.
            if (!direct_stream_mode) begin
                pending_op_read_q  <= 1'b0;
                pending_err_read_q <= 1'b0;
            end
            else begin
                if (operand_buf_error || operand_buf_read_error_pulse) begin
                    error                <= 1'b1;
                    router_error_pulse_q <= 1'b1;
                end

                if (rd_req_fire) begin
                    if (gemm_mem_rd_en && gemm_mem_wr_en) begin
                        simultaneous_req_count <= simultaneous_req_count + 32'd1;
                    end

                    case (ds_rd_route)
                        RD_ROUTE_OP: begin
                            pending_op_read_q <= 1'b1;
                            op_read_count     <= op_read_count + 32'd1;
                        end

                        RD_ROUTE_ERR: begin
                            pending_err_read_q   <= 1'b1;
                            router_error_pulse_q <= 1'b1;
                            error                <= 1'b1;
                            invalid_read_count   <= invalid_read_count + 32'd1;
                        end

                        default: begin
                            pending_err_read_q   <= 1'b1;
                            router_error_pulse_q <= 1'b1;
                            error                <= 1'b1;
                            invalid_read_count   <= invalid_read_count + 32'd1;
                        end
                    endcase
                end

                if (wr_req_fire) begin
                    sp_write_count <= sp_write_count + 32'd1;
                end

                if (pending_op_read_q && op_rd_data_valid) begin
                    pending_op_read_q <= 1'b0;
                end

                if (pending_err_read_q) begin
                    pending_err_read_q <= 1'b0;
                end
            end

            // Optional scratchpad-mode counters only. These counters
            // are not used for functional behavior.
            if (!direct_stream_mode) begin
                if (gemm_mem_rd_en && sp_mem_req_ready) begin
                    sp_read_count <= sp_read_count + 32'd1;
                end

                if (gemm_mem_wr_en && sp_mem_req_ready) begin
                    sp_write_count <= sp_write_count + 32'd1;
                end
            end
        end
    end

`ifdef DIRECT_STREAM_ROUTER_REPORT_ERRORS
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // no-op
        end
        else begin
            if (router_error_pulse_q) begin
                $error(
                    "[gemm_input_mem_router] router error: direct_stream_mode=%0b rd_en=%0b wr_en=%0b rd_addr=0x%08h base_a=0x%08h base_b=0x%08h a_loaded=%0b b_loaded=%0b in_a=%0b in_b=%0b outside_ab=%0b not_loaded=%0b",
                    direct_stream_mode,
                    gemm_mem_rd_en,
                    gemm_mem_wr_en,
                    gemm_mem_rd_addr,
                    base_addr_a,
                    base_addr_b,
                    operand_a_loaded,
                    operand_b_loaded,
                    rd_in_a_region,
                    rd_in_b_region,
                    ds_read_outside_ab,
                    ds_read_not_loaded
                );
            end
        end
    end
`endif

endmodule

`endif