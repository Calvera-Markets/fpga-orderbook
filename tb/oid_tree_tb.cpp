#include <iostream>
#include <string>

#include "Void_tree.h"
#include "verilated.h"

namespace {
int errors = 0;
Void_tree *top = nullptr;
void fail(const std::string &m) { std::cerr << "FAIL: " << m << "\n"; errors++; }
void tick() { top->clk = 0; top->eval(); top->clk = 1; top->eval(); }
void put(uint64_t oid, int slice) {
  top->wr_en = 1; top->wr_oid = oid; top->wr_slice = slice;
  top->wr_price = oid; top->wr_slot = 0; tick(); top->wr_en = 0;
}
}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top = new Void_tree;
  top->rst_n = 0; top->wr_en = 0; top->rd_oid = 0; tick();
  top->rst_n = 1; tick();
  put(1, 0);
  put(5, 1);
  top->rd_oid = 1; top->eval();
  if (!top->hit || top->visits != 1) fail("root is one visit");
  top->rd_oid = 5; top->eval();
  if (!top->hit || top->rd_slice != 1 || top->visits < 2) fail("second node costs two visits");
  if (errors == 0) std::cout << "oid_tree: passed\n";
  delete top;
  return errors == 0 ? 0 : 1;
}
