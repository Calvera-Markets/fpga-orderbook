#include <iostream>
#include <string>

#include "Void_hash.h"
#include "verilated.h"

namespace {
int errors = 0;
Void_hash *top = nullptr;

void fail(const std::string &m) { std::cerr << "FAIL: " << m << "\n"; errors++; }
void tick() {
  top->clk = 0; top->eval();
  top->clk = 1; top->eval();
}
void reset() {
  top->rst_n = 0; top->wr_en = 0; top->wr_clear = 0;
  top->wr_oid = 0; top->wr_slice = 0; top->wr_price = 0; top->wr_slot = 0;
  top->rd_oid = 0;
  tick(); top->rst_n = 1; tick();
}
}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top = new Void_hash;
  reset();
  top->wr_en = 1; top->wr_oid = 7; top->wr_slice = 1; top->wr_price = 10; top->wr_slot = 0;
  tick();
  top->wr_en = 0;
  top->rd_oid = 7; top->eval();
  if (!top->hit || top->rd_slice != 1 || top->rd_price != 10 || top->rd_slot != 0)
    fail("hit place");
  top->rd_oid = 8; top->eval();
  if (top->hit) fail("unknown id");
  top->wr_en = 1; top->wr_oid = 23; top->wr_slice = 2; top->wr_price = 11; top->wr_slot = 1;
  tick();
  top->wr_en = 0;
  top->rd_oid = 7; top->eval();
  if (!top->hit || top->rd_slice != 1) fail("7 survived the same nibble");
  top->rd_oid = 23; top->eval();
  if (!top->hit || top->rd_slice != 2 || top->rd_price != 11) fail("23 is the next bucket");
  top->wr_clear = 1; top->wr_oid = 7; tick(); top->wr_clear = 0;
  top->rd_oid = 7; top->eval();
  if (top->hit) fail("deleted id");
  top->rd_oid = 23; top->eval();
  if (!top->hit) fail("23 remains");
  if (errors == 0) std::cout << "oid_hash: passed\n";
  delete top;
  return errors == 0 ? 0 : 1;
}
