// File: tb/uvm/test/ai_accel_subsys_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_SMOKE_TEST_SV

class ai_accel_subsys_smoke_test extends uvm_test;
    `uvm_component_utils(ai_accel_subsys_smoke_test)

    // ------------------------------------------------------------
    // Components
    // ------------------------------------------------------------
    ai_accel_subsys_env env;

    // ------------------------------------------------------------
    // Virtual interface
    // ------------------------------------------------------------
    virtual ai_accel_subsys_ctrl_if vif;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_smoke_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::get(
                this, "", "vif", vif)) begin
            `uvm_fatal("TEST/NOVIF",
                "virtual interface ai_accel_subsys_ctrl_if is not set for ai_accel_subsys_smoke_test")
        end

        env = ai_accel_subsys_env::type_id::create("env", this);

        // Pass vif down to env
        uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::set(
            this, "env", "vif", vif);
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
    // Wait for acc_done with timeout
    // ------------------------------------------------------------
    task automatic wait_for_acc_done(int unsigned timeout_cycles = 20000);
        int unsigned cnt;
    begin
        cnt = 0;

        @vif.cb_mon;
        while (vif.cb_mon.acc_done !== 1'b1) begin
            @vif.cb_mon;
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("SMOKE_TIMEOUT",
                    $sformatf("Timed out waiting for acc_done after %0d cycles", timeout_cycles))
            end
        end

        `uvm_info("SMOKE_TEST",
            $sformatf("Observed acc_done after %0d monitor cycles", cnt),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ai_accel_subsys_smoke_seq seq;

        phase.raise_objection(this);

        `uvm_info("SMOKE_TEST",
            "Starting ai_accel_subsys_smoke_test",
            UVM_MEDIUM)

        wait_for_reset_release();

        seq = ai_accel_subsys_smoke_seq::type_id::create("seq");

        seq.start(env.agent.sequencer);

        `uvm_info("SMOKE_TEST",
            "Completed ai_accel_subsys_smoke_seq, now waiting for acc_done",
            UVM_MEDIUM)

        wait_for_acc_done();

        `uvm_info("SMOKE_TEST",
            "Smoke test completed with acc_done observed",
            UVM_MEDIUM)

        phase.drop_objection(this);
    endtask

endclass

`endif