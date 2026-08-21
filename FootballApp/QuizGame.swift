import SwiftUI
import Combine

// ═════════════════════════════════════════════════════════════════════════════
// QUIZ — MOTEUR DE PARTIE (5 CHAMPIONNATS)
// ─────────────────────────────────────────────────────────────────────────────
// `ObservableObject` qui pilote une partie sur UN championnat choisi : tirage
// aléatoire de N questions DANS ce championnat, suivi du score, feedback
// (bonne/mauvaise réponse), fin de partie, et MEILLEUR SCORE PAR CHAMPIONNAT
// (persistant, hors-ligne). Aucune requête réseau : tout vient de `QuizData`.
// ═════════════════════════════════════════════════════════════════════════════

@MainActor        '
final class QuizGame: ObservableObject {
    /// Nombre de questions par partie (tirées au hasard dans le championnat).
    static let questionsPerRound = 10

    /// Phases : choix du championnat, accueil (championnat choisi), jeu, fin.
    enum Phase { case picking, intro, playing, finished }

    @Published private(set) var phase: Phase = .picking
    /// Championnat sélectionné pour la partie courante.
    @Published private(set) var league: QuizLeague?
    @Published private(set) var questions: [QuizQuestion] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var score = 0
    /// Index de la réponse choisie pour la question courante (nil = pas répondu).
    @Published private(set) var selectedAnswer: Int?

    /// Question affichée actuellement (nil hors d'une partie valide).
    var currentQuestion: QuizQuestion? {
        guard phase == .playing, questions.indices.contains(currentIndex) else { return nil }
        return questions[currentIndex]
    }

    /// Progression « n / total » (1-based pour l'affichage).
    var progressText: String { "\(currentIndex + 1) / \(questions.count)" }

    /// Vrai une fois qu'on a répondu à la question courante (feedback affiché).
    var hasAnswered: Bool { selectedAnswer != nil }

    /// Vrai si la question courante est la dernière de la manche.
    var isLastQuestion: Bool { currentIndex >= questions.count - 1 }

    // ── Meilleur score PAR championnat (UserDefaults, clé dérivée) ───────────────

    /// Clé de persistance du meilleur score d'un championnat.
    private static func bestScoreKey(_ league: QuizLeague) -> String {
        "quiz.bestScore.\(league.rawValue)"
    }

    /// Meilleur score enregistré pour un championnat (0 si jamais joué).
    static func bestScore(for league: QuizLeague) -> Int {
        UserDefaults.standard.integer(forKey: bestScoreKey(league))
    }

    /// Meilleur score du championnat de la partie courante (0 si aucun).
    var bestScore: Int {
        guard let league else { return 0 }
        return Self.bestScore(for: league)
    }

    // ── Cycle de vie d'une partie ──────────────────────────────────────────────

    /// Revient à l'écran de choix du championnat.
    func chooseLeague() {
        phase = .picking
        league = nil
        questions = []
        currentIndex = 0
        score = 0
        selectedAnswer = nil
    }

    /// Sélectionne un championnat et affiche son écran d'accueil (intro).
    func select(_ league: QuizLeague) {
        self.league = league
        questions = []
        currentIndex = 0
        score = 0
        selectedAnswer = nil
        phase = .intro
    }

    /// Démarre une partie sur le championnat déjà sélectionné.
    func start() {
        guard let league else { return }
        questions = Array(QuizData.questions(for: league).shuffled().prefix(Self.questionsPerRound))
        currentIndex = 0
        score = 0
        selectedAnswer = nil
        phase = .playing
    }

    /// Enregistre la réponse choisie (une seule fois par question). Met à jour le
    /// score si elle est correcte. N'avance PAS : on laisse voir le feedback.
    func answer(_ index: Int) {
        guard phase == .playing, selectedAnswer == nil,
              let q = currentQuestion else { return }
        selectedAnswer = index
        if index == q.correctIndex { score += 1 }
    }

    /// Passe à la question suivante, ou termine la partie si c'était la dernière.
    func next() {
        guard phase == .playing else { return }
        if isLastQuestion {
            finish()
        } else {
            currentIndex += 1
            selectedAnswer = nil
        }
    }

    /// Termine la partie et met à jour le meilleur score du championnat si battu.
    private func finish() {
        if let league, score > Self.bestScore(for: league) {
            UserDefaults.standard.set(score, forKey: Self.bestScoreKey(league))
        }
        phase = .finished
    }
}
