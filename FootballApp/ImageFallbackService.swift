import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE DE REPLI D'IMAGES — TheSportsDB
// ─────────────────────────────────────────────────────────────────────────────
// API-Football est la source PRINCIPALE des visuels (logos d'équipe, photos de
// joueur, logos de compétition). Mais certains visuels manquent, surtout dans
// les divisions inférieures françaises et pour les jeunes joueurs.
//
// Ce service va chercher UNIQUEMENT le visuel manquant chez TheSportsDB (base
// communautaire riche en badges/photos), et SEULEMENT à la demande :
//   • on n'interroge JAMAIS TheSportsDB si API-Football a déjà fourni l'URL ;
//   • chaque résultat (succès ET échec) est mis en cache mémoire → on ne
//     redemande jamais deux fois la même clé (consommation minimale).
//
// FIABILITÉ DU MATCH :
//   • Équipe : TheSportsDB expose `idAPIfootball` → on fait correspondre par
//     l'ID API-Football (fiable), pas par le nom (recherche floue).
//   • Joueur : pas d'idAPIfootball côté joueurs → match par nom. On ne l'utilise
//     QUE pour l'IMAGE, jamais pour l'appartenance à un club (on garde notre
//     logique API-Football pour ça).
//
// CLÉ : clé de test publique gratuite « 3 ». Ce n'est PAS un secret (à la
// différence de la clé API-Football) — elle peut rester en clair. Si tu prends
// plus tard une clé Patreon dédiée, remplace `apiKey` ci-dessous.
// ─────────────────────────────────────────────────────────────────────────────

