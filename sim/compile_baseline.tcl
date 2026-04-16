# Clean & create work
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
]

# --------------------------------------------------------
# Compile interfaces
# --------------------------------------------------------
vlog -sv -L uvm12 {*}$INC_LIST ../rtl/interface/axi_mm_if.sv
vlog -sv -L uvm12 {*}$INC_LIST ../rtl/interface/axi_mm_apply_if.sv
vlog -sv -L uvm12 {*}$INC_LIST ../rtl/interface/axi_mm_commit_if.sv

# --------------------------------------------------------
# Compile BRAM
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../rtl/mem/axi_mm_dual_port_bram.sv

# --------------------------------------------------------
# Compile GEMM / Subsystem
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../rtl/gemm/gemm_top.sv
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../rtl/subsystem/gemm_scratchpad_adapter.sv
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../rtl/top/ai_accel_subsys.sv

# --------------------------------------------------------
# Compile top
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../tb/top/ai_accel_subsys_baseline_top.sv

puts "\n==============================="
puts "Compilation Completed!"
puts "===============================\n"