import SwiftUI

// ═════════════════════════════════════════════════════════════════════════════
// ENJEUX DE CLASSEMENT — codes couleur des zones (qualif Europe, montée, barrages,
// maintien, relégation, playoffs…)
// ─────────────────────────────────────────────────────────────────────────────
// Objectif : mettre en évidence, dans CHAQUE classement (Ligue 1, Ligue 2, Suisse
// playoff, championnats étrangers, poules de coupe d'Europe…), ce qui se joue à
// chaque position, avec une barre de couleur à gauche de la ligne + une légende.
//
// SOURCE PRINCIPALE — `AFStandingEntry.description` : l'API-Football fournit, pour
// la plupart des lignes de classement, un libellé de zone en ANGLAIS, par ex. :
//   « Promotion - Champions League (Group Stage) », « Promotion - Europa League »,
//   « Promotion - Conference League (Qualification) », « Promotion » (montée directe),
//   « Promotion - Play-offs », « Relegation », « Relegation - Play-offs »,
//   « Championship Round », « Relegation Round »…
// On classe ce libellé par mots-clés → catégorie universelle. Cela couvre TOUS les
// championnats sans seuils codés en dur.
//
// REPLI — si `description` est absent (certaines ligues/poules), on retombe sur des
// seuils de rang approximatifs propres à quelques compétitions (Ligue 1/2…).
// ═════════════════════════════════════════════════════════════════════════════

/// Catégorie d'enjeu d'une ligne de classement. L'ordre du `rawValue` sert à
/// ordonner la légende (du plus « haut » enjeu au plus « bas »).
enum StandingStake: Int, CaseIterable {
    case champion          // 1re place / titre
    case championsLeague   // Qualif Ligue des champions (phase de groupes)
    case championsLeagueQ  // Qualif Ligue des champions (tour préliminaire)
    case europaLeague      // Qualif Ligue Europa
    case conferenceLeague  // Qualif Conference League
    case promotion         // Montée directe (2e/3e div.)
    case promotionPlayoff  // Barrage de montée / playoffs de promotion
    case championshipRound // Poule haute (playoff titre : Suisse, etc.)
    case relegationRound   // Poule basse (playout maintien)
    case relegationPlayoff // Barrage de relégation
    case relegation        // Relégation directe

    /// Clé de traduction du libellé affiché dans la légende.
    var titleKey: String {
        switch self {
        case .champion:          return "stake.champion"
        case .championsLeague:   return "stake.championsLeague"
        case .championsLeagueQ:  return "stake.championsLeagueQ"
        case .europaLeague:      return "stake.europaLeague"
        case .conferenceLeague:  return "stake.conferenceLeague"
        case .promotion:         return "stake.promotion"
        case .promotionPlayoff:  return "stake.promotionPlayoff"
        case .championshipRound: return "stake.championshipRound"
        case .relegationRound:   return "stake.relegationRound"
        case .relegationPlayoff: return "stake.relegationPlayoff"
        case .relegation:        return "stake.relegation"
        }
    }

    /// Couleur de la barre/pastille associée à l'enjeu.
    var color: Color {
        switch self {
        case .champion:          return Theme.gold
        case .championsLeague:   return Color(red: 0.10, green: 0.35, blue: 0.90) // bleu
        case .championsLeagueQ:  return Color(red: 0.35, green: 0.55, blue: 0.95) // bleu clair
        case .europaLeague:      return Color(red: 0.95, green: 0.55, blue: 0.05) // orange
        case .conferenceLeague:  return Color(red: 0.15, green: 0.70, blue: 0.55) // vert-eau
        case .promotion:         return Color(red: 0.15, green: 0.75, blue: 0.35) // vert
        case .promotionPlayoff:  return Color(red: 0.55, green: 0.80, blue: 0.20) // vert-lime
        case .championshipRound: return Color(red: 0.55, green: 0.35, blue: 0.85) // violet
        case .relegationRound:   return Color(red: 0.85, green: 0.55, blue: 0.20) // ambre
        case .relegationPlayoff: return Color(red: 0.95, green: 0.45, blue: 0.30) // orange-rouge
        case .relegation:        return Color(red: 0.90, green: 0.20, blue: 0.20) // rouge
        }
    }
}

enum StandingStakeClassifier {

    /// Compétitions dont le libellé `description` de l'API est PEU FIABLE et doit être
    /// ignoré au profit de nos seuils codés en dur. Cas des divisions françaises
    /// nouvelles/instables (Ligue 3 Betclic & National 1, formats 2026-27) : l'API
    /// hérite de l'ancien format National et colore par ex. 6 équipes en "Promotion".
    static let trustRankFallbackOnly: Set<String> = ["fr_ligue3", "fr_national1"]

    /// Détermine l'enjeu d'une ligne. Pour les compétitions listées dans
    /// `trustRankFallbackOnly`, on utilise EXCLUSIVEMENT nos seuils de rang. Sinon on
    /// privilégie le libellé `description` de l'API, avec repli par rang si absent.
    static func stake(for entry: AFStandingEntry, competition: Competition) -> StandingStake? {
        if trustRankFallbackOnly.contains(competition.id) {
            return fallbackByRank(rank: entry.rank, competition: competition)
        }
        if let d = entry.description, let s = fromDescription(d, rank: entry.rank) {
            return s
        }
        return fallbackByRank(rank: entry.rank, competition: competition)
    }

