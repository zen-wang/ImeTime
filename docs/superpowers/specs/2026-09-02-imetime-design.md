# ImeTime 設計規格（Design Spec）

- 日期：2026-09-02（第 2 版，已納入專案擁有者 9 項決策）
- 狀態：**已確認（2026-09-02）**，進入 writing-plans
- 產品名稱：**ImeTime**
- 平台：iOS（iPhone），透過 TestFlight 發給朋友使用
- 下游使用者：Claude Design（UI 設計，見 §14）、Claude Code（實作，見 §13 與後續 implementation plans）

---

## 1. 概述與目標

### 1.1 一句話

一個給「一群固定朋友」用的生活紀錄 app：一天 24 小時、每小時一格，各自在任何想拍的時候拍一段 **2 秒** 的橫式即時影片，所有人都能看到彼此在每個小時的片段，可在房間聊天室留言與回應，並可把任何一天合成一支 Vlog。所有影片 **以雲端為單一事實來源**，手機只是快取。

### 1.2 靈感與差異化

靈感來源為韓國 New Chat Inc. 的 [setlog - friends camera](https://apps.apple.com/tw/app/setlog-friends-camera/id6587576438)。研究整理的 Setlog 核心機制與 ImeTime 的取捨：

| 面向 | Setlog 現況 | ImeTime 決策 |
|---|---|---|
| 房間 | 2–12 人「Log」，邀請碼加入 | 相同：邀請碼加入，上限 12 人（常數，可調） |
| 節奏 | 每小時一次、全員同時、隨機時間的提醒推播 | **不發提醒推播**。每小時一格、整小時內隨時可拍；推播只在有人發片段、留言或回應時發出 |
| 錄製 | 2 秒、即時、不可從相簿上傳、無濾鏡 | 相同；固定 **橫式 16:9** |
| 一天邊界 | 凌晨 04:00 重置 | 相同：以房間時區的 04:00 為日界 |
| 儲存 | 影片實際存在每個人的手機；24 小時後未手動存檔即消失；常見「收不到影片 / 傳送失敗」抱怨 | **雲端為主**：所有片段永久保存，任何一天、任何時間都能回看與匯出；新成員也看得到歷史 |
| 播放 | 時間線直接播放 | 時間線縮圖靜音循環；**長按（Haptic Touch）才全螢幕播放含聲音** |
| 每日 Vlog | 04:00 後自動串接（群組為分割畫面）；匯出無聲 | 任何一天皆可隨時合成；v1 為時間順序串接、含聲音、可靜音；分割畫面列為 v2 |
| 字幕 | 錄製時加簡短文字/emoji，燒進影片；中文字型過大 | 字幕以 metadata 儲存，播放時由 App 渲染（CJK 字型正確）；匯出時才燒入 |
| 互動 | 片段下方聊天 | 房間聊天室（可引用片段回覆）+ 片段 emoji 反應 |
| 刪除 | 誤刪整天無警告 | 軟刪除 + 確認對話框；30 天後才真正清除 |
| 即時照片「Zip」 | 2.3 版新增 | 不在 v1 範圍 |

### 1.3 成功標準

1. 從開啟相機到送出片段 **5 秒內** 完成（開相機 → 拍 2 秒 → 送出）。
2. 片段送出後，其他成員在 **10 秒內** 於時間線看到（Realtime）。
3. 任何成員可回看房間 **任何一天** 的所有片段，不受裝置、重新安裝或加入時間影響。
4. 網路不穩時錄製不會失敗：先存本機，背景重試上傳，UI 顯示上傳狀態。
5. 8 名以內朋友、每週約 35 支的用量下，雲端月費為 **NT$0**（僅 Apple Developer Program 年費；見 §3.2 成本模型）。

### 1.4 非目標（v1 不做）

- Android、iPad、Web。
- 公開探索、追蹤、演算法動態、按讚數等任何「觸及」功能。
- 每小時提醒推播、即時照片（Zip）、分割畫面 Vlog、濾鏡、音樂、Widget、Live Activity。
- 從相簿上傳、超過 2 秒的影片、直式錄影。
- App Store 公開上架（僅 TestFlight）。

---

## 2. 核心產品規則（精確定義）

這些是實作與測試的依據，任何模糊處以此為準。

1. **房間（Room）**：名稱、6 字元邀請碼（去除易混淆字元 0/O/1/I）、時區（建立者裝置時區，用於日界）、成員上限 12。
2. **日界（Log Day）**：`log_date = (recorded_at 轉房間時區 − 4 小時).date`。04:00 前錄的片段屬於前一天。
3. **小時格（Hour Slot）**：`hour_slot = recorded_at 轉房間時區的小時（0–23）`。全天 24 格皆可用。每人每房間每天每小時格 **最多一支** 有效片段。
4. **錄製**：固定 2.0 秒、自動停止；前/後鏡頭皆可；**橫式 1920×1080（16:9）**；HEVC 含音訊；無濾鏡、無相簿匯入。相機畫面鎖定橫向，手機直握時顯示「轉橫」提示。
5. **送出前取消**：拍完可加字幕/emoji 後送出，或取消丟棄；取消後同一小時格仍可再拍。
6. **字幕**：≤ 40 字元文字 + 選填單一 emoji，儲存為欄位，不燒入原檔。
7. **播放**：時間線縮圖以靜音循環播放；**長按任一片段** → 全螢幕播放並輸出聲音，放開即返回；**點一下** → 顯示詳情（字幕、反應列、「回覆」進聊天室並引用該片段）。
8. **刪除**：只能刪自己的片段或訊息；需確認；軟刪除（`deleted_at`）；刪除後該小時格可再拍；30 天後由排程永久清除檔案與紀錄。
9. **反應（Reaction）**：每人對每支片段一個 emoji（可更換/取消）。
10. **聊天室（Chat）**：每個房間一個聊天室；訊息 ≤ 500 字元；可引用一支片段（回覆某人的影片）。
11. **通知**：**沒有提醒推播**。只有三種事件推播：(a) 同房間有人發了片段；(b) 聊天室有新訊息；(c) 有人對你的片段做出反應。每房間可靜音 (a)(b)；(c) 只發給片段擁有者。
12. **每日 Vlog**：任選一天，把該房間當日所有成員的有效片段依 `recorded_at` 排序串接為 1920×1080 影片，疊上成員名稱、時間、字幕，匯出至相簿或分享。可選靜音、只有我的片段。合成在裝置端進行。
13. **可見範圍**：只有房間成員能讀取該房間的任何資料與影片檔。成員離開或刪除帳號後，其歷史片段與訊息 **留在房間**；離開者不再可讀。

---

## 3. 方案比較與決策

### 3.1 後端平台

| 選項 | 優點 | 缺點 | 結論 |
|---|---|---|---|
| **Supabase Free**（Postgres + Auth + Realtime + Edge Functions + pg_cron + Webhooks） | 一個服務涵蓋 DB/認證/即時/函式/排程；RLS 直接保護資料；Swift SDK（2.x）原生支援 Sign in with Apple；SQL 可測試（pgTAP）；免費且不需信用卡 | 500 MB DB、1 GB 檔案、5 GB 出口流量（因此影片不放這裡）；無備份；7 天無 API 請求會暫停 | **採用**：只放 metadata、認證、即時同步；影片另放物件儲存 |
| Firebase | 成熟 | 2026-02 起 Storage 強制 Blaze 綁卡；NoSQL 對「房間 × 日 × 小時 × 成員」查詢彆扭；Rules 難測 | 不採用 |
| CloudKit | 免費、Apple 原生 | 群組共享（CKShare）模型複雜；除錯困難；無法之後擴到其他平台 | 不採用 |
| 全 AWS（Cognito + DynamoDB + Lambda + S3 + SNS） | 完全掌控 | 開發與維運成本最高，且不比 Supabase Free + 物件儲存便宜 | 不採用 |

免費方案風險與對策：

- **無備份** → GitHub Actions 每週 `supabase db dump` 上傳至物件儲存的 `backups/` 前綴（免費）。
- **7 天暫停** → 朋友每天使用即有 API 請求；同一個 GitHub Actions 每週 ping 一次健康檢查 RPC 作保險。
- **500 MB DB** → 每年不到 1 萬筆 clips + 訊息 + 反應，遠低於上限。

### 3.2 影片物件儲存與成本模型

實際規模（專案擁有者 2026-09-02 提供）：**最多 8 名成員、每週約 35 支**；每支 2 秒 1080p HEVC 約 2 MB（含海報圖）。

| 項目 | 每月 | 每年 |
|---|---|---|
| 新增儲存 | ≈ 0.3 GB | ≈ 3.6 GB |
| 下載流量（每支被其他 7 人各看一次） | ≈ 2.1 GB | — |
| Supabase DB 列數（clips + messages + reactions） | — | < 1 萬筆 |

| 方案 | 免費額度 | 超額單價 | 月費估算 | 備註 |
|---|---|---|---|---|
| **Cloudflare R2** | 10 GB 儲存永久免費；**出口流量永遠免費** | US$0.015/GB-月 | **US$0，約 2.8 年後才超過 10 GB** | 啟用需在帳戶綁卡，免費範圍內不扣款；S3 相容 API |
| AWS S3 | 5 GB 永久免費；全 AWS 每月前 100 GB 出口免費 | 儲存約 US$0.025/GB-月（東京）；出口超過 100 GB 後約 US$0.114/GB | US$0，約 1.4 年後開始每月數美分 | 免費額度較小 |
| Supabase Storage（Pro） | 100 GB / 250 GB 出口 | 含在 US$25/月 | US$25 | 需付費方案，此規模下不划算 |

在這個規模下，Supabase Free 的 500 MB DB、5 GB 出口、50 萬次 Edge Function 呼叫都綽綽有餘；整套雲端月費為 **US$0**。

**決策**：影片放 **Cloudflare R2**。R2 儲存單價比 S3 低、免費額度較大、且無出口流量懸崖。R2 與 S3 使用同一套 S3 API 與 SigV4 簽名，程式碼完全相同；若日後想改 AWS S3，只需更換 Edge Function 的 endpoint 與金鑰。App 端一律透過 Edge Function 簽發的短效 presigned URL 上傳與下載，不知道也不在乎後面是哪家。

### 3.3 每日 Vlog 合成位置

| 選項 | 結論 |
|---|---|
| **裝置端 AVFoundation**（AVMutableComposition + AVAssetExportSession，字幕用 Core Animation 疊層） | **採用**：零伺服器成本、CJK 字型正確、隨時可對任何一天合成；缺點是首次需下載當日所有片段（≈ 100 支 × 2 MB） |
| 伺服器 FFmpeg | 不採用：需要一個運算服務，與免費方案目標相悖 |

### 3.4 通知策略

專案擁有者決定 **不做每小時提醒推播**，只在事件發生時通知。為避免 96 支/天造成轟炸：

- 「有人發了片段」使用 `apns-collapse-id = room_id`：同房間的多則通知在通知中心合併為一則並更新內文（「小明、小華 發了新片段」）。此規模（每週約 35 支）下推播量本來就低，合併主要是為了整潔。
- 「新訊息」使用 `thread-id = room_id` 分組。
- 「有人回應你的片段」使用 `apns-collapse-id = clip_id`，只發給片段擁有者。
- 每房間可靜音；個人「安靜時段」列為 v2。

---

## 4. 系統架構

```
┌──────────────────────────────┐        ┌────────────────────────────────────────┐
│ iOS App (SwiftUI, Swift 6)   │        │ Supabase (Free)                        │
│                              │  HTTPS │  Auth (Sign in with Apple)             │
│  Auth ──────────────────────────────▶ │  Postgres + RLS                        │
│  Room/Clip/Message/Reaction ────────▶ │   profiles, rooms, room_members,       │
│    Repositories              │        │   clips, messages, reactions, devices  │
│  Realtime (postgres_changes) ◀─────── │  Realtime                              │
│  SignedURLClient ───────────────────▶ │  Edge Functions:                        │
│  Uploader (background URLSession)    │   sign-clip-url  (R2 presigned URL)     │
│      PUT/GET presigned URL ─────┐    │   notify         (DB webhook → APNs)    │
│  Recorder (AVCapture, 橫式)      │    │   purge-deleted  (pg_cron 每日)         │
│  Composer (AVFoundation)         │    │  Storage bucket `avatars` (public)     │
│  Notifications (APNs token)      │    └───────────────┬────────────────────────┘
│  DiskCache (LRU 2 GB)            │                    │ APNs (HTTP/2, .p8 JWT)
└──────────────────────────────────┘                    ▼
             ▲                    │    ┌────────────────────────────────────────┐
             │ APNs 推播           └──▶ │ Cloudflare R2 bucket `imetime-clips`   │
             └──────────────────────── │  {room}/{date}/{user}/{clip}.mov/.jpg  │
                                       │  backups/  (每週 db dump)               │
                                       └────────────────────────────────────────┘
```

原則：

- **雲端是事實來源**，裝置端只有快取（影片檔 LRU、metadata 記憶體 + 短期磁碟快取）。
- **所有授權在 Postgres RLS**；App 只持有公開 anon key。Edge Function 用 service role 只做：簽 URL、驗證物件存在、發推播、清除。
- **背景上傳**用 `URLSession` background configuration 對 presigned URL 做 PUT，App 被殺也會完成；完成後 App 把 `clips.status` 改為 `ready`，`notify` 函式在推播前以 HEAD 驗證 R2 物件存在。

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
  timezone text not null,                       -- IANA，如 'Asia/Taipei'，僅用於 04:00 日界
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
  video_key text not null,                      -- R2 key：{room_id}/{log_date}/{user_id}/{clip_id}.mov
  poster_key text not null,                     -- 同前綴 .jpg
  duration_ms int not null check (duration_ms between 1800 and 2200),
  width int not null check (width = 1920), height int not null check (height = 1080),
  caption text check (char_length(caption) <= 40),
  emoji text check (char_length(emoji) <= 8),
  status text not null default 'uploading' check (status in ('uploading','ready','failed')),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
)
-- 每人每房間每天每小時一支有效片段
create unique index clips_one_per_slot
  on clips(room_id, user_id, log_date, hour_slot) where deleted_at is null;
