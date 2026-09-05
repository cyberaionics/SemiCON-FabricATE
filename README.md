# SARCathon AXI4-Stream interconnect starter

Implemented: portable synthesizable two-input/one-output streaming subsystem,
default 512-bit data, per-byte KEEP, packet LAST, source tracking, small FIFOs,
packet-held round-robin arbitration, and shared reset. No vendor IP instantiated.

## Start here

1. Read `docs/INTERFACE.md` with both teammates and freeze the boundary.
2. Run `bash sim/run.sh` from a terminal with Icarus Verilog and vvp installed.
3. Read `sim/results.log`; open `sim/interconnect.vcd` in your waveform viewer.
4. Connect `m_axis_*` to the link-layer implementation. The sink drives READY.

The script uses Bash (Linux/macOS, or an appropriate Windows Bash environment).
RTL filenames are explicitly listed so there are no compile-order surprises.

## Files

- `rtl/axis_fifo.sv`: data + metadata FIFO, arbitrary positive depth.
- `rtl/packet_rr_arbiter.sv`: two-request packet ownership and round robin.
- `rtl/axis_interconnect_2to1.sv`: two ingress FIFOs, selection, output FIFO.
- `tb/tb_arbiter.sv`: directed arbitration corner cases.
- `tb/tb_interconnect.sv`: deterministic randomized traffic and independent
  per-input queues, with comparison of every data bit, KEEP, LAST and source.
- `sim/run.sh`: three width/depth configurations and three random seeds each,
  plus one waveform run at default parameters.
- `synthesis/check.ys`: generic Yosys synthesis and structural checks.
- `docs/INTERFACE.md`: exact teammate interface and limitations.
- `docs/BUILD_PLAN.md`: next steps for the three-day deadline.

Alternative simulation with Verilator (requires a C++ toolchain):

```sh
bash sim/run_verilator.sh
```

Optional generic synthesis (requires Yosys):

```sh
yosys -l synthesis/structural_results.log synthesis/check.ys
```

## Verification scope

The testbench checks data loss/duplication/order, packet non-interleaving,
output stability during stalls, simultaneous ingress, partial final transfers,
backpressure, and flushing buffered traffic on reset. Directed arbiter checks
cover stalled first and final beats, gaps from an owner, alternating grants and
reset preference. Depth 1 and non-power-of-two depth 3 exercise pointer limits.
These are targeted functional tests, not exhaustive formal AXI verification.

## Quartus and submission scope

Add ONLY the three rtl/*.sv files to a Quartus project to synthesize the core.
Select device 10M50DAF484C7G. Simulation testbench files are not synthesizable.
For a physical board demo, create a separate top-level wrapper with internal
traffic generators/checkers, clock/reset conditioning and actual board pin
constraints. Do not assign the 512-bit internal buses to external board pins.
No board wrapper is supplied because board model and pinout are not established.

This project does not contain memory-mapped AXI4 AW/W/B/AR/R adapters, a full
N-by-M crossbar, routing descriptors, PCIe packetization, CRC/FEC, receive path,
PHY, or GDSII. It is the first verified streaming subsystem for Stage 1.
Generic synthesis does not establish MAX 10 fit, timing or PCIe compliance.

Actual executed checks and limits are recorded in `docs/VERIFICATION.md`.
Generic synthesis deliberately uses `-noabc`; it is a structural check, not technology mapping.
