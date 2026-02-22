# APB Master-Slave RTL Implementation

A Verilog implementation of the **AMBA APB (Advanced Peripheral Bus) Protocol**, featuring a 3-state FSM-based Master, a memory-mapped Slave with full `PSTRB` support, a top-level Wrapper, and a self-checking testbench targeting **Xilinx Vivado**.

---

## Table of Contents

- [Overview](#overview)
- [Protocol Background](#protocol-background)
- [Project Structure](#project-structure)
- [Module Descriptions](#module-descriptions)
  - [APB\_Master](#apb_master)
  - [APB\_Slave](#apb_slave)
  - [APB\_Wrapper](#apb_wrapper)
  - [APB\_tb (Testbench)](#apb_tb-testbench)
- [Signal Reference](#signal-reference)
- [FSM State Diagram](#fsm-state-diagram)
- [APB Transfer Timing](#apb-transfer-timing)
- [PSTRB Behavior](#pstrb-behavior)
- [How to Run in Xilinx Vivado](#how-to-run-in-xilinx-vivado)
- [Testbench Test Cases](#testbench-test-cases)
- [Design Decisions & Notes](#design-decisions--notes)

---

## Overview

This project implements a complete APB bus system consisting of:

- A **Master** that translates external system requests into timed APB transactions
- A **Slave** that responds with an internal 1024-word cache memory
- A **Wrapper** that wires them together into a single instantiable top module
- A **Testbench** with 14 directed test cases, pass/fail checking, and a watchdog timer

The implementation strictly follows the **ARM AMBA APB Protocol Specification**.

---

## Protocol Background

The **Advanced Peripheral Bus (APB)** is a low-power, low-complexity bus from ARM's AMBA family. It is designed for accessing peripheral registers and slow-speed control interfaces where high bandwidth is not required.

Key characteristics:
- **Synchronous** — all signals are sampled on the rising edge of `PCLK`
- **Non-pipelined** — one transfer at a time (no overlapping transactions)
- **3-state FSM** — every transfer goes through `IDLE → SETUP → ACCESS`
- **Wait state support** — slave can extend the ACCESS phase by holding `PREADY` low
- **Error signaling** — slave can flag failed transfers using `PSLVERR`
- **Byte lane control** — `PSTRB` allows partial word writes at byte granularity

---

## Module Descriptions

### APB\_Master

**File:** `APB_Master.v`

The master module implements the APB protocol FSM. It accepts transfer requests from an external system (or testbench) and drives the APB bus accordingly.

**Ports:**

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `SWRITE` | Input | 1 | System write enable (1=write, 0=read) |
| `SADDR` | Input | 32 | System target address |
| `SWDATA` | Input | 32 | System write data |
| `SSTRB` | Input | 4 | System byte strobes |
| `SPROT` | Input | 3 | System protection type |
| `transfer` | Input | 1 | Asserted to begin/continue a transfer |
| `PCLK` | Input | 1 | APB clock |
| `PRESETn` | Input | 1 | Active-LOW synchronous reset |
| `PREADY` | Input | 1 | Slave ready signal |
| `PSLVERR` | Input | 1 | Slave error signal |
| `PSEL` | Output | 1 | Slave select |
| `PENABLE` | Output | 1 | Transfer enable |
| `PWRITE` | Output | 1 | Write/read direction |
| `PADDR` | Output | 32 | APB address |
| `PWDATA` | Output | 32 | APB write data |
| `PSTRB` | Output | 4 | APB write strobes |
| `PPROT` | Output | 3 | APB protection signals |

**FSM States:**

| State | `PSEL` | `PENABLE` | Description |
|-------|--------|-----------|-------------|
| `IDLE` | 0 | 0 | Bus idle, waiting for `transfer` |
| `SETUP` | 1 | 0 | Signals set up, one cycle only |
| `ACCESS` | 1 | 1 | Transfer active, waiting for `PREADY` |

> The synthesizer attribute `(* fsm_encoding = "one_hot" *)` is applied to improve timing on FPGAs.

---

### APB\_Slave

**File:** `APB_Slave.v`

The slave contains a parameterizable internal cache memory that responds to APB read and write transfers. It supports all 16 `PSTRB` combinations for partial word writes and asserts `PSLVERR` on protocol violations.

**Parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `MEM_WIDTH` | 32 | Width of each memory word (bits) |
| `MEM_DEPTH` | 1024 | Number of addressable memory locations |

**Ports:**

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `PSEL` | Input | 1 | Slave is selected |
| `PENABLE` | Input | 1 | Transfer enable (ACCESS phase) |
| `PWRITE` | Input | 1 | Write/read direction |
| `PADDR` | Input | 32 | Address of the memory location |
| `PWDATA` | Input | 32 | Write data from master |
| `PSTRB` | Input | 4 | Byte write enables |
| `PPROT` | Input | 3 | Protection signals (received, not decoded) |
| `PCLK` | Input | 1 | APB clock |
| `PRESETn` | Input | 1 | Active-LOW reset |
| `PRDATA` | Output | 32 | Read data to master |
| `PREADY` | Output | 1 | Ready — asserted when transfer can complete |
| `PSLVERR` | Output | 1 | Error flag |

**Key behavior:**
- The slave only acts when **both** `PSEL` and `PENABLE` are high (ACCESS phase only)
- `PREADY` is combinationally asserted as soon as `PSEL && PENABLE` — no wait states
- `PSLVERR` is asserted if a read transfer is attempted with `PSTRB != 0`

---

### APB\_Wrapper

**File:** `APB_Wrapper.v`

Top-level integration module. Instantiates the Master and Slave and connects them through internal APB bus wires. This is the module to use as the DUT in simulation or as the top-level in synthesis.

**Ports:**

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `PCLK` | Input | 1 | APB clock |
| `PRESETn` | Input | 1 | Active-LOW reset |
| `SWRITE` | Input | 1 | System write request |
| `SADDR` | Input | 32 | System address |
| `SWDATA` | Input | 32 | System write data |
| `SSTRB` | Input | 4 | System byte strobes |
| `SPROT` | Input | 3 | System protection bits |
| `transfer` | Input | 1 | Transfer request |
| `PRDATA` | Output | 32 | Read data (from slave, to system) |

---

### APB\_tb (Testbench)

**File:** `APB_tb.v`

A self-checking Verilog testbench targeting **Xilinx Vivado Behavioral Simulation**. It instantiates `APB_Wrapper` as the DUT, taps internal bus wires for visibility, and runs 14 directed test cases with automatic PASS/FAIL reporting.

**Features:**
- `apb_write` and `apb_read` reusable tasks
- `check` task with formatted PASS/FAIL output and counters
- `$monitor` for continuous signal tracing
- `$dumpfile` / `$dumpvars` for VCD waveform export
- Watchdog timer (100 µs timeout) to catch simulation hangs
- Final summary showing total tests, passes, and failures

---

## Signal Reference

The complete APB bus signals between master and slave:

| Signal | Driver | Description |
|--------|--------|-------------|
| `PCLK` | System | Bus clock — all transfers synchronous to rising edge |
| `PRESETn` | System | Active-LOW reset — resets master FSM and slave outputs |
| `PSEL` | Master | Selects this slave for a transfer |
| `PENABLE` | Master | Marks the ACCESS (second) phase of the transfer |
| `PWRITE` | Master | Direction: 1=write, 0=read |
| `PADDR[31:0]` | Master | Target address — stable across SETUP and ACCESS |
| `PWDATA[31:0]` | Master | Write data — stable across SETUP and ACCESS |
| `PSTRB[3:0]` | Master | Byte lane enables for write; must be 0 for reads |
| `PPROT[2:0]` | Master | Protection: `[0]`=privilege, `[1]`=secure, `[2]`=instruction |
| `PRDATA[31:0]` | Slave | Read data — valid when `PREADY=1` and `PWRITE=0` |
| `PREADY` | Slave | 1=slave ready to complete; 0=insert wait states |
| `PSLVERR` | Slave | 1=transfer error occurred |

---

## FSM State Diagram

```
          ┌─────────────────────────────────────────────┐
          │                                             │
          ▼                                             │
     ┌─────────┐   transfer=1    ┌─────────┐           │
     │         │ ──────────────► │         │           │
     │  IDLE   │                 │  SETUP  │           │
     │         │ ◄────────────── │         │           │
     └─────────┘  PREADY & !tr   └────┬────┘           │
          ▲                           │ (always)        │
          │                           ▼                 │
          │                      ┌─────────┐            │
          │    PREADY & !trnsfr  │         │            │
          └──────────────────────│ ACCESS  │            │
                                 │         │────────────┘
                                 └─────────┘  PREADY & transfer=1
                                  stays here  (back-to-back: goes to SETUP)
                                  if !PREADY
```

> `tr` = `transfer` signal

---

## PSTRB Behavior

`PSTRB` is a 4-bit signal where each bit enables one byte lane of the 32-bit data bus. It **must be 0 during read transfers**.

| `PSTRB` | Bytes Written | Result in Memory |
|---------|---------------|------------------|
| `4'b0001` | Byte 0 `[7:0]` | Sign-extended from bit 7 |
| `4'b0010` | Byte 1 `[15:8]` | Sign-extended from bit 15, byte 0 zeroed |
| `4'b0011` | Bytes 0–1 (half-word) | Sign-extended from bit 15 |
| `4'b0100` | Byte 2 `[23:16]` | Sign-extended from bit 23, lower bytes zeroed |
| `4'b1000` | Byte 3 `[31:24]` | MSB stored, lower 24 bits zeroed |
| `4'b1100` | Bytes 2–3 (upper half-word) | Upper 16 bits stored, lower 16 zeroed |
| `4'b1111` | All bytes (full word) | Full 32-bit write, no modification |
| `4'b0000` on write | None | Stores `32'h00000000` (default case) |
| Any non-zero on **read** | — | `PSLVERR` asserted by slave |

---

## Testbench Test Cases

| # | Test Name | Description | Expected Result |
|---|-----------|-------------|-----------------|
| 1 | Single Write | Full-word write `0xDEADBEEF` to addr `0x00` | Written to cache |
| 2 | Single Read | Read back addr `0x00` | `PRDATA = 0xDEADBEEF` |
| 3 | Different Address | Write/read `0xCAFEBABE` to addr `0x04` | `PRDATA = 0xCAFEBABE` |
| 4 | Byte Write `PSTRB=0001` | Write byte 0 of `0xABCDEF12` | `PRDATA = 0x00000012` |
| 5 | MSB Byte Write `PSTRB=1000` | Write byte 3 of `0xAB000000` | `PRDATA = 0xAB000000` |
| 6 | Half-Word Write `PSTRB=0011` | Write lower half `0x5A5A` | `PRDATA = 0x00005A5A` |
| 7 | Full Word `PSTRB=1111` | Write `0xFFFFFFFF` | `PRDATA = 0xFFFFFFFF` |
| 8 | Upper Half `PSTRB=1100` | Write upper half `0xBEEF0000` | `PRDATA = 0xBEEF0000` |
| 9 | Illegal PSTRB on Read | Read with `PSTRB=0001` (protocol violation) | `PSLVERR = 1` |
| 10 | Mid-Transfer Reset | Assert `PRESETn=0` during ACCESS phase | `PSEL=0, PENABLE=0` |
| 11 | Multi-Address Read 0 | Readback first of 3 batch writes | `PRDATA = 0xAABBCCDD` |
| 12 | Multi-Address Read 1 | Readback second of 3 batch writes | `PRDATA = 0x11223344` |
| 13 | Multi-Address Read 2 | Readback third of 3 batch writes | `PRDATA = 0x55667788` |
| 14 | Back-to-Back Write | Two writes without returning to IDLE | Both locations correct |

---

## Design Decisions & Notes

**Why is the slave write gated on `PSEL && PENABLE` (not just `PSEL`)?**
Per the APB spec, data and address signals are only *set up* during the SETUP phase (`PSEL=1, PENABLE=0`). The actual transfer must be captured in the ACCESS phase (`PSEL=1, PENABLE=1`). Writing on `PSEL` alone would latch data one cycle too early, before it is guaranteed to be stable.

**Why is `PREADY` combinational?**
This slave has no internal latency — it can always respond in the same cycle the ACCESS phase begins. Slaves with slower memories or pipeline stages would generate `PREADY` from a sequential counter instead.

**Why does the master use a combinational output block?**
The APB spec requires that `PSEL`, `PADDR`, `PWDATA`, etc. are driven based on the *current* FSM state with no additional clock delay. A combinational output block (Mealy/Moore style) achieves this. A registered output would introduce a one-cycle offset, violating setup-to-access timing.

**Why is `(* fsm_encoding = "one_hot" *)` used with 2-bit state variables?**
The attribute instructs the Vivado synthesizer to override the binary encoding and use one-hot encoding for the FSM registers at synthesis time. One-hot encoding reduces combinational logic depth for small FSMs on FPGAs, improving timing closure — even though the RTL itself uses `2'b00/01/10`.

**What does `PPROT` do?**
`PPROT[2:0]` carries protection metadata: `[0]` distinguishes privileged vs. unprivileged access, `[1]` secure vs. non-secure, `[2]` data vs. instruction access. This implementation passes `PPROT` through the bus correctly but the slave does not act on it (no access control logic). It can be extended to add security checks.

---

*Implementation based on ARM AMBA APB Protocol Specification (ARM IHI 0024).*
