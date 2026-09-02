# ImeTime 設計規格（Design Spec）

- 日期：2026-09-02
- 狀態：草稿，待專案擁有者審閱
- 專案代號：ImeTime（暫定名，取自專案目錄；正式名稱另議）
- 平台：iOS（iPhone），透過 TestFlight 發給朋友使用
- 下游使用者：Claude Design（UI 設計，見 §14）、Claude Code（實作，見 §15 與後續 implementation plan）

---

## 1. 概述與目標

### 1.1 一句話

一個給「一群固定朋友」用的生活紀錄 app：每小時收到同一則隨機時間的推播，各自拍一段 **2 秒** 的即時影片，所有人都能看到彼此在每個小時的片段，並可把任何一天合成一支 Vlog。所有影片 **以雲端為單一事實來源**，手機只是快取。

### 1.2 靈感與差異化

靈感來源為韓國 New Chat Inc. 的 [setlog - friends camera](https://apps.apple.com/tw/app/setlog-friends-camera/id6587576438)。研究整理的 Setlog 核心機制：

| 面向 | Setlog 現況 | ImeTime 決策 |
|---|---|---|
| 房間 | 2–12 人「Log」，邀請碼加入 | 相同：邀請碼加入，上限 12 人（常數，可調） |
| 節奏 | 每小時一次、全員同時、隨機時間的推播 | 相同：每個「活躍小時」一次隨機分鐘的推播 |
| 錄製 | 2 秒、即時、不可從相簿上傳、無濾鏡 | 相同 |
| 一天邊界 | 凌晨 04:00 重置 | 相同：以房間時區的 04:00 為日界 |
| 儲存 | 影片實際存在每個人的手機；24 小時後未手動存檔即消失；常見「收不到影片 / 傳送失敗」抱怨 | **雲端為主**：所有片段永久保存在雲端，任何一天、任何時間都能回看與匯出；新成員也看得到歷史 |
| 每日 Vlog | 04:00 後自動串接（群組為分割畫面）；匯出無聲 | 任何一天皆可隨時合成；v1 為時間順序串接、含聲音、可靜音；分割畫面列為 v2 |
| 字幕 | 錄製時加簡短文字/emoji，燒進影片；中文字型過大 | 字幕以 metadata 儲存，播放時由 App 渲染（CJK 字型正確）；匯出時才燒入 |
| 刪除 | 誤刪整天無警告 | 軟刪除 + 確認對話框；30 天後才真正清除 |
| 即時照片「Zip」 | 2.3 版新增 | 不在 v1 範圍 |
| 聊天回覆 | 片段下方可聊天 | v1 只有 emoji 反應；聊天列為 v2 |

### 1.3 成功標準

1. 朋友從收到推播到送出片段，**5 秒內**完成（開相機 → 拍 2 秒 → 送出）。
2. 片段送出後，其他成員在 **10 秒內** 於時間線看到（Realtime）。
3. 任何成員可回看房間 **任何一天** 的所有片段，不受裝置、重新安裝或加入時間影響。
4. 網路不穩時錄製不會失敗：先存本機，背景重試上傳，UI 顯示上傳狀態。
5. 一群 10 人朋友每天使用的月費在 **NT$1,000 以下**（見 §4.4 成本模型）。

### 1.4 非目標（v1 不做）

- Android、iPad、Web。
- 公開探索、追蹤、演算法動態、按讚數等任何「觸及」功能。
- 聊天/留言、即時照片（Zip）、分割畫面 Vlog、濾鏡、音樂、Widget、Live Activity。
- 從相簿上傳、超過 2 秒的影片、重拍後保留多版本。
- App Store 公開上架（僅 TestFlight）。

---

## 2. 核心產品規則（精確定義）

這些是實作與測試的依據，任何模糊處以此為準。

1. **房間（Room）**：名稱、6 字元邀請碼（去除易混淆字元 0/O/1/I）、時區（建立者裝置時區）、活躍時段（預設 08:00–24:00，房間層級可調）、成員上限 12。
2. **日界（Log Day）**：`log_date = (recorded_at 轉房間時區 − 4 小時).date`。04:00 前錄的片段屬於前一天。
3. **小時格（Hour Slot）**：`hour_slot = recorded_at 轉房間時區的小時（0–23）`。每人每房間每天每小時格 **最多一支** 有效片段。
4. **推播提示（Prompt）**：房間每個活躍小時內，在一個 **確定性隨機分鐘** 發送一次推播給所有成員：`minute = hash(room_id, log_date, hour) mod 60`。同房間所有人同一時刻收到；不同房間時間不同；伺服器與客戶端皆可重算，但 App **不預先顯示** 下次時間（保留驚喜）。
5. **錄製**：固定 2.0 秒、自動停止；前/後鏡頭皆可；直式 9:16；1080p HEVC 含音訊；無濾鏡、無相簿匯入。錄製 **不限於推播後的時間窗**：活躍時段內外都可錄，但每小時格只能有一支。
6. **送出前取消**：拍完可加字幕/emoji 後送出，或取消丟棄；取消後同一小時格仍可再拍（「不可重拍」是社交約定而非技術鎖，見 §16 決策 D3）。
7. **字幕**：≤ 40 字元文字 + 選填單一 emoji，儲存為欄位，不燒入原檔。
8. **刪除**：只能刪自己的片段；需確認；軟刪除（`deleted_at`）；刪除後該小時格可再拍；30 天後由排程永久清除檔案與紀錄。
9. **反應（Reaction）**：每人對每支片段一個 emoji（可更換/取消）。
10. **每日 Vlog**：任選一天，把該房間當日所有成員的有效片段依 `recorded_at` 排序串接，疊上成員名稱、時間、字幕，匯出至相簿或分享。合成在裝置端進行，不佔伺服器運算。
11. **可見範圍**：只有房間成員能讀取該房間的任何資料與影片檔；離開房間後不再可讀（歷史片段仍屬於房間，不隨人移除，見 §16 決策 D6）。

---

## 3. 方案比較與決策

### 3.1 後端平台

| 選項 | 優點 | 缺點 | 結論 |
|---|---|---|---|
| **Supabase**（Postgres + Auth + Storage + Realtime + Edge Functions + pg_cron） | 單一供應商涵蓋 DB/認證/檔案/即時/排程；Row Level Security 直接保護資料與檔案；Swift SDK v3 原生支援 Sign in with Apple；SQL 可測試（pgTAP）；可自架 | 免費方案儲存僅 1 GB、閒置一週暫停；Pro US$25/月 | **採用** |
| Firebase（Firestore + Storage + Auth + FCM + Functions） | 成熟、推播（FCM）整合好 | 2026-02 起 Storage 強制 Blaze（綁信用卡）；NoSQL 對「房間 × 日 × 小時 × 成員」查詢較彆扭；Security Rules 難測 | 備選 |
| CloudKit | 免費、Apple 原生、無伺服器 | 無伺服器端排程（每小時隨機推播需另找地方跑）；群組共享（CKShare）模型複雜；無法之後開 Android/Web；除錯與資料檢視困難 | 不採用 |
| 自架 API（Vapor/Node + S3） | 完全掌控 | 開發與維運成本最高，對朋友專案過重 | 不採用 |

### 3.2 每小時推播的排程方式

| 選項 | 說明 | 結論 |
|---|---|---|
| **伺服器排程**：pg_cron 每分鐘觸發 Edge Function，計算每個房間本小時的 prompt 分鐘，命中則透過 APNs 推送 | 可靠、App 不開也會收到；同一機制順便發「朋友剛發了片段」通知 | **採用** |
| 客戶端確定性本機通知：每台裝置用同一個 hash 算出時間、預排 UNUserNotification（上限 64 則） | 不需伺服器；但 App 兩天不開就停、無法發「朋友發了片段」 | 不採用（hash 函數保留，供兩端一致性測試） |

### 3.3 每日 Vlog 合成位置

| 選項 | 結論 |
|---|---|
| **裝置端 AVFoundation**（AVMutableComposition + AVAssetExportSession，字幕用 Core Animation 疊層） | **採用**：零伺服器成本、CJK 字型正確、隨時可對任何一天合成；缺點是首次需下載當日所有片段（≈ 100 支 × 2 MB） |
| 伺服器 FFmpeg（Edge Function 不適合，需另開容器） | 不採用：增加一個運算服務與費用 |

### 3.4 影片儲存與成本模型

假設：10 名成員、每日 16 個活躍小時、60% 參與率 → 約 **96 支/天**；每支 2 秒 1080p HEVC 約 2 MB（含海報圖）。

| 項目 | 每月 | 每年 |
|---|---|---|
| 新增儲存 | ≈ 5.8 GB | ≈ 70 GB |
| 下載流量（每支被其他 9 人各看一次） | ≈ 52 GB | — |

| 方案 | 費用估算 | 備註 |
|---|---|---|
| Supabase Free | US$0 | 1 GB 儲存約 5 天用完，只適合開發期 |
| **Supabase Pro** | US$25/月 | 含 100 GB 儲存、250 GB 流量；約 17 個月後才需加購（US$0.021/GB） |
| Supabase Pro + Cloudflare R2 放影片 | US$25 + ≈ US$1/月 | R2 免流量費、US$0.015/GB；需 Edge Function 簽發 presigned URL |
| Firebase Blaze | 依用量 | 亞洲出口流量 US$0.12/GB，10 人約 US$6–8/月起 |

**決策**：開發期用 Supabase Free；朋友上線前升級 **Supabase Pro**（≈ NT$800/月，符合 §1.3 第 5 點）。影片一律透過 **簽名 URL** 上傳/下載（不直接用 SDK 的 upload），因此若之後儲存超過 100 GB，只要改 Edge Function 改簽 R2 的 URL 即可切換，App 不需改動。

---

## 4. 系統架構

```
┌──────────────────────────────┐        ┌────────────────────────────────────────┐
│ iOS App (SwiftUI, Swift 6)   │        │ Supabase                               │
│                              │  HTTPS │  Auth (Sign in with Apple)             │
│  Auth ──────────────────────────────▶ │  Postgres + RLS                        │
│  RoomRepository ────────────────────▶ │   profiles, rooms, room_members,       │
│  ClipRepository ────────────────────▶ │   clips, reactions, devices            │
│  Realtime (postgres_changes) ◀─────── │  Realtime                              │
│  Uploader (background URLSession) ──▶ │  Storage bucket `clips` (private)      │
│      PUT/GET 簽名 URL                 │  Edge Functions:                        │
│  Recorder (AVCapture)        │        │   sign-clip-url, hourly-prompt,        │
│  Composer (AVFoundation)     │        │   clip-posted, purge-deleted           │
│  Notifications (APNs token)  │        │  pg_cron: 每分鐘 → hourly-prompt        │
│  DiskCache (LRU 2 GB)        │        │           每日 → purge-deleted          │
└──────────────────────────────┘        │  DB Webhook: clips INSERT/UPDATE →     │
             ▲                          │             clip-posted                 │
             │ APNs 推播                 └───────────────┬────────────────────────┘
             └──────────────────────────────────────────┘  Edge Function → APNs (HTTP/2, .p8 JWT)
```

原則：

- **雲端是事實來源**，裝置端只有快取（影片檔 LRU、metadata 記憶體 + 短期磁碟快取）。
- **所有授權在 Postgres RLS**；App 只持有公開 anon key。Edge Function 用 service role 只做兩件事：簽 URL、發推播。
- **背景上傳**用 `URLSession` background configuration 對簽名 URL 做 PUT，App 被殺也會完成；完成後 App 把 `clips.status` 改為 `ready`。

---

## 5. 資料模型（Postgres）

```sql
-- 使用者檔案（1:1 auth.users）
profiles(
  id uuid primary key references auth.users on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 20),
  avatar_path text,
  created_at timestamptz not null default now()
)

rooms(
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 30),
  invite_code text not null unique,            -- 6 字元，字母表排除 0 O 1 I
  timezone text not null,                       -- IANA，如 'Asia/Taipei'
  active_start_hour int not null default 8 check (active_start_hour between 0 and 23),
  active_end_hour int not null default 24 check (active_end_hour between 1 and 24
                                                and active_end_hour > active_start_hour),
  max_members int not null default 12,
  created_by uuid not null references profiles(id),
  created_at timestamptz not null default now()
)

room_members(
  room_id uuid references rooms(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','member')),
  notifications_muted boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
)

clips(
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references rooms(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  recorded_at timestamptz not null,
  log_date date not null,                       -- trigger 依房間時區與 04:00 日界計算
  hour_slot int not null check (hour_slot between 0 and 23),  -- trigger 計算
  video_path text not null,                     -- {room_id}/{log_date}/{user_id}/{clip_id}.mov
  poster_path text not null,                    -- 同路徑 .jpg
  duration_ms int not null check (duration_ms between 1800 and 2200),
  width int not null, height int not null,
  caption text check (char_length(caption) <= 40),
  emoji text check (char_length(emoji) <= 8),
  status text not null default 'uploading' check (status in ('uploading','ready','failed')),
  deleted_at timestamptz,
  created_at timestamptz not null default now()
)
-- 每人每房間每天每小時一支有效片段
create unique index clips_one_per_slot
  on clips(room_id, user_id, log_date, hour_slot) where deleted_at is null;
create index clips_room_day on clips(room_id, log_date) where deleted_at is null;

reactions(
  clip_id uuid references clips(id) on delete cascade,
  user_id uuid references profiles(id) on delete cascade,
  emoji text not null check (char_length(emoji) <= 8),
  created_at timestamptz not null default now(),
  primary key (clip_id, user_id)
)

devices(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  apns_token text not null unique,
  environment text not null check (environment in ('sandbox','production')),
  updated_at timestamptz not null default now()
)

-- 每小時提示的去重與除錯紀錄（僅 service role 讀寫，無 App 端存取）
prompt_log(
  room_id uuid references rooms(id) on delete cascade,
  log_date date not null,
  hour_slot int not null,
  sent_at timestamptz not null default now(),
  recipients int not null,
  primary key (room_id, log_date, hour_slot)
)
```

### 5.1 觸發器與函式

- `clips_set_day_slot()` BEFORE INSERT/UPDATE：以 `rooms.timezone` 計算 `log_date`、`hour_slot`（App 不自行填，避免時區不一致）。
- `join_room(code text) returns rooms`：`security definer`，驗證碼、檢查人數上限、插入 `room_members`。房間不可被非成員以邀請碼查詢（防枚舉）；此 RPC 加簡單速率限制（每使用者每分鐘 5 次）。
- `create_room(name, timezone, active_start_hour, active_end_hour)`：產生唯一邀請碼、建立房間並把建立者設為 owner。
- `leave_room(room_id)`：離開；owner 離開時把最早加入者升為 owner；最後一人離開則房間標記待清除。
- `delete_account()`：刪除使用者資料；其片段軟刪除（房間歷史保持完整性，見 D6）。
- `prompt_minute(room_id uuid, log_date date, hour int) returns int`：`('x' || substr(md5(room_id::text || log_date::text || hour::text), 1, 8))::bit(32)::int` 取絕對值 mod 60。Swift 端有相同實作與共用測試向量。

### 5.2 RLS 政策摘要

| 表 | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| profiles | 與自己同房間的成員 + 自己 | 自己 | 自己 | 否（走 delete_account） |
| rooms | 成員 | 否（走 create_room） | owner（名稱、活躍時段） | 否 |
| room_members | 同房間成員 | 否（走 join_room） | 自己的 `notifications_muted` | 自己（離開）或 owner 踢人 |
| clips | 同房間成員，且 `deleted_at is null` 或為本人 | 自己且為該房間成員 | 本人（status、caption、deleted_at） | 否（軟刪除） |
| reactions | 同房間成員 | 自己且為該房間成員 | 自己 | 自己 |
| devices | 自己 | 自己 | 自己 | 自己 |

### 5.3 Storage

- Bucket `clips`（private）。路徑 `{room_id}/{log_date}/{user_id}/{clip_id}.mov` 與 `.jpg`。
- 不對 App 開放 storage 的直接 RLS 讀寫；一律透過 Edge Function `sign-clip-url` 簽發短效（上傳 10 分鐘、下載 1 小時）URL，函式內以 service role 驗證呼叫者是該房間成員、且路徑中的 `user_id` 等於本人（上傳時）。這樣日後切換到 R2 只改此函式。
- Bucket `avatars`（public，讀取公開、寫入僅本人路徑）。

---

## 6. 關鍵流程

### 6.1 首次進入

Sign in with Apple → Supabase `signInWithIdToken(.apple)` → 若無 `profiles` 列，進入「設定名稱與頭像」 → 請求通知權限（說明用途）→ 首頁。

### 6.2 建立 / 加入房間

- 建立：輸入名稱 → `create_room` → 顯示邀請碼與「分享」（系統分享表，文字含碼與 TestFlight 連結）。
- 加入：輸入 6 碼 → `join_room` → 進入房間；錯誤：碼無效、房間已滿、已是成員。

### 6.3 每小時提示

1. pg_cron 每分鐘呼叫 `hourly-prompt`。
2. 函式讀取所有房間，對每個房間計算「房間時區的現在」是否在活躍時段、且 `prompt_minute(room, log_date, hour) == 現在分鐘`。
3. 命中的房間，對所有未靜音成員的 devices 發 APNs：標題房間名、內文「現在 14:37，拍 2 秒吧 📹」、`thread-id = room_id`、payload 含 `room_id`、`hour_slot`、`log_date`，深連結直接開該房間相機。
4. 已於該小時格發過片段的成員不推。
5. 冪等：以 `(room_id, log_date, hour_slot)` 記錄到 `prompt_log` 表（僅供去重與除錯），避免 cron 重疊重送。

### 6.4 錄製與上傳（關鍵路徑，目標 5 秒）

1. 點推播或時間線上的「拍攝」→ 直接進相機，預覽即刻可用（相機 session 於 App 啟動後預熱）。
2. 按下快門 → 2.0 秒環形倒數，自動停止。`AVCaptureMovieFileOutput`，`maxRecordedDuration = 2.0s`，HEVC，1080×1920。
3. 立即進入循環預覽 + 字幕輸入列（可跳過）→「送出」。
4. 送出：
   a. 產生海報圖（`AVAssetImageGenerator` 於 0.5 秒）。
   b. 本機把影片與海報搬到 `Application Support/pending/{clip_id}/`。
   c. 插入 `clips` 列（status `uploading`）— 若此時無網路，先寫入本機待送佈隊列（SwiftData `PendingClip`），UI 立刻顯示「上傳中」。
   d. 呼叫 `sign-clip-url` 取得 PUT URL（影片 + 海報），以 background `URLSession` 上傳。
   e. 兩者完成 → 更新 `status = ready` → Realtime 廣播給成員 → DB webhook 觸發 `clip-posted` 推播其他成員（「小明發了新片段」，同房間合併 thread）。
   f. 失敗：指數退避重試（最多 24 小時）；超過則 `failed`，UI 提供「重試 / 刪除」。
5. 若 App 被殺，background URLSession 完成後由系統喚醒 App 收尾（步驟 e）。

### 6.5 時間線同步

進入房間 → 拉取 `log_date = 今天` 的 clips + 成員 → 訂閱 Realtime `postgres_changes`（`clips` where `room_id = X`、`reactions`）→ 有變更即更新對應小時格。切換日期時拉取該日；海報圖先顯示，影片檔懶載入並存入 LRU 快取（上限 2 GB，可在設定清除）。

### 6.6 每日 Vlog 匯出

選日期 → 下載該日所有有效片段（顯示進度）→ `AVMutableComposition` 依 `recorded_at` 串接 → `AVVideoCompositionCoreAnimationTool` 疊上「時間 · 名稱 · 字幕」（系統字型，CJK 正確）→ `AVAssetExportSession`（HEVC 1080p）→ 存至相簿（`PHPhotoLibrary`）或分享。選項：靜音、只有我的片段。

### 6.7 刪除

長按或在播放器點「刪除」→ 確認對話框（明示只刪這一支）→ `deleted_at = now()`。`purge-deleted` 每日清除 30 天前的檔案與列。

---

## 7. iOS App 架構

- **語言與工具**：Swift 6（strict concurrency）、SwiftUI、Xcode 26.x、最低 **iOS 18.0**（涵蓋 iPhone XS/XR 等 iOS 26 已放棄的機型）。
- **依賴**：`supabase-swift` v3（Auth、PostgREST、Realtime、Functions；Storage 僅用於頭像）。不引入其他第三方套件。
- **結構**（單一 Xcode 專案 + 一個本機 SPM 套件 `ImeTimeCore` 放純邏輯，方便在 macOS 上跑單元測試而不需模擬器）：

```
ImeTime/
├── App/                    # 入口、DI 容器、深連結路由、生命週期
├── Features/
│   ├── Onboarding/         # Sign in with Apple、建立檔案、通知權限
│   ├── Rooms/              # 房間列表、建立、加入、設定、成員
│   ├── Timeline/           # 房間某一天的小時 × 成員格狀時間線、日期切換
│   ├── Camera/             # 2 秒錄製、字幕、送出
│   ├── Player/             # 全螢幕循環播放、左右切換成員、反應、刪除
│   ├── DailyVlog/          # 合成預覽與匯出
│   └── Settings/           # 個人檔案、快取、登出、刪除帳號
├── Services/               # 以 protocol 定義、可注入假實作
│   ├── AuthService
│   ├── RoomRepository / ClipRepository / ReactionRepository
│   ├── ClipUploader        # 待送佈隊列 + background URLSession
│   ├── SignedURLClient     # 呼叫 sign-clip-url
│   ├── MediaCache          # LRU 磁碟快取
│   ├── Recorder            # AVCapture 封裝
│   ├── VlogComposer        # AVFoundation 合成
│   ├── RealtimeSync
│   └── PushRegistration    # APNs token → devices 表
└── Packages/ImeTimeCore/   # 純邏輯：LogDay 計算、PromptMinute、InviteCode、UploadStateMachine、Models
```

- **狀態管理**：`@Observable` view model per feature；Repository 回傳 `AsyncStream` 供 Realtime 更新。
- **本機持久化**：僅待送佈隊列（`PendingClip`）使用 SwiftData；其餘 metadata 為記憶體快取 + 短期磁碟快取，影片檔走 `MediaCache`。離線完整瀏覽列為 v2。
- **不可變資料**：模型皆為 `struct`，更新以回傳新值方式進行（符合使用者的 coding-style 規則）。
- **相機注意事項**：iOS 模擬器無相機，錄製流程只能在實機測試；`Recorder` protocol 提供假實作回傳固定測試影片以便 UI 開發。

---

## 8. 後端（Supabase 專案結構）

```
supabase/
├── migrations/             # SQL：schema、trigger、RPC、RLS、索引
├── functions/
│   ├── sign-clip-url/      # 驗證成員 → 簽發 PUT/GET URL
│   ├── hourly-prompt/      # pg_cron 每分鐘；計算命中房間 → APNs
│   ├── clip-posted/        # DB webhook：clips 變 ready → 通知其他成員
│   └── purge-deleted/      # 每日：清除 deleted_at > 30 天的檔案與列
├── tests/                  # pgTAP：RLS 政策、trigger、RPC 行為
└── seed.sql                # 本機開發假資料
```

- APNs：Edge Function 以 `.p8` 金鑰簽 JWT，直接對 `api.push.apple.com`（HTTP/2）發送；金鑰存 Supabase Secrets。sandbox/production 依 `devices.environment` 選 host。
- 本機開發用 `supabase start`（Docker），CI 前先在本機跑 pgTAP。

---

## 9. 通知

| 類型 | 觸發 | 內容 | 可關閉 |
|---|---|---|---|
| 每小時提示 | hourly-prompt | 「現在 HH:MM，拍 2 秒吧 📹」 | 房間層級 `notifications_muted` |
| 朋友發了片段 | clip-posted | 「{name} 在 {房間} 發了新片段」 | 同上 |
| 上傳失敗 | 本機 | 「有一支片段上傳失敗，點此重試」 | 否 |

- 使用 `thread-id = room_id` 讓通知中心依房間分組；`interruption-level = time-sensitive` 僅用於每小時提示（需在 entitlements 申請）。
- 首次要求權限前先顯示一頁說明「為什麼需要通知」，被拒絕時房間頁顯示引導至設定。

---

## 10. 錯誤處理與離線

- **錄製**：相機權限被拒 → 引導設定頁；錄製中來電/中斷 → 丟棄並提示重拍。
- **上傳**：詳見 §6.4 步驟 f；待送佈隊列持久化，App 重啟後續傳；同一小時格若伺服器已有有效片段（`unique index` 衝突）→ 視為重複，刪本機待送項。
- **簽名 URL 過期**：重簽一次再重試。
- **讀取**：離線時顯示快取中的海報與已下載影片，未快取者顯示「離線」佔位；恢復後自動重拉。
- **Realtime 斷線**：重連後以 `updated_at > 上次同步時間` 補拉差異。
- **所有錯誤**在 UI 有人話訊息；技術細節寫入 `os.Logger`（不上傳第三方）。

---

## 11. 安全與隱私

- App 內只有 Supabase URL 與 anon key（設計上為公開值）；所有資料存取受 RLS 保護，並以 pgTAP 測試「非成員讀不到、不能寫他人資料」。
- 影片 bucket 私有，只經短效簽名 URL 存取；URL 不落 log。
- 邀請碼查詢只經 `join_room` RPC，且有速率限制與人數上限。
- 提供「刪除帳號」（TestFlight 雖非強制，但為公開上架預留）。
- 隱私權政策一頁（Markdown 放 repo，TestFlight 測試資訊連結到 GitHub Pages 或 Notion）。
- 不蒐集分析資料、不接第三方 SDK。

---

## 12. 測試策略

| 層 | 工具 | 重點 |
|---|---|---|
| 純邏輯（ImeTimeCore） | Swift Testing，macOS 目標 | 日界/小時格計算（含 04:00 邊界、跨時區、DST）、`promptMinute` 與 SQL 版共用測試向量、邀請碼產生與驗證、上傳狀態機、Vlog 片段排序 |
| Repository / Service | Swift Testing + 假 Supabase client（protocol） | 錯誤映射、Realtime 事件套用、快取淘汰 |
| 後端 | pgTAP（`supabase test db`） | RLS 每一條政策的正反案例、trigger 計算、RPC 邊界（滿員、重複加入、離開時 owner 轉移） |
| Edge Functions | Deno test | prompt 命中邏輯（注入假時間）、APNs payload 組裝（不真的送） |
| UI | XCUITest 少量 | 登入 → 建房 → 進時間線 smoke；相機流程於實機手動測試清單 |
| 端對端 | 手動，兩台實機 + TestFlight | 推播同時到達、送出後 10 秒內對方可見、殺 App 後背景上傳完成 |

覆蓋率目標：`ImeTimeCore` 與 SQL 政策 ≥ 80%；UI 層不計入。

---

## 13. 實作階段（供 writing-plans 展開）

| 階段 | 交付 | 驗收 |
|---|---|---|
| P0 基礎 | Xcode 專案、ImeTimeCore 套件、Supabase 專案與 migrations、Sign in with Apple、profiles | 能登入、建立檔案；pgTAP 綠燈 |
| P1 房間 | create/join/leave RPC、房間列表、邀請碼分享、成員頁、RLS | 兩個帳號可互相加入同一房間 |
| P2 錄製與時間線 | Recorder、字幕、sign-clip-url、背景上傳、clips 表、時間線格狀顯示、Realtime、播放器、磁碟快取 | 實機拍 2 秒 → 另一台 10 秒內看到 |
| P3 推播 | devices 註冊、hourly-prompt、clip-posted、深連結進相機、靜音 | 兩台同時收到同一分鐘的提示 |
| P4 每日 Vlog | VlogComposer、匯出至相簿、靜音/只看我 | 任選過去一天匯出成功且字幕正確 |
| P5 反應與收尾 | reactions、刪除流程、purge-deleted、設定頁、刪除帳號、隱私頁、App icon、TestFlight 上架、Pro 方案升級 | 朋友透過 TestFlight 安裝並完成一天使用 |

每階段結束跑 code review 與該階段測試；P2 完成即可先發內部 TestFlight 給 1–2 位朋友試用。

---

## 14. UI 畫面清單（給 Claude Design 的設計簡報）

設計原則：**速度優先**（推播 → 送出 5 秒內）、**沒有數字壓力**（無按讚數、無觀看數、無連續紀錄）、**內容即介面**（時間線由朋友的 2 秒循環影片組成）、**直式**。Setlog 使用者曾抗議「散落式」新版排版、偏好「依小時堆疊」— 時間線以小時為主軸較穩妥。

| # | 畫面 | 內容與狀態 |
|---|---|---|
| 1 | 歡迎 / 登入 | 一句話價值主張、Sign in with Apple 按鈕、隱私連結 |
| 2 | 建立個人檔案 | 顯示名稱（≤ 20 字）、頭像（拍照或相簿；頭像是唯一允許相簿的地方） |
| 3 | 通知說明 | 為何需要通知、允許按鈕、稍後再說 |
| 4 | 首頁 / 房間列表 | 房間卡片（名稱、成員頭像、今日已發片段數）、「建立」「用邀請碼加入」；空狀態：邀請第一位朋友 |
| 5 | 建立房間 | 名稱、活躍時段（預設 08–24）、時區顯示 → 成功頁顯示大字邀請碼 + 分享 |
| 6 | 加入房間 | 6 格輸入、錯誤狀態（無效/已滿/已加入） |
| 7 | **房間時間線（核心）** | 頂部：房間名、日期（今天/往前滑）、成員頭像列；主體：依小時堆疊，每列 = 小時標籤 + 該小時各成員的循環播放縮圖（靜音）、未發的成員顯示灰頭像；目前小時列高亮並有「拍 2 秒」大按鈕（本人未發時）；狀態：上傳中（進度環）、上傳失敗（重試）、離線佔位、整天空白 |
| 8 | 相機 | 全螢幕預覽、翻轉鏡頭、快門；錄製中 2 秒環形倒數且不可取消；錄後循環預覽 + 字幕輸入 + emoji 選擇 + 「送出」「取消」 |
| 9 | 播放器 | 全螢幕循環、上方成員名與時間、下方字幕與 emoji、反應列（點一下換自己的 emoji）、左右滑切同小時其他成員、下滑關閉、本人片段有「刪除」 |
| 10 | 每日 Vlog | 日期選擇、下載進度、預覽播放、選項（靜音、只有我）、「存到相簿」「分享」 |
| 11 | 房間設定 | 邀請碼與分享、成員列表（owner 可移除）、活躍時段、通知靜音、離開房間 |
| 12 | 設定 | 個人檔案、快取大小與清除、隱私政策、登出、刪除帳號 |
| 13 | 推播樣式 | 每小時提示、朋友發了片段（含海報圖附件） |

深連結：`imetime://room/{id}/camera`（推播）、`imetime://room/{id}/day/{date}`。

---

## 15. 交付物與後續

1. 本 spec 審閱通過後，以 `superpowers:writing-plans` 產出 `docs/superpowers/plans/` 的實作計劃。範圍較大，計劃將依 §13 每個階段各一份，先寫 P0 與 P1。
2. Claude Design 以 §14 為輸入產出畫面設計；設計輸出的元件命名請對應 §7 的 Feature 名稱，方便 Claude Code 對照。
3. 首次 TestFlight 需要：Apple Developer Program、App ID 開啟 Push Notifications 與 Sign in with Apple、APNs `.p8` 金鑰、Supabase 專案（Free → Pro）。

---

## 16. 待專案擁有者確認的決策（已採預設值寫入本 spec）

| # | 決策 | 本 spec 的預設 | 替代方案 |
|---|---|---|---|
| D1 | 後端 | Supabase（上線後 Pro US$25/月） | Firebase Blaze；Supabase + R2 |
| D2 | 每小時提示是否「限時窗」 | 不限：整小時內都可錄，推播只是同步的提醒 | Setlog 早期做法：推播後 N 分鐘內才能錄 |
| D3 | 送出前可否取消（等同重拍） | 可以取消丟棄 | 嚴格模式：拍了就送，無取消 |
| D4 | 片段方向 | 直式 9:16 | 橫式 16:9（Setlog 早期建議） |
| D5 | 活躍時段預設 | 08:00–24:00（16 次提示/天） | 全天 24 次；或 09–23 |
| D6 | 成員離開/刪帳號後其歷史片段 | 留在房間（軟刪除僅限本人主動刪） | 隨人移除 |
| D7 | 錄音 | 錄音，匯出可靜音 | 完全無聲（同 Setlog） |
| D8 | v1 互動 | 只有 emoji 反應 | 加上文字留言 |
| D9 | App 名稱 | ImeTime（暫定） | 另議 |

---

## 17. v2 待辦（不在本 spec 範圍）

聊天留言、即時照片（Zip）、分割畫面 Vlog、鎖定畫面 Widget（Locket 式）、提示倒數 Live Activity、Universal Link 邀請、成員各自時區顯示、影片改存 Cloudflare R2、Android。

---

## 18. 參考資料

- Setlog App Store（TW）：https://apps.apple.com/tw/app/setlog-friends-camera/id6587576438
- Setlog 玩法全攻略（jyes）：https://www.jyes.com.tw/news.php?act=view&id=14783
- Marie Claire TW 教學：https://www.marieclaire.com.tw/lifestyle/news/93040
- Korea JoongAng Daily 報導：https://www.koreajoongangdaily.com/korea/social-media-app-setlog-gives-young-koreans-a-real-time-unvarnished-glimpse-at-their-friends-lives/12525462
- SetlogHub：Zip 說明 https://setloghub.com/en/learn/what-is-setlog-zip ；與替代品比較 https://setloghub.com/en/learn/setlog-vs-alternatives
- Supabase Swift SDK：https://github.com/supabase/supabase-swift
- Supabase 定價（2026）：https://uibakery.io/blog/supabase-pricing
- Firebase Storage 需 Blaze（2026-02 起）：https://unanswered.io/guide/is-firebase-free-pricing-free-tier
- Cloudflare R2 定價：https://www.bucketmate.app/blogs/cloudflare-r2-pricing-2026
- iOS 26 支援機型：https://en.wikipedia.org/wiki/IOS_26
