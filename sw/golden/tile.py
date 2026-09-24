"""One tile is the orders at one symbol, side, and price. It does not match."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class TileOrder:
    oid: int
    qty: int


@dataclass
class Tile:
    symbol: int
    side: int
    price: int
    orders: list[TileOrder] = field(default_factory=list)

    def add(self, oid: int, qty: int) -> None:
        self.orders.append(TileOrder(oid, qty))

    def oldest_first(self) -> list[tuple[int, int]]:
        return [(o.oid, o.qty) for o in self.orders]
