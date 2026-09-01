import unittest

from book import SIDE_BUY, SIDE_SELL
from venue import Venue


class TestVenue(unittest.TestCase):
    def test_two_symbols_do_not_cross(self) -> None:
        v = Venue()
        v.limit(1, SIDE_SELL, 100, 10, 1)
        r = v.limit(2, SIDE_BUY, 100, 10, 2)
        self.assertTrue(r.ok)
        self.assertEqual(r.filled_qty, 0)
        self.assertEqual(r.rest_qty, 10)
        self.assertEqual(v.book(1).bbo_ask_qty, 10)
        self.assertEqual(v.book(2).bbo_bid_qty, 10)

    def test_same_symbol_still_matches(self) -> None:
        v = Venue()
        v.limit(1, SIDE_SELL, 100, 10, 1)
        r = v.limit(1, SIDE_BUY, 100, 4, 2)
        self.assertEqual(r.filled_qty, 4)
        self.assertEqual(v.book(1).bbo_ask_qty, 6)

    def test_cancel_scans_books(self) -> None:
        v = Venue()
        v.limit(3, SIDE_BUY, 50, 8, 9)
        r = v.cancel(9)
        self.assertTrue(r.ok)
        self.assertEqual(r.rest_qty, 8)
        self.assertFalse(v.book(3).bbo_bid_valid)


if __name__ == "__main__":
    unittest.main()
