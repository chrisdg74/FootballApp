import SwiftUI

/// Détail d'une compétition de type championnat : Résultats / Classement / Journées
struct CompetitionDetailView: View {
    let competition: Competition
    @State private var selectedTab = 0
    /// Poule sélectionnée (leagueId) pour les championnats à poules distinctes
    /// (National 1 = 67/68/69). nil = compétition mono-poule (pas de sélecteur).
    /// Initialisée à la 1re poule dès l'init (évite un remontage au 1er affichage).
    @State private var selectedGroupApiId: Int?
    @Environment(\.dismiss) private var dismiss

    /// Onglet à ouvrir au premier affichage (0 = Résultats, 1 = Classement,
    /// 2 = Stats, 3 = Journées). Permet à l'assistant d'ouvrir directement le bon
    /// onglet (ex. la carte classement pousse vers l'onglet Classement).
    init(competition: Competition, initialTab: Int = 0) {
        self.competition = competition
        _selectedTab = State(initialValue: initialTab)
        // Multi-poule → présélectionne la 1re poule ; sinon nil (pas de sélecteur).
        let firstGroup = (competition.groupApiIds?.count ?? 0) > 1
            ? competition.groupApiIds?.first : nil
        _selectedGroupApiId = State(initialValue: firstGroup)
    }

    /// Vrai championnat à poules-ligues distinctes (plusieurs IDs API).
    private var isMultiPoule: Bool { (competition.groupApiIds?.count ?? 0) > 1 }

