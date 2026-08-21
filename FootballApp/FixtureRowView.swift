import SwiftUI

/// Ligne de match réutilisable dans toutes les vues
struct FixtureRowView: View {
    let fixture: AFFixture
    var showLeague: Bool = true
    /// Vrai quand la liste est DÉJÀ regroupée par date (en-tête de section = le jour).
    /// Dans ce cas, la ligne d'un match à venir n'affiche que l'HEURE, pas la date.
    var showsDateHeader: Bool = false

    /// Libellé de tour LOCALISÉ. Pour les journées de championnat/poule on garde
    /// le format court et informatif (« J5 », « Gr. J2 ») ; pour les tours à
    /// élimination on réutilise le vocabulaire canonique traduit de Phase.Key
    /// (« 16es », « Quart de finale », « Petite finale »…), au lieu de laisser
    /// l'anglais brut de l'API (« Round of 32 », « Quarter-finals »).
    static func roundLabel(_ raw: String) -> String {
        // Journées de saison régulière / poule : format court chiffré.
        if raw.contains("Regular Season - ") {
            return raw.replacingOccurrences(of: "Regular Season - ", with: "J")
        }
        if raw.contains("Group Stage - ") {
            return raw.replacingOccurrences(of: "Group Stage - ", with: "Gr. J")
        }
        // Tours à élimination : nom canonique traduit.
        let key = Phase.canonical(from: raw)
        if key == .groups {
            // Pas un vrai tour à élimination reconnu : on renvoie le libellé brut.
            return raw
        }
        return L(key.titleKey)
    }

    var homeGoals: String {
        if fixture.isFinished || fixture.isLive,
           let h = fixture.goals.home { return "\(h)" }
        return "–"
    }
    var awayGoals: String {
        if fixture.isFinished || fixture.isLive,
           let a = fixture.goals.away { return "\(a)" }
        return "–"
    }

    var homeWon: Bool {
        guard fixture.isFinished,
              let h = fixture.goals.home, let a = fixture.goals.away else { return false }
        return h > a
    }
    var awayWon: Bool {
        guard fixture.isFinished,
              let h = fixture.goals.home, let a = fixture.goals.away else { return false }
        return a > h
    }

    var body: some View {
        VStack(spacing: 4) {
            // Badge ligue + round (si demandé)
            if showLeague {
                HStack {
                    Text(CompetitionNameLocalizer.localized(fixture.league.name))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let round = fixture.league.round {
                        Text(Self.roundLabel(round))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                // Équipe domicile — tap sur logo+nom = fiche club (la ligne = match).
                TeamTapTarget(teamId: fixture.teams.home.id,
                              previewName: fixture.teams.home.name,
                              previewLogo: fixture.teams.home.logo) {
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        Text(fixture.teams.home.displayName)
                            .font(.caption)
                            .fontWeight(homeWon ? .bold : .regular)
                            .lineLimit(1)
                        TeamLogoView(urlString: fixture.teams.home.logo, name: fixture.teams.home.name, size: 20, teamId: fixture.teams.home.id)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                // Score / statut
                VStack(spacing: 2) {
                    if fixture.isFinished || fixture.isLive {
                        HStack(spacing: 6) {
                            Text(homeGoals)
                                .font(.scoreRow)
                                .foregroundColor(fixture.isLive ? Theme.live : (homeWon ? .primary : .secondary))
                            Text("–")
                                .font(.scoreRow)
                                .foregroundColor(.secondary)
                            Text(awayGoals)
                                .font(.scoreRow)
                                .foregroundColor(fixture.isLive ? Theme.live : (awayWon ? .primary : .secondary))
                        }
                        if fixture.isLive {
                            LiveBadge(minute: fixture.fixture.status.elapsed.map { "\($0)'" })
                        }
                    } else {
                        Text(showsDateHeader ? fixture.timeOnlyLabel : fixture.statusLabel)
                            .font(.caption)
                            .foregroundColor(fixture.fixture.status.short == "PST" ? .orange : .secondary)
                            .multilineTextAlignment(.center)
                            .frame(width: 70)
                    }
                }
                .frame(width: 84)

                // Équipe extérieur — tap sur logo+nom = fiche club (la ligne = match).
                TeamTapTarget(teamId: fixture.teams.away.id,
                              previewName: fixture.teams.away.name,
                              previewLogo: fixture.teams.away.logo) {
                    HStack(spacing: 6) {
                        TeamLogoView(urlString: fixture.teams.away.logo, name: fixture.teams.away.name, size: 20, teamId: fixture.teams.away.id)
                        Text(fixture.teams.away.displayName)
                            .font(.caption)
                            .fontWeight(awayWon ? .bold : .regular)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }
}