create index clips_room_day on clips(room_id, log_date) where deleted_at is null;

messages(
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references rooms(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 500),
  clip_id uuid references clips(id) on delete set null,   -- 引用/回覆某支片段，可為 null
  deleted_at timestamptz,
  created_at timestamptz not null default now()
)
create index messages_room_created on messages(room_id, created_at desc);

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
```

### 5.1 觸發器與函式

- `clips_set_day_slot()` BEFORE INSERT/UPDATE：以 `rooms.timezone` 計算 `log_date`、`hour_slot`（App 不自行填，避免時區不一致）。
- `set_updated_at()` 通用 trigger。
- `create_room(name, timezone)`：產生唯一邀請碼、建立房間並把建立者設為 owner。
- `join_room(code text) returns rooms`：`security definer`，驗證碼、檢查人數上限、插入 `room_members`。房間不可被非成員以邀請碼查詢（防枚舉）；每使用者每分鐘最多 5 次。
- `leave_room(room_id)`：離開；owner 離開時把最早加入者升為 owner；最後一人離開則房間標記待清除（30 天後連同 R2 物件清除）。
- `delete_account()`：刪除 auth 使用者與 profile；其 clips 與 messages 的 `user_id` 指向保留的「已離開成員」佔位資料（display_name「已離開的成員」），房間歷史保持完整（規則 13）。
- `health_check()`：回傳 `now()`，供每週 ping。

### 5.2 RLS 政策摘要

| 表 | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| profiles | 與自己同房間的成員 + 自己 | 自己 | 自己 | 否（走 delete_account） |
| rooms | 成員 | 否（走 create_room） | owner（名稱） | 否 |
| room_members | 同房間成員 | 否（走 join_room） | 自己的 `notifications_muted` | 自己（離開）或 owner 踢人 |
| clips | 同房間成員，且 `deleted_at is null` 或為本人 | 自己且為該房間成員 | 本人（status、caption、emoji、deleted_at） | 否（軟刪除） |
| messages | 同房間成員，且 `deleted_at is null` | 自己且為該房間成員；`clip_id` 若非 null 必須屬於同房間 | 本人（deleted_at） | 否 |
| reactions | 同房間成員 | 自己且為該房間成員 | 自己 | 自己 |
| devices | 自己 | 自己 | 自己 | 自己 |

### 5.3 物件儲存（Cloudflare R2）

- Bucket `imetime-clips`（private，不開公開存取、不設自訂網域）。Key：`{room_id}/{log_date}/{user_id}/{clip_id}.mov` 與 `.jpg`。
- App 不持有 R2 金鑰。Edge Function `sign-clip-url` 以 service role 驗證：呼叫者是該房間成員；上傳時 key 中的 `user_id` 等於本人且對應 `clips` 列存在且屬於本人。簽發 SigV4 presigned URL：PUT 有效 10 分鐘、GET 有效 1 小時。
- 前綴 `backups/` 放每週 DB dump（由 GitHub Actions 以獨立的寫入專用 token 上傳）。
- Supabase Storage 只有 bucket `avatars`（public 讀、本人路徑寫），頭像 ≤ 200 KB。

---

## 6. 關鍵流程

### 6.1 首次進入

Sign in with Apple → Supabase `signInWithIdToken(.apple)` → 若無 `profiles` 列，進入「設定名稱與頭像」 → 通知說明頁（說明只會在朋友發片段/留言/回應時通知）→ 請求通知權限 → 首頁。

### 6.2 建立 / 加入房間

- 建立：輸入名稱 → `create_room` → 顯示邀請碼與「分享」（系統分享表，文字含碼與 TestFlight 連結）。
- 加入：輸入 6 碼 → `join_room` → 進入房間；錯誤：碼無效、房間已滿、已是成員。

### 6.3 錄製與上傳（關鍵路徑，目標 5 秒）

1. 在時間線點「拍 2 秒」→ 進相機，介面鎖定橫向；若手機直握，顯示轉橫提示（快門仍可按，畫面依感測器方向旋轉後輸出 1920×1080）。相機 session 於進入房間後預熱。
2. 按下快門 → 2.0 秒環形倒數，自動停止。`AVCaptureMovieFileOutput`，`maxRecordedDuration = 2.0s`，HEVC，1920×1080，含音訊。
3. 立即進入循環預覽 + 字幕輸入列（可跳過）→「送出」或「取消」。
4. 送出：
   a. 產生海報圖（`AVAssetImageGenerator` 於 0.5 秒，16:9 JPEG）。
   b. 本機把影片與海報搬到 `Application Support/pending/{clip_id}/`。
   c. 插入 `clips` 列（status `uploading`）— 若無網路，先寫入本機待送佈隊列（SwiftData `PendingClip`），UI 立刻顯示「上傳中」。
   d. 呼叫 `sign-clip-url` 取得 PUT URL（影片 + 海報），以 background `URLSession` 上傳。
   e. 兩者完成 → 更新 `status = ready` → Realtime 廣播給成員 → DB webhook 觸發 `notify`（HEAD 驗證物件存在後推播其他成員）。
   f. 失敗：指數退避重試（最多 24 小時）；超過則 `failed`，UI 提供「重試 / 刪除」。
5. 若 App 被殺，background URLSession 完成後由系統喚醒 App 收尾（步驟 e）。

### 6.4 時間線同步

進入房間 → 拉取 `log_date = 今天` 的 clips、reactions 與成員 → 訂閱 Realtime `postgres_changes`（`clips`、`reactions`、`messages` where `room_id = X`）→ 有變更即更新對應小時格或聊天室未讀數。切換日期時拉取該日；海報圖先顯示，影片檔懶載入並存入 LRU 快取（上限 2 GB，可在設定清除）。

時間線只顯示 **有片段的小時** 與 **目前小時**（含「拍 2 秒」按鈕），避免 24 列空白。

### 6.5 播放互動

- 縮圖：`AVPlayer` 靜音循環，同時最多 6 個在播（其餘顯示海報），滑出畫面即釋放。
- **長按**縮圖（`UILongPressGestureRecognizer`，0.3 秒）→ 全螢幕橫式播放並取消靜音（`AVAudioSession` category `.playback`），放開手指 → 停止並返回。至少播完一輪 2 秒再接受放開。
- **點一下**縮圖 → 底部詳情卡：成員名、時間、字幕、反應列（點 emoji 設定/更換/取消自己的反應）、「回覆」按鈕（進聊天室並引用此片段）、本人片段的「刪除」。

### 6.6 聊天室

房間內一個聊天室；訊息依時間排列；可引用片段（顯示海報縮圖，點擊跳到該片段詳情）。Realtime 即時更新；自己的訊息可刪除（軟刪除）。未讀數以「最後讀取時間」存本機。

### 6.7 通知（Edge Function `notify`）

DB webhook 觸發條件與收件人：

| 事件 | 觸發 | 收件人 | APNs 設定 |
|---|---|---|---|
| 片段就緒 | `clips` UPDATE，status 變為 `ready` | 同房間其他未靜音成員 | `collapse-id = room_id`、`thread-id = room_id`、內文「{name} 發了新片段」、附海報圖（Notification Service Extension 下載 GET 簽名 URL） |
| 新訊息 | `messages` INSERT | 同房間其他未靜音成員；若 `clip_id` 屬於某人，該人內文改為「{name} 回覆了你的片段：{body}」 | `thread-id = room_id` |
| 新反應 | `reactions` INSERT/UPDATE | 片段擁有者（非本人時） | `collapse-id = clip_id`、內文「{name} 對你的片段回應了 {emoji}」 |

深連結：`imetime://room/{id}/day/{date}?clip={clip_id}`、`imetime://room/{id}/chat`。

