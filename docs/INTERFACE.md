# Integration contract, revision 1

Scope: two AXI4-Stream ingress ports to one buffered output. This is a streaming
switch, not a memory-mapped AXI4 master/slave, DMA engine, or PCIe controller.
No PCIe compliance or MAX 10 timing/fit result is claimed.

## Top level

`axis_interconnect_2to1` in `rtl/axis_interconnect_2to1.sv`.
Parameters: DATA_WIDTH=512, FIFO_DEPTH=4, KEEP_WIDTH=DATA_WIDTH/8.
DATA_WIDTH must be a positive multiple of 8; FIFO_DEPTH must be >=1. Do not
override KEEP_WIDTH independently. Depths need not be powers of two.

| Port | Direction relative to this module | Width | Contract |
|---|---|---|---|
| clk | Input | 1 | All ports use rising edges of this shared clock |
| rst_n | Input | 1 | Active-low asynchronous assertion; release synchronously to clk |
| s0_axis_tdata / s1_axis_tdata | Input | DATA_WIDTH | Payload |
| s0_axis_tkeep / s1_axis_tkeep | Input | KEEP_WIDTH | One validity bit per byte |
| s0_axis_tlast / s1_axis_tlast | Input | 1 | Application packet end |
| s0_axis_tvalid / s1_axis_tvalid | Input | 1 | Producer presents a beat |
| s0_axis_tready / s1_axis_tready | Output | 1 | This module accepts a beat |
| m_axis_tdata | Output | DATA_WIDTH | Payload for link-layer teammate |
| m_axis_tkeep | Output | KEEP_WIDTH | Preserved byte mask |
| m_axis_tlast | Output | 1 | Application packet end, NOT PCIe FLIT end |
| m_axis_tvalid | Output | 1 | Output beat available |
| m_axis_tready | Input | 1 | Link layer can accept output beat |
| m_axis_source | Output | 1 | 0=input 0, 1=input 1; aligned to every output beat |

A transfer occurs only on a rising edge with VALID and READY high and reset
inactive. A producer must hold VALID and all beat fields until acceptance.
VALID must not depend on READY. Invalid output payload is zero in this design
but consumers must only sample valid transfers. All-zero and sparse KEEP masks
are preserved, not rejected or compacted. The demo convention maps the earliest
byte to TDATA[7:0], qualified by TKEEP[0]. This switch never reorders bytes.

Input interfaces do not accept interleaved packets on an individual input.
No TID, TDEST, TUSER, host address or transaction tags are implemented. The
source bit is not a PCIe requester ID or address. If the system needs descriptors,
agree a separate descriptor channel or extend the FIFOs and contract together.

## Arbitration and buffering

Each input has a FIFO of FIFO_DEPTH beats; output has a two-beat FIFO. Arbitration
occurs at entry to the output FIFO. A selected packet retains ownership through
backpressure and source gaps. Ownership releases when its final beat is accepted
into the output FIFO. FIFO ordering ensures the visible output never interleaves
packets. Initial tie goes to source 0; after each completed packet preference goes
to the other source. An absent preferred input does not block the other input.

Fairness is in packets, not bytes. It assumes finite packets, eventual producer
progress, and eventual sink readiness. A source that never sends LAST can block
the other source indefinitely: no timeout or packet-abort mechanism is included.

FIFO READY depends on stored occupancy, not the same-cycle pop. A full FIFO
therefore takes one recovery cycle before accepting another beat, even if a pop
occurs. DEPTH=1 has reduced throughput. A non-full FIFO supports simultaneous
push/pop. Small async-read memories may map to registers rather than block RAM;
this is a portability-first implementation, not a MAX 10 memory optimization.

## Reset and team responsibilities

Reset aborts every buffered/in-progress packet and resets arbitration. Memory
contents are not cleared, but pointers/valid occupancy are cleared, so old data
cannot reappear as valid. Reset the downstream packetizer/checker at the same
time; otherwise it may retain a partial packet. No clock-domain crossing included.

Your block ends at m_axis_*. Link-layer owner handles framing, CRC/FEC and any
512-to-256 conversion. PHY-facing owner handles digital lane/symbol output. Agree
how packet metadata and return traffic work before adding read/write features.
Do not hard-code a latency between modules; use the handshake.

The implemented `axis_link_tx` wrapper now connects this boundary to
`axis_frame_packetizer`. See `PACKETIZER.md` for its prototype framing and
512-to-256 conversion contract. TX CRC and FEC are implemented (see `CRC.md`
and `FEC.md`); return traffic remains unimplemented. The interconnect interface
above is unchanged.

## Acceptance checklist for teammate integration

1. Connect every field above, especially KEEP, LAST and READY.
2. Use a shared clock/reset initially; no combinational VALID/READY loop.
3. Replace the testbench sink with the link-layer module.
4. Check output under random sink stalls and partial final transfers.
5. Reset all layers together during a packet and verify clean restart.
6. Define frame layout separately; 256-byte FLIT size is not all user payload.
