import SwiftUI
import Combine

// ═════════════════════════════════════════════════════════════════════════════
// FAVORIS
// ─────────────────────────────────────────────────────────────────────────────
// Store persistant des équipes favorites de l'utilisateur. Sauvegardé en JSON
// dans UserDefaults → survit au redémarrage de l'app. Injecté via
// `.environmentObject(FavoritesStore.shared)` à la racine, consommé avec
// `@EnvironmentObject var favorites: FavoritesStore`.
// ═════════════════════════════════════════════════════════════════════════════

/// Une équipe favorite (données minimales pour l'afficher et la rouvrir).
/// On stocke un instantané des infos d'équipe (id/nom/logo/pays) plutôt qu'une
/// simple liste d'IDs : ça évite un appel API pour ré-afficher la liste.
struct FavoriteTeam: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let logo: String?
    let country: String?
    let national: Bool?

    /// Reconstruit un `AFTeamInfo` pour rouvrir la fiche équipe sans requête.
    var teamInfo: AFTeamInfo {
        AFTeamInfo(id: id, name: name, code: nil,
                   country: country, founded: nil, national: national, logo: logo)
    }

    init(id: Int, name: String, logo: String?, country: String?, national: Bool?) {
        self.id = id; self.name = name; self.logo = logo
        self.country = country; self.national = national
    }

    /// Construit un favori à partir d'une équipe issue de la recherche.
    init(from team: AFTeamInfo) {
        self.init(id: team.id, name: team.name, logo: team.logo,
                  country: team.country, national: team.national)
    }
}

/// Store observable des favoris, persistant (UserDefaults / JSON).
final class FavoritesStore: ObservableObject {
    static let shared = FavoritesStore()

    /// Liste ordonnée (ajout le plus récent en dernier).
    @Published private(set) var teams: [FavoriteTeam] = []

    private let storageKey = "favorite_teams_v1"

    private init() { load() }

    // ── Lecture ───────────────────────────────────────────────────────────────
    func isFavorite(_ id: Int) -> Bool { teams.contains { $0.id == id } }

    var isEmpty: Bool { teams.isEmpty }

    // ── Écriture ────────────────────────────────────────────────────────────────
    func add(_ team: AFTeamInfo) {
        guard !isFavorite(team.id) else { return }
        teams.append(FavoriteTeam(from: team))
        save()
    }

    func remove(_ id: Int) {
        teams.removeAll { $0.id == id }
        save()
    }

    /// Bascule l'état favori d'une équipe (ajoute si absente, retire sinon).
    func toggle(_ team: AFTeamInfo) {
        if isFavorite(team.id) { remove(team.id) } else { add(team) }
    }

    // ── Persistance ─────────────────────────────────────────────────────────────
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([FavoriteTeam].self, from: data)
        else { return }
        teams = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(teams) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
