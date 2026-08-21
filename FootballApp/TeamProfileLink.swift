import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// NAVIGATION RÉUTILISABLE VERS LA FICHE CLUB
// -----------------------------------------------------------------------------
// La plupart des écrans (classement, résultats, journées, buteurs) ne disposent
// que d'un `AFTeam` léger (id / name / logo), alors que `TeamProfileView` attend
// un `AFTeamInfo` riche (pays, fondation, stade…).
//
// Plutôt que de fabriquer un `AFTeamInfo` partiel (pays/fondation à nil), on
// ROUVRE la fiche via son ID : `TeamProfileLoaderView` recharge l'`AFTeamInfo`
// complet avec `fetchTeamInfo(teamId:)` UNIQUEMENT quand l'utilisateur ouvre la
// fiche — jamais à l'affichage d'une liste (économie de quota API). L'id vient
// toujours de l'API (jamais inventé) : conforme à la règle anti-hallucination.
// ─────────────────────────────────────────────────────────────────────────────

/// Écran-tampon : reçoit un `teamId` réel, recharge l'`AFTeamInfo` complet, puis
/// affiche `TeamProfileView`. Pendant le chargement, on montre un en-tête léger
/// (logo + nom) construit à partir de ce qu'on connaît déjà, pour éviter un flash.
struct TeamProfileLoaderView: View {
    let teamId: Int
    /// Nom/logo déjà connus de l'écran appelant (affichage transitoire uniquement).
    var previewName: String = ""
    var previewLogo: String? = nil

    @State private var team: AFTeamInfo?
    @State private var failed = false

    var body: some View {
        Group {
            if let team {
                TeamProfileView(team: team)
            } else if failed {
                // Repli gracieux : on ouvre quand même la fiche avec ce qu'on a,
                // la fiche rechargera ses données par ID de son côté.
                TeamProfileView(team: AFTeamInfo(
                    id: teamId, name: previewName, code: nil,
                    country: nil, founded: nil, national: nil, logo: previewLogo))
            } else {
                VStack(spacing: 14) {
                    TeamLogoView(urlString: previewLogo, name: previewName, size: 64, teamId: teamId)
                    if !previewName.isEmpty {
                        Text(TeamNameFormatter.pretty(previewName))
                            .font(.headline).foregroundColor(Theme.text)
                    }
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg.ignoresSafeArea())
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard team == nil, !failed else { return }
        if let info = try? await FootballAPIService.shared.fetchTeamInfo(teamId: teamId) {
            team = info
        } else {
            failed = true
        }
    }
}

/// `NavigationLink` prêt à l'emploi vers la fiche club, pour les écrans où TOUTE
/// la ligne doit ouvrir le club (classement, buteurs quand on tape le club…).
/// Fournir le contenu de la ligne dans `label`.
struct TeamProfileLink<Label: View>: View {
    let teamId: Int
    var previewName: String = ""
    var previewLogo: String? = nil
    @ViewBuilder var label: () -> Label

    var body: some View {
        NavigationLink {
            TeamProfileLoaderView(teamId: teamId,
                                  previewName: previewName,
                                  previewLogo: previewLogo)
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }
}

/// Zone tappable vers la fiche club à utiliser À L'INTÉRIEUR d'une ligne qui est
/// DÉJÀ un `NavigationLink` parent (résultats, journées → la ligne ouvre le match).
/// Règle « Ligne = match, logos = club » : un `NavigationLink` imbriqué est interdit
/// en SwiftUI ; on passe donc par un lien programmatique masqué déclenché par un
/// `Button` (le bouton consomme le tap avant le lien parent).
struct TeamTapTarget<Content: View>: View {
    let teamId: Int
    var previewName: String = ""
    var previewLogo: String? = nil
    @ViewBuilder var content: () -> Content

    @State private var isActive = false

    var body: some View {
        // Le bouton visible : consomme le tap et déclenche la navigation
        // programmatique, sans propager au NavigationLink parent (le match).
        Button {
            isActive = true
        } label: {
            content()
        }
        .buttonStyle(.plain)
        // Navigation programmatique (API iOS 16+, remplace NavigationLink(isActive:)).
        .navigationDestination(isPresented: $isActive) {
            TeamProfileLoaderView(teamId: teamId,
                                  previewName: previewName,
                                  previewLogo: previewLogo)
        }
    }
}
