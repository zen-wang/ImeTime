#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/xcodebuild.sh build \
  -project ImeTime.xcodeproj -scheme ImeTime \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -quiet
