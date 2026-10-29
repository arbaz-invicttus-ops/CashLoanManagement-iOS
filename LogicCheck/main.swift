import Foundation

var failures: [String] = []

func check(_ condition: Bool, _ message: String) {
    if !condition { failures.append(message) }
}

func sampleLoan(
    id: Int64,
    name: String = "Ayesha",
    amount: Double = 100,
    type: LoanType = .GIVEN,
    status: LoanStatus = .PENDING,
    updatedAt: Int64 = 10,
    deleted: Bool = false,
    expected: Int64? = nil
) -> Loan {
    Loan(
        id: id,
        personName: name,
        phoneNumber: "03001234567",
        amount: amount,
        loanType: type,
        status: status,
        givenDate: 1_700_000_000_000,
        takenDate: nil,
        expectedReturnDate: expected,
        notes: nil,
        imagePaths: [],
        createdAt: 1,
        updatedAt: updatedAt,
        isDeleted: deleted,
        lastBackupTime: 0
    )
}

let older = sampleLoan(id: 1, updatedAt: 10)
let newer = sampleLoan(id: 1, name: "Cloud", updatedAt: 11)
let same = sampleLoan(id: 1, name: "Cloud", updatedAt: 10)
let localOnly = sampleLoan(id: 2)
let deleted = sampleLoan(id: 3, updatedAt: 5, deleted: true)
let deletedCloud = sampleLoan(id: 3, name: "Newer", updatedAt: 6, deleted: true)
let cloudOnly = sampleLoan(id: 4, name: "From cloud")

let merged = CloudMerge.mergeLoans(local: [older, localOnly, deleted], cloud: [newer, cloudOnly, deletedCloud])
check(merged.first { $0.id == 1 }?.personName == "Cloud", "newer cloud loan should replace local")
check(merged.contains { $0.id == 2 }, "local-only loan should stay")
check(merged.contains { $0.id == 4 }, "cloud-only loan should be inserted")
check(merged.first { $0.id == 3 }?.personName == "Newer", "soft-deleted loans are compared by updatedAt")

let kept = CloudMerge.mergeLoans(local: [older], cloud: [same])
check(kept.first?.personName == "Ayesha", "equal updatedAt keeps the local loan")

let localTitle = CashTitle(id: 1, titleName: "Shop", description: nil, currentBalance: 999, createdAt: 1, lastBackupTime: 0)
let localTxn = CashTransaction(id: 5, cashTitleId: 1, amount: 40, type: .DEBIT, itemName: "Tea", personName: nil, notes: nil, imageUri: nil, createdAt: 2, lastBackupTime: 0)
let untouched = CloudMerge.mergeCash(localTitles: [localTitle], localTransactions: [localTxn], cloudTitles: [], cloudTransactions: [])
check(untouched == nil, "empty cloud cash must not change local cash")

let cloudTitle = CashTitle(id: 2, titleName: "Home", description: "", currentBalance: 1, createdAt: 3, lastBackupTime: 0)
let credit = CashTransaction(id: 8, cashTitleId: 2, amount: 100, type: .CREDIT, itemName: nil, personName: "Ali", notes: nil, imageUri: nil, createdAt: 4, lastBackupTime: 0)
let orphan = CashTransaction(id: 9, cashTitleId: 99, amount: 5, type: .CREDIT, itemName: nil, personName: nil, notes: nil, imageUri: nil, createdAt: 4, lastBackupTime: 0)
let zero = CashTransaction(id: 0, cashTitleId: 2, amount: 5, type: .CREDIT, itemName: nil, personName: nil, notes: nil, imageUri: nil, createdAt: 4, lastBackupTime: 0)
let cash = CloudMerge.mergeCash(localTitles: [localTitle], localTransactions: [localTxn], cloudTitles: [cloudTitle], cloudTransactions: [credit, orphan, zero])
check(cash?.titles.contains { $0.id == 1 } == true, "local title stays")
check(cash?.titles.contains { $0.id == 2 } == true, "cloud title is upserted")
check(cash?.transactions.contains { $0.id == 5 } == true, "local transaction stays")
check(cash?.transactions.contains { $0.id == 8 } == true, "cloud transaction is upserted")
check(cash?.transactions.contains { $0.id == 9 } == false, "transaction for a missing title is dropped")
check(cash?.transactions.contains { $0.id == 0 } == false, "transaction id 0 is dropped")
check(cash?.titles.first { $0.id == 1 }?.currentBalance == -40, "local title balance is recalculated")
check(cash?.titles.first { $0.id == 2 }?.currentBalance == 100, "cloud title balance is credits minus debits")

