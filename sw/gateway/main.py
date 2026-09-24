#!/usr/bin/env python3
"""Line-oriented mini-exchange CLI. Spec: design/gateway.md"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_GOLDEN = Path(__file__).resolve().parent.parent / "golden"
if str(_GOLDEN) not in sys.path:
    sys.path.insert(0, str(_GOLDEN))

from book import Book  # noqa: E402
from exchange import Exchange
from marketdata import format_md
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
        _, token = cmd
        if token is None:
            if not exch.venue.books:
                return "BBO\n"
            lines = [
                format_bbo(exch.venue.book(s), s, exch.instruments.label(s))
                for s in sorted(exch.venue.books)
            ]
            return "\n".join(lines) + "\n"
        sid = exch.instruments.lookup(token)
        if sid is None:
            return "BBO bid=- ask=-\n"
        book = exch.venue.try_book(sid)
        if book is None:
            return format_bbo(Book(), sid, exch.instruments.label(sid)) + "\n"
        return format_bbo(book, sid, exch.instruments.label(sid)) + "\n"
    if kind == "limit":
        _, side, token, price, qty, oid = cmd
        try:
            symbol = exch.intern_symbol(token)
        except ValueError as exc:
            return f"ERR {exc}\n"
        rsp = exch.limit(symbol, side, price, qty, oid)
        label = exch.instruments.label(symbol)
        exec_rep = format_rsp(
            rsp,
            exch.venue.book(symbol),
            symbol,
            exch.venue.pipe(symbol),
            label,
        )
        return exec_rep + format_md(rsp.fills, exch.venue.book(symbol), label)
    if kind == "cancel":
        _, oid = cmd
        symbol = exch.venue.oids.get(oid)
        rsp = exch.cancel(oid)
        if symbol is None:
            return format_rsp(rsp, Book())
        book = exch.venue.book(symbol)
        pipe = exch.venue.pipe(symbol)
        label = exch.instruments.label(symbol)
        exec_rep = format_rsp(rsp, book, symbol, pipe, label)
        return exec_rep + format_md(rsp.fills, book, label)
    return "ERR internal\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="exch-core software mini-exchange")
    parser.add_argument(
        "--wal",
        default="data",
        help="WAL directory (pipe0.wal, pipe1.wal, …)",
    )
    parser.add_argument(
        "--engine",
        choices=("python", "rtl"),
        default="python",
        help="matching backend (python golden or Verilator slice_engine)",
    )
    args = parser.parse_args(argv)
    engine = None
    if args.engine == "rtl":
        from rtl_engine import RtlEngine

        engine = RtlEngine()
    exch = Exchange(Path(args.wal), engine=engine)
    for raw in sys.stdin:
        out = handle_line(exch, raw)
        if out is None:
            break
        sys.stdout.write(out)
        sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
