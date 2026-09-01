import tempfile
import unittest
from pathlib import Path

from exchange import Exchange
from main import handle_line
from protocol import ParseError, parse
from wal import Wal

import sys as _sys

_GOLDEN = Path(__file__).resolve().parent.parent / "golden"
if str(_GOLDEN) not in _sys.path:
    _sys.path.insert(0, str(_GOLDEN))

from book import SIDE_BUY, SIDE_SELL  # noqa: E402


class TestProtocol(unittest.TestCase):
    def test_parse_limit(self) -> None:
        self.assertEqual(parse("LIMIT BUY 1 100 10 1"), ("limit", SIDE_BUY, 1, 100, 10, 1))
        self.assertEqual(parse("limit sell 2 105 7 2"), ("limit", SIDE_SELL, 2, 105, 7, 2))

    def test_parse_cancel_bbo_quit(self) -> None:
        self.assertEqual(parse("CANCEL 9"), ("cancel", 9))
        self.assertEqual(parse("BBO"), ("bbo", None))
        self.assertEqual(parse("BBO 3"), ("bbo", 3))
        self.assertEqual(parse("QUIT"), ("quit",))

    def test_parse_errors(self) -> None:
        with self.assertRaises(ParseError):
            parse("LIMIT HOLD 1 1 1 1")
        with self.assertRaises(ParseError):
            parse("NOPE")


class TestExchangeWal(unittest.TestCase):
    def test_rest_match_cancel_and_replay(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wal = Path(tmp) / "exch.wal"
            a = Exchange(wal)
            r = a.limit(1, SIDE_SELL, 100, 10, 1)
            self.assertTrue(r.ok)
            r = a.limit(1, SIDE_BUY, 100, 4, 2)
            self.assertEqual(r.filled_qty, 4)
            r = a.cancel(1)
            self.assertTrue(r.ok)
            self.assertEqual(r.rest_qty, 6)

            recs = Wal(wal).read_all()
            cmds = [x for x in recs if x["type"] == "cmd"]
            self.assertEqual(len(cmds), 3)
            self.assertEqual(cmds[0]["symbol"], 1)
            self.assertEqual(a.seq, 3)

            b = Exchange(wal)
            self.assertEqual(b.seq, 3)
            self.assertFalse(b.venue.book(1).bbo_ask_valid)

            before = wal.read_text()
            b.limit(1, SIDE_BUY, 99, 1, 3)
            self.assertTrue(b.venue.book(1).bbo_bid_valid)
            self.assertEqual(b.seq, 4)
            self.assertTrue(wal.read_text().startswith(before))

    def test_two_symbols_replay(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wal = Path(tmp) / "exch.wal"
            a = Exchange(wal)
            a.limit(1, SIDE_BUY, 100, 10, 1)
            a.limit(2, SIDE_SELL, 100, 10, 2)
            cmds = [x for x in Wal(wal).read_all() if x["type"] == "cmd"]
            self.assertEqual(cmds[0]["pipe"], 1)
            self.assertEqual(cmds[1]["pipe"], 0)
            self.assertEqual(a.venue.seq[1], 1)
            self.assertEqual(a.venue.seq[0], 1)
            b = Exchange(wal)
            self.assertEqual(b.venue.book(1).bbo_bid_qty, 10)
            self.assertEqual(b.venue.book(2).bbo_ask_qty, 10)
            self.assertEqual(b.venue.book(1).bbo_ask_valid, False)


class TestCli(unittest.TestCase):
    def test_handle_lines(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            exch = Exchange(Path(tmp) / "exch.wal")
            out = handle_line(exch, "LIMIT BUY 1 100 10 1")
            assert out is not None
            self.assertIn("OK oid=1 filled=0 rest=10", out)
            self.assertIn("bid=100:10", out)
            out = handle_line(exch, "LIMIT SELL 1 100 10 2")
            assert out is not None
            self.assertIn("FILL maker=1 taker=2 price=100 qty=10", out)
            out = handle_line(exch, "BBO 1")
            self.assertIn("sym=1", out)
            self.assertIsNone(handle_line(exch, "QUIT"))
            err = handle_line(exch, "FLUB")
            self.assertTrue(err and err.startswith("ERR"))

    def test_no_cross_book_fill(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            exch = Exchange(Path(tmp) / "exch.wal")
            handle_line(exch, "LIMIT BUY 1 100 10 1")
            out = handle_line(exch, "LIMIT SELL 2 100 10 2")
            assert out is not None
            self.assertNotIn("FILL", out)
            self.assertIn("rest=10", out)


if __name__ == "__main__":
    unittest.main()
