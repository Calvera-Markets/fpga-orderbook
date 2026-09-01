# Roadmap

## Now

- Design docs in this folder
- Price-level FIFO (`rtl/book/price_level_fifo.sv`)
- One-symbol book (`rtl/book/one_symbol_book.sv`) — GTC limit + cancel, fills, BBO
- Python golden models (`sw/golden/`)
- Software mini-exchange (`sw/gateway/`) — text protocol, WAL, replay
- Pattern 4: `pipe = symbol_id % 2`, Python partitions + RTL `partitioned_engine`
- `make test` runs golden, gateway, fifo, book, bank, partitioned engine

## Next

**Ticker strings** at the gateway only (`BTC` → id). **Market-data view** of the same fills/BBO. Raise `K` / books-per-pipe when measured.

**Egress / market data.** Same match events, two views: execution reports to the gateway, BBO + last trade to a feed.

## Later

- Synthesis (Yosys or vendor tools) and timing closure
- Cheap board only to prove clocks and a UART/PCIe pipe
- Valid/ready stalls for multi-cycle walks
- BRAM linked-list levels when 16 orders is too small
- Light in-pipeline risk (price band, max qty)
- Datacenter FPGA + 100GbE when the datapath is real
