# P24C compile script: queue timeout watchdog RTL compile smoke
# Derived from the P22D integrated CSR/queue/event compile flow.
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
# CODE-COV-A RTL code coverage instrumentation
#
# Default:
#   CODE_COV_ENABLE=0 keeps the historical compile flow.
#
# Code coverage compile:
#   set CODE_COV_ENABLE 1
#   do compile_uvm.tcl
#
# Metrics:
#   b = branch
#   c = condition
#   e = expression
#   f = FSM
#   s = statement
#   t = toggle
#
# Only synthesizable RTL / DUT files receive +cover.
# UVM, testbench interfaces, test tops, memory responders,
# reference models, and simulator libraries are not instrumented.
# --------------------------------------------------------
if {![info exists CODE_COV_ENABLE]} {
    set CODE_COV_ENABLE 0
}

if {($CODE_COV_ENABLE != 0) && ($CODE_COV_ENABLE != 1)} {
    error "Unsupported CODE_COV_ENABLE='$CODE_COV_ENABLE'. Supported values: 0, 1"
}

if {![info exists CODE_COV_METRICS]} {
    set CODE_COV_METRICS bcefst
}

if {![regexp {^[bcefst]+$} $CODE_COV_METRICS]} {
    error "Unsupported CODE_COV_METRICS='$CODE_COV_METRICS'. Use only b, c, e, f, s, t"
}

set RTL_COVERAGE_ARGS [list]
set CODE_COV_MARKER_FILE [file join work .code_cov_instrumented]

if {$CODE_COV_ENABLE} {
    lappend RTL_COVERAGE_ARGS +cover=$CODE_COV_METRICS
    puts "INFO: RTL code coverage instrumentation enabled"
    puts "INFO: CODE_COV_METRICS=$CODE_COV_METRICS"
} else {
    puts "INFO: RTL code coverage instrumentation disabled"
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
  "+incdir+../rtl/csr" \
  "+incdir+../rtl/sequencer" \
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
vlog -sv -L uvm12 {*}$INC_LIST ../rtl/interface/axi_lite_if.sv
vlog -sv -L uvm12 {*}$INC_LIST ../tb/interface/ai_accel_subsys_ctrl_if.sv
vlog -sv -L uvm12 {*}$INC_LIST ../tb/interface/desc_src_inject_if.sv
vlog -sv -L uvm12 {*}$INC_LIST ../tb/interface/comp_wb_inject_if.sv

# --------------------------------------------------------
# Compile RTL / DUT
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/mem/axi_mm_dual_port_bram.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/gemm/gemm_top.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/dma/axi_mm2s_dma.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/dma/axi_mm2s_dma_sink.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/dma/axi_stream_loader.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/subsystem/dma_scratchpad_write_adapter.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/subsystem/dma_load_engine.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/subsystem/scratchpad_port0_owner_mux.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/subsystem/scratchpad_port1_owner_mux.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/subsystem/axis_async_fifo.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/subsystem/axis_preload_engine.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/subsystem/gemm_scratchpad_adapter.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/subsystem/dma_store_engine.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/subsystem/axis_scratchpad_write_adapter.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/subsystem/gemm_operand_buffer.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/subsystem/gemm_operand_buffer_write_adapter.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/subsystem/direct_stream_preload_engine.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/subsystem/gemm_input_mem_router.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/top/ai_accel_subsys.sv

# --------------------------------------------------------
# Compile CSR control-plane RTL / job sequencer
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/csr/ai_accel_csr_regs.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/sequencer/ai_accel_job_sequencer.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/sequencer/ai_accel_recipe_sequencer.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/sequencer/ai_accel_desc_fetch_engine.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/sequencer/ai_accel_completion_wb_engine.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/sequencer/ai_accel_queue_fetch_controller.sv
vlog -sv -timescale 1ns/1ps +acc {*}$RTL_COVERAGE_ARGS -L uvm12 {*}$INC_LIST ../rtl/top/ai_accel_subsys_csr_top.sv

# --------------------------------------------------------
# Compile UVM package
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../tb/uvm/pkg/ai_accel_subsys_uvm_pkg.sv

# --------------------------------------------------------
# Compile UVM tops
# --------------------------------------------------------
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../tb/top/ai_accel_subsys_uvm_top.sv
# The standalone CSR-register-block top depends on ai_accel_csr_regs_smoke_test.sv.
# Some integrated subsystem-only branches do not carry that standalone unit test.
# P22C uses ai_accel_subsys_csr_uvm_top, so keep compile robust by compiling the
# standalone CSR-regs top only when its owned test file exists.
if {[file exists "../tb/uvm/test/ai_accel_csr_regs_smoke_test.sv"]} {
    vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../tb/top/ai_accel_csr_regs_uvm_top.sv
} else {
    puts "INFO: Skipping ai_accel_csr_regs_uvm_top.sv because ../tb/uvm/test/ai_accel_csr_regs_smoke_test.sv was not found."
    puts "INFO: Integrated subsystem CSR tests still compile through ai_accel_subsys_csr_uvm_top.sv."
}
vlog -sv -timescale 1ns/1ps +acc -L uvm12 {*}$INC_LIST ../tb/top/ai_accel_subsys_csr_uvm_top.sv


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

if {$CODE_COV_ENABLE} {
    set marker_fp [open $CODE_COV_MARKER_FILE w]
    puts $marker_fp $CODE_COV_METRICS
    close $marker_fp

    puts "INFO: CODE-COV instrumentation marker: $CODE_COV_MARKER_FILE"
}

puts "\n==============================="
puts "Compilation Completed!"
puts "===============================\n"
