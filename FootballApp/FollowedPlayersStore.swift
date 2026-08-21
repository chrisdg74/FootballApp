import SwiftUI
import Combine

// ═════════════════════════════════════════════════════════════════════════════
// JOUEURS SUIVIS
// ─────────────────────────────────────────────────────────────────────────────
// Store persistant des joueurs suivis par l'utilisateur (parallèle à
// `FavoritesStore` pour les clubs). Sauvegardé en JSON dans UserDefaults → survit
// au redémarrage. Injecté via `.environmentObject(FollowedPlayersStore.shared)`
// à la racine, consommé avec `@EnvironmentObject var followed: FollowedPlayersStore`.
//
// On stocke un instantané minimal (id/nom/photo/club) : ça permet d'afficher la
// liste et de rouvrir la fiche joueur sans requête réseau, et de retrouver le
// prochain match du joueur via la surface de son club (coût API ~nul).
// ═════════════════════════════════════════════════════════════════════════════

/// Un joueur suivi (données minimales pour l'afficher et rouvrir sa fiche).
struct FollowedPlayer: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let photo: String?
    let teamId: Int?
    let teamName: String?

    init(id: Int, name: String, photo: String?, teamId: Int?, teamName: String?) {
        self.id = id; self.name = name; self.photo = photo
        self.teamId = teamId; self.teamName = teamName
    }

    /// Construit un joueur suivi à partir d'une fiche complète (AFPlayerResponse).
    /// ⚠️ Club = `clubTeamId`/`clubTeamName` (1re ligne de CLUB), JAMAIS
    /// `statistics.first` qui peut être une ligne de sélection nationale → on
    /// afficherait alors le prochain match de la sélection (France) au lieu du
    /// club (Real Madrid). Voir AFPlayerResponse.clubTeamId.
    init(from p: AFPlayerResponse) {
        self.init(id: p.player.id,
                  name: p.fullName.isEmpty ? p.player.name : p.fullName,
                  photo: (p.player.photo?.isEmpty == false ? p.player.photo : nil),
                  teamId: p.clubTeamId,
                  teamName: p.clubTeamName)
    }
}

/// Store observable des joueurs suivis, persistant (UserDefaults / JSON).
final class FollowedPlayersStore: ObservableObject {
    static let shared = FollowedPlayersStore()

    /// Liste ordonnée (ajout le plus récent en dernier).
    @Published private(set) var players: [FollowedPlayer] = []

    private let storageKey = "followed_players_v1"

    private init() { load() }

    // ── Lecture ───────────────────────────────────────────────────────────────
    func isFollowed(_ id: Int) -> Bool { players.contains { $0.id == id } }

    var isEmpty: Bool { players.isEmpty }

    // ── Écriture ────────────────────────────────────────────────────────────────
    func add(_ player: FollowedPlayer) {
        guard !isFollowed(player.id) else { return }
        players.append(player)
        save()
        // Enrichissement immédiat de CE joueur (photo + club) sans attendre le
        // prochain lancement : depuis la recherche, le snapshot peut manquer la
        // photo/club (l'endpoint /players/profiles est partiel) → l'avatar restait
        // en monogramme jusqu'au redémarrage. On complète en tâche de fond.
        Task { await enrich(playerId: player.id) }
    }

    /// Complète l'instantané d'UN joueur suivi via l'API (photo + club), sans
    /// écraser les champs déjà connus. Idempotent, tolérant à l'échec réseau.
    @MainActor
    private func enrich(playerId: Int) async {
        guard let detail = try? await FootballAPIService.shared
            .fetchPlayerDetail(playerId: playerId, season: 2026) else { return }
        guard let idx = players.firstIndex(where: { $0.id == playerId }) else { return }
        let fresh = FollowedPlayer(from: detail)
        let updated = FollowedPlayer(id: fresh.id,
                                     name: fresh.name.isEmpty ? players[idx].name : fresh.name,
                                     photo: fresh.photo ?? players[idx].photo,
                                     teamId: fresh.teamId ?? players[idx].teamId,
                                     teamName: fresh.teamName ?? players[idx].teamName)
        if updated != players[idx] { players[idx] = updated; save() }
    }

    func remove(_ id: Int) {
        players.removeAll { $0.id == id }
        save()
    }

    /// Bascule l'état suivi d'un joueur (ajoute si absent, retire sinon).
    func toggle(_ player: FollowedPlayer) {
        if isFollowed(player.id) { remove(player.id) } else { add(player) }
    }

    // ── Migration : nettoyage des noms d'affichage déjà enregistrés ─────────────
    // Les premiers favoris ont pu être stockés avec l'état civil complet
    // (« Kylian Mbappé Lottin ») avant la correction de `fullName`. Au lancement,
    // on ré-interroge l'API une fois par joueur suivi pour recalculer le nom propre
    // (et rafraîchir photo/club au passage). Idempotent : ne réécrit que si un champ
    // a changé. Volontairement séquentiel pour ménager le quota API-Football.
    private var didRefreshNames = false

    @MainActor
    func refreshDisplayNames() async {
        guard !didRefreshNames, !players.isEmpty else { return }
        didRefreshNames = true
        var changed = false
        for player in players {
            guard let detail = try? await FootballAPIService.shared
                .fetchPlayerDetail(playerId: player.id, season: 2026) else { continue }
            let fresh = FollowedPlayer(from: detail)
            guard let idx = players.firstIndex(where: { $0.id == player.id }) else { continue }
            // Conserve un club déjà connu si l'API n'en renvoie pas cette fois.
            let mergedTeamId = fresh.teamId ?? players[idx].teamId
            let mergedTeamName = fresh.teamName ?? players[idx].teamName
            let updated = FollowedPlayer(id: fresh.id,
                                         name: fresh.name,
                                         photo: fresh.photo ?? players[idx].photo,
                                         teamId: mergedTeamId,
                                         teamName: mergedTeamName)
            if updated != players[idx] { players[idx] = updated; changed = true }
        }
        if changed { save() }
    }

    // ── Persistance ─────────────────────────────────────────────────────────────
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([FollowedPlayer].self, from: data)
        else { return }
        players = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(players) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
