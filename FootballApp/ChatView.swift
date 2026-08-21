import SwiftUI
import Combine

// ═════════════════════════════════════════════════════════════════════════════
// ÉCRAN DE CHAT DE L'ASSISTANT
// ─────────────────────────────────────────────────────────────────────────────
// Bulles user/assistant + champ de saisie. Chaque réponse peut porter des CARTES
// cliquables (fixtureRow, standingMini, scorerCard, teamCard) qui rechargent leur
// détail par ID et poussent vers les vraies vues de l'app (MatchDetailView,
// CompetitionDetailView, CompetitionScorersView).
// ═════════════════════════════════════════════════════════════════════════════

struct ChatView: View {
    @StateObject private var vm = ChatViewModel()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: AppRouter

    /// Identifiant de la sentinelle de fin de liste (cible du scroll auto).
    private let bottomAnchorID = "chat_bottom_anchor"

    /// Fait défiler jusqu'à la sentinelle de fin. Appelé deux fois (à l'ajout du
    /// message, puis quand les cartes ont leur hauteur finale) + un léger délai
    /// pour attendre que le LazyVStack et les logos async se posent.
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messagesArea
                inputBar
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(L("assistant.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("assistant.close")) { dismiss() }
                }
                // Effacer la conversation — visible seulement s'il y a des messages.
                if !vm.messages.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { vm.clear() }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(L("assistant.clear"))
                    }
                }
            }
            // Amorce pré-remplie depuis la page d'accueil (encart « Pose une
            // question ») : on injecte le texte dans le champ de saisie une seule
            // fois puis on le consomme (remis à nil) pour ne pas le rejouer.
            .onAppear {
                if let prefill = router.assistantPrefill, vm.input.isEmpty {
                    vm.input = prefill
                    router.assistantPrefill = nil
                }
            }
        }
    }

    // ── Zone des messages ─────────────────────────────────────────────────────
    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if vm.messages.isEmpty {
                        emptyState
                            .transition(.opacity)
                    }
                    ForEach(vm.messages) { message in
                        ChatMessageView(message: message) { prompt in
                            vm.retry(prompt: prompt)
                        }
                        .id(message.id)
                        // Apparition douce : fondu + léger glissement vers le haut.
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                    // Sentinelle invisible en toute fin de liste : c'est vers ELLE qu'on
                    // scrolle. Ancrer le bas d'une bulle plus haute que l'écran (parcours
                    // = 8 cartes) ne fonctionne pas ; viser un point de fin, oui.
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                }
                .padding(16)
                // Marge basse généreuse : la dernière carte + la sentinelle remontent
                // franchement au-dessus de la barre de saisie (ultraThinMaterial).
                .padding(.bottom, 90)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.messages.count)
            }
            .onChange(of: vm.messages.count) { scrollToBottom(proxy) }
            // Les cartes se chargent en LazyVStack (logos async) : leur hauteur finale
            // arrive après le premier layout. On re-scrolle une fois stabilisé.
            .onChange(of: vm.messages.last?.identifiedBlocks.count) { scrollToBottom(proxy) }
        }
    }

    // ── État vide : accueil épuré (pas de suggestions pré-remplies) ───────────
    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.live.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "sparkles")
                    .font(.system(size: 30))
                    .foregroundColor(Theme.live)
            }
            Text(L("assistant.greeting"))
                .font(.headline)
                .foregroundColor(Theme.text)
                .multilineTextAlignment(.center)
            Text(L("assistant.greetingHint"))
                .font(.subheadline)
                .foregroundColor(Theme.textSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.vertical, 8)
    }

    // ── Barre de saisie ───────────────────────────────────────────────────────
    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField(L("assistant.placeholder"), text: $vm.input, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                )
                .onSubmit { vm.send() }

            Button { vm.send() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(vm.canSend ? Theme.live : Theme.textFaint)
            }
            .disabled(!vm.canSend)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// UNE BULLE (+ ses cartes)
// ─────────────────────────────────────────────────────────────────────────────

struct ChatMessageView: View {
    let message: ChatMessage
    /// Appelé quand l'utilisateur tape « Réessayer » sur une bulle d'erreur.
    var onRetry: (String) -> Void = { _ in }

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Theme.live)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if message.isPending {
                    TypingIndicator()
                } else if message.isError {
                    errorBubble
                } else if !message.text.isEmpty {
                    Text(message.text)
                        .font(.subheadline)
                        .foregroundColor(Theme.text)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Theme.hairline, lineWidth: 1)
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Les cartes cliquables, dans l'ordre renvoyé par le proxy.
                ForEach(message.identifiedBlocks) { item in
                    ChatBlockView(block: item.block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // ── Bulle d'erreur : message clair + bouton « Réessayer » ─────────────────
    private var errorBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundColor(Theme.live)
                Text(message.text)
                    .font(.subheadline)
                    .foregroundColor(Theme.text)
            }
            if let prompt = message.retryPrompt {
                Button { onRetry(prompt) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text(L("assistant.retry"))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Theme.live)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.live.opacity(0.4), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Trois points animés pendant que l'assistant réfléchit.
struct TypingIndicator: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.textFaint)
                    .frame(width: 7, height: 7)
                    .opacity(phase == i ? 1 : 0.3)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}
