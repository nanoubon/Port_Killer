import AppKit
import SwiftUI
import StoreKit
import UniformTypeIdentifiers

struct HistorySectionView: View {
    @EnvironmentObject private var viewModel: PortViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kill History")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.pkText)
                    Text(viewModel.historySummary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.pkMuted)
                }
                Spacer()
                HeaderIconButton(systemName: "trash") {
                    viewModel.killHistory = []
                }
                .help("Clear history")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                MetricCardView(metric: DashboardMetric(title: "RECENT EVENTS", value: String(format: "%02d", viewModel.historyFeed.count), tint: .warning, detail: "Last terminations logged"))
                MetricCardView(metric: DashboardMetric(title: "TODAY", value: String(format: "%02d", viewModel.historyFeed.filter { Calendar.current.isDateInToday($0.createdAt) }.count), tint: .secondary, detail: "Processes terminated"))
                MetricCardView(metric: DashboardMetric(title: "AUDIT", value: "Enabled", tint: .primary, detail: "Persistent local log"))
            }

            CardShell(fill: Color.pkCard, radius: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(title: "RECENT TERMINATIONS", trailing: "LOCAL AUDIT LOG")
                    VStack(spacing: 10) {
                        ForEach(viewModel.historyFeed) { entry in
                            HistoryRowView(entry: entry)
                        }
                    }
                }
            }
        }
    }
}

struct HistoryRowView: View {
    let entry: KillHistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 5) {
                Circle()
                    .fill(Color.pkSecondary)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(Color.pkStroke.opacity(0.5))
                    .frame(width: 1, height: 34)
            }
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(entry.processName) • Port \(entry.port)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.pkText)
                Text("PID \(entry.pid)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.pkMuted)
                Text(entry.outcome)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.pkMuted.opacity(0.8))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.pkText.opacity(0.72))
                Text(entry.createdAt.formatted(.relative(presentation: .numeric)))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.pkMuted)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.pkElevated)
        )
    }
}
