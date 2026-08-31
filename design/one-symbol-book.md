# One-symbol book

Module: `rtl/book/one_symbol_book.sv`. Golden: `sw/golden/book.py`.

A price-time CLOB for **one instrument**. Bid and ask sides are banks of price-level FIFOs. An incoming GTC limit walks the opposite side (best price first, time priority at each price), then rests any remainder on its own side.

This is the first module that actually matches.

## Bounds

| Bound | Value | Notes |
|---|---|---|
| Price levels per side | `N_LEVELS = 8` | Reject rest if no free slot and no existing level at that price |
| Orders per level | `MAX_ORDERS = 16` | Inherited from the FIFO; reject rest if that level is full |
| Price / qty | 32-bit integers | Ticks and lots; no floats |
| `order_id` | 64-bit | Unique by software invariant |

## Interface

| Field | Dir | Meaning |
|---|---|---|
| `cmd_valid` / `cmd_ready` | in / out | Accept only in `IDLE`. `cmd_ready` is low while matching/resting/canceling |
| `cmd_op` | in | `0=LIMIT`, `1=CANCEL` |
| `cmd_side` | in | `0=buy`, `1=sell` (ignored on CANCEL) |
| `cmd_price` | in | Limit price in ticks (ignored on CANCEL) |
| `cmd_qty` | in | Lots (ignored on CANCEL) |
| `cmd_oid` | in | Taker id for LIMIT; resting id for CANCEL |
| `rsp_valid` | out | One-cycle pulse when the command is finished |
| `rsp_ok` | out | LIMIT fully handled (all matched and/or rested); CANCEL found the id |
| `rsp_oid` | out | Command oid |
| `rsp_filled_qty` | out | Total lots matched (LIMIT) |
| `rsp_rest_qty` | out | Lots posted (LIMIT) or lots canceled (CANCEL) |
| `rsp_unrested_qty` | out | Remainder that could not rest (level cap / fifo full) |
| `evt_valid` / `evt_ready` | out / in | Fill stream; stall the FSM if `evt_valid && !evt_ready` |
| `evt_maker_oid`, `evt_taker_oid`, `evt_price`, `evt_qty` | out | One fill = one FIFO `MATCH` of a head |
| `bbo_bid_*` / `bbo_ask_*` | out | Best price, aggregate qty at that price, valid |

## Crossing

- Buy crosses while `bbo_ask_valid && limit_price >= best_ask`.
- Sell crosses while `bbo_bid_valid && limit_price <= best_bid`.
- Trades at the **resting** (maker) price.
- Each FSM step matches only the **head** of the best opposite level (the FIFO primitive). Walking several heads or several prices takes several cycles.

LIMIT with `qty==0` is rejected (`rsp_ok=0`), state unchanged. CANCEL of an unknown id is rejected.

If some qty fills and the remainder cannot rest, fills already emitted stand. `rsp_ok=0` and `rsp_unrested_qty` holds the leftover. Do not drop fills.

## FSM

```
IDLE
  LIMIT qty=0     -> DONE (nak)
  LIMIT crosses   -> ISSUE_MATCH
  LIMIT no cross  -> ISSUE_REST
  CANCEL          -> ISSUE_CANCEL

ISSUE_MATCH -> WAIT_MATCH -> DECIDE
  remaining==0        -> DONE
  still crosses       -> ISSUE_MATCH
  else                -> ISSUE_REST

ISSUE_REST
  no slot / level full -> DONE (unrested)
  else ADD to FIFO     -> WAIT_REST -> DONE

ISSUE_CANCEL (broadcast CANCEL to every FIFO) -> WAIT_CANCEL -> DONE
```

`cmd_ready` is high only in `IDLE` after reset. Testbench: wait for ready, present `cmd_valid` one cycle, wait for `rsp_valid`, harvest `evt_valid` every cycle.

## Memory

Eight bid FIFOs and eight ask FIFOs, each tagged with a price and a `used` bit. Same price always reuses the same slot. Best bid is the max used non-empty bid price; best ask is the min used non-empty ask price. An empty FIFO after match/cancel clears `used`.

This is not a sorted shift of module instances — slots are a free list with combinational best-price scan.

## Tests

Golden and RTL share these stories:

1. Rest bid and ask, no cross; BBO is those prices / totals
2. Incoming buy fully fills one ask
3. Partial fill, remainder rests on the bid
4. Walk two ask prices (time priority at the first price, then the next)
5. Cancel resting; BBO moves
6. Cancel missing; state unchanged
7. Qty 0 LIMIT rejected
8. Take the whole far side, rest leftover
9. Symmetric sell-crosses-bid