let summary = LoanMath.homeSummary(loans: [
    sampleLoan(id: 1, amount: 200, type: .GIVEN, status: .PENDING),
    sampleLoan(id: 2, amount: 50, type: .TAKEN, status: .PENDING),
    sampleLoan(id: 3, amount: 80, type: .GIVEN, status: .CLEARED),
    sampleLoan(id: 4, amount: 70, type: .GIVEN, status: .OVERDUE),
    sampleLoan(id: 5, amount: 90, type: .TAKEN, status: .PENDING, deleted: true),
])
check(summary.totalGiven == 270, "given total excludes cleared and deleted")
check(summary.totalTaken == 50, "taken total excludes deleted")
check(summary.net == 220, "net is given minus taken")
check(summary.pendingGiven == 1, "pending given ignores overdue")
check(summary.pendingTaken == 1, "pending taken counts exact pending")

let counts = LoanMath.counts(loans: summaryLoans())
check(counts.total == 4 && counts.cleared == 1 && counts.overdue == 1, "counts exclude deleted loans")

check(LoanSearch.matches(sampleLoan(id: 1), query: "aye", type: nil), "search matches name")
check(LoanSearch.matches(sampleLoan(id: 1), query: "0300", type: nil), "search matches phone")
check(!LoanSearch.matches(sampleLoan(id: 1, deleted: true), query: "", type: nil), "search hides deleted")
check(!LoanSearch.matches(sampleLoan(id: 1, type: .TAKEN), query: "", type: .GIVEN), "search respects type filter")

check(Money.parse("1,234.50") == 1234.5, "amount parses grouping")
check(Money.parse("0") == nil, "amount must be greater than 0")
check(Money.parse("PKR 10") == 10, "amount accepts a PKR prefix")
check(Format.money(1234.5) == "PKR 1,234.50", "money format")
check(Format.money(-10) == "PKR -10.00", "negative money format")
check(Money.fits(10, in: 10), "debit may equal the balance")
check(!Money.fits(10.01, in: 10), "debit cannot exceed the balance")

let today = Date()
let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
check(AppDate.isBeforeToday(AppDate.startOfDay(yesterday), now: today), "yesterday is overdue")
check(!AppDate.isBeforeToday(AppDate.startOfDay(today), now: today), "today is not overdue")
check(LoanRules.validate(personName: "  ", amount: 10, type: .GIVEN, givenDate: 1, takenDate: nil, expectedReturnDate: nil) != nil, "blank name is rejected")
check(LoanRules.validate(personName: "A", amount: 10, type: .GIVEN, givenDate: nil, takenDate: nil, expectedReturnDate: nil) != nil, "given date is required")
check(LoanRules.validate(personName: "A", amount: 10, type: .TAKEN, givenDate: nil, takenDate: nil, expectedReturnDate: nil) != nil, "taken date is required")
let given = AppDate.startOfDay(today)
let before = AppDate.startOfDay(yesterday)
check(LoanRules.validate(personName: "A", amount: 10, type: .GIVEN, givenDate: given, takenDate: nil, expectedReturnDate: before) != nil, "return date cannot be before the given date")
check(LoanRules.statusOnSave(isNew: true, current: nil, expectedReturnDate: before, now: today) == .OVERDUE, "past return date is overdue")
check(LoanRules.statusOnSave(isNew: true, current: nil, expectedReturnDate: AppDate.startOfDay(tomorrow), now: today) == .PENDING, "new future loan is pending")
check(LoanRules.statusOnSave(isNew: false, current: .CLEARED, expectedReturnDate: AppDate.startOfDay(tomorrow), now: today) == .CLEARED, "editing a cleared loan keeps cleared")
check(LoanRules.statusOnSave(isNew: false, current: .OVERDUE, expectedReturnDate: AppDate.startOfDay(tomorrow), now: today) == .PENDING, "a future date clears overdue")

var opened = sampleLoan(id: 1, expected: before)
opened.status = .PENDING
check(LoanRules.markedOverdueOnOpen(opened, now: today)?.status == .OVERDUE, "opening a pending past loan marks overdue")
opened.status = .CLEARED
check(LoanRules.markedOverdueOnOpen(opened, now: today) == nil, "opening a cleared loan does not change it")

check(PhoneLink.whatsAppDigits("03001234567") == "923001234567", "local Pakistani number gets country code")
check(PhoneLink.whatsAppDigits("+92 300 1234567") == "923001234567", "plus and spaces are removed")
check(PhoneLink.whatsAppDigits("00923001234567") == "923001234567", "00 prefix is removed")
check(PhoneLink.tel("0300")?.absoluteString == "tel:0300", "call link keeps the local number")

