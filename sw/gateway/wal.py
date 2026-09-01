"""Append-only JSONL write-ahead log."""

from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any


class Wal:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)

    def read_all(self) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        recs: list[dict[str, Any]] = []
        with self.path.open() as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                recs.append(json.loads(line))
        return recs

    def append(self, rec: dict[str, Any]) -> None:
        payload = json.dumps(rec, separators=(",", ":")) + "\n"
        with self.path.open("a") as f:
            f.write(payload)
            f.flush()
            os.fsync(f.fileno())
