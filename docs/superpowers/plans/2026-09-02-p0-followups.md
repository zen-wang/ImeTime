# P0 後續追蹤（來自逐任務審查與最終整支分支審查）

P0 完成於 2026-09-02，tag `p0-done`（分支 `feat/p0-foundation`）。以下是審查中延後處理的項目，依應處理的階段分類。

## 專案擁有者現在要做的事

1. **模擬器手動驗證 Sign in with Apple**（需你的 Apple ID）：
   - 先確認 `supabase status` 服務都在跑，且 `supabase/config.toml` 的 `[auth.external.apple] email_optional = true`（已設定）。
   - 冷啟動 → Welcome；取消登入 → 停留 Welcome 無錯誤；登入成功、無檔案 → 建立個人檔案；名稱空白 / 超過 20 字 → 紅字；選頭像 + 完成 → Home 顯示名稱與頭像，Studio（http://127.0.0.1:54323）的 Storage > avatars 有 `{uid}/avatar.jpg` 且 ≤ 200 KB；登出 → Welcome；重新登入 → 直接 Home；`supabase stop` 後登入 → 顯示錯誤而非閃退。
   - 若登入失敗且錯誤與 email/provider 有關，先檢查 `email_optional`。
2. **把 repo 推上 GitHub**（或決定隱私政策要放哪），然後把 `ImeTime/App/AppLinks.swift` 的 `privacyPolicy` 改成真實網址。目前指向 `github.com/zen-wang/ImeTime`，帳號是猜的。

## 排入 P1 的工作

- **新增任務：Supabase 實作的整合測試**。對本機 stack 建立使用者、透過 `SupabaseProfileRepository` 建立 profile、上傳 1 px 頭像、讀回；順便驗證小寫 UUID 路徑與日期解碼（含小數秒）。P0 目前 29 個 App 測試全部打 Fake。
- profiles：`grant update (display_name, avatar_path)` 欄位級授權，避免 `created_at` 可被客戶端改寫；P1 擴大 select 政策時把「B 讀不到 profiles」改成「B 只讀得到室友」的正向測試。
- avatars migration：`on conflict (id) do update set public, file_size_limit, allowed_mime_types` 讓既有 bucket 收斂到設定值；補一條大寫 UUID 路徑被拒（42501）的 pgTAP 斷言。
- `SupabaseAuthService.states()` 改用 `bufferingNewest(1)`；`SessionCoordinator` 加 `deinit { observation?.cancel() }`；若新增可同時進行的狀態轉換，為 `resolveProfile` 加世代計數避免過期回應覆寫。
- `WelcomeView`：登入成功後清掉 `currentNonce`；登入錯誤以 `os.Logger` 記錄型別（不含 token）；文案「請確認網路與 Supabase 是否啟動」在 TestFlight 前改為使用者語言。
- `CreateProfileViewModel.save()` 開頭加 `guard !isSaving else { return nil }`。
- `AvatarImageEncoder`：doc comment 說明 200 000 是低於 bucket 204 800 的安全邊際；品質迴圈改用整數步進。
- `ProfileDecodingTests` 加一個含小數秒的 timestamptz 案例（使用 supabase-swift 的 decoder 或等效策略）。
- scripts：`build-app.sh` / `test-app.sh` 的 `OS=18.6` 與 `name=iPhone 16` 歧義；`bootstrap.sh` 的工具檢查加入 `python3`，且 `LOCAL_SUPABASE_ANON_KEY` 那行不存在時應警告而非略過；`.gitignore` 重複的 `supabase/.temp/`；決定 `ImeTime/Info.plist` 是否改為不追蹤。
- `AppConfigError.invalidSupabaseURL.userMessage` 在 Debug 指向 `LOCAL_SUPABASE_ANON_KEY`，但 Debug 的 URL 其實寫死在 `Config/Debug.xcconfig`，訊息可更精準。
- HomeView 登出失敗目前無回饋（P1 會整個換掉 HomeView，新版要有錯誤提示）。

## 排入 P6（TestFlight 收尾）的工作

- 真實的隱私政策網址（或改連 repo 內 `docs/privacy.md` 的公開位置）。
- `AppIcon.appiconset` 目前沒有實際圖檔，TestFlight 驗證會失敗。
- 使用者可見文案去除供應商名稱（Supabase）。
- `InviteShare.text(for:)` 加上 TestFlight 公開連結。

## 已知設計取捨（不需修改）

- `avatars` bucket 維持 `public = true`：知道完整路徑的人可以不登入下載頭像；本次修正關閉的是「用 anon key 列舉所有 user id」。頭像是低敏感資料，可接受。
- P0 的 `20260902000200_avatars_bucket.sql` 在本機直接改寫（尚未部署到任何遠端）；其他 clone 需 `make db-reset`。
- `join_room` RPC（P1）以 jsonb 回傳錯誤而非 raise，讓速率限制的嘗試紀錄不被回滾。
