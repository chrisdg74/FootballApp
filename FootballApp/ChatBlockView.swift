import SwiftUI

// ═════════════════════════════════════════════════════════════════════════════
// RENDU DES CARTES CLIQUABLES DE L'ASSISTANT
// ─────────────────────────────────────────────────────────────────────────────
// Le proxy ne renvoie que des IDENTIFIANTS. Chaque carte recharge son détail par
// ID (règle d'or : aucune donnée inventée) et pousse vers la vraie vue de l'app :
//   • fixtureRow   → MatchDetailView
//   • standingMini → CompetitionDetailView
//   • scorerCard   → CompetitionScorersView
//   • teamCard     → fiche/recherche d'équipe
// Un bloc `.unknown` (type plus récent que l'app) n'affiche RIEN.
// ═════════════════════════════════════════════════════════════════════════════

struct ChatBlockView: View {
    let block: ChatBlock

    var body: some View {
        switch block {
        case .fixtureRow(let fixtureId):
            FixtureCardLoader(fixtureId: fixtureId)
        case .standingMini(let competitionId, let highlightTeamId, let focus):
            StandingCardLoader(competitionId: competitionId, highlightTeamId: highlightTeamId, focus: focus)
        case .scorerCard(let competitionId, let limit):
            ScorerCardLoader(competitionId: competitionId, limit: limit)
        case .clubScorers(let teamId, _):
            ClubScorersCardLoader(teamId: teamId)
        case .teamCard(let teamId):
            TeamCardLoader(teamId: teamId)
        case .text(let content):
            if !content.isEmpty {
                Text(content)
                    .font(.subheadline)
                    .foregroundColor(Theme.text)
            }
        case .unknown:
            EmptyView()
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coquille commune : cadre « carte » cliquable avec un chevron.
// ─────────────────────────────────────────────────────────────────────────────
private struct ChatCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 10) {
            content()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(Theme.textFaint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }
}

private struct ChatCardSkeleton: View {
    let label: String
    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(label).font(.caption).foregroundColor(Theme.textSoft)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARTE MATCH — charge le fixture par ID → pousse vers MatchDetailView
// ─────────────────────────────────────────────────────────────────────────────
private struct FixtureCardLoader: View {
    let fixtureId: Int
    @State private var fixture: AFFixture?
    @State private var failed = false

    var body: some View {
        Group {
            if let fixture {
                NavigationLink { MatchDetailView(fixture: fixture) } label: {
                    ChatCard { FixtureRowView(fixture: fixture).allowsHitTesting(false) }
                }
                .buttonStyle(.plain)
            } else if failed {
                EmptyView()   // match introuvable : on n'affiche rien plutôt qu'une carte cassée
            } else {
                ChatCardSkeleton(label: L("assistant.loadingMatch"))
            }
        }
        .animation(.easeOut(duration: 0.25), value: fixture?.fixture.id)
        .task { await load() }
    }

    private func load() async {
        guard fixture == nil, !failed else { return }
        do {
            // fetchMatchDetail renvoie un AFFixtureFull ; on en dérive un AFFixture léger
            // pour réutiliser FixtureRowView et MatchDetailView tels quels.
            let full = try await FootballAPIService.shared.fetchMatchDetail(fixtureId: fixtureId)
            fixture = AFFixture(
                fixture: full.fixture, league: full.league,
                teams: full.teams, goals: full.goals, score: full.score
            )
        } catch {
            failed = true
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARTE CLASSEMENT — aperçu top 5 → pousse vers CompetitionDetailView
// ─────────────────────────────────────────────────────────────────────────────
private struct StandingCardLoader: View {
    let competitionId: String
    let highlightTeamId: Int?
    var focus: StandingFocus = .top

    @State private var rows: [AFStandingEntry] = []
    @State private var loaded = false

    private var competition: Competition? {
        Catalog.all.first { $0.id == competitionId }
    }

    var body: some View {
        Group {
            if let competition {
                NavigationLink { CompetitionDetailView(competition: competition, initialTab: 1) } label: {
                    ChatCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L(competition.nameKey))
                                .font(.caption.weight(.bold))
                                .foregroundColor(Theme.textSoft)
                                .textCase(.uppercase)
                            if loaded {
                                if rows.isEmpty {
                                    // Classement indisponible (API lente / vide) : on le
                                    // dit au lieu d'afficher une carte fantôme.
                                    Text(L("assistant.standingUnavailable"))
                                        .font(.caption2).foregroundColor(Theme.textSoft)
                                } else {
                                    ForEach(previewRows) { entry in
                                        StandingMiniRow(entry: entry,
                                                        highlighted: isHighlighted(entry))
                                    }
                                    if rows.count > previewRows.count {
                                        Text(L("assistant.seeFullTable"))
                                            .font(.caption2).foregroundColor(Theme.live)
                                    }
                                }
                            } else {
                                ProgressView().padding(.vertical, 6)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                EmptyView()
            }
        }
        .task { await load() }
    }

    /// Les lignes à afficher dans l'aperçu.
    /// - `.top`   : top 5 (+ la ligne surlignée si elle est plus bas).
    /// - `.bottom`: les 5 DERNIÈRES lignes (pour « le dernier », « qui descend »…).
    private var previewRows: [AFStandingEntry] {
        if focus == .bottom {
            return Array(rows.suffix(5))
        }
        var top = Array(rows.prefix(5))
        if let hid = highlightTeamId,
           let hl = rows.first(where: { $0.team.id == hid }),
           !top.contains(where: { $0.team.id == hid }) {
            top.append(hl)
        }
        return top
    }

    /// Surligne l'équipe visée (highlightTeamId) ; à défaut, en focus « bas de
    /// tableau », surligne la toute dernière équipe du classement (« le dernier »).
    private func isHighlighted(_ entry: AFStandingEntry) -> Bool {
        if let hid = highlightTeamId { return entry.team.id == hid }
        if focus == .bottom { return entry.team.id == rows.last?.team.id }
        return false
    }

    private func load() async {
        guard let competition, !loaded else { return }
        // On prend la 1re poule (les compétitions à poules ouvrent sur le sélecteur
        // complet au tap ; l'aperçu montre la première).
        // Un échec transitoire (timeout/réseau) laissait la carte vide : on retente
        // une fois après une courte pause avant d'abandonner. Et on LOGGUE l'erreur
        // réelle (au lieu de l'avaler avec try?) pour diagnostiquer les cas restants.
        for attempt in 1...2 {
            do {
                let groups = try await FootballAPIService.shared.fetchStandings(competition: competition)
                rows = groups.first ?? []
                if !rows.isEmpty { break }   // succès : on arrête
            } catch {
                print("⚠️ standingMini \(competition.id) tentative \(attempt) : \(error)")
            }
            if attempt == 1 { try? await Task.sleep(nanoseconds: 500_000_000) } // 0,5 s
        }
        loaded = true
    }
}

/// Ligne compacte du mini-classement.
private struct StandingMiniRow: View {
    let entry: AFStandingEntry
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(entry.rank)")
                .font(.statNum)
                .foregroundColor(Theme.textSoft)
                .frame(width: 18, alignment: .trailing)
            TeamLogoView(urlString: entry.team.logo, name: entry.team.name, size: 18)
            Text(entry.team.displayName)
                .font(.caption)
                .fontWeight(highlighted ? .bold : .regular)
                .foregroundColor(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(entry.points)")
                .font(.statNum)
                .foregroundColor(Theme.text)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(highlighted ? Theme.live.opacity(0.12) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARTE BUTEURS — aperçu top N → pousse vers CompetitionScorersView
// ─────────────────────────────────────────────────────────────────────────────
private struct ScorerCardLoader: View {
    let competitionId: String
    let limit: Int

    @State private var players: [AFPlayerResponse] = []
    @State private var loaded = false

    private var competition: Competition? {
        Catalog.all.first { $0.id == competitionId }
    }

    var body: some View {
        Group {
            if let competition {
                NavigationLink { CompetitionScorersView(competition: competition) } label: {
                    ChatCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("stats.scorers") + " · " + L(competition.nameKey))
                                .font(.caption.weight(.bold))
                                .foregroundColor(Theme.textSoft)
                                .textCase(.uppercase)
                                .lineLimit(1)
                            if loaded {
                                ForEach(Array(players.prefix(max(1, min(limit, 5)))), id: \.id) { p in
                                    ScorerMiniRow(player: p)
                                }
                            } else {
                                ProgressView().padding(.vertical, 6)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                EmptyView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let competition, !loaded else { return }
        players = (try? await FootballAPIService.shared.fetchTopScorers(competition: competition)) ?? []
        loaded = true
    }
}

/// Ligne compacte du mini-classement des buteurs.
private struct ScorerMiniRow: View {
    let player: AFPlayerResponse

    var body: some View {
        HStack(spacing: 8) {
            AsyncImage(url: URL(string: player.player.photo ?? "")) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Theme.surface2)
            }
            .frame(width: 22, height: 22)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 0) {
                Text(player.fullName)
                    .font(.caption).foregroundColor(Theme.text).lineLimit(1)
                Text(player.teamName)
                    .font(.caption2).foregroundColor(Theme.textFaint).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(player.goals)")
                .font(.statNum).foregroundColor(Theme.text)
            Text(L("col.goalsShort"))
                .font(.caption2).foregroundColor(Theme.textFaint)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARTE BUTEURS D'UN CLUB — aperçu top 3 → pousse vers TeamScorersView
// ─────────────────────────────────────────────────────────────────────────────
private struct ClubScorersCardLoader: View {
    let teamId: Int

    @State private var scorers: [AFPlayerResponse] = []
    @State private var loaded = false
    @State private var teamName: String = ""

    var body: some View {
        Group {
            if loaded && scorers.isEmpty {
                // Pas de buteur (début de saison…) : on n'affiche pas de carte fantôme.
                EmptyView()
            } else {
                NavigationLink { TeamScorersView(teamId: teamId) } label: {
                    ChatCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text((teamName.isEmpty ? L("assistant.clubScorers.title") : teamName)
                                    + " · " + L("stats.scorers"))
                                .font(.caption.weight(.bold))
                                .foregroundColor(Theme.textSoft)
                                .textCase(.uppercase)
                                .lineLimit(1)
                            if loaded {
                                ForEach(scorers.prefix(3)) { p in
                                    ScorerMiniRow(player: p)
                                }
                                if scorers.count > 3 {
                                    Text(L("assistant.seeFullTable"))
                                        .font(.caption2).foregroundColor(Theme.live)
                                }
                            } else {
                                ProgressView().padding(.vertical, 6)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard !loaded else { return }
        let season = Calendar.current.component(.year, from: Date())
        do {
            let rows = try await FootballAPIService.shared.fetchTeamScorers(teamId: teamId, season: season)
            scorers = rows
            teamName = rows.first?.teamName ?? ""
        } catch {
            print("⚠️ clubScorers team \(teamId) : \(error)")
        }
        loaded = true
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARTE ÉQUIPE — charge l'équipe par ID → pousse vers sa fiche (via TeamProfileView)
// ─────────────────────────────────────────────────────────────────────────────
private struct TeamCardLoader: View {
    let teamId: Int
    @State private var team: AFTeamInfo?
    @State private var failed = false

    var body: some View {
        Group {
            if let team {
                NavigationLink { TeamProfileView(team: team) } label: {
                    ChatCard {
                        HStack(spacing: 10) {
                            TeamLogoView(urlString: team.logo, name: team.name, size: 30)
                            Text(team.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Theme.text)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else if failed {
                EmptyView()
            } else {
                ChatCardSkeleton(label: L("assistant.loadingTeam"))
            }
        }
        .animation(.easeOut(duration: 0.25), value: team?.id)
        .task { await load() }
    }

    private func load() async {
        guard team == nil, !failed else { return }
        // /teams?search= renvoie AFTeamResult (avec AFTeamInfo). On cherche par nom
        // impossible ici (on a un id) → on récupère via les fixtures de l'équipe le
        // logo/nom si besoin. Le plus simple et fiable : requête teams?id via le
        // service. On fait un repli gracieux si indisponible.
        if let info = try? await FootballAPIService.shared.fetchTeamInfo(teamId: teamId) {
            team = info
        } else {
            failed = true
        }
    }
}
