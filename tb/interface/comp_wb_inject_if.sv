// File: tb/interface/comp_wb_inject_if.sv
`ifndef COMP_WB_INJECT_IF_SV
`define COMP_WB_INJECT_IF_SV

// ------------------------------------------------------------
// P18/P24 completion-writeback destination injection interface
//
// TB-only control interface used by completion-writeback error
// validation tests.  It keeps completion-memory BRESP / BID injection
// out of the UVM package and avoids test-to-top hierarchical task calls.
// ------------------------------------------------------------
interface comp_wb_inject_if(input logic clk);

    bit          bresp_error_enable = 1'b0;
    int signed   bresp_error_beat   = -1;
    int unsigned bresp_error_gen    = 0;

    // CODE-COV-C1.2-B: optional TB-only BID mismatch injection.
    // The completion-memory responder returns OKAY BRESP with a nonzero
    // BID for the selected relative AW beat.  The production engine uses
    // AWID=0, so this exercises the genuine ERR_BID protocol path.
    bit          bid_mismatch_enable = 1'b0;
    int signed   bid_mismatch_beat   = -1;
    int unsigned bid_mismatch_gen    = 0;

    // P24E: optional TB-only completion-response block.
    // When enabled for a relative AW beat, the completion-memory responder
    // accepts AW/W but intentionally withholds BVALID.  This models a
    // completion writeback path that is stuck waiting for BRESP, allowing
    // the queue watchdog to expire in the completion-writeback phase.
    bit          bresp_block_enable = 1'b0;
    int signed   bresp_block_beat   = -1;
    int unsigned bresp_block_gen    = 0;

    task automatic set_bresp_error(
        input bit        enable,
        input int signed relative_write_beat
    );
    begin
        bresp_error_enable = enable;
        bresp_error_beat   = relative_write_beat;
        bresp_error_gen    = bresp_error_gen + 1;
    end
    endtask

    task automatic set_bid_mismatch(
        input bit        enable,
        input int signed relative_write_beat
    );
    begin
        bid_mismatch_enable = enable;
        bid_mismatch_beat   = relative_write_beat;
        bid_mismatch_gen    = bid_mismatch_gen + 1;
    end
    endtask

    task automatic set_bresp_block(
        input bit        enable,
        input int signed relative_write_beat
    );
    begin
        bresp_block_enable = enable;
        bresp_block_beat   = relative_write_beat;
        bresp_block_gen    = bresp_block_gen + 1;
    end
    endtask

    task automatic clear();
    begin
        set_bresp_error(1'b0, -1);
        set_bid_mismatch(1'b0, -1);
        set_bresp_block(1'b0, -1);
    end
    endtask

endinterface

`endif
