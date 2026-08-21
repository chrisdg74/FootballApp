import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// BANNIÈRE DE COMPÉTITION — visuel PAYSAGE contextualisé, réutilisable
// -----------------------------------------------------------------------------
// Objectif (demande user 2026-08-16) : « une photo qui représente chaque
// compétition, dans le même format, avec le fond de la compétition en fondu
// (Ligue 1 en bleu par ex. et une photo de Ligue 1 en fondu) », affichée PARTOUT
// (en-tête de fiche — déjà fait dans CompetitionDetailView —, vignettes du hub,
// et en-têtes de groupe dans le Live).
//
// Couches (du fond vers l'avant) :
//   1. PHOTO d'ambiance RÉELLE de la compétition (fanart/bannière TheSportsDB),
//      résolue par NOM une seule fois via `ImageFallbackService.leagueBanner`
//      (mémorisée → 1 appel réseau max par compétition pour toute l'app).
//      Affichée seulement si elle se charge → jamais de placeholder trompeur.
//   2. DÉGRADÉ de la compétition PAR-DESSUS la photo (semi-opaque s'il y a une
//      photo, plein sinon) → couleur contextualisée (Ligue 1 bleu…) + lisibilité
//      garantie du texte blanc quelle que soit la photo. C'est aussi le REPLI :
//      si aucune photo, on voit un beau dégradé coloré, jamais un trou.
//   3. Logo officiel (API-Football puis TheSportsDB) OU monogramme `shortName`.
//   4. Nom (+ sous-titre optionnel) de la compétition, blanc, lisible.
//
// Aucune donnée inventée : photo et logo viennent de sources réelles ou ne sont
// pas affichés ; le monogramme est le `shortName` du catalogue.
// ─────────────────────────────────────────────────────────────────────────────
struct CompetitionBannerView: View {
    let competition: Competition

    /// Hauteur de la bannière (paysage). 64 ≈ vignette de liste, 118 ≈ en-tête.
    var height: CGFloat = 72
    /// Coins arrondis de la carte.
    var cornerRadius: CGFloat = 16
    /// Affiche le sous-titre de la compétition sous le nom.
    var showsSubtitle: Bool = true
    /// Taille du logo/monogramme à gauche.
    var logoSize: CGFloat = 40

    @State private var logoURL: URL?
    @State private var didResolve = false

    var body: some View {
        ZStack(alignment: .leading) {
            background

            HStack(spacing: 12) {
                logoBadge

                VStack(alignment: .leading, spacing: 2) {
                    // Drapeau JUSTE AVANT le nom (choix user 2026-08-17), plutôt qu'à
                    // l'extrémité droite de la bannière.
                    HStack(spacing: 6) {
                        if let flag = flagEmoji {
                            Text(flag)
                                .font(.system(size: 18))
                                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                        }
                        Text(L(competition.nameKey))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    }

                    if showsSubtitle {
                        Text(L(competition.subtitleKey))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .task(id: competition.id) { await resolve() }
    }

    // ── Fond : PHOTO d'ambiance embarquée (style Premier League) OU dégradé+motif ─
    private var background: some View {
        ZStack {
            if let photo = competition.assetPhoto {
                // ── Bannière « photo » (ex. Ligue 2) ────────────────────────────
                // 1. La PHOTO d'ambiance embarquée, recadrée pour remplir la bannière.
                Image(photo)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                // 2. Dégradé de la compétition PAR-DESSUS, semi-opaque : contextualise
                //    la couleur (Ligue 2 orange…) ET garantit la lisibilité du texte
                //    blanc quelle que soit la photo. Plus soutenu à gauche (sous le
                //    logo/texte), plus transparent à droite (on voit la photo).
                LinearGradient(
                    colors: [
                        competition.color.opacity(0.86),
                        competition.color.opacity(0.45),
                        Color.black.opacity(0.30)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                // 3. Léger assombrissement bas → texte toujours net.
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.28)],
                    startPoint: .top, endPoint: .bottom
                )
            } else {
                // ── Bannière « dégradé + motif » (comportement par défaut) ──────
                // 1. Dégradé plein de la compétition (Ligue 1 en bleu, LaLiga en rouge…).
                competition.gradient
                // 2. Motif d'ambiance dessiné en code, teinté par le type de compétition
                //    (terrain / fanions / projecteurs / orbites). Donne l'identité
                //    « contextualisée » demandée, sans photo distante ni droits d'image.
                CompetitionPatternView(competition: competition,
                                       cornerRadius: cornerRadius,
                                       intensity: 1.0)
                // 3. Léger assombrissement du bas → texte toujours lisible.
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.18)],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .clipped()
    }

    // ── Logo (réel) ou monogramme (repli) ────────────────────────────────────────
    // Rendu UNIFORME pour TOUTES les compétitions : logo (embarqué OU distant)
    // affiché EN ENTIER, jamais rogné, sur une carte blanche arrondie nette.
    private var logoBadge: some View {
        ZStack {
            if let asset = competition.assetLogo {
                // CAS 1 : logo EMBARQUÉ (divisions françaises…).
                logoCard { anyLogoImage(Image(asset)) }
            } else if let url = logoURL {
                // CAS 2 : logo OFFICIEL DISTANT (API-Football / TheSportsDB).
                logoCard {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            anyLogoImage(image)
                        default:
                            monogram
                        }
                    }
                }
            } else {
                // CAS 3 : monogramme de repli sur pastille claire.
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: logoSize, height: logoSize)
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    monogram
                }
            }
        }
        .frame(width: logoSize, height: logoSize)
    }

    // ── Carte blanche arrondie contenant un logo ENTIER ──────────────────────────
    private func logoCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        RoundedRectangle(cornerRadius: logoSize * 0.28, style: .continuous)
            .fill(Color.white)
            .frame(width: logoSize, height: logoSize)
            .overlay(content().padding(logoSize * 0.12))
            .overlay(
                RoundedRectangle(cornerRadius: logoSize * 0.28, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }

    // ── Rendu haute qualité d'un logo, JAMAIS rogné ──────────────────────────────
    private func anyLogoImage(_ image: Image) -> some View {
        image
            .resizable()
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
    }

    private var monogram: some View {
        Text(competition.shortName)
            .font(.system(size: logoSize * 0.34, weight: .heavy, design: .rounded))
            .foregroundColor(competition.color)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(.horizontal, logoSize * 0.08)
    }

    private var flagEmoji: String? {
        guard let code = competition.countryCode?.trimmingCharacters(in: .whitespaces),
              !code.isEmpty else { return nil }
        return code
    }

    private func resolve() async {
        guard !didResolve else { return }
        didResolve = true

        // Logo EMBARQUÉ fourni par nous → prioritaire, aucun appel réseau.
        if competition.assetLogo != nil { return }

        let name = L(competition.nameKey)

        // Logo : API-Football (fiable, par ID) puis TheSportsDB (par nom).
        if let url = await FootballAPIService.shared.fetchLeagueLogo(leagueId: competition.apiId) {
            logoURL = url
        } else if let url = await ImageFallbackService.shared.leagueBadge(name: name) {
            logoURL = url
        }
        // Le fond d'ambiance est désormais le motif procédural (CompetitionPatternView) ;
        // plus aucune photo distante à résoudre ici.
    }
}
