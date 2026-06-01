1. Integration 目標

目前已完成並驗證的 local pipeline 是：

source memory
   -> axi_mm2s_dma
   -> AXI-Stream
   -> axi_stream_loader
   -> linear write request
   -> dma_scratchpad_write_adapter
   -> AXI-MM write
   -> destination memory / scratchpad

v1 subsystem integration 的目標是把這條 pipeline 接進 AI accelerator subsystem，讓 DMA 可以把資料搬進 scratchpad，之後 GEMM core 繼續使用既有 scratchpad path 計算。

2. 不變原則

這幾個東西 v1 不動：

rtl/mem/axi_mm_dual_port_bram.sv
rtl/interface/axi_mm_if.sv
rtl/subsystem/gemm_scratchpad_adapter.sv
rtl/gemm/gemm_top.sv

尤其是：

BRAM 當作已驗證類 IP
不修改 BRAM RTL
不修改 axi_mm_if.sv
不把 DMA module 改回吃 axi_mm_if
DMA / loader / adapter 繼續使用 discrete AXI wires

這樣可以避免前面遇到的 axi_mm_if clocking block / DUT master driving conflict。

3. v1 的整體架構

建議新增一層 wrapper：

rtl/subsystem/dma_load_engine.sv

它把這三顆包起來：

axi_mm2s_dma
axi_stream_loader
dma_scratchpad_write_adapter

形成一個 subsystem 可控的 DMA load engine。

架構圖
                   dma_load_engine
        +--------------------------------------+
        |                                      |
        |  +-------------+    +--------------+ |
src AXI |  | axi_mm2s_dma|--->|stream_loader | |
read -->|  +-------------+    +--------------+ |
        |                         |            |
        |                         v            |
        |             +----------------------+ |
        |             | scratchpad_write_adp | |
        |             +----------------------+ |
        |                         |            |
        +-------------------------|------------+
                                  v
                        scratchpad AXI write side
4. dma_load_engine.sv 建議介面

v1 先做一個最小控制介面。

module dma_load_engine #(
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 64,
    parameter int AXI_ID_WIDTH = 4
)(
    input  logic clk,
    input  logic rst_n,

    // control
    input  logic                  load_start,
    input  logic [ADDR_WIDTH-1:0] src_base_addr,
    input  logic [ADDR_WIDTH-1:0] dst_base_addr,
    input  logic [31:0]           load_beats,

    output logic                  load_busy,
    output logic                  load_done,
    output logic                  load_error,

    // source AXI-MM read master
    output logic [AXI_ID_WIDTH-1:0] src_axi_arid,
    output logic [ADDR_WIDTH-1:0]   src_axi_araddr,
    output logic [7:0]              src_axi_arlen,
    output logic [2:0]              src_axi_arsize,
    output logic [1:0]              src_axi_arburst,
    output logic                    src_axi_arvalid,
    input  logic                    src_axi_arready,

    input  logic [AXI_ID_WIDTH-1:0] src_axi_rid,
    input  logic [DATA_WIDTH-1:0]   src_axi_rdata,
    input  logic [1:0]              src_axi_rresp,
    input  logic                    src_axi_rlast,
    input  logic                    src_axi_rvalid,
    output logic                    src_axi_rready,

    // scratchpad AXI-MM write master
    output logic [AXI_ID_WIDTH-1:0] spad_axi_awid,
    output logic [ADDR_WIDTH-1:0]   spad_axi_awaddr,
    output logic [7:0]              spad_axi_awlen,
    output logic [2:0]              spad_axi_awsize,
    output logic [1:0]              spad_axi_awburst,
    output logic                    spad_axi_awvalid,
    input  logic                    spad_axi_awready,

    output logic [DATA_WIDTH-1:0]   spad_axi_wdata,
    output logic [DATA_WIDTH/8-1:0] spad_axi_wstrb,
    output logic                    spad_axi_wlast,
    output logic                    spad_axi_wvalid,
    input  logic                    spad_axi_wready,

    input  logic [AXI_ID_WIDTH-1:0] spad_axi_bid,
    input  logic [1:0]              spad_axi_bresp,
    input  logic                    spad_axi_bvalid,
    output logic                    spad_axi_bready
);

v1 可以先不暴露 scratchpad read channel，因為 adapter 只會寫。

5. dma_load_engine 控制流程

內部 FSM 建議先做這幾個 state：

S_IDLE
S_START_LOADER
S_START_DMA
S_WAIT_DONE
S_DONE_PULSE
S_IDLE

等待 load_start。

基本檢查：

load_beats != 0
src_base_addr beat-aligned
dst_base_addr beat-aligned

如果 invalid：

load_error = 1
load_done pulse
不啟動 DMA / loader / adapter
S_START_LOADER

先 pulse：

loader_start = 1
loader_expected_beats = load_beats
loader_dst_base_addr = dst_base_addr
S_START_DMA

下一拍 pulse：

dma_start = 1
dma_src_addr = src_base_addr
dma_xfer_len_beats = load_beats
S_WAIT_DONE

等待：

dma_done && loader_done && adapter_done

然後：

load_error = dma_error | loader_error | adapter_error
S_DONE_PULSE

load_done pulse 一拍，然後回 S_IDLE。

6. v1 phase 定義

這是最重要的 subsystem integration 規則。

新增 phase
PHASE_IDLE
PHASE_DMA_LOAD
PHASE_GEMM_RUN
PHASE_READBACK

v1 integration 不需要大改現有 GEMM flow，只要在 GEMM start 前加入 DMA load phase。

