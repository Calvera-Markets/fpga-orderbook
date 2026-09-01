"""Ticker strings live only at the gateway. The engine sees dense integer ids."""

from __future__ import annotations


class Instruments:
    def __init__(self) -> None:
        self._name_to_id: dict[str, int] = {}
        self._id_to_name: dict[int, str] = {}
        self._used: set[int] = set()
        self._next = 0

    def intern(self, token: str) -> int:
        if token.isdigit() or (token.startswith("-") and token[1:].isdigit()):
            sid = int(token)
            self._used.add(sid)
            return sid
        name = token.upper()
        if name in self._name_to_id:
            return self._name_to_id[name]
        while self._next in self._used:
            self._next += 1
        sid = self._next
        self._next += 1
        self._used.add(sid)
        self._name_to_id[name] = sid
        self._id_to_name[sid] = name
        return sid

    def label(self, symbol: int | None) -> str:
        if symbol is None:
            return "-"
        return self._id_to_name.get(symbol, str(symbol))
