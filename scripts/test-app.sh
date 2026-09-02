#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/xcodebuild.sh test \
  -project ImeTime.xcodeproj -scheme ImeTime \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -only-testing:ImeTimeTests \
  -quiet
