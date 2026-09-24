"""A venue is many one-symbol books, keyed by integer symbol_id."""

from __future__ import annotations

from book import Book, BookRsp
from oid_map import OidMap


class Venue:
    def __init__(self) -> None:
        self.books: dict[int, Book] = {}
        self.oids = OidMap()

    def book(self, symbol: int) -> Book:
        if symbol not in self.books:
            self.books[symbol] = Book()
        return self.books[symbol]

    def try_book(self, symbol: int) -> Book | None:
        return self.books.get(symbol)

    def _track(self, symbol: int, oid: int, rsp: BookRsp, price: int = 0, side: int = 0) -> BookRsp:
        if rsp.rest_qty > 0:
            self.oids.insert(oid, symbol, price=price, slot=rsp.slot, side=side)
        book = self.book(symbol)
        for fill in rsp.fills:
            if not book.has_oid(fill.maker_oid):
                self.oids.remove(fill.maker_oid)
        return rsp

    def limit(self, symbol: int, side: int, price: int, qty: int, oid: int) -> BookRsp:
        rsp = self.book(symbol).limit(side, price, qty, oid)
        return self._track(symbol, oid, rsp, price, side)

    def cancel(self, oid: int) -> BookRsp:
        symbol = self.oids.get(oid)
        if symbol is None:
            return BookRsp(ok=False, oid=oid)
        rsp = self.book(symbol).cancel(oid)
        if rsp.ok:
            self.oids.remove(oid)
        return rsp
