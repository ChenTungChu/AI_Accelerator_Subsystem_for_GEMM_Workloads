// File: tb/uvm/test/ai_accel_subsys_dma_store_error_test.sv

`ifndef AI_ACCEL_SUBSYS_DMA_STORE_ERROR_TEST_SV
`define AI_ACCEL_SUBSYS_DMA_STORE_ERROR_TEST_SV

class ai_accel_subsys_dma_store_error_test extends uvm_test;

    `uvm_component_utils(ai_accel_subsys_dma_store_error_test)

    // ------------------------------------------------------------
    // Local parameters
    // ------------------------------------------------------------
    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 64;
    localparam int ID_WIDTH   = 4;
    localparam int DIM_WIDTH  = 8;

    localparam int DMA_SRC_MEM_BYTES = 4096;
    localparam int DMA_DST_MEM_BYTES = 4096;

    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;

    localparam logic [1:0] AXI_RESP_OKAY  = 2'b00;
    localparam logic [1:0] AXI_BURST_INCR = 2'b01;

    localparam logic [ADDR_WIDTH-1:0] C_BASE_ADDR      = 32'h0000_0200;
    localparam logic [ADDR_WIDTH-1:0] DST_BASE_ADDR    = 32'h0000_0000;
    localparam logic [ADDR_WIDTH-1:0] SANITY_ADDR      = 32'h0000_0380;

    localparam int unsigned PATTERN_WORDS = 4;
    localparam int unsigned PATTERN_BYTES = PATTERN_WORDS * 4;

    typedef virtual ai_accel_subsys_ctrl_if #(
        .ADDR_WIDTH        (ADDR_WIDTH),
        .DIM_WIDTH         (DIM_WIDTH),
        .DMA_SRC_MEM_BYTES (DMA_SRC_MEM_BYTES),
        .DMA_DST_MEM_BYTES (DMA_DST_MEM_BYTES)
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
    // Optional knobs
    // ------------------------------------------------------------
    bit run_start_while_busy;

    // ------------------------------------------------------------
    // Test data
    // ------------------------------------------------------------
    logic [31:0] c_pattern [0:PATTERN_WORDS-1];

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_dma_store_error_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        int unsigned tmp;

        super.build_phase(phase);

        if (!uvm_config_db#(ctrl_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("DMA_STORE_ERR", "Failed to get ctrl vif from config_db")
        end

        if (!uvm_config_db#(axi0_vif_t)::get(this, "", "axi0_vif", axi0_vif)) begin
            `uvm_fatal("DMA_STORE_ERR", "Failed to get axi0_vif from config_db")
        end

        run_start_while_busy = 1'b0;

        if ($value$plusargs("RUN_START_WHILE_BUSY=%0d", tmp)) begin
            run_start_while_busy = (tmp != 0);
        end

        `uvm_info("DMA_STORE_ERR",
            $sformatf("run_start_while_busy=%0d", run_start_while_busy),
            UVM_MEDIUM)
    endfunction

    // ------------------------------------------------------------
    // Utility
    // ------------------------------------------------------------
    function automatic logic [DATA_WIDTH/8-1:0] full_strb();
        return {DATA_WIDTH/8{1'b1}};
    endfunction

    task automatic init_c_pattern();
    begin
        c_pattern[0] = 32'sd15;
        c_pattern[1] = -32'sd7;
        c_pattern[2] = 32'sd1234;
        c_pattern[3] = 32'sd50;
    end
    endtask

    // ------------------------------------------------------------
    // Wait for reset release
    // ------------------------------------------------------------
    task automatic wait_for_reset_release();
        `uvm_info("DMA_STORE_ERR", "Waiting for reset release", UVM_MEDIUM)

        do begin
            @(vif.cb_drv);
        end while ((vif.cb_drv.dma_rst_n !== 1'b1) ||
                   (vif.cb_drv.core_rst_n !== 1'b1));

        repeat (5) @(vif.cb_drv);

        `uvm_info("DMA_STORE_ERR", "Reset released", UVM_MEDIUM)
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

        vif.cb_drv.dma_store_start         <= 1'b0;
        vif.cb_drv.dma_store_src_base_addr <= '0;
        vif.cb_drv.dma_store_dst_base_addr <= '0;
        vif.cb_drv.dma_store_byte_count    <= '0;

        vif.cb_drv.tb_reset_override_en   <= 1'b0;
        vif.cb_drv.tb_dma_rst_n_override  <= 1'b1;
        vif.cb_drv.tb_core_rst_n_override <= 1'b1;

        vif.dma_src_set_rresp_error(1'b0, -1);
        vif.dma_dst_set_bresp_error(1'b0, -1);
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
                `uvm_fatal("DMA_STORE_ERR",
                    $sformatf("AXI0 write timeout waiting AW/W handshake addr=0x%08h",
                        addr))
            end
        end

        timeout = 0;

        while (!(axi0_vif.bvalid && axi0_vif.bready)) begin
            @(posedge axi0_vif.clk);
            timeout++;

            if (timeout > 2000) begin
                `uvm_fatal("DMA_STORE_ERR",
                    $sformatf("AXI0 write timeout waiting B response addr=0x%08h",
                        addr))
            end
        end

        if (axi0_vif.bresp !== AXI_RESP_OKAY) begin
            `uvm_fatal("DMA_STORE_ERR",
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
                `uvm_fatal("DMA_STORE_ERR",
                    $sformatf("AXI0 read timeout waiting AR handshake addr=0x%08h",
                        addr))
            end
        end

        @(posedge axi0_vif.clk);
        axi0_vif.arvalid <= 1'b0;

        timeout = 0;

        while (!(axi0_vif.rvalid && axi0_vif.rready)) begin
            @(posedge axi0_vif.clk);
            timeout++;

            if (timeout > 2000) begin
                `uvm_fatal("DMA_STORE_ERR",
                    $sformatf("AXI0 read timeout waiting R response addr=0x%08h",
                        addr))
            end
        end

        data = axi0_vif.rdata;

        if (axi0_vif.rresp !== AXI_RESP_OKAY) begin
            `uvm_fatal("DMA_STORE_ERR",
                $sformatf("AXI0 read RRESP error addr=0x%08h rresp=0x%0h",
                    addr, axi0_vif.rresp))
        end

        if (axi0_vif.rlast !== 1'b1) begin
            `uvm_fatal("DMA_STORE_ERR",
                $sformatf("AXI0 read expected RLAST=1 addr=0x%08h",
                    addr))
        end

        @(posedge axi0_vif.clk);

        axi0_vif.rready  <= 1'b0;
        axi0_vif.araddr  <= '0;
        axi0_vif.arvalid <= 1'b0;
    endtask

    // ------------------------------------------------------------
    // Preload known C data into scratchpad through host Port0
    // ------------------------------------------------------------
    task automatic preload_scratchpad_c_pattern();
        logic [DATA_WIDTH-1:0] beat0;
        logic [DATA_WIDTH-1:0] beat1;
    begin
        init_c_pattern();

        beat0 = {c_pattern[1], c_pattern[0]};
        beat1 = {c_pattern[3], c_pattern[2]};

        `uvm_info("DMA_STORE_ERR",
            $sformatf("Preloading scratchpad C pattern at base=0x%08h words=%0d",
                C_BASE_ADDR, PATTERN_WORDS),
            UVM_MEDIUM)

        axi0_write64(C_BASE_ADDR + ADDR_WIDTH'(0), beat0, full_strb());
        axi0_write64(C_BASE_ADDR + ADDR_WIDTH'(BYTES_PER_BEAT), beat1, full_strb());
    end
    endtask

    // ------------------------------------------------------------
    // Host Port0 sanity check after expected store errors
    // ------------------------------------------------------------
    task automatic host_port0_sanity_check(input string tag);
        logic [DATA_WIDTH-1:0] wr_data;
        logic [DATA_WIDTH-1:0] rd_data;
    begin
        wr_data = 64'h1122_3344_5566_7788;

        `uvm_info("DMA_STORE_ERR",
            $sformatf("Host Port0 sanity check after %s", tag),
            UVM_MEDIUM)

        axi0_write64(SANITY_ADDR, wr_data, full_strb());
        axi0_read64(SANITY_ADDR, rd_data);

        if (rd_data !== wr_data) begin
            `uvm_fatal("DMA_STORE_ERR",
                $sformatf("Host Port0 sanity mismatch after %s: got=0x%016h expected=0x%016h",
                    tag, rd_data, wr_data))
        end
    end
    endtask

    // ------------------------------------------------------------
    // Run one expected-error DMA store transaction
    // ------------------------------------------------------------
    task automatic run_expected_error_store(
        input string                 tag,
        input logic [ADDR_WIDTH-1:0] src_addr,
        input logic [ADDR_WIDTH-1:0] dst_addr,
        input int unsigned           byte_count,
        input bit                    inject_bresp_error
    );
        int unsigned timeout;
        bit done_seen;

        timeout   = 0;
        done_seen = 0;

        `uvm_info("DMA_STORE_ERR",
            $sformatf("Starting expected-error DMA store %s: src=0x%08h dst=0x%08h bytes=%0d inject_bresp=%0d",
                tag, src_addr, dst_addr, byte_count, inject_bresp_error),
            UVM_MEDIUM)

        if (inject_bresp_error) begin
            vif.dma_dst_set_bresp_error(1'b1, 0);
        end
        else begin
            vif.dma_dst_set_bresp_error(1'b0, -1);
        end

        @(vif.cb_drv);

        vif.cb_drv.dma_store_src_base_addr <= src_addr;
        vif.cb_drv.dma_store_dst_base_addr <= dst_addr;
        vif.cb_drv.dma_store_byte_count    <= byte_count[31:0];
        vif.cb_drv.dma_store_start         <= 1'b1;

        @(vif.cb_drv);

        vif.cb_drv.dma_store_start         <= 1'b0;

        while (!done_seen) begin
            @(vif.cb_drv);

            if (vif.cb_drv.dma_store_done === 1'b1) begin
                done_seen = 1;
            end

            timeout++;

            if (timeout > 10000) begin
                `uvm_fatal("DMA_STORE_ERR",
                    $sformatf("Timeout waiting for expected-error DMA store done: %s",
                        tag))
            end
        end

        if (vif.cb_drv.dma_store_error !== 1'b1) begin
            `uvm_fatal("DMA_STORE_ERR",
                $sformatf("Expected dma_store_error=1 at done, but got 0: %s",
                    tag))
        end

        if (inject_bresp_error) begin
            vif.dma_dst_set_bresp_error(1'b0, -1);
        end

        repeat (5) @(vif.cb_drv);

        if (vif.cb_drv.dma_store_busy !== 1'b0) begin
            `uvm_fatal("DMA_STORE_ERR",
                $sformatf("dma_store_busy did not clear after expected-error store: %s",
                    tag))
        end

        `uvm_info("DMA_STORE_ERR",
            $sformatf("PASS expected-error DMA store: %s", tag),
            UVM_MEDIUM)

        host_port0_sanity_check(tag);
    endtask

    // ------------------------------------------------------------
    // Optional: start while busy should flag store_error
    // ------------------------------------------------------------
    task automatic run_start_while_busy_error();
        int unsigned timeout;
        bit done_seen;
        bit busy_seen;

        timeout   = 0;
        done_seen = 0;
        busy_seen = 0;

        preload_scratchpad_c_pattern();
        vif.dma_dst_mem_clear();
        vif.dma_dst_set_bresp_error(1'b0, -1);

        `uvm_info("DMA_STORE_ERR",
            "Starting expected-error DMA store start_while_busy",
            UVM_MEDIUM)

        @(vif.cb_drv);

        vif.cb_drv.dma_store_src_base_addr <= C_BASE_ADDR;
        vif.cb_drv.dma_store_dst_base_addr <= DST_BASE_ADDR;
        vif.cb_drv.dma_store_byte_count    <= PATTERN_BYTES[31:0];
        vif.cb_drv.dma_store_start         <= 1'b1;

        @(vif.cb_drv);
        vif.cb_drv.dma_store_start         <= 1'b0;

        while (!busy_seen) begin
            @(vif.cb_drv);

            if (vif.cb_drv.dma_store_busy === 1'b1) begin
                busy_seen = 1;
            end

            timeout++;

            if (timeout > 1000) begin
                `uvm_fatal("DMA_STORE_ERR",
                    "Timeout waiting for dma_store_busy in start_while_busy test")
            end
        end

        // Inject a second start pulse while the first store is active.
        @(vif.cb_drv);
        vif.cb_drv.dma_store_start <= 1'b1;

        @(vif.cb_drv);
        vif.cb_drv.dma_store_start <= 1'b0;

        timeout = 0;

        while (!done_seen) begin
            @(vif.cb_drv);

            if (vif.cb_drv.dma_store_done === 1'b1) begin
                done_seen = 1;
            end

            timeout++;

            if (timeout > 10000) begin
                `uvm_fatal("DMA_STORE_ERR",
                    "Timeout waiting for start_while_busy DMA store done")
            end
        end

        if (vif.cb_drv.dma_store_error !== 1'b1) begin
            `uvm_fatal("DMA_STORE_ERR",
                "Expected dma_store_error=1 for start_while_busy")
        end

        repeat (5) @(vif.cb_drv);

        if (vif.cb_drv.dma_store_busy !== 1'b0) begin
            `uvm_fatal("DMA_STORE_ERR",
                "dma_store_busy did not clear after start_while_busy")
        end

        `uvm_info("DMA_STORE_ERR",
            "PASS expected-error DMA store: start_while_busy",
            UVM_MEDIUM)

        host_port0_sanity_check("start_while_busy");
    endtask

    // ------------------------------------------------------------
    // Valid recovery DMA store after previous expected errors
    // ------------------------------------------------------------
    task automatic run_valid_recovery_store();
        int unsigned timeout;
        bit done_seen;
        logic [31:0] got_word;
        logic [ADDR_WIDTH-1:0] addr;

        timeout   = 0;
        done_seen = 0;

        preload_scratchpad_c_pattern();

        vif.dma_dst_mem_clear();
        vif.dma_dst_set_bresp_error(1'b0, -1);

        `uvm_info("DMA_STORE_ERR",
            $sformatf("Starting valid recovery DMA store: src=0x%08h dst=0x%08h bytes=%0d",
                C_BASE_ADDR, DST_BASE_ADDR, PATTERN_BYTES),
            UVM_MEDIUM)

        @(vif.cb_drv);

        vif.cb_drv.dma_store_src_base_addr <= C_BASE_ADDR;
        vif.cb_drv.dma_store_dst_base_addr <= DST_BASE_ADDR;
        vif.cb_drv.dma_store_byte_count    <= PATTERN_BYTES[31:0];
        vif.cb_drv.dma_store_start         <= 1'b1;

        @(vif.cb_drv);

        vif.cb_drv.dma_store_start         <= 1'b0;

        while (!done_seen) begin
            @(vif.cb_drv);

            if (vif.cb_drv.dma_store_done === 1'b1) begin
                done_seen = 1;
            end

            timeout++;

            if (timeout > 10000) begin
                `uvm_fatal("DMA_STORE_ERR",
                    "Timeout waiting for valid recovery DMA store done")
            end
        end

        if (vif.cb_drv.dma_store_error !== 1'b0) begin
            `uvm_fatal("DMA_STORE_ERR",
                "Valid recovery DMA store reported error")
        end

        repeat (5) @(vif.cb_drv);

        if (vif.cb_drv.dma_store_busy !== 1'b0) begin
            `uvm_fatal("DMA_STORE_ERR",
                "dma_store_busy did not clear after valid recovery store")
        end

        for (int unsigned i = 0; i < PATTERN_WORDS; i++) begin
            addr     = DST_BASE_ADDR + ADDR_WIDTH'(i * 4);
            got_word = vif.dma_dst_mem_read_word32(addr);

            `uvm_info("DMA_STORE_ERR",
                $sformatf("Recovery DST_C[%0d]: got=0x%08h expected=0x%08h",
                    i, got_word, c_pattern[i]),
                UVM_MEDIUM)

            if (got_word !== c_pattern[i]) begin
                `uvm_fatal("DMA_STORE_ERR",
                    $sformatf("Recovery store mismatch at word %0d: got=0x%08h expected=0x%08h",
                        i, got_word, c_pattern[i]))
            end
        end

        `uvm_info("DMA_STORE_ERR",
            "PASS valid recovery DMA store after expected errors",
            UVM_LOW)
    endtask

    // ------------------------------------------------------------
    // Main run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        `uvm_info("DMA_STORE_ERR",
            "Starting ai_accel_subsys_dma_store_error_test",
            UVM_LOW)

        init_ctrl_outputs();
        init_axi0_outputs();

        wait_for_reset_release();

        // Prepare valid scratchpad data for tests that reach the
        // scratchpad-read / destination-write path.
        preload_scratchpad_c_pattern();
        vif.dma_dst_mem_clear();

        // --------------------------------------------------------
        // Argument validation errors
        // --------------------------------------------------------
        run_expected_error_store(
            "zero_byte_count",
            C_BASE_ADDR,
            DST_BASE_ADDR,
            0,
            1'b0
        );

        run_expected_error_store(
            "unaligned_src_addr",
            C_BASE_ADDR + ADDR_WIDTH'(1),
            DST_BASE_ADDR,
            PATTERN_BYTES,
            1'b0
        );

        run_expected_error_store(
            "unaligned_dst_addr",
            C_BASE_ADDR,
            DST_BASE_ADDR + ADDR_WIDTH'(1),
            PATTERN_BYTES,
            1'b0
        );

        // --------------------------------------------------------
        // Destination BRESP error injection
        // --------------------------------------------------------
        preload_scratchpad_c_pattern();
        vif.dma_dst_mem_clear();

        run_expected_error_store(
            "dst_bresp_error_first_beat",
            C_BASE_ADDR,
            DST_BASE_ADDR,
            PATTERN_BYTES,
            1'b1
        );

        // --------------------------------------------------------
        // Optional busy/start overlap error
        // --------------------------------------------------------
        if (run_start_while_busy) begin
            run_start_while_busy_error();
        end

        // --------------------------------------------------------
        // Valid recovery after all expected errors
        // --------------------------------------------------------
        run_valid_recovery_store();

        `uvm_info("DMA_STORE_ERR",
            "ai_accel_subsys_dma_store_error_test completed",
            UVM_LOW)

        phase.drop_objection(this);
    endtask

endclass

`endif