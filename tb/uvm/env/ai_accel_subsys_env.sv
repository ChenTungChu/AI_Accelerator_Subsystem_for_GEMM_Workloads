// File: tb/uvm/env/ai_accel_subsys_env.sv
`ifndef AI_ACCEL_SUBSYS_ENV_SV
`define AI_ACCEL_SUBSYS_ENV_SV

class ai_accel_subsys_env extends uvm_env;
    `uvm_component_utils(ai_accel_subsys_env)

    // ------------------------------------------------------------
    // Components
    // ------------------------------------------------------------
    ai_accel_subsys_agent      agent;
    ai_accel_subsys_scoreboard scoreboard;

    // ------------------------------------------------------------
    // Virtual interface
    // ------------------------------------------------------------
    virtual ai_accel_subsys_ctrl_if vif;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::get(
                this, "", "vif", vif)) begin
            `uvm_fatal("ENV/NOVIF",
                "virtual interface ai_accel_subsys_ctrl_if is not set for ai_accel_subsys_env")
        end

        // Build minimal env with one active agent + scoreboard
        agent      = ai_accel_subsys_agent     ::type_id::create("agent",      this);
        scoreboard = ai_accel_subsys_scoreboard::type_id::create("scoreboard", this);

        // Pass vif down to agent
        uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::set(
            this, "agent", "vif", vif);
    endfunction

    // ------------------------------------------------------------
    // Connect phase
    // ------------------------------------------------------------
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction

endclass

`endif