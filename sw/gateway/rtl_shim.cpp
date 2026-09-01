// C ABI around Verilated partitioned_engine. Loaded by rtl_engine.py.

#include <cstdint>
#include <vector>

#include "Vpartitioned_engine.h"
#include "verilated.h"

double sc_time_stamp() { return 0; }

namespace {

constexpr int N_PIPES = 4;
constexpr int MAX_TICKS = 10000;

struct Fill {
  uint64_t maker;
  uint64_t taker;
  uint32_t price;
  uint32_t qty;
};

struct Handle {
  Vpartitioned_engine *top;
  std::vector<Fill> fills;
};

void harvest(Handle *h) {
  for (int p = 0; p < N_PIPES; p++) {
    if ((h->top->evt_valid >> p) & 1) {
      h->fills.push_back(Fill{h->top->evt_maker_oid[p], h->top->evt_taker_oid[p],
                              h->top->evt_price[p], h->top->evt_qty[p]});
    }
  }
}

void tick(Handle *h) {
  h->top->clk = 0;
  h->top->eval();
  h->top->clk = 1;
  h->top->eval();
  harvest(h);
}

void reset(Handle *h) {
  h->fills.clear();
  h->top->rst_n = 0;
  h->top->cmd_valid = 0;
  h->top->cmd_symbol = 0;
  h->top->cmd_op = 0;
  h->top->cmd_side = 0;
  h->top->cmd_price = 0;
  h->top->cmd_qty = 0;
  h->top->cmd_oid = 0;
  h->top->evt_ready = 1;
  for (int i = 0; i < 4; i++) {
    tick(h);
  }
  h->top->rst_n = 1;
  tick(h);
}

}  // namespace

extern "C" {

struct pe_fill {
  uint64_t maker;
  uint64_t taker;
  uint32_t price;
  uint32_t qty;
};

struct pe_rsp {
  uint8_t ok;
  uint64_t oid;
  uint32_t filled;
  uint32_t rest;
  uint32_t unrested;
  int nfill;
};

void *pe_new() {
  auto *h = new Handle;
  h->top = new Vpartitioned_engine;
  reset(h);
  return h;
}

void pe_free(void *p) {
  auto *h = static_cast<Handle *>(p);
  delete h->top;
  delete h;
}

int pe_issue(void *p, uint16_t symbol, uint8_t op, uint8_t side, uint32_t price,
             uint32_t qty, uint64_t oid, pe_rsp *rsp, pe_fill *fills, int max_fills) {
  auto *h = static_cast<Handle *>(p);
  h->fills.clear();
  h->top->cmd_symbol = symbol;
  int guard = 0;
  while (!h->top->cmd_ready && guard++ < MAX_TICKS) {
    tick(h);
  }
  if (!h->top->cmd_ready) {
    return -1;
  }
  h->top->cmd_valid = 1;
  h->top->cmd_symbol = symbol;
  h->top->cmd_op = op;
  h->top->cmd_side = side;
  h->top->cmd_price = price;
  h->top->cmd_qty = qty;
  h->top->cmd_oid = oid;
  tick(h);
  h->top->cmd_valid = 0;

  const int pipe = static_cast<int>(symbol) % N_PIPES;
  guard = 0;
  while (!((h->top->rsp_valid >> pipe) & 1) && guard++ < MAX_TICKS) {
    tick(h);
  }
  if (!((h->top->rsp_valid >> pipe) & 1)) {
    return -1;
  }
  rsp->ok = (h->top->rsp_ok >> pipe) & 1;
  rsp->oid = h->top->rsp_oid[pipe];
  rsp->filled = h->top->rsp_filled_qty[pipe];
  rsp->rest = h->top->rsp_rest_qty[pipe];
  rsp->unrested = h->top->rsp_unrested_qty[pipe];
  const int n = static_cast<int>(h->fills.size());
  rsp->nfill = n < max_fills ? n : max_fills;
  for (int i = 0; i < rsp->nfill; i++) {
    fills[i].maker = h->fills[static_cast<size_t>(i)].maker;
    fills[i].taker = h->fills[static_cast<size_t>(i)].taker;
    fills[i].price = h->fills[static_cast<size_t>(i)].price;
    fills[i].qty = h->fills[static_cast<size_t>(i)].qty;
  }
  return 0;
}

void pe_bbo(void *p, uint16_t symbol, uint8_t *bid_v, uint32_t *bid_px, uint32_t *bid_qty,
            uint8_t *ask_v, uint32_t *ask_px, uint32_t *ask_qty) {
  auto *h = static_cast<Handle *>(p);
  h->top->cmd_valid = 0;
  h->top->cmd_op = 0;
  h->top->cmd_symbol = symbol;
  h->top->eval();
  const int pipe = static_cast<int>(symbol) % N_PIPES;
  *bid_v = (h->top->bbo_bid_valid >> pipe) & 1;
  *bid_px = h->top->bbo_bid_px[pipe];
  *bid_qty = h->top->bbo_bid_qty[pipe];
  *ask_v = (h->top->bbo_ask_valid >> pipe) & 1;
  *ask_px = h->top->bbo_ask_px[pipe];
  *ask_qty = h->top->bbo_ask_qty[pipe];
}

}  // extern "C"
