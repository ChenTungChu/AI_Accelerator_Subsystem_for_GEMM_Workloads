// File: tb/uvm/test/ai_accel_subsys_csr_event_driven_cq_full_stop_error_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_EVENT_DRIVEN_CQ_FULL_STOP_ERROR_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_EVENT_DRIVEN_CQ_FULL_STOP_ERROR_SMOKE_TEST_SV

// ============================================================
// P23F event-driven CQ-full recovery / stopped / error handling
// smoke
//
// Scope:
//   - Reuses the validated P21 CQ-full recovery and STOP_QUEUE live
//     service behavior, and the P22 event notification layer.
//   - Uses the P23B event-driven host runtime helper as the host-side
//     driver-style API.
//   - CQ-full subcase: CQ_DEPTH=1, host appends SQ[1] while SQ[0]
//     is active, hardware stalls at the command boundary after CQ[0]
//     fills, host consumes CQ[0] by advancing CQ_HEAD, and hardware
//     resumes without a second START_QUEUE.
//   - STOP subcase: host appends SQ[1] while SQ[0] is active, then
//     writes STOP_QUEUE.  Hardware completes SQ[0], reports stopped,
//     does not consume SQ[1] in the same live-service session, and a
//     later START_QUEUE consumes the still-pending SQ[1].
//   - ERROR subcase: host publishes an invalid SQ command and verifies
//     event-driven QUEUE_ERROR notification and sticky cleanup.
//
// This is UVM/helper-only validation.  It does not add RTL, standalone
// event CSR blocks, standalone event interfaces, standalone UVM tops,
// new sim flows, or BRAM/GEMM/DMA/frontend datapath changes.
// ============================================================

