"""Python golden model of rtl/book/price_level_fifo.sv.

Semantics: design/price-level-fifo.md
"""

from __future__ import annotations

from dataclasses import dataclass

MAX_ORDERS = 16
OP_ADD = 0
OP_MATCH = 1
OP_CANCEL = 2


@dataclass
class Order:
    oid: int
    qty: int


@dataclass
class Rsp:
    ok: bool
    oid: int
    qty: int


class PriceLevel:
    def __init__(self, max_orders: int = MAX_ORDERS) -> None:
        self.max_orders = max_orders
        self.slots: list[Order] = []

    @property
    def depth(self) -> int:
        return len(self.slots)

    @property
    def empty(self) -> bool:
        return self.depth == 0

    @property
    def full(self) -> bool:
        return self.depth >= self.max_orders

    @property
    def head_oid(self) -> int:
        return 0 if self.empty else self.slots[0].oid

    @property
    def head_qty(self) -> int:
        return 0 if self.empty else self.slots[0].qty

    @property
    def total_qty(self) -> int:
        return sum(o.qty for o in self.slots)

    def add(self, oid: int, qty: int) -> Rsp:
        if self.full or qty == 0:
            return Rsp(ok=False, oid=oid, qty=0)
        self.slots.append(Order(oid=oid, qty=qty))
        return Rsp(ok=True, oid=oid, qty=qty)

    def match(self, qty: int) -> Rsp:
        if self.empty or qty == 0:
            return Rsp(ok=False, oid=0, qty=0)
        head = self.slots[0]
        take = min(head.qty, qty)
        oid = head.oid
        head.qty -= take
        if head.qty == 0:
            self.slots.pop(0)
        return Rsp(ok=True, oid=oid, qty=take)

    def cancel(self, oid: int) -> Rsp:
        for i, order in enumerate(self.slots):
            if order.oid == oid:
                q = order.qty
                self.slots.pop(i)
                return Rsp(ok=True, oid=oid, qty=q)
        return Rsp(ok=False, oid=oid, qty=0)
