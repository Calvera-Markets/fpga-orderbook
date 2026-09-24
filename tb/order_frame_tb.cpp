#include <cstdint>
#include <iostream>
#include <string>

#include "Vorder_frame.h"
#include "verilated.h"

namespace {

constexpr int N = 4;
int errors = 0;
int checks = 0;
Vorder_frame *top = nullptr;

void fail(const std::string &msg) {
  std::cerr << "FAIL: " << msg << "\n";
  errors++;
}

void expect(bool cond, const std::string &what) {
  checks++;
  if (!cond) fail(what);
}

bool bit(uint32_t v, int i) { return ((v >> i) & 1u) != 0; }

void tick() {
  top->clk = 0;
  top->eval();
  top->clk = 1;
  top->eval();
}

void reset() {
  top->rst_n = 0;
  top->word_valid = 0;
  top->word_op = 0;
  top->word_side = 0;
  top->word_symbol = 0;
  top->word_price = 0;
  top->word_qty = 0;
  top->word_oid = 0;
  top->cmd_ready = (1u << N) - 1u;
  top->clk = 0;
  top->eval();
  tick();
  top->rst_n = 1;
  top->eval();
}

void set_word(int sym, int side, uint32_t px, uint32_t qty, uint64_t oid) {
  top->word_op = 0;
  top->word_side = side;
  top->word_symbol = sym;
  top->word_price = px;
  top->word_qty = qty;
  top->word_oid = oid;
}

void test_two_words_two_cycles() {
  reset();
  set_word(0, 0, 10, 4, 1);
  top->word_valid = 1;
  top->eval();
  expect(top->word_ready, "first word accepted");
  expect(bit(top->cmd_valid, 0) && !bit(top->cmd_valid, 1), "cycle 1 drives slice 0 only");
  expect(top->cmd_price[0] == 10 && top->cmd_qty[0] == 4 && top->cmd_oid[0] == 1, "slice 0 fields");
  tick();
  set_word(1, 1, 20, 5, 2);
  top->eval();
  expect(top->word_ready, "second word accepted the next cycle");
  expect(bit(top->cmd_valid, 1) && !bit(top->cmd_valid, 0), "cycle 2 drives slice 1 only");
  expect(top->cmd_price[1] == 20 && top->cmd_oid[1] == 2, "slice 1 fields");
  tick();
  top->word_valid = 0;
}

void test_busy_slice_does_not_hold_the_other() {
  reset();
  top->cmd_ready = ((1u << N) - 1u) & ~1u;
  set_word(0, 0, 10, 1, 9);
  top->word_valid = 1;
  top->eval();
  expect(!top->word_ready, "busy slice holds its own word");
  expect(top->cmd_valid == 0, "no slice port is driven while the word waits");
  expect(bit(top->cmd_ready, 1), "other slice stays ready");
  set_word(1, 1, 30, 1, 8);
  top->eval();
  expect(top->word_ready, "a word for the free slice is accepted");
  expect(bit(top->cmd_valid, 1) && !bit(top->cmd_valid, 0), "only the free slice sees the word");
}

}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top = new Vorder_frame;
  test_two_words_two_cycles();
  test_busy_slice_does_not_hold_the_other();
  if (errors == 0) std::cout << "order_frame: " << checks << " checks passed\n";
  else std::cout << "order_frame: " << errors << " errors in " << checks << " checks\n";
  delete top;
  return errors == 0 ? 0 : 1;
}
