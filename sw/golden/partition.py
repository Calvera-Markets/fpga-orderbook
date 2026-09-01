"""Pattern 4: pipe = symbol_id % K. Each pipe owns a disjoint Venue."""

from __future__ import annotations

from book import Book, BookRsp
from venue import Venue

N_PIPES = 4


def pipe_of(symbol: int, k: int = N_PIPES) -> int:
    return symbol % k


class _OidUnion:
    def __init__(self, pipes: list[Venue]) -> None:
        self._pipes = pipes

    def get(self, oid: int) -> int | None:
        for venue in self._pipes:
            hit = venue.oids.get(oid)
            if hit is not None:
                return hit
        return None


class PartitionedVenue:
    def __init__(self, k: int = N_PIPES) -> None:
        self.k = k
        self.pipes = [Venue() for _ in range(k)]
        self.seq = [0] * k
        self.oids = _OidUnion(self.pipes)

    def pipe(self, symbol: int) -> int:
        return pipe_of(symbol, self.k)

    def book(self, symbol: int) -> Book:
        return self.pipes[self.pipe(symbol)].book(symbol)

    def try_book(self, symbol: int) -> Book | None:
        return self.pipes[self.pipe(symbol)].try_book(symbol)

    @property
    def books(self) -> dict[int, Book]:
        out: dict[int, Book] = {}
        for venue in self.pipes:
            out.update(venue.books)
        return out

    def limit(
        self, symbol: int, side: int, price: int, qty: int, oid: int, *, bump: bool = True
    ) -> BookRsp:
        p = self.pipe(symbol)
        if bump:
            self.seq[p] += 1
        return self.pipes[p].limit(symbol, side, price, qty, oid)

    def cancel(self, oid: int, *, bump: bool = True) -> BookRsp:
        symbol = self.oids.get(oid)
        p = self.pipe(symbol) if symbol is not None else 0
        if bump:
            self.seq[p] += 1
        if symbol is None:
            return BookRsp(ok=False, oid=oid)
        return self.pipes[p].cancel(oid)
