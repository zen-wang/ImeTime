#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

RESULT_BUNDLE="${TMPDIR:-/tmp}/imetime-integration.xcresult"
rm -rf "$RESULT_BUNDLE"

# xcodebuild 會把 TEST_RUNNER_ 前綴的變數去掉前綴後傳進測試程序
TEST_RUNNER_IMETIME_INTEGRATION=1 scripts/xcodebuild.sh test \
  -project ImeTime.xcodeproj -scheme ImeTime \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -only-testing:ImeTimeTests \
  -resultBundlePath "$RESULT_BUNDLE" \
  -quiet

# 整組跳過和整組通過的 exit code 一樣。少了這道檢查，IMETIME_INTEGRATION 一旦沒傳進測試程序，
# make test 會綠燈但整合覆蓋為零。
skipped=$(xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" --format json \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("skippedTests", -1))')
if [ "$skipped" != "0" ]; then
  echo "整合測試被跳過 $skipped 個（預期 0）：IMETIME_INTEGRATION 沒有傳進測試程序，等於零覆蓋。" >&2
  exit 1
fi
echo "整合測試全部實際執行（skipped = 0）"
