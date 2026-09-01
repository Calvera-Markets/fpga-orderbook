#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

#include "Vone_symbol_book.h"
#include "verilated.h"

namespace {

constexpr uint8_t BOOK_LIMIT = 0;
constexpr uint8_t BOOK_CANCEL = 1;
constexpr uint8_t SIDE_BUY = 0;
constexpr uint8_t SIDE_SELL = 1;

int errors = 0;
int checks = 0;
Vone_symbol_book *top = nullptr;

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

struct Fill {
  uint64_t maker;
  uint64_t taker;
  uint32_t price;
  uint32_t qty;
};

std::vector<Fill> fills;

void harvest() {
  if (top->evt_valid) {
    fills.push_back(Fill{top->evt_maker_oid, top->evt_taker_oid, top->evt_price,
                         top->evt_qty});
  }
}

void tick() {
  top->clk = 0;
  top->eval();
  top->clk = 1;
  top->eval();
  harvest();
}

void reset() {
  fills.clear();
  top->rst_n = 0;
  top->cmd_valid = 0;
  top->cmd_op = 0;
  top->cmd_side = 0;
  top->cmd_price = 0;
  top->cmd_qty = 0;
  top->cmd_oid = 0;
  top->evt_ready = 1;
  for (int i = 0; i < 4; i++) {
    tick();
  }
  top->rst_n = 1;
  tick();
}

struct Rsp {
  uint8_t ok;
  uint64_t oid;
  uint32_t filled;
  uint32_t rest;
  uint32_t unrested;
};

void present(uint8_t op, uint8_t side, uint32_t price, uint32_t qty, uint64_t oid) {
  top->cmd_op = op;
  top->cmd_side = side;
  top->cmd_price = price;
  top->cmd_qty = qty;
  top->cmd_oid = oid;
}

void fire(uint8_t op, uint8_t side, uint32_t price, uint32_t qty, uint64_t oid) {
  present(op, side, price, qty, oid);
  int guard = 0;
  while (!top->cmd_ready && guard++ < 10000) {
    tick();
  }
  expect(top->cmd_ready, "cmd_ready before fire");
  top->cmd_valid = 1;
  tick();
  top->cmd_valid = 0;
}

Rsp wait_rsp() {
  int guard = 0;
  while (!top->rsp_valid && guard++ < 10000) {
    tick();
  }
  expect(top->rsp_valid, "rsp_valid after command");
  Rsp r{};
  r.ok = top->rsp_ok;
  r.oid = top->rsp_oid;
  r.filled = top->rsp_filled_qty;
  r.rest = top->rsp_rest_qty;
  r.unrested = top->rsp_unrested_qty;
  return r;
}

Rsp issue(uint8_t op, uint8_t side, uint32_t price, uint32_t qty, uint64_t oid) {
  fills.clear();
  fire(op, side, price, qty, oid);
  return wait_rsp();
}

Rsp limit(uint8_t side, uint32_t price, uint32_t qty, uint64_t oid) {
  return issue(BOOK_LIMIT, side, price, qty, oid);
}

Rsp cancel(uint64_t oid) { return issue(BOOK_CANCEL, 0, 0, 0, oid); }

void expect_bbo(int bid_valid, uint32_t bid_px, uint32_t bid_qty, int ask_valid,
                uint32_t ask_px, uint32_t ask_qty, const std::string &tag) {
  expect_eq_u64(top->bbo_bid_valid, bid_valid, tag + " bid_valid");
  expect_eq_u64(top->bbo_ask_valid, ask_valid, tag + " ask_valid");
  if (bid_valid) {
    expect_eq_u64(top->bbo_bid_px, bid_px, tag + " bid_px");
    expect_eq_u64(top->bbo_bid_qty, bid_qty, tag + " bid_qty");
  }
  if (ask_valid) {
    expect_eq_u64(top->bbo_ask_px, ask_px, tag + " ask_px");
    expect_eq_u64(top->bbo_ask_qty, ask_qty, tag + " ask_qty");
  }
}

void test_rest_no_cross() {
  reset();
  Rsp r = limit(SIDE_BUY, 100, 10, 1);
  expect(r.ok, "rest bid ok");
  expect_eq_u64(r.filled, 0, "rest bid filled");
  expect_eq_u64(r.rest, 10, "rest bid qty");
  r = limit(SIDE_SELL, 105, 7, 2);
  expect(r.ok, "rest ask ok");
  expect_eq_u64(r.rest, 7, "rest ask qty");
  expect(fills.empty(), "no fills on rest");
  expect_bbo(1, 100, 10, 1, 105, 7, "rest");
}

void test_full_fill_one_ask() {
  reset();
  limit(SIDE_SELL, 100, 10, 1);
  Rsp r = limit(SIDE_BUY, 100, 10, 2);
  expect(r.ok, "full fill ok");
  expect_eq_u64(r.filled, 10, "full fill qty");
  expect_eq_u64(r.rest, 0, "full fill rest");
  expect_eq_u64(fills.size(), 1, "one fill");
  if (!fills.empty()) {
    expect_eq_u64(fills[0].maker, 1, "maker");
    expect_eq_u64(fills[0].taker, 2, "taker");
    expect_eq_u64(fills[0].price, 100, "fill px");
    expect_eq_u64(fills[0].qty, 10, "fill qty");
  }
  expect_bbo(0, 0, 0, 0, 0, 0, "after full fill");
}

void test_partial_then_rest() {
  reset();
  limit(SIDE_SELL, 100, 10, 1);
  Rsp r = limit(SIDE_BUY, 100, 25, 2);
  expect(r.ok, "partial ok");
  expect_eq_u64(r.filled, 10, "partial filled");
  expect_eq_u64(r.rest, 15, "partial rest");
  expect_eq_u64(fills.size(), 1, "partial fills");
  expect_bbo(1, 100, 15, 0, 0, 0, "partial bbo");
}

void test_walk_two_prices() {
  reset();
  limit(SIDE_SELL, 100, 4, 1);
  limit(SIDE_SELL, 100, 6, 2);
  limit(SIDE_SELL, 105, 50, 3);
  Rsp r = limit(SIDE_BUY, 105, 15, 9);
  expect(r.ok, "walk ok");
  expect_eq_u64(r.filled, 15, "walk filled");
  expect_eq_u64(r.rest, 0, "walk rest");
  expect_eq_u64(fills.size(), 3, "walk 3 fills");
  if (fills.size() == 3) {
    expect_eq_u64(fills[0].maker, 1, "walk f0 maker");
    expect_eq_u64(fills[0].price, 100, "walk f0 px");
    expect_eq_u64(fills[0].qty, 4, "walk f0 qty");
    expect_eq_u64(fills[1].maker, 2, "walk f1 maker");
    expect_eq_u64(fills[1].qty, 6, "walk f1 qty");
    expect_eq_u64(fills[2].maker, 3, "walk f2 maker");
    expect_eq_u64(fills[2].price, 105, "walk f2 px");
    expect_eq_u64(fills[2].qty, 5, "walk f2 qty");
  }
  expect_bbo(0, 0, 0, 1, 105, 45, "walk bbo");
}

void test_cancel_updates_bbo() {
  reset();
  limit(SIDE_BUY, 100, 10, 1);
  limit(SIDE_BUY, 99, 8, 2);
  Rsp r = cancel(1);
  expect(r.ok, "cancel ok");
  expect_eq_u64(r.rest, 10, "cancel qty");
  expect_bbo(1, 99, 8, 0, 0, 0, "after cancel");
}

void test_cancel_missing() {
  reset();
  limit(SIDE_BUY, 100, 10, 1);
  Rsp r = cancel(99);
  expect(!r.ok, "cancel missing");
  expect_bbo(1, 100, 10, 0, 0, 0, "cancel missing bbo");
}

void test_qty_zero() {
  reset();
  Rsp r = limit(SIDE_BUY, 100, 0, 1);
  expect(!r.ok, "qty0 nak");
  expect_bbo(0, 0, 0, 0, 0, 0, "qty0");
}

void test_take_side_then_rest() {
  reset();
  limit(SIDE_SELL, 100, 5, 1);
  Rsp r = limit(SIDE_BUY, 110, 20, 2);
  expect(r.ok, "take side ok");
  expect_eq_u64(r.filled, 5, "take filled");
  expect_eq_u64(r.rest, 15, "take rest");
  expect_bbo(1, 110, 15, 0, 0, 0, "take bbo");
}

void test_sell_crosses_bid() {
  reset();
  limit(SIDE_BUY, 100, 8, 1);
  Rsp r = limit(SIDE_SELL, 90, 3, 2);
  expect(r.ok, "sell cross ok");
  expect_eq_u64(r.filled, 3, "sell filled");
  expect_eq_u64(r.rest, 0, "sell rest");
  expect_eq_u64(fills.size(), 1, "sell fills");
  if (!fills.empty()) {
    expect_eq_u64(fills[0].maker, 1, "sell maker");
    expect_eq_u64(fills[0].price, 100, "sell px");
  }
  expect_bbo(1, 100, 5, 0, 0, 0, "sell bbo");
}

void test_same_price_bbo() {
  reset();
  limit(SIDE_BUY, 100, 10, 1);
  limit(SIDE_BUY, 100, 7, 2);
  expect_bbo(1, 100, 17, 0, 0, 0, "agg bbo");
}

void test_bid_ask_parallel() {
  reset();
  fills.clear();
  fire(BOOK_LIMIT, SIDE_BUY, 99, 10, 1);
  present(BOOK_LIMIT, SIDE_SELL, 101, 7, 2);
  top->eval();
  expect(top->cmd_ready, "ask ready while bid resting");
  fire(BOOK_LIMIT, SIDE_SELL, 101, 7, 2);
  bool got1 = false;
  bool got2 = false;
  Rsp r1{};
  Rsp r2{};
  int guard = 0;
  while ((!got1 || !got2) && guard++ < 10000) {
    if (top->rsp_valid) {
      if (top->rsp_oid == 1) {
        got1 = true;
        r1.ok = top->rsp_ok;
        r1.rest = top->rsp_rest_qty;
      }
      if (top->rsp_oid == 2) {
        got2 = true;
        r2.ok = top->rsp_ok;
        r2.rest = top->rsp_rest_qty;
      }
    }
    if (!got1 || !got2) {
      tick();
    }
  }
  expect(got1 && got2, "both sides responded");
  expect(r1.ok, "bid rest ok");
  expect(r2.ok, "ask rest ok");
  expect_eq_u64(r1.rest, 10, "bid rest qty");
  expect_eq_u64(r2.rest, 7, "ask rest qty");
  expect(fills.empty(), "no fills on dual rest");
  expect_bbo(1, 99, 10, 1, 101, 7, "dual rest");
}

void test_same_side_serialized() {
  reset();
  fire(BOOK_LIMIT, SIDE_BUY, 99, 10, 1);
  present(BOOK_LIMIT, SIDE_BUY, 98, 5, 2);
  top->eval();
  expect(!top->cmd_ready, "same-side bid waits");
  Rsp r = wait_rsp();
  expect(r.ok, "first bid rest");
  r = issue(BOOK_LIMIT, SIDE_BUY, 98, 5, 2);
  expect(r.ok, "second bid rest");
  expect_bbo(1, 99, 10, 0, 0, 0, "two bids");
}

void test_cross_waits_for_inflight_ask() {
  reset();
  fire(BOOK_LIMIT, SIDE_SELL, 100, 10, 1);
  present(BOOK_LIMIT, SIDE_BUY, 100, 10, 2);
  top->eval();
  expect(!top->cmd_ready, "crossing buy waits for inflight ask");
  Rsp r = wait_rsp();
  expect(r.ok, "ask rested");
  r = issue(BOOK_LIMIT, SIDE_BUY, 100, 10, 2);
  expect_eq_u64(r.filled, 10, "buy matches after ask rest");
}

}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top = new Vone_symbol_book;

  test_rest_no_cross();
  test_full_fill_one_ask();
  test_partial_then_rest();
  test_walk_two_prices();
  test_cancel_updates_bbo();
  test_cancel_missing();
  test_qty_zero();
  test_take_side_then_rest();
  test_sell_crosses_bid();
  test_same_price_bbo();
  test_bid_ask_parallel();
  test_same_side_serialized();
  test_cross_waits_for_inflight_ask();

  delete top;

  if (errors) {
    std::cerr << "FAILED " << errors << " of " << checks << " checks\n";
    return 1;
  }
  std::cout << "PASSED " << checks << " checks\n";
  return 0;
}
