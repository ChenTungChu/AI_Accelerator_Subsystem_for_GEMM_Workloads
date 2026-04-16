// File: tb/uvm/seq/ai_accel_subsys_smoke_seq.sv

`ifndef AI_ACCEL_SUBSYS_SMOKE_SEQ_SV
`define AI_ACCEL_SUBSYS_SMOKE_SEQ_SV

class ai_accel_subsys_smoke_seq extends uvm_sequence #(ai_accel_subsys_seq_item);
    `uvm_object_utils(ai_accel_subsys_smoke_seq)

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_smoke_seq");
        super.new(name);
    endfunction

    // ------------------------------------------------------------
    // Body
    // ------------------------------------------------------------
    virtual task body();
        ai_accel_subsys_seq_item req;

        `uvm_info("SMOKE_SEQ",
            "Starting ai_accel_subsys_smoke_seq",
            UVM_MEDIUM)

        req = ai_accel_subsys_seq_item::type_id::create("req");

        start_item(req);

        // First UVM smoke case:
        // reuse current non-UVM known-good profile
        req.apply_fixed_baseline_case(0);

        finish_item(req);

        `uvm_info("SMOKE_SEQ",
            $sformatf("Issued seq_item: %s", req.convert2string()),
            UVM_MEDIUM)
    endtask

endclass

`endif