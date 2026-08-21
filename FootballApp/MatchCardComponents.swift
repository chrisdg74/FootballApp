import SwiftUI

// ═════════════════════════════════════════════════════════════════════════════
// COMPOSANT UNIQUE DE CARTE MATCH — identité visuelle partagée (Accueil + Live)
// ─────────────────────────────────────────────────────────────────────────────
// Choix user 2026-08-19 : « il doit y avoir une identité visuelle forte pour se
// sentir dans une appli fluide et professionnelle. Design, qualité et consistance
// sont les maîtres mots. » Décisions validées (AskUserQuestion) :
//   1) UN SEUL composant de ligne réutilisé PARTOUT ;
//   2) regroupement PAR JOUR : en-tête de date gris + carte blanche arrondie +
//      fins séparateurs entre les lignes ;
//   3) même gabarit de ligne pour les deux états — à venir → HEURE au centre ;
//      terminé/en direct → SCORE au centre.
//
// Deux briques :
//   • `MatchRowView`          → la ligne « nom · logo · heure|score · logo · nom »
//                               + chevron, tappable vers la fiche match.
//   • `DayGroupedFixturesView`→ conteneur qui regroupe une liste de matchs par
//                               jour (en-tête gris) dans des cartes blanches.
//
// Aucune donnée inventée : tout provient d'`AFFixture`. Les logos passent par
// `TeamLogoView`, les noms par `AFTeam.displayName` (déjà localisé).
// ═════════════════════════════════════════════════════════════════════════════

// MARK: - Ligne de match unifiée

/// Ligne réutilisable : `nom · logo` (domicile) · bloc central (heure ou score) ·
/// `logo · nom` (extérieur) · chevron. Le bloc central s'adapte au statut :
///   • à venir     → l'HEURE (« 20:45 »), éventuellement précédée d'un « • » si
///                   la ligne est isolée hors regroupement par jour ;
///   • en direct   → le SCORE en couleur `Theme.live` + la minute (« 63' ») ;
///   • terminé     → le SCORE + « Terminé ».
/// Le gabarit est STRICTEMENT identique dans les trois cas (mêmes largeurs de
/// colonnes) pour une grille visuelle régulière.
struct MatchRowView: View {
    let fixture: AFFixture

    /// Quand la ligne vit DÉJÀ sous un en-tête de date (regroupement par jour), on
    /// n'affiche que l'HEURE pour un match à venir (pas de date redondante).
    var showsDateHeader: Bool = true

    /// Optionnel : met en gras l'équipe correspondant à cet id (favori mis en avant).
    var highlightTeamId: Int? = nil

    private var homeGoals: String {
        if fixture.isFinished || fixture.isLive, let h = fixture.goals.home { return "\(h)" }
        return "–"
    }
    private var awayGoals: String {
        if fixture.isFinished || fixture.isLive, let a = fixture.goals.away { return "\(a)" }
        return "–"
    }
    private var homeWon: Bool {
        guard fixture.isFinished, let h = fixture.goals.home, let a = fixture.goals.away else { return false }
        return h > a
    }
    private var awayWon: Bool {
        guard fixture.isFinished, let h = fixture.goals.home, let a = fixture.goals.away else { return false }
        return a > h
    }

    /// Une équipe est « soulignée » si elle a gagné OU si c'est le favori mis en avant.
    private func emphasize(_ teamId: Int, won: Bool) -> Bool {
        if let hl = highlightTeamId, hl == teamId { return true }
        return won
    }

