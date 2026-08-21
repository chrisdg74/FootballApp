import Foundation
import SwiftUI
import Combine

// ═════════════════════════════════════════════════════════════════════════════
// ASSISTANT IA CONVERSATIONNEL — côté app
// ─────────────────────────────────────────────────────────────────────────────
// L'app N'APPELLE PAS Claude ni API-Football directement : elle envoie la question
// au PROXY (POST /chat) qui, lui, détient les clés, interroge Claude (function
// calling) et API-Football, puis renvoie { reply, blocks }.
//
// Contrat (voir agent-proxy/CONTRACT.md) :
//   Requête : { messages:[{role,content}], locale }
//   Réponse : { reply: String, blocks: [ {type, …} ] }
//
// RÈGLE D'OR : aucun chiffre n'est inventé côté app — les cartes ne portent que
// des IDENTIFIANTS (fixtureId, competitionId, teamId) et rechargent le détail via
// les vues existantes de l'app, exactement comme le reste de l'appli.
// ═════════════════════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────────────────────────────────────
// CONFIGURATION — où joindre le proxy
// ─────────────────────────────────────────────────────────────────────────────
// En développement : le proxy tourne sur ton Mac (`npm run dev`).
//   • Simulateur iOS  → http://localhost:3000  (le simulateur partage le réseau du Mac)
//   • iPhone RÉEL     → http://<IP-locale-du-Mac>:3000  (ex. http://192.168.1.20:3000)
// En production : remplacer par l'URL du proxy déployé (ex. https://xxx.vercel.app).
//
// ⚠️ App Transport Security : en HTTP (localhost) il faut autoriser le trafic non
// chiffré en debug. Voir la note ATS dans le guide d'intégration.
enum AgentConfig {
    /// URL de base du proxy. À adapter selon l'environnement (voir ci-dessus).
    static let proxyBaseURL = "http://localhost:3000"

    /// Endpoint de conversation.
    static var chatURL: URL? { URL(string: "\(proxyBaseURL)/chat") }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODÈLES DE CONVERSATION
// ─────────────────────────────────────────────────────────────────────────────

/// Un bloc visuel renvoyé par le proxy. On décode `type` puis les champs utiles.
/// Un type inconnu est conservé en `.unknown` et IGNORÉ au rendu (compat ascendante).
/// (Une enum ne peut pas stocker d'`id` : on l'enveloppe dans `IdentifiedBlock`.)
/// Quelle partie du classement mettre en avant dans la carte mini-classement.
/// `.top` (défaut) = tête du tableau ; `.bottom` = bas de tableau (« le dernier »,
/// « qui descend », « la lanterne rouge »…).
enum StandingFocus { case top, bottom }

enum ChatBlock {
    case fixtureRow(fixtureId: Int)
    case standingMini(competitionId: String, highlightTeamId: Int?, focus: StandingFocus)
    case scorerCard(competitionId: String, limit: Int)
    case clubScorers(teamId: Int, competitionId: String?)
    case teamCard(teamId: Int)
    case text(content: String)
    case unknown
}

/// Bloc + identifiant stable pour `ForEach` (les blocs n'ont pas d'id côté proxy).
struct IdentifiedBlock: Identifiable {
    let id = UUID()
    let block: ChatBlock
}

/// Un message de la conversation (affiché en bulle) + ses éventuels blocs.
struct ChatMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String
    var blocks: [ChatBlock] = []
    /// Pour l'état « … » pendant que l'assistant réfléchit.
    var isPending: Bool = false
    /// Si la réponse a échoué : true → on affiche un bouton « Réessayer ».
    var isError: Bool = false
    /// Question utilisateur à rejouer si on appuie sur « Réessayer ».
    var retryPrompt: String? = nil

    /// Blocs enveloppés pour `ForEach` (chaque bloc reçoit un id stable).
    var identifiedBlocks: [IdentifiedBlock] { blocks.map { IdentifiedBlock(block: $0) } }
}

// ─────────────────────────────────────────────────────────────────────────────
// DÉCODAGE DE LA RÉPONSE DU PROXY
// ─────────────────────────────────────────────────────────────────────────────

private struct ChatResponseDTO: Decodable {
    let reply: String
    let blocks: [BlockDTO]?

    struct BlockDTO: Decodable {
        let type: String
        let fixtureId: Int?
        let competitionId: String?
        let highlightTeamId: Int?
        let limit: Int?
        let teamId: Int?
        let content: String?
        /// "top" (défaut) ou "bottom" pour la carte mini-classement.
        let focus: String?

