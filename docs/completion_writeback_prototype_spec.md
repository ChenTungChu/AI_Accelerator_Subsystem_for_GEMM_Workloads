# P18 Completion Writeback Prototype Spec

## 1. Purpose

This document defines the P18 completion-writeback prototype for the AI Accelerator Subsystem.

P17 completed the memory-resident command ingress path:

```text
external descriptor memory
    -> P17 descriptor fetch engine
    -> fetched P16-compatible recipe snapshot
    -> existing P16 recipe sequencer
    -> existing P15 job sequencer
    -> existing datapath
    -> CSR-visible done / error / reject status
```

P18 adds the matching host-visible completion egress path:

```text
recipe terminal status / fetch terminal status
    -> P18 completion record builder
    -> completion writeback engine
    -> external host-visible completion memory
```

The goal is to let a host use memory both for command submission and for completion observation:

```text
host writes descriptor table in memory
host programs descriptor-fetch CSR window
host programs completion base address
host starts descriptor fetch
hardware fetches descriptors and runs the recipe
hardware writes a compact completion record back to memory
host polls completion memory or CSR status
```

Current baseline entering P18A:

```text
P17H/P17I descriptor-fetch closure:
  TOTAL : 105
  PASS  : 105
  FAIL  : 0
```

---

## 2. P18A Scope

P18A defines the architecture and software-visible contract for a small completion-writeback prototype.

P18A includes:

```text
completion writeback design intent
completion record format
completion commit / valid-word policy
completion CSR window proposal
completion writeback engine behavior
completion writeback error handling policy
relationship to P17 descriptor fetch
relationship to P16 recipe sequencer and P15 job worker
UVM validation plan
full-regression closure plan
```

P18A does not implement RTL.  RTL implementation, CSR plumbing, and UVM tests are later P18 milestones.

---

## 3. Fixed P18A Design Decisions

```text
Completion destination             : external host-visible completion memory
Completion interface               : dedicated completion-memory AXI write master
Completion record count            : one record per accepted descriptor-fetch command
Completion record size             : 64 bytes, 16 logical 32-bit words
Physical AXI data width            : 64-bit baseline, two 32-bit words per beat
Completion commit policy           : write payload words first, commit word last
Completion valid indication        : final write to word0 with VALID bit set
Completion base source             : CSR-programmed completion base address
Descriptor format change           : not required for P18A
P17 descriptor fetch behavior      : reused unchanged
P16 recipe sequencer behavior      : reused unchanged
P15 job worker behavior            : reused unchanged
BRAM / GEMM / DMA / frontend paths : unchanged
Interrupt output                   : not included in P18A
Ring buffer / queue head-tail      : not included in P18A
Multiple outstanding completions   : not included in P18A
```

P18A intentionally keeps the completion model small.  It completes the memory-backed prototype without turning the subsystem into a full host driver, interrupt controller, or multi-outstanding command queue.

---

## 4. P18 Relationship to Existing Milestones

### 4.1 P14 / P15 / P16 / P17 Stack

The current control stack is:

```text
P14: AXI-Lite CSR micro-operation control
P15: CSR-resident single-job descriptor + job sequencer
P16: CSR-resident multi-slot recipe sequencer
P17: memory-resident descriptor fetch into P16-compatible recipe snapshot
P18: memory-resident completion writeback after terminal status
```

P18 should sit beside the P17 descriptor-fetch path and observe terminal status from P17/P16.  It should not become a new scheduler.

Recommended partition:

```text
ai_accel_subsys_csr_top
    AXI-Lite CSR slave port
        -> ai_accel_csr_regs
            -> P14 micro-operation CSRs
            -> P15 job descriptor CSRs
            -> P16 recipe CSRs
            -> P17 descriptor-fetch CSRs
            -> P18 completion-writeback CSRs

    P17 descriptor fetch engine
        -> fetched recipe snapshot
        -> P16 recipe sequencer
            -> P15 job sequencer
                -> ai_accel_subsys datapath

    P18 completion writeback engine
        <- terminal fetch / recipe status snapshot
        -> external completion-memory AXI write master
```

### 4.2 P18 Does Not Replace CSR Status

P18 adds a memory-visible completion record.  It does not remove or redefine existing CSR status registers.

Software may use either or both:

