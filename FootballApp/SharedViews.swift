import SwiftUI

// ═════════════════════════════════════════════════════════════════════════════
// COMPOSANTS PARTAGÉS — états d'écran (chargement / vide / erreur) + logo équipe
// ─────────────────────────────────────────────────────────────────────────────
// Tous alignés sur le design system `Theme` (couleurs, accent, rayons) pour une
// finition cohérente d'un écran à l'autre. Trois états standard :
//   • LoadingView   → attente (spinner de marque + libellé optionnel)
//   • EmptyStateView→ aucune donnée (icône douce + message)
//   • ErrorView     → échec réseau (icône + message + bouton Réessayer)
// ═════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// CHARGEMENT — spinner de marque (anneau qui tourne aux couleurs de l'app).
// Remplace les `ProgressView()` nus pour une attente plus soignée et cohérente.
// ─────────────────────────────────────────────────────────────────────────────
struct LoadingView: View {
    var label: String? = nil
    @State private var spin = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                // Anneau de fond discret.
                Circle()
                    .stroke(Theme.hairline, lineWidth: 3)
                    .frame(width: 38, height: 38)
                // Arc coloré qui tourne.
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(
                        Theme.live,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 38, height: 38)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false),
                               value: spin)
            }
            if let label {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(Theme.textSoft)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { spin = true }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ÉTAT VIDE — aucune donnée (pas une erreur : la requête a réussi mais est vide).
// ─────────────────────────────────────────────────────────────────────────────
struct EmptyStateView: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.surface)
                    .frame(width: 78, height: 78)
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .regular))
                    .foregroundColor(Theme.textFaint)
            }
            Text(text)
                .font(.subheadline)
                .foregroundColor(Theme.textSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ERREUR — échec réseau, avec bouton « Réessayer » aux couleurs de l'app.
// ─────────────────────────────────────────────────────────────────────────────
struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.live.opacity(0.12))
                    .frame(width: 78, height: 78)
                Image(systemName: "wifi.slash")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundColor(Theme.live)
            }
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(Theme.textSoft)
                .padding(.horizontal, 32)
            Button(action: retry) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text(L("action.retry"))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Theme.live)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGO D'ÉQUIPE réutilisable.
// Charge le blason via AsyncImage (URL fournie par l'API) et retombe proprement
// sur un badge à initiales si l'image est absente ou bloquée.
//
// ⚠️ Licence : l'affichage des logos repose sur les conditions d'utilisation
// d'API-Football (media servi par l'API). À vérifier pour un usage commercial /
// app payante avant publication. Le repli garantit une UI intacte si désactivé.
// ─────────────────────────────────────────────────────────────────────────────
struct TeamLogoView: View {
    let urlString: String?
    let name: String
    var size: CGFloat = 22
    /// ID API-Football de l'équipe, si disponible au point d'appel. Sert au
    /// repli TheSportsDB pour un match FIABLE (via `idAPIfootball`). Optionnel :
    /// les appels sans ID retombent sur un match par nom.
    var teamId: Int? = nil

    /// URL de secours (TheSportsDB) résolue à la demande, si l'URL
    /// API-Football est absente OU si elle échoue au chargement (404, etc.).
    /// `nil` tant que non résolue ou introuvable.
    @State private var fallbackURL: URL? = nil
    @State private var didTryFallback = false
    /// Vrai si l'URL API-Football a échoué au chargement (image cassée) :
    /// déclenche le repli TheSportsDB au lieu d'afficher le monogramme.
    @State private var primaryFailed = false

    /// Initiales de repli (max 2 lettres) à partir du nom d'équipe.
    private var initials: String {
        let words = name.split(separator: " ")
        let letters = words.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    private var fallback: some View {
        ZStack {
            Circle().fill(Theme.surface)
            Text(initials)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundColor(Theme.textSoft)
        }
        .frame(width: size, height: size)
    }

    /// URL API-Football exploitable (non vide et bien formée).
    private var primaryURL: URL? {
        guard let s = urlString, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// URL effective : API-Football en priorité (tant qu'elle n'a pas échoué),
    /// sinon secours TheSportsDB.
    private var effectiveURL: URL? {
        if !primaryFailed, let url = primaryURL { return url }
        return fallbackURL
    }

    /// Vrai si l'on doit tenter le repli TheSportsDB : soit API-Football n'a
    /// fourni aucune URL, soit son URL a échoué au chargement.
    private var needsFallback: Bool {
        primaryURL == nil || primaryFailed
    }

    var body: some View {
        Group {
            if let url = effectiveURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                            .frame(width: size, height: size)
                            .transition(.opacity)          // fondu doux à l'arrivée
                    case .failure:
                        // Échec de l'URL primaire → bascule vers le repli
                        // TheSportsDB. On n'affiche le monogramme QUE si le
                        // repli lui-même est déjà résolu et infructueux.
                        if url == primaryURL {
                            Circle().fill(Theme.surface)
                                .frame(width: size, height: size)
                                .onAppear { primaryFailed = true }
                        } else {
                            fallback
                        }
                    case .empty:
                        Circle()
                            .fill(Theme.surface)
                            .frame(width: size, height: size)   // placeholder neutre
                    @unknown default:
                        fallback
                    }
                }
                .id(url)   // recharge proprement quand on bascule sur le repli
            } else {
                fallback
            }
        }
        // Repli à la demande : si API-Football n'a rien donné OU a échoué, une
        // seule fois. Le service met en cache → aucun appel réseau répété.
        .task(id: needsFallback) {
            guard needsFallback, !didTryFallback else { return }
            didTryFallback = true
            if let id = teamId {
                fallbackURL = await ImageFallbackService.shared.teamBadge(apiFootballId: id, name: name)
            }
        }
    }
}
