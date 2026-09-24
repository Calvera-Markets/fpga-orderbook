"""Python golden model of rtl/book/one_symbol_book.sv.

Semantics: design/one-symbol-book.md
"""

from __future__ import annotations

from dataclasses import dataclass, field

from price_level import PriceLevel

N_LEVELS = 8
PRICE_WIN = 128
MISS_CYCLES = 4
SIDE_BUY = 0
SIDE_SELL = 1
BOOK_LIMIT = 0
BOOK_CANCEL = 1


@dataclass
class Fill:
    maker_oid: int
    taker_oid: int
    price: int
    qty: int


@dataclass
class BookRsp:
    ok: bool
    oid: int
    filled_qty: int = 0
    rest_qty: int = 0
    unrested_qty: int = 0
    fills: list[Fill] = field(default_factory=list)
    slot: int = 0


class Book:
    def __init__(self, n_levels: int = N_LEVELS) -> None:
        self.n_levels = n_levels
        self.bids: dict[int, PriceLevel] = {}
        self.asks: dict[int, PriceLevel] = {}
        self.touch = {SIDE_BUY: None, SIDE_SELL: None}
        self.last_wait = 0

    @property
    def bbo_bid_valid(self) -> bool:
        return bool(self.bids)

    @property
    def bbo_ask_valid(self) -> bool:
        return bool(self.asks)

    @property
    def bbo_bid_px(self) -> int:
        return max(self.bids) if self.bids else 0

    @property
    def bbo_ask_px(self) -> int:
        return min(self.asks) if self.asks else 0

    @property
    def bbo_bid_qty(self) -> int:
        return self.bids[self.bbo_bid_px].total_qty if self.bids else 0

    @property
    def bbo_ask_qty(self) -> int:
        return self.asks[self.bbo_ask_px].total_qty if self.asks else 0

    def _touch(self, side: int, price: int) -> None:
        prev = self.touch[side]
        self.last_wait = 0 if prev is None or prev == price else MISS_CYCLES
        self.touch[side] = price

    def limit(self, side: int, price: int, qty: int, oid: int) -> BookRsp:
        if qty == 0:
            return BookRsp(ok=False, oid=oid)
        self._touch(side, price)
        fills: list[Fill] = []
        remaining = qty
        filled = 0
        if side == SIDE_BUY:
            while remaining and self.asks and price >= min(self.asks):
                px = min(self.asks)
                r = self.asks[px].match(remaining)
                fills.append(Fill(r.oid, oid, px, r.qty))
                remaining -= r.qty
                filled += r.qty
                if self.asks[px].empty:
                    del self.asks[px]
        else:
            while remaining and self.bids and price <= max(self.bids):
                px = max(self.bids)
                r = self.bids[px].match(remaining)
                fills.append(Fill(r.oid, oid, px, r.qty))
                remaining -= r.qty
                filled += r.qty
                if self.bids[px].empty:
                    del self.bids[px]
        rest = 0
        unrested = 0
        ok = True
        slot = 0
        if remaining:
            book = self.bids if side == SIDE_BUY else self.asks
            if price >= PRICE_WIN:
                unrested = remaining
                ok = False
                remaining = 0
            elif price not in book:
                if len(book) >= self.n_levels:
                    unrested = remaining
                    ok = False
                    remaining = 0
                else:
                    book[price] = PriceLevel()
            if remaining:
                r = book[price].add(oid, remaining)
                if r.ok:
                    rest = remaining
                    slot = book[price].depth - 1
                else:
                    unrested = remaining
                    ok = False
                    if book[price].empty:
                        del book[price]
        return BookRsp(
            ok=ok,
            oid=oid,
            filled_qty=filled,
            rest_qty=rest,
            unrested_qty=unrested,
            fills=fills,
            slot=slot,
        )

    def has_oid(self, oid: int) -> bool:
        for levels in (self.bids, self.asks):
            for level in levels.values():
                if any(order.oid == oid for order in level.slots):
                    return True
        return False

    def cancel(self, oid: int) -> BookRsp:
        for book in (self.bids, self.asks):
            for px, level in list(book.items()):
                r = level.cancel(oid)
                if r.ok:
                    if level.empty:
                        del book[px]
                    return BookRsp(ok=True, oid=oid, rest_qty=r.qty)
        return BookRsp(ok=False, oid=oid)
