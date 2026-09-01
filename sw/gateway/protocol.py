"""Text protocol for the mini-exchange. Spec: design/gateway.md"""

from __future__ import annotations

import sys
from pathlib import Path

_GOLDEN = Path(__file__).resolve().parent.parent / "golden"
if str(_GOLDEN) not in sys.path:
    sys.path.insert(0, str(_GOLDEN))

from book import SIDE_BUY, SIDE_SELL, Book, BookRsp, Fill  # noqa: E402

from instruments import Instruments
from merge import with_pipe


class ParseError(Exception):
    pass


def parse(line: str, instruments: Instruments | None = None) -> tuple:
    parts = line.split()
    if not parts:
        return ("empty",)
    op = parts[0].upper()
    if op == "LIMIT":
        if len(parts) != 6:
            raise ParseError("usage: LIMIT BUY|SELL <sym> <price> <qty> <oid>")
        side_tok = parts[1].upper()
        if side_tok == "BUY":
            side = SIDE_BUY
        elif side_tok == "SELL":
            side = SIDE_SELL
        else:
            raise ParseError("side must be BUY or SELL")
        try:
            price, qty, oid = int(parts[3]), int(parts[4]), int(parts[5])
        except ValueError as exc:
            raise ParseError("price, qty, oid must be integers") from exc
        try:
            if instruments is None:
                symbol = int(parts[2])
            else:
                symbol = instruments.intern(parts[2])
        except ValueError as exc:
            raise ParseError("sym must be an integer or ticker") from exc
        return ("limit", side, symbol, price, qty, oid)
    if op == "CANCEL":
        if len(parts) != 2:
            raise ParseError("usage: CANCEL <oid>")
        try:
            oid = int(parts[1])
        except ValueError as exc:
            raise ParseError("oid must be an integer") from exc
        return ("cancel", oid)
    if op == "BBO":
        if len(parts) == 1:
            return ("bbo", None)
        if len(parts) == 2:
            try:
                if instruments is None:
                    return ("bbo", int(parts[1]))
                return ("bbo", instruments.intern(parts[1]))
            except ValueError as exc:
                raise ParseError("sym must be an integer or ticker") from exc
        raise ParseError("usage: BBO [sym]")
    if op == "QUIT":
        return ("quit",)
    raise ParseError(f"unknown command {parts[0]!r}")


def format_bbo(book: Book, symbol: int | None = None, label: str | None = None) -> str:
    bid = f"{book.bbo_bid_px}:{book.bbo_bid_qty}" if book.bbo_bid_valid else "-"
    ask = f"{book.bbo_ask_px}:{book.bbo_ask_qty}" if book.bbo_ask_valid else "-"
    if symbol is None and label is None:
        return f"BBO bid={bid} ask={ask}"
    tag = label if label is not None else str(symbol)
    return f"BBO sym={tag} bid={bid} ask={ask}"


def format_fill(fill: Fill) -> str:
    return (
        f"FILL maker={fill.maker_oid} taker={fill.taker_oid} "
        f"price={fill.price} qty={fill.qty}"
    )


def format_rsp(
    rsp: BookRsp,
    book: Book,
    symbol: int | None = None,
    pipe: int | None = None,
    label: str | None = None,
) -> str:
    lines = [format_fill(f) for f in rsp.fills]
    status = "OK" if rsp.ok else "NAK"
    lines.append(
        with_pipe(
            f"{status} oid={rsp.oid} filled={rsp.filled_qty} "
            f"rest={rsp.rest_qty} unrested={rsp.unrested_qty}",
            pipe,
        )
    )
    lines.append(format_bbo(book, symbol, label))
    return "\n".join(lines) + "\n"