        /// Convertit le DTO brut en `ChatBlock` typé (ou `.unknown` si type inconnu
        /// ou champs manquants).
        func toBlock() -> ChatBlock {
            switch type {
            case "fixtureRow":
                guard let id = fixtureId else { return .unknown }
                return .fixtureRow(fixtureId: id)
            case "standingMini":
                guard let cid = competitionId else { return .unknown }
                let f: StandingFocus = (focus == "bottom") ? .bottom : .top
                return .standingMini(competitionId: cid, highlightTeamId: highlightTeamId, focus: f)
            case "scorerCard":
                guard let cid = competitionId else { return .unknown }
                return .scorerCard(competitionId: cid, limit: limit ?? 5)
            case "clubScorers":
                guard let tid = teamId else { return .unknown }
                return .clubScorers(teamId: tid, competitionId: competitionId)
            case "teamCard":
                guard let id = teamId else { return .unknown }
                return .teamCard(teamId: id)
            case "text":
                return .text(content: content ?? "")
            default:
                return .unknown
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE RÉSEAU
// ─────────────────────────────────────────────────────────────────────────────

/// Erreurs de conversation, assez fines pour afficher un message ADAPTÉ à l'utilisateur
/// (hors-ligne ≠ délai dépassé ≠ proxy éteint ≠ bug serveur). Chaque cas expose une
/// clé de localisation via `messageKey` pour un texte clair côté chat.
enum ChatError: Error, LocalizedError {
    case badURL
    case offline            // pas de connexion internet
    case timedOut           // le proxy met trop de temps
    case unreachable        // proxy injoignable (éteint / mauvaise URL)
    case server(Int)        // le proxy a répondu avec un code ≠ 200
    case decoding(Error)    // réponse illisible
    case network(Error)     // autre erreur réseau

    /// Clé de localisation du message montré dans la bulle d'erreur.
    var messageKey: String {
        switch self {
        case .offline:     return "assistant.error.offline"
        case .timedOut:    return "assistant.error.timeout"
        case .unreachable: return "assistant.error.unreachable"
        case .server:      return "assistant.error.server"
        default:           return "assistant.error"
        }
    }

    /// Construit le bon cas à partir d'une erreur `URLError`.
    static func from(_ error: Error) -> ChatError {
        if let u = error as? URLError {
            switch u.code {
            case .notConnectedToInternet, .dataNotAllowed:
                return .offline
            case .timedOut:
                return .timedOut
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                return .unreachable
            default:
                return .network(error)
            }
        }
        return .network(error)
    }

    var errorDescription: String? {
        switch self {
        case .badURL:         return "URL du proxy invalide"
        case .offline:        return "Pas de connexion internet"
        case .timedOut:       return "Délai dépassé"
        case .unreachable:    return "Assistant injoignable"
        case .server(let c):  return "Erreur serveur (\(c))"
        case .decoding(let e):return "Décodage : \(e.localizedDescription)"
        case .network(let e): return e.localizedDescription
        }
    }
}

struct ChatService {
    /// Envoie l'historique complet au proxy et renvoie (texte, blocs).
    /// - Parameter history: la conversation (rôles user/assistant + textes).
    /// - Parameter locale: langue courante de l'app (fr, en, …).
    static func send(history: [ChatMessage], locale: String) async throws -> (reply: String, blocks: [ChatBlock]) {
        guard let url = AgentConfig.chatURL else { throw ChatError.badURL }

        // On ne transmet que le rôle et le texte (le proxy va chercher les données).
        let payloadMessages = history
            .filter { !$0.isPending }
            .map { ["role": $0.role == .user ? "user" : "assistant",
                    "content": $0.text] }

        let body: [String: Any] = ["messages": payloadMessages, "locale": locale]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 30

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw ChatError.from(error)   // → offline / timeout / unreachable / network
        }

        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw ChatError.server(http.statusCode)
        }

        do {
            let dto = try JSONDecoder().decode(ChatResponseDTO.self, from: data)
            let blocks = (dto.blocks ?? []).map { $0.toBlock() }
            return (dto.reply, blocks)
        } catch {
            throw ChatError.decoding(error)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// VUE-MODÈLE DE LA CONVERSATION
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var input: String = ""
    @Published var isSending: Bool = false

    /// Langue courante de l'app (2 lettres). Sert à demander au proxy de répondre
    /// dans la bonne langue.
    private var currentLocale: String {
        Locale.current.language.languageCode?.identifier ?? "fr"
    }

    var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    /// Envoie le texte courant (ou un texte fourni, pour les suggestions).
    func send(_ overrideText: String? = nil) {
        let raw = (overrideText ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !isSending else { return }

        messages.append(ChatMessage(role: .user, text: raw))
        input = ""
        deliverAssistantReply(retryPrompt: raw)
    }

    /// Rejoue la dernière question après une erreur : on retire la bulle d'erreur
    /// (qui suit forcément la question) et on relance l'appel.
    func retry(prompt: String) {
        guard !isSending else { return }
        if let last = messages.last, last.role == .assistant, last.isError {
            messages.removeLast()
        }
        deliverAssistantReply(retryPrompt: prompt)
    }

    /// Repart de zéro : conversation vide → réaffiche l'accueil + suggestions.
    func clear() {
        guard !isSending else { return }
        messages.removeAll()
        input = ""
    }

    /// Cœur commun à `send` et `retry` : pose une bulle « … » puis appelle le proxy.
    private func deliverAssistantReply(retryPrompt: String) {
        isSending = true
        messages.append(ChatMessage(role: .assistant, text: "", isPending: true))
        let pendingIndex = messages.count - 1

        Task {
            do {
                let (reply, blocks) = try await ChatService.send(
                    history: messages, locale: currentLocale
                )
                if messages.indices.contains(pendingIndex) {
                    messages[pendingIndex] = ChatMessage(
                        role: .assistant, text: reply, blocks: blocks
                    )
                }
            } catch {
                let key = (error as? ChatError)?.messageKey ?? "assistant.error"
                if messages.indices.contains(pendingIndex) {
                    messages[pendingIndex] = ChatMessage(
                        role: .assistant, text: L(key),
                        isError: true, retryPrompt: retryPrompt
                    )
                }
            }
            isSending = false
        }
    }
}
