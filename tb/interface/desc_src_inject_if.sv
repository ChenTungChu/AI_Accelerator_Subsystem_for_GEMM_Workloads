// File: tb/interface/desc_src_inject_if.sv
// ============================================================
// Descriptor-source injection control interface
//
// Purpose:
//   TB-only control interface used by descriptor-fetch reject/error
//   tests to request descriptor-source AXI RRESP injection without
//   using hierarchical calls into ai_accel_subsys_csr_uvm_top and
//   without adding per-test compile exceptions.
//
// Scope:
//   - Simulation/testbench only
//   - No RTL datapath impact
//   - No BRAM changes
// ============================================================

`ifndef DESC_SRC_INJECT_IF_SV
`define DESC_SRC_INJECT_IF_SV

interface desc_src_inject_if(input logic clk);

    bit          rresp_error_enable;
    int signed   rresp_error_beat;
    int unsigned rresp_error_gen;

    initial begin
        rresp_error_enable = 1'b0;
        rresp_error_beat   = -1;
        rresp_error_gen    = 0;
    end

    task automatic set_rresp_error(
        input bit        enable,
        input int signed relative_read_beat
    );
    begin
        rresp_error_enable = enable;
        rresp_error_beat   = relative_read_beat;
        rresp_error_gen    = rresp_error_gen + 1;
    end
    endtask

endinterface

`endif
