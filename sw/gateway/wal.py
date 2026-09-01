"""Append-only JSONL write-ahead log, one file per pipe."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

_GOLDEN = Path(__file__).resolve().parent.parent / "golden"
if str(_GOLDEN) not in sys.path:
    sys.path.insert(0, str(_GOLDEN))

from partition import N_PIPES  # noqa: E402


class Wal:
    def __init__(self, dir_path: Path, n_pipes: int = N_PIPES) -> None:
        if dir_path.exists() and dir_path.is_file():
            raise ValueError(f"WAL must be a directory of pipeN.wal files, not {dir_path}")
        self.dir = dir_path
        self.n_pipes = n_pipes
        self.dir.mkdir(parents=True, exist_ok=True)

    def pipe_path(self, pipe: int) -> Path:
        return self.dir / f"pipe{pipe}.wal"

    def append(self, rec: dict[str, Any], pipe: int) -> None:
        payload = json.dumps(rec, separators=(",", ":")) + "\n"
        with self.pipe_path(pipe).open("a") as f:
            f.write(payload)
            f.flush()
            os.fsync(f.fileno())

    def read_pipe(self, pipe: int) -> list[dict[str, Any]]:
        path = self.pipe_path(pipe)
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

    def read_all(self) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        for p in range(self.n_pipes):
            out.extend(self.read_pipe(p))
        return out
