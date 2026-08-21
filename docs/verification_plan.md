# Verification Plan — AXI4 Slave

## 1. DUT summary

`axi_slave.sv`: AXI4 slave with a 128-byte byte-addressable memory.

- Channels: AW, W, B, AR, R (independent write/read FSMs, single outstanding
  burst per direction)
- Bursts: FIXED, INCR, WRAP; `LEN` 0–15 (1–16 beats); `SIZE` 1/2/4 bytes
- `WSTRB` byte lanes honored; AXI3-style `WID` checked against `AWID`
- Responses: OKAY, DECERR (SLVERR not implemented)

## 2. Verification approach

- Constrained-random stimulus for the legal space; directed sequences for
  illegal/corner stimulus the constraints deliberately exclude.
- Passive monitor reconstructs bursts from bus handshakes only (checking never
  trusts the driver).
- Scoreboard with a golden byte-accurate reference memory predicts **exact**
  per-beat responses and data; loose "either response is fine" checking is
  explicitly avoided — that looseness is what originally masked Bug #1.
- Interface SVA covers the timing rules a transaction-level scoreboard cannot
  see (stability while stalled, VALID retraction, reset behavior, X-checks).
- A test that observes zero transactions fails by design.

## 3. Feature → stimulus → check → coverage matrix

| # | Feature | Stimulus (test) | Check | Coverage |
|---|---------|-----------------|-------|----------|
| F1 | Write burst, all types/sizes/lengths | `axi_random_test` | ref-model memory + exact BRESP/BID | `x_dbsl` cross, `len_cp` |
| F2 | Read burst, all types/sizes/lengths | `axi_random_test` | per-beat RDATA/RRESP/RID, beat count, RLAST position | `x_dbsl` cross, `len_cp` |
| F3 | WSTRB byte enables (full/partial/zero) | `axi_random_test` (random strobes) | byte-accurate ref model | `wstrb_cp` |
| F4 | WRAP address wrap-around | `axi_random_test`, smoke | ref model mirrors wrap math | `burst_cp=WRAP` bins |
| F5 | Handshake timing under backpressure | `axi_backpressure_test`, `axi_random_test` | SVA: payload stable + VALID held while stalled | assertion coverage |
| F6 | Back-to-back transactions, zero idle | `axi_b2b_test` | scoreboard + SVA | `len_grp_cp` |
| F7 | Out-of-range address → DECERR | `axi_error_test` | exact DECERR expected per beat | `resp_cp=decerr` |
| F8 | Illegal SIZE / reserved burst → DECERR | `axi_error_test` | exact DECERR expected | `size_cp.illegal` |
| F9 | Burst running off end of memory | `axi_error_test` (cases 5, 6) | first illegal beat must be DECERR → **finds Bug #1** | `resp_cp` |
| F10 | WID ≠ AWID | `axi_wid_test` | DECERR **and** no memory side-effect → **finds Bug #3** | `resp_cp` |
| F11 | Early WLAST burst termination | `axi_early_wlast_test` | slave must terminate the burst → **finds Bug #2** (hang) | n/a (watchdog) |
| F12 | Mid-burst reset & recovery | `axi_reset_test` | responses quiet in reset (SVA), clean traffic after recovery | n/a |
| F13 | No X on outputs | all tests | SVA `a_no_x_*` | assertion coverage |

## 4. Pass/fail criteria

- `make regress` (smoke, random, backpressure, b2b, reset): every run ends
  with `UVM_ERROR : 0` and `UVM_FATAL : 0`.
- `make bugs` (errors, wid, early_wlast): each run reports the documented
  failure signature; an unexpected pass means the RTL was fixed and the
  README bug list should be updated.

## 5. Known gaps / future work

- Single outstanding transaction per direction is a DUT limitation; the
  blocking BFM mirrors it. Pipelined/outstanding traffic would need a
  split-channel driver and ID-indexed monitor/scoreboard tracking.
- SLVERR is not modeled (DUT never generates it).
- WRAP legality (power-of-2 lengths, aligned start) is not enforced by DUT or
  reference model — documented as a spec deviation, not scoreboard-visible.
- Coverage closure target: `x_dbsl` cross + `len_cp` across a multi-seed
  `make cov` run merged in IMC.
