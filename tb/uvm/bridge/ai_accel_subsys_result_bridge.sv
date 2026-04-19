// File: tb/uvm/bridge/ai_accel_subsys_result_bridge.sv
`ifndef AI_ACCEL_SUBSYS_RESULT_BRIDGE_SV
`define AI_ACCEL_SUBSYS_RESULT_BRIDGE_SV

class ai_accel_subsys_result_bridge extends uvm_component;
    `uvm_component_utils(ai_accel_subsys_result_bridge)

    // ------------------------------------------------------------
    // Analysis port
    // ------------------------------------------------------------
    uvm_analysis_port #(ai_accel_subsys_result_item) ap;

    // ------------------------------------------------------------
    // Simple counters / knobs
    // ------------------------------------------------------------
    int unsigned published_result_count;
    bit          enable_log;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_result_bridge",
                 uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        published_result_count = 0;
        enable_log             = 1'b1;

        void'(uvm_config_db#(bit)::get(this, "", "enable_log", enable_log));
    endfunction

    // ------------------------------------------------------------
    // Publish an already-built result item
    // ------------------------------------------------------------
    function void publish_item(ai_accel_subsys_result_item item);
        ai_accel_subsys_result_item item_copy;

        if (item == null) begin
            `uvm_error("RESULT_BRIDGE/NULL_ITEM",
                "publish_item() received null ai_accel_subsys_result_item")
            return;
        end

        item_copy = ai_accel_subsys_result_item::type_id::create("item_copy");
        item_copy.copy(item);

        published_result_count++;

        if (enable_log) begin
            `uvm_info("RESULT_BRIDGE",
                $sformatf("Publishing result item #%0d: %s",
                    published_result_count, item_copy.convert2string()),
                UVM_MEDIUM)
        end

        ap.write(item_copy);
    endfunction

    // ------------------------------------------------------------
    // Build a result item from flattened expected/actual vectors
    // and publish it.
    //
    // expected_c[] / actual_c[] should both be row-major flattened C.
    // ------------------------------------------------------------
    task automatic publish_case_result(
        input int unsigned case_id,
        input ai_accel_subsys_seq_item::test_kind_e test_kind,
        input string test_name,

        input bit [31:0] base_addr_a,
        input bit [31:0] base_addr_b,
        input bit [31:0] base_addr_c,

        input int unsigned dim_m,
        input int unsigned dim_n,
        input int unsigned dim_k,

        input int signed expected_c[],
        input int signed actual_c[]
    );
        ai_accel_subsys_result_item item;
        int unsigned i;
        int unsigned exp_sz;
        int unsigned act_sz;
        int unsigned max_sz;

        item = ai_accel_subsys_result_item::type_id::create("item");

        // --------------------------------------------------------
        // Metadata
        // --------------------------------------------------------
        item.case_id     = case_id;
        item.test_kind   = test_kind;
        item.test_name   = test_name;

        item.base_addr_a = base_addr_a;
        item.base_addr_b = base_addr_b;
        item.base_addr_c = base_addr_c;

        item.dim_m       = dim_m;
        item.dim_n       = dim_n;
        item.dim_k       = dim_k;

        // --------------------------------------------------------
        // Payload vectors
        // --------------------------------------------------------
        exp_sz = expected_c.size();
        act_sz = actual_c.size();
        max_sz = (exp_sz > act_sz) ? exp_sz : act_sz;

        if (exp_sz != act_sz) begin
            `uvm_warning("RESULT_BRIDGE/SIZE_MISMATCH",
                $sformatf("expected_c.size()=%0d actual_c.size()=%0d",
                    exp_sz, act_sz))
        end

        item.alloc_vectors(max_sz);

        for (i = 0; i < exp_sz; i++) begin
            item.expected_c[i] = expected_c[i];
        end

        for (i = exp_sz; i < max_sz; i++) begin
            item.expected_c[i] = 0;
        end

        for (i = 0; i < act_sz; i++) begin
            item.actual_c[i] = actual_c[i];
        end

        for (i = act_sz; i < max_sz; i++) begin
            item.actual_c[i] = 0;
        end

        // Leave compare decision to scoreboard
        item.clear_compare_summary();
        item.element_count = max_sz;

        publish_item(item);
    endtask

    // ------------------------------------------------------------
    // Report phase
    // ------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        if (enable_log) begin
            `uvm_info("RESULT_BRIDGE",
                $sformatf("Published %0d result item(s)", published_result_count),
                UVM_LOW)
        end
    endfunction

endclass

`endif