import SwiftUI

// ═════════════════════════════════════════════════════════════════════════════
// QUIZ LIGUE 1 — ÉCRAN DE JEU
// ─────────────────────────────────────────────────────────────────────────────
// Trois phases pilotées par `QuizGame` : accueil (intro + meilleur score), partie
// (question + 4 réponses + feedback couleur), fin (score + rejouer). Présenté en
// `fullScreenCover` depuis le bouton flottant et la carte d'accueil. Un bouton
// « Fermer » permet de quitter à tout moment (`onClose`).
// ═════════════════════════════════════════════════════════════════════════════

struct QuizView: View {
    /// Appelé quand l'utilisateur ferme le quiz (dépiler le fullScreenCover).
    var onClose: () -> Void

    @StateObject private var game = QuizGame()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().overlay(Theme.hairline)

                Group {
                    switch game.phase {
                    case .picking:  pickingScreen
                    case .intro:    introScreen
                    case .playing:  playingScreen
                    case .finished: finishedScreen
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // ── En-tête : (retour) + titre / championnat + fermer ────────────────────────
    private var header: some View {
        HStack(spacing: 10) {
            // Bouton retour vers le choix du championnat (hors écran de choix).
            if game.phase != .picking {
                Button { game.chooseLeague() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Theme.textSoft)
                }
                .accessibilityLabel(L("quiz.changeLeague"))
            }

            if let league = game.league, game.phase != .picking {
                Text("\(league.flag)  \(L(league.nameKey))")
                    .font(.headline)
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
            } else {
                Label(L("quiz.title"), systemImage: "gamecontroller.fill")
                    .font(.headline)
                    .foregroundColor(Theme.text)
            }

            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Theme.textFaint)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel(L("common.close"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // ── Écran de choix du championnat ────────────────────────────────────────────
    private var pickingScreen: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(L("quiz.pick.title"))
                    .font(.title2).fontWeight(.bold)
                    .foregroundColor(Theme.text)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                Text(L("quiz.pick.subtitle"))
                    .font(.subheadline)
                    .foregroundColor(Theme.textSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    ForEach(QuizLeague.allCases) { league in
                        leagueCard(league)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .padding(.bottom, 24)
        }
    }

    /// Carte cliquable d'un championnat (drapeau, nom, meilleur score).
    private func leagueCard(_ league: QuizLeague) -> some View {
        let best = QuizGame.bestScore(for: league)
        return Button {
            game.select(league)
        } label: {
            HStack(spacing: 14) {
                Text(league.flag)
                    .font(.system(size: 34))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L(league.nameKey))
                        .font(.headline)
                        .foregroundColor(Theme.text)
                    if best > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "trophy.fill")
                                .font(.caption2).foregroundColor(Theme.gold)
                            Text("\(L("quiz.bestScore")) \(best) / \(QuizGame.questionsPerRound)")
                                .font(.caption).foregroundColor(Theme.textSoft)
                        }
                    } else {
                        Text(L("quiz.notPlayed"))
                            .font(.caption).foregroundColor(Theme.textFaint)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textFaint)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // ── Accueil : présentation + meilleur score + jouer ──────────────────────────
    private var introScreen: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "sportscourt.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.brand)
            Text(L("quiz.intro.title"))
                .font(.title2).fontWeight(.bold)
                .foregroundColor(Theme.text)
                .multilineTextAlignment(.center)
            Text(L("quiz.intro.subtitle"))
                .font(.subheadline)
                .foregroundColor(Theme.textSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if game.bestScore > 0 {
                bestScorePill
            }

            Spacer()
            Button {
                game.start()
            } label: {
                Text(L("quiz.play"))
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Theme.brand))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private var bestScorePill: some View {
        HStack(spacing: 6) {
            Image(systemName: "trophy.fill").foregroundColor(Theme.gold)
            Text(L("quiz.bestScore"))
                .foregroundColor(Theme.textSoft)
            Text("\(game.bestScore) / \(QuizGame.questionsPerRound)")
                .fontWeight(.bold)
                .foregroundColor(Theme.text)
        }
        .font(.subheadline)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Capsule().fill(Theme.surface2))
    }

    // ── Partie en cours ──────────────────────────────────────────────────────────
    @ViewBuilder
    private var playingScreen: some View {
        if let q = game.currentQuestion {
            VStack(alignment: .leading, spacing: 20) {
                // Barre de progression + score courant.
                HStack {
                    Text(game.progressText)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(Theme.textSoft)
                    Spacer()
                    Text("\(game.score)")
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundColor(Theme.brand)
                    Image(systemName: "star.fill")
                        .font(.caption).foregroundColor(Theme.brand)
                }
                ProgressView(value: Double(game.currentIndex + 1),
                             total: Double(game.questions.count))
                    .tint(Theme.brand)

                Text(q.text)
                    .font(.title3).fontWeight(.semibold)
                    .foregroundColor(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                VStack(spacing: 12) {
                    ForEach(q.options.indices, id: \.self) { i in
                        answerButton(q: q, index: i)
                    }
                }

                Spacer()

                if game.hasAnswered {
                    Button {
                        game.next()
                    } label: {
                        Text(game.isLastQuestion ? L("quiz.seeResult") : L("quiz.nextQuestion"))
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Capsule().fill(Theme.brand))
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
            .animation(.easeInOut(duration: 0.2), value: game.selectedAnswer)
        }
    }

    /// Bouton d'une réponse. Couleur après réponse : vert = bonne, rouge = choix
    /// erroné, la bonne réponse reste soulignée en vert même si non choisie.
    @ViewBuilder
    private func answerButton(q: QuizQuestion, index: Int) -> some View {
        let answered = game.hasAnswered
        let isCorrect = index == q.correctIndex
        let isChosen = index == game.selectedAnswer

        let bg: Color = {
            guard answered else { return Theme.surface }
            if isCorrect { return Theme.win.opacity(0.18) }
            if isChosen  { return Theme.lose.opacity(0.18) }
            return Theme.surface
        }()
        let border: Color = {
            guard answered else { return Theme.hairline }
            if isCorrect { return Theme.win }
            if isChosen  { return Theme.lose }
            return Theme.hairline
        }()

        Button {
            game.answer(index)
        } label: {
            HStack(spacing: 12) {
                Text(q.options[index])
                    .font(.body).fontWeight(.medium)
                    .foregroundColor(Theme.text)
                    .multilineTextAlignment(.leading)
                Spacer()
                if answered && isCorrect {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.win)
                } else if answered && isChosen {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Theme.lose)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(bg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .stroke(border, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(answered)
    }

    // ── Fin de partie ─────────────────────────────────────────────────────────────
    private var finishedScreen: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: resultIcon)
                .font(.system(size: 64))
                .foregroundStyle(resultColor)
            Text(L("quiz.finished.title"))
                .font(.title2).fontWeight(.bold)
                .foregroundColor(Theme.text)
            Text("\(game.score) / \(game.questions.count)")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundColor(Theme.brand)
            Text(resultMessage)
                .font(.subheadline)
                .foregroundColor(Theme.textSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 6) {
                Image(systemName: "trophy.fill").foregroundColor(Theme.gold)
                Text(L("quiz.bestScore"))
                    .foregroundColor(Theme.textSoft)
                Text("\(game.bestScore) / \(QuizGame.questionsPerRound)")
                    .fontWeight(.bold).foregroundColor(Theme.text)
            }
            .font(.subheadline)
            .padding(.top, 4)

            Spacer()

            Button {
                game.start()
            } label: {
                Text(L("quiz.playAgain"))
                    .font(.headline).foregroundColor(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Capsule().fill(Theme.brand))
            }
            .padding(.horizontal, 24)

            Button(action: onClose) {
                Text(L("common.close"))
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(Theme.textSoft)
            }
            .padding(.bottom, 24)
        }
    }

    // Ratio de bonnes réponses → icône, couleur et message d'encouragement.
    private var ratio: Double {
        guard !game.questions.isEmpty else { return 0 }
        return Double(game.score) / Double(game.questions.count)
    }
    private var resultIcon: String {
        ratio >= 0.8 ? "star.circle.fill" : (ratio >= 0.5 ? "hand.thumbsup.fill" : "arrow.clockwise.circle.fill")
    }
    private var resultColor: Color {
        ratio >= 0.8 ? Theme.gold : (ratio >= 0.5 ? Theme.brand : Theme.textFaint)
    }
    private var resultMessage: String {
        ratio >= 0.8 ? L("quiz.result.great") : (ratio >= 0.5 ? L("quiz.result.good") : L("quiz.result.tryAgain"))
    }
}
