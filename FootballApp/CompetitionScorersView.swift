import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Classement des buteurs (endpoint players/topscorers)
// Fonctionne pour toute compétition active — y compris multi-poules (N1, N2),
// où l'API renvoie le classement agrégé sur l'ensemble de la compétition.
// ─────────────────────────────────────────────────────────────────────────────
struct CompetitionScorersView: View {
    let competition: Competition
    /// Poule ciblée (leagueId) : buteurs de cette poule uniquement ; nil = agrégé.
    var groupApiId: Int? = nil
    @State private var scorers: [AFPlayerResponse] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                LoadingView(label: L("loading"))
            } else if let err = errorMessage {
                ErrorView(message: err) { Task { await load() } }
            } else if scorers.isEmpty {
                EmptyStateView(icon: "soccerball", text: L("empty.noScorers"))
            } else {
                VStack(spacing: 0) {
                    ScorersHeaderView()
                    List(Array(scorers.enumerated()), id: \.element.id) { index, player in
                        NavigationLink {
                            PlayerDetailView(playerId: player.player.id, fallbackName: player.player.name)
                        } label: {
                            ScorerRow(rank: index + 1, player: player, competition: competition)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
        }
        .task { await load() }
    }

    func load() async {
        isLoading = true; errorMessage = nil
        do {
            if let gid = groupApiId {
                scorers = try await FootballAPIService.shared.fetchTopScorers(competition: competition, groupApiId: gid)
            } else {
                scorers = try await FootballAPIService.shared.fetchTopScorers(competition: competition)
            }
        }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

struct ScorersHeaderView: View {
    var body: some View {
        HStack {
            Text("#").frame(width: 26, alignment: .center)
            Text(L("col.player")).frame(maxWidth: .infinity, alignment: .leading)
            Text(L("col.matchesShort")).frame(width: 30, alignment: .center)
            Text(L("col.assistsShort")).frame(width: 30, alignment: .center)
            Text(L("col.goalsShort")).frame(width: 34, alignment: .center).fontWeight(.bold)
        }
        .font(.caption2).foregroundColor(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Color(.secondarySystemBackground))
    }
}

struct ScorerRow: View {
    let rank: Int
    let player: AFPlayerResponse
    let competition: Competition

    var rankColor: Color? {
        switch rank {
        case 1: return .yellow
        case 2: return Color(.systemGray)
        case 3: return .orange
        default: return nil
        }
    }

    var body: some View {
        HStack {
            ZStack {
                if let c = rankColor { Circle().fill(c.opacity(0.20)).frame(width: 20, height: 20) }
                Text("\(rank)")
                    .font(.caption).fontWeight(rank <= 3 ? .bold : .regular)
                    .foregroundColor(rankColor ?? .secondary)
            }
            .frame(width: 26)

            // Logo cliquable → fiche club (la ligne = fiche joueur).
            if let club = player.statistics.first?.team {
                TeamTapTarget(teamId: club.id, previewName: club.name, previewLogo: club.logo) {
                    TeamLogoView(urlString: club.logo, name: player.teamName, size: 18)
                        .contentShape(Rectangle())
                }
            } else {
                TeamLogoView(urlString: player.statistics.first?.team.logo,
                             name: player.teamName, size: 18)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(player.player.name)
                    .font(.caption).fontWeight(rank <= 3 ? .semibold : .regular)
                    .lineLimit(1)
                Text(player.teamName)
                    .font(.caption2).foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(player.appearances)")
                .font(.caption).foregroundColor(.secondary)
                .frame(width: 30, alignment: .center)
            Text("\(player.assists)")
                .font(.caption).foregroundColor(.secondary)
                .frame(width: 30, alignment: .center)
            Text("\(player.goals)")
                .font(.caption).fontWeight(.bold)
                .foregroundColor(competition.color)
                .frame(width: 34, alignment: .center)
        }
        .padding(.vertical, 4)
    }
}
