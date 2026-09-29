#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR=$(mktemp -d)
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -sdk "$(xcrun --show-sdk-path)" \
    -module-cache-path "$CHECK_DIR/cache" \
    Sources/Caffeine/AppState.swift Sources/Caffeine/RunningProcess.swift Sources/Caffeine/SystemSleepSetting.swift Tests/AppStateCheck.swift \
    -o "$CHECK_DIR/check-app-state"
"$CHECK_DIR/check-app-state"
