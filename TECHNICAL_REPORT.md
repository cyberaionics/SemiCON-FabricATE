# SemiCON-FabricATE Technical Report

**Project:** SemiCON-FabricATE  
**Challenge:** SARCathon 2026 SemiCON Hackathon, "Design the Bridge. Connect the Future."  
**Repository:** `cyberaionics/SemiCON-FabricATE`  
**Report date:** 2026-09-13  
**Assessment basis:** repository RTL, testbenches, scripts, recorded logs, design documentation, and the supplied problem-statement PDF

## 1. Executive Summary

The supplied challenge asks teams to develop an AXI4-to-PCIe interface, verify its RTL, validate it against meaningful workloads, synthesize it, and ultimately carry the design toward physical implementation and GDSII. The repository delivers a substantial transmit-side RTL prototype in two stages:

1. **Stage 1:** two 512-bit AXI4-Stream inputs are buffered, arbitrated without packet interleaving, compacted into application-data frames, protected with an eight-byte CRC and six-byte FEC field, and emitted as eight 256-bit transfers per frame.
2. **Stage 2:** an independent 256-bit protocol-to-PHY digital path stripes data across four lanes, scrambles each lane, applies Gray/PAM4 symbol mapping, and reverses the operation at the receiver under control of a link-training state machine.

The implementation is synthesizable SystemVerilog and has strong simulation evidence. The current regression executed successfully with Icarus Verilog 13.0. It covered CRC and FEC unit behavior, error-injection models, arbitration, interconnect traffic, packet framing, output backpressure, packet splitting, sparse `TKEEP`, resets, and Stage 2 PHY/LTSSM behavior.

The design should be described accurately as a **verified transmit/framing and digital-PHY prototype**, not as a complete PCIe 6.0 AXI4 bridge. It does not implement real AXI memory-mapped transactions, PCIe TLP/DLP encoding, receive-side CRC/FEC hardware, replay or credit management, PCIe ordered sets, analog SerDes behavior, application workload validation, FPGA fitting, timing closure, OpenROAD/OpenLane implementation, or GDSII generation. Stage 2 is currently not wired to the Stage 1 frame output.

## 2. Problem Statement and Requirement Interpretation

The supplied PDF, `6a98574f4fcb9_semicon_hackathon_docx.pdf`, defines two stages.

### Stage 1: Qualifier

The challenge requests:

- understanding the provided architecture and specifications;
- Verilog/SystemVerilog RTL;
- a functional testbench;
- verification of key read/write transactions, reset, and error behavior; and
- simulation results with a short design report.

The repository addresses the RTL, testbench, reset, error-injection, and simulation portions through a transmit-oriented AXI4-Stream prototype. It does not implement read/write transaction semantics or a PCIe controller boundary.

### Stage 2: Grand Finale

The PDF requests:

- performance, area, and reliability refinement;
- exhaustive functional verification;
- network-packet and ML-inference workload validation;
- synthesis and implementation analysis;
- OpenROAD/OpenLane physical design; and
- final GDSII, with FPGA testing as a bonus.

The repository adds a digital PHY prototype and generic Yosys synthesis scripts. It does not contain workload generators/results, technology-specific implementation, OpenROAD/OpenLane configuration, GDSII, FPGA results, or a complete integrated Stage 1-to-Stage 2 datapath.

## 3. Delivered Scope and Top-Level Data Flow

The tested Stage 1 path is:

```text
AXI-Stream source 0 (512 bits)
        \
         -> input FIFO 0 ----\
                              packet-held round-robin arbiter
         -> input FIFO 1 ----/          |
                                         v
                                  two-beat output FIFO
                                         |
                                         v
                              byte collection and framing
                                         |
                                         v
                                    CRC generation
                                         |
                                         v
                                    FEC generation
                                         |
                                         v
                              eight 256-bit output transfers
```

