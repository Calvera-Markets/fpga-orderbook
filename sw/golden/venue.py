"""A venue is many one-symbol books, keyed by integer symbol_id."""

from __future__ import annotations

from book import Book, BookRsp


class Venue:
    def __init__(self) -> None:
        self.books: dict[int, Book] = {}

    def book(self, symbol: int) -> Book:
        if symbol not in self.books:
            self.books[symbol] = Book()
        return self.books[symbol]

    def limit(self, symbol: int, side: int, price: int, qty: int, oid: int) -> BookRsp:
        return self.book(symbol).limit(side, price, qty, oid)

    def cancel(self, oid: int) -> BookRsp:
        for book in self.books.values():
            rsp = book.cancel(oid)
            if rsp.ok:
                return rsp
        return BookRsp(ok=False, oid=oid)
