"""Run daily; deletes expired contact data after the published retention window."""

import os
import sqlite3
from datetime import datetime, timedelta, timezone


def main():
    database = os.environ.get("DATABASE_PATH", "./data/fursa.sqlite3")
    cutoff = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat(timespec="seconds").replace("+00:00", "Z")
    with sqlite3.connect(database) as db:
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("PRAGMA secure_delete=ON")
        deleted = db.execute("DELETE FROM jobs WHERE expires_at < ?", (cutoff,)).rowcount
        db.execute("DELETE FROM audit WHERE created_at < ?", (cutoff,))
        db.execute("DELETE FROM rate_limits WHERE expires < strftime('%s','now')")
    print(f"Removed {deleted} expired submissions; no contact information logged.")


if __name__ == "__main__":
    main()
