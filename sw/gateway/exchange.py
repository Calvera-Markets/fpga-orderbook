"""Sliced venue + WAL. seq is per slice."""

from __future__ import annotations

import sys
from pathlib import Path

_GOLDEN = Path(__file__).resolve().parent.parent / "golden"
if str(_GOLDEN) not in sys.path:
    sys.path.insert(0, str(_GOLDEN))

from book import SIDE_BUY, BookRsp  # noqa: E402
from slice_table import SlicedVenue

from instruments import Instruments
from wal import Wal


class Exchange:
    def __init__(self, wal_path: Path, engine=None) -> None:
        self.venue = engine if engine is not None else SlicedVenue()
        self.instruments = Instruments()
        self.wal = Wal(wal_path, n_slices=len(self.venue.seq))
        self._replay()

    @property
    def seq(self) -> int:
        return sum(self.venue.seq)

    def intern_symbol(self, token: str) -> int:
        sid, new = self.instruments.intern(token)
        if new:
            self.wal.append(
                {"type": "instrument", "name": token.upper(), "id": sid},
                self.venue.pipe(sid),
            )
        return sid

    def _replay(self) -> None:
        for s in range(self.wal.n_slices):
            for rec in self.wal.read_slice(s):
                kind = rec.get("type")
                if kind == "instrument":
                    self.instruments.bind(str(rec["name"]), int(rec["id"]))
                    continue
                if kind != "cmd":
                    continue
                sl = int(rec.get("slice", s))
                op = rec["op"]
                if op == "limit":
                    symbol = int(rec["symbol"])
                    self.instruments.reserve(symbol)
                    table = getattr(self.venue, "table", None)
                    if table is not None:
                        table.assign(symbol, sl)
                    self.venue.limit(
                        symbol,
                        int(rec["side"]),
                        int(rec["price"]),
                        int(rec["qty"]),
                        int(rec["oid"]),
                        bump=False,
                    )
                    self.venue.seq[sl] = max(self.venue.seq[sl], int(rec["seq"]))
                elif op == "cancel":
                    oid = int(rec["oid"])
                    symbol = self.venue.oids.get(oid)
                    if symbol is not None:
                        self.instruments.reserve(symbol)
                    self.venue.cancel(oid, bump=False)
                    self.venue.seq[sl] = max(self.venue.seq[sl], int(rec["seq"]))

    def _log_cmd(self, rec: dict, slice_id: int, seq: int) -> None:
        rec = dict(rec)
        rec["type"] = "cmd"
        rec["slice"] = slice_id
        rec["seq"] = seq
        self.wal.append(rec, slice_id)

    def _log_result(self, rsp: BookRsp, slice_id: int, seq: int) -> None:
        self.wal.append(
            {
                "type": "rsp",
                "slice": slice_id,
                "seq": seq,
                "ok": rsp.ok,
                "oid": rsp.oid,
                "filled": rsp.filled_qty,
                "rest": rsp.rest_qty,
                "unrested": rsp.unrested_qty,
            },
            slice_id,
        )
        for fill in rsp.fills:
            self.wal.append(
                {
                    "type": "fill",
                    "slice": slice_id,
                    "seq": seq,
                    "maker": fill.maker_oid,
                    "taker": fill.taker_oid,
                    "price": fill.price,
                    "qty": fill.qty,
                },
                slice_id,
            )

    def limit(self, symbol: int, side: int, price: int, qty: int, oid: int) -> BookRsp:
        p = self.venue.pipe(symbol)
        rsp = self.venue.limit(symbol, side, price, qty, oid)
        self._log_cmd(
            {
                "op": "limit",
                "symbol": symbol,
                "side": side,
                "price": price,
                "qty": qty,
                "oid": oid,
            },
            p,
            self.venue.seq[p],
        )
        self._log_result(rsp, p, self.venue.seq[p])
        return rsp

    def cancel(self, oid: int) -> BookRsp:
        symbol = self.venue.oids.get(oid)
        p = self.venue.pipe(symbol) if symbol is not None else 0
        rsp = self.venue.cancel(oid)
        self._log_cmd(
            {
                "op": "cancel",
                "symbol": symbol,
                "side": SIDE_BUY,
                "price": 0,
                "qty": 0,
                "oid": oid,
            },
            p,
            self.venue.seq[p],
        )
        self._log_result(rsp, p, self.venue.seq[p])
        return rsp
