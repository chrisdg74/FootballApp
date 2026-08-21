import SwiftUI

// ═════════════════════════════════════════════════════════════════════════════
// VUE À PHASES — pour les compétitions « mixed » (CDM, EURO, UCL, UEL, UECL, UNL)
// ─────────────────────────────────────────────────────────────────────────────
// Menu latéral GAUCHE listant les phases en ordre DÉCROISSANT :
//   Finale (haut) → 3e place → Demi-finales → Quarts → 8es → … → Phase de groupes.
// Panneau DROIT :
//   • phase de groupes → classements des groupes (A, B, C…)
//   • phase à élimination → liste des matchs du tour.
// Les phases sont déduites des `round` renvoyés par l'API-Football.
// ═════════════════════════════════════════════════════════════════════════════

struct PhaseDetailView: View {
    let competition: Competition
    @Environment(\.dismiss) private var dismiss

    @State private var fixtures: [AFFixture] = []
    @State private var groups: [[AFStandingEntry]] = []
    @State private var phases: [Phase] = []
    @State private var selected: Phase? = nil
    @State private var selectedGroupIndex = 0   // groupe choisi en phase de groupes
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// IDs des clubs français (chargés au démarrage) pour remonter en tête de liste
    /// les matchs/confrontations qui impliquent une équipe française.
    @State private var frenchIds: Set<Int> = []

    /// Bornes de l'édition affichée (1er et dernier match chargés). Sert au bandeau
    /// « dernière édition » quand la compétition est terminée depuis longtemps
    /// (tournois de sélections joués il y a des mois : CAN, Copa América…).
    @State private var editionStart: Date? = nil
    @State private var editionEnd: Date? = nil

    /// Onglet du haut : 0 = Phases (défaut), 1 = Stats cumulées. N'apparaît que si
    /// l'API fournit les stats joueurs (`hasScorers`), sinon la vue reste 100 % phases.
    @State private var topTab = 0

    /// Rubriques Stats proposées pour une coupe d'Europe : buteurs, passeurs,
    /// combos, meilleures attaques, meilleures défenses (depuis le 1er tour au
    /// cumulé). On exclut séries / domicile / extérieur (peu pertinents ici).
    private let euroStatKinds: [StatKind] = [.scorers, .assists, .combo, .bestAttack, .bestDefense, .fairPlay]

    // ── Qualifications ────────────────────────────────────────────────────────
    @State private var qualifiersExpanded = false           // sous-menu déplié ?
    @State private var selectedQualifier: Qualifier? = nil   // confédération choisie
    @State private var qualifierGroups: [[AFStandingEntry]] = []
    @State private var qualifierGroupIndex = 0
    @State private var isLoadingQualifier = false

    private var hasQualifiers: Bool { !(competition.qualifiers ?? []).isEmpty }

    /// Édition « passée » = son dernier match remonte à plus de ~5 mois. On affiche
    /// alors un bandeau précisant que les infos concernent la dernière édition jouée
    /// (utile pour la CAN, la Copa América, la Coupe d'Asie… hors compétition l'année
    /// en cours). Les compétitions en cours ou à venir n'affichent pas le bandeau.
    private var isPastEdition: Bool {
        guard let end = editionEnd else { return false }
        return end < Calendar.current.date(byAdding: .month, value: -5, to: Date())!
    }

    /// Phrase « Compétition disputée du <début> au <fin>. » avec dates localisées.
    /// Le calcul (DateFormatter, appels void) est fait ICI et non dans le ViewBuilder :
    /// un ViewBuilder n'accepte que des vues + `let`, pas d'instructions void comme
    /// `setLocalizedDateFormatFromTemplate` (sinon « Type '()' cannot conform to View »).
    private func editionDatesText(_ start: Date, _ end: Date) -> String {
        let fmt = DateFormatter()
        // Locale de la langue choisie dans l'app (endonyme des mois) ; « système »
        // → Locale.current. Le rawValue (« fr », « pt-PT »…) est un identifiant valide.
        let lang = LocaleManager.shared.language
        fmt.locale = lang == .system ? .current : Locale(identifier: lang.rawValue)
        fmt.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        return String(format: L("phase.pastEdition.dates"),
                      fmt.string(from: start), fmt.string(from: end))
    }

