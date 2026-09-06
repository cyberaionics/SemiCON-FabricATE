# Eight-byte frame CRC

## Algorithm

`flit_crc8` implements the Reed-Solomon CRC construction in PCI Express Base
Specification 6.2, section 4.2.3.4.3, Figure 4-35 and Appendix K.
The [PCI-SIG overview](https://pcisig.com/blog/evolution-pci-express-specification-its-sixth-generation-third-decade-and-still-going-strong)
describes the construction and protected region. Detailed ordering and the
generator matrix were checked against pages 430-431 and the Appendix K attachment
of this [publicly hosted specification](https://icjj.github.io/icer/document/NCB-PCI_Express_Base_6.2-2024-01-25.pdf).

Arithmetic uses GF(256), primitive polynomial x^8+x^5+x^3+x+1 (0x12B), alpha=0x02.
The generator is the product of (x+alpha^i), i=1 through 8. Coefficients from
x^8 through the constant are `01 D5 68 FE D5 33 41 4D 69`.
This is not CRC-64/ECMA or two CRC-32 values.

Input bytes d0 through d241 form d0*x^241 + ... + d241. Divide this polynomial
times x^8 by the generator to obtain r7*x^7 + ... + r0. Initial state is zero;
there is no reflection or final complement. `crc[7:0]` is r0 (CRC0) and
`crc[63:56]` is r7 (CRC7).

| Frame bytes | Contents and CRC treatment |
|---|---|
| 0-235 | Application data and padding, all protected |
| 236-241 | Reserved data-link bytes, currently zero, protected |
| 242-249 | Computed CRC0 through CRC7 |
| 250-255 | Computed FEC bytes, excluded from CRC (see FEC.md) |

Internal source, byte count and packet flags are not encoded in the frame
and are not CRC-protected. Future data-link fields must be set before CRC
generation. FEC is computed after CRC insertion.

## RTL contract

`flit_crc8` consumes one byte on each rising edge with `enable` high. Active-low
asynchronous reset clears it. Synchronous `clear` takes priority over enable;
otherwise disabled cycles hold the state. The module has no implicit byte counter
or finalization; its caller manages the frame boundary.

The packetizer performs a 242-cycle CRC pass after collecting each frame and
before the 250-cycle FEC pass and output VALID. The final CRC update completes
before FEC starts.
All frame bytes and metadata, including CRC, remain stable under backpressure.
Shared reset aborts the frame and CRC calculation together. External interfaces
are unchanged. Each frame now adds 242 cycles to the prior framing-only latency.
Add `rtl/flit_crc8.sv` to custom source lists; supplied scripts already include it.

## Verification

Run `python sim/run_all.py`. Python polynomial long division generates 32 known
answers from zero, all-ones, ramp, endpoint impulses and deterministic random
messages, including nonzero data-link bytes. The reference derives the generator
from its roots instead of copying RTL coefficients or its feedback recurrence.
The unit bench checks these vectors, enable gaps, clear priority and reset.

A separate testbench checker uses log/antilog arithmetic to evaluate syndromes
at all eight roots. It rejects all 2,000 individual protected/parity bit flips in
a representative codeword and 128 patterns affecting one through eight distinct
bytes. The integrated bench applies this checker to every frame alongside its
independent payload/metadata oracle, and resets the design during CRC generation.
This checker is verification code, not a synthesized receive-path implementation.

The Python reference also matched all 1,936 single-bit basis inputs in the
specification's generator matrix. This validates the reference, not formal RTL
equivalence over every possible input. With the matrix available, reproduce using
`python sim/crc_vectors.py --matrix path/to/gen_matrix.txt`.
Its hash and results are in `sim/crc_matrix_results.log`. The reference PDF and
matrix are not distributed with the project or needed for ordinary regressions.

## Remaining scope

The payload remains the Stage 1 application-data prototype. Real TLP/DLP encoding,
receive-path CRC checking, FEC correction, replay, credits and PHY remain unimplemented.
Correct CRC arithmetic does not establish PCIe compliance of the complete bridge.
