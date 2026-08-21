import SwiftUI
import Combine

/// Écran « Live » — REFONDU.
///
/// EN HAUT : une barre épurée « ◄ [3 jours] ► ». Les trois pastilles centrales
/// forment une fenêtre GLISSANTE de 3 jours datés ; la flèche gauche recule de
/// 3 jours, la flèche droite avance de 3 jours. La pastille du jour porte en plus
/// la mention Hier / Aujourd'hui / Demain quand elle s'applique.
///
/// POUR LE JOUR SÉLECTIONNÉ : on affiche les matchs, regroupés et PRIORISÉS :
///   1. FAVORIS   — dès qu'une équipe favorite joue (titre « Favoris ») ;
///   2. FRANCE    — matchs impliquant une équipe française ;
///   3. EUROPE    — coupes d'Europe des clubs ;
///   4. MONDE     — tout le reste.
/// Chaque groupe est dépliable / repliable (Favoris ouvert par défaut).
///
/// ÉTAT DU MATCH : terminé → score final ; en direct → score live (rouge) +
/// minute ; à venir → heure du coup d'envoi (+ lieu si connu).
struct LiveView: View {
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var followed: FollowedCompetitionsStore

    /// Toute la fenêtre ±`dayRadius`, récupérée en une passe puis filtrée par jour.
    @State private var allFixtures: [AFFixture] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastUpdate = Date()

    /// Mode « tout le catalogue ». FAUX par défaut (économie de quota) : le Live ne
    /// garde alors que les matchs des compétitions SUIVIES + des équipes favorites.
    /// Le bouton « Tout afficher » le passe à VRAI → on garde aussi tout le catalogue
    /// branché (compétitions non suivies incluses). ⚠️ Dans les DEUX modes, le coût
    /// réseau est identique : `/fixtures?date=` charge tous les matchs du jour en
    /// UNE requête, quel que soit le filtre — `showAllCatalog` n'agit que sur le
    /// FILTRAGE côté client, pas sur le nombre de requêtes. Réinitialisé à chaque
    /// lancement (choix user 2026-08-18 : le Live s'ouvre léger, on élargit à la demande).
    /// ⚠️ Cas particulier (choix user 2026-08-18) : si l'utilisateur ne suit AUCUNE
    /// compétition, on force l'affichage COMPLET du catalogue (voir `effectiveShowAll`
    /// et `load()`), sinon le Live serait vide — un bandeau l'invite alors à filtrer.
    @State private var showAllCatalog = false

    /// Nombre de matchs du jour SÉLECTIONNÉ présents dans tout le catalogue branché
    /// (indépendamment du filtre « compétitions suivies »). Renseigné à chaque `load()`
    /// GRATUITEMENT depuis la même requête. Sert à distinguer, quand l'écran filtré est
    /// vide : « d'autres championnats jouent aujourd'hui » (>0) vs « pas de match du
    /// tout » (==0). Clé = `dayKey(selectedDay)` pour rester valable en changeant de jour.
    @State private var catalogTotals: [String: Int] = [:]

    /// Bandeau d'aide (toast) affiché UNIQUEMENT quand l'utilisateur ne suit AUCUNE
    /// compétition : le Live montre alors tout le catalogue et on l'invite à filtrer
    /// via Favoris → Compétitions. S'efface tout seul après quelques secondes, ou au
    /// tap sur la croix. `followHintToken` sert à annuler l'auto-dismiss si l'état change.
    @State private var showFollowHint = false
    @State private var followHintToken = 0

    /// VRAI si l'affichage montre de fait tout le catalogue : soit sur demande
    /// explicite (« Tout afficher »), soit parce qu'aucune compétition n'est suivie.
    private var effectiveShowAll: Bool { showAllCatalog || followed.apiIds.isEmpty }

    /// Jour affiché. Aujourd'hui par défaut.
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    /// Début de la fenêtre glissante de 3 jours (pastille de gauche).
    /// Par défaut : hier → [Hier · Aujourd'hui · Demain].
    @State private var windowStart: Date =
        Calendar.current.date(byAdding: .day, value: -1,
                              to: Calendar.current.startOfDay(for: Date()))!

