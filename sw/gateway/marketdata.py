"""Public market-data view of the same match events. Not a second matcher."""

from __future__ import annotations

import sys
from pathlib import Path

_GOLDEN = Path(__file__).resolve().parent.parent / "golden"
if str(_GOLDEN) not in sys.path:
    sys.path.insert(0, str(_GOLDEN))

from book import Book, Fill  # noqa: E402


def format_md_trade(fill: Fill, label: str) -> str:
    return (
        f"MD TRADE sym={label} px={fill.price} qty={fill.qty} "
        f"maker={fill.maker_oid} taker={fill.taker_oid}"
    )


def format_md_bbo(book: Book, label: str) -> str:
    bid = f"{book.bbo_bid_px}:{book.bbo_bid_qty}" if book.bbo_bid_valid else "-"
    ask = f"{book.bbo_ask_px}:{book.bbo_ask_qty}" if book.bbo_ask_valid else "-"
    return f"MD BBO sym={label} bid={bid} ask={ask}"


def format_md(fills: list[Fill], book: Book, label: str) -> str:
    lines = [format_md_trade(f, label) for f in fills]
    lines.append(format_md_bbo(book, label))
    return "\n".join(lines) + "\n"
