import SwiftUI

// ═════════════════════════════════════════════════════════════════════════════
// JEU FANTASY — ÉCRANS
// ─────────────────────────────────────────────────────────────────────────────
// Écran principal : l'équipe de l'utilisateur (max 5 joueurs), son score total et
// son budget restant, plus un bouton pour ouvrir le sélecteur de joueurs.
// Sélecteur (feuille) : le vivier chargé via l'API, filtrable, avec ajout/retrait
// respectant le budget. Tout est LOCAL (FantasyStore, UserDefaults).
// ═════════════════════════════════════════════════════════════════════════════

struct FantasyView: View {
    @EnvironmentObject private var store: FantasyStore

    @State private var pool: [FantasyPlayer] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    scoreboard
                    squadSection
                    if store.isEmpty { emptyHint }
                }
                .padding(16)
            }
            .nightBackground()
            .navigationTitle(L("fantasy.title"))
            .task {
                // À chaque ouverture de l'onglet : on relit les vraies stats de
                // saison des joueurs de l'équipe → le score monte au fil des matchs.
                await store.refreshSquadStats()
            }
            .toolbar {
                if !store.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) { store.reset() } label: {
                            Image(systemName: "trash")
                        }
                        .tint(Theme.lose)
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                FantasyPickerView(pool: pool, isLoading: isLoading, errorMessage: errorMessage)
                    .environmentObject(store)
            }
        }
    }

    // ── Tableau de score (points + budget) ─────────────────────────────────────
    private var scoreboard: some View {
        HStack(spacing: 12) {
            statCard(value: "\(store.totalPoints)", label: L("fantasy.points"), tint: Theme.gold)
            statCard(value: "\(store.remaining)", label: L("fantasy.budgetLeft"),
                     tint: store.remaining >= 0 ? Theme.win : Theme.lose)
            statCard(value: "\(store.squad.count)/\(FantasyStore.squadSize)",
                     label: L("fantasy.squadCount"), tint: Theme.text)
        }
    }

    private func statCard(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(tint)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card(padding: 14)
    }

    // ── Mon équipe ───────────────────────────────────────────────────────────
    private var squadSection: some View {
        VStack(spacing: 10) {
            ForEach(store.squad) { player in
                FantasyPlayerRow(player: player, inSquad: true) {
                    store.remove(player.id)
                }
            }
            Button {
                showPicker = true
                Task { await loadPool() }   // charge le vivier au 1er clic (mis en cache ensuite)
            } label: {
                HStack {
                    if isLoading {
                        ProgressView().tint(Theme.live)
                    } else {
                        Image(systemName: "plus.circle.fill")
                    }
                    Text(store.isFull ? L("fantasy.editSquad") : L("fantasy.addPlayer"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.live.opacity(0.16))
                .foregroundColor(Theme.live)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
        }
    }

    private var emptyHint: some View {
        Text(L("fantasy.emptyHint"))
            .font(.subheadline)
            .foregroundColor(Theme.textSoft)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }

    // ── Chargement du vivier ────────────────────────────────────────────────────
    private func loadPool() async {
        guard pool.isEmpty else { return }
        isLoading = true; errorMessage = nil
        do {
            pool = try await FootballAPIService.shared.fetchFantasyPlayerPool()
            store.refreshSnapshot(from: pool)   // met à jour les stats de l'équipe
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ligne joueur réutilisable (équipe & sélecteur)
// ─────────────────────────────────────────────────────────────────────────────
struct FantasyPlayerRow: View {
    let player: FantasyPlayer
    /// true = affichage dans l'équipe (bouton retirer) ; false = dans le sélecteur.
    let inSquad: Bool
    /// Action du bouton de droite (retirer si dans l'équipe, ajouter sinon).
    var actionEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: player.photo.flatMap(URL.init)) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Theme.surface2)
            }
            .frame(width: 42, height: 42)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                Text(player.club)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSoft)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(player.points) \(L("fantasy.ptsShort"))")
                    .font(.statNum)
                    .foregroundColor(Theme.gold)
                Text("\(player.price) \(L("fantasy.creditsShort"))")
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundColor(Theme.textFaint)
            }

            Button(action: action) {
                Image(systemName: inSquad ? "minus.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(inSquad ? Theme.lose : (actionEnabled ? Theme.win : Theme.textFaint))
            }
            .disabled(!actionEnabled && !inSquad)
        }
        .card(padding: 10)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sélecteur de joueurs (feuille modale) — vivier filtrable, respect du budget
// ─────────────────────────────────────────────────────────────────────────────
struct FantasyPickerView: View {
    @EnvironmentObject private var store: FantasyStore
    @Environment(\.dismiss) private var dismiss

    let pool: [FantasyPlayer]
    let isLoading: Bool
    let errorMessage: String?

    @State private var query = ""
    /// Poste sélectionné dans le filtre ; nil = tous les postes.
    @State private var positionFilter: FantasyPosition?

    /// Postes réellement présents dans le vivier, dans l'ordre logique (G→D→M→A),
    /// pour ne pas afficher de chip vide. `.unknown` en dernier si présent.
    private var availablePositions: [FantasyPosition] {
        let present = Set(pool.map { $0.pos })
        return FantasyPosition.allCases.filter { present.contains($0) }
    }

    /// Vivier filtré (poste + recherche texte) PUIS trié par PRIX décroissant.
    private var filtered: [FantasyPlayer] {
        var list = pool
        if let pos = positionFilter {
            list = list.filter { $0.pos == pos }
        }
        if !query.isEmpty {
            let q = query.lowercased()
            list = list.filter { $0.name.lowercased().contains(q) || $0.club.lowercased().contains(q) }
        }
        // Tri : prix décroissant, puis points décroissants en cas d'égalité.
        return list.sorted {
            if $0.price != $1.price { return $0.price > $1.price }
            return $0.points > $1.points
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && pool.isEmpty {
                    ProgressView(L("loading")).frame(maxHeight: .infinity)
                } else if let err = errorMessage, pool.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle).foregroundColor(Theme.textFaint)
                        Text(err)
                            .font(.subheadline)
                            .foregroundColor(Theme.textSoft)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxHeight: .infinity)
                } else if pool.isEmpty {
                    // Ni chargement, ni erreur, mais 0 joueur : l'API n'a rien renvoyé
                    // (saison L1 pas encore peuplée, ou plan API sans /players).
                    VStack(spacing: 8) {
                        Image(systemName: "person.slash")
                            .font(.largeTitle).foregroundColor(Theme.textFaint)
                        Text(L("fantasy.noPlayers"))
                            .font(.subheadline)
                            .foregroundColor(Theme.textSoft)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                    .frame(maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        positionFilterBar
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(filtered) { player in
                                    let inSquad = store.contains(player.id)
                                    FantasyPlayerRow(
                                        player: player,
                                        inSquad: inSquad,
                                        actionEnabled: store.canAdd(player)
                                    ) {
                                        store.toggle(player)
                                    }
                                }
                            }
                            .padding(16)
                        }
                    }
                }
            }
            .nightBackground()
            .navigationTitle(L("fantasy.choosePlayers"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: L("fantasy.searchPlayer"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("fantasy.done")) { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text("\(store.remaining) \(L("fantasy.creditsShort")) · \(store.squad.count)/\(FantasyStore.squadSize)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(Theme.textSoft)
                }
            }
        }
    }

    // ── Barre de filtre par poste (chips défilables) ─────────────────────────
    private var positionFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                positionChip(title: L("filter.all"), isOn: positionFilter == nil) {
                    positionFilter = nil
                }
                ForEach(availablePositions) { pos in
                    positionChip(title: L(pos.titleKey), isOn: positionFilter == pos) {
                        positionFilter = (positionFilter == pos) ? nil : pos
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func positionChip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isOn ? Theme.live.opacity(0.22) : Theme.surface2)
                .foregroundColor(isOn ? Theme.live : Theme.textSoft)
                .clipShape(Capsule())
        }
    }
}
