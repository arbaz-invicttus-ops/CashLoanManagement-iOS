import SwiftUI
import UIKit

enum Route: Hashable {
    case addLoan
    case editLoan(Int64)
    case loans
    case loanDetail(Int64)
    case deletedLoans
    case cashTitles
    case cashDetail(Int64)
    case tools
    case pin(PINPurpose)
}

enum PINPurpose: Hashable {
    case create
    case change
    case remove
}

enum LoanListFilter: String, CaseIterable, Identifiable {
    case all
    case given
    case taken

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .given: "Given"
        case .taken: "Taken"
        }
    }

    var type: LoanType? {
        switch self {
        case .all: nil
        case .given: .GIVEN
        case .taken: .TAKEN
        }
    }
}

struct StatusBadge: View {
    let status: LoanStatus

    var body: some View {
        Text(status.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .PENDING: .blue
        case .CLEARED: .green
        case .OVERDUE: .red
        }
    }
}

struct TypeBadge: View {
    let type: LoanType

    var body: some View {
        Text(type.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var color: Color {
        type == .GIVEN ? Color.accentColor : Color.orange
    }
}

struct MenuLink: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let route: Route

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let caption: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PhotoStrip: View {
    let paths: [String]
    var onDelete: ((String) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(paths.enumerated()), id: \.offset) { _, path in
                    ZStack(alignment: .topTrailing) {
                        photo(path)
                        if let onDelete {
                            Button {
                                onDelete(path)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.55))
                            }
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("Remove photo")
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func photo(_ path: String) -> some View {
        if let image = ImageStore.image(at: path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(width: 96, height: 96)
                .overlay {
                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                        Text("Not on this iPhone")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                    .padding(6)
                }
        }
    }
}

struct PINDots: View {
    let count: Int

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(index < count ? Color.primary : Color.primary.opacity(0.18))
                    .frame(width: 14, height: 14)
            }
        }
        .accessibilityLabel("\(count) of 4 digits entered")
    }
}

struct PINPad: View {
    let onDigit: (String) -> Void
    let onDelete: () -> Void

    private let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
    ]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 16) {
                    ForEach(row, id: \.self) { key in
                        digit(key)
                    }
                }
            }
            HStack(spacing: 16) {
                Color.clear.frame(maxWidth: .infinity, minHeight: 64)
                digit("0")
                Button(action: onDelete) {
                    Image(systemName: "delete.left")
                        .font(.title3)
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete")
            }
        }
    }

    private func digit(_ key: String) -> some View {
        Button {
            onDigit(key)
        } label: {
            Text(key)
                .font(.title.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Color(.secondarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct ErrorAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert(message ?? "", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        }
    }
}

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        modifier(ErrorAlert(message: message))
    }
}
