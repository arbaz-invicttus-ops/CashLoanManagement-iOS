import Foundation

nonisolated struct AppError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

nonisolated enum LoanType: String, Codable, CaseIterable {
    case GIVEN
    case TAKEN

    var title: String {
        switch self {
        case .GIVEN: "Given"
        case .TAKEN: "Taken"
        }
    }
}

nonisolated enum LoanStatus: String, Codable, CaseIterable {
    case PENDING
    case CLEARED
    case OVERDUE

    var title: String {
        switch self {
        case .PENDING: "Pending"
        case .CLEARED: "Cleared"
        case .OVERDUE: "Overdue"
        }
    }
}

nonisolated enum TransactionType: String, Codable, CaseIterable {
    case CREDIT
    case DEBIT

    var title: String {
        switch self {
        case .CREDIT: "Added"
        case .DEBIT: "Spent"
        }
    }
}

nonisolated struct Loan: Identifiable, Equatable {
    var id: Int64
    var personName: String
    var phoneNumber: String?
    var amount: Double
    var loanType: LoanType
    var status: LoanStatus
    var givenDate: Int64?
    var takenDate: Int64?
    var expectedReturnDate: Int64?
    var notes: String?
    var imagePaths: [String]
    var createdAt: Int64
    var updatedAt: Int64
    var isDeleted: Bool
    var lastBackupTime: Int64

    var primaryDate: Int64? {
        loanType == .GIVEN ? givenDate : takenDate
    }
}

nonisolated struct CashTitle: Identifiable, Equatable {
    var id: Int64
    var titleName: String
    var description: String?
    var currentBalance: Double
    var createdAt: Int64
    var lastBackupTime: Int64
}

nonisolated struct CashTransaction: Identifiable, Equatable {
    var id: Int64
    var cashTitleId: Int64
    var amount: Double
    var type: TransactionType
    var itemName: String?
    var personName: String?
    var notes: String?
    var imageUri: String?
    var createdAt: Int64
    var lastBackupTime: Int64

    var headline: String {
        switch type {
        case .CREDIT:
            return personName ?? "Money added"
        case .DEBIT:
            return itemName ?? "Spending"
        }
    }
}

nonisolated struct LoanDraft: Equatable {
    var personName: String
    var phoneNumber: String
    var amountText: String
    var loanType: LoanType
    var givenDate: Int64?
    var takenDate: Int64?
    var expectedReturnDate: Int64?
    var notes: String
    var imagePaths: [String]
}

nonisolated struct HomeSummary: Equatable {
    var totalGiven: Double
    var totalTaken: Double
    var net: Double
    var pendingGiven: Int
    var pendingTaken: Int
}

nonisolated struct LoanCounts: Equatable {
    var total: Int
    var cleared: Int
    var overdue: Int
}

nonisolated enum AppDate {
    static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func date(from millis: Int64?) -> Date? {
        guard let millis, millis != 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }

    static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Int64 {
        millis(calendar.startOfDay(for: date))
    }

    static func day(_ millis: Int64, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(millis) / 1000))
    }

    /// A due date is overdue once that calendar day is before today.
    /// The stored value is the start of the chosen day, so a timestamp compare
    /// against "now" would mark a loan overdue on the morning it is due.
    static func isBeforeToday(_ millis: Int64?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let millis, millis != 0 else { return false }
        return day(millis, calendar: calendar) < calendar.startOfDay(for: now)
    }

    static func isOnOrAfter(_ millis: Int64, anchor: Int64, calendar: Calendar = .current) -> Bool {
        day(millis, calendar: calendar) >= day(anchor, calendar: calendar)
    }
}

nonisolated enum Money {
    static func parse(_ text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "PKR", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard var decimal = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")), decimal > 0 else {
            return nil
        }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &decimal, 2, .plain)
        let value = NSDecimalNumber(decimal: rounded).doubleValue
        guard value.isFinite, cents(value) > 0 else { return nil }
        return value
    }

    static func cents(_ value: Double) -> Int64 {
        var decimal = Decimal(value) * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &decimal, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    static func fits(_ amount: Double, in balance: Double) -> Bool {
        cents(amount) > 0 && cents(amount) <= cents(balance)
    }
}

nonisolated enum Format {
    static func money(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.groupingSize = 3
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let body = formatter.string(from: NSNumber(value: amount)) ?? "0.00"
        return "PKR \(body)"
    }

    static func date(_ millis: Int64?) -> String {
        guard let date = AppDate.date(from: millis) else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date)
    }
}

