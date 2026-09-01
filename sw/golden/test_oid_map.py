import unittest

from book import SIDE_BUY, SIDE_SELL
from venue import Venue


class TestOidMap(unittest.TestCase):
    def test_cancel_without_symbol(self) -> None:
        v = Venue()
        v.limit(4, SIDE_BUY, 10, 5, 77)
        r = v.cancel(77)
        self.assertTrue(r.ok)
        self.assertEqual(r.rest_qty, 5)
        self.assertIsNone(v.oids.get(77))
        self.assertFalse(v.book(4).bbo_bid_valid)

    def test_unknown_oid_nak(self) -> None:
        v = Venue()
        v.limit(1, SIDE_BUY, 10, 5, 1)
        r = v.cancel(99)
        self.assertFalse(r.ok)
        self.assertEqual(v.book(1).bbo_bid_qty, 5)

    def test_full_fill_drops_maker_oid(self) -> None:
        v = Venue()
        v.limit(1, SIDE_SELL, 100, 10, 1)
        v.limit(1, SIDE_BUY, 100, 10, 2)
        self.assertIsNone(v.oids.get(1))
        self.assertIsNone(v.oids.get(2))

    def test_partial_keeps_maker_oid(self) -> None:
        v = Venue()
        v.limit(1, SIDE_SELL, 100, 10, 1)
        v.limit(1, SIDE_BUY, 100, 3, 2)
        self.assertEqual(v.oids.get(1), 1)
        r = v.cancel(1)
        self.assertTrue(r.ok)
        self.assertEqual(r.rest_qty, 7)


if __name__ == "__main__":
    unittest.main()
