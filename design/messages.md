# Messages

Two layers share one layout idea: a **command** into the engine and a **response** out of it. Software owns sessions; it translates client JSON/binary into these instructions.

Widths live in `rtl/pkg/exch_pkg.sv`. Change the package and this file together.

## Command (into the price-level FIFO, now)

| Field | Width | Meaning |
|---|---|---|
| `cmd_valid` | 1 | Command is presented this cycle |
| `cmd_ready` | 1 | Engine can accept (v1: high after reset) |
| `cmd_op` | 2 | `0=ADD`, `1=MATCH`, `2=CANCEL`, `3=NOP` |
| `cmd_oid` | 64 | Resting `order_id` for ADD/CANCEL; unused for MATCH |
| `cmd_qty` | 32 | Lots to add or match; ignored on CANCEL |

A command is accepted on a rising `clk` when `cmd_valid && cmd_ready`.

## Response (registered)

Visible after the clock edge that accepted the command.

| Field | Width | Meaning |
|---|---|---|
| `rsp_valid` | 1 | Response corresponds to the command accepted last cycle/edge |
| `rsp_ok` | 1 | Command applied; otherwise state unchanged |
| `rsp_oid` | 64 | ADD/CANCEL: command oid. MATCH success: head oid consumed against |
| `rsp_qty` | 32 | ADD: added qty. MATCH: filled qty. CANCEL: canceled qty |

Rejects (`rsp_ok=0`): ADD when full or `qty==0`; MATCH when empty or `qty==0`; CANCEL when `oid` is not resting.

## Continuous probes

These are level-sensitive views of current state (after the same edge). They are how a parent book module will attach without peeking inside the array.

| Field | Meaning |
|---|---|
| `empty` / `full` | No orders / `depth == MAX_ORDERS` |
| `depth` | Resting order count (`CNT_W = $clog2(MAX_ORDERS+1)` bits so 16 fits) |
| `head_oid` / `head_qty` | Oldest order; both 0 when empty |
| `total_qty` | Sum of resting qty at this price |

Slot indexing uses `IDX_W = $clog2(MAX_ORDERS)` (4 bits for 16 slots). Depth needs one extra bit so the value 16 is representable.

## Command (into the one-symbol book)

| Field | Width | Meaning |
|---|---|---|
| `cmd_valid` / `cmd_ready` | 1 | Ready only while the book FSM is idle |
| `cmd_op` | 1 | `0=LIMIT`, `1=CANCEL` |
| `cmd_side` | 1 | `0=buy`, `1=sell` |
| `cmd_price` | 32 | Integer ticks |
| `cmd_qty` | 32 | Integer lots |
| `cmd_oid` | 64 | Taker id (LIMIT) or resting id (CANCEL) |

`symbol_id` is not on this module — a later mux selects which book. Software maps tickers and decimal prices onto these integers.

## Book response

| Field | Meaning |
|---|---|
| `rsp_valid` | Command finished |
| `rsp_ok` | LIMIT fully placed (fills + rest) or CANCEL found |
| `rsp_filled_qty` | Lots matched |
| `rsp_rest_qty` | Lots posted, or lots canceled |
| `rsp_unrested_qty` | Remainder that could not rest |

## Fill events

Each successful head `MATCH` emits one event: `maker_oid`, `taker_oid`, `price` (maker's), `qty`. Stall if `evt_valid && !evt_ready`.

BBO probes (`bbo_bid_valid/px/qty`, `bbo_ask_*`) are continuous. Qty is aggregate at the best price.

The WAL (later, software) logs the inbound instruction, the book response, and every fill event.
