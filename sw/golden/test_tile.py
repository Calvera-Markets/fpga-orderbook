import unittest

from book import SIDE_BUY, Book


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
