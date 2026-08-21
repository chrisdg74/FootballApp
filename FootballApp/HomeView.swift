import SwiftUI

// ═════════════════════════════════════════════════════════════════════════════
// ACCUEIL — « Bonjour {prénom} » + prochains matchs des favoris
// ─────────────────────────────────────────────────────────────────────────────
// Premier onglet de l'app (page ouverte à l'accès). Salutation personnalisée
// (prénom local, sans compte) puis, EN DESSOUS, les prochains matchs des favoris,
// segmentés en CLUBS / JOUEURS / NATIONS. On n'affiche qu'UN match par favori
// (le prochain), jamais toute la liste des matchs à venir.
//
// Choix user 2026-08-17 : l'ACCUEIL et le LIVE sont deux choses distinctes. Le
// Live ne montre que les matchs DU JOUR ; l'Accueil porte la salutation + ce bloc
// « prochains matchs de mes favoris » (qui vivait auparavant dans LiveView).
//
// Périmètre des « prochains matchs » :
//   • CLUBS   → prochain match de chaque club favori (championnat + coupe) ;
//   • JOUEURS → prochain match de chaque joueur suivi, en considérant son CLUB
//               (championnat + coupe) ET sa SÉLECTION NATIONALE (nations) ;
//   • NATIONS → prochain match de chaque sélection nationale favorite.
//
// Source des matchs : `fetchFavoritesFixtures` (fetch LÉGER) — une requête `team=`
// par équipe favorite / club / sélection, EN PARALLÈLE, SANS balayer le catalogue
// (contrairement au Live). C'est ce qui rend le lancement rapide. Aucune donnée
// inventée : tout vient d'AFFixture.
// ═════════════════════════════════════════════════════════════════════════════

