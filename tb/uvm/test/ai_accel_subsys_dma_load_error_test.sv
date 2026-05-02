// File: tb/uvm/test/ai_accel_subsys_dma_load_error_test.sv

`ifndef AI_ACCEL_SUBSYS_DMA_LOAD_ERROR_TEST_SV
`define AI_ACCEL_SUBSYS_DMA_LOAD_ERROR_TEST_SV

class ai_accel_subsys_dma_load_error_test extends uvm_test;

    `uvm_component_utils(ai_accel_subsys_dma_load_error_test)

    // ------------------------------------------------------------
    // Local parameters
    // ------------------------------------------------------------
    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 64;
    localparam int ID_WIDTH   = 4;
    localparam int DIM_WIDTH  = 8;

    localparam int DMA_SRC_MEM_BYTES = 4096;
    localparam int BYTES_PER_BEAT    = DATA_WIDTH / 8;

    localparam logic [1:0] AXI_RESP_OKAY  = 2'b00;
    localparam logic [1:0] AXI_BURST_INCR = 2'b01;

    typedef virtual ai_accel_subsys_ctrl_if #(
        .ADDR_WIDTH        (ADDR_WIDTH),
        .DIM_WIDTH         (DIM_WIDTH),
        .DMA_SRC_MEM_BYTES (DMA_SRC_MEM_BYTES)
    ) ctrl_vif_t;

    typedef virtual axi_mm_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .HAS_BURST  (1)
    ) axi0_vif_t;

    // ------------------------------------------------------------
    // Virtual interfaces
    // ------------------------------------------------------------
    ctrl_vif_t vif;
    axi0_vif_t axi0_vif;

    // ------------------------------------------------------------
    // Recovery case configuration
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] base_a;
    logic [ADDR_WIDTH-1:0] base_b;
    logic [ADDR_WIDTH-1:0] base_c;

    logic [ADDR_WIDTH-1:0] dma_src_a;
    logic [ADDR_WIDTH-1:0] dma_src_b;

    logic [7:0]  a_value;
    logic [7:0]  b_value;
    logic [31:0] expected_c;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_dma_load_error_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(ctrl_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("DMA_LOAD_ERR", "Failed to get ctrl vif from config_db")
        end

        if (!uvm_config_db#(axi0_vif_t)::get(this, "", "axi0_vif", axi0_vif)) begin
            `uvm_fatal("DMA_LOAD_ERR", "Failed to get axi0_vif from config_db")
        end

        // CASE_ID=100 style recovery case.
        base_a    = 32'h0000_0000;
        base_b    = 32'h0000_0100;
        base_c    = 32'h0000_0200;

        dma_src_a = 32'h0000_0000;
        dma_src_b = 32'h0000_0100;

        a_value    = 8'd3;
        b_value    = 8'd5;
        expected_c = 32'd15;
    endfunction

    // ------------------------------------------------------------
    // Wait for reset release
    // ------------------------------------------------------------
    task automatic wait_for_reset_release();
        `uvm_info("DMA_LOAD_ERR", "Waiting for reset release", UVM_MEDIUM)

        do begin
            @(vif.cb_drv);
        end while ((vif.cb_drv.dma_rst_n !== 1'b1) ||
                   (vif.cb_drv.core_rst_n !== 1'b1));

        repeat (5) @(vif.cb_drv);

        `uvm_info("DMA_LOAD_ERR", "Reset released", UVM_MEDIUM)
    endtask

    // ------------------------------------------------------------
    // Initialize ctrl_if outputs
    // ------------------------------------------------------------
    task automatic init_ctrl_outputs();
        @(vif.cb_drv);

        vif.cb_drv.acc_start <= 1'b0;

        vif.cb_drv.base_addr_a <= '0;
        vif.cb_drv.base_addr_b <= '0;
        vif.cb_drv.base_addr_c <= '0;

        vif.cb_drv.dim_m <= '0;
        vif.cb_drv.dim_n <= '0;
        vif.cb_drv.dim_k <= '0;

        vif.cb_drv.dma_load_start    <= 1'b0;
        vif.cb_drv.dma_src_base_addr <= '0;
        vif.cb_drv.dma_dst_base_addr <= '0;
        vif.cb_drv.dma_load_beats    <= '0;

        vif.dma_src_set_rresp_error(1'b0, -1);

        vif.cb_drv.tb_reset_override_en   <= 1'b0;
        vif.cb_drv.tb_dma_rst_n_override  <= 1'b1;
        vif.cb_drv.tb_core_rst_n_override <= 1'b1;
    endtask

    // ------------------------------------------------------------
    // Initialize raw AXI0 host interface outputs
    // ------------------------------------------------------------
    task automatic init_axi0_outputs();
        @(posedge axi0_vif.clk);

        axi0_vif.awid    <= '0;
        axi0_vif.awaddr  <= '0;
        axi0_vif.awlen   <= '0;
        axi0_vif.awsize  <= '0;
        axi0_vif.awburst <= '0;
        axi0_vif.awvalid <= 1'b0;

        axi0_vif.wdata   <= '0;
        axi0_vif.wstrb   <= '0;
        axi0_vif.wlast   <= 1'b0;
        axi0_vif.wvalid  <= 1'b0;

        axi0_vif.bready  <= 1'b0;

        axi0_vif.arid    <= '0;
        axi0_vif.araddr  <= '0;
        axi0_vif.arlen   <= '0;
        axi0_vif.arsize  <= '0;
        axi0_vif.arburst <= '0;
        axi0_vif.arvalid <= 1'b0;

        axi0_vif.rready  <= 1'b0;
    endtask

    // ------------------------------------------------------------
    // AXI0 single-beat write
    // ------------------------------------------------------------
    task automatic axi0_write64(
        input logic [ADDR_WIDTH-1:0]   addr,
        input logic [DATA_WIDTH-1:0]   data,
        input logic [DATA_WIDTH/8-1:0] strb
    );
        bit aw_done;
        bit w_done;
        int unsigned timeout;

        aw_done = 0;
        w_done  = 0;
        timeout = 0;

        @(posedge axi0_vif.clk);

        axi0_vif.awid    <= '0;
        axi0_vif.awaddr  <= addr;
        axi0_vif.awlen   <= 8'd0;
        axi0_vif.awsize  <= 3'd3;
        axi0_vif.awburst <= AXI_BURST_INCR;
        axi0_vif.awvalid <= 1'b1;

        axi0_vif.wdata   <= data;
        axi0_vif.wstrb   <= strb;
        axi0_vif.wlast   <= 1'b1;
        axi0_vif.wvalid  <= 1'b1;

        axi0_vif.bready  <= 1'b1;

        while (!(aw_done && w_done)) begin
            @(posedge axi0_vif.clk);

            if (!aw_done && axi0_vif.awvalid && axi0_vif.awready) begin
                aw_done = 1;
                axi0_vif.awvalid <= 1'b0;
            end

            if (!w_done && axi0_vif.wvalid && axi0_vif.wready) begin
                w_done = 1;
                axi0_vif.wvalid <= 1'b0;
            end

            timeout++;
            if (timeout > 2000) begin
                `uvm_fatal("DMA_LOAD_ERR",
                    $sformatf("AXI0 write timeout waiting AW/W handshake addr=0x%08h", addr))
            end
        end

        timeout = 0;
        while (!(axi0_vif.bvalid && axi0_vif.bready)) begin
            @(posedge axi0_vif.clk);
            timeout++;

            if (timeout > 2000) begin
                `uvm_fatal("DMA_LOAD_ERR",
                    $sformatf("AXI0 write timeout waiting B response addr=0x%08h", addr))
            end
        end

        if (axi0_vif.bresp !== AXI_RESP_OKAY) begin
            `uvm_fatal("DMA_LOAD_ERR",
                $sformatf("AXI0 write BRESP error addr=0x%08h bresp=0x%0h",
                    addr, axi0_vif.bresp))
        end

        @(posedge axi0_vif.clk);
        axi0_vif.bready  <= 1'b0;
        axi0_vif.wlast   <= 1'b0;
        axi0_vif.wstrb   <= '0;
        axi0_vif.wdata   <= '0;
        axi0_vif.awaddr  <= '0;
    endtask

    // ------------------------------------------------------------
    // AXI0 single-beat read
    // ------------------------------------------------------------
    task automatic axi0_read64(
        input  logic [ADDR_WIDTH-1:0] addr,
        output logic [DATA_WIDTH-1:0] data
    );
        int unsigned timeout;

        timeout = 0;
        data    = '0;

        @(posedge axi0_vif.clk);

        axi0_vif.arid    <= '0;
        axi0_vif.araddr  <= addr;
        axi0_vif.arlen   <= 8'd0;
        axi0_vif.arsize  <= 3'd3;
        axi0_vif.arburst <= AXI_BURST_INCR;
        axi0_vif.arvalid <= 1'b1;
        axi0_vif.rready  <= 1'b1;

        while (!(axi0_vif.arvalid && axi0_vif.arready)) begin
            @(posedge axi0_vif.clk);
            timeout++;

            if (timeout > 2000) begin
                `uvm_fatal("DMA_LOAD_ERR",
                    $sformatf("AXI0 read timeout waiting AR handshake addr=0x%08h", addr))
            end
        end

        @(posedge axi0_vif.clk);
        axi0_vif.arvalid <= 1'b0;

        timeout = 0;
        while (!(axi0_vif.rvalid && axi0_vif.rready)) begin
            @(posedge axi0_vif.clk);
            timeout++;

            if (timeout > 2000) begin
                `uvm_fatal("DMA_LOAD_ERR",
                    $sformatf("AXI0 read timeout waiting R response addr=0x%08h", addr))
            end
        end

        data = axi0_vif.rdata;

        if (axi0_vif.rresp !== AXI_RESP_OKAY) begin
            `uvm_fatal("DMA_LOAD_ERR",
                $sformatf("AXI0 read RRESP error addr=0x%08h rresp=0x%0h",
                    addr, axi0_vif.rresp))
        end

        if (axi0_vif.rlast !== 1'b1) begin
            `uvm_fatal("DMA_LOAD_ERR",
                $sformatf("AXI0 read expected RLAST=1 addr=0x%08h", addr))
        end

        @(posedge axi0_vif.clk);
        axi0_vif.rready  <= 1'b0;
        axi0_vif.araddr  <= '0;
        axi0_vif.arvalid <= 1'b0;
    endtask

    // ------------------------------------------------------------
    // Host Port0 sanity check
    //
    // This checks that after DMA error, Port0 ownership has returned
    // to host mode and the host AXI path is not deadlocked.
    // ------------------------------------------------------------
    task automatic host_port0_sanity_check(input string tag);
        logic [DATA_WIDTH-1:0] rd;
        logic [DATA_WIDTH-1:0] exp;
        logic [ADDR_WIDTH-1:0] addr;
    begin
        addr = 32'h0000_0300;
        exp  = 64'h1122_3344_5566_7788;

        `uvm_info("DMA_LOAD_ERR",
            $sformatf("Host Port0 sanity check after %s", tag),
            UVM_MEDIUM)

        axi0_write64(addr, exp, 8'hFF);
        axi0_read64(addr, rd);

        if (rd !== exp) begin
            `uvm_fatal("DMA_LOAD_ERR",
                $sformatf("Host Port0 sanity mismatch after %s: got=0x%016h exp=0x%016h",
                    tag, rd, exp))
        end
    end
    endtask

    // ------------------------------------------------------------
    // Launch DMA and expect error
    // ------------------------------------------------------------
    task automatic expect_dma_error(
        input string                 tag,
        input logic [ADDR_WIDTH-1:0] src_addr,
        input logic [ADDR_WIDTH-1:0] dst_addr,
        input logic [31:0]           beats
    );
        int unsigned timeout;
        bit done_seen;
        bit error_at_done;
    begin
        timeout       = 0;
        done_seen     = 0;
        error_at_done = 0;

        `uvm_info("DMA_LOAD_ERR",
            $sformatf("Starting expected-error DMA load %s: src=0x%08h dst=0x%08h beats=%0d",
                tag, src_addr, dst_addr, beats),
            UVM_MEDIUM)

        @(vif.cb_drv);
        vif.cb_drv.dma_src_base_addr <= src_addr;
        vif.cb_drv.dma_dst_base_addr <= dst_addr;
        vif.cb_drv.dma_load_beats    <= beats;
        vif.cb_drv.dma_load_start    <= 1'b1;

        @(vif.cb_drv);
        if (vif.cb_drv.dma_load_done === 1'b1) begin
            done_seen     = 1;
            error_at_done = (vif.cb_drv.dma_load_error === 1'b1);
        end
        vif.cb_drv.dma_load_start <= 1'b0;

        while (!done_seen) begin
            @(vif.cb_drv);

            if (vif.cb_drv.dma_load_done === 1'b1) begin
                done_seen     = 1;
                error_at_done = (vif.cb_drv.dma_load_error === 1'b1);
            end

            timeout++;
            if (timeout > 5000) begin
                `uvm_fatal("DMA_LOAD_ERR",
                    $sformatf("Timeout waiting for expected-error DMA done: %s", tag))
            end
        end

        if (!error_at_done) begin
            `uvm_fatal("DMA_LOAD_ERR",
                $sformatf("Expected dma_load_error=1 at done, but got 0: %s", tag))
        end

        repeat (5) @(vif.cb_drv);

        if (vif.cb_drv.dma_load_busy !== 1'b0) begin
            `uvm_fatal("DMA_LOAD_ERR",
                $sformatf("dma_load_busy did not clear after expected error: %s", tag))
        end

        `uvm_info("DMA_LOAD_ERR",
            $sformatf("PASS expected-error DMA load: %s", tag),
            UVM_LOW)

        host_port0_sanity_check(tag);
    end
    endtask

    // ------------------------------------------------------------
    // Launch valid DMA and expect success
    // ------------------------------------------------------------
    task automatic run_valid_dma_load(
        input string                 tag,
        input logic [ADDR_WIDTH-1:0] src_addr,
        input logic [ADDR_WIDTH-1:0] dst_addr,
        input logic [31:0]           beats
    );
        int unsigned timeout;
        bit done_seen;
        bit error_at_done;
    begin
        timeout       = 0;
        done_seen     = 0;
        error_at_done = 0;

        `uvm_info("DMA_LOAD_ERR",
            $sformatf("Starting valid DMA load %s: src=0x%08h dst=0x%08h beats=%0d",
                tag, src_addr, dst_addr, beats),
            UVM_MEDIUM)

        @(vif.cb_drv);
        vif.cb_drv.dma_src_base_addr <= src_addr;
        vif.cb_drv.dma_dst_base_addr <= dst_addr;
        vif.cb_drv.dma_load_beats    <= beats;
        vif.cb_drv.dma_load_start    <= 1'b1;

        @(vif.cb_drv);
        if (vif.cb_drv.dma_load_done === 1'b1) begin
            done_seen     = 1;
            error_at_done = (vif.cb_drv.dma_load_error === 1'b1);
        end
        vif.cb_drv.dma_load_start <= 1'b0;

        while (!done_seen) begin
            @(vif.cb_drv);

            if (vif.cb_drv.dma_load_done === 1'b1) begin
                done_seen     = 1;
                error_at_done = (vif.cb_drv.dma_load_error === 1'b1);
            end

            timeout++;
            if (timeout > 10000) begin
                `uvm_fatal("DMA_LOAD_ERR",
                    $sformatf("Timeout waiting for valid DMA done: %s", tag))
            end
        end

        if (error_at_done) begin
            `uvm_fatal("DMA_LOAD_ERR",
                $sformatf("Unexpected dma_load_error=1 for valid DMA load: %s", tag))
        end

        repeat (5) @(vif.cb_drv);

        if (vif.cb_drv.dma_load_busy !== 1'b0) begin
            `uvm_fatal("DMA_LOAD_ERR",
                $sformatf("dma_load_busy did not clear after valid DMA load: %s", tag))
        end

        `uvm_info("DMA_LOAD_ERR",
            $sformatf("Completed valid DMA load %s", tag),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Clear C
    // ------------------------------------------------------------
    task automatic clear_c_region();
        `uvm_info("DMA_LOAD_ERR",
            $sformatf("Clearing C: base_c=0x%08h", base_c),
            UVM_MEDIUM)

        axi0_write64(base_c, 64'h0000_0000_0000_0000, 8'hFF);
    endtask

    // ------------------------------------------------------------
    // Preload DMA source memory for recovery case
    // ------------------------------------------------------------
    task automatic preload_recovery_source_memory();
    begin
        `uvm_info("DMA_LOAD_ERR",
            $sformatf("Preloading recovery source memory: A=%0d B=%0d",
                a_value, b_value),
            UVM_MEDIUM)

        vif.dma_src_mem_clear();

        vif.dma_src_mem_write_byte(dma_src_a, a_value);
        vif.dma_src_mem_write_byte(dma_src_b, b_value);
    end
    endtask

    // ------------------------------------------------------------
    // Run GEMM recovery case
    // ------------------------------------------------------------
    task automatic run_gemm_recovery();
        int unsigned timeout;
        bit done_seen;
    begin
        timeout   = 0;
        done_seen = 0;

        `uvm_info("DMA_LOAD_ERR", "Starting recovery GEMM CASE_ID=100", UVM_MEDIUM)

        @(vif.cb_drv);
        vif.cb_drv.base_addr_a <= base_a;
        vif.cb_drv.base_addr_b <= base_b;
        vif.cb_drv.base_addr_c <= base_c;
        vif.cb_drv.dim_m       <= 8'd1;
        vif.cb_drv.dim_n       <= 8'd1;
        vif.cb_drv.dim_k       <= 8'd1;

        repeat (2) @(vif.cb_drv);

        vif.cb_drv.acc_start <= 1'b1;
        @(vif.cb_drv);
        vif.cb_drv.acc_start <= 1'b0;

        while (!done_seen) begin
            @(vif.cb_drv);

            if (vif.cb_drv.acc_done === 1'b1) begin
                done_seen = 1;
            end

            timeout++;
            if (timeout > 10000) begin
                `uvm_fatal("DMA_LOAD_ERR", "Timeout waiting for recovery acc_done")
            end
        end

        repeat (5) @(vif.cb_drv);

        `uvm_info("DMA_LOAD_ERR", "Recovery GEMM completed", UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Readback and compare recovery C
    // ------------------------------------------------------------
    task automatic readback_and_compare_recovery_c();
        logic [DATA_WIDTH-1:0] rd;
        logic [31:0] got_c;
    begin
        axi0_read64(base_c, rd);
        got_c = rd[31:0];

        `uvm_info("DMA_LOAD_ERR",
            $sformatf("Recovery C readback: raw=0x%016h got=%0d expected=%0d",
                rd, got_c, expected_c),
            UVM_MEDIUM)

        if (got_c !== expected_c) begin
            `uvm_fatal("DMA_LOAD_ERR",
                $sformatf("Recovery C mismatch: got=0x%08h expected=0x%08h",
                    got_c, expected_c))
        end

        `uvm_info("DMA_LOAD_ERR",
            $sformatf("PASS recovery GEMM after DMA errors: C=%0d", got_c),
            UVM_LOW)
    end
    endtask

    // ------------------------------------------------------------
    // Run invalid launch scenarios
    // ------------------------------------------------------------
    task automatic run_invalid_launch_tests();
    begin
        expect_dma_error(
            "zero_load_beats",
            32'h0000_0000,
            32'h0000_0000,
            32'd0
        );

        expect_dma_error(
            "unaligned_src_addr",
            32'h0000_0001,
            32'h0000_0000,
            32'd1
        );

        expect_dma_error(
            "unaligned_dst_addr",
            32'h0000_0000,
            32'h0000_0001,
            32'd1
        );
    end
    endtask

    // ------------------------------------------------------------
    // Run DMA source RRESP error scenario
    //
    // This is a valid-looking DMA load request:
    //   - aligned src
    //   - aligned dst
    //   - non-zero beats
    //
    // The TB source memory responder injects SLVERR on the first
    // source read response. Expected:
    //   - dma_load_done  = 1
    //   - dma_load_error = 1
    //   - dma_load_busy clears
    //   - Port0 returns to host ownership
    // ------------------------------------------------------------
    task automatic run_source_rresp_error_test();
    begin
        `uvm_info("DMA_LOAD_ERR",
            "Starting source RRESP error injection test",
            UVM_MEDIUM)

        // Prepare legal source payload. The injected RRESP error,
        // not the address/data itself, should cause the failure.
        vif.dma_src_mem_clear();
        vif.dma_src_mem_write_byte(dma_src_a, a_value);

        // Inject SLVERR on the first source read response.
        vif.dma_src_set_rresp_error(1'b1, 0);

        expect_dma_error(
            "source_rresp_error_first_beat",
            dma_src_a,
            base_a,
            32'd1
        );

        // Disable injection before recovery test.
        vif.dma_src_set_rresp_error(1'b0, -1);

        repeat (5) @(vif.cb_drv);

        `uvm_info("DMA_LOAD_ERR",
            "PASS source RRESP error injection test",
            UVM_LOW)
    end
    endtask

    // ------------------------------------------------------------
    // Run recovery after errors
    // ------------------------------------------------------------
    task automatic run_recovery_after_errors();
    begin
        clear_c_region();
        preload_recovery_source_memory();

        run_valid_dma_load("recovery_A", dma_src_a, base_a, 32'd1);
        run_valid_dma_load("recovery_B", dma_src_b, base_b, 32'd1);

        run_gemm_recovery();
        readback_and_compare_recovery_c();
    end
    endtask

    // ------------------------------------------------------------
    // Main run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        `uvm_info("DMA_LOAD_ERR", "Starting ai_accel_subsys_dma_load_error_test", UVM_LOW)

        init_ctrl_outputs();
        init_axi0_outputs();

        wait_for_reset_release();

        run_invalid_launch_tests();
        run_source_rresp_error_test();
        run_recovery_after_errors();

        `uvm_info("DMA_LOAD_ERR", "ai_accel_subsys_dma_load_error_test completed", UVM_LOW)

        phase.drop_objection(this);
    endtask

endclass

`endif