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
  top->cmd_valid = 0;
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
  while (!bit(top->rsp_valid, s) && guard++ < 10000) {
    tick();
  }
  expect(bit(top->rsp_valid, s), "rsp_valid slice");
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
  issue(0, BOOK_LIMIT, SIDE_SELL, 101, 1, 11);
  issue(0, BOOK_LIMIT, SIDE_SELL, 102, 1, 12);
  issue(1, BOOK_LIMIT, SIDE_BUY, 50, 4, 20);

  top->evt_ready = ((1u << N_SLICES) - 1u) & ~1u;
  fills.clear();
  fire(0, BOOK_LIMIT, SIDE_BUY, 102, 3, 30);
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
  Rsp sweep = wait_rsp(0);
  expect(sweep.ok, "sweep completes after its own ready returns");
  expect_eq_u64(sweep.filled, 3, "three lots taken on slice 0");
  expect_eq_u64(fills.size(), 3, "three fills");
  if (fills.size() == 3) {
    expect_eq_u64(fills[0].price, 100, "first fill at best ask");
    expect_eq_u64(fills[1].price, 101, "second fill");
    expect_eq_u64(fills[2].price, 102, "third fill");
    expect(fills[0].slice == 0 && fills[2].slice == 0, "fills stay on slice 0");
  }
  expect(bit(top->bbo_bid_valid, 1), "slice 1 bid survived the sweep");
  expect_eq_u64(top->bbo_bid_qty[1], 4, "slice 1 bid qty untouched");
  expect(bit(top->bbo_ask_valid, 1), "slice 1 ask rested during the sweep");
  expect_eq_u64(top->bbo_ask_px[1], 80, "slice 1 ask price");
}

void test_algo_nak_is_local() {
  reset();
  issue(0, BOOK_LIMIT, SIDE_BUY, 15, 2, 40);
  top->cfg_slice = 2;
  top->cfg_symbol = 2;
  top->cfg_algo = ALGO_PRORATA;
  top->cfg_valid = 1;
  expect(top->cfg_ready, "idle slice accepts algo");
  tick();
  top->cfg_valid = 0;
  expect_eq_u64(top->slice_algo[2], ALGO_PRORATA, "algo stored");
  Rsp nak = issue(2, BOOK_LIMIT, SIDE_BUY, 15, 9, 41);
  expect(!nak.ok, "unimplemented algo naks");
  expect_eq_u64(nak.filled, 0, "nak fills nothing");
  expect(!bit(top->bbo_bid_valid, 2), "nak does not rest");
  Rsp c = issue(0, BOOK_CANCEL, SIDE_BUY, 0, 0, 40);
  expect(c.ok, "other slice still cancels");
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
  test_algo_nak_is_local();
  test_reslice_when_idle();
  if (errors == 0) {
    std::cout << "slice_engine: " << checks << " checks passed\n";
  } else {
    std::cout << "slice_engine: " << errors << " errors in " << checks << " checks\n";
  }
  delete top;
  return errors == 0 ? 0 : 1;
}
