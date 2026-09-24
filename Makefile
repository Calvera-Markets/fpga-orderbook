VERILATOR ?= verilator
COMMON_RTL := rtl/pkg/exch_pkg.sv rtl/book/price_level_fifo.sv

FIFO_TOP := price_level_fifo
BOOK_TOP := one_symbol_book
BANK_TOP := symbol_bank
PART_TOP := partitioned_engine
SLICE_TOP := slice_engine
LVL_TOP := level_table
TOUCH_TOP := touch_tile
OID_TOP := oid_hash
FIFO_DIR := obj_dir/price_level_fifo
BOOK_DIR := obj_dir/book
BANK_DIR := obj_dir/bank
PART_DIR := obj_dir/part
SLICE_DIR := obj_dir/slice
LVL_DIR := obj_dir/level_table
TOUCH_DIR := obj_dir/touch_tile
OID_DIR := obj_dir/oid_hash
FIFO_BIN := $(FIFO_DIR)/$(FIFO_TOP)_sim
BOOK_BIN := $(BOOK_DIR)/$(BOOK_TOP)_sim
BANK_BIN := $(BANK_DIR)/$(BANK_TOP)_sim
PART_BIN := $(PART_DIR)/$(PART_TOP)_sim
SLICE_BIN := $(SLICE_DIR)/$(SLICE_TOP)_sim
LVL_BIN := $(LVL_DIR)/$(LVL_TOP)_sim
TOUCH_BIN := $(TOUCH_DIR)/$(TOUCH_TOP)_sim
OID_BIN := $(OID_DIR)/$(OID_TOP)_sim
BOOK_RTL := $(COMMON_RTL) rtl/book/level_table.sv rtl/book/one_symbol_book.sv

VFLAGS := --cc --exe --build -sv -Wall -CFLAGS "-std=c++17 -Wall"
VERILATOR_ROOT ?= $(shell $(VERILATOR) --getenv VERILATOR_ROOT)
LIB_DIR := obj_dir/lib
LIBPE := $(LIB_DIR)/libpe.so
PART_RTL := $(BOOK_RTL) rtl/book/symbol_bank.sv rtl/book/oid_map.sv rtl/book/partitioned_engine.sv
ifeq ($(shell uname),Darwin)
LIBLDFLAGS := -Wl,-U,__Z15vl_time_stamp64v,-U,__Z13sc_time_stampv,-U,_vlog_startup_routines
endif

.PHONY: all help golden sim sim-fifo sim-book sim-bank sim-part sim-slice sim-level sim-touch sim-oid lib rtl-gw test clean run

all: test

help:
	@echo "make golden    Python golden-model and gateway tests"
	@echo "make sim-fifo  price-level FIFO Verilator bench"
	@echo "make sim-book  one-symbol book Verilator bench"
	@echo "make sim-bank  multi-symbol bank (one pipe)"
	@echo "make sim-part  partitioned engine (K pipes)"
	@echo "make sim-slice slice engine (one book per slice, private ports)"
	@echo "make sim-level price-addressed level table"
	@echo "make lib       Verilator slice_engine as libpe.so (gateway --engine rtl)"
	@echo "make sim       all RTL benches"
	@echo "make test      golden + all RTL sims + rtl gateway"
	@echo "make run         interactive mini-exchange (Verilator engine, WAL data/pipe*.wal)"
	@echo "make clean       remove obj_dir"

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

$(PART_BIN): $(PART_RTL) tb/partitioned_engine_tb.cpp
	$(VERILATOR) $(VFLAGS) --top-module $(PART_TOP) -Mdir $(PART_DIR) -o $(PART_TOP)_sim \
		$(PART_RTL) tb/partitioned_engine_tb.cpp

$(SLICE_BIN): $(BOOK_RTL) rtl/book/touch_tile.sv rtl/book/oid_hash.sv rtl/book/oid_tail.sv rtl/book/slice_engine.sv tb/slice_engine_tb.cpp
	$(VERILATOR) $(VFLAGS) --top-module $(SLICE_TOP) -Mdir $(SLICE_DIR) -o $(SLICE_TOP)_sim \
		$(BOOK_RTL) rtl/book/touch_tile.sv rtl/book/oid_hash.sv rtl/book/oid_tail.sv rtl/book/slice_engine.sv tb/slice_engine_tb.cpp

sim-fifo: $(FIFO_BIN)
	$(FIFO_BIN)

sim-book: $(BOOK_BIN)
	$(BOOK_BIN)

sim-bank: $(BANK_BIN)
	$(BANK_BIN)

sim-part: $(PART_BIN)
	$(PART_BIN)

sim-slice: $(SLICE_BIN)
	$(SLICE_BIN)

$(LVL_BIN): rtl/pkg/exch_pkg.sv rtl/book/level_table.sv tb/level_table_tb.cpp
	$(VERILATOR) $(VFLAGS) --top-module $(LVL_TOP) -Mdir $(LVL_DIR) -o $(LVL_TOP)_sim \
		rtl/pkg/exch_pkg.sv rtl/book/level_table.sv tb/level_table_tb.cpp

sim-level: $(LVL_BIN)
	$(LVL_BIN)

$(TOUCH_BIN): rtl/pkg/exch_pkg.sv rtl/book/touch_tile.sv tb/touch_tile_tb.cpp
	$(VERILATOR) $(VFLAGS) --top-module $(TOUCH_TOP) -Mdir $(TOUCH_DIR) -o $(TOUCH_TOP)_sim \
		rtl/pkg/exch_pkg.sv rtl/book/touch_tile.sv tb/touch_tile_tb.cpp

sim-touch: $(TOUCH_BIN)
	$(TOUCH_BIN)

$(OID_BIN): rtl/pkg/exch_pkg.sv rtl/book/oid_hash.sv tb/oid_hash_tb.cpp
	$(VERILATOR) $(VFLAGS) --top-module $(OID_TOP) -Mdir $(OID_DIR) -o $(OID_TOP)_sim \
		rtl/pkg/exch_pkg.sv rtl/book/oid_hash.sv tb/oid_hash_tb.cpp

sim-oid: $(OID_BIN)
	$(OID_BIN)

sim: sim-fifo sim-book sim-bank sim-part sim-slice sim-level

SLICE_RTL := $(BOOK_RTL) rtl/book/touch_tile.sv rtl/book/oid_hash.sv rtl/book/oid_tail.sv rtl/book/slice_engine.sv

$(LIB_DIR)/Vslice_engine.mk: $(SLICE_RTL)
	$(VERILATOR) --cc --build -sv -Wall --top-module $(SLICE_TOP) -Mdir $(LIB_DIR) \
		-CFLAGS "-std=c++17 -Wall -fPIC" $(SLICE_RTL)

$(LIBPE): $(LIB_DIR)/Vslice_engine.mk sw/gateway/rtl_shim.cpp
	c++ -shared -fPIC -std=c++17 -Wall -o $(LIBPE) sw/gateway/rtl_shim.cpp \
		-I$(LIB_DIR) -I$(VERILATOR_ROOT)/include -I$(VERILATOR_ROOT)/include/vltstd \
		$(LIB_DIR)/Vslice_engine__ALL.a $(LIB_DIR)/verilated.o $(LIB_DIR)/verilated_threads.o \
		-pthread $(LIBLDFLAGS)

lib: $(LIBPE)

rtl-gw: $(LIBPE)
	cd sw/gateway && python3 -m unittest test_rtl.py -v

test: golden sim rtl-gw

run: $(LIBPE)
	python3 sw/gateway/main.py --wal data --engine rtl


clean:
	rm -rf obj_dir
