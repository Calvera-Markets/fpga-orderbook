# Pattern 4 — commit stream

Target: **K partitioned matcher pipelines**. Each pipeline owns a disjoint set of symbols, has its own book RAM and its own FSM, and sees a FIFO of orders for only those symbols. Same `symbol_id` always hashes to the same pipeline. That is T7 partitions / LMAX shards / “matcher pipelines in parallel,” not N cloned tickers.

Background: [multi-pipeline.md](multi-pipeline.md) pattern 4, [industry-analysis.md](industry-analysis.md).

We are here today: one `one_symbol_book` FSM, one Python `Book`, gateway with no symbol field.

```
today                         Pattern 4
------                        ---------
LIMIT BUY px qty oid          LIMIT BUY <sym> px qty oid
        |                              |
        v                              v
   one Book                    hash(sym) → pipe k
                               pipe k: private books + FSM
                               seq / WAL / BBO per pipe
```

Each commit below is a checkpoint: `make test` (or the listed command) is green, and the repo is reviewable on its own. Short titles match the style of `orderbook`. Do them in order unless a note says two can land in parallel.

Frozen for this series (change here before changing code):

| Knob | v1 value |
|---|---|
| `symbol_id` | `u16`, dense integer; tickers only at the gateway |
| `K` | software: 2; RTL: parameter default 2 |
| Map | `pipe = symbol_id % K` |
| Books per pipe | software unbounded dict; RTL: `N_SYMBOLS_PER_PIPE = 4` (raise later) |
| Sequence | per pipeline, not venue-wide |
| WAL | one JSONL file with `symbol` + `pipe` + per-pipe `seq` (split files later) |
| Cancel | `CANCEL <oid>` via an oid map; client does not repeat symbol |
| Issue | at most one in-flight order **per pipe**; pipes independent |

`K=1` is a degenerate Pattern 4 (one partition). Commits 1–8 are that partition done properly (many symbols, one FSM). Commits 9–14 duplicate it.

---

## Commit 1 — `pattern4 spec`

**Why.** Freeze the hash, widths, and “same symbol ⇒ same pipe” rule before any code forks.

**Files**

- `design/pattern-4.md` — architecture of the partition (this file stays the *schedule*)
- `design/messages.md` — add `symbol_id`, `pipe_id`
- `design/decisions.md` — Pattern 4 row
- `design/README.md` — index

**Depends on.** Nothing new.

**Done when.** Spec says: hash function, `CANCEL` needs oid map, seq per pipe, no global sequence. No RTL yet.

---

## Commit 2 — `books by symbol`

**Why.** The golden model becomes “a venue,” not one instrument.

**Files**

- `sw/golden/venue.py` — `class Venue: books: dict[int, Book]`; `limit(sym, side, px, qty, oid)`, `cancel` still scans or fails until commit 3
- `sw/golden/test_venue.py` — two symbols, no cross-book fill; BBO is per symbol

**Depends on.** Commit 1 (symbol is an int).

**Done when.** `python3 -m unittest test_venue` : `LIMIT` on symbol 1 never fills an order on symbol 2.

**Checkpoint.** `make golden` still passes old book tests.

---

## Commit 3 — `oid map`

**Why.** Pattern 4 cancel cannot ask the client for `symbol`. ITCH-style cancel is id-only. Partitioning needs `oid → (symbol, pipe)` so the gateway knows which pipe to send.

**Files**

- `sw/golden/oid_map.py` — insert on rest, delete on full fill / cancel
- `sw/golden/venue.py` — use the map
- `sw/golden/test_oid_map.py` — cancel without symbol; unknown oid NAK; fill removes oid

**Depends on.** Commit 2.

**Done when.** `CANCEL 7` finds the book even if two symbols are live.

---

## Commit 4 — `gateway symbol`

**Why.** Wire format grows a symbol token; WAL records it; replay rebuilds the right book.

**Files**

- `sw/gateway/protocol.py` — `LIMIT BUY <sym> <px> <qty> <oid>`; `BBO` / `BBO <sym>`
- `sw/gateway/exchange.py` — wrap `Venue`; log `symbol` on `cmd`
- `sw/gateway/test_gateway.py` — old tests updated; replay two symbols
- `design/gateway.md` — protocol table

