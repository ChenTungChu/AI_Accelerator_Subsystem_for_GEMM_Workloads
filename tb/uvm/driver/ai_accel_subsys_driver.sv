// File: tb/uvm/driver/ai_accel_subsys_driver.sv

`ifndef AI_ACCEL_SUBSYS_DRIVER_SV
`define AI_ACCEL_SUBSYS_DRIVER_SV

class ai_accel_subsys_driver extends uvm_driver #(ai_accel_subsys_seq_item);
    `uvm_component_utils(ai_accel_subsys_driver)

    // ------------------------------------------------------------
    // Virtual interface
    // ------------------------------------------------------------
    virtual ai_accel_subsys_ctrl_if vif;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::get(
                this, "", "vif", vif)) begin
            `uvm_fatal("DRV/NOVIF",
                "virtual interface ai_accel_subsys_ctrl_if is not set for ai_accel_subsys_driver")
        end
    endfunction

    // ------------------------------------------------------------
    // Run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ai_accel_subsys_seq_item req;

        forever begin
            seq_item_port.get_next_item(req);

            `uvm_info("DRV",
                $sformatf("Driving seq_item: %s", req.convert2string()),
                UVM_MEDIUM)

            drive_one_item(req);

            seq_item_port.item_done();
        end
    endtask

    // ------------------------------------------------------------
    // Drive one subsystem job configuration
    // ------------------------------------------------------------
    task drive_one_item(ai_accel_subsys_seq_item req);
        wait_for_reset_release();
        drive_configuration(req);
        pulse_start();
    endtask

    // ------------------------------------------------------------
    // Wait until subsystem reset is released
    // ------------------------------------------------------------
    task wait_for_reset_release();
        @vif.cb_drv;
        while ((vif.cb_drv.dma_rst_n !== 1'b1) || (vif.cb_drv.core_rst_n !== 1'b1)) begin
            @vif.cb_drv;
        end
    endtask

    // ------------------------------------------------------------
    // Drive runtime configuration
    // ------------------------------------------------------------
    task drive_configuration(ai_accel_subsys_seq_item req);
        @vif.cb_drv;

        vif.cb_drv.base_addr_a       <= req.base_addr_a;
        vif.cb_drv.base_addr_b       <= req.base_addr_b;
        vif.cb_drv.base_addr_c       <= req.base_addr_c;

        vif.cb_drv.dim_m             <= req.dim_m;
        vif.cb_drv.dim_n             <= req.dim_n;
        vif.cb_drv.dim_k             <= req.dim_k;

        // C RMW accumulation runtime control.
        //
        // This must be driven per job, not only through the top-level
        // ACCUMULATE_ENABLE plusarg, because the C RMW accumulation two-job recipe uses:
        //   job0: accumulate_enable = 0
        //   job1: accumulate_enable = 1
        vif.cb_drv.accumulate_enable <= req.accumulate_enable;

        `uvm_info("DRV",
            $sformatf("Applied config: base_a=0x%08h base_b=0x%08h base_c=0x%08h dim=(%0d,%0d,%0d) accumulate_enable=%0d",
                req.base_addr_a, req.base_addr_b, req.base_addr_c,
                req.dim_m, req.dim_n, req.dim_k,
                req.accumulate_enable),
            UVM_MEDIUM)
    endtask

    // ------------------------------------------------------------
    // Generate one-cycle start pulse
    // ------------------------------------------------------------
    task pulse_start();
        @vif.cb_drv;
        vif.cb_drv.acc_start <= 1'b1;

        @vif.cb_drv;
        vif.cb_drv.acc_start <= 1'b0;

        `uvm_info("DRV", "Issued acc_start pulse", UVM_MEDIUM)
    endtask

endclass

`endif
