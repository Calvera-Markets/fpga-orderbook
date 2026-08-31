# Frozen decisions

These keep the first RTL from becoming a science project. Change them in this file before changing code.

| Decision | Choice | Rationale |
|---|---|---|
| Language | SystemVerilog | Packed structs and enums; Verilator support |
| Simulator | Verilator + C++ TB | Same RTL later synthesizes; fast compile |
| Golden model | Python, same semantics | Oracle for the C++ tests and later gateway |
| Matching rule | Price-time, GTC limits | Industry default CLOB; smallest real engine |
| First opcodes | ADD, MATCH, CANCEL | Enough for a resting book and an aggressor |
| First module | Price-level FIFO | Time priority is the inner loop of the book |
| MATCH scope | Head order only | Book FSM will walk the level; keeps this module 1-cycle |
| Prices / qty | Integers (ticks and lots) | No floating point in the chip |
| `order_id` | 64-bit, unique by software invariant | RTL cancels the oldest slot if duplicates exist |
| Book bound | 16 orders per price level (v1) | Fits combinational compact; BRAM later |
| Multi-symbol | One shared pipeline, later | Parallel books do not scale |
| Persistence | Software WAL + replay | Chip SRAM is volatile |
| Reset | Synchronous, active-low `rst_n` | FPGA-friendly |
| Handshake (FIFO) | `cmd_ready` high whenever not in reset | II=1 for the inner queue |
| Handshake (book) | `cmd_ready` only in IDLE | Matching walks heads over many cycles |
| Levels per side | 8 | Combinational best-price scan; raise later |
| Physical FPGA | Not yet | Simulation until the book is correct |

Explicitly **out of v1**: market-by-order feed, self-trade prevention, hidden qty, stop/peg/iceberg, auctions, fractional prices, per-symbol parallel matchers, DRAM, board bring-up.