**Depends on.** Commits 2–3.

**Done when.**

```
LIMIT BUY 1 100 10 1
LIMIT SELL 2 100 10 2
```

No fill. Restart on the same WAL restores both BBOs. `CANCEL 1` works.

**Note.** `sym` in the text protocol is the integer id for v1 (`1`, `2`). Ticker strings (`BTC`) are a later commit if we want them; they must not enter RTL.

---

## Commit 5 — `pipe hash software`

**Why.** First real Pattern 4: two software partitions, disjoint books, independent seq.

**Files**

- `sw/golden/partition.py` — `pipe = symbol_id % K`, `K=2`; array of `Venue` (or `Book` dicts)
- `sw/golden/test_partition.py` — symbols 0 and 1 go to different pipes; two limits on *different* pipes can be applied in either order and stay correct; two limits on the *same* symbol stay ordered
- `sw/gateway/exchange.py` — stamp `pipe` + per-pipe `seq` into WAL

**Depends on.** Commit 4.

**Done when.** WAL lines for symbol 0 and 1 show `pipe: 0` and `pipe: 1` and two `seq` counters. Replay still works.

**Checkpoint.** You can demo Pattern 4 without any new Verilog.

---

## Commit 6 — `egress merge software`

**Why.** Two pipes emit fills independently. The CLI still prints a single stream.

**Files**

- `sw/gateway/merge.py` — concat per-command (software is sync) or tag `pipe=`
- protocol replies: `FILL ...` unchanged; optional `pipe=` field for debug
- tests: one LIMIT that is not a cross stays one OK line; two sequential commands on two pipes stay in submit order at the CLI (submit order ≠ match order across pipes — document that)

**Depends on.** Commit 5.

**Done when.** Docs state: **no venue-wide match order**. Client-visible order is submit order at the gateway; match order is per pipe.

---

## Commit 7 — `rtl symbol package`

**Why.** Widths shared by RTL and C++ TB.

**Files**

- `rtl/pkg/exch_pkg.sv` — `SYMBOL_W=16`, `N_PIPES=2`, `N_SYMS_PER_PIPE=4`, `PIPE_W=$clog2(N_PIPES)`
- `design/messages.md` — book command gains `cmd_symbol`

**Depends on.** Commit 1.

**Done when.** `make sim-fifo` and `make sim-book` still pass (package lint). Can land in parallel with commits 2–6.

---

## Commit 8 — `rtl multi-symbol bank`

**Why.** One partition = one FSM + many books. This *is* a Pattern 4 pipeline with `K=1`. Reused as the body of each pipe later.

**Files**

- `rtl/book/symbol_bank.sv` — `cmd_symbol` selects among `N_SYMS_PER_PIPE` instances of `one_symbol_book` **or** muxed memory in front of one instance. v1: **generate** `N` `one_symbol_book` inside the bank, cmd_valid only to the selected one. Simple, matches “private RAM per book,” burns LUTs; fine for N=4.
- `tb/symbol_bank_tb.cpp`
- `sw/golden` already has the oracle
- `Makefile` — `make sim-bank`

**Depends on.** Commit 7. Golden from 2–3.

**Done when.** Two symbols in one bank: no cross-book fill; cancel by oid requires the TB to pass symbol *or* the bank has an oid CAM. v1 TB passes `cmd_symbol` on cancel; oid CAM is commit 11.

**Checkpoint.** `make sim-bank` + existing tests.

---

## Commit 9 — `rtl pipe router`

**Why.** Pattern 4 on the chip: hash, demux, K banks.

**Files**

- `rtl/book/pipe_router.sv` — `pipe = cmd_symbol[PIPE_W-1:0]` if K is power of two (`% K`)
- `rtl/book/partitioned_engine.sv` — `generate` `N_PIPES` of `symbol_bank`; fan-out `cmd_*` by pipe; `cmd_ready` is ready of the *selected* pipe
- `tb/partitioned_engine_tb.cpp` — issue on pipe 0 and pipe 1 back-to-back; both can be busy at once
- `Makefile` — `make sim-part`

**Depends on.** Commit 8.

**Done when.**

