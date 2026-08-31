import unittest

from price_level import MAX_ORDERS, PriceLevel


class TestPriceLevel(unittest.TestCase):
    def test_reset_empty(self) -> None:
        p = PriceLevel()
        self.assertTrue(p.empty)
        self.assertFalse(p.full)
        self.assertEqual(p.depth, 0)
        self.assertEqual(p.head_oid, 0)
        self.assertEqual(p.head_qty, 0)
        self.assertEqual(p.total_qty, 0)

    def test_add_three(self) -> None:
        p = PriceLevel()
        r = p.add(1, 100)
        self.assertTrue(r.ok)
        self.assertEqual((r.oid, r.qty), (1, 100))
        self.assertEqual((p.depth, p.head_oid, p.head_qty, p.total_qty), (1, 1, 100, 100))
        self.assertTrue(p.add(2, 50).ok)
        self.assertEqual((p.depth, p.head_oid, p.total_qty), (2, 1, 150))
        self.assertTrue(p.add(3, 25).ok)
        self.assertEqual((p.depth, p.head_oid, p.head_qty, p.total_qty), (3, 1, 100, 175))

    def test_match_partial(self) -> None:
        p = PriceLevel()
        p.add(1, 100)
        p.add(2, 50)
        r = p.match(30)
        self.assertTrue(r.ok)
        self.assertEqual((r.oid, r.qty), (1, 30))
        self.assertEqual((p.depth, p.head_oid, p.head_qty, p.total_qty), (2, 1, 70, 120))

    def test_match_exact_head(self) -> None:
        p = PriceLevel()
        p.add(1, 100)
        p.add(2, 50)
        p.add(3, 25)
        r = p.match(100)
        self.assertTrue(r.ok)
        self.assertEqual((r.oid, r.qty), (1, 100))
        self.assertEqual((p.depth, p.head_oid, p.head_qty, p.total_qty), (2, 2, 50, 75))

    def test_match_over_head(self) -> None:
        p = PriceLevel()
        p.add(1, 10)
        p.add(2, 10)
        r = p.match(25)
        self.assertTrue(r.ok)
        self.assertEqual((r.oid, r.qty), (1, 10))
        self.assertEqual((p.depth, p.head_oid, p.total_qty), (1, 2, 10))

    def test_cancel_middle(self) -> None:
        p = PriceLevel()
        p.add(1, 10)
        p.add(2, 20)
        p.add(3, 30)
        r = p.cancel(2)
        self.assertTrue(r.ok)
        self.assertEqual((r.oid, r.qty), (2, 20))
        self.assertEqual((p.depth, p.head_oid, p.total_qty), (2, 1, 40))
        self.assertTrue(p.cancel(1).ok)
        self.assertEqual((p.depth, p.head_oid, p.head_qty, p.total_qty), (1, 3, 30, 30))

    def test_cancel_head_and_tail(self) -> None:
        p = PriceLevel()
        p.add(1, 10)
        p.add(2, 20)
        p.add(3, 30)
        self.assertTrue(p.cancel(1).ok)
        self.assertEqual((p.depth, p.head_oid, p.total_qty), (2, 2, 50))
        r = p.cancel(3)
        self.assertTrue(r.ok)
        self.assertEqual(r.qty, 30)
        self.assertEqual((p.depth, p.head_oid, p.total_qty), (1, 2, 20))

    def test_cancel_missing(self) -> None:
        p = PriceLevel()
        p.add(1, 10)
        r = p.cancel(99)
        self.assertFalse(r.ok)
        self.assertEqual((p.depth, p.head_oid, p.total_qty), (1, 1, 10))

    def test_rejects(self) -> None:
        p = PriceLevel()
        self.assertFalse(p.match(10).ok)
        self.assertFalse(p.add(1, 0).ok)
        self.assertTrue(p.empty)
        p.add(1, 10)
        self.assertFalse(p.match(0).ok)
        self.assertEqual((p.depth, p.head_qty), (1, 10))

    def test_full(self) -> None:
        p = PriceLevel()
        for i in range(MAX_ORDERS):
            self.assertTrue(p.add(100 + i, 1).ok)
        self.assertTrue(p.full)
        self.assertEqual(p.depth, MAX_ORDERS)
        self.assertEqual(p.total_qty, MAX_ORDERS)
        self.assertFalse(p.add(999, 1).ok)
        self.assertTrue(p.full)
        self.assertTrue(p.cancel(100).ok)
        self.assertFalse(p.full)
        self.assertTrue(p.add(200, 5).ok)
        self.assertEqual(p.depth, MAX_ORDERS)
        self.assertEqual(p.head_oid, 101)

    def test_drain(self) -> None:
        p = PriceLevel()
        p.add(1, 10)
        p.add(2, 10)
        p.add(3, 10)
        self.assertEqual(p.match(10).oid, 1)
        self.assertEqual(p.match(10).oid, 2)
        self.assertEqual(p.match(10).oid, 3)
        self.assertTrue(p.empty)
        self.assertFalse(p.match(10).ok)


if __name__ == "__main__":
    unittest.main()
