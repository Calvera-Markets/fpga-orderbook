#include <iostream>
#include <string>

#include "Vtick_array.h"
#include "verilated.h"

namespace {
int errors = 0;
Vtick_array *top = nullptr;
void fail(const std::string &m) { std::cerr << "FAIL: " << m << "\n"; errors++; }
}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top = new Vtick_array;
  top->base = 100;
  top->used = 0b011;
  top->px[0] = 100;
  top->px[1] = 105;
  for (int i = 2; i < 8; i++) top->px[i] = 0;
  top->probe = 100;
  top->eval();
  if (!top->in_window || !top->hit || top->slot != 0) fail("100 is slot 0");
  top->probe = 105;
  top->eval();
  if (!top->hit || top->slot != 1) fail("105 is a different queue");
  top->probe = 200;
  top->eval();
  if (top->in_window || top->hit) fail("200 is outside the window");
  if (errors == 0) std::cout << "tick_array: passed\n";
  delete top;
  return errors == 0 ? 0 : 1;
}
