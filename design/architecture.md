# Architecture

## System split

```
Clients
   |
   |  TCP / WebSocket (later)
   v
Software gateway          sessions, auth, accounts, pre-trade risk
   |                      WAL: every inbound instruction + every engine event
   |  order instructions
   v
Matching hot path         this is the FPGA / Verilog
   ingest -> symbol lookup -> price-time book -> matcher -> egress
   |
   |  fills, acks, cancels, BBO / last trade
   v
Software                  persist, market-data fanout, ops, recovery replay
```

Today the “FPGA” is Verilator compiling the same SystemVerilog that will later be synthesized. The gateway can treat `obj_dir` as a library. No protocol change is required when a real chip shows up; only the transport behind the instruction word changes.

## Matching pipeline (target)

One order in flight through a shared pipeline. Many symbols. That is enough: a few cycles at a few hundred MHz is tens of millions of orders per second, which is far above a first software matcher.

```
cmd_valid/ready          book memories (BRAM-shaped even in sim)
       |                        ^
       v                        |
   ingest decode ---- symbol id + side + price ----+
       |                                           |
       v                                           v
   opcode switch                          price-level FIFO
     ADD resting -------------------------+    (this repo, now)
     CANCEL by id ------------------------+
     aggressive MATCH --------------------+--> fills to egress
       |                                           |
       v                                           v
   BBO / depth / last trade  <----- totals, head, empty
```

The first implemented block is the **price-level FIFO**: the time-priority queue at a single price on a single side of a single symbol. The one-symbol book is a sorted set of those levels plus a small FSM that walks them. Multi-symbol is a lookup from `symbol_id` onto book RAM, still one command per cycle.

## What stays out of the chip

| Concern | Where it lives | Why |
|---|---|---|
| Sessions, reconnect, auth | Software | State is per client, not per tick |
| Cash / position risk | Software (optional light checks later in RTL) | Needs account ledgers |
| Persistence | Software WAL | On-chip SRAM is lost on power-down |
| Recovery | Replay WAL into the engine | Chip is rebuilt, not checkpointed |
| Human market data / REST | Software | Fanout and encoding are not the match path |
| Auctions, stops, icebergs, pegs | Later, if ever | First matcher is GTC limit + cancel + incoming match |

## Repo layout

```
exch-core/
  design/           this folder
  commands.md       commands used to build and test
  rtl/pkg/          SystemVerilog types and opcodes
  rtl/book/         price-level FIFO + one-symbol book
  tb/               Verilator C++ testbenches
  sw/golden/        Python reference with the same semantics
  obj_dir/          Verilator build output (generated, gitignored)
```

Later, without changing this split:

- `rtl/ingest/`, `rtl/egress/`
- `sw/gateway/` — sessions and WAL
- `proto/` — frozen binary layouts shared by software and RTL

## Memory model

FPGA books are **bounded on-chip memory**, not `std::map`.

- Each price level holds a fixed maximum number of resting orders (16 in the first module; raise when the book exists).
- The future one-symbol book will cap price levels (e.g. 128–1024).
- No DRAM on the match path. DRAM is for later market-data history in software, not for matching.

That bound is a product limit: reject ADD when a level is full. Software can treat that as a system-busy NAK.

## Latency model (v1)

The price-level FIFO accepts one command per clock and returns a registered response on the **same posedge** that updates state (issue on this edge, observe response and new probes after the edge). That is easy to test and still “clocked RTL,” not a behavioral model.

A later pipeline will add explicit stages (lookup, match, writeback) and a true valid/ready stall when a command takes multiple cycles (e.g. walking several price levels). The instruction word does not change when that happens.

## Recovery

1. Software writes every accepted inbound instruction to a WAL **before** (or atomically with) presenting it to the engine.
2. Software appends every engine event (ack, fill, cancel, reject).
3. On restart, software brings up a blank engine and replays instructions.

The chip has no disk and no “load snapshot” in v1. If we later add snapshot/restore, it is an optimization on top of replay, not a replacement.
