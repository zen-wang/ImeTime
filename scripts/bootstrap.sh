#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

for tool in xcodegen supabase deno docker; do
  command -v "$tool" >/dev/null || { echo "缺少 $tool，請先執行：brew install xcodegen deno supabase/tap/supabase；Docker 請安裝 Docker Desktop"; exit 1; }
done
[ -f Config/Local.xcconfig ] || { cp Config/Local.xcconfig.example Config/Local.xcconfig; echo "已建立 Config/Local.xcconfig，請填入 LOCAL_SUPABASE_ANON_KEY"; }

# LOCAL_SUPABASE_ANON_KEY 留空時，從執行中的本機 stack 自動補上，避免全新 clone 建置起來就缺設定
fill_local_anon_key() {
  if ! grep -qE '^[[:space:]]*LOCAL_SUPABASE_ANON_KEY[[:space:]]*=[[:space:]]*$' Config/Local.xcconfig; then
    echo "Config/Local.xcconfig 的 LOCAL_SUPABASE_ANON_KEY 已有值，保持不變"
    return 0
  fi

  local status_env
  if ! status_env=$(supabase status -o env 2>/dev/null); then
    echo "本機 Supabase 尚未啟動，無法自動填入 LOCAL_SUPABASE_ANON_KEY。請先執行 supabase start，再跑一次 make bootstrap"
    return 0
  fi

  local key
  key=$(printf '%s\n' "$status_env" | sed -n 's/^ANON_KEY=//p' | tr -d '"' | head -n 1)
  [ -n "$key" ] || key=$(printf '%s\n' "$status_env" | sed -n 's/^PUBLISHABLE_KEY=//p' | tr -d '"' | head -n 1)
  if [ -z "$key" ]; then
    echo "supabase status 沒有 ANON_KEY / PUBLISHABLE_KEY，請手動填入 Config/Local.xcconfig 的 LOCAL_SUPABASE_ANON_KEY"
    return 0
  fi

  KEY="$key" python3 - <<'PY'
import os, re, pathlib
path = pathlib.Path("Config/Local.xcconfig")
path.write_text(re.sub(
    r'(?m)^([ \t]*LOCAL_SUPABASE_ANON_KEY[ \t]*=)[ \t]*$',
    lambda m: m.group(1) + " " + os.environ["KEY"],
    path.read_text(),
))
PY
  echo "已從執行中的本機 Supabase 填入 Config/Local.xcconfig 的 LOCAL_SUPABASE_ANON_KEY"
}
fill_local_anon_key

# 實機 Debug 版不能連 127.0.0.1（那是手機自己），改用這台 Mac 的 Bonjour 名稱
fill_device_supabase_host() {
  if ! grep -qE '^[[:space:]]*DEVICE_SUPABASE_HOST[[:space:]]*=[[:space:]]*$' Config/Local.xcconfig; then
    grep -qE '^[[:space:]]*DEVICE_SUPABASE_HOST[[:space:]]*=' Config/Local.xcconfig \
      && echo "Config/Local.xcconfig 的 DEVICE_SUPABASE_HOST 已有值，保持不變" \
      || echo "Config/Local.xcconfig 沒有 DEVICE_SUPABASE_HOST 這一行，實機建置前請自行加上"
    return 0
  fi

  local host
  host="$(scutil --get LocalHostName 2>/dev/null).local"
  if [ "$host" = ".local" ]; then
    echo "取不到 LocalHostName，請手動填入 Config/Local.xcconfig 的 DEVICE_SUPABASE_HOST"
    return 0
  fi

  HOST="$host" python3 - <<'PYEOF'
import os, re, pathlib
path = pathlib.Path("Config/Local.xcconfig")
path.write_text(re.sub(
    r'(?m)^([ \t]*DEVICE_SUPABASE_HOST[ \t]*=)[ \t]*$',
    lambda m: m.group(1) + " " + os.environ["HOST"],
    path.read_text(),
))
PYEOF
  echo "已填入 Config/Local.xcconfig 的 DEVICE_SUPABASE_HOST = $host"
}
fill_device_supabase_host

xcodegen generate
echo "完成。下一步：make build"
