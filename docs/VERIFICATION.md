# Verification results

The original interconnect delivery was simulated with Verilator 5.49 (Python distribution
verilator 5.48.0, whose executable reports 5.49). The Icarus run script is provided
but was not executed in that original build environment because Icarus was unavailable.
The current Icarus results are recorded separately below.

| Check | Result |
|---|---|
| Directed arbiter test | PASS |
| 512-bit, FIFO depth 4, seeds 12345 / 67890 / 314159 | PASS, 1,200 delivered beats each |
| 512-bit, FIFO depth 1, same seeds | PASS, 1,200 delivered beats each |
| 64-bit, FIFO depth 3, same seeds | PASS, 1,200 delivered beats each |
| Default-width waveform run, seed 12345 | PASS |
| Yosys 0.68 generic synthesis, ABC mapping disabled | PASS |
| Yosys structural check -assert | PASS, zero reported problems |

See `sim/verilator_results.log`, `sim/interconnect.vcd`, and
`synthesis/structural_results.log`. Compiler logs are in `sim/compile_logs/`.

Nine randomized runs validate 10,800 delivered beats after reset, plus the
repeated 1,200-beat waveform run. Each run also fills buffers while output is
blocked, resets to discard pending traffic, then verifies fresh traffic. Scoreboard
checks all payload bits, including bytes marked invalid, because this switch
preserves the entire beat without byte compaction.

Yosys maps the shallow FIFO memories to registers and emits the corresponding
memory-replacement warning. This is expected for this implementation. No latches
are inferred. The generic synthesis is not a device-specific area/timing result:
no Quartus fitting, MAX 10 hardware test, ASIC timing, GDSII or PCIe compliance
check has been performed. No exhaustive/formal verification is claimed.

## Packetizer integration verification, 2026-09-07

Executed `python sim/run_all.py` using native Windows Icarus Verilog 13.0.
WSL could not start, so a project-local MSYS2 Icarus package and runtime DLLs
were used; downloads remain in ignored `.tools/`. No RTL dependency on these
Windows packages exists. The same runner accepts ordinary Icarus on PATH.

| Check | Result |
|---|---|
| Original directed arbiter | PASS |
| Original nine width/depth/seed runs | PASS, 10,800 delivered beats |
| Standalone packetizer, three seeds | PASS, 120 packets / 388 frames |
| Integrated TX, FIFO depths 4, 1, 3; three seeds each | PASS, 720 packets / 2,328 frames |
| Additional integrated depth-4 waveform run | PASS, 80 packets / 256 frames |
| Integrated Yosys 0.68 synthesis, `-noabc` | PASS |
| Integrated `check -assert` | PASS, zero reported problems |

The 12 new regression runs cover 840 packets and 2,716 frames, excluding the
additional waveform repeat. Each run checks every output byte (including padding
and reserved bytes), frame length, KEEP, source, application-packet start/end,
and valid-byte count. Every output beat position experienced backpressure in
every run. Tests include exact frame boundaries with a subsequent empty LAST
beat, empty packets, sparse and null masks, long packets, and resets during
partial collection, first-beat stalls and partial frame transmission. Fresh
traffic after reset is checked against an independent packet oracle.

Evidence: `sim/icarus_results.log`, `sim/link_results.log`, `sim/link_tx.vcd`,
and `synthesis/link_structural_results.log`. Per-configuration compiler logs
are reproducible under ignored `sim/build/`.

The framing-only baseline reported 33,609 primitive cells, including 17,837
for the packetizer, with no latches. CRC integration results below supersede those counts.
These are unmapped generic counts, not
standard-cell area or FPGA resource estimates. Only the expected existing
FIFO memory-to-register warning is reported. That baseline made no claim of
CRC/FEC correctness, PCIe compliance, formal completeness, application workload
validation, device fit or timing. See `PACKETIZER.md` for protocol limitations.

## CRC integration verification, 2026-09-07

