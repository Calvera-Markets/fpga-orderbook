#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

#include "Vslice_engine.h"
#include "verilated.h"

namespace {

constexpr uint8_t BOOK_LIMIT = 0;
constexpr uint8_t BOOK_CANCEL = 1;
constexpr uint8_t SIDE_BUY = 0;
constexpr uint8_t SIDE_SELL = 1;
constexpr uint8_t ALGO_FIFO = 0;
constexpr uint8_t ALGO_PRORATA = 1;
constexpr uint8_t ALGO_MIDPOINT = 2;
constexpr int N_SLICES = 4;

int errors = 0;
int checks = 0;
int cycles = 0;
Vslice_engine *top = nullptr;

void fail(const std::string &msg) {
  std::cerr << "FAIL: " << msg << "\n";
  errors++;
}

void expect(bool cond, const std::string &what) {
  checks++;
  if (!cond) {
    fail(what);
  }
}

void expect_eq_u64(uint64_t got, uint64_t want, const std::string &what) {
  checks++;
  if (got != want) {
    fail(what + " got " + std::to_string(got) + " want " + std::to_string(want));
  }
}

bool bit(uint32_t v, int i) { return ((v >> i) & 1u) != 0; }

struct Fill {
  int slice;
  uint64_t maker;
  uint32_t price;
  uint32_t qty;
};

std::vector<Fill> fills;
uint32_t evt_seen = 0;

void harvest() {
  for (int s = 0; s < N_SLICES; s++) {
    bool v = bit(top->evt_valid, s);
    if (v && !bit(evt_seen, s)) {
      fills.push_back(Fill{s, top->evt_maker_oid[s], top->evt_price[s], top->evt_qty[s]});
    }
    if (v) {
      evt_seen |= 1u << s;
    } else {
      evt_seen &= ~(1u << s);
    }
  }
}

void tick() {
  top->clk = 0;
  top->eval();
  top->clk = 1;
  top->eval();
  cycles++;
  harvest();
}

void reset() {
  fills.clear();
  evt_seen = 0;
  cycles = 0;
  top->rst_n = 0;
  top->cfg_valid = 0;
  top->cfg_slice = 0;
  top->cfg_symbol = 0;
  top->cfg_algo = ALGO_FIFO;
  top->lookup_oid = 0;
  top->cmd_valid = 0;
  top->cmd_flag = 0;
  top->host_ready = 1;
  top->cmd_op = 0;
  top->cmd_side = 0;
  top->evt_ready = (1u << N_SLICES) - 1u;
  for (int s = 0; s < N_SLICES; s++) {
    top->cmd_price[s] = 0;
    top->cmd_qty[s] = 0;
    top->cmd_oid[s] = 0;
  }
  for (int i = 0; i < 4; i++) {
    tick();
  }
  top->rst_n = 1;
  tick();
}

struct Rsp {
  uint8_t ok;
  uint32_t filled;
  uint32_t rest;
  int cycle;
};

void present(int s, uint8_t op, uint8_t side, uint32_t price, uint32_t qty, uint64_t oid) {
  top->cmd_op = (top->cmd_op & ~(1u << s)) | (uint32_t(op) << s);
  top->cmd_side = (top->cmd_side & ~(1u << s)) | (uint32_t(side) << s);
  top->cmd_price[s] = price;
  top->cmd_qty[s] = qty;
  top->cmd_oid[s] = oid;
}

void set_valid(int s, bool v) {
  if (v) {
    top->cmd_valid |= 1u << s;
  } else {
    top->cmd_valid &= ~(1u << s);
  }
}

void fire(int s, uint8_t op, uint8_t side, uint32_t price, uint32_t qty, uint64_t oid) {
  present(s, op, side, price, qty, oid);
  top->eval();
  int guard = 0;
  while (!bit(top->cmd_ready, s) && guard++ < 10000) {
    tick();
  }
  expect(bit(top->cmd_ready, s), "cmd_ready before fire");
  set_valid(s, true);
  tick();
  set_valid(s, false);
}

Rsp wait_rsp(int s) {
  int guard = 0;
  bool seen = bit(top->rsp_valid, s);
  while (!seen && guard++ < 10000) {
    tick();
    seen = bit(top->rsp_valid, s);
  }
  expect(seen, "rsp_valid slice");
  Rsp r{};
  r.ok = bit(top->rsp_ok, s);
  r.filled = top->rsp_filled_qty[s];
  r.rest = top->rsp_rest_qty[s];
  r.cycle = cycles;
  return r;
}

Rsp issue(int s, uint8_t op, uint8_t side, uint32_t price, uint32_t qty, uint64_t oid) {
  fire(s, op, side, price, qty, oid);
  return wait_rsp(s);
}

void test_two_slices_same_cycle() {
  reset();
  present(0, BOOK_LIMIT, SIDE_BUY, 10, 4, 1);
  present(1, BOOK_LIMIT, SIDE_SELL, 20, 5, 2);
  expect(bit(top->cmd_ready, 0) && bit(top->cmd_ready, 1), "both slices ready together");
  set_valid(0, true);
  set_valid(1, true);
  tick();
  set_valid(0, false);
  set_valid(1, false);
  Rsp a = wait_rsp(0);
  Rsp b = wait_rsp(1);
  expect(a.ok && b.ok, "both rests ok");
  expect_eq_u64(a.rest, 4, "slice 0 rest");
  expect_eq_u64(b.rest, 5, "slice 1 rest");
  expect_eq_u64(a.filled, 0, "slice 0 did not take slice 1");
  expect_eq_u64(b.filled, 0, "slice 1 did not take slice 0");
  expect(fills.empty(), "no cross-slice fill");
}

void test_sweep_does_not_stall_other_slice() {
  reset();
  issue(0, BOOK_LIMIT, SIDE_SELL, 100, 1, 10);
  issue(0, BOOK_LIMIT, SIDE_SELL, 100, 1, 11);
  issue(0, BOOK_LIMIT, SIDE_SELL, 100, 1, 12);
  issue(1, BOOK_LIMIT, SIDE_BUY, 50, 4, 20);

  top->evt_ready = ((1u << N_SLICES) - 1u) & ~1u;
  fills.clear();
  fire(0, BOOK_LIMIT, SIDE_BUY, 100, 3, 30);
  expect(!bit(top->cmd_ready, 0), "slice 0 busy during walk");
  expect(bit(top->cmd_ready, 1), "slice 1 ready while slice 0 walks");
  expect(!bit(top->rsp_valid, 0), "slice 0 held by its own fill ready");

  int before = cycles;
  Rsp other = issue(1, BOOK_LIMIT, SIDE_SELL, 80, 1, 21);
  expect(other.ok, "slice 1 rest during foreign walk");
  expect_eq_u64(other.rest, 1, "slice 1 rested its own qty");
  expect(other.cycle > before, "slice 1 accepted on its own cycles");
  expect(!bit(top->rsp_valid, 0), "slice 0 still waiting on evt_ready");
  top->cfg_slice = 0;
  top->cfg_symbol = 7;
  top->cfg_algo = ALGO_FIFO;
  top->eval();
  expect(!top->cfg_ready, "cannot re-slice a busy book");
  expect_eq_u64(top->slice_symbol[0], 0, "symbol unchanged while busy");

  top->evt_ready = (1u << N_SLICES) - 1u;
  bool saw_sweep = bit(top->rsp_valid, 0);
  int sweep_guard = 0;
  while (!saw_sweep && sweep_guard++ < 10000) {
    tick();
    if (bit(top->rsp_valid, 0)) saw_sweep = true;
  }
  Rsp sweep{};
  sweep.ok = bit(top->rsp_ok, 0);
  sweep.filled = top->rsp_filled_qty[0];
  expect(saw_sweep || sweep.filled == 3, "sweep completes after its own ready returns");
  expect_eq_u64(sweep.filled, 3, "three lots taken on slice 0");
  expect_eq_u64(fills.size(), 3, "three fills");
  if (fills.size() == 3) {
    expect_eq_u64(fills[0].price, 100, "first fill at best ask");
    expect_eq_u64(fills[1].price, 100, "second fill");
    expect_eq_u64(fills[2].price, 100, "third fill");
    expect(fills[0].slice == 0 && fills[2].slice == 0, "fills stay on slice 0");
  }
  expect(bit(top->bbo_bid_valid, 1), "slice 1 bid survived the sweep");
  expect_eq_u64(top->bbo_bid_qty[1], 4, "slice 1 bid qty untouched");
  expect(bit(top->bbo_ask_valid, 1), "slice 1 ask rested during the sweep");
  expect_eq_u64(top->bbo_ask_px[1], 80, "slice 1 ask price");
}

void cfg_algo(int s, uint8_t algo) {
  top->cfg_slice = s;
  top->cfg_symbol = s;
  top->cfg_algo = algo;
  top->cfg_valid = 1;
  expect(top->cfg_ready, "idle slice accepts algo");
  tick();
  top->cfg_valid = 0;
  expect_eq_u64(top->slice_algo[s], algo, "algo stored");
}

void test_prorata_splits_the_queue() {
  reset();
  cfg_algo(2, ALGO_PRORATA);
  issue(2, BOOK_LIMIT, SIDE_SELL, 100, 1, 1);
  issue(2, BOOK_LIMIT, SIDE_SELL, 100, 3, 2);
  fills.clear();
  evt_seen = 0;
  fire(2, BOOK_LIMIT, SIDE_BUY, 100, 2, 9);
  expect(bit(top->cmd_ready, 0), "price-time slice stays ready during pro-rata");
  Rsp odd = wait_rsp(2);
  expect(odd.ok, "pro-rata take of 2 accepted");
  expect_eq_u64(odd.filled, 2, "pro-rata filled 2");
  expect_eq_u64(fills.size(), 2, "two pro-rata fills");
  if (fills.size() == 2) {
    expect_eq_u64(fills[0].maker, 1, "oldest gets the odd lot");
    expect_eq_u64(fills[0].qty, 1, "oldest fill is 1");
    expect_eq_u64(fills[1].maker, 2, "second maker");
    expect_eq_u64(fills[1].qty, 1, "second fill is 1");
    expect(fills[0].slice == 2 && fills[1].slice == 2, "fills stay on the pro-rata slice");
  }

  reset();
  cfg_algo(2, ALGO_PRORATA);
  issue(2, BOOK_LIMIT, SIDE_SELL, 100, 5, 1);
  issue(2, BOOK_LIMIT, SIDE_SELL, 100, 5, 2);
  issue(0, BOOK_LIMIT, SIDE_SELL, 100, 5, 10);
  issue(0, BOOK_LIMIT, SIDE_SELL, 100, 5, 11);
  fills.clear();
  evt_seen = 0;
  Rsp pr = issue(2, BOOK_LIMIT, SIDE_BUY, 100, 4, 9);
  expect_eq_u64(pr.filled, 4, "equal pro-rata took 4");
  expect_eq_u64(fills.size(), 2, "equal sizes split into two fills");
  if (fills.size() == 2) {
    expect_eq_u64(fills[0].maker, 1, "first half maker");
    expect_eq_u64(fills[0].qty, 2, "first half is 2");
    expect_eq_u64(fills[1].maker, 2, "second half maker");
    expect_eq_u64(fills[1].qty, 2, "second half is 2");
  }
  expect_eq_u64(top->bbo_ask_qty[2], 6, "pro-rata leaves 3 and 3");
  fills.clear();
  evt_seen = 0;
  Rsp fifo = issue(0, BOOK_LIMIT, SIDE_BUY, 100, 4, 12);
  expect_eq_u64(fifo.filled, 4, "price-time took 4");
  expect_eq_u64(fills.size(), 1, "price-time is one fill");
  if (!fills.empty()) {
    expect_eq_u64(fills[0].maker, 10, "price-time takes the oldest");
    expect_eq_u64(fills[0].qty, 4, "price-time does not split");
    expect_eq_u64(fills[0].slice, 0, "price-time fill stays on slice 0");
  }
  expect_eq_u64(top->bbo_ask_qty[0], 6, "price-time leaves 1 and 5");
}

void test_midpoint_trades_between_the_sides() {
  reset();
  cfg_algo(2, ALGO_MIDPOINT);
  issue(2, BOOK_LIMIT, SIDE_BUY, 100, 1, 1);
  issue(2, BOOK_LIMIT, SIDE_SELL, 110, 1, 2);
  issue(0, BOOK_LIMIT, SIDE_BUY, 100, 1, 10);
  issue(0, BOOK_LIMIT, SIDE_SELL, 110, 1, 11);
  fills.clear();
  evt_seen = 0;
  Rsp mid = issue(2, BOOK_LIMIT, SIDE_BUY, 110, 1, 3);
  expect(mid.ok, "midpoint buy trades");
  expect_eq_u64(mid.filled, 1, "midpoint filled 1");
  expect_eq_u64(fills.size(), 1, "one midpoint fill");
  if (!fills.empty()) {
    expect_eq_u64(fills[0].price, 105, "midpoint is 105");
    expect_eq_u64(fills[0].maker, 2, "midpoint takes the ask");
    expect_eq_u64(fills[0].slice, 2, "midpoint fill stays on its slice");
  }
  fills.clear();
  evt_seen = 0;
  Rsp fifo = issue(0, BOOK_LIMIT, SIDE_BUY, 110, 1, 12);
  expect_eq_u64(fifo.filled, 1, "price-time filled 1");
  expect_eq_u64(fills.size(), 1, "one price-time fill");
  if (!fills.empty()) {
    expect_eq_u64(fills[0].price, 110, "price-time trades at the ask");
    expect_eq_u64(fills[0].slice, 0, "price-time fill stays on slice 0");
  }

  reset();
  cfg_algo(2, ALGO_MIDPOINT);
  issue(2, BOOK_LIMIT, SIDE_SELL, 110, 1, 2);
  fills.clear();
  evt_seen = 0;
  Rsp rested = issue(2, BOOK_LIMIT, SIDE_BUY, 110, 1, 3);
  expect(rested.ok, "midpoint with one side rests");
  expect_eq_u64(rested.filled, 0, "missing side does not trade");
  expect_eq_u64(rested.rest, 1, "order rests as a limit");
  expect(fills.empty(), "no fill without both sides");
  expect_eq_u64(top->bbo_ask_qty[2], 1, "ask was not taken");
  expect(bit(top->bbo_bid_valid, 2), "buy rested on the bid");
}

void test_price_miss_does_not_stall_other_slice() {
  reset();
  issue(0, BOOK_LIMIT, SIDE_BUY, 50, 1, 1);
  present(0, BOOK_LIMIT, SIDE_BUY, 60, 1, 2);
  set_valid(0, true);
  tick();
  expect(!bit(top->cmd_ready, 0), "different price waits out its own miss");
  expect(bit(top->cmd_ready, 1), "other slice stays ready during the miss");
  present(1, BOOK_LIMIT, SIDE_SELL, 80, 1, 3);
  expect(bit(top->cmd_ready, 1), "slice 1 ready on the miss cycle");
  set_valid(1, true);
  bool saw0 = false;
  bool saw1 = false;
  uint32_t rest1 = 0;
  int guard = 0;
  while ((!saw0 || !saw1) && guard++ < 10000) {
    tick();
    if (bit(top->rsp_valid, 0)) saw0 = true;
    if (bit(top->rsp_valid, 1)) {
      saw1 = true;
      rest1 = top->rsp_rest_qty[1];
    }
  }
  set_valid(0, false);
  set_valid(1, false);
  expect(saw1, "other slice rested during the miss");
  expect_eq_u64(rest1, 1, "other slice rest qty");
  expect(saw0, "missed price eventually rests");
  expect_eq_u64(top->wb_px, 50, "evicted touch price was written back");
}

void test_lookup_names_the_slice() {
  reset();
  issue(0, BOOK_LIMIT, SIDE_BUY, 40, 3, 7);
  tick();
  top->lookup_oid = 7;
  top->eval();
  expect(top->lookup_hit, "resting oid is in the map");
  expect_eq_u64(top->lookup_slice, 0, "oid sits on slice 0");
  expect_eq_u64(top->lookup_price, 40, "oid remembers the price");
  expect_eq_u64(top->lookup_side, SIDE_BUY, "tile side is bid");
  expect(bit(top->cmd_ready, 1), "slice 1 stays ready");
  Rsp c = issue(top->lookup_slice, BOOK_CANCEL, SIDE_BUY, 0, 0, 7);
  expect(c.ok, "cancel enters the looked-up slice");
  expect(!bit(top->bbo_bid_valid, 0), "slice 0 bid is gone");
  expect(bit(top->cmd_ready, 1), "cancel did not busy slice 1");
}

void test_cold_lookup_does_not_stall() {
  reset();
  issue(0, BOOK_LIMIT, SIDE_BUY, 40, 1, 7);
  issue(0, BOOK_LIMIT, SIDE_BUY, 40, 1, 23);
  tick();
  tick();
  top->lookup_oid = 7;
  top->eval();
  expect(top->lookup_hit, "7 stays in its bucket");
  top->lookup_oid = 23;
  top->eval();
  expect(top->lookup_hit, "23 stays in the next bucket");
  top->lookup_oid = 100;
  top->eval();
  expect(!top->lookup_hit, "unknown id misses the hot hash");
  expect(bit(top->cmd_ready, 1), "slice 1 ready during the tail wait");
  Rsp other = issue(1, BOOK_LIMIT, SIDE_SELL, 80, 1, 99);
  expect(other.ok, "slice 1 rested during the cold lookup");
  int guard = 0;
  while (guard++ < 6) tick();
  expect(!top->lookup_hit, "unknown id is not invented by the tail");
}

void test_flag_goes_to_the_host() {
  reset();
  top->cmd_flag = 1u;
  present(0, BOOK_LIMIT, SIDE_BUY, 15, 1, 41);
  set_valid(0, true);
  top->eval();
  expect(bit(top->cmd_ready, 0), "flagged slice is ready on the host path");
  expect(bit(top->cmd_ready, 1), "other slice stays ready");
  tick();
  set_valid(0, false);
  int guard = 0;
  while (!top->host_valid && guard++ < 8) tick();
  expect(top->host_valid, "reject is on the host port");
  expect_eq_u64(top->host_oid, 41, "host records the oid");
  expect_eq_u64(top->host_slice, 0, "host names the slice");
  expect(!bit(top->bbo_bid_valid, 0), "flag does not rest");
  expect(!bit(top->rsp_valid, 1), "reject is not another slice's response");
  top->cmd_flag = 0;
  Rsp other = issue(1, BOOK_LIMIT, SIDE_BUY, 20, 1, 42);
  expect(other.ok, "other slice still rests");
  expect_eq_u64(other.rest, 1, "other slice rest qty");
}

void test_reslice_when_idle() {
  reset();
  top->cfg_slice = 3;
  top->cfg_symbol = 99;
  top->cfg_algo = ALGO_FIFO;
  top->cfg_valid = 1;
  tick();
  top->cfg_valid = 0;
  expect_eq_u64(top->slice_symbol[3], 99, "host assigned symbol 99");
  Rsp r = issue(3, BOOK_LIMIT, SIDE_SELL, 7, 1, 50);
  expect(r.ok, "re-sliced book still rests");
  expect_eq_u64(top->slice_symbol[0], 0, "other slice symbol stays");
}

}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top = new Vslice_engine;
  test_two_slices_same_cycle();
  test_sweep_does_not_stall_other_slice();
  test_price_miss_does_not_stall_other_slice();
  test_prorata_splits_the_queue();
  test_midpoint_trades_between_the_sides();
  test_lookup_names_the_slice();
  test_cold_lookup_does_not_stall();
  test_flag_goes_to_the_host();
  test_reslice_when_idle();
  if (errors == 0) {
    std::cout << "slice_engine: " << checks << " checks passed\n";
  } else {
    std::cout << "slice_engine: " << errors << " errors in " << checks << " checks\n";
  }
  delete top;
  return errors == 0 ? 0 : 1;
}
