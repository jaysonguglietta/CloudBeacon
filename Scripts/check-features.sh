#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks .build/module-cache
swiftc -O -module-cache-path .build/module-cache Sources/StatusCore/*.swift Scripts/FeatureChecks.swift -o .build/checks/feature-checks
.build/checks/feature-checks
