// File: tb/uvm/helper/ai_accel_csr_access_helper.sv

`ifndef AI_ACCEL_CSR_ACCESS_HELPER_SV
`define AI_ACCEL_CSR_ACCESS_HELPER_SV

import uvm_pkg::*;
`include "uvm_macros.svh"

class ai_accel_csr_access_helper extends uvm_object;
    `uvm_object_utils(ai_accel_csr_access_helper)

    typedef virtual axi_lite_if #(
        .ADDR_WIDTH (12),
        .DATA_WIDTH (32)
    ) csr_vif_t;

    localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

    // ------------------------------------------------------------
    // CSR address map
    // ------------------------------------------------------------
    localparam logic [11:0] CSR_VERSION              = 12'h000;
    localparam logic [11:0] CSR_COMMAND              = 12'h004;
    localparam logic [11:0] CSR_STATUS               = 12'h008;
    localparam logic [11:0] CSR_DONE_STATUS          = 12'h00C;
    localparam logic [11:0] CSR_ERROR_STATUS         = 12'h010;
    localparam logic [11:0] CSR_MODE                 = 12'h014;
    localparam logic [11:0] CSR_CMD_REJECT_STATUS    = 12'h018;

    localparam logic [11:0] CSR_BASE_ADDR_A          = 12'h020;
    localparam logic [11:0] CSR_BASE_ADDR_B          = 12'h024;
    localparam logic [11:0] CSR_BASE_ADDR_C          = 12'h028;
    localparam logic [11:0] CSR_DIM_M                = 12'h02C;
    localparam logic [11:0] CSR_DIM_N                = 12'h030;
    localparam logic [11:0] CSR_DIM_K                = 12'h034;

    localparam logic [11:0] CSR_DMA_LOAD_SRC_BASE    = 12'h040;
    localparam logic [11:0] CSR_DMA_LOAD_DST_BASE    = 12'h044;
    localparam logic [11:0] CSR_DMA_LOAD_BEATS       = 12'h048;

    localparam logic [11:0] CSR_AXIS_SRC_BASE        = 12'h050;
    localparam logic [11:0] CSR_AXIS_DST_BASE        = 12'h054;
    localparam logic [11:0] CSR_AXIS_LOAD_BEATS      = 12'h058;

    localparam logic [11:0] CSR_DS_SRC_BASE          = 12'h060;
    localparam logic [11:0] CSR_DS_DST_BASE          = 12'h064;
    localparam logic [11:0] CSR_DS_LOAD_BEATS        = 12'h068;
    localparam logic [11:0] CSR_DS_CONTROL           = 12'h06C;

    localparam logic [11:0] CSR_DMA_STORE_SRC_BASE   = 12'h070;
    localparam logic [11:0] CSR_DMA_STORE_DST_BASE   = 12'h074;
    localparam logic [11:0] CSR_DMA_STORE_BYTE_COUNT = 12'h078;

    localparam logic [11:0] CSR_PERF_BUSY_CYCLES     = 12'h080;
    localparam logic [11:0] CSR_PERF_MAC_COUNT       = 12'h084;
    localparam logic [11:0] CSR_PERF_OUTPUT_COUNT    = 12'h088;

    localparam logic [11:0] CSR_JOB_VERSION          = 12'h100;
    localparam logic [11:0] CSR_JOB_COMMAND          = 12'h104;
    localparam logic [11:0] CSR_JOB_STATUS           = 12'h108;
    localparam logic [11:0] CSR_JOB_DONE_STATUS      = 12'h10C;
    localparam logic [11:0] CSR_JOB_ERROR_STATUS     = 12'h110;
    localparam logic [11:0] CSR_JOB_MODE             = 12'h114;
    localparam logic [11:0] CSR_JOB_REJECT_STATUS    = 12'h118;
    localparam logic [11:0] CSR_JOB_STATE            = 12'h11C;

    localparam logic [11:0] CSR_JOB_BASE_ADDR_A      = 12'h120;
    localparam logic [11:0] CSR_JOB_BASE_ADDR_B      = 12'h124;
    localparam logic [11:0] CSR_JOB_BASE_ADDR_C      = 12'h128;
    localparam logic [11:0] CSR_JOB_DIM_M            = 12'h12C;
    localparam logic [11:0] CSR_JOB_DIM_N            = 12'h130;
    localparam logic [11:0] CSR_JOB_DIM_K            = 12'h134;

    localparam logic [11:0] CSR_JOB_A_SRC_BASE       = 12'h138;
    localparam logic [11:0] CSR_JOB_A_DST_BASE       = 12'h13C;
    localparam logic [11:0] CSR_JOB_A_LOAD_BEATS     = 12'h140;

    localparam logic [11:0] CSR_JOB_B_SRC_BASE       = 12'h148;
    localparam logic [11:0] CSR_JOB_B_DST_BASE       = 12'h14C;
    localparam logic [11:0] CSR_JOB_B_LOAD_BEATS     = 12'h150;

    localparam logic [11:0] CSR_JOB_STORE_SRC_BASE   = 12'h158;
    localparam logic [11:0] CSR_JOB_STORE_DST_BASE   = 12'h15C;
    localparam logic [11:0] CSR_JOB_STORE_BYTE_COUNT = 12'h160;

    localparam logic [11:0] CSR_JOB_PERF_BUSY_CYCLES = 12'h180;
    localparam logic [11:0] CSR_JOB_PERF_MAC_COUNT   = 12'h184;
    localparam logic [11:0] CSR_JOB_PERF_OUTPUT_COUNT= 12'h188;

    localparam logic [11:0] CSR_RECIPE_VERSION       = 12'h200;
    localparam logic [11:0] CSR_RECIPE_COMMAND       = 12'h204;
    localparam logic [11:0] CSR_RECIPE_STATUS        = 12'h208;
    localparam logic [11:0] CSR_RECIPE_DONE_STATUS   = 12'h20C;
    localparam logic [11:0] CSR_RECIPE_ERROR_STATUS  = 12'h210;
    localparam logic [11:0] CSR_RECIPE_CONTROL       = 12'h214;
    localparam logic [11:0] CSR_RECIPE_REJECT_STATUS = 12'h218;
    localparam logic [11:0] CSR_RECIPE_STATE         = 12'h21C;
    localparam logic [11:0] CSR_RECIPE_CURRENT_SLOT  = 12'h220;
    localparam logic [11:0] CSR_RECIPE_COMPLETED_COUNT = 12'h224;
    localparam logic [11:0] CSR_RECIPE_SLOT_DONE_MASK  = 12'h228;
    localparam logic [11:0] CSR_RECIPE_SLOT_ERROR_MASK = 12'h22C;
    localparam logic [11:0] CSR_RECIPE_SLOT_REJECT_MASK= 12'h230;
    localparam logic [11:0] CSR_RECIPE_PERF_BUSY_CYCLES = 12'h280;
    localparam logic [11:0] CSR_RECIPE_PERF_MAC_COUNT   = 12'h284;
    localparam logic [11:0] CSR_RECIPE_PERF_OUTPUT_COUNT= 12'h288;

    localparam logic [11:0] CSR_RECIPE_SLOT_BASE = 12'h300;
    localparam int unsigned CSR_RECIPE_SLOT_STRIDE = 128;

    // P17 descriptor-fetch CSR window.
    localparam logic [11:0] CSR_DESC_FETCH_VERSION       = 12'h500;
    localparam logic [11:0] CSR_DESC_FETCH_COMMAND       = 12'h504;
    localparam logic [11:0] CSR_DESC_FETCH_STATUS        = 12'h508;
    localparam logic [11:0] CSR_DESC_FETCH_DONE_STATUS   = 12'h50C;
    localparam logic [11:0] CSR_DESC_FETCH_ERROR_STATUS  = 12'h510;
    localparam logic [11:0] CSR_DESC_FETCH_REJECT_STATUS = 12'h514;
    localparam logic [11:0] CSR_DESC_FETCH_BASE_ADDR     = 12'h518;
    localparam logic [11:0] CSR_DESC_FETCH_COUNT         = 12'h51C;
    localparam logic [11:0] CSR_DESC_FETCH_STRIDE_BYTES  = 12'h520;
    localparam logic [11:0] CSR_DESC_FETCH_CURRENT_INDEX = 12'h524;
    localparam logic [11:0] CSR_DESC_FETCH_FETCHED_COUNT = 12'h528;
    localparam logic [11:0] CSR_DESC_FETCH_SNAPSHOT_STATUS = 12'h52C;

    // P18 completion-writeback CSR window.
    localparam logic [11:0] CSR_COMPLETION_WB_VERSION        = 12'h540;
    localparam logic [11:0] CSR_COMPLETION_WB_COMMAND        = 12'h544;
    localparam logic [11:0] CSR_COMPLETION_WB_STATUS         = 12'h548;
    localparam logic [11:0] CSR_COMPLETION_WB_DONE_STATUS    = 12'h54C;
    localparam logic [11:0] CSR_COMPLETION_WB_ERROR_STATUS   = 12'h550;
    localparam logic [11:0] CSR_COMPLETION_WB_REJECT_STATUS  = 12'h554;
    localparam logic [11:0] CSR_COMPLETION_WB_CONTROL        = 12'h558;
    localparam logic [11:0] CSR_COMPLETION_WB_BASE_ADDR      = 12'h55C;
    localparam logic [11:0] CSR_COMPLETION_WB_STATUS_FLAGS   = 12'h560;
    localparam logic [11:0] CSR_COMPLETION_WB_USER_TAG       = 12'h564;
    localparam logic [11:0] CSR_COMPLETION_WB_COUNTS         = 12'h568;
    localparam logic [11:0] CSR_COMPLETION_WB_RECIPE_DONE    = 12'h56C;
    localparam logic [11:0] CSR_COMPLETION_WB_RECIPE_ERROR   = 12'h570;
    localparam logic [11:0] CSR_COMPLETION_WB_RECIPE_REJECT  = 12'h574;
    localparam logic [11:0] CSR_COMPLETION_WB_PERF_MAC_COUNT = 12'h578;
    localparam logic [11:0] CSR_COMPLETION_WB_ERROR_DETAIL   = 12'h57C;


    // P19 command/completion queue CSR window
    localparam logic [11:0] CSR_QUEUE_VERSION          = 12'h580;
    localparam logic [11:0] CSR_QUEUE_COMMAND          = 12'h584;
    localparam logic [11:0] CSR_QUEUE_STATUS           = 12'h588;
    localparam logic [11:0] CSR_QUEUE_DONE_STATUS      = 12'h58C;
    localparam logic [11:0] CSR_QUEUE_ERROR_STATUS     = 12'h590;
    localparam logic [11:0] CSR_QUEUE_CONTROL          = 12'h594;
    localparam logic [11:0] CSR_QUEUE_REJECT_STATUS    = 12'h598;
    localparam logic [11:0] CSR_QUEUE_STATE            = 12'h59C;
    localparam logic [11:0] CSR_QUEUE_SQ_BASE          = 12'h5A0;
    localparam logic [11:0] CSR_QUEUE_SQ_DEPTH         = 12'h5A4;
    localparam logic [11:0] CSR_QUEUE_SQ_HEAD          = 12'h5A8;
    localparam logic [11:0] CSR_QUEUE_SQ_TAIL          = 12'h5AC;
    localparam logic [11:0] CSR_QUEUE_SQ_STRIDE        = 12'h5B0;
    localparam logic [11:0] CSR_QUEUE_CQ_BASE          = 12'h5B4;
    localparam logic [11:0] CSR_QUEUE_CQ_DEPTH         = 12'h5B8;
    localparam logic [11:0] CSR_QUEUE_CQ_HEAD          = 12'h5BC;
    localparam logic [11:0] CSR_QUEUE_CQ_TAIL          = 12'h5C0;
    localparam logic [11:0] CSR_QUEUE_CQ_STRIDE        = 12'h5C4;
    localparam logic [11:0] CSR_QUEUE_CURRENT_INDEX    = 12'h5C8;
    localparam logic [11:0] CSR_QUEUE_ERROR_INDEX      = 12'h5CC;
    localparam logic [11:0] CSR_QUEUE_ERROR_DETAIL     = 12'h5D0;
    localparam logic [11:0] CSR_QUEUE_LAST_CMD_TAG     = 12'h5D4;
    localparam logic [11:0] CSR_QUEUE_LAST_CMD_CONTROL = 12'h5D8;
    localparam logic [11:0] CSR_QUEUE_SQ_OCCUPANCY     = 12'h5DC;
    localparam logic [11:0] CSR_QUEUE_CQ_OCCUPANCY     = 12'h5E0;
    localparam logic [11:0] CSR_QUEUE_CQ_SPACE         = 12'h5E4;


    // ------------------------------------------------------------
    // P22 Event notification / interrupt-lite CSR window
    // ------------------------------------------------------------
    localparam logic [11:0] CSR_EVENT_VERSION      = 12'h600;
    localparam logic [11:0] CSR_EVENT_COMMAND      = 12'h604;
    localparam logic [11:0] CSR_EVENT_STATUS       = 12'h608;
    localparam logic [11:0] CSR_EVENT_PENDING      = 12'h60C;
    localparam logic [11:0] CSR_EVENT_ENABLE       = 12'h610;
    localparam logic [11:0] CSR_EVENT_CONTROL      = 12'h614;
    localparam logic [11:0] CSR_EVENT_LAST_CAUSE   = 12'h618;
    localparam logic [11:0] CSR_EVENT_COUNT        = 12'h61C;
    localparam logic [11:0] CSR_EVENT_SNAPSHOT0    = 12'h620;
    localparam logic [11:0] CSR_EVENT_SNAPSHOT1    = 12'h624;
    localparam logic [11:0] CSR_EVENT_CQ_THRESHOLD = 12'h628;
    localparam logic [11:0] CSR_EVENT_IRQ_COUNT    = 12'h62C;

    // P28 event coalescing / interrupt moderation registers.
    // These reuse the P22 event window reserved offsets.
    localparam logic [11:0] CSR_EVENT_MOD_CONTROL     = 12'h630;
    localparam logic [11:0] CSR_EVENT_MOD_STATUS      = 12'h634;
    localparam logic [11:0] CSR_EVENT_MOD_TIMER_LIMIT = 12'h638;
    localparam logic [11:0] CSR_EVENT_MOD_DEBUG       = 12'h63C;


    // ------------------------------------------------------------
    // P27 Memory access guard CSR window
    // ------------------------------------------------------------
    localparam logic [11:0] CSR_MEM_GUARD_VERSION              = 12'h640;
    localparam logic [11:0] CSR_MEM_GUARD_COMMAND              = 12'h644;
    localparam logic [11:0] CSR_MEM_GUARD_STATUS               = 12'h648;
    localparam logic [11:0] CSR_MEM_GUARD_ERROR_STATUS         = 12'h64C;
    localparam logic [11:0] CSR_MEM_GUARD_CONTROL              = 12'h650;
    localparam logic [11:0] CSR_MEM_GUARD_REJECT_STATUS        = 12'h654;
    localparam logic [11:0] CSR_MEM_GUARD_ERROR_DETAIL         = 12'h658;
    localparam logic [11:0] CSR_MEM_GUARD_ERROR_ADDR           = 12'h65C;
    localparam logic [11:0] CSR_MEM_GUARD_ERROR_SIZE_BYTES     = 12'h660;
    localparam logic [11:0] CSR_MEM_GUARD_ERROR_DOMAIN         = 12'h664;
    localparam logic [11:0] CSR_MEM_GUARD_CHECK_COUNT          = 12'h668;
    localparam logic [11:0] CSR_MEM_GUARD_ERROR_COUNT          = 12'h66C;
    localparam logic [11:0] CSR_MEM_GUARD_LAST_CHECK_ADDR      = 12'h670;
    localparam logic [11:0] CSR_MEM_GUARD_LAST_CHECK_SIZE_BYTES= 12'h674;
    localparam logic [11:0] CSR_MEM_GUARD_LAST_CHECK_DOMAIN    = 12'h678;

    localparam logic [11:0] CSR_MEM_GUARD_SQ_BASE              = 12'h680;
    localparam logic [11:0] CSR_MEM_GUARD_SQ_LIMIT             = 12'h684;
    localparam logic [11:0] CSR_MEM_GUARD_CQ_BASE              = 12'h688;
    localparam logic [11:0] CSR_MEM_GUARD_CQ_LIMIT             = 12'h68C;
    localparam logic [11:0] CSR_MEM_GUARD_DESC_BASE            = 12'h690;
    localparam logic [11:0] CSR_MEM_GUARD_DESC_LIMIT           = 12'h694;
    localparam logic [11:0] CSR_MEM_GUARD_SRC_BASE             = 12'h698;
    localparam logic [11:0] CSR_MEM_GUARD_SRC_LIMIT            = 12'h69C;
    localparam logic [11:0] CSR_MEM_GUARD_DST_BASE             = 12'h6A0;
    localparam logic [11:0] CSR_MEM_GUARD_DST_LIMIT            = 12'h6A4;

    // P22 Event command bits
    localparam int EVENT_CMD_CLEAR_PENDING  = 0;
    localparam int EVENT_CMD_FORCE_TEST     = 1;
    localparam int EVENT_CMD_CLEAR_COUNTERS = 8;

    // P22 Event control bits
    localparam int EVENT_CONTROL_GLOBAL_IRQ_ENABLE = 0;
    localparam int EVENT_CONTROL_IRQ_PULSE_MODE    = 1;
    localparam int EVENT_CONTROL_CAPTURE_SNAPSHOT  = 2;
    localparam int EVENT_CONTROL_COUNT_TEST_EVENTS = 3;

    // P22 Event status bits
    localparam int EVENT_STATUS_PENDING_NONZERO = 0;
    localparam int EVENT_STATUS_IRQ_ELIGIBLE    = 1;
    localparam int EVENT_STATUS_EVENT_IRQ_OUT   = 2;
    localparam int EVENT_STATUS_GLOBAL_IRQ_EN   = 3;
    localparam int EVENT_STATUS_QUEUE_PENDING   = 4;
    localparam int EVENT_STATUS_RUNTIME_PENDING = 5;
    localparam int EVENT_STATUS_TEST_PENDING    = 6;

    // P22 Event source bits
    localparam int P22_EVENT_QUEUE_COMPLETED    = 0;
    localparam int P22_EVENT_QUEUE_DRAINED      = 1;
    localparam int P22_EVENT_QUEUE_STOPPED      = 2;
    localparam int P22_EVENT_QUEUE_ERROR        = 3;
    localparam int P22_EVENT_CQ_NOT_EMPTY       = 4;
    localparam int P22_EVENT_CQ_THRESHOLD       = 5;
    localparam int P22_EVENT_CQ_FULL_STALL      = 6;
    localparam int P22_EVENT_CQ_SPACE_RECOVERED = 7;
    localparam int P22_EVENT_RUNTIME_DOORBELL   = 8;
    localparam int P22_EVENT_RUNTIME_CONSUMED   = 9;
    localparam int P22_EVENT_TEST               = 10;

    // P28 optional event source bit.
    localparam int P28_EVENT_CQ_MOD_TIMER       = 11;

    localparam logic [31:0] EVENT_VALID_MASK      = 32'h0000_0FFF;
    localparam logic [31:0] EVENT_QUEUE_COMPLETED_MASK = 32'h0000_0001;
    localparam logic [31:0] EVENT_CQ_NOT_EMPTY_MASK    = 32'h0000_0010;
    localparam logic [31:0] EVENT_CQ_THRESHOLD_MASK    = 32'h0000_0020;
    localparam logic [31:0] EVENT_CQ_MOD_TIMER_MASK    = 32'h0000_0800;

    // ------------------------------------------------------------
    // P28 Event coalescing / interrupt moderation constants
    // ------------------------------------------------------------
    localparam int EVENT_MOD_CONTROL_ENABLE             = 0;
    localparam int EVENT_MOD_CONTROL_THRESHOLD_ENABLE   = 1;
    localparam int EVENT_MOD_CONTROL_TIMER_ENABLE       = 2;
    localparam int EVENT_MOD_CONTROL_RETRIGGER_NONEMPTY = 3;

    localparam int EVENT_MOD_STATUS_ACTIVE              = 0;
    localparam int EVENT_MOD_STATUS_THRESHOLD_ACTIVE    = 1;
    localparam int EVENT_MOD_STATUS_TIMER_ACTIVE        = 2;
    localparam int EVENT_MOD_STATUS_TIMER_RUNNING       = 3;
    localparam int EVENT_MOD_STATUS_THRESHOLD_MET       = 4;
    localparam int EVENT_MOD_STATUS_TIMER_EXPIRED       = 5;
    localparam int EVENT_MOD_STATUS_RELEASE_PENDING     = 6;
    localparam int EVENT_MOD_STATUS_URGENT_BYPASS       = 7;

    localparam int EVENT_MOD_STATUS_CQ_OCC_LSB          = 16;
    localparam int EVENT_MOD_STATUS_CQ_OCC_MSB          = 23;
    localparam int EVENT_MOD_STATUS_UNNOTIFIED_LSB      = 24;
    localparam int EVENT_MOD_STATUS_UNNOTIFIED_MSB      = 31;

    localparam int EVENT_MOD_DEBUG_CAUSE_LSB            = 0;
    localparam int EVENT_MOD_DEBUG_CAUSE_MSB            = 7;
    localparam int EVENT_MOD_DEBUG_RELEASE_COUNT_LSB    = 8;
    localparam int EVENT_MOD_DEBUG_RELEASE_COUNT_MSB    = 15;
    localparam int EVENT_MOD_DEBUG_THRESHOLD_COUNT_LSB  = 16;
    localparam int EVENT_MOD_DEBUG_THRESHOLD_COUNT_MSB  = 23;
    localparam int EVENT_MOD_DEBUG_TIMER_COUNT_LSB      = 24;
    localparam int EVENT_MOD_DEBUG_TIMER_COUNT_MSB      = 31;

    localparam logic [7:0] P28_MOD_RELEASE_NONE      = 8'h00;
    localparam logic [7:0] P28_MOD_RELEASE_THRESHOLD = 8'h01;
    localparam logic [7:0] P28_MOD_RELEASE_TIMER     = 8'h02;
    localparam logic [7:0] P28_MOD_RELEASE_IMMEDIATE = 8'h03;
    localparam logic [7:0] P28_MOD_RELEASE_URGENT    = 8'h04;
    localparam logic [7:0] P28_MOD_RELEASE_REARM     = 8'h05;


    // ------------------------------------------------------------
    // P27 Memory access guard constants
    // ------------------------------------------------------------
    localparam int MEM_GUARD_CMD_CLEAR_ERROR    = 8;
    localparam int MEM_GUARD_CMD_CLEAR_REJECT   = 9;
    localparam int MEM_GUARD_CMD_CLEAR_COUNTERS = 10;

    localparam int MEM_GUARD_CONTROL_ENABLE              = 0;
    localparam int MEM_GUARD_CONTROL_STRICT_REJECT       = 1;
    localparam int MEM_GUARD_CONTROL_SQ_CHECK_ENABLE     = 4;
    localparam int MEM_GUARD_CONTROL_CQ_CHECK_ENABLE     = 5;
    localparam int MEM_GUARD_CONTROL_DESC_CHECK_ENABLE   = 6;
    localparam int MEM_GUARD_CONTROL_SRC_CHECK_ENABLE    = 7;
    localparam int MEM_GUARD_CONTROL_DST_CHECK_ENABLE    = 8;
    localparam int MEM_GUARD_CONTROL_WRITE_CQ_ERROR_SAFE = 12;

    localparam int MEM_GUARD_STATUS_GUARD_ENABLED      = 0;
    localparam int MEM_GUARD_STATUS_STRICT_ENABLED     = 1;
    localparam int MEM_GUARD_STATUS_ANY_ERROR          = 2;
    localparam int MEM_GUARD_STATUS_ANY_REJECT         = 3;
    localparam int MEM_GUARD_STATUS_SQ_CHECK_ENABLED   = 4;
    localparam int MEM_GUARD_STATUS_CQ_CHECK_ENABLED   = 5;
    localparam int MEM_GUARD_STATUS_DESC_CHECK_ENABLED = 6;
    localparam int MEM_GUARD_STATUS_SRC_CHECK_ENABLED  = 7;
    localparam int MEM_GUARD_STATUS_DST_CHECK_ENABLED  = 8;
    localparam int MEM_GUARD_STATUS_ERROR_PENDING      = 9;
    localparam int MEM_GUARD_STATUS_QUEUE_ERROR_MIRROR = 10;

    localparam int MEM_GUARD_ERR_ANY              = 0;
    localparam int MEM_GUARD_ERR_SQ_RANGE         = 1;
    localparam int MEM_GUARD_ERR_CQ_RANGE         = 2;
    localparam int MEM_GUARD_ERR_DESC_RANGE       = 3;
    localparam int MEM_GUARD_ERR_SRC_RANGE        = 4;
    localparam int MEM_GUARD_ERR_DST_RANGE        = 5;
    localparam int MEM_GUARD_ERR_BASE_LIMIT       = 6;
    localparam int MEM_GUARD_ERR_ADDR_OVERFLOW    = 7;
    localparam int MEM_GUARD_ERR_ALIGNMENT        = 8;
    localparam int MEM_GUARD_ERR_STRIDE           = 9;
    localparam int MEM_GUARD_ERR_DEPTH            = 10;
    localparam int MEM_GUARD_ERR_SIZE_ZERO        = 11;
    localparam int MEM_GUARD_ERR_UNSAFE_CQ_SUPP   = 12;
    localparam int MEM_GUARD_ERR_DOMAIN_MISMATCH  = 13;
    localparam int MEM_GUARD_ERR_CONFIG_BUSY      = 14;
    localparam int MEM_GUARD_ERR_INTERNAL         = 15;

    localparam int MEM_GUARD_REJ_CONFIG_BUSY      = 0;
    localparam int MEM_GUARD_REJ_INVALID_REGION   = 1;
    localparam int MEM_GUARD_REJ_UNSUPPORTED_CMD  = 2;
    localparam int MEM_GUARD_REJ_STRICT_START     = 3;

    localparam int P27_QUEUE_MEMORY_GUARD_ERROR_BIT = 9;

    localparam int P27_GUARD_DOMAIN_NONE   = 0;
    localparam int P27_GUARD_DOMAIN_SQ     = 1;
    localparam int P27_GUARD_DOMAIN_CQ     = 2;
    localparam int P27_GUARD_DOMAIN_DESC   = 3;
    localparam int P27_GUARD_DOMAIN_SRC    = 4;
    localparam int P27_GUARD_DOMAIN_DST    = 5;
    localparam int P27_GUARD_DOMAIN_CONFIG = 6;

    localparam logic [7:0] P27_DETAIL_SQ_RANGE       = 8'h20;
    localparam logic [7:0] P27_DETAIL_CQ_RANGE       = 8'h21;
    localparam logic [7:0] P27_DETAIL_DESC_RANGE     = 8'h22;
    localparam logic [7:0] P27_DETAIL_SRC_RANGE      = 8'h23;
    localparam logic [7:0] P27_DETAIL_DST_RANGE      = 8'h24;
    localparam logic [7:0] P27_DETAIL_ADDR_OVERFLOW  = 8'h25;
    localparam logic [7:0] P27_DETAIL_ALIGNMENT      = 8'h26;
    localparam logic [7:0] P27_DETAIL_SPAN_CONFIG    = 8'h27;
    localparam logic [7:0] P27_DETAIL_DOMAIN_MISMATCH= 8'h28;

    localparam logic [31:0] MEM_GUARD_ALL_ERROR_MASK = 32'h0000_FFFF;
    localparam logic [31:0] MEM_GUARD_ALL_REJECT_MASK= 32'h0000_000F;

    localparam logic [6:0] SLOT_CONTROL          = 7'h00;
    localparam logic [6:0] SLOT_BASE_ADDR_A      = 7'h04;
    localparam logic [6:0] SLOT_BASE_ADDR_B      = 7'h08;
    localparam logic [6:0] SLOT_BASE_ADDR_C      = 7'h0C;
    localparam logic [6:0] SLOT_DIM_M            = 7'h10;
    localparam logic [6:0] SLOT_DIM_N            = 7'h14;
    localparam logic [6:0] SLOT_DIM_K            = 7'h18;
    localparam logic [6:0] SLOT_A_SRC_BASE       = 7'h1C;
    localparam logic [6:0] SLOT_A_DST_BASE       = 7'h20;
    localparam logic [6:0] SLOT_A_LOAD_BEATS     = 7'h24;
    localparam logic [6:0] SLOT_B_SRC_BASE       = 7'h28;
    localparam logic [6:0] SLOT_B_DST_BASE       = 7'h2C;
    localparam logic [6:0] SLOT_B_LOAD_BEATS     = 7'h30;
    localparam logic [6:0] SLOT_STORE_SRC_BASE   = 7'h34;
    localparam logic [6:0] SLOT_STORE_DST_BASE   = 7'h38;
    localparam logic [6:0] SLOT_STORE_BYTE_COUNT = 7'h3C;
    localparam logic [6:0] SLOT_USER_TAG         = 7'h40;

    // ------------------------------------------------------------
    // Command bits
    // ------------------------------------------------------------
    localparam int CMD_START_GEMM      = 0;
    localparam int CMD_START_DMA_LOAD  = 1;
    localparam int CMD_START_AXIS_LOAD = 2;
    localparam int CMD_START_DS_LOAD   = 3;
    localparam int CMD_START_DMA_STORE = 4;
    localparam int CMD_CLEAR_DONE      = 8;
    localparam int CMD_CLEAR_ERROR     = 9;
    localparam int CMD_CLEAR_PERF      = 10;

    localparam int JOB_CMD_START       = 0;
    localparam int JOB_CMD_CLEAR_DONE  = 8;
    localparam int JOB_CMD_CLEAR_ERROR = 9;
    localparam int JOB_CMD_CLEAR_PERF  = 10;

    localparam int RECIPE_CMD_START             = 0;
    localparam int RECIPE_CMD_CLEAR_DONE        = 8;
    localparam int RECIPE_CMD_CLEAR_ERROR       = 9;
    localparam int RECIPE_CMD_CLEAR_PERF        = 10;
    localparam int RECIPE_CMD_CLEAR_SLOT_STATUS = 11;

    localparam int DESC_FETCH_CMD_START         = 0;
    localparam int DESC_FETCH_CMD_CLEAR_DONE    = 8;
    localparam int DESC_FETCH_CMD_CLEAR_ERROR   = 9;

    // P17 descriptor-fetch reject/status bits.
    localparam int DESC_FETCH_REJ_BUSY          = 0;
    localparam int DESC_FETCH_REJ_ZERO_COUNT    = 1;
    localparam int DESC_FETCH_REJ_COUNT_RANGE   = 2;
    localparam int DESC_FETCH_REJ_BASE_ALIGN    = 3;
    localparam int DESC_FETCH_REJ_STRIDE_ALIGN  = 4;
    localparam int DESC_FETCH_REJ_STRIDE_SMALL  = 5;

    localparam int COMP_WB_CMD_START       = 0;
    localparam int COMP_WB_CMD_CLEAR_DONE  = 8;
    localparam int COMP_WB_CMD_CLEAR_ERROR = 9;


    localparam int QUEUE_CMD_START       = 0;
    localparam int QUEUE_CMD_STOP        = 1;
    localparam int QUEUE_CMD_CLEAR_DONE     = 8;
    localparam int QUEUE_CMD_CLEAR_ERROR    = 9;
    localparam int QUEUE_CMD_CLEAR_COUNTERS = 10;
    localparam int QUEUE_CMD_RESET_POINTERS = 11;

    localparam int QUEUE_CONTROL_ENABLE          = 0;
    localparam int QUEUE_CONTROL_RUN_UNTIL_EMPTY = 1;
    localparam int QUEUE_CONTROL_STOP_ON_ERROR   = 2;

    localparam int DESC_FETCH_ERR_AXI_RRESP     = 0;
    localparam int DESC_FETCH_ERR_AXI_RLAST     = 1;
    localparam int DESC_FETCH_ERR_DESC_INVALID  = 2;
    localparam int DESC_FETCH_ERR_INTERNAL      = 8;

    localparam int DESC_FETCH_DESCERR_VALID     = 16;
    localparam int DESC_FETCH_DESCERR_OUT_MODE  = 17;
    localparam int DESC_FETCH_DESCERR_DIM_ZERO  = 18;
    localparam int DESC_FETCH_DESCERR_A_ZERO    = 19;
    localparam int DESC_FETCH_DESCERR_B_ZERO    = 20;
    localparam int DESC_FETCH_DESCERR_STORE_ZERO= 21;

    // ------------------------------------------------------------
    // Sticky status bits
    // ------------------------------------------------------------
    localparam int DONE_GEMM      = 0;
    localparam int DONE_DMA_LOAD  = 1;
    localparam int DONE_AXIS_LOAD = 2;
    localparam int DONE_DS_LOAD   = 3;
    localparam int DONE_DMA_STORE = 4;

    localparam int ERR_DMA_LOAD   = 0;
    localparam int ERR_AXIS_LOAD  = 1;
    localparam int ERR_DS_LOAD    = 2;
    localparam int ERR_DMA_STORE  = 3;

    localparam int REJ_UNSUPPORTED = 8;
    localparam int REJ_ZERO_LENGTH = 9;

    localparam int JOB_DONE       = 0;
    localparam int JOB_GEMM_DONE  = 1;
    localparam int JOB_STORE_DONE = 2;

    localparam int JOB_ERR_DMA_LOAD  = 0;
    localparam int JOB_ERR_AXIS_LOAD = 1;
    localparam int JOB_ERR_DS_LOAD   = 2;
    localparam int JOB_ERR_DMA_STORE = 3;
    localparam int JOB_ERR_SEQUENCE  = 8;

    localparam int JOB_REJ_BUSY           = 0;
    localparam int JOB_REJ_MICRO_OP_BUSY  = 1;
    localparam int JOB_REJ_UNSUPPORTED    = 2;
    localparam int JOB_REJ_ZERO_DIM       = 3;
    localparam int JOB_REJ_ZERO_A_LENGTH  = 4;
    localparam int JOB_REJ_ZERO_B_LENGTH  = 5;
    localparam int JOB_REJ_ZERO_STORE_LEN = 6;
    localparam int JOB_REJ_MANUAL_CMD     = 7;
    localparam int JOB_REJ_UNSUPPORTED_COMBO = 8;

    localparam int RECIPE_DONE             = 0;
    localparam int RECIPE_ALL_SLOTS_DONE   = 1;
    localparam int RECIPE_FINAL_STORE_DONE = 2;

    localparam int RECIPE_ERR_SLOT_JOB_ERROR  = 0;
    localparam int RECIPE_ERR_SLOT_JOB_REJECT = 1;
    localparam int RECIPE_ERR_SEQUENCE        = 2;
    localparam int RECIPE_ERR_SLOT_RANGE      = 3;
    localparam int RECIPE_ERR_SLOT_DESC       = 4;

    localparam int RECIPE_REJ_BUSY          = 0;
    localparam int RECIPE_REJ_JOB_BUSY      = 1;
    localparam int RECIPE_REJ_MICRO_OP_BUSY = 2;
    localparam int RECIPE_REJ_ZERO_COUNT    = 3;
    localparam int RECIPE_REJ_SLOT_RANGE    = 4;
    localparam int RECIPE_REJ_SLOT_INVALID  = 5;
    localparam int RECIPE_REJ_SLOT_DESC     = 6;
    localparam int RECIPE_REJ_MANUAL_CMD    = 7;
    localparam int RECIPE_REJ_UNSUPPORTED_COMBO = 8;

    localparam int unsigned DEFAULT_TIMEOUT_CYCLES = 2000;

    csr_vif_t vif;

    function automatic logic [11:0] recipe_slot_addr(
        input int unsigned slot_idx,
        input logic [6:0] slot_offset
    );
    begin
        return CSR_RECIPE_SLOT_BASE + (slot_idx * CSR_RECIPE_SLOT_STRIDE) + slot_offset;
    end
    endfunction

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_csr_access_helper");
        super.new(name);
    endfunction

    // ------------------------------------------------------------
    // Virtual interface binding
    // ------------------------------------------------------------
    function void set_vif(csr_vif_t csr_vif);
        vif = csr_vif;
    endfunction

    function void check_vif();
        if (vif == null) begin
            `uvm_fatal("CSR_HELPER/NOVIF",
                "CSR AXI-Lite virtual interface is not bound")
        end
    endfunction

    // ------------------------------------------------------------
    // Bus initialization
    // ------------------------------------------------------------
    task automatic init_bus();
    begin
        check_vif();

        vif.awaddr  <= '0;
        vif.awprot  <= '0;
        vif.awvalid <= 1'b0;

        vif.wdata   <= '0;
        vif.wstrb   <= '0;
        vif.wvalid  <= 1'b0;

        vif.bready  <= 1'b0;

        vif.araddr  <= '0;
        vif.arprot  <= '0;
        vif.arvalid <= 1'b0;

        vif.rready  <= 1'b0;
    end
    endtask

    // ------------------------------------------------------------
    // Reset wait
    // ------------------------------------------------------------
    task automatic wait_reset_release();
    begin
        check_vif();

        @(posedge vif.clk);
        while (vif.rst_n !== 1'b1) begin
            @(posedge vif.clk);
        end
    end
    endtask

    // ------------------------------------------------------------
    // AXI-Lite write
    // ------------------------------------------------------------
    task automatic write32(
        input  logic [11:0] addr,
        input  logic [31:0] data,
        input  logic [3:0]  strb = 4'hF,
        output logic [1:0]  resp
    );
        bit aw_done;
        bit w_done;
        bit b_done;
        int unsigned cnt;
    begin
        wait_reset_release();

        aw_done = 1'b0;
        w_done  = 1'b0;
        b_done  = 1'b0;
        cnt     = 0;
        resp    = AXI_RESP_OKAY;

        @(posedge vif.clk);
        vif.awaddr  <= addr;
        vif.awprot  <= 3'b000;
        vif.awvalid <= 1'b1;

        vif.wdata   <= data;
        vif.wstrb   <= strb;
        vif.wvalid  <= 1'b1;

        vif.bready  <= 1'b1;

        while (!b_done) begin
            @(posedge vif.clk);

            if (!aw_done && vif.awvalid && vif.awready) begin
                aw_done     = 1'b1;
                vif.awvalid <= 1'b0;
            end

            if (!w_done && vif.wvalid && vif.wready) begin
                w_done     = 1'b1;
                vif.wvalid <= 1'b0;
            end

            if (vif.bvalid && vif.bready) begin
                resp       = vif.bresp;
                b_done     = 1'b1;
                vif.bready <= 1'b0;
            end

            cnt++;
            if (cnt > DEFAULT_TIMEOUT_CYCLES) begin
                `uvm_fatal("CSR_HELPER/WRITE_TIMEOUT",
                    $sformatf("AXI-Lite write timeout: addr=0x%03h data=0x%08h", addr, data))
            end
        end

        @(posedge vif.clk);
        vif.awaddr  <= '0;
        vif.awprot  <= '0;
        vif.wdata   <= '0;
        vif.wstrb   <= '0;
    end
    endtask

    // ------------------------------------------------------------
    // AXI-Lite read
    // ------------------------------------------------------------
    task automatic read32(
        input  logic [11:0] addr,
        output logic [31:0] data,
        output logic [1:0]  resp
    );
        bit ar_done;
        bit r_done;
        int unsigned cnt;
    begin
        wait_reset_release();

        ar_done = 1'b0;
        r_done  = 1'b0;
        cnt     = 0;
        data    = '0;
        resp    = AXI_RESP_OKAY;

        @(posedge vif.clk);
        vif.araddr  <= addr;
        vif.arprot  <= 3'b000;
        vif.arvalid <= 1'b1;
        vif.rready  <= 1'b1;

        while (!r_done) begin
            @(posedge vif.clk);

            if (!ar_done && vif.arvalid && vif.arready) begin
                ar_done     = 1'b1;
                vif.arvalid <= 1'b0;
            end

            if (vif.rvalid && vif.rready) begin
                data       = vif.rdata;
                resp       = vif.rresp;
                r_done     = 1'b1;
                vif.rready <= 1'b0;
            end

            cnt++;
            if (cnt > DEFAULT_TIMEOUT_CYCLES) begin
                `uvm_fatal("CSR_HELPER/READ_TIMEOUT",
                    $sformatf("AXI-Lite read timeout: addr=0x%03h", addr))
            end
        end

        @(posedge vif.clk);
        vif.araddr  <= '0;
        vif.arprot  <= '0;
    end
    endtask

    // ------------------------------------------------------------
    // Convenience checks
    // ------------------------------------------------------------
    task automatic write32_expect_okay(
        input logic [11:0] addr,
        input logic [31:0] data,
        input logic [3:0]  strb = 4'hF
    );
        logic [1:0] resp;
    begin
        write32(addr, data, strb, resp);
        if (resp != AXI_RESP_OKAY) begin
            `uvm_fatal("CSR_HELPER/WRITE_RESP",
                $sformatf("Expected OKAY write response at addr=0x%03h, got resp=%0b", addr, resp))
        end
    end
    endtask

    task automatic read32_expect_okay(
        input  logic [11:0] addr,
        output logic [31:0] data
    );
        logic [1:0] resp;
    begin
        read32(addr, data, resp);
        if (resp != AXI_RESP_OKAY) begin
            `uvm_fatal("CSR_HELPER/READ_RESP",
                $sformatf("Expected OKAY read response at addr=0x%03h, got resp=%0b", addr, resp))
        end
    end
    endtask

    task automatic expect_read32(
        input logic [11:0] addr,
        input logic [31:0] expected,
        input string       tag = ""
    );
        logic [31:0] data;
    begin
        read32_expect_okay(addr, data);
        if (data !== expected) begin
            `uvm_fatal("CSR_HELPER/RD_MISMATCH",
                $sformatf("%s addr=0x%03h expected=0x%08h actual=0x%08h",
                    tag, addr, expected, data))
        end
    end
    endtask

    task automatic issue_command(
        input logic [31:0] command_bits,
        input logic [11:0] command_addr = CSR_COMMAND
    );
    begin
        write32_expect_okay(command_addr, command_bits, 4'hF);
    end
    endtask

endclass

`endif
