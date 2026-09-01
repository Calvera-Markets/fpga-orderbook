# Industry analysis: how matching engines and FPGA books are actually built

Research snapshot for exch-core (2026-09-01). This is not a product brochure. It is what production exchanges, FPGA vendors, patents, and hardware papers do — and what we should copy or ignore for **multi-symbol**.

Our current stack already matches the professional *split*: FPGA (or a cycle-accurate stand-in) owns the matching hot path; software owns sessions, WAL, and replay. Multi-symbol is **routing and memory**, not “clone the matcher N times.”

## 1. Two FPGA jobs that look alike and are not

Marketing pages mix these. They are different chips.

| Job | Customer | FPGA state | Correctness bar |
|---|---|---|---|
| **Matching** (this repo) | The exchange | Resting orders, match, acks, trades | Bit-exact price-time; same inputs → same fills |
| **Book building** | HFT firm / ticker plant | A *copy* of the venue L2 from the public feed | Fast BBO/depth; may drop or coarsen |

Examples of book-builders, not matchers:

- **Enyx nxAccess** — FPGA feed handler + algo sandbox. Up to **8,000** symbols, A/B arbitration, ~**2 MB** in-FPGA order storage, **16k+** preloaded order buffers. Normalized books *and* a raw pattern-matcher bypass. This is “see the market and fire a preloaded order,” not “be the exchange.”
- **NovaSparks** — full US equities book-build on one 2U: **15 markets × ~13k symbols**, FPGA book latency cited **&lt; 500 ns**. Options: custom **QDR** for ~**200k** instruments/FPGA, **DDR** for another ~300k, multi-FPGA for full OPRA (~2.2M symbols).
- **Algo-Logic CME F&O book** — MDP 3.0 parser, real + implied books, L2 snapshots to 10 levels, latency advertised **independent of instrument count** (the point of hashing + bounded pipelines).

A matching CLOB is smaller, hotter, and must not approximate. Book-builders optimize *instrument count* and wire-to-BBO. Matchers optimize *deterministic match + cancel* on the live book.

## 2. How a real exchange is cut into boxes

Databento’s matching-engine survey, Deutsche Börse **T7**, and the usual INET / Pillar / Millennium shape:

```
clients
   |
   v
order gateways          sessions, parse, timestamp   (parallel)
   |
   v
sequencer / partition   one FIFO into the matcher
   |
   v
matching engine         in-memory CLOB, price-time, trade reports
   |
   +-- persist (WAL / journal)
   +-- market data (same events, different view)
```

**T7 (Eurex / Xetra)** is explicit:

- A **partition** is a failure domain: matching + persist + market data for a **subset of products**.
- One **partition-specific (PS) gateway** per partition; high-frequency sessions; flat binary (ETI).
- **LF gateways** can reach all partitions but add ~12 µs.
- Matching **priority is assigned when the matcher reads** the order, not at the NIC of a random gateway.
- Core loop: process order (book or match) → hand to EOBI (order-by-order MD) → EMDI → persist. Persist is *after* the functional match.
- The matcher holds order state **in memory**. Restarts rebuild; MD during the day is “preliminary” until persist catches up.

**CME Globex, Nasdaq INET, NYSE Arca/Pillar, LSE Millennium** (as summarized in recent matching-engine literature): the match path does price-time, book maintenance, trade reports, and a few **constant-time** checks (max size, self-trade prevention, price bands). It does **not** do balance, margin, or credit. That is exactly our FPGA-vs-software split.

**LMAX** is the software twin: one in-memory business-logic thread, event sourcing, Disruptor ring buffers. Multi-symbol = **shard by symbol**, one writer per book, no locks on the book. Hot symbols get a dedicated core; cold symbols share a core.

Implications for us:

- Gateway is allowed to be slow and parallel.
- The matcher must see a **single ordered stream per shard**.
- WAL and market data are **the same event stream**, two consumers.
- There is **no venue-wide sequence** that total-orders every symbol. Sequence lives **inside the partition**.

## 3. Multi-symbol: three hardware patterns

### A. Parallel book instances (tiny N)

One full order-book module per ticker, demux on the symbol field. Open-source FPGA demos do this for **8** names (AAPL…NVDA) on an Artix-7: BRAM per book, round-robin BBO arbiter.

This dies at tens of symbols (logic + BRAM × N). It is a lab bring-up, not a CEX.

