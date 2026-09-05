# Three-day integration plan

Day 1: run these tests, review interfaces together, connect all module shells
in one shared top level. Keep clock, reset and packet conventions identical.

Day 2: replace shells with real modules. First get one packet through, then two
contending streams. Keep this subsystem's regression passing. Add an independent
checker for the link/PHY digital output format, including byte order and overhead.

Day 3: run integrated stalls/reset/partial packet tests. Freeze RTL, collect
waveforms and logs, record exact implemented scope and known limitations. Attempt
Quartus only if mandatory submission evidence is already ready. FPGA demo is
optional under the PS; organizer acceptance of Quartus remains to be confirmed.

Do not add memory-mapped AXI4 casually: it needs independent address/data handling,
bursts, response routing and transaction semantics. Keep it outside this starter.
