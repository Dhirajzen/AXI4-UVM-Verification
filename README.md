# AXI4 Slave Verification — SystemVerilog / UVM

UVM verification environment for a burst-capable **AXI4 slave** (128-byte
memory, FIXED/INCR/WRAP bursts, 1/2/4-byte beats, single outstanding
transaction per direction, AXI3-style `WID` checking). The testbench found
**three real RTL bugs**, documented below with the tests that reproduce them.

```
                 +--------------------------------------------+
                 |                axi_env                     |
  axi_seqs  -->  |  +-----------axi_agent-----------+         |
  (smoke,        |  | sequencer -> driver (BFM) ----+--> DUT  |  axi_slave.sv
   random,       |  |            monitor <----------+---------|  (axi_if + 14 SVA)
   b2b, err,     |  +-----------------|-------------+         |
   wid, reset,   |                    +--> scoreboard (ref model, per-beat)
   early_wlast)  |                    +--> coverage  (covergroup + cross)
                 +--------------------------------------------+
```

| File | Role |
|---|---|
| `axi_slave.sv` | DUT: AXI4 slave, byte-addressable 128 B memory (unchanged — bugs kept for reproduction) |
| `axi_if.sv` | Interface, driver/monitor clocking blocks, 14 protocol assertions |
| `axi_pkg.sv` / `axi_item.sv` / `axi_cfg.sv` | Package, sequence item (with error-injection knobs), agent config |
| `axi_driver.sv` | Master BFM: clocking-block handshakes, BREADY/RREADY policies, reset abort |
| `axi_monitor.sv` | Passive reconstruction of write/read bursts (incl. WID/WLAST violation flags) |
| `axi_ref_model.sv` / `axi_scoreboard.sv` | Golden memory + strict per-beat RDATA/RRESP/RID/RLAST/BRESP/BID checking |
| `axi_coverage.sv` | Functional coverage: dir/burst/size/len (+cross), alignment, WSTRB shape, responses |
| `axi_seqs.sv` / `axi_tests.sv` | Sequences and the 8 tests below |
| `Makefile` / `probe.tcl` / `filelist.f` | Xcelium (xrun) build & run infrastructure |

## Running (Cadence Xcelium)

On a machine with Xcelium (e.g. a university FastX desktop):

```bash
module load cadence/xcelium     # exact name: check `module avail 2>&1 | grep -i xcelium`
git clone https://github.com/Dhirajzen/AXI4-UVM-Verification.git
cd AXI4-UVM-Verification

make smoke        # sanity: directed write + readback
make regress      # all 5 passing tests (each must end with 0 UVM_ERRORs)
make bugs         # the 3 bug-hunting tests (fail on purpose — see below)

make waves TEST=axi_random_test   # + waveforms  ->  simvision waves.shm &
make cov   TEST=axi_random_test   # + coverage   ->  imc -load cov_work/scope/axi_random_test &
make help                          # everything else (SEED=, VERBOSITY=, gui, clean)
```

No Xcelium? Questa/VCS command lines are at the bottom of the `Makefile`.

## Tests

| Test | What it verifies | Expected |
|---|---|---|
| `axi_smoke_test` | Directed 4-beat INCR write + readback | pass |
| `axi_random_test` | 400 constrained-random bursts (all burst types/sizes/lengths, random WSTRB), READY_RANDOM backpressure | pass |
| `axi_backpressure_test` | Bursty multi-cycle BREADY/RREADY stalls → payload-stability + VALID-hold SVA under stress | pass |
| `axi_b2b_test` | Zero-idle back-to-back write/read pairs | pass |
| `axi_reset_test` | Reset asserted mid-write-burst; DUT and TB must recover with clean traffic afterwards | pass |
| `axi_error_test` | Directed illegal stimulus (out-of-range, illegal SIZE, reserved burst, boundary-crossing bursts) | **fails: Bug #1** |
| `axi_wid_test` | WID≠AWID burst then readback | **fails: Bug #3** |
| `axi_early_wlast_test` | Master terminates write burst one beat early | **fails: Bug #2** |

## Bugs found

The RTL is intentionally left unfixed so each bug can be reproduced live.
All three were found by tightening the scoreboard to predict *exact* per-beat
responses and adding directed error-injection sequences.

### Bug #1 — Error response one beat late (stale flag read after NBA write)
`axi_slave.sv` read path (~line 339) and write path (~line 237): `rd_err` /
`wr_err` are set with a **non-blocking assignment and read in the same clock**,
so the response logic sees the *previous* value.
- Read burst crossing the end of memory (`0x78`, len 3, size 4B): beat 2 hits
  address `0x80` (out of range) but returns **RRESP=OKAY with RDATA=0**;
  DECERR only appears on beat 3.
- Write burst whose *final* beat is the first illegal one (`0x74`, len 3):
  **BRESP=OKAY** for a burst that partially ran off memory.
- Reproduce: `make errors` → log shows `RRESP mismatch beat2 exp=DECERR got=00`
  and `BRESP mismatch exp=DECERR got=00`.
- Fix direction: compute the error condition combinationally for the current
  beat (or register response one cycle later), never read an NBA-updated flag
  in the same block.

### Bug #2 — Write FSM deadlocks on early WLAST
`axi_slave.sv` WR_DATA state (~line 231): an early `WLAST` only sets `wr_err`;
the FSM still waits for the full `AWLEN+1` beat count. A master that (illegally
or due to its own bug) ends the burst early hangs the whole write channel
forever — no `BVALID`, no recovery, bus locked.
- Reproduce: `make early_wlast` → `BUG2_HANG` error from the test watchdog
  (plus the scoreboard's zero-transaction guard).
- Fix direction: treat `WLAST` as the burst terminator — on early WLAST, go to
  WR_RESP immediately with an error response.

### Bug #3 — Errored burst still committed to memory
`axi_slave.sv` W-beat handling (~line 222): a `WID`≠`AWID` beat sets `wr_err`
(and B correctly returns DECERR), but the beat data **is still written to
memory** — the error path has a side effect the response says didn't happen.
- Reproduce: `make wid` → the readback shows `RDATA mismatch` on all 4 beats
  (DUT returns the "rejected" data, reference model kept the old contents).
- Fix direction: qualify `mem_write` with the accumulated error, or buffer the
  burst and commit only on a clean OKAY.

Also documented (not flagged by the scoreboard, since the reference model
mirrors the RTL): the WRAP boundary math accepts any `LEN`, while the AXI spec
only allows WRAP lengths of 2/4/8/16 with an aligned start address.

## Checking & coverage

- **Scoreboard**: golden byte-accurate memory model; per-beat expected RRESP
  (sticky error semantics), RDATA vs reference on every OKAY beat, exact beat
  count, RLAST position, BID/RID, exact BRESP; end-of-test guard that fails a
  run in which no transactions were observed.
- **Assertions** (`axi_if.sv`, 14 properties, all with failure messages):
  payload stability and VALID-hold on all five channels, response channels
  quiet during reset, no X on B/R payloads or ready outputs.
- **Coverage**: dir × burst × size × len-group cross, every individual burst
  length, address alignment, WSTRB shape (full/partial/zero), OKAY vs DECERR
  responses; per-run summary printed in `report_phase`, full reports via
  `make cov` + IMC.

See `docs/verification_plan.md` for the feature → test → coverage mapping.
