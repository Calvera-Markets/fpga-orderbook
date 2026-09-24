"""A two-symbol order is two child limits, issued one slice at a time."""

from __future__ import annotations


class TwoSlice:
    def __init__(self, venue) -> None:
        self.venue = venue
        self.children: dict[int, list[tuple[int, int]]] = {}
        self.busy: set[int] = set()
        self.waiting: list[tuple[int, int]] = []
        self.steps: list[int] = []

    def submit(
        self,
        sym_a: int,
        side_a: int,
        price_a: int,
        qty_a: int,
        sym_b: int,
        side_b: int,
        price_b: int,
        qty_b: int,
        parent: int,
    ) -> tuple[int, int]:
        first, second = parent * 2, parent * 2 + 1
        self.steps.append(first)
        self.venue.limit(sym_a, side_a, price_a, qty_a, first)
        self.steps.append(second)
        self.venue.limit(sym_b, side_b, price_b, qty_b, second)
        self.children[parent] = [(sym_a, first), (sym_b, second)]
        return first, second

    def cancel(self, parent: int) -> None:
        for sym, oid in self.children.get(parent, []):
            sl = self.venue.pipe(sym)
            if sl in self.busy:
                self.waiting.append((sl, oid))
            else:
                self.venue.cancel(oid)

    def release(self, slice_id: int) -> None:
        self.busy.discard(slice_id)
        still: list[tuple[int, int]] = []
        for sl, oid in self.waiting:
            if sl == slice_id:
                self.venue.cancel(oid)
            else:
                still.append((sl, oid))
        self.waiting = still
