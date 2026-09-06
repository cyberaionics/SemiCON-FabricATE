# Stage 1 transmit framing prototype

## Scope

`axis_frame_packetizer` collects application bytes from a 512-bit AXI4-Stream
port and emits fixed 256-byte prototype frames on a 256-bit ready/valid port.
`axis_link_tx` connects the existing two-input interconnect to this module.
All modules share the clock and active-low reset. The integrated wrapper supports
positive FIFO_DEPTH values; its stream widths are fixed at 512 and 256 bits.

This is not a PCIe-compliant transmitter. In particular, input data is not encoded
as Transaction Layer Packets (TLPs); there are no addresses, TLP headers, DLP
semantics or sequence/replay/credit management. CRC and FEC generation are
implemented; see `CRC.md` and `FEC.md` for their algorithms and verification.
The reserved region follows the byte budget described by
[Synopsys](https://www.synopsys.com/blogs/chip-design/pcie-6-verifaction-fec-crc.html).
Actual PCIe packing and encoding need a separate protocol implementation.

## Prototype frame contract

| Byte offsets | Size | Current meaning |
|---|---|---|
| 0 through 235 | 236 bytes | Compacted application data followed by zero padding |
| 236 through 241 | 6 bytes | Reserved data-link region, zero |
| 242 through 249 | 8 bytes | Computed CRC0 through CRC7 (see CRC.md) |
| 250 through 255 | 6 bytes | Computed C1, C2, C0, P1, P2, P0 (see FEC.md) |

Frame byte 0 appears at output TDATA[7:0] on the first accepted transfer.
Each frame has exactly eight 32-byte output transfers. Output TKEEP is all ones:
padding and reserved bytes are part of the transmitted frame. Output TLAST marks
transfer eight, independently of application packet termination.

Only input bytes with TKEEP=1 are collected, in increasing lane order. Invalid
bytes are discarded here, unlike the upstream switch which preserves whole beats.
All-zero non-final input beats contribute no bytes. An empty packet, terminated
by TLAST, produces one all-zero frame with byte count zero and both packet flags.

Application packets do not share frames. A packet longer than 236 valid bytes
is split across frames. Exact multiples of 236 do not produce an extra empty
frame, including when TLAST arrives on a subsequent all-zero beat. A full frame
waits for another valid byte or TLAST before emission; there is no timeout.

## Sideband metadata

The following fields describe the whole frame and are repeated unchanged on all
eight transfers, including during stalls:

| Signal | Width | Meaning |
|---|---|---|
| m_axis_source | 1 | Original source 0 or 1 |
| m_frame_bytes | 8 | Valid application bytes in this frame, from 0 to 236 |
| m_packet_start | 1 | First frame of an application packet |
| m_packet_end | 1 | Final frame of an application packet |

These are internal prototype sidebands, not PCIe wire fields. A downstream
checker must retain them to reconstruct packets and distinguish padding. Values
are meaningful only while output VALID is asserted. The standalone input source
must remain constant throughout a packet; the integrated interconnect guarantees
this. Source is captured at the first input handshake, including an empty beat.

## Handshake, buffering and reset

VALID/READY handshakes occur on rising clock edges while reset is inactive.
The source must hold data, KEEP, LAST and source until accepted. The output holds
data and all metadata stable while stalled. READY does not depend combinationally
on downstream READY.

The implementation stores one 64-byte input beat and one 236-byte payload frame.
It scans one input lane per cycle, including invalid lanes, and pauses collection
while emitting a frame. Without a frame emission, consecutive input handshakes
are 66 cycles apart. Each frame adds 242 CRC cycles, 250 FEC cycles and at least
eight emission cycles; output stalls
extend this. This is a functional baseline, not a throughput-optimized design.
Dynamic payload indexing and register buffering can be expensive in synthesis.

Reset asynchronously clears pending data and output validity. Release reset
synchronously to the shared clock. Reset all connected stages and the downstream
receiver together: a partly transmitted frame is aborted, not completed. A source
that does not finish its packet can block progress; no abort/timeout is implemented.

## Verification and reproduction

Run all original and new tests with `python sim/run_all.py` using Icarus Verilog
and vvp on PATH. The runner also recognizes the optional ignored project-local
`.tools/mingw64/bin` installation. No Python packages are needed for simulation.
Alternatively, run `bash sim/run_link.sh` for only the new tests.

The new tests exercise standalone framing and integrated FIFO depths 1, 3 and 4
using three seeds. The independent oracle compares complete application packet
contents against every output byte, padding, reserved region and metadata field.
It checks packet/frame boundaries, cross-frame source ownership, all output stall
positions, partial/sparse/all-zero KEEP and clean traffic after resets during
collection, a stalled frame and partial transmission. Packet lengths include
0, 1, 31, 32, 33, 63, 64, 65, 235, 236, 237, 472, 473 and 2048 bytes.

`yosys -l synthesis/link_structural_results.log synthesis/check_link.ys` performs
generic synthesis and structural checks. This does not establish timing closure,
technology area, physical implementation, FPGA fit or PCIe compliance.

## Next integration milestones

1. Define real transaction encoding and receiver metadata requirements.
2. Implement and verify receive FEC correction and CRC checking (TX encoding is complete).
3. Add the PS's lane striping and digital symbol mapping.
4. Measure throughput/area and optimize buffering and byte collection as needed.
