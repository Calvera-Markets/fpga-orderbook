# Price-level FIFO

First RTL module. Path: `rtl/book/price_level_fifo.sv`.

A price level is the set of resting orders at **one price**, **one side**, **one symbol**. Time priority is FIFO: new orders append at the tail; matching eats the head; cancel removes by `order_id` and compacts so the remaining sequence stays time-ordered.

## Why this is the first module

The one-symbol book is a sorted ladder of these levels. If the FIFO is wrong, the book cannot be right. The FIFO is also small enough to simulate in the head: sixteen packed slots, three opcodes, one cycle.

## Data structure

```
slots[0]  = oldest (head)     <-- MATCH
slots[1]
...
slots[depth-1] = newest (tail) <-- ADD
slots[depth .. MAX-1] unused (valid=0)
```

`MAX_ORDERS = 16`. Each slot is `{valid, oid[63:0], qty[31:0]}`. Compaction on full consume or cancel is a combinational shift of at most 16 entries. That is synthesizable and, for v1, clearer than a linked list in BRAM.

## Operations

### ADD (`cmd_op=0`)

If `!full` and `cmd_qty != 0`, write `{valid=1, oid, qty}` at `slots[depth]` and increment depth.

Reject: level full, or qty 0.

### MATCH (`cmd_op=1`)

Operates on the **head only**. `take = min(head_qty, cmd_qty)`.

- Partial: `head_qty -= take`, depth unchanged.
- Full: head slot is removed, everyone shifts down, depth decrements.

Reject: empty, or qty 0.

A parent matcher that needs to fill 100 lots across three resting orders at this price issues MATCH three times. Walking the level is the book’s job, not this module’s. That keeps the FIFO at one command per clock with no variable-latency loop.

### CANCEL (`cmd_op=2`)

Scan from head to tail for the first `oid` match, return that order’s remaining qty, compact the hole.

Reject: oid not present. `cmd_qty` is ignored.

Software must keep `order_id` unique. If a duplicate exists, the oldest slot is canceled.

## Timing

Synchronous reset: hold `rst_n=0` for at least one rising edge.

```
clk        : /‾\___/‾\___/‾\___
cmd_valid  : ____/‾‾‾‾‾\_______
cmd_*      :     < ADD  >
slots/depth:  old        <new>
rsp_valid  : ________/‾‾‾‾‾\___
rsp_*      :         < result >
probes     :  old        <new>
```

Testbench pattern: drive `cmd_*`, tick one clock, then sample `rsp_*` and probes. No wait-for-ready loop in v1 (`cmd_ready == rst_n`).

## What this module is not

- Not a full book (no prices, no opposite side, no BBO).
- Not a multi-fill walker.
- Not a BRAM-style linked list (that comes when `MAX_ORDERS` no longer fits a shift).
- Not the gateway. Software still owns sessions.

## Golden model

`sw/golden/price_level.py` implements the same three ops on a Python list. `sw/golden/test_price_level.py` runs the same scenarios as `tb/price_level_fifo_tb.cpp`. If RTL and Python disagree, the design in this file is the spec; fix the one that drifted.

## Test scenarios

Both the C++ bench and the Python tests cover:

1. Reset → empty, depth 0, total 0
2. ADD three orders → depth 3, head is first oid, total is sum
3. MATCH partial → head qty drops, depth unchanged
4. MATCH exact head qty → head consumed, next oid becomes head
5. CANCEL middle → hole compacted, time order of survivors preserved
6. CANCEL head / CANCEL tail
7. CANCEL missing oid → `rsp_ok=0`, state unchanged
8. MATCH on empty / ADD qty 0 / MATCH qty 0 → reject
9. Fill 16 orders, 17th ADD rejects, then CANCEL makes room
10. MATCH walks the head repeatedly until the level is empty
