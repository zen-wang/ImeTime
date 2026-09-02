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
