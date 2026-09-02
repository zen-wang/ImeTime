import SwiftUI

@main
struct ImeTimeApp: App {
    /// 啟動只有兩種結果：設定讀得到就正常跑，讀不到就顯示設定錯誤畫面（而不是 fatalError 直接閃退）。
    private enum Startup {
        case ready(environment: AppEnvironment, coordinator: SessionCoordinator)
        case misconfigured(AppConfigError)
    }

    @State private var startup: Startup

    init() {
        do {
            let config = try AppConfig.load()
            let environment = AppEnvironment.live(config: config)
            let coordinator = SessionCoordinator(auth: environment.auth, profiles: environment.profiles)
            _startup = State(initialValue: .ready(environment: environment, coordinator: coordinator))
        } catch {
            _startup = State(initialValue: .misconfigured(error))
        }
    }

    var body: some Scene {
        WindowGroup {
            switch startup {
            case .ready(let environment, let coordinator):
                RootView(coordinator: coordinator, environment: environment)
                    .task { coordinator.start() }
            case .misconfigured(let error):
                ConfigurationErrorView(message: error.userMessage)
            }
        }
    }
}
