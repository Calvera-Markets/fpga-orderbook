#include <cstdint>
#include <iostream>
#include <string>

#include "Vprice_level_fifo.h"
#include "verilated.h"

namespace {

constexpr uint8_t OP_ADD = 0;
constexpr uint8_t OP_MATCH = 1;
constexpr uint8_t OP_CANCEL = 2;
constexpr int MAX_ORDERS = 16;

int errors = 0;
int checks = 0;
Vprice_level_fifo *top = nullptr;

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

void tick() {
  top->clk = 0;
  top->eval();
  top->clk = 1;
  top->eval();
}

void reset() {
  top->rst_n = 0;
  top->cmd_valid = 0;
  top->cmd_op = 0;
  top->cmd_oid = 0;
  top->cmd_qty = 0;
  for (int i = 0; i < 4; i++) {
    tick();
  }
  top->rst_n = 1;
  tick();
}

struct Rsp {
  uint8_t valid;
  uint8_t ok;
  uint64_t oid;
  uint32_t qty;
};

Rsp issue(uint8_t op, uint64_t oid, uint32_t qty) {
  top->cmd_valid = 1;
  top->cmd_op = op;
  top->cmd_oid = oid;
  top->cmd_qty = qty;
  tick();
  top->cmd_valid = 0;
  Rsp r{};
  r.valid = top->rsp_valid;
  r.ok = top->rsp_ok;
  r.oid = top->rsp_oid;
  r.qty = top->rsp_qty;
  expect(r.valid, "rsp_valid after command");
  return r;
}

void expect_probes(uint32_t depth, uint64_t head_oid, uint32_t head_qty,
                   uint32_t total, const std::string &tag) {
  expect_eq_u64(top->depth, depth, tag + " depth");
  expect_eq_u64(top->empty, depth == 0, tag + " empty");
  expect_eq_u64(top->full, depth == MAX_ORDERS, tag + " full");
  expect_eq_u64(top->head_oid, head_oid, tag + " head_oid");
  expect_eq_u64(top->head_qty, head_qty, tag + " head_qty");
  expect_eq_u64(top->total_qty, total, tag + " total_qty");
}

void test_reset_empty() {
  reset();
  expect(top->empty, "reset empty");
  expect(!top->full, "reset not full");
  expect_probes(0, 0, 0, 0, "reset");
}

void test_add_three() {
  reset();
  Rsp r = issue(OP_ADD, 1, 100);
  expect(r.ok, "add1 ok");
  expect_eq_u64(r.oid, 1, "add1 oid");
  expect_eq_u64(r.qty, 100, "add1 qty");
  expect_probes(1, 1, 100, 100, "after add1");

  r = issue(OP_ADD, 2, 50);
  expect(r.ok, "add2 ok");
  expect_probes(2, 1, 100, 150, "after add2");

  r = issue(OP_ADD, 3, 25);
  expect(r.ok, "add3 ok");
  expect_probes(3, 1, 100, 175, "after add3");
}

void test_match_partial() {
  reset();
  issue(OP_ADD, 1, 100);
  issue(OP_ADD, 2, 50);
  Rsp r = issue(OP_MATCH, 0, 30);
  expect(r.ok, "partial ok");
  expect_eq_u64(r.oid, 1, "partial oid");
  expect_eq_u64(r.qty, 30, "partial qty");
  expect_probes(2, 1, 70, 120, "after partial");
}

void test_match_exact_head() {
  reset();
  issue(OP_ADD, 1, 100);
  issue(OP_ADD, 2, 50);
  issue(OP_ADD, 3, 25);
  Rsp r = issue(OP_MATCH, 0, 100);
  expect(r.ok, "exact ok");
  expect_eq_u64(r.oid, 1, "exact oid");
  expect_eq_u64(r.qty, 100, "exact qty");
  expect_probes(2, 2, 50, 75, "after exact");
}

void test_match_over_head() {
  reset();
  issue(OP_ADD, 1, 10);
  issue(OP_ADD, 2, 10);
  Rsp r = issue(OP_MATCH, 0, 25);
  expect(r.ok, "over-head ok");
  expect_eq_u64(r.oid, 1, "over-head oid");
  expect_eq_u64(r.qty, 10, "over-head fills head only");
  expect_probes(1, 2, 10, 10, "after over-head");
}

void test_cancel_middle() {
  reset();
  issue(OP_ADD, 1, 10);
  issue(OP_ADD, 2, 20);
  issue(OP_ADD, 3, 30);
  Rsp r = issue(OP_CANCEL, 2, 0);
  expect(r.ok, "cancel middle ok");
  expect_eq_u64(r.oid, 2, "cancel middle oid");
  expect_eq_u64(r.qty, 20, "cancel middle qty");
  expect_probes(2, 1, 10, 40, "after cancel middle");
  r = issue(OP_CANCEL, 1, 0);
  expect(r.ok, "cancel new head");
  expect_probes(1, 3, 30, 30, "after cancel new head");
}

void test_cancel_head_and_tail() {
  reset();
  issue(OP_ADD, 1, 10);
  issue(OP_ADD, 2, 20);
  issue(OP_ADD, 3, 30);
  Rsp r = issue(OP_CANCEL, 1, 0);
  expect(r.ok, "cancel head ok");
  expect_probes(2, 2, 20, 50, "after cancel head");
  r = issue(OP_CANCEL, 3, 0);
  expect(r.ok, "cancel tail ok");
  expect_eq_u64(r.qty, 30, "cancel tail qty");
  expect_probes(1, 2, 20, 20, "after cancel tail");
}

void test_cancel_missing() {
  reset();
  issue(OP_ADD, 1, 10);
  Rsp r = issue(OP_CANCEL, 99, 0);
  expect(!r.ok, "cancel missing rejected");
  expect_probes(1, 1, 10, 10, "after cancel missing");
}

void test_rejects() {
  reset();
  Rsp r = issue(OP_MATCH, 0, 10);
  expect(!r.ok, "match empty rejected");
  r = issue(OP_ADD, 1, 0);
  expect(!r.ok, "add qty0 rejected");
  expect(top->empty, "still empty after qty0 add");
  issue(OP_ADD, 1, 10);
  r = issue(OP_MATCH, 0, 0);
  expect(!r.ok, "match qty0 rejected");
  expect_probes(1, 1, 10, 10, "after match qty0");
}

void test_full() {
  reset();
  for (int i = 0; i < MAX_ORDERS; i++) {
    Rsp r = issue(OP_ADD, 100 + i, 1);
    expect(r.ok, "fill add ok");
  }
  expect(top->full, "level full");
  expect_eq_u64(top->depth, MAX_ORDERS, "full depth");
  expect_eq_u64(top->total_qty, MAX_ORDERS, "full total");
  Rsp r = issue(OP_ADD, 999, 1);
  expect(!r.ok, "17th add rejected");
  expect(top->full, "still full");
  r = issue(OP_CANCEL, 100, 0);
  expect(r.ok, "cancel makes room");
  expect(!top->full, "not full after cancel");
  r = issue(OP_ADD, 200, 5);
  expect(r.ok, "add after cancel ok");
  expect_eq_u64(top->depth, MAX_ORDERS, "full again");
  expect_eq_u64(top->head_oid, 101, "oldest remaining is 101");
}

void test_drain() {
  reset();
  issue(OP_ADD, 1, 10);
  issue(OP_ADD, 2, 10);
  issue(OP_ADD, 3, 10);
  Rsp r = issue(OP_MATCH, 0, 10);
  expect_eq_u64(r.oid, 1, "drain 1");
  r = issue(OP_MATCH, 0, 10);
  expect_eq_u64(r.oid, 2, "drain 2");
  r = issue(OP_MATCH, 0, 10);
  expect_eq_u64(r.oid, 3, "drain 3");
  expect(top->empty, "drained empty");
  r = issue(OP_MATCH, 0, 10);
  expect(!r.ok, "match after drain rejected");
}

}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top = new Vprice_level_fifo;

  test_reset_empty();
  test_add_three();
  test_match_partial();
  test_match_exact_head();
  test_match_over_head();
  test_cancel_middle();
  test_cancel_head_and_tail();
  test_cancel_missing();
  test_rejects();
  test_full();
  test_drain();

  delete top;

  if (errors) {
    std::cerr << "FAILED " << errors << " of " << checks << " checks\n";
    return 1;
  }
  std::cout << "PASSED " << checks << " checks\n";
  return 0;
}
