#include <cstdint>
#include <iostream>
#include <string>

#include "Vlevel_table.h"
#include "verilated.h"

namespace {

int errors = 0;
int checks = 0;
Vlevel_table *top = nullptr;

void fail(const std::string &msg) {
  std::cerr << "FAIL: " << msg << "\n";
  errors++;
}

void expect(bool cond, const std::string &what) {
  checks++;
  if (!cond) fail(what);
}

void expect_eq(uint32_t got, uint32_t want, const std::string &what) {
  checks++;
  if (got != want) {
    fail(what + " got " + std::to_string(got) + " want " + std::to_string(want));
  }
}

void load_two() {
  top->used = 0b011;
  top->px[0] = 100;
  top->px[1] = 105;
  for (int i = 2; i < 8; i++) top->px[i] = 0;
}

}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);
  top = new Vlevel_table;
  load_two();
  top->probe = 100;
  top->eval();
  expect(top->in_window, "100 in window");
  expect(top->hit, "100 hits");
  expect_eq(top->slot, 0, "100 is slot 0");
  top->probe = 105;
  top->eval();
  expect(top->hit, "105 hits");
  expect_eq(top->slot, 1, "105 is a different queue");
  top->probe = 101;
  top->eval();
  expect(top->in_window, "101 in window");
  expect(!top->hit, "empty price misses");
  top->probe = 200;
  top->eval();
  expect(!top->in_window, "200 is outside the window");
  expect(!top->hit, "outside window is not a level");
  if (errors == 0) {
    std::cout << "level_table: " << checks << " checks passed\n";
  } else {
    std::cout << "level_table: " << errors << " errors\n";
  }
  delete top;
  return errors == 0 ? 0 : 1;
}