```text
CSR polling path:
  read P17 / P16 / P15 status registers

Completion-memory path:
  poll completion record word0 VALID bit
  read completion record payload
```

The CSR path remains useful for debug and for writeback-error reporting.

---

## 5. Completion Trigger Model

P18 should generate a completion writeback for one accepted descriptor-fetch command when completion writeback is enabled.

Terminal events that can request completion writeback:

```text
1. descriptor fetch / validation fails before recipe launch
2. descriptor fetch succeeds and recipe completes successfully
3. descriptor fetch succeeds and recipe reports recipe error
4. descriptor fetch succeeds and recipe reports recipe reject / worker reject
```

Command rejects before a descriptor-fetch command is accepted do not require completion writeback because no memory command context has been accepted.

Examples that should remain CSR-only rejects:

```text
START_FETCH while fetch_busy
START_FETCH while recipe_busy, when rejected before accept
DESC_COUNT=0 reject before issuing descriptor reads
unsupported command-bit combination
```

A later implementation may optionally write completion records for pre-accept command rejects, but P18A keeps the model simple:

```text
accepted descriptor-fetch command -> exactly one terminal completion attempt when enabled
rejected descriptor-fetch command -> CSR reject only
```

---

## 6. Completion Record Format

P18A uses one fixed 64-byte completion record.

```text
Completion record size = 0x40 bytes
Logical word size      = 32 bits
Words per record       = 16
64-bit AXI beats       = 8
```

The host should initialize word0 to zero before starting a command.  Hardware writes word0 last with `VALID=1`.  This creates a simple memory polling contract.

### 6.1 Record Layout

| Byte Offset | Word Index | Name | Description |
|---:|---:|---|---|
| 0x00 | 0  | `COMP_COMMIT` | Commit / valid word. Written last. |
| 0x04 | 1  | `COMP_STATUS_FLAGS` | Overall done/error/reject/fetch/recipe flags. |
| 0x08 | 2  | `COMP_FIRST_USER_TAG` | User tag from the first fetched descriptor. |
| 0x0C | 3  | `COMP_LAST_USER_TAG` | User tag from the last fetched descriptor. |
| 0x10 | 4  | `COMP_COUNT_SUMMARY` | Packed descriptor/fetch/completed counts. |
| 0x14 | 5  | `COMP_DESC_FETCH_DONE_STATUS` | Sticky P17 descriptor-fetch done status snapshot. |
| 0x18 | 6  | `COMP_DESC_FETCH_ERROR_STATUS` | Sticky P17 descriptor-fetch error status snapshot. |
| 0x1C | 7  | `COMP_DESC_FETCH_REJECT_STATUS` | Sticky P17 descriptor-fetch reject status snapshot. |
| 0x20 | 8  | `COMP_RECIPE_DONE_STATUS` | Sticky P16 recipe done status snapshot. |
| 0x24 | 9  | `COMP_RECIPE_ERROR_STATUS` | Sticky P16 recipe error status snapshot. |
| 0x28 | 10 | `COMP_RECIPE_REJECT_STATUS` | Sticky P16 recipe reject status snapshot. |
| 0x2C | 11 | `COMP_SLOT_MASK_SUMMARY` | Packed slot done/error/reject masks. |
| 0x30 | 12 | `COMP_PERF_BUSY_CYCLES` | Recipe accumulated busy-cycle snapshot. |
| 0x34 | 13 | `COMP_PERF_MAC_COUNT` | Recipe accumulated MAC count snapshot. |
| 0x38 | 14 | `COMP_PERF_OUTPUT_COUNT` | Recipe accumulated output count snapshot. |
| 0x3C | 15 | `COMP_ERROR_DETAIL` | Fetch/recipe/writeback debug detail. |

### 6.2 `COMP_COMMIT` Word

`COMP_COMMIT` is written last.

Recommended bit fields:

| Bits | Name | Description |
|---:|---|---|
| 0 | `VALID` | Completion record is committed and may be consumed by host. |
| 1 | `OVERALL_DONE` | Command reached a successful terminal state. |
| 2 | `OVERALL_ERROR` | Command reached an error terminal state. |
| 3 | `OVERALL_REJECT` | Accepted command or launched recipe observed a reject terminal condition. |
| 7:4 | `RSVD` | Reserved. |
| 15:8 | `FEATURE_ID` | `8'h18` for P18 completion writeback. |
| 23:16 | `MINOR` | Completion format minor version. |
| 31:24 | `MAJOR` | Completion format major version. |

