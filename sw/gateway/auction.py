"""Host auction. The slice only ever sees ordinary limits."""

from __future__ import annotations

from dataclasses import dataclass

SIDE_BUY = 0
SIDE_SELL = 1


@dataclass
class AuctionOrder:
    symbol: int
    side: int
    qty: int
    oid: int


class Auction:
    def __init__(self) -> None:
        self.orders: list[AuctionOrder] = []

    def add(self, symbol: int, side: int, qty: int, oid: int) -> None:
        self.orders.append(AuctionOrder(symbol, side, qty, oid))

    def cross(self, price: int) -> list[dict]:
        buys = [o for o in self.orders if o.side == SIDE_BUY]
        sells = [o for o in self.orders if o.side == SIDE_SELL]
        return [
            {
                "op": "limit",
                "symbol": o.symbol,
                "side": o.side,
                "price": price,
                "qty": o.qty,
                "oid": o.oid,
            }
            for o in buys + sells
        ]
