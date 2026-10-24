# Max-capacitance violations in the routed result

Applies to the routed run documented in `physical_design/` (RTL as hashed in
`docs/routed_run_rtl_sha256.txt`, i.e. **before** the in-flight-recovery fix).
Final report: 9 max-capacitance violations, 0 slew, 0 fanout, 0 DRC, WNS/TNS 0.

## Measured (OpenROAD, final database, RCX extraction loaded into STA)
`physical_design/diagnostics/cap_diag2.log` reproduces the signoff report's
nine violators and values exactly (e.g. `_102905_/ZN` 34.69 fF vs 25.33 limit).

| driver | cell | limit fF | actual fF | pin fF | wire fF | loads | Manhattan distance to load |
|---|---|---:|---:|---:|---:|---:|---:|
| _102905_ | AOI21_X1 | 25.33 | 34.69 | 2.57 | 32.12 | 1 | 205 um |
| _103744_ | AOI21_X1 | 25.33 | 31.81 | 2.57 | 29.24 | 1 | 211 um |
| _058464_ | AOI21_X1 | 25.33 | 28.33 | 2.57 | 25.76 | 1 | 181 um |
| _073935_ | NOR4_X1  | 10.47 | 12.97 | 1.57 | 11.40 | 1 |  81 um |
| _076614_ | NOR3_X1  | 16.02 | 18.37 | 1.66 | 16.71 | 1 | 116 um |
| _103347_ | AOI21_X1 | 25.33 | 27.42 | 2.57 | 24.84 | 1 | 208 um |
| _066801_ | NOR2_X1  | 26.70 | 28.63 | 14.38 | 14.25 | 9 | (cluster) |
| _104203_ | AOI21_X1 | 25.33 | 26.62 | 2.57 | 24.05 | 1 | 186 um |
| _103363_ | AOI21_X1 | 25.33 | 26.35 | 2.57 | 23.78 | 1 | 215 um |

Pin capacitance is the upper end of the reported range.

## What this establishes
- Eight of nine are single-load nets; the load is almost entirely routed wire,
  not fanout. All nine drivers are minimum-size (_X1) cells.
- Six of nine are the same structure: an AOI21_X1 driving the B pin of an
  XNOR2_X1 with consecutive instance numbers, placed 180-215 um apart in a core
  about 490 um wide. (Not traced back to RTL; a parity/XOR tree in the CRC/FEC
  logic is a guess.)

## Estimate vs extraction (5 of the 9 nets were captured)
Placement-based estimate (`estimate_parasitics -placement`, metal3,
0.104 fF/um) vs final RCX extraction:

| net | limit | estimate total | extracted total | legal under estimate | extracted / estimate |
|---|---:|---:|---:|---|---:|
| _026564_ | 16.02 | 13.80 | 18.37 | yes | 1.33 |
| _046610_ | 25.33 | 24.24 | 27.42 | yes | 1.13 |
| _018536_ | 26.70 | 26.61 | 28.63 | yes | 1.08 |
| _047342_ | 25.33 | 21.99 | 26.62 | yes | 1.21 |
| _046624_ | 25.33 | 24.89 | 26.35 | yes | 1.06 |

All five are within the limit under the estimate and over it after extraction.
Extracted wire capacitance runs 7-38% above the straight-line estimate on these
nets (cause not isolated: coupling and routing detours are candidates).

## Not established
- Why the global-route-stage `repair_design` (which logged "Found 9
  capacitance violations", 8 buffers inserted, 0 cells resized) did not clear
  them. The estimate that stage used was not examined, and the log does not
  list net names, so it is not known whether those nine are these nine.
- The estimate-vs-extraction comparison for the other four nets was not
  captured (a straight-line prediction suggests the same pattern, ratios
  1.30-1.45, but that is a prediction).

## Candidate fix (NOT applied in the submitted result)
- The ORFS in use maps the environment variable `CAP_MARGIN` to
  `repair_design -cap_margin` (integer percent, 0-100, default 0). A margin of
  `1 - 1/r` is needed if extraction runs `r` times the estimate; r = 1.33
  (observed worst) to 1.45 (predicted worst) gives about 25-31%, so 30 would be
  a first trial. Untested.
- Alternatively each violator would fit under the next drive strength
  (X2 limits are 2x: AOI21_X2 50.66, NOR4_X2 20.90, NOR3_X2 31.74,
  NOR2_X2 53.41 fF). Arithmetic only; not run.