    /// Groupes dépliés. Clé propre au jour : "\(dayKey)#\(group.rawValue)".
    @State private var expandedGroups: Set<String> = []

    /// Timer de rafraîchissement auto (30 s) — actif seulement en regardant aujourd'hui.
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    /// Rayon de navigation autorisé dans la barre de dates (jours de part et d'autre
    /// d'aujourd'hui) — borne les flèches ◀ ▶. Choix user 2026-08-18 : ±4 jours
    /// (fenêtre de 9 jours max). ⚠️ Le chargement se fait PAR JOUR affiché via
    /// `/fixtures?date=` (1 requête = tous les matchs du jour, toutes compétitions) :
    /// le coût dépend donc du NOMBRE DE JOURS consultés. Plus on autorise de jours,
    /// plus le plafond de requêtes monte → on plafonne à 9 jours pour brider la conso.
    /// Les jours passés étant en cache 24 h (voir `ttl(for:)`), y revenir est gratuit.
    private let dayRadius = 4

    // ── Groupes prioritaires, dans l'ordre d'affichage ─────────────────────────
    // Choix user 2026-08-17 : on aligne le Live sur les 3 grandes familles de
    // l'onglet Compétitions (mêmes libellés) : Favoris d'abord, puis CHAMPIONNATS,
    // COUPES D'EUROPE (clubs) et NATIONS (sélections). On réutilise donc les clés
    // `seg.*` pour que les titres soient EXACTEMENT « Championnats / Coupes
    // d'Europe / Nations » comme dans le menu du haut.
    // Choix user 2026-08-17 (v2) : 3 rubriques SEULEMENT — Championnats / Coupes /
    // Nations — plus le bloc Favoris en tête. Les COUPES regroupent désormais les
    // coupes nationales (Coupe de France…) ET les coupes d'Europe des clubs (UCL/
    // UEL…). Dans chaque rubrique : France d'abord, puis le TOP 4 européen
    // (Angleterre, Espagne, Italie, Allemagne), puis le reste.
    enum LiveGroup: Int, CaseIterable, Identifiable {
        case favorites
        case championships
        case cups
        case nations
        var id: Int { rawValue }

        var titleKey: String {
            switch self {
            case .favorites:     return "live.favorites"
            case .championships: return "seg.championships"
            case .cups:          return "seg.cups"
            case .nations:       return "seg.nations"
            }
        }
        var symbol: String {
            switch self {
            case .favorites:     return "star.fill"
            case .championships: return "sportscourt.fill"
            case .cups:          return "trophy.fill"
            case .nations:       return "flag.2.crossed.fill"
            }
        }
        var accent: Color {
            switch self {
            case .favorites:     return Theme.gold
            case .championships: return Theme.brand
            case .cups:          return Color(red: 0.20, green: 0.15, blue: 0.55)
            case .nations:       return Color(red: 0.60, green: 0.12, blue: 0.20)
            }
        }
    }

    /// Un groupe affiché : le type + ses matchs (triés par heure).
    struct DisplayGroup: Identifiable {
        let group: LiveGroup
        let fixtures: [AFFixture]
        var id: Int { group.rawValue }
    }

    // ── Aides de dates ──────────────────────────────────────────────────────────
    private func dayKey(_ day: Date) -> String { String(Int(day.timeIntervalSince1970)) }

    private var isViewingToday: Bool { Calendar.current.isDateInToday(selectedDay) }

    /// Les 3 jours de la fenêtre glissante actuelle.
    private var windowDays: [Date] {
        let cal = Calendar.current
        return (0..<3).compactMap { cal.date(byAdding: .day, value: $0, to: windowStart) }
    }

