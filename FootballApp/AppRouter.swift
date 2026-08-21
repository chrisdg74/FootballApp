import SwiftUI
import Combine

/// Routeur d'application léger, partagé via `@EnvironmentObject`.
///
/// Sert de point unique pour piloter des présentations globales depuis
/// n'importe quel écran — aujourd'hui : l'ouverture de l'assistant IA (chat).
/// Ainsi, l'amorce IA de la page d'accueil (onglet Live) peut ouvrir le même
/// chat premium que le bouton flottant, sans dupliquer la feuille.
///
/// Injecté à la racine dans `FootballApp.swift`
/// (`.environmentObject(AppRouter.shared)`) et consommé avec
/// `@EnvironmentObject private var router: AppRouter`.
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    private init() {}

    /// Présente la feuille de l'assistant IA (chat conversationnel).
    @Published var showAssistant = false

    /// Message d'amorce pré-rempli au prochain affichage du chat (optionnel).
    /// Permet à un bouton d'accueil du type « Pose une question sur le match »
    /// d'ouvrir le chat sur une intention précise. `nil` = chat vierge.
    @Published var assistantPrefill: String?

    /// Ouvre l'assistant, éventuellement avec un message d'amorce.
    func openAssistant(prefill: String? = nil) {
        assistantPrefill = prefill
        showAssistant = true
    }
}
