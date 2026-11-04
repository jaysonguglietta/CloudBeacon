#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for script in Scripts/*.sh; do bash -n "$script"; done
bash Scripts/check-parser.sh
bash Scripts/check-security.sh
bash Scripts/check-readiness.sh
plutil -lint Scripts/AWSStatus.entitlements
echo "All automated checks passed. See docs/TESTING.md for manual macOS acceptance checks."
