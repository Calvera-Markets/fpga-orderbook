#include <cstdint>
#include <iostream>
#include <string>

#include "Vframe_top.h"
#include "verilated.h"

namespace {

constexpr int N = 4;
int errors = 0;
int checks = 0;
int commands = 0;
Vframe_top *top = nullptr;

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
  if (top->cmd_valid != 0) commands++;
  top->clk = 0;
  top->eval();
  top->clk = 1;
  top->eval();
}

void reset() {
  commands = 0;
  top->rst_n = 0;
  top->word_valid = 0;
  top->word_session = 0;
  top->word_seq = 1;
  top->word_kill = 0;
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

void set_word(int session, uint32_t seq, int sym, int side, uint32_t px, uint32_t qty, uint64_t oid) {
  top->word_session = session;
  top->word_seq = seq;
  top->word_op = 0;
  top->word_side = side;
  top->word_symbol = sym;
  top->word_price = px;
  top->word_qty = qty;
  top->word_oid = oid;
}

void test_two_words_two_cycles() {
  reset();
  set_word(0, 1, 0, 0, 10, 4, 1);
  top->word_valid = 1;
  top->eval();
  expect(top->word_ready, "first word accepted");
  expect(bit(top->cmd_valid, 0) && !bit(top->cmd_valid, 1), "cycle 1 drives slice 0 only");
  expect(top->cmd_price[0] == 10 && top->cmd_qty[0] == 4 && top->cmd_oid[0] == 1, "slice 0 fields");
  tick();
  set_word(1, 1, 1, 1, 20, 5, 2);
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
  set_word(0, 1, 0, 0, 10, 1, 9);
  top->word_valid = 1;
  top->eval();
  expect(!top->word_ready, "busy slice holds its own word");
  expect(top->cmd_valid == 0, "no slice port is driven while the word waits");
  expect(bit(top->cmd_ready, 1), "other slice stays ready");
  set_word(1, 1, 1, 1, 30, 1, 8);
  top->eval();
  expect(top->word_ready, "a word for the free slice is accepted");
  expect(bit(top->cmd_valid, 1) && !bit(top->cmd_valid, 0), "only the free slice sees the word");
}

void test_risk_and_kill() {
  reset();
  int before = commands;
  set_word(0, 1, 0, 0, 10, 11, 1);
  top->word_valid = 1;
  top->eval();
  expect(top->reject_valid, "qty above the cap is a reject");
  expect(top->cmd_valid == 0, "cap reject does not drive a slice");
  tick();
  expect(commands == before, "cap reject leaves the book port alone");
  set_word(0, 1, 0, 0, 10, 1, 1);
  top->eval();
  expect(bit(top->cmd_valid, 0), "legal qty still uses seq 1");
  tick();
  set_word(0, 2, 0, 0, 10, 1, 2);
  top->word_kill = 1;
  top->eval();
  expect(top->reject_valid, "kill word does not trade");
  expect(top->cmd_valid == 0, "kill does not drive a slice");
  tick();
  top->word_kill = 0;
  set_word(0, 2, 0, 0, 10, 1, 3);
  top->eval();
  expect(top->reject_valid, "later word from the killed session is a reject");
  expect(top->cmd_valid == 0, "killed session stays off the book");
  set_word(1, 1, 1, 1, 20, 1, 4);
  top->eval();
  expect(!top->reject_valid && bit(top->cmd_valid, 1), "another session still trades");
}

void test_sequence_gap_does_not_enter() {
  reset();
  set_word(0, 1, 0, 0, 10, 1, 1);
  top->word_valid = 1;
  top->eval();
  expect(bit(top->cmd_valid, 0), "seq 1 enters");
  tick();
  set_word(0, 2, 0, 0, 11, 1, 2);
  top->eval();
  expect(bit(top->cmd_valid, 0), "seq 2 enters");
  expect(!top->reject_valid, "seq 2 is not a reject");
  tick();
  int before = commands;
  set_word(0, 4, 0, 0, 99, 1, 4);
  top->eval();
  expect(top->reject_valid, "seq 4 is a gap");
  expect(top->cmd_valid == 0, "gap does not drive a slice");
  tick();
  expect(commands == before, "gap does not change the book port");
  set_word(0, 3, 0, 0, 12, 1, 3);
  top->eval();
  expect(!top->reject_valid, "seq 3 is still next");
  expect(bit(top->cmd_valid, 0) && top->cmd_price[0] == 12, "seq 3 enters");
}

}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top = new Vframe_top;
  test_two_words_two_cycles();
  test_busy_slice_does_not_hold_the_other();
  test_sequence_gap_does_not_enter();
  test_risk_and_kill();
  if (errors == 0) std::cout << "order_frame: " << checks << " checks passed\n";
  else std::cout << "order_frame: " << errors << " errors in " << checks << " checks\n";
  delete top;
  return errors == 0 ? 0 : 1;
}