### 6.8 每日 Vlog 匯出

選日期 → 下載該日所有有效片段（顯示進度）→ `AVMutableComposition` 依 `recorded_at` 串接 → `AVVideoCompositionCoreAnimationTool` 疊上「時間 · 名稱 · 字幕」（系統字型，CJK 正確）→ `AVAssetExportSession`（HEVC 1920×1080）→ 存至相簿（`PHPhotoLibrary`）或分享。選項：靜音、只有我的片段。

### 6.9 刪除與清除

- 片段/訊息：確認對話框（明示只刪這一則）→ `deleted_at = now()`。
- `purge-deleted` 每日 04:30（pg_cron → pg_net → Edge Function）：刪除 `deleted_at` 超過 30 天的 R2 物件與列；清除無成員超過 30 天的房間。

---

## 7. iOS App 架構

- **語言與工具**：Swift 6（strict concurrency）、SwiftUI、Xcode 26.x、最低 **iOS 18.0**（涵蓋 iPhone XS/XR 等 iOS 26 已放棄的機型）。
- **依賴**：`supabase-swift` 2.x（Auth、PostgREST、Realtime、Functions；Storage 僅用於頭像）。R2 上傳/下載用系統 `URLSession`。不引入其他第三方套件。
- **方向**：App 整體直式；只有相機畫面與長按全螢幕播放為橫式。
- **結構**（單一 Xcode 專案 + 一個本機 SPM 套件 `ImeTimeCore` 放純邏輯，方便在 macOS 上跑單元測試而不需模擬器）：

