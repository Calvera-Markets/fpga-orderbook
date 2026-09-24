#include <iostream>
#include <string>

#include "Vtouch_tile.h"
#include "verilated.h"

namespace {
int errors = 0;
Vtouch_tile *top = nullptr;

void fail(const std::string &m) {
  std::cerr << "FAIL: " << m << "\n";
  errors++;
}

void tick() {
  top->clk = 0;
  top->eval();
  top->clk = 1;
  top->eval();
}
}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top = new Vtouch_tile;
  top->rst_n = 0;
  top->set_valid = 0;
  top->set_price = 0;
  top->probe = 100;
  tick();
  top->rst_n = 1;
  tick();
  if (!top->hit) fail("empty line is a hit");
  top->set_price = 100;
  top->set_valid = 1;
  tick();
  top->set_valid = 0;
  top->probe = 100;
  top->eval();
  if (!top->hit) fail("touch price hits");
  top->probe = 105;
  top->eval();
  if (top->hit) fail("other price misses");
  if (errors == 0) std::cout << "touch_tile: passed\n";
  delete top;
  return errors == 0 ? 0 : 1;
}
