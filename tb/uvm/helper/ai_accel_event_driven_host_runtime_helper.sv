// File: tb/uvm/helper/ai_accel_event_driven_host_runtime_helper.sv
`ifndef AI_ACCEL_EVENT_DRIVEN_HOST_RUNTIME_HELPER_SV
`define AI_ACCEL_EVENT_DRIVEN_HOST_RUNTIME_HELPER_SV

// ============================================================
// P23B event-driven host runtime helper / driver-style API
//
// Scope:
//   - TB/UVM helper only.
//   - Builds a driver-style API on top of the existing P19/P20/P21
//     queue CSR model and the P22 event notification CSR window.
//   - Uses the existing ai_accel_csr_access_helper for AXI-Lite CSR
//     access and the existing ai_accel_subsys_ctrl_if memory arrays
//     for host-visible SQ/CQ memory modeling.
//
// This helper does not add RTL, a standalone event CSR block, a
// standalone event interface, a standalone UVM top, or a new sim flow.
// ============================================================

class ai_accel_event_driven_host_runtime_helper extends uvm_object;
    `uvm_object_utils(ai_accel_event_driven_host_runtime_helper)

    typedef virtual ai_accel_subsys_ctrl_if ctrl_vif_t;

    localparam int unsigned P23_DEFAULT_TIMEOUT_CYCLES = 200000;
    localparam int unsigned P23_SQ_ENTRY_BYTES         = 64;
    localparam int unsigned P23_CQ_ENTRY_BYTES         = 64;

    localparam logic [31:0] P23_CMD_FETCH_RECIPE_ENABLE_COMPLETION = 32'h0000_0303;
    localparam logic [31:0] P23_COMP_FLAGS_ENABLE                  = 32'h0000_0001;

    localparam logic [31:0] P23_QUEUE_CONTROL_SINGLE = 32'h0000_0005; // enable + stop_on_error
    localparam logic [31:0] P23_QUEUE_CONTROL_DRAIN  = 32'h0000_0007; // enable + run_until_empty + stop_on_error

    localparam logic [31:0] P23_EVENT_CONTROL_IRQ_SNAPSHOT = 32'h0000_0005; // global_irq_enable + capture_snapshots
    localparam logic [31:0] P23_EVENT_CMD_CLEAR_ALL        = 32'h0000_0101; // clear_pending + clear_counters

    typedef struct {
        logic [31:0] sq_base;
        logic [31:0] sq_depth;
        logic [31:0] sq_head;
        logic [31:0] sq_tail;
        logic [31:0] sq_stride;
        logic [31:0] cq_base;
        logic [31:0] cq_depth;
        logic [31:0] cq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_stride;
        logic [31:0] queue_control;
    } p23_queue_cfg_t;

    typedef struct {
        logic [31:0] control;
        logic [31:0] user_tag;
        logic [31:0] desc_base;
        logic [31:0] desc_count;
        logic [31:0] desc_stride;
        logic [31:0] completion_flags;
        logic [31:0] timeout_cycles;
    } p23_sq_cmd_t;

    typedef struct {
        logic [31:0] commit_word;
        logic [31:0] status_flags;
        logic [31:0] first_user_tag;
        logic [31:0] last_user_tag;
        logic [31:0] counts;
        logic [31:0] desc_fetch_done;
        logic [31:0] desc_fetch_error;
        logic [31:0] desc_fetch_reject;
        logic [31:0] recipe_done;
        logic [31:0] recipe_error;
        logic [31:0] recipe_reject;
        logic [31:0] slot_mask_summary;
        logic [31:0] perf_busy_cycles;
        logic [31:0] perf_mac_count;
        logic [31:0] perf_output_count;
        logic [31:0] error_detail;
    } p23_cq_record_t;

    typedef struct {
        logic [31:0] pending;
        logic [31:0] status;
        logic [31:0] last_cause;
        logic [31:0] event_count;
        logic [31:0] irq_count;
        logic [31:0] snapshot0;
        logic [31:0] snapshot1;
        logic [31:0] cq_threshold;
    } p23_event_snapshot_t;

    ai_accel_csr_access_helper csr;
    ctrl_vif_t                 ctrl_vif;

    function new(string name = "ai_accel_event_driven_host_runtime_helper");
        super.new(name);
    endfunction

    function void set_csr(ai_accel_csr_access_helper csr_h);
        csr = csr_h;
    endfunction

    function void set_ctrl_vif(ctrl_vif_t ctrl_vif_h);
        ctrl_vif = ctrl_vif_h;
    endfunction

    function void check_ready(string where = "");
        if (csr == null) begin
            `uvm_fatal("P23_HOST_RT/NOCSR",
                $sformatf("%s%sCSR helper handle is not set",
                    (where.len() == 0) ? "" : where,
                    (where.len() == 0) ? "" : ": "))
        end

        if (ctrl_vif == null) begin
            `uvm_fatal("P23_HOST_RT/NOVIF",
                $sformatf("%s%svirtual ai_accel_subsys_ctrl_if is not set",
                    (where.len() == 0) ? "" : where,
                    (where.len() == 0) ? "" : ": "))
        end
    endfunction

    // ------------------------------------------------------------
    // Queue/event mask helpers
    // ------------------------------------------------------------
    function automatic logic [31:0] event_bit(input int unsigned bit_idx);
        return (32'h0000_0001 << bit_idx);
    endfunction

    function automatic logic [31:0] queue_completion_event_mask();
        return event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_COMPLETED) |
               event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_NOT_EMPTY);
    endfunction

    function automatic logic [31:0] queue_terminal_event_mask();
        return event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED) |
               event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_STOPPED) |
               event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_ERROR);
    endfunction

    function automatic logic [31:0] runtime_event_mask();
        return event_bit(ai_accel_csr_access_helper::P22_EVENT_RUNTIME_DOORBELL) |
               event_bit(ai_accel_csr_access_helper::P22_EVENT_RUNTIME_CONSUMED);
    endfunction

    function automatic void make_default_queue_cfg(
        output p23_queue_cfg_t cfg,
        input  logic [31:0]    sq_base,
        input  logic [31:0]    cq_base,
        input  logic [31:0]    depth,
        input  bit             run_until_empty = 1'b1
    );
    begin
        cfg.sq_base       = sq_base;
        cfg.sq_depth      = depth;
        cfg.sq_head       = 32'h0000_0000;
        cfg.sq_tail       = 32'h0000_0000;
        cfg.sq_stride     = 32'(P23_SQ_ENTRY_BYTES);
        cfg.cq_base       = cq_base;
        cfg.cq_depth      = depth;
        cfg.cq_head       = 32'h0000_0000;
        cfg.cq_tail       = 32'h0000_0000;
        cfg.cq_stride     = 32'(P23_CQ_ENTRY_BYTES);
        cfg.queue_control = run_until_empty ? P23_QUEUE_CONTROL_DRAIN : P23_QUEUE_CONTROL_SINGLE;
    end
    endfunction

    function automatic void make_fetch_recipe_cmd(
        output p23_sq_cmd_t cmd,
        input  logic [31:0] desc_base,
        input  logic [31:0] desc_count,
        input  logic [31:0] desc_stride,
        input  logic [31:0] user_tag,
        input  bit          enable_completion = 1'b1,
        input  bit          stop_after_this   = 1'b0
    );
    begin
        cmd.control          = P23_CMD_FETCH_RECIPE_ENABLE_COMPLETION;
        cmd.control[9]       = stop_after_this;
        if (!enable_completion) begin
            cmd.control[8]   = 1'b0;
        end
        cmd.user_tag         = user_tag;
        cmd.desc_base        = desc_base;
        cmd.desc_count       = desc_count;
        cmd.desc_stride      = desc_stride;
        cmd.completion_flags = enable_completion ? P23_COMP_FLAGS_ENABLE : 32'h0000_0000;
        cmd.timeout_cycles   = 32'h0000_0000;
    end
    endfunction

    // ------------------------------------------------------------
    // Host-visible memory helpers
    // ------------------------------------------------------------
    task automatic write_src_byte(input int unsigned byte_addr,
                                  input logic [7:0] value);
    begin
        check_ready("write_src_byte");
        ctrl_vif.dma_src_mem[byte_addr] = value;
    end
    endtask

    task automatic write_dst_byte(input int unsigned byte_addr,
                                  input logic [7:0] value);
    begin
        check_ready("write_dst_byte");
        ctrl_vif.dma_dst_mem[byte_addr] = value;
    end
    endtask

    task automatic read_dst_byte(input  int unsigned byte_addr,
                                 output logic [7:0] value);
    begin
        check_ready("read_dst_byte");
        value = ctrl_vif.dma_dst_mem[byte_addr];
    end
    endtask

    task automatic write_src_word_le(input int unsigned byte_addr,
                                     input logic [31:0] value);
    begin
        write_src_byte(byte_addr + 0, value[7:0]);
        write_src_byte(byte_addr + 1, value[15:8]);
        write_src_byte(byte_addr + 2, value[23:16]);
        write_src_byte(byte_addr + 3, value[31:24]);
    end
    endtask

    task automatic write_dst_word_le(input int unsigned byte_addr,
                                     input logic [31:0] value);
    begin
        write_dst_byte(byte_addr + 0, value[7:0]);
        write_dst_byte(byte_addr + 1, value[15:8]);
        write_dst_byte(byte_addr + 2, value[23:16]);
        write_dst_byte(byte_addr + 3, value[31:24]);
    end
    endtask

    task automatic read_dst_word_le(input  int unsigned byte_addr,
                                    output logic [31:0] value);
        logic [7:0] b0;
        logic [7:0] b1;
        logic [7:0] b2;
        logic [7:0] b3;
    begin
        read_dst_byte(byte_addr + 0, b0);
        read_dst_byte(byte_addr + 1, b1);
        read_dst_byte(byte_addr + 2, b2);
        read_dst_byte(byte_addr + 3, b3);
        value = {b3, b2, b1, b0};
    end
    endtask

    task automatic clear_src_region(input int unsigned base,
                                    input int unsigned byte_count);
    begin
        check_ready("clear_src_region");
        for (int unsigned i = 0; i < byte_count; i++) begin
            ctrl_vif.dma_src_mem[base + i] = 8'h00;
        end
    end
    endtask

    task automatic clear_dst_region(input int unsigned base,
                                    input int unsigned byte_count);
    begin
        check_ready("clear_dst_region");
        for (int unsigned i = 0; i < byte_count; i++) begin
            ctrl_vif.dma_dst_mem[base + i] = 8'h00;
        end
    end
    endtask

    task automatic clear_queue_memory(input p23_queue_cfg_t cfg);
    begin
        clear_src_region(cfg.sq_base, cfg.sq_depth * cfg.sq_stride);
        clear_dst_region(cfg.cq_base, cfg.cq_depth * cfg.cq_stride);
    end
    endtask

    // ------------------------------------------------------------
    // SQ/CQ operations
    // ------------------------------------------------------------
    task automatic write_sq_command(input p23_queue_cfg_t cfg,
                                    input int unsigned   entry_index,
                                    input p23_sq_cmd_t   cmd,
                                    input bit            commit_valid_last = 1'b1);
        int unsigned base;
    begin
        check_ready("write_sq_command");

        base = cfg.sq_base + ((entry_index % cfg.sq_depth) * cfg.sq_stride);

        if (!commit_valid_last) begin
            write_src_word_le(base + 16'h00, cmd.control);
        end

        write_src_word_le(base + 16'h04, cmd.user_tag);
        write_src_word_le(base + 16'h08, cmd.desc_base);
        write_src_word_le(base + 16'h0C, cmd.desc_count);
        write_src_word_le(base + 16'h10, cmd.desc_stride);
        write_src_word_le(base + 16'h14, cmd.completion_flags);
        write_src_word_le(base + 16'h18, cmd.timeout_cycles);

        for (int unsigned w = 7; w < 16; w++) begin
            write_src_word_le(base + (w * 4), 32'h0000_0000);
        end

        if (commit_valid_last) begin
            write_src_word_le(base + 16'h00, cmd.control);
        end

        `uvm_info("P23_HOST_RT/SQ",
            $sformatf("SQ[%0d] programmed at 0x%08h tag=0x%08h desc_base=0x%08h count=%0d stride=0x%08h control=0x%08h",
                entry_index,
                base,
                cmd.user_tag,
                cmd.desc_base,
                cmd.desc_count,
                cmd.desc_stride,
                cmd.control),
            UVM_MEDIUM)
    end
    endtask

    task automatic read_cq_record(input  p23_queue_cfg_t cfg,
                                  input  int unsigned   entry_index,
                                  output p23_cq_record_t rec);
        int unsigned base;
    begin
        check_ready("read_cq_record");

        base = cfg.cq_base + ((entry_index % cfg.cq_depth) * cfg.cq_stride);

        read_dst_word_le(base + 16'h00, rec.commit_word);
        read_dst_word_le(base + 16'h04, rec.status_flags);
        read_dst_word_le(base + 16'h08, rec.first_user_tag);
        read_dst_word_le(base + 16'h0C, rec.last_user_tag);
        read_dst_word_le(base + 16'h10, rec.counts);
        read_dst_word_le(base + 16'h14, rec.desc_fetch_done);
        read_dst_word_le(base + 16'h18, rec.desc_fetch_error);
        read_dst_word_le(base + 16'h1C, rec.desc_fetch_reject);
        read_dst_word_le(base + 16'h20, rec.recipe_done);
        read_dst_word_le(base + 16'h24, rec.recipe_error);
        read_dst_word_le(base + 16'h28, rec.recipe_reject);
        read_dst_word_le(base + 16'h2C, rec.slot_mask_summary);
        read_dst_word_le(base + 16'h30, rec.perf_busy_cycles);
        read_dst_word_le(base + 16'h34, rec.perf_mac_count);
        read_dst_word_le(base + 16'h38, rec.perf_output_count);
        read_dst_word_le(base + 16'h3C, rec.error_detail);
    end
    endtask

    task automatic wait_cq_commit(input  p23_queue_cfg_t cfg,
                                  input  int unsigned   entry_index,
                                  output p23_cq_record_t rec,
                                  input  int unsigned   timeout_cycles = P23_DEFAULT_TIMEOUT_CYCLES);
        int unsigned cnt;
    begin
        cnt = 0;
        forever begin
            read_cq_record(cfg, entry_index, rec);
            if (rec.commit_word[0]) begin
                `uvm_info("P23_HOST_RT/CQ",
                    $sformatf("CQ[%0d] commit observed after %0d poll(s): commit=0x%08h status=0x%08h tag=0x%08h",
                        entry_index,
                        cnt,
                        rec.commit_word,
                        rec.status_flags,
                        rec.first_user_tag),
                    UVM_MEDIUM)
                return;
            end

            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P23_HOST_RT/CQ_TIMEOUT",
                    $sformatf("CQ[%0d] commit timeout: last_commit=0x%08h",
                        entry_index,
                        rec.commit_word))
            end
            @(posedge ctrl_vif.clk);
        end
    end
    endtask

    task automatic consume_cq_entry(input p23_queue_cfg_t cfg,
                                    input int unsigned   entry_index,
                                    input bit            clear_commit_word = 1'b1);
        int unsigned base;
    begin
        check_ready("consume_cq_entry");

        base = cfg.cq_base + ((entry_index % cfg.cq_depth) * cfg.cq_stride);

        if (clear_commit_word) begin
            write_dst_word_le(base + 16'h00, 32'h0000_0000);
        end

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,
            32'(entry_index + 1)
        );

        `uvm_info("P23_HOST_RT/CQ",
            $sformatf("Consumed CQ[%0d], advanced CQ_HEAD to %0d", entry_index, entry_index + 1),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Queue CSR operations
    // ------------------------------------------------------------
    task automatic clear_queue_sticky();
        logic [31:0] cmd;
    begin
        check_ready("clear_queue_sticky");
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_CLEAR_DONE]  = 1'b1;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_CLEAR_ERROR] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_COMMAND, cmd);
    end
    endtask

    task automatic program_queue(input p23_queue_cfg_t cfg);
    begin
        check_ready("program_queue");

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_BASE,   cfg.sq_base);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_DEPTH,  cfg.sq_depth);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,   cfg.sq_head);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL,   cfg.sq_tail);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_STRIDE, cfg.sq_stride);

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_BASE,   cfg.cq_base);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_DEPTH,  cfg.cq_depth);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,   cfg.cq_head);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,   cfg.cq_tail);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_STRIDE, cfg.cq_stride);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CONTROL,   cfg.queue_control);

        `uvm_info("P23_HOST_RT/QUEUE_CFG",
            $sformatf("Queue cfg: SQ base=0x%08h depth=%0d head=%0d tail=%0d CQ base=0x%08h depth=%0d head=%0d tail=%0d control=0x%08h",
                cfg.sq_base,
                cfg.sq_depth,
                cfg.sq_head,
                cfg.sq_tail,
                cfg.cq_base,
                cfg.cq_depth,
                cfg.cq_head,
                cfg.cq_tail,
                cfg.queue_control),
            UVM_MEDIUM)
    end
    endtask

    task automatic ring_sq_tail(input logic [31:0] new_tail);
    begin
        check_ready("ring_sq_tail");
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_TAIL, new_tail);
        `uvm_info("P23_HOST_RT/DOORBELL",
            $sformatf("Published SQ_TAIL=%0d", new_tail),
            UVM_MEDIUM)
    end
    endtask

    task automatic start_queue();
        logic [31:0] cmd;
    begin
        check_ready("start_queue");
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_START] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_COMMAND, cmd);
        `uvm_info("P23_HOST_RT/QUEUE_START", "Issued CSR_QUEUE_COMMAND.START_QUEUE", UVM_MEDIUM)
    end
    endtask

    task automatic stop_queue();
        logic [31:0] cmd;
    begin
        check_ready("stop_queue");
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::QUEUE_CMD_STOP] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_COMMAND, cmd);
        `uvm_info("P23_HOST_RT/QUEUE_STOP", "Issued CSR_QUEUE_COMMAND.STOP_QUEUE", UVM_MEDIUM)
    end
    endtask

    task automatic wait_queue_cq_tail(input logic [31:0] expected_tail,
                                      input int unsigned timeout_cycles = P23_DEFAULT_TIMEOUT_CYCLES);
        logic [31:0] cq_tail;
        logic [31:0] status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        int unsigned cnt;
    begin
        check_ready("wait_queue_cq_tail");
        cnt = 0;

        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL, cq_tail);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);

            if ((error_status != 32'h0000_0000) || (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P23_HOST_RT/QUEUE_ERROR",
                    $sformatf("Queue error while waiting CQ_TAIL=%0d: status=0x%08h error=0x%08h reject=0x%08h",
                        expected_tail,
                        status,
                        error_status,
                        reject_status))
            end

            if (cq_tail == expected_tail) begin
                `uvm_info("P23_HOST_RT/QUEUE_WAIT",
                    $sformatf("Observed CQ_TAIL=%0d after %0d poll(s)", expected_tail, cnt),
                    UVM_MEDIUM)
                return;
            end

            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P23_HOST_RT/QUEUE_TIMEOUT",
                    $sformatf("Timeout waiting for CQ_TAIL=%0d, last CQ_TAIL=%0d status=0x%08h",
                        expected_tail,
                        cq_tail,
                        status))
            end
            @(posedge ctrl_vif.clk);
        end
    end
    endtask

    // ------------------------------------------------------------
    // P22 event operations
    // ------------------------------------------------------------
    task automatic read_event_snapshot(output p23_event_snapshot_t snap);
    begin
        check_ready("read_event_snapshot");
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_PENDING,      snap.pending);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_STATUS,       snap.status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_LAST_CAUSE,   snap.last_cause);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_COUNT,        snap.event_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_IRQ_COUNT,    snap.irq_count);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_SNAPSHOT0,    snap.snapshot0);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_SNAPSHOT1,    snap.snapshot1);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_CQ_THRESHOLD, snap.cq_threshold);
    end
    endtask

    task automatic clear_event_state();
    begin
        check_ready("clear_event_state");

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_PENDING,
            ai_accel_csr_access_helper::EVENT_VALID_MASK
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_COMMAND,
            P23_EVENT_CMD_CLEAR_ALL
        );

        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_ENABLE,  32'h0000_0000);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_CONTROL, 32'h0000_0004);
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_CQ_THRESHOLD, 32'h0000_0000);

        `uvm_info("P23_HOST_RT/EVENT_CLEAR", "Cleared P22 event pending/counters and disabled event IRQ", UVM_MEDIUM)
    end
    endtask

    task automatic arm_events(input logic [31:0] enable_mask,
                              input logic [31:0] cq_threshold = 32'h0000_0000,
                              input logic [31:0] control     = P23_EVENT_CONTROL_IRQ_SNAPSHOT);
    begin
        check_ready("arm_events");

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_CQ_THRESHOLD,
            cq_threshold
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_ENABLE,
            enable_mask & ai_accel_csr_access_helper::EVENT_VALID_MASK
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_CONTROL,
            control
        );

        `uvm_info("P23_HOST_RT/EVENT_ARM",
            $sformatf("Armed events enable_mask=0x%08h threshold=0x%08h control=0x%08h",
                enable_mask & ai_accel_csr_access_helper::EVENT_VALID_MASK,
                cq_threshold,
                control),
            UVM_MEDIUM)
    end
    endtask

    task automatic ack_events(input logic [31:0] ack_mask);
    begin
        check_ready("ack_events");
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_EVENT_PENDING,
            ack_mask & ai_accel_csr_access_helper::EVENT_VALID_MASK
        );

        `uvm_info("P23_HOST_RT/EVENT_ACK",
            $sformatf("W1C ack event_mask=0x%08h", ack_mask & ai_accel_csr_access_helper::EVENT_VALID_MASK),
            UVM_MEDIUM)
    end
    endtask

    task automatic wait_events(input  logic [31:0]          required_mask,
                               output p23_event_snapshot_t snap,
                               input  int unsigned         timeout_cycles = P23_DEFAULT_TIMEOUT_CYCLES,
                               input  bit                  require_irq_summary = 1'b1);
        int unsigned cnt;
    begin
        check_ready("wait_events");
        cnt = 0;

        forever begin
            read_event_snapshot(snap);

            if ((snap.pending & required_mask) == required_mask) begin
                if (require_irq_summary && ((snap.status & 32'h0000_0004) == 32'h0000_0000)) begin
                    `uvm_fatal("P23_HOST_RT/EVENT_NOIRQ",
                        $sformatf("Required events pending but IRQ summary not asserted: mask=0x%08h pending=0x%08h status=0x%08h",
                            required_mask,
                            snap.pending,
                            snap.status))
                end

                `uvm_info("P23_HOST_RT/EVENT_WAIT",
                    $sformatf("Observed event_mask=0x%08h after %0d poll(s): pending=0x%08h status=0x%08h last_cause=0x%08h event_count=%0d irq_count=%0d",
                        required_mask,
                        cnt,
                        snap.pending,
                        snap.status,
                        snap.last_cause,
                        snap.event_count,
                        snap.irq_count),
                    UVM_MEDIUM)
                return;
            end

            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P23_HOST_RT/EVENT_TIMEOUT",
                    $sformatf("Timeout waiting for event_mask=0x%08h: pending=0x%08h status=0x%08h last_cause=0x%08h",
                        required_mask,
                        snap.pending,
                        snap.status,
                        snap.last_cause))
            end
            @(posedge ctrl_vif.clk);
        end
    end
    endtask

    task automatic force_test_event();
        logic [31:0] cmd;
    begin
        check_ready("force_test_event");
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::EVENT_CMD_FORCE_TEST] = 1'b1;
        csr.write32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_COMMAND, cmd);
        `uvm_info("P23_HOST_RT/EVENT_FORCE", "Forced P22 TEST_EVENT", UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Driver-style composite operations for later P23C/P23D/P23E
    // tests.  These remain thin wrappers around the primitive APIs
    // above so individual tests can still inspect intermediate state.
    // ------------------------------------------------------------
    task automatic initialize_runtime(input p23_queue_cfg_t cfg,
                                      input logic [31:0] event_enable_mask,
                                      input bit          clear_mem = 1'b1);
    begin
        check_ready("initialize_runtime");

        clear_queue_sticky();
        clear_event_state();

        if (clear_mem) begin
            clear_queue_memory(cfg);
        end

        program_queue(cfg);
        arm_events(event_enable_mask);
    end
    endtask

    task automatic submit_command_and_doorbell(input p23_queue_cfg_t cfg,
                                               input int unsigned   entry_index,
                                               input p23_sq_cmd_t   cmd,
                                               input logic [31:0]   new_tail);
    begin
        write_sq_command(cfg, entry_index, cmd, 1'b1);
        ring_sq_tail(new_tail);
    end
    endtask

    task automatic event_driven_consume_one_cq(input  p23_queue_cfg_t        cfg,
                                               input  int unsigned          entry_index,
                                               input  logic [31:0]          event_mask,
                                               output p23_cq_record_t       rec,
                                               output p23_event_snapshot_t  snap,
                                               input  bit                   clear_cq_commit = 1'b1);
    begin
        wait_events(event_mask, snap);
        wait_cq_commit(cfg, entry_index, rec);
        consume_cq_entry(cfg, entry_index, clear_cq_commit);
        ack_events(event_mask);
    end
    endtask

endclass

`endif