let loan = sampleLoan(id: 12, expected: 0)
var roundTrip = loan
roundTrip.phoneNumber = nil
roundTrip.notes = nil
roundTrip.expectedReturnDate = nil
let payload = RecordCodec.loanPayload(roundTrip)
check((payload["phoneNumber"] as? String) == "", "nil phone is stored as an empty string")
check((payload["expectedReturnDate"] as? NSNumber)?.int64Value == 0, "nil date is stored as 0")
let decoded = try RecordCodec.loan(from: payload)
check(decoded.phoneNumber == nil && decoded.expectedReturnDate == nil, "empty phone and 0 date decode as nil")
check(decoded.id == 12, "loan id round trips")

let doubleID: [String: Any] = [
    "id": NSNumber(value: 12.0),
    "personName": "A",
    "amount": NSNumber(value: 15),
    "loanType": "GIVEN",
    "status": "PENDING",
    "isDeleted": NSNumber(value: 0),
]
let fromDouble = try RecordCodec.loan(from: doubleID, documentID: "12")
check(fromDouble.id == 12 && fromDouble.amount == 15 && fromDouble.isDeleted == false, "numbers may arrive as integers or doubles")

let fileData = try BackupFile.encode(loans: [roundTrip], titles: [localTitle], transactions: [localTxn])
if case .full(let loans, let titles, let transactions) = try BackupFile.decode(fileData) {
    check(loans == [roundTrip] && titles.count == 1 && transactions.count == 1, "version 2 file round trips")
} else {
    check(false, "version 2 file should decode as a full backup")
}

let loansOnly = try JSONSerialization.data(withJSONObject: [RecordCodec.loanPayload(roundTrip)])
if case .loansOnly(let loans) = try BackupFile.decode(loansOnly) {
    check(loans.count == 1, "an older file is a loan array")
} else {
    check(false, "loan array should decode as loans only")
}

let applied = BackupFile.applying(.loansOnly([cloudOnly]), to: CloudSnapshot(loans: [older], titles: [localTitle], transactions: [localTxn]))
check(applied.loans == [cloudOnly] && applied.titles == [localTitle], "loan-only restore replaces loans and keeps cash")

let full = BackupFile.applying(
    .full(loans: [], titles: [cloudTitle], transactions: [credit]),
    to: CloudSnapshot(loans: [older], titles: [localTitle], transactions: [localTxn])
)
check(full.loans.isEmpty && full.titles.first?.currentBalance == 100, "version 2 restore replaces cash and recalculates")

let database = try Database(path: ":memory:")
let first = try database.nextID(.loan)
let second = try database.nextID(.loan)
check(first == 1 && second == 2, "ids start at 1 and increase")
try database.saveLoan(sampleLoan(id: second))
try database.deleteLoan(id: second)
let third = try database.nextID(.loan)
check(third == 3, "deleting the highest id does not reuse it")
try database.noteIDs([50], kind: .loan)
let afterCloud = try database.nextID(.loan)
check(afterCloud == 51, "the next id is above the last cloud snapshot")

let title = CashTitle(id: try database.nextID(.title), titleName: "Drawer", description: nil, currentBalance: 0, createdAt: 1, lastBackupTime: 0)
try database.saveTitle(title)
let txn = CashTransaction(id: try database.nextID(.transaction), cashTitleId: title.id, amount: 20, type: .CREDIT, itemName: nil, personName: "Sara", notes: "", imageUri: nil, createdAt: 2, lastBackupTime: 0)
try database.saveTransaction(txn)
try database.deleteTitle(id: title.id)
let remainingTitles = try database.titles()
let remainingTransactions = try database.transactions()
check(remainingTitles.isEmpty && remainingTransactions.isEmpty, "deleting a title deletes its transactions")

let stored = try database.loans()
check(stored.isEmpty, "deleted loan row is gone")
try database.saveLoan(roundTrip)
let loaded = try database.loans()
check(loaded == [roundTrip], "loan round trips through sqlite")

func summaryLoans() -> [Loan] {
    [
        sampleLoan(id: 1, amount: 200, type: .GIVEN, status: .PENDING),
        sampleLoan(id: 2, amount: 50, type: .TAKEN, status: .PENDING),
        sampleLoan(id: 3, amount: 80, type: .GIVEN, status: .CLEARED),
        sampleLoan(id: 4, amount: 70, type: .GIVEN, status: .OVERDUE),
        sampleLoan(id: 5, amount: 90, type: .TAKEN, status: .PENDING, deleted: true),
    ]
}

if failures.isEmpty {
    print("All logic checks passed")
} else {
    for failure in failures { print("FAIL \(failure)") }
    exit(1)
}
