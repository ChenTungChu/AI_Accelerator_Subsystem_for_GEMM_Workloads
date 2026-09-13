# CODE-COV-C1.2-G8-C1 — Statement Exclusion Artifact
# Generated from post-R3 current-source G8-B approved statement ledger.
# Scope: statement coverage ONLY (-code s).
# Canonical RAW UCDB must NOT be opened for modification; apply this only to a copied/effective UCDB.
# Approved semantic statement objects: 174
# Physical statement-bin target count after line-1316 item normalization: 174
# Toggle exclusions: NONE

# ../rtl/csr/ai_accel_csr_regs.sv : 9 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/csr/ai_accel_csr_regs.sv \
    -linerange 1325 \
    -code s
coverage exclude \
    -srcfile ../rtl/csr/ai_accel_csr_regs.sv \
    -linerange 1448 \
    -code s
coverage exclude \
    -srcfile ../rtl/csr/ai_accel_csr_regs.sv \
    -linerange 1499 \
    -code s
coverage exclude \
    -srcfile ../rtl/csr/ai_accel_csr_regs.sv \
    -linerange 2683 \
    -code s
coverage exclude \
    -srcfile ../rtl/csr/ai_accel_csr_regs.sv \
    -linerange 2691 \
    -code s
coverage exclude \
    -srcfile ../rtl/csr/ai_accel_csr_regs.sv \
    -linerange 3850 \
    -code s
coverage exclude \
    -srcfile ../rtl/csr/ai_accel_csr_regs.sv \
    -linerange 3854 \
    -code s
coverage exclude \
    -srcfile ../rtl/csr/ai_accel_csr_regs.sv \
    -linerange 3858 \
    -code s
coverage exclude \
    -srcfile ../rtl/csr/ai_accel_csr_regs.sv \
    -linerange 3862 \
    -code s

# ../rtl/dma/axi_mm2s_dma.sv : 3 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/dma/axi_mm2s_dma.sv \
    -linerange 103 \
    -code s
coverage exclude \
    -srcfile ../rtl/dma/axi_mm2s_dma.sv \
    -linerange 200 \
    -code s
coverage exclude \
    -srcfile ../rtl/dma/axi_mm2s_dma.sv \
    -linerange 269 \
    -code s

# ../rtl/dma/axi_stream_loader.sv : 4 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/dma/axi_stream_loader.sv \
    -linerange 102 \
    -code s
coverage exclude \
    -srcfile ../rtl/dma/axi_stream_loader.sv \
    -linerange 198 \
    -code s
coverage exclude \
    -srcfile ../rtl/dma/axi_stream_loader.sv \
    -linerange 213 \
    -code s
coverage exclude \
    -srcfile ../rtl/dma/axi_stream_loader.sv \
    -linerange 277 \
    -code s

# ../rtl/gemm/gemm_top.sv : 5 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/gemm/gemm_top.sv \
    -linerange 456 \
    -code s
coverage exclude \
    -srcfile ../rtl/gemm/gemm_top.sv \
    -linerange 480 \
    -code s
coverage exclude \
    -srcfile ../rtl/gemm/gemm_top.sv \
    -linerange 504 \
    -code s
coverage exclude \
    -srcfile ../rtl/gemm/gemm_top.sv \
    -linerange 1486 \
    -code s
coverage exclude \
    -srcfile ../rtl/gemm/gemm_top.sv \
    -linerange 1500 \
    -code s

# ../rtl/mem/axi_mm_dual_port_bram.sv : 18 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/mem/axi_mm_dual_port_bram.sv \
    -linerange 773 \
    -code s
coverage exclude \
    -srcfile ../rtl/mem/axi_mm_dual_port_bram.sv \
    -linerange 775 \
    -code s
coverage exclude \
    -srcfile ../rtl/mem/axi_mm_dual_port_bram.sv \
    -linerange 856 \
    -code s
coverage exclude \
    -srcfile ../rtl/mem/axi_mm_dual_port_bram.sv \
    -linerange 858 \
    -code s
coverage exclude \
    -srcfile ../rtl/mem/axi_mm_dual_port_bram.sv \
    -linerange 966 \
    -code s
coverage exclude \
    -srcfile ../rtl/mem/axi_mm_dual_port_bram.sv \
    -linerange 995 \
    -code s
coverage exclude \
    -srcfile ../rtl/mem/axi_mm_dual_port_bram.sv \
    -linerange 1209 \
    -code s
