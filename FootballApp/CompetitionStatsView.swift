import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// STATS — onglet regroupant plusieurs classements dérivés de données que l'app
// récupère déjà (aucun appel API supplémentaire) :
//   • Buteurs / Passeurs / Combo → players/topscorers (fetchTopScorers)
//   • Meilleures attaques        → standings.all.goals.for
//   • Meilleures défenses        → standings.all.goals.against
//   • Séries en cours            → standings.form ("WWDLW")
//   • Classement à domicile      → standings.home
//   • Classement à l'extérieur   → standings.away
//
// Un menu déroulant en haut sélectionne la statistique affichée. Les tailles de
// police sont calquées sur ScorerRow / ScorersHeaderView (onglet Buteurs) pour
// une cohérence visuelle stricte.
// ─────────────────────────────────────────────────────────────────────────────

enum StatKind: Int, CaseIterable, Identifiable {
    case scorers, assists, combo, ratings, bestAttack, bestDefense, streaks, home, away, fairPlay
    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .scorers:     return "stats.scorers"
        case .assists:     return "stats.assists"
        case .combo:       return "stats.combo"
        case .ratings:     return "stats.ratings"
        case .bestAttack:  return "stats.bestAttack"
        case .bestDefense: return "stats.bestDefense"
        case .streaks:     return "stats.streaks"
        case .home:        return "stats.home"
        case .away:        return "stats.away"
        case .fairPlay:    return "stats.fairPlay"
        }
    }

    var icon: String {
        switch self {
        case .scorers:     return "soccerball"
        case .assists:     return "hand.point.up.left.fill"
        case .combo:       return "sparkles"
        case .ratings:     return "star.fill"
        case .bestAttack:  return "flame.fill"
        case .bestDefense: return "shield.lefthalf.filled"
        case .streaks:     return "chart.line.uptrend.xyaxis"
        case .home:        return "house.fill"
        case .away:        return "airplane"
        case .fairPlay:    return "hand.raised.fill"
        }
    }

    /// Vrai si la stat provient des buteurs (players), sinon du classement.
    var isPlayerStat: Bool { self == .scorers || self == .assists || self == .combo || self == .ratings }
    /// Vrai si la stat exige les cartons par équipe (/teams/statistics, N appels).
    var isFairPlay: Bool { self == .fairPlay }
}

struct CompetitionStatsView: View {
    let competition: Competition
    var groupApiId: Int? = nil
    /// Sous-ensemble de rubriques à proposer dans le menu. Par défaut toutes.
    /// Les coupes d'Europe (mixed) n'exposent que Buteurs/Passeurs/Combos/Attaques/
    /// Défenses (les séries et classements domicile/extérieur n'ont pas de sens sur
    /// une phase de ligue partielle).
    var availableKinds: [StatKind] = StatKind.allCases

