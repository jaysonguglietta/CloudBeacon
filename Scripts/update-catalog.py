#!/usr/bin/env python3
"""Refresh the bundled public AWS service catalog; review the diff before release."""
import json
import re
import urllib.request
from pathlib import Path

SOURCE = "https://servicedata-us-east-1-prod.s3.amazonaws.com/services.json"
with urllib.request.urlopen(SOURCE, timeout=30) as response:
    data = response.read(3_000_001)
if len(data) > 3_000_000:
    raise SystemExit("AWS metadata exceeds the catalog refresh limit")
entries = json.loads(data)
feeds = []
for entry in entries:
    key = entry["service"]
    if not re.fullmatch(r"[a-z0-9-]{1,128}", key):
        raise SystemExit("AWS returned an unsupported feed identifier")
    feeds.append({"id": key, "service": entry["service_name"],
                  "regionID": entry.get("region_id") or "global",
                  "region": entry.get("region_name") or "Global"})
if not feeds or len({feed["id"] for feed in feeds}) != len(feeds):
    raise SystemExit("Empty catalog or conflicting feed identifiers")
feeds.sort(key=lambda feed: (feed["regionID"], feed["service"], feed["id"]))
output = Path(__file__).resolve().parents[1] / "Sources/StatusCore/Resources/aws-feeds.json"
encoded = json.dumps(feeds, ensure_ascii=False, separators=(",", ":")) + "\n"
if len(encoded.encode("utf-8")) > 2_000_000:
    raise SystemExit("Catalog exceeds the app resource limit; review before updating")
output.write_text(encoded)
print(f"Saved {len(feeds)} feed pairs from {SOURCE}. Review and run check-all.sh.")