```
ImeTime/
├── App/                    # 入口、DI 容器、深連結路由、生命週期、Notification Service Extension target
├── Features/
│   ├── Onboarding/         # Sign in with Apple、建立檔案、通知說明與權限
│   ├── Rooms/              # 房間列表、建立、加入、設定、成員
│   ├── Timeline/           # 房間某一天的小時 × 成員 16:9 縮圖時間線、日期切換、長按播放、詳情卡
│   ├── Camera/             # 橫式 2 秒錄製、字幕、送出/取消
│   ├── Chat/               # 房間聊天室、引用片段
│   ├── DailyVlog/          # 合成預覽與匯出
│   └── Settings/           # 個人檔案、快取、登出、刪除帳號
├── Services/               # 以 protocol 定義、可注入假實作
│   ├── AuthService
│   ├── RoomRepository / ClipRepository / MessageRepository / ReactionRepository
│   ├── ClipUploader        # 待送佈隊列 + background URLSession
│   ├── SignedURLClient     # 呼叫 sign-clip-url
│   ├── MediaCache          # LRU 磁碟快取
│   ├── Recorder            # AVCapture 封裝（橫式）
│   ├── TilePlayerPool      # 縮圖播放器池（最多 6 個）
│   ├── VlogComposer        # AVFoundation 合成
│   ├── RealtimeSync
│   └── PushRegistration    # APNs token → devices 表
└── Packages/ImeTimeCore/   # 純邏輯：LogDay 計算、InviteCode、UploadStateMachine、Models、TimelineGrouping
```