Recommended successful commit value pattern:

```text
VALID=1, OVERALL_DONE=1, FEATURE_ID=0x18, VERSION=1.0
```

Example conceptual value:

```text
0x0100_1803
```

This means:

```text
MAJOR=1
MINOR=0
FEATURE_ID=0x18
VALID=1
OVERALL_DONE=1
```

### 6.3 `COMP_STATUS_FLAGS` Word

Recommended bit fields:

| Bit | Name | Description |
|---:|---|---|
| 0 | `FETCH_ACCEPTED` | Descriptor-fetch command was accepted. |
| 1 | `FETCH_DONE` | Descriptor fetch completed successfully. |
| 2 | `FETCH_ERROR` | Descriptor fetch ended with error. |
| 3 | `FETCH_REJECT` | Descriptor fetch had a reject condition after accepted context. |
| 4 | `SNAPSHOT_VALID` | P17 built a fetched recipe snapshot. |
| 5 | `RECIPE_LAUNCHED` | P17 launched P16 recipe path. |
| 6 | `RECIPE_DONE` | P16 recipe completed successfully. |
| 7 | `RECIPE_ERROR` | P16 recipe completed with error. |
| 8 | `RECIPE_REJECT` | P16 recipe or P15 worker rejected a launched operation. |
| 9 | `COMPLETION_WB_ERROR` | Completion writeback error was observed.  Usually CSR-only if final commit failed. |
| 31:10 | `RSVD` | Reserved. |

Note: If completion writeback itself fails before word0 is committed, the host may not see this bit in memory.  The CSR completion error status is the authoritative source for writeback errors.

### 6.4 `COMP_COUNT_SUMMARY` Word

Recommended packing:

| Bits | Name | Description |
|---:|---|---|
| 7:0 | `DESC_COUNT` | CSR programmed descriptor count. |
| 15:8 | `FETCHED_COUNT` | Number of descriptors fetched successfully. |
| 23:16 | `COMPLETED_COUNT` | Number of recipe slots completed. |
| 31:24 | `CURRENT_OR_ERROR_INDEX` | Current descriptor / error index. |

### 6.5 `COMP_SLOT_MASK_SUMMARY` Word

Recommended packing:

| Bits | Name | Description |
|---:|---|---|
| 7:0 | `SLOT_DONE_MASK` | P16 slot done mask. |
| 15:8 | `SLOT_ERROR_MASK` | P16 slot error mask. |
| 23:16 | `SLOT_REJECT_MASK` | P16 slot reject mask. |
| 31:24 | `RSVD` | Reserved. |

---

## 7. Completion Commit Policy

P18 must avoid exposing a partially written completion record as valid.

Required write order:

```text
1. write record words 1 through 15
2. wait for successful write responses for payload words
3. write record word0 COMP_COMMIT with VALID=1
4. wait for successful write response for commit word
5. set CSR completion done sticky status
```

Host polling contract:

```text
host clears or initializes COMP_COMMIT word0 to 0
host starts descriptor fetch / recipe command
host polls completion_record[0].VALID
when VALID=1, host may read the rest of the record
```

This is not a full cache-coherent memory contract.  It is a verification-level host-visible memory protocol for the P18 prototype.

---

## 8. Completion CSR Window Proposal

P17 uses the `0x500 - 0x53C` descriptor-fetch CSR window.  P18 should extend the same high-level control region with a completion-writeback sub-window at `0x540` and above.

```text
P14 micro-operation CSR window : 0x000 - 0x08C
P15 job CSR window             : 0x100 - 0x18C
P16 recipe CSR window          : 0x200 - 0x28C
P16 slot CSR window            : 0x300 - 0x4FC
P17 descriptor fetch window    : 0x500 - 0x53C
P18 completion writeback window: 0x540 - 0x57C
```

### 8.1 CSR Register Map

