// File: tb/uvm/helper/ai_accel_subsys_axi_host_helper.sv
`ifndef AI_ACCEL_SUBSYS_AXI_HOST_HELPER_SV
`define AI_ACCEL_SUBSYS_AXI_HOST_HELPER_SV

class ai_accel_subsys_axi_host_helper extends uvm_object;
    `uvm_object_utils(ai_accel_subsys_axi_host_helper)

    // ------------------------------------------------------------
    // AXI interface configuration
    //   Keep v1 aligned with current subsystem baseline/UVM top
    // ------------------------------------------------------------
    localparam int ADDR_WIDTH    = 32;
    localparam int DATA_WIDTH    = 64;
    localparam int ID_WIDTH      = 4;
    localparam int BYTE_PER_WORD = DATA_WIDTH / 8;
    localparam int WORD_LSB_W    = (BYTE_PER_WORD > 1) ? $clog2(BYTE_PER_WORD) : 1;

    localparam logic [2:0] AXI_SIZE_WORD = $clog2(BYTE_PER_WORD);

    typedef virtual axi_mm_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .HAS_BURST  (1)
    ) axi0_vif_t;

    // ------------------------------------------------------------
    // Virtual interface
    // ------------------------------------------------------------
    axi0_vif_t axi_vif;

    // ------------------------------------------------------------
    // Knobs / counters
    // ------------------------------------------------------------
    bit          enable_log;
    int unsigned write_word_count;
    int unsigned read_word_count;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_axi_host_helper");
        super.new(name);

        axi_vif          = null;
        enable_log       = 1'b1;
        write_word_count = 0;
        read_word_count  = 0;
    endfunction

    // ------------------------------------------------------------
    // Bind virtual interface
    // ------------------------------------------------------------
    function void set_vif(axi0_vif_t vif);
        axi_vif = vif;
    endfunction

    // ------------------------------------------------------------
    // Internal guard
    // ------------------------------------------------------------
    function void check_vif(string caller);
        if (axi_vif == null) begin
            `uvm_fatal("AXI_HOST_HELPER/NOVIF",
                $sformatf("%s called before axi_vif was set", caller))
        end
    endfunction

    // ------------------------------------------------------------
    // Wait until AXI host interface reset is released
    // ------------------------------------------------------------
    task automatic wait_for_reset_release();
    begin
        check_vif("wait_for_reset_release");

        @(posedge axi_vif.clk);
        while (axi_vif.rst_n !== 1'b1) begin
            @(posedge axi_vif.clk);
        end
    end
    endtask

    // ------------------------------------------------------------
    // Low-level word write
    // ------------------------------------------------------------
    task automatic host_axi_write_word(
        input logic [ADDR_WIDTH-1:0]    addr,
        input logic [DATA_WIDTH-1:0]    data,
        input logic [BYTE_PER_WORD-1:0] strb
    );
    begin
        check_vif("host_axi_write_word");

        @(posedge axi_vif.clk);
        axi_vif.awid    <= '0;
        axi_vif.awaddr  <= addr;
        axi_vif.awlen   <= 8'd0;
        axi_vif.awsize  <= AXI_SIZE_WORD;
        axi_vif.awburst <= 2'b01; // INCR
        axi_vif.awvalid <= 1'b1;

        do @(posedge axi_vif.clk); while (!axi_vif.awready);
        axi_vif.awvalid <= 1'b0;

        axi_vif.wdata   <= data;
        axi_vif.wstrb   <= strb;
        axi_vif.wlast   <= 1'b1;
        axi_vif.wvalid  <= 1'b1;

        do @(posedge axi_vif.clk); while (!axi_vif.wready);
        axi_vif.wvalid  <= 1'b0;
        axi_vif.wlast   <= 1'b0;
        axi_vif.wdata   <= '0;
        axi_vif.wstrb   <= '0;

        axi_vif.bready  <= 1'b1;
        do @(posedge axi_vif.clk); while (!axi_vif.bvalid);
        @(posedge axi_vif.clk);
        axi_vif.bready  <= 1'b0;

        write_word_count++;

        if (enable_log) begin
            `uvm_info("AXI_HOST_HELPER",
                $sformatf("WRITE_WORD addr=0x%08h data=0x%016h strb=0x%0h",
                    addr, data, strb),
                UVM_HIGH)
        end
    end
    endtask

    // ------------------------------------------------------------
    // Low-level word read
    // ------------------------------------------------------------
    task automatic host_axi_read_word(
        input  logic [ADDR_WIDTH-1:0] addr,
        output logic [DATA_WIDTH-1:0] data
    );
    begin
        check_vif("host_axi_read_word");

        @(posedge axi_vif.clk);
        axi_vif.arid    <= '0;
        axi_vif.araddr  <= addr;
        axi_vif.arlen   <= 8'd0;
        axi_vif.arsize  <= AXI_SIZE_WORD;
        axi_vif.arburst <= 2'b01; // INCR
        axi_vif.arvalid <= 1'b1;

        do @(posedge axi_vif.clk); while (!axi_vif.arready);
        axi_vif.arvalid <= 1'b0;

        axi_vif.rready  <= 1'b1;
        do @(posedge axi_vif.clk); while (!axi_vif.rvalid);

        data = axi_vif.rdata;

        @(posedge axi_vif.clk);
        axi_vif.rready <= 1'b0;

        read_word_count++;

        if (enable_log) begin
            `uvm_info("AXI_HOST_HELPER",
                $sformatf("READ_WORD addr=0x%08h data=0x%016h",
                    addr, data),
                UVM_HIGH)
        end
    end
    endtask

    // ------------------------------------------------------------
    // Byte write helper
    // ------------------------------------------------------------
    task automatic host_write_u8(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [7:0]            value
    );
        logic [ADDR_WIDTH-1:0]    aligned_addr;
        logic [WORD_LSB_W-1:0]    byte_offset;
        logic [DATA_WIDTH-1:0]    data_word;
        logic [BYTE_PER_WORD-1:0] strb_word;
    begin
        aligned_addr = {addr[ADDR_WIDTH-1:WORD_LSB_W], {WORD_LSB_W{1'b0}}};
        byte_offset  = addr[WORD_LSB_W-1:0];

        data_word = {{(DATA_WIDTH-8){1'b0}}, value} << (byte_offset * 8);
        strb_word = {{(BYTE_PER_WORD-1){1'b0}}, 1'b1} << byte_offset;

        host_axi_write_word(aligned_addr, data_word, strb_word);
    end
    endtask

    // ------------------------------------------------------------
    // 32-bit write helper
    // ------------------------------------------------------------
    task automatic host_write_u32(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [31:0]           value
    );
        logic [ADDR_WIDTH-1:0]    aligned_addr;
        logic [WORD_LSB_W-1:0]    byte_offset;
        logic [DATA_WIDTH-1:0]    data_word;
        logic [BYTE_PER_WORD-1:0] strb_word;
    begin
        aligned_addr = {addr[ADDR_WIDTH-1:WORD_LSB_W], {WORD_LSB_W{1'b0}}};
        byte_offset  = addr[WORD_LSB_W-1:0];

        data_word = {{(DATA_WIDTH-32){1'b0}}, value} << (byte_offset * 8);
        strb_word = {{(BYTE_PER_WORD-4){1'b0}}, 4'b1111} << byte_offset;

        host_axi_write_word(aligned_addr, data_word, strb_word);
    end
    endtask

    // ------------------------------------------------------------
    // 32-bit read helper
    // ------------------------------------------------------------
    task automatic host_read_u32(
        input  logic [ADDR_WIDTH-1:0] addr,
        output logic [31:0]           value
    );
        logic [ADDR_WIDTH-1:0] aligned_addr;
        logic [WORD_LSB_W-1:0] byte_offset;
        logic [DATA_WIDTH-1:0] data_word;
    begin
        aligned_addr = {addr[ADDR_WIDTH-1:WORD_LSB_W], {WORD_LSB_W{1'b0}}};
        byte_offset  = addr[WORD_LSB_W-1:0];

        host_axi_read_word(aligned_addr, data_word);
        value = data_word >> (byte_offset * 8);
    end
    endtask

    // ------------------------------------------------------------
    // Convenience: preload flattened signed-8 vector as bytes
    // ------------------------------------------------------------
    task automatic preload_u8_vector(
        input logic [ADDR_WIDTH-1:0] base_addr,
        input int signed             data_vec[]
    );
        int unsigned i;
        logic [7:0]  value_u8;
    begin
        check_vif("preload_u8_vector");

        for (i = 0; i < data_vec.size(); i++) begin
            value_u8 = data_vec[i][7:0];
            host_write_u8(base_addr + i, value_u8);
        end
    end
    endtask

    // ------------------------------------------------------------
    // Convenience: clear flattened C region (32-bit elements)
    // ------------------------------------------------------------
    task automatic clear_u32_region(
        input logic [ADDR_WIDTH-1:0] base_addr,
        input int unsigned           elem_count
    );
        int unsigned i;
    begin
        check_vif("clear_u32_region");

        for (i = 0; i < elem_count; i++) begin
            host_write_u32(base_addr + (i * 4), 32'd0);
        end
    end
    endtask

    // ------------------------------------------------------------
    // Convenience: read back flattened signed-32 vector
    // ------------------------------------------------------------
    task automatic readback_s32_vector(
        input  logic [ADDR_WIDTH-1:0] base_addr,
        input  int unsigned           elem_count,
        output int signed             data_vec[]
    );
        int unsigned i;
        logic [31:0] tmp;
    begin
        check_vif("readback_s32_vector");

        data_vec = new[elem_count];

        for (i = 0; i < elem_count; i++) begin
            host_read_u32(base_addr + (i * 4), tmp);
            data_vec[i] = $signed(tmp);
        end
    end
    endtask

    // ------------------------------------------------------------
    // Report helper stats
    // ------------------------------------------------------------
    virtual function string convert2string();
        return $sformatf(
            "writes=%0d reads=%0d enable_log=%0d",
            write_word_count, read_word_count, enable_log
        );
    endfunction

endclass

`endif