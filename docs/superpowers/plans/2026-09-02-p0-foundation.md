# P0 基礎（專案骨架、Supabase、Sign in with Apple、個人檔案）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建立可在模擬器上執行的 ImeTime iOS 專案與本機 Supabase 後端，使用者能用 Sign in with Apple 登入、建立名稱與頭像，pgTAP 與 Swift 測試全綠。

**Architecture:** 單一 Xcode 專案（由 XcodeGen 的 `project.yml` 產生）+ 本機 SPM 套件 `ImeTimeCore` 放純邏輯（可在 macOS 跑測試）。App 以 protocol 定義 `AuthService`、`ProfileRepository`，Supabase 實作與測試用假實作分離。後端為 Supabase 本機專案：SQL migrations + RLS + pgTAP。

**Tech Stack:** Swift 6（strict concurrency）、SwiftUI、Swift Testing、XcodeGen、supabase-swift 2.x、Supabase CLI（Docker）、pgTAP。

**Spec:** `docs/superpowers/specs/2026-09-02-imetime-design.md`（本計劃實作 §5 的 profiles/avatars、§6.1、§7、§8、§11 中 P0 相關部分）

## Global Constraints

- 最低部署版本 **iOS 18.0**；只支援 iPhone（`TARGETED_DEVICE_FAMILY = 1`）；App 整體 **直式**。
- Swift 語言模式 6、`SWIFT_STRICT_CONCURRENCY = complete`。
- 唯一第三方依賴：`supabase-swift` 2.x（`from: 2.0.0`，目前解析為 2.55.1；尚無 3.x 正式版）。不得新增其他套件。
- 所有模型為 `struct`，不可變；更新以回傳新值方式進行。
- 單檔 ≤ 800 行；函式 ≤ 50 行。
- UI 文案為 **繁體中文**。
- Bundle ID：`com.zenwang.imetime`（可在 `project.yml` 一處修改）。
- 秘密與環境值只放 `Config/Local.xcconfig`（已 gitignore）與 `supabase/.env`（已 gitignore）。
- 這台 Mac 的 `xcode-select` 指向 Command Line Tools，**所有 xcodebuild/xcrun 都要透過 `scripts/xcodebuild.sh` 或設定 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`**。
- 資料庫測試用 `supabase test db`（pgTAP）；RLS 測試以 `set local role authenticated; set local request.jwt.claim.sub = '<uuid>'` 模擬使用者。
- `auth.uid()::text` 是小寫 UUID；Swift 的 `UUID.uuidString` 是大寫。**任何拿 UUID 當 Storage 路徑的地方都要 `.lowercased()`。**

---

## 檔案結構（本計劃結束時）

```
ImeTime/                                  # repo 根目錄
├── project.yml                           # XcodeGen 專案定義（唯一真實來源；.xcodeproj 不進 git）
├── Makefile                              # bootstrap / generate / build / test-core / test-app / test-db
├── CLAUDE.md                             # 給 Claude Code 的專案守則與指令
├── Config/
│   ├── Base.xcconfig                     # 共用；最後 #include? Local.xcconfig
│   ├── Debug.xcconfig                    # 指向本機 Supabase
│   ├── Release.xcconfig                  # 指向正式 Supabase（值來自 Local.xcconfig）
│   └── Local.xcconfig.example            # 範本：Team ID、anon key
├── scripts/
│   ├── xcodebuild.sh                     # 設 DEVELOPER_DIR 後轉呼叫 xcodebuild
│   ├── bootstrap.sh                      # 安裝 brew 工具、產生專案、複製 Local.xcconfig
│   ├── build-app.sh / test-app.sh        # 模擬器建置 / App 單元測試
│   └── test-core.sh                      # ImeTimeCore 的 swift test
├── Packages/ImeTimeCore/
│   ├── Package.swift
│   ├── Sources/ImeTimeCore/
│   │   ├── Validation/NameValidator.swift    # 共用名稱驗證（去頭尾空白、1...max）
│   │   ├── Profile/DisplayName.swift         # 20 字上限的值型別
│   │   └── Profile/Profile.swift             # profiles 資料列模型
│   └── Tests/ImeTimeCoreTests/
│       ├── DisplayNameTests.swift
│       └── ProfileDecodingTests.swift
├── ImeTime/                              # App target 原始碼
│   ├── App/
│   │   ├── ImeTimeApp.swift              # @main；建立 AppEnvironment 與 SessionCoordinator
│   │   ├── AppConfig.swift               # 從 Info.plist 讀 Supabase URL / anon key
│   │   ├── AppEnvironment.swift          # DI 容器（live 實作）
│   │   ├── AppLinks.swift                # 外部連結常數
│   │   ├── SessionCoordinator.swift      # 根狀態機：loading / welcome / createProfile / home / failed
│   │   └── RootView.swift                # 依 SessionCoordinator.screen 切畫面
│   ├── Features/Onboarding/
│   │   ├── WelcomeView.swift             # Sign in with Apple
│   │   ├── CreateProfileView.swift
│   │   ├── CreateProfileViewModel.swift
│   │   ├── AvatarImageEncoder.swift      # 縮圖 ≤ 512px、JPEG ≤ 200 KB
│   │   └── CameraPicker.swift            # UIImagePickerController 包裝（頭像拍照）
│   ├── Features/Home/HomeView.swift      # P0 佔位：顯示名稱、頭像、登出（P1 改為房間列表）
│   ├── Services/Auth/
│   │   ├── AuthService.swift             # protocol + AuthState
│   │   ├── AuthStateMapper.swift         # Supabase 事件 → AuthState 的純函式
│   │   └── SupabaseAuthService.swift
│   ├── Services/Profile/
│   │   ├── ProfileRepository.swift       # protocol
│   │   └── SupabaseProfileRepository.swift
│   ├── Resources/Assets.xcassets/        # AppIcon、AccentColor
│   └── ImeTime.entitlements              # Sign in with Apple
├── ImeTimeTests/                         # App 單元測試（模擬器）
│   ├── Fakes/FakeAuthService.swift
│   ├── Fakes/FakeProfileRepository.swift
│   ├── AuthStateMapperTests.swift
│   ├── AvatarImageEncoderTests.swift
│   ├── SessionCoordinatorTests.swift
│   └── CreateProfileViewModelTests.swift
├── supabase/
│   ├── config.toml                       # supabase init 產生後修改 Apple provider
│   ├── .env                              # SUPABASE_AUTH_EXTERNAL_APPLE_SECRET（gitignore）
│   ├── migrations/
│   │   ├── 20260902000100_profiles.sql
│   │   └── 20260902000200_avatars_bucket.sql
│   ├── tests/
│   │   ├── profiles_rls.test.sql
│   │   └── avatars_storage.test.sql
│   └── seed.sql                          # 空檔（P1 起加入假資料）
└── docs/privacy.md                       # 隱私權政策（最小版本）
```

---

### Task 1: 工具鏈與 Xcode 專案骨架（XcodeGen）

**Files:**
- Create: `project.yml`, `Makefile`, `CLAUDE.md`, `Config/Base.xcconfig`, `Config/Debug.xcconfig`, `Config/Release.xcconfig`, `Config/Local.xcconfig.example`, `scripts/xcodebuild.sh`, `scripts/bootstrap.sh`, `scripts/build-app.sh`, `scripts/test-app.sh`, `scripts/test-core.sh`, `ImeTime/App/ImeTimeApp.swift`, `ImeTime/App/RootView.swift`, `ImeTime/ImeTime.entitlements`, `ImeTime/Resources/Assets.xcassets/Contents.json`, `ImeTime/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`, `ImeTime/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`, `ImeTimeTests/SmokeTests.swift`, `Packages/ImeTimeCore/Package.swift`, `Packages/ImeTimeCore/Sources/ImeTimeCore/ImeTimeCore.swift`, `Packages/ImeTimeCore/Tests/ImeTimeCoreTests/PackageSmokeTests.swift`, `docs/privacy.md`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `make generate` / `make build` / `make test-core` / `make test-app` 指令；`ImeTimeCore` 模組；App target `ImeTime` 與測試 target `ImeTimeTests`。

- [ ] **Step 1: 安裝工具**

```bash
brew install xcodegen deno
brew install supabase/tap/supabase
open -a Docker   # 啟動 Docker Desktop，等到選單列圖示顯示 running
```

驗證：`xcodegen --version`、`supabase --version`、`deno --version`、`docker info >/dev/null && echo docker-ok`。

- [ ] **Step 2: 寫 xcodebuild 包裝與 gitignore**

`scripts/xcodebuild.sh`：
```bash
#!/usr/bin/env bash
# 這台機器的 xcode-select 指向 CommandLineTools；用 DEVELOPER_DIR 指定 Xcode.app，不需 sudo。
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
exec xcodebuild "$@"
```

`.gitignore` 追加：
```
# Xcode / SwiftPM
ImeTime.xcodeproj/
*.xcworkspace/
.swiftpm/
Packages/*/.build/
# 環境值
Config/Local.xcconfig
supabase/.env
supabase/.temp/
supabase/.branches/
```

```bash
chmod +x scripts/xcodebuild.sh
```

- [ ] **Step 3: 寫 xcconfig**

`Config/Base.xcconfig`：
```
// 共用設定。機器專屬值放 Local.xcconfig（不進 git）。
IPHONEOS_DEPLOYMENT_TARGET = 18.0
SWIFT_VERSION = 6.0
SWIFT_STRICT_CONCURRENCY = complete
DEVELOPMENT_TEAM = $(IMETIME_TEAM_ID)
CODE_SIGN_STYLE = Automatic

#include? "Local.xcconfig"
```

`Config/Debug.xcconfig`：
```
#include "Base.xcconfig"
// xcconfig 把 // 視為註解，所以用 $() 斷開
SUPABASE_URL = http:/$()/127.0.0.1:54321
SUPABASE_ANON_KEY = $(LOCAL_SUPABASE_ANON_KEY)
```

`Config/Release.xcconfig`：
```
#include "Base.xcconfig"
SUPABASE_URL = $(PROD_SUPABASE_URL)
SUPABASE_ANON_KEY = $(PROD_SUPABASE_ANON_KEY)
```

`Config/Local.xcconfig.example`：
```
// 複製為 Local.xcconfig 後填入。此檔不進 git。
// Apple Developer Team ID（Xcode > Settings > Accounts 可查；模擬器建置可留空）
IMETIME_TEAM_ID =
// 執行 `supabase status -o env` 後把 ANON_KEY（或 PUBLISHABLE_KEY）貼到這裡
LOCAL_SUPABASE_ANON_KEY =
// 正式 Supabase 專案（P6 才需要）
PROD_SUPABASE_URL = https:/$()/YOUR-PROJECT.supabase.co
PROD_SUPABASE_ANON_KEY =
```

- [ ] **Step 4: 寫 project.yml**

```yaml
name: ImeTime
options:
  bundleIdPrefix: com.zenwang
  deploymentTarget:
    iOS: "18.0"
  xcodeVersion: "26.0"
  createIntermediateGroups: true
  generateEmptyDirectories: true

configs:
  Debug: debug
  Release: release

configFiles:
  Debug: Config/Debug.xcconfig
  Release: Config/Release.xcconfig

packages:
  ImeTimeCore:
    path: Packages/ImeTimeCore
  Supabase:
    url: https://github.com/supabase/supabase-swift.git
    from: 2.0.0

targets:
  ImeTime:
    type: application
    platform: iOS
    sources:
      - path: ImeTime
    dependencies:
      - package: ImeTimeCore
        product: ImeTimeCore
      - package: Supabase
        product: Supabase
    info:
      path: ImeTime/Info.plist
      properties:
        CFBundleDisplayName: ImeTime
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        UILaunchScreen: {}
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
        NSCameraUsageDescription: ImeTime 需要相機來拍攝 2 秒片段與頭像。
        NSMicrophoneUsageDescription: ImeTime 需要麥克風來錄製片段聲音。
        NSPhotoLibraryAddUsageDescription: ImeTime 需要權限把每日 Vlog 存到你的相簿。
        SupabaseURL: $(SUPABASE_URL)
        SupabaseAnonKey: $(SUPABASE_ANON_KEY)
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
    entitlements:
      path: ImeTime/ImeTime.entitlements
      properties:
        com.apple.developer.applesignin:
          - Default
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.zenwang.imetime
        TARGETED_DEVICE_FAMILY: "1"
        ENABLE_USER_SCRIPT_SANDBOXING: YES
    scheme:
      testTargets:
        - ImeTimeTests

  ImeTimeTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: ImeTimeTests
    dependencies:
      - target: ImeTime
      - package: ImeTimeCore
        product: ImeTimeCore
```

- [ ] **Step 5: 寫 App 入口與資源**

`ImeTime/App/ImeTimeApp.swift`（Task 9 會改寫，先讓專案能建置）：
```swift
import SwiftUI

@main
struct ImeTimeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

`ImeTime/App/RootView.swift`：
```swift
import SwiftUI

struct RootView: View {
    var body: some View {
        Text("ImeTime")
            .font(.largeTitle)
    }
}
```

`ImeTime/ImeTime.entitlements`（XcodeGen 會依 `properties` 產生內容，檔案需存在；先放空 plist）：
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

`ImeTime/Resources/Assets.xcassets/Contents.json`：
```json
{ "info" : { "author" : "xcode", "version" : 1 } }
```

`ImeTime/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`：
```json
{
  "images" : [
    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`ImeTime/Resources/Assets.xcassets/AccentColor.colorset/Contents.json`：
```json
{
  "colors" : [
    { "idiom" : "universal" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

`ImeTimeTests/SmokeTests.swift`：
```swift
import Testing
@testable import ImeTime

@Suite struct SmokeTests {
    @Test func appModuleLinks() {
        #expect(true)
    }
}
```

- [ ] **Step 6: 寫 ImeTimeCore 套件骨架**

`Packages/ImeTimeCore/Package.swift`：
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImeTimeCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ImeTimeCore", targets: ["ImeTimeCore"]),
    ],
    targets: [
        .target(name: "ImeTimeCore"),
        .testTarget(name: "ImeTimeCoreTests", dependencies: ["ImeTimeCore"]),
    ]
)
```

`Packages/ImeTimeCore/Sources/ImeTimeCore/ImeTimeCore.swift`：
```swift
/// ImeTimeCore 放與 UI、網路無關的純邏輯，可在 macOS 上直接測試。
public enum ImeTimeCore {
    public static let version = "0.1.0"
}
```

`Packages/ImeTimeCore/Tests/ImeTimeCoreTests/PackageSmokeTests.swift`：
```swift
import Testing
@testable import ImeTimeCore

@Suite struct PackageSmokeTests {
    @Test func versionIsSet() {
        #expect(ImeTimeCore.version == "0.1.0")
    }
}
```

- [ ] **Step 7: 寫 scripts 與 Makefile**

`scripts/bootstrap.sh`：
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

for tool in xcodegen supabase deno docker; do
  command -v "$tool" >/dev/null || { echo "缺少 $tool，請先執行：brew install xcodegen deno supabase/tap/supabase；Docker 請安裝 Docker Desktop"; exit 1; }
done
[ -f Config/Local.xcconfig ] || { cp Config/Local.xcconfig.example Config/Local.xcconfig; echo "已建立 Config/Local.xcconfig，請填入 LOCAL_SUPABASE_ANON_KEY"; }
xcodegen generate
echo "完成。下一步：make build"
```

`scripts/build-app.sh`：
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/xcodebuild.sh build \
  -project ImeTime.xcodeproj -scheme ImeTime \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -quiet
```

`scripts/test-app.sh`：
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/xcodebuild.sh test \
  -project ImeTime.xcodeproj -scheme ImeTime \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:ImeTimeTests \
  -quiet
```

`scripts/test-core.sh`：
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun swift test --package-path Packages/ImeTimeCore
```

`Makefile`：
```make
.PHONY: bootstrap generate build test-core test-app test-db db-reset test

bootstrap:
	scripts/bootstrap.sh

generate:
	xcodegen generate

build: generate
	scripts/build-app.sh

test-core:
	scripts/test-core.sh

test-app: generate
	scripts/test-app.sh

db-reset:
	supabase db reset

test-db:
	supabase test db

test: test-core test-db test-app
```

```bash
chmod +x scripts/*.sh
```

- [ ] **Step 8: 寫 CLAUDE.md 與 privacy.md**

`CLAUDE.md`：
```markdown
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

## 守則
- Swift 6 strict concurrency；SwiftUI；`@Observable` view model 標 `@MainActor`
- 純邏輯放 `Packages/ImeTimeCore`，先寫測試
- Service 一律 protocol + Supabase 實作 + 測試用 Fake
- 模型為 struct，不可變；不寫 `var` 欄位在模型上
- 唯一第三方套件：supabase-swift；不加其他依賴
- UUID 進 Storage 路徑前 `.lowercased()`
- DB 變更只透過 `supabase/migrations/*.sql`，每個 RLS 政策都要有 pgTAP 正反案例
- UI 文案繁體中文
```

`docs/privacy.md`：
```markdown
# ImeTime 隱私權政策

ImeTime 是提供給一小群朋友使用的私人 app，目前僅透過 TestFlight 發布。

## 我們儲存什麼
- 你用 Apple 帳號登入時 Apple 提供的使用者識別碼（我們不索取 email 與姓名）
- 你自行輸入的顯示名稱與頭像
- 你在房間裡錄製的 2 秒影片、字幕、留言與 emoji 反應，以及錄製時間

## 誰能看到
只有與你在同一個房間的成員。沒有公開頁面、沒有演算法、沒有廣告。

## 存放在哪
帳號與資料存放於 Supabase；影片檔存放於 Cloudflare R2。影片只能透過短效簽名連結存取。

## 刪除
你可以在 App 內刪除自己的片段與留言，或刪除整個帳號。刪除的檔案會在 30 天內從伺服器永久清除。

## 聯絡
專案擁有者：andysam789@gmail.com
```

- [ ] **Step 9: 產生專案並建置**

```bash
make bootstrap
make build
make test-core
make test-app
```
Expected：三個指令皆成功結束（exit 0）。`make test-core` 輸出含 `Test run with 1 test passed`；`make test-app` 輸出含 `** TEST SUCCEEDED **`。

若 `make build` 抱怨 signing：模擬器不需要 Team ID；確認 `Config/Local.xcconfig` 存在（可留空值）。

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "chore: scaffold Xcode project with XcodeGen, ImeTimeCore package, scripts"
```

---

### Task 2: 名稱驗證與 DisplayName（ImeTimeCore，TDD）

**Files:**
- Create: `Packages/ImeTimeCore/Sources/ImeTimeCore/Validation/NameValidator.swift`, `Packages/ImeTimeCore/Sources/ImeTimeCore/Profile/DisplayName.swift`
- Test: `Packages/ImeTimeCore/Tests/ImeTimeCoreTests/DisplayNameTests.swift`
- Delete: `Packages/ImeTimeCore/Sources/ImeTimeCore/ImeTimeCore.swift`, `Packages/ImeTimeCore/Tests/ImeTimeCoreTests/PackageSmokeTests.swift`

**Interfaces:**
- Produces:
  - `public enum NameValidationError: Error, Equatable, Sendable { case empty; case tooLong(max: Int) }`
  - `public enum NameValidator { static func validate(_ raw: String, maxLength: Int) throws(NameValidationError) -> String }`
  - `public struct DisplayName: Equatable, Sendable { static let maxLength = 20; let value: String; init(_ raw: String) throws(NameValidationError) }`
  - P1 的 `RoomName` 會重用 `NameValidator`。

- [ ] **Step 1: 寫失敗測試**

`Packages/ImeTimeCore/Tests/ImeTimeCoreTests/DisplayNameTests.swift`：
```swift
import Testing
@testable import ImeTimeCore

@Suite struct DisplayNameTests {
    @Test func trimsSurroundingWhitespace() throws {
        #expect(try DisplayName("  小明  ").value == "小明")
    }

    @Test func rejectsWhitespaceOnly() {
        #expect(throws: NameValidationError.empty) {
            try DisplayName("   \n")
        }
    }

    @Test func rejects21Characters() {
        #expect(throws: NameValidationError.tooLong(max: 20)) {
            try DisplayName(String(repeating: "字", count: 21))
        }
    }

    @Test func accepts20Characters() throws {
        let name = try DisplayName(String(repeating: "a", count: 20))
        #expect(name.value.count == 20)
    }

    @Test func countsGraphemeClustersNotBytes() throws {
        // 20 個 emoji（每個多 byte）仍是 20 個字
        let name = try DisplayName(String(repeating: "😀", count: 20))
        #expect(name.value.count == 20)
    }
}
```

- [ ] **Step 2: 執行確認失敗**

```bash
rm Packages/ImeTimeCore/Sources/ImeTimeCore/ImeTimeCore.swift Packages/ImeTimeCore/Tests/ImeTimeCoreTests/PackageSmokeTests.swift
make test-core
```
Expected：編譯錯誤 `cannot find 'DisplayName' in scope`。

- [ ] **Step 3: 最小實作**

`Packages/ImeTimeCore/Sources/ImeTimeCore/Validation/NameValidator.swift`：
```swift
import Foundation

public enum NameValidationError: Error, Equatable, Sendable {
    case empty
    case tooLong(max: Int)
}

/// 所有「使用者輸入的名稱」共用的驗證：去頭尾空白、不可空、字數上限（以 Character 計）。
public enum NameValidator {
    public static func validate(_ raw: String, maxLength: Int) throws(NameValidationError) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw .empty }
        if trimmed.count > maxLength { throw .tooLong(max: maxLength) }
        return trimmed
    }
}
```

`Packages/ImeTimeCore/Sources/ImeTimeCore/Profile/DisplayName.swift`：
```swift
/// 個人檔案顯示名稱，對應 profiles.display_name（1...20 字）。
public struct DisplayName: Equatable, Sendable {
    public static let maxLength = 20
    public let value: String

    public init(_ raw: String) throws(NameValidationError) {
        value = try NameValidator.validate(raw, maxLength: Self.maxLength)
    }
}
```

- [ ] **Step 4: 執行確認通過**

```bash
make test-core
```
Expected：`Test run with 5 tests passed`。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(core): add NameValidator and DisplayName value type"
```

---

### Task 3: Supabase 本機專案與 profiles 資料表（pgTAP）

**Files:**
- Create: `supabase/config.toml`（由 `supabase init` 產生後修改）, `supabase/.env`, `supabase/seed.sql`, `supabase/migrations/20260902000100_profiles.sql`, `supabase/tests/profiles_rls.test.sql`

**Interfaces:**
- Produces: `public.profiles(id, display_name, avatar_path, created_at)`，RLS：本人可 select/insert/update；anon 無權限。P1 會把 select 政策擴大為「同房間成員」。

- [ ] **Step 1: 初始化 Supabase 專案**

```bash
supabase init
```
回答提示：不產生 VS Code / IntelliJ 設定。產生 `supabase/config.toml` 與 `supabase/seed.sql`（若無 seed.sql 則手動建立空檔）。

修改 `supabase/config.toml`：
- 第一行 `project_id = "imetime"`
- 找到 `[auth.external.apple]` 區塊改成：
```toml
[auth.external.apple]
enabled = true
# 原生 Sign in with Apple：client_id 填 App 的 Bundle ID（ID token 的 aud）
client_id = "com.zenwang.imetime"
# 原生流程不用 secret，但欄位需非空
secret = "env(SUPABASE_AUTH_EXTERNAL_APPLE_SECRET)"
redirect_uri = ""
url = ""
```

`supabase/.env`：
```
SUPABASE_AUTH_EXTERNAL_APPLE_SECRET=not-used-for-native-sign-in
```

- [ ] **Step 2: 啟動本機 Supabase**

```bash
supabase start
supabase status -o env
```
Expected：輸出含 `API_URL="http://127.0.0.1:54321"` 與 `ANON_KEY="..."`（或 `PUBLISHABLE_KEY`）。把該值填到 `Config/Local.xcconfig` 的 `LOCAL_SUPABASE_ANON_KEY`。

- [ ] **Step 3: 寫失敗的 pgTAP 測試**

`supabase/tests/profiles_rls.test.sql`：
```sql
begin;
select plan(9);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'b@example.com');

-- anon 沒有 grant，直接 permission denied
set local role anon;
select throws_ok(
  $$select * from public.profiles$$,
  '42501', null, 'anon cannot read profiles');

-- A 建立、讀取、更新自己的檔案
set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select results_eq(
  $$insert into public.profiles (id, display_name)
    values ('11111111-1111-1111-1111-111111111111', '小明') returning display_name$$,
  array['小明'], 'A creates own profile');
select throws_ok(
  $$insert into public.profiles (id, display_name)
    values ('22222222-2222-2222-2222-222222222222', '冒名')$$,
  '42501', null, 'A cannot create a profile for B');
select results_eq(
  $$select display_name from public.profiles$$,
  array['小明'], 'A reads only own profile');
select results_eq(
  $$update public.profiles set display_name = '小明二號'
    where id = '11111111-1111-1111-1111-111111111111' returning display_name$$,
  array['小明二號'], 'A updates own profile');

-- B 看不到、改不到 A
set local request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select is_empty(
  $$select * from public.profiles$$,
  'B reads no profiles (no shared room yet)');
select is_empty(
  $$update public.profiles set display_name = '駭' returning id$$,
  'B updates nothing');

-- check constraints
select throws_ok(
  $$insert into public.profiles (id, display_name)
    values ('22222222-2222-2222-2222-222222222222', '')$$,
  '23514', null, 'empty display_name rejected');
select throws_ok(
  $$insert into public.profiles (id, display_name)
    values ('22222222-2222-2222-2222-222222222222', repeat('字', 21))$$,
  '23514', null, '21-char display_name rejected');

select * from finish();
rollback;
```

- [ ] **Step 4: 執行確認失敗**

```bash
make test-db
```
Expected：失敗，訊息含 `relation "public.profiles" does not exist`。

- [ ] **Step 5: 寫 migration**

`supabase/migrations/20260902000100_profiles.sql`：
```sql
-- profiles：1:1 對應 auth.users，由 App 在首次登入後建立（不用 trigger，讓使用者先填名稱）
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 20),
  avatar_path text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Supabase 預設會把 public schema 的表 grant 給 anon/authenticated；收回 anon
revoke all on public.profiles from anon;
grant select, insert, update on public.profiles to authenticated;

create policy "profiles: read own"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()));

create policy "profiles: insert own"
  on public.profiles for insert to authenticated
  with check (id = (select auth.uid()));

create policy "profiles: update own"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- 不開 delete：刪除走 P6 的 delete_account()
```

- [ ] **Step 6: 重建 DB、執行確認通過**

```bash
make db-reset
make test-db
```
Expected：`profiles_rls.test.sql .. ok` 且 `All tests successful`。

- [ ] **Step 7: Commit**

```bash
git add supabase/config.toml supabase/seed.sql supabase/migrations supabase/tests
git commit -m "feat(db): add profiles table with RLS and pgTAP tests"
```

---

### Task 4: avatars 公開 bucket 與 Storage 政策（pgTAP）

**Files:**
- Create: `supabase/migrations/20260902000200_avatars_bucket.sql`, `supabase/tests/avatars_storage.test.sql`

**Interfaces:**
- Produces: bucket `avatars`（public、≤ 200 KB、僅 image/jpeg）；物件路徑 `{user_id 小寫}/avatar.jpg`；本人可 insert/update/delete 自己資料夾；任何人可讀。

- [ ] **Step 1: 寫失敗測試**

`supabase/tests/avatars_storage.test.sql`：
```sql
begin;
select plan(4);

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'a@example.com');

-- bucket 設定（以 postgres 身分檢查，不受 RLS 影響）
select results_eq(
  $$select public, file_size_limit::int, allowed_mime_types
    from storage.buckets where id = 'avatars'$$,
  $$values (true, 204800, array['image/jpeg'])$$,
  'avatars bucket is public, 200 KB, jpeg only');

set local role authenticated;
set local request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';

select results_eq(
  $$insert into storage.objects (bucket_id, name)
    values ('avatars', '11111111-1111-1111-1111-111111111111/avatar.jpg') returning name$$,
  array['11111111-1111-1111-1111-111111111111/avatar.jpg'],
  'A uploads into own folder');

select throws_ok(
  $$insert into storage.objects (bucket_id, name)
    values ('avatars', '22222222-2222-2222-2222-222222222222/avatar.jpg')$$,
  '42501', null, 'A cannot upload into another user folder');

select results_eq(
  $$update storage.objects set metadata = '{"touched": true}'::jsonb
    where bucket_id = 'avatars' and name = '11111111-1111-1111-1111-111111111111/avatar.jpg'
    returning name$$,
  array['11111111-1111-1111-1111-111111111111/avatar.jpg'],
  'A updates (upsert) own object');

select * from finish();
rollback;
```

- [ ] **Step 2: 執行確認失敗**

```bash
make test-db
```
Expected：`avatars_storage.test.sql` 失敗（bucket 不存在、insert 被拒）。

- [ ] **Step 3: 寫 migration**

`supabase/migrations/20260902000200_avatars_bucket.sql`：
```sql
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 204800, array['image/jpeg'])
on conflict (id) do nothing;

-- 路徑第一段必須是自己的 uid（小寫）
create policy "avatars: insert own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

create policy "avatars: update own folder"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

create policy "avatars: delete own folder"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

-- public bucket 的下載不經 RLS；這條讓 SDK 的 list/select 也能讀
create policy "avatars: public read"
  on storage.objects for select to public
  using (bucket_id = 'avatars');
```

- [ ] **Step 4: 執行確認通過**

```bash
make db-reset
make test-db
```
Expected：兩個測試檔皆 `ok`。

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations supabase/tests
git commit -m "feat(db): add public avatars bucket with per-user folder policies"
```

---

### Task 5: AppConfig、AuthService 與 AuthStateMapper（TDD）

**Files:**
- Create: `ImeTime/App/AppConfig.swift`, `ImeTime/Services/Auth/AuthService.swift`, `ImeTime/Services/Auth/AuthStateMapper.swift`, `ImeTime/Services/Auth/SupabaseAuthService.swift`
- Test: `ImeTimeTests/AuthStateMapperTests.swift`
- Delete: `ImeTimeTests/SmokeTests.swift`

**Interfaces:**
- Produces:
  - `struct AppConfig: Sendable { let supabaseURL: URL; let supabaseAnonKey: String; static func load(bundle: Bundle = .main) -> AppConfig }`
  - `enum AuthState: Equatable, Sendable { case signedOut; case signedIn(userID: UUID) }`
  - `protocol AuthService: Sendable { func states() -> AsyncStream<AuthState>; func signInWithApple(identityToken: String, nonce: String) async throws; func signOut() async throws }`（`nonce` 為未雜湊的原始值；Apple 請求端放的是其 SHA-256 hex）
  - `enum AuthStateMapper { static func map(event: AuthChangeEvent, userID: UUID?) -> AuthState? }`（`nil` = 忽略此事件）
  - `final class SupabaseAuthService: AuthService`

- [ ] **Step 1: 寫失敗測試**

`ImeTimeTests/AuthStateMapperTests.swift`：
```swift
import Foundation
import Supabase
import Testing
@testable import ImeTime

@Suite struct AuthStateMapperTests {
    let uid = UUID()

    @Test func initialSessionWithoutUserIsSignedOut() {
        #expect(AuthStateMapper.map(event: .initialSession, userID: nil) == .signedOut)
    }

    @Test func initialSessionWithUserIsSignedIn() {
        #expect(AuthStateMapper.map(event: .initialSession, userID: uid) == .signedIn(userID: uid))
    }

    @Test func signedInEventIsSignedIn() {
        #expect(AuthStateMapper.map(event: .signedIn, userID: uid) == .signedIn(userID: uid))
    }

    @Test func tokenRefreshedKeepsSignedIn() {
        #expect(AuthStateMapper.map(event: .tokenRefreshed, userID: uid) == .signedIn(userID: uid))
    }

    @Test func signedOutEventIsSignedOut() {
        #expect(AuthStateMapper.map(event: .signedOut, userID: nil) == .signedOut)
    }

    @Test func userDeletedIsSignedOut() {
        #expect(AuthStateMapper.map(event: .userDeleted, userID: uid) == .signedOut)
    }

    @Test func passwordRecoveryIsIgnored() {
        #expect(AuthStateMapper.map(event: .passwordRecovery, userID: uid) == nil)
    }

    @Test func userUpdatedKeepsSignedIn() {
        #expect(AuthStateMapper.map(event: .userUpdated, userID: uid) == .signedIn(userID: uid))
    }

    @Test func signedInWithoutUserIsIgnored() {
        #expect(AuthStateMapper.map(event: .signedIn, userID: nil) == nil)
    }
}
```

- [ ] **Step 2: 執行確認失敗**

```bash
rm ImeTimeTests/SmokeTests.swift
make test-app
```
Expected：編譯錯誤 `cannot find 'AuthStateMapper' in scope`。

- [ ] **Step 3: 實作**

`ImeTime/App/AppConfig.swift`：
```swift
import Foundation

/// 從 Info.plist 讀取由 xcconfig 注入的環境值。缺值時立刻 fatalError，避免帶著錯設定跑很久才失敗。
struct AppConfig: Sendable {
    let supabaseURL: URL
    let supabaseAnonKey: String

    static func load(bundle: Bundle = .main) -> AppConfig {
        let urlString = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String ?? ""
        let key = bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String ?? ""
        guard let url = URL(string: urlString), url.host() != nil, !key.isEmpty else {
            fatalError("""
            缺少 SupabaseURL / SupabaseAnonKey。
            請複製 Config/Local.xcconfig.example 為 Config/Local.xcconfig，填入 LOCAL_SUPABASE_ANON_KEY 後重新建置。
            目前讀到 SupabaseURL="\(urlString)" SupabaseAnonKey.isEmpty=\(key.isEmpty)
            """)
        }
        return AppConfig(supabaseURL: url, supabaseAnonKey: key)
    }
}
```

`ImeTime/Services/Auth/AuthService.swift`：
```swift
import Foundation

enum AuthState: Equatable, Sendable {
    case signedOut
    case signedIn(userID: UUID)
}

/// 登入狀態來源。`states()` 先送出目前狀態，之後每次變化都送；App 存活期間不會結束。
protocol AuthService: Sendable {
    func states() -> AsyncStream<AuthState>
    /// `nonce` 是產生請求時的原始亂數；Apple 的 request.nonce 必須是它的 SHA-256 hex。
    func signInWithApple(identityToken: String, nonce: String) async throws
    func signOut() async throws
}
```

`ImeTime/Services/Auth/AuthStateMapper.swift`：
```swift
import Foundation
import Supabase

/// 把 supabase-swift 的 auth 事件轉成 App 自己的狀態。純函式，方便測試。
/// 回傳 nil 表示這個事件不影響登入狀態。
enum AuthStateMapper {
    static func map(event: AuthChangeEvent, userID: UUID?) -> AuthState? {
        switch event {
        case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
            guard let userID else {
                return event == .initialSession ? .signedOut : nil
            }
            return .signedIn(userID: userID)
        case .signedOut, .userDeleted:
            return .signedOut
        default:
            return nil
        }
    }
}
```

`ImeTime/Services/Auth/SupabaseAuthService.swift`：
```swift
import Foundation
import Supabase

final class SupabaseAuthService: AuthService {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func states() -> AsyncStream<AuthState> {
        AsyncStream { continuation in
            let task = Task {
                for await (event, session) in client.auth.authStateChanges {
                    if let state = AuthStateMapper.map(event: event, userID: session?.user.id) {
                        continuation.yield(state)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {
        try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: identityToken, nonce: nonce)
        )
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
```

若編譯器指出 `OpenIDConnectCredentials` 的參數名稱不同，以 `supabase-swift` 2.x 套件內 `Sources/Auth/Types.swift` 的定義為準（provider、idToken、accessToken、nonce 四個欄位）。

- [ ] **Step 4: 執行確認通過**

```bash
make test-app
```
Expected：`** TEST SUCCEEDED **`，9 個測試通過。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(auth): add AppConfig, AuthService protocol and Supabase implementation"
```

---

### Task 6: Profile 模型與 ProfileRepository

**Files:**
- Create: `Packages/ImeTimeCore/Sources/ImeTimeCore/Profile/Profile.swift`, `ImeTime/Services/Profile/ProfileRepository.swift`, `ImeTime/Services/Profile/SupabaseProfileRepository.swift`
- Test: `Packages/ImeTimeCore/Tests/ImeTimeCoreTests/ProfileDecodingTests.swift`

**Interfaces:**
- Produces:
  - `public struct Profile: Codable, Equatable, Sendable, Identifiable { id: UUID; displayName: String; avatarPath: String?; createdAt: Date }`（JSON 鍵 snake_case）
  - `protocol ProfileRepository: Sendable { fetchProfile(userID:) async throws -> Profile?; createProfile(userID:displayName:avatarPath:) async throws -> Profile; uploadAvatar(userID:jpegData:) async throws -> String; avatarURL(path:) -> URL? }`

- [ ] **Step 1: 寫失敗測試（模型解碼）**

`Packages/ImeTimeCore/Tests/ImeTimeCoreTests/ProfileDecodingTests.swift`：
```swift
import Foundation
import Testing
@testable import ImeTimeCore

@Suite struct ProfileDecodingTests {
    @Test func decodesSnakeCaseRow() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","display_name":"小明","avatar_path":null,"created_at":"2026-09-02T10:00:00+00:00"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let profile = try decoder.decode(Profile.self, from: Data(json.utf8))
        #expect(profile.id == UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        #expect(profile.displayName == "小明")
        #expect(profile.avatarPath == nil)
    }

    @Test func encodesSnakeCaseKeys() throws {
        let profile = Profile(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            displayName: "小明", avatarPath: "abc/avatar.jpg", createdAt: Date(timeIntervalSince1970: 0))
        let data = try JSONEncoder().encode(profile)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["display_name"] as? String == "小明")
        #expect(object["avatar_path"] as? String == "abc/avatar.jpg")
    }
}
```

- [ ] **Step 2: 執行確認失敗**

```bash
make test-core
```
Expected：`cannot find 'Profile' in scope`。

- [ ] **Step 3: 實作模型**

`Packages/ImeTimeCore/Sources/ImeTimeCore/Profile/Profile.swift`：
```swift
import Foundation

/// 對應 public.profiles 一列。
public struct Profile: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let displayName: String
    public let avatarPath: String?
    public let createdAt: Date

    public init(id: UUID, displayName: String, avatarPath: String?, createdAt: Date) {
        self.id = id
        self.displayName = displayName
        self.avatarPath = avatarPath
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarPath = "avatar_path"
        case createdAt = "created_at"
    }
}
```

- [ ] **Step 4: 執行確認通過**

```bash
make test-core
```
Expected：7 tests passed。

- [ ] **Step 5: 寫 Repository protocol 與 Supabase 實作**

`ImeTime/Services/Profile/ProfileRepository.swift`：
```swift
import Foundation
import ImeTimeCore

protocol ProfileRepository: Sendable {
    /// 找不到回 nil（首次登入尚未建立檔案）。
    func fetchProfile(userID: UUID) async throws -> Profile?
    func createProfile(userID: UUID, displayName: DisplayName, avatarPath: String?) async throws -> Profile
    /// 上傳（覆寫）頭像，回傳 storage 路徑 `{uid}/avatar.jpg`。
    func uploadAvatar(userID: UUID, jpegData: Data) async throws -> String
    func avatarURL(path: String) -> URL?
}
```

`ImeTime/Services/Profile/SupabaseProfileRepository.swift`：
```swift
import Foundation
import ImeTimeCore
import Supabase

struct SupabaseProfileRepository: ProfileRepository {
    let client: SupabaseClient

    func fetchProfile(userID: UUID) async throws -> Profile? {
        let rows: [Profile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userID.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func createProfile(userID: UUID, displayName: DisplayName, avatarPath: String?) async throws -> Profile {
        struct NewProfile: Encodable {
            let id: UUID
            let display_name: String
            let avatar_path: String?
        }
        return try await client
            .from("profiles")
            .insert(NewProfile(id: userID, display_name: displayName.value, avatar_path: avatarPath), returning: .representation)
            .single()
            .execute()
            .value
    }

    func uploadAvatar(userID: UUID, jpegData: Data) async throws -> String {
        // Storage 政策比對 auth.uid()::text（小寫），路徑必須小寫
        let path = "\(userID.uuidString.lowercased())/avatar.jpg"
        try await client.storage
            .from("avatars")
            .upload(path, data: jpegData, options: FileOptions(contentType: "image/jpeg", upsert: true))
        return path
    }

    func avatarURL(path: String) -> URL? {
        try? client.storage.from("avatars").getPublicURL(path: path)
    }
}
```

若 `upload` 的簽名編譯失敗，查 `supabase-swift` 的 `Sources/Storage/StorageFileApi.swift`：2.x 為 `upload(_ path: String, data: Data, options: FileOptions)`。

- [ ] **Step 6: 建置**

```bash
make build
```
Expected：成功。

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(profile): add Profile model and ProfileRepository with Supabase implementation"
```

---

### Task 7: AvatarImageEncoder（TDD）

**Files:**
- Create: `ImeTime/Features/Onboarding/AvatarImageEncoder.swift`
- Test: `ImeTimeTests/AvatarImageEncoderTests.swift`

**Interfaces:**
- Produces: `enum AvatarImageEncoder { static func jpegData(from image: UIImage, maxDimension: CGFloat = 512, maxBytes: Int = 200_000) -> Data? }`

- [ ] **Step 1: 寫失敗測試**

`ImeTimeTests/AvatarImageEncoderTests.swift`：
```swift
import Testing
import UIKit
@testable import ImeTime

@Suite struct AvatarImageEncoderTests {
    private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    @Test func downscalesLongestSideTo512AndStaysUnder200KB() throws {
        let data = try #require(AvatarImageEncoder.jpegData(from: solidImage(width: 2000, height: 1000)))
        #expect(data.count <= 200_000)
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size.width == 512)
        #expect(decoded.size.height == 256)
    }

    @Test func doesNotUpscaleSmallImages() throws {
        let data = try #require(AvatarImageEncoder.jpegData(from: solidImage(width: 100, height: 80)))
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size.width == 100)
        #expect(decoded.size.height == 80)
    }

    @Test func returnsNilWhenImpossibleToFitBudget() {
        // 1 byte 的預算不可能達成
        #expect(AvatarImageEncoder.jpegData(from: solidImage(width: 512, height: 512), maxBytes: 1) == nil)
    }

    /// 雜訊圖在低品質下明顯變小；預算設為「0.9 品質大小 − 1」可確定迫使迴圈至少遞減一次。
    @Test func lowersQualityUntilBudgetFits() throws {
        let image = noiseImage(side: 512)
        let atTopQuality = try #require(image.jpegData(compressionQuality: 0.9)).count
        let atBottomQuality = try #require(image.jpegData(compressionQuality: 0.3)).count
        try #require(atBottomQuality < atTopQuality)
        let budget = atTopQuality - 1
        let data = try #require(AvatarImageEncoder.jpegData(from: image, maxBytes: budget))
        #expect(data.count <= budget)
    }

    private func noiseImage(side: Int) -> UIImage {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cgImage = CGImage(
            width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        return UIImage(cgImage: cgImage)
    }
}
```

- [ ] **Step 2: 執行確認失敗**

```bash
make test-app
```
Expected：`cannot find 'AvatarImageEncoder' in scope`。

- [ ] **Step 3: 實作**

`ImeTime/Features/Onboarding/AvatarImageEncoder.swift`：
```swift
import UIKit

/// 把使用者選的圖縮到最長邊 ≤ 512、JPEG ≤ 200 KB（avatars bucket 的 file_size_limit）。
enum AvatarImageEncoder {
    static let defaultMaxDimension: CGFloat = 512
    static let defaultMaxBytes = 200_000

    static func jpegData(
        from image: UIImage,
        maxDimension: CGFloat = defaultMaxDimension,
        maxBytes: Int = defaultMaxBytes
    ) -> Data? {
        let scaled = downscale(image, maxDimension: maxDimension)
        var quality: CGFloat = 0.9
        while quality >= 0.3 {
            if let data = scaled.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
            quality -= 0.1
        }
        return nil
    }

    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let ratio = maxDimension / longest
        let target = CGSize(
            width: (image.size.width * ratio).rounded(.down),
            height: (image.size.height * ratio).rounded(.down)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
```

- [ ] **Step 4: 執行確認通過**

```bash
make test-app
```
Expected：TEST SUCCEEDED。

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(onboarding): add AvatarImageEncoder with size budget"
```

---

### Task 8: SessionCoordinator 根狀態機（TDD，含 Fakes）

**Files:**
- Create: `ImeTime/App/SessionCoordinator.swift`, `ImeTimeTests/Fakes/FakeAuthService.swift`, `ImeTimeTests/Fakes/FakeProfileRepository.swift`
- Test: `ImeTimeTests/SessionCoordinatorTests.swift`

**Interfaces:**
- Consumes: `AuthService`、`ProfileRepository`（Task 5、6）
- Produces:
  - `@MainActor @Observable final class SessionCoordinator { enum Screen: Equatable { case loading, welcome, createProfile(userID: UUID), home(Profile), failed(message: String) }; private(set) var screen: Screen; func start(); func apply(_ state: AuthState) async; func profileCreated(_ profile: Profile); func retry() async }`
  - 測試用 `actor FakeAuthService: AuthService`（`emit(_:)` 推狀態）、`actor FakeProfileRepository: ProfileRepository`（`profiles`、`createCalls`、`uploadCalls`、`errorToThrow`）。P1 會重用這兩個 Fake。

- [ ] **Step 1: 寫 Fakes**

`ImeTimeTests/Fakes/FakeAuthService.swift`：
```swift
import Foundation
@testable import ImeTime

actor FakeAuthService: AuthService {
    private let stream: AsyncStream<AuthState>
    private let continuation: AsyncStream<AuthState>.Continuation
    private(set) var signInTokens: [String] = []
    private(set) var signInNonces: [String] = []
    private(set) var signOutCount = 0

    init() {
        (stream, continuation) = AsyncStream<AuthState>.makeStream()
    }

    nonisolated func states() -> AsyncStream<AuthState> { stream }

    nonisolated func emit(_ state: AuthState) {
        continuation.yield(state)
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {
        signInTokens.append(identityToken)
        signInNonces.append(nonce)
        emit(.signedIn(userID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!))
    }

    func signOut() async throws {
        signOutCount += 1
        emit(.signedOut)
    }
}
```

`ImeTimeTests/Fakes/FakeProfileRepository.swift`：
```swift
import Foundation
import ImeTimeCore
@testable import ImeTime

actor FakeProfileRepository: ProfileRepository {
    struct CreateCall: Equatable { let userID: UUID; let displayName: String; let avatarPath: String? }

    var profiles: [UUID: Profile] = [:]
    var errorToThrow: Error?
    private(set) var createCalls: [CreateCall] = []
    private(set) var uploadCalls: [(userID: UUID, bytes: Int)] = []

    func seed(_ profile: Profile) { profiles[profile.id] = profile }
    func fail(with error: Error?) { errorToThrow = error }

    func fetchProfile(userID: UUID) async throws -> Profile? {
        if let errorToThrow { throw errorToThrow }
        return profiles[userID]
    }

    func createProfile(userID: UUID, displayName: DisplayName, avatarPath: String?) async throws -> Profile {
        if let errorToThrow { throw errorToThrow }
        createCalls.append(CreateCall(userID: userID, displayName: displayName.value, avatarPath: avatarPath))
        let profile = Profile(id: userID, displayName: displayName.value, avatarPath: avatarPath, createdAt: Date())
        profiles[userID] = profile
        return profile
    }

    func uploadAvatar(userID: UUID, jpegData: Data) async throws -> String {
        if let errorToThrow { throw errorToThrow }
        uploadCalls.append((userID: userID, bytes: jpegData.count))
        return "\(userID.uuidString.lowercased())/avatar.jpg"
    }

    nonisolated func avatarURL(path: String) -> URL? {
        URL(string: "https://example.test/avatars/\(path)")
    }
}

struct FakeError: Error, Equatable {}
```

- [ ] **Step 2: 寫失敗測試**

`ImeTimeTests/SessionCoordinatorTests.swift`：
```swift
import Foundation
import ImeTimeCore
import Testing
@testable import ImeTime

@MainActor
@Suite struct SessionCoordinatorTests {
    let uid = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    /// 固定時間戳：Profile 的 Equatable 含 createdAt，兩次 Date() 永遠不相等。
    private func makeProfile() -> Profile {
        Profile(id: uid, displayName: "小明", avatarPath: nil, createdAt: Date(timeIntervalSince1970: 1_756_800_000))
    }

    @Test func startsLoading() {
        let sut = SessionCoordinator(auth: FakeAuthService(), profiles: FakeProfileRepository())
        #expect(sut.screen == .loading)
    }

    @Test func signedOutShowsWelcome() async {
        let sut = SessionCoordinator(auth: FakeAuthService(), profiles: FakeProfileRepository())
        await sut.apply(.signedOut)
        #expect(sut.screen == .welcome)
    }

    @Test func signedInWithoutProfileShowsCreateProfile() async {
        let sut = SessionCoordinator(auth: FakeAuthService(), profiles: FakeProfileRepository())
        await sut.apply(.signedIn(userID: uid))
        #expect(sut.screen == .createProfile(userID: uid))
    }

    @Test func signedInWithProfileShowsHome() async {
        let profiles = FakeProfileRepository()
        await profiles.seed(makeProfile())
        let sut = SessionCoordinator(auth: FakeAuthService(), profiles: profiles)
        await sut.apply(.signedIn(userID: uid))
        #expect(sut.screen == .home(makeProfile()))
    }

    @Test func profileFetchFailureShowsFailedAndRetryRecovers() async {
        let profiles = FakeProfileRepository()
        await profiles.fail(with: FakeError())
        let sut = SessionCoordinator(auth: FakeAuthService(), profiles: profiles)
        await sut.apply(.signedIn(userID: uid))
        guard case .failed = sut.screen else {
            Issue.record("expected .failed, got \(sut.screen)")
            return
        }
        await profiles.seed(makeProfile())
        await profiles.fail(with: nil)
        await sut.retry()
        #expect(sut.screen == .home(makeProfile()))
    }

    @Test func profileCreatedMovesToHome() async {
        let sut = SessionCoordinator(auth: FakeAuthService(), profiles: FakeProfileRepository())
        await sut.apply(.signedIn(userID: uid))
        sut.profileCreated(makeProfile())
        #expect(sut.screen == .home(makeProfile()))
    }

    @Test func startConsumesAuthStream() async throws {
        let auth = FakeAuthService()
        let sut = SessionCoordinator(auth: auth, profiles: FakeProfileRepository())
        sut.start()
        auth.emit(.signedOut)
        try await waitUntil { sut.screen == .welcome }
        auth.emit(.signedIn(userID: uid))
        try await waitUntil { sut.screen == .createProfile(userID: uid) }
    }

    /// 最多等 2 秒，每 10ms 檢查一次
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("condition not met within 2s")
    }
}
```

- [ ] **Step 3: 執行確認失敗**

```bash
make test-app
```
Expected：`cannot find 'SessionCoordinator' in scope`。

- [ ] **Step 4: 實作**

`ImeTime/App/SessionCoordinator.swift`：
```swift
import Foundation
import ImeTimeCore
import Observation

/// 根狀態機：登入狀態 × 是否已建立個人檔案 → 目前該顯示哪個畫面。
@MainActor
@Observable
final class SessionCoordinator {
    enum Screen: Equatable {
        case loading
        case welcome
        case createProfile(userID: UUID)
        case home(Profile)
        case failed(message: String)
    }

    private(set) var screen: Screen = .loading

    private let auth: any AuthService
    private let profiles: any ProfileRepository
    private var lastState: AuthState?
    private var observation: Task<Void, Never>?

    init(auth: any AuthService, profiles: any ProfileRepository) {
        self.auth = auth
        self.profiles = profiles
    }

    /// 開始觀察登入狀態。每次迭代才短暫強引用 self，避免 Task 與 coordinator 互相持有。
    func start() {
        observation?.cancel()
        observation = Task { [weak self] in
            guard let states = self?.auth.states() else { return }
            for await state in states {
                guard let self else { return }
                await self.apply(state)
            }
        }
    }

    func apply(_ state: AuthState) async {
        lastState = state
        switch state {
        case .signedOut:
            screen = .welcome
        case .signedIn(let userID):
            await resolveProfile(for: userID)
        }
    }

    func retry() async {
        guard let lastState else { return }
        await apply(lastState)
    }

    func profileCreated(_ profile: Profile) {
        screen = .home(profile)
    }

    private func resolveProfile(for userID: UUID) async {
        do {
            if let profile = try await profiles.fetchProfile(userID: userID) {
                screen = .home(profile)
            } else {
                screen = .createProfile(userID: userID)
            }
        } catch {
            screen = .failed(message: "無法載入你的個人檔案，請檢查網路後重試。")
        }
    }
}
```

- [ ] **Step 5: 執行確認通過**

```bash
make test-app
```
Expected：TEST SUCCEEDED（含 7 個 SessionCoordinator 測試）。

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(app): add SessionCoordinator root state machine with fakes and tests"
```

---

### Task 9: WelcomeView（Sign in with Apple）、AppEnvironment、RootView 接線

**Files:**
- Create: `ImeTime/App/AppEnvironment.swift`, `ImeTime/App/AppLinks.swift`, `ImeTime/Features/Onboarding/AppleNonce.swift`, `ImeTime/Features/Onboarding/WelcomeView.swift`, `ImeTime/Features/Home/HomeView.swift`
- Modify: `ImeTime/App/ImeTimeApp.swift`, `ImeTime/App/RootView.swift`
- Test: `ImeTimeTests/AppleNonceTests.swift`

**Interfaces:**
- Consumes: `SessionCoordinator`、`AuthService`、`ProfileRepository`
- Produces:
  - `@MainActor struct AppEnvironment { let auth: any AuthService; let profiles: any ProfileRepository; static func live() -> AppEnvironment }`
  - `enum AppLinks { static let privacyPolicy: URL }`
  - `enum AppleNonce { static func random(byteCount: Int = 32) -> String; static func sha256Hex(_ input: String) -> String }`
  - `struct WelcomeView: View { init(auth: any AuthService) }` — 每次按下按鈕產生新 nonce，`request.nonce = AppleNonce.sha256Hex(raw)`，成功後以原始 `raw` 呼叫 `auth.signInWithApple(identityToken:nonce:)`
  - `struct HomeView: View { init(profile: Profile, avatarURL: URL?, onSignOut: @escaping () -> Void) }`（P0 佔位，P1 改為房間列表）
  - `RootView` 在 `.createProfile` 時會使用 Task 10 的 `CreateProfileView(userID:profiles:onCreated:)`；本任務先以文字佔位，Task 10 替換。

- [ ] **Step 1: 寫 AppEnvironment 與 AppLinks**

`ImeTime/App/AppEnvironment.swift`：
```swift
import Foundation
import Supabase

/// 依賴注入容器。live() 建立真正的 Supabase 實作；測試直接用 Fakes 建構各 view model。
@MainActor
struct AppEnvironment {
    let auth: any AuthService
    let profiles: any ProfileRepository

    static func live(config: AppConfig = .load()) -> AppEnvironment {
        let client = SupabaseClient(supabaseURL: config.supabaseURL, supabaseKey: config.supabaseAnonKey)
        return AppEnvironment(
            auth: SupabaseAuthService(client: client),
            profiles: SupabaseProfileRepository(client: client)
        )
    }
}
```

`ImeTime/App/AppLinks.swift`：
```swift
import Foundation

enum AppLinks {
    /// docs/privacy.md 推上 GitHub 後的網址；把 zen-wang 換成實際的 GitHub 帳號。
    static let privacyPolicy = URL(string: "https://github.com/zen-wang/ImeTime/blob/main/docs/privacy.md")!
}
```

- [ ] **Step 2: 寫 AppleNonce（TDD）與 WelcomeView**

`ImeTimeTests/AppleNonceTests.swift`：
```swift
import Testing
@testable import ImeTime

@Suite struct AppleNonceTests {
    @Test func sha256HexMatchesKnownVector() {
        #expect(AppleNonce.sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func randomNonceIsHexOfRequestedLength() {
        let nonce = AppleNonce.random(byteCount: 32)
        #expect(nonce.count == 64)
        #expect(nonce.allSatisfy { $0.isHexDigit })
    }

    @Test func randomNoncesDiffer() {
        #expect(AppleNonce.random() != AppleNonce.random())
    }
}
```

先執行 `make test-app` 確認失敗（`cannot find 'AppleNonce' in scope`），再寫實作：

`ImeTime/Features/Onboarding/AppleNonce.swift`：
```swift
import CryptoKit
import Foundation
import Security

/// Sign in with Apple 的 nonce：原始亂數交給 Supabase，其 SHA-256 hex 放進 Apple 的請求。
enum AppleNonce {
    static func random(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
```

`ImeTime/Features/Onboarding/WelcomeView.swift`：
```swift
import AuthenticationServices
import SwiftUI

struct WelcomeView: View {
    let auth: any AuthService
    @State private var errorMessage: String?
    @State private var currentNonce: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("ImeTime")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text("每小時 2 秒，和朋友一起記錄真實生活。")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            SignInWithAppleButton(.signIn) { request in
                let nonce = AppleNonce.random()
                currentNonce = nonce
                request.requestedScopes = []
                request.nonce = AppleNonce.sha256Hex(nonce)
            } onCompletion: { result in
                Task { await handle(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            Link("隱私權政策", destination: AppLinks.privacyPolicy)
                .font(.footnote)
        }
        .padding(24)
        .alert("登入失敗", isPresented: isShowingError) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func handle(_ result: Result<ASAuthorization, any Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = "無法完成 Apple 登入，請再試一次。"
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce
            else {
                errorMessage = "Apple 沒有回傳有效的登入資訊。"
                return
            }
            do {
                try await auth.signInWithApple(identityToken: token, nonce: nonce)
            } catch {
                errorMessage = "登入伺服器失敗，請確認網路與 Supabase 是否啟動。"
            }
        }
    }
}
```

- [ ] **Step 3: 寫 HomeView 佔位**

`ImeTime/Features/Home/HomeView.swift`：
```swift
import ImeTimeCore
import SwiftUI

/// P0 佔位：顯示個人檔案與登出。P1 會改成房間列表。
struct HomeView: View {
    let profile: Profile
    let avatarURL: URL?
    let onSignOut: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                Text("嗨，\(profile.displayName)")
                    .font(.title2.bold())
                Text("房間功能將在下一階段加入。")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("ImeTime")
            .toolbar {
                Button("登出", role: .destructive, action: onSignOut)
            }
        }
    }
}
```

- [ ] **Step 4: 改寫 ImeTimeApp 與 RootView**

`ImeTime/App/ImeTimeApp.swift`：
```swift
import SwiftUI

@main
struct ImeTimeApp: App {
    private let environment: AppEnvironment
    @State private var coordinator: SessionCoordinator

    init() {
        let environment = AppEnvironment.live()
        self.environment = environment
        _coordinator = State(initialValue: SessionCoordinator(auth: environment.auth, profiles: environment.profiles))
    }

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator, environment: environment)
                .task { coordinator.start() }
        }
    }
}
```

`ImeTime/App/RootView.swift`：
```swift
import SwiftUI

struct RootView: View {
    let coordinator: SessionCoordinator
    let environment: AppEnvironment

    var body: some View {
        switch coordinator.screen {
        case .loading:
            ProgressView()
        case .welcome:
            WelcomeView(auth: environment.auth)
        case .createProfile(let userID):
            // Task 10 會換成 CreateProfileView
            Text("建立個人檔案（\(userID.uuidString.prefix(8))）")
        case .home(let profile):
            HomeView(
                profile: profile,
                avatarURL: profile.avatarPath.flatMap(environment.profiles.avatarURL),
                onSignOut: { Task { try? await environment.auth.signOut() } }
            )
        case .failed(let message):
            ContentUnavailableView {
                Label("載入失敗", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("重試") { Task { await coordinator.retry() } }
            }
        }
    }
}
```

- [ ] **Step 5: 建置並在模擬器手動驗證登入**

```bash
make build
make test-app
```
Expected：兩者成功。

手動驗證（模擬器需先在 Settings > 登入 Apple ID）：
1. `supabase start` 已在跑；`Config/Local.xcconfig` 已填 anon key。
2. Xcode 開啟 `ImeTime.xcodeproj`，Run 到 iPhone 16 模擬器。
3. 看到 Welcome，按 Sign in with Apple，完成後畫面變成「建立個人檔案（xxxxxxxx）」。
4. 到 `http://127.0.0.1:54323`（Supabase Studio）> Authentication > Users，看到一位 apple provider 的使用者。

若 Studio 出現 401/`aud` 錯誤：確認 `config.toml` 的 `client_id` 與 `project.yml` 的 `PRODUCT_BUNDLE_IDENTIFIER` 完全相同，改完要 `supabase stop && supabase start`。

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(onboarding): add WelcomeView with Sign in with Apple and wire RootView"
```

---

### Task 10: CreateProfileView 與 ViewModel（TDD）

**Files:**
- Create: `ImeTime/Features/Onboarding/CreateProfileViewModel.swift`, `ImeTime/Features/Onboarding/CreateProfileView.swift`, `ImeTime/Features/Onboarding/CameraPicker.swift`
- Modify: `ImeTime/App/RootView.swift`
- Test: `ImeTimeTests/CreateProfileViewModelTests.swift`

**Interfaces:**
- Consumes: `ProfileRepository`、`DisplayName`、`AvatarImageEncoder`、`SessionCoordinator.profileCreated(_:)`
- Produces:
  - `@MainActor @Observable final class CreateProfileViewModel { var displayNameInput: String; var avatarImage: UIImage?; private(set) var isSaving: Bool; private(set) var errorMessage: String?; init(userID: UUID, profiles: any ProfileRepository, encodeAvatar: @escaping @Sendable (UIImage) -> Data? = { AvatarImageEncoder.jpegData(from: $0) }); func save() async -> Profile? }`
  - `struct CreateProfileView: View { init(userID: UUID, profiles: any ProfileRepository, onCreated: @escaping (Profile) -> Void) }`
  - `extension NameValidationError { var userMessage: String }`（P1 的 RoomName 也用）

- [ ] **Step 1: 寫失敗測試**

`ImeTimeTests/CreateProfileViewModelTests.swift`：
```swift
import Foundation
import Testing
import UIKit
@testable import ImeTime

@MainActor
@Suite struct CreateProfileViewModelTests {
    let uid = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    private func makeSUT(profiles: FakeProfileRepository, encoded: Data? = Data([1, 2, 3])) -> CreateProfileViewModel {
        CreateProfileViewModel(userID: uid, profiles: profiles, encodeAvatar: { _ in encoded })
    }

    @Test func emptyNameShowsErrorWithoutCallingRepository() async {
        let profiles = FakeProfileRepository()
        let sut = makeSUT(profiles: profiles)
        sut.displayNameInput = "   "
        let result = await sut.save()
        #expect(result == nil)
        #expect(sut.errorMessage == "請輸入名稱。")
        #expect(await profiles.createCalls.isEmpty)
    }

    @Test func tooLongNameShowsLimitMessage() async {
        let sut = makeSUT(profiles: FakeProfileRepository())
        sut.displayNameInput = String(repeating: "字", count: 21)
        _ = await sut.save()
        #expect(sut.errorMessage == "名稱最多 20 個字。")
    }

    @Test func validNameWithoutAvatarCreatesProfileWithTrimmedName() async {
        let profiles = FakeProfileRepository()
        let sut = makeSUT(profiles: profiles)
        sut.displayNameInput = "  小明 "
        let result = await sut.save()
        #expect(result?.displayName == "小明")
        #expect(await profiles.createCalls == [.init(userID: uid, displayName: "小明", avatarPath: nil)])
        #expect(await profiles.uploadCalls.isEmpty)
    }

    @Test func avatarIsUploadedBeforeCreate() async {
        let profiles = FakeProfileRepository()
        let sut = makeSUT(profiles: profiles)
        sut.displayNameInput = "小明"
        sut.avatarImage = UIImage()
        let result = await sut.save()
        #expect(result?.avatarPath == "11111111-1111-1111-1111-111111111111/avatar.jpg")
        #expect(await profiles.uploadCalls.count == 1)
    }

    @Test func avatarEncodingFailureShowsError() async {
        let profiles = FakeProfileRepository()
        let sut = makeSUT(profiles: profiles, encoded: nil)
        sut.displayNameInput = "小明"
        sut.avatarImage = UIImage()
        let result = await sut.save()
        #expect(result == nil)
        #expect(sut.errorMessage == "頭像處理失敗，請換一張圖片。")
        #expect(await profiles.createCalls.isEmpty)
    }

    @Test func repositoryFailureShowsNetworkError() async {
        let profiles = FakeProfileRepository()
        await profiles.fail(with: FakeError())
        let sut = makeSUT(profiles: profiles)
        sut.displayNameInput = "小明"
        let result = await sut.save()
        #expect(result == nil)
        #expect(sut.errorMessage == "儲存失敗，請檢查網路後再試一次。")
        #expect(sut.isSaving == false)
    }
}
```

- [ ] **Step 2: 執行確認失敗**

```bash
make test-app
```
Expected：`cannot find 'CreateProfileViewModel' in scope`。

- [ ] **Step 3: 實作 ViewModel**

`ImeTime/Features/Onboarding/CreateProfileViewModel.swift`：
```swift
import Foundation
import ImeTimeCore
import Observation
import UIKit

@MainActor
@Observable
final class CreateProfileViewModel {
    var displayNameInput = ""
    var avatarImage: UIImage?
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    private let userID: UUID
    private let profiles: any ProfileRepository
    private let encodeAvatar: @Sendable (UIImage) -> Data?

    init(
        userID: UUID,
        profiles: any ProfileRepository,
        encodeAvatar: @escaping @Sendable (UIImage) -> Data? = { AvatarImageEncoder.jpegData(from: $0) }
    ) {
        self.userID = userID
        self.profiles = profiles
        self.encodeAvatar = encodeAvatar
    }

    /// 成功回傳建立的 Profile；失敗回 nil 並設定 errorMessage。
    func save() async -> Profile? {
        errorMessage = nil
        let name: DisplayName
        do {
            name = try DisplayName(displayNameInput)
        } catch {
            errorMessage = error.userMessage
            return nil
        }

        var avatarData: Data?
        if let avatarImage {
            guard let data = encodeAvatar(avatarImage) else {
                errorMessage = "頭像處理失敗，請換一張圖片。"
                return nil
            }
            avatarData = data
        }

        isSaving = true
        defer { isSaving = false }
        do {
            var avatarPath: String?
            if let avatarData {
                avatarPath = try await profiles.uploadAvatar(userID: userID, jpegData: avatarData)
            }
            return try await profiles.createProfile(userID: userID, displayName: name, avatarPath: avatarPath)
        } catch {
            errorMessage = "儲存失敗，請檢查網路後再試一次。"
            return nil
        }
    }
}

extension NameValidationError {
    var userMessage: String {
        switch self {
        case .empty: "請輸入名稱。"
        case .tooLong(let max): "名稱最多 \(max) 個字。"
        }
    }
}
```

- [ ] **Step 4: 執行確認通過**

```bash
make test-app
```
Expected：TEST SUCCEEDED。

- [ ] **Step 5: 寫 CameraPicker 與 CreateProfileView，接上 RootView**

`ImeTime/Features/Onboarding/CameraPicker.swift`：
```swift
import SwiftUI
import UIKit

/// 用系統相機拍一張照片（頭像用）。模擬器沒有相機時呼叫端不要顯示此入口。
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
```

`ImeTime/Features/Onboarding/CreateProfileView.swift`：
```swift
import ImeTimeCore
import PhotosUI
import SwiftUI

struct CreateProfileView: View {
    @State private var viewModel: CreateProfileViewModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    let onCreated: (Profile) -> Void

    init(userID: UUID, profiles: any ProfileRepository, onCreated: @escaping (Profile) -> Void) {
        _viewModel = State(initialValue: CreateProfileViewModel(userID: userID, profiles: profiles))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("頭像（選填）") {
                    HStack(spacing: 16) {
                        avatarPreview
                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker("從相簿選擇", selection: $pickerItem, matching: .images)
                            if CameraPicker.isAvailable {
                                Button("拍一張") { isShowingCamera = true }
                            }
                        }
                    }
                }
                Section("名稱") {
                    TextField("朋友怎麼叫你（最多 \(DisplayName.maxLength) 字）", text: $viewModel.displayNameInput)
                        .textInputAutocapitalization(.never)
                }
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                Button {
                    Task {
                        if let profile = await viewModel.save() { onCreated(profile) }
                    }
                } label: {
                    if viewModel.isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("完成").frame(maxWidth: .infinity)
                    }
                }
                .disabled(viewModel.isSaving)
            }
            .navigationTitle("建立個人檔案")
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    viewModel.avatarImage = image
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in viewModel.avatarImage = image }
                .ignoresSafeArea()
        }
    }

    private var avatarPreview: some View {
        Group {
            if let image = viewModel.avatarImage {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
    }
}
```

`ImeTime/App/RootView.swift` 把 `.createProfile` 分支換成：
```swift
        case .createProfile(let userID):
            CreateProfileView(userID: userID, profiles: environment.profiles, onCreated: coordinator.profileCreated)
                .id(userID)
```

- [ ] **Step 6: 建置、跑全部測試、手動驗證**

```bash
make build
make test-core
make test-app
```
Expected：全部成功。

手動：模擬器登入後填名稱、從相簿選一張圖（模擬器內建範例照片）、按完成 → 進入 Home 顯示名稱與頭像。Studio > Table Editor > profiles 有一列，Storage > avatars 有 `{uid}/avatar.jpg`。按登出回到 Welcome；再登入直接進 Home（不再要求建立檔案）。

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(onboarding): add CreateProfileView with avatar picker and validation"
```

---

### Task 11: P0 驗收與收尾

**Files:**
- Modify: `CLAUDE.md`（若前面任務發現指令需要調整）

- [ ] **Step 1: 全套測試**

```bash
make test
```
Expected：`test-core`、`test-db`、`test-app` 全部成功。

- [ ] **Step 2: 手動驗收清單（模擬器 + 本機 Supabase）**

- [ ] 冷啟動 → Welcome（不閃現其他畫面）
- [ ] Sign in with Apple 取消 → 停留 Welcome、無錯誤提示
- [ ] 登入成功、無檔案 → 建立個人檔案
- [ ] 名稱空白 / 超過 20 字 → 對應紅字
- [ ] 選頭像 + 完成 → Home 顯示名稱與頭像；Storage 檔案 ≤ 200 KB
- [ ] 登出 → Welcome；重新登入 → 直接 Home
- [ ] 關掉 `supabase stop` 後登入 → 顯示「登入伺服器失敗…」而非閃退

- [ ] **Step 3: 標記完成**

```bash
git tag p0-done
git log --oneline | head -15
```

Expected：從 `chore: scaffold…` 到 `feat(onboarding): add CreateProfileView…` 共 10 個 commit，tag `p0-done`。

---

## 自我檢查（撰寫者已執行）

- **Spec 覆蓋**：§5 profiles（Task 3）、§5.3 avatars bucket（Task 4）、§6.1 首次進入流程（Task 8–10，通知說明頁依 spec 屬 P3）、§7 結構與依賴（Task 1、5、6）、§8 supabase 目錄（Task 3）、§10 anon key 公開 + RLS（Task 3、4）、§11 測試層（Task 2–10）。
- **占位符**：無 TBD/TODO；`AppLinks.privacyPolicy` 是需要使用者替換帳號的設定值，非程式占位。
- **型別一致**：`AuthService.states()`、`ProfileRepository` 四個方法、`SessionCoordinator.Screen` 五個 case、`FakeProfileRepository.fail(with: Error?)` 與測試一致。