    /// Classe le libellé anglais fourni par l'API en catégorie d'enjeu.
    /// Ordre des tests : les cas les plus spécifiques d'abord.
    static func fromDescription(_ raw: String, rank: Int) -> StandingStake? {
        let s = raw.lowercased()

        // ── Relégation (avant "promotion" car certains libellés contiennent les deux) ──
        if s.contains("relegation") {
            if s.contains("play") { return .relegationPlayoff }   // "Relegation - Play-offs"
            return .relegation
        }
        // Poule basse (playout) — Suisse/écosse : "Relegation Round", "Bottom".
        if s.contains("relegation round") || s.contains("bottom") { return .relegationRound }

        // ── Qualif Coupes d'Europe (testées AVANT "promotion"/"play-off" génériques :
        //    un libellé "Conference League Play-offs" est une qualif européenne, PAS
        //    un barrage de montée). L'ordre Conference → Europa → Champions n'a pas
        //    d'importance car les mots-clés sont exclusifs. ──
        if s.contains("conference") {
            // Conference League (incl. "Europa Conference League"), avec ou sans
            // tour préliminaire : on garde la même catégorie (couleur unique).
            return .conferenceLeague
        }
        if s.contains("europa league") || s.contains("europa - league") {
            return .europaLeague
        }
        if s.contains("champions league") {
            // "Qualification"/"Qualifying"/"Play-off" = tour préliminaire.
            if s.contains("qualif") || s.contains("play") { return .championsLeagueQ }
            return .championsLeague
        }

        // ── Montée / promotion (2e-3e division) ──
        if s.contains("promotion") {
            if s.contains("play") { return .promotionPlayoff }    // "Promotion - Play-offs"
            return .promotion
        }

        // ── Poules hautes/basses de championnats à split (Suisse, Belgique, Écosse) ──
        if s.contains("championship round") || s.contains("title") || s.contains("championship group") {
            return .championshipRound
        }

        // NB : pas de repli "play-off générique → montée/relégation selon le rang".
        // Il produisait des enjeux faux (ex. "barrage de montée" en Ligue 1). Si le
        // libellé n'est rattaché à aucune catégorie connue, on ne colore rien plutôt
        // que de deviner.
        return nil
    }

    /// Repli approximatif par rang, pour les compétitions dont l'API ne fournit pas
    /// de `description`. Seuils calés sur les formats 2025-26.
    static func fallbackByRank(rank r: Int, competition: Competition) -> StandingStake? {
        switch competition.id {
        case "fr_ligue1":
            if r == 1 { return .champion }
            if r <= 3 { return .championsLeague }
            if r == 4 { return .championsLeagueQ }
            if r == 5 { return .europaLeague }
            if r == 6 { return .conferenceLeague }
            if r == 16 { return .relegationPlayoff }
            if r >= 17 { return .relegation }
        case "fr_ligue2":
            if r <= 2 { return .promotion }
            if r == 3 { return .promotionPlayoff }
            if r >= 17 { return .relegation }
        case "fr_ligue3":
            // Ligue 3 Betclic 2026-27 : 1-2 montée directe ; 3-6 play-offs d'accession
            // (barrage de montée) ; 16-17-18 relégation directe.
            if r <= 2 { return .promotion }
            if r <= 6 { return .promotionPlayoff }
            if r >= 16 { return .relegation }
        case "fr_national1":
            // National 1 2026-27 (ex-National 2) : 3 poules de 16. Montée = 1er de
            // chaque poule uniquement. Descentes : 15e-16e relégués d'office ; le 14e
            // est "à risque" (les 2 moins bons 14e des 3 poules descendent) → marqué
            // barrage de relégation car la décision se fait EN COMPARANT les 3 poules,
            // ce que ce classificateur (une ligne à la fois) ne peut pas trancher.
            if r == 1 { return .promotion }
            if r == 14 { return .relegationPlayoff }
            if r >= 15 { return .relegation }
        case "eng_pl", "esp_liga", "ita_seriea":
            if r <= 4 { return .championsLeague }
            if r == 5 { return .europaLeague }
            if r == 6 { return .conferenceLeague }
            if r >= 18 { return .relegation }
        case "ger_bundesliga":
            if r <= 4 { return .championsLeague }
            if r == 5 { return .europaLeague }
            if r == 6 { return .conferenceLeague }
            if r == 16 { return .relegationPlayoff }
            if r >= 17 { return .relegation }
        default:
            if r == 1 { return .champion }
        }
        return nil
    }

    /// Ensemble ordonné des enjeux réellement présents dans un classement donné,
    /// pour n'afficher dans la légende que les couleurs pertinentes.
    static func presentStakes(in entries: [AFStandingEntry], competition: Competition) -> [StandingStake] {
        var set = Set<StandingStake>()
        for e in entries { if let s = stake(for: e, competition: competition) { set.insert(s) } }
        return StandingStake.allCases.filter { set.contains($0) }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// LÉGENDE DÉPLIABLE — liste les couleurs présentes dans le classement et leur sens.
// ─────────────────────────────────────────────────────────────────────────────
struct StakesLegendView: View {
    let stakes: [StandingStake]
    @State private var expanded = false

    var body: some View {
        if !stakes.isEmpty {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paintpalette.fill").font(.caption2)
                        Text(L("stake.legend")).font(.caption).fontWeight(.semibold)
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                }

                if expanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(stakes, id: \.rawValue) { stake in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(stake.color)
                                    .frame(width: 12, height: 12)
                                Text(L(stake.titleKey))
                                    .font(.caption).foregroundColor(.primary)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 10)
                }
            }
            .background(Color(.secondarySystemBackground))
        }
    }
}