    var body: some View {
        VStack(spacing: 0) {
            CompetitionHeaderView(competition: competition) { dismiss() }

            Picker("", selection: $selectedTab) {
                Text(L("tab.results")).tag(0)
                Text(L("tab.standings")).tag(1)
                // Onglet Stats masqué quand l'API ne fournit pas les stats
                // joueurs (ex. Ligue 3) — évite un écran vide en permanence.
                if competition.hasScorers {
                    Text(L("tab.stats")).tag(2)
                }
                Text(L("tab.rounds")).tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.vertical, 8)
            .background(Color(.systemBackground))

            // Sélecteur de poule PARTAGÉ par les 4 onglets (National 1…).
            if isMultiPoule {
                pouleSelector
            }

            Divider()

            Group {
                switch selectedTab {
                case 0: CompetitionMatchesView(competition: competition, groupApiId: selectedGroupApiId)
                case 1: CompetitionStandingsView(competition: competition, groupApiId: selectedGroupApiId)
                case 2 where competition.hasScorers:
                    CompetitionStatsView(competition: competition, groupApiId: selectedGroupApiId)
                default: CompetitionRoundsView(competition: competition, groupApiId: selectedGroupApiId)
                }
            }
            // Recharge les onglets quand on change de poule (id() force le remontage).
            .id(selectedGroupApiId)
        }
        // CLÉ ANTI-TRONCATURE : l'en-tête déborde volontairement dans la safe area
        // du haut (`ignoresSafeArea(.top)`). SwiftUI propage alors le débordement
        // au conteneur, si bien que la List du bas passe SOUS la tab bar et sa
        // dernière ligne est masquée — `contentMargins` seul ne suffit pas car la
        // List déborde déjà. En posant un `safeAreaInset(.bottom)` de hauteur 0 sur
        // tout le VStack, on force SwiftUI à ré-ancrer le bas du contenu sur la
        // safe area réelle (au-dessus de la tab bar) : le débordement du haut ne
        // « fuit » plus vers le bas, et la dernière ligne remonte proprement.
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 0) }
        // La bannière colorée sert déjà de titre : on masque entièrement la barre
        // de navigation. Sous NavigationStack, `.toolbar(.hidden, for:)` remplace
        // l'ancien `.navigationBarHidden(true)` (déprécié) pour supprimer l'espace
        // réservé en haut qui laissait un grand vide au-dessus de la bannière.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // Chips de sélection de poule (Poule A / B / C…), sur grille horizontale.
    private var pouleSelector: some View {
        let ids = competition.groupApiIds ?? []
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(ids.enumerated()), id: \.element) { idx, id in
                    let isSel = selectedGroupApiId == id
                    Button { selectedGroupApiId = id } label: {
                        Text(pouleLabel(index: idx))
                            .font(.caption).fontWeight(isSel ? .bold : .regular)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(isSel ? competition.color : Color(.secondarySystemBackground))
                            .foregroundColor(isSel ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal).padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    /// Libellé « Poule A / B / C… » dérivé de l'index (ordre des IDs 67/68/69).
    private func pouleLabel(index: Int) -> String {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H"]
        let suffix = index < letters.count ? letters[index] : "\(index + 1)"
        return "\(L("standings.group")) \(suffix)"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// En-tête coloré
// ─────────────────────────────────────────────────────────────────────────────
struct CompetitionHeaderView: View {
    let competition: Competition
    var onBack: (() -> Void)? = nil

    var body: some View {
        // Bandeau dégradé qui remonte sous l'encoche. Le contenu (bouton retour +
        // titre) est empilé en VStack pour que RIEN ne soit tronqué.
        VStack(alignment: .leading, spacing: 0) {
            // Ligne du bouton retour (en haut).
            if let onBack = onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(.black.opacity(0.22), in: Circle())
                }
            }

            Spacer(minLength: 8)

            // Titre + sous-titre, alignés en bas du bandeau.
            HStack(spacing: 12) {
                // Drapeau retiré de la vignette (showsFlag: false) : il est désormais
                // placé JUSTE AVANT le nom de la compétition (choix user 2026-08-17),
                // comme dans les listes du hub.
                CompetitionArtworkView(competition: competition, size: 48, showsFlag: false)
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let flag = competition.countryCode?
                            .trimmingCharacters(in: .whitespaces), !flag.isEmpty {
                            Text(flag).font(.title3)
                        }
                        Text(L(competition.nameKey))
                            .font(.title2).fontWeight(.bold).foregroundColor(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Text(L(competition.subtitleKey))
                        .font(.caption).foregroundColor(.white.opacity(0.85))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .padding(.top, 4)
        .frame(maxWidth: .infinity)
        .frame(height: 118)
        .background(
            ZStack {
                if let photo = competition.assetPhoto {
                    // ── En-tête « photo » (ex. Ligue 2) ────────────────────────
                    // 1. Couleur PLEINE de la compétition en tout premier : c'est
                    //    elle qui remonte sous l'encoche / la barre d'état, pour que
                    //    cette zone soit un bandeau de couleur propre (jamais un bout
                    //    de photo tronqué par l'heure/wifi).
                    competition.color

                    // 2. La PHOTO en remplissage TOTAL de la zone (largeur ET hauteur).
                    //    Technique fiable : un Color.clear occupe toute la surface,
                    //    la photo est posée en .background avec .scaledToFill() +
                    //    .clipped() → elle couvre TOUJOURS toute la largeur, aucune
                    //    bande vide sur les côtés. `photoAnchor` choisit la tranche
                    //    verticale visible (haut/centre/bas, réglable PAR compétition).
                    // Remplissage TOTAL sans déformation : .scaledToFill() préserve
                    // le ratio RÉEL de chaque image (jamais étirée), l'agrandit pour
                    // couvrir toute la zone, et .clipped() rogne le débordement. Le
                    // .frame explicite sur la taille du conteneur (via GeometryReader)
                    // + alignment `photoAnchor` fixe la tranche verticale visible.
                    GeometryReader { geo in
                        Image(photo)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height,
                                   alignment: competition.photoAnchor)
                            .clipped()
                    }
                    .padding(.top, 44)   // réserve la barre d'état → photo dessous

                    // 3. Voile de couleur : soutenu à gauche/bas (sous le titre),
                    //    plus clair à droite/centre (on voit la photo).
                    LinearGradient(
                        colors: [
                            competition.color.opacity(0.86),
                            competition.color.opacity(0.42),
                            Color.black.opacity(0.28)
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                    // 4. Dégradé vertical : haut teinté → centre transparent → bas
                    //    assombri (titre bien lisible).
                    LinearGradient(
                        colors: [
                            competition.color.opacity(0.55),
                            Color.clear,
                            Color.black.opacity(0.30)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                } else {
                    // ── En-tête « dégradé + motif » (par défaut) ───────────────
                    // Dégradé plein de la compétition (Ligue 1 en bleu, LaLiga en rouge…).
                    competition.gradient
                    // Motif d'ambiance procédural (dessiné en code, teinté par le type
                    //  de compétition). Donne l'identité « contextualisée » demandée sans
                    //  photo distante ni droits d'image ; texte blanc toujours lisible.
                    CompetitionPatternView(competition: competition,
                                           cornerRadius: 0,
                                           intensity: 1.0)
                }
            }
            .ignoresSafeArea(edges: .top)
            .clipped()
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Résultats (14 jours glissants)
// ─────────────────────────────────────────────────────────────────────────────
struct CompetitionMatchesView: View {
    let competition: Competition
    /// Poule ciblée (leagueId) pour un championnat multi-poules ; nil = agrégé.
    var groupApiId: Int? = nil
    @State private var matches: [AFFixture] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// Nom de la journée affichée (ex. « J4 »), pour l'en-tête.
    @State private var roundLabel: String = ""
    /// Vrai quand aucune journée n'a encore été jouée et qu'on affiche, à la
    /// place, la PROCHAINE journée (championnat pas commencé / pause).
    @State private var showingUpcoming = false

    /// Matchs de la journée affichée, groupés par jour calendaire (l'ordre reste
    /// chronologique — une journée s'étale souvent sur un week-end).
    var grouped: [(String, [AFFixture])] {
        var g: [String: [AFFixture]] = [:]
        for m in matches { g[m.formattedDateSection, default: []].append(m) }
        return g.sorted { a, b in
            let da = matches.first { $0.formattedDateSection == a.0 }?.isoDate
            let db = matches.first { $0.formattedDateSection == b.0 }?.isoDate
            if let x = da, let y = db { return x < y }
            return a.0 < b.0
        }
    }

    var body: some View {
        Group {
            if isLoading {
                LoadingView(label: L("loading"))
            } else if let err = errorMessage {
                ErrorView(message: err) { Task { await load() } }
            } else if matches.isEmpty {
                EmptyStateView(icon: "calendar.badge.clock", text: L("empty.noMatch"))
            } else {
                List {
                    // En-tête : nom de la journée + éventuel bandeau « à venir ».
                    SwiftUI.Section {
                        HStack(spacing: 8) {
                            Image(systemName: showingUpcoming ? "calendar.badge.clock" : "calendar")
                            Text(roundLabel).fontWeight(.semibold)
                            if showingUpcoming {
                                Text("· \(L("matches.upcomingRound"))")
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .font(.subheadline)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    ForEach(grouped, id: \.0) { (date, day) in
                        SwiftUI.Section {
                            ForEach(day) { f in
                                NavigationLink(destination: MatchDetailView(fixture: f)) {
                                    FixtureRowView(fixture: f, showLeague: false, showsDateHeader: true)
                                }
                                .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
                            }
                        } header: {
                            Text(date).font(.subheadline).fontWeight(.semibold).textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load() }
                // Petite marge de confort en bas (le safeAreaInset du VStack gère
                // déjà la tab bar). 16 pt suffisent pour aérer la dernière ligne.
                .contentMargins(.bottom, 16, for: .scrollContent)
            }
        }
        .task { await load() }
    }

    func load() async {
        isLoading = true; errorMessage = nil; showingUpcoming = false
        do {
            // On raisonne par JOURNÉE (round), pas par fenêtre de dates : on veut
            // afficher UNIQUEMENT la dernière journée commencée (au moins 1 match
            // joué), ou à défaut la prochaine journée si rien n'a encore été joué.
            let all: [AFFixture]
            if let gid = groupApiId {
                all = try await FootballAPIService.shared.fetchAllFixtures(competition: competition, groupApiId: gid)
            } else {
                all = try await FootballAPIService.shared.fetchAllFixtures(competition: competition)
            }
            let (round, dayMatches, upcoming) = Self.pickRound(from: all)
            matches = dayMatches
            roundLabel = Self.shortRoundName(round)
            showingUpcoming = upcoming
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    /// Détermine la journée à afficher parmi TOUS les matchs de la saison :
    ///  • la DERNIÈRE journée ayant au moins un match joué (terminé/en cours) ;
    ///  • sinon (rien joué) la PROCHAINE journée (1er match à venir).
    /// Renvoie (nom de round, matchs de cette journée triés, `upcoming`).
    static func pickRound(from all: [AFFixture]) -> (String, [AFFixture], Bool) {
        func roundOf(_ f: AFFixture) -> String { f.fixture.round ?? f.league.round ?? "" }
        func isPlayed(_ f: AFFixture) -> Bool {
            let s = f.fixture.status.short.uppercased()
            return ["FT", "AET", "PEN", "1H", "2H", "HT", "ET", "P", "LIVE", "BT"].contains(s)
        }

        // Dernière journée commencée = round du match JOUÉ le plus récent.
        let played = all.filter(isPlayed)
        if let lastPlayed = played.max(by: { ($0.isoDate ?? .distantPast) < ($1.isoDate ?? .distantPast) }) {
            let round = roundOf(lastPlayed)
            let day = all.filter { roundOf($0) == round }
                         .sorted { ($0.isoDate ?? .distantPast) < ($1.isoDate ?? .distantPast) }
            return (round, day, false)
        }

        // Rien joué → prochaine journée (1er match à venir le plus proche).
        let now = Date()
        if let next = all
            .filter({ ($0.isoDate ?? .distantPast) >= now })
            .min(by: { ($0.isoDate ?? .distantFuture) < ($1.isoDate ?? .distantFuture) }) {
            let round = roundOf(next)
            let day = all.filter { roundOf($0) == round }
                         .sorted { ($0.isoDate ?? .distantPast) < ($1.isoDate ?? .distantPast) }
            return (round, day, true)
        }

        // Aucune date exploitable : on montre au plus les 10 derniers connus.
        return ("", Array(all.suffix(10)), false)
    }

    /// Nom court d'une journée : « Regular Season - 4 » → « J4 » ; garde le reste
    /// tel quel (phases finales, groupes…). Identique à CompetitionRoundsView.
    static func shortRoundName(_ round: String) -> String {
        if let r = round.range(of: "Regular Season - ") {
            return "J" + round[r.upperBound...]
        }
        if let r = round.range(of: "Group Stage - ") {
            return "Gr. J" + round[r.upperBound...]
        }
        return round
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Classement (multi-poules géré)
// ─────────────────────────────────────────────────────────────────────────────
struct CompetitionStandingsView: View {
    let competition: Competition
    /// Poule ciblée (leagueId) : quand fourni, on charge SEULEMENT cette poule
    /// et le sélecteur de poule interne est masqué (géré par la vue parente).
    var groupApiId: Int? = nil
    @State private var groups: [[AFStandingEntry]] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedGroup = 0

    var body: some View {
        Group {
            if isLoading {
                LoadingView(label: L("loading"))
            } else if let err = errorMessage {
                ErrorView(message: err) { Task { await load() } }
            } else if groups.isEmpty {
                EmptyStateView(icon: "list.number", text: L("empty.noStandings"))
            } else {
                VStack(spacing: 0) {
                    // Sélecteur interne UNIQUEMENT si aucune poule imposée par le
                    // parent ET qu'il y a plusieurs poules dans la réponse.
                    if groupApiId == nil && groups.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(0..<groups.count, id: \.self) { i in
                                    let gName = pouleLabel(groups[i].first?.group, index: i)
                                    Button { selectedGroup = i } label: {
                                        Text(gName)
                                            .font(.caption).fontWeight(selectedGroup == i ? .bold : .regular)
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(selectedGroup == i ? competition.color : Color(.secondarySystemBackground))
                                            .foregroundColor(selectedGroup == i ? .white : .primary)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(.horizontal).padding(.vertical, 8)
                        }
                        Divider()
                    }

                    StandingsHeaderView()

                    if selectedGroup < groups.count {
                        List(groups[selectedGroup]) { entry in
                            TeamProfileLink(teamId: entry.team.id,
                                            previewName: entry.team.name,
                                            previewLogo: entry.team.logo) {
                                StandingEntryRow(entry: entry, competition: competition)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                            .listRowSeparator(.hidden)
                        }
                        .listStyle(.plain)
                        .environment(\.defaultMinListRowHeight, 0)
                        .refreshable { await load() }

                        // Légende des couleurs d'enjeux (dépliable), sous le classement.
                        StakesLegendView(
                            stakes: StandingStakeClassifier.presentStakes(
                                in: groups[selectedGroup], competition: competition)
                        )
                    }
                }
            }
        }
        .task { await load() }
    }

    func load() async {
        isLoading = true; errorMessage = nil
        do {
            if let gid = groupApiId {
                // Une seule poule → un unique sous-tableau.
                let poule = try await FootballAPIService.shared.fetchStandings(competition: competition, groupApiId: gid)
                groups = poule.isEmpty ? [] : [poule]
                selectedGroup = 0
            } else {
                groups = try await FootballAPIService.shared.fetchStandings(competition: competition)
            }
        }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    /// Nettoie le nom de poule renvoyé par l'API pour l'afficher joliment.
    /// Ex. "Group A" / "National 1: Group A" / "Groupe A" → "Poule A".
    /// Repli : "Poule 1", "Poule 2"… si l'API ne fournit pas de lettre.
    func pouleLabel(_ raw: String?, index: Int) -> String {
        guard let raw = raw, !raw.isEmpty else { return "\(L("standings.group")) \(index + 1)" }
        // Récupère la dernière lettre/chiffre significatif (A, B, 1, 2…).
        let cleaned = raw
            .replacingOccurrences(of: "Group", with: "")
            .replacingOccurrences(of: "Groupe", with: "")
        // Cherche un token final court (lettre unique ou nombre).
        if let token = cleaned.split(whereSeparator: { " -:•".contains($0) }).last,
           token.count <= 2 {
            return "\(L("standings.group")) \(token)"
        }
        // Sinon on renvoie le nom nettoyé tel quel (ex. un nom régional).
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " -:•"))
        return trimmed.isEmpty ? "\(L("standings.group")) \(index + 1)" : trimmed
    }
}

struct StandingsHeaderView: View {
    var body: some View {
        HStack(spacing: 2) {
            Text("#").frame(width: 24, alignment: .center)
            Text(L("col.team"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            Text("J").frame(width: 20, alignment: .center)
            Text("G").frame(width: 20, alignment: .center)
            Text("N").frame(width: 20, alignment: .center)
            Text("P").frame(width: 20, alignment: .center)
            Text("+/-").frame(width: 30, alignment: .center)
            Text("Pts").frame(width: 30, alignment: .center).fontWeight(.bold)
        }
        .font(.caption2).foregroundColor(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Color(.secondarySystemBackground))
    }
}

struct StandingEntryRow: View {
    let entry: AFStandingEntry
    let competition: Competition

    /// Enjeu de la ligne (qualif Europe, montée, barrage, maintien, relégation…),
    /// déterminé via la description de l'API ou un repli par rang.
    private var stake: StandingStake? {
        StandingStakeClassifier.stake(for: entry, competition: competition)
    }
    private var stakeColor: Color? { stake?.color }

    var body: some View {
        HStack(spacing: 2) {
            // Barre de couleur d'enjeu, collée au bord gauche de la ligne.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(stakeColor ?? Color.clear)
                .frame(width: 3, height: 22)

            ZStack {
                if let c = stakeColor { Circle().fill(c.opacity(0.18)).frame(width: 18, height: 18) }
                Text("\(entry.rank)")
                    .font(.caption).fontWeight(entry.rank <= 3 ? .bold : .regular)
                    .foregroundColor(stakeColor ?? .secondary)
            }
            .frame(width: 21)

            TeamLogoView(urlString: entry.team.logo, name: entry.team.name, size: 20, teamId: entry.team.id)

            // Nom du club : plus grand et prioritaire sur les colonnes chiffrées
            // pour rester lisible ; réduit légèrement plutôt que de tronquer sec.
            Text(entry.team.displayName)
                .font(.subheadline).fontWeight(entry.rank <= 3 ? .semibold : .regular)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            Group {
                Text("\(entry.all.played)").frame(width: 20, alignment: .center)
                Text("\(entry.all.win)").frame(width: 20, alignment: .center)
                Text("\(entry.all.draw)").frame(width: 20, alignment: .center)
                Text("\(entry.all.lose)").frame(width: 20, alignment: .center)
                let gd = entry.goalsDiff
                Text(gd >= 0 ? "+\(gd)" : "\(gd)")
                    .frame(width: 30, alignment: .center)
                    .foregroundColor(gd > 0 ? .green : gd < 0 ? .red : .secondary)
                Text("\(entry.points)").frame(width: 30, alignment: .center).fontWeight(.bold)
            }
            .font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Navigation par journée
// ─────────────────────────────────────────────────────────────────────────────
struct CompetitionRoundsView: View {
    let competition: Competition
    /// Poule ciblée (leagueId) : journées de cette poule uniquement ; nil = agrégé.
    var groupApiId: Int? = nil
    @State private var rounds: [String] = []
    @State private var currentIndex = 0
    @State private var matches: [AFFixture] = []
    @State private var isLoadingRounds = false
    @State private var isLoadingMatches = false
    @State private var errorMessage: String?

    var currentRound: String? { rounds.indices.contains(currentIndex) ? rounds[currentIndex] : nil }

    var shortRoundName: String {
        currentRound?
            .replacingOccurrences(of: "Regular Season - ", with: "J")
            .replacingOccurrences(of: "Group Stage - ", with: "Gr. J") ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { if currentIndex > 0 { currentIndex -= 1 } } label: {
                    Image(systemName: "chevron.left").font(.title3)
                        .foregroundColor(currentIndex > 0 ? competition.color : .secondary)
                }.disabled(currentIndex <= 0)

                Spacer()
                if isLoadingRounds { ProgressView() }
                else { Text(shortRoundName).font(.headline).fontWeight(.semibold) }
                Spacer()

                Button { if currentIndex < rounds.count - 1 { currentIndex += 1 } } label: {
                    Image(systemName: "chevron.right").font(.title3)
                        .foregroundColor(currentIndex < rounds.count - 1 ? competition.color : .secondary)
                }.disabled(currentIndex >= rounds.count - 1)
            }
            .padding(.horizontal, 24).padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))

            Divider()

            if isLoadingMatches {
                LoadingView(label: L("loading"))
            } else if let err = errorMessage {
                ErrorView(message: err) { Task { await loadMatches() } }
            } else if matches.isEmpty {
                EmptyStateView(icon: "calendar", text: L("empty.noMatch"))
            } else {
                List {
                    ForEach(matches) { f in
                        NavigationLink(destination: MatchDetailView(fixture: f)) {
                            FixtureRowView(fixture: f, showLeague: false)
                        }
                        .listRowInsets(EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 12))
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                // Marge de confort (le safeAreaInset du VStack gère la tab bar).
                .contentMargins(.bottom, 16, for: .scrollContent)
            }
        }
        .task { await loadRounds() }
        .onChange(of: currentIndex) { _, _ in Task { await loadMatches() } }
    }

    func loadRounds() async {
        isLoadingRounds = true
        do {
            // Liste des journées + TOUS les matchs de la saison (pour repérer la
            // PROCHAINE journée à jouer, sur laquelle on ouvre par défaut).
            let all: [AFFixture]
            if let gid = groupApiId {
                rounds = try await FootballAPIService.shared.fetchRounds(competition: competition, groupApiId: gid)
                all = (try? await FootballAPIService.shared.fetchAllFixtures(competition: competition, groupApiId: gid)) ?? []
            } else {
                rounds = try await FootballAPIService.shared.fetchRounds(competition: competition)
                all = (try? await FootballAPIService.shared.fetchAllFixtures(competition: competition)) ?? []
            }
            currentIndex = Self.nextRoundIndex(rounds: rounds, fixtures: all)
            await loadMatches()
        } catch { errorMessage = error.localizedDescription }
        isLoadingRounds = false
    }

    /// Index de la PROCHAINE journée : celle du 1er match encore à jouer (NS).
    /// Repli : dernière journée avec ≥1 match joué, puis dernière de la liste.
    static func nextRoundIndex(rounds: [String], fixtures: [AFFixture]) -> Int {
        guard !rounds.isEmpty else { return 0 }
        func roundOf(_ f: AFFixture) -> String { f.fixture.round ?? f.league.round ?? "" }
        func isPlayed(_ f: AFFixture) -> Bool {
            let s = f.fixture.status.short.uppercased()
            return ["FT", "AET", "PEN", "1H", "2H", "HT", "ET", "P", "LIVE", "BT"].contains(s)
        }
        let now = Date()
        // 1) Journée du prochain match non joué (date future la plus proche).
        if let next = fixtures
            .filter({ !isPlayed($0) && ($0.isoDate ?? .distantPast) >= now })
            .min(by: { ($0.isoDate ?? .distantFuture) < ($1.isoDate ?? .distantFuture) }),
           let idx = rounds.firstIndex(of: roundOf(next)) {
            return idx
        }
        // 2) Sinon, journée du dernier match joué.
        if let lastPlayed = fixtures.filter(isPlayed)
            .max(by: { ($0.isoDate ?? .distantPast) < ($1.isoDate ?? .distantPast) }),
           let idx = rounds.firstIndex(of: roundOf(lastPlayed)) {
            return idx
        }
        // 3) Repli : dernière journée de la liste.
        return rounds.count - 1
    }

    func loadMatches() async {
        guard let round = currentRound else { return }
        isLoadingMatches = true; errorMessage = nil
        do {
            if let gid = groupApiId {
                matches = try await FootballAPIService.shared.fetchMatchesByRound(competition: competition, groupApiId: gid, round: round)
            } else {
                matches = try await FootballAPIService.shared.fetchMatchesByRound(competition: competition, round: round)
            }
        }
        catch { errorMessage = error.localizedDescription }
        isLoadingMatches = false
    }
}
