import SwiftUI

struct HomeView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let summary = store.summary
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Net")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(Format.money(summary.net))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .accessibilityLabel("Net \(Format.money(summary.net))")
                    Text("Given minus taken, excluding cleared loans")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.82))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )

                HStack(spacing: 12) {
                    MetricCard(title: "Total given", value: Format.money(summary.totalGiven), caption: "Still open", tint: Color.accentColor)
                    MetricCard(title: "Total taken", value: Format.money(summary.totalTaken), caption: "Still open", tint: .orange)
                }
                HStack(spacing: 12) {
                    MetricCard(title: "Pending given", value: "\(summary.pendingGiven)", caption: "Not cleared or overdue", tint: .blue)
                    MetricCard(title: "Pending taken", value: "\(summary.pendingTaken)", caption: "Not cleared or overdue", tint: .blue)
                }

                VStack(spacing: 10) {
                    MenuLink(title: "Add Loan", subtitle: "Record money given or taken", systemImage: "plus.circle.fill", route: .addLoan)
                    MenuLink(title: "All Loans", subtitle: "Search, filter, and open a loan", systemImage: "list.bullet.rectangle", route: .loans)
                    MenuLink(title: "Cash Titles", subtitle: "Track money added and spent", systemImage: "banknote", route: .cashTitles)
                    MenuLink(title: "Tools", subtitle: "Sign in, backup, restore, and PIN", systemImage: "wrench.and.screwdriver", route: .tools)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Cash Loans")
    }
}