    @State private var kind: StatKind = .scorers
    // Données joueurs et classement.
    // • players   : meilleurs buteurs (/players/topscorers) — sert aussi aux notes.
    // • assisters : meilleurs passeurs (/players/topassists) — endpoint dédié, sinon
    //               on ne verrait que les passes des buteurs et le classement passeurs
    //               serait faux.
    @State private var players: [AFPlayerResponse] = []
    @State private var assisters: [AFPlayerResponse] = []
    @State private var standings: [AFStandingEntry] = []
    @State private var fairPlay: [FairPlayEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// Vrai une fois qu'un chargement s'est terminé (sert à distinguer « pas encore
    /// chargé » de « chargé mais vide » pour l'écran « saison pas commencée »).
    @State private var didLoad = false

    /// Championnat national (par opposition à une coupe d'Europe). Pour ces
    /// compétitions, l'API ne fait PLUS de repli sur la saison précédente
    /// (voir APIService.seasonsToTry) : si la saison en cours n'a pas démarré, tout
    /// est vide → on affiche un écran « saison pas encore commencée » plutôt que des
    /// stats d'une autre saison ou une liste vide sans explication.
    private var isDomesticLeague: Bool {
        competition.kind == .league || competition.kind == .leagueGroups
    }

    /// Saison pas encore démarrée : championnat national, chargement terminé sans
    /// erreur, et la donnée pertinente pour la rubrique courante est vide → rien
    /// n'a encore été joué (le repli saison précédente est désactivé pour ces
    /// compétitions, cf. APIService.seasonsToTry).
    private var seasonNotStarted: Bool {
        guard isDomesticLeague, didLoad, errorMessage == nil else { return false }
        switch kind {
        case .fairPlay:        return false          // le fair-play garde son propre message
        case .assists:         return assisters.isEmpty
        case .combo:           return players.isEmpty && assisters.isEmpty
        case .scorers, .ratings: return players.isEmpty
        default:               return standings.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sélecteur de statistique (menu déroulant compact).
            Menu {
                ForEach(availableKinds) { k in
                    Button {
                        kind = k
                    } label: {
                        Label(L(k.titleKey), systemImage: k.icon)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: kind.icon)
                    Text(L(kind.titleKey)).fontWeight(.semibold)
                    Image(systemName: "chevron.down").font(.caption2)
                    Spacer()
                }
                .font(.subheadline)
                .foregroundColor(competition.color)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
            }

            Divider()

            Group {
                if isLoading {
                    LoadingView(label: L("loading"))
                } else if let err = errorMessage {
                    ErrorView(message: err) { Task { await load() } }
                } else {
                    content
                }
            }
        }
        .task {
            // Aligne la rubrique initiale sur les rubriques disponibles.
            if !availableKinds.contains(kind), let first = availableKinds.first {
                kind = first
            }
            await load()
        }
        .onChange(of: kind) { _, _ in Task { await load() } }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .scorers:     playersList(mode: .goals)
        case .assists:     playersList(mode: .assists)
        case .combo:       playersList(mode: .combo)
        case .ratings:     ratingsList
        case .bestAttack:  teamGoalsList(attack: true)
        case .bestDefense: teamGoalsList(attack: false)
        case .streaks:     streaksList
        case .home:        homeAwayRankingList(home: true)
        case .away:        homeAwayRankingList(home: false)
        case .fairPlay:    fairPlayList
        }
    }

    // MARK: Buteurs / Passeurs / Combo

    enum PlayerMode { case goals, assists, combo }

    private func sortedPlayers(mode: PlayerMode) -> [AFPlayerResponse] {
        // On n'affiche que les joueurs ayant une valeur > 0 pour la métrique
        // concernée : inutile de lister des passeurs à 0 passe décisive, etc.
        // (Décision user 2026-08-17 ; ne concerne pas le fair-play.)
        // Buteurs → liste topscorers ; Passeurs → liste topassists (endpoint dédié) ;
        // Combo → union des deux, dédupliquée par joueur.
        switch mode {
        case .goals:
            return players.filter { $0.goals > 0 }
                .sorted { $0.goals > $1.goals }
        case .assists:
            return assisters.filter { $0.assists > 0 }
                .sorted { $0.assists > $1.assists }
        case .combo:
            var byId: [Int: AFPlayerResponse] = [:]
            for p in players + assisters where byId[p.id] == nil { byId[p.id] = p }
            return byId.values.filter { ($0.goals + $0.assists) > 0 }
                .sorted { ($0.goals + $0.assists) > ($1.goals + $1.assists) }
        }
    }

    @ViewBuilder
    private func playersList(mode: PlayerMode) -> some View {
        let sorted: [AFPlayerResponse] = sortedPlayers(mode: mode)
        if sorted.isEmpty {
            emptyStat(icon: "soccerball", key: "empty.noScorers")
        } else {
            VStack(spacing: 0) {
                // En-tête calqué sur ScorersHeaderView ; on met en avant la
                // colonne pertinente (buts, passes, ou total combiné).
                StatsPlayerHeader(mode: mode)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(sorted.enumerated()), id: \.element.id) { index, player in
                            NavigationLink {
                                PlayerDetailView(playerId: player.player.id, fallbackName: player.player.name)
                            } label: {
                                StatsPlayerRow(rank: index + 1, player: player, mode: mode, competition: competition)
                                    .padding(.horizontal, 12)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    // Marge basse pour que la dernière ligne ne soit pas masquée
                    // par la barre d'onglets.
                    .padding(.bottom, 60)
                }
                .refreshable { await load() }
            }
        }
    }

    // MARK: Notes moyennes des joueurs
    // On classe les joueurs (issus des buteurs) par note moyenne décroissante.
    // On ignore ceux sans note (clubRating nil) : l'API ne fournit une note que
    // pour les joueurs ayant réellement disputé des minutes dans la compétition.

