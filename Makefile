VERILATOR ?= verilator
COMMON_RTL := rtl/pkg/exch_pkg.sv rtl/book/price_level_fifo.sv

FIFO_TOP := price_level_fifo
BOOK_TOP := one_symbol_book
FIFO_DIR := obj_dir/price_level_fifo
BOOK_DIR := obj_dir/book
FIFO_BIN := $(FIFO_DIR)/$(FIFO_TOP)_sim
BOOK_BIN := $(BOOK_DIR)/$(BOOK_TOP)_sim

VFLAGS := --cc --exe --build -sv -Wall -CFLAGS "-std=c++17 -Wall"

.PHONY: all help golden sim sim-fifo sim-book test clean

all: test

help:
	@echo "make golden    Python golden-model tests"
	@echo "make sim-fifo  price-level FIFO Verilator bench"
	@echo "make sim-book  one-symbol book Verilator bench"
	@echo "make sim       both RTL benches"
	@echo "make test      golden + sim"
	@echo "make clean     remove obj_dir"

golden:
	cd sw/golden && python3 -m unittest discover -v

$(FIFO_BIN): $(COMMON_RTL) tb/price_level_fifo_tb.cpp
	$(VERILATOR) $(VFLAGS) --top-module $(FIFO_TOP) -Mdir $(FIFO_DIR) -o $(FIFO_TOP)_sim \
		$(COMMON_RTL) tb/price_level_fifo_tb.cpp

$(BOOK_BIN): $(COMMON_RTL) rtl/book/one_symbol_book.sv tb/one_symbol_book_tb.cpp
	$(VERILATOR) $(VFLAGS) --top-module $(BOOK_TOP) -Mdir $(BOOK_DIR) -o $(BOOK_TOP)_sim \
		$(COMMON_RTL) rtl/book/one_symbol_book.sv tb/one_symbol_book_tb.cpp

sim-fifo: $(FIFO_BIN)
	$(FIFO_BIN)

sim-book: $(BOOK_BIN)
	$(BOOK_BIN)

sim: sim-fifo sim-book

test: golden sim

clean:
	rm -rf obj_dir
