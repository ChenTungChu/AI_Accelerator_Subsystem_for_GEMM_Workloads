// File: rtl/subsystem/gemm_operand_buffer_write_adapter.sv

`ifndef GEMM_OPERAND_BUFFER_WRITE_ADAPTER_SV
`define GEMM_OPERAND_BUFFER_WRITE_ADAPTER_SV

module gemm_operand_buffer_write_adapter #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64
)(
    input  logic                         clk,
    input  logic                         rst_n,

    // ------------------------------------------------------------
    // Status clear
    //
    // Intended usage:
    //   Pulse clear_status before launching a new direct-stream
    //   operand preload job.
    // ------------------------------------------------------------
    input  logic                         clear_status,

    // ------------------------------------------------------------
    // Operand load configuration
    //
    // operand_sel:
    //   0 = A
    //   1 = B
    //
    // operand_base_addr:
    //   Logical base address of the selected operand.
    //
    // Address translation:
    //   buf_wr_addr = wr_addr - operand_base_addr
    // ------------------------------------------------------------
    input  logic                         operand_sel,
    input  logic [ADDR_WIDTH-1:0]        operand_base_addr,

    // ------------------------------------------------------------
    // Linear write-request input
    //
    // Source:
    //   axi_stream_loader wr_* output
    //
    // Addressing:
    //   wr_addr is logical/full byte address.
    // ------------------------------------------------------------
    input  logic                         wr_valid,
    output logic                         wr_ready,
    input  logic [ADDR_WIDTH-1:0]        wr_addr,
    input  logic [DATA_WIDTH-1:0]        wr_data,
    input  logic [DATA_WIDTH/8-1:0]      wr_strb,
    input  logic                         wr_last,

    // ------------------------------------------------------------
    // Operand buffer write port
    //
    // Target:
    //   gemm_operand_buffer write side
    //
    // Addressing:
    //   buf_wr_addr is local byte offset inside selected operand.
    // ------------------------------------------------------------
    output logic                         buf_wr_valid,
    input  logic                         buf_wr_ready,
    output logic                         buf_wr_operand_sel,
    output logic [ADDR_WIDTH-1:0]        buf_wr_addr,
    output logic [DATA_WIDTH-1:0]        buf_wr_data,
    output logic [DATA_WIDTH/8-1:0]      buf_wr_strb,
    output logic                         buf_wr_last,

    // ------------------------------------------------------------
    // Status / debug
    //
    // write_done:
    //   one-cycle pulse when one loader write request has been
    //   accepted by this adapter.
    //
    // write_done_last:
    //   one-cycle pulse when the accepted request had wr_last=1.
    //
    // write_error:
    //   one-cycle pulse when this adapter detects invalid config or
    //   address translation.
    //
    // error:
    //   sticky error bit, cleared by reset or clear_status.
    // ------------------------------------------------------------
    output logic                         busy,
    output logic                         write_done,
    output logic                         write_done_last,
    output logic                         write_error,
    output logic                         error,

    output logic [31:0]                  accepted_writes,
    output logic [31:0]                  forwarded_writes,
    output logic [31:0]                  dropped_writes
);

    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam int BEAT_ADDR_LSB  = (BYTES_PER_BEAT <= 1) ? 0 : $clog2(BYTES_PER_BEAT);

    localparam logic OPERAND_A = 1'b0;
    localparam logic OPERAND_B = 1'b1;

    logic [ADDR_WIDTH-1:0] local_addr;
    logic                  operand_valid;
    logic                  base_aligned;
    logic                  wr_addr_aligned;
    logic                  addr_not_underflow;
    logic                  translate_valid;

    logic                  wr_fire;
    logic                  forward_fire;
    logic                  drop_fire;

    logic                  write_done_q;
    logic                  write_done_last_q;
    logic                  write_error_q;

    // ------------------------------------------------------------
    // Parameter sanity
    // ------------------------------------------------------------
    function automatic bit is_power_of_two(input int value);
        return (value > 0) && ((value & (value - 1)) == 0);
    endfunction

    function automatic bit addr_is_aligned(
        input logic [ADDR_WIDTH-1:0] addr
    );
        if (BYTES_PER_BEAT <= 1) begin
            return 1'b1;
        end
        else begin
            return (addr[BEAT_ADDR_LSB-1:0] == '0);
        end
    endfunction

    function automatic bit is_valid_operand_sel(input logic sel);
        return (sel === OPERAND_A) || (sel === OPERAND_B);
    endfunction

    initial begin
        if ((DATA_WIDTH % 8) != 0) begin
            $fatal(1,
                "gemm_operand_buffer_write_adapter: DATA_WIDTH must be byte-aligned"
            );
        end

        if (!is_power_of_two(BYTES_PER_BEAT)) begin
            $fatal(1,
                "gemm_operand_buffer_write_adapter: BYTES_PER_BEAT must be a power of two"
            );
        end
    end

    // ------------------------------------------------------------
    // Address translation / validation
    // ------------------------------------------------------------
    always_comb begin
        local_addr = wr_addr - operand_base_addr;

        operand_valid      = is_valid_operand_sel(operand_sel);
        base_aligned       = addr_is_aligned(operand_base_addr);
        wr_addr_aligned    = addr_is_aligned(wr_addr);
        addr_not_underflow = (wr_addr >= operand_base_addr);

        translate_valid = operand_valid      &&
                          base_aligned       &&
                          wr_addr_aligned    &&
                          addr_not_underflow;
    end

    // ------------------------------------------------------------
    // Handshake model
    //
    // If translation is valid:
    //   backpressure comes from operand buffer.
    //
    // If translation is invalid:
    //   accept and drop the write request so the upstream loader can
    //   drain deterministically. The sticky error records the failure.
    // ------------------------------------------------------------
    always_comb begin
        wr_ready = translate_valid ? buf_wr_ready : 1'b1;

        wr_fire      = wr_valid && wr_ready;
        forward_fire = wr_fire && translate_valid;
        drop_fire    = wr_fire && !translate_valid;
    end

    // ------------------------------------------------------------
    // Operand buffer output
    // ------------------------------------------------------------
    always_comb begin
        buf_wr_valid       = wr_valid && translate_valid;
        buf_wr_operand_sel = operand_sel;
        buf_wr_addr        = local_addr;
        buf_wr_data        = wr_data;
        buf_wr_strb        = wr_strb;
        buf_wr_last        = wr_last;
    end

    // ------------------------------------------------------------
    // Status outputs
    // ------------------------------------------------------------
    always_comb begin
        busy            = buf_wr_valid && !buf_wr_ready;

        write_done      = write_done_q;
        write_done_last = write_done_last_q;
        write_error     = write_error_q;
    end

    // ------------------------------------------------------------
    // Sequential status / counters
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_done_q      <= 1'b0;
            write_done_last_q <= 1'b0;
            write_error_q     <= 1'b0;

            error             <= 1'b0;
            accepted_writes   <= '0;
            forwarded_writes  <= '0;
            dropped_writes    <= '0;
        end
        else begin
            // Default one-cycle pulses.
            write_done_q      <= 1'b0;
            write_done_last_q <= 1'b0;
            write_error_q     <= 1'b0;

            if (clear_status) begin
                error            <= 1'b0;
                accepted_writes  <= '0;
                forwarded_writes <= '0;
                dropped_writes   <= '0;
            end

            if (wr_fire) begin
                accepted_writes   <= accepted_writes + 32'd1;
                write_done_q      <= 1'b1;
                write_done_last_q <= wr_last;

                if (translate_valid) begin
                    forwarded_writes <= forwarded_writes + 32'd1;
                end
                else begin
                    dropped_writes <= dropped_writes + 32'd1;
                    write_error_q  <= 1'b1;
                    error          <= 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    // ------------------------------------------------------------
    // Simulation-only diagnostics
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // no-op
        end
        else begin
            if (drop_fire) begin
                $error(
                    "[gemm_operand_buffer_write_adapter] Dropped write due to invalid translation: operand_sel=%0b operand_base=0x%08h wr_addr=0x%08h wr_strb=0x%0h operand_valid=%0b base_aligned=%0b wr_addr_aligned=%0b addr_not_underflow=%0b",
                    operand_sel,
                    operand_base_addr,
                    wr_addr,
                    wr_strb,
                    operand_valid,
                    base_aligned,
                    wr_addr_aligned,
                    addr_not_underflow
                );
            end
        end
    end
`endif

endmodule

`endif