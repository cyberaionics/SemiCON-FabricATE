# SemiCON-FabricATE

A synthesizable SystemVerilog transmit subsystem for the SARCathon AXI4-to-PCIe
challenge. It combines two 512-bit AXI4-Stream sources, assembles 256-byte frames,
generates CRC and FEC bytes, and emits eight 256-bit transfers per frame.

**Status:** transmit framing, CRC and FEC are implemented and tested. The payload
format is a Stage 1 application-data prototype, not a complete PCIe-compliant
bridge. No vendor controller IP is instantiated.

## Quick start

Requirements:

- Python 3.9 or newer; only standard-library packages are used.
- Icarus Verilog (`iverilog` and `vvp`) on PATH. Recorded tests used version 13.0.
- Optional: a VCD waveform viewer, such as GTKWave.
- Optional: Yosys for structural synthesis.

```sh
git clone https://github.com/cyberaionics/SemiCON-FabricATE.git
cd SemiCON-FabricATE
python sim/run_all.py
```

Use `py -3` on Windows or `python3` on Linux/macOS if that is your Python command.
The Python runner does not require Bash or WSL. Windows Icarus installations also
need their runtime DLLs available. An existing project-local
`.tools/mingw64/bin` installation is recognized but is not distributed in Git.

The runner compiles tests, generates vectors, runs simulations and writes logs.
Compilation failures, simulation failures or missing PASS results cause a nonzero
exit. Binaries, vectors and compiler logs are generated under `sim/build/`.

## How it works

```mermaid
flowchart LR
    A[512-bit source 0] --> F0[Input FIFO]
    B[512-bit source 1] --> F1[Input FIFO]
    F0 --> ARB[Packet round-robin arbiter]
    F1 --> ARB
    ARB --> OF[Output FIFO]
    OF --> COL[Byte collection and framing]
    COL --> CRC[8-byte CRC]
    CRC --> FEC[6-byte FEC]
    FEC --> OUT[Eight 256-bit output transfers]
```

1. **Buffer inputs.** A transfer occurs on a rising clock edge when VALID and
   READY are high. Producers hold their beat unchanged until accepted.
2. **Arbitrate packets.** The arbiter keeps one source until its accepted LAST
   beat, including during stalls and source gaps. It then prefers the other
   source. Packets cannot interleave.
3. **Collect bytes.** The packetizer scans each 64-byte input beat. It collects
   bytes selected by KEEP in increasing lane order, starting with TDATA[7:0].
   Invalid bytes are discarded here; the upstream interconnect preserves them.
4. **Assemble frames.** Up to 236 application bytes fill each data region.
   Longer packets span frames; short final frames are zero-padded. Different
   application packets never share a frame.
5. **Generate protection.** CRC covers bytes 0-241. FEC covers bytes 0-249,
   including the completed CRC. Their GF(256) field polynomials differ.
6. **Emit eight transfers.** Output data and metadata remain stable whenever
   VALID is high and READY is low.

### Frame format

| Byte offsets | Size | Contents |
|---|---:|---|
| 0-235 | 236 bytes | Application data followed by zero padding |
| 236-241 | 6 bytes | Reserved data-link region, currently zero |
| 242-249 | 8 bytes | Computed CRC0 through CRC7 |
| 250-255 | 6 bytes | Computed FEC C1, C2, C0, P1, P2, P0 |

The data region contains raw application bytes. Real PCIe TLP headers, packing
rules and data-link semantics are not implemented. Exact CRC arithmetic and FEC
mapping, with specification references, are in [CRC.md](docs/CRC.md) and
[FEC.md](docs/FEC.md).

### Top level and handshake

Use **`axis_link_tx`** as the integrated top level. FIFO_DEPTH defaults to 4;
input/output widths are fixed at 512/256 bits.

| Signals | Meaning |
|---|---|
| `clk`, `rst_n` | Shared clock and active-low reset |
| `s0_axis_*`, `s1_axis_*` | Input DATA[511:0], KEEP[63:0], LAST, VALID and READY |
| `m_axis_tdata`, `m_axis_tkeep` | Output DATA[255:0] and KEEP[31:0] |
| `m_axis_tvalid`, `m_axis_tready` | Output handshake |
| `m_axis_tlast` | Final, eighth transfer of a frame |
| `m_axis_source` | Original source 0 or 1 |
| `m_frame_bytes` | Application bytes in this frame, 0-236 |
| `m_packet_start`, `m_packet_end` | First/final frame of an application packet |

