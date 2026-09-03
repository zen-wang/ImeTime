# P2a 錄製與上傳 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在房間裡按下「拍 2 秒」，錄一段橫式 2 秒影片、加字幕、送出，片段的影音檔與海報圖進到物件儲存、`clips` 列變成 `ready`，而且 App 被殺掉也會續傳完成。

**Architecture:** 影片不經 Supabase Storage 的 SDK，而是由 Edge Function `sign-clip-url` 簽發短效 SigV4 presigned URL，App 用 background `URLSession` 直接 PUT。同一份簽名程式碼在開發時指向本機 Supabase 的 S3 相容端點、正式環境指向 Cloudflare R2，只換環境變數——所以這個階段完全不需要先開 R2。`log_date` 與 `hour_slot` 由 DB trigger 依房間時區與 04:00 日界計算，Swift 端有同語意的純邏輯實作供 UI 使用，兩邊共用測試向量。

**Tech Stack:** Swift 6（strict concurrency）、SwiftUI、AVFoundation、SwiftData（僅待送佇列）、Swift Testing、supabase-swift 2.x、Supabase CLI + pgTAP、Deno Edge Functions + `aws4fetch`。

**Spec:** `docs/superpowers/specs/2026-09-02-imetime-design.md`（本計劃實作 §2 規則 2、3、4、5、6、7，§5 clips 與 §5.1 trigger，§5.2 clips 政策，§5.3 物件儲存，§6.3 錄製與上傳，§7 Camera/Services，§8 sign-clip-url，§11 測試層。時間線、播放器、Realtime、每日 Vlog 屬 P2b 與後續。）

## Global Constraints

- 最低部署版本 **iOS 18.0**；只支援 iPhone；App 整體直式，**只有相機畫面是橫式**。
- Swift 語言模式 6、`SWIFT_STRICT_CONCURRENCY = complete`；`@Observable` view model 標 `@MainActor`。
- App 端唯一第三方依賴：`supabase-swift` 2.x（目前 2.55.1）。**不得新增任何 App 依賴。** Edge Function 是另一個執行環境，可以 import `aws4fetch`（spec §8 已指定）。
- 所有模型為 `struct`，不可變；更新以回傳新值方式進行。
- 單檔 ≤ 800 行；函式 ≤ 50 行。
- UI 文案為繁體中文。
- **UUID 進儲存路徑前一律 `.lowercased()`**（`auth.uid()::text` 是小寫）。
- 物件 key 格式：`{room_id}/{log_date}/{user_id}/{clip_id}.mov` 與同前綴 `.jpg`，全部小寫。
- 影片規格：**橫式 1920×1080**、HEVC、含音訊、時長 2.0 秒（DB 接受 1800–2200 ms）。
- 每人每房間每天每小時格最多一支有效片段（`deleted_at is null`）。
- DB 變更只透過 `supabase/migrations/*.sql`；每個 RLS 政策都要有 pgTAP 正反案例。
- 秘密只放 gitignored 的 `Config/Local.xcconfig` 與 `supabase/.env`。
- 所有 xcodebuild/xcrun 走 `scripts/xcodebuild.sh` 或 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。
- `security definer` 函式一律 `set search_path = public, pg_temp`，並 `revoke all ... from public, anon`（`from public` 對 Supabase 的預設 anon 授權無效）。
- 前置條件：`main` 上的 P1 已完成（tag `p1-done`），本機 `supabase start` 執行中，Docker 執行中。

---

## 檔案結構（本計劃新增/修改）

```
Packages/ImeTimeCore/Sources/ImeTimeCore/
├── Clips/LogSlot.swift              # log_date + hour_slot（04:00 日界），與 SQL trigger 同語意
├── Clips/Clip.swift                 # clips 資料列
├── Clips/ClipCaption.swift          # 字幕 ≤ 40 字 + 單一 emoji
└── Clips/UploadState.swift          # 上傳狀態機（純邏輯，含重試退避）
Packages/ImeTimeCore/Tests/ImeTimeCoreTests/
├── LogSlotTests.swift
├── ClipDecodingTests.swift
├── ClipCaptionTests.swift
└── UploadStateTests.swift
ImeTime/Services/Clips/
├── ClipRepository.swift             # protocol
├── SupabaseClipRepository.swift
├── SignedURLClient.swift            # 呼叫 sign-clip-url 的 protocol + 實作
├── PendingClipStore.swift           # SwiftData 待送佇列
└── ClipUploader.swift               # background URLSession + 狀態機
ImeTime/Services/Recording/
├── Recorder.swift                   # protocol + RecordedClip
└── AVFoundationRecorder.swift       # 橫式 AVCapture 實作
ImeTime/Features/Camera/
├── CameraViewModel.swift
├── CameraView.swift                 # 橫式全螢幕
├── CameraPreviewLayer.swift         # AVCaptureVideoPreviewLayer 包裝
└── ClipReviewView.swift             # 循環預覽 + 字幕 + 送出/取消
ImeTime/Features/Rooms/RoomView.swift  # 加上「拍 2 秒」入口（時間線仍是 P2b）
ImeTimeTests/
├── Fakes/FakeClipRepository.swift
├── Fakes/FakeSignedURLClient.swift
├── Fakes/FakeRecorder.swift
├── CameraViewModelTests.swift
├── ClipUploaderTests.swift
└── Integration/ClipPipelineIntegrationTests.swift
supabase/migrations/
├── 20260903000100_clips.sql         # 表、trigger、RLS、索引
└── 20260903000200_clips_bucket.sql  # 開發用 clips bucket（正式環境走 R2，此 bucket 閒置）
supabase/tests/clips_rls.test.sql
supabase/functions/sign-clip-url/
├── index.ts
└── signing.ts                       # 純函式，可單獨測
supabase/functions/tests/signing_test.ts
```

---

### Task 1: 承接前兩階段的零星修正（批次）

**背景：** P0 的追蹤文件把 12 項排進 P1，只有 2 項落地。這些全是 1 到 5 行的機械修正，一次做完，不要再往後拖。詳見 `docs/superpowers/plans/2026-09-02-p0-followups.md`。

**Files:**
- Modify: `ImeTime/Services/Auth/SupabaseAuthService.swift`, `ImeTime/App/SessionCoordinator.swift`, `ImeTime/App/RootView.swift`, `ImeTime/App/AppConfig.swift`, `ImeTime/Features/Onboarding/WelcomeView.swift`, `ImeTime/Features/Onboarding/CreateProfileViewModel.swift`, `ImeTime/Features/Onboarding/AvatarImageEncoder.swift`, `scripts/build-app.sh`, `scripts/test-app.sh`, `scripts/bootstrap.sh`, `.gitignore`, `supabase/migrations/20260902000200_avatars_bucket.sql`, `supabase/tests/avatars_storage.test.sql`

**Interfaces:**
- Produces: 無新公開 API。`RootView` 多一個 `@State private var signOutError: String?`。

- [ ] **Step 1: 一次改完以下 11 處**

1. `ImeTime/Services/Auth/SupabaseAuthService.swift` — `states()` 的 `AsyncStream { continuation in` 改為 `AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in`。只有最新的登入狀態有意義，暫停迭代的消費者不該回放一串過期事件。

2. `ImeTime/App/SessionCoordinator.swift` — 在 `init` 之後加上：
```swift
    deinit {
        observation?.cancel()
    }
```
（`start()` 已改為弱引用 self，所以 deinit 會執行；沒有這行的話被丟棄的觀察 task 要等下一個 auth 事件才結束。）

3. `ImeTime/App/RootView.swift` — 登出失敗目前是 `try?`，使用者按了完全沒有回饋。加上 `@State private var signOutError: String?`，把 `.home` 分支的 `onSignOut` 改成：
```swift
                onSignOut: {
                    Task {
                        do {
                            try await environment.auth.signOut()
                        } catch {
                            signOutError = "登出失敗，請檢查網路後再試一次。"
                        }
                    }
                }
```
並在 `switch` 外層（`var body` 的最外層 view）加：
```swift
        .alert("登出失敗", isPresented: Binding(
            get: { signOutError != nil },
            set: { if !$0 { signOutError = nil } }
        )) {
            Button("好") { signOutError = nil }
        } message: {
            Text(signOutError ?? "")
        }
```
`body` 目前是裸 `switch`，需要包一層 `Group { switch ... }` 才能掛 modifier。

4. `ImeTime/App/AppConfig.swift` — `invalidSupabaseURL` 的 `userMessage` 在 Debug 指向 `LOCAL_SUPABASE_ANON_KEY`，但 Debug 的 URL 其實來自 `Config/Debug.xcconfig`（模擬器寫死 127.0.0.1，實機用 `DEVICE_SUPABASE_HOST`）。把該分支的第一句改為：
```
            模擬器 Debug 建置的網址寫在 Config/Debug.xcconfig；實機 Debug 建置請確認 Config/Local.xcconfig 的 \
            DEVICE_SUPABASE_HOST 已填入這台 Mac 的主機名或區網 IP；\
```
（保留原本的 Release 那一句。）

5. `ImeTime/Features/Onboarding/WelcomeView.swift` — 成功呼叫 `auth.signInWithApple` 之後、以及進入 `catch` 之後，都把 `currentNonce = nil`。同時在 catch 內加一行不含 token 的紀錄：
```swift
            } catch {
                Logger(subsystem: "com.zenwang.imetime", category: "auth")
                    .error("Apple sign-in exchange failed: \(String(describing: type(of: error)), privacy: .public)")
                errorMessage = "登入伺服器失敗，請確認網路與後端是否啟動。"
            }
```
需要 `import OSLog`。注意文案已去掉供應商名稱。

6. `ImeTime/Features/Onboarding/CreateProfileViewModel.swift` — `save()` 第一行加 `guard !isSaving else { return nil }`（在 `errorMessage = nil` 之前）。

7. `ImeTime/Features/Onboarding/AvatarImageEncoder.swift` — 型別的 doc comment 改為：
```swift
/// 把使用者選的圖縮到最長邊 ≤ 512、JPEG ≤ 200 000 bytes；bucket 的 file_size_limit 是 204 800，這裡刻意留安全邊際。
```
並把品質迴圈改成整數步進，避免依賴浮點漂移剛好落在 0.3：
```swift
        for step in 0...6 {
            let quality = 0.9 - Double(step) * 0.1
            if let data = scaled.jpegData(compressionQuality: CGFloat(quality)), data.count <= maxBytes {
                return data
            }
        }
        return nil
```

8. `scripts/build-app.sh` 與 `scripts/test-app.sh` — 兩個檔案的 destination 都改成不寫死 OS 版本、並指定架構避免多重匹配警告：
```
  -destination 'platform=iOS Simulator,name=iPhone 16,arch=arm64' \
```
（`scripts/test-integration.sh` 同樣處理。）

9. `scripts/bootstrap.sh` — 工具檢查清單加入 `python3`：把 `for tool in xcodegen supabase deno docker; do` 改為 `for tool in xcodegen supabase deno docker python3; do`，並把提示訊息尾端補上「python3 由 macOS 內建，若缺少請安裝 Xcode Command Line Tools」。

10. `.gitignore` — 刪掉重複的第二個 `supabase/.temp/`（保留一個）。

11. `supabase/migrations/20260902000200_avatars_bucket.sql` — `on conflict (id) do nothing` 改成收斂設定，否則既有 bucket 的設定永遠不會被更新：
```sql
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;
```

- [ ] **Step 2: 補一條大寫 UUID 路徑被拒的 pgTAP 斷言**

政策比對的是 `auth.uid()::text`（小寫）。Swift 端若哪天忘了 `.lowercased()`，目前沒有任何測試會發現。

`supabase/tests/avatars_storage.test.sql`：把 `select plan(9);` 改為 `select plan(10);`，並在既有的 `'A cannot upload into another user folder'` 斷言之後、`'A updates (upsert) own object'` 之前加入：
```sql
select throws_ok(
  $$insert into storage.objects (bucket_id, name)
    values ('avatars', upper('11111111-1111-1111-1111-111111111111') || '/avatar.jpg')$$,
  '42501', null, 'an uppercase uid folder is rejected');
```

- [ ] **Step 3: 驗證**

```bash
make db-reset && make test-db
```
Expected：7 個檔案 ok，69 個子測試（原 68 + 1）。

```bash
make build && make test-app
```
Expected：兩者 exit 0，App 單元測試數不變（57），無新警告。

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: apply the carried-forward fixes from P0 and P1 reviews"
```

---

### Task 2: LogSlot — 04:00 日界與小時格（ImeTimeCore，TDD）

**Files:**
- Create: `Packages/ImeTimeCore/Sources/ImeTimeCore/Clips/LogSlot.swift`
- Test: `Packages/ImeTimeCore/Tests/ImeTimeCoreTests/LogSlotTests.swift`

**Interfaces:**
- Produces:
  - `public struct LogSlot: Equatable, Hashable, Sendable { public let logDate: String; public let hourSlot: Int }`（`logDate` 是房間時區的 `yyyy-MM-dd`）
  - `public extension LogSlot { static func slot(for recordedAt: Date, timeZoneID: String) -> LogSlot? }`（時區無效回 nil）
  - `public extension LogSlot { static func logDateFormatter(timeZoneID: String) -> DateFormatter? }` 不公開；格式化細節封裝在型別內。
- Task 3 的 SQL trigger 必須對同一組輸入產生同樣的輸出；兩邊共用本任務測試裡的向量。

- [ ] **Step 1: 寫失敗測試**

`Packages/ImeTimeCore/Tests/ImeTimeCoreTests/LogSlotTests.swift`：
```swift
import Foundation
import Testing
@testable import ImeTimeCore

