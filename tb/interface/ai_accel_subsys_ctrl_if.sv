// File: tb/interface/ai_accel_subsys_ctrl_if.sv

`ifndef AI_ACCEL_SUBSYS_CTRL_IF_SV
`define AI_ACCEL_SUBSYS_CTRL_IF_SV

interface ai_accel_subsys_ctrl_if #(
    parameter int ADDR_WIDTH        = 32,
    parameter int DIM_WIDTH         = 8,
    parameter int DMA_SRC_MEM_BYTES = 4096,
    parameter int DMA_DST_MEM_BYTES = 4096
)(
    input logic clk
);

    // ------------------------------------------------------------
    // Reset/status observation
    // ------------------------------------------------------------
    logic dma_rst_n;
    logic core_rst_n;

    // ------------------------------------------------------------
    // CODE-COV-C1.2-C2-A1 descriptor-to-recipe handoff observation
    //
    // These are passive testbench observations only.  They do not drive
    // or alter DUT state.
    // ------------------------------------------------------------
    logic desc_fetch_busy_obs;
    logic recipe_busy_obs;
    logic desc_fetch_recipe_start_pulse_obs;
    logic desc_fetch_launch_ownership_obs;
    logic csr_dma_load_start_pulse_obs;
    logic csr_job_start_pulse_obs;
    logic csr_recipe_start_pulse_obs;
    logic csr_desc_fetch_start_pulse_obs;
    logic desc_fetch_start_to_engine_obs;

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G7-Z3-A Queue-PRESENT / manual-P17 collision
    // observation
    //
    // Passive testbench observations only.  These expose the exact queue
    // arbitration terms needed to prove that a manual P17 START presented
    // while a legal queue command is in Q_PRESENT stalls queue acceptance
    // for one cycle without reaching the descriptor-fetch engine.
    // ------------------------------------------------------------
    logic [31:0] queue_state_obs;
    logic        queue_cmd_valid_obs;
    logic        queue_cmd_ready_obs;
    logic        queue_cmd_reject_obs;
    logic        desc_fetch_start_blocked_obs;
    logic        csr_desc_fetch_start_blocked_obs;
    logic        queue_desc_fetch_start_pulse_obs;

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G7-Z4-C2-B queue auto-continue control-window
    // observation
    //
    // Passive testbench observations only.  These expose the queue
    // completion/auto-continue state used by the legal CSR timing
    // probes; they never drive or alter DUT state.
    // ------------------------------------------------------------
    logic        completion_wb_busy_obs;
    logic        queue_completion_commit_pulse_obs;
    logic        queue_auto_continue_pending_obs;
    logic        queue_enable_obs;
    logic        queue_run_until_empty_obs;
    logic        queue_busy_obs;

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G7-Z4-C2-C P18/watchdog terminal-boundary
    // observation
    //
    // Passive testbench observations only.  These expose the exact
    // watchdog / queue-completion / auto-P18 terms used by the legal
    // phase-tolerant constructive probes.  They never drive DUT state.
    // ------------------------------------------------------------
    logic        queue_timeout_watchdog_active_obs;
    logic [31:0] queue_timeout_budget_obs;
    logic [31:0] queue_timeout_count_obs;
    logic        queue_timeout_pulse_obs;
    logic [31:0] queue_timeout_error_status_obs;
    logic        queue_completion_commit_raw_obs;
    logic        queue_completion_error_raw_obs;
    logic        completion_wb_auto_pending_obs;
    logic        completion_wb_enable_obs;

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G7-X2 Port1 owner-overlap observation
    //
    // Passive testbench observations only.  These expose the exact
    // core-domain owner inputs and the mux defensive overlap signal;
    // they do not drive or alter DUT state.
    // ------------------------------------------------------------
    logic        axis_stream_load_active_obs;
    logic        acc_busy_core_obs;
    logic        port1_illegal_overlap_obs;
    int unsigned port1_illegal_overlap_observed_count;

    // ------------------------------------------------------------
    // Testbench reset override control
    // ------------------------------------------------------------
    logic tb_reset_override_en;
    logic tb_dma_rst_n_override;
    logic tb_core_rst_n_override;

    // ------------------------------------------------------------
    // DMA load control / status
    // ------------------------------------------------------------
    logic                  dma_load_start;
    logic [ADDR_WIDTH-1:0] dma_src_base_addr;
    logic [ADDR_WIDTH-1:0] dma_dst_base_addr;
    logic [31:0]           dma_load_beats;

    logic                  dma_load_busy;
    logic                  dma_load_done;
    logic                  dma_load_error;

    // ------------------------------------------------------------
    // DMA store / S2MM control / status
    // ------------------------------------------------------------
    logic                  dma_store_start;
    logic [ADDR_WIDTH-1:0] dma_store_src_base_addr;
    logic [ADDR_WIDTH-1:0] dma_store_dst_base_addr;
    logic [31:0]           dma_store_byte_count;

    logic                  dma_store_busy;
    logic                  dma_store_done;
    logic                  dma_store_error;

    // ------------------------------------------------------------
    // AXI-Stream preload control / status
    //
    // V1 Option A:
    //   AXI source -> MM2S -> AXIS FIFO -> stream loader
    //   -> scratchpad Port1 preload A/B
    // ------------------------------------------------------------
    logic                  axis_load_start;
    logic [ADDR_WIDTH-1:0] axis_src_base_addr;
    logic [ADDR_WIDTH-1:0] axis_dst_base_addr;
    logic [31:0]           axis_load_beats;

    logic                  axis_load_busy;
    logic                  axis_load_done;
    logic                  axis_load_error;

    // ------------------------------------------------------------
    // Direct-stream GEMM operand preload control / status
    //
    // Direct Stream B1:
    //   AXI source -> MM2S -> AXIS FIFO -> stream loader
    //   -> operand buffer A/B
    //
    // ds_operand_sel:
    //   0 = operand A
    //   1 = operand B
    //
    // ds_dst_base_addr:
    //   logical operand base address. The direct-stream write
    //   adapter converts stream-loader wr_addr into local operand
    //   buffer offset by subtracting this base address.
    // ------------------------------------------------------------
    logic                  gemm_input_stream_mode;

    logic                  ds_load_start;
    logic [ADDR_WIDTH-1:0] ds_src_base_addr;
    logic [ADDR_WIDTH-1:0] ds_dst_base_addr;
    logic [31:0]           ds_load_beats;
    logic                  ds_operand_sel;

    logic                  ds_load_busy;
    logic                  ds_load_done;
    logic                  ds_load_error;

    // ------------------------------------------------------------
    // Accelerator control / status
    // ------------------------------------------------------------
    logic acc_start;
    logic acc_busy;
    logic acc_done;

    // ------------------------------------------------------------
    // GEMM performance counters
    //
    // Core-clock-domain snapshots from gemm_top.
    // Counters clear on accepted GEMM start and remain stable
    // after GEMM done until the next accepted start.
    // ------------------------------------------------------------
    logic [31:0] gemm_perf_busy_cycles;
    logic [31:0] gemm_perf_mac_count;
    logic [31:0] gemm_perf_output_count;

    // ------------------------------------------------------------
    // Runtime configuration
    // ------------------------------------------------------------
    logic [ADDR_WIDTH-1:0] base_addr_a;
    logic [ADDR_WIDTH-1:0] base_addr_b;
    logic [ADDR_WIDTH-1:0] base_addr_c;

    logic [DIM_WIDTH-1:0]  dim_m;
    logic [DIM_WIDTH-1:0]  dim_n;
    logic [DIM_WIDTH-1:0]  dim_k;

    // C RMW accumulation runtime control bit.
    // When GEMM_ENABLE_C_RMW_ACCUM=1 in the DUT, this bit selects
    // whether the current GEMM job overwrites C or accumulates into
    // the existing C contents.
    logic                  accumulate_enable;

    // ------------------------------------------------------------
    // DMA / AXIS / Direct-stream source memory model storage
    //
    // Shared by:
    //   - DMA load source responder
    //   - AXI-Stream preload source responder
    //   - Direct-stream preload source responder
    // ------------------------------------------------------------
    logic [7:0] dma_src_mem [0:DMA_SRC_MEM_BYTES-1];

    function automatic int unsigned dma_src_byte_index(
        input logic [ADDR_WIDTH-1:0] addr
    );
        return int'(addr);
    endfunction

    task automatic dma_src_mem_clear();
        int unsigned i;
    begin
        for (i = 0; i < DMA_SRC_MEM_BYTES; i++) begin
            dma_src_mem[i] = 8'h00;
        end
    end
    endtask

    task automatic dma_src_mem_write_byte(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [7:0]            data
    );
        int unsigned idx;
    begin
        idx = dma_src_byte_index(addr);

        if (idx >= DMA_SRC_MEM_BYTES) begin
            $fatal(1,
                "[CTRL_IF_DMA_SRC] dma_src_mem_write_byte out of range: addr=0x%08h idx=%0d depth=%0d",
                addr, idx, DMA_SRC_MEM_BYTES
            );
        end

        dma_src_mem[idx] = data;
    end
    endtask

    task automatic dma_src_mem_write_word64(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [63:0]           data
    );
        int unsigned lane;
        int unsigned idx;
    begin
        idx = dma_src_byte_index(addr);

        if ((idx + 8) > DMA_SRC_MEM_BYTES) begin
            $fatal(1,
                "[CTRL_IF_DMA_SRC] dma_src_mem_write_word64 out of range: addr=0x%08h idx=%0d depth=%0d",
                addr, idx, DMA_SRC_MEM_BYTES
            );
        end

        for (lane = 0; lane < 8; lane++) begin
            dma_src_mem[idx + lane] = data[8*lane +: 8];
        end
    end
    endtask

    // ------------------------------------------------------------
    // DMA source RRESP error injection control
    // ------------------------------------------------------------
    logic      dma_src_inject_rresp_error;
    int signed dma_src_inject_rresp_error_beat;

    task automatic dma_src_set_rresp_error(
        input bit        enable,
        input int signed beat_index
    );
    begin
        dma_src_inject_rresp_error      = enable;
        dma_src_inject_rresp_error_beat = beat_index;
    end
    endtask

    // ------------------------------------------------------------
    // AXI-Stream preload source protocol injection control
    // ------------------------------------------------------------
    logic      axis_src_inject_rresp_error;
    int signed axis_src_inject_rresp_error_beat;

    task automatic axis_src_set_rresp_error(
        input bit        enable,
        input int signed beat_index
    );
    begin
        axis_src_inject_rresp_error      = enable;
        axis_src_inject_rresp_error_beat = beat_index;
    end
    endtask

    // CODE-COV-C1.3-B1: legal AXI read-address backpressure and
    // protocol-integrity injection for the external AXIS preload source.
    // Beat indices are relative to the AR count captured when the control
    // generation changes.  Observation counters are driven by the UVM top.
    int unsigned axis_src_arready_stall_cycles = 0;
    int unsigned axis_src_arready_stall_gen    = 0;
    int unsigned axis_src_arready_stall_observed_count;

    logic        axis_src_inject_rid_mismatch = 1'b0;
    int signed   axis_src_inject_rid_mismatch_beat = -1;
    int unsigned axis_src_inject_rid_mismatch_gen  = 0;
    int unsigned axis_src_rid_mismatch_observed_count;

    logic        axis_src_inject_rlast_error = 1'b0;
    int signed   axis_src_inject_rlast_error_beat = -1;
    int unsigned axis_src_inject_rlast_error_gen  = 0;
    int unsigned axis_src_rlast_error_observed_count;

    task automatic axis_src_set_arready_stall(
        input int unsigned stall_cycles
    );
    begin
        axis_src_arready_stall_cycles = stall_cycles;
        axis_src_arready_stall_gen    = axis_src_arready_stall_gen + 1;
    end
    endtask

    task automatic axis_src_set_rid_mismatch(
        input bit        enable,
        input int signed beat_index
    );
    begin
        axis_src_inject_rid_mismatch      = enable;
        axis_src_inject_rid_mismatch_beat = beat_index;
        axis_src_inject_rid_mismatch_gen  = axis_src_inject_rid_mismatch_gen + 1;
    end
    endtask

    task automatic axis_src_set_rlast_error(
        input bit        enable,
        input int signed beat_index
    );
    begin
        axis_src_inject_rlast_error      = enable;
        axis_src_inject_rlast_error_beat = beat_index;
        axis_src_inject_rlast_error_gen  = axis_src_inject_rlast_error_gen + 1;
    end
    endtask

    task automatic axis_src_clear_protocol_faults();
    begin
        axis_src_set_rresp_error(1'b0, -1);
        axis_src_set_arready_stall(0);
        axis_src_set_rid_mismatch(1'b0, -1);
        axis_src_set_rlast_error(1'b0, -1);
    end
    endtask

    // ------------------------------------------------------------
    // Direct-stream preload source RRESP error injection control
    //
    // Separate from DMA load and AXIS preload injection controls so
    // direct-stream error tests can be isolated.
    // ------------------------------------------------------------
    logic      ds_src_inject_rresp_error;
    int signed ds_src_inject_rresp_error_beat;

    task automatic ds_src_set_rresp_error(
        input bit        enable,
        input int signed beat_index
    );
    begin
        ds_src_inject_rresp_error      = enable;
        ds_src_inject_rresp_error_beat = beat_index;
    end
    endtask

    // ------------------------------------------------------------
    // P19 command-source AXI read protocol fault injection control
    //
    // These controls are verification-only and affect only the command
    // source responder in ai_accel_subsys_csr_uvm_top.  Beat indices are
    // relative to the current command-entry read burst.
    // ------------------------------------------------------------
    logic      cmd_src_inject_rresp_error = 1'b0;
    int signed cmd_src_inject_rresp_error_beat = -1;

    logic      cmd_src_inject_early_rlast = 1'b0;
    int signed cmd_src_inject_early_rlast_beat = -1;

    logic      cmd_src_inject_missing_rlast = 1'b0;
    int signed cmd_src_inject_missing_rlast_beat = -1;

    // CODE-COV-C1.3-B2-B: legal command-source ARREADY backpressure.
    // The generation counter lets the UVM top capture each new stall request
    // without force/deposit or any DUT-internal state manipulation.
    int unsigned cmd_src_arready_stall_cycles = 0;
    int unsigned cmd_src_arready_stall_gen    = 0;
    int unsigned cmd_src_arready_stall_observed_count;

    task automatic cmd_src_set_arready_stall(
        input int unsigned stall_cycles
    );
    begin
        cmd_src_arready_stall_cycles = stall_cycles;
        cmd_src_arready_stall_gen    = cmd_src_arready_stall_gen + 1;
    end
    endtask

    task automatic cmd_src_clear_faults();
    begin
        cmd_src_inject_rresp_error       = 1'b0;
        cmd_src_inject_rresp_error_beat  = -1;
        cmd_src_inject_early_rlast       = 1'b0;
        cmd_src_inject_early_rlast_beat  = -1;
        cmd_src_inject_missing_rlast      = 1'b0;
        cmd_src_inject_missing_rlast_beat = -1;
        cmd_src_set_arready_stall(0);
    end
    endtask

    task automatic cmd_src_set_rresp_error(
        input bit        enable,
        input int signed beat_index
    );
    begin
        cmd_src_clear_faults();
        cmd_src_inject_rresp_error      = enable;
        cmd_src_inject_rresp_error_beat = beat_index;
    end
    endtask

    task automatic cmd_src_set_early_rlast(
        input bit        enable,
        input int signed beat_index
    );
    begin
        cmd_src_clear_faults();
        cmd_src_inject_early_rlast      = enable;
        cmd_src_inject_early_rlast_beat = beat_index;
    end
    endtask

    task automatic cmd_src_set_missing_rlast(
        input bit        enable,
        input int signed beat_index
    );
    begin
        cmd_src_clear_faults();
        cmd_src_inject_missing_rlast      = enable;
        cmd_src_inject_missing_rlast_beat = beat_index;
    end
    endtask

    // ------------------------------------------------------------
    // DMA destination memory model storage
    // ------------------------------------------------------------
    logic [7:0] dma_dst_mem [0:DMA_DST_MEM_BYTES-1];

    function automatic int unsigned dma_dst_byte_index(
        input logic [ADDR_WIDTH-1:0] addr
    );
        return int'(addr);
    endfunction

    task automatic dma_dst_mem_clear();
        int unsigned i;
    begin
        for (i = 0; i < DMA_DST_MEM_BYTES; i++) begin
            dma_dst_mem[i] = 8'h00;
        end
    end
    endtask

    task automatic dma_dst_mem_write_byte(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [7:0]            data
    );
        int unsigned idx;
    begin
        idx = dma_dst_byte_index(addr);

        if (idx >= DMA_DST_MEM_BYTES) begin
            $fatal(1,
                "[CTRL_IF_DMA_DST] dma_dst_mem_write_byte out of range: addr=0x%08h idx=%0d depth=%0d",
                addr, idx, DMA_DST_MEM_BYTES
            );
        end

        dma_dst_mem[idx] = data;
    end
    endtask

    function automatic logic [7:0] dma_dst_mem_read_byte(
        input logic [ADDR_WIDTH-1:0] addr
    );
        int unsigned idx;
    begin
        idx = dma_dst_byte_index(addr);

        if (idx >= DMA_DST_MEM_BYTES) begin
            $fatal(1,
                "[CTRL_IF_DMA_DST] dma_dst_mem_read_byte out of range: addr=0x%08h idx=%0d depth=%0d",
                addr, idx, DMA_DST_MEM_BYTES
            );
        end

        return dma_dst_mem[idx];
    end
    endfunction

    function automatic logic [31:0] dma_dst_mem_read_word32(
        input logic [ADDR_WIDTH-1:0] addr
    );
        int unsigned idx;
        logic [31:0] data;
    begin
        idx = dma_dst_byte_index(addr);

        if ((idx + 4) > DMA_DST_MEM_BYTES) begin
            $fatal(1,
                "[CTRL_IF_DMA_DST] dma_dst_mem_read_word32 out of range: addr=0x%08h idx=%0d depth=%0d",
                addr, idx, DMA_DST_MEM_BYTES
            );
        end

        data = '0;
        data[7:0]   = dma_dst_mem[idx + 0];
        data[15:8]  = dma_dst_mem[idx + 1];
        data[23:16] = dma_dst_mem[idx + 2];
        data[31:24] = dma_dst_mem[idx + 3];

        return data;
    end
    endfunction

    function automatic int signed dma_dst_mem_read_s32(
        input logic [ADDR_WIDTH-1:0] addr
    );
        logic signed [31:0] data_s32;
    begin
        data_s32 = dma_dst_mem_read_word32(addr);
        return int'(data_s32);
    end
    endfunction

    task automatic dma_dst_mem_read_s32_array(
        input  logic [ADDR_WIDTH-1:0] base_addr,
        input  int unsigned           word_count,
        output int signed             values[]
    );
        int unsigned i;
    begin
        values = new[word_count];

        for (i = 0; i < word_count; i++) begin
            values[i] = dma_dst_mem_read_s32(base_addr + ADDR_WIDTH'(i * 4));
        end
    end
    endtask

    // ------------------------------------------------------------
    // DMA destination BRESP error injection control
    // ------------------------------------------------------------
    logic      dma_dst_inject_bresp_error;
    int signed dma_dst_inject_bresp_error_beat;

    task automatic dma_dst_set_bresp_error(
        input bit        enable,
        input int signed beat_index
    );
    begin
        dma_dst_inject_bresp_error      = enable;
        dma_dst_inject_bresp_error_beat = beat_index;
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G7-V4-B DMA destination AW/W backpressure
    // injection and observation control
    //
    // Beat indices are relative to the first DMA destination write
    // accepted after injection is enabled.  Use -1 to disable an
    // individual ordering probe.
    //
    //   aw_first_beat: hold WREADY low until AW handshakes first
    //   w_first_beat : hold AWREADY low until W handshakes first
    // ------------------------------------------------------------
    logic      dma_dst_inject_aw_w_backpressure;
    int signed dma_dst_aw_first_beat;
    int signed dma_dst_w_first_beat;

    int unsigned dma_dst_aw_first_observed_count;
    int unsigned dma_dst_w_first_observed_count;

    task automatic dma_dst_set_aw_w_backpressure(
        input bit        enable,
        input int signed aw_first_beat,
        input int signed w_first_beat
    );
    begin
        dma_dst_inject_aw_w_backpressure = enable;
        dma_dst_aw_first_beat            = aw_first_beat;
        dma_dst_w_first_beat             = w_first_beat;
    end
    endtask

    // ------------------------------------------------------------
    // Driver clocking block
    // ------------------------------------------------------------
    clocking cb_drv @(posedge clk);
        // DMA load control
        output dma_load_start;
        output dma_src_base_addr;
        output dma_dst_base_addr;
        output dma_load_beats;

        input  dma_load_busy;
        input  dma_load_done;
        input  dma_load_error;

        // DMA store control
        output dma_store_start;
        output dma_store_src_base_addr;
        output dma_store_dst_base_addr;
        output dma_store_byte_count;

        input  dma_store_busy;
        input  dma_store_done;
        input  dma_store_error;

        // AXI-Stream preload control
        output axis_load_start;
        output axis_src_base_addr;
        output axis_dst_base_addr;
        output axis_load_beats;

        input  axis_load_busy;
        input  axis_load_done;
        input  axis_load_error;

        // Direct-stream control
        output gemm_input_stream_mode;

        output ds_load_start;
        output ds_src_base_addr;
        output ds_dst_base_addr;
        output ds_load_beats;
        output ds_operand_sel;

        input  ds_load_busy;
        input  ds_load_done;
        input  ds_load_error;

        // Accelerator control
        output acc_start;

        output base_addr_a;
        output base_addr_b;
        output base_addr_c;

        output dim_m;
        output dim_n;
        output dim_k;

        // C RMW accumulation runtime control
        output accumulate_enable;

        // Reset override control
        output tb_reset_override_en;
        output tb_dma_rst_n_override;
        output tb_core_rst_n_override;

        // Reset/status observation
        input  dma_rst_n;
        input  core_rst_n;

        input  acc_busy;
        input  acc_done;

        input  gemm_perf_busy_cycles;
        input  gemm_perf_mac_count;
        input  gemm_perf_output_count;
    endclocking

    // ------------------------------------------------------------
    // Monitor clocking block
    // ------------------------------------------------------------
    clocking cb_mon @(posedge clk);
        input dma_rst_n;
        input core_rst_n;

        // DMA load observation
        input dma_load_start;
        input dma_src_base_addr;
        input dma_dst_base_addr;
        input dma_load_beats;

        input dma_load_busy;
        input dma_load_done;
        input dma_load_error;

        // DMA store observation
        input dma_store_start;
        input dma_store_src_base_addr;
        input dma_store_dst_base_addr;
        input dma_store_byte_count;

        input dma_store_busy;
        input dma_store_done;
        input dma_store_error;

        // AXI-Stream preload observation
        input axis_load_start;
        input axis_src_base_addr;
        input axis_dst_base_addr;
        input axis_load_beats;

        input axis_load_busy;
        input axis_load_done;
        input axis_load_error;

        // Direct-stream observation
        input gemm_input_stream_mode;

        input ds_load_start;
        input ds_src_base_addr;
        input ds_dst_base_addr;
        input ds_load_beats;
        input ds_operand_sel;

        input ds_load_busy;
        input ds_load_done;
        input ds_load_error;

        // Accelerator observation
        input acc_start;
        input acc_busy;
        input acc_done;

        input gemm_perf_busy_cycles;
        input gemm_perf_mac_count;
        input gemm_perf_output_count;

        input base_addr_a;
        input base_addr_b;
        input base_addr_c;

        input dim_m;
        input dim_n;
        input dim_k;

        // C RMW accumulation runtime control observation
        input accumulate_enable;

        input tb_reset_override_en;
        input tb_dma_rst_n_override;
        input tb_core_rst_n_override;
    endclocking

    // ------------------------------------------------------------
    // Modports
    // ------------------------------------------------------------
    modport drv (
        clocking cb_drv
    );

    modport mon (
        clocking cb_mon
    );

endinterface

`endif
