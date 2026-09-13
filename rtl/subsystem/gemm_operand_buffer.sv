// File: rtl/subsystem/gemm_operand_buffer.sv

`ifndef GEMM_OPERAND_BUFFER_SV
`define GEMM_OPERAND_BUFFER_SV

module gemm_operand_buffer #(
    parameter int ADDR_WIDTH     = 32,
    parameter int WR_DATA_WIDTH  = 64,
    parameter int RD_DATA_WIDTH  = 32,

    // Byte capacity for each operand buffer.
    // Keep these larger than the directed A/B payload footprints used
    // by the current Direct Stream frontend tests.
    parameter int A_BUFFER_BYTES = 1024,
    parameter int B_BUFFER_BYTES = 1024
)(
    input  logic                         clk,
    input  logic                         rst_n,

    // ------------------------------------------------------------
    // Clear controls
    //
    // Intended use:
    //   clear_a before direct-stream loading A
    //   clear_b before direct-stream loading B
    //   clear_all during test/init/reset-like cleanup
    //   clear_status to clear sticky status without changing loaded flags
    //
    // Memory contents are not required to be cleared. Loaded flags
    // and counters define validity.
    // ------------------------------------------------------------
    input  logic                         clear_all,
    input  logic                         clear_a,
    input  logic                         clear_b,
    input  logic                         clear_status,

    // ------------------------------------------------------------
    // Write side
    //
    // Source:
    //   gemm_operand_buffer_write_adapter
    //
    // Addressing:
    //   wr_addr is a local byte offset within selected operand buffer.
    //
    // Operand select:
    //   0 = A
    //   1 = B
    // ------------------------------------------------------------
    input  logic                         wr_valid,
    output logic                         wr_ready,
    input  logic                         wr_operand_sel,
    input  logic [ADDR_WIDTH-1:0]        wr_addr,
    input  logic [WR_DATA_WIDTH-1:0]     wr_data,
    input  logic [WR_DATA_WIDTH/8-1:0]   wr_strb,
    input  logic                         wr_last,

    // ------------------------------------------------------------
    // Read side
    //
    // Source:
    //   gemm_input_mem_router
    //
    // Addressing:
    //   rd_addr is a local byte offset within selected operand buffer.
    //
    // Read response:
    //   rd_data_valid is a one-cycle pulse one cycle after rd_fire.
    // ------------------------------------------------------------
    input  logic                         rd_valid,
    output logic                         rd_ready,
    input  logic                         rd_operand_sel,
    input  logic [ADDR_WIDTH-1:0]        rd_addr,
    output logic [RD_DATA_WIDTH-1:0]     rd_data,
    output logic                         rd_data_valid,

    // ------------------------------------------------------------
    // Status
    // ------------------------------------------------------------
    output logic                         a_loaded,
    output logic                         b_loaded,

    output logic [31:0]                  a_written_beats,
    output logic [31:0]                  b_written_beats,

    output logic [31:0]                  read_count,

    output logic                         wr_accept_pulse,
    output logic                         rd_accept_pulse,

    output logic                         write_error_pulse,
    output logic                         read_error_pulse,

    output logic                         error
);

    localparam int WR_BYTES = WR_DATA_WIDTH / 8;
    localparam int RD_BYTES = RD_DATA_WIDTH / 8;

    localparam logic OPERAND_A = 1'b0;
    localparam logic OPERAND_B = 1'b1;

    // ------------------------------------------------------------
    // Operand storage
    //
    // Byte-addressed storage keeps Direct Stream simple: A/B are
    // compact int8 payloads, and GEMM local reads use byte offsets.
    // C data is not stored here; C stays in scratchpad.
    // ------------------------------------------------------------
    logic [7:0] a_mem [0:A_BUFFER_BYTES-1];
    logic [7:0] b_mem [0:B_BUFFER_BYTES-1];

    // ------------------------------------------------------------
    // Internal status
    // ------------------------------------------------------------
    logic a_write_error_seen_q;
    logic b_write_error_seen_q;

    logic rd_pending_q;
    logic rd_operand_sel_q;
    logic [ADDR_WIDTH-1:0] rd_addr_q;

    logic [RD_DATA_WIDTH-1:0] rd_data_q;
    logic rd_data_valid_q;

    logic write_error_pulse_q;
    logic read_error_pulse_q;

    logic wr_fire;
    logic rd_fire;

    // ------------------------------------------------------------
    // Parameter checks
    // ------------------------------------------------------------
    function automatic bit is_power_of_two(input int value);
        return (value > 0) && ((value & (value - 1)) == 0);
    endfunction

    initial begin
        if (ADDR_WIDTH <= 0) begin
            $fatal(1, "gemm_operand_buffer: ADDR_WIDTH must be > 0");
        end

        if (WR_DATA_WIDTH <= 0 || (WR_DATA_WIDTH % 8) != 0) begin
            $fatal(1, "gemm_operand_buffer: WR_DATA_WIDTH must be positive and byte-aligned");
        end

        if (RD_DATA_WIDTH <= 0 || (RD_DATA_WIDTH % 8) != 0) begin
            $fatal(1, "gemm_operand_buffer: RD_DATA_WIDTH must be positive and byte-aligned");
        end

        if (!is_power_of_two(WR_BYTES)) begin
            $fatal(1, "gemm_operand_buffer: WR_BYTES must be a power of two");
        end

        if (!is_power_of_two(RD_BYTES)) begin
            $fatal(1, "gemm_operand_buffer: RD_BYTES must be a power of two");
        end

        if (A_BUFFER_BYTES <= 0) begin
            $fatal(1, "gemm_operand_buffer: A_BUFFER_BYTES must be > 0");
        end

        if (B_BUFFER_BYTES <= 0) begin
            $fatal(1, "gemm_operand_buffer: B_BUFFER_BYTES must be > 0");
        end
    end

    // ------------------------------------------------------------
    // Handshake
    // ------------------------------------------------------------
    always_comb begin
        wr_ready = 1'b1;

        // One outstanding read at a time.
        // This is enough for current GEMM local memory behavior.
        rd_ready = !rd_pending_q;

        wr_fire = wr_valid && wr_ready;
        rd_fire = rd_valid && rd_ready;

        wr_accept_pulse = wr_fire;
        rd_accept_pulse = rd_fire;
    end

    // ------------------------------------------------------------
    // Output assignments
    // ------------------------------------------------------------
    always_comb begin
        rd_data             = rd_data_q;
        rd_data_valid       = rd_data_valid_q;

        write_error_pulse   = write_error_pulse_q;
        read_error_pulse    = read_error_pulse_q;
    end

    // ------------------------------------------------------------
    // Address / range helpers
    // ------------------------------------------------------------
    function automatic bit valid_operand_sel(input logic operand_sel);
        return (operand_sel === OPERAND_A) || (operand_sel === OPERAND_B);
    endfunction

    function automatic bit write_in_range(
        input logic                     operand_sel,
        input logic [ADDR_WIDTH-1:0]    addr,
        input logic [WR_BYTES-1:0]      strb
    );
        int unsigned base_idx;
        int unsigned lane;
        bit ok;
    begin
        ok       = 1'b1;
        base_idx = int'(addr);

        if (!valid_operand_sel(operand_sel)) begin
            return 1'b0;
        end

        for (lane = 0; lane < WR_BYTES; lane++) begin
            if (strb[lane]) begin
                if (operand_sel === OPERAND_A) begin
                    if ((base_idx + lane) >= A_BUFFER_BYTES) begin
                        ok = 1'b0;
                    end
                end
                else begin
                    if ((base_idx + lane) >= B_BUFFER_BYTES) begin
                        ok = 1'b0;
                    end
                end
            end
        end

        return ok;
    end
    endfunction

    function automatic bit read_in_range(
        input logic                  operand_sel,
        input logic [ADDR_WIDTH-1:0] addr
    );
        int unsigned base_idx;
    begin
        base_idx = int'(addr);

        if (!valid_operand_sel(operand_sel)) begin
            return 1'b0;
        end

        // A local operand read is legal when its START byte lies inside the
        // selected operand buffer.  The returned RD_DATA_WIDTH container may
        // extend past the physical tail of the buffer; pack_read_data()
        // already zero-fills those out-of-range upper byte lanes.
        //
        // This keeps the local read contract aligned with GEMM's int8 operand
        // semantics: a valid final matrix element must not be rejected merely
        // because the 32-bit convenience container straddles the buffer tail.
        // A request whose START byte is outside the selected buffer remains
        // illegal and still generates the normal read-error response.
        if (operand_sel === OPERAND_A) begin
            return (base_idx < A_BUFFER_BYTES);
        end
        else begin
            return (base_idx < B_BUFFER_BYTES);
        end
    end
    endfunction

    function automatic bit operand_is_loaded(input logic operand_sel);
        if (operand_sel === OPERAND_A) begin
            return a_loaded;
        end
        else if (operand_sel === OPERAND_B) begin
            return b_loaded;
        end
        else begin
            return 1'b0;
        end
    endfunction

    function automatic logic [RD_DATA_WIDTH-1:0] pack_read_data(
        input logic                  operand_sel,
        input logic [ADDR_WIDTH-1:0] addr
    );
        logic [RD_DATA_WIDTH-1:0] data;
        int unsigned base_idx;
        int unsigned lane;
    begin
        data     = '0;
        base_idx = int'(addr);

        for (lane = 0; lane < RD_BYTES; lane++) begin
            if (operand_sel === OPERAND_A) begin
                if ((base_idx + lane) < A_BUFFER_BYTES) begin
                    data[8*lane +: 8] = a_mem[base_idx + lane];
                end
            end
            else begin
                if ((base_idx + lane) < B_BUFFER_BYTES) begin
                    data[8*lane +: 8] = b_mem[base_idx + lane];
                end
            end
        end

        return data;
    end
    endfunction

    // ------------------------------------------------------------
    // Main sequential logic
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            int unsigned i;

            a_loaded             <= 1'b0;
            b_loaded             <= 1'b0;

            a_written_beats      <= '0;
            b_written_beats      <= '0;
            read_count           <= '0;

            a_write_error_seen_q <= 1'b0;
            b_write_error_seen_q <= 1'b0;

            rd_pending_q         <= 1'b0;
            rd_operand_sel_q     <= OPERAND_A;
            rd_addr_q            <= '0;

            rd_data_q            <= '0;
            rd_data_valid_q      <= 1'b0;

            write_error_pulse_q  <= 1'b0;
            read_error_pulse_q   <= 1'b0;

            error                <= 1'b0;

            for (i = 0; i < A_BUFFER_BYTES; i++) begin
                a_mem[i] <= 8'h00;
            end

            for (i = 0; i < B_BUFFER_BYTES; i++) begin
                b_mem[i] <= 8'h00;
            end
        end
        else begin
            int unsigned base_idx;
            int unsigned lane;
            bit wr_ok;
            bit rd_ok;
            bit rd_loaded_ok;

            // Default one-cycle pulses.
            rd_data_valid_q     <= 1'b0;
            write_error_pulse_q <= 1'b0;
            read_error_pulse_q  <= 1'b0;

            // ----------------------------------------------------
            // Clear handling
            // ----------------------------------------------------
            if (clear_status || clear_all) begin
                error               <= 1'b0;
                write_error_pulse_q <= 1'b0;
                read_error_pulse_q  <= 1'b0;
            end

            if (clear_all || clear_a) begin
                a_loaded             <= 1'b0;
                a_written_beats      <= '0;
                a_write_error_seen_q <= 1'b0;
            end

            if (clear_all || clear_b) begin
                b_loaded             <= 1'b0;
                b_written_beats      <= '0;
                b_write_error_seen_q <= 1'b0;
            end

            if (clear_all) begin
                read_count      <= '0;
                rd_pending_q    <= 1'b0;
                rd_data_q       <= '0;
            end

            // ----------------------------------------------------
            // Write side
            // ----------------------------------------------------
            if (wr_fire) begin
                wr_ok    = write_in_range(wr_operand_sel, wr_addr, wr_strb);
                base_idx = int'(wr_addr);

                if (!wr_ok) begin
                    write_error_pulse_q <= 1'b1;
                    error               <= 1'b1;

                    if (wr_operand_sel === OPERAND_A) begin
                        a_write_error_seen_q <= 1'b1;
                    end
                    else if (wr_operand_sel === OPERAND_B) begin
                        b_write_error_seen_q <= 1'b1;
                    end
                end
                else begin
                    for (lane = 0; lane < WR_BYTES; lane++) begin
                        if (wr_strb[lane]) begin
                            if (wr_operand_sel === OPERAND_A) begin
                                a_mem[base_idx + lane] <= wr_data[8*lane +: 8];
                            end
                            else begin
                                b_mem[base_idx + lane] <= wr_data[8*lane +: 8];
                            end
                        end
                    end

                    if (wr_operand_sel === OPERAND_A) begin
                        a_written_beats <= a_written_beats + 32'd1;

                        if (wr_last && !a_write_error_seen_q) begin
                            a_loaded <= 1'b1;
                        end
                    end
                    else begin
                        b_written_beats <= b_written_beats + 32'd1;

                        if (wr_last && !b_write_error_seen_q) begin
                            b_loaded <= 1'b1;
                        end
                    end
                end
            end

            // ----------------------------------------------------
            // Read request accept
            // ----------------------------------------------------
            if (rd_fire) begin
                rd_pending_q     <= 1'b1;
                rd_operand_sel_q <= rd_operand_sel;
                rd_addr_q        <= rd_addr;
            end

            // ----------------------------------------------------
            // Read response generation
            //
            // One-cycle latency from rd_fire to rd_data_valid.
            // ----------------------------------------------------
            if (rd_pending_q) begin
                rd_ok        = read_in_range(rd_operand_sel_q, rd_addr_q);
                rd_loaded_ok = operand_is_loaded(rd_operand_sel_q);

                if (!rd_ok || !rd_loaded_ok) begin
                    rd_data_q          <= '0;
                    read_error_pulse_q <= 1'b1;
                    error              <= 1'b1;
                end
                else begin
                    rd_data_q <= pack_read_data(rd_operand_sel_q, rd_addr_q);
                end

                rd_data_valid_q <= 1'b1;
                read_count      <= read_count + 32'd1;
                rd_pending_q    <= 1'b0;
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
            if (write_error_pulse_q) begin
                $error(
                    "[gemm_operand_buffer] Write error: operand=%0d addr=0x%08h strb=0x%0h",
                    wr_operand_sel,
                    wr_addr,
                    wr_strb
                );
            end

            if (read_error_pulse_q) begin
                $error(
                    "[gemm_operand_buffer] Read error: operand=%0d addr=0x%08h a_loaded=%0b b_loaded=%0b",
                    rd_operand_sel_q,
                    rd_addr_q,
                    a_loaded,
                    b_loaded
                );
            end
        end
    end
`endif

endmodule

`endif