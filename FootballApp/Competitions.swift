import Foundation
import SwiftUI

// ═════════════════════════════════════════════════════════════════════════════
// MODÈLE GÉNÉRIQUE DE COMPÉTITION
// ─────────────────────────────────────────────────────────────────────────────
// Toute l'app repose sur cette structure. Pour ajouter une compétition (un pays,
// une coupe d'Europe, un tournoi de sélections…), il suffit d'ajouter une entrée
// dans le catalogue plus bas — aucune autre partie du code n'est à modifier.
// ═════════════════════════════════════════════════════════════════════════════

/// Les 4 grandes rubriques de l'app (= les onglets)
enum AppSection: String, CaseIterable, Identifiable {
    case france        // Championnats français
    case foreign       // Championnats étrangers
    case europe        // Coupes d'Europe des clubs
    case nations       // Sélections nationales

    var id: String { rawValue }

    /// Clé de traduction (voir Localizable) + emoji d'onglet
    var titleKey: String {
        switch self {
        case .france:   return "section.france"
        case .foreign:  return "section.foreign"
        case .europe:   return "section.europe"
        case .nations:  return "section.nations"
        }
    }

    var systemImage: String {
        switch self {
        case .france:   return "flag.fill"
        case .foreign:  return "globe.europe.africa.fill"
        case .europe:   return "star.circle.fill"
        case .nations:  return "person.3.fill"
        }
    }
}

/// Type de compétition — détermine l'affichage (classement ou format coupe)
enum CompetitionKind {
    case league        // Championnat avec classement (une seule poule)
    case leagueGroups  // Championnat à plusieurs poules (N1, N2…)
    case cup           // Coupe à élimination directe / tours
    case mixed         // Phase de groupes + phase finale (Champions League, CDM…)
}

/// Continent — sert à regrouper les championnats de la rubrique « International »
/// en sous-sections (Europe, Amérique, Asie, Moyen-Orient).
/// `order` fixe l'ordre d'affichage des sous-sections.
enum Continent: Int, CaseIterable, Identifiable {
    case europe      = 0
    case america     = 1
    case asia        = 2
    case middleEast  = 3

    var id: Int { rawValue }

    /// Clé de traduction du titre de la sous-section.
    var titleKey: String {
        switch self {
        case .europe:     return "continent.europe"
        case .america:    return "continent.america"
        case .asia:       return "continent.asia"
        case .middleEast: return "continent.middleEast"
        }
    }
}

/// Zone du segment « Championnats » : soit la France (toujours en tête), soit un
/// continent. Sert à la fois au sélecteur (chips horizontales) et à la bannière
/// uniforme qui suit le choix de l'utilisateur. Unifie France + continents pour
/// n'avoir qu'UN seul type de sélection dans `ChampionnatsView`.
enum ChampZone: Identifiable, Hashable {
    case france
    case continent(Continent)
    /// Regroupe TOUS les continents hors Europe (Amérique + Asie + Moyen-Orient)
    /// sous une seule zone « Monde », pour alléger le sélecteur de championnats.
    case world

    /// Continents inclus dans la zone « Monde » (tout sauf l'Europe).
    static let worldContinents: [Continent] = [.america, .asia, .middleEast]

    var id: String {
        switch self {
        case .france:            return "france"
        case .continent(let c):  return "cont_\(c.rawValue)"
        case .world:             return "world"
        }
    }

    /// Clé de traduction du libellé court (chip) et titre de bannière.
    var titleKey: String {
        switch self {
        case .france:            return "section.france"
        case .continent(let c):  return c.titleKey
        case .world:             return "zone.world"
        }
    }

    /// Clé de traduction du sous-titre de bannière.
    var subtitleKey: String {
        switch self {
        case .france:                 return "zone.france.sub"
        case .continent(.europe):     return "zone.europe.sub"
        case .continent(.america):    return "zone.america.sub"
        case .continent(.asia):       return "zone.asia.sub"
        case .continent(.middleEast): return "zone.middleEast.sub"
        case .world:                  return "zone.world.sub"
        }
    }

    /// Emoji affiché dans la bannière.
    var emoji: String {
        switch self {
        case .france:                 return "🇫🇷"
        case .continent(.europe):     return "🇪🇺"
        case .continent(.america):    return "🌎"
        case .continent(.asia):       return "🌏"
        case .continent(.middleEast): return "🕌"
        case .world:                  return "🌍"
        }
    }

    /// Couleurs du dégradé de bannière (par zone, pour un rendu distinct).
    var gradientColors: [Color] {
        switch self {
        case .france:
            return [Color(red: 0.07, green: 0.20, blue: 0.60),
                    Color(red: 0.85, green: 0.10, blue: 0.10)]
        case .continent(.europe):
            return [Color(red: 0.10, green: 0.25, blue: 0.55),
                    Color(red: 0.20, green: 0.45, blue: 0.75)]
        case .continent(.america):
            return [Color(red: 0.10, green: 0.45, blue: 0.35),
                    Color(red: 0.15, green: 0.30, blue: 0.55)]
        case .continent(.asia):
            return [Color(red: 0.60, green: 0.10, blue: 0.20),
                    Color(red: 0.85, green: 0.35, blue: 0.10)]
        case .continent(.middleEast):
            return [Color(red: 0.10, green: 0.40, blue: 0.30),
                    Color(red: 0.35, green: 0.30, blue: 0.10)]
        case .world:
            return [Color(red: 0.12, green: 0.35, blue: 0.45),
                    Color(red: 0.20, green: 0.30, blue: 0.60)]
        }
    }

    /// Les compétitions actives de cette zone (France, un continent, ou « Monde »
    /// = tous les continents hors Europe agrégés dans leur ordre d'affichage).
    var competitions: [Competition] {
        switch self {
        case .france:            return Catalog.availableFrance
        case .continent(let c):  return Catalog.available(in: c)
        case .world:             return Self.worldContinents.flatMap { Catalog.available(in: $0) }
        }
    }
}