The principal integrated top level is `rtl/axis_link_tx.sv`. Its input boundary is two 512-bit AXI4-Stream-like interfaces. Its output boundary is a 256-bit ready/valid stream with frame metadata.

The independent Stage 2 path is:

```text
256-bit input
  -> byte striping over four lanes
  -> independent 23-bit lane scramblers
  -> Gray coding
  -> two-bit digital PAM4 symbols
  -> inverse RX mapping, descrambling, and destriping
  -> 256-bit output
```

The Stage 2 top level is `rtl/protocol_to_phy_top.sv`. Its LTSSM controls whether the TX and RX datapaths are enabled. No direct RTL connection currently exists between `axis_link_tx` and `protocol_to_phy_top`; integration remains a future milestone.

## 4. Stage 1 Architecture

### 4.1 AXI4-Stream ingress and arbitration

`rtl/axis_interconnect_2to1.sv` instantiates one FIFO per source and a two-beat output FIFO. The FIFO preserves complete input beats and their `TKEEP`, `TLAST`, and source identity. It does not compact bytes; compaction occurs later in the packetizer.

`rtl/packet_rr_arbiter.sv` implements packet-held round-robin arbitration:

- ownership is acquired when a source presents a selectable beat;
- ownership remains fixed during stalls and source gaps;
- ownership is released only after the selected `TLAST` beat is accepted;
- the next preference alternates after a completed packet; and
- a missing preferred source does not prevent the other source from progressing.

This prevents packet interleaving, but fairness is packet-based and assumes packets eventually terminate. A source that never asserts `TLAST` can block the other source indefinitely because there is no timeout or abort protocol.

The stream convention is byte lane zero at `TDATA[7:0]`, with `TKEEP[0]` qualifying that byte. Invalid bytes are retained through the interconnect and discarded only by the packetizer. FIFO readiness depends on current occupancy, so a full FIFO does not recover in the same cycle as a pop; this is functionally conservative but reduces throughput, especially at depth one.

### 4.2 Frame packetizer

`rtl/axis_frame_packetizer.sv` uses the following phases:

| Phase | Function |
|---|---|
| `COLLECT` | Accept and store one 512-bit input beat. |
| `SCAN` | Examine all 64 byte lanes, one lane per cycle, and append only qualified bytes. |
| `FINISH` | Determine whether the packet ended, whether the frame is full, and whether another frame is required. |
| `CRC` | Process the first 242 frame bytes. |
| `FEC` | Process the first 250 frame bytes, including the generated CRC. |
| `EMIT` | Present eight 256-bit output transfers with stable metadata. |

The packetizer stores one input beat and a 236-byte application payload region. It does not combine application packets in one frame. Long packets are divided into multiple frames. An empty packet produces one zero-byte frame. Exact 236-byte packets do not produce an unwanted extra empty frame, even if a later all-zero-`TKEEP` beat carries `TLAST`.

During output backpressure, `TDATA`, `TKEEP`, `TLAST`, source, byte count, and packet flags remain stable. Reset aborts any partial collection, parity calculation, or frame transmission.

### 4.3 Frame format

Every emitted frame is 256 bytes and is transferred as eight 32-byte beats.

| Byte offsets | Size | Contents | Protection |
|---:|---:|---|---|
| 0-235 | 236 bytes | Compacted application bytes followed by zero padding | CRC and FEC |
| 236-241 | 6 bytes | Reserved data-link region, currently zero | CRC and FEC |
| 242-249 | 8 bytes | CRC0 through CRC7 | FEC only |
| 250-255 | 6 bytes | `C1, C2, C0, P1, P2, P0` | Transmitted FEC |

Output `TKEEP` is all ones for every valid transfer. Padding, reserved bytes, CRC, and FEC are transmitted bytes, so the output is a fixed-size frame rather than a variable-size final transfer.

Frame metadata is repeated on all eight transfers:

