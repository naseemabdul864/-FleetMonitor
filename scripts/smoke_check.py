"""Run offline checks and optional live connectivity checks."""

from __future__ import annotations

import sys
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def main() -> int:
    print("Running offline unit smoke tests...")
    result = subprocess.run([sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v"], check=False)
    if result.returncode:
        return result.returncode

    try:
        from app.data_access import load_data

        data, status = load_data()
        print(f"Loaded {len(data['vehicles'])} vehicles, {len(data['schedules'])} schedules, {len(data['maintenance'])} work orders.")
        print(f"PostgreSQL connected: {status.postgres}; MongoDB connected: {status.mongo}")
        for message in status.messages or []:
            print(f"INFO: {message}")
    except Exception as exc:
        print(f"Live/fallback data load failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