@Suite struct LogSlotTests {
    /// 以房間時區的牆上時間建立 Date，避免測試自己算時區
    private func date(_ iso: String, _ timeZoneID: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = try #require(TimeZone(identifier: timeZoneID))
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return try #require(formatter.date(from: iso))
    }

    @Test func middayIsTheSameDay() throws {
        let slot = try #require(LogSlot.slot(for: date("2026-09-03 14:37:00", "Asia/Taipei"), timeZoneID: "Asia/Taipei"))
        #expect(slot.logDate == "2026-09-03")
        #expect(slot.hourSlot == 14)
    }

    @Test func justBeforeFourAMBelongsToThePreviousDay() throws {
        let slot = try #require(LogSlot.slot(for: date("2026-09-03 03:59:59", "Asia/Taipei"), timeZoneID: "Asia/Taipei"))
        #expect(slot.logDate == "2026-09-02")
        #expect(slot.hourSlot == 3)
    }

    @Test func fourAMStartsTheNewDay() throws {
        let slot = try #require(LogSlot.slot(for: date("2026-09-03 04:00:00", "Asia/Taipei"), timeZoneID: "Asia/Taipei"))
        #expect(slot.logDate == "2026-09-03")
        #expect(slot.hourSlot == 4)
    }

    @Test func midnightBelongsToThePreviousDayButKeepsHourZero() throws {
        let slot = try #require(LogSlot.slot(for: date("2026-09-03 00:00:00", "Asia/Taipei"), timeZoneID: "Asia/Taipei"))
        #expect(slot.logDate == "2026-09-02")
        #expect(slot.hourSlot == 0)
    }

    /// 同一個瞬間在不同房間時區會落在不同的日期與小時格
    @Test func sameInstantDiffersByRoomTimeZone() throws {
        let instant = try date("2026-09-03 14:00:00", "Asia/Taipei")   // = 2026-09-03 06:00 UTC
        let taipei = try #require(LogSlot.slot(for: instant, timeZoneID: "Asia/Taipei"))
        let utc = try #require(LogSlot.slot(for: instant, timeZoneID: "UTC"))
        #expect(taipei == LogSlot(logDate: "2026-09-03", hourSlot: 14))
        #expect(utc == LogSlot(logDate: "2026-09-03", hourSlot: 6))
    }

    /// 美國東部 2026-03-08 02:00 進入夏令時間；當天 03:30 仍在 04:00 日界之前
    @Test func handlesSpringForwardWithoutShiftingTheDay() throws {
        let slot = try #require(LogSlot.slot(for: date("2026-03-08 03:30:00", "America/New_York"), timeZoneID: "America/New_York"))
        #expect(slot.logDate == "2026-03-07")
        #expect(slot.hourSlot == 3)
    }

    @Test func rejectsUnknownTimeZone() {
        #expect(LogSlot.slot(for: Date(), timeZoneID: "Mars/Olympus") == nil)
    }
}
```

- [ ] **Step 2: 執行確認失敗**

```bash
make test-core
```
Expected：`cannot find 'LogSlot' in scope`。

- [ ] **Step 3: 實作**

`Packages/ImeTimeCore/Sources/ImeTimeCore/Clips/LogSlot.swift`：
```swift
import Foundation

/// 一支片段落在哪一天的哪個小時格。
///
/// 規則與 SQL trigger `clips_set_day_slot()` 一致：
/// - `logDate` = （錄製時間轉房間時區後往前推 4 小時）的日期，所以凌晨 04:00 前算前一天
/// - `hourSlot` = 錄製時間轉房間時區後的小時（0...23），**不做位移**
public struct LogSlot: Equatable, Hashable, Sendable {
    public let logDate: String
    public let hourSlot: Int

    public init(logDate: String, hourSlot: Int) {
        self.logDate = logDate
        self.hourSlot = hourSlot
    }

    /// 時區代號無效時回 nil。
    public static func slot(for recordedAt: Date, timeZoneID: String) -> LogSlot? {
        guard let timeZone = TimeZone(identifier: timeZoneID) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hourSlot = calendar.component(.hour, from: recordedAt)

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let logDate = formatter.string(from: recordedAt.addingTimeInterval(-4 * 60 * 60))

        return LogSlot(logDate: logDate, hourSlot: hourSlot)
    }
}
```

- [ ] **Step 4: 執行確認通過**

```bash
make test-core
```
Expected：28 tests passed（21 + 7）。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(core): add LogSlot for the 04:00 day boundary and hour slot"
```

---

### Task 3: clips 表、trigger 與 RLS（pgTAP）

**Files:**
- Create: `supabase/migrations/20260903000100_clips.sql`, `supabase/tests/clips_rls.test.sql`

**Interfaces:**
- Consumes: `public.rooms`（`timezone`）、`public.profiles`、`public.is_room_member(uuid)`（P1）
- Produces:
  - 表 `public.clips`（欄位見 spec §5）
  - trigger `clips_set_day_slot`（BEFORE INSERT OR UPDATE）計算 `log_date`、`hour_slot`、`updated_at`
  - RLS：同房間成員可讀未刪除的片段（本人可讀自己的已刪除片段）；本人可插入；本人可更新 `status` / `caption` / `emoji` / `deleted_at`；不開 delete
  - 唯一索引 `clips_one_per_slot`、查詢索引 `clips_room_day`

- [ ] **Step 1: 寫失敗的 pgTAP 測試**

`supabase/tests/clips_rls.test.sql`：
```sql
begin;
select plan(18);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'b@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'c@example.com');
insert into public.profiles (id, display_name) values
  ('11111111-1111-1111-1111-111111111111', 'A'),
  ('22222222-2222-2222-2222-222222222222', 'B'),
  ('33333333-3333-3333-3333-333333333333', 'C');
insert into public.rooms (id, name, invite_code, timezone, created_by) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'R1', 'ABCDEF', 'Asia/Taipei', '11111111-1111-1111-1111-111111111111');
insert into public.room_members (room_id, user_id, role) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111', 'owner'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'member');

-- anon 沒有任何 grant
set local role anon;
select throws_ok($$select * from public.clips$$, '42501', null, 'anon cannot read clips');

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

-- trigger：14:37 台北 → 當天、小時 14
select results_eq(
  $$insert into public.clips
      (id, room_id, user_id, recorded_at, duration_ms, width, height)
    values ('c1c1c1c1-0000-0000-0000-000000000001',
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111',
            '2026-09-03 14:37:00+08', 2000, 1920, 1080)
    returning log_date::text || ' ' || hour_slot::text$$,
  array['2026-09-03 14'], 'trigger derives log_date and hour_slot in the room time zone');

-- key 全部小寫、由伺服器組出來
select results_eq(
  $$select video_key || ' ' || poster_key from public.clips
    where id = 'c1c1c1c1-0000-0000-0000-000000000001'$$,
  array['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/2026-09-03/11111111-1111-1111-1111-111111111111/c1c1c1c1-0000-0000-0000-000000000001.mov '
     || 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/2026-09-03/11111111-1111-1111-1111-111111111111/c1c1c1c1-0000-0000-0000-000000000001.jpg'],
  'the trigger derives both object keys');

-- 客戶端送的 key 會被覆寫，不能指向別人的物件
select results_eq(
  $$insert into public.clips
      (id, room_id, user_id, recorded_at, duration_ms, width, height)
    values ('c1c1c1c1-0000-0000-0000-000000000009',
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111',
            '2026-09-03 20:00:00+08', 'someone-elses/object.mov', 'someone-elses/object.jpg',
            2000, 1920, 1080)
    returning video_key$$,
  array['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/2026-09-03/11111111-1111-1111-1111-111111111111/c1c1c1c1-0000-0000-0000-000000000009.mov'],
  'a client-supplied key is overwritten by the trigger');

-- trigger：03:59 台北 → 前一天、小時 3
select results_eq(
  $$insert into public.clips
      (id, room_id, user_id, recorded_at, duration_ms, width, height)
    values ('c1c1c1c1-0000-0000-0000-000000000002',
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111',
            '2026-09-03 03:59:00+08', 2000, 1920, 1080)
    returning log_date::text || ' ' || hour_slot::text$$,
  array['2026-09-02 3'], 'a clip before 04:00 belongs to the previous log day');

-- 同一個小時格不能有第二支
select throws_ok(
  $$insert into public.clips
      (room_id, user_id, recorded_at, duration_ms, width, height)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111',
            '2026-09-03 14:59:00+08', 2000, 1920, 1080)$$,
  '23505', null, 'a second clip in the same hour slot is rejected');

-- 軟刪除之後同一格可以再拍
select lives_ok(
  $$update public.clips set deleted_at = now()
    where id = 'c1c1c1c1-0000-0000-0000-000000000001'$$,
  'A soft-deletes own clip');
select lives_ok(
  $$insert into public.clips
      (id, room_id, user_id, recorded_at, duration_ms, width, height)
    values ('c1c1c1c1-0000-0000-0000-000000000003',
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111',
            '2026-09-03 14:59:00+08', 2000, 1920, 1080)$$,
  'the slot is free again after a soft delete');

-- 尺寸與時長的 check
select throws_ok(
  $$insert into public.clips
      (room_id, user_id, recorded_at, duration_ms, width, height)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111',
            '2026-09-03 15:00:00+08', 5000, 1920, 1080)$$,
  '23514', null, 'a 5s duration is rejected');
select throws_ok(
  $$insert into public.clips
      (room_id, user_id, recorded_at, duration_ms, width, height)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '11111111-1111-1111-1111-111111111111',
            '2026-09-03 16:00:00+08', 2000, 1080, 1920)$$,
  '23514', null, 'a portrait clip is rejected');

-- 不能替別人插入
select throws_ok(
  $$insert into public.clips
      (room_id, user_id, recorded_at, duration_ms, width, height)
    values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222',
            '2026-09-03 17:00:00+08', 2000, 1920, 1080)$$,
  '42501', null, 'A cannot insert a clip for B');

-- B 是同房間成員：讀得到 A 未刪除的片段，讀不到已刪除的
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select results_eq(
  $$select count(*)::int from public.clips
    where user_id = '11111111-1111-1111-1111-111111111111'$$,
  array[2], 'B reads A undeleted clips only');
select is_empty(
  $$select 1 from public.clips where id = 'c1c1c1c1-0000-0000-0000-000000000001'$$,
  'B cannot read a soft-deleted clip');
select is_empty(
  $$update public.clips set caption = 'hijack'
    where user_id = '11111111-1111-1111-1111-111111111111' returning id$$,
  'B cannot edit A clips');
select throws_ok(
  $$delete from public.clips$$,
  '42501', null, 'authenticated cannot hard-delete clips');

-- C 不在房間：什麼都讀不到
set local request.jwt.claim.sub = '33333333-3333-3333-3333-333333333333';
select is_empty($$select * from public.clips$$, 'a stranger reads no clips');

-- A 自己讀得到自己已刪除的片段，也能改自己的 caption 與 status
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select results_eq(
  $$select count(*)::int from public.clips
    where id = 'c1c1c1c1-0000-0000-0000-000000000001'$$,
  array[1], 'A still reads own soft-deleted clip');
select results_eq(
  $$update public.clips set caption = '午餐', status = 'ready'
    where id = 'c1c1c1c1-0000-0000-0000-000000000003'
    returning caption || ' ' || status$$,
  array['午餐 ready'], 'A updates own caption and status');
select throws_ok(
  $$update public.clips set room_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    where id = 'c1c1c1c1-0000-0000-0000-000000000003'$$,
  '42501', null, 'A cannot move a clip between rooms');

select * from finish();
rollback;
```

- [ ] **Step 2: 執行確認失敗**

```bash
make test-db
```
Expected：`relation "public.clips" does not exist`；其餘 7 個檔案照舊通過。

- [ ] **Step 3: 寫 migration**

`supabase/migrations/20260903000100_clips.sql`：
```sql
create table public.clips (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  recorded_at timestamptz not null,
  -- log_date / hour_slot 由 trigger 依房間時區計算，客戶端不得自行填寫
  log_date date not null,
  hour_slot int not null check (hour_slot between 0 and 23),
  -- 由 trigger 產生；客戶端送的值會被覆寫
  video_key text not null,
  poster_key text not null,
  duration_ms int not null check (duration_ms between 1800 and 2200),
  width int not null check (width = 1920),
  height int not null check (height = 1080),
  caption text check (char_length(caption) <= 40),
  emoji text check (char_length(emoji) <= 8),
  status text not null default 'uploading' check (status in ('uploading', 'ready', 'failed')),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index clips_one_per_slot
  on public.clips (room_id, user_id, log_date, hour_slot)
  where deleted_at is null;
create index clips_room_day on public.clips (room_id, log_date)
  where deleted_at is null;

-- 04:00 日界：往前推 4 小時後取日期；小時格則是房間時區的原始小時
create or replace function public.clips_set_day_slot() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_zone text;
  v_local timestamp;
begin
  select timezone into v_zone from public.rooms where id = new.room_id;
  if v_zone is null then raise exception 'room_not_found'; end if;

  v_local := new.recorded_at at time zone v_zone;
  new.log_date := (v_local - interval '4 hours')::date;
  new.hour_slot := extract(hour from v_local)::int;

  -- 物件 key 由伺服器決定。若讓客戶端自己填，使用者可以把 video_key 指向別人的物件，
  -- 再向 sign-clip-url 要一份下載連結。
  new.video_key := lower(new.room_id::text) || '/' || new.log_date::text || '/'
                   || lower(new.user_id::text) || '/' || lower(new.id::text) || '.mov';
  new.poster_key := lower(new.room_id::text) || '/' || new.log_date::text || '/'
                    || lower(new.user_id::text) || '/' || lower(new.id::text) || '.jpg';

  new.updated_at := now();
  return new;
end;
$$;

revoke all on function public.clips_set_day_slot() from public, anon, authenticated;

create trigger clips_set_day_slot
  before insert or update on public.clips
  for each row execute function public.clips_set_day_slot();

alter table public.clips enable row level security;
revoke all on public.clips from anon, authenticated;
grant select, insert on public.clips to authenticated;
-- 只有這四欄可以改：搬房間、改時間、改 key 都不允許
grant update (status, caption, emoji, deleted_at) on public.clips to authenticated;

create policy "clips: members read live clips"
  on public.clips for select to authenticated
  using (
    public.is_room_member(room_id)
    and (deleted_at is null or user_id = (select auth.uid()))
  );

create policy "clips: insert own"
  on public.clips for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and public.is_room_member(room_id)
  );

create policy "clips: update own"
  on public.clips for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
```

