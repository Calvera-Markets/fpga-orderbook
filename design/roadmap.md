# Roadmap

## Now

- Design docs in this folder
- Price-level FIFO (`rtl/book/price_level_fifo.sv`)
- One-symbol book (`rtl/book/one_symbol_book.sv`) — GTC limit + cancel, fills, BBO
- Python golden models (`sw/golden/`)
- `make test` runs FIFO + book (Python and Verilator)

## Next

**Software mini-exchange.** A process that accepts a simple text or binary protocol, feeds the Verilator-compiled engine (or the Python golden), WAL-logs instructions and events, replays on restart.

**Multi-symbol.** `symbol_id` → book memory. Still one command in the pipeline at a time.

**Egress / market data.** Same match events, two views: execution reports to the gateway, BBO + last trade to a feed.

## Later

- Synthesis (Yosys or vendor tools) and timing closure
- Cheap board only to prove clocks and a UART/PCIe pipe
- Valid/ready stalls for multi-cycle walks
- BRAM linked-list levels when 16 orders is too small
- Light in-pipeline risk (price band, max qty)
- Datacenter FPGA + 100GbE when the datapath is real
