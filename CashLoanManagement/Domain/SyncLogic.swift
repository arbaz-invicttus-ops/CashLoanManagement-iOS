import Foundation

nonisolated enum FlexibleNumber {
    static func int64(_ value: Any?) -> Int64? {
        if let string = value as? String { return Int64(string) }
        guard let number = number(value) else { return nil }
        return number.int64Value
    }

    static func double(_ value: Any?) -> Double? {
        if let string = value as? String { return Double(string) }
        guard let number = number(value) else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }

    private static func number(_ value: Any?) -> NSNumber? {
        guard let value, !isBoolean(value) else { return nil }
        return value as? NSNumber
    }

    private static func isBoolean(_ value: Any) -> Bool {
        guard let object = value as? NSObject else { return false }
        return CFGetTypeID(object) == CFBooleanGetTypeID()
    }
}

nonisolated enum FieldCodec {
    static func optionalString(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    static func optionalDate(_ value: Any?) -> Int64? {
        guard let number = FlexibleNumber.int64(value), number != 0 else { return nil }
        return number
    }

    static func bool(_ value: Any?, default defaultValue: Bool = false) -> Bool {
        guard let value else { return defaultValue }
        if let object = value as? NSObject, CFGetTypeID(object) == CFBooleanGetTypeID() {
            return (value as? Bool) ?? defaultValue
        }
        if let number = value as? NSNumber {
            return number.intValue != 0
        }
        return defaultValue
    }

    static func stringList(_ value: Any?) -> [String] {
        if let values = value as? [String] { return values }
        if let values = value as? [Any] { return values.compactMap { $0 as? String } }
        return []
    }

    static func storedString(_ value: String?) -> String { value ?? "" }
    static func storedDate(_ value: Int64?) -> NSNumber { NSNumber(value: value ?? 0) }
    static func storedInt(_ value: Int64) -> NSNumber { NSNumber(value: value) }
}

nonisolated enum RecordCodec {
    static func loanPayload(_ loan: Loan) -> [String: Any] {
        [
            "id": FieldCodec.storedInt(loan.id),
            "personName": loan.personName,
            "phoneNumber": FieldCodec.storedString(loan.phoneNumber),
            "amount": loan.amount,
            "loanType": loan.loanType.rawValue,
            "status": loan.status.rawValue,
            "givenDate": FieldCodec.storedDate(loan.givenDate),
            "takenDate": FieldCodec.storedDate(loan.takenDate),
            "expectedReturnDate": FieldCodec.storedDate(loan.expectedReturnDate),
            "notes": FieldCodec.storedString(loan.notes),
            "imagePaths": loan.imagePaths,
            "createdAt": FieldCodec.storedInt(loan.createdAt),
            "updatedAt": FieldCodec.storedInt(loan.updatedAt),
            "isDeleted": loan.isDeleted,
            "lastBackupTime": FieldCodec.storedInt(loan.lastBackupTime),
        ]
    }

    static func titlePayload(_ title: CashTitle) -> [String: Any] {
        [
            "id": FieldCodec.storedInt(title.id),
            "titleName": title.titleName,
            "description": FieldCodec.storedString(title.description),
            "currentBalance": title.currentBalance,
            "createdAt": FieldCodec.storedInt(title.createdAt),
            "lastBackupTime": FieldCodec.storedInt(title.lastBackupTime),
        ]
    }

    static func transactionPayload(_ transaction: CashTransaction) -> [String: Any] {
        [
            "id": FieldCodec.storedInt(transaction.id),
            "cashTitleId": FieldCodec.storedInt(transaction.cashTitleId),
            "amount": transaction.amount,
            "type": transaction.type.rawValue,
            "itemName": FieldCodec.storedString(transaction.itemName),
            "personName": FieldCodec.storedString(transaction.personName),
            "notes": FieldCodec.storedString(transaction.notes),
            "imageUri": FieldCodec.storedString(transaction.imageUri),
            "createdAt": FieldCodec.storedInt(transaction.createdAt),
            "lastBackupTime": FieldCodec.storedInt(transaction.lastBackupTime),
        ]
    }

    static func loan(from data: [String: Any], documentID: String? = nil) throws -> Loan {
        let id = try identifier(data, documentID: documentID, label: "loan")
        guard let personName = data["personName"] as? String, !TextValue.trimmed(personName).isEmpty else {
            throw AppError("A loan is missing a name.")
        }
        guard let amount = FlexibleNumber.double(data["amount"]) else {
            throw AppError("A loan is missing an amount.")
        }
        guard let typeRaw = data["loanType"] as? String, let loanType = LoanType(rawValue: typeRaw) else {
            throw AppError("A loan has an unknown type.")
        }
        guard let statusRaw = data["status"] as? String, let status = LoanStatus(rawValue: statusRaw) else {
            throw AppError("A loan has an unknown status.")
        }
        return Loan(
            id: id,
            personName: personName,
            phoneNumber: FieldCodec.optionalString(data["phoneNumber"]),
            amount: amount,
            loanType: loanType,
            status: status,
            givenDate: FieldCodec.optionalDate(data["givenDate"]),
            takenDate: FieldCodec.optionalDate(data["takenDate"]),
            expectedReturnDate: FieldCodec.optionalDate(data["expectedReturnDate"]),
            notes: FieldCodec.optionalString(data["notes"]),
            imagePaths: FieldCodec.stringList(data["imagePaths"]),
            createdAt: FlexibleNumber.int64(data["createdAt"]) ?? 0,
            updatedAt: FlexibleNumber.int64(data["updatedAt"]) ?? 0,
            isDeleted: FieldCodec.bool(data["isDeleted"]),
            lastBackupTime: FlexibleNumber.int64(data["lastBackupTime"]) ?? 0
        )
    }

    static func title(from data: [String: Any], documentID: String? = nil) throws -> CashTitle {
        let id = try identifier(data, documentID: documentID, label: "cash title")
        guard let titleName = data["titleName"] as? String, !TextValue.trimmed(titleName).isEmpty else {
            throw AppError("A cash title is missing a name.")
        }
        guard let balance = FlexibleNumber.double(data["currentBalance"]) else {
            throw AppError("A cash title is missing a balance.")
        }
        return CashTitle(
            id: id,
            titleName: titleName,
            description: FieldCodec.optionalString(data["description"]),
            currentBalance: balance,
            createdAt: FlexibleNumber.int64(data["createdAt"]) ?? 0,
            lastBackupTime: FlexibleNumber.int64(data["lastBackupTime"]) ?? 0
        )
    }

    static func transaction(from data: [String: Any], documentID: String? = nil) throws -> CashTransaction {
        let id = try identifier(data, documentID: documentID, label: "transaction")
        guard let titleID = FlexibleNumber.int64(data["cashTitleId"]) else {
            throw AppError("A transaction is missing its cash title.")
        }
        guard let amount = FlexibleNumber.double(data["amount"]) else {
            throw AppError("A transaction is missing an amount.")
        }
        guard let typeRaw = data["type"] as? String, let type = TransactionType(rawValue: typeRaw) else {
            throw AppError("A transaction has an unknown type.")
        }
        return CashTransaction(
            id: id,
            cashTitleId: titleID,
            amount: amount,
            type: type,
            itemName: FieldCodec.optionalString(data["itemName"]),
            personName: FieldCodec.optionalString(data["personName"]),
            notes: FieldCodec.optionalString(data["notes"]),
            imageUri: FieldCodec.optionalString(data["imageUri"]),
            createdAt: FlexibleNumber.int64(data["createdAt"]) ?? 0,
            lastBackupTime: FlexibleNumber.int64(data["lastBackupTime"]) ?? 0
        )
    }

    private static func identifier(_ data: [String: Any], documentID: String?, label: String) throws -> Int64 {
        if let id = FlexibleNumber.int64(data["id"]) { return id }
        if let documentID, let id = Int64(documentID) { return id }
        throw AppError("A \(label) is missing its id.")
    }
}

nonisolated struct CloudSnapshot: Equatable {
    var loans: [Loan]
    var titles: [CashTitle]
    var transactions: [CashTransaction]
}

nonisolated enum CloudMerge {
    static func mergeLoans(local: [Loan], cloud: [Loan]) -> [Loan] {
        var byID: [Int64: Loan] = [:]
        for loan in local {
            byID[loan.id] = loan
        }
        for loan in cloud {
            if let existing = byID[loan.id] {
                if loan.updatedAt > existing.updatedAt {
                    byID[loan.id] = loan
                }
            } else {
                byID[loan.id] = loan
            }
        }
        return byID.values.sorted { $0.id < $1.id }
    }

    static func balance(for titleID: Int64, transactions: [CashTransaction]) -> Double {
        transactions.reduce(0) { partial, transaction in
            guard transaction.cashTitleId == titleID else { return partial }
            switch transaction.type {
            case .CREDIT: return partial + transaction.amount
            case .DEBIT: return partial - transaction.amount
            }
        }
    }

    static func recalculated(_ titles: [CashTitle], transactions: [CashTransaction]) -> [CashTitle] {
        titles.map { title in
            var copy = title
            copy.currentBalance = balance(for: title.id, transactions: transactions)
            return copy
        }
    }

    /// An empty cloud cash snapshot must not wipe titles that only exist on this phone.
    static func mergeCash(localTitles: [CashTitle], localTransactions: [CashTransaction], cloudTitles: [CashTitle], cloudTransactions: [CashTransaction]) -> CloudSnapshot? {
        if cloudTitles.isEmpty && cloudTransactions.isEmpty {
            return nil
        }
        var titles: [Int64: CashTitle] = [:]
        for title in localTitles { titles[title.id] = title }
        for title in cloudTitles { titles[title.id] = title }

        let titleIDs = Set(titles.keys)
        var transactions: [Int64: CashTransaction] = [:]
        for transaction in localTransactions { transactions[transaction.id] = transaction }
        for transaction in cloudTransactions where transaction.id > 0 && titleIDs.contains(transaction.cashTitleId) {
            transactions[transaction.id] = transaction
        }

        let mergedTransactions = Array(transactions.values)
        let mergedTitles = recalculated(Array(titles.values), transactions: mergedTransactions)
        return CloudSnapshot(loans: [], titles: mergedTitles, transactions: mergedTransactions)
    }

    static func applying(local: CloudSnapshot, cloud: CloudSnapshot) -> CloudSnapshot {
        let loans = mergeLoans(local: local.loans, cloud: cloud.loans)
        if let cash = mergeCash(
            localTitles: local.titles,
            localTransactions: local.transactions,
            cloudTitles: cloud.titles,
            cloudTransactions: cloud.transactions
        ) {
            return CloudSnapshot(loans: loans, titles: cash.titles, transactions: cash.transactions)
        }
        return CloudSnapshot(loans: loans, titles: local.titles, transactions: local.transactions)
    }
}

nonisolated enum DecodedBackup: Equatable {
    case loansOnly([Loan])
    case full(loans: [Loan], titles: [CashTitle], transactions: [CashTransaction])
}

nonisolated enum BackupFile {
    static func encode(loans: [Loan], titles: [CashTitle], transactions: [CashTransaction]) throws -> Data {
        let object: [String: Any] = [
            "version": NSNumber(value: 2),
            "loans": loans.map(RecordCodec.loanPayload),
            "cashTitles": titles.map(RecordCodec.titlePayload),
            "cashTransactions": transactions.map(RecordCodec.transactionPayload),
        ]
        guard JSONSerialization.isValidJSONObject(object) else {
            throw AppError("The backup could not be written.")
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }

    static func decode(_ data: Data) throws -> DecodedBackup {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AppError("This backup file could not be read.")
        }
        if let loans = json as? [Any] {
            return .loansOnly(try decodeLoans(loans))
        }
        guard let object = json as? [String: Any] else {
            throw AppError("This backup file could not be read.")
        }
        let loans = try decodeLoans(object["loans"] as? [Any] ?? [])
        let version = FlexibleNumber.int64(object["version"]) ?? 0
        if version >= 2 {
            let titles = try decodeTitles(object["cashTitles"] as? [Any] ?? [])
            let transactions = try decodeTransactions(object["cashTransactions"] as? [Any] ?? [])
            return .full(loans: loans, titles: titles, transactions: transactions)
        }
        if object["loans"] != nil {
            return .loansOnly(loans)
        }
        throw AppError("This backup file could not be read.")
    }

    static func applying(_ backup: DecodedBackup, to local: CloudSnapshot) -> CloudSnapshot {
        switch backup {
        case .loansOnly(let loans):
            return CloudSnapshot(loans: loans, titles: local.titles, transactions: local.transactions)
        case .full(let loans, let titles, let transactions):
            return CloudSnapshot(
                loans: loans,
                titles: CloudMerge.recalculated(titles, transactions: transactions),
                transactions: transactions
            )
        }
    }

    private static func decodeLoans(_ values: [Any]) throws -> [Loan] {
        var loans: [Loan] = []
        for value in values {
            guard let data = value as? [String: Any] else { throw AppError("A loan in the backup could not be read.") }
            loans.append(try RecordCodec.loan(from: data))
        }
        try requireUniqueIDs(loans.map(\.id), label: "loans")
        return loans
    }

    private static func decodeTitles(_ values: [Any]) throws -> [CashTitle] {
        var titles: [CashTitle] = []
        for value in values {
            guard let data = value as? [String: Any] else { throw AppError("A cash title in the backup could not be read.") }
            titles.append(try RecordCodec.title(from: data))
        }
        try requireUniqueIDs(titles.map(\.id), label: "cash titles")
        return titles
    }

    private static func decodeTransactions(_ values: [Any]) throws -> [CashTransaction] {
        var transactions: [CashTransaction] = []
        for value in values {
            guard let data = value as? [String: Any] else { throw AppError("A transaction in the backup could not be read.") }
            transactions.append(try RecordCodec.transaction(from: data))
        }
        try requireUniqueIDs(transactions.map(\.id), label: "transactions")
        return transactions
    }

    private static func requireUniqueIDs(_ ids: [Int64], label: String) throws {
        if Set(ids).count != ids.count {
            throw AppError("The backup contains two \(label) with the same id.")
        }
    }
}