- [ ] **Step 4: 執行確認通過**

```bash
make db-reset && make test-db
```
Expected：8 個檔案 ok，87 個子測試（69 + 18）。

若 `'A cannot move a clip between rooms'` 這條回傳的是 0 列而不是 42501，代表 `room_id` 沒有被欄位授權擋下——不要放寬斷言，回報實際輸出並停下。

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations supabase/tests
git commit -m "feat(db): add clips with day-slot trigger and RLS"
```

---

### Task 4: sign-clip-url Edge Function（SigV4 presigned URL）

**背景：** App 不持有任何物件儲存的金鑰。這個函式驗證呼叫者、讀出 `clips` 列上伺服器產生的 key，再簽出短效的 PUT / GET URL。同一份程式碼開發時指向本機 Supabase 的 S3 相容端點、正式環境指向 Cloudflare R2，只換環境變數；因此這個階段完全不需要先開 R2。

**Files:**
- Create: `supabase/functions/sign-clip-url/signing.ts`, `supabase/functions/sign-clip-url/index.ts`, `supabase/functions/tests/signing_test.ts`, `supabase/migrations/20260903000200_clips_bucket.sql`, `scripts/test-functions.sh`
- Modify: `supabase/config.toml`, `supabase/.env`（gitignored）, `Makefile`, `CLAUDE.md`

**Interfaces:**
- Consumes: `public.clips`（`video_key`、`poster_key`、`status`、`user_id`）與其 RLS
- Produces: `POST /functions/v1/sign-clip-url`
  - 請求：`{ "clipId": "<uuid>", "kind": "video" | "poster", "action": "upload" | "download" }`，`Authorization: Bearer <使用者 JWT>`
  - 成功：`200 { "url": "<presigned>", "expiresIn": 600 | 3600 }`
  - 失敗：`400 invalid_body`、`401 not_authenticated`、`403 not_owner`、`404 not_found`、`405 method_not_allowed`、`409 not_uploading`、`500 signing_failed`
  - `signing.ts` 匯出 `storageConfigFromEnv`、`objectURL`、`presign`

- [ ] **Step 1: 開發用 bucket 的 migration**

正式環境的物件在 R2，這個 bucket 只是讓開發時的 S3 端點有地方放東西。

`supabase/migrations/20260903000200_clips_bucket.sql`：
```sql
-- 開發用：本機 S3 相容端點的目標 bucket。正式環境改指向 Cloudflare R2，這個 bucket 就會閒置。
-- private：所有存取都要經過 sign-clip-url 簽出的短效 URL。
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('clips', 'clips', false, 20971520, array['video/quicktime', 'image/jpeg'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- 不開任何 storage.objects 政策：客戶端一律走 presigned URL，不經 PostgREST。
```

- [ ] **Step 2: 寫失敗的 Deno 測試**

`supabase/functions/tests/signing_test.ts`：
```ts
import { assertEquals, assertStringIncludes, assertThrows } from "jsr:@std/assert@1";
import { objectURL, presign, storageConfigFromEnv } from "../sign-clip-url/signing.ts";

const config = {
  endpoint: "http://kong:8000/storage/v1/s3",
  region: "local",
  bucket: "clips",
  accessKeyId: "test-key-id",
  secretAccessKey: "test-secret",
};

Deno.test("storageConfigFromEnv reports every missing variable at once", () => {
  const error = assertThrows(() => storageConfigFromEnv({ CLIP_STORAGE_REGION: "local" }));
  assertStringIncludes(String(error), "CLIP_STORAGE_ENDPOINT");
  assertStringIncludes(String(error), "CLIP_STORAGE_BUCKET");
});

Deno.test("storageConfigFromEnv strips a trailing slash from the endpoint", () => {
  const parsed = storageConfigFromEnv({
    CLIP_STORAGE_ENDPOINT: "http://kong:8000/storage/v1/s3/",
    CLIP_STORAGE_REGION: "local",
    CLIP_STORAGE_BUCKET: "clips",
    CLIP_STORAGE_ACCESS_KEY_ID: "id",
    CLIP_STORAGE_SECRET_ACCESS_KEY: "secret",
  });
  assertEquals(parsed.endpoint, "http://kong:8000/storage/v1/s3");
});

Deno.test("objectURL joins endpoint, bucket and key", () => {
  assertEquals(
    objectURL(config, "room/2026-09-03/user/clip.mov"),
    "http://kong:8000/storage/v1/s3/clips/room/2026-09-03/user/clip.mov",
  );
});

Deno.test("presign produces a query-signed URL carrying the requested expiry", async () => {
  const url = await presign(config, "room/2026-09-03/user/clip.mov", "PUT", 600);
  assertStringIncludes(url, "X-Amz-Signature=");
  assertStringIncludes(url, "X-Amz-Expires=600");
  assertStringIncludes(url, "/clips/room/2026-09-03/user/clip.mov");
});

Deno.test("presign signs GET and PUT differently", async () => {
  const put = await presign(config, "k.mov", "PUT", 600);
  const get = await presign(config, "k.mov", "GET", 3600);
  assertEquals(put === get, false);
  assertStringIncludes(get, "X-Amz-Expires=3600");
});
```

`scripts/test-functions.sh`：
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
deno test --allow-net --allow-env supabase/functions/tests/
```
```bash
chmod +x scripts/test-functions.sh
```

`Makefile`：`.PHONY` 加上 `test-functions`，新增目標，並把它放進 `test`：
```make
test-functions:
	scripts/test-functions.sh

test: test-core test-functions test-db test-integration
```

```bash
make test-functions
```
Expected：失敗，`Module not found ... signing.ts`。

- [ ] **Step 3: 實作 signing.ts**

`supabase/functions/sign-clip-url/signing.ts`：
```ts
import { AwsClient } from "https://esm.sh/aws4fetch@1.0.20";

export interface StorageConfig {
  endpoint: string;
  region: string;
  bucket: string;
  accessKeyId: string;
  secretAccessKey: string;
}

const REQUIRED_KEYS = [
  "CLIP_STORAGE_ENDPOINT",
  "CLIP_STORAGE_REGION",
  "CLIP_STORAGE_BUCKET",
  "CLIP_STORAGE_ACCESS_KEY_ID",
  "CLIP_STORAGE_SECRET_ACCESS_KEY",
] as const;

/// 開發指向本機 Supabase 的 S3 端點，正式指向 R2；除了這五個值以外沒有差別。
export function storageConfigFromEnv(env: Record<string, string | undefined>): StorageConfig {
  const missing = REQUIRED_KEYS.filter((key) => !env[key]);
  if (missing.length > 0) {
    throw new Error(`missing storage config: ${missing.join(", ")}`);
  }
  return {
    endpoint: env.CLIP_STORAGE_ENDPOINT!.replace(/\/+$/, ""),
    region: env.CLIP_STORAGE_REGION!,
    bucket: env.CLIP_STORAGE_BUCKET!,
    accessKeyId: env.CLIP_STORAGE_ACCESS_KEY_ID!,
    secretAccessKey: env.CLIP_STORAGE_SECRET_ACCESS_KEY!,
  };
}

export function objectURL(config: StorageConfig, key: string): string {
  return `${config.endpoint}/${config.bucket}/${key}`;
}

export async function presign(
  config: StorageConfig,
  key: string,
  method: "PUT" | "GET",
  expiresIn: number,
): Promise<string> {
  const client = new AwsClient({
    accessKeyId: config.accessKeyId,
    secretAccessKey: config.secretAccessKey,
    service: "s3",
    region: config.region,
  });
  const url = new URL(objectURL(config, key));
  url.searchParams.set("X-Amz-Expires", String(expiresIn));
  const signed = await client.sign(url.toString(), { method, aws: { signQuery: true } });
  return signed.url;
}
```

```bash
make test-functions
```
Expected：5 個測試通過。若 `aws4fetch` 的 `signQuery` 選項名稱不同，查 `https://esm.sh/aws4fetch@1.0.20` 的型別定義後用最小改動修正，並記在 Deviations。

- [ ] **Step 4: 實作 index.ts**

`supabase/functions/sign-clip-url/index.ts`：
```ts
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { presign, storageConfigFromEnv } from "./signing.ts";

const UPLOAD_TTL = 600;      // 10 分鐘
const DOWNLOAD_TTL = 3600;   // 1 小時

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ error: "not_authenticated" }, 401);

  let body: { clipId?: string; kind?: string; action?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const { clipId, kind, action } = body;
  const kindOK = kind === "video" || kind === "poster";
  const actionOK = action === "upload" || action === "download";
  if (!clipId || !kindOK || !actionOK) return json({ error: "invalid_body" }, 400);

  // 帶著呼叫者的 JWT：讀不讀得到這一列由 clips 的 RLS 決定，函式本身不需要 service role
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authorization } } },
  );

  const { data: userResult } = await supabase.auth.getUser();
  const userID = userResult?.user?.id;
  if (!userID) return json({ error: "not_authenticated" }, 401);

  const { data: clip, error } = await supabase
    .from("clips")
    .select("id, user_id, status, video_key, poster_key")
    .eq("id", clipId)
    .maybeSingle();
  if (error) return json({ error: "lookup_failed" }, 500);
  if (!clip) return json({ error: "not_found" }, 404);

  if (action === "upload") {
    if (clip.user_id !== userID) return json({ error: "not_owner" }, 403);
    if (clip.status !== "uploading") return json({ error: "not_uploading" }, 409);
  }

  const key = kind === "video" ? clip.video_key : clip.poster_key;
  const expiresIn = action === "upload" ? UPLOAD_TTL : DOWNLOAD_TTL;

  try {
    const config = storageConfigFromEnv(Deno.env.toObject());
    const url = await presign(config, key, action === "upload" ? "PUT" : "GET", expiresIn);
    return json({ url, expiresIn });
  } catch {
    return json({ error: "signing_failed" }, 500);
  }
});
```

- [ ] **Step 5: 設定與本機驗證**

`supabase/config.toml` 末尾加上（`verify_jwt` 明寫，別依賴預設值）：
```toml
[functions.sign-clip-url]
verify_jwt = true
```

`supabase/.env`（gitignored）加上五個變數。值取自 `supabase status -o env` 的 `S3_PROTOCOL_ACCESS_KEY_ID` 與 `S3_PROTOCOL_ACCESS_KEY_SECRET`；端點用容器內部名稱：
```
CLIP_STORAGE_ENDPOINT=http://kong:8000/storage/v1/s3
CLIP_STORAGE_REGION=local
CLIP_STORAGE_BUCKET=clips
CLIP_STORAGE_ACCESS_KEY_ID=<S3_PROTOCOL_ACCESS_KEY_ID>
CLIP_STORAGE_SECRET_ACCESS_KEY=<S3_PROTOCOL_ACCESS_KEY_SECRET>
```

同時把這五行（值留空）加進 `Config/Local.xcconfig.example` 旁邊的說明——不，它們是後端設定，改為在 `CLAUDE.md` 的「指令」段落補一行：
```markdown
- Edge Function 的儲存設定放 `supabase/.env` 的 `CLIP_STORAGE_*`；開發指向本機 S3 端點，正式指向 Cloudflare R2
```

重啟並確認 edge runtime 起得來：
```bash
supabase stop && supabase start
docker ps --format '{{.Names}}' | grep -i edge
```
Expected：出現 edge runtime 容器。若沒有，改用 `supabase functions serve sign-clip-url --env-file supabase/.env` 在另一個終端跑，並在報告裡註明採用哪一種方式。

未帶 JWT 的請求應該被擋：
```bash
curl -s -o /dev/null -w "%{http_code}\n" -X POST \
  -H "Content-Type: application/json" \
  -d '{"clipId":"00000000-0000-0000-0000-000000000000","kind":"video","action":"download"}' \
  http://127.0.0.1:54321/functions/v1/sign-clip-url
```
Expected：401（`verify_jwt = true` 由 gateway 擋下）。把實際輸出貼進報告。

端對端的成功路徑由 Task 10 的整合測試涵蓋。

- [ ] **Step 6: 全部測試**

```bash
make db-reset && make test-db && make test-functions
```
Expected：9 個 pgTAP 檔案 ok；5 個 Deno 測試通過。

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(functions): add sign-clip-url with SigV4 presigned URLs"
```

---

### Task 5: Clip 模型、字幕與 ClipRepository

**Files:**
- Create: `Packages/ImeTimeCore/Sources/ImeTimeCore/Clips/Clip.swift`, `Clips/ClipCaption.swift`, `ImeTime/Services/Clips/ClipRepository.swift`, `ImeTime/Services/Clips/SupabaseClipRepository.swift`, `ImeTimeTests/Fakes/FakeClipRepository.swift`
- Test: `Packages/ImeTimeCore/Tests/ImeTimeCoreTests/ClipDecodingTests.swift`, `ClipCaptionTests.swift`
- Modify: `ImeTime/App/AppEnvironment.swift`

**Interfaces:**
- Consumes: `LogSlot`（Task 2）、`clips` 表（Task 3）
- Produces:
  - `public struct Clip: Codable, Hashable, Sendable, Identifiable { id, roomID, userID, recordedAt, logDate, hourSlot, videoKey, posterKey, durationMs, width, height, caption, emoji, status, createdAt }`（`status` 是 `Clip.Status` enum：`uploading`/`ready`/`failed`）
  - `/// 片段的字幕：一段短文字加一個選填的 emoji。兩者都存成欄位，播放時才由 App 疊上去，
/// 所以中文字型不會像燒進影片那樣走鐘。
public struct ClipCaption: Equatable, Sendable {
    public static let maxLength = 40
    /// 沒有文字也沒有 emoji。
    public static let empty = ClipCaption()

    public let text: String?
    public let emoji: String?

    public init() {
        text = nil
        emoji = nil
    }

    public init(text: String?, emoji: String?) throws(ClipCaptionError) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedText = (trimmed?.isEmpty ?? true) ? nil : trimmed
        if let normalizedText, normalizedText.count > Self.maxLength {
            throw .tooLong(max: Self.maxLength)
        }

        var normalizedEmoji: String?
        if let emoji, !emoji.isEmpty {
            guard emoji.count == 1, let character = emoji.first, character.isEmojiPresentation else {
                throw .invalidEmoji
            }
            normalizedEmoji = emoji
        }

        self.text = normalizedText
        self.emoji = normalizedEmoji
    }
}

private extension Character {
    /// 單一字元且預設以彩色 emoji 呈現（排除 "a"、數字這類 isEmoji 為 true 但其實是文字的字元）。
    var isEmojiPresentation: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmojiPresentation || unicodeScalars.count > 1
    }
}
```

`Packages/ImeTimeCore/Sources/ImeTimeCore/Clips/Clip.swift`：
```swift
import Foundation