### B. One pipeline, many books in on-chip RAM (our next step)

`symbol_id` is a dense integer. A hash or direct index selects a BRAM/URAM slice. **One matcher FSM**, one order in flight.

Why this exists: on CPUs, multiplexing 10k books through one cache hierarchy raises per-message latency (published figures: ~30 ns at 1 symbol → ~49 ns at 10k on one core). No software trick removes the eviction. FPGA gives each book a **private on-chip partition** and a **hard resource wall** instead of a smooth slowdown.

stephenry/ob (academic FPGA matcher): one stock, sorted bid/ask tables as associative shift registers, **integer/BCD prices**, ~40M trades/s on a small Kintex-7 with 32×32 resting slots. The lesson is bounded tables + constant-time insert/remove, not “std::map in RTL.”

Columbia teaching design (DE1-SoC): multiple symbols via **virtual pages** in BRAM — `symbol_id || VPN` into a page table, heaps in paged BRAM. Same idea: shared datapath, addressed memory, not N cloned matchers.

### C. Tile cache + off-chip memory (production size)

Patents on hardware matching-engine books (e.g. US20240192854 / related “asymmetric multi-level cache”):

- A **tile** = all resting orders for one `(instrument, side, price)` plus metadata, priority lists, freelist.
- Tiles live in **DRAM**, pulled into FPGA **BRAM** when that price is active.
- A **symbol registry** maps instrument → memory.
- A nightly **fitter** spreads symbols across matcher servers for the next session.

Book-builders at 100k+ instruments use **cuckoo hashing into QDR SRAM** (Dvořák et al., DDECS 2014: ~119k instruments in 144 Mbit QDR, ~253 ns average lookup). Off-chip is a *scale* tool. It is not the first matcher.

## 4. What the hot path actually contains

FPGA and software engines that care about cancel agree on the structures:

1. **Price-time queues** — FIFO of orders at one price (our `price_level_fifo`).
2. **Price index** — sorted / hashed / neighbor-linked levels so “best opposite” is cheap (our 8-level scan; later a tree or skip list of levels).
3. **Order-id map** — `oid → {symbol, side, price, qty}`. ITCH delete/cancel often carries **only** the id. Without this map the book cannot find the level. We do not have this in RTL yet; software cancel today scans every level.
4. **Instruction word** — packed opcode, side, integer ticks/lots, oid. No floats, no `"BTC-USD"` on the chip. Pipebomb’s ITCH `inst_t` is the same shape as `design/messages.md`.

Pipelining (Pipebomb / typical HFT book):

```
wire bytes → parse → inst FIFO
                      → oid map  (cancel/delete)
                      → bid XOR ask processor
                      → BBO / depth / events
```

Bid and ask are disjoint, so they can run in parallel **after** the instruction is fully decoded. Two *symbols* in one matcher at once is a much harder hazard (two writers to the same RAM). Production matchers usually **do not**; they keep one order in the match pipeline per shard.

Recent “PIN + neighbor-aware tree” work (arXiv:2606.01183) is aimed at FPGA: fixed-capacity contiguous slots → BRAM, priority bitmasks → hardware encoders, tree splices from known neighbors instead of root-to-leaf search. We do not need that data structure yet. We do need its **constraints**: statically sized memory, bounded pipeline depth, no pointer-chasing on the match path.

## 5. Memory hierarchy (matcher vs book-builder)

| Store | Latency | Use |
|---|---|---|
| Registers / LUT RAM | 0–1 cycle | Best price, tiny FIFOs, our 16-deep compacting level |
| BRAM | 1 cycle, deterministic | Per-symbol book, oid map, our next multi-symbol store |
| UltraRAM | 1–2 cycles, large | Many symbols still on-chip |
| QDR SRAM | ~few ns, dual-port | 10k–200k instrument **metadata / L2** |
| DDR / HBM | 10s–100s ns, bursty | Cold tiles, history, not the first match |

Rule used by everyone who publishes numbers: **nothing on the match path that can miss**. DRAM is allowed only behind an explicit tile fetch, with the matcher stalled or the command queued.

## 6. Software multi-symbol (what LMAX / exchange-core / T7 do)