| Offset | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0x540 | `CSR_COMP_VERSION` | RO | `0x0001_0018` | Completion writeback version / feature ID. |
| 0x544 | `CSR_COMP_COMMAND` | W1P | 0 | Completion sticky clear commands. |
| 0x548 | `CSR_COMP_STATUS` | RO | implementation | Live completion-writeback status summary. |
| 0x54C | `CSR_COMP_DONE_STATUS` | RO/W1C | 0 | Sticky completion-writeback done status. |
| 0x550 | `CSR_COMP_ERROR_STATUS` | RO/W1C | 0 | Sticky completion-writeback error status. |
| 0x554 | `CSR_COMP_CONTROL` | RW | `0x0000_0007` | Completion policy bits. |
| 0x558 | `CSR_COMP_REJECT_STATUS` | RO/W1C | 0 | Sticky completion command / config reject status. |
| 0x55C | `CSR_COMP_BASE_ADDR` | RW | 0 | Base address of the 64-byte completion record. |
| 0x560 | `CSR_COMP_LAST_COMMIT` | RO | 0 | Last committed `COMP_COMMIT` word. |
| 0x564 | `CSR_COMP_WRITTEN_COUNT` | RO | 0 | Number of completion records successfully committed. |
| 0x568 | `CSR_COMP_ERROR_DETAIL` | RO | 0 | Last completion writeback error detail. |
| 0x56C | `CSR_COMP_STATE` | RO | 0 | Current completion writeback FSM state. |
| 0x570 | `CSR_COMP_RESERVED_570` | RO | 0 | Reserved. |
| 0x574 | `CSR_COMP_RESERVED_574` | RO | 0 | Reserved. |
| 0x578 | `CSR_COMP_RESERVED_578` | RO | 0 | Reserved. |
| 0x57C | `CSR_COMP_RESERVED_57C` | RO | 0 | Reserved. |

### 8.2 `CSR_COMP_COMMAND` at 0x544

Reads return zero.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 8 | `CLEAR_COMP_DONE` | W1P | Clear completion done sticky bits. |
| 9 | `CLEAR_COMP_ERROR` | W1P | Clear completion error and reject sticky bits. |
| 10 | `CLEAR_COMP_COUNTERS` | W1P | Clear `CSR_COMP_WRITTEN_COUNT` and last commit/debug snapshots. |

No explicit `START_COMPLETION` command is required in P18A.  Completion writeback starts from P17/P16 terminal status when enabled.

### 8.3 `CSR_COMP_STATUS` at 0x548

| Bit | Name | Access | Description |
|---:|---|---|
| 0 | `COMP_BUSY` | RO | Completion writeback engine is writing the record. |
| 1 | `COMP_DONE` | RO | Sticky completion writeback done is set. |
| 2 | `COMP_ERROR` | RO | Sticky completion writeback error or reject is set. |
| 3 | `COMP_ACCEPT_READY` | RO | Completion engine is idle and can accept a terminal event. |
| 4 | `COMP_ENABLED` | RO | Completion writeback is enabled by CSR control. |
| 8 | `FETCH_BUSY` | RO | P17 descriptor fetch is busy. |
| 9 | `RECIPE_BUSY` | RO | P16 recipe sequencer is busy. |
| 16 | `CSR_READY` | RO | CSR block ready for transactions. |

### 8.4 `CSR_COMP_DONE_STATUS` at 0x54C

| Bit | Name | Type | Description |
|---:|---|---|
| 0 | `COMP_WRITE_DONE` | RO/W1C | Completion record payload and commit word were written successfully. |
| 1 | `COMP_COMMIT_DONE` | RO/W1C | Final commit word write completed successfully. |

### 8.5 `CSR_COMP_ERROR_STATUS` at 0x550

| Bit | Name | Type | Description |
|---:|---|---|
| 0 | `COMP_AXI_WRITE_ERROR` | RO/W1C | Completion memory write returned non-OKAY response. |
| 1 | `COMP_UNALIGNED_BASE_ERROR` | RO/W1C | Completion base address was not aligned. |
| 2 | `COMP_BUSY_SEQUENCE_ERROR` | RO/W1C | Terminal event arrived while completion engine was already busy. |
| 3 | `COMP_FSM_ERROR` | RO/W1C | Completion FSM reached an illegal state. |
| 8 | `COMP_TIMEOUT_RESERVED` | RO/W1C | Reserved for future timeout support. |

### 8.6 `CSR_COMP_CONTROL` at 0x554

