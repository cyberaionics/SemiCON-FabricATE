# Transmit FEC encoder

`flit_fec6` generates the six ECC bytes after CRC generation. The construction
and ordering follow PCI Express Base Specification 6.2 section 4.2.3.4.4 and
the Appendix J `ecc_250to256_encoder.sv` and `ecc_84to86_encoder.sv` attachments
in the [reference specification](https://icjj.github.io/icer/document/NCB-PCI_Express_Base_6.2-2024-01-25.pdf).
The project RTL was independently implemented as a sequential accumulator;
the reference files are optional verification inputs, not distributed RTL.

## Groups and arithmetic

FEC covers all 250 preceding bytes, including padding, reserved data-link bytes
and the eight generated CRC bytes. Group g takes frame bytes 3*i+g.
Group 0 has 84 bytes. Groups 1 and 2 have 83 bytes and an implicit trailing zero
at group position 83; these two zeros are not transmitted.

Arithmetic uses GF(256), alpha=0x02, primitive polynomial 0x11D
(x^8+x^4+x^3+x^2+1). This is different from the CRC field polynomial 0x12B.
For each group, P is the XOR of its 84 symbols and
C is the XOR of symbol[i]*alpha^(84-i), i=0 through 83.

| Frame byte | Value |
|---|---|
| 250 | Group 1 check C1 |
| 251 | Group 2 check C2 |
| 252 | Group 0 check C0 |
| 253 | Group 1 parity P1 |
| 254 | Group 2 parity P2 |
| 255 | Group 0 parity P0 |

Output `fec[7:0]` is byte 250. The preceding 250 bytes are unchanged. Internal
source/count/packet flags are not included in the transmitted frame or protected.

## Interface and pipeline

The accumulator uses the same clock and active-low asynchronous reset as the
packetizer. `clear` synchronously resets all groups and takes priority over
`enable`. After clear, provide exactly 250 enabled bytes in frame order. Disabled
cycles hold state and group position. Sample the parity after byte 249 is
accepted; intermediate values are not complete frame parity. The caller owns
length enforcement; this module has no standalone ready/valid or done signal.

The packetizer now follows collection -> 242-cycle CRC -> 250-cycle FEC -> eight
256-bit output transfers. It holds CRC during FEC and both results during output
stalls. Reset during any phase discards the pending frame. External port names,
sidebands and frame size are unchanged. Source lists must include `flit_fec6.sv`.

This baseline adds 250 cycles per frame beyond the CRC implementation. It is
not optimized for line rate. Synthesis results are generic structural results,
not timing closure or device-specific area estimates.

## Verification and reproduction

`python sim/run_all.py` runs encoder, CRC and integrated tests. The FEC oracle
uses independent GF polynomial multiplication and direct weighted sums. The
encoder matches 32 data patterns plus all 2,000 single-bit input basis vectors.
Tests also cover disabled cycles, clear priority, output holding and reset from
each of the three group positions followed by a complete new frame.

Every integrated frame is checked against both CRC and FEC oracles, including
partial payloads, empty packets, packet splitting and output stalls. Reset during
FEC calculation is exercised before fresh checked traffic in every configuration.

Optional reference comparison:
`python sim/check_fec_reference.py path/to/reference-files`.
The directory must contain the two Appendix J encoder files and alpha_powers.vh.
For Icarus compatibility, the helper converts only the used constant alpha table
declaration into constant wire assignments. The original encoder equations and
mapping remain intact. All 2,032 vectors also match that reference encoder.

A Python verification-only decoder restored all 2,048 single-bit corruptions
and 254 three-consecutive-byte bursts in a representative full frame. It can
correct one erroneous byte per group, including check/parity bytes. This is not
a production decoder and does not guarantee detection of multiple errors in
one group; CRC verification after FEC correction is still necessary.

Logs: `sim/fec_results.log`, `sim/fec_reference_results.log`,
`sim/fec_correction_results.log`, `sim/link_results.log` and
`synthesis/link_structural_results.log`.

## Remaining work

Receive-side FEC correction and CRC checking are not synthesized RTL yet.
The frame payload still uses the Stage 1 application-data prototype; TLP/DLP
protocol encoding, replay, credits and PHY remain unimplemented. Correct FEC
encoding does not establish compliance of the complete bridge.
