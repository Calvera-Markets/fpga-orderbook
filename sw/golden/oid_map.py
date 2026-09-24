"""oid → (slice, price, slot). Cancel does not need the client to repeat the instrument."""

from __future__ import annotations


class OidMap:
    def __init__(self) -> None:
        self._sym: dict[int, int] = {}
        self._place: dict[int, tuple[int, int, int]] = {}

    def insert(self, oid: int, symbol: int, price: int = 0, slot: int = 0, slice_id: int | None = None) -> None:
        self._sym[oid] = symbol
        where = symbol if slice_id is None else slice_id
        self._place[oid] = (where, price, slot)

    def get(self, oid: int) -> int | None:
        return self._sym.get(oid)

    def place(self, oid: int) -> tuple[int, int, int] | None:
        return self._place.get(oid)

    def remove(self, oid: int) -> None:
        self._sym.pop(oid, None)
        self._place.pop(oid, None)
