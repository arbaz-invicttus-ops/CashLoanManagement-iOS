import SwiftUI

@main
struct CashLoanManagementApp: App {
    @State private var store: AppStore
    @State private var auth: AuthService
    @State private var lock: LockService

    init() {
        FirebaseBootstrap.configureIfPossible()
        _store = State(initialValue: AppStore.openDefault())
        _auth = State(initialValue: AuthService())
        _lock = State(initialValue: LockService())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(auth)
                .environment(lock)
        }
    }
}