Output KEEP is all ones during valid transfers: padding and parity are transmitted
bytes. Metadata is repeated on every transfer of its frame. These internal
sidebands are not encoded into the protected bytes; downstream logic must retain
them to reconstruct application packets.

An empty packet produces one frame with byte count zero. Exact multiples of
236 bytes do not create an extra empty frame, including when LAST arrives on a
subsequent all-zero KEEP beat. A full frame waits for another valid byte or packet
end before finalization.

### Reset and performance

Reset aborts pending packets, frames and parity calculations. Reset all connected
stages together and release reset synchronously to the shared clock. There is no
clock-domain crossing, packet timeout or abort protocol. A source that never
completes a packet can block the other source.

The collector scans one lane per cycle, including invalid lanes. Without frame
processing, input handshakes are 66 clocks apart. Each frame adds 242 CRC cycles,
250 FEC cycles and at least eight output cycles. Backpressure extends this.
The implementation is a functional baseline, not optimized for PCIe line rate.

## File structure

```text
SemiCON-FabricATE/
|-- rtl/                         Synthesizable hardware
|   |-- axis_fifo.sv             FIFO for data and metadata
|   |-- packet_rr_arbiter.sv     Packet-held round-robin arbitration
|   |-- axis_interconnect_2to1.sv  Two ingress FIFOs and an output FIFO
|   |-- axis_frame_packetizer.sv  Collection, framing and CRC/FEC sequencing
|   |-- flit_crc8.sv             Eight-byte CRC accumulator
|   |-- flit_fec6.sv             Three-group FEC encoder
|   `-- axis_link_tx.sv          Integrated transmit top level
|-- tb/                          Simulation-only testbenches
|   |-- tb_arbiter.sv
|   |-- tb_interconnect.sv
|   |-- tb_link_tx.sv
|   |-- tb_flit_crc8.sv
|   |-- tb_flit_fec6.sv
|   |-- crc_reference.svh        Independent CRC checking functions
|   `-- fec_reference.svh        Independent FEC checking functions
|-- sim/
|   |-- run_all.py               Complete Icarus regression
|   |-- crc_vectors.py           Independent CRC vector generation
|   |-- fec_vectors.py           FEC vectors and software correction checks
|   |-- check_fec_reference.py   Optional specification-encoder comparison
|   |-- run.sh                   Original interconnect: Bash/Icarus
|   |-- run_link.sh              Frame pipeline: Bash/Icarus
|   |-- run_verilator.sh         Original interconnect: Verilator
|   |-- *_results.log            Recorded verification evidence
|   `-- build/                   Generated binaries/vectors; ignored
|-- synthesis/
|   |-- check.ys                 Original interconnect synthesis
|   |-- check_link.ys            Integrated transmit synthesis
|   `-- *_results.log            Recorded synthesis evidence
|-- docs/
|   |-- INTERFACE.md             Original interconnect boundary
|   |-- PACKETIZER.md            Frame and sideband contract
|   |-- CRC.md                   CRC arithmetic and ordering
|   |-- FEC.md                   FEC grouping and parity mapping
|   |-- VERIFICATION.md          Executed checks and limitations
|   `-- BUILD_PLAN.md            Original planning notes
|-- .gitignore                   Generated/local files excluded
|-- .gitattributes               Consistent text line endings
`-- README.md
```

## Testbenches and simulation

| Testbench | Main checks |
|---|---|
| `tb_arbiter` | Stalled first/final beats, owner gaps, alternating grants and reset |
| `tb_interconnect` | Independent per-source scoreboards; data/KEEP/LAST integrity, ordering and reset flushing |
| `tb_flit_crc8` | 32 reference vectors, enable gaps, clear/reset and corruption checks |
| `tb_flit_fec6` | 32 patterns plus all 2,000 input basis bits; enable gaps and reset at each group position |
| `tb_link_tx` | Payload, padding, metadata, CRC, FEC, frame boundaries, source ownership, stalls and reset during processing |

The runner uses seeds 12345, 67890 and 314159. Interconnect width/depth cases are
512/4, 512/1 and 64/3. Frame tests cover the standalone packetizer and integrated
FIFO depths 4, 1 and 3.

