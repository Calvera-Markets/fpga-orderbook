"""Append-only JSONL write-ahead log, one file per slice."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

_GOLDEN = Path(__file__).resolve().parent.parent / "golden"
if str(_GOLDEN) not in sys.path:
    sys.path.insert(0, str(_GOLDEN))

from slice_table import N_SLICES  # noqa: E402


class Wal:
    def __init__(self, dir_path: Path, n_slices: int = N_SLICES) -> None:
        if dir_path.exists() and dir_path.is_file():
            raise ValueError(f"WAL must be a directory of sliceN.wal files, not {dir_path}")
        self.dir = dir_path
        self.n_slices = n_slices
        self.dir.mkdir(parents=True, exist_ok=True)

    def slice_path(self, slice_id: int) -> Path:
        return self.dir / f"slice{slice_id}.wal"

    def host_path(self) -> Path:
        return self.dir / "host.wal"

    def append(self, rec: dict[str, Any], slice_id: int) -> None:
        payload = json.dumps(rec, separators=(",", ":")) + "\n"
        with self.slice_path(slice_id).open("a") as f:
            f.write(payload)
            f.flush()
            os.fsync(f.fileno())

    def read_slice(self, slice_id: int) -> list[dict[str, Any]]:
        path = self.slice_path(slice_id)
        if not path.exists():
            return []
        recs: list[dict[str, Any]] = []
        with path.open() as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                recs.append(json.loads(line))
        return recs

    def append_host(self, rec: dict[str, Any]) -> None:
        payload = json.dumps(rec, separators=(",", ":")) + "\n"
        with self.host_path().open("a") as f:
            f.write(payload)
            f.flush()
            os.fsync(f.fileno())

    def read_host(self) -> list[dict[str, Any]]:
        path = self.host_path()
        if not path.exists():
            return []
        recs: list[dict[str, Any]] = []
        with path.open() as f:
            for line in f:
                line = line.strip()
                if line:
                    recs.append(json.loads(line))
        return recs

    def read_all(self) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        for s in range(self.n_slices):
            out.extend(self.read_slice(s))
        return out
