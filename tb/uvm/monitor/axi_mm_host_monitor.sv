// File: tb/uvm/monitor/axi_mm_host_monitor.sv
`ifndef AXI_MM_HOST_MONITOR_SV
`define AXI_MM_HOST_MONITOR_SV

class axi_mm_host_monitor extends uvm_monitor;
    `uvm_component_utils(axi_mm_host_monitor)

    // ------------------------------------------------------------
    // AXI host vif typedef
    //   Must match ai_accel_subsys_uvm_top.sv / driver.sv
    // ------------------------------------------------------------
    typedef virtual axi_mm_if #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (64),
        .ID_WIDTH   (4),
        .HAS_BURST  (1)
    ) axi0_vif_t;

    // ------------------------------------------------------------
    // Local protocol constants
    // ------------------------------------------------------------
    localparam int unsigned ADDR_WIDTH    = 32;
    localparam int unsigned DATA_WIDTH    = 64;
    localparam int unsigned BYTE_PER_WORD = DATA_WIDTH / 8;
    localparam int unsigned WORD_LSB_W    = (BYTE_PER_WORD > 1) ? $clog2(BYTE_PER_WORD) : 1;

    // ------------------------------------------------------------
    // Virtual interface
    // ------------------------------------------------------------
    axi0_vif_t vif;

    // ------------------------------------------------------------
    // Analysis port
    // ------------------------------------------------------------
    uvm_analysis_port #(axi_mm_host_seq_item) ap;

    // ------------------------------------------------------------
    // Optional runtime context
    //   Helpful if test wants to label host traffic with current
    //   case / kind / job_idx.
    // ------------------------------------------------------------
    int unsigned current_case_id;
    ai_accel_subsys_seq_item::test_kind_e current_test_kind;
    string       current_test_name;
    int unsigned current_job_idx;
    bit          has_runtime_context;

    // ------------------------------------------------------------
    // Internal observed channel state
    // ------------------------------------------------------------
    typedef struct {
        bit [ADDR_WIDTH-1:0] addr;
        bit [7:0]            len;
        bit [2:0]            size;
        bit [1:0]            burst;
    } aw_info_t;

    typedef struct {
        bit [DATA_WIDTH-1:0]      data;
        bit [BYTE_PER_WORD-1:0]   strb;
        bit                       last;
    } w_info_t;

    typedef struct {
        bit [ADDR_WIDTH-1:0] addr;
        bit [7:0]            len;
        bit [2:0]            size;
        bit [1:0]            burst;
    } ar_info_t;

    typedef struct {
        bit [ADDR_WIDTH-1:0]      addr;
        bit [2:0]                 size;
        bit [1:0]                 burst;
        bit [DATA_WIDTH-1:0]      data;
        bit [BYTE_PER_WORD-1:0]   strb;
        bit                       last;
    } wr_info_t;

    aw_info_t aw_q[$];
    w_info_t  w_q[$];
    axi_mm_host_seq_item pending_write_item_q[$];
    ar_info_t ar_q[$];

    bit                       active_read_valid;
    ar_info_t                 active_ar;
    bit [DATA_WIDTH-1:0]      active_r_data_q[$];

    // ------------------------------------------------------------
    // Debug / bookkeeping
    // ------------------------------------------------------------
    bit          enable_log;
    int unsigned observed_write_count;
    int unsigned observed_read_count;
    int unsigned dropped_on_reset_count;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "axi_mm_host_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);

        current_case_id      = 0;
        current_test_kind    = ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE;
        current_test_name    = "";
        current_job_idx      = 0;
        has_runtime_context  = 1'b0;
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(axi0_vif_t)::get(this, "", "axi0_vif", vif)) begin
            `uvm_fatal("AXI_HOST_MON/NOVIF",
                "axi0_vif is not set for axi_mm_host_monitor")
        end

        enable_log             = 1'b1;
        observed_write_count   = 0;
        observed_read_count    = 0;
        dropped_on_reset_count = 0;
        active_read_valid      = 1'b0;
        active_r_data_q.delete();

        void'(uvm_config_db#(bit)::get(this, "", "enable_log", enable_log));
    endfunction

    // ------------------------------------------------------------
    // Runtime context control
    // ------------------------------------------------------------
    function void set_case_context(
        input int unsigned case_id,
        input ai_accel_subsys_seq_item::test_kind_e test_kind,
        input string test_name = "",
        input int unsigned job_idx = 0
    );
        current_case_id     = case_id;
        current_test_kind   = test_kind;
        current_test_name   = test_name;
        current_job_idx     = job_idx;
        has_runtime_context = 1'b1;

        if (enable_log) begin
            `uvm_info("AXI_HOST_MON",
                $sformatf("Updated runtime context: case_id=%0d test_kind=%0d job_idx=%0d test_name=%s",
                    current_case_id, current_test_kind, current_job_idx, current_test_name),
                UVM_HIGH)
        end
    endfunction

    function void clear_case_context();
        has_runtime_context = 1'b0;
        current_test_name   = "";
    endfunction

    // ------------------------------------------------------------
    // Context annotation helper
    // ------------------------------------------------------------
    function string default_test_name_from_context();
        case (current_test_kind)
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE:
                return $sformatf("fixed_baseline_case_%0d", current_case_id);

            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE:
                return $sformatf("variable_dim_case_%0d", current_case_id);

            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE:
                return $sformatf("config_base_case_%0d", current_case_id);

            default:
                return $sformatf("observed_case_%0d_kind_%0d",
                    current_case_id, current_test_kind);
        endcase
    endfunction

    function void annotate_context(ref axi_mm_host_seq_item item);
        if (!has_runtime_context)
            return;

        item.case_id   = current_case_id;
        item.test_kind = current_test_kind;
        item.job_idx   = current_job_idx;

        if (current_test_name != "")
            item.test_name = current_test_name;
        else
            item.test_name = default_test_name_from_context();
    endfunction

    // ------------------------------------------------------------
    // Pending state management
    // ------------------------------------------------------------
    function void clear_pending_state();
        int unsigned pending_count;
    begin
        pending_count =
            aw_q.size() +
            w_q.size() +
            pending_write_item_q.size() +
            ar_q.size() +
            (active_read_valid ? 1 : 0);

        if (pending_count != 0) begin
            dropped_on_reset_count += pending_count;

            `uvm_warning("AXI_HOST_MON/RESET_DROP",
                $sformatf("Clearing %0d pending host channel entries due to reset",
                    pending_count))
        end

        aw_q.delete();
        w_q.delete();
        pending_write_item_q.delete();
        ar_q.delete();
        active_read_valid = 1'b0;
        active_r_data_q.delete();
    end
    endfunction

    // ------------------------------------------------------------
    // Wait until AXI reset is released
    // ------------------------------------------------------------
    task automatic wait_for_reset_release();
        @(posedge vif.clk);
        while (vif.rst_n !== 1'b1) begin
            @(posedge vif.clk);
        end
    endtask

    // ------------------------------------------------------------
    // Byte-lane helpers
    // ------------------------------------------------------------
    function int unsigned count_active_bytes(bit [BYTE_PER_WORD-1:0] strb);
        int unsigned i;
        int unsigned cnt;
    begin
        cnt = 0;
        for (i = 0; i < BYTE_PER_WORD; i++) begin
            if (strb[i])
                cnt++;
        end
        return cnt;
    end
    endfunction

    function int signed first_active_lane(bit [BYTE_PER_WORD-1:0] strb);
        int signed i;
    begin
        for (i = 0; i < BYTE_PER_WORD; i++) begin
            if (strb[i])
                return i;
        end
        return -1;
    end
    endfunction

    function bit is_contiguous_4byte_write(
        bit [BYTE_PER_WORD-1:0] strb,
        int signed first_lane
    );
        bit [BYTE_PER_WORD-1:0] exp_strb;
    begin
        if (first_lane < 0)
            return 1'b0;

        if ((first_lane + 3) >= BYTE_PER_WORD)
            return 1'b0;

        exp_strb = (4'b1111 << first_lane);

        if (strb !== exp_strb)
            return 1'b0;

        if ((first_lane % 4) != 0)
            return 1'b0;

        return 1'b1;
    end
    endfunction

    function byte signed extract_s8_lane(
        bit [DATA_WIDTH-1:0] data,
        int unsigned lane
    );
        bit [7:0] tmp;
    begin
        tmp = data >> (lane * 8);
        return byte'(tmp);
    end
    endfunction

    function bit [31:0] extract_u32_at_lane(
        bit [DATA_WIDTH-1:0] data,
        int unsigned first_lane
    );
        bit [31:0] tmp;
    begin
        tmp = data >> (first_lane * 8);
        return tmp;
    end
    endfunction

    function bit is_strb_sparse(bit [BYTE_PER_WORD-1:0] strb);
        int signed first_lane_idx;
        int signed last_lane_idx;
        int signed i;
        bit        seen_gap;
    begin
        first_lane_idx = -1;
        last_lane_idx  = -1;
        seen_gap       = 1'b0;

        for (i = 0; i < BYTE_PER_WORD; i++) begin
            if (strb[i]) begin
                if (first_lane_idx < 0)
                    first_lane_idx = i;
                last_lane_idx = i;
            end
        end

        if (first_lane_idx < 0)
            return 1'b0;

        for (i = first_lane_idx; i <= last_lane_idx; i++) begin
            if (!strb[i])
                seen_gap = 1'b1;
        end

        return seen_gap;
    end
    endfunction

    // ------------------------------------------------------------
    // Build observed item from completed write
    //
    // v1 policy:
    //   - 1 active byte  -> WRITE_BYTES of size 1
    //   - aligned 4-byte contiguous strobe -> FILL_U32 count=1
    //   - otherwise -> WRITE_BYTES containing all active bytes in
    //                  ascending lane order, starting at first lane
    //                  (warn if sparse)
    // ------------------------------------------------------------
    function axi_mm_host_seq_item build_write_item(wr_info_t wr);
        axi_mm_host_seq_item item;
        int unsigned         active_cnt;
        int signed           first_lane_idx;
        byte signed          byte_vec[];
        int unsigned         i;
        int unsigned         j;
        bit [31:0]           value_u32;
        bit [31:0]           observed_addr;
    begin
        item = axi_mm_host_seq_item::type_id::create("observed_write_item");
        annotate_context(item);

        active_cnt      = count_active_bytes(wr.strb);
        first_lane_idx  = first_active_lane(wr.strb);

        if (active_cnt == 0) begin
            `uvm_warning("AXI_HOST_MON/EMPTY_WRITE",
                $sformatf("Observed write completion with zero-active strobe at addr=0x%08h",
                    wr.addr))
            item.setup_write_bytes(wr.addr, byte_vec, axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC);
            item.response_valid = 1'b1;
            return item;
        end

        if ((active_cnt == 4) && is_contiguous_4byte_write(wr.strb, first_lane_idx)) begin
            value_u32    = extract_u32_at_lane(wr.data, first_lane_idx);
            observed_addr = wr.addr + first_lane_idx;

            item.setup_fill_u32(
                observed_addr,
                1,
                value_u32,
                axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC
            );
            item.response_valid = 1'b1;
            return item;
        end

        if (is_strb_sparse(wr.strb)) begin
            `uvm_warning("AXI_HOST_MON/SPARSE_STRB",
                $sformatf("Observed sparse write strobe=0x%0h at addr=0x%08h; packing active bytes in ascending lane order",
                    wr.strb, wr.addr))
        end

        byte_vec = new[active_cnt];
        j = 0;
        for (i = 0; i < BYTE_PER_WORD; i++) begin
            if (wr.strb[i]) begin
                byte_vec[j] = extract_s8_lane(wr.data, i);
                j++;
            end
        end

        observed_addr = wr.addr + first_lane_idx;

        item.setup_write_bytes(
            observed_addr,
            byte_vec,
            axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC
        );
        item.response_valid = 1'b1;

        return item;
    end
    endfunction

    // ------------------------------------------------------------
    // Build observed item from completed read
    //
    // v1 policy:
    //   interpret each completed read beat as READ_S32 count=1,
    //   using the 32-bit value selected by ar.addr byte offset.
    // ------------------------------------------------------------
    function axi_mm_host_seq_item build_read_item(
        ar_info_t ar,
        bit [DATA_WIDTH-1:0] data_word
    );
        axi_mm_host_seq_item item;
        bit [WORD_LSB_W-1:0] byte_offset;
        bit [31:0]           value_u32;
    begin
        item = axi_mm_host_seq_item::type_id::create("observed_read_item");
        annotate_context(item);

        item.setup_read_s32(
            ar.addr,
            1,
            axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC
        );

        byte_offset = ar.addr[WORD_LSB_W-1:0];
        value_u32   = data_word >> (byte_offset * 8);

        item.read_data_s32 = new[1];
        item.read_data_s32[0] = int'(value_u32);
        item.response_valid   = 1'b1;

        return item;
    end
    endfunction

    // ------------------------------------------------------------
    // Build observed item from a completed raw write burst.
    //
    // Legacy single-beat INCR writes continue to use
    // build_write_item() so existing monitor/checker behavior is
    // unchanged.  Any non-legacy burst is published as one raw
    // burst transaction with exact LEN/SIZE/BURST metadata.
    // ------------------------------------------------------------
    function axi_mm_host_seq_item build_raw_write_burst_item(
        aw_info_t aw,
        bit [DATA_WIDTH-1:0] data_vec[],
        bit [BYTE_PER_WORD-1:0] strb_vec[]
    );
        axi_mm_host_seq_item item;
        bit [63:0]           data64[];
        bit [7:0]            strb8[];
        int unsigned         i;
    begin
        item = axi_mm_host_seq_item::type_id::create("observed_raw_write_burst_item");
        annotate_context(item);

        data64 = new[data_vec.size()];
        strb8  = new[strb_vec.size()];

        for (i = 0; i < data_vec.size(); i++) begin
            data64[i] = data_vec[i];
        end

        for (i = 0; i < strb_vec.size(); i++) begin
            strb8[i] = strb_vec[i];
        end

        item.setup_raw_write_burst(
            aw.addr,
            data64,
            strb8,
            aw.size,
            aw.burst,
            axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC
        );
        item.response_valid = 1'b0;

        return item;
    end
    endfunction

    // ------------------------------------------------------------
    // Build observed item from a completed raw read burst.
    //
    // Legacy single-beat INCR reads continue to use
    // build_read_item().  Any non-legacy burst is published as one
    // raw read transaction after all expected R beats are observed.
    // ------------------------------------------------------------
    function axi_mm_host_seq_item build_raw_read_burst_item(
        ar_info_t ar,
        bit [DATA_WIDTH-1:0] data_vec[]
    );
        axi_mm_host_seq_item item;
        int unsigned         i;
        int unsigned         beat_count;
    begin
        beat_count = int'(ar.len) + 1;

        item = axi_mm_host_seq_item::type_id::create("observed_raw_read_burst_item");
        annotate_context(item);

        item.setup_raw_read_burst(
            ar.addr,
            beat_count,
            ar.size,
            ar.burst,
            axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC
        );

        item.burst_read_data = new[data_vec.size()];
        for (i = 0; i < data_vec.size(); i++) begin
            item.burst_read_data[i] = data_vec[i];
        end

        item.response_valid = 1'b1;
        return item;
    end
    endfunction

    // ------------------------------------------------------------
    // Publish helpers
    // ------------------------------------------------------------
    function void publish_write_item(wr_info_t wr);
        axi_mm_host_seq_item item;
    begin
        item = build_write_item(wr);
        observed_write_count++;

        if (enable_log) begin
            `uvm_info("AXI_HOST_MON",
                $sformatf("Observed host write #%0d: %s",
                    observed_write_count, item.convert2string()),
                UVM_MEDIUM)
        end

        ap.write(item);
    end
    endfunction

    function void publish_read_item(
        ar_info_t ar,
        bit [DATA_WIDTH-1:0] data_word
    );
        axi_mm_host_seq_item item;
    begin
        item = build_read_item(ar, data_word);
        observed_read_count++;

        if (enable_log) begin
            `uvm_info("AXI_HOST_MON",
                $sformatf("Observed host read #%0d: %s",
                    observed_read_count, item.convert2string()),
                UVM_MEDIUM)
        end

        ap.write(item);
    end
    endfunction

    function void publish_prebuilt_write_item(axi_mm_host_seq_item item);
    begin
        observed_write_count++;

        if (enable_log) begin
            `uvm_info("AXI_HOST_MON",
                $sformatf("Observed host write #%0d: %s",
                    observed_write_count, item.convert2string()),
                UVM_MEDIUM)
        end

        ap.write(item);
    end
    endfunction

    function void publish_prebuilt_read_item(axi_mm_host_seq_item item);
    begin
        observed_read_count++;

        if (enable_log) begin
            `uvm_info("AXI_HOST_MON",
                $sformatf("Observed host read #%0d: %s",
                    observed_read_count, item.convert2string()),
                UVM_MEDIUM)
        end

        ap.write(item);
    end
    endfunction

    // ------------------------------------------------------------
    // Run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        aw_info_t aw;
        w_info_t  w;
        wr_info_t wr;
        ar_info_t ar;
        axi_mm_host_seq_item item;
        bit [DATA_WIDTH-1:0]    write_data_vec[];
        bit [BYTE_PER_WORD-1:0] write_strb_vec[];
        bit [DATA_WIDTH-1:0]    read_data_vec[];
        int unsigned expected_beats;
        int unsigned beat_idx;
    begin
        wait_for_reset_release();
        clear_pending_state();

        forever begin
            @(posedge vif.clk);

            if (vif.rst_n !== 1'b1) begin
                clear_pending_state();
                continue;
            end

            // --------------------------------------------
            // Sample AW handshake
            // --------------------------------------------
            if (vif.awvalid && vif.awready) begin
                aw.addr  = vif.awaddr;
                aw.len   = vif.awlen;
                aw.size  = vif.awsize;
                aw.burst = vif.awburst;
                aw_q.push_back(aw);
            end

            // --------------------------------------------
            // Sample W handshake
            // --------------------------------------------
            if (vif.wvalid && vif.wready) begin
                w.data = vif.wdata;
                w.strb = vif.wstrb;
                w.last = vif.wlast;
                w_q.push_back(w);
            end

            // --------------------------------------------
            // Combine one AW with all of its W beats.
            //
            // AXI4 W has no transaction ID, so write data is
            // associated with AW transactions in issue order.
            // Wait until all LEN+1 beats for the oldest AW have
            // arrived, then build exactly one pending transaction
            // that will be published when its B response is seen.
            // --------------------------------------------
            while (aw_q.size() > 0) begin
                expected_beats = int'(aw_q[0].len) + 1;

                if (w_q.size() < expected_beats)
                    break;

                aw = aw_q.pop_front();

                write_data_vec = new[expected_beats];
                write_strb_vec = new[expected_beats];

                for (beat_idx = 0; beat_idx < expected_beats; beat_idx++) begin
                    w = w_q.pop_front();

                    write_data_vec[beat_idx] = w.data;
                    write_strb_vec[beat_idx] = w.strb;

                    if ((beat_idx + 1) < expected_beats) begin
                        if (w.last) begin
                            `uvm_error("AXI_HOST_MON/EARLY_WLAST",
                                $sformatf("Observed early WLAST for AW addr=0x%08h len=%0d at beat=%0d",
                                    aw.addr, aw.len, beat_idx))
                        end
                    end
                    else begin
                        if (!w.last) begin
                            `uvm_error("AXI_HOST_MON/MISSING_WLAST",
                                $sformatf("Missing WLAST on final W beat for AW addr=0x%08h len=%0d",
                                    aw.addr, aw.len))
                        end
                    end
                end

                // Preserve the existing single-beat INCR monitor
                // representation exactly for all legacy traffic.
                if ((aw.len == 8'd0) && (aw.burst == 2'b01)) begin
                    wr.addr  = aw.addr;
                    wr.size  = aw.size;
                    wr.burst = aw.burst;
                    wr.data  = write_data_vec[0];
                    wr.strb  = write_strb_vec[0];
                    wr.last  = 1'b1;

                    item = build_write_item(wr);
                    item.response_valid = 1'b0;
                end
                else begin
                    item = build_raw_write_burst_item(
                        aw,
                        write_data_vec,
                        write_strb_vec
                    );
                end

                pending_write_item_q.push_back(item);
            end

            // --------------------------------------------
            // Sample B handshake -> completed write item
            // --------------------------------------------
            if (vif.bvalid && vif.bready) begin
                if (pending_write_item_q.size() == 0) begin
                    `uvm_error("AXI_HOST_MON/UNMATCHED_B",
                        "Observed B handshake with no pending write")
                end
                else begin
                    item = pending_write_item_q.pop_front();
                    item.response_valid = 1'b1;
                    publish_prebuilt_write_item(item);
                end
            end

            // --------------------------------------------
            // Sample AR handshake
            // --------------------------------------------
            if (vif.arvalid && vif.arready) begin
                ar.addr  = vif.araddr;
                ar.len   = vif.arlen;
                ar.size  = vif.arsize;
                ar.burst = vif.arburst;
                ar_q.push_back(ar);
            end

            // --------------------------------------------
            // Sample R handshake.
            //
            // Keep the AR active for LEN+1 beats.  This fixes the
            // previous single-beat assumption that popped AR on the
            // first R handshake and reported the remaining burst
            // beats as UNMATCHED_R.
            // --------------------------------------------
            if (vif.rvalid && vif.rready) begin
                if (!active_read_valid) begin
                    if (ar_q.size() == 0) begin
                        `uvm_error("AXI_HOST_MON/UNMATCHED_R",
                            "Observed R handshake with no pending AR")
                    end
                    else begin
                        active_ar         = ar_q.pop_front();
                        active_read_valid = 1'b1;
                        active_r_data_q.delete();
                    end
                end

                if (active_read_valid) begin
                    expected_beats = int'(active_ar.len) + 1;
                    active_r_data_q.push_back(vif.rdata);

                    beat_idx = active_r_data_q.size() - 1;

                    if ((beat_idx + 1) < expected_beats) begin
                        if (vif.rlast) begin
                            `uvm_error("AXI_HOST_MON/EARLY_RLAST",
                                $sformatf("Observed early RLAST for AR addr=0x%08h len=%0d at beat=%0d",
                                    active_ar.addr, active_ar.len, beat_idx))
                        end
                    end
                    else if ((beat_idx + 1) == expected_beats) begin
                        if (!vif.rlast) begin
                            `uvm_error("AXI_HOST_MON/MISSING_RLAST",
                                $sformatf("Missing RLAST on final R beat for AR addr=0x%08h len=%0d",
                                    active_ar.addr, active_ar.len))
                        end

                        // Preserve the existing single-beat INCR
                        // monitor representation for legacy traffic.
                        if ((active_ar.len == 8'd0) &&
                            (active_ar.burst == 2'b01)) begin
                            publish_read_item(
                                active_ar,
                                active_r_data_q[0]
                            );
                        end
                        else begin
                            read_data_vec = new[active_r_data_q.size()];
                            for (beat_idx = 0;
                                 beat_idx < active_r_data_q.size();
                                 beat_idx++) begin
                                read_data_vec[beat_idx] =
                                    active_r_data_q[beat_idx];
                            end

                            item = build_raw_read_burst_item(
                                active_ar,
                                read_data_vec
                            );
                            publish_prebuilt_read_item(item);
                        end

                        active_read_valid = 1'b0;
                        active_r_data_q.delete();
                    end
                    else begin
                        `uvm_error("AXI_HOST_MON/EXTRA_R",
                            $sformatf("Observed more than LEN+1 R beats for AR addr=0x%08h len=%0d",
                                active_ar.addr, active_ar.len))
                        active_read_valid = 1'b0;
                        active_r_data_q.delete();
                    end
                end
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // Report phase
    // ------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        if (enable_log) begin
            `uvm_info("AXI_HOST_MON",
                $sformatf("Observed host traffic summary: writes=%0d reads=%0d dropped_on_reset=%0d",
                    observed_write_count, observed_read_count, dropped_on_reset_count),
                UVM_LOW)
        end
    endfunction

endclass

`endif
