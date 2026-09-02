#!/usr/bin/env bash
# 這台機器的 xcode-select 指向 CommandLineTools；用 DEVELOPER_DIR 指定 Xcode.app，不需 sudo。
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
exec xcodebuild "$@"
