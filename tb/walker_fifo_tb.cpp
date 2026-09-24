#include <iostream>
#include "Vwalker_fifo.h"
#include "verilated.h"

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  auto *top = new Vwalker_fifo;
  top->rst_n = 0; top->start = 0; top->clk = 0; top->eval(); top->clk = 1; top->eval();
  top->rst_n = 1;
  top->take_qty = 2; top->oid0 = 1; top->qty0 = 1; top->oid1 = 2; top->qty1 = 3;
  top->start = 1; top->clk = 0; top->eval(); top->clk = 1; top->eval();
  int bad = !(top->done && top->fill0 == 1 && top->fill1 == 1);
  if (bad) std::cerr << "FAIL walker_fifo\n";
  else std::cout << "walker_fifo: passed\n";
  delete top;
  return bad;
}
