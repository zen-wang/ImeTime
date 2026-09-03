#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# xcodebuild 會把 TEST_RUNNER_ 前綴的變數去掉前綴後傳進測試程序
TEST_RUNNER_IMETIME_INTEGRATION=1 scripts/xcodebuild.sh test \
  -project ImeTime.xcodeproj -scheme ImeTime \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -only-testing:ImeTimeTests \
  -quiet