coverage exclude \
    -srcfile ../rtl/mem/axi_mm_dual_port_bram.sv \
    -linerange 1211 \
    -code s
coverage exclude \
    -srcfile ../rtl/mem/axi_mm_dual_port_bram.sv \
    -linerange 1227 \
    -code s
coverage exclude \
    -srcfile ../rtl/mem/axi_mm_dual_port_bram.sv \
    -linerange 1242 \
    -code s
# Line 1316 contains TWO statement items in Questa:
#   item 1 = outer/for statement, covered (10991 hits) -> MUST remain active
#   item 2 = inner-loop body-entry statement, zero-hit structural candidate -> approved
# Use item-selective exclusion so G8-C1 preserves the covered item.
coverage exclude \
    -srcfile ../rtl/mem/axi_mm_dual_port_bram.sv \
    -linerange 1316 \
    -item s 2
coverage exclude \
    -srcfile ../rtl/mem/axi_mm_dual_port_bram.sv \
    -linerange 1318-1319 \
    -code s
coverage exclude \
    -srcfile ../rtl/mem/axi_mm_dual_port_bram.sv \
    -linerange 1324-1326 \
    -code s
coverage exclude \
    -srcfile ../rtl/mem/axi_mm_dual_port_bram.sv \
    -linerange 1457 \
    -code s
coverage exclude \
    -srcfile ../rtl/mem/axi_mm_dual_port_bram.sv \
    -linerange 1474 \
    -code s

# ../rtl/sequencer/ai_accel_completion_wb_engine.sv : 8 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_completion_wb_engine.sv \
    -linerange 236 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_completion_wb_engine.sv \
    -linerange 431-437 \
    -code s

# ../rtl/sequencer/ai_accel_desc_fetch_engine.sv : 3 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_desc_fetch_engine.sv \
    -linerange 524-526 \
    -code s

# ../rtl/sequencer/ai_accel_job_sequencer.sv : 28 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_job_sequencer.sv \
    -linerange 372-373 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_job_sequencer.sv \
    -linerange 384-385 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_job_sequencer.sv \
    -linerange 395-396 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_job_sequencer.sv \
    -linerange 406-407 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_job_sequencer.sv \
    -linerange 416-417 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_job_sequencer.sv \
    -linerange 455-456 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_job_sequencer.sv \
    -linerange 469-470 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_job_sequencer.sv \
    -linerange 480-481 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_job_sequencer.sv \
    -linerange 491-492 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_job_sequencer.sv \
    -linerange 501-502 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_job_sequencer.sv \
    -linerange 540-541 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_job_sequencer.sv \
    -linerange 552-553 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_job_sequencer.sv \
    -linerange 594-595 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_job_sequencer.sv \
    -linerange 616-617 \
    -code s

# ../rtl/sequencer/ai_accel_queue_fetch_controller.sv : 6 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_queue_fetch_controller.sv \
    -linerange 650-653 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_queue_fetch_controller.sv \
    -linerange 669 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_queue_fetch_controller.sv \
    -linerange 845 \
    -code s

# ../rtl/sequencer/ai_accel_recipe_sequencer.sv : 21 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_recipe_sequencer.sv \
    -linerange 254 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_recipe_sequencer.sv \
    -linerange 260 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_recipe_sequencer.sv \
    -linerange 265 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_recipe_sequencer.sv \
    -linerange 270 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_recipe_sequencer.sv \
    -linerange 275 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_recipe_sequencer.sv \
    -linerange 485-486 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_recipe_sequencer.sv \
    -linerange 489 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_recipe_sequencer.sv \
    -linerange 491 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_recipe_sequencer.sv \
    -linerange 493 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_recipe_sequencer.sv \
    -linerange 502 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_recipe_sequencer.sv \
    -linerange 504 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_recipe_sequencer.sv \
    -linerange 506 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_recipe_sequencer.sv \
    -linerange 509-511 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_recipe_sequencer.sv \
    -linerange 525-527 \
    -code s
coverage exclude \
    -srcfile ../rtl/sequencer/ai_accel_recipe_sequencer.sv \
    -linerange 572-573 \
    -code s

# ../rtl/subsystem/axis_async_fifo.sv : 1 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/subsystem/axis_async_fifo.sv \
    -linerange 113 \
    -code s

