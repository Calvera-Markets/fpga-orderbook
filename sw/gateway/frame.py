"""Fixed order word. The text line becomes this word and does not call a book."""

from __future__ import annotations

import struct

SIDE_BUY = 0
SIDE_SELL = 1
OP_LIMIT = 0
OP_CANCEL = 1

# session, op, side, symbol, price, qty, oid
_FMT = "<BBBHIIQ"


def pack(session: int, op: int, side: int, symbol: int, price: int, qty: int, oid: int) -> bytes:
    return struct.pack(_FMT, session & 0xFF, op & 0xFF, side & 0xFF, symbol & 0xFFFF,
                       price & 0xFFFFFFFF, qty & 0xFFFFFFFF, oid & 0xFFFFFFFFFFFFFFFF)


def unpack(word: bytes) -> tuple[int, int, int, int, int, int, int]:
    session, op, side, symbol, price, qty, oid = struct.unpack(_FMT, word)
    return session, op, side, symbol, price, qty, oid


def from_line(line: str) -> bytes:
    parts = line.split()
    if len(parts) != 6 or parts[0].upper() != "LIMIT":
        raise ValueError("usage: LIMIT BUY|SELL <sym> <price> <qty> <oid>")
    side_tok = parts[1].upper()
    if side_tok == "BUY":
        side = SIDE_BUY
    elif side_tok == "SELL":
        side = SIDE_SELL
    else:
        raise ValueError("side must be BUY or SELL")
    symbol, price, qty, oid = (int(parts[2]), int(parts[3]), int(parts[4]), int(parts[5]))
    return pack(0, OP_LIMIT, side, symbol, price, qty, oid)