| Signal | Width | Meaning |
|---|---:|---|
| `m_axis_source` | 1 | Original source number, 0 or 1 |
| `m_frame_bytes` | 8 | Application bytes represented by this frame, 0-236 |
| `m_packet_start` | 1 | First frame of an application packet |
| `m_packet_end` | 1 | Final frame of an application packet |
| `m_axis_tlast` | 1 | Final transfer of the 256-byte frame, independent of packet end |

These sidebands are internal prototype metadata. They are not inserted into the protected bytes and would need a defined downstream representation in a complete link.

## 5. CRC and FEC Implementation

### 5.1 Eight-byte CRC

`rtl/flit_crc8.sv` computes an eight-byte Reed-Solomon CRC over frame bytes 0-241:

- field: GF(256);
- primitive polynomial: `0x12B`, or $x^8+x^5+x^3+x+1$;
- field alpha: `0x02`;
- generator coefficients: `01 D5 68 FE D5 33 41 4D 69`;
- initial state: zero;
- reflection: none;
- final complement: none; and
- byte order: `crc[7:0]` is CRC0 and `crc[63:56]` is CRC7.

The CRC accumulator accepts one enabled byte per cycle. The caller controls clearing, byte count, and frame boundaries. The packetizer performs the complete 242-cycle CRC pass before starting FEC.

The Python reference in `sim/crc_vectors.py` derives the generator through polynomial operations rather than copying the RTL recurrence. This provides an independent oracle for known vectors and integrated frames.

### 5.2 Six-byte FEC

`rtl/flit_fec6.sv` computes six ECC bytes over frame bytes 0-249, including the completed CRC:

- field: GF(256);
- primitive polynomial: `0x11D`, or $x^8+x^4+x^3+x^2+1$;
- three interleaved groups selected by byte index modulo three;
- group 0 has 84 transmitted symbols;
- groups 1 and 2 have 83 transmitted symbols plus an implicit zero; and
- each group generates a weighted check value `C` and an XOR parity value `P`.

The transmitted mapping is:

| Frame byte | Value |
|---:|---|
| 250 | `C1` |
| 251 | `C2` |
| 252 | `C0` |
| 253 | `P1` |
| 254 | `P2` |
| 255 | `P0` |

The FEC pass consumes 250 enabled cycles after CRC insertion. The RTL is an encoder only. The correction model in `sim/fec_vectors.py` is verification software and is not a synthesized receive datapath.

## 6. Stage 2 Digital PHY Prototype

### 6.1 Datapath

The Stage 2 modules implement a reversible digital transformation:

1. `lane_striper.sv` distributes bytes over four lanes.
2. `lane_scrambler.sv` applies an independent 23-bit LFSR-based operation on each lane.
3. `gray_pam4_tx.sv` maps pairs of bits through Gray coding to two-bit PAM4 symbols.
4. `gray_pam4_rx.sv` reverses the symbol mapping and Gray coding.
5. `lane_destriper.sv` reconstructs the original 256-bit word.

`protocol_to_phy_tx.sv` and `protocol_to_phy_rx.sv` provide ready/valid buffering around the transform. RX output is held until accepted, and the TX path is gated by link state.

### 6.2 LTSSM

`rtl/ltssm.sv` models Detect, Polling, Configuration, L0, Recovery, Disabled, and Hot Reset behavior. It exposes `link_up`, TX/RX enable controls, training/recovery indicators, the current state, and a state-change pulse.

The Stage 2 testbench exercises invalid link width blocking, link bring-up, recovery requests, PHY-error recovery, disabled/retraining, and hot reset. One implementation detail should be addressed before claiming a parameter-complete LTSSM: `DETECT_WAIT_CYCLES` is exposed as a parameter but the current Detect path does not use it to delay the next state.

## 7. Verification Strategy and Results

### 7.1 Current executable validation

On 2026-09-13, the repository regression was run with Python 3 and Icarus Verilog 13.0 using:

