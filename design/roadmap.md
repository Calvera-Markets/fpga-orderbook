# Roadmap

## Now

- Design docs in this folder
- Price-level FIFO (`rtl/book/price_level_fifo.sv`)
- One-symbol book (`rtl/book/one_symbol_book.sv`) — GTC limit + cancel, fills, BBO
- Python golden models (`sw/golden/`)
- Software mini-exchange (`sw/gateway/`) — text protocol, WAL, replay
- Pattern 4: `pipe = symbol_id % 4`, Python partitions + RTL `partitioned_engine` (`N_SYMS_PER_PIPE = 8`)
- `make test` runs golden, gateway, fifo, book, bank, partitioned engine

## Next

Verilator as a library behind the gateway. WAL file per pipe.

## Later

- Synthesis (Yosys or vendor tools) and timing closure
- Cheap board only to prove clocks and a UART/PCIe pipe
- Valid/ready stalls for multi-cycle walks
- BRAM linked-list levels when 16 orders is too small
- Light in-pipeline risk (price band, max qty)
- Datacenter FPGA + 100GbE when the datapath is real
