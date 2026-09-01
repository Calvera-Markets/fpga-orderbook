#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

#include "Vsymbol_bank.h"
#include "verilated.h"

namespace {

constexpr uint8_t BOOK_LIMIT = 0;
constexpr uint8_t BOOK_CANCEL = 1;
constexpr uint8_t SIDE_BUY = 0;
constexpr uint8_t SIDE_SELL = 1;

int errors = 0;
int checks = 0;
Vsymbol_bank *top = nullptr;

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

void tick() {
  top->clk = 0;
  top->eval();
  top->clk = 1;
  top->eval();
  if (top->evt_valid) {
    fills.push_back(
        Fill{top->evt_maker_oid, top->evt_taker_oid, top->evt_price, top->evt_qty});
  }
}

void reset() {
  fills.clear();
  top->rst_n = 0;
  top->cmd_valid = 0;
  top->cmd_symbol = 0;
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
};

Rsp issue(uint16_t symbol, uint8_t op, uint8_t side, uint32_t price, uint32_t qty,
          uint64_t oid) {
  fills.clear();
  top->cmd_symbol = symbol;
  top->cmd_op = op;
  top->cmd_side = side;
  top->cmd_price = price;
  top->cmd_qty = qty;
  top->cmd_oid = oid;
  int guard = 0;
  while (!top->cmd_ready && guard++ < 10000) {
    tick();
  }
  expect(top->cmd_ready, "cmd_ready");
  top->cmd_valid = 1;
  tick();
  top->cmd_valid = 0;
  guard = 0;
  while (!top->rsp_valid && guard++ < 10000) {
    tick();
  }
  expect(top->rsp_valid, "rsp_valid");
  Rsp r{};
  r.ok = top->rsp_ok;
  r.oid = top->rsp_oid;
  r.filled = top->rsp_filled_qty;
  r.rest = top->rsp_rest_qty;
  return r;
}

void test_no_cross_book() {
  reset();
  issue(0, BOOK_LIMIT, SIDE_SELL, 100, 10, 1);
  Rsp r = issue(1, BOOK_LIMIT, SIDE_BUY, 100, 10, 2);
  expect(r.ok, "sym1 rest ok");
  expect_eq_u64(r.filled, 0, "no cross-book fill");
  expect_eq_u64(r.rest, 10, "sym1 rest");
  expect(fills.empty(), "no fills");
}

void test_same_symbol_matches() {
  reset();
  issue(0, BOOK_LIMIT, SIDE_SELL, 100, 10, 1);
  Rsp r = issue(0, BOOK_LIMIT, SIDE_BUY, 100, 4, 2);
  expect_eq_u64(r.filled, 4, "same-symbol fill");
  expect_eq_u64(fills.size(), 1, "one fill");
}

void test_cancel() {
  reset();
  issue(2, BOOK_LIMIT, SIDE_BUY, 50, 8, 9);
  Rsp r = issue(2, BOOK_CANCEL, 0, 0, 0, 9);
  expect(r.ok, "cancel ok");
  expect_eq_u64(r.rest, 8, "cancel qty");
}

void test_out_of_range_nak() {
  reset();
  Rsp r = issue(99, BOOK_LIMIT, SIDE_BUY, 10, 1, 1);
  expect(!r.ok, "oor nak");
}

void test_beyond_old_n_syms() {
  // N_SYMS_PER_PIPE is 16 (N_PIPES_P=1 so local == symbol).
  reset();
  Rsp r = issue(8, BOOK_LIMIT, SIDE_BUY, 50, 5, 11);
  expect(r.ok, "ninth book rests");
  expect_eq_u64(r.rest, 5, "ninth book qty");
  r = issue(8, BOOK_LIMIT, SIDE_SELL, 50, 5, 12);
  expect_eq_u64(r.filled, 5, "ninth book fill");
  r = issue(15, BOOK_LIMIT, SIDE_BUY, 50, 5, 13);
  expect(r.ok, "last book rests");
  r = issue(15, BOOK_LIMIT, SIDE_SELL, 50, 5, 14);
  expect_eq_u64(r.filled, 5, "last book fill");
  r = issue(16, BOOK_LIMIT, SIDE_BUY, 10, 1, 15);
  expect(!r.ok, "local 16 oor");
}

}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top = new Vsymbol_bank;
  test_no_cross_book();
  test_same_symbol_matches();
  test_cancel();
  test_out_of_range_nak();
  test_beyond_old_n_syms();
  delete top;
  if (errors) {
    std::cerr << "FAILED " << errors << " of " << checks << " checks\n";
    return 1;
  }
  std::cout << "PASSED " << checks << " checks\n";
  return 0;
}