struct HomeView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var followedPlayers: FollowedPlayersStore
    @EnvironmentObject private var profile: UserProfileStore

    /// Matchs des équipes favorites/joueurs suivis (fetch léger), filtrés localement
    /// pour ne garder que le prochain match de chaque favori.
    @State private var allFixtures: [AFFixture] = []
    @State private var isLoading = false
    @State private var showSettings = false

    /// Cache id-joueur → id-club actuel (résolu via l'API si absent du snapshot).
    @State private var playerTeamIds: [Int: Int] = [:]
    /// Cache id-joueur → id-sélection nationale (résolu via l'API).
    @State private var playerNationalIds: [Int: Int] = [:]
    /// Empêche les résolutions concurrentes multiples.
    @State private var resolvingPlayers = false

    // ── Segment « Clubs / Joueurs / Nations » ───────────────────────────────────
    enum NextScope: Int, CaseIterable, Identifiable {
        case clubs, players, nations
        var id: Int { rawValue }
        var titleKey: String {
            switch self {
            case .clubs:   return "home.next.clubs"
            case .players: return "home.next.players"
            case .nations: return "home.next.nations"
            }
        }
    }
    @State private var nextScope: NextScope = .clubs
    @Namespace private var nextScopeAnim

    /// Sous-chip sélectionnée (un favori) par scope. On mémorise l'index choisi pour
    /// chaque onglet afin qu'il reste stable en revenant dessus. Défaut : 0 (le 1er
    /// favori). Choix user 2026-08-18 : une sélection à la fois, 3 prochains matchs.
    @State private var selectedFavID: [NextScope: String] = [:]

    /// « Signature » de la liste des favoris : recharge seulement si elle change.
    private var favTeamIds: [Int] {
        var ids = Set(favorites.teams.map { $0.id })
        for p in followedPlayers.players {
            if let t = p.teamId { ids.insert(t) }
            if let t = playerTeamIds[p.id] { ids.insert(t) }
            if let t = playerNationalIds[p.id] { ids.insert(t) }
        }
        return Array(ids)
    }
    private var signature: String {
        favTeamIds.sorted().map(String.init).joined(separator: ",")
    }
    private var hasFavorites: Bool {
        !favorites.teams.isEmpty || !followedPlayers.players.isEmpty
    }

    // ── Carte « Jeu du jour » (quiz Ligue 1) ───────────────────────────────────
    // Bannière cliquable qui ouvre le quiz. Poste `.openQuiz` : c'est ContentView
    // (qui possède le fullScreenCover) qui présente réellement l'écran de jeu.
    private var quizCard: some View {
        Button {
            NotificationCenter.default.post(name: .openQuiz, object: nil)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(.white.opacity(0.18)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("quiz.card.title"))
                        .font(.headline).foregroundColor(.white)
                    Text(L("quiz.card.subtitle"))
                        .font(.caption).foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.brand, Theme.brandDeep],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // ── Corps ─────────────────────────────────────────────────────────────────
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    greetingCard

                    quizCard

                    if !hasFavorites {
                        noFavoritesCard
                    } else {
                        nextMatchesSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(L("home.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 10) {
                        if isLoading { ProgressView().scaleEffect(0.8) }
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .accessibilityLabel(L("settings.title"))
                    }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .refreshable { await load() }
        }
        // `signature` = ids favoris (clubs + sélections). Recharge à CHAQUE changement
        // (ajout/retrait d'un favori en cours de session) — pas de garde `isEmpty`,
        // sinon les nouveaux favoris n'apparaissaient qu'au redémarrage de l'app.
        // Le fetch est léger + mis en cache, donc un rechargement est peu coûteux.
        .task(id: signature) { await load() }
        .task(id: followedPlayers.players.map { $0.id }) {
            await resolvePlayerTeams()
            // Un joueur suivi → on a besoin de son club pour ses matchs : recharge.
            await load()
        }
    }

    // ── Carte de salutation ───────────────────────────────────────────────────
    private var greetingCard: some View {
        // Sous-titre retiré : « Les prochains matchs de vos favoris » faisait
        // doublon avec l'en-tête de la section juste en dessous.
        Text(greetingText)
            .font(.title.weight(.bold))
            .foregroundColor(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// « Bonjour Camille » si le prénom est renseigné, sinon « Bonjour » simple.
    private var greetingText: String {
        let name = profile.trimmedName
        if name.isEmpty { return L("home.hello") }
        return String(format: L("home.helloName"), name)
    }

    // ── Matchs EN DIRECT d'un favori (club, sélection ou club d'un joueur suivi) ──
    // On balaie la fenêtre déjà chargée et on garde ceux qui sont live ET qui
    // concernent une équipe favorite. Triés par minute écoulée décroissante.
    private var liveMatches: [AFFixture] {
        let favIds = Set(favTeamIds)
        return allFixtures
            .filter { $0.isLive
                && (favIds.contains($0.teams.home.id) || favIds.contains($0.teams.away.id)) }
            .sorted { ($0.fixture.status.elapsed ?? 0) > ($1.fixture.status.elapsed ?? 0) }
    }

    // ── Section EN DIRECT (bleu foncé, en tête de l'accueil) ─────────────────────
    // Affichée seulement s'il y a au moins un live d'un favori. Code visuel distinct
    // du reste (dégradé bleu nuit → cyan) pour attirer l'œil immédiatement.
    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                LivePulseDot(size: 7)
                Text(L("home.live.title"))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(.white)
                    .textCase(.uppercase)
                    .kerning(0.5)
            }
            .padding(.horizontal, 2)

            VStack(spacing: 8) {
                ForEach(liveMatches) { fixture in
                    NavigationLink(destination: MatchDetailView(fixture: fixture)) {
                        liveMatchRow(fixture)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.brandDeep, Color(red: 0.05, green: 0.13, blue: 0.30)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(Theme.brand.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Theme.brandDeep.opacity(0.35), radius: 10, y: 4)
    }

    /// Une ligne de match en direct : logos + noms + score live + minute écoulée.
    private func liveMatchRow(_ fixture: AFFixture) -> some View {
        HStack(spacing: 10) {
            // Équipes empilées à gauche (nom + logo).
            VStack(alignment: .leading, spacing: 6) {
                liveTeamLine(fixture.teams.home)
                liveTeamLine(fixture.teams.away)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Score live.
            VStack(alignment: .trailing, spacing: 6) {
                Text("\(fixture.goals.home ?? 0)")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("\(fixture.goals.away ?? 0)")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }

            // Minute écoulée.
            Text(liveMinuteLabel(fixture))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(Theme.brand)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    private func liveTeamLine(_ team: AFTeam) -> some View {
        HStack(spacing: 7) {
            TeamLogoView(urlString: team.logo, name: team.displayName,
                         size: 18, teamId: team.id)
            Text(team.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// « 63' » en jeu ; « MT » à la mi-temps ; « TAB » aux tirs au but.
    private func liveMinuteLabel(_ fixture: AFFixture) -> String {
        switch fixture.fixture.status.short {
        case "HT": return L("status.halftime.short")
        case "P":  return L("status.penalties.short")
        default:
            if let m = fixture.fixture.status.elapsed { return "\(m)'" }
            return fixture.fixture.status.short
        }
    }

    // ── Section « prochains matchs des favoris » (segment + cartes) ─────────────
    private var nextMatchesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // EN DIRECT en tête (code visuel bleu foncé + pastille « LIVE » pulsante).
            if !liveMatches.isEmpty {
                liveSection
            }

            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.brand)
                Text(L("home.next.title"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Theme.text)
            }

            SlidingSegmentedControl(segments: NextScope.allCases,
                                    selection: $nextScope,
                                    titleKey: { $0.titleKey },
                                    namespace: nextScopeAnim)

            if isLoading && allFixtures.isEmpty {
                // Squelette : cartes grisées pulsantes le temps du chargement. La
                // salutation reste affichée immédiatement → sensation « instantané ».
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in SkeletonCard() }
                }
            } else {
                scopeContent
            }
        }
    }

    // ── Entité favorite (une par sous-chip) ─────────────────────────────────────
    // Représente un favori sélectionnable dans la barre de sous-chips : un club, une
    // sélection nationale, ou un joueur suivi. `teamId` est l'équipe dont on affiche
    // les prochains matchs (pour un joueur, c'est son CLUB actuel résolu par l'API).
    struct FavEntity: Identifiable {
        enum Kind { case team, player }
        let key: String            // identité stable (préfixe + id)
        let displayName: String
        let logo: String?          // logo club / drapeau sélection
        let playerPhoto: String?   // photo joueur (scope .players)
        let teamId: Int            // équipe dont on montre les matchs
        let kind: Kind
        var id: String { key }
    }

    /// Liste des sous-chips pour le scope courant (une entité par favori).
    private func entities(for scope: NextScope) -> [FavEntity] {
        switch scope {
        case .clubs:
            return favorites.teams
                .filter { !($0.national ?? false) }
                .map { FavEntity(key: "club-\($0.id)", displayName: $0.name,
                                 logo: $0.logo, playerPhoto: nil,
                                 teamId: $0.id, kind: .team) }
        case .nations:
            return favorites.teams
                .filter { $0.national ?? false }
                .map { FavEntity(key: "nat-\($0.id)", displayName: $0.name,
                                 logo: $0.logo, playerPhoto: nil,
                                 teamId: $0.id, kind: .team) }
        case .players:
            return followedPlayers.players.compactMap { p in
                // Club résolu par l'API en priorité (le snapshot peut être périmé).
                guard let clubId = playerTeamIds[p.id] ?? p.teamId else { return nil }
                return FavEntity(key: "pl-\(p.id)", displayName: p.name,
                                 logo: nil, playerPhoto: p.photo,
                                 teamId: clubId, kind: .player)
            }
        }
    }

    /// Entité actuellement sélectionnée pour le scope (défaut : la 1re).
    private func selectedEntity(for scope: NextScope) -> FavEntity? {
        let list = entities(for: scope)
        guard !list.isEmpty else { return nil }
        if let key = selectedFavID[scope], let match = list.first(where: { $0.key == key }) {
            return match
        }
        return list.first
    }

    @ViewBuilder
    private var scopeContent: some View {
        let list = entities(for: nextScope)
        if list.isEmpty {
            switch nextScope {
            case .clubs:   emptyRow(L("home.next.clubs.empty"))
            case .players: emptyRow(L("home.next.players.empty"))
            case .nations: emptyRow(L("home.next.nations.empty"))
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                favSubChips(list)
                if let entity = selectedEntity(for: nextScope) {
                    let nexts = nextMatches(forTeamId: entity.teamId, limit: 3)
                    if nexts.isEmpty {
                        emptyRow(L("home.next.none"))
                    } else {
                        // Composant UNIQUE partout : cartes blanches groupées par
                        // jour (même design que le Live et les journées de compét.).
                        // Le club/joueur/sélection sélectionné est mis en avant.
                        DayGroupedFixturesView(fixtures: nexts,
                                               highlightTeamId: entity.teamId)
                    }
                }
            }
        }
    }

    /// Grille de sous-chips (un favori par chip). Choix user 2026-08-18 : alignés sur
    /// plusieurs lignes, 3 par ligne (au lieu d'un défilement horizontal). Une seule
    /// sélection à la fois.
    @ViewBuilder
    private func favSubChips(_ list: [FavEntity]) -> some View {
        let currentKey = selectedEntity(for: nextScope)?.key
        // Vignettes VISUELLES (choix user 2026-08-19) : uniquement l'image du favori
        // (logo club, photo joueur, drapeau sélection), SANS nom — l'utilisateur
        // reconnaît ses favoris d'un coup d'œil, et le bloc se distingue nettement
        // des cartes de matchs en dessous. Le nom reste accessible au maintien
        // (`.contextMenu`). Grille adaptative de tuiles carrées arrondies.
        let columns = Array(repeating: GridItem(.adaptive(minimum: 60, maximum: 88), spacing: 10),
                            count: 1)
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(list) { entity in
                favVignette(entity, isSelected: entity.key == currentKey)
            }
        }
        .padding(.vertical, 2)
    }

    /// Une tuile-vignette d'un favori : image seule, anneau bleu si sélectionnée,
    /// nom au maintien (long press).
    @ViewBuilder
    private func favVignette(_ entity: FavEntity, isSelected: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFavID[nextScope] = entity.key
            }
        } label: {
            ZStack {
                if entity.kind == .player {
                    // Joueur : la PHOTO remplit toute la tuile (rendu premium).
                    PlayerVignette(name: entity.displayName,
                                   photo: entity.playerPhoto, cornerRadius: 16)
                        .frame(width: 60, height: 60)
                } else {
                    // Clubs & sélections : logo/drapeau centré sur fond blanc.
                    TeamLogoView(urlString: entity.logo,
                                 name: entity.displayName,
                                 size: 40, teamId: entity.teamId)
                        .frame(width: 60, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(isSelected ? Theme.brandSoft : Theme.surface)
                        )
                }
            }
            .frame(width: 60, height: 60)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Theme.brand : Theme.hairline,
                            lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? Theme.brand.opacity(0.18) : Color.black.opacity(0.04),
                    radius: isSelected ? 6 : 2, y: isSelected ? 2 : 1)
            .scaleEffect(isSelected ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        // Nom au maintien (long press) — visuel épuré par défaut, info à la demande.
        .contextMenu {
            Label(entity.displayName, systemImage: entity.kind == .player ? "person.fill" : "shield.fill")
        }
        .accessibilityLabel(entity.displayName)
    }

    /// Ligne « aucun prochain match » (état vide d'un segment).
    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(Theme.textSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    // ── État vide global (aucun favori) ─────────────────────────────────────────
    private var noFavoritesCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "star")
                .font(.system(size: 40))
                .foregroundColor(Theme.textFaint)
            Text(L("home.noFavorites.title"))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.text)
            Text(L("home.noFavorites.text"))
                .font(.footnote)
                .foregroundColor(Theme.textSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28).padding(.horizontal, 20)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .stroke(Theme.hairline, lineWidth: 1))
    }

    // ── Calcul des prochains matchs d'UN favori (les N plus proches) ─────────────
    // Choix user 2026-08-18 : une sous-chip sélectionnée à la fois → on montre les 3
    // prochains matchs de CE favori (et non un match par favori). On NE déduplique PAS
    // par équipe ici : on veut bien les 3 prochaines échéances de la même équipe.
    private func nextMatches(forTeamId teamId: Int, limit: Int) -> [AFFixture] {
        let now = Date()
        return allFixtures
            .filter { f in
                guard !f.isCancelledOrPostponed, !f.isLive, !f.isFinished,
                      let d = f.isoDate, d > now else { return false }
                return f.teams.home.id == teamId || f.teams.away.id == teamId
            }
            .sorted { ($0.isoDate ?? .distantFuture) < ($1.isoDate ?? .distantFuture) }
            .prefix(limit).map { $0 }
    }

    /// Résout, pour chaque joueur suivi, son CLUB actuel ET sa SÉLECTION nationale,
    /// via un appel /players?id= par joueur (mis en cache). Recharge la fenêtre si
    /// une nouvelle équipe est découverte, pour que son prochain match soit inclus.
    ///
    /// ⚠️ On IGNORE volontairement le `teamId` du snapshot ici : il a pu être stocké
    /// AVANT le correctif `clubTeamId` (bug « Mbappé → équipe de France »). Un
    /// snapshot pointant sur la sélection nationale ferait afficher 2× le match de
    /// la France (une fois comme « club », une fois comme « sélection ») et masquerait
    /// le vrai match de club (Real Madrid). On re-résout donc TOUJOURS le club ET la
    /// sélection depuis l'API, source d'autorité. Le cache empêche les appels répétés.
    @MainActor
    private func resolvePlayerTeams() async {
        guard !resolvingPlayers else { return }
        let missing = followedPlayers.players.filter { p in
            let clubKnown = playerTeamIds[p.id] != nil
            let nationKnown = playerNationalIds[p.id] != nil
            return !clubKnown || !nationKnown
        }
        guard !missing.isEmpty else { return }
        resolvingPlayers = true
        defer { resolvingPlayers = false }
        var discoveredNewTeam = false
        for player in missing {
            // ── CLUB : on résout d'abord via /players/teams (source d'autorité,
            //    INDÉPENDANTE de la saison, sélections nationales déjà exclues) —
            //    même chemin que la FICHE joueur, qui affiche bien « Real Madrid ».
            //    ⚠️ On NE se fie PLUS à `clubTeamId` seul : il dépend des stats de la
            //    saison courante et renvoie `nil` en début de saison si le joueur n'a
            //    encore joué qu'en sélection → l'accueil se rabattait alors sur le
            //    `teamId` du snapshot (l'équipe de France) et affichait ses matchs.
            if playerTeamIds[player.id] == nil {
                if let club = await FootballAPIService.shared
                    .fetchPlayerCurrentClub(playerId: player.id) {
                    playerTeamIds[player.id] = club.id
                    discoveredNewTeam = true
                }
            }
            // ── SÉLECTION nationale : via les stats de la saison (ligne « World »).
            //    On charge la fiche seulement si le club OU la sélection manque encore.
            let needsNation = playerNationalIds[player.id] == nil
            let needsClubFallback = playerTeamIds[player.id] == nil
            if needsNation || needsClubFallback,
               let detail = try? await FootballAPIService.shared
                .fetchPlayerDetail(playerId: player.id, season: 2026) {
                // Repli club si /players/teams n'a rien donné (rare).
                if playerTeamIds[player.id] == nil, let clubId = detail.clubTeamId {
                    playerTeamIds[player.id] = clubId
                    discoveredNewTeam = true
                }
                if playerNationalIds[player.id] == nil, let natId = detail.nationalTeamId {
                    playerNationalIds[player.id] = natId
                    discoveredNewTeam = true
                }
            }
        }
        if discoveredNewTeam { await load() }
    }

    // ── Chargement (même fenêtre que le Live, favoris + joueurs inclus) ──────────
    @MainActor
    private func load() async {
        guard hasFavorites else { allFixtures = []; return }
        isLoading = true
        // Fetch LÉGER : matchs des équipes favorites (clubs ET sélections favorites) +
        // CLUB des joueurs suivis — une requête `team=` par équipe, EN PARALLÈLE. On ne
        // balaie PLUS tout le catalogue au lancement → cold start bien plus rapide.
        // On n'inclut PLUS la sélection nationale des joueurs suivis : l'onglet Joueurs
        // n'affiche que leur match de club, et les sélections FAVORITES sont déjà dans
        // `favorites.teams` (onglet Nations).
        let playerClubIds: [Int] = followedPlayers.players.compactMap {
            playerTeamIds[$0.id] ?? $0.teamId
        }
        let allTeamIds = favorites.teams.map { $0.id } + playerClubIds
        allFixtures = (try? await FootballAPIService.shared
            .fetchFavoritesFixtures(teamIds: allTeamIds)) ?? allFixtures
        isLoading = false
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// Carte SQUELETTE (placeholder de chargement)
// ─────────────────────────────────────────────────────────────────────────────
// Reproduit grossièrement la forme d'une carte de match (ligne compétition +
// ligne équipes + ligne compte à rebours) en blocs gris arrondis qui « pulsent »
// doucement. Donne une sensation de chargement instantané, sans spinner.
// ═════════════════════════════════════════════════════════════════════════════
private struct SkeletonCard: View {
    @State private var pulse = false

    private var barColor: Color { Theme.textFaint.opacity(pulse ? 0.10 : 0.22) }

    private func bar(width: CGFloat, height: CGFloat = 12) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(barColor)
            .frame(width: width, height: height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            bar(width: 120, height: 11)                 // ligne compétition
            HStack(spacing: 8) {
                Circle().fill(barColor).frame(width: 22, height: 22)
                bar(width: 70)
                Spacer(minLength: 0)
                bar(width: 26, height: 16)              // badge « vs »
                Spacer(minLength: 0)
                bar(width: 70)
                Circle().fill(barColor).frame(width: 22, height: 22)
            }
            bar(width: 100, height: 11)                 // compte à rebours
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
