# File: sim/run_dma.tcl
file mkdir logs

# --------------------------------------------------
# Select DMA testbench top
#   default: axi_mm2s_dma_tb_top
# --------------------------------------------------
if {![info exists DMA_TB_TOP]} {
    set DMA_TB_TOP axi_mm2s_dma_tb_top
}

# --------------------------------------------------
# Supported DMA testbench tops
# --------------------------------------------------
set SUPPORTED_DMA_TB_TOPS [list \
    axi_mm2s_dma_tb_top \
    axi_mm2s_dma_integration_tb_top \
    axi_stream_loader_tb_top \
    axi_mm2s_dma_to_loader_tb_top \
    dma_scratchpad_write_adapter_tb_top \
    axi_mm2s_dma_to_loader_to_adapter_tb_top \
    dma_load_engine_tb_top \
]

if {[lsearch -exact $SUPPORTED_DMA_TB_TOPS $DMA_TB_TOP] < 0} {
    error "Unsupported DMA_TB_TOP='$DMA_TB_TOP'. Supported tops: $SUPPORTED_DMA_TB_TOPS"
}

# --------------------------------------------------
# Optional waveform enable
#   default: 1
# --------------------------------------------------
if {![info exists ENABLE_WAVE]} {
    set ENABLE_WAVE 1
}

# --------------------------------------------------
# Optional transcript tag
#   lets you rename log file when needed
# --------------------------------------------------
if {![info exists DMA_RUN_TAG]} {
    set DMA_RUN_TAG default
}

# --------------------------------------------------
# Transcript log naming
# --------------------------------------------------
set LOG_FILE logs/${DMA_TB_TOP}_${DMA_RUN_TAG}.log

transcript file $LOG_FILE
transcript on

# --------------------------------------------------
# Run simulation
# --------------------------------------------------
vsim -voptargs=+acc work.$DMA_TB_TOP

if {$ENABLE_WAVE} {
    add wave -r sim:/*
}

run -all

transcript off