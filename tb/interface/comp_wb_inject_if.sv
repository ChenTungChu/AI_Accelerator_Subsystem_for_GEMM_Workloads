// File: tb/interface/comp_wb_inject_if.sv
`ifndef COMP_WB_INJECT_IF_SV
`define COMP_WB_INJECT_IF_SV

// ------------------------------------------------------------
// P18 completion-writeback destination injection interface
//
// TB-only control interface used by completion-writeback error
// validation tests.  It keeps completion-memory BRESP injection out
// of the UVM package and avoids test-to-top hierarchical task calls.
// ------------------------------------------------------------
interface comp_wb_inject_if(input logic clk);

    bit          bresp_error_enable = 1'b0;
    int signed   bresp_error_beat   = -1;
    int unsigned bresp_error_gen    = 0;

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

    task automatic clear();
    begin
        set_bresp_error(1'b0, -1);
    end
    endtask

endinterface

`endif
