# Pattern 4 — partitioned matcher pipelines

Architecture for [pattern-4-checkpoints.md](pattern-4-checkpoints.md). Each pipeline owns a disjoint set of symbols, private book RAM, and its own FSM. Same `symbol_id` always hashes to the same pipe.

```
cmd (symbol, op, side, px, qty, oid)
        |
        v
 pipe = symbol_id % K          K power of two: low bits
        |
   +----+----+
   |         |
bank[0]   bank[1]     one in-flight order per bank
 N books    N books   generate of one_symbol_book
 seq[0]     seq[1]
   |         |
   +----+----+
        v
 fills / BBO tagged with symbol
```

## Frozen knobs

| Knob | v1 |
|---|---|
| `SYMBOL_W` | 16 |
| `K` / `N_PIPES` | 2 |
| Map | `pipe = symbol_id % N_PIPES` |
| Local index | `local = symbol_id / N_PIPES` |
| Books per pipe | RTL `N_SYMS_PER_PIPE = 4` (symbols `0 .. K*N-1`) |
| Software books | unbounded `dict` per pipe |
| Seq | per pipe, not venue-wide |
| WAL | one JSONL file; each `cmd` has `symbol`, `pipe`, `seq` |
| Cancel | `CANCEL <oid>` via oid → symbol → pipe |
| Issue | at most one in-flight command **per pipe**; pipes independent |
| Tickers | integer ids on the engine; no `"BTC"` in RTL |

Invalid local index (RTL: `local >= N_SYMS_PER_PIPE`) → NAK, state unchanged.

## Handshake

One command port at the top. `cmd_ready` is the **selected** pipe’s ready (function of `cmd_symbol`). Pipe B can accept while pipe A is matching.

Responses and fill events are **per pipe** (arrays of `N_PIPES`). Two pipes may complete in the same cycle; the TB/gateway harvests every high `rsp_valid[k]` / `evt_valid[k]`.

## Correctness

- Two orders on **different** pipes: no ordering between their matches.
- Two orders on the **same** symbol: FIFO in that pipe (second waits `cmd_ready`).
- A fill on symbol 1 never consumes resting qty on symbol 2.
