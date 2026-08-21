import SwiftUI

/// Écran d'accueil d'une rubrique (France, Étranger, Europe, Nations).
/// Générique : il liste les compétitions du catalogue pour la section donnée.
struct SectionHubView: View {
    let section: AppSection
    /// Quand `false`, le titre de navigation interne est supprimé : utilisé quand
    /// la vue est intégrée dans `CompetitionsHomeView` (qui a son propre titre
    /// « Compétitions » + un sélecteur segmenté qui identifie déjà la rubrique).
    var showsOwnTitle: Bool = true
    /// Quand `true`, le `body` ne wrappe PAS de `NavigationView` (l'écran parent
    /// en fournit déjà une). Évite deux NavigationView imbriquées.
    var embedded: Bool = false
    @State private var selectedContinent: Continent = .europe

    var available: [Competition] { Catalog.available(in: section) }
    var comingSoon: [Competition] { Catalog.competitions(in: section).filter { !$0.isAvailable } }

    /// Championnats affichés pour l'onglet International = ceux du continent sélectionné.
    var foreignForContinent: [Competition] { Catalog.available(in: selectedContinent) }

    var body: some View {
        if embedded {
            // Pas de NavigationStack : le parent en fournit un.
            sectionContent
        } else {
            NavigationStack {
                sectionContent
            }
        }
    }

    /// Contenu de la rubrique (les deux variantes de corps selon la section).
    @ViewBuilder
    private var sectionContent: some View {
        if section == .foreign {
            internationalBody
        } else {
            standardBody
        }
    }