nonisolated enum TextValue {
    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func optional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = trimmed(value)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated enum LoanRules {
    static func validate(personName: String, amount: Double, type: LoanType, givenDate: Int64?, takenDate: Int64?, expectedReturnDate: Int64?) -> String? {
        if TextValue.trimmed(personName).isEmpty {
            return "Name is required."
        }
        if !amount.isFinite || Money.cents(amount) <= 0 {
            return "Amount must be greater than 0."
        }
        switch type {
        case .GIVEN:
            guard let givenDate, givenDate != 0 else { return "Given date is required." }
            if let expectedReturnDate, expectedReturnDate != 0, !AppDate.isOnOrAfter(expectedReturnDate, anchor: givenDate) {
                return "Expected return date must be on or after the given date."
            }
        case .TAKEN:
            guard let takenDate, takenDate != 0 else { return "Taken date is required." }
            if let expectedReturnDate, expectedReturnDate != 0, !AppDate.isOnOrAfter(expectedReturnDate, anchor: takenDate) {
                return "Expected return date must be on or after the taken date."
            }
        }
        return nil
    }

    static func statusOnSave(isNew: Bool, current: LoanStatus?, expectedReturnDate: Int64?, now: Date = Date()) -> LoanStatus {
        if AppDate.isBeforeToday(expectedReturnDate, now: now) {
            return .OVERDUE
        }
        if isNew || current == .OVERDUE || current == nil {
            return .PENDING
        }
        return current ?? .PENDING
    }

    static func markedOverdueOnOpen(_ loan: Loan, now: Date = Date()) -> Loan? {
        guard !loan.isDeleted, loan.status == .PENDING, AppDate.isBeforeToday(loan.expectedReturnDate, now: now) else {
            return nil
        }
        var copy = loan
        copy.status = .OVERDUE
        copy.updatedAt = AppDate.millis(now)
        return copy
    }
}

nonisolated enum CashRules {
    static func validateTitleName(_ name: String) -> String? {
        TextValue.trimmed(name).isEmpty ? "Title name is required." : nil
    }

    static func validateCredit(amount: Double) -> String? {
        amount.isFinite && Money.cents(amount) > 0 ? nil : "Amount must be greater than 0."
    }

    static func validateDebit(amount: Double, balance: Double) -> String? {
        if let message = validateCredit(amount: amount) { return message }
        if !Money.fits(amount, in: balance) {
            return "Amount is more than the current balance."
        }
        return nil
    }
}

nonisolated enum LoanMath {
    static func homeSummary(loans: [Loan]) -> HomeSummary {
        let open = loans.filter { !$0.isDeleted && $0.status != .CLEARED }
        let given = open.filter { $0.loanType == .GIVEN }
        let taken = open.filter { $0.loanType == .TAKEN }
        let totalGiven = given.reduce(0) { $0 + $1.amount }
        let totalTaken = taken.reduce(0) { $0 + $1.amount }
        return HomeSummary(
            totalGiven: totalGiven,
            totalTaken: totalTaken,
            net: totalGiven - totalTaken,
            pendingGiven: given.filter { $0.status == .PENDING }.count,
            pendingTaken: taken.filter { $0.status == .PENDING }.count
        )
    }

    static func counts(loans: [Loan]) -> LoanCounts {
        let active = loans.filter { !$0.isDeleted }
        return LoanCounts(
            total: active.count,
            cleared: active.filter { $0.status == .CLEARED }.count,
            overdue: active.filter { $0.status == .OVERDUE }.count
        )
    }
}

nonisolated enum LoanSearch {
    static func matches(_ loan: Loan, query: String, type: LoanType?) -> Bool {
        guard !loan.isDeleted else { return false }
        if let type, loan.loanType != type { return false }
        let trimmed = TextValue.trimmed(query)
        guard !trimmed.isEmpty else { return true }
        if loan.personName.localizedCaseInsensitiveContains(trimmed) { return true }
        if let phone = loan.phoneNumber, phone.localizedCaseInsensitiveContains(trimmed) { return true }
        return false
    }
}

nonisolated enum PhoneLink {
    static func tel(_ raw: String) -> URL? {
        var filtered = raw.filter { $0.isNumber || $0 == "+" }
        if let plus = filtered.firstIndex(of: "+") {
            filtered.remove(at: plus)
            filtered.insert("+", at: filtered.startIndex)
            filtered = "+" + filtered.filter(\.isNumber)
        }
        guard filtered.contains(where: \.isNumber) else { return nil }
        return URL(string: "tel:\(filtered)")
    }

    static func whatsAppDigits(_ raw: String) -> String? {
        var digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        if digits.hasPrefix("00") { digits.removeFirst(2) }
        if digits.hasPrefix("0") { digits = "92" + digits.dropFirst() }
        guard !digits.isEmpty else { return nil }
        return digits
    }

    static func whatsApp(_ raw: String) -> URL? {
        guard let digits = whatsAppDigits(raw) else { return nil }
        return URL(string: "https://wa.me/\(digits)")
    }
}
