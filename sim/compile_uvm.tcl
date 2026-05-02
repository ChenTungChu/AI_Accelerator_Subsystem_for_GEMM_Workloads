# --------------------------------------------------------
# Clean & create work
# --------------------------------------------------------
if { [file exists work] } {
    vdel -lib work -all
}
vlib work
vmap work work

# --------------------------------------------------------
# Local override
# --------------------------------------------------------
if {[file exists "local_uvm_12.tcl"]} {
    puts "INFO: Loading local_uvm_12.tcl"
    do local_uvm_12.tcl
} else {
    puts "ERROR: local_uvm_12.tcl not found"
    puts "Please create local_uvm_12.tcl with UVM path settings"
    quit -f
}

# --------------------------------------------------------
# Build UVM 1.2
# --------------------------------------------------------
if { [file exists uvm12] } {
    vdel -lib uvm12 -all
}
vlib uvm12
vmap uvm12 uvm12

set UVM12_INCS [list "+incdir+$UVM12_SRC"]

vlog -sv -work uvm12 +define+UVM_NO_DPI {*}$UVM12_INCS $UVM12_PKG

# --------------------------------------------------------
# Include directories
# --------------------------------------------------------
set INC_LIST [list \
  "+incdir+$UVM12_SRC" \
  "+incdir+../rtl/interface" \
  "+incdir+../rtl/top" \
  "+incdir+../rtl/gemm" \
  "+incdir+../rtl/subsystem" \
  "+incdir+../rtl/mem" \
  "+incdir+../rtl/dma" \
  "+incdir+../tb/interface" \
  "+incdir+../tb/dma" \
  "+incdir+../tb/uvm/pkg" \
  "+incdir+../tb/uvm/item" \
  "+incdir+../tb/uvm/helper" \
  "+incdir+../tb/uvm/bridge" \
  "+incdir+../tb/uvm/seq_item" \
  "+incdir+../tb/uvm/sequencer" \
  "+incdir+../tb/uvm/driver" \
  "+incdir+../tb/uvm/monitor" \
  "+incdir+../tb/uvm/scoreboard" \
  "+incdir+../tb/uvm/agent" \
  "+incdir+../tb/uvm/env" \
  "+incdir+../tb/uvm/seq" \
  "+incdir+../tb/uvm/test" \
  "+incdir+../tb/top" \
]

# --------------------------------------------------------
# Compile interfaces
# --------------------------------------------------------
vlog -sv -L uvm12 {*}$INC_LIST ../rtl/interface/axi_mm_if.sv
vlog -sv -L uvm12 {*}$INC_LIST ../rtl/interface/axi_mm_apply_if.sv
vlog -sv -L uvm12 {*}$INC_LIST ../rtl/interface/axi_mm_commit_if.sv
vlog -sv -L uvm12 {*}$INC_LIST ../tb/interface/ai_accel_subsys_ctrl_if.sv

# --------------------------------------------------------
# Compile RTL / DUT
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../rtl/mem/axi_mm_dual_port_bram.sv
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../rtl/gemm/gemm_top.sv
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../rtl/dma/axi_mm2s_dma.sv
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../rtl/dma/axi_mm2s_dma_sink.sv
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../rtl/dma/axi_stream_loader.sv
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../rtl/subsystem/dma_scratchpad_write_adapter.sv
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../rtl/subsystem/dma_load_engine.sv
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../rtl/subsystem/scratchpad_port0_owner_mux.sv
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../rtl/subsystem/gemm_scratchpad_adapter.sv
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../rtl/top/ai_accel_subsys.sv

# --------------------------------------------------------
# Compile UVM package
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../tb/uvm/pkg/ai_accel_subsys_uvm_pkg.sv

# --------------------------------------------------------
# Compile UVM top
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../tb/top/ai_accel_subsys_uvm_top.sv

# --------------------------------------------------------
# Compile DMA unit-level TB
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../tb/dma/axi_mm2s_dma_tb_top.sv

# --------------------------------------------------------
# Compile DMA + sink integration TB
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../tb/dma/axi_mm2s_dma_integration_tb_top.sv

# --------------------------------------------------------
# Compile Loader unit-level TB
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../tb/dma/axi_stream_loader_tb_top.sv

# --------------------------------------------------------
# Compile DMA -> Loader integration TB
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../tb/dma/axi_mm2s_dma_to_loader_tb_top.sv

# --------------------------------------------------------
# Compile scratchpad write adapter unit-level TB
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../tb/dma/dma_scratchpad_write_adapter_tb_top.sv

# --------------------------------------------------------
# Compile DMA -> Loader -> Adapter integration TB
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../tb/dma/axi_mm2s_dma_to_loader_to_adapter_tb_top.sv

# --------------------------------------------------------
# Compile DMA load engine unit-level TB
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../tb/dma/dma_load_engine_tb_top.sv

puts "\n==============================="
puts "Compilation Completed!"
puts "===============================\n"