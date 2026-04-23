// File: tb/uvm/item/axi_mm_host_seq_item.sv
`ifndef AXI_MM_HOST_SEQ_ITEM_SV
`define AXI_MM_HOST_SEQ_ITEM_SV

class axi_mm_host_seq_item extends uvm_sequence_item;

    // ------------------------------------------------------------
    // Host operation kind
    // ------------------------------------------------------------
    typedef enum int unsigned {
        AXI_HOST_OP_WRITE_BYTES = 0,
        AXI_HOST_OP_FILL_U32    = 1,
        AXI_HOST_OP_READ_S32    = 2
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
    // Response payload
    // ------------------------------------------------------------
    int signed   read_data_s32[];
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

        // Response payload
        `uvm_field_array_int(read_data_s32, UVM_DEFAULT)
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
        response_valid    = 1'b0;

        write_data_s8     = new[0];
        read_data_s32     = new[0];
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
    // Clear response helper
    // ------------------------------------------------------------
    function void clear_response();
        read_data_s32  = new[0];
        response_valid = 1'b0;
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
        clear_response();
    endfunction

    // ------------------------------------------------------------
    // Convenience helper
    // ------------------------------------------------------------
    function int unsigned total_byte_count();
        return (element_count * bytes_per_element);
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
            "case_id=%0d test_kind=%0d test_name=%s job_idx=%0d op_kind=%0d op_role=%0d addr=0x%08h element_count=%0d bytes_per_element=%0d total_byte_count=%0d write_bytes=%0d fill_value_u32=0x%08h response_valid=%0d read_s32_count=%0d",
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
            response_valid,
            read_data_s32.size()
        );
    endfunction

endclass

`endif