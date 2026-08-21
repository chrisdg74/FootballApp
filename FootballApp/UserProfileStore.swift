import SwiftUI
import Combine

// ═════════════════════════════════════════════════════════════════════════════
// PROFIL UTILISATEUR (LOCAL, SANS COMPTE)
// ─────────────────────────────────────────────────────────────────────────────
// Un simple prénom saisi en local (UserDefaults) qui sert à personnaliser l'accueil
// (« Bonjour {prénom} »). AUCUN compte, AUCUN réseau : c'est juste un libellé.
// Les favoris/joueurs suivis sont déjà persistés localement de leur côté ; ce
// prénom ne les « rattache » pas à un serveur — il rend seulement l'accueil chaleureux.
//
// Injecté via `.environmentObject(UserProfileStore.shared)` à la racine, consommé
// avec `@EnvironmentObject var profile: UserProfileStore`.
// ═════════════════════════════════════════════════════════════════════════════

final class UserProfileStore: ObservableObject {
    static let shared = UserProfileStore()

    private let storageKey = "user_first_name_v1"

    /// Prénom de l'utilisateur. Chaîne vide = pas encore renseigné.
    @Published var firstName: String {
        didSet {
            let trimmed = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(trimmed, forKey: storageKey)
        }
    }

    private init() {
        firstName = UserDefaults.standard.string(forKey: storageKey) ?? ""
    }

    /// Prénom nettoyé (sans espaces superflus). Vide si non renseigné.
    var trimmedName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Vrai tant que l'utilisateur n'a pas saisi de prénom.
    var isUnset: Bool { trimmedName.isEmpty }
}
