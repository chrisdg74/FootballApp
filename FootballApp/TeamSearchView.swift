import SwiftUI

// ═════════════════════════════════════════════════════════════════════════════
// RECHERCHE D'ÉQUIPE
// ─────────────────────────────────────────────────────────────────────────────
// Barre de recherche (avec anti-rebond) → liste de résultats → fiche équipe
// avec ses matchs (à venir + récents). Fonctionne pour toutes les équipes,
// tous championnats confondus (endpoint teams?search=).
// ═════════════════════════════════════════════════════════════════════════════

struct TeamSearchView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @State private var query = ""
    @State private var results: [AFTeamResult] = []
    @State private var playerResults: [AFPlayerProfile] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private var isSearching: Bool {
        query.trimmingCharacters(in: .whitespaces).count >= 3
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingView(label: L("loading"))
                } else if let err = errorMessage {
                    ErrorView(message: err) { runSearch(query) }
                } else if !isSearching {
                    // Barre de recherche vide → on montre les favoris (ou une
                    // invitation si aucun favori n'est encore enregistré).
                    if favorites.isEmpty {
                        searchPrompt
                    } else {
                        FavoritesListView(header: L("favorites.title"))
                    }
                } else if results.isEmpty && playerResults.isEmpty {
                    EmptyStateView(icon: "sportscourt", text: L("search.noResult"))
                } else {
                    List {
                        if !results.isEmpty {
                            SwiftUI.Section {
                                ForEach(results) { result in
                                    TeamRowLink(team: result.team)
                                }
                            } header: {
                                Text(L("search.section.teams"))
                                    .font(.subheadline).fontWeight(.semibold).textCase(nil)
                            }
                        }
                        if !playerResults.isEmpty {
                            SwiftUI.Section {
                                ForEach(playerResults) { p in
                                    PlayerSearchRow(profile: p)
                                }
                            } header: {
                                Text(L("search.section.players"))
                                    .font(.subheadline).fontWeight(.semibold).textCase(nil)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(L("search.title"))
            .navigationBarTitleDisplayMode(.large)
        }
        .searchable(text: $query, prompt: L("search.placeholder"))
        .onChange(of: query) { _, newValue in
            // Anti-rebond : on attend 400 ms après la dernière frappe.
            searchTask?.cancel()
            let q = newValue.trimmingCharacters(in: .whitespaces)
            guard q.count >= 3 else { results = []; errorMessage = nil; return }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
                await search(q)
            }
        }
    }

    /// Invitation initiale (aucun favori, aucune recherche en cours).
    private var searchPrompt: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 52))
                .foregroundColor(Theme.textFaint)
            Text(L("search.prompt"))
                .font(.subheadline)
                .foregroundColor(Theme.textSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private func runSearch(_ q: String) { Task { await search(q) } }

    @MainActor
    private func search(_ q: String) async {
        isLoading = true; errorMessage = nil
        // Équipes et joueurs recherchés en parallèle. Une erreur sur l'une des
        // deux requêtes ne doit pas masquer les résultats de l'autre.
        async let teamsTask = FootballAPIService.shared.searchTeams(query: q)
        async let playersTask = FootballAPIService.shared.searchPlayers(query: q)
        do { results = try await teamsTask } catch { results = [] }
        do { playerResults = try await playersTask } catch { playerResults = [] }
        isLoading = false
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ligne d'équipe (NavigationLink + étoile favori). Réutilisée par la recherche
// ET par la liste de favoris.
// ─────────────────────────────────────────────────────────────────────────────
struct TeamRowLink: View {
    let team: AFTeamInfo

    var body: some View {
        // L'étoile est un bouton indépendant, placée EN DEHORS du NavigationLink
        // pour qu'un tap sur l'étoile n'ouvre PAS la fiche (et inversement).
        HStack(spacing: 0) {
            NavigationLink(destination: TeamProfileView(team: team)) {
                TeamResultRow(team: team)
            }
            FavoriteStar(team: team)
                .padding(.leading, 4)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contenu d'une ligne d'équipe (logo + nom + pays + chevron)
// ─────────────────────────────────────────────────────────────────────────────
struct TeamResultRow: View {
    let team: AFTeamInfo

    var body: some View {
        HStack(spacing: 12) {
            TeamLogoView(urlString: team.logo, name: team.name, size: 34, teamId: team.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.displayName)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(Theme.text)
                if let country = team.country {
                    // « Sélection » seulement pour une VRAIE sélection (flag national
                    // ET nom = pays connu). L'API marque parfois `national` à tort sur
                    // des clubs (« Adh Brasil ») → on ne les étiquette pas « Sélection ».
                    let normName = team.name
                        .folding(options: .diacriticInsensitive, locale: .current).lowercased()
                    let isNation = (team.national ?? false) && CountryFlag.isCountryName(normName)
                    Text(isNation ? "\(country) · \(L("search.nationalTeam"))" : country)
                        .font(.caption2).foregroundColor(Theme.textSoft)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Étoile de favori — bouton qui bascule l'état favori d'une équipe.
// ─────────────────────────────────────────────────────────────────────────────
struct FavoriteStar: View {
    @EnvironmentObject private var favorites: FavoritesStore
    let team: AFTeamInfo

    private var isOn: Bool { favorites.isFavorite(team.id) }

    var body: some View {
        Button {
            favorites.toggle(team)
        } label: {
            Image(systemName: isOn ? "star.fill" : "star")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(isOn ? Theme.gold : Theme.textFaint)
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L(isOn ? "favorites.remove" : "favorites.add"))
    }
}

/// Étoile « suivre un joueur » (fiche joueur). Même style visuel que `FavoriteStar`.
struct PlayerFollowStar: View {
    @EnvironmentObject private var followed: FollowedPlayersStore
    let player: FollowedPlayer

    private var isOn: Bool { followed.isFollowed(player.id) }

    var body: some View {
        Button {
            followed.toggle(player)
        } label: {
            Image(systemName: isOn ? "star.fill" : "star")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(isOn ? Theme.gold : Theme.textFaint)
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L(isOn ? "player.unfollow" : "player.follow"))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Liste des équipes favorites (réutilisée dans la recherche vide + onglet Favoris)
// ─────────────────────────────────────────────────────────────────────────────
struct FavoritesListView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    var header: String? = nil

    var body: some View {
        List {
            if let header = header {
                SwiftUI.Section {
                    rows
                } header: {
                    Text(header).font(.subheadline).fontWeight(.semibold).textCase(nil)
                }
            } else {
                rows
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(favorites.teams) { fav in
            TeamRowLink(team: fav.teamInfo)
        }
        .onDelete { offsets in
            for i in offsets { favorites.remove(favorites.teams[i].id) }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ligne « joueur suivi » (NavigationLink + étoile suivi). Onglet Favoris.
// ─────────────────────────────────────────────────────────────────────────────
struct PlayerRowLink: View {
    let player: FollowedPlayer

    var body: some View {
        HStack(spacing: 0) {
            NavigationLink(destination: PlayerDetailView(playerId: player.id,
                                                         fallbackName: player.name)) {
                HStack(spacing: 12) {
                    PlayerAvatar(name: player.name, photo: player.photo, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.name)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(Theme.text)
                        if let club = player.teamName, !club.isEmpty {
                            Text(club).font(.caption2).foregroundColor(Theme.textSoft)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            PlayerFollowStar(player: player)
                .padding(.leading, 4)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ligne « joueur » dans les résultats de recherche.
// L'API `/players/profiles?search=` ne renvoie que l'identité (id, nom, photo,
// nationalité) — pas le club. `searchPlayers` résout ensuite le club actuel des
// premiers résultats (`resolvedClubName`) pour désambiguïser les homonymes
// (« Dembélé » ×N). On convertit vers `FollowedPlayer` et on réutilise
// `PlayerRowLink`, qui affiche déjà le club sous le nom.
// ─────────────────────────────────────────────────────────────────────────────
struct PlayerSearchRow: View {
    let profile: AFPlayerProfile

    var body: some View {
        PlayerRowLink(player: FollowedPlayer(id: profile.id,
                                             name: profile.displayName,
                                             photo: profile.photo,
                                             teamId: nil,
                                             teamName: profile.resolvedClubName))
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// ONGLET FAVORIS + RECHERCHE FUSIONNÉ (barre du bas)
// ─────────────────────────────────────────────────────────────────────────────
// Un seul onglet qui combine :
//   • la RECHERCHE (barre `.searchable`, clubs + joueurs) ;
//   • la BIBLIOTHÈQUE de favoris : clubs favoris + joueurs suivis.
// Quand la barre de recherche est VIDE → on montre la bibliothèque (clubs puis
// joueurs), avec bouton Réglages. Dès qu'on tape (≥ 3 caractères) → on montre les
// résultats. État totalement vide (aucun favori) → invitation à rechercher.
// ═════════════════════════════════════════════════════════════════════════════
/// Barre de recherche FIXE de l'écran Favoris (ne défile pas avec la liste).
/// On remplace `.searchable` par ce champ maison, placé dans un `safeAreaInset`,
/// pour qu'il reste ancré en haut de l'écran quel que soit le défilement.
private struct FavoritesSearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Theme.textFaint)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($focused)
                .foregroundColor(Theme.text)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.textFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface2)
        )
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

struct FavoritesTabView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var followed: FollowedPlayersStore
    @EnvironmentObject private var followedComps: FollowedCompetitionsStore

    @State private var query = ""
    @State private var results: [AFTeamResult] = []
    @State private var playerResults: [AFPlayerProfile] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var showSettings = false

    // ── Sous-onglets de la bibliothèque : Clubs / Joueurs / Nations ────────────
    // Choix user 2026-08-17 : « 3 favoris : clubs / joueurs / nations ». On
    // segmente la bibliothèque en 3 pour retrouver rapidement chaque type. Les
    // clubs et les sélections nationales vivent dans le MÊME store (`favorites`),
    // distingués par le drapeau `national` de l'équipe ; les joueurs ont leur store.
    // Ordre des chips (choix user 2026-08-18) : Compétitions, Clubs, Joueurs, Sélections.
    enum FavScope: Int, CaseIterable, Identifiable {
        case competitions, clubs, players, nations
        var id: Int { rawValue }
        var titleKey: String {
            switch self {
            case .clubs:        return "favorites.clubs"
            case .players:      return "favorites.players"
            case .nations:      return "favorites.nations"
            case .competitions: return "favorites.competitions"
            }
        }
    }
    @State private var favScope: FavScope = .clubs
    @Namespace private var favScopeAnim

    // Sous-onglet « Compétitions » : arborescence à 2 niveaux (Famille → Sous-famille).
    // Familles dépliées (niveau 1) et sous-familles dépliées (niveau 2), par clé.
    // Défaut (choix user 2026-08-18) : TOUT est fermé à l'ouverture (écran épuré).
    @State private var expandedFamilies: Set<String> = []
    @State private var expandedSubgroups: Set<String> = []

    private var isSearching: Bool {
        query.trimmingCharacters(in: .whitespaces).count >= 3
    }
    private var libraryEmpty: Bool { favorites.isEmpty && followed.isEmpty }

    /// Clubs favoris = équipes favorites qui NE sont PAS des sélections nationales.
    private var favoriteClubs: [FavoriteTeam] {
        favorites.teams.filter { !($0.national ?? false) }
    }
    /// Sélections favorites = équipes favorites marquées `national == true`.
    private var favoriteNations: [FavoriteTeam] {
        favorites.teams.filter { $0.national ?? false }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    searchResults
                } else if libraryEmpty {
                    emptyLibraryPrompt
                } else {
                    libraryList
                }
            }
            .navigationTitle(L("library.title"))
            // Titre COMPACT (`.inline`) : contrairement au grand titre, il ne se
            // replie pas au défilement — il reste donc FIXE en haut (demande user
            // 2026-08-19 : « le titre et la barre de recherche bougent, je les veux
            // fixes »).
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel(L("settings.title"))
                }
            }
            // Barre de recherche FIXE : on n'utilise plus `.searchable` (qui vit dans
            // le tiroir de la barre de nav et se replie avec le grand titre). On place
            // un champ personnalisé dans un `safeAreaInset(.top)` : cet en-tête reste
            // ancré en haut et NE défile jamais avec la liste.
            .safeAreaInset(edge: .top, spacing: 0) {
                FavoritesSearchField(text: $query, prompt: L("search.placeholder"))
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
        .onChange(of: query) { _, newValue in
            searchTask?.cancel()
            let q = newValue.trimmingCharacters(in: .whitespaces)
            guard q.count >= 3 else { results = []; playerResults = []; errorMessage = nil; return }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
                await search(q)
            }
        }
    }

    // ── Bibliothèque segmentée : Clubs / Joueurs / Nations ─────────────────────
    // Un sélecteur en pilule glissante en tête, puis la liste du sous-onglet actif.
    // Chaque sous-onglet a son propre état vide (« aucun club / joueur / nation »)
    // pour guider l'utilisateur vers la recherche.
    private var libraryList: some View {
        VStack(spacing: 0) {
            SlidingSegmentedControl(segments: FavScope.allCases,
                                    selection: $favScope,
                                    titleKey: { $0.titleKey },
                                    namespace: favScopeAnim)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

            switch favScope {
            case .clubs:        clubsList
            case .players:      playersList
            case .nations:      nationsList
            case .competitions: competitionsList
            }
        }
    }

    /// Sous-onglet CLUBS : équipes favorites hors sélections nationales.
    @ViewBuilder
    private var clubsList: some View {
        if favoriteClubs.isEmpty {
            librarySubEmpty(icon: "shield.lefthalf.filled", text: L("favorites.clubs.empty"))
        } else {
            List {
                ForEach(favoriteClubs) { fav in
                    TeamRowLink(team: fav.teamInfo)
                }
                .onDelete { offsets in
                    for i in offsets { favorites.remove(favoriteClubs[i].id) }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// Sous-onglet JOUEURS : joueurs suivis.
    @ViewBuilder
    private var playersList: some View {
        if followed.players.isEmpty {
            librarySubEmpty(icon: "person.fill", text: L("favorites.players.empty"))
        } else {
            List {
                ForEach(followed.players) { p in
                    PlayerRowLink(player: p)
                }
                .onDelete { offsets in
                    for i in offsets { followed.remove(followed.players[i].id) }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// Sous-onglet NATIONS : sélections nationales favorites.
    @ViewBuilder
    private var nationsList: some View {
        if favoriteNations.isEmpty {
            librarySubEmpty(icon: "flag.2.crossed.fill", text: L("favorites.nations.empty"))
        } else {
            List {
                ForEach(favoriteNations) { fav in
                    TeamRowLink(team: fav.teamInfo)
                }
                .onDelete { offsets in
                    for i in offsets { favorites.remove(favoriteNations[i].id) }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    /// Sous-onglet COMPÉTITIONS : sélection des compétitions suivies (= filtre par
    /// défaut de l'onglet Live). Arborescence à 2 niveaux (choix user 2026-08-18) :
    /// FAMILLE (Championnats / Coupes / Sélections) → SOUS-FAMILLE (France / Europe /
    /// Monde …). Chaque sous-famille est une liste de cases à cocher individuelles.
    /// Objectif : ne pas tout empiler, rendre la sélection fluide et intuitive.

    /// Une sous-famille : un libellé traduit, une clé d'expansion stable, ses comps.
    private struct CompSubgroup: Identifiable {
        let key: String
        let titleKey: String
        let comps: [Competition]
        var id: String { key }
    }

    /// Sous-familles de « Championnats » : France / Europe / Monde (zones actives).
    private var leagueSubgroups: [CompSubgroup] {
        Catalog.availableChampZones.map { zone in
            CompSubgroup(key: "sub.leagues.\(zone.id)",
                         titleKey: zone.titleKey,
                         comps: zone.competitions)
        }
    }
    /// Sous-familles de « Coupes » : Nationales / Europe / Monde / Internationale.
    private var cupSubgroups: [CompSubgroup] {
        Catalog.availableCupFamilies.map { fam in
            CompSubgroup(key: "sub.cups.\(fam.id)",
                         titleKey: fam.titleKey,
                         comps: fam.competitions)
        }
    }
    /// Sous-familles de « Sélections » : International / Europe / Monde.
    private var nationSubgroups: [CompSubgroup] {
        Catalog.availableNationZones.map { zone in
            CompSubgroup(key: "sub.nations.\(zone.id)",
                         titleKey: zone.titleKey,
                         comps: zone.competitions)
        }
    }

    @ViewBuilder
    private var competitionsList: some View {
        List {
            competitionFamily(key: "fam.leagues",
                              titleKey: "favorites.comps.leagues",
                              subgroups: leagueSubgroups)
            competitionFamily(key: "fam.cups",
                              titleKey: "favorites.comps.cups",
                              subgroups: cupSubgroups)
            competitionFamily(key: "fam.nations",
                              titleKey: "favorites.comps.nations",
                              subgroups: nationSubgroups)
        }
        .listStyle(.insetGrouped)
    }

    /// Niveau 1 : famille (Championnats / Coupes / Sélections) → DisclosureGroup
    /// contenant les sous-familles. On lie l'ouverture à `expandedFamilies`.
    @ViewBuilder
    private func competitionFamily(key: String,
                                   titleKey: String,
                                   subgroups: [CompSubgroup]) -> some View {
        SwiftUI.Section {
            DisclosureGroup(isExpanded: familyBinding(key)) {
                ForEach(subgroups) { sub in
                    competitionSubgroup(sub)
                }
            } label: {
                Text(L(titleKey))
                    .font(.headline)
                    .foregroundColor(Theme.text)
            }
        }
    }

    /// Niveau 2 : sous-famille (France / Europe / Monde …) → DisclosureGroup
    /// contenant les cases à cocher. On lie l'ouverture à `expandedSubgroups`.
    @ViewBuilder
    private func competitionSubgroup(_ sub: CompSubgroup) -> some View {
        DisclosureGroup(isExpanded: subgroupBinding(sub.key)) {
            ForEach(sub.comps) { comp in
                competitionCheckRow(comp)
            }
        } label: {
            HStack(spacing: 8) {
                Text(L(sub.titleKey))
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(Theme.textSoft)
                Spacer(minLength: 4)
                // Badge « n suivies » : pilule discrète en couleur brand seulement
                // quand au moins une compétition du groupe est suivie (sinon rien →
                // écran plus épuré). Compteur total affiché en gris clair.
                subgroupCountBadge(followed: followedCount(in: sub.comps),
                                   total: sub.comps.count)
            }
        }
    }

    /// Pilule compteur d'une sous-famille : « n suivies » en brand si n>0, sinon un
    /// simple « /total » très discret. Style épuré, moderne.
    @ViewBuilder
    private func subgroupCountBadge(followed: Int, total: Int) -> some View {
        if followed > 0 {
            Text("\(followed)")
                .font(.caption2).fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Theme.brand))
        } else {
            Text("\(total)")
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(Theme.textFaint)
        }
    }

    /// Ligne « case à cocher » d'une compétition (suivre / ne plus suivre).
    @ViewBuilder
    private func competitionCheckRow(_ comp: Competition) -> some View {
        let isOn = followedComps.isFollowed(comp.id)
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { followedComps.toggle(comp.id) }
        } label: {
            HStack(spacing: 12) {
                CompetitionArtworkView(competition: comp, size: 32, cornerRadius: 8)
                Text(L(comp.nameKey))
                    .font(.subheadline).fontWeight(isOn ? .semibold : .regular)
                    .foregroundColor(Theme.text)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isOn ? Theme.brand : Theme.textFaint)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Nombre de compétitions suivies dans un groupe (badge « n/total »).
    private func followedCount(in comps: [Competition]) -> Int {
        comps.filter { followedComps.isFollowed($0.id) }.count
    }

    /// Bindings d'ouverture depuis les Sets d'expansion (niveaux 1 et 2).
    private func familyBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { expandedFamilies.contains(key) },
                set: { isOn in
                    if isOn { expandedFamilies.insert(key) }
                    else { expandedFamilies.remove(key) }
                })
    }
    private func subgroupBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { expandedSubgroups.contains(key) },
                set: { isOn in
                    if isOn { expandedSubgroups.insert(key) }
                    else { expandedSubgroups.remove(key) }
                })
    }

    /// État vide d'un sous-onglet de la bibliothèque (invite à rechercher).
    @ViewBuilder
    private func librarySubEmpty(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(Theme.textFaint)
            Text(text)
                .font(.subheadline)
                .foregroundColor(Theme.textSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── Résultats de recherche (clubs + joueurs) ──────────────────────────────
    @ViewBuilder
    private var searchResults: some View {
        if isLoading {
            LoadingView(label: L("loading"))
        } else if let err = errorMessage {
            ErrorView(message: err) { Task { await search(query) } }
        } else if results.isEmpty && playerResults.isEmpty {
            EmptyStateView(icon: "sportscourt", text: L("search.noResult"))
        } else {
            List {
                if !results.isEmpty {
                    SwiftUI.Section {
                        ForEach(results) { result in
                            TeamRowLink(team: result.team)
                        }
                    } header: {
                        Text(L("search.section.teams"))
                            .font(.subheadline).fontWeight(.semibold).textCase(nil)
                    }
                }
                if !playerResults.isEmpty {
                    SwiftUI.Section {
                        ForEach(playerResults) { p in
                            PlayerSearchRow(profile: p)
                        }
                    } header: {
                        Text(L("search.section.players"))
                            .font(.subheadline).fontWeight(.semibold).textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // ── Invitation (aucun favori, aucune recherche) ───────────────────────────
    private var emptyLibraryPrompt: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "star")
                .font(.system(size: 52))
                .foregroundColor(Theme.textFaint)
            Text(L("library.empty"))
                .font(.subheadline)
                .foregroundColor(Theme.textSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    @MainActor
    private func search(_ q: String) async {
        isLoading = true; errorMessage = nil
        async let teamsTask = FootballAPIService.shared.searchTeams(query: q)
        async let playersTask = FootballAPIService.shared.searchPlayers(query: q)
        do { results = try await teamsTask } catch { results = [] }
        do { playerResults = try await playersTask } catch { playerResults = [] }
        isLoading = false
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// RÉGLAGES — feuille présentée depuis l'onglet Favoris
// ─────────────────────────────────────────────────────────────────────────────
// Choix de la langue de l'app (indépendante du système). Le changement est
// appliqué immédiatement (les libellés se retraduisent), avec une note indiquant
// qu'un redémarrage garantit une bascule complète (formats de dates système…).
// ═════════════════════════════════════════════════════════════════════════════
struct SettingsView: View {
    @EnvironmentObject private var locale: LocaleManager
    @EnvironmentObject private var profile: UserProfileStore
    @Environment(\.dismiss) private var dismiss
    // Compteur de requêtes API-Football (diagnostic quota). Observe le singleton
    // réseau : `requestsRemaining` / `requestsLimit` viennent des en-têtes
    // `x-ratelimit-requests-*` (quota QUOTIDIEN), `sessionNetworkCalls` compte les
    // appels réseau réels de cette session (hors cache).
    @ObservedObject private var api = FootballAPIService.shared

    var body: some View {
        NavigationStack {
            List {
                // Prénom local (personnalise l'accueil « Bonjour {prénom} »). Sans
                // compte ni réseau : simple libellé stocké dans UserDefaults.
                SwiftUI.Section {
                    TextField(L("settings.name.placeholder"), text: $profile.firstName)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                } header: {
                    Text(L("settings.name"))
                        .font(.subheadline).fontWeight(.semibold).textCase(nil)
                } footer: {
                    Text(L("settings.name.note"))
                        .font(.caption).foregroundColor(Theme.textSoft)
                }

                SwiftUI.Section {
                    ForEach(AppLanguage.allCases) { lang in
                        Button {
                            locale.language = lang
                        } label: {
                            HStack(spacing: 12) {
                                Text(lang.flag).font(.title3)
                                Text(lang.displayName)
                                    .foregroundColor(Theme.text)
                                Spacer()
                                if locale.language == lang {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(Theme.live)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(L("settings.language"))
                        .font(.subheadline).fontWeight(.semibold).textCase(nil)
                } footer: {
                    Text(L("settings.language.note"))
                        .font(.caption).foregroundColor(Theme.textSoft)
                }

                // Diagnostic quota API : quota quotidien restant (en-têtes serveur)
                // et appels réseau réels de la session. Purement informatif.
                SwiftUI.Section {
                    HStack {
                        Text(L("settings.api.remaining"))
                            .foregroundColor(Theme.text)
                        Spacer()
                        if let rem = api.requestsRemaining, let lim = api.requestsLimit {
                            Text("\(rem) / \(lim)")
                                .foregroundColor(rem < 500 ? Theme.live : Theme.textSoft)
                                .monospacedDigit()
                        } else {
                            Text("—").foregroundColor(Theme.textFaint)
                        }
                    }
                    HStack {
                        Text(L("settings.api.session"))
                            .foregroundColor(Theme.text)
                        Spacer()
                        Text("\(api.sessionNetworkCalls)")
                            .foregroundColor(Theme.textSoft)
                            .monospacedDigit()
                    }
                } header: {
                    Text(L("settings.api"))
                        .font(.subheadline).fontWeight(.semibold).textCase(nil)
                } footer: {
                    Text(L("settings.api.note"))
                        .font(.caption).foregroundColor(Theme.textSoft)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("common.done")) { dismiss() }
                }
            }
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// FICHE ÉQUIPE — en-tête (stade/ville/fondation) + effectif + matchs
// ─────────────────────────────────────────────────────────────────────────────
// « Non coûteux » : 3 appels max, tous réutilisant des endpoints déjà connus —
//   • /fixtures?team=   (matchs, comme avant)
//   • /teams?id=        (stade/ville/fondation, même endpoint que fetchTeamInfo)
//   • /players/squads?team=  (effectif complet en 1 appel léger, sans stats)
// La fiche d'UN joueur (PlayerDetailView) ne se charge qu'au tap → 1 appel de plus.
// Le palmarès et les clubs précédents (/transfers = 1 appel PAR joueur) sont
// volontairement écartés pour rester non coûteux.
// ═════════════════════════════════════════════════════════════════════════════
struct TeamProfileView: View {
    let team: AFTeamInfo

    @State private var fixtures: [AFFixture] = []
    @State private var venue: AFVenue?
    @State private var founded: Int?
    @State private var squad: [AFSquadPlayer] = []
    @State private var seasonStats: AFTeamSeasonStats?
    @State private var coach: AFCoach?
    @State private var isLoading = false
    @State private var errorMessage: String?
    // Photo de stade de REPLI (TheSportsDB) quand API-Football ne fournit pas
    // `venue.image` (ex. Arsenal / Emirates). Chargée à la demande, jamais bloquante.
    @State private var stadiumFallbackURL: URL?
    // Rubrique active de la fiche : Identité (photo stade + infos + prochain match
    // + bilan) / Effectif / Matchs. Identité ouverte par défaut.
    @State private var detailTab: TeamDetailTab = .identite
    // Sous-filtre de l'onglet Matchs : matchs déjà joués OU à venir (2 chips).
    @State private var matchsFilter: MatchsFilter = .played

    /// Matchs à venir, triés du plus proche au plus loin. On EXCLUT les matchs
    /// annulés / reportés / abandonnés (sinon un match annulé — ex. la Finalissima
    /// Espagne-Argentine — serait présenté comme « prochain match ») et on exige
    /// une date future (les matchs sans date exploitable sont écartés).
    var upcoming: [AFFixture] {
        let now = Date()
        return fixtures
            .filter { !$0.isFinished && !$0.isLive && !$0.isCancelledOrPostponed }
            .filter { ($0.isoDate ?? .distantPast) >= now }
            .sorted { ($0.isoDate ?? .distantFuture) < ($1.isoDate ?? .distantFuture) }
    }
    /// Matchs en direct.
    var live: [AFFixture] { fixtures.filter { $0.isLive } }

    var body: some View {
        Group {
            if isLoading {
                LoadingView(label: L("loading"))
            } else if let err = errorMessage {
                ErrorView(message: err) { Task { await load() } }
            } else {
                List {
                    // En-tête FIGÉ : logo + nom + drapeau + pays uniquement.
                    headerSection

                    // Sélecteur de rubrique (3 chips, bleu marque) :
                    //   Identité (photo stade + infos + prochain match + bilan)
                    //   Effectif · Matchs
                    // Identité est TOUJOURS disponible → onglet par défaut. Les deux
                    // autres n'apparaissent que si leur donnée existe.
                    let hasSquad = !squad.isEmpty
                    let hasMatchs = !fixtures.isEmpty
                    let effective = firstAvailableTab(
                        desired: detailTab, hasSquad: hasSquad, hasMatchs: hasMatchs)
                    detailTabChips(selected: effective, hasSquad: hasSquad, hasMatchs: hasMatchs)

                    switch effective {
                    case .identite:
                        identiteSection
                    case .effectif:
                        if hasSquad { squadSections }
                    case .matchs:
                        if hasMatchs { matchsSections }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load() }
            }
        }
        .navigationTitle(OfficialTeamNames.official(for: team.displayName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                FavoriteStar(team: team)
            }
        }
        .task { await load() }
    }

    // ── En-tête FIGÉ : logo + nom + drapeau + pays UNIQUEMENT ─────────────────
    // Reste affiché quelle que soit la chip sélectionnée. Tout le reste (photo du
    // stade, infos pratiques, prochain match, bilan) vit dans la chip « Identité ».
    @ViewBuilder
    private var headerSection: some View {
        SwiftUI.Section {
            HStack(spacing: 14) {
                TeamLogoView(urlString: team.logo, name: team.name, size: 72, teamId: team.id)
                VStack(alignment: .leading, spacing: 3) {
                    Text(OfficialTeamNames.official(for: team.displayName))
                        .font(.title3.weight(.bold)).foregroundColor(Theme.text)
                    if let country = team.country {
                        let flag = CountryFlag.emoji(for: country)
                        Text(flag.isEmpty ? country : "\(flag)  \(country)")
                            .font(.subheadline).foregroundColor(Theme.textSoft)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    // ── Chip « Identité » : photo stade + infos pratiques + prochain match + bilan
    // Rassemble tout le contenu descriptif du club, réparti en sections propres.
    @ViewBuilder
    private var identiteSection: some View {
        // Bloc infos + photo du stade.
        SwiftUI.Section {
            VStack(alignment: .leading, spacing: 9) {
                if let stadium = displayStadium {
                    infoRow(icon: "mappin.and.ellipse", text: stadium)
                }
                // Capacité masquée pour les sélections (stade forcé officiel).
                if !(team.national ?? false), let cap = venue?.capacity, cap > 0 {
                    infoRow(icon: "person.2",
                            text: "\(formattedCapacity(cap)) \(L("team.seats"))")
                }
                if let founded {
                    infoRow(icon: "flag",
                            text: "\(L("team.founded")) \(String(founded))")
                }
            }
            .padding(.vertical, 2)

            if let url = effectiveStadiumURL {
                stadiumBanner(url)
            }
        }
        // Repli photo de stade : si API-Football n'a pas donné `venue.image`, on
        // interroge TheSportsDB (par ID API-Football) UNE fois, en tâche de fond.
        .task(id: venue?.image) {
            guard (venue?.image ?? "").isEmpty, stadiumFallbackURL == nil else { return }
            stadiumFallbackURL = await ImageFallbackService.shared.teamStadiumPhoto(
                apiFootballId: team.id, name: team.name)
        }

        // Prochain match (s'il existe).
        if let next = upcoming.first { nextMatchSection(next) }

        // Bilan de la saison (s'il y a des données).
        if let s = seasonStats, s.hasData { seasonBilanSection(s) }
    }

    /// Stade « maison » à afficher dans l'en-tête (nom · ville).
    /// Pour une SÉLECTION NATIONALE dont on connaît le stade officiel, on FORCE ce
    /// stade (API-Football rattache parfois un stade de club, ex. France → Groupama
    /// Stadium ; on veut le Stade de France à Saint-Denis). Sinon on prend le stade
    /// de l'API tel quel. `nil` si aucune donnée → la ligne disparaît.
    private var displayStadium: String? {
        if team.national ?? false,
           let override = OfficialTeamNames.nationalHomeVenue(for: team.name) {
            return "\(override.name) · \(override.city)"
        }
        guard let name = venue?.name, !name.isEmpty else { return nil }
        return venue?.city.map { "\(name) · \($0)" } ?? name
    }

    /// Nom du stade posé EN BAS de la photo (bandeau). Pour une sélection dont on
    /// force le stade officiel (ex. France → Stade de France, et NON « Groupama
    /// Stadium » mal rattaché par API-Football), on affiche le nom officiel — sinon
    /// le nom du stade viendrait de l'API et contredirait la ligne d'info au-dessus.
    private var stadiumCaption: String? {
        if team.national ?? false,
           let override = OfficialTeamNames.nationalHomeVenue(for: team.name) {
            return override.name
        }
        guard let name = venue?.name, !name.isEmpty else { return nil }
        return name
    }

    /// URL de photo de stade effective : API-Football en priorité, sinon repli
    /// TheSportsDB. `nil` → aucun bandeau (repli silencieux, jamais de trou gris).
    private var effectiveStadiumURL: URL? {
        if let img = venue?.image, !img.isEmpty, let url = URL(string: img) { return url }
        return stadiumFallbackURL
    }

    // Ligne d'info uniforme de l'en-tête : icône fine dans une colonne de largeur
    // fixe (alignement du texte), teinte douce cohérente (plus de rouge criard).
    @ViewBuilder
    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Theme.textSoft)
                .frame(width: 16, alignment: .center)
            Text(text)
                .font(.caption)
                .foregroundColor(Theme.textSoft)
                .lineLimit(1)
        }
    }

    // ── Bandeau photo du stade ────────────────────────────────────────────────
    // Photo large en tête (venue.image d'API-Football), nom du stade posé en bas
    // sur un dégradé sombre pour la lisibilité. Repli SILENCIEUX : tant que
    // l'image ne charge pas (ou échoue), on n'affiche RIEN (pas de rectangle gris)
    // → l'en-tête classique logo+texte reste seul, sans trou visuel.
    @ViewBuilder
    private func stadiumBanner(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        // Dégradé sombre bas → lisibilité du nom du stade.
                        LinearGradient(
                            colors: [.black.opacity(0.55), .clear],
                            startPoint: .bottom, endPoint: .center)
                        .overlay(alignment: .bottomLeading) {
                            if let name = stadiumCaption, !name.isEmpty {
                                Text(name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(12)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
            // .empty / .failure → rien (repli silencieux).
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 8, trailing: 12))
    }

    // ── Prochain match mis en avant ──────────────────────────────────────────
    // Reprend le 1er match à venir (déjà chargé, 0 appel). Style sobre : une
    // ligne cliquable qui ouvre la fiche du match, dans sa propre section.
    @ViewBuilder
    private func nextMatchSection(_ f: AFFixture) -> some View {
        SwiftUI.Section {
            NavigationLink(destination: MatchDetailView(fixture: f)) {
                NextMatchRow(fixture: f)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        } header: {
            Text(L("team.nextMatch")).font(.subheadline).fontWeight(.semibold).textCase(nil)
        }
    }

    // ── Bilan de la saison (sobre, intégré) ──────────────────────────────────
    // ── Chips de rubrique : Bilan de la saison / Effectif ─────────────────────
    // Boutons capsule dans une SwiftUI.Section transparente ; le tap change
    // `detailTab`. On n'affiche un chip que si sa donnée existe.
    @ViewBuilder
    private func detailTabChips(selected: TeamDetailTab, hasSquad: Bool, hasMatchs: Bool) -> some View {
        SwiftUI.Section {
            HStack(spacing: 8) {
                // Identité TOUJOURS présente (contenu descriptif du club).
                detailChip(.identite, selected: selected)
                if hasSquad { detailChip(.effectif, selected: selected) }
                if hasMatchs { detailChip(.matchs, selected: selected) }
                Spacer(minLength: 0)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    /// Rubrique effectivement affichée : on part de celle voulue par l'utilisateur
    /// mais on retombe sur une rubrique disponible. Identité est toujours dispo.
    private func firstAvailableTab(desired: TeamDetailTab,
                                   hasSquad: Bool, hasMatchs: Bool) -> TeamDetailTab {
        switch desired {
        case .identite: return .identite
        case .effectif: return hasSquad ? .effectif : .identite
        case .matchs:   return hasMatchs ? .matchs : .identite
        }
    }

    @ViewBuilder
    private func detailChip(_ tab: TeamDetailTab, selected: TeamDetailTab) -> some View {
        let isSel = tab == selected
        Button { withAnimation(.easeInOut(duration: 0.15)) { detailTab = tab } } label: {
            Text(L(tab.titleKey))
                .font(.subheadline.weight(isSel ? .semibold : .regular))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(isSel ? Theme.brand : Color(.secondarySystemBackground))
                .foregroundColor(isSel ? .white : Theme.text)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // Forme récente (5 dernières pastilles V/N/D) + chiffres clés en grille.
    @ViewBuilder
    private func seasonBilanSection(_ s: AFTeamSeasonStats) -> some View {
        SwiftUI.Section {
            if let form = s.form, !form.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(recentFormPills(form).enumerated()), id: \.offset) { _, r in
                        formPill(r)
                    }
                    Spacer()
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            bilanRow(L("team.played"), "\(s.played)")
            bilanRow(L("team.record"), "\(s.wins) \(L("team.winsShort")) · \(s.draws) \(L("team.drawsShort")) · \(s.losses) \(L("team.lossesShort"))")
            bilanRow(L("team.goalsForAgainst"), "\(s.goalsFor) : \(s.goalsAgainst)  (\(s.goalDiff >= 0 ? "+" : "")\(s.goalDiff))")
            if s.cleanSheets > 0 { bilanRow(L("team.cleanSheets"), "\(s.cleanSheets)") }
            if s.longestWinStreak > 0 { bilanRow(L("team.winStreak"), "\(s.longestWinStreak)") }
            if let avg = s.avgGoalsFor { bilanRow(L("team.avgGoals"), String(format: "%.1f", avg)) }
            if let avgA = s.avgGoalsAgainst { bilanRow(L("team.avgGoalsAgainst"), String(format: "%.1f", avgA)) }
        } header: {
            Text(L("team.seasonSummary")).font(.subheadline).fontWeight(.semibold).textCase(nil)
        }
    }

    private func bilanRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundColor(Theme.textSoft)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).foregroundColor(Theme.text)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    /// 5 dernières issues (les plus récentes à droite dans la chaîne "WDLWW").
    private func recentFormPills(_ form: String) -> [Character] {
        Array(form.uppercased().suffix(5))
    }

    @ViewBuilder
    private func formPill(_ r: Character) -> some View {
        let (letter, color): (String, Color) = {
            switch r {
            case "W": return (L("team.winsShort"), .green)
            case "D": return (L("team.drawsShort"), .orange)
            case "L": return (L("team.lossesShort"), .red)
            default:  return ("?", .gray)
            }
        }()
        Text(letter)
            .font(.caption2.weight(.bold))
            .foregroundColor(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(color))
    }

    /// Capacité formatée avec séparateur de milliers selon la locale.
    private func formattedCapacity(_ cap: Int) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        return fmt.string(from: NSNumber(value: cap)) ?? "\(cap)"
    }

    // ── Effectif regroupé par poste (G / D / M / A) ──────────────────────────
    @ViewBuilder
    private var squadSections: some View {
        ForEach(SquadPosition.allCases, id: \.rawValue) { pos in
            let players = squad.filter { $0.posGroup == pos }
            if !players.isEmpty {
                SwiftUI.Section {
                    ForEach(players) { p in
                        NavigationLink(destination: PlayerDetailView(playerId: p.id, fallbackName: p.name)) {
                            SquadPlayerRow(player: p)
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                    }
                } header: {
                    Text(L(pos.titleKey)).font(.subheadline).fontWeight(.semibold).textCase(nil)
                }
            }
        }
    }

    // ── Rubrique MATCHS (compacte, avec score coloré) ─────────────────────────
    // Demande user 2026-08-16 : liste PETITE des matchs joués (dont amicaux depuis
    // le 1er juillet 2026) + à venir, avec dates et clic → fiche du match. Score
    // vert = victoire / orange = nul / rouge = défaite (du point de vue du club).
    // On conserve les mêmes regroupements que la fiche mais dans des lignes denses.

    /// Matchs terminés depuis le 1er juillet 2026 (inclut les amicaux d'intersaison),
    /// du plus récent au plus ancien.
    private var playedMatchs: [AFFixture] {
        let cutoff = DateComponents(calendar: .current, year: 2026, month: 7, day: 1).date
            ?? Date.distantPast
        return fixtures
            .filter { $0.isFinished && ($0.isoDate ?? .distantPast) >= cutoff }
            .sorted { ($0.isoDate ?? .distantPast) > ($1.isoDate ?? .distantPast) }
    }

    @ViewBuilder
    private var matchsSections: some View {
        // Sous-sélecteur : « Déjà joués » / « À venir ». On n'affiche un chip que
        // si la catégorie correspondante contient au moins un match.
        let hasPlayed = !playedMatchs.isEmpty || !live.isEmpty
        let hasUpcoming = !upcoming.isEmpty
        matchsFilterChips(hasPlayed: hasPlayed, hasUpcoming: hasUpcoming)

        // Catégorie effective : on retombe sur celle qui a des matchs.
        let effective: MatchsFilter = {
            switch matchsFilter {
            case .played:   return hasPlayed ? .played : .upcoming
            case .upcoming: return hasUpcoming ? .upcoming : .played
            }
        }()

        if effective == .played {
            // En direct puis résultats récents (les deux comptent comme « joués »).
            if !live.isEmpty { compactMatchSection(title: L("tab.live"), items: live) }
            if !playedMatchs.isEmpty {
                compactMatchSection(title: L("search.recent"), items: playedMatchs)
            }
        } else if !upcoming.isEmpty {
            compactMatchSection(title: L("search.upcoming"), items: upcoming)
        }
    }

    /// Les 2 chips « Déjà joués » / « À venir » du sous-filtre de l'onglet Matchs.
    @ViewBuilder
    private func matchsFilterChips(hasPlayed: Bool, hasUpcoming: Bool) -> some View {
        SwiftUI.Section {
            HStack(spacing: 8) {
                if hasPlayed   { matchsFilterChip(.played) }
                if hasUpcoming { matchsFilterChip(.upcoming) }
                Spacer(minLength: 0)
            }
            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private func matchsFilterChip(_ filter: MatchsFilter) -> some View {
        let isSel = filter == matchsFilter
        Button { withAnimation(.easeInOut(duration: 0.15)) { matchsFilter = filter } } label: {
            Text(L(filter.titleKey))
                .font(.footnote.weight(isSel ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSel ? Theme.brand : Color(.secondarySystemBackground))
                .foregroundColor(isSel ? .white : Theme.text)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func compactMatchSection(title: String, items: [AFFixture]) -> some View {
        SwiftUI.Section {
            ForEach(items) { f in
                NavigationLink(destination: MatchDetailView(fixture: f)) {
                    CompactMatchRow(fixture: f, teamId: team.id)
                }
                .listRowInsets(EdgeInsets(top: 1, leading: 16, bottom: 1, trailing: 16))
            }
        } header: {
            Text(title).font(.subheadline).fontWeight(.semibold).textCase(nil)
        }
    }

    @MainActor
    private func load() async {
        isLoading = true; errorMessage = nil
        // Les 3 chargements sont indépendants et tolérants à l'échec (ex. effectif
        // indisponible) sans casser toute la fiche. On les fait EN SÉQUENCE et non
        // en parallèle : 3 requêtes simultanées vers API-Football déclenchaient un
        // 429 (rate-limit PAR MINUTE) sur toutes en même temps → fiche vide +
        // « Erreur serveur 429 ». Séquentiel + le retry back-off de fetch()
        // suffisent à absorber les pics sans surcoût de quota.
        fixtures = (try? await FootballAPIService.shared.fetchTeamFixtures(teamId: team.id)) ?? []
        if let result = try? await FootballAPIService.shared.fetchTeamResult(teamId: team.id) {
            venue = result.venue
            founded = result.team.founded
        }
        squad = (try? await FootballAPIService.shared.fetchTeamSquad(teamId: team.id)) ?? []

        // Coach RETIRÉ de l'affichage (donnée API-Football pas fiable à
        // l'intersaison 2026/27 : renvoyait l'ex-coach). On n'appelle donc plus
        // fetchTeamCoach — 1 requête économisée. À rebrancher en V2 avec source sûre.

        // Bilan de saison — dérivé des fixtures déjà chargées (ligue principale +
        // saison), donc pas d'appel de découverte. 1 seul appel /teams/statistics,
        // tolérant à l'échec. Ignoré si aucune ligue exploitable dans les matchs.
        if let (league, season) = FootballAPIService.shared.mainLeague(from: fixtures) {
            seasonStats = await FootballAPIService.shared.fetchTeamStatistics(
                teamId: team.id, league: league, season: season)
        }

        // On n'affiche une erreur que si absolument rien n'a pu être chargé.
        if fixtures.isEmpty && squad.isEmpty && venue == nil {
            do { fixtures = try await FootballAPIService.shared.fetchTeamFixtures(teamId: team.id) }
            catch { errorMessage = error.localizedDescription }
        }
        isLoading = false
    }
}

/// Avatar circulaire d'un joueur : affiche la photo si elle charge, sinon une
/// pastille colorée avec les initiales (repli élégant, zéro appel réseau).
/// La couleur est dérivée du nom → stable et différente d'un joueur à l'autre.
struct PlayerAvatar: View {
    let name: String
    let photo: String?
    var size: CGFloat = 34

    /// Initiales : 1re lettre du dernier mot significatif, préfixée de la 1re
    /// lettre du prénom si présent (ex. « J. de Lange » → « JL »).
    private var initials: String {
        let cleaned = name
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 || $0.first?.isLetter == true }
        let letters = cleaned.compactMap { $0.first }.map { String($0).uppercased() }
        if letters.count >= 2 { return letters.first! + letters.last! }
        return letters.first ?? "?"
    }

    /// Couleur stable dérivée du nom (hash simple → teinte).
    private var tint: Color {
        let hash = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.45, brightness: 0.75)
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(tint.opacity(0.22))
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundColor(tint)
        }
    }

    // Retry : AsyncImage ne réessaie jamais un échec. On incrémente cet id sur
    // .failure (2 tentatives max) → SwiftUI recrée l'AsyncImage et relance le
    // chargement, ce qui rattrape les échecs transitoires (30+ images en //).
    @State private var attempt = 0

    /// Photo de secours (TheSportsDB) résolue par nom, uniquement si API-Football
    /// n'a pas fourni de photo. `nil` tant que non résolue / introuvable.
    @State private var fallbackURL: URL? = nil
    @State private var didTryFallback = false

    /// URL effective : photo API-Football en priorité, sinon secours TheSportsDB.
    private var effectiveURL: URL? {
        if let s = photo, !s.isEmpty, let url = URL(string: s) { return url }
        return fallbackURL
    }

    private var primaryMissing: Bool { (photo?.isEmpty ?? true) }

    var body: some View {
        Group {
            if let url = effectiveURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        placeholder
                            .onAppear {
                                if attempt < 2 {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                        attempt += 1
                                    }
                                } else if !didTryFallback {
                                    // La photo API-Football existe mais échoue à se
                                    // charger (URL périmée) → on tente TheSportsDB
                                    // même si `primaryMissing` est faux.
                                    didTryFallback = true
                                    Task {
                                        fallbackURL = await ImageFallbackService.shared
                                            .playerPhoto(name: name)
                                    }
                                }
                            }
                    case .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
                .id(attempt)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        // Repli photo à la demande : seulement si API-Football n'a rien, 1 fois.
        .task(id: primaryMissing) {
            guard primaryMissing, !didTryFallback else { return }
            didTryFallback = true
            fallbackURL = await ImageFallbackService.shared.playerPhoto(name: name)
        }
    }
}

/// Ligne d'un joueur de l'effectif : photo, nom, poste, n° de maillot.
/// Rubrique de la fiche équipe : bilan de la saison ou effectif.
enum TeamDetailTab {
    case identite, effectif, matchs
    var titleKey: String {
        switch self {
        case .identite: return "team.identity"
        case .effectif: return "team.squad"
        case .matchs:   return "team.matches"
        }
    }
}

/// Sous-filtre de l'onglet « Matchs » : matchs déjà joués (+ en direct) ou à venir.
enum MatchsFilter {
    case played, upcoming
    var titleKey: String {
        switch self {
        case .played:   return "team.matches.played"
        case .upcoming: return "team.matches.upcoming"
        }
    }
}

// Ligne d'effectif DENSIFIÉE : avatar plus petit, n° et âge sur la même ligne à
// droite pour tenir le maximum de joueurs à l'écran (demande user 2026-08-16).
private struct SquadPlayerRow: View {
    let player: AFSquadPlayer

    var body: some View {
        HStack(spacing: 10) {
            PlayerAvatar(name: player.name, photo: player.photo, size: 28)

            Text(TeamNameFormatter.pretty(player.name))
                .font(.subheadline).foregroundColor(Theme.text).lineLimit(1)

            Spacer(minLength: 6)

            if let age = player.age {
                Text("\(age) \(L("player.yearsShort"))")
                    .font(.caption2).foregroundColor(Theme.textFaint)
            }
            if let number = player.number {
                Text("#\(number)")
                    .font(.statNum).foregroundColor(Theme.textSoft)
                    .frame(minWidth: 28, alignment: .trailing)
            }
        }
        .padding(.vertical, 1)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIGNE DE MATCH COMPACTE — rubrique « Matchs » de la fiche équipe
// -----------------------------------------------------------------------------
// Ligne PETITE (demande user 2026-08-16) : date · logo adversaire · nom · score.
// Le score porte une pastille colorée DU POINT DE VUE DU CLUB affiché :
//   vert = victoire · orange = nul · rouge = défaite. Matchs à venir : pas de
//   score → on montre l'heure/statut. Toujours cliquable (fiche du match).
// Aucune donnée inventée : score et statut viennent de l'objet AFFixture.
// ─────────────────────────────────────────────────────────────────────────────
// ═════════════════════════════════════════════════════════════════════════════
// TYPE DE COMPÉTITION D'UN MATCH — amical / championnat / coupe / coupe d'Europe
// ─────────────────────────────────────────────────────────────────────────────
// Classement DÉTERMINISTE, sans devinette :
//   1. si la compétition est au catalogue → on lit sa nature (section europe →
//      coupe d'Europe ; kind cup/mixed → coupe ; league/leagueGroups → championnat) ;
//   2. sinon on retombe sur les infos brutes de l'API-Football : un nom de ligue
//      contenant « friendl » (Friendlies, Club Friendlies) → AMICAL ; type
//      « Cup » → coupe ; type « League » → championnat ; défaut → championnat.
// ═════════════════════════════════════════════════════════════════════════════
enum MatchKind {
    case friendly, league, cup, europe

    /// Nature d'un match d'après sa ligue (catalogue prioritaire, puis API brute).
    static func of(_ f: AFFixture) -> MatchKind {
        // Amical d'abord : l'API nomme ces matchs « Friendlies » / « Club Friendlies ».
        if f.league.name.lowercased().contains("friendl") { return .friendly }

        if let comp = Catalog.competition(forLeagueId: f.league.id) {
            if comp.section == .europe { return .europe }
            switch comp.kind {
            case .cup, .mixed:               return .cup
            case .league, .leagueGroups:     return .league
            }
        }
        // Hors catalogue : on se fie au type API-Football (« League » / « Cup »).
        switch f.league.type?.lowercased() {
        case "cup":  return .cup
        default:     return .league
        }
    }

    var labelKey: String {
        switch self {
        case .friendly: return "matchtype.friendly"
        case .league:   return "matchtype.league"
        case .cup:      return "matchtype.cup"
        case .europe:   return "matchtype.europe"
        }
    }
    var symbol: String {
        switch self {
        case .friendly: return "figure.walk"
        case .league:   return "list.number"
        case .cup:      return "trophy.fill"
        case .europe:   return "star.circle.fill"
        }
    }
    var tint: Color {
        switch self {
        case .friendly: return Theme.textSoft
        case .league:   return Color(red: 0.13, green: 0.32, blue: 0.78)
        case .cup:      return Theme.gold
        case .europe:   return Color(red: 0.20, green: 0.15, blue: 0.55)
        }
    }
}

/// Petit badge « type de compétition » (icône + libellé), discret, à droite du nom.
private struct MatchKindBadge: View {
    let kind: MatchKind
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: kind.symbol).font(.system(size: 8, weight: .semibold))
            Text(L(kind.labelKey))
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)                 // jamais de retour à la ligne
        }
        .fixedSize(horizontal: true, vertical: false) // le badge garde sa largeur
        .foregroundColor(kind.tint)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(kind.tint.opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct CompactMatchRow: View {
    let fixture: AFFixture
    /// ID du club dont on affiche la fiche → détermine dom./ext. et V/N/D.
    let teamId: Int

    /// Le club affiché joue-t-il à domicile ?
    private var isHome: Bool { fixture.teams.home.id == teamId }
    /// L'adversaire (l'autre équipe).
    private var opponent: AFTeam { isHome ? fixture.teams.away : fixture.teams.home }

    /// Date compacte « 12 août » (sans année pour rester court).
    private var shortDate: String {
        guard let d = fixture.isoDate else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "d MMM"
        fmt.timeZone = .current
        return fmt.string(from: d)
    }

    /// Score « 2-1 » (buts du club à gauche) si le match est terminé.
    private var scoreText: String? {
        guard fixture.isFinished,
              let h = fixture.goals.home, let a = fixture.goals.away else { return nil }
        let mine = isHome ? h : a
        let theirs = isHome ? a : h
        return "\(mine)-\(theirs)"
    }

    /// Couleur du score : vert=victoire, orange=nul, rouge=défaite (club affiché).
    private var scoreColor: Color {
        guard fixture.isFinished,
              let h = fixture.goals.home, let a = fixture.goals.away else { return .gray }
        let mine = isHome ? h : a
        let theirs = isHome ? a : h
        if mine > theirs { return .green }
        if mine < theirs { return .red }
        return .orange
    }

    /// Heure « 21:00 » pour un match à venir.
    private var kickoffTime: String {
        guard let d = fixture.isoDate else { return L("status.upcoming") }
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = .current
        return fmt.string(from: d)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Date (colonne fixe pour un alignement propre).
            Text(shortDate)
                .font(.caption2).foregroundColor(Theme.textFaint)
                .frame(width: 46, alignment: .leading)

            // Logo + nom de l'adversaire, préfixé d'une petite icône discrète :
            // 🏠 maison = match à domicile, ✈️ avion = match à l'extérieur.
            TeamLogoView(urlString: opponent.logo, name: opponent.name, size: 22, teamId: opponent.id)
            Image(systemName: isHome ? "house.fill" : "airplane")
                .font(.system(size: 9))
                .foregroundColor(Theme.textFaint)
                .help(isHome ? L("match.homeShort") : L("match.awayShort"))
            Text(opponent.displayName)
                .font(.caption).foregroundColor(Theme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)            // le nom cède l'espace avant le badge

            // Type de compétition (amical / championnat / coupe / coupe d'Europe).
            MatchKindBadge(kind: MatchKind.of(fixture))
                .layoutPriority(1)            // badge prioritaire → reste entier

            Spacer(minLength: 6)

            // Score coloré (terminé) OU heure/statut (à venir/live).
            if let s = scoreText {
                Text(s)
                    .font(.caption.weight(.bold)).foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(scoreColor))
            } else if fixture.isLive {
                Text(L("status.liveShort"))
                    .font(.caption2.weight(.bold)).foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.red))
            } else {
                Text(kickoffTime)
                    .font(.caption.weight(.semibold)).foregroundColor(Theme.textSoft)
            }
        }
        .padding(.vertical, 1)
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// PROCHAIN MATCH — carte mise en avant, très fluide
// ─────────────────────────────────────────────────────────────────────────────
// Deux équipes (logo + nom) de part et d'autre d'une colonne centrale claire :
//   • nom de la compétition (petit, discret) tout en haut ;
//   • DATE sur une ligne (« ven. 25 sept. ») ;
//   • HEURE sur la ligne du dessous (« 20:45 »), en avant.
// Objectif : lecture instantanée, aucune date qui se coupe sur plusieurs lignes.
// ═════════════════════════════════════════════════════════════════════════════
private struct NextMatchRow: View {
    let fixture: AFFixture

    /// Date « ven. 25 sept. » (jour de semaine + jour + mois, sans année).
    private var dateLine: String {
        guard let d = fixture.isoDate else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "EEE d MMM"
        fmt.timeZone = .current
        return fmt.string(from: d)
    }

    /// Heure « 20:45 ».
    private var timeLine: String {
        guard let d = fixture.isoDate else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = .current
        return fmt.string(from: d)
    }

    /// Lieu « Stade · Ville » du prochain match, si connu. `nil` sinon → non affiché.
    private var venueLine: String? {
        guard let v = fixture.fixture.venue, let name = v.name, !name.isEmpty else { return nil }
        return v.city.map { "\(name) · \($0)" } ?? name
    }

    var body: some View {
        VStack(spacing: 8) {
            // Compétition (discrète, centrée).
            Text(CompetitionNameLocalizer.localized(fixture.league.name))
                .font(.caption2.weight(.medium))
                .foregroundColor(Theme.textFaint)
                .lineLimit(1)

            HStack(alignment: .center, spacing: 8) {
                // Équipe à domicile (nom à droite, logo collé au centre).
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text(fixture.teams.home.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.text)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                    TeamLogoView(urlString: fixture.teams.home.logo,
                                 name: fixture.teams.home.name, size: 30,
                                 teamId: fixture.teams.home.id)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                // Colonne centrale : DATE puis HEURE (deux lignes nettes).
                VStack(spacing: 2) {
                    Text(dateLine)
                        .font(.caption2)
                        .foregroundColor(Theme.textSoft)
                        .lineLimit(1)
                        .fixedSize()
                    Text(timeLine)
                        .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(Theme.text)
                    // Lieu du match, sous la date et l'heure (si connu).
                    if let line = venueLine {
                        HStack(spacing: 3) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 8))
                                .foregroundColor(Theme.textFaint)
                            Text(line)
                                .font(.system(size: 9))
                                .foregroundColor(Theme.textFaint)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                        .padding(.top, 1)
                    }
                }
                .frame(minWidth: 90)

                // Équipe à l'extérieur (logo puis nom à gauche).
                HStack(spacing: 8) {
                    TeamLogoView(urlString: fixture.teams.away.logo,
                                 name: fixture.teams.away.name, size: 30,
                                 teamId: fixture.teams.away.id)
                    Text(fixture.teams.away.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.text)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// FICHE JOUEUR — identité + stats de la saison, rechargée par playerId
// ─────────────────────────────────────────────────────────────────────────────
// Règle d'or : on ne reçoit qu'un identifiant (playerId) ; la fiche recharge tout
// via /players?id= (1 appel). Photo, âge, nationalité, poste, puis stats saison
// (matchs joués, buts, passes) agrégées toutes compétitions.
// ═════════════════════════════════════════════════════════════════════════════
struct PlayerDetailView: View {
    let playerId: Int
    var fallbackName: String = ""

    @State private var detail: AFPlayerResponse?
    @State private var isLoading = false
    @State private var failed = false

    // Stats de la SAISON EN COURS UNIQUEMENT (2026). Distinct de `detail`, qui peut
    // provenir d'un repli sur une saison passée (pour toujours afficher l'identité).
    // nil = pas encore chargé / joueur sans match cette saison → carte « pas de match ».
    @State private var seasonStats: AFPlayerResponse?

    // Fiche carrière Wikidata (2e source) : chargée en parallèle des stats saison.
    // Nullable : un joueur introuvable sur Wikidata → on n'affiche aucune section.
    @State private var wiki: WikidataPlayer?

    // Club ACTUEL (source /players/teams, autoritaire) : sert au sous-titre « Real
    // Madrid » même en début de saison où les stats de match ne contiennent que la
    // sélection. nil = pas encore chargé / échec réseau → repli sur stats puis Wikidata.
    @State private var currentClub: AFTeamInfo?

    // Saison sportive en cours (année de début : août 2026 → saison 2026).
    private var currentSeason: Int { Calendar.current.component(.year, from: Date()) }

    // ── Navigation par chips ────────────────────────────────────────────────
    // Chip principale : Identité (infos) ou Stats saison en cours.
    private enum MainTab: Hashable { case identity, seasonStats }
    @State private var mainTab: MainTab = .identity

    // Sous-chip de la vue Stats : une catégorie de compétition (ou le total).
    // On mémorise le choix pour ne pas le réinitialiser à chaque recomposition.
    // Ordre d'affichage demandé : Championnat, Coupes, Sélections, Total.
    // Les AMICAUX sont retirés (demande user). Ces 4 sous-chips sont TOUJOURS
    // affichées même à 0 match (on précise la compétition concernée).
    private enum StatScope: Hashable {
        case league         // championnat
        case cups           // coupes (Europe + nationale, détaillées par comp)
        case nations        // sélection
    }
    @State private var statScope: StatScope = .league

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let p = detail {
                    header(p)
                    mainTabPicker
                    switch mainTab {
                    case .identity:
                        identitySection(p)
                    case .seasonStats:
                        seasonStatsSection(p)
                    }
                } else if failed {
                    EmptyStateView(icon: "person.crop.circle.badge.exclamationmark",
                                   text: L("player.unavailable"))
                        .padding(.top, 40)
                } else {
                    ProgressView().padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            // Marge basse généreuse : la dernière ligne de stats ne doit pas être
            // collée à la barre d'onglets du bas (demande user).
            .padding(.bottom, 40)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(detail?.fullName ?? TeamNameFormatter.pretty(fallbackName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Étoile « suivre » : active seulement une fois la fiche chargée
                // (on a besoin de l'identité + club pour l'instantané persistant).
                if let p = detail {
                    PlayerFollowStar(player: FollowedPlayer(from: p))
                }
            }
        }
        .task { await load() }
    }

    // Bandeau compact : GRANDE photo (120) + nom, puis deux pastilles côte à côte :
    // CLUB (logo + nom, cliquable → fiche club) et SÉLECTION (drapeau + nom). Les
    // attributs biographiques sont dans la chip « Identité » juste en dessous.
    @ViewBuilder
    private func header(_ p: AFPlayerResponse) -> some View {
        // Photo : API-Football d'abord, Wikidata en repli (règle décidée avec l'user).
        let photoURL = (p.player.photo?.isEmpty == false ? p.player.photo : nil) ?? wiki?.photoUrl
        VStack(spacing: 12) {
            PlayerAvatar(name: p.fullName.isEmpty ? p.player.name : p.fullName,
                         photo: photoURL, size: 120)
                .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)

            Text(p.fullName)
                .font(.title2.weight(.bold)).foregroundColor(Theme.text)
                .multilineTextAlignment(.center)

            headerTeams(p)
        }
    }

    // Rangée club + sélection sous le nom. Chaque pastille n'apparaît que si l'info
    // existe (règle d'or). Le club est cliquable (→ fiche club) quand on a son id.
    @ViewBuilder
    private func headerTeams(_ p: AFPlayerResponse) -> some View {
        let clubName = clubSubtitle(p)
        let clubId = p.clubTeamId ?? currentClub?.id
        let clubLogo = p.clubTeamLogo ?? currentClub?.logo
        // Nom de la sélection : Wikidata nettoyé (« Espagne »), repli nationalité API.
        let natName = Self.prettyNationalTeam(wiki?.nationalTeam)
            ?? (p.player.nationality?.isEmpty == false ? p.player.nationality : nil)

        HStack(spacing: 10) {
            if let name = clubName, !name.isEmpty {
                if let id = clubId {
                    TeamProfileLink(teamId: id, previewName: name, previewLogo: clubLogo) {
                        headerPill(logoURL: clubLogo, logoName: name,
                                   teamId: id, flag: nil, text: name)
                    }
                } else {
                    headerPill(logoURL: clubLogo, logoName: name,
                               teamId: nil, flag: nil, text: name)
                }
            }
            if let nat = natName, !nat.isEmpty {
                headerPill(logoURL: nil, logoName: nat, teamId: nil,
                           flag: CountryFlag.emoji(for: p.player.nationality), text: nat)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // Une pastille club/sélection : logo (club) ou drapeau (sélection) + nom.
    private func headerPill(logoURL: String?, logoName: String, teamId: Int?,
                            flag: String?, text: String) -> some View {
        HStack(spacing: 7) {
            if let flag, !flag.isEmpty {
                Text(flag).font(.system(size: 20))
            } else {
                TeamLogoView(urlString: logoURL, name: logoName, size: 22, teamId: teamId)
            }
            Text(text)
                .font(.subheadline.weight(.medium)).foregroundColor(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Theme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
    }

    /// Nom du CLUB à afficher sous le nom du joueur — JAMAIS la sélection nationale.
    /// En tout début de saison, les stats API ne contiennent parfois QUE la ligne de
    /// sélection (ex. Mbappé : France en Nations League, Real Madrid pas encore joué)
    /// → `p.teamName`/`clubTeamName` retombaient sur « France ». On privilégie donc :
    ///   1. la 1re ligne de CLUB des stats API (`clubTeamName`) si elle existe ;
    ///   2. sinon le club actuel Wikidata (`wiki.currentClub`, source carrière fiable) ;
    ///   3. sinon RIEN (on n'affiche pas la sélection nationale comme si c'était le club).
    // Sous-titre « club » de l'en-tête. Ordre de priorité, du plus fiable au repli :
    //   1. /players/teams (currentClub) : club actuel autoritaire, fiable même en
    //      début de saison où les stats ne contiennent que la sélection nationale.
    //   2. clubTeamName : 1re ligne de stats non-nationale (dispo une fois le club
    //      ayant joué en championnat).
    //   3. Wikidata currentClub : dernier repli (proxy, parfois indisponible).
    // On ne renvoie JAMAIS la sélection nationale comme « club » (bug « France »).
    private func clubSubtitle(_ p: AFPlayerResponse) -> String? {
        if let apiClub = currentClub?.displayName, !apiClub.isEmpty { return apiClub }
        if let club = p.clubTeamName, !club.isEmpty { return club }
        if let wikiClub = wiki?.currentClub?.name, !wikiClub.isEmpty {
            return TeamNameFormatter.pretty(wikiClub)
        }
        return nil
    }

    // ── Sélecteur de chips principales (Identité / Stats saison) ─────────────
    private var mainTabPicker: some View {
        HStack(spacing: 8) {
            chip(title: L("player.tab.identity"),
                 isOn: mainTab == .identity) { mainTab = .identity }
            chip(title: L("player.tab.seasonStats"),
                 isOn: mainTab == .seasonStats) { mainTab = .seasonStats }
        }
        .frame(maxWidth: .infinity)
    }

    // Pastille de menu générique (chip pleine si active, contour léger sinon).
    private func chip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isOn ? .white : Theme.text)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(isOn ? Theme.brand : Theme.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isOn ? Color.clear : Theme.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // ── Chip 1 : IDENTITÉ ────────────────────────────────────────────────────
    // Les infos biographiques (infoCard) + la carte Équipe nationale (sélection,
    // total sélections, buts en sélection) que l'user voulait voir « complétées ».
    @ViewBuilder
    private func identitySection(_ p: AFPlayerResponse) -> some View {
        infoCard(p)
        nationalTeamCard(p)
    }

    // ── Chip 2 : STATS SAISON EN COURS (sous-chips sélectionnables) ──────────
    // Rangée de sous-chips (Total / Championnat / Coupes / Sélection / Amicaux),
    // limitée aux catégories réellement jouées cette saison. La grille de stats
    // se met à jour selon la sous-chip active. « Coupes » ajoute en plus le
    // détail par compétition (LDC, Coupe de France…).
    @ViewBuilder
    private func seasonStatsSection(_ p: AFPlayerResponse) -> some View {
        if let s = seasonStats {
            let scopes = availableScopes(s)           // toujours 3 (Champ./Coupes/Sél.)
            let active = scopes.contains(statScope) ? statScope : (scopes.first ?? .league)
            VStack(alignment: .leading, spacing: 12) {
                Text(L("player.currentSeasonStats"))
                    .font(.caption.weight(.bold)).foregroundColor(.gray)
                    .textCase(.uppercase)

                // Sous-chips (wrap sur plusieurs lignes si besoin).
                statScopePicker(scopes)

                // Contenu de la sous-chip active. Pour Championnat / Total → une
                // grille compacte (une compétition ou un cumul). Pour Coupes /
                // Sélections → une LISTE de compétitions (nom + stats sur une ligne),
                // pour qu'on sache TOUJOURS de quelle compétition on parle et sans
                // avoir à scroller.
                switch active {
                case .cups:
                    competitionList(s.cupCompetitions, emptyKey: "player.noCupYet")
                case .nations:
                    competitionList(s.nationCompetitions, emptyKey: "player.noSelectionYet")
                case .league:
                    // Sous-titre : précise la compétition (ex. « Ligue 1 »).
                    if let ctx = scopeContext(active, in: s), !ctx.isEmpty {
                        Text(ctx)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Theme.brand)
                    }
                    compactStatStrip(bucket(for: active, in: s))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        } else {
            noDataNotice
        }
    }

    // Sous-chips TOUJOURS présentes, dans l'ordre demandé : Championnat, Coupes,
    // Sélections. On les affiche même à 0 match (demande user : « si championnat
    // à 0 matchs mettre quand même »). Amicaux et Total retirés.
    private func availableScopes(_ s: AFPlayerResponse) -> [StatScope] {
        _ = s
        return [.league, .cups, .nations]
    }

    private func scopeTitle(_ scope: StatScope) -> String {
        switch scope {
        case .league:   return L("player.comp.league")
        case .cups:     return L("player.cat.cups")
        case .nations:  return L("player.comp.nations")
        }
    }

    private func bucket(for scope: StatScope, in s: AFPlayerResponse) -> AFPlayerResponse.StatBucket {
        switch scope {
        case .league:   return s.leagueBucket
        case .cups:     return s.cupsTotalBucket
        case .nations:  return s.nationalTotalBucket
        }
    }

    // Précise la compétition concernée par la sous-chip (affiché sous les chips) :
    // Championnat → nom de la ligue (« Ligue 1 »), Sélections → nom de la sélection
    // (« France »). Coupes = détaillé par lignes, Total = cumul → pas de contexte.
    private func scopeContext(_ scope: StatScope, in s: AFPlayerResponse) -> String? {
        switch scope {
        case .league:   return s.leagueName
        case .nations:  return s.nationalTeamName
        case .cups:     return nil
        }
    }

    // Rangée de sous-chips (grille souple 3 par ligne, wrap).
    private func statScopePicker(_ scopes: [StatScope]) -> some View {
        let columns = [GridItem(.flexible(), spacing: 8),
                       GridItem(.flexible(), spacing: 8),
                       GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(scopes.enumerated()), id: \.offset) { _, scope in
                Button { statScope = scope } label: {
                    Text(scopeTitle(scope))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(statScope == scope ? .white : Theme.text)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(statScope == scope ? Theme.brand : Theme.surface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(statScope == scope ? Color.clear : Theme.hairline,
                                             lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ── Bandeau de stats COMPACT (une ligne, pas de scroll) ──────────────────
    // Remplace l'ancienne grille haute (note + 6 cellules). Affiche une rangée
    // horizontale de mini-stats : note, matchs, buts, passes, jaunes/rouges,
    // titularisations. Tient à l'écran sans scroll. Utilisé pour Championnat/Total.
    private func compactStatStrip(_ b: AFPlayerResponse.StatBucket) -> some View {
        var items: [(icon: String, tint: Color, value: String, label: String)] = []
        if let r = b.rating {
            items.append(("star.fill", .green, String(format: "%.1f", r), L("player.rating")))
        }
        items.append(("sportscourt.fill", .blue, "\(b.appearances)", L("player.appearances")))
        items.append(("soccerball", .green, "\(b.goals)", L("player.goals")))
        items.append(("hand.point.up.left.fill", .teal, "\(b.assists)", L("player.assists")))
        items.append(("figure.stand", .indigo, "\(b.lineups)", L("player.starts")))
        items.append(("rectangle.portrait.fill", .yellow, "\(b.yellowCards)", L("player.yellowCards")))
        items.append(("rectangle.portrait.fill", .red, "\(b.redCards)", L("player.redCards")))
        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, it in
                VStack(spacing: 5) {
                    Image(systemName: it.icon).font(.footnote).foregroundColor(it.tint)
                    Text(it.value)
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundColor(.black)
                    Text(it.label)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color.gray.opacity(0.7))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 4)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // ── Liste de compétitions (Coupes / Sélections) ──────────────────────────
    // Une carte par compétition RÉELLE (nom + logo + stats en ligne). On sait
    // TOUJOURS de quelle compétition on parle (Trophée des Champions, Euro U21…).
    @ViewBuilder
    private func competitionList(_ comps: [AFPlayerResponse.CompetitionBucket],
                                 emptyKey: String) -> some View {
        if comps.isEmpty {
            Text(L(emptyKey)).font(.caption).foregroundColor(.gray)
        } else {
            VStack(spacing: 8) {
                ForEach(comps) { comp in competitionRow(comp) }
            }
        }
    }

    // Une carte compétition : ligne 1 = logo + nom (+ note à droite),
    // ligne 2 = mini-stats en ligne (matchs, buts, passes, jaunes, titul.).
    private func competitionRow(_ comp: AFPlayerResponse.CompetitionBucket) -> some View {
        let b = comp.bucket
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TeamLogoView(urlString: comp.logo, name: comp.name, size: 24)
                Text(comp.name)
                    .font(.subheadline.weight(.semibold)).foregroundColor(.black)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 6)
                if let r = b.rating {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill").font(.caption2).foregroundColor(.green)
                        Text(String(format: "%.1f", r))
                            .font(.caption.weight(.bold).monospacedDigit()).foregroundColor(.black)
                    }
                }
            }
            HStack(spacing: 0) {
                inlineStat("sportscourt.fill", .blue, b.appearances, L("player.appearances"))
                inlineStat("soccerball", .green, b.goals, L("player.goals"))
                inlineStat("hand.point.up.left.fill", .teal, b.assists, L("player.assists"))
                inlineStat("figure.stand", .indigo, b.lineups, L("player.starts"))
                inlineStat("rectangle.portrait.fill", .yellow, b.yellowCards, L("player.yellowCards"))
                inlineStat("rectangle.portrait.fill", .red, b.redCards, L("player.redCards"))
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // Mini-stat en ligne : icône + valeur + libellé court, largeur égale.
    private func inlineStat(_ icon: String, _ tint: Color, _ value: Int, _ label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption2).foregroundColor(tint)
            Text("\(value)")
                .font(.subheadline.weight(.bold).monospacedDigit()).foregroundColor(.black)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(Color.gray.opacity(0.7))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    // Carte d'infos compacte — grille de 2 colonnes : date de naissance + âge,
    // lieu de naissance (drapeau devant), nationalité (drapeau devant), taille, poids, poste.
    // Chaque cellule ne s'affiche que si la donnée existe.
    // PAS de @ViewBuilder ici : le corps commence par des instructions
    // impératives (construction de `cells`) puis retourne UNE vue (LazyVGrid).
    // Un @ViewBuilder traiterait `cells.append(...)` comme une vue → erreur
    // « Type '()' cannot conform to 'View' ».
    private func infoCard(_ p: AFPlayerResponse) -> some View {
        let natFlag = CountryFlag.emoji(for: p.player.nationality)
        let birthFlag = CountryFlag.emoji(for: p.player.birth?.country)
        // Construit la liste des cellules disponibles.
        var cells: [(icon: String, prefix: String, label: String, value: String)] = []
        if let d = p.player.birth?.date, !d.isEmpty {
            cells.append(("calendar", "", L("player.birth"), fullDate(d)))
        }
        if let age = p.player.age {
            cells.append(("number", "", L("player.age"), "\(age) \(L("player.yearsShort"))"))
        }
        if let place = p.player.birth?.place, !place.isEmpty {
            cells.append(("mappin.and.ellipse", birthFlag, L("player.birthPlace"), place))
        }
        if let nat = p.player.nationality, !nat.isEmpty {
            cells.append(("flag", natFlag, L("player.nationality"), nat))
        }
        if let h = p.player.height, !h.isEmpty {
            cells.append(("ruler", "", L("player.height"), formatHeight(h)))
        }
        if let w = p.player.weight, !w.isEmpty {
            cells.append(("scalemass", "", L("player.weight"), formatWeight(w)))
        }
        if let pos = p.displayPosition {
            cells.append(("figure.soccer", "", L("player.position"), pos))
        }
        // NB : les sélections/buts en équipe nationale sont désormais dans la carte
        // dédiée « Équipe nationale » (nationalTeamCard) — on ne les duplique plus ici.

        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                infoCell(icon: c.icon, flagPrefix: c.prefix, label: c.label, value: c.value)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    // Une cellule de la grille : libellé en petit + valeur (drapeau optionnel devant).
    private func infoCell(icon: String, flagPrefix: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2).foregroundColor(.gray)
                Text(label).font(.caption2).foregroundColor(.gray)
                    .textCase(.uppercase)
            }
            HStack(spacing: 4) {
                if !flagPrefix.isEmpty { Text(flagPrefix).font(.subheadline) }
                Text(value).font(.subheadline.weight(.semibold)).foregroundColor(.black)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Taille API = String en cm ("191") → "1,91 m" (ou "191 cm" si non numérique).
    private func formatHeight(_ h: String) -> String {
        let digits = h.filter { $0.isNumber }
        if let cm = Int(digits), cm > 0 {
            let m = Double(cm) / 100.0
            return String(format: "%.2f m", m)
        }
        return h
    }

    // Poids API = String en kg ("80") → "80 kg".
    private func formatWeight(_ w: String) -> String {
        let digits = w.filter { $0.isNumber }
        if let kg = Int(digits), kg > 0 { return "\(kg) kg" }
        return w
    }

    // Carte stats — SAISON EN COURS, CLUB UNIQUEMENT. Même esprit que infoCard :
    // grille de cellules compactes, chacune avec une pastille d'icône colorée, la
    // valeur en gros et un libellé. Les 5 stats de base (matchs, buts, passes,
    // cartons jaunes, cartons rouges) sont TOUJOURS présentes (même à 0, car on est
    // certain que c'est la saison en cours). Minutes, titularisations et note ne
    // s'affichent que si la donnée existe (souvent absente en divisions basses).
    // PAS de @ViewBuilder : le corps construit un tableau `cells` de façon
    // impérative puis retourne UNE vue (LazyVGrid), comme infoCard.
    private func statsCard(_ p: AFPlayerResponse) -> some View {
        // (icône SF Symbol, teinte, valeur, libellé)
        // La NOTE MOYENNE est traitée à part (bandeau mis en avant) : on ne la met
        // PLUS dans la grille des cellules ordinaires.
        var cells: [(icon: String, tint: Color, value: String, label: String)] = []
        cells.append(("sportscourt.fill", .blue, "\(p.clubAppearances)", L("player.appearances")))
        cells.append(("soccerball", .green, "\(p.clubGoals)", L("player.goals")))
        cells.append(("hand.point.up.left.fill", .teal, "\(p.clubAssists)", L("player.assists")))
        cells.append(("rectangle.portrait.fill", .yellow, "\(p.clubYellowCards)", L("player.yellowCards")))
        cells.append(("rectangle.portrait.fill", .red, "\(p.clubRedCards)", L("player.redCards")))
        if p.clubLineups > 0 {
            cells.append(("figure.stand", .indigo, "\(p.clubLineups)", L("player.starts")))
        }
        if p.clubMinutes > 0 {
            cells.append(("clock.fill", .orange, "\(p.clubMinutes)", L("player.minutes")))
        }

        let columns = [GridItem(.flexible(), spacing: 10),
                       GridItem(.flexible(), spacing: 10),
                       GridItem(.flexible(), spacing: 10)]
        return VStack(alignment: .leading, spacing: 12) {
            Text(L("player.currentSeasonStats"))
                .font(.caption.weight(.bold)).foregroundColor(.gray)
                .textCase(.uppercase)

            // Note moyenne MISE EN AVANT (élément important) : bandeau large en tête,
            // avant la grille, uniquement si l'API fournit la note pour cette saison.
            if let rating = p.clubRating {
                ratingBanner(rating)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                    statCell(icon: c.icon, tint: c.tint, value: c.value, label: c.label)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    // Bandeau NOTE MOYENNE — élément mis en avant. Grande étoile + valeur en gros
    // sur un fond violet doux, occupe toute la largeur pour capter le regard.
    // Couleur de la note = repère qualité (rouge < 6, orange < 6,5, vert < 7,5, or au-delà).
    @ViewBuilder
    private func ratingBanner(_ rating: Double) -> some View {
        let color: Color = {
            switch rating {
            case ..<6.0:  return .red
            case ..<6.5:  return .orange
            case ..<7.5:  return .green
            default:      return Theme.gold
            }
        }()
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.16)).frame(width: 52, height: 52)
                Image(systemName: "star.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L("player.rating"))
                    .font(.caption.weight(.semibold)).foregroundColor(.gray)
                    .textCase(.uppercase)
                Text(String(format: "%.1f", rating))
                    .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundColor(.black)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }

    // Une cellule de stat : pastille d'icône teintée + valeur en gros + libellé.
    private func statCell(icon: String, tint: Color, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(tint.opacity(0.15)).frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(tint)
            }
            Text(value)
                .font(.title3.weight(.bold)).foregroundColor(.black)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2).foregroundColor(.gray)
                .multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    // Carte ÉQUIPE NATIONALE (carrière). Trois infos alignées :
    //   • Sélection : nom du pays (Wikidata, repli nationalité API) + drapeau
    //   • Sélections : total de matchs A
    //   • Buts : total de buts en sélection A
    //
    // Sources et repli (demande user 2026-08-18 : « il manque le nombre de
    // sélections et de buts en sélection en mode carrière ») :
    //   1. Wikidata (carrière complète) — source privilégiée si disponible.
    //   2. Repli API-Football : cumul des lignes de sélection de la saison en cours
    //      (nationalAppearances / nationalGoals). Moins complet mais toujours dispo
    //      pour un jeune joueur dont Wikidata n'a pas encore les totaux (ex. Doué).
    //   3. « — » honnête quand une valeur reste inconnue (pas de 0 inventé).
    //
    // On affiche la carte dès qu'on connaît la SÉLECTION (nom de pays) ou au moins
    // un nombre de sélections, pour que l'info soit présente en mode Identité.
    // Wikidata renvoie le nom LONG de la sélection (« équipe d'Espagne de
    // football », « France national football team »…). On extrait le nom du PAYS
    // pour un affichage sobre (« Espagne », « France »). Retire les gabarits fr/en
    // usuels ; si rien ne matche, on renvoie le nom nettoyé tel quel. nil si vide.
    private static func prettyNationalTeam(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        var s = raw.trimmingCharacters(in: .whitespaces)
        // Français : « équipe de/d'/du/des <Pays> de football (des moins de …) »
        if let r = s.range(of: #"^équipe d[e'](?:s| du| de la| de l')?\s*"#,
                           options: [.regularExpression, .caseInsensitive]) {
            s.removeSubrange(r)
        }
        // Retire les suffixes descriptifs (fr + en), y compris catégories d'âge.
        let suffixes = [" de football", " national football team",
                        " national association football team",
                        " football team", " men's national football team"]
        for suf in suffixes {
            if let r = s.range(of: suf, options: [.caseInsensitive]) {
                s = String(s[..<r.lowerBound])
            }
        }
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }

    @ViewBuilder
    private func nationalTeamCard(_ p: AFPlayerResponse) -> some View {
        // Nom de la sélection : Wikidata d'abord, nettoyé (« équipe d'Espagne de
        // football » → « Espagne »), repli sur la nationalité API.
        let teamName = Self.prettyNationalTeam(wiki?.nationalTeam)
            ?? (p.player.nationality?.isEmpty == false ? p.player.nationality : nil)

        // Sélections (caps) : Wikidata > repli stats saison API (si > 0).
        let apiCaps = p.nationalAppearances
        let capsValue: Int? = (wiki?.nationalCaps).flatMap { $0 > 0 ? $0 : nil }
            ?? (apiCaps > 0 ? apiCaps : nil)

        // Buts en sélection : Wikidata > repli stats saison API (si > 0).
        let apiGoals = p.nationalGoals
        let goalsValue: Int? = wiki?.nationalGoals
            ?? (apiGoals > 0 ? apiGoals : nil)

        // On affiche la carte si on a un nom de sélection OU un nombre de sélections.
        if (teamName?.isEmpty == false) || capsValue != nil {
            let flag = CountryFlag.emoji(for: p.player.nationality)
            VStack(alignment: .leading, spacing: 12) {
                Text(L("player.nationalTeam"))
                    .font(.caption.weight(.bold)).foregroundColor(.gray)
                    .textCase(.uppercase)

                // Bandeau sélection : drapeau + nom du pays.
                HStack(spacing: 10) {
                    Text(flag).font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("player.selection"))
                            .font(.caption2).foregroundColor(.gray).textCase(.uppercase)
                        Text(teamName ?? "—")
                            .font(.headline).foregroundColor(.black)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }

                // Sélections + buts, côte à côte. « — » quand la valeur est inconnue.
                let columns = [GridItem(.flexible(), spacing: 12),
                               GridItem(.flexible(), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    statCell(icon: "flag.checkered", tint: .blue,
                             value: capsValue.map { "\($0)" } ?? "—",
                             label: L("player.selections"))
                    statCell(icon: "soccerball", tint: .green,
                             value: goalsValue.map { "\($0)" } ?? "—",
                             label: L("player.nationalGoals"))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
    }

    // (La répartition des matchs par compétition est désormais intégrée aux
    //  sous-chips de la section « Stats saison en cours » — voir seasonStatsSection.)

    // Petits utilitaires de présentation --------------------------------------

    // Dates Wikidata : souvent au 1er janvier → seule l'ANNÉE est fiable.
    // (Toujours utilisé en repli par fullDate ci-dessous.)
    private func year(_ iso: String?) -> String? {
        guard let iso, iso.count >= 4 else { return nil }
        return String(iso.prefix(4))
    }
    // Date de naissance : jour réel fiable → on formate en date localisée.
    private func fullDate(_ iso: String) -> String {
        let inFmt = DateFormatter()
        inFmt.dateFormat = "yyyy-MM-dd"
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        guard let date = inFmt.date(from: iso) else { return year(iso) ?? iso }
        let out = DateFormatter()
        out.dateStyle = .long
        out.timeStyle = .none
        return out.string(from: date)
    }

    // Bandeau « aucun match cette saison » : honnête et sobre. S'affiche quand le
    // joueur n'a pas encore disputé de match cette saison (ex. L1 non démarrée) ou
    // qu'aucune stat de la saison en cours n'est disponible. On NE montre JAMAIS
    // les stats d'une saison passée à la place (règle d'or).
    private var noDataNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundColor(Theme.textSoft)
            Text(L("player.noSeasonMatch"))
                .font(.subheadline)
                .foregroundColor(Theme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private func load() async {
        guard detail == nil, !isLoading else { return }
        isLoading = true
        do {
            // (1) IDENTITÉ : repli tolérant (season, -1, -2) pour toujours afficher
            //     la fiche même en tout début de saison. Peut donc provenir d'une
            //     saison passée — on ne s'en sert QUE pour l'identité (nom, photo,
            //     âge, nationalité, poste), jamais pour les stats affichées.
            let d = try await FootballAPIService.shared.fetchPlayerDetail(playerId: playerId, season: currentSeason)
            detail = d

            // (2) CLUB ACTUEL (source /players/teams, autoritaire) : chargé TÔT et
            //     indépendamment du proxy. AVANT (bug 2026-08-18) il était résolu en
            //     DERNIER, après l'appel Wikidata (proxy externe, souvent lent) : tant
            //     que le proxy tardait, le sous-titre club restait vide → Mbappé
            //     s'affichait sans « Real Madrid ». On le lance donc juste après
            //     l'identité, en parallèle des enrichissements Wikidata/stats.
            async let clubTask = FootballAPIService.shared.fetchPlayerCurrentClub(playerId: playerId)

            // (3) Enrichissement carrière (Wikidata) : LANCÉ EN PARALLÈLE, dès qu'on
            //     a le nom (correctif délai 2026-08-18). AVANT il était `await` en
            //     DERNIER, après les stats + le club → sélections/buts (portés par
            //     Wikidata) n'apparaissaient qu'avec un gros retard. Désormais il
            //     tourne PENDANT les stats/club et finit souvent avant. Tolérant :
            //     si le proxy est absent/lent, la fiche reste utilisable.
            let name = d.fullName.isEmpty ? d.player.name : d.fullName
            async let wikiTask = FootballAPIService.shared.fetchWikidataPlayer(name: name)

            // (4) STATS SAISON EN COURS (strict, sans repli) : chargées à part. Si
            //     le joueur n'a pas encore joué cette saison, seasonStats reste nil
            //     → la vue affiche « aucun match cette saison » (zéros honnêtes),
            //     jamais les stats d'une saison passée.
            seasonStats = await FootballAPIService.shared.fetchPlayerSeasonStats(playerId: playerId, season: currentSeason)

            // Chaque enrichissement s'affiche dès qu'il est prêt (les 3 tournent
            // en parallèle). Le club et Wikidata ne se bloquent plus l'un l'autre.
            currentClub = await clubTask
            wiki = await wikiTask
        } catch {
            print("⚠️ PlayerDetailView player \(playerId) : \(error)")
            failed = true
        }
        isLoading = false
    }
}
