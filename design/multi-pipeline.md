# Multiple pipelines and multiple books

Follow-on to [industry-analysis.md](industry-analysis.md). Question: *do designs use several pipelines so they can run several books at once?* Yes — but only in a few specific shapes. Mixing those shapes up is how people build a chip that is either huge or wrong.

“Pipelined” and “multiple pipelines” are different:

| Phrase | Meaning |
|---|---|
| **A pipeline** | One order walks through stages (decode → lookup → match → emit) over several clocks. Initiation interval can still be 1. |
| **Multiple pipelines** | Several of those datapaths exist at once, each with its own in-flight order. |

Our `one_symbol_book` is already a *pipeline* (IDLE → MATCH → REST → DONE). It is **one** pipeline. This note is about instantiating more than one.

## 1. Why you cannot just dual-issue into one book

A CLOB is mutable shared state. Two orders on **the same symbol** in two pipelines is a classic CPU hazard:

- RAW / WAW on the best price, the head of a level, `total_qty`, `used` bits.
- A buy that should see the sell that just posted must not race it.
- Price-time priority is an **order** on that book. Two writers destroy the order.

FPGA dual-port BRAM does **not** fix this. Two ports allow two addresses in one cycle; a write+read of the *same* address is a collision (undefined or old data, vendor-dependent). AMD’s embedded-memory guide is explicit about that.

So every real design that “runs multiple books in parallel” first answers: **are the in-flight orders allowed to touch the same book?** If yes, they add a scoreboard. If no, they **partition**.

## 2. The designs that actually exist

Five patterns show up in papers, patents, exchanges, and FPGA demos. Only some of them are “multiple pipelines ⇒ multiple books.”

### Pattern 1 — Deep pipeline, one matcher (what we have)

Stages in series, one symbol in the datapath.

```
parse → oid map → side/book RAM → match walk → fills / BBO
```

Pipebomb (Punt Engine) is this, plus a split of bid vs ask *after* decode. He et al. FPL 2017 (Tsinghua / Imperial) pipeline order-book **update** on a hash of instrument → fixed-tick array + top-5 cache; 1.2–1.5M msg/s, 132–288 ns. Still one update stream.

Good until one pipeline’s throughput (clock / cycles-per-order) is enough. At 300 MHz and ~10 cycles/order you already have ~30M orders/s — more than most software shards.

### Pattern 2 — Bid pipeline ∥ ask pipeline (same symbol, disjoint RAM)

Pipebomb: “with all info in hand, we split off into the Bid side and the Ask side… parallelized on two axes, performing order book update operations on **disjoint** data structures.”

IP Reservoir / Taylor et al. (US 10,929,930, US20210174445): **order engines** and **price engines** run in parallel; each side of the book is its own sorted region; engines **interleave** DRAM/QDR accesses through an arbiter to hide latency.

This is two pipelines, **not** two books. A crossing match still has to touch both sides in a defined order (or take a lock on the symbol). Useful for *book building* and for rest-only updates. For matching, the cross is the serial part.

Our RTL already has separate bid and ask FIFO banks. We do not yet run them as two independent issue slots.

### Pattern 3 — One pipeline per symbol (replicated books)

adilsondias `08-fpga-order-book` (Artix-7, synthesized):

- 8 `order_book_manager` instances (AAPL … NVDA)
- Symbol demux routes ITCH to one manager
- Each manager: own order BRAM (1024 × 130b) + price-level BRAM (256 levels)
- Round-robin BBO arbiter

Columbia 4840 HFT (DE1-SoC) is the grown-up version of “many books in one fabric”: **virtual pages** in BRAM, `symbol_id || VPN` in a page table, **and a per-symbol scoreboard**. The scoreboard stalls *that* symbol if a heap sift / page fault is in flight, and lets **other** symbols proceed. That is an out-of-order CPU trick (reservation station) applied to books.

This *is* “multiple pipelines to achieve multiple books.” Cost is **logic + BRAM × N**. Fine for 8–32 names. Impossible for a CEX universe.

Algo-Logic’s 2013 “Low Latency Order-Book” used on-chip memory for “a dozen symbols”; the “Scalable” variant moved millions of orders / thousands of symbols to DDR3 — i.e. they stopped replicating pipelines and went to indexed off-chip memory.

### Pattern 4 — K partitioned matcher pipelines (what production means)

The professional multi-pipeline story:

```
incoming order
    → hash/table: symbol_id → pipeline k   (static or nightly fitter)
    → pipeline k’s private book RAM
    → pipeline k’s matcher FSM
```

Each pipeline owns a **disjoint** set of books. Two orders for the same symbol **always** hit the same pipeline, so price-time is preserved with no scoreboard. Two orders for different symbols in different pipelines run truly in parallel.

Where this appears:

- **T7 partitions** — each partition is a matcher + persist + MD for a product subset; one PS gateway into that FIFO.
- **LMAX / exchange-core / shard-per-core** — one matching thread per shard, shared-nothing, bounded queues only.
- **Matching-engine book (MEB) servers** in the tile-cache patents — nightly fitter spreads symbols across FPGA/ASIC matchers.
- arXiv:2606.01183 — CPU: many matcher *segments*, each a disjoint slice of 10k symbols; FPGA claim: “each book in its own BRAM partition… **matcher pipelines in parallel**,” scaling until the fabric is full.
- Student/open engines that advertise “shard-per-core pipelines” with SPSC rings into Matcher 0, Matcher 1, …

This is the only pattern that scales past a few dozen symbols **and** keeps a simple correctness story.

### Pattern 5 — Parallel lookup pipelines sharing one table (do not copy for matching)

