// File: tb/uvm/driver/axi_mm_host_driver.sv
`ifndef AXI_MM_HOST_DRIVER_SV
`define AXI_MM_HOST_DRIVER_SV

class axi_mm_host_driver extends uvm_driver #(axi_mm_host_seq_item);
    `uvm_component_utils(axi_mm_host_driver)

    // ------------------------------------------------------------
    // AXI host vif typedef
    //   Must match ai_accel_subsys_uvm_top.sv / smoke_test.sv
    // ------------------------------------------------------------
    typedef virtual axi_mm_if #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (64),
        .ID_WIDTH   (4),
        .HAS_BURST  (1)
    ) axi0_vif_t;

    // ------------------------------------------------------------
    // Local protocol constants
    //   Current subsystem host path uses 64-bit AXI data width
    // ------------------------------------------------------------
    localparam int unsigned ADDR_WIDTH    = 32;
    localparam int unsigned DATA_WIDTH    = 64;
    localparam int unsigned BYTE_PER_WORD = DATA_WIDTH / 8;
    localparam int unsigned WORD_LSB_W    = (BYTE_PER_WORD > 1) ? $clog2(BYTE_PER_WORD) : 1;

    // ------------------------------------------------------------
    // Virtual interface
    // ------------------------------------------------------------
    axi0_vif_t vif;

    // ------------------------------------------------------------
    // Debug / bookkeeping
    // ------------------------------------------------------------
    bit          enable_log;
    int unsigned completed_item_count;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "axi_mm_host_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(axi0_vif_t)::get(this, "", "axi0_vif", vif)) begin
            `uvm_fatal("AXI_HOST_DRV/NOVIF",
                "axi0_vif is not set for axi_mm_host_driver")
        end

        enable_log           = 1'b1;
        completed_item_count = 0;

        void'(uvm_config_db#(bit)::get(this, "", "enable_log", enable_log));
    endfunction

    // ------------------------------------------------------------
    // Wait until AXI reset is released
    // ------------------------------------------------------------
    task automatic wait_for_reset_release();
        @(posedge vif.clk);
        while (vif.rst_n !== 1'b1) begin
            @(posedge vif.clk);
        end
    endtask

    // ------------------------------------------------------------
    // Drive all host interface outputs to idle
    // ------------------------------------------------------------
    task automatic drive_idle();
    begin
        vif.awid    <= '0;
        vif.awaddr  <= '0;
        vif.awlen   <= '0;
        vif.awsize  <= '0;
        vif.awburst <= '0;
        vif.awvalid <= 1'b0;

        vif.wdata   <= '0;
        vif.wstrb   <= '0;
        vif.wlast   <= 1'b0;
        vif.wvalid  <= 1'b0;

        vif.bready  <= 1'b0;

        vif.arid    <= '0;
        vif.araddr  <= '0;
        vif.arlen   <= '0;
        vif.arsize  <= '0;
        vif.arburst <= '0;
        vif.arvalid <= 1'b0;

        vif.rready  <= 1'b0;
    end
    endtask

    // ------------------------------------------------------------
    // AXI single-beat write
    // ------------------------------------------------------------
    task automatic host_axi_write_word(
        input bit [ADDR_WIDTH-1:0]      addr,
        input bit [DATA_WIDTH-1:0]      data,
        input bit [BYTE_PER_WORD-1:0]   strb
    );
    begin
        @(posedge vif.clk);
        vif.awid    <= '0;
        vif.awaddr  <= addr;
        vif.awlen   <= 8'd0;
        vif.awsize  <= WORD_LSB_W[2:0];
        vif.awburst <= 2'b01;
        vif.awvalid <= 1'b1;

        do @(posedge vif.clk); while (!vif.awready);
        vif.awvalid <= 1'b0;

        vif.wdata   <= data;
        vif.wstrb   <= strb;
        vif.wlast   <= 1'b1;
        vif.wvalid  <= 1'b1;

        do @(posedge vif.clk); while (!vif.wready);
        vif.wvalid  <= 1'b0;
        vif.wlast   <= 1'b0;
        vif.wdata   <= '0;
        vif.wstrb   <= '0;

        vif.bready  <= 1'b1;
        do @(posedge vif.clk); while (!vif.bvalid);
        @(posedge vif.clk);
        vif.bready  <= 1'b0;
    end
    endtask

    // ------------------------------------------------------------
    // AXI single-beat read
    // ------------------------------------------------------------
    task automatic host_axi_read_word(
        input  bit [ADDR_WIDTH-1:0]     addr,
        output bit [DATA_WIDTH-1:0]     data
    );
    begin
        @(posedge vif.clk);
        vif.arid    <= '0;
        vif.araddr  <= addr;
        vif.arlen   <= 8'd0;
        vif.arsize  <= WORD_LSB_W[2:0];
        vif.arburst <= 2'b01;
        vif.arvalid <= 1'b1;

        do @(posedge vif.clk); while (!vif.arready);
        vif.arvalid <= 1'b0;

        vif.rready  <= 1'b1;
        do @(posedge vif.clk); while (!vif.rvalid);

        data = vif.rdata;

        @(posedge vif.clk);
        vif.rready <= 1'b0;
    end
    endtask

    // ------------------------------------------------------------
    // AXI raw multi-beat write burst
    // ------------------------------------------------------------
    task automatic host_axi_write_burst(
        input axi_mm_host_seq_item item
    );
        int unsigned i;
        int unsigned repeat_idx;
        int unsigned rsp_idx;
        int unsigned hold_idx;
        bit [ADDR_WIDTH-1:0] repeated_addr;
    begin
        // Keep BREADY low while issuing all repeated bursts.  For the
        // default repeat_count=1 / hold_cycles=0 case this preserves the
        // original single-burst behavior except for making the idle value
        // explicit before AW.
        vif.bready <= 1'b0;

        for (repeat_idx = 0;
             repeat_idx < item.burst_repeat_count;
             repeat_idx++) begin

            repeated_addr =
                item.addr + (repeat_idx * item.burst_repeat_stride_bytes);

            @(posedge vif.clk);
            vif.awid    <= '0;
            vif.awaddr  <= repeated_addr;
            vif.awlen   <= item.burst_len;
            vif.awsize  <= item.burst_size;
            vif.awburst <= item.burst_type;
            vif.awvalid <= 1'b1;

            do @(posedge vif.clk); while (!vif.awready);
            vif.awvalid <= 1'b0;

            for (i = 0; i < item.element_count; i++) begin
                vif.wdata  <= item.burst_write_data[i];
                vif.wstrb  <= item.burst_write_strb[i];
                vif.wlast  <= (i == (item.element_count - 1));
                vif.wvalid <= 1'b1;

                do @(posedge vif.clk); while (!vif.wready);

                vif.wvalid <= 1'b0;
                vif.wlast  <= 1'b0;
                vif.wdata  <= '0;
                vif.wstrb  <= '0;
            end
        end

        // Optional legal B-channel backpressure window.  K3-B uses this
        // only after lower engines are quiescent so multiple committed
        // responses can accumulate in the BRAM Port0 B FIFO.
        for (hold_idx = 0;
             hold_idx < item.burst_bready_hold_cycles;
             hold_idx++) begin
            @(posedge vif.clk);
        end

        // Drain exactly one B response per independently issued AW burst.
        vif.bready <= 1'b1;

        for (rsp_idx = 0;
             rsp_idx < item.burst_repeat_count;
             rsp_idx++) begin
            do @(posedge vif.clk); while (!vif.bvalid);

            if (vif.bresp !== 2'b00) begin
                `uvm_fatal("AXI_HOST_DRV/RAW_BRESP",
                    $sformatf("RAW_WRITE_BURST returned BRESP=0x%0h for base=0x%08h repeat=%0d/%0d",
                        vif.bresp,
                        item.addr,
                        rsp_idx,
                        item.burst_repeat_count))
            end
        end

        @(posedge vif.clk);
        vif.bready <= 1'b0;
    end
    endtask

    // ------------------------------------------------------------
    // AXI raw multi-beat read burst
    // ------------------------------------------------------------
    task automatic host_axi_read_burst(
        input axi_mm_host_seq_item req,
        input axi_mm_host_seq_item rsp
    );
        int unsigned i;
        bit expected_last;
    begin
        @(posedge vif.clk);
        vif.arid    <= '0;
        vif.araddr  <= req.addr;
        vif.arlen   <= req.burst_len;
        vif.arsize  <= req.burst_size;
        vif.arburst <= req.burst_type;
        vif.arvalid <= 1'b1;

        do @(posedge vif.clk); while (!vif.arready);
        vif.arvalid <= 1'b0;

        rsp.burst_read_data = new[req.element_count];
        vif.rready <= 1'b1;

        for (i = 0; i < req.element_count; i++) begin
            do @(posedge vif.clk); while (!vif.rvalid);

            rsp.burst_read_data[i] = vif.rdata;
            expected_last = (i == (req.element_count - 1));

            if (vif.rresp !== 2'b00) begin
                `uvm_fatal("AXI_HOST_DRV/RAW_RRESP",
                    $sformatf("RAW_READ_BURST returned RRESP=0x%0h for addr=0x%08h beat=%0d",
                        vif.rresp, req.addr, i))
            end

            if (vif.rlast !== expected_last) begin
                `uvm_fatal("AXI_HOST_DRV/RAW_RLAST",
                    $sformatf("RAW_READ_BURST RLAST mismatch for addr=0x%08h beat=%0d/%0d actual=%0b expected=%0b",
                        req.addr, i, req.element_count, vif.rlast, expected_last))
            end
        end

        @(posedge vif.clk);
        vif.rready <= 1'b0;
    end
    endtask

    // ------------------------------------------------------------
    // Byte write helper
    // ------------------------------------------------------------
    task automatic host_write_u8(
        input bit [ADDR_WIDTH-1:0] addr,
        input bit [7:0]            value
    );
        bit [ADDR_WIDTH-1:0]    aligned_addr;
        bit [WORD_LSB_W-1:0]    byte_offset;
        bit [DATA_WIDTH-1:0]    data_word;
        bit [BYTE_PER_WORD-1:0] strb_word;
    begin
        aligned_addr = {addr[ADDR_WIDTH-1:WORD_LSB_W], {WORD_LSB_W{1'b0}}};
        byte_offset  = addr[WORD_LSB_W-1:0];

        data_word = {{(DATA_WIDTH-8){1'b0}}, value} << (byte_offset * 8);
        strb_word = {{(BYTE_PER_WORD-1){1'b0}}, 1'b1} << byte_offset;

        host_axi_write_word(aligned_addr, data_word, strb_word);
    end
    endtask

    // ------------------------------------------------------------
    // U32 write helper
    // ------------------------------------------------------------
    task automatic host_write_u32(
        input bit [ADDR_WIDTH-1:0] addr,
        input bit [31:0]           value
    );
        bit [ADDR_WIDTH-1:0]    aligned_addr;
        bit [WORD_LSB_W-1:0]    byte_offset;
        bit [DATA_WIDTH-1:0]    data_word;
        bit [BYTE_PER_WORD-1:0] strb_word;
    begin
        aligned_addr = {addr[ADDR_WIDTH-1:WORD_LSB_W], {WORD_LSB_W{1'b0}}};
        byte_offset  = addr[WORD_LSB_W-1:0];

        data_word = {{(DATA_WIDTH-32){1'b0}}, value} << (byte_offset * 8);
        strb_word = {{(BYTE_PER_WORD-4){1'b0}}, 4'b1111} << byte_offset;

        host_axi_write_word(aligned_addr, data_word, strb_word);
    end
    endtask

    // ------------------------------------------------------------
    // U32 read helper
    // ------------------------------------------------------------
    task automatic host_read_u32(
        input  bit [ADDR_WIDTH-1:0] addr,
        output bit [31:0]           value
    );
        bit [ADDR_WIDTH-1:0] aligned_addr;
        bit [WORD_LSB_W-1:0] byte_offset;
        bit [DATA_WIDTH-1:0] data_word;
    begin
        aligned_addr = {addr[ADDR_WIDTH-1:WORD_LSB_W], {WORD_LSB_W{1'b0}}};
        byte_offset  = addr[WORD_LSB_W-1:0];

        host_axi_read_word(aligned_addr, data_word);
        value = data_word >> (byte_offset * 8);
    end
    endtask

    // ------------------------------------------------------------
    // Drive op: WRITE_BYTES
    //
    // IMPORTANT:
    //   item.write_data_s8[i] is a signed byte.
    //   We must preserve the full 8-bit pattern.
    //   DO NOT use bit'(...), which truncates to 1 bit.
    // ------------------------------------------------------------
    task automatic drive_write_bytes(axi_mm_host_seq_item item);
        int unsigned i;
        bit [7:0]    value_u8;
    begin
        if (item.write_data_s8.size() != item.element_count) begin
            `uvm_fatal("AXI_HOST_DRV/BAD_WRITE_BYTES",
                $sformatf("WRITE_BYTES size mismatch: element_count=%0d write_data_s8.size=%0d",
                    item.element_count, item.write_data_s8.size()))
        end

        for (i = 0; i < item.element_count; i++) begin
            value_u8 = item.write_data_s8[i][7:0];
            host_write_u8(item.addr + i, value_u8);
        end
    end
    endtask

    // ------------------------------------------------------------
    // Drive op: FILL_U32
    // ------------------------------------------------------------
    task automatic drive_fill_u32(axi_mm_host_seq_item item);
        int unsigned i;
    begin
        for (i = 0; i < item.element_count; i++) begin
            host_write_u32(item.addr + (i * 4), item.fill_value_u32);
        end
    end
    endtask

    // ------------------------------------------------------------
    // Drive op: READ_S32
    // ------------------------------------------------------------
    task automatic drive_read_s32(
        axi_mm_host_seq_item req,
        axi_mm_host_seq_item rsp
    );
        int unsigned i;
        bit [31:0]   value_u32;
    begin
        rsp.read_data_s32 = new[req.element_count];

        for (i = 0; i < req.element_count; i++) begin
            host_read_u32(req.addr + (i * 4), value_u32);
            rsp.read_data_s32[i] = $signed(value_u32);
        end
    end
    endtask

    // ------------------------------------------------------------
    // Drive op: RAW_WRITE_BURST
    // ------------------------------------------------------------
    task automatic drive_raw_write_burst(axi_mm_host_seq_item item);
    begin
        host_axi_write_burst(item);
    end
    endtask

    // ------------------------------------------------------------
    // Drive op: RAW_READ_BURST
    // ------------------------------------------------------------
    task automatic drive_raw_read_burst(
        axi_mm_host_seq_item req,
        axi_mm_host_seq_item rsp
    );
    begin
        host_axi_read_burst(req, rsp);
    end
    endtask

    // ------------------------------------------------------------
    // Dispatch one host item
    // ------------------------------------------------------------
    task automatic drive_item(
        axi_mm_host_seq_item req,
        axi_mm_host_seq_item rsp
    );
    begin
        case (req.op_kind)
            axi_mm_host_seq_item::AXI_HOST_OP_WRITE_BYTES: begin
                drive_write_bytes(req);
            end

            axi_mm_host_seq_item::AXI_HOST_OP_FILL_U32: begin
                drive_fill_u32(req);
            end

            axi_mm_host_seq_item::AXI_HOST_OP_READ_S32: begin
                drive_read_s32(req, rsp);
            end

            axi_mm_host_seq_item::AXI_HOST_OP_RAW_WRITE_BURST: begin
                drive_raw_write_burst(req);
            end

            axi_mm_host_seq_item::AXI_HOST_OP_RAW_READ_BURST: begin
                drive_raw_read_burst(req, rsp);
            end

            default: begin
                `uvm_fatal("AXI_HOST_DRV/BAD_OP",
                    $sformatf("Unsupported op_kind=%0d", req.op_kind))
            end
        endcase

        rsp.response_valid = 1'b1;
    end
    endtask

    // ------------------------------------------------------------
    // Run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        axi_mm_host_seq_item req;
        axi_mm_host_seq_item rsp;
    begin
        wait_for_reset_release();
        drive_idle();

        forever begin
            seq_item_port.get_next_item(req);

            if (req == null) begin
                `uvm_fatal("AXI_HOST_DRV/NULL_REQ",
                    "seq_item_port.get_next_item() returned null request")
            end

            if (!req.is_request_valid()) begin
                `uvm_fatal("AXI_HOST_DRV/BAD_REQ",
                    $sformatf("Invalid host request: %s", req.convert2string()))
            end

            rsp = axi_mm_host_seq_item::type_id::create("rsp");
            rsp.copy(req);
            rsp.clear_response();
            rsp.set_id_info(req);

            if (enable_log) begin
                `uvm_info("AXI_HOST_DRV",
                    $sformatf("Driving host item: %s", req.convert2string()),
                    UVM_MEDIUM)
            end

            drive_item(req, rsp);

            completed_item_count++;

            if (enable_log) begin
                `uvm_info("AXI_HOST_DRV",
                    $sformatf("Completed host item #%0d: %s",
                        completed_item_count, rsp.convert2string()),
                    UVM_MEDIUM)
            end

            seq_item_port.item_done(rsp);
        end
    end
    endtask

    // ------------------------------------------------------------
    // Report phase
    // ------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        if (enable_log) begin
            `uvm_info("AXI_HOST_DRV",
                $sformatf("Driver completed %0d host item(s)", completed_item_count),
                UVM_LOW)
        end
    endfunction

endclass

`endif