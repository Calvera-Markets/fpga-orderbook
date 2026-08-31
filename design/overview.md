# How we start

You can aim at a production-shaped mini-exchange from day one, and you can write Verilog this week. What you should **not** do is put gateway, accounts, persistence, and a multi-symbol book into one first RTL blob. That is how FPGA beginners stall.

The production split is: **FPGA owns the matching hot path. Software owns everything that is sessions, money, and recovery.** We start by writing that hot path in Verilog, simulated as if it were already the chip, with a software shell around it so the system looks like an exchange immediately.

## What “core engine” means here

A CEX/equities matching engine on FPGA is a **deterministic pipeline**, not a CPU program:

1. An order message arrives (add, cancel, match).
2. A few clock cycles later, the chip emits acks, trades, book updates, and market data.
3. Same inputs always produce the same outputs in the same number of cycles.

Software still does:

- TCP/WebSocket sessions, auth, account state
- Pre-trade risk that needs balances / positions
- Write-ahead log, replay, restart
- Market-data fanout to humans and REST

FPGA does:

- Per-symbol price-time book
- Match, cancel, partial fill
- Trade / ack / BBO / depth events
- Optional later: simple in-pipeline checks (price bands, max qty)

That is how real FPGA matching engines are built. Recovery is **replay the log into the chip**, not “the FPGA has a database.”

## How we start despite no Verilog

Jumping into the matching engine is fine if the **first module is a real piece of the engine**, not an LED, and if we **never need a physical FPGA** until simulation is boringly correct.

Do not buy a board yet. Verilator is the chip for the next months.

Three mental models matter more than a Verilog course:

| Idea | Meaning for this project |
|---|---|
| Clock + flip-flops | State (book, FIFOs) updates only on a clock edge |
| Combinational logic | “What is the match *this* cycle?” |
| Valid/ready handshake | Orders flow between pipeline stages without being dropped |

Language: **SystemVerilog**, not Verilog-2001. Packed structs for order messages, enums for opcodes. Verilator handles this. Classic Verilog makes a production-shaped engine miserable.

## First slice

**Product shape (now):** a mini-exchange you can talk to.

- Software gateway: one binary protocol, multiple symbols
- Engine: add limit, cancel, match, emit trades
- Outputs: execution reports + top-of-book

**First Verilog (this week):** not the whole exchange. The matcher’s inner core:

1. **Order instruction word** — packed `opcode, symbol, side, price, qty, order_id`
2. **Price-level FIFO** — orders at one price, time priority (head match, tail add, cancel-by-id)
3. **One-symbol book** — bid/ask ladders + match logic (next)
4. **Symbol mux** — N symbols sharing one pipeline (one order in flight at a time is enough at 300+ MHz)

Steps 2–4 *are* the matching engine. The gateway is software that feeds that pipeline, first through Verilator-as-a-library, later through a real FPGA link.

A full multi-symbol CLOB in one go is how this dies. A price-level FIFO with a software checker beside it is already an engine-shaped system.

## Tooling stance

- Simulate first: Verilator + a C++ testbench + a Python golden model
- Waveforms: GTKWave when a test fails (optional `make waves`)
- Synthesis (Yosys or Vivado) only after the book is correct in sim
- Cheap FPGA board only after synthesis is clean
- Datacenter FPGA (Alveo-class, 100GbE) is a later procurement, not a starting dependency

The golden model is not a delay. It is the **test oracle**. Every Verilog change is: same orders in → bit-identical trades and books out.
