import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct ToolsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthService.self) private var auth
    @Environment(LockService.self) private var lock

    @State private var showingSignIn = false
    @State private var isWorking = false
    @State private var message: String?
    @State private var confirmBackup = false
    @State private var confirmRestore = false
    @State private var showingImporter = false
    @State private var pendingImport: PendingImport?
    @State private var exportURL: URL?
    @State private var biometricsOn = false

    private var exportStamp: Int64 {
        let loanStamp = store.loans.map(\.updatedAt).max() ?? 0
        let cashStamp = store.transactions.map(\.createdAt).max() ?? 0
        return loanStamp &+ cashStamp &+ Int64(store.loans.count + store.titles.count)
    }

    var body: some View {
        let counts = store.counts
        List {
            Section("Account") {
                if auth.isSignedIn {
                    LabeledContent("Signed in", value: auth.email ?? "")
                    Button("Sign out", role: .destructive) { signOut() }
                } else {
                    Button("Sign in") { showingSignIn = true }
                    if !auth.isConfigured {
                        Text("Add GoogleService-Info.plist from Firebase project mycash-3b971. Register an iOS app with bundle ID abc.CashLoanManagement. An account created on Android works here with the same email and password.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Cloud") {
                Button("Back up to cloud") { confirmBackup = true }
                    .disabled(!auth.isSignedIn || isWorking)
                Button("Restore from cloud") { confirmRestore = true }
                    .disabled(!auth.isSignedIn || isWorking)
                if !auth.isSignedIn {
                    Text("Sign in to back up or restore. Restoring merges cloud data into this iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("File backup") {
                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("Export backup", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button("Export backup") { refreshExport() }
                }
                Button("Import backup") { showingImporter = true }
                    .disabled(isWorking)
            }
            Section("Security") {
                if lock.isEnabled {
                    NavigationLink("Change PIN", value: Route.pin(.change))
                    NavigationLink("Remove PIN", value: Route.pin(.remove))
                } else {
                    NavigationLink("Set PIN", value: Route.pin(.create))
                }
                if let name = lock.biometryName {
                    Toggle(name, isOn: $biometricsOn)
                        .disabled(!lock.isEnabled)
                }
                Text("The PIN and \(lock.biometryName ?? "biometrics") stay on this iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Loans") {
                LabeledContent("Total", value: "\(counts.total)")
                LabeledContent("Cleared", value: "\(counts.cleared)")
                LabeledContent("Overdue", value: "\(counts.overdue)")
            }
            Section {
                NavigationLink("Deleted loans", value: Route.deletedLoans)
            }
        }
        .navigationTitle("Tools")
        .overlay {
            if isWorking {
                ProgressView("Working…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .sheet(isPresented: $showingSignIn) {
            NavigationStack { SignInView() }
        }
        .confirmationDialog("Back up this iPhone?", isPresented: $confirmBackup, titleVisibility: .visible) {
            Button("Back up") { runCloud(backup: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Loans that are not deleted are uploaded. Cash titles and transactions on this iPhone replace the cloud copies, and cloud cash records missing here are deleted. Cloud loans that are missing here are left in place.")
        }
        .confirmationDialog("Restore from the cloud?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore") { runCloud(backup: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Loans already on this iPhone stay unless the cloud copy is newer. If the cloud has no cash records, cash titles on this iPhone are left alone.")
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json, .plainText, .data], allowsMultipleSelection: false) { result in
            handleImportPick(result)
        }
        .alert("Import this backup?", isPresented: Binding(
            get: { pendingImport != nil },
            set: { if !$0 { pendingImport = nil } }
        )) {
            Button("Import") { applyImport() }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text(pendingImport?.summary ?? "")
        }
        .errorAlert($message)
        .onAppear {
            biometricsOn = lock.biometricsEnabled
            refreshExport()
        }
        .onChange(of: exportStamp) { _, _ in refreshExport() }
        .onChange(of: biometricsOn) { _, enabled in
            guard enabled != lock.biometricsEnabled else { return }
            if !enabled {
                lock.biometricsEnabled = false
                return
            }
            Task {
                let accepted = await lock.authenticate()
                lock.biometricsEnabled = accepted
                biometricsOn = accepted
            }
        }
    }

    private func signOut() {
        do { try auth.signOut() }
        catch { message = error.localizedDescription }
    }

    private func runCloud(backup: Bool) {
        isWorking = true
        Task {
            do {
                if backup {
                    try await CloudClient.backup(store: store)
                    message = "Backup finished."
                } else {
                    try await CloudClient.restore(store: store)
                    message = "Restore finished."
                }
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
            refreshExport()
        }
    }

    private func refreshExport() {
        exportURL = try? store.writeExportFile()
    }

    private func handleImportPick(_ result: Result<[URL], Error>) {
        do {
            let url = try result.get().first
            guard let url else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let decoded = try BackupFile.decode(data)
            let summary: String
            switch decoded {
            case .loansOnly(let loans):
                summary = "This file replaces the loans on this iPhone (\(loans.count)) and leaves cash titles alone."
            case .full(let loans, let titles, let transactions):
                summary = "This version 2 file replaces loans (\(loans.count)), cash titles (\(titles.count)), and transactions (\(transactions.count)) on this iPhone."
            }
            pendingImport = PendingImport(data: data, summary: summary)
        } catch {
            message = error.localizedDescription
        }
    }

    private func applyImport() {
        guard let pendingImport else { return }
        do {
            try store.importBackup(pendingImport.data)
            message = "Import finished."
        } catch {
            message = error.localizedDescription
        }
        self.pendingImport = nil
        refreshExport()
    }
}

private struct PendingImport: Identifiable {
    let id = UUID()
    let data: Data
    let summary: String
}

struct SignInView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        Form {
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(.password)
            Section {
                Button("Sign in") { submit(create: false) }
                Button("Create account") { submit(create: true) }
            }
            .disabled(isWorking)
            Text("Password must be at least 6 characters. Use the same email and password as the Android app.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Sign In")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .overlay {
            if isWorking { ProgressView() }
        }
        .errorAlert($message)
    }

    private func submit(create: Bool) {
        isWorking = true
        Task {
            do {
                if create {
                    try await auth.createAccount(email: email, password: password)
                } else {
                    try await auth.signIn(email: email, password: password)
                }
                dismiss()
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }
}

struct PINSetupView: View {
    let purpose: PINPurpose
    @Environment(LockService.self) private var lock
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var first = ""
    @State private var current = ""
    @State private var step = 0
    @State private var message = ""

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Text(title)
                .font(.title2.weight(.semibold))
            Text(message.isEmpty ? instruction : message)
                .font(.subheadline)
                .foregroundStyle(message.isEmpty ? Color.secondary : Color.red)
                .multilineTextAlignment(.center)
            PINDots(count: pin.count)
            PINPad { digit in
                guard pin.count < 4 else { return }
                pin.append(digit)
                if pin.count == 4 { advance() }
            } onDelete: {
                if !pin.isEmpty { pin.removeLast() }
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .padding()
        .navigationTitle("PIN")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        switch purpose {
        case .create: "Set PIN"
        case .change: "Change PIN"
        case .remove: "Remove PIN"
        }
    }

    private var instruction: String {
        switch purpose {
        case .create:
            return step == 0 ? "Enter a 4-digit PIN." : "Enter the same PIN again."
        case .remove:
            return "Enter your current PIN."
        case .change:
            if step == 0 { return "Enter your current PIN." }
            if step == 1 { return "Enter a new 4-digit PIN." }
            return "Enter the new PIN again."
        }
    }

    private func advance() {
        switch purpose {
        case .create:
            confirmNewPIN()
        case .remove:
            if lock.removePIN(pin) {
                dismiss()
            } else {
                reject("Wrong PIN.")
            }
        case .change:
            if step == 0 {
                guard PINStore.matches(pin) else {
                    reject("Wrong PIN.")
                    return
                }
                current = pin
                pin = ""
                step = 1
                message = ""
            } else {
                confirmChangedPIN()
            }
        }
    }

    private func confirmNewPIN() {
        if step == 0 {
            first = pin
            pin = ""
            step = 1
            message = ""
            return
        }
        guard pin == first else {
            first = ""
            step = 0
            reject("Those PINs did not match. Start again.")
            return
        }
        do {
            try lock.setPIN(pin)
            dismiss()
        } catch {
            reject(error.localizedDescription)
        }
    }

    private func confirmChangedPIN() {
        if step == 1 {
            first = pin
            pin = ""
            step = 2
            message = ""
            return
        }
        guard pin == first else {
            step = 1
            first = ""
            reject("Those PINs did not match. Enter a new PIN.")
            return
        }
        do {
            if try lock.changePIN(current: current, newPIN: pin) {
                dismiss()
            } else {
                reject("Wrong PIN.")
            }
        } catch {
            reject(error.localizedDescription)
        }
    }

    private func reject(_ text: String) {
        pin = ""
        message = text
    }
}

struct LockView: View {
    @Environment(LockService.self) private var lock
    @State private var pin = ""
    @State private var message = ""
    @State private var didPrompt = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
            Text("Cash Loans")
                .font(.title.weight(.bold))
            Text(message.isEmpty ? "Enter your PIN" : message)
                .foregroundStyle(message.isEmpty ? Color.secondary : Color.red)
            PINDots(count: pin.count)
            if lock.biometricsEnabled, lock.biometryName != nil {
                Button {
                    Task { await unlockBiometrics() }
                } label: {
                    Label(lock.biometryName ?? "Unlock", systemImage: "faceid")
                }
            }
            PINPad { digit in
                guard pin.count < 4 else { return }
                pin.append(digit)
                if pin.count == 4 { submit() }
            } onDelete: {
                if !pin.isEmpty { pin.removeLast() }
            }
            .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task {
            guard !didPrompt else { return }
            didPrompt = true
            await unlockBiometrics()
        }
    }

    private func submit() {
        if lock.unlock(pin: pin) {
            message = ""
        } else {
            pin = ""
            message = "Wrong PIN."
        }
    }

    private func unlockBiometrics() async {
        guard lock.biometricsEnabled else { return }
        _ = await lock.unlockWithBiometrics()
    }
}
