"""oid → symbol. Cancel does not need the client to repeat the instrument."""

from __future__ import annotations


class OidMap:
    def __init__(self) -> None:
        self._sym: dict[int, int] = {}

    def insert(self, oid: int, symbol: int) -> None:
        self._sym[oid] = symbol

    def get(self, oid: int) -> int | None:
        return self._sym.get(oid)

    def remove(self, oid: int) -> None:
        self._sym.pop(oid, None)
