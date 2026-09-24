import unittest

from walkers import fifo_take, midpoint_price, prorata_take


class TestWalkers(unittest.TestCase):
    def test_fifo_oldest_first(self) -> None:
        orders = [[1, 1], [2, 3]]
        fills, took = fifo_take(orders, 2, 9, 100)
        self.assertEqual(took, 2)
        self.assertEqual([(f.maker_oid, f.qty) for f in fills], [(1, 1), (2, 1)])

    def test_prorata_splits_and_oldest_gets_odd_lot(self) -> None:
        orders = [[1, 5], [2, 5]]
        fills, took = prorata_take(orders, 4, 9, 100)
        self.assertEqual(took, 4)
        self.assertEqual([(f.maker_oid, f.qty) for f in fills], [(1, 2), (2, 2)])
        small = [[1, 1], [2, 3]]
        fills, _ = prorata_take(small, 2, 9, 100)
        self.assertEqual([(f.maker_oid, f.qty) for f in fills], [(1, 1), (2, 1)])

    def test_midpoint(self) -> None:
        self.assertEqual(midpoint_price(100, 110), 105)
