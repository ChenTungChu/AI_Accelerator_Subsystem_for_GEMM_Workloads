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
    //
    // Same ctrl path as before.
    // v1.5 change:
    //   this path now publishes both START and DONE events.
    // ------------------------------------------------------------
    uvm_analysis_port #(ai_accel_subsys_seq_item) ap;

    // ------------------------------------------------------------
    // Optional static test context from config_db
    //   Works for single-job smoke flow.
    // ------------------------------------------------------------
    int unsigned selected_case_id;
    ai_accel_subsys_seq_item::test_kind_e selected_test_kind;
    bit has_selected_case_id;
    bit has_selected_test_kind;

    // ------------------------------------------------------------
    // Runtime test context
    //   Needed for back-to-back / multi-job flow.
    // ------------------------------------------------------------
    int unsigned runtime_case_id;
    ai_accel_subsys_seq_item::test_kind_e runtime_test_kind;
    bit has_runtime_case_context;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);

        selected_case_id         = 0;
        selected_test_kind       = ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE;
        has_selected_case_id     = 1'b0;
        has_selected_test_kind   = 1'b0;

        runtime_case_id          = 0;
        runtime_test_kind        = ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE;
        has_runtime_case_context = 1'b0;
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
    // Runtime context setter
    // ------------------------------------------------------------
    function void set_case_context(
        input int unsigned case_id,
        input ai_accel_subsys_seq_item::test_kind_e test_kind
    );
        runtime_case_id          = case_id;
        runtime_test_kind        = test_kind;
        has_runtime_case_context = 1'b1;

        `uvm_info("MON",
            $sformatf("Updated runtime context: case_id=%0d test_kind=%0d",
                runtime_case_id, runtime_test_kind),
            UVM_HIGH)
    endfunction

    // ------------------------------------------------------------
    // Optional runtime context clear
    // ------------------------------------------------------------
    function void clear_case_context();
        has_runtime_case_context = 1'b0;
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
    // Helper: build test_name from case_id / test_kind
    // ------------------------------------------------------------
    function string build_test_name(
        input int unsigned case_id,
        input ai_accel_subsys_seq_item::test_kind_e test_kind
    );
        case (test_kind)
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE:
                return $sformatf("fixed_baseline_case_%0d", case_id);

            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE:
                return $sformatf("variable_dim_case_%0d", case_id);

            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE:
                return $sformatf("config_base_case_%0d", case_id);

            default:
                return $sformatf("observed_case_%0d_kind_%0d", case_id, test_kind);
        endcase
    endfunction

    // ------------------------------------------------------------
    // Fill context fields
    //
    // Priority:
    //   1. runtime context   (for back-to-back / multi-job)
    //   2. static config_db  (for single-job smoke)
    //   3. fallback only
    // ------------------------------------------------------------
    function void annotate_test_context(ref ai_accel_subsys_seq_item tr);
        if (has_runtime_case_context) begin
            tr.case_id   = runtime_case_id;
            tr.test_kind = runtime_test_kind;
            tr.test_name = build_test_name(runtime_case_id, runtime_test_kind);
        end
        else if (has_selected_case_id && has_selected_test_kind) begin
            tr.case_id   = selected_case_id;
            tr.test_kind = selected_test_kind;
            tr.test_name = build_test_name(selected_case_id, selected_test_kind);
        end
        else begin
            tr.test_name = "monitored_ctrl_event";
        end
    endfunction

    // ------------------------------------------------------------
    // Fill profile fields from ctrl_if
    // ------------------------------------------------------------
    function void fill_ctrl_profile(ref ai_accel_subsys_seq_item tr);
        tr.base_addr_a = vif.cb_mon.base_addr_a;
        tr.base_addr_b = vif.cb_mon.base_addr_b;
        tr.base_addr_c = vif.cb_mon.base_addr_c;

        tr.dim_m       = vif.cb_mon.dim_m;
        tr.dim_n       = vif.cb_mon.dim_n;
        tr.dim_k       = vif.cb_mon.dim_k;

        annotate_test_context(tr);
    endfunction

    // ------------------------------------------------------------
    // Publish START event on the same ctrl path
    // ------------------------------------------------------------
    task automatic publish_start_event(
        input int unsigned mon_cycle,
        output ai_accel_subsys_seq_item active_job
    );
        ai_accel_subsys_seq_item tr_start;
    begin
        tr_start = ai_accel_subsys_seq_item::type_id::create("tr_start");
        fill_ctrl_profile(tr_start);
        tr_start.mark_start_event(mon_cycle);

        `uvm_info("MON",
            $sformatf("Observed acc_start: case_id=%0d test_kind=%0d base_a=0x%08h base_b=0x%08h base_c=0x%08h dim=(%0d,%0d,%0d) start_cycle=%0d",
                tr_start.case_id, tr_start.test_kind,
                tr_start.base_addr_a, tr_start.base_addr_b, tr_start.base_addr_c,
                tr_start.dim_m, tr_start.dim_n, tr_start.dim_k,
                tr_start.start_cycle),
            UVM_MEDIUM)

        ap.write(tr_start);

        active_job = ai_accel_subsys_seq_item::type_id::create("active_job");
        active_job.copy(tr_start);
    end
    endtask

    // ------------------------------------------------------------
    // Publish DONE event on the same ctrl path
    // ------------------------------------------------------------
    task automatic publish_done_event(
        input ai_accel_subsys_seq_item active_job,
        input int unsigned             mon_cycle
    );
        ai_accel_subsys_seq_item tr_done;
    begin
        if (active_job == null) begin
            `uvm_error("MON/DONE_NO_ACTIVE_JOB",
                "publish_done_event called with null active_job; dropping DONE event")
            return;
        end

        tr_done = ai_accel_subsys_seq_item::type_id::create("tr_done");
        tr_done.copy(active_job);
        tr_done.mark_done_event(active_job.start_cycle, mon_cycle);

        `uvm_info("MON",
            $sformatf("Observed acc_done: case_id=%0d test_kind=%0d start_cycle=%0d done_cycle=%0d latency_cycles=%0d",
                tr_done.case_id, tr_done.test_kind,
                tr_done.start_cycle, tr_done.done_cycle, tr_done.latency_cycles),
            UVM_MEDIUM)

        ap.write(tr_done);
    end
    endtask

    // ------------------------------------------------------------
    // Run phase
    //
    // Same ctrl path, but now phase-aware:
    //   - publish START event on acc_start rising edge
    //   - publish DONE  event on acc_done  rising edge
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ai_accel_subsys_seq_item active_job;
        bit prev_acc_start;
        bit prev_acc_done;
        bit has_active_job;
        int unsigned mon_cycle;

        prev_acc_start = 1'b0;
        prev_acc_done  = 1'b0;
        has_active_job = 1'b0;
        mon_cycle      = 0;
        active_job     = null;

        wait_for_reset_release();

        forever begin
            @vif.cb_mon;

            // If runtime reset is asserted, drop any pending job state
            // and wait until reset is released again.
            if ((vif.cb_mon.dma_rst_n !== 1'b1) || (vif.cb_mon.core_rst_n !== 1'b1)) begin
                if (has_active_job) begin
                    `uvm_info("MON/RESET_DROPPED_ACTIVE_JOB",
                        "Reset asserted while monitor still had an active ctrl job; dropping pending state",
                        UVM_MEDIUM)
                end

                has_active_job = 1'b0;
                active_job     = null;
                prev_acc_start = 1'b0;
                prev_acc_done  = 1'b0;

                wait_for_reset_release();
                continue;
            end

            mon_cycle++;

            // detect rising edge of acc_start
            if ((vif.cb_mon.acc_start === 1'b1) && (prev_acc_start === 1'b0)) begin
                if (has_active_job) begin
                    `uvm_error("MON/START_WHILE_ACTIVE",
                        "Observed new acc_start while previous ctrl job is still active; ignoring new START edge")
                end
                else begin
                    publish_start_event(mon_cycle, active_job);
                    has_active_job = 1'b1;
                end
            end

            // detect rising edge of acc_done
            if ((vif.cb_mon.acc_done === 1'b1) && (prev_acc_done === 1'b0)) begin
                if (!has_active_job) begin
                    `uvm_warning("MON/DONE_WITHOUT_ACTIVE_JOB",
                        "Observed acc_done without an active ctrl job; dropping DONE edge")
                end
                else begin
                    publish_done_event(active_job, mon_cycle);

                    has_active_job = 1'b0;
                    active_job     = null;
                end
            end

            prev_acc_start = vif.cb_mon.acc_start;
            prev_acc_done  = vif.cb_mon.acc_done;
        end
    endtask

endclass

`endif