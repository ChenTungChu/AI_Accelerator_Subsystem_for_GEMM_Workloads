// File: tb/uvm/sequencer/axi_mm_host_sequencer.sv
`ifndef AXI_MM_HOST_SEQUENCER_SV
`define AXI_MM_HOST_SEQUENCER_SV

class axi_mm_host_sequencer extends uvm_sequencer #(axi_mm_host_seq_item);
    `uvm_component_utils(axi_mm_host_sequencer)

    // ------------------------------------------------------------
    // Optional debug / bookkeeping
    // ------------------------------------------------------------
    bit          enable_log;
    int unsigned started_item_count;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "axi_mm_host_sequencer",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        enable_log         = 1'b1;
        started_item_count = 0;

        void'(uvm_config_db#(bit)::get(this, "", "enable_log", enable_log));
    endfunction

    // ------------------------------------------------------------
    // Optional helper:
    // sequence side can call this before start_item()/finish_item()
    // if it wants a centralized sequencer-side log.
    // ------------------------------------------------------------
    function void note_item_start(axi_mm_host_seq_item item);
        if (item == null) begin
            `uvm_error("AXI_HOST_SEQ/NUL_ITEM",
                "note_item_start() received null item")
            return;
        end

        started_item_count++;

        if (enable_log) begin
            `uvm_info("AXI_HOST_SEQ",
                $sformatf("Starting host item #%0d: %s",
                    started_item_count, item.convert2string()),
                UVM_MEDIUM)
        end
    endfunction

    // ------------------------------------------------------------
    // Report phase
    // ------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        if (enable_log) begin
            `uvm_info("AXI_HOST_SEQ",
                $sformatf("Sequencer observed %0d started host item(s)",
                    started_item_count),
                UVM_LOW)
        end
    endfunction

endclass

`endif