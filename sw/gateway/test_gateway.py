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
        self.assertEqual(parse("LIMIT BUY 1 100 10 1"), ("limit", SIDE_BUY, "1", 100, 10, 1))
        self.assertEqual(parse("limit sell 2 105 7 2"), ("limit", SIDE_SELL, "2", 105, 7, 2))
        self.assertEqual(parse("LIMIT BUY BTC 100 10 1"), ("limit", SIDE_BUY, "BTC", 100, 10, 1))

    def test_parse_cancel_bbo_quit(self) -> None:
        self.assertEqual(parse("CANCEL 9"), ("cancel", 9))
        self.assertEqual(parse("BBO"), ("bbo", None))
        self.assertEqual(parse("BBO 3"), ("bbo", "3"))
        self.assertEqual(parse("BBO BTC"), ("bbo", "BTC"))
        self.assertEqual(parse("QUIT"), ("quit",))

    def test_parse_errors(self) -> None:
        with self.assertRaises(ParseError):
            parse("LIMIT HOLD 1 1 1 1")
        with self.assertRaises(ParseError):
            parse("NOPE")


class TestExchangeWal(unittest.TestCase):
    def test_rest_match_cancel_and_replay(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wal = Path(tmp)
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

            p1 = Wal(wal).slice_path(1)
            before = p1.read_text()
            b.limit(1, SIDE_BUY, 99, 1, 3)
            self.assertTrue(b.venue.book(1).bbo_bid_valid)
            self.assertEqual(b.seq, 4)
            self.assertTrue(p1.read_text().startswith(before))

    def test_two_symbols_replay(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wal = Path(tmp)
            a = Exchange(wal)
            a.limit(1, SIDE_BUY, 100, 10, 1)
            a.limit(2, SIDE_SELL, 100, 10, 2)
            cmds = [x for x in Wal(wal).read_all() if x["type"] == "cmd"]
            self.assertEqual(cmds[0]["slice"], 1)
            self.assertEqual(cmds[1]["slice"], 2)
            self.assertEqual(a.venue.seq[1], 1)
            self.assertEqual(a.venue.seq[2], 1)
            b = Exchange(wal)
            self.assertEqual(b.venue.book(1).bbo_bid_qty, 10)
            self.assertEqual(b.venue.book(2).bbo_ask_qty, 10)
            self.assertEqual(b.venue.book(1).bbo_ask_valid, False)

    def test_one_file_per_pipe(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wal = Path(tmp)
            a = Exchange(wal)
            a.limit(1, SIDE_BUY, 100, 10, 1)
            a.limit(2, SIDE_SELL, 100, 10, 2)
            self.assertFalse(Wal(wal).slice_path(0).exists())
            self.assertTrue(Wal(wal).slice_path(1).exists())
            self.assertTrue(Wal(wal).slice_path(2).exists())
            c1 = [x for x in Wal(wal).read_slice(1) if x["type"] == "cmd"]
            c2 = [x for x in Wal(wal).read_slice(2) if x["type"] == "cmd"]
            self.assertEqual(len(c1), 1)
            self.assertEqual(len(c2), 1)
            self.assertEqual(c1[0]["symbol"], 1)
            self.assertEqual(c2[0]["symbol"], 2)
            self.assertEqual(c1[0]["seq"], 1)
            self.assertEqual(c2[0]["seq"], 1)


class TestTwoSlice(unittest.TestCase):
    def test_parent_becomes_two_child_limits(self) -> None:
        from slice_table import SlicedVenue
        from spread import TwoSlice

        venue = SlicedVenue()
        host = TwoSlice(venue)
        parent = 50
        first, second = host.submit(0, SIDE_BUY, 10, 1, 1, SIDE_SELL, 20, 1, parent)
        self.assertIsNone(venue.oids.get(parent))
        self.assertEqual(venue.oids.get(first), 0)
        self.assertEqual(venue.oids.get(second), 1)
        self.assertTrue(venue.book(0).bbo_bid_valid)
        self.assertTrue(venue.book(1).bbo_ask_valid)
        self.assertEqual(host.steps, [first, second])
        host.busy.add(venue.pipe(0))
        host.cancel(parent)
        self.assertTrue(venue.book(0).bbo_bid_valid)
        self.assertFalse(venue.book(1).bbo_ask_valid)
        host.release(venue.pipe(0))
        self.assertFalse(venue.book(0).bbo_bid_valid)


class TestAuction(unittest.TestCase):
    def test_batch_is_ordinary_limits_after_an_off_chip_gap(self) -> None:
        from auction import SIDE_BUY, SIDE_SELL, Auction
        from slice_table import SlicedVenue

        auc = Auction()
        auc.add(1, SIDE_BUY, 2, 1)
        auc.add(1, SIDE_BUY, 1, 2)
        auc.add(1, SIDE_SELL, 2, 3)
        tape = [("slice", {"op": "limit", "symbol": 2, "oid": 9})]
        tape.append(("host", "auction"))
        cmds = auc.cross(100)
        self.assertEqual(len(cmds), 3)
        for cmd in cmds:
            self.assertEqual(cmd["op"], "limit")
            self.assertNotIn("auction", cmd)
            self.assertEqual(cmd["price"], 100)
            tape.append(("slice", cmd))
        self.assertEqual([kind for kind, _ in tape], ["slice", "host", "slice", "slice", "slice"])
        venue = SlicedVenue()
        for cmd in cmds:
            venue.limit(cmd["symbol"], cmd["side"], cmd["price"], cmd["qty"], cmd["oid"])
        book = venue.book(1)
        self.assertEqual(book.bbo_bid_qty, 1)
        self.assertFalse(book.bbo_ask_valid)


class TestHostReject(unittest.TestCase):
    def test_reject_is_on_the_host_and_the_slice(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wal = Path(tmp)
            ex = Exchange(wal)
            ex.limit(1, SIDE_BUY, 10, 1, 1)
            rsp = ex.reject_to_host(1, 9, "auction")
            self.assertFalse(rsp.ok)
            self.assertEqual(rsp.oid, 9)
            self.assertEqual(ex.venue.book(1).bbo_bid_qty, 1)
            slice_recs = [r for r in Wal(wal).read_slice(1) if r["type"] == "host_reject"]
            host_recs = Wal(wal).read_host()
            self.assertEqual(slice_recs[0]["oid"], 9)
            self.assertEqual(host_recs[0]["oid"], 9)
            self.assertEqual(host_recs[0]["slice"], 1)


class TestCli(unittest.TestCase):
    def test_handle_lines(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            exch = Exchange(Path(tmp))
            out = handle_line(exch, "LIMIT BUY 1 100 10 1")
            assert out is not None
            self.assertIn("OK oid=1 filled=0 rest=10 unrested=0 slice=1", out)
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
            exch = Exchange(Path(tmp))
            handle_line(exch, "LIMIT BUY 1 100 10 1")
            out = handle_line(exch, "LIMIT SELL 2 100 10 2")
            assert out is not None
            self.assertNotIn("FILL", out)
            self.assertIn("rest=10", out)


class TestTickersAndMd(unittest.TestCase):
    def test_ticker_intern_and_no_cross(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            exch = Exchange(Path(tmp))
            out = handle_line(exch, "LIMIT BUY BTC 100 10 1")
            assert out is not None
            self.assertIn("OK oid=1", out)
            self.assertIn("sym=BTC", out)
            self.assertIn("MD BBO sym=BTC", out)
            out = handle_line(exch, "LIMIT SELL ETH 100 10 2")
            assert out is not None
            self.assertNotIn("FILL", out)
            self.assertIn("sym=ETH", out)

    def test_ticker_match_and_md_trade(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            exch = Exchange(Path(tmp))
            handle_line(exch, "LIMIT SELL BTC 100 10 1")
            out = handle_line(exch, "LIMIT BUY BTC 100 4 2")
            assert out is not None
            self.assertIn("FILL maker=1 taker=2 price=100 qty=4", out)
            self.assertIn("MD TRADE sym=BTC px=100 qty=4 maker=1 taker=2", out)
            self.assertIn("MD BBO sym=BTC", out)

    def test_integer_still_works(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            exch = Exchange(Path(tmp))
            out = handle_line(exch, "LIMIT BUY 3 10 1 8")
            assert out is not None
            self.assertIn("slice=3", out)

    def test_fill_then_md_trade_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            exch = Exchange(Path(tmp))
            handle_line(exch, "LIMIT SELL BTC 100 10 1")
            out = handle_line(exch, "LIMIT BUY BTC 100 4 2")
            assert out is not None
            fill_at = out.find("FILL maker=1")
            md_at = out.find("MD TRADE sym=BTC")
            self.assertGreaterEqual(fill_at, 0)
            self.assertGreater(md_at, fill_at)

    def test_replay_tickers_eth_does_not_fill_btc(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wal = Path(tmp)
            a = Exchange(wal)
            handle_line(a, "LIMIT BUY BTC 100 10 1")
            handle_line(a, "LIMIT BUY ETH 100 10 2")
            recs = Wal(wal).read_all()
            inst = [x for x in recs if x["type"] == "instrument"]
            self.assertEqual({(x["name"], x["id"]) for x in inst}, {("BTC", 0), ("ETH", 1)})
            b = Exchange(wal)
            self.assertEqual(b.instruments.lookup("BTC"), 0)
            self.assertEqual(b.instruments.lookup("ETH"), 1)
            out = handle_line(b, "LIMIT SELL ETH 100 10 3")
            assert out is not None
            self.assertIn("FILL maker=2 taker=3", out)
            self.assertNotIn("FILL maker=1", out)
            self.assertEqual(b.venue.book(0).bbo_bid_qty, 10)
            self.assertFalse(b.venue.book(1).bbo_bid_valid)

    def test_mixed_int_then_ticker_replay(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wal = Path(tmp)
            a = Exchange(wal)
            handle_line(a, "LIMIT BUY 0 100 10 1")
            handle_line(a, "LIMIT BUY BTC 100 10 2")
            self.assertEqual(a.instruments.lookup("BTC"), 1)
            inst = [x for x in Wal(wal).read_all() if x["type"] == "instrument"]
            self.assertEqual(len(inst), 1)
            b = Exchange(wal)
            self.assertEqual(b.instruments.lookup("BTC"), 1)
            out = handle_line(b, "LIMIT SELL BTC 100 10 3")
            assert out is not None
            self.assertIn("FILL maker=2", out)
            self.assertNotIn("FILL maker=1", out)
            inst = [x for x in Wal(wal).read_all() if x["type"] == "instrument"]
            self.assertEqual(len(inst), 1)

    def test_integer_wal_restart_then_intern_skips_used_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wal = Path(tmp)
            a = Exchange(wal)
            handle_line(a, "LIMIT BUY 0 100 10 1")
            b = Exchange(wal)
            out = handle_line(b, "LIMIT BUY BTC 100 10 2")
            assert out is not None
            self.assertEqual(b.instruments.lookup("BTC"), 1)
            self.assertNotIn("FILL", out)
            out = handle_line(b, "LIMIT SELL BTC 100 10 3")
            assert out is not None
            self.assertIn("FILL maker=2", out)
            self.assertNotIn("FILL maker=1", out)
            self.assertEqual(b.venue.book(0).bbo_bid_qty, 10)

    def test_unknown_cancel_replay_does_not_reserve_zero(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wal = Path(tmp)
            a = Exchange(wal)
            handle_line(a, "CANCEL 999")
            cmds = [x for x in Wal(wal).read_all() if x["type"] == "cmd"]
            self.assertEqual(len(cmds), 1)
            self.assertIsNone(cmds[0]["symbol"])
            b = Exchange(wal)
            out = handle_line(b, "LIMIT BUY BTC 100 10 1")
            assert out is not None
            self.assertEqual(b.instruments.lookup("BTC"), 0)
            self.assertIn("OK oid=1", out)

    def test_unknown_cancel_then_intern_survives_replay(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            wal = Path(tmp)
            a = Exchange(wal)
            handle_line(a, "CANCEL 999")
            handle_line(a, "LIMIT BUY BTC 100 10 1")
            self.assertEqual(a.instruments.lookup("BTC"), 0)
            b = Exchange(wal)
            self.assertEqual(b.instruments.lookup("BTC"), 0)

    def test_bbo_unseen_ticker_does_not_allocate(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            exch = Exchange(Path(tmp))
            handle_line(exch, "LIMIT BUY BTC 100 10 1")
            books_before = set(exch.venue.books)
            names_before = dict(exch.instruments._name_to_id)
            out = handle_line(exch, "BBO ZZZ")
            self.assertEqual(out, "BBO bid=- ask=-\n")
            self.assertEqual(set(exch.venue.books), books_before)
            self.assertEqual(exch.instruments._name_to_id, names_before)
            self.assertIsNone(exch.instruments.lookup("ZZZ"))

    def test_bbo_known_ticker_no_new_book(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            exch = Exchange(Path(tmp))
            handle_line(exch, "LIMIT BUY BTC 100 10 1")
            n = len(exch.venue.books)
            out = handle_line(exch, "BBO BTC")
            assert out is not None
            self.assertIn("sym=BTC", out)
            self.assertIn("bid=100:10", out)
            self.assertEqual(len(exch.venue.books), n)

    def test_unknown_cancel_has_no_md(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            exch = Exchange(Path(tmp))
            handle_line(exch, "LIMIT BUY BTC 100 10 1")
            out = handle_line(exch, "CANCEL 999")
            assert out is not None
            self.assertIn("NAK oid=999", out)
            self.assertNotIn("MD ", out)
            self.assertIn("BBO bid=- ask=-", out)
            self.assertEqual(exch.venue.book(0).bbo_bid_qty, 10)

    def test_invalid_ticker_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            exch = Exchange(Path(tmp))
            out = handle_line(exch, "LIMIT BUY +1 100 10 1")
            assert out is not None
            self.assertTrue(out.startswith("ERR"))
            self.assertEqual(exch.venue.books, {})


if __name__ == "__main__":
    unittest.main()
