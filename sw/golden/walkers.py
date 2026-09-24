"""Per-slice match rules over one price queue. Odd lots in pro-rata go to the oldest."""

from __future__ import annotations

def fifo_take(orders: list[list[int]], qty: int, taker: int, price: int) -> tuple[list, int]:
    from book import Fill

    fills: list[Fill] = []
    left = qty
    i = 0
    while left and i < len(orders):
        oid, have = orders[i]
        take = min(have, left)
        if take:
            fills.append(Fill(oid, taker, price, take))
            orders[i][1] = have - take
            left -= take
        if orders[i][1] == 0:
            i += 1
    orders[:] = [o for o in orders if o[1] > 0]
    return fills, qty - left


def prorata_take(orders: list[list[int]], qty: int, taker: int, price: int) -> tuple[list, int]:
    from book import Fill
    total = sum(o[1] for o in orders)
    if total == 0 or qty == 0:
        return [], 0
    take = min(qty, total)
    raw = [take * o[1] // total for o in orders]
    spare = take - sum(raw)
    for i in range(len(orders)):
        if spare == 0:
            break
        room = orders[i][1] - raw[i]
        give = min(room, spare)
        raw[i] += give
        spare -= give
    fills: list[Fill] = []
    for order, part in zip(orders, raw):
        if part:
            fills.append(Fill(order[0], taker, price, part))
            order[1] -= part
    orders[:] = [o for o in orders if o[1] > 0]
    return fills, take


def midpoint_price(bid: int, ask: int) -> int:
    return (bid + ask) // 2