/// 對應 public.clips 一列。`videoKey` / `posterKey` 由 DB trigger 產生，客戶端只讀不寫。
public struct Clip: Codable, Hashable, Sendable, Identifiable {
    public enum Status: String, Codable, Hashable, Sendable {
        case uploading, ready, failed
    }

    public let id: UUID
    public let roomID: UUID
    public let userID: UUID
    public let recordedAt: Date
    public let logDate: String
    public let hourSlot: Int
    public let videoKey: String
    public let posterKey: String
    public let durationMs: Int
    public let width: Int
    public let height: Int
    public let caption: String?
    public let emoji: String?
    public let status: Status
    public let createdAt: Date

    public var slot: LogSlot { LogSlot(logDate: logDate, hourSlot: hourSlot) }

    public init(
        id: UUID, roomID: UUID, userID: UUID, recordedAt: Date,
        logDate: String, hourSlot: Int, videoKey: String, posterKey: String,
        durationMs: Int, width: Int, height: Int,
        caption: String?, emoji: String?, status: Status, createdAt: Date
    ) {
        self.id = id
        self.roomID = roomID
        self.userID = userID
        self.recordedAt = recordedAt
        self.logDate = logDate
        self.hourSlot = hourSlot
        self.videoKey = videoKey
        self.posterKey = posterKey
        self.durationMs = durationMs
        self.width = width
        self.height = height
        self.caption = caption
        self.emoji = emoji
        self.status = status
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, caption, emoji, status, width, height
        case roomID = "room_id"
        case userID = "user_id"
        case recordedAt = "recorded_at"
        case logDate = "log_date"
        case hourSlot = "hour_slot"
        case videoKey = "video_key"
        case posterKey = "poster_key"
        case durationMs = "duration_ms"
        case createdAt = "created_at"
    }
}
```
```bash
make test-core
```
Expected：38 tests passed（28 + 10）。

- [ ] **Step 3: 寫 ClipRepository、Supabase 實作與 Fake**

`ImeTime/Services/Clips/ClipRepository.swift`：
```swift
import Foundation
import ImeTimeCore

protocol ClipRepository: Sendable {
    /// 插入一列 status = uploading 的片段；log_date、hour_slot 與物件 key 由伺服器產生。
    func createClip(roomID: UUID, recordedAt: Date, durationMs: Int, caption: ClipCaption) async throws -> Clip
    func markReady(clipID: UUID) async throws
    func markFailed(clipID: UUID) async throws
    func clips(roomID: UUID, logDate: String) async throws -> [Clip]
}
```

`ImeTime/Services/Clips/SupabaseClipRepository.swift`：
```swift
import Foundation
import ImeTimeCore
import Supabase

struct SupabaseClipRepository: ClipRepository {
    let client: SupabaseClient
    let currentUserID: @Sendable () async -> UUID?

    func createClip(roomID: UUID, recordedAt: Date, durationMs: Int, caption: ClipCaption) async throws -> Clip {
        guard let userID = await currentUserID() else { throw ClipRepositoryError.notAuthenticated }
        struct NewClip: Encodable {
            let room_id: UUID
            let user_id: UUID
            let recorded_at: Date
            let duration_ms: Int
            let width: Int
            let height: Int
            let caption: String?
            let emoji: String?
        }
        return try await client
            .from("clips")
            .insert(NewClip(room_id: roomID, user_id: userID, recorded_at: recordedAt,
                            duration_ms: durationMs, width: 1920, height: 1080,
                            caption: caption.text, emoji: caption.emoji),
                    returning: .representation)
            .single()
            .execute()
            .value
    }

    func markReady(clipID: UUID) async throws { try await setStatus(clipID: clipID, status: "ready") }
    func markFailed(clipID: UUID) async throws { try await setStatus(clipID: clipID, status: "failed") }

    private func setStatus(clipID: UUID, status: String) async throws {
        struct AffectedRow: Decodable { let id: UUID }
        let updated: [AffectedRow] = try await client
            .from("clips")
            .update(["status": status], returning: .representation)
            .eq("id", value: clipID.uuidString)
            .execute()
            .value
        guard !updated.isEmpty else { throw ClipRepositoryError.notPermitted }
    }

    func clips(roomID: UUID, logDate: String) async throws -> [Clip] {
        try await client
            .from("clips")
            .select()
            .eq("room_id", value: roomID.uuidString)
            .eq("log_date", value: logDate)
            .order("recorded_at")
            .execute()
            .value
    }
}

enum ClipRepositoryError: Error, Equatable, Sendable {
    case notAuthenticated
    case notPermitted
}
```

`AppEnvironment` 加上 `let clips: any ClipRepository`，並在 `live(config:)` 建立：
```swift
            clips: SupabaseClipRepository(
                client: client,
                currentUserID: { [client] in try? await client.auth.session.user.id }
            ),
```

`ImeTimeTests/Fakes/FakeClipRepository.swift`：
```swift
import Foundation
import ImeTimeCore
@testable import ImeTime

actor FakeClipRepository: ClipRepository {
    struct CreateCall: Equatable {
        let roomID: UUID
        let durationMs: Int
        let captionText: String?
        let emoji: String?
    }

    var errorToThrow: Error?
    var clipsByDay: [String: [Clip]] = [:]
    private(set) var createCalls: [CreateCall] = []
    private(set) var readyCalls: [UUID] = []
    private(set) var failedCalls: [UUID] = []
    private(set) var lastCreated: Clip?

    func fail(with error: Error?) { errorToThrow = error }
    func set(clips: [Clip], for logDate: String) { clipsByDay[logDate] = clips }

    func createClip(roomID: UUID, recordedAt: Date, durationMs: Int, caption: ClipCaption) async throws -> Clip {
        if let errorToThrow { throw errorToThrow }
        createCalls.append(CreateCall(roomID: roomID, durationMs: durationMs,
                                      captionText: caption.text, emoji: caption.emoji))
        let clip = Self.makeClip(roomID: roomID, recordedAt: recordedAt,
                                 durationMs: durationMs, caption: caption)
        lastCreated = clip
        return clip
    }

    func markReady(clipID: UUID) async throws {
        if let errorToThrow { throw errorToThrow }
        readyCalls.append(clipID)
    }

    func markFailed(clipID: UUID) async throws {
        if let errorToThrow { throw errorToThrow }
        failedCalls.append(clipID)
    }

    func clips(roomID: UUID, logDate: String) async throws -> [Clip] {
        if let errorToThrow { throw errorToThrow }
        return clipsByDay[logDate] ?? []
    }

    static func makeClip(
        id: UUID = UUID(),
        roomID: UUID = UUID(),
        userID: UUID = UUID(),
        recordedAt: Date = Date(timeIntervalSince1970: 1_756_800_000),
        durationMs: Int = 2000,
        caption: ClipCaption = .empty,
        status: Clip.Status = .uploading
    ) -> Clip {
        let slot = LogSlot.slot(for: recordedAt, timeZoneID: "Asia/Taipei")
            ?? LogSlot(logDate: "2026-09-03", hourSlot: 0)
        let prefix = "\(roomID.uuidString.lowercased())/\(slot.logDate)/\(userID.uuidString.lowercased())/\(id.uuidString.lowercased())"
        return Clip(id: id, roomID: roomID, userID: userID, recordedAt: recordedAt,
                    logDate: slot.logDate, hourSlot: slot.hourSlot,
                    videoKey: "\(prefix).mov", posterKey: "\(prefix).jpg",
                    durationMs: durationMs, width: 1920, height: 1080,
                    caption: caption.text, emoji: caption.emoji,
                    status: status, createdAt: recordedAt)
    }
}
```
- [ ] **Step 4: 建置與測試**

```bash
make build && make test-core && make test-app
```
Expected：全部 exit 0；Core 38，App 測試數不變。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(clips): add Clip model, caption value type and ClipRepository"
```

---

### Task 6: 上傳重試策略與簽名 URL 客戶端

**Files:**
- Create: `Packages/ImeTimeCore/Sources/ImeTimeCore/Clips/UploadState.swift`, `ImeTime/Services/Clips/SignedURLClient.swift`, `ImeTimeTests/Fakes/FakeSignedURLClient.swift`
- Test: `Packages/ImeTimeCore/Tests/ImeTimeCoreTests/UploadStateTests.swift`

**Interfaces:**
- Consumes: Task 4 的 Edge Function
- Produces:
  - `public enum UploadOutcome: Equatable, Sendable { case retry(after: TimeInterval); case giveUp }`
  - `public enum UploadRetryPolicy { static let maxAttempts = 12; static let maxElapsed: TimeInterval = 86_400; static let cap: TimeInterval = 3_600; static let base: TimeInterval = 5; static func next(afterAttempt attempt: Int, elapsed: TimeInterval) -> UploadOutcome }`
  - `enum SignedURLKind: String, Sendable { case video, poster }`、`enum SignedURLAction: String, Sendable { case upload, download }`
  - `protocol SignedURLClient: Sendable { func signedURL(clipID: UUID, kind: SignedURLKind, action: SignedURLAction) async throws -> URL }`
  - `struct SupabaseSignedURLClient: SignedURLClient`
  - `actor FakeSignedURLClient: SignedURLClient`（`requests`、`urlToReturn`、`errorToThrow`）

- [ ] **Step 1: 寫失敗測試**

`Packages/ImeTimeCore/Tests/ImeTimeCoreTests/UploadStateTests.swift`：
```swift
import Foundation
import Testing
@testable import ImeTimeCore

@Suite struct UploadStateTests {
    @Test func firstRetryWaitsTheBaseDelay() {
        #expect(UploadRetryPolicy.next(afterAttempt: 1, elapsed: 0) == .retry(after: 5))
    }

    @Test func delayDoublesEachAttempt() {
        #expect(UploadRetryPolicy.next(afterAttempt: 2, elapsed: 0) == .retry(after: 10))
        #expect(UploadRetryPolicy.next(afterAttempt: 3, elapsed: 0) == .retry(after: 20))
    }

    @Test func delayIsCappedAtOneHour() {
        // 第 11 次的原始退避是 5 * 2^10 = 5120 秒，超過上限
        #expect(UploadRetryPolicy.next(afterAttempt: 11, elapsed: 0) == .retry(after: 3_600))
    }

    @Test func givesUpAfterTheAttemptCap() {
        #expect(UploadRetryPolicy.next(afterAttempt: 12, elapsed: 0) == .giveUp)
    }

    @Test func givesUpAfterTwentyFourHours() {
        #expect(UploadRetryPolicy.next(afterAttempt: 2, elapsed: 86_400) == .giveUp)
    }

    @Test func stillRetriesJustBeforeTheDeadline() {
        #expect(UploadRetryPolicy.next(afterAttempt: 2, elapsed: 86_399) == .retry(after: 10))
    }
}
```

```bash
make test-core
```
Expected：`cannot find 'UploadRetryPolicy' in scope`。

- [ ] **Step 2: 實作**

`Packages/ImeTimeCore/Sources/ImeTimeCore/Clips/UploadState.swift`：
```swift
import Foundation

public enum UploadOutcome: Equatable, Sendable {
    case retry(after: TimeInterval)
    case giveUp
}

/// 背景上傳失敗後要不要再試、隔多久。指數退避，但有次數與總時長兩道上限，
/// 免得一支永遠傳不上去的片段一直佔著佇列。
public enum UploadRetryPolicy {
    public static let maxAttempts = 12
    public static let maxElapsed: TimeInterval = 24 * 60 * 60
    public static let cap: TimeInterval = 60 * 60
    public static let base: TimeInterval = 5

    /// - Parameters:
    ///   - attempt: 已經失敗過幾次（第一次失敗傳 1）
    ///   - elapsed: 從第一次嘗試到現在經過幾秒
    public static func next(afterAttempt attempt: Int, elapsed: TimeInterval) -> UploadOutcome {
        guard attempt < maxAttempts, elapsed < maxElapsed else { return .giveUp }
        let delay = base * pow(2, Double(attempt - 1))
        return .retry(after: min(delay, cap))
    }
}
```