- **狀態管理**：`@Observable` view model per feature；Repository 回傳 `AsyncStream` 供 Realtime 更新。
- **本機持久化**：僅待送佈隊列（`PendingClip`）與聊天室最後讀取時間使用 SwiftData；其餘 metadata 為記憶體快取 + 短期磁碟快取，影片檔走 `MediaCache`。離線完整瀏覽列為 v2。
- **不可變資料**：模型皆為 `struct`，更新以回傳新值方式進行。
- **相機注意事項**：iOS 模擬器無相機，錄製流程只能在實機測試；`Recorder` protocol 提供假實作回傳固定測試影片以便 UI 開發。

---

## 8. 後端（Supabase 專案結構）

```
supabase/
├── migrations/             # SQL：schema、trigger、RPC、RLS、索引、pg_cron 排程
├── functions/
│   ├── sign-clip-url/      # 驗證成員 → 以 aws4fetch 簽發 R2 PUT/GET presigned URL
│   ├── notify/             # DB webhook：clips ready / messages insert / reactions → HEAD 驗證 → APNs
│   └── purge-deleted/      # 每日：清除 deleted_at > 30 天的 R2 物件與列、無人房間
├── tests/                  # pgTAP：RLS 政策、trigger、RPC 行為
└── seed.sql                # 本機開發假資料
.github/workflows/
└── weekly-maintenance.yml  # 每週：supabase db dump → 上傳 R2 backups/；呼叫 health_check
```

