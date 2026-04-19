// File: tb/uvm/item/ai_accel_subsys_result_item.sv
`ifndef AI_ACCEL_SUBSYS_RESULT_ITEM_SV
`define AI_ACCEL_SUBSYS_RESULT_ITEM_SV

class ai_accel_subsys_result_item extends uvm_object;
    `uvm_object_utils(ai_accel_subsys_result_item)

    // ------------------------------------------------------------
    // Case identity / metadata
    // ------------------------------------------------------------
    int unsigned case_id;
    ai_accel_subsys_seq_item::test_kind_e test_kind;
    string test_name;

    // ------------------------------------------------------------
    // Runtime configuration snapshot
    // ------------------------------------------------------------
    bit [31:0] base_addr_a;
    bit [31:0] base_addr_b;
    bit [31:0] base_addr_c;

    int unsigned dim_m;
    int unsigned dim_n;
    int unsigned dim_k;

    // ------------------------------------------------------------
    // Result payload
    //   Flattened C matrix, row-major
    // ------------------------------------------------------------
    int signed expected_c[];
    int signed actual_c[];

    // ------------------------------------------------------------
    // Compare summary
    // ------------------------------------------------------------
    int unsigned element_count;
    int unsigned mismatch_count;
    bit          compare_done;
    bit          compare_pass;

    int          first_mismatch_idx;
    int          first_mismatch_row;
    int          first_mismatch_col;
    int signed   first_expected;
    int signed   first_actual;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_result_item");
        super.new(name);

        case_id            = 0;
        test_kind          = ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE;
        test_name          = "";

        base_addr_a        = '0;
        base_addr_b        = '0;
        base_addr_c        = '0;

        dim_m              = 0;
        dim_n              = 0;
        dim_k              = 0;

        element_count      = 0;
        mismatch_count     = 0;
        compare_done       = 1'b0;
        compare_pass       = 1'b0;

        first_mismatch_idx = -1;
        first_mismatch_row = -1;
        first_mismatch_col = -1;
        first_expected     = 0;
        first_actual       = 0;
    endfunction

    // ------------------------------------------------------------
    // Helper: allocate result vectors
    // ------------------------------------------------------------
    function void alloc_vectors(int unsigned count);
        expected_c = new[count];
        actual_c   = new[count];
        element_count = count;
    endfunction

    // ------------------------------------------------------------
    // Helper: clear compare summary
    // ------------------------------------------------------------
    function void clear_compare_summary();
        mismatch_count     = 0;
        compare_done       = 1'b0;
        compare_pass       = 1'b0;
        first_mismatch_idx = -1;
        first_mismatch_row = -1;
        first_mismatch_col = -1;
        first_expected     = 0;
        first_actual       = 0;
    endfunction

    // ------------------------------------------------------------
    // Helper: run compare
    // ------------------------------------------------------------
    function void run_compare();
        int unsigned i;

        clear_compare_summary();

        if (expected_c.size() != actual_c.size()) begin
            mismatch_count     = 1;
            compare_done       = 1'b1;
            compare_pass       = 1'b0;
            first_mismatch_idx = -1;
            first_mismatch_row = -1;
            first_mismatch_col = -1;
            return;
        end

        element_count = expected_c.size();

        for (i = 0; i < element_count; i++) begin
            if (expected_c[i] !== actual_c[i]) begin
                mismatch_count++;

                if (first_mismatch_idx < 0) begin
                    first_mismatch_idx = i;
                    first_expected     = expected_c[i];
                    first_actual       = actual_c[i];

                    if (dim_n != 0) begin
                        first_mismatch_row = i / dim_n;
                        first_mismatch_col = i % dim_n;
                    end
                end
            end
        end

        compare_done = 1'b1;
        compare_pass = (mismatch_count == 0);
    endfunction

    // ------------------------------------------------------------
    // Deep copy
    // ------------------------------------------------------------
    virtual function void do_copy(uvm_object rhs);
        ai_accel_subsys_result_item rhs_;
        int unsigned i;

        if (!$cast(rhs_, rhs)) begin
            `uvm_fatal("RESULT_ITEM_COPY",
                "do_copy() cast failed for ai_accel_subsys_result_item")
        end

        super.do_copy(rhs);

        case_id            = rhs_.case_id;
        test_kind          = rhs_.test_kind;
        test_name          = rhs_.test_name;

        base_addr_a        = rhs_.base_addr_a;
        base_addr_b        = rhs_.base_addr_b;
        base_addr_c        = rhs_.base_addr_c;

        dim_m              = rhs_.dim_m;
        dim_n              = rhs_.dim_n;
        dim_k              = rhs_.dim_k;

        expected_c = new[rhs_.expected_c.size()];
        for (i = 0; i < rhs_.expected_c.size(); i++) begin
            expected_c[i] = rhs_.expected_c[i];
        end

        actual_c = new[rhs_.actual_c.size()];
        for (i = 0; i < rhs_.actual_c.size(); i++) begin
            actual_c[i] = rhs_.actual_c[i];
        end

        element_count      = rhs_.element_count;
        mismatch_count     = rhs_.mismatch_count;
        compare_done       = rhs_.compare_done;
        compare_pass       = rhs_.compare_pass;

        first_mismatch_idx = rhs_.first_mismatch_idx;
        first_mismatch_row = rhs_.first_mismatch_row;
        first_mismatch_col = rhs_.first_mismatch_col;
        first_expected     = rhs_.first_expected;
        first_actual       = rhs_.first_actual;
    endfunction

    // ------------------------------------------------------------
    // Pretty print helper
    // ------------------------------------------------------------
    virtual function string convert2string();
        return $sformatf(
            "test_name=%s case_id=%0d test_kind=%0d dim=(%0d,%0d,%0d) element_count=%0d mismatch_count=%0d compare_done=%0d compare_pass=%0d first_idx=%0d first_row=%0d first_col=%0d",
            test_name, case_id, test_kind,
            dim_m, dim_n, dim_k,
            element_count, mismatch_count,
            compare_done, compare_pass,
            first_mismatch_idx, first_mismatch_row, first_mismatch_col
        );
    endfunction

endclass

`endif