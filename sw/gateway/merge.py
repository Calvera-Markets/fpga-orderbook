"""CLI is one stream. Match order is per pipe — not venue-wide.

Submit order at the gateway is preserved. Two fills on different pipes
have no defined match-time order relative to each other.
"""

from __future__ import annotations


def with_pipe(status_line: str, pipe: int | None) -> str:
    if pipe is None:
        return status_line
    return f"{status_line} slice={pipe}"
