VERILATOR ?= verilator
COMMON_RTL := rtl/pkg/exch_pkg.sv rtl/book/price_level_fifo.sv

FIFO_TOP := price_level_fifo
BOOK_TOP := one_symbol_book
BANK_TOP := symbol_bank
PART_TOP := partitioned_engine
FIFO_DIR := obj_dir/price_level_fifo
BOOK_DIR := obj_dir/book
BANK_DIR := obj_dir/bank
PART_DIR := obj_dir/part
FIFO_BIN := $(FIFO_DIR)/$(FIFO_TOP)_sim
BOOK_BIN := $(BOOK_DIR)/$(BOOK_TOP)_sim
BANK_BIN := $(BANK_DIR)/$(BANK_TOP)_sim
PART_BIN := $(PART_DIR)/$(PART_TOP)_sim
BOOK_RTL := $(COMMON_RTL) rtl/book/one_symbol_book.sv

VFLAGS := --cc --exe --build -sv -Wall -CFLAGS "-std=c++17 -Wall"

.PHONY: all help golden sim sim-fifo sim-book sim-bank sim-part test clean run

all: test

help:
	@echo "make golden    Python golden-model and gateway tests"
	@echo "make sim-fifo  price-level FIFO Verilator bench"
	@echo "make sim-book  one-symbol book Verilator bench"
	@echo "make sim-bank  multi-symbol bank (one pipe)"
	@echo "make sim-part  partitioned engine (K pipes)"
	@echo "make sim       all RTL benches"
	@echo "make test      golden + all RTL sims"
	@echo "make run       interactive mini-exchange (stdin, WAL at data/exch.wal)"
	@echo "make clean     remove obj_dir"

golden:
	cd sw/golden && python3 -m unittest discover -v
	cd sw/gateway && python3 -m unittest discover -v

$(FIFO_BIN): $(COMMON_RTL) tb/price_level_fifo_tb.cpp
	$(VERILATOR) $(VFLAGS) --top-module $(FIFO_TOP) -Mdir $(FIFO_DIR) -o $(FIFO_TOP)_sim \
		$(COMMON_RTL) tb/price_level_fifo_tb.cpp

$(BOOK_BIN): $(BOOK_RTL) tb/one_symbol_book_tb.cpp
	$(VERILATOR) $(VFLAGS) --top-module $(BOOK_TOP) -Mdir $(BOOK_DIR) -o $(BOOK_TOP)_sim \
		$(BOOK_RTL) tb/one_symbol_book_tb.cpp

$(BANK_BIN): $(BOOK_RTL) rtl/book/symbol_bank.sv tb/symbol_bank_tb.cpp
	$(VERILATOR) $(VFLAGS) --top-module $(BANK_TOP) -Mdir $(BANK_DIR) -o $(BANK_TOP)_sim \
		$(BOOK_RTL) rtl/book/symbol_bank.sv tb/symbol_bank_tb.cpp

$(PART_BIN): $(BOOK_RTL) rtl/book/symbol_bank.sv rtl/book/oid_map.sv rtl/book/partitioned_engine.sv tb/partitioned_engine_tb.cpp
	$(VERILATOR) $(VFLAGS) --top-module $(PART_TOP) -Mdir $(PART_DIR) -o $(PART_TOP)_sim \
		$(BOOK_RTL) rtl/book/symbol_bank.sv rtl/book/oid_map.sv rtl/book/partitioned_engine.sv tb/partitioned_engine_tb.cpp

sim-fifo: $(FIFO_BIN)
	$(FIFO_BIN)

sim-book: $(BOOK_BIN)
	$(BOOK_BIN)

sim-bank: $(BANK_BIN)
	$(BANK_BIN)

sim-part: $(PART_BIN)
	$(PART_BIN)

sim: sim-fifo sim-book sim-bank sim-part

test: golden sim

run:
	python3 sw/gateway/main.py --wal data/exch.wal

clean:
	rm -rf obj_dir