```sh
python3 sim/run_all.py
```

The run completed successfully. The key results were:

| Area | Result |
|---|---|
| FEC RTL | 2,032 vectors, including 2,000 basis-bit vectors, enable gaps, clear priority, and three reset positions: PASS |
| FEC software correction | 2,302 injected-error frames restored: 2,048 bit flips and 254 three-byte bursts: PASS |
| CRC RTL | 32 vectors, enable gaps, clear/reset, and 2,128 corrupted codewords rejected: PASS |
| Arbiter | Stalled first/final beat, source gaps, round robin, and reset: PASS |
| Interconnect | 10 randomized configurations/runs, 10,800 delivered beats overall: PASS |
| Stage 1 packetizer/link | Standalone and integrated runs across depths 1, 3, and 4, 840 packets and 2,716 frames in the recorded regression set: PASS |
| Waveform run | Integrated `sim/link_tx.vcd` generated successfully: PASS |

The integrated checker covers:

- empty packets;
- sparse, null, and partial `TKEEP` masks;
- packet lengths around 236-byte boundaries;
- long packets split across frames;
- source ownership across packet boundaries;
- backpressure at all eight output positions;
- output stability while stalled;
- reset during collection, CRC, FEC, and output; and
- fresh traffic after reset.

The measured architecture is intentionally low-throughput. A 512-bit input beat is scanned one byte lane per cycle, so collection alone introduces approximately 66 cycles between input handshakes. Each frame adds 242 CRC cycles, 250 FEC cycles, and at least eight output handshake cycles, with stalls extending the latency.

### 7.2 Stage 2 executable validation

The three Stage 2 benches were also compiled and run directly with Icarus 13.0. The integrated bench completed with 113 checks/transactions and reported:

- invalid link width correctly blocked L0;
- LTSSM reached L0;
- directed TX-to-four-lane-PAM4-to-RX loopback passed;
- RX ready/valid backpressure passed;
- injected symbol corruption was observable at RX;
- explicit Recovery and `phy_error` both returned to L0;
- 100 randomized end-to-end transactions passed;
- Disabled returned toward Detect;
- retraining transferred data; and
- Hot Reset returned toward Detect.

The block-level bench passed striping/destriping, Gray/PAM4 inverse mapping, scrambler round trips, and a second directed pattern. The standalone LTSSM bench passed L0, Recovery-to-L0, and Disabled-to-Detect checks.

Icarus emitted expected support warnings for constant selects in `always_*` blocks in the scrambler and missing explicit time units in several modules. These did not cause a test failure, but adding explicit time units and considering `always_comb`/`always_ff` portability would make tool behavior clearer.

### 7.3 Verification limits

The tests are strong directed and randomized simulation evidence, but they are not exhaustive proof. In particular:

- no formal properties or equivalence checking are included;
- receive-side CRC checking and FEC correction are not RTL-tested because they do not exist as hardware;
- no real PCIe transaction workload is generated;
- the corruption tests do not establish complete multi-error detection guarantees;
- Stage 1 and Stage 2 are not verified as one connected end-to-end design; and
- the Stage 2 result logs referenced by `docs/VERIFICATION.md` are absent from this checkout even though the tests can be run directly.

## 8. Synthesis and Implementation Status

The checked-in scripts provide generic Yosys structural checks:

- `synthesis/check_link.ys` targets the Stage 1 `axis_link_tx` hierarchy;
- `synthesis/run_yosys.ys` targets the Stage 2 `protocol_to_phy_top` hierarchy; and
- `check -assert` is included after synthesis.

Recorded repository evidence reports:

| Design | Recorded result |
|---|---|
| Stage 1 CRC/FEC-integrated path | Yosys structural synthesis passed; 38,148 unmapped generic primitive cells; no inferred latches; `check -assert` passed |
| Stage 2 digital PHY path | Yosys structural synthesis reported 7,758 primitive cells and 4,171 wires; no inferred latches; `check -assert` passed |