```bash
make test-core
```
Expected：44 tests passed（38 + 6）。

- [ ] **Step 3: 寫 SignedURLClient 與 Fake**

`ImeTime/Services/Clips/SignedURLClient.swift`：
```swift
import Foundation
import Supabase

enum SignedURLKind: String, Sendable {
    case video, poster
}

enum SignedURLAction: String, Sendable {
    case upload, download
}

enum SignedURLError: Error, Equatable, Sendable {
    /// Edge Function 回的錯誤字串，例如 not_owner、not_uploading、not_found
    case rejected(String)
    case malformedResponse
}

protocol SignedURLClient: Sendable {
    func signedURL(clipID: UUID, kind: SignedURLKind, action: SignedURLAction) async throws -> URL
}

struct SupabaseSignedURLClient: SignedURLClient {
    let client: SupabaseClient

    func signedURL(clipID: UUID, kind: SignedURLKind, action: SignedURLAction) async throws -> URL {
        struct Request: Encodable {
            let clipId: String
            let kind: String
            let action: String
        }
        struct Response: Decodable {
            let url: String?
            let error: String?
        }
        let response: Response = try await client.functions.invoke(
            "sign-clip-url",
            options: FunctionInvokeOptions(
                body: Request(clipId: clipID.uuidString.lowercased(),
                              kind: kind.rawValue,
                              action: action.rawValue)
            )
        )
        if let error = response.error { throw SignedURLError.rejected(error) }
        guard let raw = response.url, let url = URL(string: raw) else {
            throw SignedURLError.malformedResponse
        }
        return url
    }
}
```
若 `functions.invoke` 在非 2xx 時直接丟 `FunctionsError` 而不是回傳 body，就改成 catch `FunctionsError` 並把它的 body 解析成 `error` 字串再丟 `SignedURLError.rejected`；查 supabase-swift 的 `Sources/Functions/` 決定，並記在 Deviations。

`ImeTimeTests/Fakes/FakeSignedURLClient.swift`：
```swift
import Foundation
@testable import ImeTime

actor FakeSignedURLClient: SignedURLClient {
    struct Request: Equatable {
        let clipID: UUID
        let kind: SignedURLKind
        let action: SignedURLAction
    }

    var urlToReturn = URL(string: "https://example.test/signed")!
    var errorToThrow: Error?
    private(set) var requests: [Request] = []

    func set(url: URL) { urlToReturn = url }
    func fail(with error: Error?) { errorToThrow = error }

    func signedURL(clipID: UUID, kind: SignedURLKind, action: SignedURLAction) async throws -> URL {
        if let errorToThrow { throw errorToThrow }
        requests.append(Request(clipID: clipID, kind: kind, action: action))
        return urlToReturn
    }
}

extension SignedURLKind: Equatable {}
extension SignedURLAction: Equatable {}
```
`SignedURLKind` / `SignedURLAction` 是 `String` 的 raw representable，已自動取得 `Equatable`；若編譯器抱怨重複 conformance，把最後兩行刪掉。

- [ ] **Step 4: 建置**

```bash
make build && make test-app
```
Expected：兩者 exit 0。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(clips): add upload retry policy and signed URL client"
```

---

### Task 7: 待送佇列與背景上傳器

**Files:**
- Create: `ImeTime/Services/Clips/PendingClipStore.swift`, `ImeTime/Services/Clips/ClipUploader.swift`
- Test: `ImeTimeTests/ClipUploaderTests.swift`
- Modify: `ImeTime/App/AppEnvironment.swift`, `project.yml`

**Interfaces:**
- Consumes: `ClipRepository`、`SignedURLClient`、`UploadRetryPolicy`
- Produces:
  - `@Model final class PendingClip`（SwiftData：`clipID`、`videoPath`、`posterPath`、`attempt`、`firstAttemptAt`、`videoUploaded`）
  - `actor PendingClipStore { init(inMemory: Bool) throws; func enqueue(...) throws; func all() throws -> [PendingClipSnapshot]; func markVideoUploaded(clipID:) throws; func remove(clipID:) throws; func recordFailure(clipID:) throws -> Int }`
  - `struct PendingClipSnapshot: Equatable, Sendable { clipID, videoURL, posterURL, attempt, firstAttemptAt, videoUploaded }`
  - `protocol ClipUploading: Sendable { func enqueue(clip: Clip, videoURL: URL, posterURL: URL) async throws; func drain() async }`
  - `actor ClipUploader: ClipUploading`
  - `AppEnvironment.uploader: any ClipUploading`

**設計說明：** `ClipUploader` 本身不直接建立 background `URLSession`（那需要 App delegate 的喚醒回呼，屬於 Task 9 的接線）。它把「要傳哪一個檔案、傳到哪個 URL、傳完要做什麼」的順序邏輯集中在一處，並透過一個可注入的 `ClipUploadTransport` 執行實際傳輸，讓這一段可以完整測試。

- [ ] **Step 1: 寫失敗測試**

`ImeTimeTests/ClipUploaderTests.swift`：
```swift
import Foundation
import ImeTimeCore
import Testing
@testable import ImeTime

/// 記錄每一次 PUT，並可指定第幾次要失敗
actor FakeTransport: ClipUploadTransport {
    struct Put: Equatable {
        let url: URL
        let fileURL: URL
        let contentType: String
    }
    private(set) var puts: [Put] = []
    var failuresRemaining = 0

    func failNext(_ count: Int) { failuresRemaining = count }

    func upload(fileURL: URL, to url: URL, contentType: String) async throws {
        puts.append(Put(url: url, fileURL: fileURL, contentType: contentType))
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw URLError(.networkConnectionLost)
        }
    }
}

@Suite struct ClipUploaderTests {
    private func makeSUT() async throws -> (ClipUploader, FakeClipRepository, FakeSignedURLClient, FakeTransport) {
        let clips = FakeClipRepository()
        let urls = FakeSignedURLClient()
        let transport = FakeTransport()
        let store = try PendingClipStore(inMemory: true)
        let uploader = ClipUploader(store: store, clips: clips, signedURLs: urls, transport: transport)
        return (uploader, clips, urls, transport)
    }

    private func tempFile(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try Data("x".utf8).write(to: url)
        return url
    }

    @Test func uploadsVideoThenPosterThenMarksReady() async throws {
        let (uploader, clips, urls, transport) = try await makeSUT()
        let clip = FakeClipRepository.makeClip()
        try await uploader.enqueue(clip: clip, videoURL: tempFile("v.mov"), posterURL: tempFile("p.jpg"))

        await uploader.drain()

        let requests = await urls.requests
        #expect(requests.map(\.kind) == [.video, .poster])
        #expect(requests.allSatisfy { $0.action == .upload })
        let puts = await transport.puts
        #expect(puts.map(\.contentType) == ["video/quicktime", "image/jpeg"])
        #expect(await clips.readyCalls == [clip.id])
        #expect(await clips.failedCalls.isEmpty)
    }

    @Test func aFailedVideoUploadLeavesTheClipQueuedAndNotReady() async throws {
        let (uploader, clips, _, transport) = try await makeSUT()
        await transport.failNext(1)
        let clip = FakeClipRepository.makeClip()
        try await uploader.enqueue(clip: clip, videoURL: tempFile("v.mov"), posterURL: tempFile("p.jpg"))

        await uploader.drain()

        #expect(await clips.readyCalls.isEmpty)
        #expect(await clips.failedCalls.isEmpty)
        #expect(await uploader.pendingCount() == 1)
    }

    @Test func aRetryDoesNotRepeatAnAlreadyUploadedVideo() async throws {
        let (uploader, clips, _, transport) = try await makeSUT()
        await transport.failNext(2)   // 影片成功、海報失敗（第一次 drain）
        let clip = FakeClipRepository.makeClip()
        try await uploader.enqueue(clip: clip, videoURL: tempFile("v.mov"), posterURL: tempFile("p.jpg"))

        await transport.failNext(1)   // 只讓海報失敗一次
        await uploader.drain()
        let afterFirst = await transport.puts.count
        await uploader.drain()
        let afterSecond = await transport.puts.count

        // 第二輪只重傳海報，不會再傳一次影片
        #expect(afterSecond == afterFirst + 1)
        #expect(await clips.readyCalls == [clip.id])
        #expect(await uploader.pendingCount() == 0)
    }

    @Test func givingUpMarksTheClipFailedAndClearsTheQueue() async throws {
        let (uploader, clips, _, transport) = try await makeSUT()
        let clip = FakeClipRepository.makeClip()
        try await uploader.enqueue(clip: clip, videoURL: tempFile("v.mov"), posterURL: tempFile("p.jpg"))

        // 讓它失敗到超過次數上限
        await transport.failNext(UploadRetryPolicy.maxAttempts + 1)
        for _ in 0...UploadRetryPolicy.maxAttempts {
            await uploader.drain()
        }

        #expect(await clips.failedCalls == [clip.id])
        #expect(await uploader.pendingCount() == 0)
    }
}
```

```bash
make test-app
```
Expected：`cannot find 'ClipUploader' in scope`。

- [ ] **Step 2: 寫 PendingClipStore**

`ImeTime/Services/Clips/PendingClipStore.swift`：
```swift
import Foundation
import SwiftData

@Model
final class PendingClip {
    @Attribute(.unique) var clipID: UUID
    var videoPath: String
    var posterPath: String
    var attempt: Int
    var firstAttemptAt: Date
    var videoUploaded: Bool

    init(clipID: UUID, videoPath: String, posterPath: String) {
        self.clipID = clipID
        self.videoPath = videoPath
        self.posterPath = posterPath
        attempt = 0
        firstAttemptAt = Date()
        videoUploaded = false
    }
}

struct PendingClipSnapshot: Equatable, Sendable {
    let clipID: UUID
    let videoURL: URL
    let posterURL: URL
    let attempt: Int
    let firstAttemptAt: Date
    let videoUploaded: Bool
}

