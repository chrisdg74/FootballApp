import SwiftUI

// ═════════════════════════════════════════════════════════════════════════════
// BUTEURS D'UN CLUB — vue plein écran ouverte depuis la carte de l'assistant
// ─────────────────────────────────────────────────────────────────────────────
// L'assistant ne renvoie qu'un IDENTIFIANT (teamId) : cette vue recharge elle-même
// l'effectif du club et affiche ses buteurs (règle d'or : aucune donnée inventée,
// tout est rechargé par ID via l'API, comme le reste de l'app).
// ═════════════════════════════════════════════════════════════════════════════

struct TeamScorersView: View {
    let teamId: Int

    @State private var scorers: [AFPlayerResponse] = []
    @State private var loaded = false
    @State private var teamName: String = ""

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if loaded {
                    if scorers.isEmpty {
                        Text(L("assistant.clubScorers.empty"))
                            .font(.subheadline)
                            .foregroundColor(Theme.textSoft)
                            .padding(.top, 40)
                    } else {
                        ForEach(Array(scorers.enumerated()), id: \.element.id) { idx, p in
                            NavigationLink {
                                PlayerDetailView(playerId: p.player.id, fallbackName: p.player.name)
                            } label: {
                                TeamScorerRow(rank: idx + 1, player: p)
                            }
                            .buttonStyle(.plain)
                            if idx < scorers.count - 1 {
                                Divider().overlay(Theme.hairline).padding(.leading, 44)
                            }
                        }
                    }
                } else {
                    ProgressView().padding(.top, 40)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(teamName.isEmpty ? L("assistant.clubScorers.title") : teamName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard !loaded else { return }
        // Saison en cours (fuseau Paris) : cohérent avec le proxy.
        let season = Calendar.current.component(.year, from: Date())
        do {
            let rows = try await FootballAPIService.shared.fetchTeamScorers(teamId: teamId, season: season)
            scorers = rows
            teamName = rows.first?.teamName ?? ""
        } catch {
            print("⚠️ TeamScorersView team \(teamId) : \(error)")
        }
        loaded = true
    }
}

/// Ligne d'un buteur du club : rang, photo, nom, buts (et passes en second).
private struct TeamScorerRow: View {
    let rank: Int
    let player: AFPlayerResponse

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.statNum)
                .foregroundColor(Theme.textSoft)
                .frame(width: 22, alignment: .trailing)

            AsyncImage(url: URL(string: player.player.photo ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Theme.surface2)
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())

            Text(player.fullName)
                .font(.subheadline)
                .foregroundColor(Theme.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            // Buts (mise en avant) + passes en libellé court.
            HStack(spacing: 4) {
                Text("\(player.totalGoals)")
                    .font(.statNum).foregroundColor(Theme.text)
                Text(L("col.goalsShort"))
                    .font(.caption2).foregroundColor(Theme.textFaint)
            }
            if player.totalAssists > 0 {
                HStack(spacing: 4) {
                    Text("\(player.totalAssists)")
                        .font(.statNum).foregroundColor(Theme.textSoft)
                    Text(L("col.assistsShort"))
                        .font(.caption2).foregroundColor(Theme.textFaint)
                }
                .padding(.leading, 6)
            }
        }
        .padding(.vertical, 8)
    }
}
