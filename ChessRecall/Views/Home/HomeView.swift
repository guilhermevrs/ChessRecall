import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var showingPuzzle = false
    @State private var showingStats = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // App icon area
            VStack(spacing: 8) {
                Text("♟")
                    .font(.system(size: 80))
                Text("Chess Recall")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Spaced repetition puzzle trainer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Stats summary — or loading indicator during initial fetch
            if let progress = viewModel.fetchProgressText {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.85)
                    Text(progress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 32)
                .transition(.opacity)
            } else {
                HStack(spacing: 24) {
                    statBadge(
                        value: "\(viewModel.duePuzzleCount)",
                        label: "Due today",
                        color: viewModel.duePuzzleCount > 0 ? .orange : .green
                    )
                    statBadge(
                        value: "\(viewModel.totalPuzzleCount)",
                        label: "Puzzles saved",
                        color: .blue
                    )
                }
                .padding(.bottom, 32)
                .transition(.opacity)
            }

            // Start button
            Button {
                showingPuzzle = true
            } label: {
                HStack {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.white)
                            .padding(.trailing, 4)
                    }
                    Text(viewModel.isLoading ? "Almost ready…" : "Start Training")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isLoading)
            .padding(.horizontal, 32)

            // Stats link
            Button("View Stats") {
                showingStats = true
            }
            .padding(.top, 16)
            .foregroundStyle(.secondary)

            Spacer()

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.bottom, 8)
            }
        }
        .padding()
        .navigationDestination(isPresented: $showingPuzzle) {
            PuzzleView()
        }
        .navigationDestination(isPresented: $showingStats) {
            StatsView()
        }
        .task { await viewModel.onAppear() }
        .refreshable { await viewModel.onAppear() }
    }

    private func statBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 80)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
}
