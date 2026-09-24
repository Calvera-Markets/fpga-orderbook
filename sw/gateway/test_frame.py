import unittest

from frame import OP_LIMIT, SIDE_BUY, from_line, unpack


class TestFrame(unittest.TestCase):
    def test_line_becomes_a_word(self) -> None:
        word = from_line("LIMIT BUY 1 100 10 7")
        session, op, side, symbol, seq, price, qty, oid = unpack(word)
        self.assertEqual(session, 0)
        self.assertEqual(op, OP_LIMIT)
        self.assertEqual(side, SIDE_BUY)
        self.assertEqual(seq, 1)
        self.assertEqual((symbol, price, qty, oid), (1, 100, 10, 7))
