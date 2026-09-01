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
        self.assertEqual(parse("LIMIT BUY 100 10 1"), ("limit", SIDE_BUY, 100, 10, 1))
        self.assertEqual(parse("limit sell 105 7 2"), ("limit", SIDE_SELL, 105, 7, 2))

    def test_parse_cancel_bbo_quit(self) -> None:
        self.assertEqual(parse("CANCEL 9"), ("cancel", 9))
        self.assertEqual(parse("BBO"), ("bbo",))
        self.assertEqual(parse("QUIT"), ("quit",))

    def test_parse_errors(self) -> None:
        with self.assertRaises(ParseError):
            parse("LIMIT HOLD 1 1 1")
        with self.assertRaises(ParseError):
            parse("NOPE")


class TestExchangeWal(unittest.TestCase):
    def test_rest_match_cancel_and_replay(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wal = Path(tmp) / "exch.wal"
            a = Exchange(wal)
            r = a.limit(SIDE_SELL, 100, 10, 1)
            self.assertTrue(r.ok)
            r = a.limit(SIDE_BUY, 100, 4, 2)
            self.assertEqual(r.filled_qty, 4)
            self.assertEqual(len(r.fills), 1)
            r = a.cancel(1)
            self.assertTrue(r.ok)
            self.assertEqual(r.rest_qty, 6)
            self.assertFalse(a.book.bbo_ask_valid)

            recs = Wal(wal).read_all()
            cmds = [x for x in recs if x["type"] == "cmd"]
            self.assertEqual(len(cmds), 3)
            self.assertEqual(a.seq, 3)

            b = Exchange(wal)
            self.assertEqual(b.seq, 3)
            self.assertFalse(b.book.bbo_ask_valid)
            self.assertFalse(b.book.bbo_bid_valid)

            before = wal.read_text()
            b.limit(SIDE_BUY, 99, 1, 3)
            self.assertTrue(b.book.bbo_bid_valid)
            self.assertEqual(b.seq, 4)
            self.assertTrue(wal.read_text().startswith(before))

    def test_replay_restores_bbo(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wal = Path(tmp) / "exch.wal"
            a = Exchange(wal)
            a.limit(SIDE_BUY, 100, 10, 1)
            a.limit(SIDE_SELL, 105, 7, 2)
            b = Exchange(wal)
            self.assertEqual((b.book.bbo_bid_px, b.book.bbo_bid_qty), (100, 10))
            self.assertEqual((b.book.bbo_ask_px, b.book.bbo_ask_qty), (105, 7))


class TestCli(unittest.TestCase):
    def test_handle_lines(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            exch = Exchange(Path(tmp) / "exch.wal")
            out = handle_line(exch, "LIMIT BUY 100 10 1")
            self.assertIsNotNone(out)
            assert out is not None
            self.assertIn("OK oid=1 filled=0 rest=10", out)
            self.assertIn("BBO bid=100:10 ask=-", out)
            out = handle_line(exch, "LIMIT SELL 100 10 2")
            assert out is not None
            self.assertIn("FILL maker=1 taker=2 price=100 qty=10", out)
            self.assertIn("OK oid=2 filled=10 rest=0", out)
            self.assertIn("BBO bid=- ask=-", out)
            out = handle_line(exch, "BBO")
            self.assertEqual(out, "BBO bid=- ask=-\n")
            self.assertIsNone(handle_line(exch, "QUIT"))
            err = handle_line(exch, "FLUB")
            self.assertTrue(err and err.startswith("ERR"))


if __name__ == "__main__":
    unittest.main()