class ai_accel_subsys_csr_event_driven_cq_full_stop_error_smoke_test
    extends ai_accel_subsys_csr_event_driven_runtime_append_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_event_driven_cq_full_stop_error_smoke_test)

    localparam int unsigned P23F_QUEUE_DEPTH       = 4;
    localparam int unsigned P23F_CQ_DEPTH_ONE      = 1;
    localparam int unsigned P23F_DESC_STRIDE       = 32'h0000_0080;

    localparam int unsigned P23F_CQFULL_SQ_BASE    = 32'h0000_0700;
    localparam int unsigned P23F_CQFULL_CQ_BASE    = 32'h0000_0800;
    localparam int unsigned P23F_CQFULL_DESC0_BASE = 32'h0000_0300;
    localparam int unsigned P23F_CQFULL_DESC1_BASE = 32'h0000_0400;

    localparam int unsigned P23F_STOP_SQ_BASE      = 32'h0000_0900;
    localparam int unsigned P23F_STOP_CQ_BASE      = 32'h0000_0A00;
    localparam int unsigned P23F_STOP_DESC0_BASE   = 32'h0000_0500;
    localparam int unsigned P23F_STOP_DESC1_BASE   = 32'h0000_0600;

    localparam int unsigned P23F_ERR_SQ_BASE       = 32'h0000_0B00;
    localparam int unsigned P23F_ERR_CQ_BASE       = 32'h0000_0C00;

    localparam logic [31:0] P23F_CQFULL_CMD0_TAG   = 32'hD23F_0000;
    localparam logic [31:0] P23F_CQFULL_CMD1_TAG   = 32'hD23F_0001;
    localparam logic [31:0] P23F_CQFULL_DESC0_TAG0 = 32'hD23F_1000;
    localparam logic [31:0] P23F_CQFULL_DESC0_TAG1 = 32'hD23F_1001;
    localparam logic [31:0] P23F_CQFULL_DESC1_TAG0 = 32'hD23F_2000;
    localparam logic [31:0] P23F_CQFULL_DESC1_TAG1 = 32'hD23F_2001;

    localparam logic [31:0] P23F_STOP_CMD0_TAG     = 32'hD23F_3000;
    localparam logic [31:0] P23F_STOP_CMD1_TAG     = 32'hD23F_3001;
    localparam logic [31:0] P23F_STOP_DESC0_TAG0   = 32'hD23F_4000;
    localparam logic [31:0] P23F_STOP_DESC0_TAG1   = 32'hD23F_4001;
    localparam logic [31:0] P23F_STOP_DESC1_TAG0   = 32'hD23F_5000;
    localparam logic [31:0] P23F_STOP_DESC1_TAG1   = 32'hD23F_5001;

    localparam logic [31:0] P23F_ERR_CMD_TAG       = 32'hD23F_E000;

    function new(string name = "ai_accel_subsys_csr_event_driven_cq_full_stop_error_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task automatic expect_p23f_eq32(input string       name,
                                    input logic [31:0] actual,
                                    input logic [31:0] expected);
    begin
        if (actual !== expected) begin
            `uvm_fatal("P23F_HOST_RT/MISMATCH",
                $sformatf("%s mismatch: actual=0x%08h expected=0x%08h",
                    name,
                    actual,
                    expected))
        end

        `uvm_info("P23F_HOST_RT/CHECK",
            $sformatf("%s PASS: 0x%08h", name, actual),
            UVM_LOW)
    end
    endtask

    task automatic program_p23f_descriptor_table(
        input int unsigned             desc_base,
        input logic [31:0]             first_tag,
        input logic [31:0]             second_tag,
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             a_bytes,
        input int unsigned             b_bytes,
        input int unsigned             c_bytes
    );
    begin
        program_memory_descriptor(
            desc_base + (0 * P23F_DESC_STRIDE),
            SLOT0_CONTROL_DMA_HOST_READBACK,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            first_tag
        );

        program_memory_descriptor(
            desc_base + (1 * P23F_DESC_STRIDE),
            SLOT1_CONTROL_DMA_DMA_STORE,
            profile_item,
            a_bytes,
            b_bytes,
            c_bytes,
            second_tag
        );
    end
    endtask

    task automatic expect_p23f_event_snapshot(
        input string                                                     case_name,
        input ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t snap,
        input logic [31:0]                                               required_mask,
        input bit                                                        require_irq = 1'b1
    );
    begin
        if ((snap.pending & required_mask) !== required_mask) begin
            `uvm_fatal("P23F_HOST_RT/EVENT_MISSING",
                $sformatf("%s missing required events: pending=0x%08h required=0x%08h status=0x%08h",
                    case_name,
                    snap.pending,
                    required_mask,
                    snap.status))
        end

        if (require_irq && ((snap.status & 32'h0000_0004) == 32'h0000_0000)) begin
            `uvm_fatal("P23F_HOST_RT/EVENT_NOIRQ",
                $sformatf("%s expected IRQ summary before ack: pending=0x%08h status=0x%08h",
                    case_name,
                    snap.pending,
                    snap.status))
        end

        if (snap.event_count == 32'h0000_0000) begin
            `uvm_fatal("P23F_HOST_RT/EVENT_COUNT_ZERO",
                $sformatf("%s expected EVENT_COUNT to increment", case_name))
        end

        `uvm_info("P23F_HOST_RT/EVENT",
            $sformatf("%s event snapshot PASS: pending=0x%08h required=0x%08h status=0x%08h last_cause=0x%08h count=%0d irq_count=%0d snapshot0=0x%08h snapshot1=0x%08h",
                case_name,
                snap.pending,
                required_mask,
                snap.status,
                snap.last_cause,
                snap.event_count,
                snap.irq_count,
                snap.snapshot0,
                snap.snapshot1),
            UVM_MEDIUM)
    end
    endtask

    task automatic wait_p23f_cq_full_stall(
        input logic [31:0] expected_last_tag,
        input int unsigned timeout_cycles
    );
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] sq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
        logic [31:0] cq_space;
        logic [31:0] last_tag;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS,        status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS,   done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,  error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,       sq_head);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,       cq_tail);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY,  cq_occ);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_SPACE,      cq_space);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG,  last_tag);

            if ((error_status != 32'h0000_0000) ||
                (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P23F_HOST_RT/CQ_FULL_ERROR",
                    $sformatf("CQ full should stall, not error: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h cq_space=0x%08h last_tag=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        cq_space,
                        last_tag))
            end

            if ((sq_head == 32'h0000_0001) &&
                (cq_tail == 32'h0000_0001) &&
                (cq_occ  == 32'h0000_0001) &&
                (cq_space == 32'h0000_0000) &&
                (last_tag == expected_last_tag)) begin
                `uvm_info("P23F_HOST_RT/CQ_FULL",
                    $sformatf("CQ full stall observed: status=0x%08h done=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h CQ_SPACE=0x%08h last_tag=0x%08h",
                        status,
                        done_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        cq_space,
                        last_tag),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P23F_HOST_RT/CQ_FULL_TIMEOUT",
                    $sformatf("Timeout waiting CQ-full stall: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h cq_space=0x%08h last_tag=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        cq_space,
                        last_tag))
            end
        end
    end
    endtask

    task automatic check_p23f_cqfull_final_state(input logic [31:0] expected_last_tag);
        logic [31:0] sq_head;
        logic [31:0] cq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
        logic [31:0] done_status;
        logic [31:0] last_tag;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,      sq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_HEAD,      cq_head);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,      cq_tail);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS,  done_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);

        expect_p23f_eq32("CQ-full SQ_HEAD after recovery", sq_head, 32'h0000_0002);
        expect_p23f_eq32("CQ-full CQ_HEAD before second consume", cq_head, 32'h0000_0001);
        expect_p23f_eq32("CQ-full CQ_TAIL after second commit", cq_tail, 32'h0000_0002);
        expect_p23f_eq32("CQ-full CQ_OCC before second consume", cq_occ, 32'h0000_0001);
        expect_p23f_eq32("CQ-full QUEUE_LAST_CMD_TAG", last_tag, expected_last_tag);

        if (!done_status[1] || !done_status[2]) begin
            `uvm_fatal("P23F_HOST_RT/CQ_FULL_DONE",
                $sformatf("Expected QUEUE_DRAINED and COMMAND_COMPLETED after CQ-head recovery, done_status=0x%08h",
                    done_status))
        end

        `uvm_info("P23F_HOST_RT/CQ_FULL",
            $sformatf("CQ-full recovery final queue state PASS: done_status=0x%08h", done_status),
            UVM_LOW)
    end
    endtask

    task automatic wait_p23f_stopped_after_first_command(
        input logic [31:0] expected_last_tag,
        input int unsigned timeout_cycles
    );
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] sq_head;
        logic [31:0] cq_tail;
        logic [31:0] cq_occ;
        logic [31:0] last_tag;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS,        status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS,   done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,  error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,       sq_head);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,       cq_tail);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY,  cq_occ);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG,  last_tag);

            if ((error_status != 32'h0000_0000) ||
                (reject_status != 32'h0000_0000)) begin
                `uvm_fatal("P23F_HOST_RT/STOP_ERROR",
                    $sformatf("STOP_QUEUE should stop cleanly, not error: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h last_tag=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        last_tag))
            end

            if ((sq_head == 32'h0000_0001) &&
                (cq_tail == 32'h0000_0001) &&
                (cq_occ  == 32'h0000_0001) &&
                (last_tag == expected_last_tag) &&
                done_status[3]) begin
                repeat (80) @(posedge csr_vif.clk);

                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_SQ_HEAD,      sq_head);
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,      cq_tail);
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_OCCUPANCY, cq_occ);
                csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG, last_tag);

                if ((sq_head !== 32'h0000_0001) ||
                    (cq_tail !== 32'h0000_0001) ||
                    (cq_occ  !== 32'h0000_0001) ||
                    (last_tag !== expected_last_tag)) begin
                    `uvm_fatal("P23F_HOST_RT/STOP_AUTO_CONTINUE",
                        $sformatf("STOP_QUEUE failed to suppress auto-continue: sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h last_tag=0x%08h",
                            sq_head,
                            cq_tail,
                            cq_occ,
                            last_tag))
                end

                `uvm_info("P23F_HOST_RT/STOPPED",
                    $sformatf("STOP_QUEUE event-driven stop observed: status=0x%08h done=0x%08h SQ_HEAD=0x%08h CQ_TAIL=0x%08h CQ_OCC=0x%08h last_tag=0x%08h",
                        status,
                        done_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        last_tag),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P23F_HOST_RT/STOP_TIMEOUT",
                    $sformatf("Timeout waiting STOP_QUEUE event-driven stop: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h sq_head=0x%08h cq_tail=0x%08h cq_occ=0x%08h last_tag=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        sq_head,
                        cq_tail,
                        cq_occ,
                        last_tag))
            end
        end
    end
    endtask

    task automatic wait_p23f_queue_error(input int unsigned timeout_cycles);
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] detail;
        logic [31:0] last_tag;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_STATUS,        status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_DONE_STATUS,   done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,  error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_DETAIL,  detail);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_LAST_CMD_TAG,  last_tag);

            if (error_status != 32'h0000_0000) begin
                `uvm_info("P23F_HOST_RT/ERROR",
                    $sformatf("Queue validation error observed: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h detail=0x%08h last_tag=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        detail,
                        last_tag),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > timeout_cycles) begin
                `uvm_fatal("P23F_HOST_RT/ERROR_TIMEOUT",
                    $sformatf("Timeout waiting queue validation error: status=0x%08h done=0x%08h error=0x%08h reject=0x%08h detail=0x%08h last_tag=0x%08h",
                        status,
                        done_status,
                        error_status,
                        reject_status,
                        detail,
                        last_tag))
            end
        end
    end
    endtask

    task automatic check_p23f_event_cleanup(
        input string       case_name,
        input logic [31:0] ack_mask
    );
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t snap;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_PENDING, snap.pending);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_STATUS,  snap.status);

        if ((snap.pending & ack_mask) != 32'h0000_0000) begin
            `uvm_fatal("P23F_HOST_RT/EVENT_ACK_FAIL",
                $sformatf("%s acked event bits still pending: pending=0x%08h ack_mask=0x%08h",
                    case_name,
                    snap.pending,
                    ack_mask))
        end

        if ((snap.status & 32'h0000_0007) != 32'h0000_0000) begin
            `uvm_fatal("P23F_HOST_RT/EVENT_STATUS_AFTER_ACK",
                $sformatf("%s pending/eligible/irq status bits still set after ack: status=0x%08h",
                    case_name,
                    snap.status))
        end

        `uvm_info("P23F_HOST_RT/CHECK",
            $sformatf("%s event cleanup PASS: pending=0x%08h status=0x%08h",
                case_name,
                snap.pending,
                snap.status),
            UVM_MEDIUM)
    end
    endtask



    task automatic check_p23f_event_ack_bits_only(
        input string       case_name,
        input logic [31:0] ack_mask
    );
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t snap;
    begin
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_PENDING, snap.pending);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_EVENT_STATUS,  snap.status);

        if ((snap.pending & ack_mask) != 32'h0000_0000) begin
            `uvm_fatal("P23F_HOST_RT/EVENT_ACK_FAIL",
                $sformatf("%s acked event bits still pending: pending=0x%08h ack_mask=0x%08h",
                    case_name,
                    snap.pending,
                    ack_mask))
        end

        `uvm_info("P23F_HOST_RT/CHECK",
            $sformatf("%s event ack-bits cleanup PASS: pending=0x%08h status=0x%08h ack_mask=0x%08h",
                case_name,
                snap.pending,
                snap.status,
                ack_mask),
            UVM_MEDIUM)
    end
    endtask

    task automatic p23f_case_cq_full_recovery(
        input ai_accel_event_driven_host_runtime_helper rt,
        input ai_accel_subsys_seq_item                 profile_item
    );
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t    cmd0;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t    cmd1;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec0;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec1;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t snap;
        logic [31:0] event_enable;
        logic [31:0] event_required;
        logic [31:0] ack_mask;
    begin
        `uvm_info("P23F_CASE/CQ_FULL",
            "Starting event-driven CQ-full stall and CQ_HEAD recovery case",
            UVM_MEDIUM)

        rt.make_default_queue_cfg(
            cfg,
            32'(P23F_CQFULL_SQ_BASE),
            32'(P23F_CQFULL_CQ_BASE),
            32'(P23F_QUEUE_DEPTH),
            1'b1
        );
        cfg.cq_depth = 32'(P23F_CQ_DEPTH_ONE);

        rt.make_fetch_recipe_cmd(cmd0, 32'(P23F_CQFULL_DESC0_BASE), 32'h0000_0002, 32'(P23F_DESC_STRIDE), P23F_CQFULL_CMD0_TAG, 1'b1, 1'b0);
        rt.make_fetch_recipe_cmd(cmd1, 32'(P23F_CQFULL_DESC1_BASE), 32'h0000_0002, 32'(P23F_DESC_STRIDE), P23F_CQFULL_CMD1_TAG, 1'b1, 1'b0);

        event_enable = rt.queue_completion_event_mask() |
                       rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED) |
                       rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_FULL_STALL) |
                       rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_CQ_SPACE_RECOVERED);

        csr_queue_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        rt.initialize_runtime(cfg, event_enable, 1'b1);

        csr_check_recipe_idle_ready("before P23F CQ-full START");

        rt.write_sq_command(cfg, 0, cmd0, 1'b1);
        rt.ring_sq_tail(32'h0000_0001);
        rt.start_queue();

        wait_p23e_queue_active_before_runtime_append(done_timeout_cycles);
        rt.write_sq_command(cfg, 1, cmd1, 1'b1);
        rt.ring_sq_tail(32'h0000_0002);

        wait_p23f_cq_full_stall(P23F_CQFULL_CMD0_TAG, done_timeout_cycles * 4);
        event_required = rt.queue_completion_event_mask();
        rt.wait_events(event_required, snap, done_timeout_cycles * 4, 1'b1);
        expect_p23f_event_snapshot("CQ full first completion", snap, event_required, 1'b1);
        ack_mask = snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;

        rt.wait_cq_commit(cfg, 0, rec0, done_timeout_cycles * 2);
        check_p23d_cq_record(0, rec0, profile_item, P23F_CQFULL_DESC0_TAG0, P23F_CQFULL_DESC0_TAG1);
        rt.consume_cq_entry(cfg, 0, 1'b1);
        rt.ack_events(ack_mask);
        check_p23f_event_ack_bits_only("CQ full first completion", ack_mask);

        event_required = rt.queue_completion_event_mask() |
                         rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);
        rt.wait_events(event_required, snap, done_timeout_cycles * 8, 1'b1);
        expect_p23f_event_snapshot("CQ full recovery final drain", snap, event_required, 1'b1);

        rt.wait_cq_commit(cfg, 1, rec1, done_timeout_cycles * 4);
        check_p23d_cq_record(1, rec1, profile_item, P23F_CQFULL_DESC1_TAG0, P23F_CQFULL_DESC1_TAG1);
        check_p23f_cqfull_final_state(P23F_CQFULL_CMD1_TAG);

        ack_mask = snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.consume_cq_entry(cfg, 1, 1'b1);
        rt.ack_events(ack_mask);
        check_p23f_event_cleanup("CQ full recovery final drain", ack_mask);

        `uvm_info("P23F_HOST_RT/CQ_FULL_PASS",
            "Event-driven CQ-full recovery case PASS: CQ_HEAD recovery resumed queue service without a second START_QUEUE",
            UVM_MEDIUM)
    end
    endtask

    task automatic p23f_case_stop_queue(
        input ai_accel_event_driven_host_runtime_helper rt,
        input ai_accel_subsys_seq_item                 profile_item
    );
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t    cmd0;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t    cmd1;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec0;
        ai_accel_event_driven_host_runtime_helper::p23_cq_record_t rec1;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t snap;
        logic [31:0] event_enable;
        logic [31:0] event_required;
        logic [31:0] ack_mask;
        logic [31:0] cq_slot1_commit;
    begin
        `uvm_info("P23F_CASE/STOPPED",
            "Starting event-driven STOP_QUEUE stopped/restart case",
            UVM_MEDIUM)

        rt.make_default_queue_cfg(
            cfg,
            32'(P23F_STOP_SQ_BASE),
            32'(P23F_STOP_CQ_BASE),
            32'(P23F_QUEUE_DEPTH),
            1'b1
        );

        rt.make_fetch_recipe_cmd(cmd0, 32'(P23F_STOP_DESC0_BASE), 32'h0000_0002, 32'(P23F_DESC_STRIDE), P23F_STOP_CMD0_TAG, 1'b1, 1'b0);
        rt.make_fetch_recipe_cmd(cmd1, 32'(P23F_STOP_DESC1_BASE), 32'h0000_0002, 32'(P23F_DESC_STRIDE), P23F_STOP_CMD1_TAG, 1'b1, 1'b0);

        event_enable = rt.queue_completion_event_mask() |
                       rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_STOPPED) |
                       rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);

        csr_queue_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        rt.initialize_runtime(cfg, event_enable, 1'b1);

        csr_check_recipe_idle_ready("before P23F STOP_QUEUE START");

        rt.write_sq_command(cfg, 0, cmd0, 1'b1);
        rt.ring_sq_tail(32'h0000_0001);
        rt.start_queue();

        wait_p23e_queue_active_before_runtime_append(done_timeout_cycles);
        rt.write_sq_command(cfg, 1, cmd1, 1'b1);
        rt.ring_sq_tail(32'h0000_0002);
        rt.stop_queue();

        event_required = rt.queue_completion_event_mask() |
                         rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_STOPPED);
        rt.wait_events(event_required, snap, done_timeout_cycles * 8, 1'b1);
        expect_p23f_event_snapshot("STOP_QUEUE stopped", snap, event_required, 1'b1);

        wait_p23f_stopped_after_first_command(P23F_STOP_CMD0_TAG, done_timeout_cycles * 4);
        rt.wait_cq_commit(cfg, 0, rec0, done_timeout_cycles * 2);
        check_p23d_cq_record(0, rec0, profile_item, P23F_STOP_DESC0_TAG0, P23F_STOP_DESC0_TAG1);

        rt.read_dst_word_le(P23F_STOP_CQ_BASE + (1 * 64), cq_slot1_commit);
        expect_p23f_eq32("STOP_QUEUE CQ[1] remains invalid before restart", cq_slot1_commit, 32'h0000_0000);

        ack_mask = snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.consume_cq_entry(cfg, 0, 1'b1);
        rt.ack_events(ack_mask);
        check_p23f_event_cleanup("STOP_QUEUE stopped", ack_mask);

        csr_queue_clear_sticky_status();
        rt.start_queue();

        event_required = rt.queue_completion_event_mask() |
                         rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_DRAINED);
        rt.wait_events(event_required, snap, done_timeout_cycles * 8, 1'b1);
        expect_p23f_event_snapshot("STOP_QUEUE restart pending SQ[1]", snap, event_required, 1'b1);
        rt.wait_cq_commit(cfg, 1, rec1, done_timeout_cycles * 4);
        check_p23d_cq_record(1, rec1, profile_item, P23F_STOP_DESC1_TAG0, P23F_STOP_DESC1_TAG1);

        ack_mask = snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.consume_cq_entry(cfg, 1, 1'b1);
        rt.ack_events(ack_mask);
        check_p23f_event_cleanup("STOP_QUEUE restart pending SQ[1]", ack_mask);

        `uvm_info("P23F_HOST_RT/STOP_PASS",
            "Event-driven STOP_QUEUE case PASS: SQ[1] remained pending until host restarted queue service",
            UVM_MEDIUM)
    end
    endtask

    task automatic p23f_case_error_event(
        input ai_accel_event_driven_host_runtime_helper rt
    );
        ai_accel_event_driven_host_runtime_helper::p23_queue_cfg_t cfg;
        ai_accel_event_driven_host_runtime_helper::p23_sq_cmd_t    bad_cmd;
        ai_accel_event_driven_host_runtime_helper::p23_event_snapshot_t snap;
        logic [31:0] event_required;
        logic [31:0] ack_mask;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] cq_tail;
    begin
        `uvm_info("P23F_CASE/ERROR",
            "Starting event-driven invalid SQ command error case",
            UVM_MEDIUM)

        rt.make_default_queue_cfg(
            cfg,
            32'(P23F_ERR_SQ_BASE),
            32'(P23F_ERR_CQ_BASE),
            32'(P23F_QUEUE_DEPTH),
            1'b0
        );

        bad_cmd.control          = 32'h0000_0000; // invalid: VALID clear / unsupported command
        bad_cmd.user_tag         = P23F_ERR_CMD_TAG;
        bad_cmd.desc_base        = 32'h0000_0300;
        bad_cmd.desc_count       = 32'h0000_0001;
        bad_cmd.desc_stride      = 32'(P23F_DESC_STRIDE);
        bad_cmd.completion_flags = 32'h0000_0000;
        bad_cmd.timeout_cycles   = 32'h0000_0000;

        event_required = rt.event_bit(ai_accel_csr_access_helper::P22_EVENT_QUEUE_ERROR);

        csr_queue_clear_sticky_status();
        rt.initialize_runtime(cfg, event_required, 1'b1);
        rt.write_sq_command(cfg, 0, bad_cmd, 1'b1);
        rt.ring_sq_tail(32'h0000_0001);
        rt.start_queue();

        wait_p23f_queue_error(done_timeout_cycles);
        rt.wait_events(event_required, snap, done_timeout_cycles * 2, 1'b1);
        expect_p23f_event_snapshot("QUEUE_ERROR invalid SQ command", snap, event_required, 1'b1);

        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_ERROR_STATUS,  error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_REJECT_STATUS, reject_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_QUEUE_CQ_TAIL,       cq_tail);

        if (error_status == 32'h0000_0000) begin
            `uvm_fatal("P23F_HOST_RT/ERROR_STATUS_ZERO", "Expected queue error sticky status for invalid SQ command")
        end

        `uvm_info("P23F_HOST_RT/ERROR_PASS",
            $sformatf("Event-driven queue error observed: error_status=0x%08h reject_status=0x%08h cq_tail=0x%08h",
                error_status,
                reject_status,
                cq_tail),
            UVM_MEDIUM)

        ack_mask = snap.pending & ai_accel_csr_access_helper::EVENT_VALID_MASK;
        rt.ack_events(ack_mask);
        check_p23f_event_cleanup("QUEUE_ERROR invalid SQ command", ack_mask);
        csr_queue_clear_sticky_status();
    end
    endtask

    task run_phase(uvm_phase phase);
        ai_accel_subsys_seq_item profile_item;
        int signed               a_flat[];
        int signed               b_flat[];
        int signed               expected_c[];
        int signed               actual_c[];
        int unsigned             c_elems;
        int unsigned             c_bytes;

        ai_accel_event_driven_host_runtime_helper rt;
    begin
        phase.raise_objection(this);

        `uvm_info("P23F_HOST_RT/START",
            "Starting P23F event-driven CQ-full recovery / stopped / error handling smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        rt = ai_accel_event_driven_host_runtime_helper::type_id::create("rt");
        rt.set_csr(csr);
        rt.set_ctrl_vif(p17d_ctrl_vif);

        build_selected_payload(profile_item, a_flat, b_flat, expected_c);

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("P23F_HOST_RT/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(),
                    c_elems))
        end

        prepare_dma_source_and_destination(a_flat, b_flat);

        program_p23f_descriptor_table(P23F_CQFULL_DESC0_BASE, P23F_CQFULL_DESC0_TAG0, P23F_CQFULL_DESC0_TAG1, profile_item, a_flat.size(), b_flat.size(), c_bytes);
        program_p23f_descriptor_table(P23F_CQFULL_DESC1_BASE, P23F_CQFULL_DESC1_TAG0, P23F_CQFULL_DESC1_TAG1, profile_item, a_flat.size(), b_flat.size(), c_bytes);
        program_p23f_descriptor_table(P23F_STOP_DESC0_BASE,   P23F_STOP_DESC0_TAG0,   P23F_STOP_DESC0_TAG1,   profile_item, a_flat.size(), b_flat.size(), c_bytes);
        program_p23f_descriptor_table(P23F_STOP_DESC1_BASE,   P23F_STOP_DESC1_TAG0,   P23F_STOP_DESC1_TAG1,   profile_item, a_flat.size(), b_flat.size(), c_bytes);

        csr_clear_sticky_status();
        csr_job_clear_sticky_status();
        csr_recipe_clear_sticky_status();
        csr_desc_fetch_clear_sticky_status();
        csr_completion_wb_clear_sticky_status();
        csr_queue_clear_sticky_status();
        csr_program_completion_wb();

        p23f_case_cq_full_recovery(rt, profile_item);
        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        p23f_case_stop_queue(rt, profile_item);
        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        p23f_case_error_event(rt);

        `uvm_info("P23F_HOST_RT/PASS",
            $sformatf("P23F event-driven CQ-full/stopped/error handling completed: CASE_ID=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
                selected_case_id,
                a_flat.size(),
                b_flat.size(),
                c_elems),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