    /// Bandeau « dernière édition · du <début> au <fin> » (dates réelles de l'édition).
    @ViewBuilder
    private var pastEditionBanner: some View {
        if isPastEdition, let start = editionStart, let end = editionEnd {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(competition.color)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("phase.pastEdition"))
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text(editionDatesText(start, end))
                        .font(.caption2).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(competition.color.opacity(0.08))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            CompetitionHeaderView(competition: competition) { dismiss() }

            // Onglet du haut Phases | Stats — uniquement si les stats existent.
            if competition.hasScorers {
                Picker("", selection: $topTab) {
                    Text(L("phase.tab.phases")).tag(0)
                    Text(L("tab.stats")).tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.vertical, 8)
                Divider()
            }

            if topTab == 1 && competition.hasScorers {
                // Stats cumulées de la coupe (buteurs → meilleures défenses).
                CompetitionStatsView(competition: competition,
                                     availableKinds: euroStatKinds)
            } else if isLoading {
                LoadingView(label: L("loading"))
            } else if let err = errorMessage {
                ErrorView(message: err) { Task { await load() } }
            } else if phases.isEmpty {
                EmptyStateView(icon: "trophy", text: L("empty.noMatch"))
            } else {
                pastEditionBanner
                HStack(spacing: 0) {
                    phaseMenu
                    Divider()
                    phaseContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    // ── Menu latéral gauche : phases en ordre décroissant ────────────────────
    // Étroit + petite police pour tenir sur un écran d'iPhone sans troncature.
    private var phaseMenu: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(phases) { phase in
                    let isSel = selected == phase && selectedQualifier == nil
                    Button {
                        selected = phase
                        selectedQualifier = nil     // sortir du mode qualifs
                    } label: {
                        menuLabel(phase.displayName, selected: isSel)
                    }
                }

                // ── Sous-menu Qualifications (en bas, sous les phases) ──
                if hasQualifiers {
                    Divider().padding(.vertical, 4)
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { qualifiersExpanded.toggle() }
                    } label: {
                        HStack(spacing: 3) {
                            Text(L("phase.qualifiers"))
                                .font(.caption2)
                                .fontWeight(selectedQualifier != nil ? .semibold : .regular)
                                .foregroundColor(selectedQualifier != nil ? competition.color : .primary)
                                .lineLimit(2).minimumScaleFactor(0.7)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: qualifiersExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 7).padding(.vertical, 7)
                    }

                    if qualifiersExpanded {
                        ForEach(competition.qualifiers ?? []) { q in
                            let isSel = selectedQualifier == q
                            Button { selectQualifier(q) } label: {
                                HStack(spacing: 4) {
                                    Text(q.flag).font(.system(size: 11))
                                    Text(L(q.nameKey))
                                        .font(.system(size: 10))
                                        .fontWeight(isSel ? .semibold : .regular)
                                        .foregroundColor(isSel ? .white : .primary)
                                        .lineLimit(2).minimumScaleFactor(0.7)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 6).padding(.vertical, 6)
                                .padding(.leading, 4)   // léger retrait = sous-niveau
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSel ? competition.color : Color.clear)
                                )
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8).padding(.horizontal, 5)
        }
        .frame(width: 92)
        .background(Color(.secondarySystemBackground))
    }

    // Libellé standard d'une entrée de phase (factorisé).
    private func menuLabel(_ text: String, selected isSel: Bool) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(isSel ? .semibold : .regular)
            .foregroundColor(isSel ? .white : .primary)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSel ? competition.color : Color.clear)
            )
    }

    // ── Panneau droit ────────────────────────────────────────────────────────
    @ViewBuilder
    private var phaseContent: some View {
        if selectedQualifier != nil {
            qualifierContent
        } else if let phase = selected {
            if phase.isGroupStage {
                groupStandingsList
            } else {
                matchList(for: phase)
            }
        } else {
            EmptyStateView(icon: "sidebar.left", text: L("phase.select"))
        }
    }

    // ── Panneau Qualifications : groupes + classement de la confédération ──────
    @ViewBuilder
    private var qualifierContent: some View {
        if isLoadingQualifier {
            ProgressView(L("loading")).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if qualifierGroups.isEmpty {
            EmptyStateView(icon: "list.number", text: L("empty.noStandings"))
        } else {
            VStack(spacing: 0) {
                if qualifierGroups.count > 1 {
                    qualifierGroupSelector
                    Divider()
                }
                if qualifierGroups.indices.contains(safeQualifierGroupIndex) {
                    let group = qualifierGroups[safeQualifierGroupIndex]
                    List {
                        SwiftUI.Section {
                            StandingsHeaderView().listRowInsets(EdgeInsets())
                            ForEach(group) { entry in
                                StandingEntryRow(entry: entry, competition: competition)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                                    .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .environment(\.defaultMinListRowHeight, 0)

                    // Légende des couleurs d'enjeux (qualif, barrages…).
                    StakesLegendView(
                        stakes: StandingStakeClassifier.presentStakes(
                            in: group, competition: competition)
                    )
                }
            }
        }
    }

    // Sélecteur de groupes de qualif (grille 3 colonnes, comme la phase de groupes).
    private var qualifierGroupSelector: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(qualifierGroups.enumerated()), id: \.offset) { idx, group in
                Button { qualifierGroupIndex = idx } label: {
                    Text(groupLabel(group.first?.group, index: idx))
                        .font(.caption).fontWeight(qualifierGroupIndex == idx ? .bold : .regular)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(qualifierGroupIndex == idx ? competition.color : Color(.secondarySystemBackground))
                        .foregroundColor(qualifierGroupIndex == idx ? .white : .primary)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
    }

    private var safeQualifierGroupIndex: Int {
        min(max(qualifierGroupIndex, 0), max(qualifierGroups.count - 1, 0))
    }

    // Sélection d'une confédération → charge ses classements de qualif.
    private func selectQualifier(_ q: Qualifier) {
        selectedQualifier = q
        selected = nil
        qualifierGroupIndex = 0
        qualifierGroups = []
        isLoadingQualifier = true
        Task {
            let result = await FootballAPIService.shared
                .fetchQualifierStandings(leagueId: q.leagueId, season: q.season)
            // IMPORTANT : FootballAPIService n'est pas @MainActor, donc on repasse
            // explicitement sur le main thread pour muter l'état SwiftUI et
            // déclencher le rafraîchissement de la vue (sinon l'écran reste vide).
            await MainActor.run {
                qualifierGroups = result
                isLoadingQualifier = false
            }
        }
    }

    // Phase de groupes : on choisit UN groupe (A, B, C…) et on affiche son
    // classement PUIS ses matchs — plutôt que d'empiler tous les groupes.
    private var groupStandingsList: some View {
        Group {
            if groups.isEmpty {
                EmptyStateView(icon: "list.number", text: L("empty.noStandings"))
            } else {
                VStack(spacing: 0) {
                    groupSelector
                    Divider()
                    if groups.indices.contains(safeGroupIndex) {
                        let group = groups[safeGroupIndex]
                        List {
                            // ── Classement du groupe ──
                            SwiftUI.Section {
                                StandingsHeaderView().listRowInsets(EdgeInsets())
                                ForEach(group) { entry in
                                    StandingEntryRow(entry: entry, competition: competition)
                                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                                        .listRowSeparator(.hidden)
                                }
                            }
                            // ── Matchs du groupe ──
                            let ms = groupMatches(for: group)
                            if !ms.isEmpty {
                                SwiftUI.Section {
                                    ForEach(ms) { f in
                                        NavigationLink(destination: MatchDetailView(fixture: f)) {
                                            FixtureRowView(fixture: f, showLeague: false)
                                        }
                                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                                    }
                                } header: {
                                    Text(L("tab.results"))
                                        .font(.caption).fontWeight(.semibold)
                                        .foregroundColor(.secondary).textCase(nil)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .environment(\.defaultMinListRowHeight, 0)

                        // Légende des couleurs d'enjeux (qualif 8es, élimination…).
                        StakesLegendView(
                            stakes: StandingStakeClassifier.presentStakes(
                                in: group, competition: competition)
                        )
                    }
                }
            }
        }
    }

    // Sélecteur des groupes (chips A / B / C…) sur PLUSIEURS lignes.
    // Grille à 3 colonnes → 8 groupes tiennent sur 3 lignes, tous visibles
    // sans scroll horizontal (avant, seuls 4 tenaient sur une ligne).
    private var groupSelector: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(groups.enumerated()), id: \.offset) { idx, group in
                Button { selectedGroupIndex = idx } label: {
                    Text(groupLabel(group.first?.group, index: idx))
                        .font(.caption).fontWeight(selectedGroupIndex == idx ? .bold : .regular)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(selectedGroupIndex == idx ? competition.color : Color(.secondarySystemBackground))
                        .foregroundColor(selectedGroupIndex == idx ? .white : .primary)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
    }

    private var safeGroupIndex: Int {
        min(max(selectedGroupIndex, 0), max(groups.count - 1, 0))
    }

    /// Matchs appartenant à un groupe : ceux dont les DEUX équipes figurent au
    /// classement de ce groupe (fiable même si le `round` ne nomme pas le groupe).
    private func groupMatches(for group: [AFStandingEntry]) -> [AFFixture] {
        let teamIds = Set(group.map { $0.team.id })
        return fixtures
            .filter { Phase.canonical(from: roundName($0)) == .groups }
            .filter { teamIds.contains($0.teams.home.id) && teamIds.contains($0.teams.away.id) }
            .sorted { a, b in
                let fa = isFrenchFixture(a), fb = isFrenchFixture(b)
                if fa != fb { return fa }
                return a.fixture.date < b.fixture.date
            }
    }

    /// Vrai si l'un des deux camps est un club français (selon les IDs chargés).
    private func isFrenchFixture(_ f: AFFixture) -> Bool {
        frenchIds.contains(f.teams.home.id) || frenchIds.contains(f.teams.away.id)
    }

    /// La compétition est-elle une coupe d'Europe de CLUBS (UCL/UEL/UECL) ?
    /// Détermine si les 8es/quarts/demies se jouent en aller-retour. Les
    /// compétitions de sélections (Coupe du monde, Euro, Ligue des Nations)
    /// jouent ces tours en MATCH UNIQUE.
    private var isEuropeanClubCup: Bool { competition.section == .europe }

    // Liste des matchs d'une phase à élimination.
    // • Coupe d'Europe de clubs : 8es→demies en aller-retour (confrontations).
    // • Barrages / tours de qualif : toujours aller-retour.
    // • Coupe du monde / Euro / Nations (phase finale) : MATCH UNIQUE.
    @ViewBuilder
    private func matchList(for phase: Phase) -> some View {
        let ms = fixtures
            .filter { Phase.canonical(from: roundName($0)) == phase.key }
            .sorted { a, b in
                // Clubs français d'abord ; à statut FR égal, ordre chronologique.
                let fa = isFrenchFixture(a), fb = isFrenchFixture(b)
                if fa != fb { return fa }
                return a.fixture.date < b.fixture.date
            }

        if ms.isEmpty {
            EmptyStateView(icon: "calendar", text: L("empty.noMatch"))
        } else if phase.key.isTwoLegged(europeanClubCup: isEuropeanClubCup) {
            twoLeggedList(ms, phase: phase)
        } else {
            List(ms) { f in
                NavigationLink(destination: MatchDetailView(fixture: f)) {
                    FixtureRowView(fixture: f, showLeague: false)
                }
                .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
            }
            .listStyle(.plain)
        }
    }

    /// Affiche un tour aller-retour SOUS FORME DE CONFRONTATIONS : bannière
    /// d'explication puis une carte par duel montrant les deux manches, le score
    /// cumulé et l'équipe qualifiée (dès que les deux manches sont terminées).
    @ViewBuilder
    private func twoLeggedList(_ ms: [AFFixture], phase: Phase) -> some View {
        let ties = EuroTie.build(from: ms, frenchIds: frenchIds)
        ScrollView {
            LazyVStack(spacing: 10) {
                // Bannière explicative en tête.
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(competition.color)
                        .font(.system(size: 14))
                    Text(playoffExplanation(for: phase.key))
                        .font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 4)

                ForEach(ties) { tie in
                    TieCardView(tie: tie, competition: competition)
                        .padding(.horizontal, 10)
                }
            }
            .padding(.top, 6)
            // Marge basse : la dernière confrontation reste visible au-dessus de
            // la barre d'onglets.
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity)
        }
        // Fond de page BLEU CLAIR (bleu franc, pas turquoise) : fait ressortir les
        // cartes BLANCHES qui « flottent » par-dessus. Teinte douce et lumineuse.
        .background(Color(red: 0.90, green: 0.94, blue: 1.0))
    }

    /// Texte d'explication affiché en haut d'un tour à élimination directe.
    private func playoffExplanation(for key: Phase.Key) -> String {
        switch key {
        case .knockoutPlayoff: return L("phase.explain.knockoutPlayoff")
        case .accessPlayoff:   return L("phase.explain.accessPlayoff")
        case .qualifying1, .qualifying2, .qualifying3:
            return L("phase.explain.qualifying")
        default:               return L("phase.explain.twoLegged")
        }
    }

    // ── Chargement ───────────────────────────────────────────────────────────
    private func load() async {
        isLoading = true; errorMessage = nil
        do {
            async let fx = FootballAPIService.shared.fetchAllFixtures(competition: competition)
            // Coupes d'Europe : la PHASE DE GROUPES ne doit afficher QUE la saison
            // courante. En tout début de saison (tours préliminaires), le classement
            // 2026-27 n'existe pas encore → on ne veut PAS retomber sur celui de la
            // saison passée (qui montrerait une phase de groupes déjà jouée alors
            // qu'on n'y est pas). Sans classement courant → « phase pas encore
            // commencée » plutôt qu'un tableau trompeur de l'édition précédente.
            async let gp = FootballAPIService.shared.fetchStandings(
                competition: competition, fallbackToPreviousSeason: false)
            // Charge (une seule fois pour la session) les IDs des clubs FR afin de
            // les prioriser dans les tris de matchs/confrontations.
            await FootballAPIService.shared.ensureFrenchTeamIds()
            frenchIds = FootballAPIService.shared.loadedFrenchTeamIds
            let (loadedFixtures, loadedGroups) = try await (fx, gp)
            fixtures = loadedFixtures
            // Bornes de l'édition (pour le bandeau « dernière édition »).
            let dates = loadedFixtures.compactMap { $0.isoDate }.sorted()
            editionStart = dates.first
            editionEnd = dates.last
            // Écarte les pseudo-groupes fantômes (« Stage », « Group Stage » sans
            // lettre) que l'API renvoie parfois en plus des vraies poules A…L.
            groups = loadedGroups.filter { isRealGroup($0.first?.group) }

            // Construit la liste des phases présentes, en ordre décroissant.
            var present = Set<Phase.Key>()
            for f in loadedFixtures { present.insert(Phase.canonical(from: roundName(f))) }
            // La phase de groupes existe si un classement OU un match de groupe est présent.
            if !loadedGroups.isEmpty { present.insert(.groups) }

            phases = Phase.Key.allCasesDescending
                .filter { present.contains($0) }
                .map { Phase(key: $0) }

            // Sélection par défaut : la phase la plus avancée qui a des matchs joués,
            // sinon la première (la plus haute) de la liste.
            selected = defaultSelection() ?? phases.first
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Choisit la phase la plus « actuelle » : la plus avancée ayant au moins un
    /// match joué ou en cours ; à défaut la plus avancée tout court.
    private func defaultSelection() -> Phase? {
        for phase in phases where !phase.isGroupStage {
            let hasPlayed = fixtures.contains {
                Phase.canonical(from: roundName($0)) == phase.key && ($0.isFinished || $0.isLive)
            }
            if hasPlayed { return phase }
        }
        // Aucun match à élimination joué → on montre la phase de groupes si dispo.
        return phases.first(where: { $0.isGroupStage })
    }

    private func roundName(_ f: AFFixture) -> String {
        f.league.round ?? f.fixture.round ?? ""
    }

    /// Vrai groupe = une fois « Group/Groupe/Stage » retirés, il reste un token
    /// court (une lettre A…L ou un numéro) identifiant une poule. Sinon c'est un
    /// pseudo-groupe (« Stage », « Group Stage ») qu'on ne veut pas afficher.
    private func isRealGroup(_ raw: String?) -> Bool {
        guard let raw = raw, !raw.isEmpty else { return false }
        let cleaned = raw
            .replacingOccurrences(of: "Group Stage", with: "")
            .replacingOccurrences(of: "Stage", with: "")
            .replacingOccurrences(of: "Group", with: "")
            .replacingOccurrences(of: "Groupe", with: "")
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " -:•"))
        return !trimmed.isEmpty
    }

    /// Réutilise la logique de nettoyage de nom de groupe (« Group A » → « Poule A »).
    private func groupLabel(_ raw: String?, index: Int) -> String {
        guard let raw = raw, !raw.isEmpty else { return "\(L("standings.group")) \(index + 1)" }
        let cleaned = raw
            .replacingOccurrences(of: "Group Stage", with: "")
            .replacingOccurrences(of: "Stage", with: "")
            .replacingOccurrences(of: "Group", with: "")
            .replacingOccurrences(of: "Groupe", with: "")
        if let token = cleaned.split(whereSeparator: { " -:•".contains($0) }).last,
           token.count <= 2 {
            return "\(L("standings.group")) \(token)"
        }
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " -:•"))
        return trimmed.isEmpty ? "\(L("standings.group")) \(index + 1)" : trimmed
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// MODÈLE DE PHASE
// ─────────────────────────────────────────────────────────────────────────────
// On mappe les libellés bruts de l'API (« Round of 16 », « Quarter-finals »…)
// vers un ensemble canonique ordonné, pour un menu propre et traduit.
// ═════════════════════════════════════════════════════════════════════════════

struct Phase: Identifiable, Hashable {
    let key: Key
    var id: Key { key }
    var isGroupStage: Bool { key == .groups }
    var displayName: String { L(key.titleKey) }

    /// Ensemble canonique des phases, dans l'ordre d'affichage DÉCROISSANT
    /// (Finale en haut → tours préliminaires en bas).
    ///
    /// La Ligue des Champions (format 2024+) enchaîne, dans l'ordre CHRONOLOGIQUE :
    ///   1er tour qualif → 2e tour qualif → 3e tour qualif → Play-offs d'accès →
    ///   Phase de ligue (8 j.) → Barrages (9e-24e, aller-retour) → 8es → quarts →
    ///   demies → finale.
    /// On expose chaque tour préliminaire séparément pour que ce soit lisible.
    enum Key: String, CaseIterable {
        case final           // Finale
        case thirdPlace      // Match pour la 3e place
        case semi            // Demi-finales
        case quarter         // Quarts de finale
        case round16         // 8es de finale
        case round32         // 16es de finale
        case knockoutPlayoff // Barrages d'accès aux 8es (9e-24e, aller-retour)
        case groups          // Phase de groupes / phase de ligue
        case accessPlayoff   // « Play-offs » d'accès à la phase de ligue
        case qualifying3     // 3e tour de qualification
        case qualifying2     // 2e tour de qualification
        case qualifying1     // 1er tour de qualification

        /// Ordre du haut vers le bas dans le menu (du plus avancé au plus ancien).
        static var allCasesDescending: [Key] {
            [.final, .thirdPlace, .semi, .quarter, .round16, .round32,
             .knockoutPlayoff, .groups,
             .accessPlayoff, .qualifying3, .qualifying2, .qualifying1]
        }

        var titleKey: String {
            switch self {
            case .final:           return "phase.final"
            case .thirdPlace:      return "phase.thirdPlace"
            case .semi:            return "phase.semi"
            case .quarter:         return "phase.quarter"
            case .round16:         return "phase.round16"
            case .round32:         return "phase.round32"
            case .knockoutPlayoff: return "phase.playoff"
            case .groups:          return "phase.groups"
            case .accessPlayoff:   return "phase.accessPlayoff"
            case .qualifying3:     return "phase.qualif3"
            case .qualifying2:     return "phase.qualif2"
            case .qualifying1:     return "phase.qualif1"
            }
        }

        /// Tours TOUJOURS joués en aller-retour, quelle que soit la compétition :
        /// barrages et tours préliminaires de qualification (confrontations à deux
        /// manches dans les qualifs continentales comme dans les coupes de clubs).
        var isAlwaysTwoLegged: Bool {
            switch self {
            case .knockoutPlayoff, .accessPlayoff,
                 .qualifying3, .qualifying2, .qualifying1:
                return true
            default:
                return false
            }
        }

        /// Tours à élimination directe (8es → demies) qui NE sont en aller-retour
        /// QUE dans les coupes d'Europe de clubs (UCL/UEL/UECL). En Coupe du monde,
        /// à l'Euro, en Ligue des Nations (phase finale), etc. → MATCH UNIQUE.
        var isTwoLeggedInClubCups: Bool {
            switch self {
            case .round16, .quarter, .semi:
                return true
            default:
                return false
            }
        }

        /// Décision finale selon la compétition : aller-retour ou match unique.
        /// `europeanClubCup` = la compétition est une coupe d'Europe de clubs.
        func isTwoLegged(europeanClubCup: Bool) -> Bool {
            if isAlwaysTwoLegged { return true }
            return europeanClubCup && isTwoLeggedInClubCups
        }
    }

    /// Convertit un libellé de round brut de l'API en phase canonique.
    /// Libellés UCL observés (saison 2024, via `fixtures/rounds`) :
    ///   « 1st/2nd/3rd Qualifying Round », « Play-offs », « League Stage - 1…8 »,
    ///   « Knockout Round Play-offs », « Round of 16 », « Quarter-finals »,
    ///   « Semi-finals », « Final », « 3rd Place Final ».
    /// ORDRE des tests important : les cas les plus spécifiques d'abord.
    static func canonical(from raw: String) -> Key {
        let s = raw.lowercased()
        if s.contains("3rd place") || s.contains("third place") { return .thirdPlace }
        if s.contains("final") && !s.contains("semi") && !s.contains("quarter") { return .final }
        if s.contains("semi")    { return .semi }
        if s.contains("quarter") { return .quarter }
        if s.contains("round of 16") || s.contains("1/8") || s.contains("last 16") { return .round16 }
        if s.contains("round of 32") || s.contains("1/16") { return .round32 }
        // Tours PRÉLIMINAIRES d'été (avant la phase de ligue). À tester AVANT le
        // « knockout play-offs » et AVANT « play-offs » seul.
        if s.contains("qualifying") || s.contains("qualif") {
            if s.contains("1st") || s.contains("1 ") || s.contains("first")  { return .qualifying1 }
            if s.contains("2nd") || s.contains("second")                     { return .qualifying2 }
            if s.contains("3rd") || s.contains("third")                      { return .qualifying3 }
            return .qualifying1   // « Qualifying Round » sans numéro
        }
        // « Knockout Round Play-offs » = barrages APRÈS la phase de ligue (9e-24e).
        if s.contains("knockout") {
            return .knockoutPlayoff
        }
        // « Play-offs » seul = barrages d'accès À la phase de ligue (été).
        if s.contains("play-off") || s.contains("playoff") {
            return .accessPlayoff
        }
        // Tout le reste (« Group Stage », « League Stage », « Regular Season »,
        // « Preliminary Round »…) est rangé en phase de groupes/ligue.
        return .groups
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// CONFRONTATION ALLER-RETOUR (coupes d'Europe)
// ─────────────────────────────────────────────────────────────────────────────
// Regroupe les deux manches d'un même duel, calcule le score cumulé et détermine
// l'équipe qualifiée (uniquement quand les deux manches sont terminées).
// ═════════════════════════════════════════════════════════════════════════════

struct EuroTie: Identifiable {
    let id: String            // clé stable de la paire d'équipes
    let teamA: AFTeam         // référence = équipe « à domicile » de l'aller
    let teamB: AFTeam
    let leg1: AFFixture?      // aller (1re rencontre chronologique)
    let leg2: AFFixture?      // retour

    /// Buts cumulés de A et de B sur les manches JOUÉES.
    var aggregate: (a: Int, b: Int) {
        var ga = 0, gb = 0
        for f in [leg1, leg2].compactMap({ $0 }) where f.isFinished || f.isLive {
            let h = f.goals.home ?? 0, aw = f.goals.away ?? 0
            if f.teams.home.id == teamA.id { ga += h; gb += aw }
            else { ga += aw; gb += h }
        }
        return (ga, gb)
    }

    /// Confrontation terminée = les deux manches sont jouées (ou une seule manche
    /// terminée pour les rares tours à match unique classés ici).
    var isComplete: Bool {
        let legs = [leg1, leg2].compactMap { $0 }
        guard !legs.isEmpty else { return false }
        return legs.allSatisfy { $0.isFinished }
    }

    /// ID de l'équipe qualifiée, ou nil si indéterminé (manche(s) restante(s) ou
    /// égalité parfaite sans tirs au but exploitables).
    var qualifiedTeamId: Int? {
        guard isComplete else { return nil }
        let agg = aggregate
        if agg.a != agg.b { return agg.a > agg.b ? teamA.id : teamB.id }
        // Égalité au cumulé → départage aux tirs au but de la 2e manche.
        if let pen = leg2?.score?.penalty, let ph = pen.home, let pa = pen.away, ph != pa,
           let secondLeg = leg2 {
            let aIsHome = secondLeg.teams.home.id == teamA.id
            let aPen = aIsHome ? ph : pa
            let bPen = aIsHome ? pa : ph
            return aPen > bPen ? teamA.id : teamB.id
        }
        return nil
    }

    /// Vrai si l'un des deux camps est un club français (selon les IDs fournis).
    func involvesFrench(_ frenchIds: Set<Int>) -> Bool {
        frenchIds.contains(teamA.id) || frenchIds.contains(teamB.id)
    }

    /// Buts marqués par l'équipe `teamId` lors d'une manche donnée, quel que soit
    /// le sens (domicile/extérieur). nil si la manche n'existe pas ou pas encore jouée.
    func goals(for teamId: Int, in leg: AFFixture?) -> Int? {
        guard let f = leg, f.isFinished || f.isLive else { return nil }
        let h = f.goals.home ?? 0, aw = f.goals.away ?? 0
        return f.teams.home.id == teamId ? h : aw
    }

    /// Vrai si `teamId` recevait (jouait à domicile) lors de cette manche.
    func isHome(_ teamId: Int, in leg: AFFixture?) -> Bool {
        leg?.teams.home.id == teamId
    }

    /// Résultat d'une manche pour `teamId` : .win / .draw / .loss, ou nil si non jouée.
    enum LegOutcome { case win, draw, loss }
    func outcome(for teamId: Int, in leg: AFFixture?) -> LegOutcome? {
        let otherId = teamId == teamA.id ? teamB.id : teamA.id
        guard let mine = goals(for: teamId, in: leg),
              let theirs = goals(for: otherId, in: leg) else { return nil }
        if mine > theirs { return .win }
        if mine < theirs { return .loss }
        return .draw
    }

    /// Construit les confrontations à partir des matchs d'un tour. Clé = paire
    /// d'IDs indépendante du sens ; tri des manches par date (aller puis retour).
    /// Les confrontations impliquant un club français (`frenchIds`) sont remontées
    /// en tête ; à statut FR égal, tri chronologique par date de l'aller.
    static func build(from ms: [AFFixture], frenchIds: Set<Int> = []) -> [EuroTie] {
        var byTie: [String: [AFFixture]] = [:]
        for m in ms {
            let a = m.teams.home.id, b = m.teams.away.id
            let key = a < b ? "\(a)-\(b)" : "\(b)-\(a)"
            byTie[key, default: []].append(m)
        }
        var ties: [EuroTie] = []
        for (key, legs) in byTie {
            let sorted = legs.sorted { $0.fixture.date < $1.fixture.date }
            guard let first = sorted.first else { continue }
            let second = sorted.count > 1 ? sorted[1] : nil
            // Référence A/B = équipes de l'aller (home = A) pour un affichage stable.
            ties.append(EuroTie(id: key,
                                teamA: first.teams.home,
                                teamB: first.teams.away,
                                leg1: first,
                                leg2: second))
        }
        // Clubs FR d'abord, puis tri chronologique par date du 1er match.
        return ties.sorted { l, r in
            let fl = l.involvesFrench(frenchIds), fr = r.involvesFrench(frenchIds)
            if fl != fr { return fl }
            return (l.leg1?.isoDate ?? .distantFuture) < (r.leg1?.isoDate ?? .distantFuture)
        }
    }
}

// Carte visuelle d'une confrontation : deux équipes, score de chaque manche,
// score cumulé et coche verte sur le qualifié.
struct TieCardView: View {
    let tie: EuroTie
    let competition: Competition

    private var qualifiedId: Int? { tie.qualifiedTeamId }

    // Géométrie d'une colonne de manche (aller / retour). Le CHIFFRE est centré sur
    // toute la largeur de la colonne, donc parfaitement aligné d'une ligne à l'autre
    // et sous l'intitulé. La maison « domicile » est posée en OVERLAY à gauche : elle
    // flotte par-dessus sans jamais occuper d'espace ni décaler le chiffre.
    private let legColWidth: CGFloat = 34       // largeur totale d'une colonne de manche

    var body: some View {
        VStack(spacing: 6) {
            // En-tête de colonnes : intitulés « Aller » / « Retour » alignés
            // au-dessus des scores. Une petite maison marque le match à domicile.
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                legHeader(L("phase.leg1Short"))
                legHeader(L("phase.leg2Short"))
            }

            // Une ligne par équipe : nom aligné à gauche, ses deux scores à droite,
            // toujours DU POINT DE VUE de l'équipe (donc lisibles en colonne).
            teamRow(team: tie.teamA)
            teamRow(team: tie.teamB)

            // Cumulé mis en avant.
            if !legsPlayed.isEmpty {
                Divider().padding(.vertical, 1)
                HStack(spacing: 6) {
                    Image(systemName: "sum").font(.caption2).foregroundColor(.secondary)
                    Text(L("tie.aggregate")).font(.caption2).foregroundColor(.secondary)
                    Text("\(tie.aggregate.a) - \(tie.aggregate.b)")
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(competition.color)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .background(
            // Carte BLANCHE franche qui « flotte » sur le fond gris de la page.
            // Un liseré fin coloré (couleur de la compétition, très discret) donne
            // la personnalité sans alourdir. L'ombre douce crée le relief.
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(competition.color.opacity(0.15), lineWidth: 1)
        )
    }

    private var legsPlayed: [AFFixture] {
        [tie.leg1, tie.leg2].compactMap { $0 }.filter { $0.isFinished || $0.isLive }
    }

    // Intitulé d'une colonne de manche (Aller / Retour). Centré sur toute la largeur
    // de la colonne, exactement comme le chiffre → l'intitulé tombe pile au-dessus.
    private func legHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2).foregroundColor(.secondary)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(width: legColWidth, alignment: .center)
    }

    // Une ligne équipe : logo + nom (coche verte + fond si qualifiée) suivi de
    // ses scores à l'aller et au retour, alignés dans les colonnes du haut.
    private func teamRow(team: AFTeam) -> some View {
        let isQualified = qualifiedId == team.id
        return HStack(spacing: 8) {
            TeamLogoView(urlString: team.logo, name: team.name, size: 20)
            Text(team.displayName)
                .font(.footnote)
                .fontWeight(isQualified ? .bold : .regular)
                .lineLimit(1)
            if isQualified {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green).font(.caption)
            }
            Spacer(minLength: 4)
            legScoreCell(team: team, leg: tie.leg1)
            legScoreCell(team: team, leg: tie.leg2)
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isQualified ? Color.green.opacity(0.12) : Color.clear)
        )
    }

    // Cellule score cliquable : ouvre le détail du match si la manche existe,
    // sinon reste un simple affichage (tiret). Le NavigationLink enveloppe la
    // cellule pour un accès fluide au détail de chaque rencontre.
    @ViewBuilder
    private func legScoreCell(team: AFTeam, leg: AFFixture?) -> some View {
        if let leg = leg {
            NavigationLink(destination: MatchDetailView(fixture: leg)) {
                legScore(team: team, leg: leg)
            }
            .buttonStyle(.plain)
        } else {
            legScore(team: team, leg: leg)
        }
    }

    // Score d'une équipe sur une manche : chiffre coloré selon le résultat de la
    // manche (vert = gagnée, gris = perdue), avec une petite maison si l'équipe
    // recevait. Un tiret si la manche n'est pas encore jouée.
    @ViewBuilder
    private func legScore(team: AFTeam, leg: AFFixture?) -> some View {
        let value = tie.goals(for: team.id, in: leg)
        let outcome = tie.outcome(for: team.id, in: leg)
        // Le CHIFFRE est centré sur toute la largeur de la colonne → même axe pour
        // toutes les lignes, et pile sous l'intitulé Aller / Retour. La maison est
        // posée en OVERLAY à gauche : elle flotte et n'occupe aucun espace, donc elle
        // n'influence JAMAIS l'alignement des chiffres.
        Group {
            if let value = value {
                Text("\(value)")
                    .font(.subheadline)
                    .fontWeight(outcome == .win ? .bold : .semibold)
                    .foregroundColor(legColor(outcome))
            } else {
                Text("–").font(.subheadline).foregroundColor(Theme.textFaint)
            }
        }
        .frame(width: legColWidth, alignment: .center)
        .overlay(alignment: .leading) {
            if tie.isHome(team.id, in: leg) {
                Image(systemName: "house.fill")
                    .font(.system(size: 7)).foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())   // toute la cellule reste tappable
    }

    private func legColor(_ outcome: EuroTie.LegOutcome?) -> Color {
        switch outcome {
        case .win:  return .green
        case .loss: return Theme.textSoft
        default:    return .primary   // nul ou non joué
        }
    }
}