- APNs：Edge Function 以 `.p8` 金鑰簽 JWT，直接對 `api.push.apple.com`（HTTP/2）發送；金鑰與 R2 金鑰存 Supabase Secrets。sandbox/production 依 `devices.environment` 選 host。
- 本機開發用 `supabase start`（Docker）+ R2 的獨立開發 bucket。

---

## 9. 錯誤處理與離線

- **錄製**：相機/麥克風權限被拒 → 引導設定頁；錄製中來電/中斷 → 丟棄並提示重拍。
- **上傳**：詳見 §6.3 步驟 f；待送佈隊列持久化，App 重啟後續傳；同一小時格若伺服器已有有效片段（unique index 衝突）→ 視為重複，刪本機待送項並提示。
- **簽名 URL 過期**：重簽一次再重試。
- **讀取**：離線時顯示快取中的海報與已下載影片，未快取者顯示「離線」佔位；恢復後自動重拉。
- **Realtime 斷線**：重連後以 `updated_at`/`created_at > 上次同步時間` 補拉差異。
- **所有錯誤**在 UI 有人話訊息；技術細節寫入 `os.Logger`（不上傳第三方）。

---

## 10. 安全與隱私

- App 內只有 Supabase URL 與 anon key（設計上為公開值）；所有資料存取受 RLS 保護，並以 pgTAP 測試「非成員讀不到、不能寫他人資料、訊息不能引用其他房間的片段」。
- R2 bucket 私有，只經短效 presigned URL 存取；URL 不落 log；R2 金鑰只在 Edge Function Secrets。
- 邀請碼查詢只經 `join_room` RPC，且有速率限制與人數上限。
- 提供「刪除帳號」。
- 隱私權政策一頁（Markdown 放 repo，TestFlight 測試資訊連結到 GitHub Pages）。
- 不蒐集分析資料、不接第三方 SDK。

---

## 11. 測試策略

