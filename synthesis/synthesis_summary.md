# Protocol-to-PHY Synthesis Summary

## Tool
- Tool: Yosys
- Version: 0.52

## Target
- Top module: protocol_to_phy_top
- Script: synthesis/run_yosys.ys
- Log: synthesis/phy_structural_results.log

## Generic Synthesis Statistics
- Total cells in final hierarchy: 7799
- Wire bits: 49465
- Memories: 0
- Memory bits: 0
- Warnings: 2 unique messages, 2 total

## Cell Breakdown
| Cell type | Count |
|---|---:|
| AND | 285 |
| DFFE_PN0P | 633 |
| DFFE_PN1P | 96 |
| DFF_PN0 | 7 |
| MUX | 812 |
| NOT | 1338 |
| OR | 1516 |
| XOR | 3112 |

## Limitations
These are generic Yosys synthesis statistics. They do not represent
technology-mapped standard cells or physical silicon area. Area and
timing must be evaluated using a specified target library, constraints,
and an appropriate implementation flow.

## Status
Synthesis completed and the log reports two warnings.
The warnings must be reviewed before the result is treated as finalized.

## Warning Analysis

Yosys 0.52 reports two warnings in `rtl/lane_scrambler.sv`:
- `lfsr_q` is replaced with a list of registers.
- `lfsr_d` is replaced with a list of registers.

These warnings indicate that Yosys is representing the array-like
objects as registers. The warnings do not, by themselves, establish
a functional or synthesis problem. The RTL and resulting behavior
must be reviewed before deciding whether changes are necessary.
