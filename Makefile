VERILATOR ?= verilator
TOP       := price_level_fifo
VDIR      := obj_dir
BIN       := $(VDIR)/$(TOP)_sim
RTL       := rtl/pkg/exch_pkg.sv rtl/book/price_level_fifo.sv
TB        := tb/price_level_fifo_tb.cpp

VERILATOR_FLAGS := --cc --exe --build -sv -Wall \
	--top-module $(TOP) \
	-Mdir $(VDIR) \
	-o $(TOP)_sim \
	-CFLAGS "-std=c++17 -Wall"

.PHONY: all help sim golden test clean

all: test

help:
	@echo "make golden  - Python golden-model unit tests (no Verilator)"
	@echo "make sim     - Build and run the price-level FIFO Verilator bench"
	@echo "make test    - golden + sim"
	@echo "make clean   - remove obj_dir"

golden:
	cd sw/golden && python3 -m unittest test_price_level -v

$(BIN): $(RTL) $(TB)
	$(VERILATOR) $(VERILATOR_FLAGS) $(RTL) $(TB)

sim: $(BIN)
	$(BIN)

test: golden sim

clean:
	rm -rf $(VDIR)
