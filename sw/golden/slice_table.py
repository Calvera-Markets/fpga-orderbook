"""One symbol per slice. A second hot name on a taken slice is rejected."""

from __future__ import annotations

from book import Book, BookRsp
from venue import Venue

N_SLICES = 4


class SliceAssignError(Exception):
    pass


class SliceTable:
    def __init__(self, n: int = N_SLICES) -> None:
        self.n = n
        self._slice_of: dict[int, int] = {}
        self._owner: dict[int, int] = {}

    def slice_of(self, symbol: int) -> int | None:
        return self._slice_of.get(symbol)

    def owner(self, slice_id: int) -> int | None:
        return self._owner.get(slice_id)

    def assign(self, symbol: int, slice_id: int, *, hot: bool = True) -> None:
        del hot  # every name on a slice is alone; the flag is the caller's intent
        if not 0 <= slice_id < self.n:
            raise SliceAssignError(f"slice {slice_id} out of range")
        owner = self._owner.get(slice_id)
        if owner is not None and owner != symbol:
            raise SliceAssignError(f"slice {slice_id} already has {owner}")
        prev = self._slice_of.get(symbol)
        if prev is not None and prev != slice_id:
            raise SliceAssignError(f"symbol {symbol} is already on slice {prev}")
        self._owner[slice_id] = symbol
        self._slice_of[symbol] = slice_id

    def ensure(self, symbol: int) -> int:
        hit = self._slice_of.get(symbol)
        if hit is not None:
            return hit
        if 0 <= symbol < self.n and symbol not in self._owner:
            self.assign(symbol, symbol)
            return symbol
        raise SliceAssignError(f"no free slice for symbol {symbol}")


class _OidUnion:
    def __init__(self, slices: list[Venue]) -> None:
        self._slices = slices

    def get(self, oid: int) -> int | None:
        for venue in self._slices:
            hit = venue.oids.get(oid)
            if hit is not None:
                return hit
        return None


class SlicedVenue:
    """Same call shape as PartitionedVenue. pipe() is the slice id."""

    def __init__(self, n: int = N_SLICES) -> None:
        self.n = n
        self.table = SliceTable(n)
        self.slices = [Venue() for _ in range(n)]
        self.seq = [0] * n
        self.oids = _OidUnion(self.slices)

    def pipe(self, symbol: int) -> int:
        return self.table.ensure(symbol)

    def book(self, symbol: int) -> Book:
        return self.slices[self.pipe(symbol)].book(symbol)

    def try_book(self, symbol: int) -> Book | None:
        sl = self.table.slice_of(symbol)
        if sl is None:
            return None
        return self.slices[sl].try_book(symbol)

    @property
    def books(self) -> dict[int, Book]:
        out: dict[int, Book] = {}
        for venue in self.slices:
            out.update(venue.books)
        return out

    def limit(
        self, symbol: int, side: int, price: int, qty: int, oid: int, *, bump: bool = True
    ) -> BookRsp:
        try:
            sl = self.pipe(symbol)
        except SliceAssignError:
            return BookRsp(ok=False, oid=oid)
        if bump:
            self.seq[sl] += 1
        return self.slices[sl].limit(symbol, side, price, qty, oid)

    def cancel(self, oid: int, *, bump: bool = True) -> BookRsp:
        symbol = self.oids.get(oid)
        if symbol is None:
            if bump:
                self.seq[0] += 1
            return BookRsp(ok=False, oid=oid)
        sl = self.pipe(symbol)
        if bump:
            self.seq[sl] += 1
        return self.slices[sl].cancel(oid)
