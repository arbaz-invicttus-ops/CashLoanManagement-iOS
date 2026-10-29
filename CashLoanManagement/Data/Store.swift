import Foundation
import Observation

@Observable
final class AppStore {
    private let database: Database
    private(set) var loans: [Loan] = []
    private(set) var titles: [CashTitle] = []
    private(set) var transactions: [CashTransaction] = []

    init(databasePath: String) throws {
        database = try Database(path: databasePath)
        try reload()
    }

    static func openDefault() -> AppStore {
        do {
            return try AppStore(databasePath: try defaultPath())
        } catch {
            fatalError("Could not open the local database: \(error.localizedDescription)")
        }
    }

    static func preview() -> AppStore {
        try! AppStore(databasePath: ":memory:")
    }

    var summary: HomeSummary { LoanMath.homeSummary(loans: loans) }
    var counts: LoanCounts { LoanMath.counts(loans: loans) }
    var deletedLoans: [Loan] { loans.filter(\.isDeleted) }

    func loan(id: Int64) -> Loan? {
        loans.first { $0.id == id && !$0.isDeleted }
    }

    func anyLoan(id: Int64) -> Loan? {
        loans.first { $0.id == id }
    }

    func title(id: Int64) -> CashTitle? {
        titles.first { $0.id == id }
    }

    func transactions(for titleID: Int64) -> [CashTransaction] {
        transactions.filter { $0.cashTitleId == titleID }
    }

    func balance(for titleID: Int64) -> Double {
        CloudMerge.balance(for: titleID, transactions: transactions)
    }

    func creditedTotal(for titleID: Int64) -> Double {
        transactions(for: titleID).filter { $0.type == .CREDIT }.reduce(0) { $0 + $1.amount }
    }

    func spentTotal(for titleID: Int64) -> Double {
        transactions(for: titleID).filter { $0.type == .DEBIT }.reduce(0) { $0 + $1.amount }
    }

    func saveNewLoan(_ draft: LoanDraft, now: Date = Date()) throws {
        let loan = try makeLoan(from: draft, existing: nil, now: now)
        try database.saveLoan(loan)
        try reload()
    }

    func updateLoan(id: Int64, draft: LoanDraft, now: Date = Date()) throws {
        guard let existing = anyLoan(id: id), !existing.isDeleted else {
            throw AppError("That loan is no longer on this iPhone.")
        }
        let loan = try makeLoan(from: draft, existing: existing, now: now)
        try database.saveLoan(loan)
        try reload()
        removeUnusedImages(existing.imagePaths)
    }

    func markOverdueIfNeeded(id: Int64, now: Date = Date()) throws {
        guard let loan = anyLoan(id: id), let updated = LoanRules.markedOverdueOnOpen(loan, now: now) else { return }
        try database.saveLoan(updated)
        try reload()
    }

    func setStatus(id: Int64, status: LoanStatus, now: Date = Date()) throws {
        guard status == .PENDING || status == .CLEARED else { return }
        guard var loan = loan(id: id) else { throw AppError("That loan is no longer on this iPhone.") }
        loan.status = status
        loan.updatedAt = AppDate.millis(now)
        try database.saveLoan(loan)
        try reload()
    }

    func softDelete(id: Int64, now: Date = Date()) throws {
        guard var loan = loan(id: id) else { throw AppError("That loan is no longer on this iPhone.") }
        loan.isDeleted = true
        loan.updatedAt = AppDate.millis(now)
        try database.saveLoan(loan)
        try reload()
    }

    func recover(id: Int64, now: Date = Date()) throws {
        guard var loan = anyLoan(id: id), loan.isDeleted else {
            throw AppError("That loan is no longer in the deleted list.")
        }
        loan.isDeleted = false
        loan.updatedAt = AppDate.millis(now)
        try database.saveLoan(loan)
        try reload()
    }

    func permanentlyDelete(id: Int64) throws {
        guard let loan = anyLoan(id: id) else { return }
        let paths = loan.imagePaths
        try database.deleteLoan(id: id)
        try reload()
        removeUnusedImages(paths)
    }

    func createTitle(name: String, description: String, now: Date = Date()) throws {
        if let message = CashRules.validateTitleName(name) { throw AppError(message) }
        let title = CashTitle(
            id: try database.nextID(.title),
            titleName: TextValue.trimmed(name),
            description: TextValue.optional(description),
            currentBalance: 0,
            createdAt: AppDate.millis(now),
            lastBackupTime: 0
        )
        try database.saveTitle(title)
        try reload()
    }

    func deleteTitle(id: Int64) throws {
        guard title(id: id) != nil else { return }
        let paths = transactions(for: id).compactMap(\.imageUri)
        try database.deleteTitle(id: id)
        try reload()
        removeUnusedImages(paths)
    }

    func addTransaction(
        titleID: Int64,
        amountText: String,
        type: TransactionType,
        itemName: String,
        personName: String,
        notes: String,
        imageUri: String?,
        createdAt: Int64
    ) throws {
        guard title(id: titleID) != nil else { throw AppError("That cash title is no longer on this iPhone.") }
        guard let amount = Money.parse(amountText) else { throw AppError("Amount must be greater than 0.") }
        switch type {
        case .CREDIT:
            if let message = CashRules.validateCredit(amount: amount) { throw AppError(message) }
        case .DEBIT:
            if let message = CashRules.validateDebit(amount: amount, balance: balance(for: titleID)) { throw AppError(message) }
        }
        let transaction = CashTransaction(
            id: try database.nextID(.transaction),
            cashTitleId: titleID,
            amount: amount,
            type: type,
            itemName: TextValue.optional(itemName),
            personName: TextValue.optional(personName),
            notes: TextValue.optional(notes),
            imageUri: TextValue.optional(imageUri),
            createdAt: createdAt == 0 ? AppDate.millis(Date()) : createdAt,
            lastBackupTime: 0
        )
        try database.saveTransaction(transaction)
        try reload()
        try storeBalance(for: titleID)
    }