These numbers are generic structural counts, not standard-cell area, FPGA utilization, timing, power, or a technology-specific result. The Stage 1 FIFOs and Stage 2 small scrambler memories are expected to map to registers in this implementation.

The current machine does not have `yosys` on `PATH`, so the recorded synthesis results could not be independently regenerated during this review. Additionally, `synthesis/run_yosys.sh` invokes a nonexistent `synthesis/run_yosys.py`; the checked-in `.ys` script must be invoked directly or the wrapper must be repaired.

No OpenROAD/OpenLane configuration, floorplan, placement, routing, parasitic extraction, timing report, signoff report, or GDSII was found. No FPGA fit or hardware test evidence was found.

## 9. Traceability to the Challenge

| Challenge requirement | Repository evidence | Status |
|---|---|---|
| Develop synthesizable RTL | `rtl/*.sv`, Stage 1 and Stage 2 tops | Addressed for the prototype scope |
| Provide functional testbench | `tb/*.sv`, independent Python reference models | Addressed |
| Verify reset behavior | Unit, interconnect, packetizer, CRC/FEC, and LTSSM tests | Addressed for implemented blocks |
| Verify error behavior | CRC corruption rejection, FEC correction model, PHY symbol corruption visibility | Partially addressed; no receive FEC/CRC hardware |
| Verify key AXI/PCIe read/write transactions | AXI4-Stream beat movement is tested; no memory-mapped AXI or PCIe TLP transactions | Not addressed |
| Demonstrate simulation results | Current Icarus regression and recorded logs | Addressed |
| Optimize for performance/area/reliability | Functional baseline and generic structural synthesis only | Partially addressed |
| Test network packet workloads | No workload model or results | Not addressed |
| Test ML-inference workloads | No workload model or results | Not addressed |
| Synthesize and analyze implementation | Generic Yosys scripts and recorded structural counts | Partially addressed |
| Complete OpenROAD/OpenLane flow | No flow configuration or reports | Not addressed |
| Generate GDSII | No GDSII artifact | Not addressed |
| FPGA-tested bonus | No FPGA project, fit, or board evidence | Not addressed |

## 10. Limitations and Engineering Risks

1. **Not a complete PCIe bridge.** The frame payload is raw application data. TLP headers, addresses, attributes, tags, DLP semantics, sequence numbers, replay, credits, flow control, and completion handling are absent.
2. **Transmit-only protection.** CRC and FEC encoders exist, but receive-side checking and correction are not synthesized RTL.
3. **Stage 2 is disconnected.** The PHY top level begins at an independent 256-bit interface rather than consuming `axis_link_tx` frames.
4. **No read path.** The design does not provide host-to-accelerator or PCIe-to-AXI return traffic.
5. **Packet termination dependency.** A missing `TLAST` can block the other source indefinitely.
6. **Low throughput.** One-byte-per-cycle scanning and sequential CRC/FEC passes create large per-frame latency.
7. **Register-heavy buffering.** Shallow FIFO memories and the 236-byte frame store may consume substantial resources on a target FPGA or ASIC standard-cell implementation.
8. **Parameter checks are implicit.** Invalid widths and illegal FIFO depths are documented but are not guarded by explicit elaboration-time assertions.
9. **LTSSM parameter gap.** `DETECT_WAIT_CYCLES` is declared but not used in the Detect transition behavior.
10. **Digital PHY abstraction.** PAM4 symbols are represented as digital two-bit values; physical SerDes and compliance behavior are outside the model.
11. **Tooling inconsistency.** The Linux Yosys wrapper references a missing Python script, and the documented Stage 2 result artifacts are not present in the current checkout.
12. **No physical-design evidence.** Generic synthesis is not a substitute for timing closure, power analysis, placement/routing, or GDSII signoff.

## 11. Recommended Next Steps