/// 待送佇列。App 被殺掉後重啟仍要知道有哪些片段還沒傳完，所以用 SwiftData 落地。
actor PendingClipStore {
    private let container: ModelContainer
    private let context: ModelContext

    init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: PendingClip.self, configurations: configuration)
        context = ModelContext(container)
    }

    func enqueue(clipID: UUID, videoURL: URL, posterURL: URL) throws {
        context.insert(PendingClip(clipID: clipID, videoPath: videoURL.path, posterPath: posterURL.path))
        try context.save()
    }

    func all() throws -> [PendingClipSnapshot] {
        let descriptor = FetchDescriptor<PendingClip>(sortBy: [SortDescriptor(\.firstAttemptAt)])
        return try context.fetch(descriptor).map {
            PendingClipSnapshot(clipID: $0.clipID,
                                videoURL: URL(fileURLWithPath: $0.videoPath),
                                posterURL: URL(fileURLWithPath: $0.posterPath),
                                attempt: $0.attempt,
                                firstAttemptAt: $0.firstAttemptAt,
                                videoUploaded: $0.videoUploaded)
        }
    }

    func markVideoUploaded(clipID: UUID) throws {
        guard let pending = try fetch(clipID) else { return }
        pending.videoUploaded = true
        try context.save()
    }

    /// 回傳累加後的嘗試次數。
    @discardableResult
    func recordFailure(clipID: UUID) throws -> Int {
        guard let pending = try fetch(clipID) else { return 0 }
        pending.attempt += 1
        try context.save()
        return pending.attempt
    }

    func remove(clipID: UUID) throws {
        guard let pending = try fetch(clipID) else { return }
        context.delete(pending)
        try context.save()
    }

    private func fetch(_ clipID: UUID) throws -> PendingClip? {
        var descriptor = FetchDescriptor<PendingClip>(predicate: #Predicate { $0.clipID == clipID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
```

- [ ] **Step 3: 寫 ClipUploader**

`ImeTime/Services/Clips/ClipUploader.swift`：
```swift
import Foundation
import ImeTimeCore

/// 實際把檔案 PUT 上去的傳輸層。抽出來是為了讓上傳順序邏輯可以完整測試，
/// 正式實作在 Task 9 用 background URLSession 提供。
protocol ClipUploadTransport: Sendable {
    func upload(fileURL: URL, to url: URL, contentType: String) async throws
}

protocol ClipUploading: Sendable {
    func enqueue(clip: Clip, videoURL: URL, posterURL: URL) async throws
    func drain() async
}

/// 影片 → 海報 → 標記 ready。任何一步失敗就留在佇列裡等下一次 drain；
/// 超過重試上限才把片段標成 failed 並移出佇列。
actor ClipUploader: ClipUploading {
    private let store: PendingClipStore
    private let clips: any ClipRepository
    private let signedURLs: any SignedURLClient
    private let transport: any ClipUploadTransport

    init(store: PendingClipStore,
         clips: any ClipRepository,
         signedURLs: any SignedURLClient,
         transport: any ClipUploadTransport) {
        self.store = store
        self.clips = clips
        self.signedURLs = signedURLs
        self.transport = transport
    }

    func enqueue(clip: Clip, videoURL: URL, posterURL: URL) async throws {
        try await store.enqueue(clipID: clip.id, videoURL: videoURL, posterURL: posterURL)
    }

    func pendingCount() async -> Int {
        ((try? await store.all()) ?? []).count
    }

    func drain() async {
        let pending = (try? await store.all()) ?? []
        for item in pending {
            await process(item)
        }
    }

    private func process(_ item: PendingClipSnapshot) async {
        do {
            if !item.videoUploaded {
                let url = try await signedURLs.signedURL(clipID: item.clipID, kind: .video, action: .upload)
                try await transport.upload(fileURL: item.videoURL, to: url, contentType: "video/quicktime")
                try await store.markVideoUploaded(clipID: item.clipID)
            }
            let posterURL = try await signedURLs.signedURL(clipID: item.clipID, kind: .poster, action: .upload)
            try await transport.upload(fileURL: item.posterURL, to: posterURL, contentType: "image/jpeg")

            try await clips.markReady(clipID: item.clipID)
            try? await store.remove(clipID: item.clipID)
            removeLocalFiles(item)
        } catch {
            await handleFailure(item)
        }
    }

    private func handleFailure(_ item: PendingClipSnapshot) async {
        let attempt = (try? await store.recordFailure(clipID: item.clipID)) ?? item.attempt + 1
        let elapsed = Date().timeIntervalSince(item.firstAttemptAt)
        if case .giveUp = UploadRetryPolicy.next(afterAttempt: attempt, elapsed: elapsed) {
            try? await clips.markFailed(clipID: item.clipID)
            try? await store.remove(clipID: item.clipID)
            removeLocalFiles(item)
        }
    }

    private func removeLocalFiles(_ item: PendingClipSnapshot) {
        try? FileManager.default.removeItem(at: item.videoURL)
        try? FileManager.default.removeItem(at: item.posterURL)
    }
}
```

- [ ] **Step 4: 接上 AppEnvironment**

`PendingClipStore.init` 會 throw，而 `AppEnvironment.live(config:)` 目前不會。最小的處理是讓它也 throw 同一個錯誤型別，`ImeTimeApp` 既有的設定錯誤畫面就能直接接住。

`ImeTime/App/AppConfig.swift` — `AppConfigError` 加一個 case 與訊息：
```swift
    /// 本機待送佇列（SwiftData）建立失敗。
    case storageUnavailable
```
```swift
        case .storageUnavailable:
            return "本機資料庫無法建立，請刪除 App 後重新安裝。"
```

`ImeTime/App/AppEnvironment.swift`：
```swift
@MainActor
struct AppEnvironment {
    let auth: any AuthService
    let profiles: any ProfileRepository
    let rooms: any RoomRepository
    let clips: any ClipRepository
    let uploader: any ClipUploading

    static func live(config: AppConfig) throws(AppConfigError) -> AppEnvironment {
        let client = SupabaseClient(supabaseURL: config.supabaseURL, supabaseKey: config.supabaseAnonKey)
        let store: PendingClipStore
        do {
            store = try PendingClipStore()
        } catch {
            throw .storageUnavailable
        }
        let clips = SupabaseClipRepository(
            client: client,
            currentUserID: { [client] in try? await client.auth.session.user.id }
        )
        return AppEnvironment(
            auth: SupabaseAuthService(client: client),
            profiles: SupabaseProfileRepository(client: client),
            rooms: SupabaseRoomRepository(client: client),
            clips: clips,
            uploader: ClipUploader(
                store: store,
                clips: clips,
                signedURLs: SupabaseSignedURLClient(client: client),
                transport: BackgroundUploadTransport.shared
            )
        )
    }
}
```
`BackgroundUploadTransport` 由 Task 9 提供。在本任務先建一個最小的暫時實作，讓專案編得起來，Task 9 再換掉：

`ImeTime/Services/Clips/BackgroundUploadTransport.swift`：
```swift
import Foundation

/// Task 9 會換成 background URLSession 的版本。這一版用預設 session，
/// 功能正確但 App 被殺掉就不會續傳。
final class BackgroundUploadTransport: ClipUploadTransport {
    static let shared = BackgroundUploadTransport()

    func upload(fileURL: URL, to url: URL, contentType: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
```

`ImeTime/App/ImeTimeApp.swift` 的 `init()` 把 `AppEnvironment.live(config:)` 改成 `try AppEnvironment.live(config: config)`（同一個 `do` 區塊內，catch 不用改，因為兩者都丟 `AppConfigError`）。

- [ ] **Step 5: 執行測試**

```bash
make test-core && make build && make test-app
```
Expected：Core 44；App 測試多 4 個（`ClipUploaderTests`），全部通過。

若 `aRetryDoesNotRepeatAnAlreadyUploadedVideo` 的計數對不上，先確認 `FakeTransport.failNext` 的語意（設定的是「接下來幾次失敗」而非「第幾次失敗」），必要時調整測試裡的 `failNext` 呼叫次數，但**不要**放寬「第二輪只重傳海報」這個斷言。

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(clips): add the pending queue and upload orchestration"
```

---

### Task 8: 橫式 Recorder（AVFoundation）

**Files:**
- Create: `ImeTime/Services/Recording/Recorder.swift`, `ImeTime/Services/Recording/AVFoundationRecorder.swift`, `ImeTimeTests/Fakes/FakeRecorder.swift`
- Modify: `project.yml`（Info.plist 已有相機與麥克風說明，確認即可）

**Interfaces:**
- Produces:
  - `struct RecordedClip: Equatable, Sendable { let videoURL: URL; let posterURL: URL; let durationMs: Int; let recordedAt: Date }`
  - `enum RecorderError: Error, Equatable, Sendable { case permissionDenied; case unavailable; case interrupted; case tooShort(ms: Int) }`
  - `protocol Recorder: AnyObject, Sendable { func prepare() async throws; func record() async throws -> RecordedClip; func flipCamera() async; var previewSource: AVCaptureSession? { get } }`
  - `final class AVFoundationRecorder: Recorder`
  - `actor FakeRecorder: Recorder`（`recordedClipToReturn`、`errorToThrow`、`prepareCount`、`recordCount`、`flipCount`）

**測試策略：** iOS 模擬器沒有相機，`AVFoundationRecorder` 只能在實機驗證，因此本任務不寫它的單元測試——它的正確性由 Task 11 的實機驗收把關。`FakeRecorder` 讓 Task 9 的 view model 可以完整測試。這一點與 spec §7「相機注意事項」一致。

- [ ] **Step 1: 寫 protocol 與錯誤型別**

`ImeTime/Services/Recording/Recorder.swift`：
```swift
import AVFoundation
import Foundation

/// 一次錄製的產物：2 秒橫式影片，加上從 0.5 秒處抽出的海報圖。
struct RecordedClip: Equatable, Sendable {
    let videoURL: URL
    let posterURL: URL
    let durationMs: Int
    let recordedAt: Date
}

enum RecorderError: Error, Equatable, Sendable {
    case permissionDenied
    case unavailable
    case interrupted
    case tooShort(ms: Int)
}

extension RecorderError {
    var userMessage: String {
        switch self {
        case .permissionDenied: "需要相機與麥克風權限才能拍攝，請到「設定」開啟。"
        case .unavailable: "這台裝置的相機無法使用。"
        case .interrupted: "錄影被中斷了，請再試一次。"
        case .tooShort: "錄影太短了，請再試一次。"
        }
    }
}

protocol Recorder: AnyObject, Sendable {
    /// 建立並啟動 capture session。進入房間時先呼叫，讓按下快門時預覽已經是熱的。
    func prepare() async throws
    /// 錄滿 2.0 秒後自動停止並回傳產物。
    func record() async throws -> RecordedClip
    func flipCamera() async
    /// 給 SwiftUI 預覽層用；FakeRecorder 回 nil。
    var previewSource: AVCaptureSession? { get }
}
```

- [ ] **Step 2: 寫 AVFoundationRecorder**

`ImeTime/Services/Recording/AVFoundationRecorder.swift`：
```swift
import AVFoundation
import Foundation
import UIKit

/// 固定輸出橫式 1920×1080 HEVC + 音訊，時長 2.0 秒。
/// 錄影一律以 landscapeRight 的方向寫檔，所以手機直握時畫面會被旋轉後裁切成 16:9。
final class AVFoundationRecorder: NSObject, Recorder, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var continuation: CheckedContinuation<URL, Error>?
    private var recordingStartedAt: Date?
    private let queue = DispatchQueue(label: "com.zenwang.imetime.recorder")

    static let clipDuration = CMTime(seconds: 2.0, preferredTimescale: 600)

    var previewSource: AVCaptureSession? { session }

    func prepare() async throws {
        guard await Self.hasPermission(for: .video), await Self.hasPermission(for: .audio) else {
            throw RecorderError.permissionDenied
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try configureSession()
                    if !session.isRunning { session.startRunning() }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func record() async throws -> RecordedClip {
        let recordedAt = Date()
        let videoURL = try await startAndWait()
        let posterURL = try await Self.makePoster(from: videoURL)
        let duration = try await AVURLAsset(url: videoURL).load(.duration).seconds
        let durationMs = Int((duration * 1000).rounded())
        guard durationMs >= 1800 else { throw RecorderError.tooShort(ms: durationMs) }
        return RecordedClip(videoURL: videoURL, posterURL: posterURL,
                            durationMs: min(durationMs, 2200), recordedAt: recordedAt)
    }

    func flipCamera() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                guard let current = videoInput else { return continuation.resume() }
                let next: AVCaptureDevice.Position = current.device.position == .back ? .front : .back
                session.beginConfiguration()
                session.removeInput(current)
                if let device = Self.camera(at: next), let input = try? AVCaptureDeviceInput(device: device),
                   session.canAddInput(input) {
                    session.addInput(input)
                    videoInput = input
                } else {
                    session.addInput(current)
                }
                session.commitConfiguration()
                continuation.resume()
            }
        }
    }

    // MARK: - Session

    private func configureSession() throws {
        guard videoInput == nil else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1920x1080

        guard let camera = Self.camera(at: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { throw RecorderError.unavailable }
        session.addInput(input)
        videoInput = input

        if let microphone = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        guard session.canAddOutput(output) else { throw RecorderError.unavailable }
        session.addOutput(output)
        output.maxRecordedDuration = Self.clipDuration
        if let connection = output.connection(with: .video) {
            connection.videoRotationAngle = 0   // landscapeRight
            if let codec = output.availableVideoCodecTypes.first(where: { $0 == .hevc }) {
                output.setOutputSettings([AVVideoCodecKey: codec], for: connection)
            }
        }
    }

    private func startAndWait() async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mov")
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard session.isRunning else {
                    return continuation.resume(throwing: RecorderError.unavailable)
                }
                self.continuation = continuation
                recordingStartedAt = Date()
                output.startRecording(to: destination, recordingDelegate: self)
            }
        }
    }

    private static func camera(at position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: position
        ).devices.first
    }

    private static func hasPermission(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: mediaType)
        default: return false
        }
    }

    private static func makePoster(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        let (image, _) = try await generator.image(at: time)
        guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else {
            throw RecorderError.interrupted
        }
        let posterURL = videoURL.deletingPathExtension().appendingPathExtension("jpg")
        try data.write(to: posterURL)
        return posterURL
    }
}

extension AVFoundationRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: (any Error)?) {
        let pending = continuation
        continuation = nil
        // maxRecordedDuration 到達時會帶一個 error，但檔案是完整的
        let reachedLimit = (error as NSError?)?.code == AVError.maximumDurationReached.rawValue
        if let error, !reachedLimit {
            pending?.resume(throwing: RecorderError.interrupted)
        } else {
            pending?.resume(returning: outputFileURL)
        }
    }
}
```

- [ ] **Step 3: 寫 FakeRecorder**

`ImeTimeTests/Fakes/FakeRecorder.swift`：
```swift
import AVFoundation
import Foundation
@testable import ImeTime

final class FakeRecorder: Recorder, @unchecked Sendable {
    private let lock = NSLock()
    private var _prepareCount = 0
    private var _recordCount = 0
    private var _flipCount = 0

    var errorToThrow: Error?
    var clipToReturn: RecordedClip = FakeRecorder.makeClip()

    var prepareCount: Int { lock.withLock { _prepareCount } }
    var recordCount: Int { lock.withLock { _recordCount } }
    var flipCount: Int { lock.withLock { _flipCount } }

    var previewSource: AVCaptureSession? { nil }

    func prepare() async throws {
        lock.withLock { _prepareCount += 1 }
        if let errorToThrow { throw errorToThrow }
    }

    func record() async throws -> RecordedClip {
        lock.withLock { _recordCount += 1 }
        if let errorToThrow { throw errorToThrow }
        return clipToReturn
    }

    func flipCamera() async {
        lock.withLock { _flipCount += 1 }
    }

    /// 產生兩個真的存在的暫存檔，讓上傳流程的測試有東西可以搬。
    static func makeClip(durationMs: Int = 2000) -> RecordedClip {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let videoURL = base.appendingPathExtension("mov")
        let posterURL = base.appendingPathExtension("jpg")
        try? Data("video".utf8).write(to: videoURL)
        try? Data("poster".utf8).write(to: posterURL)
        return RecordedClip(videoURL: videoURL, posterURL: posterURL,
                            durationMs: durationMs,
                            recordedAt: Date(timeIntervalSince1970: 1_756_800_000))
    }
}
```

- [ ] **Step 4: 建置**

```bash
make build && make test-app
```
Expected：兩者 exit 0，測試數不變。若 `videoRotationAngle` 在 iOS 18 SDK 需要先檢查 `isVideoRotationAngleSupported(_:)`，加上該檢查並記在 Deviations。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(recording): add the landscape 2-second recorder"
```

---

### Task 9: 相機畫面與送出流程

**Files:**
- Create: `ImeTime/Features/Camera/CameraViewModel.swift`, `CameraView.swift`, `CameraPreviewLayer.swift`, `ClipReviewView.swift`
- Modify: `ImeTime/Features/Rooms/RoomView.swift`, `ImeTime/Services/Clips/BackgroundUploadTransport.swift`, `ImeTime/App/ImeTimeApp.swift`
- Test: `ImeTimeTests/CameraViewModelTests.swift`

**Interfaces:**
- Consumes: `Recorder`、`ClipRepository`、`ClipUploading`、`ClipCaption`
- Produces:
  - `@MainActor @Observable final class CameraViewModel { enum Phase: Equatable { case idle, recording, reviewing(RecordedClip), submitting }; var captionInput: String; var emoji: String?; private(set) var phase: Phase; private(set) var errorMessage: String?; init(roomID: UUID, recorder: any Recorder, clips: any ClipRepository, uploader: any ClipUploading); func prepare() async; func startRecording() async; func submit() async -> Bool; func discard() }`
  - `struct CameraView: View { init(roomID: UUID, environment: AppEnvironment, onFinished: @escaping () -> Void) }`

- [ ] **Step 1: 寫失敗測試**

`ImeTimeTests/CameraViewModelTests.swift`：
```swift
import Foundation
import ImeTimeCore
import Testing
@testable import ImeTime

@MainActor
@Suite struct CameraViewModelTests {
    private func makeSUT() -> (CameraViewModel, FakeRecorder, FakeClipRepository, FakeUploader) {
        let recorder = FakeRecorder()
        let clips = FakeClipRepository()
        let uploader = FakeUploader()
        let sut = CameraViewModel(roomID: UUID(), recorder: recorder, clips: clips, uploader: uploader)
        return (sut, recorder, clips, uploader)
    }

    @Test func startsIdleAndPreparesTheRecorder() async {
        let (sut, recorder, _, _) = makeSUT()
        #expect(sut.phase == .idle)
        await sut.prepare()
        #expect(recorder.prepareCount == 1)
        #expect(sut.errorMessage == nil)
    }

    @Test func permissionDeniedSurfacesItsMessage() async {
        let (sut, recorder, _, _) = makeSUT()
        recorder.errorToThrow = RecorderError.permissionDenied
        await sut.prepare()
        #expect(sut.errorMessage == RecorderError.permissionDenied.userMessage)
    }

    @Test func recordingMovesToReviewing() async {
        let (sut, recorder, _, _) = makeSUT()
        let clip = FakeRecorder.makeClip()
        recorder.clipToReturn = clip
        await sut.startRecording()
        #expect(sut.phase == .reviewing(clip))
        #expect(recorder.recordCount == 1)
    }

    @Test func submitCreatesTheClipThenEnqueuesTheUpload() async {
        let (sut, recorder, clips, uploader) = makeSUT()
        recorder.clipToReturn = FakeRecorder.makeClip()
        await sut.startRecording()
        sut.captionInput = "  午餐 "
        sut.emoji = "🌮"

        #expect(await sut.submit() == true)

        let calls = await clips.createCalls
        #expect(calls.count == 1)
        #expect(calls.first?.captionText == "午餐")
        #expect(calls.first?.emoji == "🌮")
        let enqueued = await uploader.enqueued
        #expect(enqueued.count == 1)
        #expect(enqueued.first?.clipID == (await clips.lastCreated)?.id)
    }

    @Test func aTooLongCaptionBlocksSubmitWithoutTouchingTheRepository() async {
        let (sut, recorder, clips, _) = makeSUT()
        recorder.clipToReturn = FakeRecorder.makeClip()
        await sut.startRecording()
        sut.captionInput = String(repeating: "字", count: 41)

        #expect(await sut.submit() == false)
        #expect(sut.errorMessage == "字幕最多 40 個字。")
        #expect(await clips.createCalls.isEmpty)
    }

    @Test func aDuplicateSlotSurfacesAFriendlyMessage() async {
        let (sut, recorder, clips, uploader) = makeSUT()
        recorder.clipToReturn = FakeRecorder.makeClip()
        await clips.fail(with: ClipRepositoryError.notPermitted)
        await sut.startRecording()

        #expect(await sut.submit() == false)
        #expect(sut.errorMessage != nil)
        #expect(await uploader.enqueued.isEmpty)
    }

    @Test func discardReturnsToIdleAndClearsTheCaption() async {
        let (sut, recorder, _, _) = makeSUT()
        recorder.clipToReturn = FakeRecorder.makeClip()
        await sut.startRecording()
        sut.captionInput = "午餐"
        sut.discard()
        #expect(sut.phase == .idle)
        #expect(sut.captionInput.isEmpty)
        #expect(sut.emoji == nil)
    }
}

actor FakeUploader: ClipUploading {
    struct Enqueued: Equatable {
        let clipID: UUID
        let videoURL: URL
        let posterURL: URL
    }
    private(set) var enqueued: [Enqueued] = []
    private(set) var drainCount = 0
    var errorToThrow: Error?

    func fail(with error: Error?) { errorToThrow = error }

    func enqueue(clip: Clip, videoURL: URL, posterURL: URL) async throws {
        if let errorToThrow { throw errorToThrow }
        enqueued.append(Enqueued(clipID: clip.id, videoURL: videoURL, posterURL: posterURL))
    }

    func drain() async { drainCount += 1 }
}
```

```bash
make test-app
```
Expected：`cannot find 'CameraViewModel' in scope`。

- [ ] **Step 2: 實作 view model**

`ImeTime/Features/Camera/CameraViewModel.swift`：
```swift
import Foundation
import ImeTimeCore
import Observation

@MainActor
@Observable
final class CameraViewModel {
    enum Phase: Equatable {
        case idle
        case recording
        case reviewing(RecordedClip)
        case submitting
    }

    var captionInput = ""
    var emoji: String?
    private(set) var phase: Phase = .idle
    private(set) var errorMessage: String?

    private let roomID: UUID
    private let recorder: any Recorder
    private let clips: any ClipRepository
    private let uploader: any ClipUploading

    init(roomID: UUID, recorder: any Recorder, clips: any ClipRepository, uploader: any ClipUploading) {
        self.roomID = roomID
        self.recorder = recorder
        self.clips = clips
        self.uploader = uploader
    }

    func prepare() async {
        errorMessage = nil
        do {
            try await recorder.prepare()
        } catch let error as RecorderError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = "相機無法啟動，請再試一次。"
        }
    }

    func startRecording() async {
        guard phase == .idle else { return }
        errorMessage = nil
        phase = .recording
        do {
            let clip = try await recorder.record()
            phase = .reviewing(clip)
        } catch let error as RecorderError {
            errorMessage = error.userMessage
            phase = .idle
        } catch {
            errorMessage = "錄影失敗，請再試一次。"
            phase = .idle
        }
    }

    func flip() async {
        await recorder.flipCamera()
    }

    /// 成功回 true，呼叫端關閉相機。
    func submit() async -> Bool {
        guard case .reviewing(let recorded) = phase else { return false }
        errorMessage = nil

        let caption: ClipCaption
        do {
            caption = try ClipCaption(text: captionInput, emoji: emoji)
        } catch {
            errorMessage = error.userMessage
            return false
        }

        phase = .submitting
        do {
            let clip = try await clips.createClip(roomID: roomID,
                                                  recordedAt: recorded.recordedAt,
                                                  durationMs: recorded.durationMs,
                                                  caption: caption)
            try await uploader.enqueue(clip: clip,
                                       videoURL: recorded.videoURL,
                                       posterURL: recorded.posterURL)
            Task { await uploader.drain() }
            return true
        } catch {
            errorMessage = "這個小時已經有一支片段了，或是網路有問題。請稍後再試。"
            phase = .reviewing(recorded)
            return false
        }
    }

    func discard() {
        if case .reviewing(let recorded) = phase {
            try? FileManager.default.removeItem(at: recorded.videoURL)
            try? FileManager.default.removeItem(at: recorded.posterURL)
        }
        captionInput = ""
        emoji = nil
        errorMessage = nil
        phase = .idle
    }
}

extension ClipCaptionError {
    var userMessage: String {
        switch self {
        case .tooLong(let max): "字幕最多 \(max) 個字。"
        case .invalidEmoji: "請選一個 emoji。"
        }
    }
}
```

```bash
make test-app
```
Expected：多 7 個測試，全部通過。

- [ ] **Step 3: 寫相機畫面**

`ImeTime/Features/Camera/CameraPreviewLayer.swift`：
```swift
import AVFoundation
import SwiftUI

/// 把 AVCaptureVideoPreviewLayer 包成 SwiftUI view。session 為 nil（模擬器 / Fake）時顯示黑底。
struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
```

`ImeTime/Features/Camera/ClipReviewView.swift`：
```swift
import AVKit
import ImeTimeCore
import SwiftUI

/// 錄完之後的循環預覽，加上字幕與 emoji，再決定送出或丟棄。
struct ClipReviewView: View {
    let clip: RecordedClip
    @Bindable var viewModel: CameraViewModel
    let onSubmitted: () -> Void

    private static let emojiChoices = ["😀", "🌮", "☕️", "🌙", "🏃", "🎧", "🐈", "🌧️"]

    var body: some View {
        VStack(spacing: 16) {
            LoopingPlayer(url: clip.videoURL)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            TextField("加一句話（最多 \(ClipCaption.maxLength) 字）", text: $viewModel.captionInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                ForEach(Self.emojiChoices, id: \.self) { choice in
                    Button(choice) {
                        viewModel.emoji = viewModel.emoji == choice ? nil : choice
                    }
                    .font(.title2)
                    .opacity(viewModel.emoji == nil || viewModel.emoji == choice ? 1 : 0.35)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red).font(.footnote)
            }

            HStack(spacing: 12) {
                Button("取消", role: .destructive) { viewModel.discard() }
                    .buttonStyle(.bordered)
                Button("送出") {
                    Task { if await viewModel.submit() { onSubmitted() } }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.phase == .submitting)
            }
        }
        .padding(20)
    }
}

/// 2 秒的片段直接循環播放，靜音。
private struct LoopingPlayer: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVQueuePlayer()
        let item = AVPlayerItem(url: url)
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = true
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var looper: AVPlayerLooper?
    }
}
```

`ImeTime/Features/Camera/CameraView.swift`：
```swift
import SwiftUI

/// 全螢幕橫式相機。App 其餘部分是直式，只有這一頁鎖橫。
struct CameraView: View {
    @State private var viewModel: CameraViewModel
    private let recorder: any Recorder
    let onFinished: () -> Void

    init(roomID: UUID, environment: AppEnvironment, onFinished: @escaping () -> Void) {
        let recorder = AVFoundationRecorder()
        self.recorder = recorder
        _viewModel = State(initialValue: CameraViewModel(
            roomID: roomID,
            recorder: recorder,
            clips: environment.clips,
            uploader: environment.uploader
        ))
        self.onFinished = onFinished
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 送出中仍停在預覽畫面，只是按鈕變成 disabled
            if case .reviewing(let clip) = viewModel.phase {
                ClipReviewView(clip: clip, viewModel: viewModel, onSubmitted: onFinished)
            } else if case .submitting = viewModel.phase {
                ProgressView().tint(.white)
            } else {
                captureLayer
            }
        }
        .task { await viewModel.prepare() }
    }

    private var captureLayer: some View {
        ZStack {
            CameraPreviewLayer(session: recorder.previewSource)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Button("關閉") { onFinished() }
                        .padding()
                    Spacer()
                    Button {
                        Task { await viewModel.flip() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                    }
                    .padding()
                }
                Spacer()
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                }
                shutter
                    .padding(.bottom, 24)
            }
            .tint(.white)
            .foregroundStyle(.white)
        }
    }

    private var shutter: some View {
        Button {
            Task { await viewModel.startRecording() }
        } label: {
            Circle()
                .strokeBorder(.white, lineWidth: 5)
                .frame(width: 76, height: 76)
                .overlay {
                    Circle()
                        .fill(viewModel.phase == .recording ? .red : .white)
                        .frame(width: 58, height: 58)
                }
        }
        .disabled(viewModel.phase == .recording)
    }
}
```
- [ ] **Step 4: 從房間頁進入相機**

`ImeTime/Features/Rooms/RoomView.swift` — 目前是 `ContentUnavailableView` 佔位（時間線是 P2b）。加上一個 `@State private var isShowingCamera = false`，把描述文字改成「時間線將在下一階段加入。先試著拍一支 2 秒吧。」，並加上動作與 sheet：
```swift
        } actions: {
            Button("拍 2 秒") { isShowingCamera = true }
                .buttonStyle(.borderedProminent)
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraView(roomID: room.id, environment: environment) {
                isShowingCamera = false
            }
        }
