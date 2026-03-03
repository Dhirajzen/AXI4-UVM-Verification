# AXI4 RAM Slave Design

## Goal
This design provides a compact **AXI4 memory-mapped slave** that can be dropped into a testbench or lightweight SoC integration as an on-chip RAM target.

## Module
- File: `rtl/axi4_ram_slave.sv`
- Top-level module: `axi4_ram_slave`

## Key characteristics
- Full AXI4 split channels (`AW`, `W`, `B`, `AR`, `R`).
- Parameterized bus sizing:
  - `ID_WIDTH`
  - `ADDR_WIDTH`
  - `DATA_WIDTH`
  - `MEM_SIZE_BYTES`
- Internal byte-addressable RAM (`mem` array).
- Burst support:
  - `FIXED` and `INCR` are implemented.
  - `WRAP` is flagged as unsupported and returns `SLVERR`.
- One outstanding write transaction and one outstanding read transaction at a time.
- Response policy:
  - `OKAY` (`2'b00`) for valid accesses.
  - `SLVERR` (`2'b10`) for unsupported burst type, out-of-range access, or protocol mismatch (`WLAST` mismatch).

## Channel behavior
### Write path (`AW/W/B`)
1. `AW` handshake latches ID, address, burst metadata.
2. `W` beats write `WSTRB`-selected bytes into RAM.
3. Address updates per beat based on burst mode.
4. Final beat raises `BVALID` with `BRESP`.

### Read path (`AR/R`)
1. `AR` handshake latches ID, address, burst metadata.
2. First read beat is returned immediately via `RDATA`/`RVALID`.
3. Subsequent beats are returned as `RREADY` consumes each beat.
4. `RLAST` asserts on the final beat.

## Notes and integration guidance
- This is a practical baseline for simulation and FPGA prototyping.
- It is intentionally conservative (single outstanding transaction per direction).
- For higher throughput, add:
  - outstanding transaction queues,
  - support for `WRAP` bursts,
  - stricter size/alignment checks,
  - optional backpressure/latency insertion.
