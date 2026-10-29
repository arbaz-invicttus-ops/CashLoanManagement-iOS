import CoreTransferable
import PhotosUI
import SwiftUI

struct CashTitleListView: View {
    @Environment(AppStore.self) private var store
    @State private var showingCreate = false

    var body: some View {
        Group {
            if store.titles.isEmpty {
                ContentUnavailableView("No cash titles", systemImage: "banknote", description: Text("Create a title to record money added and spent."))
            } else {
                List(store.titles) { title in
                    NavigationLink(value: Route.cashDetail(title.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(title.titleName).font(.body.weight(.semibold))
                                Spacer()
                                Text(Format.money(title.currentBalance))
                                    .font(.body.weight(.semibold))
                            }
                            if let description = title.description {
                                Text(description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Cash Titles")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New cash title")
            }
        }
        .sheet(isPresented: $showingCreate) {
            NavigationStack {
                CreateTitleView()
            }
        }
    }
}

struct CreateTitleView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var details = ""
    @State private var message: String?

    var body: some View {
        Form {
            TextField("Title name", text: $name)
            TextField("Description", text: $details, axis: .vertical)
                .lineLimit(2...4)
        }
        .navigationTitle("New Title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .errorAlert($message)
    }

    private func save() {
        do {
            try store.createTitle(name: name, description: details)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

struct CashTitleDetailView: View {
    let titleID: Int64
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var transactionType: TransactionType?
    @State private var confirmDelete = false
    @State private var message: String?

    private var title: CashTitle? { store.title(id: titleID) }

    var body: some View {
        Group {
            if let title {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Balance")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(Format.money(store.balance(for: title.id)))
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                            if let description = title.description {
                                Text(description)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Section {
                        LabeledContent("Total credited", value: Format.money(store.creditedTotal(for: title.id)))
                        LabeledContent("Total spent", value: Format.money(store.spentTotal(for: title.id)))
                    }
                    Section("Transactions") {
                        let rows = store.transactions(for: title.id)
                        if rows.isEmpty {
                            Text("No transactions yet")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(rows) { transaction in
                                TransactionRow(transaction: transaction)
                            }
                        }
                    }
                    Section {
                        Button {
                            transactionType = .CREDIT
                        } label: {
                            Label("Add money", systemImage: "plus.circle")
                        }
                        Button {
                            transactionType = .DEBIT
                        } label: {
                            Label("Spend", systemImage: "minus.circle")
                        }
                        .disabled(Money.cents(store.balance(for: title.id)) <= 0)
                        Button("Delete title", role: .destructive) { confirmDelete = true }
                    }
                }
                .navigationTitle(title.titleName)
            } else {
                ContentUnavailableView("Title unavailable", systemImage: "banknote", description: Text("This cash title is no longer on this iPhone."))
            }
        }
        .sheet(item: $transactionType) { type in
            NavigationStack {
                TransactionFormView(titleID: titleID, type: type)
            }
        }
        .confirmationDialog("Delete this cash title?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete title and transactions", role: .destructive) {
                do {
                    try store.deleteTitle(id: titleID)
                    dismiss()
                } catch {
                    message = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the title and every transaction under it from this iPhone.")
        }
        .errorAlert($message)
    }
}

struct TransactionRow: View {
    let transaction: CashTransaction

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.headline)
                    .font(.body.weight(.semibold))
                Text(Format.date(transaction.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notes = transaction.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text((transaction.type == .CREDIT ? "+" : "−") + Format.money(transaction.amount))
                .font(.body.weight(.semibold))
                .foregroundStyle(transaction.type == .CREDIT ? Color.accentColor : .red)
        }
        .padding(.vertical, 4)
    }
}

struct TransactionFormView: View {
    let titleID: Int64
    let type: TransactionType
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var personName = ""
    @State private var itemName = ""
    @State private var notes = ""
    @State private var date = Date()
    @State private var imagePath: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var didSave = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                if type == .DEBIT {
                    LabeledContent("Available", value: Format.money(store.balance(for: titleID)))
                }
            }
            if type == .CREDIT {
                Section("Person") {
                    TextField("Person", text: $personName)
                }
            } else {
                Section("Item") {
                    TextField("Item", text: $itemName)
                }
            }
            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
            if type == .DEBIT {
                Section("Photo") {
                    if let imagePath {
                        PhotoStrip(paths: [imagePath]) { _ in
                            ImageStore.deleteIfOwned(imagePath)
                            self.imagePath = nil
                        }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(imagePath == nil ? "Add photo" : "Replace photo", systemImage: "photo")
                    }
                }
            }
        }
        .navigationTitle(type == .CREDIT ? "Add Money" : "Spend")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await importPhoto(item) }
        }
        .onDisappear {
            if !didSave, let imagePath {
                ImageStore.deleteIfOwned(imagePath)
            }
        }
        .errorAlert($message)
    }

    private func save() {
        do {
            try store.addTransaction(
                titleID: titleID,
                amountText: amountText,
                type: type,
                itemName: itemName,
                personName: personName,
                notes: notes,
                imageUri: imagePath,
                createdAt: AppDate.startOfDay(date)
            )
            didSave = true
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let picked = try await item.loadTransferable(type: PickedPhoto.self) else { return }
            if let imagePath { ImageStore.deleteIfOwned(imagePath) }
            imagePath = try ImageStore.save(picked.data)
        } catch {
            message = error.localizedDescription
        }
        pickerItem = nil
    }
}

extension TransactionType: Identifiable {
    var id: String { rawValue }
}