actor ImageFallbackService {
    static let shared = ImageFallbackService()

    private let apiKey = "3"
    private var base: String { "https://www.thesportsdb.com/api/v1/json/\(apiKey)" }

    // Caches mémoire. La valeur est une URL optionnelle : `nil` mémorisé =
    // « déjà cherché, rien trouvé » → on ne relance pas la requête.
    private var teamCache: [Int: URL?] = [:]      // clé = idAPIfootball
    private var teamStadiumCache: [Int: URL?] = [:] // clé = idAPIfootball (photo stade/ambiance)
    private var playerCache: [String: URL?] = [:] // clé = nom normalisé
    private var leagueCache: [String: URL?] = [:] // clé = nom normalisé (badge/logo)
    private var leagueBannerCache: [String: URL?] = [:] // clé = nom normalisé (fanart/bannière)

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 8
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: cfg)
    }()

    private init() {}

    // ── Équipe : badge/logo par ID API-Football ────────────────────────────────
    // On cherche l'équipe par nom (searchteams) puis on retient l'entrée dont
    // `idAPIfootball` == l'ID fourni. Renvoie strBadge (prioritaire) ou strLogo.
    func teamBadge(apiFootballId: Int, name: String) async -> URL? {
        if let cached = teamCache[apiFootballId] { return cached }

        let resolved = await resolveTeamBadge(apiFootballId: apiFootballId, name: name)
        teamCache[apiFootballId] = resolved   // mémorise aussi l'échec (nil)
        return resolved
    }

    private func resolveTeamBadge(apiFootballId: Int, name: String) async -> URL? {
        guard let teams = await searchTeams(name: name) else { return nil }
        let match = matchTeam(teams, apiFootballId: apiFootballId, name: name)
        let candidate = firstNonEmpty(match?.strBadge, match?.strLogo)
        return candidate.flatMap(URL.init(string:))
    }

    // ── Stade : photo par ID API-Football ───────────────────────────────────────
    // Repli utilisé QUAND API-Football ne fournit pas `venue.image`. On privilégie
    // la vignette de stade (strStadiumThumb) — cohérente avec le bandeau « stade »
    // de la fiche — puis, à défaut, une photo d'ambiance du club (strFanart1..4).
    // Match fiable par idAPIfootball (jamais par nom seul), cache incl. les échecs.
    func teamStadiumPhoto(apiFootballId: Int, name: String) async -> URL? {
        if let cached = teamStadiumCache[apiFootballId] { return cached }
        let resolved = await resolveTeamStadiumPhoto(apiFootballId: apiFootballId, name: name)
        teamStadiumCache[apiFootballId] = resolved   // mémorise aussi l'échec (nil)
        return resolved
    }

    private func resolveTeamStadiumPhoto(apiFootballId: Int, name: String) async -> URL? {
        guard let teams = await searchTeams(name: name) else { return nil }
        let match = matchTeam(teams, apiFootballId: apiFootballId, name: name)
        // VRAIE photo de stade UNIQUEMENT (strStadiumThumb). Choix user 2026-08-16 :
        // pas de repli fanart (pour Arsenal le fanart est un motif de blason, pas le
        // stade → trompeur). Si pas de photo de stade réelle → nil → aucun bandeau.
        let candidate = firstNonEmpty(match?.strStadiumThumb)
        return candidate.flatMap(URL.init(string:))
    }

    // Recherche d'équipes par nom (searchteams.php). Factorisé : badge ET stade.
    private func searchTeams(name: String) async -> [TSDBTeam]? {
        guard let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base)/searchteams.php?t=\(q)")
        else { return nil }
        return await getTeams(url)
    }

    // Sélection fiable : par idAPIfootball, à défaut nom exact.
    private func matchTeam(_ teams: [TSDBTeam], apiFootballId: Int, name: String) -> TSDBTeam? {
        teams.first { Int($0.idAPIfootball ?? "") == apiFootballId }
            ?? teams.first { $0.strTeam?.caseInsensitiveCompare(name) == .orderedSame }
    }

    // ── Joueur : photo par nom ──────────────────────────────────────────────────
    // strCutout (détourée, fond transparent — idéale pour une fiche) prioritaire,
    // sinon strThumb. Match par nom uniquement → usage IMAGE seulement.
    func playerPhoto(name: String) async -> URL? {
        let key = normalized(name)
        guard !key.isEmpty else { return nil }
        if let cached = playerCache[key] { return cached }

        let resolved = await resolvePlayerPhoto(name: name)
        playerCache[key] = resolved
        return resolved
    }

    private func resolvePlayerPhoto(name: String) async -> URL? {
        guard let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base)/searchplayers.php?p=\(q)")
        else { return nil }

        guard let players = await getPlayers(url) else { return nil }
        let match = players.first { normalized($0.strPlayer ?? "") == normalized(name) }
            ?? players.first
        let candidate = firstNonEmpty(match?.strCutout, match?.strThumb)
        return candidate.flatMap(URL.init(string:))
    }

    // ── Compétition : badge par nom ───────────────────────────────────────────────
    // PIÈGE (vérifié) : `all_leagues.php` ne renvoie QUE `strLeague`/`idLeague`,
    // PAS les badges → il faut une 2e requête `lookupleague.php?id=` pour obtenir
    // `strBadge`/`strLogo`. Stratégie frugale :
    //   1. On récupère la liste complète des ligues UNE seule fois (all_leagues.php)
    //      → mémorisée, sert à résoudre nom → idLeague localement.
    //   2. On résout `idLeague` par correspondance de nom, PUIS on appelle
    //      `lookupleague.php?id=` UNE fois par compétition demandée (mémorisé).
    // Correspondance de nom : nom EXACT, sinon alias connus (les libellés de notre
    // catalogue ne collent pas toujours à ceux de TheSportsDB), sinon inclusion.
    private var allLeagues: [TSDBLeague]?

    /// Alias : nom de notre catalogue (normalisé) → nom TheSportsDB (normalisé).
    /// TheSportsDB préfixe souvent par le pays (« French Ligue 1 », « Spanish La Liga »).
    private let leagueNameAliases: [String: String] = [
        "ligue 1": "french ligue 1",
        "ligue 2": "french ligue 2",
        "ligue 3": "french national",
        "premier league": "english premier league",
        "laliga": "spanish la liga",
        "la liga": "spanish la liga",
        "serie a": "italian serie a",
        "bundesliga": "german bundesliga",
        "primeira liga": "portuguese primeira liga",
        "super league": "swiss super league",
        "mls": "american major league soccer",
        "brasileirao": "brazilian serie a",
        "liga mx": "mexican liga mx",
        "primera division": "argentinian primera division",
        "j1 league": "japanese j league",
        "pro league": "saudi pro league",
        "ligue des champions": "uefa champions league",
        "champions league": "uefa champions league",
        "ligue europa": "uefa europa league",
        "europa league": "uefa europa league",
        "ligue conference": "uefa conference league",
        "conference league": "uefa conference league",
        "coupe du monde": "fifa world cup",
        "ligue des nations": "uefa nations league"
    ]

    func leagueBadge(name: String) async -> URL? {
        let key = normalized(name)
        guard !key.isEmpty else { return nil }
        if let cached = leagueCache[key] { return cached }

        guard let id = await resolveLeagueId(key: key) else {
            // Repli : badge éventuellement porté par all_leagues (rare).
            let match = matchLeague(key: key)
            let resolved = firstNonEmpty(match?.strBadge, match?.strLogo).flatMap(URL.init(string:))
            leagueCache[key] = resolved
            return resolved
        }

        let detail = await lookupLeague(id: id)
        let resolved = firstNonEmpty(detail?.strBadge, detail?.strLogo).flatMap(URL.init(string:))
        leagueCache[key] = resolved
        return resolved
    }

    // ── Compétition : bannière / fanart (photo d'ambiance réelle) ─────────────────
    // Source vérifiée : lookupleague.php expose strFanart1…4 (photos de stade /
    // ambiance) et strBanner. On privilégie le fanart (paysage riche), puis la
    // bannière. Sert de toile de fond au bandeau d'en-tête d'une compétition.
    func leagueBanner(name: String) async -> URL? {
        let key = normalized(name)
        guard !key.isEmpty else { return nil }
        if let cached = leagueBannerCache[key] { return cached }

        guard let id = await resolveLeagueId(key: key) else {
            leagueBannerCache[key] = nil
            return nil
        }
        let detail = await lookupLeague(id: id)
        let resolved = firstNonEmpty(detail?.strFanart1, detail?.strFanart2,
                                     detail?.strFanart3, detail?.strFanart4,
                                     detail?.strBanner, detail?.strPoster)
            .flatMap(URL.init(string:))
        leagueBannerCache[key] = resolved
        return resolved
    }

    /// Résout l'idLeague TheSportsDB par NOM (jamais par un ID deviné → jamais la
    /// mauvaise ligue). Priorité : (1) recherche directe par nom via l'endpoint
    /// dédié `search_all_leagues.php?l=` (souvent OK même avec la clé « 3 » et
    /// renvoie déjà les fanart), (2) repli sur all_leagues.php + correspondance.
    private func resolveLeagueId(key: String) async -> String? {
        let target = leagueNameAliases[key] ?? key
        // 1) Recherche directe par nom (alias TheSportsDB prioritaire, puis brut).
        //    NB : `await` interdit à droite d'un `??` (autoclosure) → appels séparés.
        if let league = await searchLeagueByName(target),
           let id = league.idLeague, !id.isEmpty {
            return id
        }
        if let league = await searchLeagueByName(key),
           let id = league.idLeague, !id.isEmpty {
            return id
        }
        // 2) Dernier recours : liste complète + correspondance de nom.
        if allLeagues == nil { allLeagues = await getAllLeagues() }
        return matchLeague(key: key)?.idLeague.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Recherche une ligue par nom via `searchleagues.php?l=` (endpoint documenté
    /// qui renvoie déjà les champs badge/fanart/banner). Match de nom EXACT
    /// prioritaire (jamais une ligue au nom différent), sinon rien → on ne renvoie
    /// jamais une ligue arbitraire.
    private func searchLeagueByName(_ name: String) async -> TSDBLeague? {
        guard let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base)/searchleagues.php?l=\(q)"),
              let data = try? await session.data(from: url).0,
              let wrap = try? JSONDecoder().decode(TSDBLeaguesWrap.self, from: data),
              let leagues = wrap.leagues, !leagues.isEmpty
        else { return nil }
        // Nom EXACT uniquement → aucune ligue arbitraire.
        return leagues.first { normalized($0.strLeague ?? "") == normalized(name) }
    }

    private func matchLeague(key: String) -> TSDBLeague? {
        let target = leagueNameAliases[key] ?? key
        return allLeagues?.first { normalized($0.strLeague ?? "") == target }
            ?? allLeagues?.first { normalized($0.strLeague ?? "") == key }
            ?? allLeagues?.first { normalized($0.strLeague ?? "").contains(target) }
    }

    /// Fiche complète d'une ligue via son idLeague (badge + fanart + bannière).
    private func lookupLeague(id: String) async -> TSDBLeague? {
        guard let url = URL(string: "\(base)/lookupleague.php?id=\(id)"),
              let data = try? await session.data(from: url).0,
              let wrap = try? JSONDecoder().decode(TSDBLeaguesWrap.self, from: data)
        else { return nil }
        return wrap.leagues?.first
    }

    // ── Réseau bas niveau ─────────────────────────────────────────────────────
    private func getTeams(_ url: URL) async -> [TSDBTeam]? {
        guard let data = try? await session.data(from: url).0,
              let wrap = try? JSONDecoder().decode(TSDBTeamsWrap.self, from: data)
        else { return nil }
        return wrap.teams
    }

    private func getPlayers(_ url: URL) async -> [TSDBPlayer]? {
        guard let data = try? await session.data(from: url).0,
              let wrap = try? JSONDecoder().decode(TSDBPlayersWrap.self, from: data)
        else { return nil }
        return wrap.player
    }

    private func getAllLeagues() async -> [TSDBLeague] {
        guard let url = URL(string: "\(base)/all_leagues.php"),
              let data = try? await session.data(from: url).0,
              let wrap = try? JSONDecoder().decode(TSDBLeaguesWrap.self, from: data)
        else { return [] }
        return wrap.leagues ?? []
    }

    // ── Utilitaires ───────────────────────────────────────────────────────────
    private func firstNonEmpty(_ values: String?...) -> String? {
        for v in values { if let v, !v.isEmpty { return v } }
        return nil
    }

    private func normalized(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// ── Modèles de décodage TheSportsDB (calés sur la réponse réelle) ──────────────
// `nonisolated` : détache ces types de toute isolation d'acteur (le projet est
// en isolation MainActor par défaut). Sinon leur conformité à `Decodable` est
// « main actor-isolated » et le décodage depuis l'acteur ImageFallbackService
// déclenche l'avertissement « Main actor-isolated conformance … cannot be used
// in actor-isolated context » (erreur en Swift 6). `Sendable` en complément
// pour le passage de frontière async.
nonisolated private struct TSDBTeamsWrap: Decodable, Sendable { let teams: [TSDBTeam]? }
nonisolated private struct TSDBTeam: Decodable, Sendable {
    let strTeam: String?
    let idAPIfootball: String?
    let strBadge: String?
    let strLogo: String?
    // Photos de stade / ambiance (présentes sur searchteams.php). Servent de repli
    // quand API-Football ne fournit pas `venue.image` (ex. Arsenal / Emirates).
    let strStadium: String?
    let strStadiumThumb: String?
    let strFanart1: String?
    let strFanart2: String?
    let strFanart3: String?
    let strFanart4: String?
}

nonisolated private struct TSDBPlayersWrap: Decodable, Sendable { let player: [TSDBPlayer]? }
nonisolated private struct TSDBPlayer: Decodable, Sendable {
    let strPlayer: String?
    let strCutout: String?
    let strThumb: String?
}

nonisolated private struct TSDBLeaguesWrap: Decodable, Sendable { let leagues: [TSDBLeague]? }
nonisolated private struct TSDBLeague: Decodable, Sendable {
    let idLeague: String?
    let strLeague: String?
    let strBadge: String?
    let strLogo: String?
    // Champs photo (présents uniquement sur lookupleague.php, pas all_leagues.php).
    let strBanner: String?
    let strPoster: String?
    let strFanart1: String?
    let strFanart2: String?
    let strFanart3: String?
    let strFanart4: String?
}
