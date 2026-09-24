import unittest

from book import SIDE_BUY, SIDE_SELL
from slice_table import N_SLICES, SliceAssignError, SliceTable, SlicedVenue


class TestSliceTable(unittest.TestCase):
    def test_two_hot_names_cannot_share(self) -> None:
        table = SliceTable()
        table.assign(10, 0, hot=True)
        with self.assertRaises(SliceAssignError):
            table.assign(11, 0, hot=True)
        self.assertEqual(table.owner(0), 10)
        self.assertEqual(table.slice_of(10), 0)

    def test_two_slices_do_not_cross(self) -> None:
        v = SlicedVenue()
        v.table.assign(10, 0, hot=True)
        v.table.assign(11, 1, hot=True)
        v.limit(10, SIDE_SELL, 100, 10, 1)
        r = v.limit(11, SIDE_BUY, 100, 10, 2)
        self.assertEqual(r.filled_qty, 0)
        self.assertEqual(r.rest_qty, 10)
        self.assertEqual(v.book(10).bbo_ask_qty, 10)
        self.assertEqual(v.book(11).bbo_bid_qty, 10)
        self.assertEqual(v.pipe(10), 0)
        self.assertEqual(v.pipe(11), 1)
        self.assertEqual(N_SLICES, 4)

    def test_default_symbol_lands_on_its_index(self) -> None:
        v = SlicedVenue()
        v.limit(1, SIDE_BUY, 100, 4, 1)
        v.limit(2, SIDE_SELL, 100, 4, 2)
        self.assertEqual(v.pipe(1), 1)
        self.assertEqual(v.pipe(2), 2)
        self.assertEqual(v.book(1).bbo_bid_qty, 4)
        self.assertFalse(v.book(2).bbo_bid_valid)