| 層 | 工具 | 重點 |
|---|---|---|
| 純邏輯（ImeTimeCore） | Swift Testing，macOS 目標 | 日界/小時格計算（含 04:00 邊界、跨時區、DST）、邀請碼產生與驗證、上傳狀態機、時間線分組（隱藏空小時、保留目前小時）、Vlog 片段排序 |
| Repository / Service | Swift Testing + 假 Supabase client（protocol） | 錯誤映射、Realtime 事件套用、快取淘汰、播放器池上限 |
| 後端 | pgTAP（`supabase test db`） | RLS 每一條政策的正反案例、trigger 計算、RPC 邊界（滿員、重複加入、離開時 owner 轉移、delete_account 佔位） |
| Edge Functions | Deno test | 簽名 URL 授權判斷、notify 收件人計算與 payload 組裝（不真的送）、purge 篩選 |
| UI | XCUITest 少量 | 登入 → 建房 → 進時間線 smoke；相機與長按播放於實機手動測試清單 |
| 端對端 | 手動，兩台實機 + TestFlight | 送出後 10 秒內對方可見並收到推播、殺 App 後背景上傳完成、聊天室即時 |

覆蓋率目標：`ImeTimeCore` 與 SQL 政策 ≥ 80%；UI 層不計入。

---

## 12. 需要的帳戶與金鑰

| 項目 | 用途 | 費用 |
|---|---|---|
| Apple Developer Program | TestFlight、Sign in with Apple、APNs `.p8` 金鑰 | US$99/年（已有則免） |
| Supabase 專案（Free） | DB、Auth、Realtime、Edge Functions | US$0 |
| Cloudflare 帳戶 + R2 | 影片與備份 | US$0（需綁卡，10 GB 內免費） |
| GitHub repo | 原始碼、每週維護 workflow、隱私頁 | US$0 |

---

## 13. 實作階段（供 writing-plans 展開，每階段一份計劃）

| 階段 | 交付 | 驗收 |
|---|---|---|
| P0 基礎 | Xcode 專案、ImeTimeCore 套件、Supabase 專案與 migrations、Sign in with Apple、profiles、頭像 | 能登入、建立檔案；pgTAP 綠燈 |
| P1 房間 | create/join/leave RPC、房間列表、邀請碼分享、成員頁、RLS | 兩個帳號可互相加入同一房間 |
| P2 錄製與時間線 | 橫式 Recorder、字幕、sign-clip-url（R2）、背景上傳、clips 表、時間線 16:9 縮圖與播放器池、長按有聲播放、詳情卡、日期切換、磁碟快取、Realtime | 實機拍 2 秒 → 另一台 10 秒內看到；長按有聲 |
| P3 通知 | devices 註冊、notify（片段就緒）、Notification Service Extension 附海報、深連結、房間靜音 | 對方發片段後收到合併通知，點擊跳到該片段 |
| P4 聊天與反應 | messages、reactions 表與 RLS、聊天室 UI、引用片段、notify 擴充兩種事件 | 兩台互傳訊息與反應皆即時且有通知 |
| P5 每日 Vlog | VlogComposer、匯出至相簿、靜音/只看我 | 任選過去一天匯出 1080p 成功且字幕正確 |
| P6 收尾 | 刪除流程、purge-deleted、設定頁、刪除帳號、每週備份 workflow、隱私頁、App icon、TestFlight 上架 | 朋友透過 TestFlight 安裝並完成一天使用 |

每階段結束跑 code review 與該階段測試；P2 完成即可先發內部 TestFlight 給 1–2 位朋友試用。

---

## 14. UI 畫面清單（給 Claude Design 的設計簡報）

設計原則：**速度優先**（開相機 → 送出 5 秒內）、**沒有數字壓力**（無按讚數、無觀看數、無連續紀錄）、**內容即介面**（時間線由朋友的 2 秒循環影片組成）、**App 直式、影片橫式 16:9**、**長按才有聲**。Setlog 使用者曾抗議「散落式」新版排版、偏好「依小時堆疊」— 時間線以小時為主軸。

