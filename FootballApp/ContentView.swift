import SwiftUI

struct ContentView: View {
    /// Présentation du mini-jeu quiz (bouton flottant + carte d'accueil).
    @State private var showQuiz = false

    var body: some View {
        // TabView plein écran : 4 onglets. L'assistant IA a été RETIRÉ (trop
        // complexe pour la V1). Un BOUTON FLOTTANT « Jeu » (quiz Ligue 1, 100 %
        // local) est posé en overlay pour garder la barre à 4 onglets aérée.
        TabView {
            // Accueil : « Bonjour {prénom} » + prochains matchs des favoris.
            HomeView()
                .tabItem { Label(L("home.title"), systemImage: "house.fill") }

            // Onglet unique regroupant les 4 rubriques (France / International /
            // Europe / Nations) via un sélecteur segmenté — évite une TabBar à 7
            // onglets (iOS n'en montre que 5 + « More »).
            CompetitionsHomeView()
                .tabItem { Label(L("competitions.title"), systemImage: "trophy.fill") }

            LiveView()
                .tabItem { Label(L("tab.live"), systemImage: "dot.radiowaves.left.and.right") }

            // Favoris + Recherche FUSIONNÉS : la barre `.searchable` cherche clubs
            // et joueurs ; quand elle est vide, on montre la bibliothèque de favoris.
            FavoritesTabView()
                .tabItem { Label(L("library.title"), systemImage: "star.fill") }

            // ⏸️ Jeu fantasy MASQUÉ pour l'instant (classement/récompenses à décider).
            //    Tout le code (FantasyView, FantasyStore…) reste en place :
            //    il suffit de décommenter ce bloc pour le réactiver.
            // FantasyView()
            //     .tabItem { Label(L("fantasy.title"), systemImage: "gamecontroller.fill") }
        }
        .tint(Theme.live)
        // Bouton flottant « Jeu » : posé en bas à droite, au-dessus de la TabBar.
        // On l'affiche via `NotificationCenter` aussi bien que par tap direct pour
        // que la carte d'accueil puisse déclencher le même écran (voir HomeView).
        .overlay(alignment: .bottomTrailing) {
            QuizFloatingButton { showQuiz = true }
                .padding(.trailing, 16)
                .padding(.bottom, 66)   // au-dessus de la barre d'onglets
        }
        .fullScreenCover(isPresented: $showQuiz) {
            QuizView { showQuiz = false }
        }
        // La carte « Jeu du jour » de l'accueil poste cette notification pour
        // ouvrir le quiz sans dupliquer l'état de présentation.
        .onReceive(NotificationCenter.default.publisher(for: .openQuiz)) { _ in
            showQuiz = true
        }
        // Migration ponctuelle : nettoie les noms des joueurs déjà suivis
        // (« Kylian Mbappé Lottin » → « Kylian Mbappé ») + rafraîchit photo/club.
        .task { await FollowedPlayersStore.shared.refreshDisplayNames() }
    }
}

/// Notification déclenchant l'ouverture du quiz depuis n'importe quel écran.
extension Notification.Name {
    static let openQuiz = Notification.Name("openQuiz")
}

/// Bouton flottant rond « Jeu » (style cohérent avec la palette brand).
struct QuizFloatingButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle().fill(
                        LinearGradient(colors: [Theme.brand, Theme.brandDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                )
                .shadow(color: Theme.brand.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .accessibilityLabel(L("quiz.title"))
    }
}