1. Symbol 0 and 1 process overlapping in time (`cmd_ready` high for pipe B while pipe A is matching).
2. Two orders on symbol 0 never overlap (second waits `cmd_ready` of pipe 0).
3. Fills tagged with `symbol` (and pipe in TB probes).

This is the first hardware checkpoint that *is* Pattern 4.

---

## Commit 10 — `parallel issue test`

**Why.** Prove the point of K>1, not just the mux.

**Files**

- `tb/partitioned_engine_tb.cpp` — scenario: rest ask on sym 0, rest bid on sym 1, then aggressive on each; count cycles vs K=1
- `design/pattern-4.md` — record the cycle counts so we do not “optimize” them away

**Depends on.** Commit 9.

**Done when.** Wall-clock cycles for two independent matches on two symbols is ~max(pipeA, pipeB), not sum, in the TB.

---

## Commit 11 — `rtl oid map`

**Why.** Hardware cancel without the TB cheating `cmd_symbol`.

**Files**

- `rtl/book/oid_map.sv` — simple table `MAX_LIVE_ORDERS` (e.g. 64): `{valid, oid, symbol, side, price}`
- wire into `symbol_bank` / `partitioned_engine`: LIMIT rest → insert; full fill / cancel → clear; CANCEL looks up symbol then routes
- golden `oid_map.py` is the oracle
- TB: `CANCEL oid` only

**Depends on.** Commit 9 (router must see symbol from the map, not the cmd).

**Done when.** Cancel of a resting order on pipe 1 does not require `cmd_symbol` from the client.

---

## Commit 12 — `gateway to pipes`

**Why.** Software mini-exchange drives the *idea* of K pipes (still Python banks, not Verilator). Optional: Verilator as a library later.

**Files**

- `sw/gateway/exchange.py` — use `partition.py` as the engine
- `BBO <sym>` in CLI
- tests for two-pipe replay

**Depends on.** Commits 5–6, 11 conceptually (oid map already in software from 3).

**Done when.** `make run` with two symbols shows independent books; WAL replay restores both pipes’ seq.

---

## Commit 13 — `docs + make test`

**Why.** One green button for the series.

**Files**

- `Makefile` — `sim-bank`, `sim-part` in `make test`
- `design/roadmap.md` — Pattern 4 is “now”
- `design/architecture.md` — diagram with hash → K banks
- `commands.md` — session log

**Depends on.** 9–12.

**Done when.** `make test` runs golden + fifo + book + bank + partitioned engine + gateway.

---

## Later commits (not this series)

Do not sneak these into 1–13.

| Title | Why later |
|---|---|
| `ticker strings` | `BTC` → id table in gateway only |
| `K=4` | Parameter bump + tests; no design change |
| `per-symbol scoreboard` | Overlap *different* symbols *inside* one pipe; Columbia trick; not required for Pattern 4 |
| `Verilator as .so` | Gateway loads `partitioned_engine` |
| `WAL file per pipe` | Split `data/pipe0.wal` |
| `bid∥ask issue` | Pattern 2, inside a pipe |
| `N cloned tickers` | Pattern 3 — rejected |
| synthesis / board | After sim is boring |

---

## Graph (what can overlap)

```
1 spec
├─ 2 books-by-symbol → 3 oid-map → 4 gateway-symbol → 5 pipe-hash-sw → 6 egress-merge-sw
│                                                      └──────────────→ 12 gateway-to-pipes
└─ 7 rtl-package → 8 symbol-bank → 9 pipe-router → 10 parallel-issue-test → 11 rtl-oid-map
                                                                        ↓
                                                              13 docs + make test
```

Software track (2–6, 12) and RTL track (7–11) meet at 13. Do not start 9 until 8 is green. Do not start 8 until 2’s tests exist (oracle).

---

## What “Pattern 4 done” looks like

```
              cmd_valid (one command)
                    |
                    v
             pipe = symbol % K
              /           \
         bank[0]         bank[1]      … each is N one_symbol_book
         FSM 0           FSM 1
         seq 0           seq 1
              \           /
               fills + BBO (tagged with symbol)
```

- Two symbols on different pipes match in parallel.
- Two orders on one symbol stay FIFO in that pipe.
- Restart from WAL restores every book.
- Still no DRAM, no board, no global sequence.
