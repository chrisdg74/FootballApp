import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// MOTIF PROCÉDURAL DE COMPÉTITION — visuel d'ambiance 100% dessiné en code
// -----------------------------------------------------------------------------
// Remplace les « photos d'ambiance » (qu'on ne peut pas embarquer sans droits ni
// dépendre de TheSportsDB, souvent vide). À la place : un motif graphique abstrait
// dessiné à la volée, TEINTÉ par `competition.color`, et DISTINCT selon le TYPE de
// compétition (`kind`) pour que chaque famille ait sa propre identité visuelle :
//
//   • .league        → lignes de terrain + rond central (un championnat)
//   • .leagueGroups   → grille de fanions (évoque plusieurs poules : N1, N2…)
//   • .cup            → éventail de projecteurs de stade (soirée de coupe)
//   • .mixed          → orbites + étoiles (prestige Europe / Coupe du Monde)
//
// AVANTAGES : aucun fichier à gérer, aucun droit d'image, cohérent partout, et le
// motif suit AUTOMATIQUEMENT la couleur de chaque compétition. Aucune donnée
// inventée : c'est purement décoratif (jamais un logo ni un stade réel simulé).
//
// USAGE : à placer en overlay AU-DESSUS du dégradé de fond et EN DESSOUS du logo /
// du texte. Il se clippe lui-même à `cornerRadius` fourni. Opacité déjà calibrée
// pour rester discret (le texte blanc et le logo restent parfaitement lisibles).
// ─────────────────────────────────────────────────────────────────────────────
struct CompetitionPatternView: View {
    let competition: Competition
    /// Rayon d'arrondi du clip (doit matcher la carte hôte). 0 possible.
    var cornerRadius: CGFloat = 16
    /// Intensité globale du motif (0…1). Plus bas dans les petites vignettes.
    var intensity: Double = 1.0

    private var tint: Color { competition.color }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                switch competition.kind {
                case .league:       fieldPattern(in: size)
                case .leagueGroups: pennantsPattern(in: size)
                case .cup:          floodlightPattern(in: size)
                case .mixed:        orbitPattern(in: size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    // ── .league : lignes de terrain + rond central ──────────────────────────────
    // Évoque un terrain vu de côté : ligne médiane, rond central, arcs de surface.
    // Traits blancs très discrets → « ambiance stade » sans jamais gêner la lecture.
    private func fieldPattern(in size: CGSize) -> some View {
        let stroke = Color.white.opacity(0.12 * intensity)
        let w = size.width, h = size.height
        return ZStack {
            // Bandes horizontales de pelouse (alternance très légère).
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { i in
                    Rectangle()
                        .fill(Color.white.opacity((i % 2 == 0 ? 0.05 : 0.0) * intensity))
                }
            }
            // Ligne médiane verticale + rond central.
            Path { p in
                p.move(to: CGPoint(x: w * 0.5, y: 0))
                p.addLine(to: CGPoint(x: w * 0.5, y: h))
            }
            .stroke(stroke, lineWidth: 1)
            Circle()
                .stroke(stroke, lineWidth: 1)
                .frame(width: h * 0.42, height: h * 0.42)
                .position(x: w * 0.5, y: h * 0.5)
            // Arc de surface à gauche (partiel, pour l'asymétrie « photo »).
            Circle()
                .stroke(stroke, lineWidth: 1)
                .frame(width: h * 0.7, height: h * 0.7)
                .position(x: 0, y: h * 0.5)
        }
    }

    // ── .leagueGroups : grille de fanions ───────────────────────────────────────
    // Rangée de triangles (fanions) → suggère plusieurs groupes/poules côte à côte.
    private func pennantsPattern(in size: CGSize) -> some View {
        let w = size.width, h = size.height
        let count = max(6, Int(w / 26))
        let step = w / CGFloat(count)
        return ZStack {
            ForEach(0..<count, id: \.self) { i in
                Triangle()
                    .fill(Color.white.opacity((i % 2 == 0 ? 0.10 : 0.05) * intensity))
                    .frame(width: step * 0.8, height: h * 0.5)
                    .position(x: step * (CGFloat(i) + 0.5), y: h * 0.28)
            }
            // Fil suspendu (ligne fine en haut).
            Path { p in
                p.move(to: CGPoint(x: 0, y: h * 0.06))
                p.addLine(to: CGPoint(x: w, y: h * 0.06))
            }
            .stroke(Color.white.opacity(0.14 * intensity), lineWidth: 1)
        }
    }

    // ── .cup : éventail de projecteurs ──────────────────────────────────────────
    // Rayons partant du haut → « projecteurs de stade » d'une soirée de coupe.
    private func floodlightPattern(in size: CGSize) -> some View {
        let w = size.width, h = size.height
        let origin = CGPoint(x: w * 0.5, y: -h * 0.15)
        return ZStack {
            ForEach(0..<7, id: \.self) { i in
                Path { p in
                    let angle = Double(i) / 6.0 * .pi * 0.9 + .pi * 0.05
                    let len = h * 2.2
                    let dx = cos(angle) * len
                    let dy = sin(angle) * len
                    p.move(to: origin)
                    p.addLine(to: CGPoint(x: origin.x + dx - w * 0.5, y: origin.y + dy))
                    p.addLine(to: CGPoint(x: origin.x + dx - w * 0.5 + 10, y: origin.y + dy))
                    p.closeSubpath()
                }
                .fill(Color.white.opacity((i % 2 == 0 ? 0.07 : 0.03) * intensity))
            }
        }
    }

    // ── .mixed : orbites + étoiles ──────────────────────────────────────────────
    // Ellipses concentriques + petites étoiles → prestige Europe / Coupe du Monde.
    private func orbitPattern(in size: CGSize) -> some View {
        let w = size.width, h = size.height
        let center = CGPoint(x: w * 0.78, y: h * 0.5)
        return ZStack {
            ForEach(0..<3, id: \.self) { i in
                Ellipse()
                    .stroke(Color.white.opacity(0.10 * intensity), lineWidth: 1)
                    .frame(width: h * (1.0 + Double(i) * 0.6),
                           height: h * (0.6 + Double(i) * 0.35))
                    .position(center)
            }
            ForEach(0..<5, id: \.self) { i in
                Star(points: 5)
                    .fill(Color.white.opacity((i % 2 == 0 ? 0.16 : 0.09) * intensity))
                    .frame(width: h * 0.16, height: h * 0.16)
                    .position(x: w * (0.12 + Double(i) * 0.14),
                              y: h * (0.28 + Double(i % 2) * 0.42))
            }
        }
    }
}

// ── Formes utilitaires ────────────────────────────────────────────────────────

/// Triangle isocèle pointe en bas (fanion).
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Étoile à N branches (décor « prestige »).
private struct Star: Shape {
    var points: Int = 5
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.42
        var p = Path()
        let total = points * 2
        for i in 0..<total {
            let radius = i.isMultiple(of: 2) ? outer : inner
            let angle = Double(i) / Double(total) * 2 * .pi - .pi / 2
            let pt = CGPoint(x: center.x + CGFloat(cos(angle)) * radius,
                             y: center.y + CGFloat(sin(angle)) * radius)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}
