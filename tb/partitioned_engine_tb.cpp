#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

#include "Vpartitioned_engine.h"
#include "verilated.h"

namespace {

constexpr uint8_t BOOK_LIMIT = 0;
constexpr uint8_t BOOK_CANCEL = 1;
constexpr uint8_t SIDE_BUY = 0;
constexpr uint8_t SIDE_SELL = 1;
constexpr int N_PIPES = 2;

int errors = 0;
int checks = 0;
int cycles = 0;
Vpartitioned_engine *top = nullptr;

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

int pipe_of(uint16_t symbol) { return symbol % N_PIPES; }

struct Fill {
  int pipe;
  uint64_t maker;
  uint32_t qty;
};

std::vector<Fill> fills;

void harvest() {
  for (int p = 0; p < N_PIPES; p++) {
    if ((top->evt_valid >> p) & 1) {
      fills.push_back(Fill{p, top->evt_maker_oid[p], top->evt_qty[p]});
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
  cycles = 0;
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
  uint32_t filled;
  uint32_t rest;
};

void fire(uint16_t symbol, uint8_t op, uint8_t side, uint32_t price, uint32_t qty,
          uint64_t oid) {
  top->cmd_symbol = symbol;
  int guard = 0;
  while (!top->cmd_ready && guard++ < 10000) {
    tick();
  }
  expect(top->cmd_ready, "cmd_ready before fire");
  top->cmd_valid = 1;
  top->cmd_symbol = symbol;
  top->cmd_op = op;
  top->cmd_side = side;
  top->cmd_price = price;
  top->cmd_qty = qty;
  top->cmd_oid = oid;
  tick();
  top->cmd_valid = 0;
}

Rsp wait_pipe(int p) {
  int guard = 0;
  while (!((top->rsp_valid >> p) & 1) && guard++ < 10000) {
    tick();
  }
  expect((top->rsp_valid >> p) & 1, "rsp_valid pipe");
  Rsp r{};
  r.ok = (top->rsp_ok >> p) & 1;
  r.filled = top->rsp_filled_qty[p];
  r.rest = top->rsp_rest_qty[p];
  return r;
}

Rsp issue(uint16_t symbol, uint8_t op, uint8_t side, uint32_t price, uint32_t qty,
          uint64_t oid) {
  fills.clear();
  fire(symbol, op, side, price, qty, oid);
  return wait_pipe(pipe_of(symbol));
}

void test_no_cross_pipe() {
  reset();
  issue(0, BOOK_LIMIT, SIDE_SELL, 100, 10, 1);
  Rsp r = issue(1, BOOK_LIMIT, SIDE_BUY, 100, 10, 2);
  expect_eq_u64(r.filled, 0, "no cross-pipe fill");
  expect_eq_u64(r.rest, 10, "sym1 rest");
}

void test_cancel() {
  reset();
  issue(1, BOOK_LIMIT, SIDE_BUY, 50, 8, 9);
  Rsp r = issue(1, BOOK_CANCEL, 0, 0, 0, 9);
  expect(r.ok, "cancel ok");
  expect_eq_u64(r.rest, 8, "cancel qty");
}

void test_cancel_without_symbol() {
  reset();
  issue(1, BOOK_LIMIT, SIDE_BUY, 50, 8, 9);
  for (int i = 0; i < 8; i++) {
    tick();
  }
  fire(0, BOOK_CANCEL, 0, 0, 0, 9);
  Rsp r = wait_pipe(1);
  expect(r.ok, "oid map routes cancel");
  expect_eq_u64(r.rest, 8, "cancel qty via map");
}

void test_same_symbol_fifo() {
  reset();
  issue(0, BOOK_LIMIT, SIDE_SELL, 100, 10, 1);
  Rsp r = issue(0, BOOK_LIMIT, SIDE_BUY, 100, 4, 2);
  expect_eq_u64(r.filled, 4, "same-symbol fill");
}

void test_parallel_issue() {
  reset();
  issue(0, BOOK_LIMIT, SIDE_SELL, 100, 10, 1);
  issue(1, BOOK_LIMIT, SIDE_SELL, 100, 10, 2);
  fills.clear();
  fire(0, BOOK_LIMIT, SIDE_BUY, 100, 10, 3);
  int start = cycles;
  top->cmd_symbol = 1;
  top->eval();
  expect(top->cmd_ready, "pipe 1 ready while pipe 0 matching");
  fire(1, BOOK_LIMIT, SIDE_BUY, 100, 10, 4);
  int gap = cycles - start;
  expect(gap <= 4, "second fire without waiting for first match");
  bool got[2] = {false, false};
  Rsp rs[2]{};
  int guard = 0;
  while ((!got[0] || !got[1]) && guard++ < 10000) {
    for (int p = 0; p < N_PIPES; p++) {
      if (!got[p] && ((top->rsp_valid >> p) & 1)) {
        got[p] = true;
        rs[p].ok = (top->rsp_ok >> p) & 1;
        rs[p].filled = top->rsp_filled_qty[p];
      }
    }
    if (!got[0] || !got[1]) {
      tick();
    }
  }
  expect(got[0] && got[1], "both pipes responded");
  expect_eq_u64(rs[0].filled, 10, "pipe0 fill");
  expect_eq_u64(rs[1].filled, 10, "pipe1 fill");
  std::cout << "parallel_issue gap_cycles=" << gap << "\n";
}

}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top = new Vpartitioned_engine;
  test_no_cross_pipe();
  test_same_symbol_fifo();
  test_cancel();
  test_cancel_without_symbol();
  test_parallel_issue();
  delete top;
  if (errors) {
    std::cerr << "FAILED " << errors << " of " << checks << " checks\n";
    return 1;
  }
  std::cout << "PASSED " << checks << " checks\n";
  return 0;
}
