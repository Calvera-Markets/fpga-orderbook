"""Ticker strings live only at the gateway. The engine sees dense integer ids."""

from __future__ import annotations

import re

# Unambiguous vs integer tokens: must start with a letter.
TICKER_RE = re.compile(r"^[A-Z][A-Z0-9._-]{0,15}$")


def is_int_token(token: str) -> bool:
    return token.isdigit()


class Instruments:
    def __init__(self) -> None:
        self._name_to_id: dict[str, int] = {}
        self._id_to_name: dict[int, str] = {}
        self._used: set[int] = set()
        self._next = 0

    def bind(self, name: str, sid: int) -> None:
        name = name.upper()
        if not TICKER_RE.match(name):
            raise ValueError(f"invalid ticker {name!r}")
        if sid < 0:
            raise ValueError("symbol id must be >= 0")
        have = self._name_to_id.get(name)
        if have is not None and have != sid:
            raise ValueError(f"{name} already bound to {have}")
        owner = self._id_to_name.get(sid)
        if owner is not None and owner != name:
            raise ValueError(f"id {sid} already bound to {owner}")
        self._name_to_id[name] = sid
        self._id_to_name[sid] = name
        self.reserve(sid)

    def reserve(self, sid: int) -> None:
        self._used.add(sid)
        if sid >= self._next:
            self._next = sid + 1

    def lookup(self, token: str) -> int | None:
        """Resolve without allocating. Unknown ticker → None."""
        if is_int_token(token):
            return int(token)
        name = token.upper()
        if not TICKER_RE.match(name):
            return None
        return self._name_to_id.get(name)

    def intern(self, token: str) -> tuple[int, bool]:
        """Return (id, newly_bound_ticker). Integers only reserve the id."""
        if is_int_token(token):
            sid = int(token)
            self.reserve(sid)
            return sid, False
        name = token.upper()
        if not TICKER_RE.match(name):
            raise ValueError("invalid ticker")
        if name in self._name_to_id:
            return self._name_to_id[name], False
        while self._next in self._used:
            self._next += 1
        sid = self._next
        self.bind(name, sid)
        return sid, True

    def label(self, symbol: int | None) -> str:
        if symbol is None:
            return "-"
        return self._id_to_name.get(symbol, str(symbol))