| Bits | Name | Access | Reset | Description |
|---:|---|---:|---|
| 0 | `COMP_ENABLE` | RW | 1 | Enable completion writeback on accepted descriptor-fetch terminal events. |
| 1 | `WRITE_ON_FETCH_ERROR` | RW | 1 | Write a completion record when descriptor fetch / validation errors before recipe launch. |
| 2 | `WRITE_ON_RECIPE_TERMINAL` | RW | 1 | Write a completion record when launched recipe reaches done/error terminal state. |
| 3 | `CLEAR_COMP_STICKY_ON_START` | RW | 0 | Clear completion sticky state when a new descriptor-fetch command is accepted. |
| 4 | `REQUIRE_BASE_NONZERO` | RW | 0 | Optionally reject completion enable when base address is zero. |
| 31:5 | `RSVD` | RO | 0 | Reserved. |

Recommended reset value:

```text
0x0000_0007
```

### 8.7 `CSR_COMP_REJECT_STATUS` at 0x558

| Bit | Name | Type | Description |
|---:|---|---|
| 0 | `COMP_BUSY_REJECT` | RO/W1C | Completion request arrived while completion engine was busy. |
| 1 | `COMP_DISABLED_DROP` | RO/W1C | Completion event was dropped because completion writeback was disabled. |
| 2 | `COMP_BASE_INVALID_REJECT` | RO/W1C | Completion base was invalid under the configured policy. |
| 8 | `UNSUPPORTED_COMBO` | RO/W1C | Unsupported completion command-bit combination. |

A disabled-drop status is a debug aid.  It is not necessarily an error if software intentionally disabled completion writeback.

---

## 9. Completion Writeback Engine Interface

Recommended RTL module name:

```text
rtl/sequencer/ai_accel_completion_wb_engine.sv
```

Recommended interface direction:

```systemverilog
module ai_accel_completion_wb_engine #(
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 64,
    parameter int AXI_ID_WIDTH = 4
)(
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  wb_start,
    input  logic [ADDR_WIDTH-1:0] wb_base_addr,
    input  logic [31:0]           wb_record_words [16],

    output logic                  wb_busy,
    output logic                  wb_done,
    output logic                  wb_error,
    output logic [31:0]           wb_error_detail,

    output logic [AXI_ID_WIDTH-1:0] comp_axi_awid,
    output logic [ADDR_WIDTH-1:0]   comp_axi_awaddr,
    output logic [7:0]              comp_axi_awlen,
    output logic [2:0]              comp_axi_awsize,
    output logic [1:0]              comp_axi_awburst,
    output logic                    comp_axi_awvalid,
    input  logic                    comp_axi_awready,

    output logic [DATA_WIDTH-1:0]   comp_axi_wdata,
    output logic [DATA_WIDTH/8-1:0] comp_axi_wstrb,
    output logic                    comp_axi_wlast,
    output logic                    comp_axi_wvalid,
    input  logic                    comp_axi_wready,

    input  logic [AXI_ID_WIDTH-1:0] comp_axi_bid,
    input  logic [1:0]              comp_axi_bresp,
    input  logic                    comp_axi_bvalid,
    output logic                    comp_axi_bready
);
```

The final RTL may flatten `wb_record_words` into individual input words or a packed vector if the tool flow is simpler.

---

## 10. AXI Write Policy

P18A recommends a conservative single-beat write policy.

```text
DATA_WIDTH = 64
one AXI write transaction writes 8 bytes
completion payload requires 8 write transactions
AWLEN = 0 for each transaction
AWSIZE = log2(DATA_WIDTH/8)
AWBURST = INCR
WSTRB = all ones
```

Write order for 64-bit beats:

```text
beat for words 1/2
beat for words 3/4
beat for words 5/6
beat for words 7/8
beat for words 9/10
beat for words 11/12
beat for words 13/14
beat for words 15 + reserved/padding if needed
final separate write for word0 commit
```

Because word0 shares a 64-bit beat with word1 if naturally aligned, P18A should either:

```text
Option A: write word0 as a masked 32-bit commit write with WSTRB[3:0]
Option B: reserve the first 64-bit beat and rewrite word0/word1 at commit time
```

Recommended first implementation:

```text
Option B
```

Detailed sequence:

```text
1. write beat at base+0x08 through base+0x3F for words 2..15
2. write beat at base+0x00 containing word0=0 and word1 payload, optional pre-commit staging
3. write beat at base+0x00 containing word0=COMP_COMMIT_VALID and word1 payload
```

This avoids partial-WSTRB support in the first completion engine.

