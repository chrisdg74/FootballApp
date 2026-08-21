import SwiftUI

// ═════════════════════════════════════════════════════════════════════════════
// DESIGN SYSTEM — « STADE NOCTURNE »
// ─────────────────────────────────────────────────────────────────────────────
// Palette sombre premium, épurée, façon appli sport moderne (FotMob / OneFootball).
// Aucune image décorative : le « waow » vient de la typographie, de l'espace,
// de la couleur d'accent par compétition et des micro-animations.
//
// Tout est centralisé ici. Pour ajuster l'identité visuelle de toute l'app,
// il suffit de modifier les constantes de `Theme`.
// ═════════════════════════════════════════════════════════════════════════════

enum Theme {

    // ── Couleurs adaptatives (clair / sombre) ─────────────────────────────────
    // L'app suit le thème système. Chaque token renvoie une couleur différente en
    // mode clair et en mode sombre, pour que le texte reste TOUJOURS lisible
    // (piège corrigé 2026-08-13 : palette figée en blanc → texte invisible sur le
    // fond blanc du mode clair). `light` = valeur en mode clair, `dark` = en sombre.
    private static func adaptive(light: (CGFloat, CGFloat, CGFloat, CGFloat),
                                 dark: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
        Color(UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
    }

    // ── Fonds (du plus profond au plus clair) ────────────────────────────────
    /// Fond général de l'app.
    static let bg        = adaptive(light: (0.96, 0.97, 0.98, 1), dark: (0.05, 0.06, 0.09, 1))
    /// Surface d'une carte / cellule posée sur le fond.
    static let surface   = adaptive(light: (1.00, 1.00, 1.00, 1), dark: (0.09, 0.10, 0.14, 1))
    /// Surface surélevée (sélection, en-tête de section).
    static let surface2  = adaptive(light: (0.92, 0.93, 0.95, 1), dark: (0.13, 0.15, 0.20, 1))
    /// Trait de séparation discret.
    static let hairline  = adaptive(light: (0.00, 0.00, 0.00, 0.10), dark: (1, 1, 1, 0.08))

    // ── Texte ────────────────────────────────────────────────────────────────
    static let text      = adaptive(light: (0.06, 0.07, 0.10, 1),   dark: (1, 1, 1, 1))
    static let textSoft  = adaptive(light: (0.30, 0.32, 0.38, 1),   dark: (1, 1, 1, 0.62))
    static let textFaint = adaptive(light: (0.55, 0.57, 0.62, 1),   dark: (1, 1, 1, 0.38))

    // ── Marque / navigation (bleu nuit → cyan) ───────────────────────────────
    // Couleur d'identité pour la navigation (menus, pilules, sélections). Le
    // ROUGE reste réservé exclusivement à l'état « live ». Esprit broadcast TV.
    static let brand     = Color(red: 0.055, green: 0.65, blue: 0.91)  // cyan #0EA5E9
    static let brandDeep = Color(red: 0.12, green: 0.23, blue: 0.54)   // bleu nuit #1E3A8A
    /// Dégradé de marque (bleu nuit → cyan) pour les pilules de navigation.
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [brandDeep, brand],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// Teinte claire pour les puces secondaires sélectionnées (sous-filtres).
    static let brandSoft = Color(red: 0.055, green: 0.65, blue: 0.91).opacity(0.14)

    // ── Accents fonctionnels ─────────────────────────────────────────────────
    static let live      = Color(red: 1.00, green: 0.23, blue: 0.28)   // rouge live
    static let win       = Color(red: 0.20, green: 0.80, blue: 0.45)   // positif / qualif
    static let lose      = Color(red: 1.00, green: 0.36, blue: 0.36)   // négatif / relégation
    static let gold      = Color(red: 1.00, green: 0.78, blue: 0.20)   // 1re place
    static let silver    = Color(red: 0.78, green: 0.80, blue: 0.86)
    static let bronze    = Color(red: 0.80, green: 0.52, blue: 0.30)

    // ── Rayons & espacements ─────────────────────────────────────────────────
    static let radius: CGFloat     = 16
    static let radiusSmall: CGFloat = 10
}

// ─────────────────────────────────────────────────────────────────────────────
// Typographie — chiffres alignés (tabular) pour les scores et stats
// ─────────────────────────────────────────────────────────────────────────────
extension Font {
    /// Gros score central (34pt, gras, chiffres à largeur fixe).
    static var scoreBig: Font   { .system(size: 34, weight: .bold, design: .rounded).monospacedDigit() }
    /// Score de cellule de match.
    static var scoreRow: Font   { .system(size: 17, weight: .bold, design: .rounded).monospacedDigit() }
    /// Chiffres de tableau (points, stats) alignés.
    static var statNum: Font    { .system(size: 13, weight: .semibold, design: .rounded).monospacedDigit() }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modificateurs réutilisables
// ─────────────────────────────────────────────────────────────────────────────

/// Style « carte » sombre standard.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 14
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 14) -> some View { modifier(CardStyle(padding: padding)) }

    /// Applique le fond général « stade nocturne » derrière la vue, bord à bord.
    func nightBackground() -> some View {
        background(Theme.bg.ignoresSafeArea())
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Indicateur LIVE qui pulse — la signature visuelle de l'app
// ─────────────────────────────────────────────────────────────────────────────
struct LivePulseDot: View {
    var size: CGFloat = 8
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.live.opacity(0.35))
                .frame(width: size * 2.2, height: size * 2.2)
                .scaleEffect(animate ? 1.0 : 0.4)
                .opacity(animate ? 0 : 0.9)
            Circle()
                .fill(Theme.live)
                .frame(width: size, height: size)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.1).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// Petit badge « LIVE 67' » cohérent partout.
struct LiveBadge: View {
    var minute: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            LivePulseDot(size: 6)
            Text(minute.map { "LIVE \($0)" } ?? "LIVE")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.live)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Theme.live.opacity(0.14))
        .clipShape(Capsule())
    }
}