    // ── Classement d'un match dans une des 3 grandes familles ──────────────────
    // Priorité : Favoris d'abord. Puis la NATURE de la compétition :
    //   • Sélection nationale (section .nations)                    → nations
    //   • Coupe (kind == .cup / .mixed) OU coupe d'Europe des clubs  → cups
    //   • Tout championnat de clubs (kind == .league / .leagueGroups) → championships
    // Les coupes d'Europe (UCL/UEL…) rejoignent volontairement « Coupes ».
    private func group(for f: AFFixture) -> LiveGroup {
        let favIds = Set(favorites.teams.map { $0.id })
        if favIds.contains(f.teams.home.id) || favIds.contains(f.teams.away.id) {
            return .favorites
        }
        if let comp = Catalog.competition(forLeagueId: f.league.id) {
            if comp.section == .nations { return .nations }
            if comp.section == .europe { return .cups }        // coupes d'Europe des clubs
            switch comp.kind {
            case .cup, .mixed:            return .cups
            case .league, .leagueGroups:  return .championships
            }
        }
        // Hors catalogue : traité comme un championnat de clubs.
        return .championships
    }

    // ── Priorité pays pour l'ordre des compétitions dans une rubrique ──────────
    // France d'abord (0), puis le TOP 4 européen (Angleterre, Espagne, Italie,
    // Allemagne = 1…4), puis tout le reste (5). Déduit du drapeau (countryCode)
    // de la compétition au catalogue — `AFLeague` (fixture) n'a pas de pays fiable.
    private func countryPriority(forLeagueId leagueId: Int) -> Int {
        guard let cc = Catalog.competition(forLeagueId: leagueId)?.countryCode else { return 5 }
        switch cc {
        case "🇫🇷":              return 0   // France
        case "🏴󠁧󠁢󠁥󠁮󠁧󠁿": return 1   // Angleterre
        case "🇪🇸":              return 2   // Espagne
        case "🇮🇹":              return 3   // Italie
        case "🇩🇪":              return 4   // Allemagne
        default:                  return 5
        }
    }

    /// Les matchs du jour sélectionné, groupés Favoris → France → Europe → Monde.
    private var groupsForSelectedDay: [DisplayGroup] {
        let cal = Calendar.current
        let dayMatches = allFixtures.filter {
            guard let d = $0.isoDate else { return false }
            return cal.isDate(d, inSameDayAs: selectedDay)
        }
        var byGroup: [LiveGroup: [AFFixture]] = [:]
        for f in dayMatches { byGroup[group(for: f), default: []].append(f) }

        return LiveGroup.allCases.compactMap { g in
            guard let items = byGroup[g], !items.isEmpty else { return nil }
            // Ordre DANS une rubrique (Championnats / Coupes / Nations) :
            //   1) priorité PAYS de la compétition : France, puis TOP 4 (Angleterre,
            //      Espagne, Italie, Allemagne), puis le reste ;
            //   2) pour les coupes d'Europe / sélections (pas de pays propre), on
            //      promeut d'abord les compétitions ayant AU MOINS un match français ;
            //   3) rang catalogue → chaque compétition reste un BLOC contigu
            //      (la bannière ne s'affiche qu'au changement de compétition) ;
            //   4) à compétition égale : matchs français d'abord, puis l'heure.
            let api = FootballAPIService.shared
            // Compétitions (coupes/nations) qui contiennent un camp français : à hisser
            // en tête même si leur drapeau n'est pas 🇫🇷 (ex. UCL avec le PSG).
            let promoteFrench = (g == .cups || g == .nations)
            let leaguesWithFrench: Set<Int> = promoteFrench
                ? Set(items.filter { api.isFrenchFixture($0) }.map { $0.league.id })
                : []
            let sorted = items.sorted { a, b in
                // 1) Priorité pays de la compétition (France → TOP 4 → reste).
                let ca = countryPriority(forLeagueId: a.league.id)
                let cb = countryPriority(forLeagueId: b.league.id)
                if ca != cb { return ca < cb }
                // 2) Bloc « compétition avec présence française » avant les autres.
                if promoteFrench {
                    let fa = leaguesWithFrench.contains(a.league.id)
                    let fb = leaguesWithFrench.contains(b.league.id)
                    if fa != fb { return fa && !fb }
                }
                // 3) Rang catalogue = clé de bloc → chaque compétition reste groupée.
                let ra = Catalog.rank(forLeagueId: a.league.id)
                let rb = Catalog.rank(forLeagueId: b.league.id)
                if ra != rb { return ra < rb }
                // 4) À compétition égale : matchs français d'abord, puis l'heure.
                if promoteFrench {
                    let fa = api.isFrenchFixture(a), fb = api.isFrenchFixture(b)
                    if fa != fb { return fa && !fb }
                }
                return a.fixture.date < b.fixture.date
            }
            return DisplayGroup(group: g, fixtures: sorted)
        }
    }