A later implementation may use WSTRB to write only word0 as the final commit.

---

## 11. Completion Builder Policy

The completion record builder should snapshot terminal status in the `dma_clk` domain.

Recommended sources:

```text
P17 descriptor fetch status:
  fetch_done_status
  fetch_error_status
  fetch_reject_status
  fetched_count
  current_desc_index
  first_user_tag
  last_user_tag

P16 recipe status:
  recipe_done_status
  recipe_error_status
  recipe_reject_status
  completed_count
  slot_done_mask
  slot_error_mask
  slot_reject_mask
  recipe_perf_busy_cycles
  recipe_perf_mac_count
  recipe_perf_output_count

P18 completion status:
  writeback error detail
```

Snapshot rule:

```text
On terminal event, capture all status fields into a completion snapshot.
The writeback engine uses the snapshot, not live CSR wires that may be cleared later.
```

This mirrors the existing P15/P16 descriptor snapshot philosophy.

---

## 12. Completion Error Handling

### 12.1 Write Response Error

If any completion AXI write returns non-OKAY:

```text
set CSR_COMP_ERROR_STATUS.COMP_AXI_WRITE_ERROR
set CSR_COMP_ERROR_DETAIL with failing beat/word index and BRESP
stop issuing further completion writes if the commit word has not yet been written
return completion engine to idle/error terminal state
```

If the error occurs before the final commit word, the host should not see `VALID=1` in memory.

If the error occurs on the final commit word, the CSR error status is authoritative.

### 12.2 Base Alignment Error

The first implementation should require:

```text
CSR_COMP_BASE_ADDR aligned to DATA_WIDTH/8 bytes
```

If not aligned:

```text
completion writeback does not start
CSR_COMP_ERROR_STATUS.COMP_UNALIGNED_BASE_ERROR is set
```

### 12.3 Completion Busy Error

A second completion terminal event while `comp_busy=1` is unexpected because P17/P18 support one outstanding descriptor-fetched recipe.

If it occurs:

```text
set CSR_COMP_ERROR_STATUS.COMP_BUSY_SEQUENCE_ERROR
set CSR_COMP_REJECT_STATUS.COMP_BUSY_REJECT
```

### 12.4 Disabled Completion Writeback

If completion writeback is disabled:

```text
no AXI writes are issued
CSR_COMP_REJECT_STATUS.COMP_DISABLED_DROP may be set for debug
P17/P16 CSR terminal status remains valid
```

Disabled writeback should not break descriptor-fetch recipe execution.

---

## 13. Software Programming Model

Recommended P18 happy path:

```text
1. Host clears completion record word0 to 0 in completion memory.
2. Host writes descriptor table in descriptor memory.
3. Host writes CSR_COMP_BASE_ADDR.
4. Host enables CSR_COMP_CONTROL.COMP_ENABLE.
5. Host writes CSR_DESC_BASE_ADDR / CSR_DESC_COUNT / CSR_DESC_STRIDE.
6. Host writes CSR_DESC_FETCH_COMMAND.START_FETCH_RECIPE.
7. Hardware fetches descriptors and runs the recipe.
8. Hardware writes completion record payload.
9. Hardware writes completion commit word with VALID=1.
10. Host polls completion memory word0 until VALID=1.
11. Host reads completion record payload and checks status/perf/error fields.
```

CSR polling remains available:

```text
Host may also poll CSR_DESC_FETCH_STATUS, CSR_RECIPE_STATUS, and CSR_COMP_STATUS.
```

---

## 14. UVM Testbench Model

P18 UVM tests should add one completion memory responder/model to the CSR UVM top.

Recommended testbench model:

```text
completion AXI write slave / memory model
  accepts comp_axi_aw/w/b
  stores completion record bytes
  supports BRESP error injection
  supports readback by helper task
```

The completion memory model is separate from:

```text
descriptor memory read responder
DMA source memory model
AXI-Stream source memory model
Direct Stream source memory model
DMA destination memory model
scratchpad BRAM
```

This keeps P18 debug waveforms clear and avoids modifying the BRAM.

---

## 15. Validation Plan

### 15.1 P18A Spec Closure

P18A completion criteria:

```text
completion-writeback prototype spec completed
record format defined
CSR map proposal defined
validation plan defined
non-goals defined
no RTL changes
no regression change
```