```

- [ ] **Step 5: 背景 URLSession**

把 `ImeTime/Services/Clips/BackgroundUploadTransport.swift` 換成真正的背景 session，讓 App 被殺掉也會續傳：
```swift
import Foundation

/// background configuration 的 URLSession：App 被系統終止後，傳輸完成時會被喚醒。
final class BackgroundUploadTransport: NSObject, ClipUploadTransport, @unchecked Sendable {
    static let shared = BackgroundUploadTransport()

    /// 系統喚醒 App 時由 SwiftUI 的 backgroundTask 呼叫，讓 session 事件處理完再結束。
    var completionHandler: (@Sendable () -> Void)?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: "com.zenwang.imetime.upload")
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private let lock = NSLock()
    private var waiters: [Int: CheckedContinuation<Void, Error>] = [:]

    func upload(fileURL: URL, to url: URL, contentType: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let task = session.uploadTask(with: request, fromFile: fileURL)
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { waiters[task.taskIdentifier] = continuation }
            task.resume()
        }
    }
}

extension BackgroundUploadTransport: URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let continuation = lock.withLock { waiters.removeValue(forKey: task.taskIdentifier) }
        if let error {
            continuation?.resume(throwing: error)
            return
        }
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) {
            continuation?.resume()
        } else {
            continuation?.resume(throwing: URLError(.badServerResponse))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = completionHandler
        completionHandler = nil
        handler?()
    }
}
```
`ImeTime/App/ImeTimeApp.swift` 在 `WindowGroup` 的內容加上：
```swift
                .backgroundTask(.urlSession("com.zenwang.imetime.upload")) {
                    await MainActor.run { }
                }
