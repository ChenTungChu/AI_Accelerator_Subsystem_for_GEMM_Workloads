// File: tb/uvm/monitor/ai_accel_subsys_monitor.sv
`ifndef AI_ACCEL_SUBSYS_MONITOR_SV
`define AI_ACCEL_SUBSYS_MONITOR_SV

class ai_accel_subsys_monitor extends uvm_monitor;
    `uvm_component_utils(ai_accel_subsys_monitor)

    // ------------------------------------------------------------
    // Virtual interface
    // ------------------------------------------------------------
    virtual ai_accel_subsys_ctrl_if vif;

    // ------------------------------------------------------------
    // Analysis port
    // ------------------------------------------------------------
    uvm_analysis_port #(ai_accel_subsys_seq_item) ap;

    // ------------------------------------------------------------
    // Optional test context from config_db
    //   For current smoke flow, this lets monitor annotate the
    //   observed transaction with case_id / test_kind.
    // ------------------------------------------------------------
    int unsigned selected_case_id;
    ai_accel_subsys_seq_item::test_kind_e selected_test_kind;
    bit has_selected_case_id;
    bit has_selected_test_kind;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);

        selected_case_id      = 0;
        selected_test_kind    = ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE;
        has_selected_case_id  = 1'b0;
        has_selected_test_kind= 1'b0;
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::get(
                this, "", "vif", vif)) begin
            `uvm_fatal("MON/NOVIF",
                "virtual interface ai_accel_subsys_ctrl_if is not set for ai_accel_subsys_monitor")
        end

        has_selected_case_id = uvm_config_db#(int unsigned)::get(
            this, "", "selected_case_id", selected_case_id);

        has_selected_test_kind = uvm_config_db#(ai_accel_subsys_seq_item::test_kind_e)::get(
            this, "", "selected_test_kind", selected_test_kind);
    endfunction

    // ------------------------------------------------------------
    // Wait until subsystem reset is released
    // ------------------------------------------------------------
    task automatic wait_for_reset_release();
        @vif.cb_mon;
        while ((vif.cb_mon.dma_rst_n !== 1'b1) || (vif.cb_mon.core_rst_n !== 1'b1)) begin
            @vif.cb_mon;
        end
    endtask

    // ------------------------------------------------------------
    // Wait for acc_done and return done cycle
    // ------------------------------------------------------------
    task automatic wait_for_acc_done(
        input  int unsigned start_cycle,
        output int unsigned done_cycle
    );
    begin
        done_cycle = start_cycle;

        while (vif.cb_mon.acc_done !== 1'b1) begin
            @vif.cb_mon;
            done_cycle++;
        end
    end
    endtask

    // ------------------------------------------------------------
    // Fill optional context fields
    // ------------------------------------------------------------
    function void annotate_test_context(ref ai_accel_subsys_seq_item tr);
        if (has_selected_case_id)
            tr.case_id = selected_case_id;

        if (has_selected_test_kind)
            tr.test_kind = selected_test_kind;

        if (has_selected_case_id && has_selected_test_kind) begin
            case (selected_test_kind)
                ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE:
                    tr.test_name = $sformatf("fixed_baseline_case_%0d", selected_case_id);

                ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE:
                    tr.test_name = $sformatf("variable_dim_case_%0d", selected_case_id);

                ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE:
                    tr.test_name = $sformatf("config_base_case_%0d", selected_case_id);

                default:
                    tr.test_name = $sformatf("observed_case_%0d_kind_%0d",
                        selected_case_id, selected_test_kind);
            endcase
        end
        else begin
            tr.test_name = "monitored_start_event";
        end
    endfunction

    // ------------------------------------------------------------
    // Run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ai_accel_subsys_seq_item tr;
        bit prev_acc_start;
        int unsigned mon_cycle;
        int unsigned done_cycle_local;

        prev_acc_start   = 1'b0;
        mon_cycle        = 0;
        done_cycle_local = 0;

        wait_for_reset_release();

        forever begin
            @vif.cb_mon;
            mon_cycle++;

            // detect rising edge of acc_start
            if ((vif.cb_mon.acc_start === 1'b1) && (prev_acc_start === 1'b0)) begin
                tr = ai_accel_subsys_seq_item::type_id::create("tr", this);

                tr.base_addr_a = vif.cb_mon.base_addr_a;
                tr.base_addr_b = vif.cb_mon.base_addr_b;
                tr.base_addr_c = vif.cb_mon.base_addr_c;

                tr.dim_m       = vif.cb_mon.dim_m;
                tr.dim_n       = vif.cb_mon.dim_n;
                tr.dim_k       = vif.cb_mon.dim_k;

                tr.done_seen      = 1'b0;
                tr.start_cycle    = mon_cycle;
                tr.done_cycle     = 0;
                tr.latency_cycles = 0;

                annotate_test_context(tr);

                `uvm_info("MON",
                    $sformatf("Observed acc_start: case_id=%0d test_kind=%0d base_a=0x%08h base_b=0x%08h base_c=0x%08h dim=(%0d,%0d,%0d) start_cycle=%0d",
                        tr.case_id, tr.test_kind,
                        tr.base_addr_a, tr.base_addr_b, tr.base_addr_c,
                        tr.dim_m, tr.dim_n, tr.dim_k, tr.start_cycle),
                    UVM_MEDIUM)

                wait_for_acc_done(tr.start_cycle, done_cycle_local);

                // keep local cycle counter aligned with wait_for_acc_done progress
                mon_cycle = done_cycle_local;

                tr.done_seen      = 1'b1;
                tr.done_cycle     = done_cycle_local;
                tr.latency_cycles = tr.done_cycle - tr.start_cycle;

                `uvm_info("MON",
                    $sformatf("Observed acc_done: case_id=%0d test_kind=%0d start_cycle=%0d done_cycle=%0d latency_cycles=%0d",
                        tr.case_id, tr.test_kind,
                        tr.start_cycle, tr.done_cycle, tr.latency_cycles),
                    UVM_MEDIUM)

                ap.write(tr);

                prev_acc_start = vif.cb_mon.acc_start;
                continue;
            end

            prev_acc_start = vif.cb_mon.acc_start;
        end
    endtask

endclass

`endif