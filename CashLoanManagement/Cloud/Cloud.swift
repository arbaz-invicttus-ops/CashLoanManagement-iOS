import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

enum FirebaseBootstrap {
    static var isConfigured = false

    static func configureIfPossible() {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        isConfigured = true
    }
}

@Observable
final class AuthService {
    private(set) var email: String?
    let isConfigured: Bool
    private var listener: AuthStateDidChangeListenerHandle?

    var isSignedIn: Bool { email != nil }

    init() {
        isConfigured = FirebaseBootstrap.isConfigured
        email = nil
        listener = nil
        guard isConfigured else { return }
        email = Auth.auth().currentUser?.email
        listener = Auth.auth().addStateDidChangeListener { _, user in
            let nextEmail = user?.email
            Task { @MainActor in
                self.email = nextEmail
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        try validate(email: email, password: password)
        _ = try await Auth.auth().signIn(withEmail: TextValue.trimmed(email), password: password)
    }

    func createAccount(email: String, password: String) async throws {
        try validate(email: email, password: password)
        _ = try await Auth.auth().createUser(withEmail: TextValue.trimmed(email), password: password)
    }

    func signOut() throws {
        guard isConfigured else { return }
        try Auth.auth().signOut()
        email = nil
    }

    private func validate(email: String, password: String) throws {
        guard isConfigured else {
            throw AppError("Add GoogleService-Info.plist from Firebase project mycash-3b971. Use bundle ID abc.CashLoanManagement.")
        }
        guard TextValue.trimmed(email).contains("@") else { throw AppError("Enter a valid email address.") }
        guard password.count >= 6 else { throw AppError("Password must be at least 6 characters.") }
    }
}

enum CloudClient {
    static func refreshIDWatermarks(store: AppStore) async {
        do {
            let user = try userDocument()
            let loanIDs = try await documentIDs(user.collection("loans"))
            let titleIDs = try await documentIDs(user.collection("cashTitles"))
            let transactionIDs = try await documentIDs(user.collection("cashTransactions"))
            try store.noteCloudDocumentIDs(loans: loanIDs, titles: titleIDs, transactions: transactionIDs)
        } catch {
            return
        }
    }

    static func backup(store: AppStore) async throws {
        let user = try userDocument()
        let loanSnap = try await user.collection("loans").getDocuments(source: .server)
        let titleSnap = try await user.collection("cashTitles").getDocuments(source: .server)
        let transactionSnap = try await user.collection("cashTransactions").getDocuments(source: .server)
        try store.noteCloudDocumentIDs(
            loans: loanSnap.documents.map(\.documentID),
            titles: titleSnap.documents.map(\.documentID),
            transactions: transactionSnap.documents.map(\.documentID)
        )

        let now = AppDate.millis(Date())
        let loans = store.loans.filter { !$0.isDeleted }.map { loan -> Loan in
            var copy = loan
            copy.lastBackupTime = now
            return copy
        }
        let titles = store.titles.map { title -> CashTitle in
            var copy = title
            copy.lastBackupTime = now
            return copy
        }
        let transactions = store.transactions.map { transaction -> CashTransaction in
            var copy = transaction
            copy.lastBackupTime = now
            return copy
        }

        try await write(loans.map { ($0.id, RecordCodec.loanPayload($0)) }, to: user.collection("loans"))
        try await write(titles.map { ($0.id, RecordCodec.titlePayload($0)) }, to: user.collection("cashTitles"))
        try await deleteDocuments(in: titleSnap, keeping: Set(titles.map { String($0.id) }))
        try await write(transactions.map { ($0.id, RecordCodec.transactionPayload($0)) }, to: user.collection("cashTransactions"))
        try await deleteDocuments(in: transactionSnap, keeping: Set(transactions.map { String($0.id) }))
        try store.markBackedUp(
            loanIDs: loans.map(\.id),
            titleIDs: titles.map(\.id),
            transactionIDs: transactions.map(\.id),
            time: now
        )
    }

    static func restore(store: AppStore) async throws {
        let user = try userDocument()
        let loanSnap = try await user.collection("loans").getDocuments(source: .server)
        let titleSnap = try await user.collection("cashTitles").getDocuments(source: .server)
        let transactionSnap = try await user.collection("cashTransactions").getDocuments(source: .server)
        let cloud = CloudSnapshot(
            loans: try loanSnap.documents.map { try RecordCodec.loan(from: $0.data(), documentID: $0.documentID) },
            titles: try titleSnap.documents.map { try RecordCodec.title(from: $0.data(), documentID: $0.documentID) },
            transactions: try transactionSnap.documents.map { try RecordCodec.transaction(from: $0.data(), documentID: $0.documentID) }
        )
        try store.applyCloud(cloud)
    }

    private static func userDocument() throws -> DocumentReference {
        guard FirebaseBootstrap.isConfigured else {
            throw AppError("Add GoogleService-Info.plist from Firebase project mycash-3b971 before using cloud backup.")
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError("Sign in before using cloud backup.")
        }
        return Firestore.firestore().collection("users").document(uid)
    }

    private static func documentIDs(_ collection: CollectionReference) async throws -> [String] {
        let snapshot = try await collection.getDocuments(source: .server)
        return snapshot.documents.map(\.documentID)
    }

    private static func write(_ records: [(Int64, [String: Any])], to collection: CollectionReference) async throws {
        let database = Firestore.firestore()
        var batch = database.batch()
        var count = 0
        for record in records {
            batch.setData(record.1, forDocument: collection.document(String(record.0)))
            count += 1
            if count == 400 {
                try await batch.commit()
                batch = database.batch()
                count = 0
            }
        }
        if count > 0 {
            try await batch.commit()
        }
    }

    private static func deleteDocuments(in snapshot: QuerySnapshot, keeping ids: Set<String>) async throws {
        let stale = snapshot.documents.filter { !ids.contains($0.documentID) }
        guard !stale.isEmpty else { return }
        let database = Firestore.firestore()
        var batch = database.batch()
        var count = 0
        for document in stale {
            batch.deleteDocument(document.reference)
            count += 1
            if count == 400 {
                try await batch.commit()
                batch = database.batch()
                count = 0
            }
        }
        if count > 0 {
            try await batch.commit()
        }
    }
}
