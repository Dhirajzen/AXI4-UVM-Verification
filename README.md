# AXI4

This repository now includes a synthesizable AXI4 RAM slave reference design.

## Contents
- `rtl/axi4_ram_slave.sv` – parameterized AXI4 memory-mapped RAM slave.
- `docs/axi4_design.md` – architecture and behavior notes.

## Quick start
Instantiate `axi4_ram_slave` in your SoC/testbench and connect AXI4 master signals.

Current implementation focus:
- Supported bursts: `FIXED`, `INCR`
- Unsupported burst: `WRAP` (returns `SLVERR`)
- One outstanding write + one outstanding read transaction
