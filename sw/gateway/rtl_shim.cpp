// C ABI around Verilated slice_engine. Loaded by rtl_engine.py.
// One symbol per slice: slice i owns symbol i unless the host reassigns it.

#include <cstdint>
#include <vector>

#include "Vslice_engine.h"
#include "verilated.h"

double sc_time_stamp() { return 0; }

namespace {

constexpr int N_SLICES = 4;
constexpr int MAX_TICKS = 10000;

struct Fill {
  uint64_t maker;
  uint64_t taker;
  uint32_t price;
  uint32_t qty;
};

struct Handle {
  Vslice_engine *top;
  std::vector<Fill> fills;
};

void harvest(Handle *h) {
  for (int s = 0; s < N_SLICES; s++) {
    if ((h->top->evt_valid >> s) & 1) {
      h->fills.push_back(Fill{h->top->evt_maker_oid[s], h->top->evt_taker_oid[s],
                              h->top->evt_price[s], h->top->evt_qty[s]});
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
  h->top->cfg_valid = 0;
  h->top->cfg_slice = 0;
  h->top->cfg_symbol = 0;
  h->top->cfg_algo = 0;
  h->top->cmd_valid = 0;
  h->top->cmd_op = 0;
  h->top->cmd_side = 0;
  h->top->evt_ready = (1u << N_SLICES) - 1u;
  for (int s = 0; s < N_SLICES; s++) {
    h->top->cmd_price[s] = 0;
    h->top->cmd_qty[s] = 0;
    h->top->cmd_oid[s] = 0;
  }
  for (int i = 0; i < 4; i++) {
    tick(h);
  }
  h->top->rst_n = 1;
  tick(h);
}

int slice_of(uint16_t symbol) {
  if (symbol >= N_SLICES) {
    return -1;
  }
  return static_cast<int>(symbol);
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
  h->top = new Vslice_engine;
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
  const int sl = slice_of(symbol);
  if (sl < 0) {
    return -1;
  }
  h->fills.clear();
  h->top->cmd_op = (h->top->cmd_op & ~(1u << sl)) | (static_cast<unsigned>(op) << sl);
  h->top->cmd_side = (h->top->cmd_side & ~(1u << sl)) | (static_cast<unsigned>(side) << sl);
  h->top->cmd_price[sl] = price;
  h->top->cmd_qty[sl] = qty;
  h->top->cmd_oid[sl] = oid;
  int guard = 0;
  while (!((h->top->cmd_ready >> sl) & 1) && guard++ < MAX_TICKS) {
    tick(h);
  }
  if (!((h->top->cmd_ready >> sl) & 1)) {
    return -1;
  }
  h->top->cmd_valid = static_cast<unsigned>(1u << sl);
  tick(h);
  h->top->cmd_valid = 0;

  guard = 0;
  while (!((h->top->rsp_valid >> sl) & 1) && guard++ < MAX_TICKS) {
    tick(h);
  }
  if (!((h->top->rsp_valid >> sl) & 1)) {
    return -1;
  }
  rsp->ok = (h->top->rsp_ok >> sl) & 1;
  rsp->oid = h->top->rsp_oid[sl];
  rsp->filled = h->top->rsp_filled_qty[sl];
  rsp->rest = h->top->rsp_rest_qty[sl];
  rsp->unrested = h->top->rsp_unrested_qty[sl];
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
  const int sl = slice_of(symbol);
  if (sl < 0) {
    *bid_v = 0;
    *bid_px = 0;
    *bid_qty = 0;
    *ask_v = 0;
    *ask_px = 0;
    *ask_qty = 0;
    return;
  }
  h->top->eval();
  *bid_v = (h->top->bbo_bid_valid >> sl) & 1;
  *bid_px = h->top->bbo_bid_px[sl];
  *bid_qty = h->top->bbo_bid_qty[sl];
  *ask_v = (h->top->bbo_ask_valid >> sl) & 1;
  *ask_px = h->top->bbo_ask_px[sl];
  *ask_qty = h->top->bbo_ask_qty[sl];
}

}  // extern "C"
