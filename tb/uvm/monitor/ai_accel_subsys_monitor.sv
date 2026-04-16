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
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
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
    // Run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ai_accel_subsys_seq_item tr;
        bit prev_acc_start;

        prev_acc_start = 1'b0;

        wait_for_reset_release();

        forever begin
            @vif.cb_mon;

            // detect rising edge of acc_start
            if ((vif.cb_mon.acc_start === 1'b1) && (prev_acc_start === 1'b0)) begin
                tr = ai_accel_subsys_seq_item::type_id::create("tr", this);

                tr.base_addr_a = vif.cb_mon.base_addr_a;
                tr.base_addr_b = vif.cb_mon.base_addr_b;
                tr.base_addr_c = vif.cb_mon.base_addr_c;

                tr.dim_m       = vif.cb_mon.dim_m;
                tr.dim_n       = vif.cb_mon.dim_n;
                tr.dim_k       = vif.cb_mon.dim_k;

                tr.test_name   = "monitored_start_event";

                `uvm_info("MON",
                    $sformatf("Observed acc_start: base_a=0x%08h base_b=0x%08h base_c=0x%08h dim=(%0d,%0d,%0d)",
                        tr.base_addr_a, tr.base_addr_b, tr.base_addr_c,
                        tr.dim_m, tr.dim_n, tr.dim_k),
                    UVM_MEDIUM)

                ap.write(tr);
            end

            prev_acc_start = vif.cb_mon.acc_start;
        end
    endtask

endclass

`endif