/// Sous-familles du segment « Coupes » (choix user 2026-08-17). Fonctionne comme
/// `ChampZone` pour les championnats : un sélecteur à chips (Nationales / Europe /
/// Monde / Internationale), la liste dessous ne montre que la famille choisie.
///   • national      → coupes nationales de chaque pays (Coupe de France, FA Cup…)
///   • europe        → coupes européennes des clubs (UCL / UEL / UECL / Supercoupe)
///   • world         → coupes CONTINENTALES de clubs (Libertadores, Sudamericana,
///                     CAF Champions League, AFC Champions League)
///   • international → coupes MONDIALES de clubs (Mondial des clubs FIFA, Coupe
///                     Intercontinentale FIFA) — ajout demandé user 2026-08-17
/// Volontairement DÉCOUPLÉ de `AppSection` : les checks existants `section == .europe`
/// (PhaseDetailView, stats cumulées, Live) restent réservés aux coupes européennes.
enum CupFamily: Identifiable, Hashable, CaseIterable {
    case national
    case europe
    case world
    case international

    var id: String {
        switch self {
        case .national:      return "national"
        case .europe:        return "europe"
        case .world:         return "world"
        case .international: return "international"
        }
    }

    /// Clé de traduction du libellé de la chip.
    var titleKey: String {
        switch self {
        case .national:      return "cup.national"
        case .europe:        return "cup.europe"
        case .world:         return "cup.world"
        case .international: return "cup.international"
        }
    }

    /// Les compétitions actives de cette famille (dans l'ordre du catalogue).
    var competitions: [Competition] { Catalog.available(inFamily: self) }
}

/// Zone du segment « Nations » (sélections nationales). Calqué sur `ChampZone` et
/// `CupFamily` : un sélecteur à chips (Europe / Monde / International), la liste
/// dessous ne montre que la zone choisie (choix user 2026-08-17).
///   • europe        → Ligue des Nations (UEFA) + EURO
///   • world          → tournois continentaux de sélections hors Europe
///                     (Gold Cup CONCACAF, Copa América, CAN, Coupe d'Asie)
///   • international → Coupe du Monde FIFA
enum NationZone: Identifiable, Hashable, CaseIterable {
    case europe
    case world
    case international

    var id: String {
        switch self {
        case .europe:        return "nat_europe"
        case .world:         return "nat_world"
        case .international: return "nat_international"
        }
    }

    /// Clé de traduction du libellé de la chip.
    var titleKey: String {
        switch self {
        case .europe:        return "nation.europe"
        case .world:         return "nation.world"
        case .international: return "nation.international"
        }
    }

    /// Les sélections actives de cette zone (dans l'ordre du catalogue).
    var competitions: [Competition] { Catalog.available(inNationZone: self) }
}

/// Ancrage du recadrage d'une photo d'ambiance (bannière). Enum simple (Hashable)
/// pour rester conforme à `Competition: Hashable`, converti en `Alignment` SwiftUI.
enum PhotoAnchor: Hashable {
    case top, center, bottom
    var alignment: Alignment {
        switch self {
        case .top:    return .top
        case .center: return .center
        case .bottom: return .bottom
        }
    }
}

/// Une compétition, quelle qu'elle soit
struct Competition: Identifiable, Hashable {
    let id: String            // identifiant interne stable (ex. "fr_ligue1")
    let apiId: Int            // ID API-Football (poule principale si multi-poules)
    let section: AppSection
    let nameKey: String       // clé de traduction du nom
    let shortName: String     // badge court (L1, PL, UCL…)
    let kind: CompetitionKind
    let countryCode: String?  // drapeau émoji du pays (nil pour internationales)
    let tint: RGB             // couleur du badge
    let isAvailable: Bool     // false = « bientôt disponible » (placeholder)
    let subtitleKey: String   // clé de traduction de la description
    var continent: Continent? = nil  // continent (rubrique International) ; nil ailleurs
    /// Championnats à poules dont chaque poule est une ligue DISTINCTE côté API
    /// (ex. National 1 = 3 IDs : 67/68/69). nil = compétition mono-ID classique.
    /// Quand présent, standings/matchs bouclent sur ces IDs et fusionnent les poules.
    var groupApiIds: [Int]? = nil

    /// Sous-famille de coupe (Nationales / Europe / Monde) pour le segment « Coupes ».
    /// nil = la compétition n'apparaît PAS dans l'onglet Coupes (championnat, etc.).
    var cupFamily: CupFamily? = nil

    /// Clé de traduction du PAYS pour le regroupement des coupes nationales
    /// (en-têtes de section « France », « Angleterre »…). nil pour Europe/Monde.
    var cupCountryKey: String? = nil

    /// Zone du segment « Nations » (Europe / Monde / International). nil = la
    /// compétition n'appartient pas à l'onglet Nations (championnat, coupe de clubs…).
    var nationZone: NationZone? = nil

    /// Phases de qualification (CDM par confédération, EURO = UEFA seul).
    /// nil = pas d'onglet Qualifications dans le menu latéral.
    var qualifiers: [Qualifier]? = nil

    /// L'API fournit-elle le classement des buteurs pour cette compétition ?
    /// Défaut true. Mettre à false quand l'API-Football ne couvre pas les stats
    /// joueurs (ex. Ligue 3 : `players/topscorers?league=63` renvoie toujours 0)
    /// → l'onglet « Buteurs » est alors masqué au lieu d'afficher un écran vide.
    var hasScorers: Bool = true

    /// Nom d'un logo EMBARQUÉ dans Assets.xcassets à utiliser EN PRIORITÉ (avant
    /// l'API-Football et TheSportsDB). Sert à afficher le VRAI logo officiel quand
    /// on l'a fourni nous-mêmes (ex. les divisions françaises, dont l'API ne donne
    /// qu'un placeholder générique). nil = on résout le logo à distance comme avant.
    var assetLogo: String? = nil

