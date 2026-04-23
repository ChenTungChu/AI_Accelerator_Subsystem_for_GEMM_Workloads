// File: tb/uvm/env/ai_accel_subsys_env.sv
`ifndef AI_ACCEL_SUBSYS_ENV_SV
`define AI_ACCEL_SUBSYS_ENV_SV

class ai_accel_subsys_env extends uvm_env;
    `uvm_component_utils(ai_accel_subsys_env)

    // ------------------------------------------------------------
    // AXI host vif typedef
    //   Must match ai_accel_subsys_uvm_top.sv / host agent
    // ------------------------------------------------------------
    typedef virtual axi_mm_if #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (64),
        .ID_WIDTH   (4),
        .HAS_BURST  (1)
    ) axi0_vif_t;

    // ------------------------------------------------------------
    // Components
    // ------------------------------------------------------------
    ai_accel_subsys_agent                agent;
    axi_mm_host_agent                    host_agent;
    ai_accel_subsys_scoreboard           scoreboard;
    ai_accel_subsys_result_bridge        result_bridge;
    ai_accel_subsys_host_traffic_checker host_traffic_checker;

    // ------------------------------------------------------------
    // Virtual interfaces
    // ------------------------------------------------------------
    virtual ai_accel_subsys_ctrl_if vif;
    axi0_vif_t                      axi0_vif;

    // ------------------------------------------------------------
    // Config knobs
    // ------------------------------------------------------------
    uvm_active_passive_enum host_is_active;
    bit                     enable_log;

    // Host traffic checker knobs
    bit host_traffic_check_enable;
    bit host_traffic_strict_check_enable;
    bit host_traffic_log_enable;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    //
    // Responsibilities:
    //   - fetch shared virtual interfaces
    //   - pass config down to agent / host_agent / scoreboard /
    //     result_bridge / host_traffic_checker
    //   - build all env-level components
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        bit strict_override_present;
        super.build_phase(phase);

        if (!uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::get(
                this, "", "vif", vif)) begin
            `uvm_fatal("ENV/NOVIF",
                "virtual interface ai_accel_subsys_ctrl_if is not set for ai_accel_subsys_env")
        end

        if (!uvm_config_db#(axi0_vif_t)::get(
                this, "", "axi0_vif", axi0_vif)) begin
            `uvm_fatal("ENV/NOAXIVIF",
                "axi0_vif is not set for ai_accel_subsys_env")
        end

        // --------------------------------------------------------
        // Default config
        // --------------------------------------------------------
        host_is_active                  = UVM_PASSIVE;
        enable_log                      = 1'b1;
        host_traffic_check_enable       = 1'b1;
        host_traffic_strict_check_enable = 1'b0;
        host_traffic_log_enable         = 1'b1;

        void'(uvm_config_db#(uvm_active_passive_enum)::get(
            this, "", "host_is_active", host_is_active));

        void'(uvm_config_db#(bit)::get(
            this, "", "enable_log", enable_log));

        void'(uvm_config_db#(bit)::get(
            this, "", "host_traffic_check_enable", host_traffic_check_enable));

        strict_override_present =
            uvm_config_db#(bit)::get(
                this, "", "host_traffic_strict_check_enable",
                host_traffic_strict_check_enable);

        void'(uvm_config_db#(bit)::get(
            this, "", "host_traffic_log_enable", host_traffic_log_enable));

        // Default strict policy:
        //   strict checking only when host agent is ACTIVE
        //   (this matches current Policy B primary-path runs)
        if (!strict_override_present) begin
            host_traffic_strict_check_enable = (host_is_active == UVM_ACTIVE);
        end

        // If checker log knob is not explicitly managed elsewhere,
        // keep it aligned with env logging by default.
        if (!uvm_config_db#(bit)::exists(this, "", "host_traffic_log_enable")) begin
            host_traffic_log_enable = enable_log;
        end

        // --------------------------------------------------------
        // Pass config down
        // --------------------------------------------------------

        // control agent
        uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::set(
            this, "agent", "vif", vif);

        // host agent
        uvm_config_db#(axi0_vif_t)::set(
            this, "host_agent", "axi0_vif", axi0_vif);

        uvm_config_db#(uvm_active_passive_enum)::set(
            this, "host_agent", "is_active", host_is_active);

        uvm_config_db#(bit)::set(
            this, "host_agent", "enable_log", enable_log);

        // scoreboard / result bridge
        uvm_config_db#(bit)::set(
            this, "scoreboard", "enable_log", enable_log);

        uvm_config_db#(bit)::set(
            this, "result_bridge", "enable_log", enable_log);

        // host traffic checker
        uvm_config_db#(bit)::set(
            this, "host_traffic_checker", "enable_check",
            host_traffic_check_enable);

        uvm_config_db#(bit)::set(
            this, "host_traffic_checker", "strict_check_enable",
            host_traffic_strict_check_enable);

        uvm_config_db#(bit)::set(
            this, "host_traffic_checker", "log_enable",
            host_traffic_log_enable);

        // --------------------------------------------------------
        // Build env components
        // --------------------------------------------------------
        agent                = ai_accel_subsys_agent               ::type_id::create("agent",                this);
        host_agent           = axi_mm_host_agent                   ::type_id::create("host_agent",           this);
        scoreboard           = ai_accel_subsys_scoreboard          ::type_id::create("scoreboard",           this);
        result_bridge        = ai_accel_subsys_result_bridge       ::type_id::create("result_bridge",        this);
        host_traffic_checker = ai_accel_subsys_host_traffic_checker::type_id::create("host_traffic_checker", this);

        if (enable_log) begin
            `uvm_info("ENV",
                $sformatf("Built env with host_agent is_active=%s, host_traffic_checker(enable=%0d strict=%0d)",
                    (host_is_active == UVM_ACTIVE) ? "UVM_ACTIVE" : "UVM_PASSIVE",
                    host_traffic_check_enable,
                    host_traffic_strict_check_enable),
                UVM_LOW)
        end
    endfunction

    // ------------------------------------------------------------
    // Connect phase
    //
    // Paths:
    //   - control observation -> scoreboard + host traffic checker
    //   - result compare      -> scoreboard
    //   - host monitor        -> host traffic checker
    // ------------------------------------------------------------
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        // --------------------------------------------------------
        // Control observation path
        // --------------------------------------------------------
        agent.monitor.ap.connect(scoreboard.ctrl_analysis_export);
        agent.monitor.ap.connect(host_traffic_checker.ctrl_imp);

        // --------------------------------------------------------
        // Result compare path
        // --------------------------------------------------------
        result_bridge.ap.connect(scoreboard.result_analysis_export);

        // --------------------------------------------------------
        // Host AXI observation path
        // --------------------------------------------------------
        host_agent.monitor.ap.connect(host_traffic_checker.host_imp);
    endfunction

    // ------------------------------------------------------------
    // Convenience pass-through helpers
    // ------------------------------------------------------------
    function void set_host_case_context(
        input int unsigned case_id,
        input ai_accel_subsys_seq_item::test_kind_e test_kind,
        input string test_name = "",
        input int unsigned job_idx = 0
    );
        if (host_agent == null) begin
            `uvm_error("ENV/NOHOSTAGENT",
                "set_host_case_context() called when host_agent is null")
            return;
        end

        host_agent.set_case_context(case_id, test_kind, test_name, job_idx);
    endfunction

    function void clear_host_case_context();
        if (host_agent == null)
            return;

        host_agent.clear_case_context();
    endfunction

endclass

`endif