| # | 畫面 | 內容與狀態 |
|---|---|---|
| 1 | 歡迎 / 登入 | 一句話價值主張、Sign in with Apple 按鈕、隱私連結 |
| 2 | 建立個人檔案 | 顯示名稱（≤ 20 字）、頭像（拍照或相簿；頭像是唯一允許相簿的地方） |
| 3 | 通知說明 | 「只在朋友發片段、留言或回應你時通知，不會催你拍」、允許按鈕、稍後再說 |
| 4 | 首頁 / 房間列表 | 房間卡片（名稱、成員頭像、今日已發片段數、聊天未讀）、「建立」「用邀請碼加入」；空狀態：邀請第一位朋友 |
| 5 | 建立房間 | 名稱 → 成功頁顯示大字邀請碼 + 分享 |
| 6 | 加入房間 | 6 格輸入、錯誤狀態（無效/已滿/已加入） |
| 7 | **房間時間線（核心）** | 頂部：房間名、日期（今天/往前滑）、成員頭像列、聊天室入口（含未讀）；主體：依小時堆疊，只顯示有片段的小時與目前小時；每列 = 小時標籤 + 該小時各成員的 16:9 靜音循環縮圖（一列放 2 個，多的橫向捲動）+ 反應 emoji 角標；目前小時列高亮並有「拍 2 秒」大按鈕（本人未發時）；狀態：上傳中（進度環）、上傳失敗（重試）、離線佔位、整天空白 |
| 8 | 相機（橫式） | 全螢幕橫式預覽、翻轉鏡頭、快門；直握時「轉橫」提示；錄製中 2 秒環形倒數且不可取消；錄後循環預覽 + 字幕輸入 + emoji 選擇 + 「送出」「取消」 |
| 9 | 長按播放（橫式） | 長按縮圖出現：全螢幕橫式播放、有聲、上方成員名與時間、下方字幕；放開即消失 |
| 10 | 片段詳情卡 | 點縮圖從底部升起：成員名、時間、字幕與 emoji、反應列（自己的反應高亮）、「回覆」（進聊天室引用）、本人片段「刪除」 |
| 11 | 聊天室 | 訊息列表、引用片段卡（海報縮圖，點擊回到片段）、輸入列、自己訊息長按刪除 |
| 12 | 每日 Vlog | 日期選擇、下載進度、橫式預覽播放、選項（靜音、只有我）、「存到相簿」「分享」 |
| 13 | 房間設定 | 邀請碼與分享、成員列表（owner 可移除）、通知靜音、離開房間 |
| 14 | 設定 | 個人檔案、快取大小與清除、隱私政策、登出、刪除帳號 |
| 15 | 推播樣式 | 「{name} 發了新片段」（合併、附海報）、「{name}：{訊息}」、「{name} 回覆了你的片段」、「{name} 對你的片段回應了 {emoji}」 |

---

## 15. 交付物與後續

1. 本 spec 確認後，以 `superpowers:writing-plans` 依 §13 每階段各產出一份實作計劃至 `docs/superpowers/plans/`，先寫 P0 與 P1。
2. Claude Design 以 §14 為輸入產出畫面設計；元件命名對應 §7 的 Feature 名稱，方便 Claude Code 對照。
3. 開工前需備妥 §12 的帳戶與金鑰。

---

## 16. 決策紀錄（2026-09-02 由專案擁有者確認）

| # | 決策 | 結果 |
|---|---|---|
| D1 | 後端與儲存 | Supabase Free（metadata/認證/即時）+ **Cloudflare R2**（影片，S3 相容，可隨時改 AWS S3）。規模：≤ 8 人、每週約 35 支 |
| D2 | 錄製時間窗 | 整小時內都可錄，每小時格一支 |
| D3 | 送出前可否取消 | 可以取消丟棄 |
| D4 | 片段方向 | 橫式 16:9（1920×1080） |
| D5 | 時段與提醒 | 全天 24 格；**不發提醒推播**；只在有人發片段、留言、回應時通知 |
| D6 | 成員離開後其歷史片段 | 留在房間 |
| D7 | 聲音 | 錄音；匯出可靜音；只有長按才全螢幕有聲播放 |
| D8 | 互動 | emoji 反應與聊天室訊息皆納入 v1（技術上皆可行） |
| D9 | App 名稱 | ImeTime |

---

## 17. v2 待辦（不在本 spec 範圍）

可選的每小時提示（opt-in，同房間確定性同一分鐘）、個人安靜時段、即時照片（Zip）、分割畫面 Vlog、鎖定畫面 Widget（Locket 式）、Universal Link 邀請、成員各自時區顯示、離線完整瀏覽、Android。

---

## 18. 參考資料

- Setlog App Store（TW）：https://apps.apple.com/tw/app/setlog-friends-camera/id6587576438
- Setlog 玩法全攻略（jyes）：https://www.jyes.com.tw/news.php?act=view&id=14783
- Marie Claire TW 教學：https://www.marieclaire.com.tw/lifestyle/news/93040
- Korea JoongAng Daily 報導：https://www.koreajoongangdaily.com/korea/social-media-app-setlog-gives-young-koreans-a-real-time-unvarnished-glimpse-at-their-friends-lives/12525462
- SetlogHub：Zip 說明 https://setloghub.com/en/learn/what-is-setlog-zip ；與替代品比較 https://setloghub.com/en/learn/setlog-vs-alternatives
- Supabase Swift SDK：https://github.com/supabase/supabase-swift
- Supabase 免費方案限制（2026）：https://uibakery.io/blog/supabase-pricing
- Cloudflare R2 定價與綁卡需求：https://www.bucketmate.app/blogs/cloudflare-r2-pricing-2026 、https://community.cloudflare.com/t/why-using-r2-free-tier-involves-giving-card-info/945179
- AWS 免費方案 2026（抵用金制、S3 5 GB 永久免費、100 GB 出口免費）：https://infratally.com/articles/aws-free-tier-2026/
- Firebase Storage 需 Blaze（2026-02 起）：https://unanswered.io/guide/is-firebase-free-pricing-free-tier
- iOS 26 支援機型：https://en.wikipedia.org/wiki/IOS_26
