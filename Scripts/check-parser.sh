#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks .build/module-cache
swiftc -module-cache-path .build/module-cache Sources/StatusCore/Feed.swift Scripts/ParserChecks.swift -o .build/checks/parser-checks
.build/checks/parser-checks "$@"
