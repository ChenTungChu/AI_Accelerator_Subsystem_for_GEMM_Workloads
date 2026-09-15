// File: tb/interface/desc_src_inject_if.sv
// ============================================================
// Descriptor-source injection control interface
//
// Purpose:
//   TB-only control interface used by descriptor-fetch reject/error
//   tests to request descriptor-source AXI RRESP / RLAST injection
//   without using hierarchical calls into ai_accel_subsys_csr_uvm_top
//   and without adding per-test compile exceptions.
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

    // CODE-COV-C1.2-B: optional TB-only missing-RLAST injection.
    // The responder still returns one RVALID beat with OKAY RRESP, but
    // drives RLAST low for the selected relative descriptor read beat.
    bit          rlast_error_enable;
    int signed   rlast_error_beat;
    int unsigned rlast_error_gen;

    // CODE-COV-C1.3-B1: legal descriptor-source ARREADY backpressure.
    // Stall cycles are consumed only while descriptor ARVALID is asserted.
    int unsigned arready_stall_cycles;
    int unsigned arready_stall_gen;
    int unsigned arready_stall_observed_count;

    initial begin
        rresp_error_enable = 1'b0;
        rresp_error_beat   = -1;
        rresp_error_gen    = 0;

        rlast_error_enable = 1'b0;
        rlast_error_beat   = -1;
        rlast_error_gen    = 0;

        arready_stall_cycles = 0;
        arready_stall_gen    = 0;
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

    task automatic set_rlast_error(
        input bit        enable,
        input int signed relative_read_beat
    );
    begin
        rlast_error_enable = enable;
        rlast_error_beat   = relative_read_beat;
        rlast_error_gen    = rlast_error_gen + 1;
    end
    endtask

    task automatic set_arready_stall(
        input int unsigned stall_cycles
    );
    begin
        arready_stall_cycles = stall_cycles;
        arready_stall_gen    = arready_stall_gen + 1;
    end
    endtask

    task automatic clear();
    begin
        set_rresp_error(1'b0, -1);
        set_rlast_error(1'b0, -1);
        set_arready_stall(0);
    end
    endtask

endinterface

`endif
