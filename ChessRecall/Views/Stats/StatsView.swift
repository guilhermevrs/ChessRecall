import SwiftUI

struct StatsView: View {
    @StateObject private var viewModel = StatsViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading stats…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                statsContent
            }
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.load() }
    }

    private var statsContent: some View {
        List {
            // Overview section
            Section("Overview") {
                HStack {
                    Label("Puzzles solved", systemImage: "checkmark.circle")
                    Spacer()
                    Text("\(viewModel.totalSolved)")
                        .fontWeight(.semibold)
                }

                HStack {
                    Label("Overall accuracy", systemImage: "percent")
                    Spacer()
                    Text(viewModel.overallSuccessRate, format: .percent.precision(.fractionLength(0)))
                        .fontWeight(.semibold)
                        .foregroundStyle(accuracyColor(viewModel.overallSuccessRate))
                }
            }

            // Themes section
            if !viewModel.themeStats.isEmpty {
                Section("By Theme") {
                    ForEach(viewModel.themeStats) { stat in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stat.theme.capitalized.replacingOccurrences(of: "_", with: " "))
                                    .font(.subheadline)
                                Text("\(stat.totalAttempts) attempt\(stat.totalAttempts == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(stat.successRate, format: .percent.precision(.fractionLength(0)))
                                .fontWeight(.semibold)
                                .foregroundStyle(accuracyColor(stat.successRate))
                        }
                    }
                }
            }

            if viewModel.totalSolved == 0 {
                Section {
                    ContentUnavailableView(
                        "No stats yet",
                        systemImage: "chart.bar",
                        description: Text("Solve some puzzles to see your performance.")
                    )
                }
            }
        }
    }

    private func accuracyColor(_ rate: Double) -> Color {
        if rate >= 0.8 { return .green }
        if rate >= 0.5 { return .orange }
        return .red
    }
}

#Preview {
    NavigationStack {
        StatsView()
    }
}
