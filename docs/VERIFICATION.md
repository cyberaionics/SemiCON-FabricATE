# Verification results

The delivered RTL was simulated with Verilator 5.49 (Python distribution
verilator 5.48.0, whose executable reports 5.49). The Icarus run script is provided
but was not executed in the build environment because Icarus was unavailable.

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
