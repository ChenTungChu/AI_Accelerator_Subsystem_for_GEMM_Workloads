// File: tb/uvm/seq/axi_mm_host_seq.sv
`ifndef AXI_MM_HOST_SEQ_SV
`define AXI_MM_HOST_SEQ_SV

class axi_mm_host_seq extends uvm_sequence #(axi_mm_host_seq_item);
    `uvm_object_utils(axi_mm_host_seq)
    `uvm_declare_p_sequencer(axi_mm_host_sequencer)

    // ------------------------------------------------------------
    // Queued requests / collected responses
    // ------------------------------------------------------------
    protected axi_mm_host_seq_item req_q[$];
    protected axi_mm_host_seq_item rsp_q[$];

    // ------------------------------------------------------------
    // Default context for newly queued items
    // ------------------------------------------------------------
    int unsigned default_case_id;
    ai_accel_subsys_seq_item::test_kind_e default_test_kind;
    string       default_test_name;
    int unsigned default_job_idx;

    // ------------------------------------------------------------
    // Config
    // ------------------------------------------------------------
    bit enable_log;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "axi_mm_host_seq");
        super.new(name);

        default_case_id   = 0;
        default_test_kind = ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE;
        default_test_name = "";
        default_job_idx   = 0;

        enable_log        = 1'b1;
    endfunction

    // ------------------------------------------------------------
    // Config helpers
    // ------------------------------------------------------------
    function void set_enable_log(bit enable);
        enable_log = enable;
    endfunction

    function void set_case_context(
        input int unsigned case_id,
        input ai_accel_subsys_seq_item::test_kind_e test_kind,
        input string test_name = "",
        input int unsigned job_idx = 0
    );
        default_case_id   = case_id;
        default_test_kind = test_kind;
        default_test_name = test_name;
        default_job_idx   = job_idx;
    endfunction

    // ------------------------------------------------------------
    // Queue / response management
    // ------------------------------------------------------------
    function void clear_requests();
        req_q.delete();
    endfunction

    function void clear_responses();
        rsp_q.delete();
    endfunction

    function void clear_all();
        clear_requests();
        clear_responses();
    endfunction

    function int unsigned get_request_count();
        return req_q.size();
    endfunction

    function int unsigned get_response_count();
        return rsp_q.size();
    endfunction

    function axi_mm_host_seq_item get_response_item(int unsigned idx);
        if (idx >= rsp_q.size()) begin
            `uvm_error("AXI_HOST_SEQ/BAD_RSP_IDX",
                $sformatf("get_response_item(): idx=%0d out of range, rsp_q.size=%0d",
                    idx, rsp_q.size()))
            return null;
        end
        return rsp_q[idx];
    endfunction

    // ------------------------------------------------------------
    // Internal helpers
    // ------------------------------------------------------------
    protected function string build_default_test_name();
        if (default_test_name != "")
            return default_test_name;

        case (default_test_kind)
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE:
                return $sformatf("fixed_baseline_case_%0d", default_case_id);

            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE:
                return $sformatf("variable_dim_case_%0d", default_case_id);

            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE:
                return $sformatf("config_base_case_%0d", default_case_id);

            default:
                return $sformatf("case_%0d_kind_%0d",
                    default_case_id, default_test_kind);
        endcase
    endfunction

    protected function axi_mm_host_seq_item alloc_item(string prefix = "req");
        axi_mm_host_seq_item item;
        string item_name;

        item_name = $sformatf("%s_%0d", prefix, req_q.size());
        item = axi_mm_host_seq_item::type_id::create(item_name);

        item.set_case_context(
            default_case_id,
            default_test_kind,
            build_default_test_name(),
            default_job_idx
        );

        return item;
    endfunction

    protected function axi_mm_host_seq_item clone_item(
        axi_mm_host_seq_item src,
        string clone_name = "item_clone"
    );
        axi_mm_host_seq_item dst;
        dst = axi_mm_host_seq_item::type_id::create(clone_name);
        dst.copy(src);
        return dst;
    endfunction

    protected function void push_request(axi_mm_host_seq_item item);
        if (item == null) begin
            `uvm_error("AXI_HOST_SEQ/NULL_REQ",
                "push_request() received null item")
            return;
        end
        req_q.push_back(item);
    endfunction

    // ------------------------------------------------------------
    // Generic queue helpers
    // ------------------------------------------------------------
    function void queue_write_bytes_from_ints(
        input bit [31:0] addr,
        input int signed data[],
        input axi_mm_host_seq_item::op_role_e role =
              axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC
    );
        axi_mm_host_seq_item item;
        item = alloc_item("write_bytes");
        item.setup_write_bytes_from_ints(addr, data, role);
        push_request(item);
    endfunction

    function void queue_fill_u32(
        input bit [31:0] addr,
        input int unsigned word_count,
        input bit [31:0] value = 32'h0000_0000,
        input axi_mm_host_seq_item::op_role_e role =
              axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC
    );
        axi_mm_host_seq_item item;
        item = alloc_item("fill_u32");
        item.setup_fill_u32(addr, word_count, value, role);
        push_request(item);
    endfunction

    function void queue_read_s32(
        input bit [31:0] addr,
        input int unsigned word_count,
        input axi_mm_host_seq_item::op_role_e role =
              axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC
    );
        axi_mm_host_seq_item item;
        item = alloc_item("read_s32");
        item.setup_read_s32(addr, word_count, role);
        push_request(item);
    endfunction

    // ------------------------------------------------------------
    // Raw AXI burst queue helpers
    // ------------------------------------------------------------
    function void queue_raw_write_burst(
        input bit [31:0] addr,
        input bit [63:0] data[],
        input bit [7:0]  strb[],
        input bit [2:0]  size,
        input bit [1:0]  burst,
        input axi_mm_host_seq_item::op_role_e role =
              axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC
    );
        axi_mm_host_seq_item item;
        item = alloc_item("raw_write_burst");
        item.setup_raw_write_burst(addr, data, strb, size, burst, role);
        push_request(item);
    endfunction

    // ------------------------------------------------------------
    // Raw write helper with repeated independent bursts and deferred
    // B-channel acceptance.  Existing queue_raw_write_burst() remains
    // unchanged and therefore preserves all legacy callers.
    // ------------------------------------------------------------
    function void queue_raw_write_burst_repeated(
        input bit [31:0] addr,
        input bit [63:0] data[],
        input bit [7:0]  strb[],
        input bit [2:0]  size,
        input bit [1:0]  burst,
        input int unsigned repeat_count,
        input int unsigned repeat_stride_bytes,
        input int unsigned bready_hold_cycles,
        input axi_mm_host_seq_item::op_role_e role =
              axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC
    );
        axi_mm_host_seq_item item;
        item = alloc_item("raw_write_burst_repeated");
        item.setup_raw_write_burst(addr, data, strb, size, burst, role);
        item.configure_raw_write_repeats(
            repeat_count,
            repeat_stride_bytes,
            bready_hold_cycles
        );
        push_request(item);
    endfunction

    function void queue_raw_read_burst(
        input bit [31:0] addr,
        input int unsigned beat_count,
        input bit [2:0]  size,
        input bit [1:0]  burst,
        input axi_mm_host_seq_item::op_role_e role =
              axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC
    );
        axi_mm_host_seq_item item;
        item = alloc_item("raw_read_burst");
        item.setup_raw_read_burst(addr, beat_count, size, burst, role);
        push_request(item);
    endfunction

    // ------------------------------------------------------------
    // Convenience wrappers for current subsystem flow
    // ------------------------------------------------------------
    function void queue_preload_a(
        input bit [31:0] addr,
        input int signed data[]
    );
        queue_write_bytes_from_ints(
            addr,
            data,
            axi_mm_host_seq_item::AXI_HOST_ROLE_PRELOAD_A
        );
    endfunction

    function void queue_preload_b(
        input bit [31:0] addr,
        input int signed data[]
    );
        queue_write_bytes_from_ints(
            addr,
            data,
            axi_mm_host_seq_item::AXI_HOST_ROLE_PRELOAD_B
        );
    endfunction

    function void queue_clear_c(
        input bit [31:0] addr,
        input int unsigned word_count,
        input bit [31:0] value = 32'h0000_0000
    );
        queue_fill_u32(
            addr,
            word_count,
            value,
            axi_mm_host_seq_item::AXI_HOST_ROLE_CLEAR_C
        );
    endfunction

    function void queue_readback_c(
        input bit [31:0] addr,
        input int unsigned word_count
    );
        queue_read_s32(
            addr,
            word_count,
            axi_mm_host_seq_item::AXI_HOST_ROLE_READBACK_C
        );
    endfunction

    // ------------------------------------------------------------
    // Optional helper: append an externally prepared item
    // ------------------------------------------------------------
    function void append_item(axi_mm_host_seq_item item);
        axi_mm_host_seq_item clone;
        if (item == null) begin
            `uvm_error("AXI_HOST_SEQ/NULL_APPEND",
                "append_item() received null item")
            return;
        end
        clone = clone_item(item, $sformatf("append_req_%0d", req_q.size()));
        push_request(clone);
    endfunction

    // ------------------------------------------------------------
    // Body
    // ------------------------------------------------------------
    virtual task body();
        axi_mm_host_seq_item req;
        axi_mm_host_seq_item rsp;
        axi_mm_host_seq_item rsp_copy;
        int unsigned i;

        clear_responses();

        if (req_q.size() == 0) begin
            if (enable_log) begin
                `uvm_info("AXI_HOST_SEQ",
                    "No queued host requests, sequence exits without driving",
                    UVM_MEDIUM)
            end
            return;
        end

        if (enable_log) begin
            `uvm_info("AXI_HOST_SEQ",
                $sformatf("Starting axi_mm_host_seq with %0d queued request(s)",
                    req_q.size()),
                UVM_MEDIUM)
        end

        for (i = 0; i < req_q.size(); i++) begin
            req = req_q[i];

            if (req == null) begin
                `uvm_fatal("AXI_HOST_SEQ/NULL_REQ",
                    $sformatf("req_q[%0d] is null", i))
            end

            if (!req.is_request_valid()) begin
                `uvm_fatal("AXI_HOST_SEQ/BAD_REQ",
                    $sformatf("Invalid queued request[%0d]: %s",
                        i, req.convert2string()))
            end

            if (p_sequencer != null) begin
                p_sequencer.note_item_start(req);
            end

            start_item(req);
            finish_item(req);

            get_response(rsp);

            if (rsp == null) begin
                `uvm_fatal("AXI_HOST_SEQ/NULL_RSP",
                    $sformatf("Null response returned for request[%0d]", i))
            end

            rsp_copy = clone_item(rsp, $sformatf("rsp_copy_%0d", rsp_q.size()));
            rsp_q.push_back(rsp_copy);

            if (enable_log) begin
                `uvm_info("AXI_HOST_SEQ",
                    $sformatf("Collected response[%0d]: %s",
                        i, rsp_copy.convert2string()),
                    UVM_MEDIUM)
            end
        end

        if (enable_log) begin
            `uvm_info("AXI_HOST_SEQ",
                $sformatf("Completed axi_mm_host_seq: requests=%0d responses=%0d",
                    req_q.size(), rsp_q.size()),
                UVM_MEDIUM)
        end
    endtask

endclass

`endif