7. Port ownership 規則

這部分要特別小心，因為你不想破壞 BRAM。

v1 建議規則
DMA_LOAD phase:
    DMA owns scratchpad write-side path

GEMM_RUN phase:
    GEMM core owns scratchpad core-side path

READBACK phase:
    host / testbench owns readback path

v1 不允許：

DMA_LOAD 和 GEMM_RUN 同時發生
DMA_LOAD 時 host agent 同時寫同一個 scratchpad port
DMA_LOAD 時 core 開始讀取尚未完成的 A/B region

也就是 v1 先用 phase ownership 避免 arbitration 複雜化。

8. Scratchpad port 建議

依照你目前架構，scratchpad 大概可以這樣分：

Port0 / dma_clk side:
    host preload/readback 或 DMA load path

Port1 / core_clk side:
    GEMM core scratchpad adapter

v1 建議：

DMA load writes A/B into scratchpad through dma_clk side
GEMM core continues reading through core_clk side

也就是：

DMA_LOAD:
    dma_scratchpad_write_adapter -> scratchpad Port0

GEMM_RUN:
    gemm_scratchpad_adapter -> scratchpad Port1

不過這裡要注意一件事：你現在 Port0 可能已經被 host AXI path 使用，所以真正接 top 前，要先確認 ai_accel_subsys.sv 裡 Port0 是怎麼接的。

9. Top-level integration 需要解決的問題

真正接進 ai_accel_subsys.sv 時，最重要的是這個：

Port0 owner selection

因為 Port0 可能有兩個來源：

1. existing host AXI path
2. DMA scratchpad write adapter

v1 不能讓兩個 master 同時驅動 Port0。

所以需要一個 ownership rule：

if dma_load_active:
    Port0 owner = DMA write adapter
else:
    Port0 owner = existing host path

實作上可以做成：

rtl/subsystem/scratchpad_port0_owner_mux.sv

不過這顆要等我們看過你目前 ai_accel_subsys.sv 的 Port0 wiring 後再寫，因為它牽涉到 axi_mm_if 的實際接法。

10. v1 不做的事情

v1 先不做：

多 outstanding DMA read
burst read
burst write
DMA descriptor queue
同時 load A/B/C 多 job
DMA load 和 GEMM compute overlap
DMA source 也從同一個 scratchpad port 讀
DMA error abort 後自動 flush loader/adapter
AXI arbitration
CDC 複雜化

目前先維持：

single clock local pipeline
single-beat AXI read
single-beat AXI write
one load job at a time
DMA load completes before GEMM start
11. v1 的限制與風險
風險 1：DMA read error 會讓 loader / adapter 等不到 TLAST

目前 axi_mm2s_dma 如果遇到 RRESP error，可能不會送出完整 AXIS sequence。
這時 loader 可能還在等 TLAST。

所以 v1 subsystem test 先不注入 DMA read-side error。

後面 v2 再加：

abort / clear / soft_reset

到：

axi_stream_loader
dma_scratchpad_write_adapter
dma_load_engine
風險 2：scratchpad Port0 ownership

這是 integration 最大風險。
所以正式改 ai_accel_subsys.sv 前，要先看你目前 Port0 是怎麼接的。

風險 3：axi_mm_if.sv 不適合 RTL master 直接驅動

前面我們已經遇到過這個問題，所以 v1 不讓 DMA module 吃 axi_mm_if。
所有 DMA RTL 繼續使用 discrete AXI wires。

12. 建議測試順序
Step 1：新增 dma_load_engine.sv

先不要碰 ai_accel_subsys.sv。

做一個 local TB：

tb/dma/dma_load_engine_tb_top.sv

測：

source memory -> dma_load_engine -> destination AXI write slave
Step 2：驗 dma_load_engine

至少跑：

exact-length load
capture-until-TLAST 不需要，engine v1 固定 expected_beats = load_beats
write-side backpressure
adapter BRESP error
invalid load_beats = 0
invalid unaligned src/dst
Step 3：再看 ai_accel_subsys.sv

確認：

scratchpad Port0 connection
host AXI path
reset
clock domain
existing testbench control signals
Step 4：做 subsystem-level DMA load smoke

新增 UVM 或 non-UVM test：

DMA load A/B -> GEMM run -> readback C -> compare

13.  v1 完成標準
這個 integration v1 算完成，需要滿足：

[1] dma_load_engine unit/integration TB PASS
[2] ai_accel_subsys.sv 可以選擇 DMA_LOAD phase
[3] DMA load A/B 到 scratchpad
[4] GEMM core 使用 DMA-loaded A/B 正常完成
[5] result check PASS
[6] existing smoke/back-to-back/reset regression 不被破壞

14. P13 C RMW compatibility note

P13 does not change the DMA load protocol.

For P13 C read-modify-write accumulation, the DMA load path is used repeatedly to provide compact A/B payloads for each partial job:

```text
for each partial job:
    DMA load A_part into scratchpad
    DMA load B_part into scratchpad
    GEMM computes partial C
    if accumulate_enable=1, GEMM reads old C from scratchpad and accumulates
```

C remains in scratchpad between partial jobs.  The DMA load engine must not clear or overwrite C as part of A/B preload.

P13 frontend representative validation includes:

```text
DMA load-store CASE_ID=211 PASS
Full regression after P13G: 82/82 PASS
```

The original v1 rule still holds:

```text
DMA load completes before GEMM start.
DMA load and GEMM compute do not overlap in this baseline.
BRAM RTL remains unchanged.
```
