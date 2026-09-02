#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

for tool in xcodegen supabase deno docker; do
  command -v "$tool" >/dev/null || { echo "缺少 $tool，請先執行：brew install xcodegen deno supabase/tap/supabase；Docker 請安裝 Docker Desktop"; exit 1; }
done
[ -f Config/Local.xcconfig ] || { cp Config/Local.xcconfig.example Config/Local.xcconfig; echo "已建立 Config/Local.xcconfig，請填入 LOCAL_SUPABASE_ANON_KEY"; }
xcodegen generate
echo "完成。下一步：make build"
