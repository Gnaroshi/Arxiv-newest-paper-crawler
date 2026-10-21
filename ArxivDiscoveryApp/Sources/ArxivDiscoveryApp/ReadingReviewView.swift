import ArxivDiscoveryCore
import SwiftUI

struct ReadingReviewHeader: View {
    @ObservedObject var reading: ReadingReviewModel
    @State private var showingPreferences = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's reading").font(.title2.bold())
                Spacer(minLength: 8)
                Button {
                    showingPreferences = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .help("Reading focus and daily limit").accessibilityLabel("Reading focus")
            }
            if let plan = reading.plan {
                Text("Checked \(plan.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("Show", selection: $reading.bucket) {
                ForEach(ReadingBucket.allCases) { value in
                    Text("\(value.label) (\(reading.count(value)))").tag(value)
                }
            }.pickerStyle(.menu)
            if reading.isUpdating {
                ProgressView("Updating priorities…").controlSize(.small)
            } else if let error = reading.error {
                Text(error).font(.callout).foregroundStyle(.red)
                Button("Retry") { reading.retry() }
            } else {
                Text(
                    reading.notice
                        ?? (reading.bucket == .notNow
                            ? "Lower relevance or deferred by you. Nothing was deleted."
                            : "Based on your topics, focus phrases and reading choices.")
                )
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(16)
            .onAppear { reading.refreshIfNewDay() }
            .sheet(isPresented: $showingPreferences) { ReadingPreferencesView(reading: reading) }
    }
}

struct ReadingPriorityView: View {
    @ObservedObject var reading: ReadingReviewModel
    let paperID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let recommendation = reading.byID[paperID] {
                Label(
                    recommendation.bucket.label,
                    systemImage: recommendation.bucket == .readFirst ? "text.badge.star" : "list.bullet"
                )
                .font(.headline)
                Text(recommendation.reasons.joined(separator: " "))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Picker(
                "Reading priority",
                selection: Binding(
                    get: { reading.state.activeChoice(for: paperID) },
                    set: { reading.choose($0, for: paperID) }
                )
            ) {
                ForEach(ReadingChoice.allCases) { choice in Text(choice.label).tag(choice) }
            }.pickerStyle(.menu)
        }
    }
}

private struct ReadingPreferencesView: View {
    @ObservedObject var reading: ReadingReviewModel
    @Environment(\.dismiss) private var dismiss
    @State private var limit = 5
    @State private var terms: [String] = []
    @State private var newTerm = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reading focus").font(.title2.bold())
            Stepper("Suggested papers per day: \(limit)", value: $limit, in: 1...20)
            Text("Your manually pinned papers are kept in addition to the suggested daily limit.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Focus phrases").font(.headline)
            HStack {
                TextField("e.g. inverse dynamics", text: $newTerm).onSubmit { addTerm() }
                Button {
                    addTerm()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add focus phrase").disabled(ResearchTopic.normalize(newTerm).isEmpty)
            }
            List {
                ForEach(terms, id: \.self) { term in
                    HStack {
                        Text(term)
                        Spacer()
                        Button {
                            terms.removeAll { $0 == term }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless).accessibilityLabel("Remove \(term)")
                    }
                }
            }.frame(minHeight: 120)
            Text(
                "Priorities refresh locally each day when the app is open or reopened. No automatic collection, PDF downloads or paid requests."
            )
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = reading.error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save focus") {
                    addTerm()
                    if reading.setPreferences(limit: limit, focus: terms) { dismiss() }
                }.buttonStyle(.borderedProminent)
                    .disabled(
                        limit == reading.state.dailyLimit && terms == reading.state.focusTerms
                            && ResearchTopic.normalize(newTerm).isEmpty)
            }
        }.padding(20).frame(width: 460, height: 460)
            .onAppear {
                limit = reading.state.dailyLimit
                terms = reading.state.focusTerms
            }
    }

    private func addTerm() {
        let values = newTerm.components(separatedBy: ",").map(ResearchTopic.normalize).filter { !$0.isEmpty }
        terms = Array(Set(terms + values)).sorted()
        newTerm = ""
    }
}
