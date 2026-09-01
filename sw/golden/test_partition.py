import unittest

from book import SIDE_BUY, SIDE_SELL
from partition import N_PIPES, PartitionedVenue, pipe_of


class TestPartition(unittest.TestCase):
    def test_hash(self) -> None:
        self.assertEqual(pipe_of(0), 0)
        self.assertEqual(pipe_of(1), 1)
        self.assertEqual(pipe_of(2), 0)
        self.assertEqual(N_PIPES, 2)

    def test_disjoint_pipes(self) -> None:
        v = PartitionedVenue()
        v.limit(0, SIDE_SELL, 100, 10, 1)
        r = v.limit(1, SIDE_BUY, 100, 10, 2)
        self.assertEqual(r.filled_qty, 0)
        self.assertEqual(v.pipe(0), 0)
        self.assertEqual(v.pipe(1), 1)
        self.assertEqual(v.seq[0], 1)
        self.assertEqual(v.seq[1], 1)

    def test_same_symbol_ordered(self) -> None:
        v = PartitionedVenue()
        v.limit(0, SIDE_SELL, 100, 10, 1)
        r = v.limit(0, SIDE_BUY, 100, 4, 2)
        self.assertEqual(r.filled_qty, 4)
        self.assertEqual(v.seq[0], 2)
        self.assertEqual(v.seq[1], 0)

    def test_cancel_routes(self) -> None:
        v = PartitionedVenue()
        v.limit(1, SIDE_BUY, 50, 3, 9)
        r = v.cancel(9)
        self.assertTrue(r.ok)
        self.assertEqual(v.seq[1], 2)
        self.assertFalse(v.book(1).bbo_bid_valid)


if __name__ == "__main__":
    unittest.main()
