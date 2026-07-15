import ArxivDiscoveryCore
import SwiftUI

struct DiscoveryCalendarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: AppViewModel
    @ObservedObject var settings: AppSettings
    @State private var visibleMonth = Self.startOfMonth(Date())

    private let columns = Array(repeating: GridItem(.flexible(minimum: 72), spacing: 8), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Discovery calendar")
                        .font(.title2.weight(.bold))
                    Text("Select dates to search · arXiv dates use UTC")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Text(monthTitle)
                    .font(.headline)
                    .frame(minWidth: 135)
                Button { moveMonth(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
                    .disabled(!canMoveForward)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(DiscoveryDate.calendar.veryShortWeekdaySymbols, id: \.self) { weekday in
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

            HStack(spacing: 12) {
                Button("Select unsearched") { selectUnsearchedMonth() }
                    .disabled(unsearchedMonthKeys.isEmpty || model.isDiscovering)
                Button("Clear") { model.selectedDiscoveryDays.removeAll() }
                    .disabled(model.selectedDiscoveryDays.isEmpty || model.isDiscovering)
                Spacer()
                Text("\(model.selectedDiscoveryDays.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    model.searchSelectedDates()
                } label: {
                    if model.isDiscovering {
                        Label("Searching…", systemImage: "hourglass")
                    } else {
                        Label("Search selected dates", systemImage: "magnifyingglass")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.sky)
                .foregroundStyle(Color.black.opacity(0.82))
                .disabled(model.selectedDiscoveryDays.isEmpty || model.isDiscovering || ShowcaseMode.isEnabled)
            }

            HStack(spacing: 18) {
                legend(color: AppTheme.teal, text: "Searched")
                legend(color: AppTheme.orange, text: "Search again for current subjects")
                legend(color: .secondary, text: "Not searched")
            }
            .font(.caption)
        }
        .padding(20)
        .background(AppTheme.canvas(for: colorScheme))
    }

    private func dayCell(_ date: Date) -> some View {
        let key = DiscoveryDate.key(for: date)
        let record = model.discoveryHistory.days[key]
        let covers = record?.covers(categories: settings.enabledCategories) == true
        let isSelected = model.selectedDiscoveryDays.contains(key)
        let isFuture = date > Date()
        let count = record.map { $0.isComplete ? "\($0.paperCount) papers" : "\($0.paperCount)+ papers" }

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
                Text(count ?? "Not searched")
                    .font(.caption)
                    .foregroundStyle(record == nil ? .secondary : .primary)
                    .lineLimit(1)
                if let record {
                    Text(covers ? record.lastSearchedAt.formatted(date: .omitted, time: .shortened) : "Subjects changed")
                        .font(.caption2)
                        .foregroundStyle(covers ? .secondary : AppTheme.orange)
                        .lineLimit(1)
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

    private var canMoveForward: Bool {
        visibleMonth < Self.startOfMonth(Date())
    }

    private var unsearchedMonthKeys: Set<String> {
        Set(monthSlots.compactMap { date in
            guard let date, date <= Date() else { return nil }
            let key = DiscoveryDate.key(for: date)
            return model.discoveryHistory.days[key]?.covers(categories: settings.enabledCategories) == true ? nil : key
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