    /// Nom d'une PHOTO d'ambiance EMBARQUÉE dans Assets.xcassets, affichée en FOND
    /// de la bannière paysage (style « Premier League » avec photo de stade/action)
    /// avec un dégradé de la couleur de la compétition par-dessus pour la lisibilité.
    /// nil = fond dégradé + motif procédural classique (comportement par défaut).
    var assetPhoto: String? = nil

    /// Ancrage vertical/horizontal de la photo d'ambiance dans la bannière quand
    /// `scaledToFill` recadre (chaque photo a un cadrage différent). `.top` montre
    /// le haut (têtes des joueurs), `.center` le milieu, `.bottom` le bas. Réglable
    /// par compétition pour ne jamais couper le sujet. Défaut : centre.
    var photoAnchorRaw: PhotoAnchor = .center
    var photoAnchor: Alignment { photoAnchorRaw.alignment }

    static func == (l: Competition, r: Competition) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// Tous les IDs API à interroger : les poules si définies, sinon l'ID principal.
    var allApiIds: [Int] { groupApiIds ?? [apiId] }

    var color: Color { tint.color }
    var gradient: LinearGradient {
        LinearGradient(colors: [color, color.opacity(0.7)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var isCup: Bool { kind == .cup || kind == .mixed }
    var hasGroups: Bool { kind == .leagueGroups || kind == .mixed }

    /// La compétition doit-elle afficher le trophée vectoriel teinté (et non un
    /// drapeau) ? Vrai pour les compétitions « prestige » Europe / International dont
    /// le `countryCode` est un pictogramme (coupe, médaille, globe) plutôt qu'un
    /// drapeau national. Les championnats nationaux gardent leur drapeau.
    var usesTrophyIcon: Bool {
        guard let code = countryCode else { return true }
        let prestige: Set<String> = ["🏆", "🥈", "🥉", "🌍", "🏅"]
        return prestige.contains(code)
    }
}

/// Petite struct couleur (Codable-friendly, sans dépendre de SwiftUI dans le catalogue)
struct RGB: Hashable {
    let r, g, b: Double
    var color: Color { Color(red: r, green: g, blue: b) }
}

/// Une phase de qualification rattachée à une compétition (CDM/EURO).
/// `leagueId` = ID de la ligue de qualif côté API-Football ; `season` = saison
/// de la campagne de qualif (souvent différente de la phase finale).
struct Qualifier: Identifiable, Hashable {
    let confederation: Confederation
    let leagueId: Int
    let season: Int
    var id: Confederation { confederation }
    var nameKey: String { confederation.nameKey }
    var flag: String { confederation.flag }
}

/// Confédérations continentales (drapeau + clé de traduction).
enum Confederation: String, Hashable {
    case europe, southAmerica, africa, asia, concacaf, oceania

    var nameKey: String {
        switch self {
        case .europe:       return "conf.europe"
        case .southAmerica: return "conf.southAmerica"
        case .africa:       return "conf.africa"
        case .asia:         return "conf.asia"
        case .concacaf:     return "conf.concacaf"
        case .oceania:      return "conf.oceania"
        }
    }
    var flag: String {
        switch self {
        case .europe:       return "🇪🇺"
        case .southAmerica: return "🌎"
        case .africa:       return "🌍"
        case .asia:         return "🌏"
        case .concacaf:     return "🌎"
        case .oceania:      return "🌊"
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// CATALOGUE DES COMPÉTITIONS
// ─────────────────────────────────────────────────────────────────────────────
// C'est LE seul endroit à éditer pour faire évoluer l'app.
// Passez isAvailable à true quand vous branchez réellement une compétition.
// ═════════════════════════════════════════════════════════════════════════════

enum Catalog {

    // ── FRANCE (nomenclature 2026-27) ─────────────────────────────────────────
    static let france: [Competition] = [
        Competition(id: "fr_ligue1",   apiId: 61, section: .france,
                    nameKey: "comp.ligue1", shortName: "L1", kind: .league,
                    countryCode: "🇫🇷", tint: RGB(r: 0.07, g: 0.32, b: 0.60),
                    isAvailable: true, subtitleKey: "comp.ligue1.sub",
                    assetLogo: "Ligue 1", assetPhoto: "Jeu Ligue 1",
                    photoAnchorRaw: .top),
        Competition(id: "fr_ligue2",   apiId: 62, section: .france,
                    nameKey: "comp.ligue2", shortName: "L2", kind: .league,
                    countryCode: "🇫🇷", tint: RGB(r: 0.85, g: 0.55, b: 0.05),
                    isAvailable: true, subtitleKey: "comp.ligue2.sub",
                    assetLogo: "Ligue 2", assetPhoto: "Jeu Ligue 2",
                    photoAnchorRaw: .center),
        Competition(id: "fr_ligue3",   apiId: 63, section: .france,
                    nameKey: "comp.ligue3", shortName: "L3", kind: .league,
                    countryCode: "🇫🇷", tint: RGB(r: 0.15, g: 0.50, b: 0.25),
                    isAvailable: true, subtitleKey: "comp.ligue3.sub",
                    hasScorers: false, assetLogo: "Ligue 3",
                    assetPhoto: "Jeu Ligue 3", photoAnchorRaw: .top),
        // National 1 (4e div. depuis la réforme 2026-27, 3 groupes de 16).
        // ⚠️ Côté API-Football, ces 3 poules sont RÉFÉRENCÉES sous le nom
        //    « National 2 - Group A/B/C » (IDs 67/68/69) : l'API n'a pas suivi
        //    le renommage FFF. On agrège les 3 IDs sous une seule entrée N1.
        //    (L'ancien id 64 = « Feminine Division 1 » → à NE PAS utiliser.)
        Competition(id: "fr_national1", apiId: 67, section: .france,
                    nameKey: "comp.national1", shortName: "N1", kind: .leagueGroups,
                    countryCode: "🇫🇷", tint: RGB(r: 0.40, g: 0.20, b: 0.60),
                    isAvailable: true, subtitleKey: "comp.national1.sub",
                    groupApiIds: [67, 68, 69], hasScorers: false,
                    assetLogo: "National", assetPhoto: "Jeu National",
                    photoAnchorRaw: .top),
        // National 2 (5e div. depuis la réforme) : NON COUVERT par API-Football
        //    en 2026 → indisponible pour l'instant (pas de données fausses).
        //    À rebrancher si une source apparaît (piste : data propriétaire).
        Competition(id: "fr_national2", apiId: 0, section: .france,
                    nameKey: "comp.national2", shortName: "N2", kind: .leagueGroups,
                    countryCode: "🇫🇷", tint: RGB(r: 0.60, g: 0.15, b: 0.15),
                    isAvailable: false, subtitleKey: "comp.national2.sub"),
        // Trophée des Champions : finale sèche champion L1 vs vainqueur CdF.
        Competition(id: "fr_trophee", apiId: 526, section: .france,
                    nameKey: "comp.tropheeChampions", shortName: "TdC", kind: .cup,
                    countryCode: "🇫🇷", tint: RGB(r: 0.10, g: 0.20, b: 0.55),
                    isAvailable: true, subtitleKey: "comp.tropheeChampions.sub",
                    cupFamily: .national, cupCountryKey: "section.france"),
        Competition(id: "fr_coupe",    apiId: 66, section: .france,
                    nameKey: "comp.coupeFrance", shortName: "CdF", kind: .cup,
                    countryCode: "🇫🇷", tint: RGB(r: 0.80, g: 0.10, b: 0.10),
                    isAvailable: true, subtitleKey: "comp.coupeFrance.sub",
                    cupFamily: .national, cupCountryKey: "section.france"),
        // Arkema Première Ligue : 1re division féminine française (API id 64,
        //    libellé brut « Feminine Division 1 » → on affiche notre nom propre).
        Competition(id: "fr_feminine", apiId: 64, section: .france,
                    nameKey: "comp.feminine", shortName: "APL", kind: .league,
                    countryCode: "🇫🇷", tint: RGB(r: 0.75, g: 0.10, b: 0.45),
                    isAvailable: true, subtitleKey: "comp.feminine.sub"),
    ]

    // ── INTERNATIONAL (championnats étrangers, regroupés par continent) ───────
    static let foreign: [Competition] = [
        // ── Europe ────────────────────────────────────────────────────────────
        Competition(id: "eng_pl",  apiId: 39, section: .foreign,
                    nameKey: "comp.premierLeague", shortName: "PL", kind: .league,
                    countryCode: "🏴󠁧󠁢󠁥󠁮󠁧󠁿", tint: RGB(r: 0.23, g: 0.05, b: 0.38),
                    isAvailable: true, subtitleKey: "comp.premierLeague.sub",
                    continent: .europe),
        Competition(id: "esp_liga", apiId: 140, section: .foreign,
                    nameKey: "comp.laLiga", shortName: "Liga", kind: .league,
                    countryCode: "🇪🇸", tint: RGB(r: 0.90, g: 0.15, b: 0.20),
                    isAvailable: true, subtitleKey: "comp.laLiga.sub",
                    continent: .europe),
        Competition(id: "ita_seriea", apiId: 135, section: .foreign,
                    nameKey: "comp.serieA", shortName: "SA", kind: .league,
                    countryCode: "🇮🇹", tint: RGB(r: 0.05, g: 0.30, b: 0.65),
                    isAvailable: true, subtitleKey: "comp.serieA.sub",
                    continent: .europe),
        Competition(id: "ger_bundesliga", apiId: 78, section: .foreign,
                    nameKey: "comp.bundesliga", shortName: "BL", kind: .league,
                    countryCode: "🇩🇪", tint: RGB(r: 0.85, g: 0.10, b: 0.10),
                    isAvailable: true, subtitleKey: "comp.bundesliga.sub",
                    continent: .europe),
        Competition(id: "por_liga", apiId: 94, section: .foreign,
                    nameKey: "comp.primeiraLiga", shortName: "PT", kind: .league,
                    countryCode: "🇵🇹", tint: RGB(r: 0.10, g: 0.45, b: 0.25),
                    isAvailable: true, subtitleKey: "comp.primeiraLiga.sub",
                    continent: .europe),
        Competition(id: "ned_eredivisie", apiId: 88, section: .foreign,
                    nameKey: "comp.eredivisie", shortName: "NL", kind: .league,
                    countryCode: "🇳🇱", tint: RGB(r: 0.90, g: 0.40, b: 0.05),
                    isAvailable: true, subtitleKey: "comp.eredivisie.sub",
                    continent: .europe),
        Competition(id: "sui_superleague", apiId: 207, section: .foreign,
                    nameKey: "comp.swissSuperLeague", shortName: "SUI", kind: .league,
                    countryCode: "🇨🇭", tint: RGB(r: 0.85, g: 0.12, b: 0.15),
                    isAvailable: true, subtitleKey: "comp.swissSuperLeague.sub",
                    continent: .europe),
        Competition(id: "tur_superlig", apiId: 203, section: .foreign,
                    nameKey: "comp.superLig", shortName: "TUR", kind: .league,
                    countryCode: "🇹🇷", tint: RGB(r: 0.85, g: 0.10, b: 0.15),
                    isAvailable: true, subtitleKey: "comp.superLig.sub",
                    continent: .europe),

        // ── Amérique (saison en année civile — voir season(for:)) ─────────────
        Competition(id: "usa_mls", apiId: 253, section: .foreign,
                    nameKey: "comp.mls", shortName: "MLS", kind: .league,
                    countryCode: "🇺🇸", tint: RGB(r: 0.02, g: 0.15, b: 0.40),
                    isAvailable: true, subtitleKey: "comp.mls.sub",
                    continent: .america),
        Competition(id: "bra_seriea", apiId: 71, section: .foreign,
                    nameKey: "comp.brasileirao", shortName: "BRA", kind: .league,
                    countryCode: "🇧🇷", tint: RGB(r: 0.10, g: 0.55, b: 0.25),
                    isAvailable: true, subtitleKey: "comp.brasileirao.sub",
                    continent: .america),
        Competition(id: "mex_ligamx", apiId: 262, section: .foreign,
                    nameKey: "comp.ligaMX", shortName: "MX", kind: .league,
                    countryCode: "🇲🇽", tint: RGB(r: 0.05, g: 0.45, b: 0.25),
                    isAvailable: true, subtitleKey: "comp.ligaMX.sub",
                    continent: .america),
        Competition(id: "arg_primera", apiId: 128, section: .foreign,
                    nameKey: "comp.ligaArgentina", shortName: "ARG", kind: .league,
                    countryCode: "🇦🇷", tint: RGB(r: 0.40, g: 0.68, b: 0.85),
                    isAvailable: true, subtitleKey: "comp.ligaArgentina.sub",
                    continent: .america),

        // ── Asie ──────────────────────────────────────────────────────────────
        Competition(id: "jpn_j1", apiId: 98, section: .foreign,
                    nameKey: "comp.j1League", shortName: "J1", kind: .league,
                    countryCode: "🇯🇵", tint: RGB(r: 0.80, g: 0.10, b: 0.20),
                    isAvailable: true, subtitleKey: "comp.j1League.sub",
                    continent: .asia),

        // ── Moyen-Orient ──────────────────────────────────────────────────────
        Competition(id: "sau_proleague", apiId: 307, section: .foreign,
                    nameKey: "comp.saudiProLeague", shortName: "SAU", kind: .league,
                    countryCode: "🇸🇦", tint: RGB(r: 0.05, g: 0.45, b: 0.20),
                    isAvailable: true, subtitleKey: "comp.saudiProLeague.sub",
                    continent: .middleEast),

    ]

    // ── EUROPE (coupes des clubs — placeholders prêts) ────────────────────────
    static let europe: [Competition] = [
        Competition(id: "eu_ucl", apiId: 2, section: .europe,
                    nameKey: "comp.ucl", shortName: "UCL", kind: .mixed,
                    countryCode: "🏆", tint: RGB(r: 0.03, g: 0.10, b: 0.35),
                    isAvailable: true, subtitleKey: "comp.ucl.sub",
                    cupFamily: .europe),
        Competition(id: "eu_uel", apiId: 3, section: .europe,
                    nameKey: "comp.uel", shortName: "UEL", kind: .mixed,
                    countryCode: "🥈", tint: RGB(r: 0.90, g: 0.45, b: 0.05),
                    isAvailable: true, subtitleKey: "comp.uel.sub",
                    cupFamily: .europe),
        Competition(id: "eu_uecl", apiId: 848, section: .europe,
                    nameKey: "comp.uecl", shortName: "UECL", kind: .mixed,
                    countryCode: "🥉", tint: RGB(r: 0.10, g: 0.55, b: 0.35),
                    isAvailable: true, subtitleKey: "comp.uecl.sub",
                    cupFamily: .europe),
        // Supercoupe de l'UEFA (id API-Football 531) : match unique vainqueur UCL
        // vs vainqueur UEL. Ajout demandé (user 2026-08-16) : c'est la seule autre
        // coupe d'Europe des clubs officielle couverte par l'API.
        Competition(id: "eu_supercup", apiId: 531, section: .europe,
                    nameKey: "comp.uefaSuperCup", shortName: "SUC", kind: .mixed,
                    countryCode: "🇪🇺", tint: RGB(r: 0.20, g: 0.15, b: 0.45),
                    isAvailable: true, subtitleKey: "comp.uefaSuperCup.sub",
                    cupFamily: .europe),
    ]

    // ── COUPES NATIONALES ÉTRANGÈRES (segment Coupes › Nationales) ─────────────
    // Section .foreign par commodité (continent = nil → jamais dans les listes de
    // championnats par continent, qui filtrent sur continent != nil et kind league).
    // Chaque coupe porte cupFamily = .national et sa clé de pays pour le regroupement.
    static let nationalCupsForeign: [Competition] = [
        // ── Angleterre ──────────────────────────────────────────────────────────
        Competition(id: "eng_facup", apiId: 45, section: .foreign,
                    nameKey: "comp.faCup", shortName: "FA", kind: .cup,
                    countryCode: "🏴󠁧󠁢󠁥󠁮󠁧󠁿", tint: RGB(r: 0.10, g: 0.20, b: 0.55),
                    isAvailable: true, subtitleKey: "comp.faCup.sub",
                    cupFamily: .national, cupCountryKey: "country.england"),
        Competition(id: "eng_efl", apiId: 48, section: .foreign,
                    nameKey: "comp.carabaoCup", shortName: "EFL", kind: .cup,
                    countryCode: "🏴󠁧󠁢󠁥󠁮󠁧󠁿", tint: RGB(r: 0.10, g: 0.35, b: 0.65),
                    isAvailable: true, subtitleKey: "comp.carabaoCup.sub",
                    cupFamily: .national, cupCountryKey: "country.england"),
        Competition(id: "eng_shield", apiId: 528, section: .foreign,
                    nameKey: "comp.communityShield", shortName: "CS", kind: .cup,
                    countryCode: "🏴󠁧󠁢󠁥󠁮󠁧󠁿", tint: RGB(r: 0.35, g: 0.10, b: 0.45),
                    isAvailable: true, subtitleKey: "comp.communityShield.sub",
                    cupFamily: .national, cupCountryKey: "country.england", hasScorers: false),
        // ── Espagne ─────────────────────────────────────────────────────────────
        Competition(id: "esp_copa", apiId: 143, section: .foreign,
                    nameKey: "comp.copaDelRey", shortName: "CDR", kind: .cup,
                    countryCode: "🇪🇸", tint: RGB(r: 0.85, g: 0.15, b: 0.15),
                    isAvailable: true, subtitleKey: "comp.copaDelRey.sub",
                    cupFamily: .national, cupCountryKey: "country.spain"),
        Competition(id: "esp_supercopa", apiId: 556, section: .foreign,
                    nameKey: "comp.supercopaEspana", shortName: "SEsp", kind: .cup,
                    countryCode: "🇪🇸", tint: RGB(r: 0.90, g: 0.55, b: 0.10),
                    isAvailable: true, subtitleKey: "comp.supercopaEspana.sub",
                    cupFamily: .national, cupCountryKey: "country.spain", hasScorers: false),
        // ── Italie ──────────────────────────────────────────────────────────────
        Competition(id: "ita_coppa", apiId: 137, section: .foreign,
                    nameKey: "comp.coppaItalia", shortName: "CI", kind: .cup,
                    countryCode: "🇮🇹", tint: RGB(r: 0.05, g: 0.30, b: 0.65),
                    isAvailable: true, subtitleKey: "comp.coppaItalia.sub",
                    cupFamily: .national, cupCountryKey: "country.italy"),
        Competition(id: "ita_supercoppa", apiId: 547, section: .foreign,
                    nameKey: "comp.supercoppaItaliana", shortName: "SIt", kind: .cup,
                    countryCode: "🇮🇹", tint: RGB(r: 0.10, g: 0.45, b: 0.75),
                    isAvailable: true, subtitleKey: "comp.supercoppaItaliana.sub",
                    cupFamily: .national, cupCountryKey: "country.italy", hasScorers: false),
        // ── Allemagne ───────────────────────────────────────────────────────────
        Competition(id: "ger_pokal", apiId: 81, section: .foreign,
                    nameKey: "comp.dfbPokal", shortName: "DFB", kind: .cup,
                    countryCode: "🇩🇪", tint: RGB(r: 0.80, g: 0.10, b: 0.10),
                    isAvailable: true, subtitleKey: "comp.dfbPokal.sub",
                    cupFamily: .national, cupCountryKey: "country.germany"),
        Competition(id: "ger_supercup", apiId: 529, section: .foreign,
                    nameKey: "comp.dflSupercup", shortName: "DFL", kind: .cup,
                    countryCode: "🇩🇪", tint: RGB(r: 0.20, g: 0.20, b: 0.20),
                    isAvailable: true, subtitleKey: "comp.dflSupercup.sub",
                    cupFamily: .national, cupCountryKey: "country.germany", hasScorers: false),
        // ── Portugal ────────────────────────────────────────────────────────────
        Competition(id: "por_taca", apiId: 96, section: .foreign,
                    nameKey: "comp.tacaPortugal", shortName: "TP", kind: .cup,
                    countryCode: "🇵🇹", tint: RGB(r: 0.10, g: 0.45, b: 0.25),
                    isAvailable: true, subtitleKey: "comp.tacaPortugal.sub",
                    cupFamily: .national, cupCountryKey: "country.portugal"),
        Competition(id: "por_supertaca", apiId: 550, section: .foreign,
                    nameKey: "comp.supertacaPortugal", shortName: "STP", kind: .cup,
                    countryCode: "🇵🇹", tint: RGB(r: 0.15, g: 0.55, b: 0.30),
                    isAvailable: true, subtitleKey: "comp.supertacaPortugal.sub",
                    cupFamily: .national, cupCountryKey: "country.portugal", hasScorers: false),
        // ── Suisse ──────────────────────────────────────────────────────────────
        Competition(id: "sui_cup", apiId: 209, section: .foreign,
                    nameKey: "comp.schweizerCup", shortName: "SC", kind: .cup,
                    countryCode: "🇨🇭", tint: RGB(r: 0.85, g: 0.12, b: 0.15),
                    isAvailable: true, subtitleKey: "comp.schweizerCup.sub",
                    cupFamily: .national, cupCountryKey: "country.switzerland"),
    ]

    // ── COUPES CONTINENTALES DE CLUBS (segment Coupes › Monde) ─────────────────
    // Coupes de clubs continentales : phase de groupes + phase finale → .mixed.
    // countryCode = pictogramme prestige (globe/trophée) → icône trophée (pas de drapeau).
    static let worldCups: [Competition] = [
        Competition(id: "world_libertadores", apiId: 13, section: .foreign,
                    nameKey: "comp.libertadores", shortName: "LIB", kind: .mixed,
                    countryCode: "🌎", tint: RGB(r: 0.05, g: 0.35, b: 0.65),
                    isAvailable: true, subtitleKey: "comp.libertadores.sub",
                    cupFamily: .world),
        Competition(id: "world_sudamericana", apiId: 11, section: .foreign,
                    nameKey: "comp.sudamericana", shortName: "SUD", kind: .mixed,
                    countryCode: "🌎", tint: RGB(r: 0.85, g: 0.45, b: 0.05),
                    isAvailable: true, subtitleKey: "comp.sudamericana.sub",
                    cupFamily: .world),
        Competition(id: "world_cafcl", apiId: 12, section: .foreign,
                    nameKey: "comp.cafChampionsLeague", shortName: "CAF", kind: .mixed,
                    countryCode: "🌍", tint: RGB(r: 0.10, g: 0.50, b: 0.30),
                    isAvailable: true, subtitleKey: "comp.cafChampionsLeague.sub",
                    cupFamily: .world),
        Competition(id: "world_afccl", apiId: 17, section: .foreign,
                    nameKey: "comp.afcChampionsLeague", shortName: "AFC", kind: .mixed,
                    countryCode: "🌏", tint: RGB(r: 0.60, g: 0.10, b: 0.20),
                    isAvailable: true, subtitleKey: "comp.afcChampionsLeague.sub",
                    cupFamily: .world),
    ]

    // ── COUPES INTERNATIONALES DE CLUBS (segment Coupes › Internationale) ──────
    // Ajout demandé (user 2026-08-17) : les deux trophées MONDIAUX de clubs FIFA.
    //   • Coupe du Monde des Clubs FIFA (id 15) — couverte par l'API-Football.
    //   • Coupe Intercontinentale FIFA — nouvelle compétition (1re édition déc. 2024).
    //     L'ID API-Football n'étant pas confirmé de façon fiable, on la laisse en
    //     « Prochainement » (isAvailable=false) pour éviter un écran vide ; il
    //     suffira de passer isAvailable=true + le bon apiId une fois vérifié.
    static let internationalCups: [Competition] = [
        Competition(id: "intl_clubwc", apiId: 15, section: .foreign,
                    nameKey: "comp.clubWorldCup", shortName: "CWC", kind: .mixed,
                    countryCode: "🏆", tint: RGB(r: 0.10, g: 0.20, b: 0.50),
                    isAvailable: true, subtitleKey: "comp.clubWorldCup.sub",
                    cupFamily: .international),
        Competition(id: "intl_intercontinental", apiId: 0, section: .foreign,
                    nameKey: "comp.intercontinental", shortName: "IC", kind: .mixed,
                    countryCode: "🏆", tint: RGB(r: 0.55, g: 0.35, b: 0.05),
                    isAvailable: false, subtitleKey: "comp.intercontinental.sub",
                    cupFamily: .international),
    ]

    // ── NATIONS (sélections) — 3 zones : International / Europe / Monde ────────
    // Choix user 2026-08-17 : l'onglet Nations présente 3 sous-menus à chips
    //   • International → Coupe du Monde FIFA
    //   • Europe        → Ligue des Nations (UEFA) + EURO
    //   • Monde         → tournois continentaux hors Europe (Gold Cup, Copa
    //                     América, CAN, Coupe d'Asie)
    // L'EURO reste isAvailable=false (API-Football n'a pas encore la prochaine
    // édition) → il apparaît dans « Prochainement », non cliquable.
    static let nations: [Competition] = [
        // ── International : Coupe du Monde FIFA ────────────────────────────────
        Competition(id: "nat_worldcup", apiId: 1, section: .nations,
                    nameKey: "comp.worldCup", shortName: "CDM", kind: .mixed,
                    countryCode: "🌍", tint: RGB(r: 0.70, g: 0.10, b: 0.10),
                    isAvailable: true, subtitleKey: "comp.worldCup.sub",
                    nationZone: .international, assetLogo: "Fifa World Cup"),

        // ── Europe : Ligue des Nations + EURO ─────────────────────────────────
        Competition(id: "nat_nationsleague", apiId: 5, section: .nations,
                    nameKey: "comp.nationsLeague", shortName: "UNL", kind: .mixed,
                    countryCode: "🇪🇺", tint: RGB(r: 0.15, g: 0.20, b: 0.55),
                    isAvailable: true, subtitleKey: "comp.nationsLeague.sub",
                    nationZone: .europe),
        Competition(id: "nat_euro", apiId: 4, section: .nations,
                    nameKey: "comp.euro", shortName: "EURO", kind: .mixed,
                    countryCode: "🇪🇺", tint: RGB(r: 0.10, g: 0.40, b: 0.20),
                    isAvailable: false, subtitleKey: "comp.euro.sub",
                    nationZone: .europe),

        // ── Monde : tournois continentaux de sélections hors Europe ───────────
        // IDs API-Football v3 : Gold Cup CONCACAF=22, Copa América=9, CAN=6,
        // Coupe d'Asie AFC=7. Éditions non annuelles : les données peuvent être
        // vides hors tournoi → repli de saison géré par seasonsToTry côté API.
        Competition(id: "nat_goldcup", apiId: 22, section: .nations,
                    nameKey: "comp.goldCup", shortName: "GC", kind: .mixed,
                    countryCode: "🌎", tint: RGB(r: 0.05, g: 0.35, b: 0.60),
                    isAvailable: true, subtitleKey: "comp.goldCup.sub",
                    nationZone: .world),
        Competition(id: "nat_copaamerica", apiId: 9, section: .nations,
                    nameKey: "comp.copaAmerica", shortName: "CA", kind: .mixed,
                    countryCode: "🌎", tint: RGB(r: 0.10, g: 0.45, b: 0.30),
                    isAvailable: true, subtitleKey: "comp.copaAmerica.sub",
                    nationZone: .world),
        Competition(id: "nat_afcon", apiId: 6, section: .nations,
                    nameKey: "comp.afcon", shortName: "CAN", kind: .mixed,
                    countryCode: "🌍", tint: RGB(r: 0.10, g: 0.50, b: 0.25),
                    isAvailable: true, subtitleKey: "comp.afcon.sub",
                    nationZone: .world),
        Competition(id: "nat_asiancup", apiId: 7, section: .nations,
                    nameKey: "comp.asianCup", shortName: "AC", kind: .mixed,
                    countryCode: "🌏", tint: RGB(r: 0.60, g: 0.10, b: 0.20),
                    isAvailable: true, subtitleKey: "comp.asianCup.sub",
                    nationZone: .world),
    ]

    /// Toutes les compétitions
    static var all: [Competition] {
        france + foreign + nationalCupsForeign + worldCups + internationalCups + europe + nations
    }

    /// Compétitions actives d'une famille de coupe (Nationales / Europe / Monde /
    /// Internationale), dans l'ordre du catalogue. Alimente le segment « Coupes ».
    static func available(inFamily family: CupFamily) -> [Competition] {
        all.filter { $0.isAvailable && $0.cupFamily == family }
    }

    /// Sélections actives d'une zone Nations (Europe / Monde / International),
    /// dans l'ordre du catalogue. Alimente le segment « Nations ».
    static func available(inNationZone zone: NationZone) -> [Competition] {
        nations.filter { $0.isAvailable && $0.nationZone == zone }
    }

    /// Sélections INACTIVES (« Prochainement ») d'une zone Nations donnée.
    static func comingSoon(inNationZone zone: NationZone) -> [Competition] {
        nations.filter { !$0.isAvailable && $0.nationZone == zone }
    }

    /// Zones Nations ayant au moins une compétition (active ou à venir), dans
    /// l'ordre : International → Europe → Monde. Masque les zones vides.
    static var availableNationZones: [NationZone] {
        let order: [NationZone] = [.international, .europe, .world]
        return order.filter { z in
            nations.contains { $0.nationZone == z }
        }
    }

    /// Familles de coupes ayant au moins une compétition active, dans l'ordre :
    /// Nationales → Europe → Monde → Internationale. Masque les familles vides.
    static var availableCupFamilies: [CupFamily] {
        let order: [CupFamily] = [.national, .europe, .world, .international]
        return order.filter { !available(inFamily: $0).isEmpty }
    }

    /// Coupes nationales actives, regroupées par PAYS (en-têtes de section), dans
    /// l'ordre : France → Angleterre → Espagne → Italie → Allemagne → Portugal →
    /// Suisse. Chaque entrée = (clé de traduction du pays, coupes de ce pays).
    static var nationalCupsByCountry: [(countryKey: String, comps: [Competition])] {
        let order = ["section.france", "country.england", "country.spain",
                     "country.italy", "country.germany", "country.portugal",
                     "country.switzerland"]
        let comps = available(inFamily: .national)
        return order.compactMap { key in
            let group = comps.filter { $0.cupCountryKey == key }
            return group.isEmpty ? nil : (key, group)
        }
    }

    /// Rang d'IMPORTANCE d'une compétition (par leagueId API). Plus le rang est
    /// petit, plus la compétition passe en premier dans les listes triées (ex. Live).
    /// L'ordre suit `all` : France (Ligue 1 → Ligue 2 → Ligue 3 → National → Coupe…),
    /// puis étranger, Europe, sélections. Les compétitions hors catalogue vont en fin.
    static func rank(forLeagueId leagueId: Int) -> Int {
        if let idx = all.firstIndex(where: { $0.allApiIds.contains(leagueId) }) {
            return idx
        }
        return Int.max
    }

    /// Compétitions d'une rubrique donnée
    static func competitions(in section: AppSection) -> [Competition] {
        switch section {
        case .france:  return france
        case .foreign: return foreign
        case .europe:  return europe
        case .nations: return nations
        }
    }

    /// Compétitions actives (branchées) d'une rubrique
    static func available(in section: AppSection) -> [Competition] {
        competitions(in: section).filter { $0.isAvailable }
    }

    /// Compétitions actives d'un continent (rubrique International).
    static func available(in continent: Continent) -> [Competition] {
        foreign.filter { $0.isAvailable && $0.continent == continent }
    }

    /// Continents ayant au moins une compétition active, dans l'ordre d'affichage.
    static var availableContinents: [Continent] {
        Continent.allCases.filter { !available(in: $0).isEmpty }
    }

    /// Tous les IDs API des compétitions actives (pour le live global).
    /// Inclut chaque poule des championnats multi-IDs (National 1 = 67/68/69).
    static var availableApiIds: [Int] {
        all.filter { $0.isAvailable }.flatMap { $0.allApiIds }
    }

    /// Retrouve la compétition (du catalogue) à laquelle appartient un leagueId
    /// API donné — gère les championnats multi-poules (National 1 = 67/68/69).
    static func competition(forLeagueId leagueId: Int) -> Competition? {
        all.first { $0.allApiIds.contains(leagueId) }
    }

    /// IDs API des championnats FRANÇAIS actifs (section France) — pour repérer
    /// les clubs français en Coupe d'Europe (charge leurs effectifs) et prioriser.
    static var frenchLeagueApiIds: [Int] {
        available(in: .france)
            .filter { $0.kind == .league || $0.kind == .leagueGroups }
            .flatMap { $0.allApiIds }
    }

    /// Championnats français actifs (section France) — pour la vue « Championnats »
    /// groupée qui met la France en 1re section, avant les continents. Les COUPES
    /// (Coupe de France, Trophée des Champions) sont EXCLUES ici depuis 2026-08-17 :
    /// elles ont désormais leur place dédiée sous le segment « Coupes › Nationales ».
    static var availableFrance: [Competition] {
        available(in: .france).filter { $0.kind != .cup }
    }

    /// Zones du segment « Championnats », dans l'ordre : France (si elle a des
    /// compétitions actives) puis chaque continent non vide. Sert au sélecteur
    /// à chips de `ChampionnatsView` (masque automatiquement les zones vides).
    static var availableChampZones: [ChampZone] {
        var zones: [ChampZone] = []
        if !availableFrance.isEmpty { zones.append(.france) }
        // Europe garde sa propre chip (si active).
        // `Continent.europe` explicite : `available(in:)` existe aussi pour
        // AppSection (qui a aussi un cas .europe) → sans ça, usage ambigu.
        if !available(in: Continent.europe).isEmpty { zones.append(.continent(.europe)) }
        // Amérique + Asie + Moyen-Orient regroupés sous une seule chip « Monde ».
        let worldHasComps = ChampZone.worldContinents.contains { !available(in: $0).isEmpty }
        if worldHasComps { zones.append(.world) }
        return zones
    }
}
