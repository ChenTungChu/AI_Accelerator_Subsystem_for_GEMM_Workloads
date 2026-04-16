// File: tb/uvm/agent/ai_accel_subsys_agent.sv
`ifndef AI_ACCEL_SUBSYS_AGENT_SV
`define AI_ACCEL_SUBSYS_AGENT_SV

class ai_accel_subsys_agent extends uvm_agent;
    `uvm_component_utils(ai_accel_subsys_agent)

    // ------------------------------------------------------------
    // Components
    // ------------------------------------------------------------
    ai_accel_subsys_sequencer sequencer;
    ai_accel_subsys_driver    driver;
    ai_accel_subsys_monitor   monitor;

    // ------------------------------------------------------------
    // Virtual interface
    // ------------------------------------------------------------
    virtual ai_accel_subsys_ctrl_if vif;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::get(
                this, "", "vif", vif)) begin
            `uvm_fatal("AGT/NOVIF",
                "virtual interface ai_accel_subsys_ctrl_if is not set for ai_accel_subsys_agent")
        end

        // First-step minimal active agent:
        // build sequencer + driver + monitor
        sequencer = ai_accel_subsys_sequencer::type_id::create("sequencer", this);
        driver    = ai_accel_subsys_driver   ::type_id::create("driver",    this);
        monitor   = ai_accel_subsys_monitor  ::type_id::create("monitor",   this);

        // Pass vif down to driver and monitor
        uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::set(
            this, "driver", "vif", vif);

        uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::set(
            this, "monitor", "vif", vif);
    endfunction

    // ------------------------------------------------------------
    // Connect phase
    // ------------------------------------------------------------
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass

`endif