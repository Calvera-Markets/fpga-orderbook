"""Gateway on the Verilator partitioned_engine. Skips if libpe.so is missing."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

_GOLDEN = Path(__file__).resolve().parent.parent / "golden"
if str(_GOLDEN) not in sys.path:
    sys.path.insert(0, str(_GOLDEN))

from book import SIDE_BUY, SIDE_SELL  # noqa: E402
from exchange import Exchange
from main import handle_line
from rtl_engine import RtlEngine, lib_available
from wal import Wal


class TestRtlGateway(unittest.TestCase):
    def setUp(self) -> None:
        if not lib_available():
            self.skipTest("libpe.so not built (make lib)")

    def _ex(self, wal: Path) -> Exchange:
        return Exchange(wal, engine=RtlEngine())

    def test_rest_match_and_md(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            exch = self._ex(Path(tmp))
            out = handle_line(exch, "LIMIT SELL 1 100 10 1")
            assert out is not None
            self.assertIn("OK oid=1", out)
            self.assertIn("pipe=1", out)
            self.assertIn("MD BBO", out)
            out = handle_line(exch, "LIMIT BUY 1 100 4 2")
            assert out is not None
            self.assertIn("FILL maker=1 taker=2 price=100 qty=4", out)
            self.assertIn("MD TRADE sym=1 px=100 qty=4 maker=1 taker=2", out)

    def test_no_cross_and_ticker(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            exch = self._ex(Path(tmp))
            handle_line(exch, "LIMIT BUY BTC 100 10 1")
            out = handle_line(exch, "LIMIT SELL ETH 100 10 2")
            assert out is not None
            self.assertNotIn("FILL", out)
            out = handle_line(exch, "LIMIT SELL BTC 100 10 3")
            assert out is not None
            self.assertIn("FILL maker=1 taker=3", out)

    def test_cancel_and_replay(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wal = Path(tmp)
            a = self._ex(wal)
            a.limit(1, SIDE_SELL, 100, 10, 1)
            r = a.limit(1, SIDE_BUY, 100, 4, 2)
            self.assertEqual(r.filled_qty, 4)
            r = a.cancel(1)
            self.assertTrue(r.ok)
            self.assertEqual(r.rest_qty, 6)
            cmds = [x for x in Wal(wal).read_all() if x["type"] == "cmd"]
            self.assertEqual(len(cmds), 3)
            b = self._ex(wal)
            self.assertEqual(b.seq, 3)
            self.assertFalse(b.venue.book(1).bbo_ask_valid)
            r = b.limit(1, SIDE_BUY, 99, 1, 3)
            self.assertTrue(b.venue.book(1).bbo_bid_valid)
            self.assertEqual(r.rest_qty, 1)


if __name__ == "__main__":
    unittest.main()
