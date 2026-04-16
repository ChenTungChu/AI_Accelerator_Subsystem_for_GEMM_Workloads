// File: tb/uvm/sequencer/ai_accel_subsys_sequencer.sv

`ifndef AI_ACCEL_SUBSYS_SEQUENCER_SV
`define AI_ACCEL_SUBSYS_SEQUENCER_SV

class ai_accel_subsys_sequencer extends uvm_sequencer #(ai_accel_subsys_seq_item);
    `uvm_component_utils(ai_accel_subsys_sequencer)

    function new(string name = "ai_accel_subsys_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass

`endif