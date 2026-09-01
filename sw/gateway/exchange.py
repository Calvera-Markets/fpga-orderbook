"""Book + WAL: apply commands, persist, replay on start."""

from __future__ import annotations

import sys
from pathlib import Path

_GOLDEN = Path(__file__).resolve().parent.parent / "golden"
if str(_GOLDEN) not in sys.path:
    sys.path.insert(0, str(_GOLDEN))

from book import SIDE_BUY, Book, BookRsp  # noqa: E402

from wal import Wal


class Exchange:
    def __init__(self, wal_path: Path) -> None:
        self.book = Book()
        self.wal = Wal(wal_path)
        self.seq = 0
        self._replay()

    def _replay(self) -> None:
        for rec in self.wal.read_all():
            if rec.get("type") != "cmd":
                continue
            self.seq = max(self.seq, int(rec["seq"]))
            op = rec["op"]
            if op == "limit":
                self.book.limit(int(rec["side"]), int(rec["price"]), int(rec["qty"]), int(rec["oid"]))
            elif op == "cancel":
                self.book.cancel(int(rec["oid"]))

    def _log_cmd(self, rec: dict) -> None:
        self.seq += 1
        rec = dict(rec)
        rec["type"] = "cmd"
        rec["seq"] = self.seq
        self.wal.append(rec)

    def _log_result(self, rsp: BookRsp) -> None:
        self.wal.append(
            {
                "type": "rsp",
                "seq": self.seq,
                "ok": rsp.ok,
                "oid": rsp.oid,
                "filled": rsp.filled_qty,
                "rest": rsp.rest_qty,
                "unrested": rsp.unrested_qty,
            }
        )
        for fill in rsp.fills:
            self.wal.append(
                {
                    "type": "fill",
                    "seq": self.seq,
                    "maker": fill.maker_oid,
                    "taker": fill.taker_oid,
                    "price": fill.price,
                    "qty": fill.qty,
                }
            )

    def limit(self, side: int, price: int, qty: int, oid: int) -> BookRsp:
        self._log_cmd(
            {
                "op": "limit",
                "side": side,
                "price": price,
                "qty": qty,
                "oid": oid,
            }
        )
        rsp = self.book.limit(side, price, qty, oid)
        self._log_result(rsp)
        return rsp

    def cancel(self, oid: int) -> BookRsp:
        self._log_cmd({"op": "cancel", "side": SIDE_BUY, "price": 0, "qty": 0, "oid": oid})
        rsp = self.book.cancel(oid)
        self._log_result(rsp)
        return rsp
