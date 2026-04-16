// File: tb/uvm/scoreboard/ai_accel_subsys_scoreboard.sv
`ifndef AI_ACCEL_SUBSYS_SCOREBOARD_SV
`define AI_ACCEL_SUBSYS_SCOREBOARD_SV

class ai_accel_subsys_scoreboard extends uvm_component;
    `uvm_component_utils(ai_accel_subsys_scoreboard)

    // ------------------------------------------------------------
    // Analysis import
    // ------------------------------------------------------------
    uvm_analysis_imp #(ai_accel_subsys_seq_item, ai_accel_subsys_scoreboard) analysis_export;

    // ------------------------------------------------------------
    // Simple counters / last-observed item
    // ------------------------------------------------------------
    int unsigned observed_start_count;
    ai_accel_subsys_seq_item last_seen_item;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        analysis_export = new("analysis_export", this);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        observed_start_count = 0;
    endfunction

    // ------------------------------------------------------------
    // Analysis write callback
    // ------------------------------------------------------------
    function void write(ai_accel_subsys_seq_item t);
        observed_start_count++;

        last_seen_item = ai_accel_subsys_seq_item::type_id::create("last_seen_item");
        last_seen_item.copy(t);

        `uvm_info("SB",
            $sformatf(
                "Observed start event #%0d: base_a=0x%08h base_b=0x%08h base_c=0x%08h dim=(%0d,%0d,%0d) test_name=%s",
                observed_start_count,
                t.base_addr_a, t.base_addr_b, t.base_addr_c,
                t.dim_m, t.dim_n, t.dim_k,
                t.test_name
            ),
            UVM_MEDIUM)
    endfunction

    // ------------------------------------------------------------
    // Report phase
    // ------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        `uvm_info("SB",
            $sformatf("Scoreboard observed %0d start event(s)", observed_start_count),
            UVM_LOW)

        if (observed_start_count == 0) begin
            `uvm_error("SB/NOSTART", "Scoreboard did not observe any acc_start event")
        end
    endfunction

endclass

`endif