    // ── Onglet International : sélecteur de continent + liste compacte ─────────
    private var internationalBody: some View {
        VStack(spacing: 0) {
            SectionBannerView(section: section)
                .padding(.top, 4)

            // Sélecteur de continent (chips horizontales).
            ContinentPicker(selected: $selectedContinent)

            List {
                ForEach(foreignForContinent) { comp in
                    NavigationLink(destination: destination(for: comp)) {
                        CompetitionRowView(competition: comp, compact: true)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle(showsOwnTitle ? L(section.titleKey) : "")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Bannière de la rubrique. Pour Coupes d'Europe / Sélections nationales, on
    /// force des titres explicites (« Coupes d'Europe » plutôt que « Europe »,
    /// « Sélections nationales » plutôt que « Nations ») tout en gardant le
    /// dégradé/emoji d'origine de la section.
    @ViewBuilder
    private var banner: some View {
        switch section {
        case .europe:
            SectionBannerView(titleKey: "seg.europeanCups",
                              subtitleKey: "section.europe.sub",
                              gradientColors: [Color(red: 0.03, green: 0.10, blue: 0.35),
                                               Color(red: 0.20, green: 0.35, blue: 0.70)],
                              emoji: "🏆")
        case .nations:
            // Même dégradé bleu que Championnats et Coupes d'Europe (choix user
            // 2026-08-13 : bannières uniformes en couleur sur les 3 segments).
            SectionBannerView(titleKey: "seg.nations.full",
                              subtitleKey: "banner.nations.sub",
                              gradientColors: [Color(red: 0.03, green: 0.10, blue: 0.35),
                                               Color(red: 0.20, green: 0.35, blue: 0.70)],
                              emoji: "🌐")
        default:
            SectionBannerView(section: section)
        }
    }

    // ── Onglets standard (France / Europe / Nations) : comportement inchangé ──
    private var standardBody: some View {
        List {
            // Bannière retirée (choix user 2026-08-17) : redondante avec le menu
            // segmenté du haut. La liste des compétitions démarre directement.
            if !available.isEmpty {
                // Pas d'en-tête « Disponible » (jugé superflu par l'utilisateur).
                SwiftUI.Section {
                    ForEach(available) { comp in
                        NavigationLink(destination: destination(for: comp)) {
                            CompetitionRowView(competition: comp)
                        }
                        .modifier(HubCardRow())
                    }
                }
            }

            if !comingSoon.isEmpty {
                SwiftUI.Section(L("hub.comingSoon")) {
                    ForEach(comingSoon) { comp in
                        CompetitionRowView(competition: comp)
                            .opacity(0.55)
                            .modifier(HubCardRow())
                    }
                }
            }

            if available.isEmpty && comingSoon.isEmpty {
                SwiftUI.Section {
                    Text(L("hub.empty"))
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(hubBackground)
        .navigationTitle(showsOwnTitle ? L(section.titleKey) : "")
        .navigationBarTitleDisplayMode(showsOwnTitle ? .large : .inline)
    }

    @ViewBuilder
    func destination(for comp: Competition) -> some View {
        competitionDestination(for: comp)
    }
}

/// Vue de détail pour une compétition, selon son type. Fonction LIBRE (partagée)
/// pour être réutilisée par `SectionHubView` ET `ChampionnatsView`.
@ViewBuilder
func competitionDestination(for comp: Competition) -> some View {
    switch comp.kind {
    case .cup:
        // Coupe à élimination pure (Coupe de France) → vue coupe simple.
        CupDetailView(competition: comp)
    case .mixed:
        // UCL, EURO, CDM, Ligue des Nations… (phase de groupes + phase finale)
        // → vue à phases avec menu latéral (Finale en haut → Groupes en bas).
        PhaseDetailView(competition: comp)
    default:
        // Championnat classique (une ou plusieurs poules) → 4 onglets.
        CompetitionDetailView(competition: comp)
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// VUE « CHAMPIONNATS » — bannière uniforme + menu de zones (France + continents)
// ─────────────────────────────────────────────────────────────────────────────
// Choix user 2026-08-13 (maj) : le segment « Championnats » présente une BANNIÈRE
// uniforme (modèle Coupes d'Europe / Sélections nationales) surmontant un MENU de
// zones sous forme de CHIPS horizontales : France en 1re, puis les continents
// (Europe, Amérique, Asie, Moyen-Orient). On sélectionne UNE zone à la fois et la
// liste dessous ne montre QUE cette zone → changement instantané et fluide (pas
// de gros scroll unique regroupant toutes les sections). La bannière SUIT le
// choix (titre/emoji/dégradé de la zone). Intégrée sans NavigationView (le parent
// `CompetitionsHomeView` en fournit une).
// ═════════════════════════════════════════════════════════════════════════════
struct ChampionnatsView: View {
    /// France par défaut (championnat principal). Repli sur la 1re zone dispo.
    @State private var zone: ChampZone = Catalog.availableChampZones.first ?? .france

    var body: some View {
        // Même structure/format/position que Coupes d'Europe et Sélections :
        // bannière = 1re ligne de la List (inset nul), titre FIXE « Championnats »
        // (ne suit plus la zone). Le menu de zones vient juste sous la bannière.
        List {
            // Bannière retirée (choix user 2026-08-17) : elle faisait doublon avec le
            // menu segmenté du haut (« Championnats »). On garde directement le menu
            // de zones, l'app respire et la liste remonte.
            // Menu de zones (chips horizontales) : France · Europe · … .
            Section {
                HubPromptHeader(messageKey: "hub.prompt.champ")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                ChampZonePicker(selected: $zone)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            // Liste de la seule zone sélectionnée.
            Section {
                ForEach(zone.competitions) { comp in
                    NavigationLink(destination: competitionDestination(for: comp)) {
                        CompetitionRowView(competition: comp, compact: true)
                    }
                    .modifier(HubCardRow())
                }
            }
            // Recharge la liste (et évite les glitches d'animation) au changement.
            .id(zone)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(hubBackground)
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// VUE « COUPES » — menu de familles (Nationales / Europe / Monde) + liste
// ─────────────────────────────────────────────────────────────────────────────
// Choix user 2026-08-17 : le segment « Coupes » (ex « Coupes d'Europe ») présente
// un MENU de familles sous forme de chips, calqué sur « Championnats ». La liste
// dessous ne montre QUE la famille choisie :
//   • Nationales → coupes de chaque pays, regroupées par en-tête de pays
//   • Europe     → UCL / UEL / UECL / Supercoupe UEFA (comportement historique)
//   • Monde      → Libertadores, Sudamericana, Mondial des clubs, CAF, AFC
// Intégrée sans NavigationView (le parent `CompetitionsHomeView` en fournit une).
// ═════════════════════════════════════════════════════════════════════════════
struct CupsView: View {
    /// Europe par défaut : les utilisateurs retrouvent le contenu historique.
    @State private var family: CupFamily = .europe

    var body: some View {
        List {
            // Menu de familles (chips) : Nationales · Europe · Monde.
            Section {
                HubPromptHeader(messageKey: "hub.prompt.cups")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                CupFamilyPicker(selected: $family)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            // Contenu de la seule famille sélectionnée.
            if family == .national {
                // Regroupement par pays (en-tête de section par pays).
                ForEach(Catalog.nationalCupsByCountry, id: \.countryKey) { group in
                    Section(L(group.countryKey)) {
                        ForEach(group.comps) { comp in
                            NavigationLink(destination: competitionDestination(for: comp)) {
                                CompetitionRowView(competition: comp, compact: true)
                            }
                            .modifier(HubCardRow())
                        }
                    }
                }
            } else {
                // Liste plate (Europe / Monde).
                Section {
                    ForEach(family.competitions) { comp in
                        NavigationLink(destination: competitionDestination(for: comp)) {
                            CompetitionRowView(competition: comp, compact: true)
                        }
                        .modifier(HubCardRow())
                    }
                }
            }
        }
        // Recharge la liste (évite les glitches d'animation) au changement de famille.
        .id(family)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(hubBackground)
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// VUE « NATIONS » — menu de zones (Europe / Monde / International) + liste
// ─────────────────────────────────────────────────────────────────────────────
// Choix user 2026-08-17 : le segment « Nations » présente un MENU de zones sous
// forme de chips, calqué sur « Championnats » et « Coupes ». La liste dessous ne
// montre QUE la zone choisie :
//   • International → Coupe du Monde FIFA
//   • Europe        → Ligue des Nations + EURO
//   • Monde         → Gold Cup, Copa América, CAN, Coupe d'Asie
// Les sélections « à venir » (ex. EURO 2028) restent dans une section
// « Prochainement » (non cliquables). Intégrée sans NavigationView (le parent
// `CompetitionsHomeView` en fournit une).
// ═════════════════════════════════════════════════════════════════════════════
struct NationsView: View {
    /// International par défaut : la Coupe du Monde est la plus emblématique.
    @State private var zone: NationZone = Catalog.availableNationZones.first ?? .international

    var body: some View {
        List {
            // Menu de zones (chips) : International · Europe · Monde.
            Section {
                HubPromptHeader(messageKey: "hub.prompt.nations")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                NationZonePicker(selected: $zone)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            // Sélections actives de la zone choisie.
            let available = Catalog.available(inNationZone: zone)
            let comingSoon = Catalog.comingSoon(inNationZone: zone)

            if !available.isEmpty {
                Section {
                    ForEach(available) { comp in
                        NavigationLink(destination: competitionDestination(for: comp)) {
                            CompetitionRowView(competition: comp, compact: true)
                        }
                        .modifier(HubCardRow())
                    }
                }
            }

            if !comingSoon.isEmpty {
                Section(L("hub.comingSoon")) {
                    ForEach(comingSoon) { comp in
                        CompetitionRowView(competition: comp, compact: true)
                            .opacity(0.55)
                            .modifier(HubCardRow())
                    }
                }
            }

            if available.isEmpty && comingSoon.isEmpty {
                Section {
                    Text(L("hub.empty"))
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            }
        }
        // Recharge la liste (évite les glitches d'animation) au changement de zone.
        .id(zone)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(hubBackground)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sélecteur de zone du segment Nations (chips) — calqué sur ChampZonePicker.
// ─────────────────────────────────────────────────────────────────────────────
struct NationZonePicker: View {
    @Binding var selected: NationZone

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Catalog.availableNationZones) { zone in
                let isSel = selected == zone
                Button { selected = zone } label: {
                    // Police + padding réduits (vs les autres pickers) pour que les 3
                    // zones — dont « International », le libellé le plus long — tiennent
                    // sur UNE seule ligne sans passer à la ligne.
                    Text(L(zone.titleKey))
                        .font(.footnote)
                        .fontWeight(isSel ? .semibold : .regular)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .fixedSize()
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundColor(isSel ? Theme.brand : .primary)
                        .background(
                            Capsule()
                                .fill(isSel ? Theme.brandSoft : Color(.secondarySystemBackground))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(isSel ? Theme.brand : Color.clear, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sélecteur de famille du segment Coupes (chips) — calqué sur ChampZonePicker.
// ─────────────────────────────────────────────────────────────────────────────
struct CupFamilyPicker: View {
    @Binding var selected: CupFamily

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Catalog.availableCupFamilies) { family in
                let isSel = selected == family
                Button { selected = family } label: {
                    Text(L(family.titleKey))
                        .font(.subheadline)
                        .fontWeight(isSel ? .semibold : .regular)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .foregroundColor(isSel ? Theme.brand : .primary)
                        .background(
                            Capsule()
                                .fill(isSel ? Theme.brandSoft : Color(.secondarySystemBackground))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(isSel ? Theme.brand : Color.clear, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sélecteur de zone du segment Championnats (chips)
// ─────────────────────────────────────────────────────────────────────────────
// Choix user 2026-08-13 : TOUS les libellés doivent avoir la MÊME taille de texte
// (avant : `minimumScaleFactor` rétrécissait « Moyen-Orient » → tailles inégales).
// On ne tronque JAMAIS et on ne réduit JAMAIS le texte : chaque chip prend sa
// largeur naturelle et les chips passent à la LIGNE SUIVANTE au besoin (2 lignes
// acceptées par l'utilisateur) grâce à un `FlowLayout` maison.
// ─────────────────────────────────────────────────────────────────────────────
// HubPromptHeader — petite phrase d'accroche AU-DESSUS des chips de zone.
// ─────────────────────────────────────────────────────────────────────────────
// Choix user 2026-08-18 : l'en-tête des chips manquait de chaleur. On ajoute une
// ligne conviviale mais classe (icône + phrase) qui invite à choisir la
// compétition pour tout voir. Le texte vient d'une clé localisée (8 langues).
struct HubPromptHeader: View {
    let messageKey: String
    var icon: String = "hand.tap.fill"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.brand)
            Text(L(messageKey))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}

struct ChampZonePicker: View {
    @Binding var selected: ChampZone

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Catalog.availableChampZones) { zone in
                let isSel = selected == zone
                Button { selected = zone } label: {
                    Text(L(zone.titleKey))
                        .font(.subheadline)
                        .fontWeight(isSel ? .semibold : .regular)
                        .lineLimit(1)
                        .fixedSize()                     // taille naturelle, pas de troncature
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .foregroundColor(isSel ? Theme.brand : .primary)
                        .background(
                            Capsule()
                                .fill(isSel ? Theme.brandSoft : Color(.secondarySystemBackground))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(isSel ? Theme.brand : Color.clear, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// FlowLayout — disposition en lignes qui passent à la ligne suivante (wrap)
// ─────────────────────────────────────────────────────────────────────────────
// `Layout` maison (iOS 16+) : place les sous-vues à leur taille naturelle de
// gauche à droite ; quand la largeur restante est insuffisante, on passe à la
// ligne suivante. Aucune sous-vue n'est rétrécie ni tronquée.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6       // écart horizontal entre chips
    var lineSpacing: CGFloat = 6   // écart vertical entre lignes

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var lineWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var lineHeight: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            let needed = (rows[rows.count - 1].isEmpty ? 0 : spacing) + sz.width
            if lineWidth + needed > maxWidth && !rows[rows.count - 1].isEmpty {
                totalHeight += lineHeight + lineSpacing
                rows.append([])
                lineWidth = 0
                lineHeight = 0
            }
            rows[rows.count - 1].append(sz)
            lineWidth += (rows[rows.count - 1].count == 1 ? 0 : spacing) + sz.width
            lineHeight = max(lineHeight, sz.height)
        }
        totalHeight += lineHeight
        return CGSize(width: maxWidth == .infinity ? lineWidth : maxWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        var isFirstInLine = true
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            let needed = (isFirstInLine ? 0 : spacing) + sz.width
            if x - bounds.minX + needed > maxWidth && !isFirstInLine {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
                isFirstInLine = true
            }
            if !isFirstInLine { x += spacing }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                     proposal: ProposedViewSize(sz))
            x += sz.width
            lineHeight = max(lineHeight, sz.height)
            isFirstInLine = false
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// ONGLET « COMPÉTITIONS » — 3 segments sous un seul onglet
// ─────────────────────────────────────────────────────────────────────────────
// Choix user 2026-08-13 : la TabBar passait à 7 onglets (iOS n'en montre que 5
// + « More »). On regroupe tout sous UN onglet, avec un sélecteur segmenté à
// 3 entrées (choix user affiné) :
//   • Championnats     → France (en tête) + continents, dans une liste à sections
//   • Coupes d'Europe  → UCL / UEL / UECL (ancienne rubrique .europe)
//   • Nations          → sélections (EURO / CDM / Ligue des Nations, rubrique .nations)
// Une SEULE NavigationView ici ; les sous-vues sont intégrées sans la leur.
// ═════════════════════════════════════════════════════════════════════════════
struct CompetitionsHomeView: View {

    /// Les 3 segments de l'onglet Compétitions.
    enum Segment: Int, CaseIterable, Identifiable {
        case championnats     // France + tous les continents
        case cups             // Coupes : Nationales / Europe / Monde (choix user 2026-08-17)
        case nations          // Sélections nationales (.nations)

        var id: Int { rawValue }
        var titleKey: String {
            switch self {
            case .championnats: return "seg.championships"
            case .cups:         return "seg.cups"
            case .nations:      return "seg.nations"
            }
        }
    }

    @State private var selection: Segment = .championnats

    /// Namespace pour l'animation de la pilule qui glisse entre les segments.
    @Namespace private var segAnim

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Sélecteur segmenté MODERNE à pilule glissante (remplace le Picker
                // système, jugé fade). Fond arrondi discret + pilule accent animée.
                SlidingSegmentedControl(segments: Segment.allCases,
                                        selection: $selection,
                                        titleKey: { $0.titleKey },
                                        namespace: segAnim)
                    .padding(.horizontal)
                    .padding(.top, 6)
                    .padding(.bottom, 20)

                // Contenu du segment sélectionné (sans NavigationView interne).
                Group {
                    switch selection {
                    case .championnats:
                        ChampionnatsView()
                    case .cups:
                        CupsView()
                    case .nations:
                        NationsView()
                    }
                }
                // Force le remontage à chaque changement de segment.
                .id(selection)
            }
            // Pas de grand titre « Compétitions » en haut (jugé superflu par
            // l'utilisateur) : titre vide + inline → on gagne de la place.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sélecteur segmenté MODERNE — pilule glissante (remplace le Picker système)
// ─────────────────────────────────────────────────────────────────────────────
// Générique : une pilule accent glisse (matchedGeometryEffect) sous l'onglet
// sélectionné, sur un fond arrondi discret. Rendu « premium » et fluide,
// cohérent avec le reste de l'app. Réutilisable pour tout enum de segments.
struct SlidingSegmentedControl<S: Hashable & Identifiable>: View {
    let segments: [S]
    @Binding var selection: S
    let titleKey: (S) -> String
    var namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 4) {
            ForEach(segments) { seg in
                let isSel = seg == selection
                Text(L(titleKey(seg)))
                    .font(.system(size: 14, weight: isSel ? .semibold : .medium,
                                  design: .rounded))
                    .foregroundColor(isSel ? .white : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        ZStack {
                            if isSel {
                                Capsule()
                                    .fill(Theme.brandGradient)
                                    .matchedGeometryEffect(id: "segPill", in: namespace)
                                    .shadow(color: Theme.brand.opacity(0.40),
                                            radius: 6, y: 2)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selection = seg
                        }
                    }
            }
        }
        .padding(4)
        .background(
            Capsule().fill(Color(.secondarySystemBackground))
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sélecteur de continent (chips horizontales)
// ─────────────────────────────────────────────────────────────────────────────
struct ContinentPicker: View {
    @Binding var selected: Continent

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Catalog.availableContinents) { continent in
                    let isSel = selected == continent
                    Button { selected = continent } label: {
                        Text(L(continent.titleKey))
                            .font(.subheadline)
                            .fontWeight(isSel ? .semibold : .regular)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .foregroundColor(isSel ? Theme.brand : .primary)
                            .background(
                                Capsule()
                                    .fill(isSel ? Theme.brandSoft : Color(.secondarySystemBackground))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(isSel ? Theme.brand : Color.clear, lineWidth: 1.5)
                            )
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bannière de rubrique (générique)
// ─────────────────────────────────────────────────────────────────────────────
// Bannière uniforme réutilisée par TOUS les segments (Championnats / Coupes
// d'Europe / Sélections nationales) : titre + sous-titre + dégradé + emoji.
// Deux inits : un init EXPLICITE (clés/couleurs/emoji fournis directement, pour
// des titres personnalisés « Coupes d'Europe » / « Sélections nationales » /
// bannière de zone qui suit le choix) et un init de COMMODITÉ `section:` qui
// dérive tout depuis une `AppSection` (comportement historique).
// ─────────────────────────────────────────────────────────────────────────────
struct SectionBannerView: View {
    let titleKey: String
    let subtitleKey: String
    let gradientColors: [Color]
    let emoji: String

    /// Init explicite : contrôle total sur le contenu de la bannière.
    init(titleKey: String, subtitleKey: String, gradientColors: [Color], emoji: String) {
        self.titleKey = titleKey
        self.subtitleKey = subtitleKey
        self.gradientColors = gradientColors
        self.emoji = emoji
    }

    /// Init de commodité : dérive titre/sous-titre/dégradé/emoji d'une rubrique.
    init(section: AppSection) {
        self.titleKey = section.titleKey
        self.subtitleKey = section.titleKey + ".sub"
        self.emoji = Self.emoji(for: section)
        self.gradientColors = Self.gradientColors(for: section)
    }

    private static func gradientColors(for section: AppSection) -> [Color] {
        switch section {
        case .france:
            return [Color(red: 0.07, green: 0.20, blue: 0.60),
                    Color(red: 0.85, green: 0.10, blue: 0.10)]
        case .foreign:
            return [Color(red: 0.10, green: 0.45, blue: 0.55),
                    Color(red: 0.15, green: 0.25, blue: 0.50)]
        case .europe:
            return [Color(red: 0.03, green: 0.10, blue: 0.35),
                    Color(red: 0.20, green: 0.35, blue: 0.70)]
        case .nations:
            return [Color(red: 0.10, green: 0.40, blue: 0.20),
                    Color(red: 0.55, green: 0.10, blue: 0.10)]
        }
    }

    private static func emoji(for section: AppSection) -> String {
        switch section {
        case .france:  return "🇫🇷"
        case .foreign: return "🌍"
        case .europe:  return "🏆"
        case .nations: return "🌐"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Emoji dans une pastille circulaire translucide → aspect « badge »
            // soigné plutôt qu'un gros emoji nu, et plus compact.
            Text(emoji)
                .font(.system(size: 22))
                .frame(width: 42, height: 42)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(L(titleKey))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(L(subtitleKey))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(
            ZStack {
                // Dégradé diagonal de la rubrique.
                LinearGradient(colors: gradientColors,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // Reflet lumineux doux en haut → touche « premium ».
                LinearGradient(colors: [Color.white.opacity(0.16), Color.clear],
                               startPoint: .top, endPoint: .center)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .shadow(color: gradientColors.first?.opacity(0.35) ?? .clear, radius: 8, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Style « carte » d'une ligne du hub + fond d'écran doux (rendu moderne)
// ─────────────────────────────────────────────────────────────────────────────
// Chaque ligne devient une carte flottante (fond système arrondi, séparateur
// masqué, léger espacement vertical) posée sur un fond dégradé très doux → look
// premium et aéré, plutôt que la liste grise standard.

/// Fond d'écran discret et moderne des hubs de compétitions.
var hubBackground: some View {
    LinearGradient(
        colors: [Color(.systemGroupedBackground),
                 Color(.systemGroupedBackground).opacity(0.6)],
        startPoint: .top, endPoint: .bottom
    )
    .ignoresSafeArea()
}

/// Transforme une ligne de List en « carte » flottante arrondie.
struct HubCardRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .listRowBackground(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 12)
            )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ligne de compétition
// ─────────────────────────────────────────────────────────────────────────────
struct CompetitionRowView: View {
    let competition: Competition
    /// Mode compact : police et espacement resserrés (onglet International)
    /// pour afficher tous les championnats d'un continent sans scroller.
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 10 : 12) {
            // Drapeau retiré de la vignette (showsFlag: false) : il est désormais
            // placé juste avant le nom (choix user 2026-08-17).
            CompetitionArtworkView(competition: competition,
                                   size: compact ? 40 : 52,
                                   showsFlag: false)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    if let flag = competitionFlag {
                        Text(flag)
                            .font(compact ? .subheadline : .headline)
                    }
                    Text(L(competition.nameKey))
                        .font(compact ? .subheadline : .headline)
                        .fontWeight(compact ? .medium : .semibold)
                }
                Text(L(competition.subtitleKey))
                    .font(compact ? .caption2 : .caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Étoile « suivre » retirée des championnats (choix user 2026-08-17).
            // Seul le badge « bientôt disponible » subsiste pour les comps non prêtes.
            if !competition.isAvailable {
                Text(L("badge.soon"))
                    .font(.caption2).fontWeight(.semibold)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, compact ? 2 : 4)
    }

    /// Drapeau émoji du pays, affiché juste avant le nom. `countryCode` contient
    /// déjà l'emoji (ex. 🇫🇷) ; nil si absent (compétitions internationales).
    private var competitionFlag: String? {
        guard let code = competition.countryCode?.trimmingCharacters(in: .whitespaces),
              !code.isEmpty else { return nil }
        return code
    }
}
