import SwiftUI
import Combine

// ═════════════════════════════════════════════════════════════════════════════
// JEU FANTASY — « ÉQUIPE DE LA SAISON »
// ─────────────────────────────────────────────────────────────────────────────
// Jeu 100 % LOCAL (aucun serveur, aucun compte). L'utilisateur compose une équipe
// de 5 joueurs dans la limite d'un BUDGET virtuel. Chaque joueur a :
//   • un PRIX, dérivé de ses stats de saison (une star coûte cher) ;
//   • un nombre de POINTS, calculé au barème simple (but ×5, passe ×3, match ×1).
// Le score de l'équipe = somme des points de ses joueurs. Comme les stats de
// saison grandissent au fil des matchs, le score se met à jour tout seul à chaque
// rafraîchissement — pas besoin de stats match-par-match (coûteuses en quota API).
//
// L'équipe sélectionnée est persistée en JSON dans UserDefaults, sur le modèle de
// FavoritesStore. On stocke un INSTANTANÉ des joueurs (id/nom/prix…) : le score
// est recalculé à partir du vivier rechargé, l'instantané sert d'affichage de
// repli tant que le vivier n'est pas chargé.
// ═════════════════════════════════════════════════════════════════════════════

/// Barème de points (règle simple, lisible et validable avec les stats saison).
enum FantasyScoring {
    static let pointsPerGoal   = 5
    static let pointsPerAssist = 3
    static let pointsPerAppearance = 1

    /// Points d'un joueur d'après ses stats cumulées de saison.
    static func points(goals: Int, assists: Int, appearances: Int) -> Int {
        goals * pointsPerGoal
            + assists * pointsPerAssist
            + appearances * pointsPerAppearance
    }

    /// Prix (en crédits) d'un joueur d'après ses stats. Barème volontairement
    /// simple : une base + une prime aux buts/passes, borné pour rester lisible.
    /// Objectif : une équipe de 5 stars dépasse le budget, on doit donc arbitrer.
    static func price(goals: Int, assists: Int, appearances: Int) -> Int {
        let raw = 3 + goals * 3 + assists * 2 + appearances / 4
        return min(max(raw, 3), 45)   // borné entre 3 et 45 crédits
    }
}

/// Poste normalisé d'un joueur, pour le filtre du sélecteur.
/// API-Football renvoie `games.position` en anglais : « Goalkeeper », « Defender »,
/// « Midfielder », « Attacker » (parfois nil). On mappe vers 4 postes + `.unknown`.
enum FantasyPosition: String, CaseIterable, Identifiable {
    case goalkeeper, defender, midfielder, attacker, unknown
    var id: String { rawValue }

    /// Construit le poste à partir de la chaîne brute renvoyée par l'API.
    init(apiValue: String?) {
        switch apiValue?.lowercased() {
        case let s? where s.contains("goalkeeper") || s == "g": self = .goalkeeper
        case let s? where s.contains("defender")   || s == "d": self = .defender
        case let s? where s.contains("midfielder") || s == "m": self = .midfielder
        case let s? where s.contains("attacker")   || s == "f" || s.contains("forward"): self = .attacker
        default: self = .unknown
        }
    }

    /// Clé de localisation du libellé court (chip du filtre).
    var titleKey: String {
        switch self {
        case .goalkeeper: return "pos.goalkeeper"
        case .defender:   return "pos.defender"
        case .midfielder: return "pos.midfielder"
        case .attacker:   return "pos.attacker"
        case .unknown:    return "pos.unknown"
        }
    }

    /// Clé de localisation du libellé SINGULIER (fiche d'un joueur : « Attaquant »).
    var singularTitleKey: String {
        switch self {
        case .goalkeeper: return "pos.one.goalkeeper"
        case .defender:   return "pos.one.defender"
        case .midfielder: return "pos.one.midfielder"
        case .attacker:   return "pos.one.attacker"
        case .unknown:    return "pos.unknown"
        }
    }
}

