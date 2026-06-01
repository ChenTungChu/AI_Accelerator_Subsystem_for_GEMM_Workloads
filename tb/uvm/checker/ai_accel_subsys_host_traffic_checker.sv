// File: tb/uvm/checker/ai_accel_subsys_host_traffic_checker.sv
// C_RMW_ACCUM_SANITY: binds C RMW accumulation monitor ctrl fallback names to open partial-job host traffic identities.
`ifndef AI_ACCEL_SUBSYS_HOST_TRAFFIC_CHECKER_SV
`define AI_ACCEL_SUBSYS_HOST_TRAFFIC_CHECKER_SV

`uvm_analysis_imp_decl(_hostchk_ctrl)
`uvm_analysis_imp_decl(_hostchk_host)

// ------------------------------------------------------------
// Per-job host phase state
// ------------------------------------------------------------
typedef enum int unsigned {
    HOST_JOB_PHASE_PRESTART = 0,
    HOST_JOB_PHASE_COMPUTE  = 1,
    HOST_JOB_PHASE_POSTDONE = 2,
    HOST_JOB_PHASE_CLOSED   = 3
} host_job_phase_e;

// ------------------------------------------------------------
// Per-job host traffic state
// ------------------------------------------------------------
class ai_accel_subsys_host_traffic_job extends uvm_object;
    `uvm_object_utils(ai_accel_subsys_host_traffic_job)

    // Job identity
    int unsigned case_id;
    ai_accel_subsys_seq_item::test_kind_e test_kind;
    string test_name;

    // Expected profile
    logic [31:0] base_addr_a;
    logic [31:0] base_addr_b;
    logic [31:0] base_addr_c;

    int unsigned dim_m;
    int unsigned dim_n;
    int unsigned dim_k;

    int unsigned exp_a_write_count;
    int unsigned exp_b_write_count;
    int unsigned exp_c_clear_count;
    int unsigned exp_c_read_count;

    // Observed counts
    int unsigned obs_a_write_count;
    int unsigned obs_b_write_count;
    int unsigned obs_c_clear_count;
    int unsigned obs_c_read_count;
    int unsigned obs_other_count;

    // Control-side observation
    bit ctrl_start_seen;
    bit ctrl_done_seen;
    bit ctrl_profile_checked;

    // Host-side completion
    bit host_readback_complete;

    // C RMW accumulation recipe classification
    //
    // C RMW accumulation uses a mixed recipe/job host flow:
    //   - recipe-level identity owns C clear and final C readback
    //   - partial-job identity owns A/B preload and START/DONE
    // This metadata lets the checker keep strict checking enabled
    // without forcing recipe-level C traffic into a normal one-job
    // A/B/C-clear/compute/readback lifecycle.
    bit          c_rmw_accum_recipe_level;
    bit          c_rmw_accum_partial_job;
    int unsigned c_rmw_accum_job_idx;

    // Phase
    host_job_phase_e phase;

    // Final state
    bit closed;
    bit failed;

    function new(string name = "ai_accel_subsys_host_traffic_job");
        super.new(name);

        case_id              = 0;
        test_kind            = ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE;
        test_name            = "";

        base_addr_a          = '0;
        base_addr_b          = '0;
        base_addr_c          = '0;

        dim_m                = 0;
        dim_n                = 0;
        dim_k                = 0;

        exp_a_write_count    = 0;
        exp_b_write_count    = 0;
        exp_c_clear_count    = 0;
        exp_c_read_count     = 0;

        obs_a_write_count    = 0;
        obs_b_write_count    = 0;
        obs_c_clear_count    = 0;
        obs_c_read_count     = 0;
        obs_other_count      = 0;

        ctrl_start_seen      = 1'b0;
        ctrl_done_seen       = 1'b0;
        ctrl_profile_checked = 1'b0;

        host_readback_complete = 1'b0;

        c_rmw_accum_recipe_level     = 1'b0;
        c_rmw_accum_partial_job      = 1'b0;
        c_rmw_accum_job_idx          = 0;

        phase                = HOST_JOB_PHASE_PRESTART;

        closed               = 1'b0;
        failed               = 1'b0;
    endfunction

    function void mark_failed();
        failed = 1'b1;
    endfunction

    function bit all_expected_counts_match();
        return (obs_a_write_count == exp_a_write_count) &&
               (obs_b_write_count == exp_b_write_count) &&
               (obs_c_clear_count == exp_c_clear_count) &&
               (obs_c_read_count  == exp_c_read_count)  &&
               (obs_other_count   == 0);
    endfunction

endclass

// ------------------------------------------------------------
// Host traffic checker
//
// v2 scope:
//   - strict checking in host-agent primary mode
//   - checks region / count / access width
//   - uses the same ctrl path, now phase-aware
//   - enforces simple phase rules:
//       * PRESTART: allow A/B writes + C clear only
//       * COMPUTE : no host traffic allowed
//       * POSTDONE: allow C read only
//   - supports expected aborted job semantics for mid-run reset:
//       * one or more jobs may legally end after START but before DONE
//       * aborted jobs do not require readback/result completion
// ------------------------------------------------------------
class ai_accel_subsys_host_traffic_checker extends uvm_component;
    `uvm_component_utils(ai_accel_subsys_host_traffic_checker)

    // ------------------------------------------------------------
    // Analysis ports
    // ------------------------------------------------------------
    uvm_analysis_imp_hostchk_ctrl #(ai_accel_subsys_seq_item,
                                    ai_accel_subsys_host_traffic_checker) ctrl_imp;

    uvm_analysis_imp_hostchk_host #(axi_mm_host_seq_item,
                                    ai_accel_subsys_host_traffic_checker) host_imp;

    // ------------------------------------------------------------
    // Config
    // ------------------------------------------------------------
    bit enable_check;
    bit strict_check_enable;
    bit log_enable;

    bit          midrun_reset_test_mode;
    int unsigned expected_aborted_job_count;

    // ------------------------------------------------------------
    // Internal state
    // ------------------------------------------------------------
    ai_accel_subsys_host_traffic_job active_jobs[$];

    int unsigned total_ctrl_events;
    int unsigned total_host_events;
    int unsigned total_jobs_created;
    int unsigned total_jobs_passed;
    int unsigned total_jobs_failed;
    int unsigned total_jobs_aborted_expected;
    int unsigned total_host_events_skipped;

    int unsigned total_start_events;
    int unsigned total_done_events;

    // ------------------------------------------------------------
    // Local access classification
    // ------------------------------------------------------------
    typedef enum int unsigned {
        HOST_ACCESS_A_WRITE = 0,
        HOST_ACCESS_B_WRITE = 1,
        HOST_ACCESS_C_CLEAR = 2,
        HOST_ACCESS_C_READ  = 3,
        HOST_ACCESS_OTHER   = 4
    } host_access_kind_e;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_host_traffic_checker",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        ctrl_imp = new("ctrl_imp", this);
        host_imp = new("host_imp", this);

        if (!uvm_config_db#(bit)::get(this, "", "enable_check", enable_check)) begin
            enable_check = 1'b1;
        end

        if (!uvm_config_db#(bit)::get(this, "", "strict_check_enable", strict_check_enable)) begin
            strict_check_enable = 1'b0;
        end

        if (!uvm_config_db#(bit)::get(this, "", "log_enable", log_enable)) begin
            log_enable = 1'b1;
        end

        if (!uvm_config_db#(bit)::get(this, "", "midrun_reset_test_mode", midrun_reset_test_mode)) begin
            midrun_reset_test_mode = 1'b0;
        end

        if (!uvm_config_db#(int unsigned)::get(this, "", "expected_aborted_job_count", expected_aborted_job_count)) begin
            expected_aborted_job_count = 0;
        end
    endfunction

    // ------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------
    function string phase_name(host_job_phase_e phase);
        case (phase)
            HOST_JOB_PHASE_PRESTART: return "PRESTART";
            HOST_JOB_PHASE_COMPUTE:  return "COMPUTE";
            HOST_JOB_PHASE_POSTDONE: return "POSTDONE";
            HOST_JOB_PHASE_CLOSED:   return "CLOSED";
            default:                 return "UNKNOWN";
        endcase
    endfunction

    function string ctrl_event_name(ai_accel_subsys_seq_item t);
        case (t.ctrl_event_kind)
            ai_accel_subsys_seq_item::CTRL_EVENT_NONE:  return "NONE";
            ai_accel_subsys_seq_item::CTRL_EVENT_START: return "START";
            ai_accel_subsys_seq_item::CTRL_EVENT_DONE:  return "DONE";
            default:                                    return "UNKNOWN";
        endcase
    endfunction

    function bit is_ctrl_start_event(ai_accel_subsys_seq_item t);
        if (t == null)
            return 1'b0;

        if (t.ctrl_event_kind == ai_accel_subsys_seq_item::CTRL_EVENT_START)
            return 1'b1;

        if (t.ctrl_event_kind == ai_accel_subsys_seq_item::CTRL_EVENT_DONE)
            return 1'b0;

        // Legacy fallback
        return !t.done_seen;
    endfunction

    function bit is_ctrl_done_event(ai_accel_subsys_seq_item t);
        if (t == null)
            return 1'b0;

        if (t.ctrl_event_kind == ai_accel_subsys_seq_item::CTRL_EVENT_DONE)
            return 1'b1;

        if (t.ctrl_event_kind == ai_accel_subsys_seq_item::CTRL_EVENT_START)
            return 1'b0;

        // Legacy fallback
        return t.done_seen;
    endfunction

    function bit is_metadata_missing(axi_mm_host_seq_item t);
        return ((t.case_id == 0) && (t.test_name == ""));
    endfunction

    function bit is_read_event(axi_mm_host_seq_item t);
        return (t.read_data_s32.size() != 0);
    endfunction

    function bit addr_in_byte_region(
        input logic [31:0] addr,
        input logic [31:0] base,
        input int unsigned count
    );
        return ((addr >= base) && (addr < (base + count)));
    endfunction

    function bit addr_in_word_region(
        input logic [31:0] addr,
        input logic [31:0] base,
        input int unsigned count
    );
        logic [31:0] offset;
    begin
        if ((addr < base) || (addr >= (base + count * 4))) begin
            return 1'b0;
        end

        offset = addr - base;
        return ((offset % 4) == 0);
    end
    endfunction

    function bit is_c_rmw_accum_kind(
        input ai_accel_subsys_seq_item::test_kind_e test_kind
    );
        return (test_kind == ai_accel_subsys_seq_item::TEST_KIND_C_RMW_ACCUM_RECIPE);
    endfunction

    function bit is_c_rmw_accum_recipe_level_identity(
        input int unsigned case_id,
        input string       test_name
    );
        return (test_name == $sformatf("c_rmw_accum_recipe_%0d", case_id));
    endfunction

    function bit try_get_c_rmw_accum_job_idx_from_name(
        input  int unsigned case_id,
        input  string       test_name,
        output int unsigned job_idx
    );
        ai_accel_subsys_seq_item profile_item;
    begin
        profile_item = ai_accel_subsys_seq_item::type_id::create("c_rmw_accum_host_chk_job_name_item");

        profile_item.apply_c_rmw_accum_job_case(case_id, 0);
        if (test_name == profile_item.test_name) begin
            job_idx = 0;
            return 1'b1;
        end

        profile_item.apply_c_rmw_accum_job_case(case_id, 1);
        if (test_name == profile_item.test_name) begin
            job_idx = 1;
            return 1'b1;
        end

        job_idx = 0;
        return 1'b0;
    end
    endfunction

    function void fill_expected_profile(ref ai_accel_subsys_host_traffic_job job);
        ai_accel_subsys_seq_item profile_item;
        int unsigned             c_rmw_accum_job_idx;
    begin
        profile_item = ai_accel_subsys_seq_item::type_id::create("host_chk_profile_item");

        case (job.test_kind)
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE: begin
                profile_item.apply_fixed_baseline_case(job.case_id);
            end

            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE: begin
                profile_item.apply_variable_dim_case(job.case_id);
            end

            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE: begin
                profile_item.apply_configurable_base_case(job.case_id);
            end

            ai_accel_subsys_seq_item::TEST_KIND_C_RMW_ACCUM_RECIPE: begin
                if (is_c_rmw_accum_recipe_level_identity(job.case_id, job.test_name)) begin
                    profile_item.apply_c_rmw_accum_recipe_case(job.case_id);
                    job.c_rmw_accum_recipe_level = 1'b1;
                    job.c_rmw_accum_partial_job  = 1'b0;
                    job.c_rmw_accum_job_idx      = 0;
                end
                else if (try_get_c_rmw_accum_job_idx_from_name(job.case_id, job.test_name, c_rmw_accum_job_idx)) begin
                    profile_item.apply_c_rmw_accum_job_case(job.case_id, c_rmw_accum_job_idx);
                    job.c_rmw_accum_recipe_level = 1'b0;
                    job.c_rmw_accum_partial_job  = 1'b1;
                    job.c_rmw_accum_job_idx      = c_rmw_accum_job_idx;
                end
                else begin
                    `uvm_fatal("HOST_CHK/C_RMW_ACCUM_BAD_NAME",
                        $sformatf("Unsupported C RMW accumulation host identity: case_id=%0d test_name=%s",
                            job.case_id, job.test_name))
                end
            end

            default: begin
                `uvm_fatal("HOST_CHK/BAD_KIND",
                    $sformatf("Unsupported test_kind=%0d for case_id=%0d",
                        job.test_kind, job.case_id))
            end
        endcase

        // Preserve the observed identity for C RMW accumulation, because recipe-level
        // traffic and partial-job traffic intentionally use different
        // test_name values under the same case_id/test_kind.
        if (!is_c_rmw_accum_kind(job.test_kind)) begin
            job.test_name = profile_item.test_name;
        end

        job.base_addr_a = profile_item.base_addr_a;
        job.base_addr_b = profile_item.base_addr_b;
        job.base_addr_c = profile_item.base_addr_c;

        job.dim_m = profile_item.dim_m;
        job.dim_n = profile_item.dim_n;
        job.dim_k = profile_item.dim_k;

        if (job.c_rmw_accum_recipe_level) begin
            // Recipe-level host traffic owns only C initialization and
            // final C readback. A/B preload and START/DONE belong to
            // the partial-job identities.
            job.exp_a_write_count = 0;
            job.exp_b_write_count = 0;
            job.exp_c_clear_count = profile_item.dim_m * profile_item.dim_n;
            job.exp_c_read_count  = profile_item.dim_m * profile_item.dim_n;
        end
        else if (job.c_rmw_accum_partial_job) begin
            // Partial-job host traffic owns only compact A/B preload.
            // There is no per-partial-job C clear or readback in the
            // focused C RMW accumulation DUT recipe.
            job.exp_a_write_count = profile_item.dim_m * profile_item.dim_k;
            job.exp_b_write_count = profile_item.dim_k * profile_item.dim_n;
            job.exp_c_clear_count = 0;
            job.exp_c_read_count  = 0;
        end
        else begin
            job.exp_a_write_count = profile_item.dim_m * profile_item.dim_k;
            job.exp_b_write_count = profile_item.dim_k * profile_item.dim_n;
            job.exp_c_clear_count = profile_item.dim_m * profile_item.dim_n;
            job.exp_c_read_count  = profile_item.dim_m * profile_item.dim_n;
        end
    end
    endfunction

    function ai_accel_subsys_host_traffic_job find_open_job_by_identity(
        input int unsigned case_id,
        input ai_accel_subsys_seq_item::test_kind_e test_kind,
        input string test_name
    );
        ai_accel_subsys_host_traffic_job job;
    begin
        foreach (active_jobs[i]) begin
            job = active_jobs[i];
            if (!job.closed &&
                (job.case_id   == case_id) &&
                (job.test_kind == test_kind) &&
                (job.test_name == test_name)) begin
                return job;
            end
        end
        return null;
    end
    endfunction

    function ai_accel_subsys_host_traffic_job find_open_job_by_case_kind(
        input int unsigned case_id,
        input ai_accel_subsys_seq_item::test_kind_e test_kind
    );
        ai_accel_subsys_host_traffic_job job;
    begin
        foreach (active_jobs[i]) begin
            job = active_jobs[i];
            if (!job.closed &&
                (job.case_id   == case_id) &&
                (job.test_kind == test_kind)) begin
                return job;
            end
        end
        return null;
    end
    endfunction

    function ai_accel_subsys_host_traffic_job find_open_c_rmw_accum_partial_job_for_ctrl(
        input ai_accel_subsys_seq_item t
    );
        ai_accel_subsys_host_traffic_job job;
    begin
        if (t == null) begin
            return null;
        end

        if (!is_c_rmw_accum_kind(t.test_kind)) begin
            return null;
        end

        foreach (active_jobs[i]) begin
            job = active_jobs[i];

            if (job.closed ||
                !job.c_rmw_accum_partial_job ||
                (job.case_id   != t.case_id) ||
                (job.test_kind != t.test_kind)) begin
                continue;
            end

            if (is_ctrl_start_event(t)) begin
                if (!job.ctrl_start_seen && !job.ctrl_done_seen) begin
                    return job;
                end
            end
            else if (is_ctrl_done_event(t)) begin
                if (job.ctrl_start_seen && !job.ctrl_done_seen) begin
                    return job;
                end
            end
        end

        return null;
    end
    endfunction

    function ai_accel_subsys_host_traffic_job create_job_from_identity(
        input int unsigned case_id,
        input ai_accel_subsys_seq_item::test_kind_e test_kind,
        input string test_name
    );
        ai_accel_subsys_host_traffic_job job;
    begin
        job = ai_accel_subsys_host_traffic_job::type_id::create(
            $sformatf("host_job_%0d_%0d_%0d",
                case_id, int'(test_kind), total_jobs_created)
        );

        job.case_id   = case_id;
        job.test_kind = test_kind;
        job.test_name = test_name;

        fill_expected_profile(job);

        active_jobs.push_back(job);
        total_jobs_created++;

        if (log_enable) begin
            `uvm_info("HOST_CHK",
                $sformatf("Created host traffic job #%0d: case_id=%0d test_kind=%0d test_name=%s dim=(%0d,%0d,%0d) c_rmw_accum_recipe=%0d c_rmw_accum_partial=%0d c_rmw_accum_job_idx=%0d exp(A=%0d B=%0d Cclr=%0d Crd=%0d)",
                    total_jobs_created,
                    job.case_id,
                    job.test_kind,
                    job.test_name,
                    job.dim_m,
                    job.dim_n,
                    job.dim_k,
                    job.c_rmw_accum_recipe_level,
                    job.c_rmw_accum_partial_job,
                    job.c_rmw_accum_job_idx,
                    job.exp_a_write_count,
                    job.exp_b_write_count,
                    job.exp_c_clear_count,
                    job.exp_c_read_count),
                UVM_MEDIUM)
        end

        return job;
    end
    endfunction

    function host_access_kind_e classify_host_access(
        input ai_accel_subsys_host_traffic_job job,
        input axi_mm_host_seq_item             t
    );
        logic [31:0] addr;
    begin
        addr = t.addr;

        if (is_read_event(t)) begin
            if ((t.bytes_per_element == 4) &&
                addr_in_word_region(addr, job.base_addr_c, job.exp_c_read_count)) begin
                return HOST_ACCESS_C_READ;
            end
            else begin
                return HOST_ACCESS_OTHER;
            end
        end

        if ((t.bytes_per_element == 1) &&
            addr_in_byte_region(addr, job.base_addr_a, job.exp_a_write_count)) begin
            return HOST_ACCESS_A_WRITE;
        end

        if ((t.bytes_per_element == 1) &&
            addr_in_byte_region(addr, job.base_addr_b, job.exp_b_write_count)) begin
            return HOST_ACCESS_B_WRITE;
        end

        if ((t.bytes_per_element == 4) &&
            addr_in_word_region(addr, job.base_addr_c, job.exp_c_clear_count)) begin
            return HOST_ACCESS_C_CLEAR;
        end

        return HOST_ACCESS_OTHER;
    end
    endfunction

    function void check_count_overflow(
        input ai_accel_subsys_host_traffic_job job
    );
    begin
        if (job.obs_a_write_count > job.exp_a_write_count) begin
            job.mark_failed();
            `uvm_error("HOST_CHK/A_OVERFLOW",
                $sformatf("A write count overflow: case_id=%0d got=%0d exp=%0d",
                    job.case_id, job.obs_a_write_count, job.exp_a_write_count))
        end

        if (job.obs_b_write_count > job.exp_b_write_count) begin
            job.mark_failed();
            `uvm_error("HOST_CHK/B_OVERFLOW",
                $sformatf("B write count overflow: case_id=%0d got=%0d exp=%0d",
                    job.case_id, job.obs_b_write_count, job.exp_b_write_count))
        end

        if (job.obs_c_clear_count > job.exp_c_clear_count) begin
            job.mark_failed();
            `uvm_error("HOST_CHK/C_CLEAR_OVERFLOW",
                $sformatf("C clear count overflow: case_id=%0d got=%0d exp=%0d",
                    job.case_id, job.obs_c_clear_count, job.exp_c_clear_count))
        end

        if (job.obs_c_read_count > job.exp_c_read_count) begin
            job.mark_failed();
            `uvm_error("HOST_CHK/C_READ_OVERFLOW",
                $sformatf("C read count overflow: case_id=%0d got=%0d exp=%0d",
                    job.case_id, job.obs_c_read_count, job.exp_c_read_count))
        end
    end
    endfunction

    function void check_ctrl_profile_against_expected(
        input ai_accel_subsys_host_traffic_job job,
        input ai_accel_subsys_seq_item         t
    );
    begin
        if (job.ctrl_profile_checked) begin
            return;
        end

        job.ctrl_profile_checked = 1'b1;

        if ((t.base_addr_a != job.base_addr_a) ||
            (t.base_addr_b != job.base_addr_b) ||
            (t.base_addr_c != job.base_addr_c) ||
            (t.dim_m      != job.dim_m)      ||
            (t.dim_n      != job.dim_n)      ||
            (t.dim_k      != job.dim_k)) begin
            job.mark_failed();
            `uvm_error("HOST_CHK/CTRL_PROFILE_MISMATCH",
                $sformatf("Ctrl profile mismatch for case_id=%0d test_kind=%0d job=%s ctrl_dim=(%0d,%0d,%0d) exp_dim=(%0d,%0d,%0d)",
                    t.case_id, t.test_kind, job.test_name,
                    t.dim_m, t.dim_n, t.dim_k,
                    job.dim_m, job.dim_n, job.dim_k))
        end

        // C RMW accumulation note:
        //   Host preloads use the exact partial-job test_name, but the
        //   control monitor may publish a fallback name such as
        //   observed_case_<id>_kind_<kind>.  In that path, the checker
        //   already binds the control event to the currently-open partial
        //   job, so recipe_job_idx from the monitor-side item is not a
        //   reliable identity source.  Only enforce job_idx when the
        //   ctrl-side name matches the partial-job identity exactly.
        if (job.c_rmw_accum_partial_job &&
            (t.test_name == job.test_name) &&
            (t.recipe_job_idx != job.c_rmw_accum_job_idx)) begin
            job.mark_failed();
            `uvm_error("HOST_CHK/C_RMW_ACCUM_JOB_IDX_MISMATCH",
                $sformatf("C RMW accumulation ctrl job_idx mismatch: case_id=%0d test_name=%s ctrl_job_idx=%0d exp_job_idx=%0d",
                    t.case_id, job.test_name, t.recipe_job_idx, job.c_rmw_accum_job_idx))
        end
    end
    endfunction

    function void check_prestart_complete_at_start(
        input ai_accel_subsys_host_traffic_job job,
        input ai_accel_subsys_seq_item         t
    );
    begin
        if (job.obs_a_write_count != job.exp_a_write_count) begin
            job.mark_failed();
            `uvm_error("HOST_CHK/START_A_INCOMPLETE",
                $sformatf("START seen before A preload completed: case_id=%0d got=%0d exp=%0d",
                    job.case_id, job.obs_a_write_count, job.exp_a_write_count))
        end

        if (job.obs_b_write_count != job.exp_b_write_count) begin
            job.mark_failed();
            `uvm_error("HOST_CHK/START_B_INCOMPLETE",
                $sformatf("START seen before B preload completed: case_id=%0d got=%0d exp=%0d",
                    job.case_id, job.obs_b_write_count, job.exp_b_write_count))
        end

        if (job.obs_c_clear_count != job.exp_c_clear_count) begin
            job.mark_failed();
            `uvm_error("HOST_CHK/START_CCLR_INCOMPLETE",
                $sformatf("START seen before C clear completed: case_id=%0d got=%0d exp=%0d",
                    job.case_id, job.obs_c_clear_count, job.exp_c_clear_count))
        end

        if (job.obs_c_read_count != 0) begin
            job.mark_failed();
            `uvm_error("HOST_CHK/START_READBACK_EARLY",
                $sformatf("START seen after unexpected pre-start C readback: case_id=%0d read_count=%0d",
                    job.case_id, job.obs_c_read_count))
        end

        if (job.obs_other_count != 0) begin
            job.mark_failed();
            `uvm_error("HOST_CHK/START_OTHER_EARLY",
                $sformatf("START seen after unexpected pre-start host accesses: case_id=%0d other_count=%0d",
                    job.case_id, job.obs_other_count))
        end
    end
    endfunction

    function void check_phase_rule_for_access(
        input ai_accel_subsys_host_traffic_job job,
        input axi_mm_host_seq_item             t,
        input host_access_kind_e               kind
    );
    begin
        if (job.c_rmw_accum_recipe_level) begin
            case (kind)
                HOST_ACCESS_C_CLEAR,
                HOST_ACCESS_C_READ: begin
                    // allowed: C RMW accumulation recipe-level traffic owns C clear
                    // before job0 and final C readback after the last job.
                end

                default: begin
                    job.mark_failed();
                    `uvm_error("HOST_CHK/C_RMW_ACCUM_RECIPE_TRAFFIC",
                        $sformatf("Unexpected C RMW accumulation recipe-level host access: case_id=%0d test_name=%s kind=%0d addr=0x%08h bytes_per_element=%0d",
                            job.case_id, job.test_name, kind, t.addr, t.bytes_per_element))
                end
            endcase
            return;
        end

        case (job.phase)
            HOST_JOB_PHASE_PRESTART: begin
                case (kind)
                    HOST_ACCESS_A_WRITE,
                    HOST_ACCESS_B_WRITE,
                    HOST_ACCESS_C_CLEAR: begin
                        // allowed
                    end

                    HOST_ACCESS_C_READ: begin
                        job.mark_failed();
                        `uvm_error("HOST_CHK/PHASE_PRESTART_READ",
                            $sformatf("C read observed before START: case_id=%0d test_kind=%0d addr=0x%08h",
                                job.case_id, job.test_kind, t.addr))
                    end

                    default: begin
                        job.mark_failed();
                        `uvm_error("HOST_CHK/PHASE_PRESTART_OTHER",
                            $sformatf("Unexpected PRESTART host access: case_id=%0d test_kind=%0d addr=0x%08h bytes_per_element=%0d",
                                job.case_id, job.test_kind, t.addr, t.bytes_per_element))
                    end
                endcase
            end

            HOST_JOB_PHASE_COMPUTE: begin
                job.mark_failed();
                `uvm_error("HOST_CHK/PHASE_COMPUTE_TRAFFIC",
                    $sformatf("Host traffic observed during COMPUTE phase: case_id=%0d test_kind=%0d kind=%0d addr=0x%08h",
                        job.case_id, job.test_kind, kind, t.addr))
            end

            HOST_JOB_PHASE_POSTDONE: begin
                case (kind)
                    HOST_ACCESS_C_READ: begin
                        // allowed
                    end

                    HOST_ACCESS_A_WRITE,
                    HOST_ACCESS_B_WRITE,
                    HOST_ACCESS_C_CLEAR: begin
                        job.mark_failed();
                        `uvm_error("HOST_CHK/PHASE_POSTDONE_WRITE",
                            $sformatf("Non-readback host traffic observed after DONE: case_id=%0d test_kind=%0d kind=%0d addr=0x%08h",
                                job.case_id, job.test_kind, kind, t.addr))
                    end

                    default: begin
                        job.mark_failed();
                        `uvm_error("HOST_CHK/PHASE_POSTDONE_OTHER",
                            $sformatf("Unexpected POSTDONE host access: case_id=%0d test_kind=%0d addr=0x%08h bytes_per_element=%0d",
                                job.case_id, job.test_kind, t.addr, t.bytes_per_element))
                    end
                endcase
            end

            HOST_JOB_PHASE_CLOSED: begin
                job.mark_failed();
                `uvm_error("HOST_CHK/PHASE_CLOSED_TRAFFIC",
                    $sformatf("Host traffic observed after job already closed: case_id=%0d test_kind=%0d addr=0x%08h",
                        job.case_id, job.test_kind, t.addr))
            end

            default: begin
                job.mark_failed();
                `uvm_error("HOST_CHK/BAD_PHASE",
                    $sformatf("Unknown phase for case_id=%0d test_kind=%0d", job.case_id, job.test_kind))
            end
        endcase
    end
    endfunction

    // ------------------------------------------------------------
    // Expected-abort helpers
    // ------------------------------------------------------------
    function bit job_can_be_expected_abort(
        input ai_accel_subsys_host_traffic_job job
    );
    begin
        if (job == null)
            return 1'b0;

        if (!midrun_reset_test_mode)
            return 1'b0;

        if (job.closed)
            return 1'b0;

        if (!job.ctrl_start_seen)
            return 1'b0;

        if (job.ctrl_done_seen)
            return 1'b0;

        if (job.phase != HOST_JOB_PHASE_COMPUTE)
            return 1'b0;

        if (job.failed)
            return 1'b0;

        if (job.obs_a_write_count != job.exp_a_write_count)
            return 1'b0;

        if (job.obs_b_write_count != job.exp_b_write_count)
            return 1'b0;

        if (job.obs_c_clear_count != job.exp_c_clear_count)
            return 1'b0;

        if (job.obs_c_read_count != 0)
            return 1'b0;

        if (job.obs_other_count != 0)
            return 1'b0;

        if (job.host_readback_complete)
            return 1'b0;

        return 1'b1;
    end
    endfunction

    function bit can_accept_more_expected_aborts();
        return (total_jobs_aborted_expected < expected_aborted_job_count);
    endfunction

    function bit close_job_as_expected_abort(
        ref ai_accel_subsys_host_traffic_job job,
        input string reason
    );
    begin
        if (!job_can_be_expected_abort(job))
            return 1'b0;

        if (!can_accept_more_expected_aborts())
            return 1'b0;

        job.phase  = HOST_JOB_PHASE_CLOSED;
        job.closed = 1'b1;

        total_jobs_aborted_expected++;

        `uvm_info("HOST_CHK",
            $sformatf("Accepted expected aborted job #%0d: case_id=%0d test_kind=%0d test_name=%s reason=%s A=%0d/%0d B=%0d/%0d Cclr=%0d/%0d",
                total_jobs_aborted_expected,
                job.case_id,
                job.test_kind,
                job.test_name,
                reason,
                job.obs_a_write_count, job.exp_a_write_count,
                job.obs_b_write_count, job.exp_b_write_count,
                job.obs_c_clear_count, job.exp_c_clear_count),
            UVM_MEDIUM)

        return 1'b1;
    end
    endfunction

    function bit maybe_close_stale_open_job_before_reuse(
        ref ai_accel_subsys_host_traffic_job job,
        input string reason
    );
    begin
        if (job == null)
            return 1'b0;

        if (close_job_as_expected_abort(job, reason)) begin
            job = null;
            return 1'b1;
        end

        return 1'b0;
    end
    endfunction

    function void maybe_finalize_job(ref ai_accel_subsys_host_traffic_job job);
        bit ready_to_close;
    begin
        if (job.closed) begin
            return;
        end

        ready_to_close = 1'b0;

        if (job.c_rmw_accum_recipe_level) begin
            ready_to_close = (job.obs_c_clear_count == job.exp_c_clear_count) &&
                             job.host_readback_complete;
        end
        else if (job.c_rmw_accum_partial_job) begin
            ready_to_close = job.ctrl_done_seen;
        end
        else begin
            ready_to_close = job.ctrl_done_seen && job.host_readback_complete;
        end

        if (!ready_to_close) begin
            return;
        end

        job.phase  = HOST_JOB_PHASE_CLOSED;
        job.closed = 1'b1;

        if (job.all_expected_counts_match() && !job.failed) begin
            total_jobs_passed++;
            `uvm_info("HOST_CHK",
                $sformatf("PASS job: case_id=%0d test_kind=%0d test_name=%s c_rmw_accum_recipe=%0d c_rmw_accum_partial=%0d A=%0d/%0d B=%0d/%0d Cclr=%0d/%0d Crd=%0d/%0d",
                    job.case_id, job.test_kind, job.test_name,
                    job.c_rmw_accum_recipe_level, job.c_rmw_accum_partial_job,
                    job.obs_a_write_count, job.exp_a_write_count,
                    job.obs_b_write_count, job.exp_b_write_count,
                    job.obs_c_clear_count, job.exp_c_clear_count,
                    job.obs_c_read_count,  job.exp_c_read_count),
                UVM_MEDIUM)
        end
        else begin
            total_jobs_failed++;
            `uvm_error("HOST_CHK/JOB_FAIL",
                $sformatf("FAIL job: case_id=%0d test_kind=%0d test_name=%s phase=%s c_rmw_accum_recipe=%0d c_rmw_accum_partial=%0d A=%0d/%0d B=%0d/%0d Cclr=%0d/%0d Crd=%0d/%0d other=%0d start_seen=%0d done_seen=%0d",
                    job.case_id, job.test_kind, job.test_name, phase_name(job.phase),
                    job.c_rmw_accum_recipe_level, job.c_rmw_accum_partial_job,
                    job.obs_a_write_count, job.exp_a_write_count,
                    job.obs_b_write_count, job.exp_b_write_count,
                    job.obs_c_clear_count, job.exp_c_clear_count,
                    job.obs_c_read_count,  job.exp_c_read_count,
                    job.obs_other_count,
                    job.ctrl_start_seen,
                    job.ctrl_done_seen))
        end
    end
    endfunction

    // ------------------------------------------------------------
    // Ctrl event input
    //
    // Same ctrl path as v1, now phase-aware.
    // ------------------------------------------------------------
    function void write_hostchk_ctrl(ai_accel_subsys_seq_item t);
        ai_accel_subsys_host_traffic_job job;
    begin
        total_ctrl_events++;

        if (!enable_check) begin
            return;
        end

        if (!strict_check_enable) begin
            return;
        end

        job = find_open_job_by_identity(t.case_id, t.test_kind, t.test_name);
        if (job == null) begin
            if (is_c_rmw_accum_kind(t.test_kind)) begin
                // C RMW accumulation control monitor items may use a generic observed_*
                // test_name.  Bind them to the currently-open partial-job
                // host traffic job created by the A/B preload sequence.
                job = find_open_c_rmw_accum_partial_job_for_ctrl(t);
            end
            else begin
                job = find_open_job_by_case_kind(t.case_id, t.test_kind);
            end
        end

        // If a stale open job from a prior aborted run is being reused
        // with the same identity, try to close it first.
        if (is_ctrl_start_event(t) && (job != null)) begin
            if (job.ctrl_start_seen && !job.ctrl_done_seen) begin
                void'(maybe_close_stale_open_job_before_reuse(job, "new START event for reused identity"));
            end
        end

        if (job == null) begin
            if (is_c_rmw_accum_kind(t.test_kind)) begin
                `uvm_fatal("HOST_CHK/C_RMW_ACCUM_NO_PARTIAL_JOB",
                    $sformatf("C RMW accumulation ctrl event could not be matched to an open partial-job host traffic identity: case_id=%0d test_name=%s event=%s",
                        t.case_id, t.test_name, ctrl_event_name(t)))
            end
            else begin
                job = create_job_from_identity(t.case_id, t.test_kind, t.test_name);
            end
        end

        check_ctrl_profile_against_expected(job, t);

        if (is_ctrl_start_event(t)) begin
            total_start_events++;

            if (job.ctrl_start_seen) begin
                job.mark_failed();
                `uvm_error("HOST_CHK/DUP_START",
                    $sformatf("Duplicate START event: case_id=%0d test_kind=%0d test_name=%s",
                        t.case_id, t.test_kind, t.test_name))
            end

            if (job.phase != HOST_JOB_PHASE_PRESTART) begin
                job.mark_failed();
                `uvm_error("HOST_CHK/START_BAD_PHASE",
                    $sformatf("START event observed in bad phase: case_id=%0d test_kind=%0d phase=%s",
                        t.case_id, t.test_kind, phase_name(job.phase)))
            end

            check_prestart_complete_at_start(job, t);

            job.ctrl_start_seen = 1'b1;
            job.phase           = HOST_JOB_PHASE_COMPUTE;

            if (log_enable) begin
                `uvm_info("HOST_CHK",
                    $sformatf("Accepted START event: case_id=%0d test_kind=%0d start_cycle=%0d -> phase=%s",
                        t.case_id, t.test_kind, t.start_cycle, phase_name(job.phase)),
                    UVM_HIGH)
            end

            return;
        end

        if (is_ctrl_done_event(t)) begin
            total_done_events++;

            if (!job.ctrl_start_seen) begin
                // Allow legacy done-only ctrl stream, but flag modern START/DONE mismatch.
                if (t.ctrl_event_kind == ai_accel_subsys_seq_item::CTRL_EVENT_NONE) begin
                    job.ctrl_start_seen = 1'b1;
                end
                else begin
                    job.mark_failed();
                    `uvm_error("HOST_CHK/DONE_WITHOUT_START",
                        $sformatf("DONE event observed before START: case_id=%0d test_kind=%0d test_name=%s",
                            t.case_id, t.test_kind, t.test_name))
                end
            end

            if (job.ctrl_done_seen) begin
                job.mark_failed();
                `uvm_error("HOST_CHK/DUP_DONE",
                    $sformatf("Duplicate DONE event: case_id=%0d test_kind=%0d test_name=%s",
                        t.case_id, t.test_kind, t.test_name))
            end

            if ((job.phase != HOST_JOB_PHASE_COMPUTE) &&
                (job.phase != HOST_JOB_PHASE_POSTDONE)) begin
                job.mark_failed();
                `uvm_error("HOST_CHK/DONE_BAD_PHASE",
                    $sformatf("DONE event observed in bad phase: case_id=%0d test_kind=%0d phase=%s",
                        t.case_id, t.test_kind, phase_name(job.phase)))
            end

            job.ctrl_done_seen = 1'b1;
            job.phase          = HOST_JOB_PHASE_POSTDONE;

            if (log_enable) begin
                `uvm_info("HOST_CHK",
                    $sformatf("Accepted DONE event: case_id=%0d test_kind=%0d done_cycle=%0d -> phase=%s",
                        t.case_id, t.test_kind, t.done_cycle, phase_name(job.phase)),
                    UVM_HIGH)
            end

            maybe_finalize_job(job);
            return;
        end

        `uvm_warning("HOST_CHK/CTRL_EVENT_UNKNOWN",
            $sformatf("Ignoring ctrl event with unknown classification: case_id=%0d test_kind=%0d event_kind=%s done_seen=%0d",
                t.case_id, t.test_kind, ctrl_event_name(t), t.done_seen))
    end
    endfunction

    // ------------------------------------------------------------
    // Host traffic input
    // ------------------------------------------------------------
    function void write_hostchk_host(axi_mm_host_seq_item t);
        ai_accel_subsys_host_traffic_job job;
        host_access_kind_e               kind;
    begin
        total_host_events++;

        if (!enable_check) begin
            return;
        end

        // In helper fallback mode, passive host monitor still sees bus
        // activity. Phase-aware checker still does not do strict
        // checking there.
        if (!strict_check_enable) begin
            total_host_events_skipped++;
            return;
        end

        if (is_metadata_missing(t)) begin
            `uvm_error("HOST_CHK/MISSING_METADATA",
                "Strict host checking is enabled, but host traffic metadata is missing")
            return;
        end

        job = find_open_job_by_identity(t.case_id, t.test_kind, t.test_name);

        // If new host-prestart traffic appears with the same identity
        // after a prior job was interrupted mid-run, try to close that
        // stale job first and create a fresh one.
        if (job != null) begin
            if (job.ctrl_start_seen && !job.ctrl_done_seen) begin
                void'(maybe_close_stale_open_job_before_reuse(job, "new host traffic for reused identity"));
            end
        end

        if (job == null) begin
            job = create_job_from_identity(t.case_id, t.test_kind, t.test_name);
        end

        kind = classify_host_access(job, t);

        check_phase_rule_for_access(job, t, kind);

        case (kind)
            HOST_ACCESS_A_WRITE: job.obs_a_write_count++;
            HOST_ACCESS_B_WRITE: job.obs_b_write_count++;
            HOST_ACCESS_C_CLEAR: job.obs_c_clear_count++;
            HOST_ACCESS_C_READ:  begin
                job.obs_c_read_count++;
                if (job.obs_c_read_count == job.exp_c_read_count) begin
                    job.host_readback_complete = 1'b1;
                end
            end

            default: begin
                job.obs_other_count++;
                job.mark_failed();
                `uvm_error("HOST_CHK/UNEXPECTED_ACCESS",
                    $sformatf("Unexpected host access: case_id=%0d test_kind=%0d test_name=%s addr=0x%08h bytes_per_element=%0d phase=%s",
                        t.case_id, t.test_kind, t.test_name, t.addr, t.bytes_per_element, phase_name(job.phase)))
            end
        endcase

        check_count_overflow(job);
        maybe_finalize_job(job);
    end
    endfunction

    // ------------------------------------------------------------
    // Report phase
    // ------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        ai_accel_subsys_host_traffic_job job;
        int unsigned observed_aborted_jobs_in_report;

        super.report_phase(phase);

        observed_aborted_jobs_in_report = 0;

        if (enable_check && strict_check_enable) begin
            foreach (active_jobs[i]) begin
                job = active_jobs[i];
                if (!job.closed) begin
                    if (close_job_as_expected_abort(job, "report_phase incomplete active job")) begin
                        observed_aborted_jobs_in_report++;
                    end
                    else begin
                        total_jobs_failed++;
                        `uvm_error("HOST_CHK/INCOMPLETE_JOB",
                            $sformatf("Incomplete host traffic job: case_id=%0d test_kind=%0d phase=%s A=%0d/%0d B=%0d/%0d Cclr=%0d/%0d Crd=%0d/%0d start_seen=%0d done_seen=%0d",
                                job.case_id, job.test_kind, phase_name(job.phase),
                                job.obs_a_write_count, job.exp_a_write_count,
                                job.obs_b_write_count, job.exp_b_write_count,
                                job.obs_c_clear_count, job.exp_c_clear_count,
                                job.obs_c_read_count,  job.exp_c_read_count,
                                job.ctrl_start_seen, job.ctrl_done_seen))
                    end
                end
            end

            if (midrun_reset_test_mode) begin
                if (total_jobs_aborted_expected != expected_aborted_job_count) begin
                    `uvm_error("HOST_CHK/ABORT_COUNT",
                        $sformatf("Expected aborted job count mismatch: observed=%0d expected=%0d",
                            total_jobs_aborted_expected, expected_aborted_job_count))
                end
            end
        end

        `uvm_info("HOST_CHK",
            $sformatf("Summary: enable=%0d strict=%0d ctrl_events=%0d start_events=%0d done_events=%0d host_events=%0d skipped_host_events=%0d jobs_created=%0d pass=%0d fail=%0d aborted_expected=%0d",
                enable_check,
                strict_check_enable,
                total_ctrl_events,
                total_start_events,
                total_done_events,
                total_host_events,
                total_host_events_skipped,
                total_jobs_created,
                total_jobs_passed,
                total_jobs_failed,
                total_jobs_aborted_expected),
            UVM_LOW)
    endfunction

endclass

`endif