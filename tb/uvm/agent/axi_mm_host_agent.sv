// File: tb/uvm/agent/axi_mm_host_agent.sv
`ifndef AXI_MM_HOST_AGENT_SV
`define AXI_MM_HOST_AGENT_SV

class axi_mm_host_agent extends uvm_agent;
    `uvm_component_utils(axi_mm_host_agent)

    // ------------------------------------------------------------
    // AXI host vif typedef
    //   Must match top / driver / monitor
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
    axi_mm_host_sequencer sequencer;
    axi_mm_host_driver    driver;
    axi_mm_host_monitor   monitor;

    // ------------------------------------------------------------
    // Config / bookkeeping
    // ------------------------------------------------------------
    axi0_vif_t                 vif;
    uvm_active_passive_enum    is_active_mode;
    bit                        enable_log;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "axi_mm_host_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(axi0_vif_t)::get(this, "", "axi0_vif", vif)) begin
            `uvm_fatal("AXI_HOST_AGENT/NOVIF",
                "axi0_vif is not set for axi_mm_host_agent")
        end

        is_active_mode = UVM_ACTIVE;
        enable_log     = 1'b1;

        void'(uvm_config_db#(uvm_active_passive_enum)::get(
            this, "", "is_active", is_active_mode));

        void'(uvm_config_db#(bit)::get(
            this, "", "enable_log", enable_log));

        // Pass common config down
        uvm_config_db#(axi0_vif_t)::set(this, "monitor", "axi0_vif", vif);
        uvm_config_db#(bit)::set(this, "monitor", "enable_log", enable_log);

        monitor = axi_mm_host_monitor::type_id::create("monitor", this);

        if (is_active_mode == UVM_ACTIVE) begin
            uvm_config_db#(axi0_vif_t)::set(this, "driver", "axi0_vif", vif);
            uvm_config_db#(bit)::set(this, "driver", "enable_log", enable_log);
            uvm_config_db#(bit)::set(this, "sequencer", "enable_log", enable_log);

            sequencer = axi_mm_host_sequencer::type_id::create("sequencer", this);
            driver    = axi_mm_host_driver   ::type_id::create("driver",    this);
        end

        if (enable_log) begin
            `uvm_info("AXI_HOST_AGENT",
                $sformatf("Built host agent: is_active=%s",
                    (is_active_mode == UVM_ACTIVE) ? "UVM_ACTIVE" : "UVM_PASSIVE"),
                UVM_LOW)
        end
    endfunction

    // ------------------------------------------------------------
    // Connect phase
    // ------------------------------------------------------------
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        if (is_active_mode == UVM_ACTIVE) begin
            if ((driver == null) || (sequencer == null)) begin
                `uvm_fatal("AXI_HOST_AGENT/NULL_ACTIVE_COMP",
                    "driver/sequencer is null while agent is ACTIVE")
            end
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end

        if (monitor == null) begin
            `uvm_fatal("AXI_HOST_AGENT/NOMON",
                "monitor is null in connect_phase")
        end
    endfunction

    // ------------------------------------------------------------
    // Runtime context pass-through
    // ------------------------------------------------------------
    function void set_case_context(
        input int unsigned case_id,
        input ai_accel_subsys_seq_item::test_kind_e test_kind,
        input string test_name = "",
        input int unsigned job_idx = 0
    );
        if (monitor == null) begin
            `uvm_error("AXI_HOST_AGENT/NOMON",
                "set_case_context() called when monitor is null")
            return;
        end

        monitor.set_case_context(case_id, test_kind, test_name, job_idx);
    endfunction

    function void clear_case_context();
        if (monitor == null)
            return;

        monitor.clear_case_context();
    endfunction

    // ------------------------------------------------------------
    // Report phase
    // ------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        if (enable_log) begin
            `uvm_info("AXI_HOST_AGENT",
                $sformatf("Host agent summary: is_active=%s",
                    (is_active_mode == UVM_ACTIVE) ? "UVM_ACTIVE" : "UVM_PASSIVE"),
                UVM_LOW)
        end
    endfunction

endclass

`endif