    private var selectedDayMatchCount: Int {
        groupsForSelectedDay.reduce(0) { $0 + $1.fixtures.count }
    }

    private func matchCount(on day: Date) -> Int {
        let cal = Calendar.current
        return allFixtures.filter {
            guard let d = $0.isoDate else { return false }
            return cal.isDate(d, inSameDayAs: day)
        }.count
    }

    var timeSinceUpdate: String {
        let secs = Int(Date().timeIntervalSince(lastUpdate))
        if secs < 60 { return String(format: L("live.updatedSecs"), secs) }
        return String(format: L("live.updatedMins"), secs / 60)
    }

    // ── Corps ─────────────────────────────────────────────────────────────────
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dateBar
                Divider()
                content
            }
            .overlay(alignment: .bottom) {
                if showFollowHint { followHintToast }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 6) {
                        if isLoading { ProgressView().scaleEffect(0.8) }
                        Text(timeSinceUpdate)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
        .task {
            // À l'ouverture : Favoris déplié pour aujourd'hui.
            if expandedGroups.isEmpty {
                expandedGroups.insert("\(dayKey(selectedDay))#\(LiveGroup.favorites.rawValue)")
            }
            if allFixtures.isEmpty { await load() }
            triggerFollowHintIfNeeded()
        }
        // Si l'utilisateur suit/dé-suit des compétitions depuis Favoris pendant
        // que le Live est monté, on réévalue le bandeau d'aide.
        .onChange(of: followed.apiIds) { _, _ in
            triggerFollowHintIfNeeded()
        }
        .onReceive(refreshTimer) { _ in
            if isViewingToday { Task { await load() } }
        }
        // Le chargement se fait PAR JOUR (`/fixtures?date=`) : dès que le jour
        // sélectionné change (chip de la barre ou flèches ◀ ▶ qui déplacent aussi
        // `selectedDay`), on charge ce jour-là. `load()` accumule (dédoublonné), donc
        // revenir sur un jour déjà chargé ne relance rien côté réseau (jours en
        // mémoire + cache disque 24 h pour le passé).
        .onChange(of: selectedDay) { _, _ in
            Task { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && allFixtures.isEmpty {
            LoadingView(label: L("live.searching"))
        } else if let err = errorMessage {
            ErrorView(message: err) { Task { await load() } }
        } else if selectedDayMatchCount == 0 {
            emptyStateForDay
        } else {
            List {
                ForEach(groupsForSelectedDay) { dg in
                    groupRows(dg)
                }
                // En mode léger : proposer d'élargir à tout le catalogue (charge le
                // reste des matchs du jour, compétitions non suivies incluses).
                if !effectiveShowAll {
                    showAllRow
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await load() }
        }
    }

    /// Ligne / bouton « Tout afficher » : bascule en mode catalogue complet.
    @ViewBuilder
    private var showAllRow: some View {
        Button {
            Task { await loadAllCatalog() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe.europe.africa.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("live.showAll"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text(L("live.showAll.note"))
                        .font(.caption)
                        .foregroundColor(Theme.textSoft)
                }
                Spacer()
                if isLoading { ProgressView().scaleEffect(0.8) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// État vide du jour sélectionné, avec DEUX messages distincts (choix user
    /// 2026-08-18) :
    ///   • si d'AUTRES championnats jouent ce jour (catalogue > 0) mais rien dans les
    ///     compétitions suivies → message convivial + bouton « Afficher les autres
    ///     championnats » (bascule tout le catalogue) ;
    ///   • si AUCUN match nulle part ce jour (catalogue == 0) → « Pas de match à
    ///     regarder aujourd'hui », sans bouton (rien à afficher de toute façon).
    /// On n'affiche l'invite « autres championnats » qu'en mode léger (des comp. sont
    /// suivies) ; en mode « tout affiché », un écran vide = vraiment aucun match.
    @ViewBuilder
    private var emptyStateForDay: some View {
        let hasOthers = (catalogTotals[dayKey(selectedDay)] ?? 0) > 0
        if !effectiveShowAll && hasOthers {
            emptyState(
                title: L("live.noFollowedTitle"),
                body: L("live.noFollowedBody"),
                showAllButton: true
            )
        } else {
            emptyState(
                title: L("live.noMatchAnywhereTitle"),
                body: L("live.noMatchAnywhereBody"),
                showAllButton: false
            )
        }
    }

    @ViewBuilder
    private func emptyState(title: String, body: String, showAllButton: Bool) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: showAllButton ? "star.slash" : "calendar.badge.clock")
                .font(.system(size: 56)).foregroundColor(.secondary)
            Text(title).font(.title3).fontWeight(.semibold)
                .multilineTextAlignment(.center)
            Text(body)
                .font(.subheadline).foregroundColor(Theme.textSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if showAllButton {
                Button(L("live.showOtherLeagues")) { Task { await loadAllCatalog() } }
                    .buttonStyle(.borderedProminent).tint(Theme.brand)
            }
            Button(L("action.refresh")) { Task { await load() } }
                .buttonStyle(.bordered).tint(Theme.live)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // ── Barre du haut : ◄ [3 jours] ► ─────────────────────────────────────────
    private var dateBar: some View {
        HStack(spacing: 10) {
            arrowButton(systemName: "chevron.left") { shiftWindow(by: -3) }
            HStack(spacing: 8) {
                ForEach(windowDays, id: \.self) { day in
                    dateChip(day)
                }
            }
            .frame(maxWidth: .infinity)
            arrowButton(systemName: "chevron.right") { shiftWindow(by: 3) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func arrowButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(Theme.text)
                .frame(width: 38, height: 46)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func dateChip(_ day: Date) -> some View {
        let isSel = Calendar.current.isDate(day, inSameDayAs: selectedDay)
        let count = matchCount(on: day)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedDay = day }
            ensureFavoritesOpen(for: day)
        } label: {
            VStack(spacing: 2) {
                Text(dayLabel(day))
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .lineLimit(1)
                Text(dayNumber(day))
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                Text(count > 0 ? "\(count)" : " ")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundColor(isSel ? .white.opacity(0.9) : Theme.textSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSel ? Theme.live : Color(.secondarySystemBackground))
            .foregroundColor(isSel ? .white : Theme.text)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// Décale la fenêtre de 3 jours ET sélectionne le premier jour de la nouvelle
    /// fenêtre (retour visuel immédiat). Borné à ±`dayRadius` autour d'aujourd'hui
    /// pour ne jamais afficher des jours HORS de la fenêtre de données chargée
    /// (sinon jours garantis vides).
    private func shiftWindow(by days: Int) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // La barre montre 3 jours à partir de `windowStart` : on garde son 1er jour
        // entre J-dayRadius et J+dayRadius-2 pour que les 3 chips restent dans la fenêtre.
        guard let minStart = cal.date(byAdding: .day, value: -dayRadius, to: today),
              let maxStart = cal.date(byAdding: .day, value: dayRadius - 2, to: today),
              var newStart = cal.date(byAdding: .day, value: days, to: windowStart)
        else { return }
        if newStart < minStart { newStart = minStart }
        if newStart > maxStart { newStart = maxStart }
        guard newStart != windowStart else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            windowStart = newStart
            selectedDay = newStart
        }
        ensureFavoritesOpen(for: newStart)
    }

    /// Garantit que le groupe « Favoris » est déplié pour le jour donné.
    private func ensureFavoritesOpen(for day: Date) {
        expandedGroups.insert("\(dayKey(day))#\(LiveGroup.favorites.rawValue)")
    }

    /// Libellé du jour : « Hier » / « Auj. » / « Demain », sinon jour de semaine.
    private func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day)     { return L("day.todayShort") }
        if cal.isDateInYesterday(day) { return L("day.yesterdayShort") }
        if cal.isDateInTomorrow(day)  { return L("day.tomorrowShort") }
        let fmt = DateFormatter(); fmt.locale = Locale.current; fmt.dateFormat = "EEE"
        return fmt.string(from: day)
    }

    private func dayNumber(_ day: Date) -> String {
        let fmt = DateFormatter(); fmt.locale = Locale.current; fmt.dateFormat = "d/M"
        return fmt.string(from: day)
    }

    // ── Un groupe dépliable + ses matchs ───────────────────────────────────────
    @ViewBuilder
    private func groupRows(_ dg: DisplayGroup) -> some View {
        let key = "\(dayKey(selectedDay))#\(dg.group.rawValue)"
        let isOpen = expandedGroups.contains(key)
        LiveGroupHeader(
            symbol: dg.group.symbol,
            title: L(dg.group.titleKey),
            count: dg.fixtures.count,
            accent: dg.group.accent,
            isOpen: isOpen
        )
        .contentShape(Rectangle())
        .onTapGesture { toggle(group: key) }
        .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))

        if isOpen {
            ForEach(Array(dg.fixtures.enumerated()), id: \.element.id) { index, fixture in
                // Bannière PHOTO contextualisée de la compétition (Ligue 1 en bleu +
                // photo Ligue 1 en fondu, etc.), insérée dès que la compétition change
                // en descendant la liste triée du groupe → chaque compétition présente
                // ce jour-là a son visuel « premium » juste au-dessus de ses matchs.
                if let comp = competitionBanner(at: index, in: dg.fixtures) {
                    CompetitionBannerView(competition: comp, height: 62,
                                          showsSubtitle: false, logoSize: 34)
                        .listRowInsets(EdgeInsets(top: index == 0 ? 4 : 12,
                                                  leading: 14, bottom: 6, trailing: 14))
                        .listRowSeparator(.hidden)
                }

                NavigationLink(destination: MatchDetailView(fixture: fixture)) {
                    // Composant UNIQUE partout : même ligne que l'Accueil et les
                    // journées de compétition (identité visuelle cohérente). Le
                    // Live regroupe déjà par section → showsDateHeader = true (heure
                    // seule pour un match à venir).
                    MatchRowView(fixture: fixture, showsDateHeader: true)
                }
                .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 14))
            }
        }
    }

    /// Renvoie la compétition à afficher en bannière AVANT le match d'index `index`,
    /// c.-à-d. seulement quand la compétition change par rapport au match précédent
    /// (ou pour le tout premier match). `nil` sinon → pas de bannière répétée.
    private func competitionBanner(at index: Int, in fixtures: [AFFixture]) -> Competition? {
        guard let comp = Catalog.competition(forLeagueId: fixtures[index].league.id) else { return nil }
        if index == 0 { return comp }
        let prev = Catalog.competition(forLeagueId: fixtures[index - 1].league.id)
        return prev?.id == comp.id ? nil : comp
    }

    private func toggle(group key: String) {
        withAnimation(.easeInOut(duration: 0.22)) {
            if expandedGroups.contains(key) { expandedGroups.remove(key) }
            else { expandedGroups.insert(key) }
        }
    }

    // ── Chargement (TOUT le catalogue + équipes favorites) ───────────────────────
    // On charge tous les matchs des compétitions branchées de l'app, pas seulement
    // celles suivies : le Live liste ainsi tous les matchs du jour, même sans
    // compétition suivie. Les clubs favoris restent priorisés par le regroupement
    // (groupe « Favoris »), et n'apparaissent donc que si leur match tombe le jour
    // affiché. Les joueurs suivis ne concernent QUE l'accueil : pas résolus ici.
    /// Charge les matchs du SEUL jour sélectionné (`selectedDay`) via `/fixtures?date=`
    /// — UNE requête, TOUTES compétitions confondues (au lieu d'une requête par
    /// compétition suivie). Choix user 2026-08-18 : « limiter au max le nombre de
    /// requêtes » → on ne charge PAS les 3 jours de la barre d'un coup, seulement le
    /// jour réellement consulté. Le coût ne dépend donc plus du NOMBRE de compétitions
    /// suivies (suivre 5 ou 50 ligues coûte pareil), ni de la largeur de la fenêtre :
    /// chaque jour ouvert = au plus 1 requête, et un jour PASSÉ est ensuite servi
    /// depuis le cache 24 h (voir `ttl(for:)`) → y revenir est gratuit. Le filtrage
    /// catalogue/suivies/favoris est fait côté API-service. On accumule dans
    /// `allFixtures` (dédoublonné par ID) pour que la navigation entre jours déjà
    /// chargés soit instantanée et sans nouvelle requête.
    func load() async {
        isLoading = true; errorMessage = nil
        do {
            let api = FootballAPIService.shared
            let favTeamIds = favorites.teams.map { $0.id }
            let followedApiIds = Set(followed.apiIds)
            var collected: [Int: AFFixture] = [:]
            // On repart des matchs déjà en mémoire (navigation fluide entre jours).
            for f in allFixtures { collected[f.id] = f }
            // Choix user 2026-08-18 : si l'utilisateur NE SUIT AUCUNE compétition,
            // on affiche TOUT le catalogue par défaut (sinon le Live serait vide),
            // et un bandeau l'invite à filtrer via Favoris → Compétitions.
            let noneFollowed = followedApiIds.isEmpty
            let detailed = try await api.fetchDayForLiveDetailed(
                day: selectedDay,
                favoriteTeamIds: favTeamIds,
                includeAllCatalog: showAllCatalog || noneFollowed,
                followedApiIds: followedApiIds
            )
            for f in detailed.fixtures { collected[f.id] = f }
            allFixtures = collected.values.sorted { $0.fixture.date < $1.fixture.date }
            // Mémorise le total « catalogue » du jour (gratuit) pour l'état vide.
            catalogTotals[dayKey(selectedDay)] = detailed.catalogTotal
            lastUpdate = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Passe en mode « tout le catalogue » et recharge (bouton « Tout afficher »).
    /// On vide `allFixtures` pour repartir proprement : les jours déjà chargés en
    /// mode léger ne contenaient que les compétitions suivies.
    private func loadAllCatalog() async {
        showAllCatalog = true
        allFixtures = []
        await load()
    }

    // ── Bandeau d'aide « aucune compétition suivie » ───────────────────────────
    /// Affiche le bandeau si (et seulement si) aucune compétition n'est suivie,
    /// puis programme son extinction automatique (~7 s). Utilise `followHintToken`
    /// pour qu'un déclenchement plus récent annule un auto-dismiss en attente.
    private func triggerFollowHintIfNeeded() {
        guard followed.apiIds.isEmpty else {
            withAnimation { showFollowHint = false }
            return
        }
        followHintToken += 1
        let token = followHintToken
        withAnimation { showFollowHint = true }
        Task {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if token == followHintToken {
                withAnimation { showFollowHint = false }
            }
        }
    }

    /// Toast informatif : explique que tout le catalogue est affiché et invite à
    /// filtrer via Favoris → Compétitions. Fermable via la croix.
    private var followHintToast: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(Theme.brand)
            Text(L("live.followHint"))
                .font(.footnote)
                .foregroundColor(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                followHintToken += 1
                withAnimation { showFollowHint = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textSoft)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface2)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.brand.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte « compte à rebours » d'un prochain match favori (page d'accueil)
// ─────────────────────────────────────────────────────────────────────────────
// Affiche les deux équipes (logo + nom, l'équipe favorite mise en avant), la
// compétition, et un COMPTE À REBOURS qui se met à jour en direct (chaque
// seconde via `TimelineView(.periodic)`) : « J-3 · 14 h 20 min » quand c'est
// loin, puis « 02:14:07 » dans les dernières 24 h, puis « Coup d'envoi imminent »
// à l'heure du match. Bordure teintée marque (bleu/cyan) pour rester cohérent.
struct FavoriteCountdownCard: View {
    let fixture: AFFixture
    let favoriteIds: Set<Int>

    private var kickoff: Date { fixture.isoDate ?? Date() }

    /// Date + heure du coup d'envoi, formatées dans la locale courante (ex.
    /// « lun. 22 sept. · 20:45 »). `nil` si la fixture n'a pas de date valide.
    private var kickoffDateText: String? {
        guard fixture.isoDate != nil else { return nil }
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("EEE d MMM · HH:mm")
        fmt.timeZone = TimeZone(identifier: "Europe/Paris")
        return fmt.string(from: kickoff)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Ligne compétition (petit label discret).
            HStack(spacing: 6) {
                if let logo = fixture.league.logo, let url = URL(string: logo) {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFit()
                    } placeholder: { Color.clear }
                    .frame(width: 16, height: 16)
                }
                Text(CompetitionNameLocalizer.localized(fixture.league.name))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textSoft)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let dateText = kickoffDateText {
                    Text(dateText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textSoft)
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            // Ligne des équipes : domicile · vs · extérieur (badge « vs » centré).
            HStack(spacing: 8) {
                teamCell(fixture.teams.home)
                Text(L("home.next.vs"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.textSoft)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.surface2))
                    .fixedSize()
                teamCell(fixture.teams.away)
            }

            // Compte à rebours vivant.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                countdownLabel(now: context.date)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.brand.opacity(0.28), lineWidth: 1)
                )
        )
    }

    /// Cellule d'une équipe : logo + nom (favorite en gras/marque).
    @ViewBuilder
    private func teamCell(_ team: AFTeam) -> some View {
        let isFav = favoriteIds.contains(team.id)
        HStack(spacing: 6) {
            TeamLogoView(urlString: team.logo, name: team.name, size: 22, teamId: team.id)
            Text(team.displayName)
                .font(.system(size: 14, weight: isFav ? .bold : .medium))
                .foregroundColor(isFav ? Theme.text : Theme.textSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Le libellé du compte à rebours, calculé pour l'instant `now`.
    @ViewBuilder
    private func countdownLabel(now: Date) -> some View {
        let remaining = kickoff.timeIntervalSince(now)
        HStack(spacing: 6) {
            Image(systemName: "clock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.brand)
            Text(countdownText(remaining))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(Theme.brand)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.textFaint)
        }
    }

    /// Texte du compte à rebours selon le temps restant.
    private func countdownText(_ remaining: TimeInterval) -> String {
        if remaining <= 0 { return L("home.next.kickoffNow") }
        let totalSec = Int(remaining)
        let days = totalSec / 86_400
        let hours = (totalSec % 86_400) / 3_600
        let mins = (totalSec % 3_600) / 60
        let secs = totalSec % 60
        // > 24 h : « J-3 · 14 h 20 » (jours + heures + minutes, sans secondes).
        if days >= 1 {
            return String(format: L("home.next.countdownDays"), days, hours, mins)
        }
        // < 24 h : compte à rebours précis HH:MM:SS.
        return String(format: "%02d:%02d:%02d", hours, mins, secs)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// En-tête d'un groupe Live (Favoris / France / Europe / Monde)
// ─────────────────────────────────────────────────────────────────────────────
struct LiveGroupHeader: View {
    let symbol: String
    let title: String
    let count: Int
    let accent: Color
    let isOpen: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(accent)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.text)
                .lineLimit(1)
            Text("\(count)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundColor(Theme.textSoft)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Theme.surface2)
                .clipShape(Capsule())
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.textSoft)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
        }
    }
}

// NB : l'ancienne `LiveFixtureRow` a été remplacée par le composant UNIQUE
// `MatchRowView` (voir MatchCardComponents.swift), désormais partagé par l'Accueil,
// le Live et les journées de compétition pour une identité visuelle cohérente.
