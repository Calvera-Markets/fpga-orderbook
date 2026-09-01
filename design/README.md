# exch-core design

This folder is the design record for an FPGA matching hot path with a software shell around it: a production-shaped mini-exchange whose first Verilog is a real piece of the matcher, not a tutorial blinky.

| Doc | What it covers |
|---|---|
| [overview.md](overview.md) | Why this split, how a Verilog beginner starts, week-by-week path |
| [architecture.md](architecture.md) | FPGA vs software, pipeline, repo layout, recovery |
| [decisions.md](decisions.md) | Frozen choices (matching rules, memory, persistence) |
| [messages.md](messages.md) | Order instruction word and engine events |
| [price-level-fifo.md](price-level-fifo.md) | First RTL module: interface, semantics, timing, tests |
| [one-symbol-book.md](one-symbol-book.md) | One-instrument price-time book on top of the FIFO |
| [gateway.md](gateway.md) | Software mini-exchange: text protocol, WAL, replay |
| [industry-analysis.md](industry-analysis.md) | How production matchers and FPGA books are built; what we copy |
| [multi-pipeline.md](multi-pipeline.md) | Multiple pipelines vs multiple books: five patterns, hazards, what we should build |
| [pattern-4.md](pattern-4.md) | Partitioned pipelines: hash, banks, seq, handshake |
| [pattern-4-checkpoints.md](pattern-4-checkpoints.md) | Pattern 4 broken into a stream of commits |
| [roadmap.md](roadmap.md) | What is built now vs next |

Build and simulation commands live in [`../commands.md`](../commands.md).
