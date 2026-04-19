// File: tb/uvm/seq/ai_accel_subsys_smoke_seq.sv

`ifndef AI_ACCEL_SUBSYS_SMOKE_SEQ_SV
`define AI_ACCEL_SUBSYS_SMOKE_SEQ_SV

class ai_accel_subsys_smoke_seq extends uvm_sequence #(ai_accel_subsys_seq_item);
    `uvm_object_utils(ai_accel_subsys_smoke_seq)

    // ------------------------------------------------------------
    // Public knobs set by smoke_test
    // ------------------------------------------------------------
    int unsigned case_id;
    ai_accel_subsys_seq_item::test_kind_e test_kind;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_smoke_seq");
        super.new(name);

        case_id   = 0;
        test_kind = ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE;
    endfunction

    // ------------------------------------------------------------
    // Body
    // ------------------------------------------------------------
    virtual task body();
        ai_accel_subsys_seq_item req;

        `uvm_info("SMOKE_SEQ",
            $sformatf("Starting ai_accel_subsys_smoke_seq with case_id=%0d test_kind=%0d",
                case_id, test_kind),
            UVM_MEDIUM)

        req = ai_accel_subsys_seq_item::type_id::create("req");

        start_item(req);

        case (test_kind)
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE: begin
                req.apply_fixed_baseline_case(case_id);
            end

            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE: begin
                req.apply_variable_dim_case(case_id);
            end

            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE: begin
                req.apply_configurable_base_case(case_id);
            end

            default: begin
                `uvm_fatal("SMOKE_SEQ/BAD_KIND",
                    $sformatf("Unsupported test_kind=%0d for case_id=%0d",
                        test_kind, case_id))
            end
        endcase

        finish_item(req);

        `uvm_info("SMOKE_SEQ",
            $sformatf("Issued seq_item: %s", req.convert2string()),
            UVM_MEDIUM)
    endtask

endclass

`endif