### 15.2 P18B Completion Record / CSR Map Freeze

P18B should freeze exact constants and maybe add compile-time localparams to existing CSR files.  It should still avoid adding unnecessary standalone package files unless the constants must be shared across many modules.

### 15.3 P18C Completion Writeback Engine RTL / Compile Smoke

Target:

```text
ai_accel_completion_wb_engine.sv compiles in existing compile_uvm.tcl
no standalone TB directory
no dedicated run script
```

### 15.4 P18D CSR Plumbing + Standalone Completion Writeback Smoke

Target:

```text
program CSR_COMP_BASE_ADDR
trigger a synthetic terminal event or CSR-controlled debug writeback
completion memory receives valid 64-byte record
CSR_COMP_DONE_STATUS reports completion
```

This should validate the writeback engine before tying it to full P17/P16 terminal sequencing.

### 15.5 P18E Descriptor-Fetch DMA Recipe + Completion Writeback

Target:

```text
P17 descriptor-fetch DMA two-slot recipe
completion writeback enabled
recipe result compare PASS
completion record VALID=1
completion record reports done/no-error
completion perf fields match recipe perf CSR snapshot
```

### 15.6 P18F Representative Frontend / C RMW Completion Writeback

Recommended one or two representatives:

```text
C RMW descriptor-fetch two-slot recipe + completion writeback
Direct Stream descriptor-fetch two-slot recipe + completion writeback
```

A single C RMW representative is enough for minimal closure if runtime is a concern.  Direct Stream representative is useful because it proves frontend mode survives the writeback-enabled control flow.

### 15.7 P18G Completion Error / Busy / Sticky Clear Handling

Coverage candidates:

```text
unaligned completion base error
completion AXI BRESP error before commit word
completion AXI BRESP error on commit word
completion disabled drop behavior
sticky completion done clear
sticky completion error clear
valid retry after writeback error cleanup
START_FETCH while comp_busy reject or delay policy
```

### 15.8 P18H Full Regression Integration + Docs Closure

Expected full-regression adders:

```text
csr_completion_wb_smoke
csr_desc_fetch_dma_two_slot_completion_wb_case102
csr_desc_fetch_c_rmw_completion_wb_case208 or direct_stream_completion_wb_case102
csr_completion_wb_reject_error_case102
```

If P17H baseline is 105/105, a four-item P18H integration would target:

```text
Expected P18H full regression total: 109
```

The exact total should be updated after P18 targeted tests are selected.

---

## 16. P18 Milestone Proposal

Recommended P18 sequence:

```text
P18A: Completion writeback prototype spec
P18B: Completion record format / CSR map freeze
P18C: Completion writeback engine RTL / compile smoke
P18D: CSR plumbing + standalone completion writeback smoke
P18E: Descriptor-fetch DMA recipe + completion writeback validation
P18F: C RMW or Direct Stream completion writeback representative validation
P18G: Completion writeback error / busy / sticky clear handling
P18H: Full regression integration + docs closure
```

Compressed alternative:

```text
P18A: spec
P18B: RTL + CSR plumbing
P18C: DMA happy path
P18D: C RMW / Direct Stream representative
P18E: error handling
P18F: full regression + docs
```

The expanded sequence is safer because it keeps the writeback engine independently debuggable before full P17/P16 terminal integration.

---

## 17. Non-Goals and Explicit Boundaries

P18 does not include:

```text
interrupt controller
MSI/MSI-X
Linux driver
C software driver
UVM RAL model
completion ring buffer
host-owned head/tail pointers
multiple outstanding descriptor-fetched commands
multiple outstanding completion records
out-of-order completion
completion coalescing
cache coherency
AXI interconnect / NoC integration
linked-list command descriptors
preemptive abort
rollback of partially completed recipe slots
BRAM changes
GEMM datapath changes
DMA datapath changes
AXI-Stream / Direct Stream datapath changes
```

P18 is a completion-writeback prototype, not a full platform integration.

---

## 18. Interview / Design Explanation

A concise explanation of P18:

```text
P17 made command ingress memory-backed: the host can place a descriptor table in memory and the accelerator fetches it.
P18 adds the matching completion egress: after the fetched recipe reaches a terminal state, hardware writes a compact completion record back to host-visible memory.
The record is committed by writing a valid word last, so the host can poll memory without relying only on CSR status.
The implementation intentionally remains single-outstanding and reuses the existing P16 recipe sequencer and P15 job worker.
```

