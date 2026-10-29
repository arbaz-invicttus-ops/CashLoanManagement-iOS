import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(LockService.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            NavigationStack {
                HomeView()
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .addLoan:
                            LoanFormView(loanID: nil)
                        case .editLoan(let id):
                            LoanFormView(loanID: id)
                        case .loans:
                            LoanListView()
                        case .loanDetail(let id):
                            LoanDetailView(loanID: id)
                        case .deletedLoans:
                            DeletedLoansView()
                        case .cashTitles:
                            CashTitleListView()
                        case .cashDetail(let id):
                            CashTitleDetailView(titleID: id)
                        case .tools:
                            ToolsView()
                        case .pin(let purpose):
                            PINSetupView(purpose: purpose)
                        }
                    }
            }
            if lock.isLocked {
                LockView()
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                lock.lock()
            }
        }
        .task(id: auth.email) {
            guard auth.isSignedIn else { return }
            await CloudClient.refreshIDWatermarks(store: store)
        }
    }
}
