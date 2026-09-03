# P1 後續追蹤（來自逐任務審查與最終整支分支審查）

P1 完成於 2026-09-03，tag `p1-done`（分支 `feat/p1-rooms`）。

## 寫 P2 計劃時的必要步驟

**先打開 `docs/superpowers/plans/2026-09-02-p0-followups.md` 與本檔的「排入下一階段」段落，把項目折進 P2 的任務清單再開始寫。** P1 這一輪掉了兩項（profiles 欄位級授權、登出失敗無回饋），原因就是這一步不在流程裡；兩項都已在最終修正補上，但機制本身必須修好。

## 專案擁有者現在要做的事

**兩個帳號的手動驗收**（需要兩個已登入的 Apple 帳號，實機或兩台模擬器）：

- [ ] A 建立房間，取得邀請碼
- [ ] B 輸入邀請碼（故意用小寫加空格）→ 加入成功、進入房間
- [ ] A 的房間設定看到 B（含頭像與名稱）；B 的設定看到 A 標示「管理員」
- [ ] B 再輸入同一碼 →「你已經在這個房間裡了。」
- [ ] 連續輸入 6 次錯碼 → 第 6 次「嘗試太多次了…」
- [ ] A 左滑移除 B → B 重新載入首頁後房間消失
- [ ] B 再加入；A 離開 → B 的設定頁顯示自己是管理員
- [ ] B 離開 → 首頁空狀態；Studio 中該 rooms 列的 `abandoned_at` 非空
- [ ] 建立房間後從邀請碼畫面「滑動返回」→ 再進「建立房間」應看到空白表單，且列表已含新房間

這份清單涵蓋自動化測試碰不到的三處：`RoomCreatedView` 的滑動返回、加入後 `path = [.room(room)]` 的替換、以及透過公開 bucket 載入室友頭像。

## 排入下一階段（P2）

- `RoomView` 換成時間線（P2 的主要工作）；順帶把 `RoomsListViewModel.load()` 的錯誤記錄下來，並讓「重試」先回到 `.loading` 才有進度指示。
- `RoomSettingsViewModel`：`toggleMute()` 在 `load()` 尚未完成時會以預設的 `false` 計算新值並寫入伺服器，之後對不上本地列而視覺回彈——加上 `me != nil` 的前置條件；`isLoading` 目前有追蹤但沒有畫面；`remove()` 的 guard 失敗時靜默返回。
- `SupabaseRoomRepository`：`myRooms()` 的 `order("created_at")` 與 `members()` 的 `order("joined_at")` 沒有次要排序鍵（SQL 端的 `leave_room` 用的是 `joined_at, user_id`）。
- 三個 view model 的 `save()` / `create()` / `join()` 都沒有方法內的重入保護，只靠按鈕的 `.disabled`。P0 的 `CreateProfileViewModel.save()` 也一樣，一起處理。
- `join_attempts` 的清理是全表掃描且會跨使用者鎖列；限縮到當前使用者或改為定期工作。
- `create_room` 完全沒有速率限制。
- `generate_invite_code()` 仍保有 `authenticated` 的 EXECUTE（其他六個函式都已明確撤銷）；它不讀任何資料，但這是唯一不符規則的 ACL。
- 邀請碼用 `random()` 而非 `gen_random_bytes()`。
- 整合測試：`mapErrors` 的 `PostgrestError` 分支（`not_authenticated`、`profile_required` 這些 raise 路徑）沒有覆蓋；optional 欄位（`avatarPath`、`Room.createdBy`、`room.timezone`）在鍵缺失時會靜默解碼成 nil；`scripts/test-integration.sh` 用固定的結果包路徑，平行執行會互撞，且與 `test-app.sh` 重複了 xcodebuild 參數。
- `scripts/bootstrap.sh` 的工具檢查沒有 `python3`，但 `make test` 現在依賴它。
- `Task 4` 的 `decodesRoomRow` 沒有斷言 `createdBy`；`RoomError` 的 doc comment 說「一一對應」，但 `code_generation_failed` 刻意走 default。
- `RoomSettingsViewModel` 只有 `remove()` 有「成功後清除舊錯誤」的回歸測試，另外三個方法沒有。
- 觸發器的「房間本身被刪除」分支目前是死路（P1 沒有直接刪 `rooms` 的路徑），P6 實作 `delete_account()` 與清除工作時要補測試。

## 排入 P6（TestFlight 收尾）

- `supabase/config.toml` 的 `[auth.email] enable_signup = true` 是整合測試需要的；**正式專案絕對不能繼承這個設定**（產品只用 Sign in with Apple）。
- `profiles` 的 INSERT 仍是表層級授權，客戶端可以在建立時自訂 `created_at`。
- `abandoned_at` 一旦設定就不會清除；若未來房間可以復活，`join_room` 之外的路徑要一併處理。
- `delete_account()` 必須依賴 `room_members_after_delete` 觸發器來完成交接與 `abandoned_at`，不要在 RPC 裡重寫一份。

## 給 Claude Design 的回饋

spec §14 畫面 6 描述的是 6 格獨立輸入框，目前 `JoinRoomView` 用單一等寬 TextField（計劃如此指定）。要不要改成 6 格由設計決定。

## 已知設計取捨（不需修改）

- 房間存取的唯一關卡是 6 碼邀請碼；速率限制為每人每分鐘 5 次，且錯誤以 jsonb 回傳而非 raise，確保嘗試紀錄不被回滾。
- `code_generation_failed` 刻意不對應 `RoomError` case（10 次碰撞的機率約 5e-31）。
- `RoomError.notPermitted` 由客戶端判定：RLS 過濾掉所有目標列時，伺服器不會報錯。