Why this is useful:

```text
It demonstrates a realistic accelerator command/completion model.
It keeps the scope small and understandable.
It avoids jumping directly into interrupts, software drivers, cache coherency, or ring-buffer queues.
It preserves all validated datapath blocks.
```

---

## 19. P18A / P18B Closure Status

P18A is considered complete when this spec is added to the docs set and reviewed as the contract for P18B/P18C.

Current status:

```text
P18A: Completion writeback prototype spec          PASS
P18B: Completion record format / CSR map freeze    PASS
```


---

## 20. P18B Record / CSR Map Freeze Addendum

P18B freezes the exact completion record layout, CSR register map, bit definitions, 64-bit AXI packing rule, and no-partial-WSTRB first implementation write order.  The register map and record layout are documented in the AXI-Lite CSR control-plane spec rather than in a standalone map document.

The companion document is:

```text
docs/axi_lite_csr_control_plane_spec.md
```

Key frozen P18B decisions:

```text
Completion record size             : 64 bytes
Completion logical words           : 16 x 32-bit
Completion commit word             : word0, written last
Completion status word             : word1
Completion CSR window              : 0x540 - 0x57C
Completion version reset           : 0x0001_0018
Completion control reset           : 0x0000_0007
Completion base alignment          : DATA_WIDTH/8 bytes
First implementation AXI policy    : 64-bit single-beat writes, AWLEN=0
First implementation commit policy : rewrite base+0x00 beat at commit time
DATA_WIDTH=64 write count          : 9 single-beat writes
```

P18B does not add RTL, UVM tests, Tcl scripts, README updates, or regression-list items.  The completion record format and CSR map are integrated into `docs/axi_lite_csr_control_plane_spec.md` instead of creating a separate record/map document, keeping the docs set compact.  This integrated CSR spec is the frozen contract for P18C/P18D implementation.


---

## 21. P24B Timeout Completion Record Policy

P24B does not change the 64-byte P18 completion record size or the commit-last visibility rule.

A timeout completion record, when produced, uses the existing P18 record format:

```text
COMP_COMMIT.VALID        = 1
COMP_COMMIT.OVERALL_DONE = 0
COMP_COMMIT.OVERALL_ERROR = 1
COMP_COMMIT.OVERALL_REJECT = 0 unless the timeout was reporting a reject-completion path
COMP_STATUS_FLAGS.QUEUE_TIMEOUT = 1
COMP_ERROR_DETAIL mirrors CSR_QUEUE_ERROR_DETAIL when practical
```

Recommended timeout commit value pattern:

```text
VALID=1, OVERALL_ERROR=1, FEATURE_ID=0x18, VERSION=1.0
Conceptual COMP_COMMIT value: 0x0100_1805
```

P24B extends `COMP_STATUS_FLAGS` by consuming the first reserved status bit:

| Bit | Name | Description |
|---:|---|---|
| 10 | `QUEUE_TIMEOUT` | Queue watchdog expired for the accepted SQ command represented by this completion record. |

All existing lower-level snapshot words remain unchanged.  For a queue-level timeout record:

```text
COMP_FIRST_USER_TAG / COMP_LAST_USER_TAG may both carry the active SQ CMD_USER_TAG
COMP_COUNT_SUMMARY keeps the command descriptor count and any available fetched/completed count snapshots
COMP_DESC_FETCH_* and COMP_RECIPE_* words carry available sticky snapshots at timeout capture
COMP_PERF_* words carry available performance snapshots or zero when no valid snapshot exists
COMP_ERROR_DETAIL carries DETAIL_COMMAND_TIMEOUT or a phase-specific DETAIL_TIMEOUT_* code
```

If the completion writeback engine itself is the stalled or timed-out path, P24 must not require a second nested completion writeback to report that timeout.  In that case:

```text
CSR_QUEUE_ERROR_STATUS.COMMAND_TIMEOUT_ERROR is authoritative
CSR_QUEUE_ERROR_DETAIL is authoritative
CSR_CQ_TAIL must not advance unless a valid timeout completion record was committed
host runtime must handle CSR-only timeout reporting
```

This keeps the timeout mechanism from depending on the same blocked completion path that it is trying to diagnose.
