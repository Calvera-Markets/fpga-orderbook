import unittest

from book import SIDE_BUY, Book
from tile import Tile


class TestTile(unittest.TestCase):
    def test_miss_on_one_book_does_not_delay_another(self) -> None:
        a = Book()
        b = Book()
        a.limit(SIDE_BUY, 100, 1, 1)
        self.assertEqual(a.last_wait, 0)
        a.limit(SIDE_BUY, 105, 1, 2)
        self.assertEqual(a.last_wait, 4)
        b.limit(SIDE_BUY, 100, 1, 3)
        self.assertEqual(b.last_wait, 0)
        self.assertEqual(a.touch[SIDE_BUY], 105)
        self.assertEqual(b.touch[SIDE_BUY], 100)


class TestTileRecord(unittest.TestCase):
    def test_round_trip_keeps_oldest_first(self) -> None:
        tile = Tile(symbol=1, side=SIDE_BUY, price=100)
        tile.add(1, 4)
        tile.add(2, 1)
        tile.add(3, 9)
        self.assertEqual(tile.oldest_first(), [(1, 4), (2, 1), (3, 9)])