/// Un joueur sélectionnable / sélectionné dans le jeu fantasy.
/// `Codable` pour la persistance ; `points`/`price` sont figés à l'instant de la
/// capture mais recalculés dès que le vivier est rechargé (voir FantasyStore).
struct FantasyPlayer: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let club: String
    let photo: String?
    let position: String?
    let goals: Int
    let assists: Int
    let appearances: Int

    var points: Int { FantasyScoring.points(goals: goals, assists: assists, appearances: appearances) }
    var price: Int  { FantasyScoring.price(goals: goals, assists: assists, appearances: appearances) }

    /// Poste normalisé (dérivé de `position`), pour le filtre du sélecteur.
    var pos: FantasyPosition { FantasyPosition(apiValue: position) }

    static func == (lhs: FantasyPlayer, rhs: FantasyPlayer) -> Bool { lhs.id == rhs.id }
}

/// Store observable du jeu fantasy, persistant (UserDefaults / JSON).
/// Injecté via `.environmentObject(FantasyStore.shared)` à la racine.
final class FantasyStore: ObservableObject {
    static let shared = FantasyStore()

    /// Budget total (crédits) alloué pour composer l'équipe.
    static let budget = 100
    /// Taille maximale de l'équipe.
    static let squadSize = 5

    /// Équipe sélectionnée (instantané persistant, max `squadSize` joueurs).
    @Published private(set) var squad: [FantasyPlayer] = []

    private let storageKey = "fantasy_squad_v1"

    private init() { load() }

    // ── Lecture ───────────────────────────────────────────────────────────────
    func contains(_ id: Int) -> Bool { squad.contains { $0.id == id } }
    var isEmpty: Bool { squad.isEmpty }
    var isFull: Bool { squad.count >= Self.squadSize }

    /// Coût total de l'équipe.
    var spent: Int { squad.reduce(0) { $0 + $1.price } }
    /// Budget restant.
    var remaining: Int { Self.budget - spent }
    /// Score total de l'équipe.
    var totalPoints: Int { squad.reduce(0) { $0 + $1.points } }

    /// Peut-on ajouter ce joueur ? (place libre, pas déjà pris, budget suffisant)
    func canAdd(_ player: FantasyPlayer) -> Bool {
        !isFull && !contains(player.id) && player.price <= remaining
    }

    // ── Écriture ──────────────────────────────────────────────────────────────
    @discardableResult
    func add(_ player: FantasyPlayer) -> Bool {
        guard canAdd(player) else { return false }
        squad.append(player)
        save()
        return true
    }

    func remove(_ id: Int) {
        squad.removeAll { $0.id == id }
        save()
    }

    func toggle(_ player: FantasyPlayer) {
        if contains(player.id) { remove(player.id) } else { add(player) }
    }

    func reset() {
        squad.removeAll()
        save()
    }

    /// Rafraîchit l'instantané de l'équipe à partir d'un vivier fraîchement chargé
    /// (stats de saison à jour). Les joueurs absents du vivier sont conservés tels
    /// quels (repli). N'ajoute/ne retire personne — met juste les stats à jour.
    func refreshSnapshot(from pool: [FantasyPlayer]) {
        guard !pool.isEmpty else { return }
        let byId = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = false
        squad = squad.map { current in
            if let fresh = byId[current.id] { changed = true; return fresh }
            return current
        }
        if changed { save() }
    }

    /// Recalcule les points de l'équipe en relisant les VRAIES stats de saison de
    /// SES joueurs uniquement (pas tout le vivier). Appelé à chaque ouverture de
    /// l'onglet « Mon équipe » : c'est ce qui fait MONTER le score au fil des
    /// journées réelles (chaque but/passe/match des joueurs ajoute des points).
    @MainActor
    func refreshSquadStats() async {
        guard !squad.isEmpty else { return }
        let fresh = await FootballAPIService.shared.fetchFantasySquadRefresh(ids: squad.map { $0.id })
        refreshSnapshot(from: fresh)
    }

    // ── Persistance ─────────────────────────────────────────────────────────────
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([FantasyPlayer].self, from: data)
        else { return }
        squad = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(squad) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