Packet lengths include 0, 1, 31, 32, 33, 63, 64, 65, 235, 236, 237, 472, 473
and 2048 bytes, plus other deterministic lengths. Tests exercise sparse/null
KEEP, long packets, exact boundaries and stalls at all eight output positions.

### Recorded results

| Evidence | Result |
|---|---|
| `sim/icarus_results.log` | Arbiter plus nine original runs passed; 10,800 delivered beats |
| `sim/link_results.log` | 12 runs passed; 840 packets / 2,716 frames, plus a waveform repeat |
| `sim/crc_results.log` | 32 vectors passed; checker rejected 2,128 corrupted codewords |
| `sim/crc_matrix_results.log` | Python reference matched 1,936 specification matrix basis inputs |
| `sim/fec_results.log` | FEC RTL matched all 2,032 vectors |
| `sim/fec_reference_results.log` | Specification reference encoder matched those vectors |
| `sim/fec_correction_results.log` | Software model restored 2,302 injected-error frames |

The runner regenerates **`sim/link_tx.vcd`**. Open it in a waveform viewer to
inspect DATA, VALID/READY, LAST, source, byte count and packet flags. VCD files
are ignored by Git; compact result logs remain verification evidence.

Optional matrix/reference comparisons require externally supplied specification
files and are not part of the default regression. Commands are in
[CRC.md](docs/CRC.md) and [FEC.md](docs/FEC.md). Reference files and local
compatibility copies are not distributed. The correction model is Python
verification code, not a synthesized receiver.

For narrower runs, use:

```sh
bash sim/run.sh
bash sim/run_link.sh
bash sim/run_verilator.sh
```

The Verilator script covers the **original interconnect only** and needs a C++
toolchain. Use the Python/Icarus runner for the complete current subsystem.

## Synthesis

With Yosys installed, run from the repository root:

```sh
yosys -l synthesis/link_structural_results.log synthesis/check_link.ys
```

This synthesizes `axis_link_tx` and runs `check -assert`. Recorded Yosys 0.68
results show zero structural problems, no inferred latches and 38,148 generic
primitive cells. Small FIFO memories become registers, producing the expected
warning. The script uses `-noabc`, so it does not perform technology mapping.

These results do not establish device area, timing closure, FPGA fit or GDSII.
Only the seven files under `rtl/` belong in the integrated synthesis source
list. Testbenches are not synthesizable. A board demonstration also needs a
board-specific wrapper, clock/reset conditioning and pin constraints; wide
stream buses should remain internal.

## Changes from the original starter

1. Added the packetizer and integrated wrapper: byte compaction, padding,
   packet splitting, metadata and 256-bit frame output.
2. Added CRC generation and independent vectors/syndrome checks.
3. Added FEC generation, reference-encoder comparison, basis-vector tests and
   a verification-only correction model.
4. Added the complete Python regression runner, integrated synthesis script,
   waveform generation and detailed implementation/result documentation.
5. Excluded generated builds, downloaded tools and waveforms from Git, while
   retaining sources, scripts, documentation and compact result logs.

## Commit and push

GitHub recognizes the existing `README.md` filename. Local tool installations,
simulation executables, Python caches and waveforms should not be staged.
The documented commands regenerate these files.

Review and publish from the repository root:

```sh
git status --short
git diff --check
git add README.md .gitignore .gitattributes rtl tb sim synthesis docs
git diff --cached --stat
git commit -m "Document and integrate transmit packetizer, CRC and FEC"
git push -u origin HEAD
```

Inspect the staged changes before committing. The push publishes your current
branch and requires write access to the configured remote. No force push is needed.

## Remaining work

- Receive-side FEC correction and CRC checking in synthesizable RTL.
- Real TLP/DLP encoding, descriptors, transactions, replay and credits.
- Lane striping, digital symbol mapping and PHY integration.
- Throughput optimization, application workloads and broader verification.
- Technology-mapped synthesis, timing analysis, physical design and GDSII.

Memory-mapped AXI4 AW/W/B/AR/R interfaces, a general N-by-M crossbar and a board
wrapper are also outside the current implementation. See
[VERIFICATION.md](docs/VERIFICATION.md) for the limits of the executed checks.
