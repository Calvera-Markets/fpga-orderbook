# Software mini-exchange

Code: `sw/gateway/`. Engine: the Python golden book (`sw/golden/book.py`). Same instruction semantics as `rtl/book/one_symbol_book.sv`. Verilator is not on this path yet; swapping the book backend later must not change the text protocol or WAL.

## Split

```
stdin text  ->  protocol  ->  Exchange.limit/cancel  ->  Book
                                  |                      |
                                  v                      v
                               WAL (jsonl)            BBO / fills
                                  |
                                  v
                         restart: replay cmds into a blank Book
```

Software owns persistence. The book is rebuilt by replay, not by loading a snapshot.

## Text protocol (one command per line)

| Command | Meaning |
|---|---|
| `LIMIT BUY <sym> <price> <qty> <oid>` | GTC limit. `<sym>` is an integer id **or** a ticker (`BTC`) |
| `LIMIT SELL <sym> <price> <qty> <oid>` | GTC limit |
| `CANCEL <oid>` | Cancel resting order (oid map finds the symbol) |
| `BBO` | Print BBO for every live symbol (not logged) |
| `BBO <sym>` | Print BBO for one symbol or ticker |
| `QUIT` | Exit the CLI |

Ticks and lots are integers. Tickers are interned at the gateway to dense ids; the engine and WAL store the integer. `BUY=0`, `SELL=1` on the book API.

Reply, in order:

```
FILL maker=<id> taker=<id> price=<px> qty=<qty>     # execution report
OK|NAK oid=<id> filled=<n> rest=<n> unrested=<n> pipe=<k>
BBO [sym=<name|id>] bid=<px>:<qty>| -  ask=<px>:<qty>| -
MD TRADE sym=<name> px=<px> qty=<qty> maker=<id> taker=<id>   # public feed
MD BBO sym=<name> bid=... ask=...

Match order is **per pipe**. The CLI prints replies in submit order. Two fills on different pipes have no venue-wide sequence. `MD *` is the same events, not a second matcher.
```

`NAK` is a rejected command (qty 0, unknown cancel, rest bound hit). Fills already produced still print first.

## WAL

Path given by `--wal` (default `data/exch.wal`). JSONL, one object per line, `fsync` after each command’s records.

| `type` | Fields |
|---|---|
| `instrument` | `name` (ticker), `id` (dense integer). Written once on first intern. No `seq`. |
| `cmd` | `seq`, `pipe`, `op` (`limit`\|`cancel`), `symbol` (int), `side`, `price`, `qty`, `oid` |
| `rsp` | `seq`, `pipe`, `ok`, `oid`, `filled`, `rest`, `unrested` |
| `fill` | `seq`, `pipe`, `maker`, `taker`, `price`, `qty` |

`seq` is per pipe, one per inbound mutating command. `BBO` does not bump seq and is not logged. Replay binds `instrument` rows first (file order), reserves every `cmd.symbol`, then applies cmds. Tickers never appear on `cmd`.

**Replay:** read the file, apply only `cmd` records to a new `Book`, then append new cmds. Do not write the WAL during replay.

## CLI

```sh
PYTHONPATH=sw/golden python3 sw/gateway/main.py --wal data/exch.wal
```

Reads stdin, writes stdout. Restarting the process with the same `--wal` restores BBO and resting orders.
