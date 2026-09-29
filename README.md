# FPGA Orderbook

SystemVerilog central-limit order book, simulated with Verilator. A symbol is assigned to one slice. The slice has its own book, its own command port, and its own fill-ready signal. A burst of orders on one symbol does not delay acceptance of an order on another symbol.

Prices on chip sit in a window of 128 ticks (`PRICE_WIN`, base 0), with at most eight live levels on a side. A level holds at most 16 orders, oldest first. If the price is not already resident, that slice waits out a fixed fetch and a writeback before it accepts the order. The order-id map stores `(slice, tile, slot)` in an on-chip hash. An id that misses the hash is looked up in a short list. The matching rule is chosen per slice: price-time, pro-rata, or midpoint.

The front of the chip takes one order word per cycle. The word carries the session, the sequence number, the operation, and the order fields. A sequence gap, a replay, a quantity above the session cap, or a kill bit is rejected before a book sees it. Auctions and orders that name two symbols are handled on the host, then submitted as ordinary limits. Accepted commands are appended to `sliceN.wal`. A command the slice rejects is also appended to `host.wal`.

Widths and opcodes are in [`rtl/pkg/exch_pkg.sv`](rtl/pkg/exch_pkg.sv).

This tree has no vendor memory PHY and no TCP stack. A miss is a latency parameter on the slice. The order-word bench and the slice bench are built as separate simulations. The text gateway uses the Python book by default, and `slice_engine` through `libpe.so` when `--engine rtl` is set.

## Requirements

- GNU make
- Python 3
- A C++17 compiler (`g++` or Apple clang)
- [Verilator](https://www.veripool.org/verilator/) 5. The benches were run on 5.050.

## Build and test

From the repo root:

```sh
make help        # list targets
make test        # Python tests, RTL benches, and the Verilator gateway library
make golden      # Python model and gateway tests
make sim-slice   # slice engine
make sim-book    # one symbol
make sim-frame   # order word, session, cap, and kill
make sim         # the RTL benches
make run         # text interface, Verilator slice engine, logs under data/
make clean       # remove obj_dir/
```

`make sim` also builds the FIFO, the level table, the walker, `sim-bank`, and `sim-part`.

## Text interface

```sh
python3 sw/gateway/main.py --wal data
python3 sw/gateway/main.py --wal data --engine rtl
```

`--engine python` is the default. `--engine rtl` needs `make rtl-gw` first (`make run` and `make test` build that library). Lines are:

```text
LIMIT BUY AAPL 100 10 1
LIMIT SELL AAPL 100 4 2
CANCEL 1
BBO AAPL
BBO
```

`QUIT` ends the session. Prices and quantities are integers. A symbol string is interned to a dense id and assigned to a slice.

## Layout

| Path | What it is |
|---|---|
| `rtl/pkg/exch_pkg.sv` | Widths, window, rule ids |
| `rtl/book/` | Tick array, level FIFO, one-symbol book, walkers, slice engine, tile port, order-id hash and tree |
| `rtl/gateway/` | Order word, session sequence, quantity cap, kill bit |
| `tb/` | Verilator benches |
| `sw/golden/` | Python book, tile, and walkers |
| `sw/gateway/` | Text protocol, logs, auction, two-symbol orders, Verilator shim |
| `design/` | Notes on the matcher. Numbers in the RTL override the notes. |
