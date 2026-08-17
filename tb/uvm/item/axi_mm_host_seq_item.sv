// File: tb/uvm/item/axi_mm_host_seq_item.sv
`ifndef AXI_MM_HOST_SEQ_ITEM_SV
`define AXI_MM_HOST_SEQ_ITEM_SV

class axi_mm_host_seq_item extends uvm_sequence_item;

    // ------------------------------------------------------------
    // Host operation kind
    // ------------------------------------------------------------
    typedef enum int unsigned {
        AXI_HOST_OP_WRITE_BYTES     = 0,
        AXI_HOST_OP_FILL_U32        = 1,
        AXI_HOST_OP_READ_S32        = 2,
        AXI_HOST_OP_RAW_WRITE_BURST = 3,
        AXI_HOST_OP_RAW_READ_BURST  = 4
    } op_kind_e;

    // ------------------------------------------------------------
    // Optional semantic role
    //   Helpful for log / debug / future scoreboard usage
    // ------------------------------------------------------------
    typedef enum int unsigned {
        AXI_HOST_ROLE_GENERIC    = 0,
        AXI_HOST_ROLE_PRELOAD_A  = 1,
        AXI_HOST_ROLE_PRELOAD_B  = 2,
        AXI_HOST_ROLE_CLEAR_C    = 3,
        AXI_HOST_ROLE_READBACK_C = 4
    } op_role_e;

    // ------------------------------------------------------------
    // Case / job context
    // ------------------------------------------------------------
    int unsigned case_id;
    ai_accel_subsys_seq_item::test_kind_e test_kind;
    string       test_name;
    int unsigned job_idx;

    // ------------------------------------------------------------
    // Operation identity
    // ------------------------------------------------------------
    op_kind_e op_kind;
    op_role_e op_role;

    // ------------------------------------------------------------
    // Common addressing / sizing
    //
    // addr:
    //   byte address
    //
    // element_count:
    //   WRITE_BYTES -> byte count
    //   FILL_U32    -> number of 32-bit words
    //   READ_S32    -> number of signed 32-bit elements
    //
    // bytes_per_element:
    //   WRITE_BYTES -> 1
    //   FILL_U32    -> 4
    //   READ_S32    -> 4
    // ------------------------------------------------------------
    bit [31:0]   addr;
    int unsigned element_count;
    int unsigned bytes_per_element;

    // ------------------------------------------------------------
    // Request payload
    // ------------------------------------------------------------
    byte signed  write_data_s8[];
    bit [31:0]   fill_value_u32;

    // ------------------------------------------------------------
    // Raw AXI burst request payload / metadata
    //
    // burst_len:
    //   AXI LEN field (beats - 1)
    //
    // burst_size:
    //   AXI SIZE field (log2(bytes per beat))
    //
    // burst_type:
    //   2'b00 FIXED, 2'b01 INCR, 2'b10 WRAP
    //
    // The current host interface is 64-bit, so burst_size must not
    // exceed 3 for legal raw-burst requests.
    // ------------------------------------------------------------
    bit [7:0]    burst_len;
    bit [2:0]    burst_size;
    bit [1:0]    burst_type;
    bit [63:0]   burst_write_data[];
    bit [7:0]    burst_write_strb[];

    // Optional repeated-write / B-channel backpressure controls.
    //
    // burst_repeat_count:
    //   Number of independent AW/W bursts emitted for one raw-write item.
    //   Each repeated burst uses the same LEN/SIZE/BURST/data/strobe payload.
    //
    // burst_repeat_stride_bytes:
    //   Byte-address increment applied between repeated bursts.
    //
    // burst_bready_hold_cycles:
    //   Number of AXI clocks to keep BREADY low after all repeated AW/W
    //   bursts have completed.  This is a verification control used to
    //   exercise legal outstanding write-response / backpressure behavior.
    //
    // Defaults preserve the original one-burst, immediate-BREADY behavior.
    int unsigned burst_repeat_count;
    int unsigned burst_repeat_stride_bytes;
    int unsigned burst_bready_hold_cycles;

    // ------------------------------------------------------------
    // Response payload
    // ------------------------------------------------------------
    int signed   read_data_s32[];
    bit [63:0]   burst_read_data[];
    bit          response_valid;

    `uvm_object_utils_begin(axi_mm_host_seq_item)
        // Case / job context
        `uvm_field_int(case_id, UVM_DEFAULT)
        `uvm_field_enum(ai_accel_subsys_seq_item::test_kind_e, test_kind, UVM_DEFAULT)
        `uvm_field_string(test_name, UVM_DEFAULT)
        `uvm_field_int(job_idx, UVM_DEFAULT)

        // Operation identity
        `uvm_field_enum(op_kind_e, op_kind, UVM_DEFAULT)
        `uvm_field_enum(op_role_e, op_role, UVM_DEFAULT)

        // Common addressing / sizing
        `uvm_field_int(addr, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(element_count, UVM_DEFAULT)
        `uvm_field_int(bytes_per_element, UVM_DEFAULT)

        // Request payload
        `uvm_field_array_int(write_data_s8, UVM_DEFAULT)
        `uvm_field_int(fill_value_u32, UVM_DEFAULT | UVM_HEX)

        // Raw AXI burst request payload / metadata
        `uvm_field_int(burst_len, UVM_DEFAULT)
        `uvm_field_int(burst_size, UVM_DEFAULT)
        `uvm_field_int(burst_type, UVM_DEFAULT)
        `uvm_field_array_int(burst_write_data, UVM_DEFAULT | UVM_HEX)
        `uvm_field_array_int(burst_write_strb, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(burst_repeat_count, UVM_DEFAULT)
        `uvm_field_int(burst_repeat_stride_bytes, UVM_DEFAULT)
        `uvm_field_int(burst_bready_hold_cycles, UVM_DEFAULT)

        // Response payload
        `uvm_field_array_int(read_data_s32, UVM_DEFAULT)
        `uvm_field_array_int(burst_read_data, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(response_valid, UVM_DEFAULT)
    `uvm_object_utils_end

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "axi_mm_host_seq_item");
        super.new(name);

        case_id           = 0;
        test_kind         = ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE;
        test_name         = "";
        job_idx           = 0;

        op_kind           = AXI_HOST_OP_WRITE_BYTES;
        op_role           = AXI_HOST_ROLE_GENERIC;

        addr              = '0;
        element_count     = 0;
        bytes_per_element = 1;

        fill_value_u32    = 32'h0000_0000;

        burst_len                  = 8'd0;
        burst_size                 = 3'd3;
        burst_type                 = 2'b01;
        burst_repeat_count         = 1;
        burst_repeat_stride_bytes  = 0;
        burst_bready_hold_cycles   = 0;

        response_valid             = 1'b0;

        write_data_s8     = new[0];
        burst_write_data  = new[0];
        burst_write_strb  = new[0];
        read_data_s32     = new[0];
        burst_read_data   = new[0];
    endfunction

    // ------------------------------------------------------------
    // Context helper
    // ------------------------------------------------------------
    function void set_case_context(
        input int unsigned case_id_in,
        input ai_accel_subsys_seq_item::test_kind_e test_kind_in,
        input string test_name_in = "",
        input int unsigned job_idx_in = 0
    );
        case_id   = case_id_in;
        test_kind = test_kind_in;
        test_name = test_name_in;
        job_idx   = job_idx_in;
    endfunction

    // ------------------------------------------------------------
    // Raw-burst request reset helper
    // ------------------------------------------------------------
    function void clear_raw_burst_request();
        burst_len                  = 8'd0;
        burst_size                 = 3'd3;
        burst_type                 = 2'b01;
        burst_write_data           = new[0];
        burst_write_strb           = new[0];
        burst_repeat_count         = 1;
        burst_repeat_stride_bytes  = 0;
        burst_bready_hold_cycles   = 0;
    endfunction

    // ------------------------------------------------------------
    // Clear response helper
    // ------------------------------------------------------------
    function void clear_response();
        read_data_s32   = new[0];
        burst_read_data = new[0];
        response_valid  = 1'b0;
    endfunction

    // ------------------------------------------------------------
    // Setup: WRITE_BYTES
    // ------------------------------------------------------------
    function void setup_write_bytes(
        input bit [31:0] addr_in,
        input byte signed data_in[],
        input op_role_e role_in = AXI_HOST_ROLE_GENERIC
    );
        int unsigned i;

        op_kind           = AXI_HOST_OP_WRITE_BYTES;
        op_role           = role_in;
        addr              = addr_in;
        bytes_per_element = 1;
        element_count     = data_in.size();

        write_data_s8 = new[data_in.size()];
        for (i = 0; i < data_in.size(); i++) begin
            write_data_s8[i] = data_in[i];
        end

        fill_value_u32 = 32'h0000_0000;
        clear_raw_burst_request();
        clear_response();
    endfunction

    // ------------------------------------------------------------
    // Setup: WRITE_BYTES from int signed vector
    //   Useful for current A/B preload flow
    // ------------------------------------------------------------
    function void setup_write_bytes_from_ints(
        input bit [31:0] addr_in,
        input int signed data_in[],
        input op_role_e role_in = AXI_HOST_ROLE_GENERIC
    );
        int unsigned i;
        byte signed tmp[];

        tmp = new[data_in.size()];
        for (i = 0; i < data_in.size(); i++) begin
            if ((data_in[i] < -128) || (data_in[i] > 127)) begin
                `uvm_fatal("AXI_HOST_ITEM/RANGE",
                    $sformatf("setup_write_bytes_from_ints(): data_in[%0d]=%0d is outside signed 8-bit range",
                        i, data_in[i]))
            end
            tmp[i] = byte'(data_in[i]);
        end

        setup_write_bytes(addr_in, tmp, role_in);
    endfunction

    // ------------------------------------------------------------
    // Setup: FILL_U32
    // ------------------------------------------------------------
    function void setup_fill_u32(
        input bit [31:0] addr_in,
        input int unsigned word_count_in,
        input bit [31:0] value_in = 32'h0000_0000,
        input op_role_e role_in = AXI_HOST_ROLE_GENERIC
    );
        op_kind           = AXI_HOST_OP_FILL_U32;
        op_role           = role_in;
        addr              = addr_in;
        bytes_per_element = 4;
        element_count     = word_count_in;

        write_data_s8  = new[0];
        fill_value_u32 = value_in;
        clear_raw_burst_request();
        clear_response();
    endfunction

    // ------------------------------------------------------------
    // Setup: READ_S32
    // ------------------------------------------------------------
    function void setup_read_s32(
        input bit [31:0] addr_in,
        input int unsigned word_count_in,
        input op_role_e role_in = AXI_HOST_ROLE_GENERIC
    );
        op_kind           = AXI_HOST_OP_READ_S32;
        op_role           = role_in;
        addr              = addr_in;
        bytes_per_element = 4;
        element_count     = word_count_in;

        write_data_s8  = new[0];
        fill_value_u32 = 32'h0000_0000;
        clear_raw_burst_request();
        clear_response();
    endfunction

    // ------------------------------------------------------------
    // Setup: RAW_WRITE_BURST
    // ------------------------------------------------------------
    function void setup_raw_write_burst(
        input bit [31:0] addr_in,
        input bit [63:0] data_in[],
        input bit [7:0]  strb_in[],
        input bit [2:0]  size_in,
        input bit [1:0]  burst_in,
        input op_role_e role_in = AXI_HOST_ROLE_GENERIC
    );
        int unsigned i;

        op_kind           = AXI_HOST_OP_RAW_WRITE_BURST;
        op_role           = role_in;
        addr              = addr_in;
        element_count     = data_in.size();
        bytes_per_element = (1 << size_in);

        burst_len                  = (data_in.size() > 0) ? (data_in.size() - 1) : 0;
        burst_size                 = size_in;
        burst_type                 = burst_in;
        burst_repeat_count         = 1;
        burst_repeat_stride_bytes  = 0;
        burst_bready_hold_cycles   = 0;

        write_data_s8     = new[0];
        fill_value_u32    = 32'h0000_0000;

        burst_write_data = new[data_in.size()];
        for (i = 0; i < data_in.size(); i++) begin
            burst_write_data[i] = data_in[i];
        end

        burst_write_strb = new[strb_in.size()];
        for (i = 0; i < strb_in.size(); i++) begin
            burst_write_strb[i] = strb_in[i];
        end

        clear_response();
    endfunction

    // ------------------------------------------------------------
    // Configure repeated raw-write bursts with deferred BREADY.
    //
    // Call after setup_raw_write_burst().  Keeping this as a separate
    // helper preserves the existing setup_raw_write_burst() API.
    // ------------------------------------------------------------
    function void configure_raw_write_repeats(
        input int unsigned repeat_count_in,
        input int unsigned repeat_stride_bytes_in,
        input int unsigned bready_hold_cycles_in
    );
        burst_repeat_count        = repeat_count_in;
        burst_repeat_stride_bytes = repeat_stride_bytes_in;
        burst_bready_hold_cycles  = bready_hold_cycles_in;
    endfunction

    // ------------------------------------------------------------
    // Setup: RAW_READ_BURST
    // ------------------------------------------------------------
    function void setup_raw_read_burst(
        input bit [31:0] addr_in,
        input int unsigned beat_count_in,
        input bit [2:0]  size_in,
        input bit [1:0]  burst_in,
        input op_role_e role_in = AXI_HOST_ROLE_GENERIC
    );
        op_kind           = AXI_HOST_OP_RAW_READ_BURST;
        op_role           = role_in;
        addr              = addr_in;
        element_count     = beat_count_in;
        bytes_per_element = (1 << size_in);

        burst_len                  = (beat_count_in > 0) ? (beat_count_in - 1) : 0;
        burst_size                 = size_in;
        burst_type                 = burst_in;
        burst_repeat_count         = 1;
        burst_repeat_stride_bytes  = 0;
        burst_bready_hold_cycles   = 0;

        write_data_s8     = new[0];
        fill_value_u32    = 32'h0000_0000;
        burst_write_data  = new[0];
        burst_write_strb  = new[0];

        clear_response();
    endfunction

    // ------------------------------------------------------------
    // Convenience helper
    // ------------------------------------------------------------
    function int unsigned total_byte_count();
        return (element_count * bytes_per_element);
    endfunction

    // ------------------------------------------------------------
    // Raw AXI burst common sanity check
    // ------------------------------------------------------------
    function bit is_raw_burst_common_valid();
        int unsigned beat_count;
        int unsigned beat_bytes;

        beat_count = int'(burst_len) + 1;

        if ((element_count == 0) || (element_count > 256))
            return 1'b0;
        if (beat_count != element_count)
            return 1'b0;
        if (burst_size > 3)
            return 1'b0;
        if (burst_type == 2'b11)
            return 1'b0;

        beat_bytes = (1 << burst_size);
        if (bytes_per_element != beat_bytes)
            return 1'b0;
        if ((addr % beat_bytes) != 0)
            return 1'b0;

        if (burst_type == 2'b10) begin
            if (!((beat_count == 2) ||
                  (beat_count == 4) ||
                  (beat_count == 8) ||
                  (beat_count == 16)))
                return 1'b0;
        end

        return 1'b1;
    endfunction

    // ------------------------------------------------------------
    // Request sanity check
    // ------------------------------------------------------------
    function bit is_request_valid();
        case (op_kind)
            AXI_HOST_OP_WRITE_BYTES: begin
                if (bytes_per_element != 1)
                    return 1'b0;
                if (element_count != write_data_s8.size())
                    return 1'b0;
                return 1'b1;
            end

            AXI_HOST_OP_FILL_U32: begin
                if (bytes_per_element != 4)
                    return 1'b0;
                return 1'b1;
            end

            AXI_HOST_OP_READ_S32: begin
                if (bytes_per_element != 4)
                    return 1'b0;
                return 1'b1;
            end

            AXI_HOST_OP_RAW_WRITE_BURST: begin
                int unsigned beat_bytes;
                int unsigned repeat_idx;
                bit [31:0] repeated_addr;

                if (!is_raw_burst_common_valid())
                    return 1'b0;
                if (burst_write_data.size() != element_count)
                    return 1'b0;
                if (burst_write_strb.size() != element_count)
                    return 1'b0;
                if (burst_repeat_count == 0)
                    return 1'b0;

                beat_bytes = (1 << burst_size);
                for (repeat_idx = 0;
                     repeat_idx < burst_repeat_count;
                     repeat_idx++) begin
                    repeated_addr = addr + (repeat_idx * burst_repeat_stride_bytes);
                    if ((repeated_addr % beat_bytes) != 0)
                        return 1'b0;
                end

                return 1'b1;
            end

            AXI_HOST_OP_RAW_READ_BURST: begin
                if (!is_raw_burst_common_valid())
                    return 1'b0;
                return 1'b1;
            end

            default: begin
                return 1'b0;
            end
        endcase
    endfunction

    // ------------------------------------------------------------
    // Pretty print helper
    // ------------------------------------------------------------
    virtual function string convert2string();
        return $sformatf(
            "case_id=%0d test_kind=%0d test_name=%s job_idx=%0d op_kind=%0d op_role=%0d addr=0x%08h element_count=%0d bytes_per_element=%0d total_byte_count=%0d write_bytes=%0d fill_value_u32=0x%08h burst_len=%0d burst_size=%0d burst_type=%0d burst_write_beats=%0d burst_repeat_count=%0d burst_repeat_stride_bytes=%0d burst_bready_hold_cycles=%0d response_valid=%0d read_s32_count=%0d burst_read_beats=%0d",
            case_id,
            test_kind,
            test_name,
            job_idx,
            op_kind,
            op_role,
            addr,
            element_count,
            bytes_per_element,
            total_byte_count(),
            write_data_s8.size(),
            fill_value_u32,
            burst_len,
            burst_size,
            burst_type,
            burst_write_data.size(),
            burst_repeat_count,
            burst_repeat_stride_bytes,
            burst_bready_hold_cycles,
            response_valid,
            read_data_s32.size(),
            burst_read_data.size()
        );
    endfunction

endclass

`endif