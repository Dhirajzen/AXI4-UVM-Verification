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

The RTL is intentionally left unfixed so each bug can be reproduced live. All
three were found by tightening the scoreboard to predict *exact* per-beat
responses and adding directed error-injection sequences, then confirmed on
real hardware (Cadence Xcelium 26.03). Log excerpts below are copy-pasted
from actual `make bugs` output, not predicted from static analysis.

### Bug #1 — Error response one beat late (stale flag read after NBA write)
`axi_slave.sv` write path (`wr_err` set: lines 224/228/233, read back: line
239) and read path (`rd_err` set: line 342, read back: line 345): the error
flag is set with a **non-blocking assignment and read in the same always_ff
evaluation**, so the response logic sees the *previous* value, not the one
just computed.
- Read burst crossing the end of memory (`0x78`, len 3, size 4B, INCR): beat 2
  hits address `0x80` (out of range) but returns RRESP=OKAY; DECERR only
  appears one beat later.
- Write burst whose *final* beat is the first illegal one (`0x74`, len 3,
  INCR): BRESP=OKAY for a burst that ran off memory.
- Reproduce: `make errors` (or `axi_error_test`) →
  ```
  UVM_ERROR axi_scoreboard.sv(119) [AXI_SCB] RRESP mismatch beat2 exp=DECERR got=0 (addr=0x80 len=3 size=2 burst=AXI_BURST_INCR)
  UVM_ERROR axi_scoreboard.sv(77)  [AXI_SCB] BRESP mismatch exp=DECERR got=0 (addr=0x74 len=3 size=2 burst=AXI_BURST_INCR wid_mm=0 wlast_mm=0)
  ```
  Only 2 of the test's 6 directed illegal cases fail — the other 4 are
  illegal from beat 0, whose response is computed inline at the AW/AR-accept
  cycle (not through the buggy stale-read path), so they correctly return
  DECERR immediately. Only a burst that turns illegal *mid-burst* exposes
  this bug, which is exactly what cases 5/6 are built to do.
- Fix direction: compute the error condition combinationally for the current
  beat (or register the response one cycle later), never read an NBA-updated
  flag in the same block that wrote it.

### Bug #2 — Write FSM deadlocks on early WLAST
`axi_slave.sv` W-beat handling (lines 233–244): an early `WLAST` (line 233)
only sets `wr_err`; the surrounding `if (last_expected) ... else ...` (lines
236–244) still waits for the beat counter to reach `AWLEN+1` regardless, so
the FSM never shortcuts to `WR_RESP`. A master that ends the burst early
hangs the whole write channel forever — no `BVALID`, no recovery, bus locked.
- Reproduce: `make early_wlast` (or `axi_early_wlast_test`) →
  ```
  UVM_ERROR axi_tests.sv(208) [BUG2_HANG] DUT hung after early WLAST: write FSM ignored WLAST and never returned BRESP (axi_slave.sv WR_DATA state)
  UVM_ERROR axi_scoreboard.sv(151) [AXI_SCB] No transactions observed - the test drove nothing; a silent pass is not a pass
  ```
  The first error is the test's own 20µs watchdog firing (the DUT genuinely
  never responds); the second is the scoreboard's separate zero-transaction
  guard, correctly refusing to call a burst that never completed a "pass."
- Fix direction: treat `WLAST` as the burst terminator — on early WLAST, go to
  `WR_RESP` immediately with an error response instead of waiting for the
  declared beat count.

### Bug #3 — Errored burst still committed to memory
`axi_slave.sv` W-beat handling (line 224 sets `wr_err` on `WID`≠`AWID`; line
227's legality check — which gates `mem_write` at line 230 — never looks at
the WID check at all): B correctly returns DECERR, but the beat's data is
**still written to memory**, because `mem_write` is only gated by the
per-beat size/burst/address check, not by the WID mismatch that also
happened this beat.
- Reproduce: `make wid` (or `axi_wid_test`) →
  ```
  UVM_ERROR axi_scoreboard.sv(126) [AXI_SCB] RDATA mismatch beat0 addr=0x40 exp=0x0c0c0c0c got=0xc1d00000
  UVM_ERROR axi_scoreboard.sv(126) [AXI_SCB] RDATA mismatch beat1 addr=0x44 exp=0x0c0c0c0c got=0xc1d00001
  UVM_ERROR axi_scoreboard.sv(126) [AXI_SCB] RDATA mismatch beat2 addr=0x48 exp=0x0c0c0c0c got=0xc1d00002
  UVM_ERROR axi_scoreboard.sv(126) [AXI_SCB] RDATA mismatch beat3 addr=0x4c exp=0x0c0c0c0c got=0xc1d00003
  ```
  `exp=0x0c0c0c0c` is the untouched reset-fill value the reference model
  correctly kept (it predicted the whole burst should be rejected); `got=`
  is the "rejected" write data the DUT committed anyway.
- Fix direction: qualify `mem_write` with the accumulated per-beat error
  (including the WID check), or buffer the burst and commit only once the
  whole burst is confirmed clean.

### Also found: the same commit-on-error behavior via unaligned WRAP addressing
Independently of Bug #3's WID trigger, `axi_rand_seq`'s constrained-random
WRAP bursts originally exposed the identical DUT behavior through a different
path: a WRAP burst with an unaligned start address has its first beat (driven
verbatim, before any wrap-around correction applies) spill past the wrap
window's own edge, going out of range while later beats — legal again after
wrapping — still get individually committed to memory despite the burst
overall reporting DECERR. This produced cascading `RDATA mismatch` errors in
`axi_random_test` at addresses an earlier, partially-illegal burst had
touched. Fixed in the stimulus (WRAP bursts now constrained to
`addr % (1<<size) == 0`, matching AXI's own alignment requirement for WRAP)
since `axi_random_test` is meant to stay in the legal-stimulus space —
`axi_wid_test` remains the dedicated, intentional reproduction of this DUT
behavior.

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

### Measured results (Xcelium, merged coverage)

Coverage databases from `axi_random_test`, `axi_error_test`, `axi_wid_test`,
and `axi_early_wlast_test` merged in IMC:

- **Functional coverage: 100%** (90/90 bins), including the direction × burst
  × size × length-group cross (54/54) closing in a single 400-op random run.
  `resp_cp`'s DECERR bin only closes once the directed bug tests are merged
  in — `axi_random_test` alone can't reach it, since it deliberately stays in
  the legal-stimulus space.
- **DUT (`axi_slave`) code coverage: ~80%** block/expression/toggle, up from
  ~70% with `axi_random_test` alone — the directed tests close RTL paths
  (illegal SIZE, reserved burst, WID mismatch) pure random stimulus
  structurally can't reach on its own.
- **Assertion coverage: 8/14 (57%), and it doesn't move**. Every response-
  channel assertion (`a_stable_r/b`, `a_hold_r/b`) fires and passes across
  every test that exercises backpressure. Every request-channel assertion
  (`a_stable_aw/w/ar`, `a_hold_aw/w/ar`) sits at a flat 0% — never triggered,
  even after merging in the bug-hunting tests. That's not a stimulus gap: this
  DUT's `awready`/`wready`/`arready` are combinational on FSM idle state and
  accept almost instantly, so nothing in the master's control ever holds a
  request-channel VALID against a stalled READY for more than an instant.
  Documented here rather than "fixed," since manufacturing an artificial
  request-side stall isn't meaningful without a DUT change.

See `docs/verification_plan.md` for the feature → test → coverage mapping.