```
（背景 session 完成時系統會喚醒 App；佇列的續傳由下一次 `drain()` 處理。）

- [ ] **Step 6: 驗證**

```bash
make build && make test-app
```
Expected：兩者 exit 0；App 測試多 7 個。模擬器沒有相機，相機畫面只會顯示黑底與錯誤訊息，這是預期行為——實機驗收在 Task 11。

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(camera): add the landscape capture screen and submit flow"
```

---

### Task 10: 端對端整合測試（本機 stack）

**Files:**
- Create: `ImeTimeTests/Integration/ClipPipelineIntegrationTests.swift`
- Modify: `ImeTimeTests/Integration/LocalSupabase.swift`

**背景：** P1 的整合測試證明了 rooms 的客戶端與後端一致。這裡要證明的是這條鏈：插入 clips 列 → trigger 產生 log_date 與 key → Edge Function 簽出 PUT URL → 真的 PUT 上去 → 簽出 GET URL → 取回同樣的位元組。這是 P2a 唯一能在沒有實機的情況下驗證整條路徑的方式。

**Interfaces:**
- Consumes: Task 3 的 clips、Task 4 的 Edge Function、Task 5 的 `SupabaseClipRepository`、Task 6 的 `SupabaseSignedURLClient`
- Produces: `LocalSupabase.signUpUserInRoom(displayName:)` 回傳已建立房間並在其中的使用者及其 repositories

- [ ] **Step 1: 擴充測試支援**

`ImeTimeTests/Integration/LocalSupabase.swift` 加入：
```swift
    /// 建立使用者、profile，再建一個房間，回傳這一組完整的依賴。
    static func signUpUserInRoom(
        displayName: String
    ) async throws -> (client: SupabaseClient, userID: UUID, room: Room,
                       clips: SupabaseClipRepository, signedURLs: SupabaseSignedURLClient) {
        let (client, userID, _, rooms) = try await signUpUserWithProfile(displayName: displayName)
        let room = try await rooms.createRoom(name: try RoomName("整合測試"), timeZoneID: "Asia/Taipei")
        let clips = SupabaseClipRepository(
            client: client,
            currentUserID: { [client] in try? await client.auth.session.user.id }
        )
        return (client, userID, room, clips, SupabaseSignedURLClient(client: client))
    }
```

- [ ] **Step 2: 寫整合測試**

`ImeTimeTests/Integration/ClipPipelineIntegrationTests.swift`：
```swift
import Foundation
import ImeTimeCore
import Testing
@testable import ImeTime

@Suite(.enabled(if: LocalSupabase.isEnabled), .serialized)
struct ClipPipelineIntegrationTests {
    /// 2026-09-03 14:37 台北 = 06:37 UTC
    private var recordedAt: Date {
        get throws { try #require(ISO8601DateFormatter().date(from: "2026-09-03T06:37:00Z")) }
    }

    @Test func serverDerivesTheDaySlotAndObjectKeys() async throws {
        let user = try await LocalSupabase.signUpUserInRoom(displayName: "拍攝者")
        let caption = try ClipCaption(text: "午餐", emoji: "🌮")
        let clip = try await user.clips.createClip(roomID: user.room.id,
                                                   recordedAt: try recordedAt,
                                                   durationMs: 2000,
                                                   caption: caption)

        // trigger 的結果必須和 Swift 端的 LogSlot 一致
        let expected = try #require(LogSlot.slot(for: try recordedAt, timeZoneID: user.room.timezone))
        #expect(clip.slot == expected)
        #expect(clip.status == .uploading)
        #expect(clip.caption == "午餐")
        #expect(clip.emoji == "🌮")

        let prefix = "\(user.room.id.uuidString.lowercased())/\(expected.logDate)/"
            + "\(user.userID.uuidString.lowercased())/\(clip.id.uuidString.lowercased())"
        #expect(clip.videoKey == "\(prefix).mov")
        #expect(clip.posterKey == "\(prefix).jpg")
    }

    @Test func aSecondClipInTheSameHourIsRejected() async throws {
        let user = try await LocalSupabase.signUpUserInRoom(displayName: "拍攝者")
        _ = try await user.clips.createClip(roomID: user.room.id, recordedAt: try recordedAt,
                                           durationMs: 2000, caption: .empty)
        await #expect(throws: (any Error).self) {
            _ = try await user.clips.createClip(roomID: user.room.id,
                                                recordedAt: try recordedAt.addingTimeInterval(600),
                                                durationMs: 2000, caption: .empty)
        }
    }

    @Test func uploadedBytesComeBackThroughASignedDownloadURL() async throws {
        let user = try await LocalSupabase.signUpUserInRoom(displayName: "拍攝者")
        let clip = try await user.clips.createClip(roomID: user.room.id, recordedAt: try recordedAt,
                                                   durationMs: 2000, caption: .empty)

        let payload = Data("pretend this is an hevc clip".utf8)
        let uploadURL = try await user.signedURLs.signedURL(clipID: clip.id, kind: .video, action: .upload)
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue("video/quicktime", forHTTPHeaderField: "Content-Type")
        let (_, putResponse) = try await URLSession.shared.upload(for: request, from: payload)
        #expect((putResponse as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } == true)

        let downloadURL = try await user.signedURLs.signedURL(clipID: clip.id, kind: .video, action: .download)
        let (data, getResponse) = try await URLSession.shared.data(from: downloadURL)
        #expect((getResponse as? HTTPURLResponse)?.statusCode == 200)
        #expect(data == payload)
    }

    @Test func anotherMemberCannotGetAnUploadURLForSomeoneElsesClip() async throws {
        let owner = try await LocalSupabase.signUpUserInRoom(displayName: "拍攝者")
        let guest = try await LocalSupabase.signUpUserWithProfile(displayName: "客人")
        let code = try #require(InviteCode(exact: owner.room.inviteCode))
        _ = try await guest.rooms.joinRoom(code: code)

        let clip = try await owner.clips.createClip(roomID: owner.room.id, recordedAt: try recordedAt,
                                                    durationMs: 2000, caption: .empty)
        let guestSignedURLs = SupabaseSignedURLClient(client: guest.client)

        // 同房間成員讀得到這一列，但不是擁有者，所以不能拿上傳連結
        await #expect(throws: SignedURLError.rejected("not_owner")) {
            _ = try await guestSignedURLs.signedURL(clipID: clip.id, kind: .video, action: .upload)
        }
        // 下載連結則是可以的
        _ = try await guestSignedURLs.signedURL(clipID: clip.id, kind: .video, action: .download)
    }

    @Test func aStrangerCannotGetAnyURL() async throws {
        let owner = try await LocalSupabase.signUpUserInRoom(displayName: "拍攝者")
        let stranger = try await LocalSupabase.signUpUserWithProfile(displayName: "路人")
        let clip = try await owner.clips.createClip(roomID: owner.room.id, recordedAt: try recordedAt,
                                                    durationMs: 2000, caption: .empty)
        let strangerSignedURLs = SupabaseSignedURLClient(client: stranger.client)

        // RLS 讓房外的人根本讀不到這一列，函式回 not_found
        await #expect(throws: SignedURLError.rejected("not_found")) {
            _ = try await strangerSignedURLs.signedURL(clipID: clip.id, kind: .video, action: .download)
        }
    }

    @Test func markingReadyMovesTheStatus() async throws {
        let user = try await LocalSupabase.signUpUserInRoom(displayName: "拍攝者")
        let clip = try await user.clips.createClip(roomID: user.room.id, recordedAt: try recordedAt,
                                                   durationMs: 2000, caption: .empty)
        try await user.clips.markReady(clipID: clip.id)

        let sameDay = try await user.clips.clips(roomID: user.room.id, logDate: clip.logDate)
        #expect(sameDay.first { $0.id == clip.id }?.status == .ready)
    }
}
```

- [ ] **Step 3: 執行**

```bash
make test-integration
```
Expected：整合測試從 8 個增加到 14 個，`skipped = 0`，全部通過。

若 `uploadedBytesComeBackThroughASignedDownloadURL` 的 PUT 回 403 或 SignatureDoesNotMatch，代表 Edge Function 的 `CLIP_STORAGE_ENDPOINT` 從容器內連不到、或簽名的 host 與實際請求的 host 不一致（presigned URL 裡的 host 是 `kong:8000`，但測試從 Mac 發出時解析不到這個名稱）。這是真正的設定問題，**不要**改測試繞過：把實際的錯誤回應貼進報告並停下，由控制端裁定（可能的解法是讓函式簽出 `127.0.0.1:54321` 的 host，或在 `/etc/hosts` 加 kong 對應）。

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test(integration): cover the clip pipeline end to end"
```

---

### Task 11: P2a 驗收與收尾

- [ ] **Step 1: 全套測試**

```bash
make test
```
Expected：`test-core`（44）、`test-functions`（5）、`test-db`（9 個檔案）、`test-integration`（App 單元測試 + 14 個整合測試，skipped = 0）全綠。

- [ ] **Step 2: 實機驗收（專案擁有者）**

模擬器沒有相機，以下只能在實機做。實作者把這份清單原樣抄進報告並全部標記「owner manual verification pending」，**不要嘗試執行**：

- [ ] iPhone 與 Mac 同一個 Wi-Fi、`supabase start` 執行中，用 Xcode Run 到實機
- [ ] 進入一個房間 → 按「拍 2 秒」→ 第一次會要求相機與麥克風權限，允許
- [ ] 手機直握時看得到畫面（輸出仍是橫式）；轉橫後預覽填滿畫面
- [ ] 按快門 → 約 2 秒後自動停止 → 進入預覽，影片循環播放
- [ ] 輸入字幕與 emoji → 送出 → 相機關閉回到房間頁
- [ ] Supabase Studio（http://127.0.0.1:54323）的 clips 表出現一列，`log_date` / `hour_slot` 正確，`status` 先是 `uploading` 後變 `ready`
- [ ] Storage 的 clips bucket 出現 `.mov` 與 `.jpg` 兩個物件，路徑全小寫
- [ ] 同一個小時再拍一次 → 送出時出現「這個小時已經有一支片段了」
- [ ] 開飛航模式再拍一支 → 送出後 App 不當機；關掉飛航模式並重開 App → 片段最終變成 `ready`
- [ ] 錄影中途接電話或切到背景 → 回到 App 不會卡在錄影狀態

- [ ] **Step 3: 標記完成**

```bash
git tag p2a-done
git log --oneline | head -15
```

---

## 自我檢查（撰寫者已執行）

- **Spec 覆蓋**：§2 規則 2、3（Task 2 的 LogSlot + Task 3 的 trigger）、規則 4（Task 8 的 1920×1080 HEVC 與 Task 3 的 check）、規則 5（Task 9 的取消丟棄）、規則 6（Task 5 的 ClipCaption）、規則 7 的儲存部分（字幕存欄位不燒進影片）；§5 clips 與 §5.1 trigger（Task 3）；§5.2 clips 政策（Task 3）；§5.3 物件儲存與簽名 URL（Task 4，開發指向本機 S3、正式指向 R2）；§6.3 錄製與上傳全部 5 個步驟（Tasks 7、8、9）；§7 的 Camera / ClipUploader / SignedURLClient / Recorder（Tasks 6–9）；§8 的 sign-clip-url（Task 4）；§11 的純邏輯、Repository、後端、整合四層（Tasks 2、3、4、5、6、7、10）。
  - **不在本計劃**（屬 P2b）：時間線格狀顯示、播放器池、長按有聲播放、詳情卡、日期切換、`MediaCache`、Realtime 同步。§6.4、§6.5 與 §14 畫面 7、9、10 因此沒有對應任務。
  - **不在本計劃**（屬 P3 以後）：`notify` 推播、每日 Vlog、反應與聊天室、`purge-deleted`。
- **占位符**：無 TBD/TODO。Task 7 的 `BackgroundUploadTransport` 是刻意的兩階段實作（Task 7 先給可運作的前景版本讓專案編得起來，Task 9 換成背景版本），兩處都寫出完整程式碼。
- **型別一致**：`LogSlot(logDate:hourSlot:)` 在 Task 2 定義、Task 5 的 `Clip.slot` 與 Task 10 使用；`ClipCaption.empty` 與 `init(text:emoji:)` 在 Task 5 定義、Tasks 9、10 使用；`ClipRepository` 四個方法在 protocol、Supabase 實作、Fake、Tasks 9、10 一致；`ClipUploading` 兩個方法在 Task 7 定義、Task 9 的 `FakeUploader` 與 view model 一致；`SignedURLKind` / `SignedURLAction` / `SignedURLError.rejected` 在 Task 6 定義、Task 10 斷言使用；`RecordedClip` 在 Task 8 定義、Task 9 的 `Phase.reviewing` 攜帶。
- **前置條件**：Task 4 的整合驗證與 Task 10 都需要 edge runtime 能在本機跑起來；Task 4 Step 5 有明確的檢查與替代方案。
