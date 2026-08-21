import SwiftUI

/// Détail d'une compétition de type coupe : liste des matchs avec filtre par tour.
struct CupDetailView: View {
    let competition: Competition
    @State private var matches: [AFFixture] = []
    @State private var rounds: [String] = []
    @State private var selectedRound: String? = nil
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var filteredMatches: [AFFixture] {
        guard let round = selectedRound else { return matches }
        return matches.filter { $0.fixture.round == round || $0.league.round == round }
    }

    var groupedMatches: [(String, [AFFixture])] {
        var groups: [String: [AFFixture]] = [:]
        for m in filteredMatches {
            groups[m.formattedDateSection, default: []].append(m)
        }
        return groups.sorted { a, b in
            let dA = filteredMatches.first(where: { $0.formattedDateSection == a.0 })?.isoDate
            let dB = filteredMatches.first(where: { $0.formattedDateSection == b.0 })?.isoDate
            if let x = dA, let y = dB { return x < y }
            return a.0 < b.0
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            CompetitionHeaderView(competition: competition) { dismiss() }

            // Filtre par tour
            if !rounds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(
                            label: L("filter.all"),
                            isSelected: selectedRound == nil,
                            color: competition.color
                        ) { selectedRound = nil }

                        ForEach(rounds, id: \.self) { round in
                            FilterChip(
                                label: round
                                    .replacingOccurrences(of: "Round of ", with: "1/")
                                    .replacingOccurrences(of: "Regular Season - ", with: "J"),
                                isSelected: selectedRound == round,
                                color: competition.color
                            ) { selectedRound = round }
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                }
                .background(Color(.systemBackground))
                Divider()
            }

            if isLoading {
                LoadingView(label: L("loading"))
            } else if let err = errorMessage {
                ErrorView(message: err) { Task { await load() } }
            } else if groupedMatches.isEmpty {
                EmptyStateView(icon: "trophy", text: L("empty.noMatch"))
            } else {
                List {
                    ForEach(groupedMatches, id: \.0) { (date, dayMatches) in
                        SwiftUI.Section {
                            ForEach(dayMatches) { fixture in
                                NavigationLink(destination: MatchDetailView(fixture: fixture)) {
                                    FixtureRowView(fixture: fixture, showLeague: false, showsDateHeader: true)
                                }
                                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                            }
                        } header: {
                            Text(date).font(.subheadline).fontWeight(.semibold).textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load() }
            }
        }
        // La bannière colorée sert déjà de titre : nav bar entièrement masquée.
        // Sous NavigationStack, `.toolbar(.hidden, for:)` remplace l'ancien
        // `.navigationBarHidden(true)` (déprécié) et supprime l'espace mort au-dessus.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    func load() async {
        isLoading = true; errorMessage = nil
        do {
            async let m = FootballAPIService.shared.fetchMatches(competition: competition)
            async let r = FootballAPIService.shared.fetchRounds(competition: competition)
            (matches, rounds) = try await (m, r)
            if selectedRound == nil, let last = rounds.last { selectedRound = last }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption).fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? color : Color(.secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
