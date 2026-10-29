import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct LoanListView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""
    @State private var filter = LoanListFilter.all

    private var rows: [Loan] {
        store.loans.filter { LoanSearch.matches($0, query: query, type: filter.type) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(LoanListFilter.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if rows.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No loans" : "No matches",
                    systemImage: "tray",
                    description: Text(query.isEmpty ? "Add a loan from the home screen." : "Try another name or phone number.")
                )
            } else {
                List(rows) { loan in
                    NavigationLink(value: Route.loanDetail(loan.id)) {
                        LoanRow(loan: loan)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("All Loans")
        .searchable(text: $query, prompt: "Name or phone")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.deletedLoans) {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Deleted loans")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Route.addLoan) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add loan")
            }
        }
    }
}

struct LoanRow: View {
    let loan: Loan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(loan.personName)
                    .font(.body.weight(.semibold))
                Spacer()
                Text(Format.money(loan.amount))
                    .font(.body.weight(.semibold))
            }
            HStack(spacing: 8) {
                TypeBadge(type: loan.loanType)
                StatusBadge(status: loan.status)
                Spacer()
                Text(Format.date(loan.primaryDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let phone = loan.phoneNumber {
                Text(phone)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct LoanDetailView: View {
    let loanID: Int64
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var message: String?
    @State private var confirmDelete = false

    private var loan: Loan? { store.loan(id: loanID) }

    var body: some View {
        Group {
            if let loan {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(loan.personName)
                                .font(.title2.weight(.bold))
                            Text(Format.money(loan.amount))
                                .font(.title.weight(.bold))
                                .foregroundStyle(loan.loanType == .GIVEN ? Color.accentColor : .orange)
                            HStack {
                                TypeBadge(type: loan.loanType)
                                StatusBadge(status: loan.status)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Section("Contact") {
                        if let phone = loan.phoneNumber {
                            Text(phone).textSelection(.enabled)
                        } else {
                            Text("No phone number")
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            guard let phone = loan.phoneNumber, let url = PhoneLink.tel(phone) else { return }
                            openURL(url)
                        } label: {
                            Label("Call", systemImage: "phone")
                        }
                        .disabled(loan.phoneNumber == nil)
                        Button {
                            guard let phone = loan.phoneNumber, let url = PhoneLink.whatsApp(phone) else { return }
                            openURL(url)
                        } label: {
                            Label("WhatsApp", systemImage: "message")
                        }
                        .disabled(loan.phoneNumber == nil)
                    }
                    Section("Dates") {
                        LabeledContent("Given", value: Format.date(loan.givenDate))
                        LabeledContent("Taken", value: Format.date(loan.takenDate))
                        LabeledContent("Expected return", value: Format.date(loan.expectedReturnDate))
                    }
                    if let notes = loan.notes {
                        Section("Notes") { Text(notes) }
                    }
                    if !loan.imagePaths.isEmpty {
                        Section("Photos") { PhotoStrip(paths: loan.imagePaths) }
                    }
                    Section {
                        if loan.status != .CLEARED {
                            Button("Mark cleared") { update(.CLEARED) }
                        }
                        if loan.status != .PENDING {
                            Button("Mark pending") { update(.PENDING) }
                        }
                        Button("Delete loan", role: .destructive) { confirmDelete = true }
                    }
                }
                .navigationTitle("Loan")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: Route.editLoan(loan.id)) {
                            Text("Edit")
                        }
                    }
                }
                .confirmationDialog("Delete this loan?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { softDelete() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("It will be hidden from the active list. You can recover it from deleted loans. The cloud copy stays until a backup overwrites that same id.")
                }
            } else {
                ContentUnavailableView("Loan unavailable", systemImage: "doc", description: Text("This loan is no longer on this iPhone."))
            }
        }
        .task(id: loanID) {
            do { try store.markOverdueIfNeeded(id: loanID) }
            catch { message = error.localizedDescription }
        }
        .errorAlert($message)
    }

    private func update(_ status: LoanStatus) {
        do { try store.setStatus(id: loanID, status: status) }
        catch { message = error.localizedDescription }
    }

    private func softDelete() {
        do {
            try store.softDelete(id: loanID)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

struct DeletedLoansView: View {
    @Environment(AppStore.self) private var store
    @State private var message: String?
    @State private var pendingPermanent: Loan?

    var body: some View {
        Group {
            if store.deletedLoans.isEmpty {
                ContentUnavailableView("No deleted loans", systemImage: "trash", description: Text("Loans you delete can be recovered here."))
            } else {
                List(store.deletedLoans) { loan in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(loan.personName).font(.body.weight(.semibold))
                            Spacer()
                            Text(Format.money(loan.amount))
                        }
                        HStack {
                            TypeBadge(type: loan.loanType)
                            StatusBadge(status: loan.status)
                        }
                        HStack {
                            Button("Recover") {
                                do { try store.recover(id: loan.id) }
                                catch { message = error.localizedDescription }
                            }
                            Spacer()
                            Button("Delete permanently", role: .destructive) {
                                pendingPermanent = loan
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Deleted Loans")
        .confirmationDialog(
            "Permanently delete this loan?",
            isPresented: Binding(get: { pendingPermanent != nil }, set: { if !$0 { pendingPermanent = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete permanently", role: .destructive) {
                guard let loan = pendingPermanent else { return }
                do { try store.permanentlyDelete(id: loan.id) }
                catch { message = error.localizedDescription }
                pendingPermanent = nil
            }
            Button("Cancel", role: .cancel) { pendingPermanent = nil }
        } message: {
            Text("This removes the loan from this iPhone. It does not delete the cloud copy.")
        }
        .errorAlert($message)
    }
}

struct LoanFormView: View {
    let loanID: Int64?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var personName = ""
    @State private var phone = ""
    @State private var amountText = ""
    @State private var loanType = LoanType.GIVEN
    @State private var givenDate = Date()
    @State private var takenDate = Date()
    @State private var includeGiven = false
    @State private var includeTaken = false
    @State private var expectedDate = Date()
    @State private var includeExpected = false
    @State private var notes = ""
    @State private var imagePaths: [String] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var didLoad = false
    @State private var message: String?

    private var existing: Loan? {
        guard let loanID else { return nil }
        return store.anyLoan(id: loanID)
    }

    var body: some View {
        Group {
            if loanID != nil && (existing == nil || existing?.isDeleted == true) {
                ContentUnavailableView("Loan unavailable", systemImage: "doc", description: Text("This loan is no longer on this iPhone."))
            } else {
                form
            }
        }
    }

    private var form: some View {
        Form {
            Section("Person") {
                TextField("Name", text: $personName)
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }
            Section("Amount") {
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                Picker("Type", selection: $loanType) {
                    Text("Given").tag(LoanType.GIVEN)
                    Text("Taken").tag(LoanType.TAKEN)
                }
                .pickerStyle(.segmented)
            }
            Section("Dates") {
                if loanType == .GIVEN {
                    DatePicker("Given date", selection: $givenDate, displayedComponents: .date)
                } else {
                    Toggle("Given date", isOn: $includeGiven)
                    if includeGiven {
                        DatePicker("Given date", selection: $givenDate, displayedComponents: .date)
                    }
                }
                if loanType == .TAKEN {
                    DatePicker("Taken date", selection: $takenDate, displayedComponents: .date)
                } else {
                    Toggle("Taken date", isOn: $includeTaken)
                    if includeTaken {
                        DatePicker("Taken date", selection: $takenDate, displayedComponents: .date)
                    }
                }
                Toggle("Expected return date", isOn: $includeExpected)
                if includeExpected {
                    DatePicker("Expected return", selection: $expectedDate, displayedComponents: .date)
                }
            }
            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section("Photos") {
                if !imagePaths.isEmpty {
                    PhotoStrip(paths: imagePaths) { path in
                        imagePaths.removeAll { $0 == path }
                        if existing?.imagePaths.contains(path) != true {
                            ImageStore.deleteIfOwned(path)
                        }
                    }
                }
                if imagePaths.count < 8 {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 8 - imagePaths.count, matching: .images) {
                        Label("Add photos", systemImage: "photo.on.rectangle")
                    }
                }
            }
            if let preview = statusPreview {
                Section {
                    LabeledContent("Status on save", value: preview.title)
                }
            }
        }
        .navigationTitle(loanID == nil ? "New Loan" : "Edit Loan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .onAppear(perform: load)
        .onChange(of: loanType) { _, type in
            if type == .GIVEN { includeGiven = true }
            if type == .TAKEN { includeTaken = true }
        }
        .onChange(of: includeExpected) { _, isOn in
            if isOn { expectedDate = loanType == .GIVEN ? givenDate : takenDate }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPhotos(items) }
        }
        .errorAlert($message)
    }

    private var statusPreview: LoanStatus? {
        let draft = currentDraft()
        guard let amount = Money.parse(draft.amountText),
              LoanRules.validate(
                personName: draft.personName,
                amount: amount,
                type: draft.loanType,
                givenDate: draft.givenDate,
                takenDate: draft.takenDate,
                expectedReturnDate: draft.expectedReturnDate
              ) == nil else { return nil }
        return LoanRules.statusOnSave(
            isNew: existing == nil,
            current: existing?.status,
            expectedReturnDate: draft.expectedReturnDate
        )
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let loan = existing, !loan.isDeleted else { return }
        personName = loan.personName
        phone = loan.phoneNumber ?? ""
        amountText = String(format: "%.2f", loan.amount)
        loanType = loan.loanType
        if let date = AppDate.date(from: loan.givenDate) {
            givenDate = date
            includeGiven = true
        }
        if let date = AppDate.date(from: loan.takenDate) {
            takenDate = date
            includeTaken = true
        }
        if let date = AppDate.date(from: loan.expectedReturnDate) {
            expectedDate = date
            includeExpected = true
        }
        notes = loan.notes ?? ""
        imagePaths = loan.imagePaths
        if loan.loanType == .GIVEN { includeGiven = true }
        if loan.loanType == .TAKEN { includeTaken = true }
    }

    private func currentDraft() -> LoanDraft {
        LoanDraft(
            personName: personName,
            phoneNumber: phone,
            amountText: amountText,
            loanType: loanType,
            givenDate: (loanType == .GIVEN || includeGiven) ? AppDate.startOfDay(givenDate) : nil,
            takenDate: (loanType == .TAKEN || includeTaken) ? AppDate.startOfDay(takenDate) : nil,
            expectedReturnDate: includeExpected ? AppDate.startOfDay(expectedDate) : nil,
            notes: notes,
            imagePaths: imagePaths
        )
    }

    private func save() {
        let draft = currentDraft()
        do {
            if let loanID {
                try store.updateLoan(id: loanID, draft: draft)
            } else {
                try store.saveNewLoan(draft)
            }
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        var next = imagePaths
        for item in items {
            guard next.count < 8 else { break }
            do {
                guard let picked = try await item.loadTransferable(type: PickedPhoto.self) else { continue }
                next.append(try ImageStore.save(picked.data))
            } catch {
                message = error.localizedDescription
            }
        }
        imagePaths = next
        pickerItems = []
    }
}

struct PickedPhoto: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PickedPhoto(data: data)
        }
    }
}