### Priority 1: define and integrate the protocol boundary

1. Specify a real transaction model: AXI4 memory-mapped or a clearly constrained AXI4-Stream transaction layer.
2. Add request/completion descriptors, address fields, tags, packet attributes, and return traffic.
3. Define how frame metadata is encoded or transported downstream.
4. Connect `axis_link_tx` to the Stage 2 256-bit input with a documented adapter and end-to-end testbench.

### Priority 2: complete receive and link-layer protection

1. Implement RTL CRC checking and FEC syndrome/correction logic on the receive path.
2. Verify correction followed by CRC validation for one-error-per-group and multi-error cases.
3. Add sequence/replay handling, credit/flow control, and error reporting appropriate to the target protocol.

### Priority 3: improve throughput and resource use

1. Compact multiple input bytes per cycle instead of scanning one lane per cycle.
2. Pipeline or parallelize CRC/FEC processing where the target clock and area budget justify it.
3. Replace register-heavy FIFOs with inferred or instantiated target memories where appropriate.
4. Add explicit parameter assertions and measure latency, throughput, area, and power under representative traffic.

### Priority 4: make verification challenge-complete

1. Add constrained-random transaction traffic for network packet and ML tensor workloads.
2. Add assertions for ready/valid stability, packet ownership, frame boundaries, reset recovery, and protocol invariants.
3. Add formal checks for FIFO safety, no packet interleaving, and output stability under arbitrary backpressure.
4. Store reproducible Stage 2 logs and waveforms in the expected locations or update the documentation to match the artifact policy.

### Priority 5: complete implementation flow

1. Repair `synthesis/run_yosys.sh` or replace it with a direct Yosys wrapper.
2. Select a target FPGA or open PDK and establish constraints.
3. Add OpenROAD/OpenLane configuration, timing constraints, floorplanning, and signoff checks.
4. Generate and archive reports for area, timing, power, DRC/LVS, and GDSII.

## 12. Reproduction Commands

### Stage 1 regression

```sh
python3 sim/run_all.py
```

or:

```sh
./sim/run_all_crc.sh
```

### Stage 2 integrated simulation

```sh
mkdir -p sim/build
iverilog -g2012 -Wall -s tb_integrated -o sim/build/phy_integrated_sim \
  rtl/phy_pkg.sv rtl/ltssm.sv rtl/lane_striper.sv rtl/lane_destriper.sv \
  rtl/lane_scrambler.sv rtl/gray_pam4_tx.sv rtl/gray_pam4_rx.sv \
  rtl/protocol_to_phy_tx.sv rtl/protocol_to_phy_rx.sv \
  rtl/protocol_to_phy_top.sv tb/tb_integrated.sv
vvp sim/build/phy_integrated_sim
```

The block-level and standalone LTSSM benches use the same source list pattern and are listed in `sim/run_all.ps1`.

### Generic synthesis, when Yosys is installed

```sh
yosys -l synthesis/link_structural_results.log synthesis/check_link.ys
yosys -l synthesis/phy_structural_results.log synthesis/run_yosys.ys
```

## 13. Conclusion

SemiCON-FabricATE provides a coherent, synthesizable, and well-tested transmit-side baseline. Its strongest contribution is the complete simulated Stage 1 data path: packet-preserving arbitration, byte-compacting frame assembly, CRC/FEC generation, metadata propagation, and robust ready/valid behavior under stalls and resets. The independent Stage 2 prototype extends the work into a digital four-lane PAM4-style path with link-state control and meaningful randomized verification.

The evidence supports claiming a functional RTL prototype and a strong Stage 1 simulation result. It does not support claiming a complete AXI4-to-PCIe bridge, PCIe compliance, full workload validation, FPGA implementation, physical design completion, or GDSII. The most important engineering step is to close the boundary between the tested prototypes and then add the missing transaction, receive, implementation, and workload-validation layers required by the challenge statement.