#!/usr/bin/env python3
"""Line-oriented mini-exchange CLI. Spec: design/gateway.md"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from exchange import Exchange
from protocol import ParseError, format_bbo, format_rsp, parse


def handle_line(exch: Exchange, line: str) -> str | None:
    try:
        cmd = parse(line)
    except ParseError as exc:
        return f"ERR {exc}\n"
    kind = cmd[0]
    if kind == "empty":
        return ""
    if kind == "quit":
        return None
    if kind == "bbo":
        _, symbol = cmd
        if symbol is None:
            if not exch.venue.books:
                return "BBO\n"
            lines = [
                format_bbo(exch.venue.book(s), s) for s in sorted(exch.venue.books)
            ]
            return "\n".join(lines) + "\n"
        return format_bbo(exch.venue.book(symbol), symbol) + "\n"
    if kind == "limit":
        _, side, symbol, price, qty, oid = cmd
        rsp = exch.limit(symbol, side, price, qty, oid)
        return format_rsp(
            rsp, exch.venue.book(symbol), symbol, exch.venue.pipe(symbol)
        )
    if kind == "cancel":
        _, oid = cmd
        symbol = exch.venue.oids.get(oid)
        rsp = exch.cancel(oid)
        book = exch.venue.book(symbol) if symbol is not None else exch.venue.book(0)
        pipe = exch.venue.pipe(symbol) if symbol is not None else None
        return format_rsp(rsp, book, symbol, pipe)
    return "ERR internal\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="exch-core software mini-exchange")
    parser.add_argument("--wal", default="data/exch.wal", help="WAL path (JSONL)")
    args = parser.parse_args(argv)
    exch = Exchange(Path(args.wal))
    for raw in sys.stdin:
        out = handle_line(exch, raw)
        if out is None:
            break
        sys.stdout.write(out)
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
