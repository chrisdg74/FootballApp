//
//  Icons.swift
//  FootballApp
//
//  Icônes vectorielles maison (aucun logo/trophée officiel UEFA — formes génériques
//  « prestige »). Toutes teintables. Dessinées dans un repère 0…48 puis mises à
//  l'échelle via GeometryReader pour rester nettes à n'importe quelle taille.
//

import SwiftUI

// MARK: - Trophée (Variante A : coupe classique à anses)

/// Coupe classique dessinée en vectoriel, teintée par une couleur unique.
/// Utilisée pour représenter une compétition à trophée (Ligue des champions, etc.).
struct TrophyShape: View {
    /// Couleur principale (corps de la coupe). Le contour est une version assombrie.
    var color: Color = Color(red: 0.79, green: 0.64, blue: 0.15) // or par défaut

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 48.0
            let dark = color.opacity(0.85)
            ZStack {
                // Bol de la coupe
                CupBowl().fill(color)
                CupBowl().stroke(dark, lineWidth: 1 * s)
                // Anses
                LeftHandle().stroke(dark, style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
                RightHandle().stroke(dark, style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
                // Tige
                Rectangle().fill(dark)
                    .frame(width: 4 * s, height: 6 * s)
                    .position(x: 24 * s, y: 29 * s)
                // Socle (base évasée)
                CupBase().fill(color)
                CupBase().stroke(dark, lineWidth: 1 * s)
                // Pied
                RoundedRectangle(cornerRadius: 1.5 * s).fill(dark)
                    .frame(width: 20 * s, height: 3.5 * s)
                    .position(x: 24 * s, y: 38.75 * s)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // Sous-formes exprimées dans le repère 0…48 puis mises à l'échelle.
    private struct CupBowl: Shape {
        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height) / 48.0
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var path = Path()
            path.move(to: p(15, 8))
            path.addLine(to: p(33, 8))
            path.addLine(to: p(33, 14))
            path.addCurve(to: p(24, 26), control1: p(33, 21), control2: p(29, 26))
            path.addCurve(to: p(15, 14), control1: p(19, 26), control2: p(15, 21))
            path.closeSubpath()
            return path
        }
    }
    private struct LeftHandle: Shape {
        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height) / 48.0
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var path = Path()
            path.move(to: p(15, 10))
            path.addCurve(to: p(8, 16), control1: p(10, 10), control2: p(8, 13))
            path.addCurve(to: p(14, 21), control1: p(8, 19), control2: p(10, 21))
            return path
        }
    }
    private struct RightHandle: Shape {
        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height) / 48.0
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var path = Path()
            path.move(to: p(33, 10))
            path.addCurve(to: p(40, 16), control1: p(38, 10), control2: p(40, 13))
            path.addCurve(to: p(34, 21), control1: p(40, 19), control2: p(38, 21))
            return path
        }
    }
    private struct CupBase: Shape {
        func path(in rect: CGRect) -> Path {
            let s = min(rect.width, rect.height) / 48.0
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var path = Path()
            path.move(to: p(16, 32))
            path.addLine(to: p(32, 32))
            path.addLine(to: p(30, 37))
            path.addLine(to: p(18, 37))
            path.closeSubpath()
            return path
        }
    }
}

// MARK: - Badge de compétition

/// Pastille ronde d'une compétition : trophée teinté sur un disque de la couleur de
/// la compétition (fond très clair). Sert d'icône « prestige » pour les compétitions
/// européennes / internationales qui n'ont pas de drapeau national.
struct CompetitionTrophyBadge: View {
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.12))
            TrophyShape(color: color)
                .frame(width: size * 0.62, height: size * 0.62)
        }
        .frame(width: size, height: size)
    }
}

/// Icône d'une compétition : trophée teinté pour les compétitions « prestige »
/// (Europe / international), drapeau émoji sinon. Remplace l'affichage direct de
/// `competition.countryCode` afin d'unifier le style dans toute l'app.
struct CompetitionIcon: View {
    let competition: Competition
    var size: CGFloat = 30

    var body: some View {
        if competition.usesTrophyIcon {
            CompetitionTrophyBadge(color: competition.color, size: size)
        } else if let flag = competition.countryCode {
            Text(flag).font(.system(size: size))
        } else {
            CompetitionTrophyBadge(color: competition.color, size: size)
        }
    }
}
