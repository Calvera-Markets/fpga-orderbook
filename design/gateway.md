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
| `LIMIT BUY <price> <qty> <oid>` | GTC limit |
| `LIMIT SELL <price> <qty> <oid>` | GTC limit |
| `CANCEL <oid>` | Cancel resting order |
| `BBO` | Print top of book (not logged) |
| `QUIT` | Exit the CLI |

Integers only (ticks and lots). `BUY=0`, `SELL=1` on the book API.

Reply, in order:

```
FILL maker=<id> taker=<id> price=<px> qty=<qty>     # zero or more
OK|NAK oid=<id> filled=<n> rest=<n> unrested=<n>
BBO bid=<px>:<qty>| -  ask=<px>:<qty>| -
```

`NAK` is a rejected command (qty 0, unknown cancel, rest bound hit). Fills already produced still print first.

## WAL

Path given by `--wal` (default `data/exch.wal`). JSONL, one object per line, `fsync` after each command’s records.

| `type` | Fields |
|---|---|
| `cmd` | `seq`, `op` (`limit`\|`cancel`), `side`, `price`, `qty`, `oid` |
| `rsp` | `seq`, `ok`, `oid`, `filled`, `rest`, `unrested` |
| `fill` | `seq`, `maker`, `taker`, `price`, `qty` |

`seq` is monotonic from 1, one per inbound mutating command. `BBO` does not bump seq and is not logged.

**Replay:** read the file, apply only `cmd` records to a new `Book`, then append new cmds. Do not write the WAL during replay.

## CLI

```sh
PYTHONPATH=sw/golden python3 sw/gateway/main.py --wal data/exch.wal
```

Reads stdin, writes stdout. Restarting the process with the same `--wal` restores BBO and resting orders.