Executed the updated `python sim/run_all.py` with Icarus 13.0 and re-ran
`synthesis/check_link.ys` with Yosys 0.68 after adding the CRC engine.

| Check | Result |
|---|---|
| Python reference versus Appendix K matrix | PASS, all 1,936 single-bit basis inputs |
| CRC RTL versus independent polynomial division | PASS, 32 known-answer vectors |
| CRC enable gaps, clear priority, asynchronous reset | PASS |
| Syndrome checker corruption tests | PASS, 2,000 single-bit flips and 128 multi-byte patterns rejected |
| Original arbitration/interconnect regressions | PASS, all 10 runs |
| Standalone/integrated CRC-enabled frame regressions | PASS, all 12 runs; 840 packets / 2,716 frames |
| Additional CRC-enabled waveform run | PASS, 80 packets / 256 frames |
| Integrated synthesis and `check -assert` | PASS, zero reported problems |

Every emitted frame is now checked for CRC syndromes as well as payload,
padding, FEC zeros and metadata. A reset during CRC calculation was added to
every frame regression. All eight transfer positions still experienced stalls
in every run, including the final transfer containing the CRC bytes.

CRC-stage generic synthesis reported 35,931 primitive cells (370 in `flit_crc8`);
no latches are reported. These remain unmapped structural counts, not technology
area or timing results. Evidence is in `sim/crc_results.log`,
`sim/crc_matrix_results.log`, the refreshed `sim/link_results.log`,
`sim/icarus_results.log`, `sim/link_tx.vcd` and `synthesis/link_structural_results.log`.

The matrix cross-check validates the Python reference; the RTL was tested on
the listed vectors and integrated traffic, not formally proven equivalent over
all inputs. CRC checking and fault injection exist in the testbench only.
FEC, receiver RTL, protocol compliance and physical timing remain outside scope.
See `CRC.md` for the exact arithmetic, protected region and byte ordering.

## FEC integration verification, 2026-09-07

Executed the updated regression with Icarus 13.0, the optional Appendix J
reference comparison, the Python correction checks and Yosys 0.68 synthesis.

| Check | Result |
|---|---|
| FEC RTL versus independent weighted-sum oracle | PASS, 32 data patterns and all 2,000 input basis bits |
| Appendix J reference encoder versus same vectors | PASS, all 2,032 vectors |
| FEC enable gaps, clear priority, holding and reset/restart | PASS, reset from each of 3 group positions |
| Verification-only correction model | PASS, 2,048 single-bit flips and 254 three-byte bursts restored |
| Existing CRC and interconnect tests | PASS |
| CRC/FEC-enabled frame regressions | PASS, all 12 runs; 840 packets / 2,716 frames |
| Additional waveform repeat | PASS, 80 packets / 256 frames |
| Integrated synthesis and `check -assert` | PASS, zero reported problems |

Every complete frame now undergoes both CRC syndrome and FEC parity checking.
Reset during FEC calculation is included in each frame run. Stalls at all eight
output transfer positions are covered in every run; final-transfer stability
includes the CRC and FEC bytes. Existing payload and metadata checks still pass.

Current generic synthesis reports 38,148 primitive cells, including 181 in the
FEC encoder and 370 in the CRC engine. Only the expected FIFO memory replacement
warning is reported; no latches are inferred. These are unmapped structural
counts and do not establish area on a specific device or timing closure.

Evidence: `sim/fec_results.log`, `sim/fec_reference_results.log`,
`sim/fec_correction_results.log`, refreshed CRC/interconnect/link logs,
`sim/link_tx.vcd` and `synthesis/link_structural_results.log`.
The reference comparison uses the original Appendix J encoder equations, with
only the used constant alpha table declaration converted for Icarus compatibility.

The new hardware is TX encoding. Error correction was demonstrated in a Python
verification model, not receive RTL. The application-data framing prototype and
other protocol limitations remain. See `FEC.md` for mapping, arithmetic, timing
and the optional reference-comparison command.