    @ViewBuilder
    private var ratingsList: some View {
        let rated: [AFPlayerResponse] = players
            .filter { $0.clubRating != nil }
            .sorted { ($0.clubRating ?? 0) > ($1.clubRating ?? 0) }
        if rated.isEmpty {
            emptyStat(icon: "star", key: "empty.noRatings")
        } else {
            VStack(spacing: 0) {
                // En-tête : # | Joueur | Note
                HStack {
                    Text("#").frame(width: 26, alignment: .center)
                    Text(L("col.player")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L("col.ratingShort")).frame(width: 44, alignment: .center).fontWeight(.bold)
                }
                .font(.caption2).foregroundColor(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color(.secondarySystemBackground))

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rated.enumerated()), id: \.element.id) { index, player in
                            NavigationLink {
                                PlayerDetailView(playerId: player.player.id, fallbackName: player.player.name)
                            } label: {
                                StatsRatingRow(rank: index + 1, player: player, competition: competition)
                                    .padding(.horizontal, 12)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .padding(.bottom, 60)
                }
                .refreshable { await load() }
            }
        }
    }

    /// État vide contextuel : « saison pas commencée » (championnat national sans
    /// données) ou le message générique fourni par la rubrique.
    @ViewBuilder
    private func emptyStat(icon: String, key: String) -> some View {
        if seasonNotStarted {
            EmptyStateView(icon: "calendar", text: L("stats.notStarted"))
        } else {
            EmptyStateView(icon: icon, text: L(key))
        }
    }

    // MARK: Meilleures attaques / défenses

    @ViewBuilder
    private func teamGoalsList(attack: Bool) -> some View {
        if standings.isEmpty {
            emptyStat(icon: "chart.bar", key: "empty.noStandings")
        } else {
            // Attaque = buts marqués (desc) ; défense = buts encaissés (asc).
            let ranked: [AFStandingEntry] = attack
                ? standings.sorted { $0.all.goals.for > $1.all.goals.for }
                : standings.sorted { $0.all.goals.against < $1.all.goals.against }
            VStack(spacing: 0) {
                // En-tête : # | Équipe | J | (buts)
                HStack {
                    Text("#").frame(width: 26, alignment: .center)
                    Text(L("col.team")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L("col.matchesShort")).frame(width: 30, alignment: .center)
                    Text(L("col.goalsShort")).frame(width: 34, alignment: .center).fontWeight(.bold)
                }
                .font(.caption2).foregroundColor(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color(.secondarySystemBackground))

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(ranked.enumerated()), id: \.element.id) { index, e in
                            let rank = index + 1
                            HStack {
                                StatsRankNumber(rank: rank)
                                TeamLogoView(urlString: e.team.logo, name: e.team.name, size: 18)
                                Text(e.team.displayName)
                                    .font(.caption).fontWeight(rank <= 3 ? .semibold : .regular)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(e.all.played)")
                                    .font(.caption).foregroundColor(.secondary)
                                    .frame(width: 30, alignment: .center)
                                Text("\(attack ? e.all.goals.for : e.all.goals.against)")
                                    .font(.caption).fontWeight(.bold)
                                    .foregroundColor(competition.color)
                                    .frame(width: 34, alignment: .center)
                            }
                            .padding(.vertical, 6).padding(.horizontal, 12)
                            Divider()
                        }
                    }
                    // Marge basse : évite que la barre d'onglets masque la dernière équipe.
                    .padding(.bottom, 60)
                }
                .refreshable { await load() }
            }
        }
    }

    // MARK: Fair-play (indiscipline — croissant, le plus fair-play en tête)

    @ViewBuilder
    private var fairPlayList: some View {
        if fairPlay.isEmpty {
            EmptyStateView(icon: "hand.raised", text: L("empty.noFairPlay"))
        } else {
            VStack(spacing: 0) {
                // En-tête : # | Équipe | J | 🟨 | 🟥 | Pts
                HStack {
                    Text("#").frame(width: 26, alignment: .center)
                    Text(L("col.team")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L("col.matchesShort")).frame(width: 28, alignment: .center)
                    yellowChip.frame(width: 26, alignment: .center)
                    redChip.frame(width: 26, alignment: .center)
                    Text(L("col.pointsShort")).frame(width: 34, alignment: .center).fontWeight(.bold)
                }
                .font(.caption2).foregroundColor(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color(.secondarySystemBackground))

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(fairPlay.enumerated()), id: \.element.id) { index, e in
                            let rank = index + 1
                            TeamProfileLink(teamId: e.team.id,
                                            previewName: e.team.name,
                                            previewLogo: e.team.logo) {
                                HStack {
                                    StatsRankNumber(rank: rank)
                                    TeamLogoView(urlString: e.team.logo, name: e.team.name, size: 18)
                                    Text(e.team.displayName)
                                        .font(.caption).fontWeight(rank <= 3 ? .semibold : .regular)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(e.played)")
                                        .font(.caption).foregroundColor(.secondary)
                                        .frame(width: 28, alignment: .center)
                                    Text("\(e.yellow)")
                                        .font(.caption).foregroundColor(.secondary)
                                        .frame(width: 26, alignment: .center)
                                    Text("\(e.red)")
                                        .font(.caption).foregroundColor(.secondary)
                                        .frame(width: 26, alignment: .center)
                                    Text("\(e.points)")
                                        .font(.caption).fontWeight(.bold)
                                        .foregroundColor(competition.color)
                                        .frame(width: 34, alignment: .center)
                                }
                                .padding(.vertical, 6).padding(.horizontal, 12)
                                .contentShape(Rectangle())
                            }
                            Divider()
                        }
                    }
                    // Avertissement couverture partielle (coupes d'Europe) : les cartons
                    // ne sont agrégés que sur la phase de ligue / de groupes.
                    if competition.section == .europe {
                        Label(L("fairPlay.euroPartial"), systemImage: "info.circle")
                            .font(.caption2).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20).padding(.top, 10)
                    }
                    // Note de bas de liste : barème + sens du classement.
                    Text(L("fairPlay.note"))
                        .font(.caption2).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20).padding(.top, 10)
                    .padding(.bottom, 60)
                }
                .refreshable { await load() }
            }
        }
    }

    /// Pastille jaune (en-tête colonne cartons jaunes).
    private var yellowChip: some View {
        RoundedRectangle(cornerRadius: 2).fill(Color.yellow)
            .frame(width: 9, height: 12)
    }
    /// Pastille rouge (en-tête colonne cartons rouges).
    private var redChip: some View {
        RoundedRectangle(cornerRadius: 2).fill(Color.red)
            .frame(width: 9, height: 12)
    }

    // MARK: Séries en cours (forme)

    @ViewBuilder
    private var streaksList: some View {
        if standings.isEmpty {
            emptyStat(icon: "chart.line.uptrend.xyaxis", key: "empty.noStandings")
        } else {
            // Tri par nombre de victoires dans les 5 derniers matchs (forme).
            let ranked = standings.sorted { winCount($0.form) > winCount($1.form) }
            VStack(spacing: 0) {
                HStack {
                    Text("#").frame(width: 26, alignment: .center)
                    Text(L("col.team")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L("stats.streaks")).frame(width: 110, alignment: .trailing)
                }
                .font(.caption2).foregroundColor(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color(.secondarySystemBackground))

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(ranked.enumerated()), id: \.element.id) { index, e in
                            let rank = index + 1
                            HStack {
                                StatsRankNumber(rank: rank)
                                TeamLogoView(urlString: e.team.logo, name: e.team.name, size: 18)
                                Text(e.team.displayName)
                                    .font(.caption).fontWeight(rank <= 3 ? .semibold : .regular)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                FormBadges(form: e.form)
                            }
                            .padding(.vertical, 6).padding(.horizontal, 12)
                            Divider()
                        }
                    }
                    // Marge basse : évite que la barre d'onglets masque la dernière équipe.
                    .padding(.bottom, 60)
                }
                .refreshable { await load() }
            }
        }
    }

    private func winCount(_ form: String?) -> Int {
        (form ?? "").filter { $0 == "W" }.count
    }

    // MARK: Classement à domicile / à l'extérieur (2 rubriques distinctes)

    @ViewBuilder
    private func homeAwayRankingList(home: Bool) -> some View {
        if standings.isEmpty {
            emptyStat(icon: home ? "house" : "airplane", key: "empty.noStandings")
        } else {
            // Tri par points du bloc concerné (V×3 + N), puis diff. de buts.
            let ranked = standings.sorted { a, b in
                let ba = home ? a.home : a.away
                let bb = home ? b.home : b.away
                let pa = ba.win * 3 + ba.draw
                let pb = bb.win * 3 + bb.draw
                if pa != pb { return pa > pb }
                return (ba.goals.for - ba.goals.against) > (bb.goals.for - bb.goals.against)
            }
            VStack(spacing: 0) {
                // En-tête : # | Équipe | J V N D | Pts
                HStack {
                    Text("#").frame(width: 26, alignment: .center)
                    Text(L("col.team")).frame(maxWidth: .infinity, alignment: .leading)
                    Text(L("col.matchesShort")).frame(width: 26, alignment: .center)
                    Text("V").frame(width: 22, alignment: .center)
                    Text("N").frame(width: 22, alignment: .center)
                    Text("D").frame(width: 22, alignment: .center)
                    Text("Pts").frame(width: 30, alignment: .center).fontWeight(.bold)
                }
                .font(.caption2).foregroundColor(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Color(.secondarySystemBackground))

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(ranked.enumerated()), id: \.element.id) { index, e in
                            let rank = index + 1
                            let b = home ? e.home : e.away
                            HStack {
                                StatsRankNumber(rank: rank)
                                TeamLogoView(urlString: e.team.logo, name: e.team.name, size: 18)
                                Text(e.team.displayName)
                                    .font(.caption).fontWeight(rank <= 3 ? .semibold : .regular)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(b.played)").font(.caption).foregroundColor(.secondary)
                                    .frame(width: 26, alignment: .center)
                                Text("\(b.win)").font(.caption).frame(width: 22, alignment: .center)
                                Text("\(b.draw)").font(.caption).frame(width: 22, alignment: .center)
                                Text("\(b.lose)").font(.caption).frame(width: 22, alignment: .center)
                                Text("\(b.win * 3 + b.draw)")
                                    .font(.caption).fontWeight(.bold)
                                    .foregroundColor(competition.color)
                                    .frame(width: 30, alignment: .center)
                            }
                            .padding(.vertical, 6).padding(.horizontal, 12)
                            Divider()
                        }
                    }
                    // Marge basse : évite que la barre d'onglets masque la dernière équipe.
                    .padding(.bottom, 60)
                }
                .refreshable { await load() }
            }
        }
    }

    // MARK: Chargement

    func load() async {
        isLoading = true; errorMessage = nil
        do {
            if kind.isFairPlay {
                fairPlay = await FootballAPIService.shared.fetchFairPlay(competition: competition)
            } else if kind.isPlayerStat {
                // Buteurs & notes → topscorers ; passeurs → topassists ; combo → les deux.
                let needScorers = (kind == .scorers || kind == .ratings || kind == .combo)
                let needAssists = (kind == .assists || kind == .combo)
                if needScorers {
                    if let gid = groupApiId {
                        players = try await FootballAPIService.shared.fetchTopScorers(competition: competition, groupApiId: gid)
                    } else {
                        players = try await FootballAPIService.shared.fetchTopScorers(competition: competition)
                    }
                }
                if needAssists {
                    if let gid = groupApiId {
                        assisters = try await FootballAPIService.shared.fetchTopAssists(competition: competition, groupApiId: gid)
                    } else {
                        assisters = try await FootballAPIService.shared.fetchTopAssists(competition: competition)
                    }
                }
            } else {
                if let gid = groupApiId {
                    // Surcharge par poule : renvoie déjà une liste plate.
                    standings = try await FootballAPIService.shared.fetchStandings(competition: competition, groupApiId: gid)
                } else {
                    // Surcharge agrégée : tableau de groupes → on aplatit.
                    let groups = try await FootballAPIService.shared.fetchStandings(competition: competition)
                    standings = groups.flatMap { $0 }
                }
            }
        } catch { errorMessage = error.localizedDescription }
        didLoad = true
        isLoading = false
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lignes/entêtes joueurs — mêmes tailles de police que ScorerRow (onglet Buteurs)
// ─────────────────────────────────────────────────────────────────────────────

private struct StatsPlayerHeader: View {
    let mode: CompetitionStatsView.PlayerMode
    var body: some View {
        HStack {
            Text("#").frame(width: 26, alignment: .center)
            Text(L("col.player")).frame(maxWidth: .infinity, alignment: .leading)
            // Colonne « matchs joués » retirée : l'endpoint topscorers renvoie une
            // valeur peu fiable (souvent 0 alors que le joueur a marqué).
            // Buteurs → uniquement la colonne Buts. Passeurs → uniquement Passes.
            // Combo → les trois (Passes, Buts, Total).
            if mode == .assists || mode == .combo {
                Text(L("col.assistsShort"))
                    .frame(width: 34, alignment: .center)
                    .fontWeight(mode == .assists ? .bold : .regular)
            }
            if mode == .goals || mode == .combo {
                Text(L("col.goalsShort"))
                    .frame(width: 34, alignment: .center)
                    .fontWeight(mode == .goals ? .bold : .regular)
            }
            if mode == .combo {
                Text(L("stats.comboShort")).frame(width: 34, alignment: .center).fontWeight(.bold)
            }
        }
        .font(.caption2).foregroundColor(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Color(.secondarySystemBackground))
    }
}

private struct StatsPlayerRow: View {
    let rank: Int
    let player: AFPlayerResponse
    let mode: CompetitionStatsView.PlayerMode
    let competition: Competition

    private var rankColor: Color? {
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
                Text(player.fullName)
                    .font(.caption).fontWeight(rank <= 3 ? .semibold : .regular)
                    .lineLimit(1)
                Text(player.teamName)
                    .font(.caption2).foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Buteurs → uniquement Buts. Passeurs → uniquement Passes. Combo → tout.
            // Passes : affichée en mode passeurs (mise en avant) et en combo.
            if mode == .assists || mode == .combo {
                Text("\(player.assists)")
                    .font(.caption)
                    .fontWeight(mode == .assists ? .bold : .regular)
                    .foregroundColor(mode == .assists ? competition.color : .secondary)
                    .frame(width: 34, alignment: .center)
            }
            // Buts : affichée en mode buteurs (mise en avant) et en combo.
            if mode == .goals || mode == .combo {
                Text("\(player.goals)")
                    .font(.caption)
                    .fontWeight(mode == .goals ? .bold : .regular)
                    .foregroundColor(mode == .goals ? competition.color : .primary)
                    .frame(width: 34, alignment: .center)
            }
            // Colonne total combiné (buts + passes) uniquement en mode combo.
            if mode == .combo {
                Text("\(player.goals + player.assists)")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(competition.color)
                    .frame(width: 34, alignment: .center)
            }
        }
        .padding(.vertical, 6)
    }
}

