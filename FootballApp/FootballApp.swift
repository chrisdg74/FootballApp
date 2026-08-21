import SwiftUI

@main
struct FootballApp: App {
    // Langue in-app : on observe le manager pour reconstruire l'UI au changement.
    @StateObject private var locale = LocaleManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)   // Thème clair (fond blanc, façon FotMob)
                .tint(Theme.live)
                .environmentObject(FavoritesStore.shared)
                .environmentObject(FantasyStore.shared)
                .environmentObject(FollowedCompetitionsStore.shared)
                .environmentObject(FollowedPlayersStore.shared)
                .environmentObject(UserProfileStore.shared)
                .environmentObject(AppRouter.shared)
                .environmentObject(locale)
                // Sens de lecture selon la langue choisie (arabe = droite→gauche).
                .environment(\.layoutDirection, locale.layoutDirection)
                // Reconstruit tout l'arbre de vues quand la langue change → les
                // libellés déjà rendus sont retraduits immédiatement.
                .id(locale.refreshToken)
        }
    }
}
