---
trigger: always_on
---

Rule 1: Spatial over Temporal (Unroll and Parallelize): Avoid nested for loops for sequential processing if the computation can be parallelized. Always prioritize data flattening and parallel execution across multiple Processing Elements (PEs). Do not introduce meaningless wait states or force the hardware to sit idle.

Rule 2: Memory Port Awareness (Respect Physical Limits): Never design a circuit that requires reading multiple random addresses from a single SRAM block in the same clock cycle. BRAMs and LUTRAMs typically have a maximum of 1 or 2 ports. If parallel data access is required, utilize Shift Registers, Window Arrays, or memory banking.

Rule 3: Dataflow is King (Pipeline Continuity): Treat data like a continuous flow of water through pipes. The Finite State Machine (FSM) should merely act as valves (Enables, Mux selects). Minimize pipeline stalls, flushes, or bubbles unless absolutely necessary. Keep the data moving.

Rule 4: Keep Combinational Logic Simple: NEVER use division (/), modulo (%) with non-powers of 2, or variable-by-variable multiplication (var * var) for address calculations in combinational blocks. These create massive critical paths. Instead, use simple Counters and Accumulators within sequential (always_ff) blocks.

Rule 5: Routing (MUX) over Memory Duplication: Do not fear Multiplexers. In FPGA architecture, routing and MUXes consume very few resources (LUTs) compared to duplicating registers. Route data using Crossbars/MUXes instead of forcing the memory to store redundant copies or creating massive snapshot registers.