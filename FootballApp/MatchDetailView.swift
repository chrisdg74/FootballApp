import SwiftUI

/// Page détail d'un match — fonctionne pour toutes les compétitions.
/// Onglets : Résumé (buts / cartons / remplacements), Compositions, Statistiques.
struct MatchDetailView: View {
    /// Le match de base (pour afficher immédiatement l'en-tête sans attendre le réseau).
    let fixture: AFFixture

    @Environment(\.dismiss) private var dismiss
    @State private var detail: AFFixtureFull?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            MatchHeaderView(fixture: fixture, onBack: { dismiss() })

            Picker("", selection: $selectedTab) {
                Text(L("match.summary")).tag(0)
                Text(L("match.lineups")).tag(1)
                Text(L("match.stats")).tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.vertical, 8)
            .background(Color(.systemBackground))

            Divider()

            Group {
                if isLoading {
                    LoadingView(label: L("loading"))
                } else if let err = errorMessage {
                    ErrorView(message: err) { Task { await load() } }
                } else {
                    switch selectedTab {
                    case 0: MatchEventsView(detail: detail, fixture: fixture)
                    case 1: MatchLineupsView(detail: detail)
                    default: MatchStatsView(detail: detail)
                    }
                }
            }
        }
        // On masque entièrement la barre de navigation native (sinon on obtient
        // un 2e bouton retour). Le retour est géré par notre bouton dans la bannière
        // + le geste de balayage depuis le bord gauche. Sous NavigationStack,
        // `.toolbar(.hidden, for: .navigationBar)` est le modificateur moderne
        // (remplace `.navigationBarHidden(true)`, déprécié).
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    func load() async {
        isLoading = true; errorMessage = nil
        do { detail = try await FootballAPIService.shared.fetchMatchDetail(fixtureId: fixture.id) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// En-tête : score + logos + statut
// ─────────────────────────────────────────────────────────────────────────────
struct MatchHeaderView: View {
    let fixture: AFFixture
    var onBack: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            // Bouton retour custom (unique) aligné à gauche
            if let onBack {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
            }

            // Compétition + journée sur UNE seule ligne : « Ligue 2 · J2 »,
            // avec la date/heure juste en dessous.
            VStack(spacing: 2) {
                Text(competitionLine)
                    .font(.caption).fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1).minimumScaleFactor(0.8)
                if let date = dateLine {
                    Text(date)
                        .font(.caption2).foregroundColor(.white.opacity(0.7))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }

            HStack(alignment: .center, spacing: 0) {
                // Domicile
                VStack(spacing: 8) {
                    TeamLogoView(urlString: fixture.teams.home.logo, name: fixture.teams.home.name, size: 48, teamId: fixture.teams.home.id)
                    Text(fixture.teams.home.displayName)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center).lineLimit(2)
                }
                .frame(maxWidth: .infinity)

                // Score central
                VStack(spacing: 6) {
                    if fixture.isFinished || fixture.isLive {
                        Text("\(fixture.goals.home ?? 0) – \(fixture.goals.away ?? 0)")
                            .font(.scoreBig)
                            .foregroundColor(.white)
                    } else {
                        Text("–")
                            .font(.scoreBig)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    if fixture.isLive {
                        LiveBadge(minute: fixture.fixture.status.elapsed.map { "\($0)'" })
                    } else {
                        Text(fixture.statusLabel)
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.85))
                    }
                    // Score à la mi-temps (uniquement ici, dans le résumé du match)
                    if (fixture.isFinished || fixture.isLive),
                       let ht = fixture.score?.halftime,
                       let hh = ht.home, let ah = ht.away {
                        Text("\(L("status.halftime")) \(hh) – \(ah)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .frame(width: 120)

                // Extérieur
                VStack(spacing: 8) {
                    TeamLogoView(urlString: fixture.teams.away.logo, name: fixture.teams.away.name, size: 48, teamId: fixture.teams.away.id)
                    Text(fixture.teams.away.displayName)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center).lineLimit(2)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)

            // Infos pratiques (date · stade · arbitre) intégrées à l'en-tête bleu,
            // en discrétion (petit, blanc translucide) sous le score.
            if !infoLines.isEmpty {
                VStack(spacing: 2) {
                    ForEach(infoLines, id: \.self) { line in
                        Text(line)
                            .font(.caption2).foregroundColor(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.top, 12).padding(.bottom, 16).padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.10, green: 0.15, blue: 0.35),
                                    Color(red: 0.20, green: 0.30, blue: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    /// « Ligue 2 · J2 » — compétition et journée réunies sur une ligne.
    private var competitionLine: String {
        let comp = CompetitionNameLocalizer.localized(fixture.league.name)
        guard let round = fixture.league.round else { return comp }
        let r = round
            .replacingOccurrences(of: "Regular Season - ", with: "J")
            .replacingOccurrences(of: "Group Stage - ", with: "Gr. J")
        return r.isEmpty ? comp : "\(comp) · \(r)"
    }

    /// Date + heure du match, affichée sous « Ligue 2 · J2 ».
    private var dateLine: String? {
        guard let d = fixture.isoDate else { return nil }
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEE d MMM yyyy · HH:mm"
        f.timeZone = TimeZone.current
        return f.string(from: d).capitalized
    }

    /// Lignes d'infos pratiques (stade, arbitre) affichées en discret plus bas.
    private var infoLines: [String] {
        var out: [String] = []
        if let venue = fixture.fixture.venue?.name {
            if let city = fixture.fixture.venue?.city { out.append("\(venue) · \(city)") }
            else { out.append(venue) }
        }
        if let ref = fixture.fixture.referee, !ref.isEmpty {
            // « Arbitre : Prénom Nom » — on raccourcit à 2 mots max (souvent
            // l'API ajoute la nationalité, ex. « Geoffrey Kubler, French Guiana »).
            let clean = ref.split(separator: ",").first.map(String.init) ?? ref
            let shortName = clean
                .split(separator: " ", omittingEmptySubsequences: true)
                .prefix(2).joined(separator: " ")
            out.append("\(L("match.referee")) \(shortName)")
        }
        return out
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Résumé — 2 COLONNES (domicile / extérieur). Chaque équipe a son logo
// affiché UNE seule fois en tête de colonne (fini le petit blason répété à chaque
// ligne). Les événements se rangent dans la colonne de leur équipe, alignés.
//
// Hiérarchie visuelle voulue : les BUTS sont mis en avant (carte verte marquée,
// buteur en gras, ballon coloré) ; les CARTONS et REMPLACEMENTS sont secondaires
// (carte discrète, plus légère). C'est l'aspect (couleur/fond/poids) qui porte la
// hiérarchie, pas la taille de police.
// ─────────────────────────────────────────────────────────────────────────────
struct MatchEventsView: View {
    let detail: AFFixtureFull?
    let fixture: AFFixture

    var events: [AFEvent] { detail?.events ?? [] }

    private func sorted(_ list: [AFEvent]) -> [AFEvent] {
        list.sorted { ($0.time.elapsed, $0.time.extra ?? 0) < ($1.time.elapsed, $1.time.extra ?? 0) }
    }
    var goals: [AFEvent] { sorted(events.filter { $0.isGoal }) }
    var cards: [AFEvent] { sorted(events.filter { $0.isCard }) }
    var subs:  [AFEvent] { sorted(events.filter { $0.isSub }) }

    private var homeId: Int { fixture.teams.home.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if events.isEmpty {
                    EmptyStateView(icon: "list.bullet.rectangle", text: L("match.noEvents"))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else {
                    // Pas de ré-affichage des logos/noms d'équipes : déjà présents
                    // dans l'en-tête bleu, aligné avec le haut de l'écran.

                    // BUTS — mis en évidence.
                    twoColumnSection(title: L("match.sec.goals"),
                                     items: goals,
                                     emphasis: true)
                    // CARTONS / REMPLACEMENTS — secondaires.
                    twoColumnSection(title: L("match.sec.cards"),
                                     items: cards,
                                     emphasis: false)
                    twoColumnSection(title: L("match.sec.subs"),
                                     items: subs,
                                     emphasis: false)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            // Marge basse généreuse : évite que la barre d'onglets masque les
            // dernières lignes (bancs fournis = jusqu'à ~11 remplacements).
            .padding(.bottom, 80)
        }
    }

    // Section 2 colonnes : titre + une carte. Les événements domicile (gauche)
    // et extérieur (droite) sont appariés par index sur une MÊME rangée, ce qui
    // divise par deux la hauteur → tout tient à l'écran sans défilement.
    @ViewBuilder
    private func twoColumnSection(title: String, items: [AFEvent], emphasis: Bool) -> some View {
        if !items.isEmpty {
            // Répartition domicile / extérieur, ordre chronologique conservé.
            let home = items.filter { $0.team.id == homeId }
            let away = items.filter { $0.team.id != homeId }
            let rows = max(home.count, away.count)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: emphasis ? 15 : 13,
                                  weight: emphasis ? .heavy : .semibold))
                    .foregroundColor(emphasis ? Theme.text : Theme.textSoft)
                    .padding(.leading, 4)

                VStack(spacing: emphasis ? 2 : 3) {
                    ForEach(0..<rows, id: \.self) { idx in
                        PairedEventRow(
                            home: idx < home.count ? home[idx] : nil,
                            away: idx < away.count ? away[idx] : nil,
                            emphasis: emphasis
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, emphasis ? 4 : 3)
                        // Buts : fin séparateur discret. Cartons/remplacements : on
                        // s'appuie sur un léger espacement blanc (spacing 3) → aéré
                        // mais compact, sans le côté « pâté » d'un trait par ligne.
                        if emphasis, idx < rows - 1 {
                            Divider().padding(.horizontal, 10).opacity(0.4)
                        }
                    }
                }
                .padding(.vertical, emphasis ? 2 : 3)
                .background(
                    emphasis
                        ? Color.green.opacity(0.08)
                        : Color(.secondarySystemGroupedBackground)
                )
                .overlay(
                    // Liseré vert pour signaler la zone « buts ».
                    emphasis
                        ? RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.green.opacity(0.35), lineWidth: 1)
                        : nil
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

// Rangée appariée : événement domicile à gauche, extérieur à droite, sur la même
// ligne. Les deux moitiés occupent chacune la moitié de la largeur → alignement
// stable même quand l'une des deux est vide.
struct PairedEventRow: View {
    let home: AFEvent?
    let away: AFEvent?
    var emphasis: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let home {
                    EventContent(event: home, trailing: false, emphasis: emphasis)
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if let away {
                    EventContent(event: away, trailing: true, emphasis: emphasis)
                } else {
                    Color.clear.frame(height: 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

// Contenu d'un événement (minute + icône + joueur + sous-ligne passeur/mention),
// aligné à gauche (domicile) ou à droite (extérieur).
struct EventContent: View {
    let event: AFEvent
    let trailing: Bool
    var emphasis: Bool = false

    private var iconColor: Color {
        if event.isGoal { return .green }
        if event.isCard { return event.detail.contains("Red") ? .red : .yellow }
        if event.isSub  { return .blue }
        return .secondary
    }

    // Tailles : buts mis en avant, cartons/remplacements nettement plus petits.
    private var iconSize: CGFloat { event.isGoal ? 14 : (emphasis ? 12 : 10) }
    private var nameSize: CGFloat { emphasis ? 13 : 11 }
    private var subSize:  CGFloat { emphasis ? 10 : 9 }
    private var minuteSize: CGFloat { emphasis ? 12 : 10 }
    /// Largeur FIXE de la colonne minute → « 6' », « 71' » ET « 90+3' » restent
    /// alignés sur UNE seule ligne (le nom démarre toujours à la même abscisse).
    /// Assez large pour le temps additionnel (« 90+3' ») sans retour à la ligne.
    private var minuteWidth: CGFloat { emphasis ? 44 : 40 }

    private var iconView: some View {
        Image(systemName: event.symbol)
            .font(.system(size: iconSize, weight: event.isGoal ? .bold : .regular))
            .foregroundColor(iconColor)
    }

    private var minuteView: some View {
        Text(event.minuteLabel)
            .font(.system(size: minuteSize, weight: .bold).monospacedDigit())
            .foregroundColor(Theme.textSoft)
            // Une seule ligne, même pour « 90+3' » (temps additionnel) : jamais de
            // retour à la ligne, on réduit légèrement la police au pire des cas.
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // Largeur fixe + alignement vers le bord extérieur du terrain.
            .frame(width: minuteWidth, alignment: trailing ? .trailing : .leading)
    }

    // Sous-ligne : passeur (« → X ») pour un but, entrant (« ↔ X ») pour un
    // remplacement, ou mention (pen.)/(csc) pour un but sans passeur « normal ».
    private var subtitle: String? {
        if event.isGoal {
            if let key = event.goalDetailKey { return L(key) }
            if let a = event.assist?.name { return "→ \(a)" }
            return nil
        }
        if event.isSub, let inName = event.assist?.name { return "↔ \(inName)" }
        return nil
    }

    private var nameBlock: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
            Text(event.player.name ?? "—")
                .font(.system(size: nameSize, weight: emphasis ? .bold : .semibold))
                .foregroundColor(Theme.text).lineLimit(1)
            if let s = subtitle {
                Text(s).font(.system(size: subSize)).foregroundColor(Theme.textSoft).lineLimit(1)
            }
        }
    }

    var body: some View {
        // On compose l'ordre horizontal minute/icône/texte selon le côté pour que
        // tout « pointe » vers le centre du terrain. La minute a une largeur fixe,
        // donc les noms sont alignés quel que soit le nombre de chiffres.
        HStack(spacing: emphasis ? 7 : 6) {
            if trailing {
                nameBlock
                iconView
                minuteView
            } else {
                minuteView
                iconView
                nameBlock
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Compositions
// ─────────────────────────────────────────────────────────────────────────────
/// Marqueurs d'événements accumulés par un joueur au cours du match.
struct PlayerBadges {
    var goals = 0
    var yellow = 0
    var red = 0
    var subbedOut = false   // remplacé (sorti)
    var subbedIn = false    // entré en jeu

    var isEmpty: Bool { goals == 0 && yellow == 0 && red == 0 && !subbedOut && !subbedIn }
}

struct MatchLineupsView: View {
    let detail: AFFixtureFull?
    @State private var selectedTeam = 0   // 0 = domicile, 1 = extérieur

    var lineups: [AFLineup] { detail?.lineups ?? [] }

    /// Construit une table id de joueur → badges, à partir des événements du match.
    private var badgesByPlayer: [Int: PlayerBadges] {
        var map: [Int: PlayerBadges] = [:]
        for e in (detail?.events ?? []) {
            if e.isGoal, let pid = e.player.id {
                map[pid, default: PlayerBadges()].goals += 1
            } else if e.isCard, let pid = e.player.id {
                if e.detail.contains("Red") { map[pid, default: PlayerBadges()].red += 1 }
                else { map[pid, default: PlayerBadges()].yellow += 1 }
            } else if e.isSub {
                // API : player = celui qui SORT, assist = celui qui ENTRE
                if let out = e.player.id { map[out, default: PlayerBadges()].subbedOut = true }
                if let inn = e.assist?.id { map[inn, default: PlayerBadges()].subbedIn = true }
            }
        }
        return map
    }

    private func badges(for player: AFLineupPlayer) -> PlayerBadges {
        guard let id = player.id else { return PlayerBadges() }
        return badgesByPlayer[id] ?? PlayerBadges()
    }

    var body: some View {
        if lineups.count < 2 {
            EmptyStateView(icon: "person.3", text: L("match.noLineups"))
        } else {
            let lineup = lineups[min(selectedTeam, lineups.count - 1)]
            VStack(spacing: 8) {
                // Sélecteur d'équipe avec LOGO + nom (le Picker segmenté natif
                // n'accepte pas d'image ; on le remplace par 2 chips maison qui
                // affichent le blason de chaque club). L'onglet sélectionné est
                // surligné (fond blanc + ombre) comme un vrai contrôle segmenté.
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { idx in
                        TeamSegment(team: lineups[idx].team,
                                    isSelected: selectedTeam == idx)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) { selectedTeam = idx }
                            }
                    }
                }
                .padding(4)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 8)

                // Formation (si connue) + coach
                let startPlayers = lineup.startXI.map { $0.player }
                let canDrawPitch = PitchView.hasUsableGrid(startPlayers)
                // L'API-Football ne renvoie pas toujours la chaîne `formation` (souvent
                // nil sur les matchs de sélection / plan gratuit). Dans ce cas, on la
                // DÉDUIT du placement des joueurs (nb de joueurs par ligne, gardien exclu).
                let formationLabel = lineup.formation ?? PitchView.derivedFormation(startPlayers)
                HStack(spacing: 12) {
                    if let f = formationLabel, !f.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "sportscourt")
                            Text(f).fontWeight(.bold)
                        }
                    }
                    if let coach = lineup.coach?.name, !coach.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                            Text(coach)
                        }
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                if canDrawPitch {
                    // Terrain + banc dans un ScrollView : le terrain a une hauteur
                    // BORNÉE (plus de maxHeight:.infinity qui écrasait le banc et
                    // faisait chevaucher le titre « Remplaçants » sur le vert). Ainsi
                    // tout le groupe est visible, et scrollable si le banc est long.
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            PitchView(startXI: startPlayers, badgesProvider: badges)
                                .frame(height: 340)

                            // Remplaçants : grille 2 colonnes compacte SOUS le terrain
                            // (le user les juge importants : ils font partie du groupe).
                            if !lineup.substitutes.isEmpty {
                                Text(L("match.substitutes"))
                                    .font(.footnote).fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                    .padding(.top, 2)
                                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6),
                                                    GridItem(.flexible(), spacing: 6)],
                                          spacing: 4) {
                                    ForEach(Array(lineup.substitutes.enumerated()), id: \.offset) { _, wrap in
                                        SubChip(player: wrap.player, badges: badges(for: wrap.player))
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        // Marge basse généreuse : le dernier rang de remplaçants doit
                        // passer AU-DESSUS de la barre d'onglets (Compétitions/En
                        // direct/Favoris/Recherche), sinon il est masqué en bas.
                        .padding(.bottom, 96)
                    }
                } else {
                    // Pas de positions exploitables → liste des joueurs, triée par
                    // numéro de maillot croissant (les sans-numéro en fin de liste).
                    let sortedStarters = startPlayers
                        .sorted { ($0.number ?? Int.max) < ($1.number ?? Int.max) }
                    let sortedSubs = lineup.substitutes.map { $0.player }
                        .sorted { ($0.number ?? Int.max) < ($1.number ?? Int.max) }
                    List {
                        SwiftUI.Section {
                            ForEach(Array(sortedStarters.enumerated()), id: \.offset) { _, player in
                                LineupPlayerRow(player: player, badges: badges(for: player))
                            }
                        } header: {
                            Text(L("match.startingXI")).textCase(nil)
                        }

                        if !sortedSubs.isEmpty {
                            SwiftUI.Section {
                                ForEach(Array(sortedSubs.enumerated()), id: \.offset) { _, player in
                                    LineupPlayerRow(player: player, badges: badges(for: player))
                                }
                            } header: {
                                Text(L("match.substitutes")).textCase(nil)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
    }
}

/// Petite rangée de symboles d'événements (buts, cartons, remplacement).
struct EventBadgesView: View {
    let badges: PlayerBadges
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<badges.goals, id: \.self) { _ in
                Image(systemName: "soccerball").font(.system(size: 9))
                    .foregroundColor(.primary)
            }
            if badges.yellow > 0 {
                Rectangle().fill(Color.yellow)
                    .frame(width: 7, height: 10).cornerRadius(1)
            }
            if badges.red > 0 {
                Rectangle().fill(Color.red)
                    .frame(width: 7, height: 10).cornerRadius(1)
            }
            // Remplacement : double flèche bleue (jamais rouge → pas de confusion
            // avec un carton rouge). Sortant = flèche vers le bas, entrant = vers le haut,
            // toutes deux en bleu.
            if badges.subbedOut {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 9))
                    .foregroundColor(.blue)
            }
            if badges.subbedIn {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 9))
                    .foregroundColor(.blue)
            }
        }
    }
}

/// Puce compacte pour un remplaçant (numéro + nom court), défile horizontalement.
struct SubChip: View {
    let player: AFLineupPlayer
    var badges: PlayerBadges = PlayerBadges()

    private var shortName: String {
        let name = player.name ?? "—"
        return name.split(separator: " ").last.map(String.init) ?? name
    }

    var body: some View {
        HStack(spacing: 6) {
            // Numéro dans une pastille fixe pour aligner tous les noms.
            Text(player.number.map { "\($0)" } ?? "–")
                .font(.caption2).fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 20, alignment: .center)
            Text(shortName)
                .font(.caption).fontWeight(.medium)
                .lineLimit(1).minimumScaleFactor(0.8)
            if player.captain == true {
                Text("C")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(.black)
                    .frame(width: 12, height: 12)
                    .background(Color.yellow)
                    .clipShape(Circle())
            }
            Spacer(minLength: 0)
            if !badges.isEmpty {
                EventBadgesView(badges: badges)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Segment d'équipe (sélecteur avec logo) — remplace le Picker segmenté natif qui
// ne sait pas afficher d'image. Surligné quand sélectionné.
// ─────────────────────────────────────────────────────────────────────────────
struct TeamSegment: View {
    let team: AFTeam
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            TeamLogoView(urlString: team.logo, name: team.name, size: 20)
            Text(team.displayName)
                .font(.subheadline)
                .fontWeight(isSelected ? .bold : .medium)
                .foregroundColor(isSelected ? Theme.text : .secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color(.systemBackground) : Color.clear)
                .shadow(color: isSelected ? Color.black.opacity(0.12) : .clear,
                        radius: 2, x: 0, y: 1)
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Terrain de football avec placement des joueurs selon la formation
// ─────────────────────────────────────────────────────────────────────────────
struct PitchView: View {
    let startXI: [AFLineupPlayer]
    var badgesProvider: (AFLineupPlayer) -> PlayerBadges = { _ in PlayerBadges() }

    /// Vrai si on peut dessiner le terrain. On accepte DEUX sources de placement :
    ///  1) le champ `grid` ("ligne:colonne") pour TOUS les titulaires (idéal), OU
    ///  2) le champ `pos` (G/D/M/F) pour TOUS les titulaires (repli par ligne).
    /// Avant, on exigeait le grid pour tous → un seul joueur sans grid faisait
    /// basculer TOUT le match en liste (plus de terrain), même quand les positions
    /// étaient connues. On dessine désormais dès que l'une des deux sources suffit.
    static func hasUsableGrid(_ players: [AFLineupPlayer]) -> Bool {
        guard !players.isEmpty else { return false }
        let allHaveGrid = players.allSatisfy { p in
            guard let grid = p.grid,
                  Int(grid.split(separator: ":").first ?? "") != nil else { return false }
            return true
        }
        if allHaveGrid { return true }
        // Repli : positions G/D/M/F connues pour tout le monde.
        let allHavePos = players.allSatisfy { p in
            guard let pos = p.pos?.uppercased() else { return false }
            return ["G", "D", "M", "F"].contains(pos)
        }
        return allHavePos
    }

    /// Regroupe les joueurs par ligne tactique (délègue à `computeLines`).
    private var lines: [[AFLineupPlayer]] { PitchView.computeLines(startXI) }

    /// Regroupe les joueurs par ligne tactique.
    /// Priorité au champ `grid` ("ligne:colonne") : c'est lui qui donne le placement
    /// PRÉCIS (nb de colonnes par ligne → un vrai 4-3-3, 3-5-2, etc.). On l'utilise
    /// dès qu'une MAJORITÉ de joueurs l'ont, et on rattache les rares joueurs sans
    /// grid à la ligne correspondant à leur `pos` (G→ligne 1, D→2, M→3, F→dernière).
    /// Avant, on exigeait le grid pour les 11 → un seul joueur sans grid faisait
    /// basculer tout le monde sur le repli grossier par position (une pastille par
    /// ligne, mal réparties). Ne reste sur le repli pur `pos` que si aucun grid.
    /// Les lignes sont retournées du GARDIEN (index 0) vers l'ATTAQUE.
    static func computeLines(_ startXI: [AFLineupPlayer]) -> [[AFLineupPlayer]] {
        // (row, col) parsés depuis grid, pour les joueurs qui en ont un valide.
        let withGrid = startXI.compactMap { p -> (row: Int, col: Int, player: AFLineupPlayer)? in
            guard let grid = p.grid,
                  let row = Int(grid.split(separator: ":").first ?? "") else { return nil }
            let col = Int(grid.split(separator: ":").last ?? "") ?? 0
            return (row, col, p)
        }

        // Assez de grids (au moins la moitié) → placement précis par grid.
        if !withGrid.isEmpty && withGrid.count * 2 >= startXI.count {
            var byRow = Dictionary(grouping: withGrid, by: { $0.row })
            let sortedRows = byRow.keys.sorted()               // 1 = gardien, croissant
            let firstRow = sortedRows.first ?? 1
            let lastRow = sortedRows.last ?? sortedRows.count

            // Rattache chaque joueur SANS grid à une ligne d'après son `pos`.
            let placedIds = Set(withGrid.compactMap { $0.player.id })
            for p in startXI where !(p.id.map(placedIds.contains) ?? false) {
                let targetRow: Int
                switch p.pos?.uppercased() {
                case "G": targetRow = firstRow
                case "D": targetRow = min(firstRow + 1, lastRow)
                case "F": targetRow = lastRow
                default:  targetRow = max(firstRow, lastRow - 1)   // milieu par défaut
                }
                let nextCol = (byRow[targetRow]?.map { $0.col }.max() ?? 0) + 1
                byRow[targetRow, default: []].append((targetRow, nextCol, p))
            }

            return byRow.keys.sorted().map { key in
                byRow[key]!.sorted { $0.col < $1.col }.map { $0.player }
            }
        }

        // Repli pur : aucun grid → une ligne par position (placement approximatif).
        let order = ["G": 0, "D": 1, "M": 2, "F": 3]
        let grouped = Dictionary(grouping: startXI, by: { order[($0.pos ?? "M").uppercased()] ?? 2 })
        return grouped.keys.sorted().map { grouped[$0]! }
    }

    /// Déduit une chaîne de formation ("4-3-3") depuis le placement, en excluant
    /// la ligne du gardien. Renvoie nil si le placement n'a pas assez de lignes de
    /// champ (ex. données trop pauvres) pour éviter d'afficher une formation absurde.
    static func derivedFormation(_ startXI: [AFLineupPlayer]) -> String? {
        let lines = computeLines(startXI)
        guard lines.count >= 3 else { return nil }   // gardien + au moins 2 lignes
        let outfield = lines.dropFirst().map { $0.count }   // on retire la ligne gardien
        guard outfield.reduce(0, +) >= 7 else { return nil }
        return outfield.map(String.init).joined(separator: "-")
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Pelouse
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.45, blue: 0.20),
                                                  Color(red: 0.08, green: 0.36, blue: 0.16)],
                                         startPoint: .top, endPoint: .bottom))
                // Marquages
                PitchMarkings()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1.5)

                // Joueurs répartis par ligne (gardien en bas → attaque en haut)
                VStack(spacing: 0) {
                    ForEach(Array(lines.reversed().enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 0) {
                            ForEach(Array(line.enumerated()), id: \.offset) { _, player in
                                PlayerDot(player: player, badges: badgesProvider(player))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

/// Marquages du terrain (ligne médiane, rond central, surfaces).
struct PitchMarkings: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Ligne médiane
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        // Rond central
        let cr = r.width * 0.14
        p.addEllipse(in: CGRect(x: r.midX - cr, y: r.midY - cr, width: cr * 2, height: cr * 2))
        // Surface haut
        let boxW = r.width * 0.5, boxH = r.height * 0.14
        p.addRect(CGRect(x: r.midX - boxW/2, y: r.minY, width: boxW, height: boxH))
        // Surface bas
        p.addRect(CGRect(x: r.midX - boxW/2, y: r.maxY - boxH, width: boxW, height: boxH))
        return p
    }
}

/// Pastille d'un joueur sur le terrain : numéro + nom court.
struct PlayerDot: View {
    let player: AFLineupPlayer
    var badges: PlayerBadges = PlayerBadges()

    /// Nom raccourci : "K. Mbappé" -> "Mbappé" (dernier mot).
    private var shortName: String {
        let name = player.name ?? "—"
        return name.split(separator: " ").last.map(String.init) ?? name
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 30, height: 30)
                    .shadow(radius: 2)
                Text(player.number.map { "\($0)" } ?? "–")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0.08, green: 0.36, blue: 0.16))

                // Brassard capitaine : petit "C" doré en haut à droite
                if player.captain == true {
                    Text("C")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.black)
                        .frame(width: 14, height: 14)
                        .background(Color.yellow)
                        .clipShape(Circle())
                        .offset(x: 13, y: -13)
                }
            }
            Text(shortName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .shadow(radius: 1)

            // Symboles d'événements sous le nom (buts, cartons, sortie…)
            if !badges.isEmpty {
                EventBadgesView(badges: badges)
            }
        }
    }
}

struct LineupPlayerRow: View {
    let player: AFLineupPlayer
    var badges: PlayerBadges = PlayerBadges()

    var body: some View {
        HStack(spacing: 12) {
            Text(player.number.map { "\($0)" } ?? "–")
                .font(.caption).fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 24)
            Text(player.name ?? "—").font(.subheadline)
            if player.captain == true {
                Text("C")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(.black)
                    .frame(width: 14, height: 14)
                    .background(Color.yellow)
                    .clipShape(Circle())
            }
            if !badges.isEmpty {
                EventBadgesView(badges: badges)
            }
            Spacer()
            if let pos = player.pos {
                Text(pos).font(.caption2).foregroundColor(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet Statistiques — barres comparatives domicile / extérieur
// ─────────────────────────────────────────────────────────────────────────────
struct MatchStatsView: View {
    let detail: AFFixtureFull?

    var stats: [AFTeamStatistics] { detail?.statistics ?? [] }

    var body: some View {
        if stats.count < 2 {
            EmptyStateView(icon: "chart.bar", text: L("match.noStats"))
        } else {
            let home = stats[0]
            let away = stats[1]
            // On apparie les stats domicile/extérieur par TYPE (plus fiable que par
            // index), puis on trie selon l'ordre de priorité (possession, xG, tirs…).
            let rows = pairedRows(home: home, away: away)
            List {
                SwiftUI.Section {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        StatComparisonRow(
                            type: StatTypeLocalizer.localized(row.type),
                            homeValue: row.home?.display ?? "–",
                            awayValue: row.away?.display ?? "–",
                            homeFraction: row.homeFraction,
                            awayFraction: row.awayFraction
                        )
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                } header: {
                    HStack(spacing: 6) {
                        TeamLogoView(urlString: home.team.logo, name: home.team.name, size: 20)
                        Text(home.team.displayName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Theme.text)
                        Spacer()
                        Text(away.team.displayName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Theme.text)
                        TeamLogoView(urlString: away.team.logo, name: away.team.name, size: 20)
                    }
                    .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// Une ligne appariée domicile/extérieur pour une même statistique.
    struct StatRowData {
        let type: String
        let home: AFStatValue?
        let away: AFStatValue?

        /// Valeur numérique exploitable pour la barre (entier ou pourcentage/décimal).
        private static func numeric(_ v: AFStatValue?) -> Double? {
            switch v {
            case .int(let i): return Double(i)
            case .string(let s):
                // « 54% » → 54 ; « 1.8 » (xG) → 1.8.
                let cleaned = s.replacingOccurrences(of: "%", with: "")
                    .replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespaces)
                return Double(cleaned)
            default: return nil
            }
        }

        private var homeNum: Double? { Self.numeric(home) }
        private var awayNum: Double? { Self.numeric(away) }

        /// Part de la barre pour le domicile (0…1). nil si non chiffrable.
        var homeFraction: Double? {
            guard let h = homeNum, let a = awayNum else { return nil }
            let total = h + a
            return total > 0 ? h / total : 0.5
        }
        var awayFraction: Double? {
            guard let f = homeFraction else { return nil }
            return 1 - f
        }
    }

    /// Apparie les stats des deux équipes par type puis trie par priorité.
    private func pairedRows(home: AFTeamStatistics, away: AFTeamStatistics) -> [StatRowData] {
        // Index extérieur par type brut normalisé.
        var awayByType: [String: AFStatValue?] = [:]
        for item in away.statistics {
            awayByType[item.type.lowercased()] = item.value
        }
        var seen = Set<String>()
        var rows: [StatRowData] = []
        for item in home.statistics {
            let key = item.type.lowercased()
            seen.insert(key)
            rows.append(StatRowData(type: item.type,
                                    home: item.value,
                                    away: awayByType[key] ?? nil))
        }
        // Types présents seulement côté extérieur.
        for item in away.statistics where !seen.contains(item.type.lowercased()) {
            rows.append(StatRowData(type: item.type, home: nil, away: item.value))
        }
        return rows.sorted {
            StatTypeLocalizer.sortRank(for: $0.type) < StatTypeLocalizer.sortRank(for: $1.type)
        }
    }
}

struct StatComparisonRow: View {
    let type: String
    let homeValue: String
    let awayValue: String
    var homeFraction: Double? = nil
    var awayFraction: Double? = nil

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(homeValue)
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundColor(Theme.text)
                Spacer()
                Text(type)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSoft)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer()
                Text(awayValue)
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundColor(Theme.text)
            }
            comparisonBar
        }
        .padding(.vertical, 1)
    }

    /// Barre de comparaison : part domicile (gauche, verte) vs extérieur (droite,
    /// bleue). Le côté qui domine est plus opaque. Masquée si non chiffrable.
    @ViewBuilder
    private var comparisonBar: some View {
        if let hf = homeFraction, let af = awayFraction {
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.green.opacity(hf >= af ? 0.9 : 0.4))
                        .frame(width: max(2, w * hf - 1))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue.opacity(af > hf ? 0.9 : 0.4))
                        .frame(width: max(2, w * af - 1))
                }
            }
            .frame(height: 4)
        } else {
            Color.clear.frame(height: 0)
        }
    }
}