// Ligne « note moyenne » : rang + club + joueur + note (badge coloré).
private struct StatsRatingRow: View {
    let rank: Int
    let player: AFPlayerResponse
    let competition: Competition

    private var rankColor: Color? {
        switch rank {
        case 1: return .yellow
        case 2: return Color(.systemGray)
        case 3: return .orange
        default: return nil
        }
    }

    /// Couleur du badge selon la note (vert ≥7.5, olive ≥7, orange ≥6.5, gris sinon).
    private func ratingColor(_ r: Double) -> Color {
        switch r {
        case 7.5...: return Color(red: 0.12, green: 0.55, blue: 0.20)
        case 7.0..<7.5: return Color(red: 0.35, green: 0.55, blue: 0.15)
        case 6.5..<7.0: return .orange
        default: return Color(.systemGray)
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
                Text(player.fullName)
                    .font(.caption).fontWeight(rank <= 3 ? .semibold : .regular)
                    .lineLimit(1)
                Text(player.teamName)
                    .font(.caption2).foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            let r = player.clubRating ?? 0
            Text(String(format: "%.2f", r))
                .font(.caption).fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 44, height: 20)
                .background(ratingColor(r))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(.vertical, 6)
    }
}

// Numéro de rang compact (pastille or/argent/bronze pour le podium),
// calqué sur le style du rang de ScorerRow.
struct StatsRankNumber: View {
    let rank: Int
    private var color: Color? {
        switch rank {
        case 1: return .yellow
        case 2: return Color(.systemGray)
        case 3: return .orange
        default: return nil
        }
    }
    var body: some View {
        ZStack {
            if let c = color { Circle().fill(c.opacity(0.20)).frame(width: 20, height: 20) }
            Text("\(rank)")
                .font(.caption).fontWeight(rank <= 3 ? .bold : .regular)
                .foregroundColor(color ?? .secondary)
        }
        .frame(width: 26)
    }
}

// Pastilles de forme (5 derniers matchs) : V vert / N gris / D rouge.
struct FormBadges: View {
    let form: String?
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array((form ?? "").suffix(5).enumerated()), id: \.offset) { _, ch in
                Text(letter(ch))
                    .font(.caption2).fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(color(ch))
                    .clipShape(Circle())
            }
        }
    }
    private func color(_ c: Character) -> Color {
        switch c { case "W": return .green; case "D": return .gray; case "L": return .red; default: return .gray }
    }
    private func letter(_ c: Character) -> String {
        switch c { case "W": return "V"; case "D": return "N"; case "L": return "D"; default: return "-" }
    }
}