Network exact-match (IEICE 2024, P4 match-action, SmartNIC MAU stages): **P** pipelines share one rule table so they do not replicate SRAM; an output reorder buffer restores packet order. That works because the table is **read-mostly**.

A matching engine **writes** the book. Shared-table + N writers = the hazard in §1. Packet-classifier papers are a trap if you cite them as CLOB architecture.

## 3. How FPGA people overlap work without extra matchers

Even with **one** matcher pipeline you can still have several *symbols* in flight, if you stall per id:

```
scoreboard[symbol].busy
issue next order if !scoreboard[its_symbol].busy
else stall only that order (or the whole front of the queue)
```

Columbia’s HFT write-up: “per-symbol stalling without blocking the entire pipeline… a small register file with one entry per active symbol… similar to a reservation station.”

Hazards they list: stale heap root (RAW during sift), page-fault pending, compacting. Those are exactly the multi-cycle walks our book FSM does (MATCH / REST / CANCEL).

UCI FPGA “MultiQueue”: 512 symbols in BRAM, CAM for symbol index, **pipeline overlaps** 2-cycle RAM with 1-cycle CAM and 1-cycle match — still one issue stream, many symbols in memory.

BRAM dual-port: one pipeline can read port A while another (or a BBO scanner) reads port B, **different addresses**. The BBO round-robin in the 8-book demo is that: matchers write, a separate arbiter reads.

## 4. Throughput vs resources (why K is small)

| Design | Parallelism | Symbols | Memory |
|---|---|---|---|
| Our book (now) | 1 FSM | 1 | 16 FIFOs on-chip |
| 8-book Artix demo | 8 FSMs | 8 | 32 × RAMB36 |
| Algo-Logic on-chip SKU | 1 FPGA | ~dozen | BRAM |
| Algo-Logic scalable SKU | 1 FPGA | thousands | DDR3 |
| T7 / INET | many servers | universe, sharded | DRAM per partition |
| PIN paper FPGA claim | several matcher pipelines | many, BRAM-sliced | on-chip until the wall |
| NovaSparks (book-build) | 1–4 FPGAs | 13k–2.2M | QDR + DDR |

One extra pipeline copies: the FSM, the oid-map ports, the fill egress, and **all** the book RAM for the symbols it owns. BRAM, not LUTs, is the wall. That is why pattern 3 dies and pattern 4 (partition, don’t replicate the world) wins.

A single 300 MHz pipeline at 4–20 cycles/order is 15–75M orders/s. Production software shards are often 0.2–10M/s. **We do not need K>1 until measurement says the one pipeline is the bottleneck** — and even then K=2 or 4 with a symbol hash is the move, not K=number of symbols.

## 5. Correctness rules if we ever add pipelines

1. **Partition by `symbol_id`.** `pipeline = symbol_id % K` (or a static map). Same symbol ⇒ same pipeline. Never two writers on one book.
2. **Do not share book RAM across pipelines** unless you have a scoreboard *and* dual-port collision logic. Prefer private BRAM slices.
3. **Bid∥ask issue** is allowed for non-crossing ops. A crossing LIMIT must own both sides (hold the symbol).
4. **Sequence is per pipeline**, not global. WAL, `seq`, and MD all follow the pipeline. Same as T7 partitions.
5. **Egress** needs a merge (round-robin or per-pipeline streams). BBO is per symbol, so no merge problem if each pipeline emits its own symbols.
6. **Scoreboard inside one pipeline** is the cheaper way to overlap *different* symbols before you pay for a second FSM.

## 6. What this means for exch-core

The user’s instinct is right: **multiple pipelines are how you host multiple books in parallel.** The professional form is pattern 4, not pattern 3.

Recommended ladder:

| Step | Parallelism | Why |
|---|---|---|
| Now | 1 FSM, 1 book | Done |
| Multi-symbol v1 | 1 FSM, N books in a map / BRAM bank | Pattern 1 + indexed memory. Python `dict[symbol, Book]`, then RTL mux |
| Optional | 1 FSM, N books, **per-symbol scoreboard** | Overlap cold symbols in the same pipeline (Columbia) |
| Later, if measured | K=2..4 partitioned FSMs | Pattern 4. Hash `symbol_id` → pipeline. Private RAM. Separate WALs |
| Not planned | N FSMs for N symbols | Pattern 3. Lab only |
| Not planned | P pipelines on one shared writable book | Pattern 5. Wrong for matching |

Do not start K pipelines until the single-pipeline multi-symbol book is correct. Partitioning is a **routing** change on top of a working `one_symbol_book`.

## 7. Sources

- Punt Engine, *The architecture of a pipelined order book* (bid/ask split; “multiple entire pipelines” listed as future work).
- He, Fu, Luk et al., FPL 2017, *Exploring the Potential of Reconfigurable Platforms for Order Book Update* (instrument hash → pipelined OBU, top-5 cache).
- Taylor / IP Reservoir, US 10,929,930 and US20210174445 (parallel order engines + price engines, interleaved memory, sides independent).
- adilsondias-engineer/08-fpga-order-book (8 replicated BRAM books + demux).
- Columbia CSEE 4840, 2026 HFT design (paged multi-symbol BRAM, **per-symbol scoreboard / stall**).
- Algo-Logic Full Order-Book launch (on-chip “dozen symbols” vs DDR3 “thousands”).
- Deutsche Börse T7 partition model; LMAX / shard-per-core software pipelines.
- arXiv:2606.01183 §6.5 (matcher pipelines in parallel on per-symbol BRAM).
- IEICE 2024, shared rule tables among parallel EM pipelines (read-mostly; **not** a CLOB).
- AMD PG326, dual-port BRAM collision behavior.