    var body: some View {
        HStack(spacing: 10) {
            // Domicile : nom (aligné à droite) puis logo, collés au centre.
            TeamTapTarget(teamId: fixture.teams.home.id,
                          previewName: fixture.teams.home.name,
                          previewLogo: fixture.teams.home.logo) {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text(fixture.teams.home.displayName)
                        .font(.system(size: 14, weight: emphasize(fixture.teams.home.id, won: homeWon) ? .semibold : .regular))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    TeamLogoView(urlString: fixture.teams.home.logo,
                                 name: fixture.teams.home.name,
                                 size: 24, teamId: fixture.teams.home.id)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Bloc central : heure (à venir) ou score (terminé / en direct).
            centerColumn
                .frame(width: 76)

            // Extérieur : logo puis nom, collés au centre.
            TeamTapTarget(teamId: fixture.teams.away.id,
                          previewName: fixture.teams.away.name,
                          previewLogo: fixture.teams.away.logo) {
                HStack(spacing: 8) {
                    TeamLogoView(urlString: fixture.teams.away.logo,
                                 name: fixture.teams.away.name,
                                 size: 24, teamId: fixture.teams.away.id)
                    Text(fixture.teams.away.displayName)
                        .font(.system(size: 14, weight: emphasize(fixture.teams.away.id, won: awayWon) ? .semibold : .regular))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textFaint)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var centerColumn: some View {
        if fixture.isLive {
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    Text(homeGoals)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.live)
                    Text("–")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.textFaint)
                    Text(awayGoals)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(Theme.live)
                }
                LiveBadge(minute: fixture.fixture.status.elapsed.map { "\($0)'" })
            }
        } else if fixture.isFinished {
            VStack(spacing: 2) {
                HStack(spacing: 5) {
                    Text(homeGoals)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(homeWon ? Theme.text : Theme.textSoft)
                    Text("–")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(Theme.textFaint)
                    Text(awayGoals)
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                        .foregroundColor(awayWon ? Theme.text : Theme.textSoft)
                }
                Text(L("status.finished"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textFaint)
            }
        } else {
            // À venir : heure (regroupé par jour) ou statut complet (isolé).
            Text(showsDateHeader ? fixture.timeOnlyLabel : fixture.statusLabel)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(fixture.fixture.status.short == "PST" ? .orange : Theme.textSoft)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Vignette photo de joueur (remplit une tuile carrée arrondie)

/// Photo de joueur cadrée pour REMPLIR une tuile carrée arrondie (pas un cercle),
/// pour un rendu « premium » cohérent avec les logos de clubs dans les vignettes
/// de favoris (choix user 2026-08-19 : « idéal d'avoir une photo »).
///
/// Chaîne de repli identique à `PlayerAvatar` : photo API-Football en priorité,
/// sinon photo TheSportsDB résolue par NOM (`ImageFallbackService`), sinon —
/// en tout dernier recours — les initiales sur un fond teinté stable.
struct PlayerVignette: View {
    let name: String
    let photo: String?
    var cornerRadius: CGFloat = 16

    @State private var attempt = 0
    @State private var fallbackURL: URL? = nil
    @State private var didTryFallback = false

    private var primaryMissing: Bool { (photo?.isEmpty ?? true) }

    private var effectiveURL: URL? {
        if let s = photo, !s.isEmpty, let url = URL(string: s) { return url }
        return fallbackURL
    }

    /// Initiales (repli ultime) : 1re + dernière lettre significative.
    private var initials: String {
        let words = name.replacingOccurrences(of: ".", with: " ")
            .split(separator: " ").map(String.init)
            .filter { $0.count > 1 || $0.first?.isLetter == true }
        let letters = words.compactMap { $0.first }.map { String($0).uppercased() }
        if letters.count >= 2 { return letters.first! + letters.last! }
        return letters.first ?? "?"
    }

    private var tint: Color {
        let hash = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Color(hue: Double(hash % 360) / 360.0, saturation: 0.45, brightness: 0.75)
    }

    private var placeholder: some View {
        ZStack {
            tint.opacity(0.22)
            Text(initials)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(tint)
        }
    }

    var body: some View {
        Group {
            if let url = effectiveURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        placeholder.onAppear {
                            if attempt < 2 {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { attempt += 1 }
                            } else if !didTryFallback {
                                didTryFallback = true
                                Task { fallbackURL = await ImageFallbackService.shared.playerPhoto(name: name) }
                            }
                        }
                    case .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
                .id(attempt)
            } else {
                placeholder
            }
        }
        // Remplit la tuile (recadrage centré) puis clip en carré arrondi.
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: primaryMissing) {
            guard primaryMissing, !didTryFallback else { return }
            didTryFallback = true
            fallbackURL = await ImageFallbackService.shared.playerPhoto(name: name)
        }
    }
}

// MARK: - Regroupement par jour (en-tête gris + carte blanche)

/// Regroupe une liste de matchs par JOUR et les présente dans le style de la
/// référence : au-dessus de chaque groupe, un en-tête de date discret
/// (« Vendredi 21 Août 2026 ») ; en dessous, une carte blanche arrondie
/// contenant les lignes `MatchRowView` séparées par de fins traits.
///
/// Chaque ligne est un `NavigationLink` vers la fiche du match. Convient à un
/// `ScrollView`/`LazyVStack` (contrairement à un `List`), donc réutilisable dans
/// l'Accueil comme dans le Live.
struct DayGroupedFixturesView: View {
    let fixtures: [AFFixture]

    /// Id d'équipe à mettre en avant (favori), propagé à chaque ligne.
    var highlightTeamId: Int? = nil

    /// Regroupement par section de date, trié chronologiquement.
    private var grouped: [(String, [AFFixture])] {
        var g: [String: [AFFixture]] = [:]
        for m in fixtures { g[m.formattedDateSection, default: []].append(m) }
        return g.sorted { a, b in
            let da = fixtures.first { $0.formattedDateSection == a.0 }?.isoDate
            let db = fixtures.first { $0.formattedDateSection == b.0 }?.isoDate
            if let x = da, let y = db { return x < y }
            return a.0 < b.0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(grouped, id: \.0) { (date, day) in
                VStack(alignment: .leading, spacing: 8) {
                    // En-tête de date discret.
                    Text(date)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textSoft)
                        .padding(.horizontal, 4)

                    // Carte blanche : lignes + fins séparateurs.
                    VStack(spacing: 0) {
                        ForEach(Array(day.enumerated()), id: \.element.id) { (idx, f) in
                            NavigationLink(destination: MatchDetailView(fixture: f)) {
                                MatchRowView(fixture: f,
                                             showsDateHeader: true,
                                             highlightTeamId: highlightTeamId)
                                    .padding(.horizontal, 12)
                            }
                            .buttonStyle(.plain)

                            if idx < day.count - 1 {
                                Divider()
                                    .overlay(Theme.hairline)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .fill(Theme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                            .stroke(Theme.hairline, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
                }
            }
        }
    }
}