# ../rtl/subsystem/axis_preload_engine.sv : 9 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/subsystem/axis_preload_engine.sv \
    -linerange 263 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/axis_preload_engine.sv \
    -linerange 445-446 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/axis_preload_engine.sv \
    -linerange 456-457 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/axis_preload_engine.sv \
    -linerange 478-479 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/axis_preload_engine.sv \
    -linerange 497 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/axis_preload_engine.sv \
    -linerange 627 \
    -code s

# ../rtl/subsystem/axis_scratchpad_write_adapter.sv : 7 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/subsystem/axis_scratchpad_write_adapter.sv \
    -linerange 154 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/axis_scratchpad_write_adapter.sv \
    -linerange 252 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/axis_scratchpad_write_adapter.sv \
    -linerange 329-330 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/axis_scratchpad_write_adapter.sv \
    -linerange 353-354 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/axis_scratchpad_write_adapter.sv \
    -linerange 368 \
    -code s

# ../rtl/subsystem/direct_stream_preload_engine.sv : 9 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/subsystem/direct_stream_preload_engine.sv \
    -linerange 285 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/direct_stream_preload_engine.sv \
    -linerange 491-492 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/direct_stream_preload_engine.sv \
    -linerange 502-503 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/direct_stream_preload_engine.sv \
    -linerange 521-522 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/direct_stream_preload_engine.sv \
    -linerange 537 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/direct_stream_preload_engine.sv \
    -linerange 737 \
    -code s

# ../rtl/subsystem/dma_load_engine.sv : 1 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/subsystem/dma_load_engine.sv \
    -linerange 205 \
    -code s

# ../rtl/subsystem/dma_scratchpad_write_adapter.sv : 2 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/subsystem/dma_scratchpad_write_adapter.sv \
    -linerange 124 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/dma_scratchpad_write_adapter.sv \
    -linerange 320 \
    -code s

# ../rtl/subsystem/dma_store_engine.sv : 8 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/subsystem/dma_store_engine.sv \
    -linerange 161 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/dma_store_engine.sv \
    -linerange 346 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/dma_store_engine.sv \
    -linerange 445 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/dma_store_engine.sv \
    -linerange 451 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/dma_store_engine.sv \
    -linerange 458 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/dma_store_engine.sv \
    -linerange 477 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/dma_store_engine.sv \
    -linerange 492 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/dma_store_engine.sv \
    -linerange 513 \
    -code s

# ../rtl/subsystem/gemm_input_mem_router.sv : 15 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/subsystem/gemm_input_mem_router.sv \
    -linerange 271 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/gemm_input_mem_router.sv \
    -linerange 372-373 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/gemm_input_mem_router.sv \
    -linerange 434-435 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/gemm_input_mem_router.sv \
    -linerange 440 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/gemm_input_mem_router.sv \
    -linerange 455-458 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/gemm_input_mem_router.sv \
    -linerange 462-465 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/gemm_input_mem_router.sv \
    -linerange 483 \
    -code s

# ../rtl/subsystem/gemm_operand_buffer.sv : 11 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/subsystem/gemm_operand_buffer.sv \
    -linerange 136 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/gemm_operand_buffer.sv \
    -linerange 217 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/gemm_operand_buffer.sv \
    -linerange 248 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/gemm_operand_buffer.sv \
    -linerange 278 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/gemm_operand_buffer.sv \
    -linerange 381-383 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/gemm_operand_buffer.sv \
    -linerange 452-454 \
    -code s
coverage exclude \
    -srcfile ../rtl/subsystem/gemm_operand_buffer.sv \
    -linerange 486 \
    -code s

# ../rtl/subsystem/gemm_operand_buffer_write_adapter.sv : 1 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/subsystem/gemm_operand_buffer_write_adapter.sv \
    -linerange 127 \
    -code s

# ../rtl/subsystem/scratchpad_port0_owner_mux.sv : 1 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/subsystem/scratchpad_port0_owner_mux.sv \
    -linerange 310 \
    -code s

# ../rtl/subsystem/scratchpad_port1_owner_mux.sv : 1 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/subsystem/scratchpad_port1_owner_mux.sv \
    -linerange 336 \
    -code s

# ../rtl/top/ai_accel_subsys.sv : 1 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/top/ai_accel_subsys.sv \
    -linerange 604 \
    -code s

# ../rtl/top/ai_accel_subsys_csr_top.sv : 2 approved source-line record(s)
coverage exclude \
    -srcfile ../rtl/top/ai_accel_subsys_csr_top.sv \
    -linerange 1084-1085 \
    -code s
