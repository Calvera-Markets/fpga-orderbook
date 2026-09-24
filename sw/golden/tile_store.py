"""Timed backing store. Fetch and writeback are cycle counts, not a sleep."""

from __future__ import annotations

from tile import Tile

FETCH_CYCLES = 4
WRITEBACK_CYCLES = 4


class TileStore:
    def __init__(self) -> None:
        self.mem: dict[tuple[int, int, int], Tile] = {}
        self.touch: dict[tuple[int, int], int] = {}
        self.wait: dict[int, int] = {}

    def access(self, symbol: int, side: int, price: int) -> Tile:
        key = (symbol, side, price)
        resident = self.touch.get((symbol, side))
        if resident == price and key in self.mem:
            self.wait[symbol] = 0
            return self.mem[key]
        cycles = FETCH_CYCLES
        if resident is not None:
            cycles += WRITEBACK_CYCLES
        self.wait[symbol] = cycles
        self.touch[(symbol, side)] = price
        return self.mem.setdefault(key, Tile(symbol, side, price))
