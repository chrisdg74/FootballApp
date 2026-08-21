import SwiftUI
import Combine

// ═════════════════════════════════════════════════════════════════════════════
// COMPÉTITIONS SUIVIES
// ─────────────────────────────────────────────────────────────────────────────
// Store persistant des compétitions que l'utilisateur souhaite suivre dans
// l'onglet Live. On ne stocke QUE les identifiants internes (Competition.id) —
// les objets `Competition` sont reconstruits depuis le catalogue (`Catalog`).
// Sauvegardé en JSON dans UserDefaults → survit au redémarrage. Injecté via
// `.environmentObject(FollowedCompetitionsStore.shared)` à la racine, consommé
// avec `@EnvironmentObject var followed: FollowedCompetitionsStore`.
//
// Défaut au premier lancement (choix utilisateur) : Ligue 1 + les 3 coupes
// d'Europe (Ligue des champions / Europa / Conférence) → écran Live non vide.
// ═════════════════════════════════════════════════════════════════════════════

final class FollowedCompetitionsStore: ObservableObject {
    static let shared = FollowedCompetitionsStore()

    /// Identifiants (`Competition.id`) des compétitions suivies.
    @Published private(set) var ids: Set<String> = []

    private let storageKey = "followed_competitions_v1"
    /// Marqueur : distingue « l'utilisateur a tout décoché » d'un premier lancement.
    private let seededKey = "followed_competitions_seeded_v1"

    /// Jeu par défaut au tout premier lancement (avant tout choix de l'utilisateur).
    private static let defaultIds: Set<String> = ["fr_ligue1", "eu_ucl", "eu_uel", "eu_uecl"]

    private init() { load() }

    // ── Lecture ───────────────────────────────────────────────────────────────
    func isFollowed(_ id: String) -> Bool { ids.contains(id) }

    var isEmpty: Bool { ids.isEmpty }

    /// Les compétitions suivies, reconstruites depuis le catalogue, dans l'ordre du
    /// catalogue (France d'abord, puis International, Europe, Nations).
    var competitions: [Competition] {
        Catalog.all.filter { ids.contains($0.id) }
    }

    /// IDs API à interroger pour les compétitions suivies (poules incluses).
    var apiIds: [Int] { competitions.flatMap { $0.allApiIds } }

    // ── Écriture ────────────────────────────────────────────────────────────────
    func add(_ id: String) {
        guard !ids.contains(id) else { return }
        ids.insert(id); save()
    }

    func remove(_ id: String) {
        ids.remove(id); save()
    }

    /// Bascule l'état « suivi » d'une compétition.
    func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        save()
    }

    // ── Persistance ─────────────────────────────────────────────────────────────
    private func load() {
        let seeded = UserDefaults.standard.bool(forKey: seededKey)
        if !seeded {
            // Premier lancement : on amorce avec le jeu par défaut.
            ids = Self.defaultIds
            UserDefaults.standard.set(true, forKey: seededKey)
            save()
            return
        }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        ids = Set(decoded)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Array(ids)) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
