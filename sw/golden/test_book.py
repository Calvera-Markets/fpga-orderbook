import unittest

from book import SIDE_BUY, SIDE_SELL, Book


class TestBook(unittest.TestCase):
    def test_rest_no_cross(self) -> None:
        b = Book()
        r = b.limit(SIDE_BUY, 100, 10, 1)
        self.assertTrue(r.ok)
        self.assertEqual((r.filled_qty, r.rest_qty), (0, 10))
        r = b.limit(SIDE_SELL, 105, 7, 2)
        self.assertTrue(r.ok)
        self.assertEqual(r.rest_qty, 7)
        self.assertTrue(b.bbo_bid_valid and b.bbo_ask_valid)
        self.assertEqual((b.bbo_bid_px, b.bbo_bid_qty), (100, 10))
        self.assertEqual((b.bbo_ask_px, b.bbo_ask_qty), (105, 7))
        self.assertEqual(r.fills, [])

    def test_full_fill_one_ask(self) -> None:
        b = Book()
        b.limit(SIDE_SELL, 100, 10, 1)
        r = b.limit(SIDE_BUY, 100, 10, 2)
        self.assertTrue(r.ok)
        self.assertEqual((r.filled_qty, r.rest_qty), (10, 0))
        self.assertEqual(len(r.fills), 1)
        self.assertEqual(
            (r.fills[0].maker_oid, r.fills[0].taker_oid, r.fills[0].price, r.fills[0].qty),
            (1, 2, 100, 10),
        )
        self.assertFalse(b.bbo_ask_valid)
        self.assertFalse(b.bbo_bid_valid)

    def test_partial_then_rest(self) -> None:
        b = Book()
        b.limit(SIDE_SELL, 100, 10, 1)
        r = b.limit(SIDE_BUY, 100, 25, 2)
        self.assertTrue(r.ok)
        self.assertEqual((r.filled_qty, r.rest_qty), (10, 15))
        self.assertEqual(r.fills[0].qty, 10)
        self.assertFalse(b.bbo_ask_valid)
        self.assertEqual((b.bbo_bid_px, b.bbo_bid_qty), (100, 15))

    def test_walk_two_prices_time_priority(self) -> None:
        b = Book()
        b.limit(SIDE_SELL, 100, 4, 1)
        b.limit(SIDE_SELL, 100, 6, 2)
        b.limit(SIDE_SELL, 105, 50, 3)
        r = b.limit(SIDE_BUY, 105, 15, 9)
        self.assertTrue(r.ok)
        self.assertEqual(r.filled_qty, 15)
        self.assertEqual(r.rest_qty, 0)
        self.assertEqual(
            [(f.maker_oid, f.price, f.qty) for f in r.fills],
            [(1, 100, 4), (2, 100, 6), (3, 105, 5)],
        )
        self.assertEqual((b.bbo_ask_px, b.bbo_ask_qty), (105, 45))

    def test_cancel_updates_bbo(self) -> None:
        b = Book()
        b.limit(SIDE_BUY, 100, 10, 1)
        b.limit(SIDE_BUY, 99, 8, 2)
        r = b.cancel(1)
        self.assertTrue(r.ok)
        self.assertEqual(r.rest_qty, 10)
        self.assertEqual((b.bbo_bid_px, b.bbo_bid_qty), (99, 8))

    def test_cancel_middle_keeps_time(self) -> None:
        b = Book()
        b.limit(SIDE_BUY, 100, 1, 1)
        b.limit(SIDE_BUY, 100, 1, 2)
        b.limit(SIDE_BUY, 100, 1, 3)
        b.cancel(2)
        r = b.limit(SIDE_SELL, 100, 2, 9)
        self.assertEqual([f.maker_oid for f in r.fills], [1, 3])

    def test_cancel_missing(self) -> None:
        b = Book()
        b.limit(SIDE_BUY, 100, 10, 1)
        r = b.cancel(99)
        self.assertFalse(r.ok)
        self.assertEqual(b.bbo_bid_qty, 10)

    def test_price_outside_window_does_not_rest(self) -> None:
        b = Book()
        r = b.limit(SIDE_BUY, 200, 4, 1)
        self.assertFalse(r.ok)
        self.assertEqual(r.unrested_qty, 4)
        self.assertFalse(b.bbo_bid_valid)

    def test_qty_zero_rejected(self) -> None:
        b = Book()
        r = b.limit(SIDE_BUY, 100, 0, 1)
        self.assertFalse(r.ok)
        self.assertFalse(b.bbo_bid_valid)

    def test_take_whole_side_then_rest(self) -> None:
        b = Book()
        b.limit(SIDE_SELL, 100, 5, 1)
        r = b.limit(SIDE_BUY, 110, 20, 2)
        self.assertTrue(r.ok)
        self.assertEqual((r.filled_qty, r.rest_qty), (5, 15))
        self.assertFalse(b.bbo_ask_valid)
        self.assertEqual((b.bbo_bid_px, b.bbo_bid_qty), (110, 15))

    def test_sell_crosses_bid(self) -> None:
        b = Book()
        b.limit(SIDE_BUY, 100, 8, 1)
        r = b.limit(SIDE_SELL, 90, 3, 2)
        self.assertTrue(r.ok)
        self.assertEqual((r.filled_qty, r.rest_qty), (3, 0))
        self.assertEqual(r.fills[0].maker_oid, 1)
        self.assertEqual(r.fills[0].price, 100)
        self.assertEqual((b.bbo_bid_px, b.bbo_bid_qty), (100, 5))

    def test_same_price_aggregates_bbo(self) -> None:
        b = Book()
        b.limit(SIDE_BUY, 100, 10, 1)
        b.limit(SIDE_BUY, 100, 7, 2)
        self.assertEqual(b.bbo_bid_qty, 17)


if __name__ == "__main__":
    unittest.main()
