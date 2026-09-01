"""PartitionedVenue-shaped backend over Verilated partitioned_engine (.so)."""

from __future__ import annotations

import ctypes
import sys
from pathlib import Path

_GOLDEN = Path(__file__).resolve().parent.parent / "golden"
if str(_GOLDEN) not in sys.path:
    sys.path.insert(0, str(_GOLDEN))

from book import BOOK_CANCEL, BOOK_LIMIT, BookRsp, Fill  # noqa: E402
from oid_map import OidMap  # noqa: E402
from partition import N_PIPES, pipe_of  # noqa: E402

_REPO = Path(__file__).resolve().parents[2]
LIB_PATH = _REPO / "obj_dir" / "lib" / "libpe.so"
MAX_FILLS = 256


class BboBook:
    def __init__(
        self,
        bid_v: bool,
        bid_px: int,
        bid_qty: int,
        ask_v: bool,
        ask_px: int,
        ask_qty: int,
    ) -> None:
        self.bbo_bid_valid = bid_v
        self.bbo_bid_px = bid_px
        self.bbo_bid_qty = bid_qty
        self.bbo_ask_valid = ask_v
        self.bbo_ask_px = ask_px
        self.bbo_ask_qty = ask_qty


class _PeFill(ctypes.Structure):
    _fields_ = [
        ("maker", ctypes.c_uint64),
        ("taker", ctypes.c_uint64),
        ("price", ctypes.c_uint32),
        ("qty", ctypes.c_uint32),
    ]


class _PeRsp(ctypes.Structure):
    _fields_ = [
        ("ok", ctypes.c_uint8),
        ("oid", ctypes.c_uint64),
        ("filled", ctypes.c_uint32),
        ("rest", ctypes.c_uint32),
        ("unrested", ctypes.c_uint32),
        ("nfill", ctypes.c_int),
    ]


def lib_available() -> bool:
    return LIB_PATH.is_file()


def _load():
    if not lib_available():
        raise FileNotFoundError(f"build the engine first: make lib ({LIB_PATH})")
    lib = ctypes.CDLL(str(LIB_PATH))
    lib.pe_new.restype = ctypes.c_void_p
    lib.pe_free.argtypes = [ctypes.c_void_p]
    lib.pe_issue.argtypes = [
        ctypes.c_void_p,
        ctypes.c_uint16,
        ctypes.c_uint8,
        ctypes.c_uint8,
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.c_uint64,
        ctypes.POINTER(_PeRsp),
        ctypes.POINTER(_PeFill),
        ctypes.c_int,
    ]
    lib.pe_issue.restype = ctypes.c_int
    lib.pe_bbo.argtypes = [
        ctypes.c_void_p,
        ctypes.c_uint16,
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.POINTER(ctypes.c_uint32),
        ctypes.POINTER(ctypes.c_uint32),
        ctypes.POINTER(ctypes.c_uint8),
        ctypes.POINTER(ctypes.c_uint32),
        ctypes.POINTER(ctypes.c_uint32),
    ]
    return lib


class RtlEngine:
    def __init__(self) -> None:
        self._lib = _load()
        self._h = self._lib.pe_new()
        if not self._h:
            raise RuntimeError("pe_new failed")
        self.seq = [0] * N_PIPES
        self.oids = OidMap()
        self._rest_qty: dict[int, int] = {}
        self._live: set[int] = set()

    def __del__(self) -> None:
        h = getattr(self, "_h", None)
        lib = getattr(self, "_lib", None)
        if h and lib:
            lib.pe_free(h)

    def pipe(self, symbol: int) -> int:
        return pipe_of(symbol)

    def book(self, symbol: int) -> BboBook:
        return self._peek(symbol)

    def try_book(self, symbol: int) -> BboBook | None:
        if symbol not in self._live:
            return None
        return self._peek(symbol)

    @property
    def books(self) -> dict[int, BboBook]:
        return {s: self._peek(s) for s in self._live}

    def _peek(self, symbol: int) -> BboBook:
        bid_v = ctypes.c_uint8()
        bid_px = ctypes.c_uint32()
        bid_qty = ctypes.c_uint32()
        ask_v = ctypes.c_uint8()
        ask_px = ctypes.c_uint32()
        ask_qty = ctypes.c_uint32()
        self._lib.pe_bbo(
            self._h,
            ctypes.c_uint16(symbol),
            ctypes.byref(bid_v),
            ctypes.byref(bid_px),
            ctypes.byref(bid_qty),
            ctypes.byref(ask_v),
            ctypes.byref(ask_px),
            ctypes.byref(ask_qty),
        )
        return BboBook(
            bool(bid_v.value),
            int(bid_px.value),
            int(bid_qty.value),
            bool(ask_v.value),
            int(ask_px.value),
            int(ask_qty.value),
        )

    def _issue(
        self, symbol: int, op: int, side: int, price: int, qty: int, oid: int
    ) -> BookRsp:
        rsp_c = _PeRsp()
        fills_c = (_PeFill * MAX_FILLS)()
        rc = self._lib.pe_issue(
            self._h,
            ctypes.c_uint16(symbol),
            ctypes.c_uint8(op),
            ctypes.c_uint8(side),
            ctypes.c_uint32(price),
            ctypes.c_uint32(qty),
            ctypes.c_uint64(oid),
            ctypes.byref(rsp_c),
            fills_c,
            MAX_FILLS,
        )
        if rc != 0:
            raise RuntimeError("engine issue timed out")
        fills = [
            Fill(fills_c[i].maker, fills_c[i].taker, fills_c[i].price, fills_c[i].qty)
            for i in range(rsp_c.nfill)
        ]
        return BookRsp(
            ok=bool(rsp_c.ok),
            oid=int(rsp_c.oid),
            filled_qty=int(rsp_c.filled),
            rest_qty=int(rsp_c.rest),
            unrested_qty=int(rsp_c.unrested),
            fills=fills,
        )

    def _track(self, symbol: int, oid: int, rsp: BookRsp) -> None:
        self._live.add(symbol)
        if rsp.rest_qty > 0:
            self.oids.insert(oid, symbol)
            self._rest_qty[oid] = rsp.rest_qty
        for fill in rsp.fills:
            left = self._rest_qty.get(fill.maker_oid, 0) - fill.qty
            if left <= 0:
                self.oids.remove(fill.maker_oid)
                self._rest_qty.pop(fill.maker_oid, None)
            else:
                self._rest_qty[fill.maker_oid] = left

    def limit(
        self, symbol: int, side: int, price: int, qty: int, oid: int, *, bump: bool = True
    ) -> BookRsp:
        p = self.pipe(symbol)
        if bump:
            self.seq[p] += 1
        rsp = self._issue(symbol, BOOK_LIMIT, side, price, qty, oid)
        self._track(symbol, oid, rsp)
        return rsp

    def cancel(self, oid: int, *, bump: bool = True) -> BookRsp:
        symbol = self.oids.get(oid)
        p = self.pipe(symbol) if symbol is not None else 0
        if bump:
            self.seq[p] += 1
        route = 0 if symbol is None else symbol
        rsp = self._issue(route, BOOK_CANCEL, 0, 0, 0, oid)
        if rsp.ok and symbol is not None:
            self.oids.remove(oid)
            self._rest_qty.pop(oid, None)
        return rsp