- `symbol_id → OrderBook` (hash or array).
- **Single writer** per book. Cross-symbol matching (spreads) is a *different* engine, not a lock on two books.
- Ids and sequences are **per engine / per partition**. Several symbols ⇒ several engines or one engine with a map — but **not** one global seq over the whole venue.
- Ingress, journal, match, egress communicate with **bounded queues**. Journal (WAL) is in the pipeline so recovery = replay.
- Integer ticks at the core; `Instrument` converts decimals only at the API edge.

This is already how `sw/gateway` should grow: a dictionary of `Book` objects, WAL `cmd` records gain `symbol`, protocol gains a token.

## 7. What we should copy, defer, and reject

**Copy now (multi-symbol v1)**

- Dense integer `symbol_id` on the engine; ticker strings only in the gateway.
- One shared matcher; books addressed by id (Python `dict` first, then RTL mux / BRAM bank).
- One command in flight per shard.
- WAL per shard; `seq` stays per engine, not venue-wide.
- Protocol: `LIMIT BUY <sym> <px> <qty> <oid>`.
- Keep accounts / balances in software.
- Add an **order-id map** (software first) so `CANCEL <oid>` does not require the client to repeat symbol/price.

**Defer**

- DRAM tiles, QDR, HBM.
- Parallel matcher pipelines / one Verilog book per symbol.
- Self-trade prevention, price bands, icebergs, auctions, implied books.
- FPGA NIC, 100GbE, T7-style PS vs LF gateways.
- Nightly symbol fitter across boards.

**Reject**

- Floating point on the match path.
- A global sequence that total-orders every symbol.
- Putting risk ledgers in RTL.
- Treating Enyx/NovaSparks book-builders as the template for *our* matcher.

## 8. Mapping onto this repo

| Industry piece | We have | Next |
|---|---|---|
| Price-time queue | `rtl/book/price_level_fifo.sv` | Keep |
| One-instrument matcher | `rtl/book/one_symbol_book.sv` | Reuse as the per-id book |
| Gateway + WAL + replay | `sw/gateway/` | Add `symbol` to protocol and WAL |
| Golden model | `sw/golden/book.py` | `Books: dict[int, Book]` |
| Symbol mux in RTL | — | `symbol_id` → bank of books or indexed RAM |
| Order-id map | scan all levels | `oid → (symbol, side, price)` |
| Market-data feed | BBO probes + FILL lines | Same events, second consumer |
| Partition / shard | one process, one book | one process, many books, still one writer |

## 9. Sources

- Enyx, *nxAccess* product page (symbol count, on-chip order storage).
- NovaSparks / Novatick, STAC Chicago 2024 slides (equities vs OPRA scale, QDR vs DDR).
- Algo-Logic, CME futures & options FPGA order book (2016 launch note).
- Deutsche Börse, *Insights into T7 trading system dynamics* (partitions, PS/LF gateways, match-then-persist-then-MD).
- Databento, *An introduction to matching engines*.
- Martin Fowler, *The LMAX Architecture* (single-threaded in-memory matcher, event sourcing, Disruptors).
- Dvořák et al., DDECS 2014, FPGA HFT book with cuckoo hashing + QDR (~119k instruments).
- US20240192854 / related patents, tile cache for `(instrument, side, price)` on FPGA+DRAM.
- stephenry/ob, FPGA matching engine (sorted tables, integer prices).
- Punt Engine, *The architecture of a pipelined order book* (ITCH-as-ISA, oid map, bid/ask split).
- arXiv:2606.01183, PIN + neighbor-aware tree; CPU multi-symbol cache cost vs FPGA BRAM partitions.
- adilsondias-engineer/08-fpga-order-book (8 parallel BRAM books — the anti-pattern at scale).

## 10. Decision for exch-core

Multi-symbol v1 is **pattern B in software first, then the same mux in RTL**:

1. Gateway: `LIMIT BUY BTC 100 10 1` (BTC → `symbol_id`).
2. `Exchange` holds `dict[symbol_id, Book]`; WAL `cmd` includes `symbol`.
3. Replay still applies only `cmd` records, now to the right book.
4. RTL later: `symbol_id` selects which `one_symbol_book` memory; still one pipeline.

Do not instantiate eight `one_symbol_book` modules as the architecture. That is pattern A.

**Multiple pipelines** (a second matcher FSM, or one FSM per symbol) are a real industry technique. They only stay correct if each pipeline owns a **disjoint** set of symbols. Details, hazards, and the five patterns: [multi-pipeline.md](multi-pipeline.md).
