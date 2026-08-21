import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// ARTWORK DE COMPÉTITION — vignette « premium » réutilisable
// -----------------------------------------------------------------------------
// Objectif : un rendu classe et cohérent pour CHAQUE compétition, sans dépendre
// de la qualité inégale des logos distants ni jamais laisser un « trou ».
//
// Couches (du fond vers l'avant) :
//   1. Dégradé maison dérivé de `competition.tint` (profond, légèrement assombri
//      en bas) + halo radial clair en haut-gauche → profondeur « premium ».
//   2. Le VRAI logo officiel de la compétition, résolu par NOM une seule fois via
//      `ImageFallbackService.leagueBadge(name:)` (mémorisé → 1 appel réseau max
//      pour toute l'app). Affiché seulement s'il se charge proprement.
//   3. REPLI élégant si pas de logo : monogramme `shortName` (L1, PL, UCL…) en
//      typo bold blanche. Toujours lisible, jamais cheap.
//
// Aucune donnée inventée : le logo vient de TheSportsDB (source réelle) ou n'est
// pas affiché ; le monogramme est le `shortName` du catalogue.
// ─────────────────────────────────────────────────────────────────────────────
struct CompetitionArtworkView: View {
    let competition: Competition
    var size: CGFloat = 44
    /// Coins arrondis proportionnels (vignette « carte »). 0 = cercle.
    var cornerRadius: CGFloat? = nil
    /// Affiche le drapeau du pays en pastille sur le coin bas-droit (choix user
    /// 2026-08-16 : « le drapeau du pays à côté »). Actif dans les listes ; on
    /// peut le désactiver là où le drapeau est déjà affiché ailleurs.
    var showsFlag: Bool = true

    @State private var logoURL: URL? = nil
    @State private var didResolve = false
    @State private var logoLoaded = false

    private var radius: CGFloat { cornerRadius ?? size * 0.28 }
    private var base: Color { competition.color }

    /// Dégradé de fond : teinte pleine en haut-gauche → variante assombrie en
    /// bas-droite. Donne une profondeur soignée quelle que soit la couleur.
    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                base.opacity(0.95),
                base,
                base.blended(with: .black, amount: 0.45)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            if let asset = competition.assetLogo {
                // ── CAS 1 : logo EMBARQUÉ (divisions françaises…) ────────────────
                // Logo officiel complet → carte blanche arrondie, logo ENTIER.
                logoCard { anyLogoImage(Image(asset)) }
            } else if let url = logoURL {
                // ── CAS 2 : logo OFFICIEL DISTANT (API-Football / TheSportsDB) ───
                // Même rendu « classe » que les logos embarqués : carte blanche
                // arrondie + logo ENTIER haute qualité. Vaut pour TOUTES les
                // compétitions (Premier League, Liga, UCL, etc.).
                logoCard {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            anyLogoImage(image)
                                .transition(.opacity)
                                .onAppear { withAnimation(.easeOut(duration: 0.25)) { logoLoaded = true } }
                        case .empty, .failure:
                            Color.clear
                        @unknown default:
                            Color.clear
                        }
                    }
                }
            } else {
                // ── CAS 3 : REPLI (logo pas encore chargé ou introuvable) ────────
                // Carte dégradée « premium » teintée + motif + monogramme. Jamais
                // de vide : on voit toujours une belle vignette colorée.
                fallbackCard
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        // Drapeau du pays en pastille sur le coin bas-droit (débordant légèrement),
        // affiché par-DESSUS le clip de la vignette. Uniforme pour TOUTES les
        // compétitions (logo réel OU monogramme) → réponse à la demande user.
        .overlay(alignment: .bottomTrailing) {
            if showsFlag, let flag = flagEmoji {
                Text(flag)
                    .font(.system(size: size * 0.34))
                    .padding(size * 0.06)
                    .background(
                        Circle().fill(Color(.systemBackground))
                            .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 0.5))
                    )
                    .offset(x: size * 0.14, y: size * 0.14)
            }
        }
        .task(id: competition.id) { await resolveLogo() }
    }

    // ── Carte blanche arrondie « premium » contenant un logo ENTIER ──────────────
    // Fond blanc net + fine bordure + ombre douce. Le logo (embarqué OU distant)
    // est passé en `content` et affiché en entier via `anyLogoImage`.
    private func logoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.white)
            .overlay(content().padding(size * 0.12))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.8)
            )
    }

    // ── Rendu haute qualité d'un logo, JAMAIS rogné ──────────────────────────────
    private func anyLogoImage(_ image: Image) -> some View {
        image
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
    }

    // ── Repli : carte dégradée teintée + motif + monogramme ──────────────────────
    private var fallbackCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(backgroundGradient)
                .overlay(
                    CompetitionPatternView(competition: competition,
                                           cornerRadius: radius,
                                           intensity: 0.85)
                )
                .overlay(
                    RadialGradient(
                        colors: [Color.white.opacity(0.22), Color.clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.9
                    )
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                )

            Text(competition.shortName)
                .font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, size * 0.1)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        }
    }

    /// Drapeau émoji du pays de la compétition. `countryCode` stocke déjà un emoji
    /// (ex. 🇫🇷) dans le catalogue ; on ne l'affiche que si présent et non vide.
    private var flagEmoji: String? {
        guard let code = competition.countryCode?.trimmingCharacters(in: .whitespaces),
              !code.isEmpty else { return nil }
        return code
    }

    private func resolveLogo() async {
        guard !didResolve else { return }
        didResolve = true

        // 0) Logo EMBARQUÉ fourni par nous → prioritaire, aucun appel réseau.
        if competition.assetLogo != nil { logoLoaded = true; return }

        let name = L(competition.nameKey)

        // 1) SOURCE FIABLE : logo API-Football par ID (couvre L1/L2/L3/N1/CdF…).
        //    Match par apiId → jamais de mauvaise ligue.
        if let url = await FootballAPIService.shared.fetchLeagueLogo(leagueId: competition.apiId) {
            logoURL = url
        } else if let url = await ImageFallbackService.shared.leagueBadge(name: name) {
            // 2) REPLI : TheSportsDB par nom (badge communautaire) si l'API n'a rien.
            logoURL = url
        }
        // Le fond d'ambiance est désormais le motif procédural (CompetitionPatternView),
        // plus aucune photo distante à résoudre ici.
    }
}

// Mélange deux couleurs (pour assombrir/éclaircir une teinte) via composants RGB.
extension Color {
    func blended(with other: Color, amount: Double) -> Color {
        let a = max(0, min(1, amount))
        let c1 = UIColor(self).rgbaComponents
        let c2 = UIColor(other).rgbaComponents
        return Color(
            red:   c1.r * (1 - a) + c2.r * a,
            green: c1.g * (1 - a) + c2.g * a,
            blue:  c1.b * (1 - a) + c2.b * a
        )
    }
}

private extension UIColor {
    var rgbaComponents: (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }
}
