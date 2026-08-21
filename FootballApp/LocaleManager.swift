import SwiftUI
import Combine

// ═════════════════════════════════════════════════════════════════════════════
// LANGUE DE L'APPLICATION (choix in-app)
// ─────────────────────────────────────────────────────────────────────────────
// Permet à l'utilisateur de choisir la langue de l'app INDÉPENDAMMENT de la langue
// du système. Le choix est persistant (UserDefaults) et pris en compte par le
// helper `L(_:)` (Models.swift) : quand une langue est choisie, `L` lit la table
// du bundle `.lproj` correspondant au lieu de la langue système.
//
// iOS ne recharge pas instantanément toute l'UI déjà rendue quand on change de
// bundle de langue ; on incrémente donc `refreshToken` (auquel la racine se lie
// via `.id(...)`) pour forcer une reconstruction immédiate de l'arbre de vues.
// Pour les 100 % (dates système, formats), un vrai redémarrage reste idéal :
// l'écran de réglages propose donc un message d'info.
// ═════════════════════════════════════════════════════════════════════════════

/// Les langues proposées dans l'app (les 8 langues effectivement traduites).
enum AppLanguage: String, CaseIterable, Identifiable {
    case system          // Suit la langue de l'iPhone
    case fr, en, it, es, de
    case ptPT = "pt-PT"
    case ja, ar

    var id: String { rawValue }

    /// Code de dossier `.lproj` à charger. `nil` pour « système ».
    var lprojName: String? {
        switch self {
        case .system: return nil
        default:      return rawValue
        }
    }

    /// Libellé affiché dans le sélecteur, dans SA PROPRE langue (endonyme).
    var displayName: String {
        switch self {
        case .system: return L("settings.language.system")
        case .fr:     return "Français"
        case .en:     return "English"
        case .it:     return "Italiano"
        case .es:     return "Español"
        case .de:     return "Deutsch"
        case .ptPT:   return "Português"
        case .ja:     return "日本語"
        case .ar:     return "العربية"
        }
    }

    /// Petit drapeau représentatif (indicatif, pas une revendication politique).
    var flag: String {
        switch self {
        case .system: return "🌐"
        case .fr:     return "🇫🇷"
        case .en:     return "🇬🇧"
        case .it:     return "🇮🇹"
        case .es:     return "🇪🇸"
        case .de:     return "🇩🇪"
        case .ptPT:   return "🇵🇹"
        case .ja:     return "🇯🇵"
        case .ar:     return "🇸🇦"
        }
    }
}

/// Gère la langue choisie et expose le bundle `.lproj` correspondant.
final class LocaleManager: ObservableObject {
    static let shared = LocaleManager()

    private let storageKey = "app_language_v1"

    /// Langue choisie. Écriture → persistance + recalcul du bundle + refresh UI.
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: storageKey)
            resolveBundle()
            refreshToken &+= 1
        }
    }

    /// Bundle de la langue choisie (nil = langue système → `L` utilise NSLocalizedString).
    private(set) var bundle: Bundle?

    /// Jeton incrémenté à chaque changement : la racine s'y lie via `.id(...)`
    /// pour forcer la reconstruction immédiate de toute l'UI.
    @Published private(set) var refreshToken: Int = 0

    private init() {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.system.rawValue
        language = AppLanguage(rawValue: raw) ?? .system
        resolveBundle()
    }

    private func resolveBundle() {
        guard let name = language.lprojName,
              let path = Bundle.main.path(forResource: name, ofType: "lproj"),
              let b = Bundle(path: path) else {
            bundle = nil          // langue système
            return
        }
        bundle = b
    }

    /// Sens de lecture de la langue courante (l'arabe est de droite à gauche).
    var layoutDirection: LayoutDirection {
        language == .ar ? .rightToLeft : .leftToRight
    }
}