    func applyCloud(_ cloud: CloudSnapshot) throws {
        let local = snapshot
        let loans = CloudMerge.mergeLoans(local: local.loans, cloud: cloud.loans)
        let cash = CloudMerge.mergeCash(
            localTitles: local.titles,
            localTransactions: local.transactions,
            cloudTitles: cloud.titles,
            cloudTransactions: cloud.transactions
        )
        let previousImages = imagePaths(in: local)
        if let cash {
            try database.replaceAll(loans: loans, titles: cash.titles, transactions: cash.transactions)
        } else {
            try database.replaceLoans(loans)
        }
        try database.noteIDs(cloud.loans.map(\.id), kind: .loan)
        try database.noteIDs(cloud.titles.map(\.id), kind: .title)
        try database.noteIDs(cloud.transactions.map(\.id), kind: .transaction)
        try reload()
        removeUnusedImages(previousImages)
    }

    func noteCloudDocumentIDs(loans: [String], titles: [String], transactions: [String]) throws {
        try database.noteIDs(loans.compactMap(Int64.init), kind: .loan)
        try database.noteIDs(titles.compactMap(Int64.init), kind: .title)
        try database.noteIDs(transactions.compactMap(Int64.init), kind: .transaction)
    }

    func markBackedUp(loanIDs: [Int64], titleIDs: [Int64], transactionIDs: [Int64], time: Int64) throws {
        let loansToStamp = Set(loanIDs)
        let titlesToStamp = Set(titleIDs)
        let transactionsToStamp = Set(transactionIDs)
        var nextLoans = loans
        var nextTitles = titles
        var nextTransactions = transactions
        for index in nextLoans.indices where loansToStamp.contains(nextLoans[index].id) {
            nextLoans[index].lastBackupTime = time
        }
        for index in nextTitles.indices where titlesToStamp.contains(nextTitles[index].id) {
            nextTitles[index].lastBackupTime = time
        }
        for index in nextTransactions.indices where transactionsToStamp.contains(nextTransactions[index].id) {
            nextTransactions[index].lastBackupTime = time
        }
        try database.replaceAll(loans: nextLoans, titles: nextTitles, transactions: nextTransactions)
        try reload()
    }

    func importBackup(_ data: Data) throws {
        let decoded = try BackupFile.decode(data)
        let merged = BackupFile.applying(decoded, to: snapshot)
        let previousImages = imagePaths(in: snapshot)
        switch decoded {
        case .loansOnly:
            try database.replaceLoans(merged.loans)
        case .full:
            try database.replaceAll(loans: merged.loans, titles: merged.titles, transactions: merged.transactions)
        }
        try reload()
        removeUnusedImages(previousImages)
    }

    func exportData() throws -> Data {
        try BackupFile.encode(loans: loans, titles: titles, transactions: transactions)
    }

    func writeExportFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cash-loans-backup.json")
        try exportData().write(to: url, options: .atomic)
        return url
    }

    private func makeLoan(from draft: LoanDraft, existing: Loan?, now: Date) throws -> Loan {
        let amount = Money.parse(draft.amountText) ?? 0
        if let message = LoanRules.validate(
            personName: draft.personName,
            amount: amount,
            type: draft.loanType,
            givenDate: draft.givenDate,
            takenDate: draft.takenDate,
            expectedReturnDate: draft.expectedReturnDate
        ) {
            throw AppError(message)
        }
        let stamp = AppDate.millis(now)
        return Loan(
            id: try existing?.id ?? database.nextID(.loan),
            personName: TextValue.trimmed(draft.personName),
            phoneNumber: TextValue.optional(draft.phoneNumber),
            amount: amount,
            loanType: draft.loanType,
            status: LoanRules.statusOnSave(
                isNew: existing == nil,
                current: existing?.status,
                expectedReturnDate: draft.expectedReturnDate,
                now: now
            ),
            givenDate: draft.givenDate,
            takenDate: draft.takenDate,
            expectedReturnDate: draft.expectedReturnDate,
            notes: TextValue.optional(draft.notes),
            imagePaths: draft.imagePaths,
            createdAt: existing?.createdAt ?? stamp,
            updatedAt: stamp,
            isDeleted: false,
            lastBackupTime: existing?.lastBackupTime ?? 0
        )
    }

    private func storeBalance(for titleID: Int64) throws {
        guard var title = title(id: titleID) else { return }
        title.currentBalance = balance(for: titleID)
        try database.saveTitle(title)
        try reload()
    }

    private func reload() throws {
        loans = try database.loans()
        titles = try database.titles()
        transactions = try database.transactions()
    }

    private var snapshot: CloudSnapshot {
        CloudSnapshot(loans: loans, titles: titles, transactions: transactions)
    }

    private func imagePaths(in snapshot: CloudSnapshot) -> [String] {
        snapshot.loans.flatMap(\.imagePaths) + snapshot.transactions.compactMap(\.imageUri)
    }

    private func removeUnusedImages(_ paths: [String]) {
        let keep = Set(imagePaths(in: snapshot))
        for path in Set(paths) where !keep.contains(path) {
            ImageStore.deleteIfOwned(path)
        }
    }

    private static func defaultPath() throws -> String {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CashLoanManagement", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("cash.sqlite").path
    }
}
