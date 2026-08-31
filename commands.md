# Commands

Project commands first. The session log below is what was actually run while scaffolding this repo.

## Project

From the repo root (`/Users/boavida/Documents/programs/exch-core`):

```sh
make help       # list targets
make golden     # Python golden-model tests (FIFO + book, no Verilator)
make sim-fifo   # price-level FIFO Verilator bench
make sim-book   # one-symbol book Verilator bench
make sim        # both RTL benches
make test       # golden + sim
make clean      # remove obj_dir/
```

Direct equivalents:

```sh
cd sw/golden && python3 -m unittest discover -v

# FIFO (build output is now obj_dir/price_level_fifo/)
verilator --cc --exe --build -sv -Wall \
  --top-module price_level_fifo \
  -Mdir obj_dir/price_level_fifo \
  -o price_level_fifo_sim \
  -CFLAGS "-std=c++17 -Wall" \
  rtl/pkg/exch_pkg.sv \
  rtl/book/price_level_fifo.sv \
  tb/price_level_fifo_tb.cpp
./obj_dir/price_level_fifo/price_level_fifo_sim

# Book
verilator --cc --exe --build -sv -Wall \
  --top-module one_symbol_book \
  -Mdir obj_dir/book \
  -o one_symbol_book_sim \
  -CFLAGS "-std=c++17 -Wall" \
  rtl/pkg/exch_pkg.sv \
  rtl/book/price_level_fifo.sv \
  rtl/book/one_symbol_book.sv \
  tb/one_symbol_book_tb.cpp
./obj_dir/book/one_symbol_book_sim
```

## Tooling (macOS)

Installed 2026-08-31:

```sh
brew install verilator
verilator --version    # Verilator 5.050 2026-07-01
python3 --version      # Python 3.12.3
g++ --version          # Apple clang 15.0.0
```

`verilator` lands at `/opt/homebrew/bin/verilator`. No FPGA board, Icarus, or GTKWave required for `make test`.

## Session log — 2026-08-31 scaffold

Check what was already on the machine:

```sh
which verilator; verilator --version 2>/dev/null
which python3; python3 --version
which g++; g++ --version | head -1
which make
which brew
```

Verilator was missing. Install:

```sh
brew install verilator
```

Golden model (must run from `sw/golden`, which is what `make golden` does). Running `python3 -m unittest test_price_level -v` from the repo root fails with `No module named 'test_price_level'`.

```sh
cd /Users/boavida/Documents/programs/exch-core/sw/golden
python3 -m unittest test_price_level -v
```

First Verilator build (`make sim`) exited on `-Wall` width warnings: `count` is 5 bits (`$clog2(17)`) but `slots[15:0]` wants a 4-bit index. Fixed in RTL with `IDX_W = $clog2(MAX_ORDERS)` and an `OP_NOP` case so the unused-param warning goes away. Rebuild:

```sh
cd /Users/boavida/Documents/programs/exch-core
make sim
make test
```

Last successful `make test` after FIFO scaffold: 11 Python tests OK, `PASSED 192 checks` from `obj_dir/price_level_fifo_sim`.

## Session log — 2026-08-31 one-symbol book

`design/` was ignored by a `design/*` line in `.gitignore`; removed so the design docs can be committed.

```sh
cd /Users/boavida/Documents/programs/exch-core
make golden
make sim-book
make test
```

`make sim-book` first failed: `BOOK_LIMIT` unused (`-Wall`). Used it in the LIMIT decode. Then `make test` failed on the FIFO top: shared package params unused in that module. Wrapped `exch_pkg` in `verilator lint_off UNUSEDPARAM`.

Remote:

```sh
kaizu git remote add origin git@github.com:Calvera-Markets/exchange-core.git
kaizu git remote -v
```

Last successful `make test`: 21 Python tests OK, FIFO `PASSED 192 checks`, book `PASSED 125 checks`.
