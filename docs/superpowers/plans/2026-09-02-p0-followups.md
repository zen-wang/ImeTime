# P0 後續追蹤（來自逐任務審查與最終整支分支審查）

P0 完成於 2026-09-02，tag `p0-done`（分支 `feat/p0-foundation`）。以下是審查中延後處理的項目，依應處理的階段分類。

## 在實機上測試（本機 Supabase）

實機不能連 `127.0.0.1`（那是手機自己）。Debug 設定已改成依 SDK 分流：

| 建置目標 | SUPABASE_URL |
|---|---|
| 模擬器 | `http://127.0.0.1:54321` |
| 實機 | `http://$(DEVICE_SUPABASE_HOST):54321`，由 `Config/Local.xcconfig` 提供 |

`make bootstrap` 會把 `DEVICE_SUPABASE_HOST` 自動填成 `scutil --get LocalHostName` 的 `.local` 名稱。若你的網路解析不到 Bonjour 名稱，改填 Mac 的區網 IP。

前提條件：iPhone 與 Mac 連同一個 Wi-Fi；Mac 上 `supabase start` 執行中；iPhone 第一次連線時會跳出「本機網路」權限，必須按允許，然後再試一次登入（第一次嘗試通常會在跳出權限時失敗）。

## 已完成（2026-09-03）

- 實機（iPhone 16 Pro）驗證 Sign in with Apple：登入、登出、再次登入皆成功。P0 的手動驗收到此完成。
- repo 已推上 `https://github.com/zen-wang/ImeTime`（**Private**），含 `main` 與 tag `p0-done`。

## 專案擁有者現在要做的事

1. **模擬器手動驗證 Sign in with Apple**（需你的 Apple ID）：
   - 先確認 `supabase status` 服務都在跑，且 `supabase/config.toml` 的 `[auth.external.apple] email_optional = true`（已設定）。
   - 冷啟動 → Welcome；取消登入 → 停留 Welcome 無錯誤；登入成功、無檔案 → 建立個人檔案；名稱空白 / 超過 20 字 → 紅字；選頭像 + 完成 → Home 顯示名稱與頭像，Studio（http://127.0.0.1:54323）的 Storage > avatars 有 `{uid}/avatar.jpg` 且 ≤ 200 KB；登出 → Welcome；重新登入 → 直接 Home；`supabase stop` 後登入 → 顯示錯誤而非閃退。
   - 若登入失敗且錯誤與 email/provider 有關，先檢查 `email_optional`。
2. ~~決定隱私政策要放在哪個公開位置。~~ **已解決（2026-09-03）**：repo 改為 Public，`AppLinks.privacyPolicy` 指向的 `https://github.com/zen-wang/ImeTime/blob/main/docs/privacy.md` 已可正常開啟（HTTP 200）。TestFlight 前若把 repo 改回 Private，這個連結會再次失效。

## 排入 P1 的工作 — 已對帳（2026-09-03）

P1 完成時只有 2 項真的落地。其餘 10 項全部是 1 到 5 行的小修正，已整併成 **P2 計劃的第一個批次任務**，不再散落在這裡。

**已完成：**
- ~~Supabase 實作的整合測試~~ → P1 Task 10，7 個測試對本機 stack 執行。
- ~~profiles 欄位級授權~~ → migration `20260902000600`，`created_at` 不再可由客戶端改寫。

**未完成，已轉入 P2 批次任務：**
- `supabase-swift` 的 `emitLocalSessionAsInitialSession`：opt-in 新行為並在 `AuthStateMapper` 加 `session.isExpired` 檢查。
- avatars migration 的 `on conflict (id) do update set` 收斂 bucket 設定。
- 補一條大寫 UUID storage 路徑被拒（42501）的 pgTAP 斷言。
- `SupabaseAuthService.states()` 改用 `bufferingNewest(1)`。
- `SessionCoordinator` 加 `deinit { observation?.cancel() }`。
- `WelcomeView`：登入成功後清掉 `currentNonce`；錯誤以 `os.Logger` 記錄型別（不含 token）。
- `CreateProfileViewModel.save()` 開頭加 `guard !isSaving else { return nil }`。
- `AvatarImageEncoder` 的 doc comment 修正；品質迴圈改整數步進。
- `ProfileDecodingTests` 加含小數秒的 timestamptz 案例。
- scripts：`OS=18.6` 硬編與 `iPhone 16` 歧義；`bootstrap.sh` 的工具檢查加 `python3`；`.gitignore` 重複的 `supabase/.temp/`。
- `AppConfigError.invalidSupabaseURL.userMessage` 在 Debug 指錯 key。
- `RootView` 登出失敗仍是 `try?`，使用者按了沒有任何回饋。

## 排入 P6（TestFlight 收尾）的工作

- 真實的隱私政策網址（或改連 repo 內 `docs/privacy.md` 的公開位置）。
- `AppIcon.appiconset` 目前沒有實際圖檔，TestFlight 驗證會失敗。
- 使用者可見文案去除供應商名稱（Supabase）。
- `InviteShare.text(for:)` 加上 TestFlight 公開連結。

## 已知設計取捨（不需修改）

- `avatars` bucket 維持 `public = true`：知道完整路徑的人可以不登入下載頭像；本次修正關閉的是「用 anon key 列舉所有 user id」。頭像是低敏感資料，可接受。
- P0 的 `20260902000200_avatars_bucket.sql` 在本機直接改寫（尚未部署到任何遠端）；其他 clone 需 `make db-reset`。
- `join_room` RPC（P1）以 jsonb 回傳錯誤而非 raise，讓速率限制的嘗試紀錄不被回滾。
