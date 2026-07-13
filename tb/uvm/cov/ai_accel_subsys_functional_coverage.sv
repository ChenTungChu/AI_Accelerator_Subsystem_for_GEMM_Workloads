// File: tb/uvm/cov/ai_accel_subsys_functional_coverage.sv
`ifndef AI_ACCEL_SUBSYS_FUNCTIONAL_COVERAGE_SV
`define AI_ACCEL_SUBSYS_FUNCTIONAL_COVERAGE_SV

class ai_accel_subsys_functional_coverage extends uvm_subscriber #(ai_accel_subsys_seq_item);
    `uvm_component_utils(ai_accel_subsys_functional_coverage)

    typedef virtual axi_lite_if #(
        .ADDR_WIDTH (12),
        .DATA_WIDTH (32)
    ) csr_vif_t;

    // ------------------------------------------------------------
    // Canonical CSR offsets
    //   Source: docs/axi_lite_csr_control_plane_spec.md
    // ------------------------------------------------------------
    localparam logic [11:0] CSR_QUEUE_COMMAND              = 12'h584;
    localparam logic [11:0] CSR_QUEUE_STATUS               = 12'h588;
    localparam logic [11:0] CSR_QUEUE_DONE_STATUS          = 12'h58C;
    localparam logic [11:0] CSR_QUEUE_ERROR_STATUS         = 12'h590;
    localparam logic [11:0] CSR_QUEUE_CONTROL              = 12'h594;
    localparam logic [11:0] CSR_QUEUE_REJECT_STATUS        = 12'h598;
    localparam logic [11:0] CSR_SQ_DEPTH                   = 12'h5A4;
    localparam logic [11:0] CSR_SQ_TAIL                    = 12'h5AC;
    localparam logic [11:0] CSR_CQ_DEPTH                   = 12'h5B8;
    localparam logic [11:0] CSR_CQ_HEAD                    = 12'h5BC;
    localparam logic [11:0] CSR_QUEUE_ERROR_DETAIL         = 12'h5D4;
    localparam logic [11:0] CSR_QUEUE_SQ_OCCUPANCY         = 12'h5E0;
    localparam logic [11:0] CSR_QUEUE_CQ_OCCUPANCY         = 12'h5E4;

    localparam logic [11:0] CSR_EVENT_COMMAND              = 12'h604;
    localparam logic [11:0] CSR_EVENT_STATUS               = 12'h608;
    localparam logic [11:0] CSR_EVENT_PENDING              = 12'h60C;
    localparam logic [11:0] CSR_EVENT_ENABLE               = 12'h610;
    localparam logic [11:0] CSR_EVENT_CONTROL              = 12'h614;
    localparam logic [11:0] CSR_EVENT_CQ_THRESHOLD         = 12'h628;
    localparam logic [11:0] CSR_EVENT_MOD_CONTROL          = 12'h630;
    localparam logic [11:0] CSR_EVENT_MOD_STATUS           = 12'h634;
    localparam logic [11:0] CSR_EVENT_MOD_TIMER_LIMIT      = 12'h638;
    localparam logic [11:0] CSR_EVENT_MOD_DEBUG            = 12'h63C;

    localparam logic [11:0] CSR_MEM_GUARD_COMMAND          = 12'h644;
    localparam logic [11:0] CSR_MEM_GUARD_STATUS           = 12'h648;
    localparam logic [11:0] CSR_MEM_GUARD_ERROR_STATUS     = 12'h64C;
    localparam logic [11:0] CSR_MEM_GUARD_CONTROL          = 12'h650;
    localparam logic [11:0] CSR_MEM_GUARD_REJECT_STATUS    = 12'h654;
    localparam logic [11:0] CSR_MEM_GUARD_ERROR_DETAIL     = 12'h658;
    localparam logic [11:0] CSR_MEM_GUARD_ERROR_DOMAIN     = 12'h664;

    localparam logic [11:0] CSR_TELEM_COMMAND              = 12'h6C4;
    localparam logic [11:0] CSR_TELEM_STATUS               = 12'h6C8;
    localparam logic [11:0] CSR_TELEM_CONTROL              = 12'h6CC;
    localparam logic [11:0] CSR_TELEM_QUEUE_START_COUNT    = 12'h6D0;
    localparam logic [11:0] CSR_TELEM_SQ_ACCEPT_COUNT      = 12'h6D4;
    localparam logic [11:0] CSR_TELEM_CMD_COMPLETE_COUNT   = 12'h6D8;
    localparam logic [11:0] CSR_TELEM_CQ_COMMIT_COUNT      = 12'h6DC;
    localparam logic [11:0] CSR_TELEM_QUEUE_DRAINED_COUNT  = 12'h6E0;
    localparam logic [11:0] CSR_TELEM_QUEUE_STOPPED_COUNT  = 12'h6E4;
    localparam logic [11:0] CSR_TELEM_QUEUE_ERROR_COUNT    = 12'h6E8;
    localparam logic [11:0] CSR_TELEM_CQ_CONSUMED_COUNT    = 12'h6F0;
    localparam logic [11:0] CSR_TELEM_EVENT_CAPTURE_COUNT  = 12'h6F8;
    localparam logic [11:0] CSR_TELEM_IRQ_ELIGIBLE_COUNT   = 12'h6FC;
    localparam logic [11:0] CSR_TELEM_THRESHOLD_REL_COUNT  = 12'h708;
    localparam logic [11:0] CSR_TELEM_TIMER_REL_COUNT      = 12'h70C;
    localparam logic [11:0] CSR_TELEM_CQ_FULL_STALL_COUNT  = 12'h714;
    localparam logic [11:0] CSR_TELEM_CQ_RECOVERED_COUNT   = 12'h718;
    localparam logic [11:0] CSR_TELEM_TIMEOUT_ERROR_COUNT  = 12'h71C;
    localparam logic [11:0] CSR_TELEM_GUARD_ERROR_COUNT    = 12'h720;
    localparam logic [11:0] CSR_TELEM_STOP_REQUEST_COUNT   = 12'h724;
    localparam logic [11:0] CSR_TELEM_BUSY_CYCLES         = 12'h72C;
    localparam logic [11:0] CSR_TELEM_STALLED_CYCLES      = 12'h734;

    // ------------------------------------------------------------
    // Optional CSR source
    // ------------------------------------------------------------
    csr_vif_t csr_vif;
    bit       csr_source_enable;

    // ------------------------------------------------------------
    // Static configuration supplied by the selected top
    // ------------------------------------------------------------
    int gemm_mac_lanes;
    bit gemm_enable_b_cache;
    bit gemm_enable_packed_bcache_preload;
    bit gemm_enable_a_row_cache;
    bit gemm_enable_packed_a_row_preload;
    bit gemm_enable_k_tiling;
    bit gemm_enable_n_tiling;
    bit gemm_enable_m_tiling;
    bit gemm_enable_c_rmw_accum;
    real dma_clk_period_ns;
    real core_clk_period_ns;
    bit  is_csr_top;

    // ------------------------------------------------------------
    // Sample variables
    // ------------------------------------------------------------
    int ctrl_event_sample;
    int test_kind_sample;
    int case_class_sample;
    int dim_m_sample;
    int dim_n_sample;
    int dim_k_sample;
    int latency_sample;
    int job_profile_class_sample;

    int lanes_sample;
    int cache_class_sample;
    int packed_class_sample;
    int tiling_class_sample;
    int c_rmw_sample;
    int clock_profile_sample;
    int top_class_sample;
    int top_lane_profile_sample;
    int lane_cache_profile_sample;
    int tiling_crmw_profile_sample;

    int queue_cmd_sample;
    int queue_state_sample;
    int queue_terminal_sample;
    int sq_occ_class_sample;
    int cq_occ_class_sample;

    int event_cause_sample;
    int moderation_policy_sample;
    int moderation_retrigger_sample;
    int moderation_release_profile_sample;
    int moderation_rearm_action_sample;

    int guard_domain_sample;
    int guard_error_sample;
    int guard_enable_sample;
    int guard_pair_sample;

    int telemetry_semantic_sample;

    // ------------------------------------------------------------
    // Per-sample validity gating
    // ------------------------------------------------------------
    bit queue_cmd_valid;
    bit queue_state_valid;
    bit queue_terminal_valid;
    bit sq_occ_valid;
    bit cq_occ_valid;

    bit event_cause_valid;
    bit moderation_policy_valid;
    bit moderation_retrigger_valid;
    bit moderation_release_valid;
    bit moderation_rearm_action_valid;

    bit guard_enable_valid;
    bit guard_domain_valid;
    bit guard_error_valid;
    bit guard_pair_valid;

    bit telemetry_clear_valid;
    bit telemetry_read_valid;
    bit telemetry_nonzero_valid;

    // ------------------------------------------------------------
    // CSR transaction reconstruction state
    // ------------------------------------------------------------
    bit          aw_pending;
    logic [11:0] awaddr_q;
    bit          w_pending;
    logic [31:0] wdata_q;
    logic [3:0]  wstrb_q;

    bit          ar_pending;
    logic [11:0] araddr_q;

    int unsigned sq_depth_q;
    int unsigned cq_depth_q;
    int unsigned last_cq_occupancy_q;

    // ------------------------------------------------------------
    // Control monitor source coverage
    //
    // test_kind is a job-profile classification.  Back-to-back and reset
    // recovery are orchestration scenarios, not stable transaction kinds on
    // this monitor path, so they are intentionally not planned bins here.
    // ------------------------------------------------------------
    covergroup cg_ctrl_event;
        option.per_instance = 1;

        cp_event: coverpoint ctrl_event_sample {
            ignore_bins none = {0};
            bins start = {1};
            bins done  = {2};
        }

        cp_test_kind: coverpoint test_kind_sample {
            bins fixed_baseline = {0};
            bins variable_dim   = {1};
            bins configurable   = {2};
            bins c_rmw_recipe   = {5};
        }

        cp_case_class: coverpoint case_class_sample {
            bins baseline       = {0};
            bins small_variable = {1};
            bins cache_scaled   = {2};
            bins k_tiling       = {3};
            bins n_tiling       = {4};
            bins m_tiling       = {5};
            bins c_rmw          = {6};
        }

        cross cp_event, cp_test_kind;
    endgroup

    // ------------------------------------------------------------
    // Planned GEMM profile coverage
    //
    // The validated scope does not include arbitrary M/N/K Cartesian
    // combinations.  Individual dimension classes and milestone profile
    // classes are covered instead of a 5x5x5 auto-cross.
    // ------------------------------------------------------------
    covergroup cg_job_profile;
        option.per_instance = 1;

        cp_m: coverpoint dim_m_sample {
            bins one        = {1};
            bins dim_2_to_4 = {[2:4]};
            bins dim_5_to_8 = {[5:8]};
        }

        cp_n: coverpoint dim_n_sample {
            bins one         = {1};
            bins dim_2_to_4  = {[2:4]};
            bins dim_5_to_8  = {[5:8]};
            bins dim_9_to_16 = {[9:16]};
        }

        cp_k: coverpoint dim_k_sample {
            bins one         = {1};
            bins dim_2_to_4  = {[2:4]};
            bins dim_5_to_8  = {[5:8]};
            bins dim_9_to_16 = {[9:16]};
        }

        cp_profile_class: coverpoint job_profile_class_sample {
            bins baseline       = {0};
            bins small_variable = {1};
            bins cache_scaled   = {2};
            bins k_tiling       = {3};
            bins n_tiling       = {4};
            bins m_tiling       = {5};
            bins c_rmw          = {6};
        }

        cp_latency: coverpoint latency_sample {
            bins short_job  = {[0:99]};
            bins medium_job = {[100:999]};
            bins long_job   = {[1000:9999]};
            bins very_long  = {[10000:$]};
        }
    endgroup

    // ------------------------------------------------------------
    // Static configuration coverage
    //
    // Combo coverpoints encode only the validated configuration matrix from
    // uvm_regression.list.  Unsupported or unplanned combinations do not
    // become artificial closure obligations.
    // ------------------------------------------------------------
    covergroup cg_static_cfg;
        option.per_instance = 1;

        cp_top: coverpoint top_class_sample {
            bins legacy_sideband = {0};
            bins csr_wrapper     = {1};
        }

        cp_lanes: coverpoint lanes_sample {
            bins lane1 = {1};
            bins lane2 = {2};
            bins lane4 = {4};
        }

        cp_cache: coverpoint cache_class_sample {
            bins none       = {0};
            bins b_only     = {1};
            bins b_and_arow = {2};
        }

        cp_packed: coverpoint packed_class_sample {
            bins none           = {0};
            bins packed_b       = {1};
            bins packed_b_and_a = {2};
        }

        cp_tiling: coverpoint tiling_class_sample {
            bins none  = {0};
            bins k     = {1};
            bins k_n   = {2};
            bins k_n_m = {3};
        }

        cp_c_rmw: coverpoint c_rmw_sample {
            bins disabled = {0};
            bins enabled  = {1};
        }

        cp_clock: coverpoint clock_profile_sample {
            bins nominal_10_14 = {0};
            bins cdc_10_13     = {1};
        }

        cp_top_lane_profile: coverpoint top_lane_profile_sample {
            bins legacy_lane1 = {0};
            bins legacy_lane2 = {1};
            bins legacy_lane4 = {2};
            bins csr_lane1    = {3};
        }

        cp_lane_cache_profile: coverpoint lane_cache_profile_sample {
            bins lane1_none  = {0};
            bins lane2_none  = {1};
            bins lane2_b     = {2};
            bins lane2_full  = {3};
            bins lane4_full  = {4};
        }

        cp_tiling_crmw_profile: coverpoint tiling_crmw_profile_sample {
            bins none_disabled  = {0};
            bins k_disabled     = {1};
            bins k_n_disabled   = {2};
            bins k_n_m_disabled = {3};
            bins none_enabled   = {4};
            bins k_n_m_enabled  = {5};
        }
    endgroup

    // ------------------------------------------------------------
    // CSR source coverage
    // ------------------------------------------------------------
    covergroup cg_queue_runtime;
        option.per_instance = 1;

        cp_command: coverpoint queue_cmd_sample iff (queue_cmd_valid) {
            bins start_queue    = {0};
            bins stop_queue     = {1};
            bins clear_done     = {2};
            bins clear_error    = {3};
            bins clear_counters = {4};
            bins sq_doorbell    = {6};
            bins cq_consume     = {7};
        }

        cp_state: coverpoint queue_state_sample iff (queue_state_valid) {
            bins idle    = {0};
            bins busy    = {1};
            bins stalled = {2};
            bins error   = {3};
        }

        cp_terminal: coverpoint queue_terminal_sample iff (queue_terminal_valid) {
            bins started   = {0};
            bins drained   = {1};
            bins completed = {2};
            bins stopped   = {3};
            bins error     = {4};
            bins reject    = {5};
        }

        cp_sq_occ: coverpoint sq_occ_class_sample iff (sq_occ_valid) {
            bins empty   = {0};
            bins partial = {1};
        }

        cp_cq_occ: coverpoint cq_occ_class_sample iff (cq_occ_valid) {
            bins empty   = {0};
            bins partial = {1};
            bins full    = {2};
        }
    endgroup

    covergroup cg_event_moderation;
        option.per_instance = 1;

        cp_event: coverpoint event_cause_sample iff (event_cause_valid) {
            bins command_completed = {0};
            bins drained           = {1};
            bins stopped           = {2};
            bins queue_error       = {3};
            bins cq_not_empty      = {4};
            bins threshold         = {5};
            bins cq_full_stall     = {6};
            bins cq_recovered      = {7};
            bins runtime_doorbell  = {8};
            bins runtime_consumed  = {9};
            bins test_event        = {10};
            bins moderation_timer  = {11};
        }

        cp_policy: coverpoint moderation_policy_sample iff (moderation_policy_valid) {
            bins immediate_compat = {0};
            bins threshold        = {1};
            bins threshold_timer  = {3};
        }

        cp_retrigger: coverpoint moderation_retrigger_sample iff (moderation_retrigger_valid) {
            bins disabled = {0};
            bins enabled  = {1};
        }

        cp_release_profile: coverpoint moderation_release_profile_sample
            iff (moderation_release_valid) {
            bins immediate_compat = {0};
            bins threshold        = {1};
            bins timer            = {2};
            bins urgent_bypass    = {3};
        }

        cp_rearm_action: coverpoint moderation_rearm_action_sample
            iff (moderation_rearm_action_valid) {
            bins ack_rearm = {1};
        }
    endgroup

    covergroup cg_memory_guard;
        option.per_instance = 1;

        cp_enable: coverpoint guard_enable_sample iff (guard_enable_valid) {
            bins disabled = {0};
            bins strict   = {2};
        }

        cp_domain: coverpoint guard_domain_sample iff (guard_domain_valid) {
            bins none = {0};
            bins sq   = {1};
            bins cq   = {2};
            bins desc = {3};
            bins src  = {4};
            bins dst  = {5};
        }

        cp_error: coverpoint guard_error_sample iff (guard_error_valid) {
            bins clean      = {0};
            bins sq_range   = {1};
            bins cq_range   = {2};
            bins desc_range = {3};
            bins src_range  = {4};
            bins dst_range  = {5};
        }

        cp_domain_error_pair: coverpoint guard_pair_sample iff (guard_pair_valid) {
            bins clean_none = {0};
            bins sq_range   = {1};
            bins cq_range   = {2};
            bins desc_range = {3};
            bins src_range  = {4};
            bins dst_range  = {5};
        }
    endgroup

    // ------------------------------------------------------------
    // Telemetry coverage
    //
    // A counter read proves visibility; a non-zero read proves activity.
    // CLEAR is a separate command semantic and is not crossed with non-zero.
    // ------------------------------------------------------------
    covergroup cg_telemetry;
        option.per_instance = 1;

        cp_clear: coverpoint telemetry_semantic_sample iff (telemetry_clear_valid) {
            bins clear = {0};
        }

        cp_counter_read: coverpoint telemetry_semantic_sample iff (telemetry_read_valid) {
            bins queue_start       = {1};
            bins sq_accept         = {2};
            bins command_complete  = {3};
            bins cq_commit         = {4};
            bins drained           = {5};
            bins stopped           = {6};
            bins queue_error       = {7};
            bins cq_consumed       = {8};
            bins event_capture     = {9};
            bins irq_eligible      = {10};
            bins threshold_release = {11};
            bins timer_release     = {12};
            bins cq_full_stall     = {13};
            bins cq_recovered      = {14};
            bins timeout_error     = {15};
            bins guard_error       = {16};
            bins stop_request      = {17};
            bins busy_cycles       = {18};
            bins stalled_cycles    = {19};
        }

        cp_counter_nonzero: coverpoint telemetry_semantic_sample
            iff (telemetry_nonzero_valid) {
            bins queue_start       = {1};
            bins sq_accept         = {2};
            bins command_complete  = {3};
            bins cq_commit         = {4};
            bins drained           = {5};
            bins stopped           = {6};
            bins queue_error       = {7};
            bins cq_consumed       = {8};
            bins event_capture     = {9};
            bins irq_eligible      = {10};
            bins threshold_release = {11};
            bins timer_release     = {12};
            bins cq_full_stall     = {13};
            bins cq_recovered      = {14};
            bins timeout_error     = {15};
            bins guard_error       = {16};
            bins stop_request      = {17};
            bins busy_cycles       = {18};
            bins stalled_cycles    = {19};
        }
    endgroup

    function new(string name = "ai_accel_subsys_functional_coverage",
                 uvm_component parent = null);
        super.new(name, parent);
        cg_ctrl_event       = new();
        cg_job_profile      = new();
        cg_static_cfg       = new();
        cg_queue_runtime    = new();
        cg_event_moderation = new();
        cg_memory_guard     = new();
        cg_telemetry        = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        csr_source_enable = uvm_config_db#(csr_vif_t)::get(
            this, "", "csr_vif", csr_vif);

        gemm_mac_lanes = 1;
        dma_clk_period_ns = 10.0;
        core_clk_period_ns = 14.0;

        moderation_policy_sample  = 0;
        moderation_retrigger_sample = 0;
        guard_enable_sample       = 0;
        last_cq_occupancy_q       = 0;
        clear_queue_sample_valid();
        clear_event_sample_valid();
        clear_guard_sample_valid();
        clear_telemetry_sample_valid();

        void'(uvm_config_db#(int)::get(this, "", "cov_gemm_mac_lanes", gemm_mac_lanes));
        void'(uvm_config_db#(bit)::get(this, "", "cov_enable_b_cache", gemm_enable_b_cache));
        void'(uvm_config_db#(bit)::get(this, "", "cov_enable_packed_bcache", gemm_enable_packed_bcache_preload));
        void'(uvm_config_db#(bit)::get(this, "", "cov_enable_a_row_cache", gemm_enable_a_row_cache));
        void'(uvm_config_db#(bit)::get(this, "", "cov_enable_packed_a_row", gemm_enable_packed_a_row_preload));
        void'(uvm_config_db#(bit)::get(this, "", "cov_enable_k_tiling", gemm_enable_k_tiling));
        void'(uvm_config_db#(bit)::get(this, "", "cov_enable_n_tiling", gemm_enable_n_tiling));
        void'(uvm_config_db#(bit)::get(this, "", "cov_enable_m_tiling", gemm_enable_m_tiling));
        void'(uvm_config_db#(bit)::get(this, "", "cov_enable_c_rmw", gemm_enable_c_rmw_accum));
        void'(uvm_config_db#(real)::get(this, "", "cov_dma_clk_period_ns", dma_clk_period_ns));
        void'(uvm_config_db#(real)::get(this, "", "cov_core_clk_period_ns", core_clk_period_ns));
        void'(uvm_config_db#(bit)::get(this, "", "cov_is_csr_top", is_csr_top));
    endfunction

    function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);

        top_class_sample = is_csr_top ? 1 : 0;
        lanes_sample = gemm_mac_lanes;

        if (!gemm_enable_b_cache)
            cache_class_sample = 0;
        else if (!gemm_enable_a_row_cache)
            cache_class_sample = 1;
        else
            cache_class_sample = 2;

        if (!gemm_enable_packed_bcache_preload)
            packed_class_sample = 0;
        else if (!gemm_enable_packed_a_row_preload)
            packed_class_sample = 1;
        else
            packed_class_sample = 2;

        if (!gemm_enable_k_tiling && !gemm_enable_n_tiling && !gemm_enable_m_tiling)
            tiling_class_sample = 0;
        else if (gemm_enable_k_tiling && !gemm_enable_n_tiling && !gemm_enable_m_tiling)
            tiling_class_sample = 1;
        else if (gemm_enable_k_tiling && gemm_enable_n_tiling && !gemm_enable_m_tiling)
            tiling_class_sample = 2;
        else if (gemm_enable_k_tiling && gemm_enable_n_tiling && gemm_enable_m_tiling)
            tiling_class_sample = 3;
        else
            tiling_class_sample = 99;

        c_rmw_sample = gemm_enable_c_rmw_accum;

        if ((dma_clk_period_ns > 9.99) && (dma_clk_period_ns < 10.01) &&
            (core_clk_period_ns > 13.99) && (core_clk_period_ns < 14.01))
            clock_profile_sample = 0;
        else if ((dma_clk_period_ns > 9.99) && (dma_clk_period_ns < 10.01) &&
                 (core_clk_period_ns > 12.99) && (core_clk_period_ns < 13.01))
            clock_profile_sample = 1;
        else
            clock_profile_sample = 99;

        top_lane_profile_sample    = classify_top_lane_profile();
        lane_cache_profile_sample  = classify_lane_cache_profile();
        tiling_crmw_profile_sample = classify_tiling_crmw_profile();

        cg_static_cfg.sample();

        `uvm_info("RC_COV/CFG",
            $sformatf("RC-COV-C2 planned-bin model enabled: control=1 csr=%0d top=%s lanes=%0d cache=%0d packed=%0d tiling=%0d c_rmw=%0d clk=%0.3f/%0.3f ns",
                csr_source_enable,
                is_csr_top ? "CSR" : "LEGACY",
                lanes_sample,
                cache_class_sample,
                packed_class_sample,
                tiling_class_sample,
                c_rmw_sample,
                dma_clk_period_ns,
                core_clk_period_ns),
            UVM_LOW)
    endfunction

    // ------------------------------------------------------------
    // Source 1: control monitor analysis transaction
    // ------------------------------------------------------------
    virtual function void write(ai_accel_subsys_seq_item t);
        ctrl_event_sample = int'(t.ctrl_event_kind);
        test_kind_sample  = int'(t.test_kind);
        case_class_sample = classify_case(t.case_id, t.test_kind);
        cg_ctrl_event.sample();

        if (t.ctrl_event_kind == ai_accel_subsys_seq_item::CTRL_EVENT_DONE) begin
            dim_m_sample            = int'(t.dim_m);
            dim_n_sample            = int'(t.dim_n);
            dim_k_sample            = int'(t.dim_k);
            latency_sample          = int'(t.latency_cycles);
            job_profile_class_sample = classify_case(t.case_id, t.test_kind);
            cg_job_profile.sample();
        end
    endfunction

    function int classify_case(
        int unsigned                            case_id,
        ai_accel_subsys_seq_item::test_kind_e  test_kind
    );
        if (test_kind == ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE)
            return 0;
        if (test_kind == ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE)
            return 0;
        if (test_kind == ai_accel_subsys_seq_item::TEST_KIND_C_RMW_ACCUM_RECIPE)
            return 6;

        if ((case_id >= 100) && (case_id <= 105))
            return 1;
        if ((case_id >= 190) && (case_id <= 192))
            return 2;
        if ((case_id >= 193) && (case_id <= 197))
            return 3;
        if ((case_id >= 198) && (case_id <= 202))
            return 4;
        if ((case_id >= 203) && (case_id <= 207))
            return 5;
        if ((case_id >= 208) && (case_id <= 212))
            return 6;

        return 99;
    endfunction

    function int classify_top_lane_profile();
        if (!is_csr_top && (gemm_mac_lanes == 1))
            return 0;
        if (!is_csr_top && (gemm_mac_lanes == 2))
            return 1;
        if (!is_csr_top && (gemm_mac_lanes == 4))
            return 2;
        if (is_csr_top && (gemm_mac_lanes == 1))
            return 3;
        return 99;
    endfunction

    function int classify_lane_cache_profile();
        if ((gemm_mac_lanes == 1) && (cache_class_sample == 0))
            return 0;
        if ((gemm_mac_lanes == 2) && (cache_class_sample == 0))
            return 1;
        if ((gemm_mac_lanes == 2) && (cache_class_sample == 1))
            return 2;
        if ((gemm_mac_lanes == 2) && (cache_class_sample == 2))
            return 3;
        if ((gemm_mac_lanes == 4) && (cache_class_sample == 2))
            return 4;
        return 99;
    endfunction

    function int classify_tiling_crmw_profile();
        if ((tiling_class_sample == 0) && !gemm_enable_c_rmw_accum)
            return 0;
        if ((tiling_class_sample == 1) && !gemm_enable_c_rmw_accum)
            return 1;
        if ((tiling_class_sample == 2) && !gemm_enable_c_rmw_accum)
            return 2;
        if ((tiling_class_sample == 3) && !gemm_enable_c_rmw_accum)
            return 3;
        if ((tiling_class_sample == 0) && gemm_enable_c_rmw_accum)
            return 4;
        if ((tiling_class_sample == 3) && gemm_enable_c_rmw_accum)
            return 5;
        return 99;
    endfunction

    function void clear_queue_sample_valid();
        queue_cmd_valid      = 1'b0;
        queue_state_valid    = 1'b0;
        queue_terminal_valid = 1'b0;
        sq_occ_valid         = 1'b0;
        cq_occ_valid         = 1'b0;
    endfunction

    function void clear_event_sample_valid();
        event_cause_valid          = 1'b0;
        moderation_policy_valid    = 1'b0;
        moderation_retrigger_valid = 1'b0;
        moderation_release_valid   = 1'b0;
        moderation_rearm_action_valid = 1'b0;
    endfunction

    function void clear_guard_sample_valid();
        guard_enable_valid = 1'b0;
        guard_domain_valid = 1'b0;
        guard_error_valid  = 1'b0;
        guard_pair_valid   = 1'b0;
    endfunction

    function void clear_telemetry_sample_valid();
        telemetry_clear_valid   = 1'b0;
        telemetry_read_valid    = 1'b0;
        telemetry_nonzero_valid = 1'b0;
    endfunction

    function int classify_occupancy(logic [31:0] occ, int unsigned depth);
        if (depth == 0)
            return (occ == 0) ? 0 : 3;
        if (occ == 0)
            return 0;
        if (occ < depth)
            return 1;
        if (occ == depth)
            return 2;
        return 3;
    endfunction

    function bit write_byte_active(logic [3:0] strb, int byte_index);
        return strb[byte_index];
    endfunction

    function bit write_bit_active(logic [3:0] strb, int bit_index);
        return strb[bit_index / 8];
    endfunction

    // ------------------------------------------------------------
    // Source 2: passive AXI-Lite CSR observation
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        if (!csr_source_enable)
            return;

        forever begin
            @(posedge csr_vif.clk);

            if (!csr_vif.rst_n) begin
                aw_pending          = 1'b0;
                w_pending           = 1'b0;
                ar_pending          = 1'b0;
                sq_depth_q          = 0;
                cq_depth_q          = 0;
                last_cq_occupancy_q = 0;
                moderation_policy_sample  = 0;
                moderation_retrigger_sample = 0;
            end
            else begin
                if (csr_vif.awvalid && csr_vif.awready) begin
                    awaddr_q   = csr_vif.awaddr;
                    aw_pending = 1'b1;
                end

                if (csr_vif.wvalid && csr_vif.wready) begin
                    wdata_q   = csr_vif.wdata;
                    wstrb_q   = csr_vif.wstrb;
                    w_pending = 1'b1;
                end

                if (aw_pending && w_pending) begin
                    observe_csr_write(awaddr_q, wdata_q, wstrb_q);
                    aw_pending = 1'b0;
                    w_pending  = 1'b0;
                end

                if (csr_vif.arvalid && csr_vif.arready) begin
                    araddr_q   = csr_vif.araddr;
                    ar_pending = 1'b1;
                end

                if (csr_vif.rvalid && csr_vif.rready && ar_pending) begin
                    observe_csr_read(araddr_q, csr_vif.rdata, csr_vif.rresp);
                    ar_pending = 1'b0;
                end
            end
        end
    endtask

    function void observe_csr_write(
        logic [11:0] addr,
        logic [31:0] data,
        logic [3:0]  strb
    );
        if (strb == 4'b0000)
            return;

        case (addr)
            CSR_QUEUE_COMMAND: begin
                if (write_bit_active(strb, 0)  && data[0])  sample_queue_command(0);
                if (write_bit_active(strb, 1)  && data[1])  sample_queue_command(1);
                if (write_bit_active(strb, 8)  && data[8])  sample_queue_command(2);
                if (write_bit_active(strb, 9)  && data[9])  sample_queue_command(3);
                if (write_bit_active(strb, 10) && data[10]) sample_queue_command(4);
                if (write_bit_active(strb, 11) && data[11]) sample_queue_command(5);
            end

            CSR_SQ_DEPTH: begin
                sq_depth_q = data;
            end

            CSR_CQ_DEPTH: begin
                cq_depth_q = data;
            end

            CSR_SQ_TAIL: begin
                sample_queue_command(6);
            end

            CSR_CQ_HEAD: begin
                sample_queue_command(7);
            end

            CSR_EVENT_COMMAND: begin
                if (write_bit_active(strb, 1) && data[1])
                    sample_event_cause(10);
            end

            CSR_EVENT_PENDING: begin
                sample_event_mask(data, strb, 1'b1);

                if (moderation_retrigger_sample && (|data[11:0]))
                    sample_moderation_rearm_action();
            end

            CSR_EVENT_MOD_CONTROL: begin
                sample_moderation_control(data);
            end

            CSR_MEM_GUARD_CONTROL: begin
                sample_guard_enable(data);
            end

            CSR_TELEM_COMMAND: begin
                if (write_bit_active(strb, 8) && data[8]) begin
                    clear_telemetry_sample_valid();
                    telemetry_semantic_sample = 0;
                    telemetry_clear_valid     = 1'b1;
                    cg_telemetry.sample();
                end
            end

            default: begin
            end
        endcase
    endfunction

    function void observe_csr_read(
        logic [11:0] addr,
        logic [31:0] data,
        logic [1:0]  resp
    );
        int i;

        if (resp != 2'b00)
            return;

        case (addr)
            CSR_QUEUE_STATUS: begin
                clear_queue_sample_valid();
                queue_state_valid = 1'b1;
                if (data[2])
                    queue_state_sample = 3;
                else if (data[7])
                    queue_state_sample = 2;
                else if (data[0])
                    queue_state_sample = 1;
                else
                    queue_state_sample = 0;
                cg_queue_runtime.sample();
            end

            CSR_QUEUE_DONE_STATUS: begin
                for (i = 0; i < 4; i++) begin
                    if (data[i]) begin
                        clear_queue_sample_valid();
                        queue_terminal_sample = i;
                        queue_terminal_valid  = 1'b1;
                        cg_queue_runtime.sample();
                    end
                end
            end

            CSR_QUEUE_ERROR_STATUS: begin
                if (data != 0) begin
                    clear_queue_sample_valid();
                    queue_terminal_sample = 4;
                    queue_terminal_valid  = 1'b1;
                    cg_queue_runtime.sample();
                end
            end

            CSR_QUEUE_REJECT_STATUS: begin
                if (data != 0) begin
                    clear_queue_sample_valid();
                    queue_terminal_sample = 5;
                    queue_terminal_valid  = 1'b1;
                    cg_queue_runtime.sample();
                end
            end

            CSR_QUEUE_SQ_OCCUPANCY: begin
                clear_queue_sample_valid();
                sq_occ_class_sample = classify_occupancy(data, sq_depth_q);
                sq_occ_valid = 1'b1;
                cg_queue_runtime.sample();
            end

            CSR_QUEUE_CQ_OCCUPANCY: begin
                last_cq_occupancy_q = data;
                clear_queue_sample_valid();
                cq_occ_class_sample = classify_occupancy(data, cq_depth_q);
                cq_occ_valid = 1'b1;
                cg_queue_runtime.sample();
            end

            CSR_EVENT_PENDING: begin
                sample_event_mask(data, 4'hF, 1'b0);
            end

            CSR_EVENT_MOD_CONTROL: begin
                sample_moderation_control(data);
            end

            CSR_EVENT_MOD_DEBUG: begin
                sample_moderation_debug(data[7:0]);
            end

            CSR_MEM_GUARD_STATUS: begin
                sample_guard_enable(data);
            end

            CSR_MEM_GUARD_ERROR_STATUS: begin
                if (data == 0)
                    sample_guard_result(0, 0);
                else
                    sample_guard_error_status(data);
            end

            CSR_MEM_GUARD_ERROR_DETAIL: begin
                sample_guard_result(
                    int'(data[15:8]),
                    classify_guard_detail(data[7:0])
                );
            end

            CSR_MEM_GUARD_ERROR_DOMAIN: begin
                clear_guard_sample_valid();
                guard_domain_sample = int'(data[7:0]);
                guard_domain_valid  = 1'b1;
                cg_memory_guard.sample();
            end

            default: begin
                sample_telemetry_read(addr, data);
            end
        endcase
    endfunction

    function int decode_moderation_policy(logic [31:0] data);
        if (!data[0])
            return 0;

        case ({data[2], data[1]})
            2'b01: return 1;
            2'b10: return 2;
            2'b11: return 3;
            default: return 99;
        endcase
    endfunction

    function void sample_moderation_control(logic [31:0] data);
        moderation_policy_sample    = decode_moderation_policy(data);
        moderation_retrigger_sample = data[3];

        clear_event_sample_valid();
        moderation_policy_valid    = 1'b1;
        moderation_retrigger_valid = 1'b1;
        cg_event_moderation.sample();
    endfunction

    function void sample_moderation_debug(logic [7:0] cause);
        case (cause)
            8'h01: sample_moderation_release_profile(1);
            8'h02: sample_moderation_release_profile(2);
            8'h03: sample_moderation_release_profile(0);
            8'h04: sample_moderation_release_profile(3);
            8'h05: sample_moderation_rearm_action();
            default: begin
            end
        endcase
    endfunction

    function void sample_event_mask(
        logic [31:0] data,
        logic [3:0]  strb,
        bit          is_write
    );
        int i;
        for (i = 0; i < 12; i++) begin
            if (data[i] && (!is_write || write_bit_active(strb, i)))
                sample_event_cause(i);
        end
    endfunction

    function void sample_event_cause(int cause);
        clear_event_sample_valid();
        event_cause_sample = cause;
        event_cause_valid  = 1'b1;
        cg_event_moderation.sample();

        // QUEUE_STALLED is architecturally proven by the CQ-full-stall event
        // even when a status snapshot is taken after the transient bit drops.
        if (cause == 6)
            sample_queue_state(2);

        case (cause)
            0, 4: begin
                if (moderation_policy_sample == 0)
                    sample_moderation_release_profile(0);
            end

            5:  sample_moderation_release_profile(1);
            11: sample_moderation_release_profile(2);

            1, 2, 3, 6, 7, 8, 9, 10: begin
                if (moderation_policy_sample != 0)
                    sample_moderation_release_profile(3);
            end

            default: begin
            end
        endcase
    endfunction

    function void sample_moderation_release_profile(int release_class);
        clear_event_sample_valid();
        moderation_release_profile_sample = release_class;
        moderation_release_valid          = 1'b1;
        cg_event_moderation.sample();
    endfunction

    function void sample_moderation_rearm_action();
        clear_event_sample_valid();
        moderation_rearm_action_sample = 1;
        moderation_rearm_action_valid  = 1'b1;
        cg_event_moderation.sample();
    endfunction

    function void sample_queue_command(int command_class);
        clear_queue_sample_valid();
        queue_cmd_sample = command_class;
        queue_cmd_valid  = 1'b1;
        cg_queue_runtime.sample();
    endfunction

    function void sample_queue_state(int state_class);
        clear_queue_sample_valid();
        queue_state_sample = state_class;
        queue_state_valid  = 1'b1;
        cg_queue_runtime.sample();
    endfunction

    function void sample_guard_enable(logic [31:0] data);
        clear_guard_sample_valid();
        if (!data[0])
            guard_enable_sample = 0;
        else if (data[1])
            guard_enable_sample = 2;
        else
            guard_enable_sample = 1;
        guard_enable_valid = 1'b1;
        cg_memory_guard.sample();
    endfunction

    function void sample_guard_error_status(logic [31:0] data);
        int i;

        // Current planned P27 regression proves the five domain-specific
        // range failures.  Other status bits remain visible diagnostics but
        // are not part of this milestone's planned functional-coverage bins.
        for (i = 1; i <= 5; i++) begin
            if (data[i])
                sample_guard_result(i, i);
        end
    endfunction

    function int classify_guard_detail(logic [7:0] detail);
        case (detail)
            8'h00: return 0;
            8'h20: return 1;
            8'h21: return 2;
            8'h22: return 3;
            8'h23: return 4;
            8'h24: return 5;
            default: return 99;
        endcase
    endfunction

    function void sample_guard_result(int domain_class, int error_class);
        clear_guard_sample_valid();

        guard_domain_sample = domain_class;
        guard_error_sample  = error_class;
        guard_domain_valid  = 1'b1;
        guard_error_valid   = 1'b1;

        if ((domain_class == 0) && (error_class == 0)) begin
            guard_pair_sample = 0;
            guard_pair_valid  = 1'b1;
        end
        else if ((domain_class >= 1) && (domain_class <= 5) &&
                 (error_class == domain_class)) begin
            guard_pair_sample = domain_class;
            guard_pair_valid  = 1'b1;
        end

        cg_memory_guard.sample();
    endfunction

    function void sample_telemetry_read(logic [11:0] addr, logic [31:0] data);
        case (addr)
            CSR_TELEM_QUEUE_START_COUNT:   telemetry_semantic_sample = 1;
            CSR_TELEM_SQ_ACCEPT_COUNT:     telemetry_semantic_sample = 2;
            CSR_TELEM_CMD_COMPLETE_COUNT:  telemetry_semantic_sample = 3;
            CSR_TELEM_CQ_COMMIT_COUNT:     telemetry_semantic_sample = 4;
            CSR_TELEM_QUEUE_DRAINED_COUNT: telemetry_semantic_sample = 5;
            CSR_TELEM_QUEUE_STOPPED_COUNT: telemetry_semantic_sample = 6;
            CSR_TELEM_QUEUE_ERROR_COUNT:   telemetry_semantic_sample = 7;
            CSR_TELEM_CQ_CONSUMED_COUNT:   telemetry_semantic_sample = 8;
            CSR_TELEM_EVENT_CAPTURE_COUNT: telemetry_semantic_sample = 9;
            CSR_TELEM_IRQ_ELIGIBLE_COUNT:  telemetry_semantic_sample = 10;
            CSR_TELEM_THRESHOLD_REL_COUNT: telemetry_semantic_sample = 11;
            CSR_TELEM_TIMER_REL_COUNT:     telemetry_semantic_sample = 12;
            CSR_TELEM_CQ_FULL_STALL_COUNT: telemetry_semantic_sample = 13;
            CSR_TELEM_CQ_RECOVERED_COUNT:  telemetry_semantic_sample = 14;
            CSR_TELEM_TIMEOUT_ERROR_COUNT: telemetry_semantic_sample = 15;
            CSR_TELEM_GUARD_ERROR_COUNT:   telemetry_semantic_sample = 16;
            CSR_TELEM_STOP_REQUEST_COUNT:  telemetry_semantic_sample = 17;
            CSR_TELEM_BUSY_CYCLES:         telemetry_semantic_sample = 18;
            CSR_TELEM_STALLED_CYCLES:      telemetry_semantic_sample = 19;
            default: return;
        endcase

        clear_telemetry_sample_valid();
        telemetry_read_valid    = 1'b1;
        telemetry_nonzero_valid = (data != 0);
        cg_telemetry.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("RC_COV/SUMMARY",
            $sformatf("Planned-bin instance coverage: static=%0.2f ctrl=%0.2f job=%0.2f queue=%0.2f event=%0.2f guard=%0.2f telemetry=%0.2f csr_source=%0d",
                cg_static_cfg.get_inst_coverage(),
                cg_ctrl_event.get_inst_coverage(),
                cg_job_profile.get_inst_coverage(),
                cg_queue_runtime.get_inst_coverage(),
                cg_event_moderation.get_inst_coverage(),
                cg_memory_guard.get_inst_coverage(),
                cg_telemetry.get_inst_coverage(),
                csr_source_enable),
            UVM_LOW)
    endfunction

endclass

`endif
