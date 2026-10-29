import Foundation
import SQLite3

nonisolated enum RecordKind {
    case loan
    case title
    case transaction

    var table: String {
        switch self {
        case .loan: "loans"
        case .title: "cash_titles"
        case .transaction: "cash_transactions"
        }
    }

    var metaKey: String {
        switch self {
        case .loan: "loanHighWater"
        case .title: "titleHighWater"
        case .transaction: "transactionHighWater"
        }
    }
}

nonisolated final class Database {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        var handle: OpaquePointer?
        if sqlite3_open(path, &handle) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Couldn't open the local database."
            sqlite3_close(handle)
            throw AppError(message)
        }
        self.handle = handle
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
        try migrate()
        try seedHighWater()
    }

    deinit {
        sqlite3_close(handle)
    }

    func loans() throws -> [Loan] {
        try queryLoans("SELECT id, personName, phoneNumber, amount, loanType, status, givenDate, takenDate, expectedReturnDate, notes, imagePaths, createdAt, updatedAt, isDeleted, lastBackupTime FROM loans ORDER BY createdAt DESC, id DESC")
    }

    func titles() throws -> [CashTitle] {
        try queryTitles("SELECT id, titleName, description, currentBalance, createdAt, lastBackupTime FROM cash_titles ORDER BY createdAt DESC, id DESC")
    }

    func transactions() throws -> [CashTransaction] {
        try queryTransactions("SELECT id, cashTitleId, amount, type, itemName, personName, notes, imageUri, createdAt, lastBackupTime FROM cash_transactions ORDER BY createdAt DESC, id DESC")
    }

    func saveLoan(_ loan: Loan) throws {
        try transaction {
            try insertLoan(loan)
            try bump(.loan, floor: loan.id)
        }
    }

    func deleteLoan(id: Int64) throws {
        try transaction {
            try run("DELETE FROM loans WHERE id = ?") { statement in
                sqlite3_bind_int64(statement, 1, id)
            }
        }
    }

    func saveTitle(_ title: CashTitle) throws {
        try transaction {
            try insertTitle(title)
            try bump(.title, floor: title.id)
        }
    }

    func saveTransaction(_ transaction: CashTransaction) throws {
        try self.transaction {
            try insertTransaction(transaction)
            try bump(.transaction, floor: transaction.id)
        }
    }

    func deleteTitle(id: Int64) throws {
        try transaction {
            try run("DELETE FROM cash_transactions WHERE cashTitleId = ?") { statement in
                sqlite3_bind_int64(statement, 1, id)
            }
            try run("DELETE FROM cash_titles WHERE id = ?") { statement in
                sqlite3_bind_int64(statement, 1, id)
            }
        }
    }

    func replaceLoans(_ loans: [Loan]) throws {
        try transaction {
            try execute("DELETE FROM loans")
            for loan in loans { try insertLoan(loan) }
            try bump(.loan, floor: loans.map(\.id).max() ?? 0)
        }
    }

    func replaceCash(titles: [CashTitle], transactions: [CashTransaction]) throws {
        try transaction {
            try execute("DELETE FROM cash_transactions")
            try execute("DELETE FROM cash_titles")
            for title in titles { try insertTitle(title) }
            for item in transactions { try insertTransaction(item) }
            try bump(.title, floor: titles.map(\.id).max() ?? 0)
            try bump(.transaction, floor: transactions.map(\.id).max() ?? 0)
        }
    }

    func replaceAll(loans: [Loan], titles: [CashTitle], transactions: [CashTransaction]) throws {
        try transaction {
            try execute("DELETE FROM loans")
            try execute("DELETE FROM cash_transactions")
            try execute("DELETE FROM cash_titles")
            for loan in loans { try insertLoan(loan) }
            for title in titles { try insertTitle(title) }
            for item in transactions { try insertTransaction(item) }
            try bump(.loan, floor: loans.map(\.id).max() ?? 0)
            try bump(.title, floor: titles.map(\.id).max() ?? 0)
            try bump(.transaction, floor: transactions.map(\.id).max() ?? 0)
        }
    }

    func nextID(_ kind: RecordKind) throws -> Int64 {
        var issued: Int64 = 0
        try transaction {
            let current = max(try readMeta(kind.metaKey), try readMaxID(kind))
            issued = current + 1
            try writeMeta(kind.metaKey, issued)
        }
        return issued
    }

    func noteIDs(_ ids: [Int64], kind: RecordKind) throws {
        guard let maxID = ids.max() else { return }
        try transaction {
            try bump(kind, floor: maxID)
        }
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS loans (
            id INTEGER PRIMARY KEY,
            personName TEXT NOT NULL,
            phoneNumber TEXT,
            amount REAL NOT NULL,
            loanType TEXT NOT NULL,
            status TEXT NOT NULL,
            givenDate INTEGER NOT NULL,
            takenDate INTEGER NOT NULL,
            expectedReturnDate INTEGER NOT NULL,
            notes TEXT,
            imagePaths TEXT NOT NULL,
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL,
            isDeleted INTEGER NOT NULL,
            lastBackupTime INTEGER NOT NULL
        )
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS cash_titles (
            id INTEGER PRIMARY KEY,
            titleName TEXT NOT NULL,
            description TEXT,
            currentBalance REAL NOT NULL,
            createdAt INTEGER NOT NULL,
            lastBackupTime INTEGER NOT NULL
        )
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS cash_transactions (
            id INTEGER PRIMARY KEY,
            cashTitleId INTEGER NOT NULL,
            amount REAL NOT NULL,
            type TEXT NOT NULL,
            itemName TEXT,
            personName TEXT,
            notes TEXT,
            imageUri TEXT,
            createdAt INTEGER NOT NULL,
            lastBackupTime INTEGER NOT NULL
        )
        """)
        try execute("CREATE INDEX IF NOT EXISTS idx_cash_transactions_cashTitleId ON cash_transactions(cashTitleId)")
        try execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value INTEGER NOT NULL)")
    }

    private func seedHighWater() throws {
        try transaction {
            try bump(.loan, floor: try readMaxID(.loan))
            try bump(.title, floor: try readMaxID(.title))
            try bump(.transaction, floor: try readMaxID(.transaction))
        }
    }

    private func insertLoan(_ loan: Loan) throws {
        try run("""
        INSERT OR REPLACE INTO loans
        (id, personName, phoneNumber, amount, loanType, status, givenDate, takenDate, expectedReturnDate, notes, imagePaths, createdAt, updatedAt, isDeleted, lastBackupTime)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """) { statement in
            sqlite3_bind_int64(statement, 1, loan.id)
            bindText(statement, 2, loan.personName)
            bindText(statement, 3, loan.phoneNumber)
            sqlite3_bind_double(statement, 4, loan.amount)
            bindText(statement, 5, loan.loanType.rawValue)
            bindText(statement, 6, loan.status.rawValue)
            sqlite3_bind_int64(statement, 7, loan.givenDate ?? 0)
            sqlite3_bind_int64(statement, 8, loan.takenDate ?? 0)
            sqlite3_bind_int64(statement, 9, loan.expectedReturnDate ?? 0)
            bindText(statement, 10, loan.notes)
            bindText(statement, 11, try encodePaths(loan.imagePaths))
            sqlite3_bind_int64(statement, 12, loan.createdAt)
            sqlite3_bind_int64(statement, 13, loan.updatedAt)
            sqlite3_bind_int64(statement, 14, loan.isDeleted ? 1 : 0)
            sqlite3_bind_int64(statement, 15, loan.lastBackupTime)
        }
    }

    private func insertTitle(_ title: CashTitle) throws {
        try run("""
        INSERT OR REPLACE INTO cash_titles
        (id, titleName, description, currentBalance, createdAt, lastBackupTime)
        VALUES (?, ?, ?, ?, ?, ?)
        """) { statement in
            sqlite3_bind_int64(statement, 1, title.id)
            bindText(statement, 2, title.titleName)
            bindText(statement, 3, title.description)
            sqlite3_bind_double(statement, 4, title.currentBalance)
            sqlite3_bind_int64(statement, 5, title.createdAt)
            sqlite3_bind_int64(statement, 6, title.lastBackupTime)
        }
    }

    private func insertTransaction(_ transaction: CashTransaction) throws {
        try run("""
        INSERT OR REPLACE INTO cash_transactions
        (id, cashTitleId, amount, type, itemName, personName, notes, imageUri, createdAt, lastBackupTime)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """) { statement in
            sqlite3_bind_int64(statement, 1, transaction.id)
            sqlite3_bind_int64(statement, 2, transaction.cashTitleId)
            sqlite3_bind_double(statement, 3, transaction.amount)
            bindText(statement, 4, transaction.type.rawValue)
            bindText(statement, 5, transaction.itemName)
            bindText(statement, 6, transaction.personName)
            bindText(statement, 7, transaction.notes)
            bindText(statement, 8, transaction.imageUri)
            sqlite3_bind_int64(statement, 9, transaction.createdAt)
            sqlite3_bind_int64(statement, 10, transaction.lastBackupTime)
        }
    }

    private func queryLoans(_ sql: String) throws -> [Loan] {
        var loans: [Loan] = []
        try query(sql, bind: { _ in }, row: { statement in
            guard let personName = columnText(statement, 1),
                  let typeRaw = columnText(statement, 4),
                  let loanType = LoanType(rawValue: typeRaw),
                  let statusRaw = columnText(statement, 5),
                  let status = LoanStatus(rawValue: statusRaw),
                  let paths = columnText(statement, 10) else {
                throw AppError("A saved loan could not be read.")
            }
            loans.append(Loan(
                id: sqlite3_column_int64(statement, 0),
                personName: personName,
                phoneNumber: columnText(statement, 2),
                amount: sqlite3_column_double(statement, 3),
                loanType: loanType,
                status: status,
                givenDate: optionalDate(sqlite3_column_int64(statement, 6)),
                takenDate: optionalDate(sqlite3_column_int64(statement, 7)),
                expectedReturnDate: optionalDate(sqlite3_column_int64(statement, 8)),
                notes: columnText(statement, 9),
                imagePaths: try decodePaths(paths),
                createdAt: sqlite3_column_int64(statement, 11),
                updatedAt: sqlite3_column_int64(statement, 12),
                isDeleted: sqlite3_column_int64(statement, 13) != 0,
                lastBackupTime: sqlite3_column_int64(statement, 14)
            ))
        })
        return loans
    }

    private func queryTitles(_ sql: String) throws -> [CashTitle] {
        var titles: [CashTitle] = []
        try query(sql, bind: { _ in }, row: { statement in
            guard let name = columnText(statement, 1) else {
                throw AppError("A saved cash title could not be read.")
            }
            titles.append(CashTitle(
                id: sqlite3_column_int64(statement, 0),
                titleName: name,
                description: columnText(statement, 2),
                currentBalance: sqlite3_column_double(statement, 3),
                createdAt: sqlite3_column_int64(statement, 4),
                lastBackupTime: sqlite3_column_int64(statement, 5)
            ))
        })
        return titles
    }

    private func queryTransactions(_ sql: String) throws -> [CashTransaction] {
        var transactions: [CashTransaction] = []
        try query(sql, bind: { _ in }, row: { statement in
            guard let typeRaw = columnText(statement, 3), let type = TransactionType(rawValue: typeRaw) else {
                throw AppError("A saved transaction could not be read.")
            }
            transactions.append(CashTransaction(
                id: sqlite3_column_int64(statement, 0),
                cashTitleId: sqlite3_column_int64(statement, 1),
                amount: sqlite3_column_double(statement, 2),
                type: type,
                itemName: columnText(statement, 4),
                personName: columnText(statement, 5),
                notes: columnText(statement, 6),
                imageUri: columnText(statement, 7),
                createdAt: sqlite3_column_int64(statement, 8),
                lastBackupTime: sqlite3_column_int64(statement, 9)
            ))
        })
        return transactions
    }

    private func optionalDate(_ value: Int64) -> Int64? {
        value == 0 ? nil : value
    }

    private func encodePaths(_ paths: [String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: paths)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func decodePaths(_ value: String) throws -> [String] {
        guard let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String] else {
            throw AppError("Saved photo paths could not be read.")
        }
        return object
    }

    private func bump(_ kind: RecordKind, floor: Int64) throws {
        let current = try readMeta(kind.metaKey)
        if floor > current {
            try writeMeta(kind.metaKey, floor)
        }
    }

    private func readMeta(_ key: String) throws -> Int64 {
        var value: Int64 = 0
        try query("SELECT value FROM meta WHERE key = ?", bind: { statement in
            bindText(statement, 1, key)
        }, row: { statement in
            value = sqlite3_column_int64(statement, 0)
        })
        return value
    }

    private func writeMeta(_ key: String, _ value: Int64) throws {
        try run("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)") { statement in
            bindText(statement, 1, key)
            sqlite3_bind_int64(statement, 2, value)
        }
    }

    private func readMaxID(_ kind: RecordKind) throws -> Int64 {
        var value: Int64 = 0
        try query("SELECT IFNULL(MAX(id), 0) FROM \(kind.table)", bind: { _ in }, row: { statement in
            value = sqlite3_column_int64(statement, 0)
        })
        return value
    }

    private func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? databaseError()
            sqlite3_free(errorMessage)
            throw AppError(message)
        }
    }

    private func run(_ sql: String, bind: (OpaquePointer?) throws -> Void) throws {
        try query(sql, bind: bind, row: { _ in })
    }

    private func query(_ sql: String, bind: (OpaquePointer?) throws -> Void, row: (OpaquePointer?) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw AppError(databaseError())
        }
        defer { sqlite3_finalize(statement) }
        try bind(statement)
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                try row(statement)
            } else if step == SQLITE_DONE {
                return
            } else {
                throw AppError(databaseError())
            }
        }
    }

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, transient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL, let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private func databaseError() -> String {
        guard let handle else { return "The local database could not be used." }
        return String(cString: sqlite3_errmsg(handle))
    }
}
