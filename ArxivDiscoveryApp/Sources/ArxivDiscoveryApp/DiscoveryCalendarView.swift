import ArxivDiscoveryCore
import SwiftUI

struct DiscoveryCalendarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: AppViewModel
    @ObservedObject var settings: AppSettings
    @State private var visibleMonth = Self.startOfMonth(Date())

    private let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: 7)

    var body: some View {
        VStack(spacing: 0) {
          ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            DiscoveryScopeControls(settings: settings).disabled(model.isDiscovering)
            Divider()
            ViewThatFits(in: .horizontal) {
              HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Discovery calendar")
                        .font(.title2.weight(.bold))
                    Text("Select dates to search · arXiv dates use UTC")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                monthControls
              }
              VStack(alignment: .leading, spacing: 12) {
                Text("Discovery calendar").font(.title2.bold())
                Text("Select dates to search · UTC").font(.caption).foregroundStyle(.secondary)
                monthControls
              }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(DiscoveryDate.calendar.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, weekday in
                    Text(weekday)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(monthSlots.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 72)
                    }
                }
            }
            HStack(spacing: 18) {
                legend(color: AppTheme.teal, text: "Searched")
                legend(color: AppTheme.orange, text: "Needs search")
                legend(color: .secondary, text: "Not searched")
            }.font(.caption)
          }.padding(20).frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
          }
          Divider()
          discoveryFooter.padding(16)
        }
        .background(AppTheme.canvas(for: colorScheme))
    }

    private var discoveryFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let message = model.errorMessage ?? model.notice {
                Text(message).font(.callout).foregroundStyle(model.errorMessage == nil ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let progress = model.discoveryProgress { Text(progress).font(.caption).foregroundStyle(.secondary) }
            if model.isDiscovering, let started = model.discoveryStartedAt {
                ProgressView(value: Double(model.discoveryCompletedDays), total: Double(max(1, model.discoveryTotalDays)))
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(Int(context.date.timeIntervalSince(started)))s elapsed · \(model.discoveryCompletedDays)/\(model.discoveryTotalDays) dates complete · \(model.discoveryReceivedPapers) matching papers saved · 45s search limit")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Button("Select unsearched") { selectUnsearchedMonth() }
                    .disabled(unsearchedMonthKeys.isEmpty || model.isDiscovering)
                Button("Clear") { model.selectedDiscoveryDays.removeAll() }
                    .disabled(model.selectedDiscoveryDays.isEmpty || model.isDiscovering)
                Spacer()
                Text("\(model.selectedDiscoveryDays.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
              }
                Button {
                    model.searchSelectedDates()
                } label: {
                    if model.isDiscovering {
                        Label("Searching…", systemImage: "hourglass")
                    } else {
                        Label(settings.discoveryMode == .topics ? "Find topic papers" : "Search full categories", systemImage: "magnifyingglass")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.sky)
                .foregroundStyle(Color.black.opacity(0.82))
                .disabled(model.selectedDiscoveryDays.isEmpty || !model.canChangeLibrary || (settings.discoveryMode == .topics ? settings.selectedTopics.isEmpty : settings.enabledCategories.isEmpty))
                if model.isDiscovering { Button("Cancel search") { model.cancelDiscovery() } }
                else {
                    HStack {
                        if model.discoveryReport?.pendingDays.isEmpty == false {
                            Button("Retry unfinished dates") { model.retryUnfinishedDates() }
                        }
                        Menu {
                            Button("Refresh selected dates (ignore saved results)") { model.searchSelectedDates(forceRefresh: true) }
                        } label: { Label("Search options", systemImage: "ellipsis.circle") }
                            .menuStyle(.borderlessButton).fixedSize()
                    }
                }
            }
        }.frame(maxWidth: 928, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayCell(_ date: Date) -> some View {
        let key = DiscoveryDate.key(for: date)
        let record = model.discoveryHistory.days[key]
        let covers = record?.covers(mode: settings.discoveryMode, categories: settings.enabledCategories, researchTopics: settings.selectedTopics) == true
        let matchesScope = record?.matchesScope(mode: settings.discoveryMode, categories: settings.enabledCategories, researchTopics: settings.selectedTopics) == true
        let isSelected = model.selectedDiscoveryDays.contains(key)
        let isFuture = date > Date()
        let count = record.map { record in
            matchesScope ? (record.isComplete ? "\(record.paperCount)" : "\(record.paperCount)+") : "—"
        }

        return Button {
            if isSelected { model.selectedDiscoveryDays.remove(key) }
            else { model.selectedDiscoveryDays.insert(key) }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(date.formatted(.dateTime.day()))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Circle()
                        .fill(statusColor(record: record, covers: covers))
                        .frame(width: 7, height: 7)
                }
                Text(count ?? "—")
                    .font(.caption)
                    .foregroundStyle(record == nil ? .secondary : .primary)
                    .lineLimit(1)
                if let record, covers {
                    Text(record.lastSearchedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if record != nil {
                    Image(systemName: "arrow.clockwise").font(.caption2).foregroundStyle(AppTheme.orange)
                        .help(matchesScope ? "Partial results; search again to continue" : "Search again after changing topics")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .padding(8)
            .background(isSelected ? AppTheme.sky.opacity(colorScheme == .dark ? 0.24 : 0.18) : AppTheme.panel(for: colorScheme))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? AppTheme.sky : AppTheme.border(for: colorScheme), lineWidth: isSelected ? 2 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(isFuture || model.isDiscovering)
        .opacity(isFuture ? 0.35 : 1)
        .accessibilityLabel(accessibilityLabel(date: date, record: record, covers: covers, selected: isSelected))
    }

    private var monthSlots: [Date?] {
        let calendar = DiscoveryDate.calendar
        let range = calendar.range(of: .day, in: .month, for: visibleMonth) ?? 1..<1
        let weekday = calendar.component(.weekday, from: visibleMonth)
        let leading = Array<Date?>(repeating: nil, count: max(weekday - 1, 0))
        let days = range.compactMap { day -> Date? in
            calendar.date(bySetting: .day, value: day, of: visibleMonth)
        }.map(Optional.some)
        return leading + days
    }

    private var monthTitle: String {
        visibleMonth.formatted(.dateTime.year().month(.wide))
    }

    private var monthControls: some View {
        HStack {
            Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                .help("Previous month").accessibilityLabel("Previous month")
            Text(monthTitle).font(.headline).frame(minWidth: 135)
            Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                .help("Next month").accessibilityLabel("Next month").disabled(!canMoveForward)
        }
    }

    private var canMoveForward: Bool {
        visibleMonth < Self.startOfMonth(Date())
    }

    private var unsearchedMonthKeys: Set<String> {
        Set(monthSlots.compactMap { date in
            guard let date, date <= Date() else { return nil }
            let key = DiscoveryDate.key(for: date)
            return model.discoveryHistory.days[key]?.covers(mode: settings.discoveryMode, categories: settings.enabledCategories, researchTopics: settings.selectedTopics) == true ? nil : key
        })
    }

    private func selectUnsearchedMonth() {
        model.selectedDiscoveryDays.formUnion(unsearchedMonthKeys)
    }

    private func moveMonth(_ value: Int) {
        guard let date = DiscoveryDate.calendar.date(byAdding: .month, value: value, to: visibleMonth) else { return }
        visibleMonth = Self.startOfMonth(date)
    }

    private func statusColor(record: DiscoveryDayRecord?, covers: Bool) -> Color {
        guard record != nil else { return .secondary }
        return covers ? AppTheme.teal : AppTheme.orange
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).foregroundStyle(.secondary)
        }
    }

    private func accessibilityLabel(date: Date, record: DiscoveryDayRecord?, covers: Bool, selected: Bool) -> String {
        var parts = [date.formatted(date: .long, time: .omitted)]
        if let record {
            parts.append("\(record.paperCount) papers")
            parts.append(covers ? "searched" : "search again for current subjects")
        } else {
            parts.append("not searched")
        }
        if selected { parts.append("selected") }
        return parts.joined(separator: ", ")
    }

    private static func startOfMonth(_ date: Date) -> Date {
        let components = DiscoveryDate.calendar.dateComponents([.year, .month], from: date)
        return DiscoveryDate.calendar.date(from: components) ?? date
    }
}
