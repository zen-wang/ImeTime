# ImeTime — 給 Claude Code 的專案守則

## 專案是什麼
朋友限定的 2 秒生活紀錄 iOS app，雲端為單一事實來源。設計規格：`docs/superpowers/specs/2026-09-02-imetime-design.md`。實作計劃：`docs/superpowers/plans/`。

## 指令
- `make bootstrap`：安裝檢查、產生 Xcode 專案、建立 Config/Local.xcconfig
- `make generate`：新增/刪除檔案後必須執行（.xcodeproj 由 project.yml 產生，不進 git）
- `make build`：模擬器建置
- `make test-core`：Packages/ImeTimeCore 的 Swift Testing（macOS，最快）
- `make test-app`：App 單元測試（模擬器）
- `make db-reset` / `make test-db`：重建本機 DB / 跑 pgTAP（需 Docker 與 `supabase start`）
- 所有 xcodebuild/xcrun 都要走 `scripts/xcodebuild.sh` 或 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- 實機 Debug 版連本機 Supabase 走 `Config/Local.xcconfig` 的 `DEVICE_SUPABASE_HOST`（Mac 的 `.local` 名稱），模擬器走 127.0.0.1；由 `Config/Debug.xcconfig` 的 `[sdk=iphoneos*]` 條件切換

## 守則
- Swift 6 strict concurrency；SwiftUI；`@Observable` view model 標 `@MainActor`
- 純邏輯放 `Packages/ImeTimeCore`，先寫測試
- Service 一律 protocol + Supabase 實作 + 測試用 Fake
- 模型為 struct，不可變；不寫 `var` 欄位在模型上
- 唯一第三方套件：supabase-swift；不加其他依賴
- UUID 進 Storage 路徑前 `.lowercased()`
- DB 變更只透過 `supabase/migrations/*.sql`，每個 RLS 政策都要有 pgTAP 正反案例
- UI 文案繁體中文
