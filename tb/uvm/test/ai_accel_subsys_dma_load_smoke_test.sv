// File: tb/uvm/test/ai_accel_subsys_dma_load_smoke_test.sv

`ifndef AI_ACCEL_SUBSYS_DMA_LOAD_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_DMA_LOAD_SMOKE_TEST_SV

class ai_accel_subsys_dma_load_smoke_test extends uvm_test;

    `uvm_component_utils(ai_accel_subsys_dma_load_smoke_test)

    // ------------------------------------------------------------
    // Local parameters
    // ------------------------------------------------------------
    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 64;
    localparam int ID_WIDTH   = 4;

    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;

    localparam logic [1:0] AXI_RESP_OKAY = 2'b00;
    localparam logic [1:0] AXI_BURST_INCR = 2'b01;

    typedef virtual ai_accel_subsys_ctrl_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DIM_WIDTH  (8)
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
    // Test configuration
    // ------------------------------------------------------------
    int unsigned case_id;

    logic [ADDR_WIDTH-1:0] base_a;
    logic [ADDR_WIDTH-1:0] base_b;
    logic [ADDR_WIDTH-1:0] base_c;

    logic [ADDR_WIDTH-1:0] dma_src_a;
    logic [ADDR_WIDTH-1:0] dma_src_b;

    logic [7:0] a_value;
    logic [7:0] b_value;
    logic [31:0] expected_c;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_dma_load_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(ctrl_vif_t)::get(this, "", "vif", vif)) begin
            `uvm_fatal("DMA_LOAD_SMOKE", "Failed to get ctrl vif from config_db")
        end

        if (!uvm_config_db#(axi0_vif_t)::get(this, "", "axi0_vif", axi0_vif)) begin
            `uvm_fatal("DMA_LOAD_SMOKE", "Failed to get axi0_vif from config_db")
        end

        if (!$value$plusargs("CASE_ID=%0d", case_id)) begin
            case_id = 100;
        end

        if (case_id != 100) begin
            `uvm_warning("DMA_LOAD_SMOKE",
                $sformatf("Only CASE_ID=100 is supported in v1. Overriding CASE_ID=%0d to 100.", case_id))
            case_id = 100;
        end

        // CASE_ID=100 equivalent:
        //   dim=(1,1,1)
        //   A: 1 byte
        //   B: 1 byte
        //   C: 1 int32 result
        base_a    = 32'h0000_0000;
        base_b    = 32'h0000_0100;
        base_c    = 32'h0000_0200;

        dma_src_a = 32'h0000_0000;
        dma_src_b = 32'h0000_0100;

        // Use small positive values to avoid signed/overflow ambiguity.
        a_value    = 8'd3;
        b_value    = 8'd5;
        expected_c = 32'd15;
    endfunction

    // ------------------------------------------------------------
    // Wait for reset release
    // ------------------------------------------------------------
    task automatic wait_for_reset_release();
        `uvm_info("DMA_LOAD_SMOKE", "Waiting for reset release", UVM_MEDIUM)

        do begin
            @(vif.cb_drv);
        end while ((vif.cb_drv.dma_rst_n !== 1'b1) ||
                   (vif.cb_drv.core_rst_n !== 1'b1));

        repeat (5) @(vif.cb_drv);

        `uvm_info("DMA_LOAD_SMOKE", "Reset released", UVM_MEDIUM)
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
        axi0_vif.awsize  <= 3'd3;          // 8 bytes / beat
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
            if (timeout > 1000) begin
                `uvm_fatal("DMA_LOAD_SMOKE",
                    $sformatf("AXI0 write timeout waiting AW/W handshake addr=0x%08h", addr))
            end
        end

        timeout = 0;
        while (!(axi0_vif.bvalid && axi0_vif.bready)) begin
            @(posedge axi0_vif.clk);
            timeout++;

            if (timeout > 1000) begin
                `uvm_fatal("DMA_LOAD_SMOKE",
                    $sformatf("AXI0 write timeout waiting B response addr=0x%08h", addr))
            end
        end

        if (axi0_vif.bresp !== AXI_RESP_OKAY) begin
            `uvm_fatal("DMA_LOAD_SMOKE",
                $sformatf("AXI0 write BRESP error addr=0x%08h bresp=0x%0h",
                    addr, axi0_vif.bresp))
        end

        @(posedge axi0_vif.clk);
        axi0_vif.bready <= 1'b0;
        axi0_vif.wlast  <= 1'b0;
        axi0_vif.wstrb  <= '0;
        axi0_vif.wdata  <= '0;
        axi0_vif.awaddr <= '0;
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
        axi0_vif.arsize  <= 3'd3;          // 8 bytes / beat
        axi0_vif.arburst <= AXI_BURST_INCR;
        axi0_vif.arvalid <= 1'b1;
        axi0_vif.rready  <= 1'b1;

        while (!(axi0_vif.arvalid && axi0_vif.arready)) begin
            @(posedge axi0_vif.clk);
            timeout++;

            if (timeout > 1000) begin
                `uvm_fatal("DMA_LOAD_SMOKE",
                    $sformatf("AXI0 read timeout waiting AR handshake addr=0x%08h", addr))
            end
        end

        @(posedge axi0_vif.clk);
        axi0_vif.arvalid <= 1'b0;

        timeout = 0;
        while (!(axi0_vif.rvalid && axi0_vif.rready)) begin
            @(posedge axi0_vif.clk);
            timeout++;

            if (timeout > 1000) begin
                `uvm_fatal("DMA_LOAD_SMOKE",
                    $sformatf("AXI0 read timeout waiting R response addr=0x%08h", addr))
            end
        end

        data = axi0_vif.rdata;

        if (axi0_vif.rresp !== AXI_RESP_OKAY) begin
            `uvm_fatal("DMA_LOAD_SMOKE",
                $sformatf("AXI0 read RRESP error addr=0x%08h rresp=0x%0h",
                    addr, axi0_vif.rresp))
        end

        if (axi0_vif.rlast !== 1'b1) begin
            `uvm_fatal("DMA_LOAD_SMOKE",
                $sformatf("AXI0 read expected RLAST=1 addr=0x%08h", addr))
        end

        @(posedge axi0_vif.clk);
        axi0_vif.rready  <= 1'b0;
        axi0_vif.araddr  <= '0;
        axi0_vif.arvalid <= 1'b0;
    endtask

    // ------------------------------------------------------------
    // Host clear C
    // ------------------------------------------------------------
    task automatic clear_c_region();
        `uvm_info("DMA_LOAD_SMOKE",
            $sformatf("Clearing C via AXI0: base_c=0x%08h", base_c),
            UVM_MEDIUM)

        // CASE_ID=100 has one int32 C element.
        // Clear full 64-bit beat to make debug easier.
        axi0_write64(base_c, 64'h0000_0000_0000_0000, 8'hFF);
    endtask

    // ------------------------------------------------------------
    // Fill DMA source memory through top-level helper task
    // ------------------------------------------------------------
    task automatic preload_dma_source_memory();
        `uvm_info("DMA_LOAD_SMOKE",
            $sformatf("Preloading DMA source memory: A src=0x%08h value=%0d, B src=0x%08h value=%0d",
                dma_src_a, a_value, dma_src_b, b_value),
            UVM_MEDIUM)

        // These tasks live in ai_accel_subsys_uvm_top.sv.
        // The source memory responder is byte-addressed.
        vif.dma_src_mem_clear();

        vif.dma_src_mem_write_byte(dma_src_a, a_value);
        vif.dma_src_mem_write_byte(dma_src_b, b_value);
    endtask

    // ------------------------------------------------------------
    // Launch one DMA load job
    // ------------------------------------------------------------
    task automatic run_dma_load(
        input string                  tag,
        input logic [ADDR_WIDTH-1:0]  src_addr,
        input logic [ADDR_WIDTH-1:0]  dst_addr,
        input logic [31:0]            beats
    );
        int unsigned timeout;
        bit done_seen;

        timeout   = 0;
        done_seen = 0;

        `uvm_info("DMA_LOAD_SMOKE",
            $sformatf("Starting DMA load %s: src=0x%08h dst=0x%08h beats=%0d",
                tag, src_addr, dst_addr, beats),
            UVM_MEDIUM)

        @(vif.cb_drv);
        vif.cb_drv.dma_src_base_addr <= src_addr;
        vif.cb_drv.dma_dst_base_addr <= dst_addr;
        vif.cb_drv.dma_load_beats    <= beats;
        vif.cb_drv.dma_load_start    <= 1'b1;

        @(vif.cb_drv);
        vif.cb_drv.dma_load_start    <= 1'b0;

        while (!done_seen) begin
            @(vif.cb_drv);

            if (vif.cb_drv.dma_load_done === 1'b1) begin
                done_seen = 1;
            end

            timeout++;
            if (timeout > 5000) begin
                `uvm_fatal("DMA_LOAD_SMOKE",
                    $sformatf("Timeout waiting for DMA load done: %s", tag))
            end
        end

        if (vif.cb_drv.dma_load_error !== 1'b0) begin
            `uvm_fatal("DMA_LOAD_SMOKE",
                $sformatf("DMA load reported error: %s", tag))
        end

        // Let Port0 owner mux return to host mode.
        repeat (5) @(vif.cb_drv);

        if (vif.cb_drv.dma_load_busy !== 1'b0) begin
            `uvm_fatal("DMA_LOAD_SMOKE",
                $sformatf("DMA load busy did not clear after done: %s", tag))
        end

        `uvm_info("DMA_LOAD_SMOKE",
            $sformatf("Completed DMA load %s", tag),
            UVM_MEDIUM)
    endtask

    // ------------------------------------------------------------
    // Configure and start GEMM
    // ------------------------------------------------------------
    task automatic run_gemm();
        int unsigned timeout;
        bit done_seen;

        timeout   = 0;
        done_seen = 0;

        `uvm_info("DMA_LOAD_SMOKE", "Starting GEMM after DMA-loaded A/B", UVM_MEDIUM)

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
                `uvm_fatal("DMA_LOAD_SMOKE", "Timeout waiting for acc_done")
            end
        end

        repeat (5) @(vif.cb_drv);

        `uvm_info("DMA_LOAD_SMOKE", "GEMM completed", UVM_MEDIUM)
    endtask

    // ------------------------------------------------------------
    // Readback and compare C
    // ------------------------------------------------------------
    task automatic readback_and_compare_c();
        logic [DATA_WIDTH-1:0] read_word;
        logic [31:0]           got_c;

        axi0_read64(base_c, read_word);
        got_c = read_word[31:0];

        `uvm_info("DMA_LOAD_SMOKE",
            $sformatf("C readback: raw=0x%016h got=%0d expected=%0d",
                read_word, got_c, expected_c),
            UVM_MEDIUM)

        if (got_c !== expected_c) begin
            `uvm_fatal("DMA_LOAD_SMOKE",
                $sformatf("C mismatch: got=0x%08h expected=0x%08h",
                    got_c, expected_c))
        end

        `uvm_info("DMA_LOAD_SMOKE",
            $sformatf("PASS: DMA-loaded GEMM CASE_ID=%0d A=%0d B=%0d C=%0d",
                case_id, a_value, b_value, got_c),
            UVM_LOW)
    endtask

    // ------------------------------------------------------------
    // Main run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        `uvm_info("DMA_LOAD_SMOKE", "Starting ai_accel_subsys_dma_load_smoke_test", UVM_LOW)

        init_ctrl_outputs();
        init_axi0_outputs();

        wait_for_reset_release();

        clear_c_region();
        preload_dma_source_memory();

        // DMA load A and B into scratchpad.
        // load_beats=1 because dma_load_engine v1 transfers 64-bit beats.
        run_dma_load("A", dma_src_a, base_a, 32'd1);
        run_dma_load("B", dma_src_b, base_b, 32'd1);

        run_gemm();
        readback_and_compare_c();

        `uvm_info("DMA_LOAD_SMOKE", "ai_accel_subsys_dma_load_smoke_test completed", UVM_LOW)

        phase.drop_objection(this);
    endtask

endclass

`endif