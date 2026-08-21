import Foundation
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// CONFIGURATION — Remplissez vos clés API ici
// ─────────────────────────────────────────────────────────────────────────────

// Clé API-Football (api-sports.io) — plan Pro (7500 req/jour)
// Inscription : https://dashboard.api-football.com/register
let API_FOOTBALL_KEY = "2321550d4d152570b8c43b32d31ef088"

// Clé football-data.org — pour les matchs internationaux (Ligue 1 + CL)
// Inscription : https://www.football-data.org/client/register
let FOOTBALL_DATA_KEY = "YOUR_FOOTBALL_DATA_KEY"

// ─────────────────────────────────────────────────────────────────────────────
// ERREURS
// ─────────────────────────────────────────────────────────────────────────────

enum APIError: Error, LocalizedError {
    case invalidURL, noData, serverError(Int), missingAPIKey
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:        return "URL invalide"
        case .noData:            return "Aucune donnée reçue"
        case .serverError(let c):return "Erreur serveur \(c)"
        case .missingAPIKey:     return "Clé API manquante. Configurez APIService.swift"
        case .decodingError(let e): return "Décodage : \(e.localizedDescription)"
        }
    }
}

// Le catalogue des compétitions est défini dans Competitions.swift.

// ─────────────────────────────────────────────────────────────────────────────
// MODÈLES API-Football
// ─────────────────────────────────────────────────────────────────────────────

struct AFResponse<T: Codable>: Codable {
    let response: [T]
    let results: Int?
    let paging: AFPaging?
}

/// Enveloppe pour les (rares) endpoints API-Football où `response` est un OBJET
/// unique et non un tableau. Cas connu : `/teams/statistics`, qui renvoie
/// `"response": { … }` (un seul bilan) là où tous les autres endpoints renvoient
/// un tableau. Décoder ça avec `AFResponse<T>` (response = [T]) ÉCHOUE
/// silencieusement → c'était la cause du fair-play vide et du bilan de saison
/// jamais affiché. Ce wrapper décode l'objet directement.
struct AFObjectResponse<T: Codable>: Codable {
    let response: T?
    let results: Int?
    let paging: AFPaging?
}

/// Pagination renvoyée par API-Football (endpoints volumineux comme /players).
struct AFPaging: Codable {
    let current: Int
    let total: Int
}

struct AFFixture: Codable, Identifiable {
    let fixture: AFFixtureDetail
    let league: AFLeague
    let teams: AFTeams
    let goals: AFGoals
    let score: AFScore?

    var id: Int { fixture.id }

    var statusLabel: String {
        switch fixture.status.short {
        case "FT", "AET", "PEN": return L("status.finished")
        case "1H":   return L("status.firstHalf")
        case "HT":   return L("status.halftime")
        case "2H":   return L("status.secondHalf")
        case "ET":   return L("status.extraTime")
        case "P":    return L("status.penalties")
        case "NS":
            if let date = isoDate {
                let fmt = DateFormatter()
                fmt.locale = Locale.current
                fmt.dateFormat = "EEE d MMM · HH:mm"
                fmt.timeZone = TimeZone.current
                return fmt.string(from: date)
            }
            return L("status.upcoming")
        case "PST":  return L("status.postponed")
        case "CANC": return L("status.cancelled")
        default:     return fixture.status.short
        }
    }

    /// Comme `statusLabel` mais, pour un match à venir, ne renvoie que l'HEURE
    /// (« 21:00 ») sans la date. Utilisé dans les listes DÉJÀ regroupées par jour,
    /// où répéter la date sur chaque ligne serait redondant.
    var timeOnlyLabel: String {
        guard fixture.status.short == "NS", let date = isoDate else { return statusLabel }
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = TimeZone.current
        return fmt.string(from: date)
    }

    var isLive: Bool {
        ["1H","HT","2H","ET","P","BT"].contains(fixture.status.short)
    }
    var isFinished: Bool {
        ["FT","AET","PEN"].contains(fixture.status.short)
    }
    /// Match annulé / reporté / abandonné / WO : à EXCLURE de « prochain match ».
    /// (API-Football laisse ces matchs dans la réponse avec ces codes de statut ;
    /// sans ce filtre, un match annulé peut être présenté comme « prochain match »
    /// — ex. la Finalissima Espagne-Argentine annulée.)
    var isCancelledOrPostponed: Bool {
        ["PST","CANC","ABD","AWD","WO","SUSP","INT"].contains(fixture.status.short)
    }

    var isoDate: Date? {
        ISO8601DateFormatter().date(from: fixture.date)
    }

    var formattedDateSection: String {
        guard let date = isoDate else { return "?" }
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "EEEE d MMMM yyyy"
        fmt.timeZone = TimeZone.current
        return fmt.string(from: date).capitalized
    }
}

struct AFFixtureDetail: Codable {
    let id: Int
    let date: String
    let status: AFStatus
    let round: String?
    let venue: AFVenue?
    let referee: String?      // arbitre (fourni par l'API sur la plupart des matchs)
}

struct AFStatus: Codable {
    let long: String
    let short: String
    let elapsed: Int?
}

struct AFVenue: Codable {
    let name: String?
    let city: String?
    let capacity: Int?   // capacité du stade (fournie par /teams?id=)
    let image: String?   // photo du stade (URL) — souvent présente sur /teams
}

struct AFLeague: Codable {
    let id: Int
    let name: String
    let round: String?
    let logo: String?
    /// « League » / « Cup » côté API-Football. Sert à distinguer, pour les matchs
    /// des clubs favoris hors catalogue, une COUPE d'un simple AMICAL.
    let type: String?
    /// Saison du match (ex. 2026). Sert à dériver league+season pour le bilan
    /// (/teams/statistics) sans appel supplémentaire. Optionnel : tolérant.
    let season: Int?
}

// Réponse de /leagues?id= : chaque entrée porte un sous-objet `league` (id, name,
// logo) + `country` (name, code, flag). On ne décode que ce dont on a besoin.
struct AFLeagueEntry: Codable {
    struct LeagueInfo: Codable {
        let id: Int?
        let name: String?
        let logo: String?
    }
    let league: LeagueInfo
}

struct AFTeams: Codable {
    let home: AFTeam
    let away: AFTeam
}

struct AFTeam: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let logo: String?

    /// Nom prêt à l'affichage : certaines équipes (surtout en Ligue 2) sont
    /// renvoyées par l'API tout en majuscules (« PAU », « RED Star »).
    /// On remet en Capitale/minuscules les mots entièrement en majuscules,
    /// tout en préservant les sigles usuels du football (FC, AC, AS…).
    var displayName: String { TeamNameFormatter.pretty(name) }
}

/// Normalisation cosmétique des noms d'équipes renvoyés en CAPITALES.
// ─────────────────────────────────────────────────────────────────────────────
// DRAPEAU À PARTIR D'UN NOM DE PAYS
// ─────────────────────────────────────────────────────────────────────────────
// API-Football renvoie la nationalité d'un joueur sous forme de NOM de pays en
// anglais (« France », « Brazil », « England »…), pas un code ISO. On convertit
// ce nom en code ISO-3166 alpha-2, puis en émoji drapeau régional. Repli propre
// (chaîne vide) si le pays est inconnu, pour ne jamais afficher un carré cassé.
enum CountryFlag {
    /// Nom de pays (anglais, tel que renvoyé par l'API) → code ISO alpha-2.
    private static let iso: [String: String] = [
        "france": "FR", "spain": "ES", "italy": "IT", "germany": "DE",
        "portugal": "PT", "netherlands": "NL", "belgium": "BE", "england": "GB-ENG",
        "scotland": "GB-SCT", "wales": "GB-WLS", "northern ireland": "GB-NIR",
        "switzerland": "CH", "austria": "AT", "croatia": "HR", "serbia": "RS",
        "poland": "PL", "denmark": "DK", "sweden": "SE", "norway": "NO",
        "ireland": "IE", "republic of ireland": "IE", "ukraine": "UA", "russia": "RU",
        "turkey": "TR", "türkiye": "TR", "greece": "GR", "czech republic": "CZ",
        "czechia": "CZ", "slovakia": "SK", "slovenia": "SI", "hungary": "HU",
        "romania": "RO", "bulgaria": "BG", "finland": "FI", "iceland": "IS",
        "bosnia and herzegovina": "BA", "albania": "AL", "north macedonia": "MK",
        "montenegro": "ME", "kosovo": "XK", "georgia": "GE", "armenia": "AM",
        "brazil": "BR", "argentina": "AR", "uruguay": "UY", "colombia": "CO",
        "chile": "CL", "peru": "PE", "ecuador": "EC", "paraguay": "PY",
        "bolivia": "BO", "venezuela": "VE", "mexico": "MX", "usa": "US",
        "united states": "US", "canada": "CA", "costa rica": "CR", "honduras": "HN",
        "panama": "PA", "jamaica": "JM", "morocco": "MA", "algeria": "DZ",
        "tunisia": "TN", "egypt": "EG", "senegal": "SN", "ivory coast": "CI",
        "cote d'ivoire": "CI", "côte d'ivoire": "CI", "cameroon": "CM", "ghana": "GH",
        "nigeria": "NG", "mali": "ML", "guinea": "GN", "burkina faso": "BF",
        "dr congo": "CD", "congo dr": "CD", "congo": "CG", "gabon": "GA",
        "south africa": "ZA", "japan": "JP", "south korea": "KR", "korea republic": "KR",
        "australia": "AU", "china": "CN", "iran": "IR", "saudi arabia": "SA",
        "qatar": "QA", "united arab emirates": "AE", "iraq": "IQ", "india": "IN",
        "new zealand": "NZ",
    ]

    /// Vrai si la chaîne est un NOM DE PAYS connu (« France », « Brazil »…). Sert à
    /// repérer une SÉLECTION nationale déguisée en club sur /players/teams, où le
    /// flag `national` est parfois absent. `s` doit déjà être normalisé (minuscule,
    /// sans accents) par l'appelant.
    static func isCountryName(_ s: String) -> Bool {
        iso[s] != nil
    }

    /// Convertit un nom de pays en émoji drapeau (« France » → 🇫🇷). Vide si inconnu.
    static func emoji(for country: String?) -> String {
        guard let raw = country?.trimmingCharacters(in: .whitespaces), !raw.isEmpty,
              let code = iso[raw.lowercased()] else { return "" }
        // Cas particuliers : nations britanniques (drapeaux à tags Unicode).
        switch code {
        case "GB-ENG": return "🏴\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        case "GB-SCT": return "🏴\u{E0067}\u{E0062}\u{E0073}\u{E0063}\u{E0074}\u{E007F}"
        case "GB-WLS": return "🏴\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}"
        case "GB-NIR": return "🇬🇧"   // pas de drapeau officiel → Union Jack
        default: break
        }
        // Code ISO standard → indicateurs régionaux (A → 🇦, etc.).
        let scalars = code.unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value)   // 0x1F1E6 - 'A'
        }
        guard scalars.count == 2 else { return "" }
        return String(String.UnicodeScalarView(scalars))
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// TRADUCTION DES NOMS DE PAYS → ANGLAIS (pour la recherche d'équipes)
// ─────────────────────────────────────────────────────────────────────────────
// API-Football n'indexe les noms d'équipes/sélections qu'en ANGLAIS (« Brazil »,
// « Spain »…). Un utilisateur francophone qui tape « Brésil » n'atteint donc pas
// le serveur. On traduit la requête AVANT l'appel /teams?search= via une table
// DÉTERMINISTE multilingue (fr surtout, + es/it/de/pt courants). Si la saisie
// n'est pas un nom de pays connu, on la laisse telle quelle (recherche de club).
// ═════════════════════════════════════════════════════════════════════════════
enum CountryNameTranslator {
    /// Nom de pays localisé (normalisé, minuscule sans accents) → nom ANGLAIS
    /// exact attendu par API-Football. On ne met QUE les cas où la graphie diffère
    /// de l'anglais (« brazil » = « brazil » n'a pas besoin d'entrée).
    private static let toEnglish: [String: String] = [
        // Français
        "bresil": "Brazil", "espagne": "Spain", "italie": "Italy",
        "allemagne": "Germany", "angleterre": "England", "ecosse": "Scotland",
        "pays de galles": "Wales", "pays-bas": "Netherlands", "belgique": "Belgium",
        "suisse": "Switzerland", "autriche": "Austria", "croatie": "Croatia",
        "serbie": "Serbia", "pologne": "Poland", "danemark": "Denmark",
        "suede": "Sweden", "norvege": "Norway", "irlande": "Ireland",
        "ukraine": "Ukraine", "russie": "Russia", "turquie": "Turkey",
        "grece": "Greece", "hongrie": "Hungary", "roumanie": "Romania",
        "bulgarie": "Bulgaria", "finlande": "Finland", "islande": "Iceland",
        "albanie": "Albania", "argentine": "Argentina", "colombie": "Colombia",
        "chili": "Chile", "perou": "Peru", "equateur": "Ecuador",
        "mexique": "Mexico", "etats-unis": "USA", "etats unis": "USA",
        "canada": "Canada", "maroc": "Morocco", "algerie": "Algeria",
        "tunisie": "Tunisia", "egypte": "Egypt", "senegal": "Senegal",
        "cote d'ivoire": "Ivory Coast", "cameroun": "Cameroon", "ghana": "Ghana",
        "nigeria": "Nigeria", "mali": "Mali", "guinee": "Guinea",
        "afrique du sud": "South Africa", "japon": "Japan",
        "coree du sud": "South Korea", "australie": "Australia",
        "chine": "China", "iran": "Iran", "arabie saoudite": "Saudi Arabia",
        "qatar": "Qatar", "emirats arabes unis": "United Arab Emirates",
        "portugal": "Portugal", "uruguay": "Uruguay",
        // Espagnol (les clés identiques entre langues, ex. « polonia », « italia »,
        // « grecia », donnent le même résultat → une seule entrée suffit).
        "brasil": "Brazil", "espana": "Spain", "alemania": "Germany",
        "inglaterra": "England", "paises bajos": "Netherlands", "belgica": "Belgium",
        "suiza": "Switzerland", "croacia": "Croatia", "polonia": "Poland",
        "dinamarca": "Denmark", "suecia": "Sweden", "noruega": "Norway",
        "turquia": "Turkey", "grecia": "Greece", "hungria": "Hungary",
        "rumania": "Romania", "marruecos": "Morocco", "argelia": "Algeria",
        "italia": "Italy", "francia": "France",
        // Italien
        "brasile": "Brazil", "spagna": "Spain", "germania": "Germany",
        "inghilterra": "England", "paesi bassi": "Netherlands", "belgio": "Belgium",
        "svizzera": "Switzerland", "croazia": "Croatia",
        "danimarca": "Denmark", "svezia": "Sweden", "norvegia": "Norway",
        "turchia": "Turkey", "ungheria": "Hungary", "giappone": "Japan",
        // Allemand
        "brasilien": "Brazil", "spanien": "Spain", "deutschland": "Germany",
        "niederlande": "Netherlands", "belgien": "Belgium",
        "schweiz": "Switzerland", "kroatien": "Croatia", "polen": "Poland",
        "schweden": "Sweden", "norwegen": "Norway",
        "turkei": "Turkey", "griechenland": "Greece", "ungarn": "Hungary",
        "rumanien": "Romania", "frankreich": "France", "italien": "Italy",
        // Portugais
        "espanha": "Spain", "alemanha": "Germany", "paises baixos": "Netherlands",
        "suica": "Switzerland", "japao": "Japan", "franca": "France",
        "marrocos": "Morocco",
    ]

    /// Si `query` est un nom de pays localisé connu, renvoie le nom ANGLAIS attendu
    /// par l'API ; sinon renvoie `nil` (l'appelant garde la saisie d'origine).
    static func englishName(for query: String) -> String? {
        let key = query
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return toEnglish[key]
    }
}

enum TeamNameFormatter {
    /// Sigles à laisser en majuscules même isolés.
    private static let acronyms: Set<String> = [
        "FC", "AC", "AS", "SC", "RC", "SM", "SG", "OL", "OGC", "PSG",
        "RB", "US", "CS", "AJ", "EA", "SO", "GF", "FCO", "ESTAC", "USL",
        "VfB", "VfL", "TSG", "SV", "BSC", "MLS", "UD", "CD", "SD", "CF",
        "AEK", "PAOK", "PSV", "AZ", "NAC", "NEC"
    ]

    static func pretty(_ raw: String) -> String {
        // 1) Localisation d'abord (ex. « Sparta Praha » → « Sparta Prague » en FR).
        let localized = TeamNameLocalizer.localized(raw)
        // 2) Recapitalisation cosmétique des mots tout en majuscules.
        let words = localized.split(separator: " ", omittingEmptySubsequences: true)
        let mapped = words.map { word -> String in
            let s = String(word)
            // Sigle connu (FC, AC, PSG…) → conservé en majuscules.
            if acronyms.contains(s.uppercased()) { return s }
            // Mot entièrement en majuscules et alphabétique (PAU, RED) → Capitalise.
            let hasLetters = s.rangeOfCharacter(from: .letters) != nil
            let hasLowercase = s.rangeOfCharacter(from: .lowercaseLetters) != nil
            if hasLetters && !hasLowercase {
                return s.prefix(1).uppercased() + s.dropFirst().lowercased()
            }
            return s
        }
        return mapped.joined(separator: " ")
    }
}

/// Traduction des noms d'équipes étrangères selon la langue de l'app.
/// L'API renvoie un nom unique (souvent dans la langue locale du club, ex.
/// « Sparta Praha », « Bayern München »). On propose une variante par langue
/// pour les clubs dont le nom de ville se traduit couramment.
///
/// Fonctionnement : on cherche une clé de localisation `team.<slug>` ; si une
/// traduction existe dans le `.strings` de la langue courante ET qu'elle diffère
/// de la clé, on l'utilise. Sinon, on garde le nom d'origine (le plus courant).
enum TeamNameLocalizer {
    /// Table nom API (normalisé minuscules) → slug de clé de localisation.
    /// N'inclure QUE les clubs dont l'affichage doit varier selon la langue.
    private static let slugByRawName: [String: String] = [
        "sparta praha": "spartaPrague",
        "slavia praha": "slaviaPrague",
        "viktoria plzen": "viktoriaPlzen",
        "bayern münchen": "bayernMunich",
        "bayern munchen": "bayernMunich",
        "fc bayern münchen": "bayernMunich",
        "1. fc köln": "fcKoln",
        "fc köln": "fcKoln",
        "köln": "fcKoln",
        "rapid wien": "rapidVienna",
        "austria wien": "austriaVienna",
        "sk rapid wien": "rapidVienna",
        "red star belgrade": "redStarBelgrade",
        "crvena zvezda": "redStarBelgrade",
        "fk crvena zvezda": "redStarBelgrade",
        "sporting cp": "sportingLisbon",
        "genk": "genk",
        "club brugge kv": "clubBruges",
        "club brugge": "clubBruges",
        "olympiakos piraeus": "olympiacos",
        "olympiacos piraeus": "olympiacos"
    ]

    /// Table nom API des SÉLECTIONS NATIONALES (normalisé minuscules) → slug de
    /// clé de localisation `team.nat.<slug>`. L'API renvoie ces noms en anglais
    /// (« Türkiye », « Belgium », « Korea Republic »…) ; on les traduit dans les
    /// 8 langues. Les alias couvrent les variantes connues de l'API
    /// (Turkey/Türkiye, Czech Republic/Czechia, formes régionales, etc.).
    private static let nationSlugByRawName: [String: String] = [
        // — Europe (UEFA) —
        "france": "france",
        "england": "england",
        "scotland": "scotland",
        "wales": "wales",
        "northern ireland": "northernIreland",
        "republic of ireland": "republicOfIreland", "ireland": "republicOfIreland",
        "germany": "germany",
        "italy": "italy",
        "spain": "spain",
        "portugal": "portugal",
        "netherlands": "netherlands",
        "belgium": "belgium",
        "croatia": "croatia",
        "switzerland": "switzerland",
        "austria": "austria",
        "poland": "poland",
        "denmark": "denmark",
        "sweden": "sweden",
        "norway": "norway",
        "finland": "finland",
        "iceland": "iceland",
        "czech republic": "czechRepublic", "czechia": "czechRepublic",
        "slovakia": "slovakia",
        "hungary": "hungary",
        "romania": "romania",
        "serbia": "serbia",
        "ukraine": "ukraine",
        "russia": "russia",
        "greece": "greece",
        "turkey": "turkey", "türkiye": "turkey", "turkiye": "turkey",
        "bosnia and herzegovina": "bosniaHerzegovina",
        "slovenia": "slovenia",
        "bulgaria": "bulgaria",
        "albania": "albania",
        "north macedonia": "northMacedonia",
        "montenegro": "montenegro",
        "kosovo": "kosovo",
        "georgia": "georgia",
        "armenia": "armenia",
        "azerbaijan": "azerbaijan",
        "israel": "israel",
        "belarus": "belarus",
        "moldova": "moldova",
        "lithuania": "lithuania",
        "latvia": "latvia",
        "estonia": "estonia",
        "luxembourg": "luxembourg",
        "cyprus": "cyprus",
        "malta": "malta",
        "faroe islands": "faroeIslands",
        "kazakhstan": "kazakhstan",
        "andorra": "andorra",
        "san marino": "sanMarino",
        "liechtenstein": "liechtenstein",
        "gibraltar": "gibraltar",
        // — Amérique du Sud (CONMEBOL) —
        "brazil": "brazil",
        "argentina": "argentina",
        "uruguay": "uruguay",
        "colombia": "colombia",
        "chile": "chile",
        "peru": "peru",
        "ecuador": "ecuador",
        "paraguay": "paraguay",
        "bolivia": "bolivia",
        "venezuela": "venezuela",
        // — Amérique du Nord / Centrale & Caraïbes (CONCACAF) —
        "usa": "usa", "united states": "usa",
        "mexico": "mexico",
        "canada": "canada",
        "costa rica": "costaRica",
        "panama": "panama",
        "honduras": "honduras",
        "jamaica": "jamaica",
        "el salvador": "elSalvador",
        "guatemala": "guatemala",
        "haiti": "haiti",
        "trinidad and tobago": "trinidadAndTobago",
        "curacao": "curacao", "curaçao": "curacao",
        // — Afrique (CAF) —
        "morocco": "morocco",
        "senegal": "senegal",
        "egypt": "egypt",
        "tunisia": "tunisia",
        "algeria": "algeria",
        "nigeria": "nigeria",
        "ghana": "ghana",
        "ivory coast": "ivoryCoast", "cote d'ivoire": "ivoryCoast",
        "cameroon": "cameroon",
        "mali": "mali",
        "burkina faso": "burkinaFaso",
        "south africa": "southAfrica",
        "guinea": "guinea",
        "dr congo": "drCongo", "congo dr": "drCongo",
        "congo": "congo",
        "cape verde": "capeVerde", "cape verde islands": "capeVerde",
        "gabon": "gabon",
        "zambia": "zambia",
        "angola": "angola",
        "equatorial guinea": "equatorialGuinea",
        "uganda": "uganda",
        "kenya": "kenya",
        "benin": "benin",
        "mozambique": "mozambique",
        "madagascar": "madagascar",
        "zimbabwe": "zimbabwe",
        "mauritania": "mauritania",
        "namibia": "namibia",
        "togo": "togo",
        "libya": "libya",
        "sudan": "sudan",
        "sierra leone": "sierraLeone",
        "guinea-bissau": "guineaBissau",
        "niger": "niger",
        "malawi": "malawi",
        "tanzania": "tanzania",
        "comoros": "comoros",
        "rwanda": "rwanda",
        "ethiopia": "ethiopia",
        "burundi": "burundi",
        // — Asie (AFC) —
        "japan": "japan",
        "korea republic": "southKorea", "south korea": "southKorea",
        "korea dpr": "northKorea", "north korea": "northKorea",
        "ir iran": "iran", "iran": "iran",
        "saudi arabia": "saudiArabia",
        "australia": "australia",
        "qatar": "qatar",
        "iraq": "iraq",
        "united arab emirates": "uae", "uae": "uae",
        "china pr": "china", "china": "china",
        "uzbekistan": "uzbekistan",
        "jordan": "jordan",
        "oman": "oman",
        "bahrain": "bahrain",
        "kuwait": "kuwait",
        "syria": "syria",
        "lebanon": "lebanon",
        "palestine": "palestine",
        "india": "india",
        "vietnam": "vietnam",
        "thailand": "thailand",
        "indonesia": "indonesia",
        "malaysia": "malaysia",
        "philippines": "philippines",
        "singapore": "singapore",
        "tajikistan": "tajikistan",
        "turkmenistan": "turkmenistan",
        "kyrgyzstan": "kyrgyzstan",
        // — Océanie (OFC) —
        "new zealand": "newZealand",
        "fiji": "fiji",
        "new caledonia": "newCaledonia",
        "tahiti": "tahiti",
        "solomon islands": "solomonIslands",
        "papua new guinea": "papuaNewGuinea",
        "vanuatu": "vanuatu"
    ]

    static func localized(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
        // 1) Sélections nationales : clé `team.nat.<slug>`.
        if let natSlug = nationSlugByRawName[key] {
            let locKey = "team.nat.\(natSlug)"
            let value = L(locKey)
            if value != locKey && !value.isEmpty { return value }
        }
        // 2) Clubs dont le nom varie selon la langue : clé `team.<slug>`.
        guard let slug = slugByRawName[key] else { return raw }
        let locKey = "team.\(slug)"
        let value = L(locKey)
        // NSLocalizedString renvoie la clé elle-même si aucune traduction n'existe.
        return (value == locKey || value.isEmpty) ? raw : value
    }
}

/// Traduction des noms de COMPÉTITIONS selon la langue de l'app.
/// L'API-Football renvoie les noms en anglais (« UEFA Nations League »,
/// « World Cup - Qualification », « Friendlies »…). On mappe le nom API vers
/// une clé `comp.api.<slug>` traduite dans les 8 langues. Les qualifs de Coupe
/// du monde arrivent souvent suffixées par confédération
/// (« World Cup - Qualification Europe ») : on normalise par préfixe.
enum CompetitionNameLocalizer {
    /// Table nom API exact (normalisé minuscules) → slug de clé `comp.api.<slug>`.
    private static let slugByRawName: [String: String] = [
        "uefa nations league": "nationsLeague",
        "world cup - qualification": "worldCupQualification",
        "uefa world cup qualifiers": "worldCupQualification",
        "euro championship - qualification": "euroQualification",
        "euro championship": "euroChampionship",
        "world cup": "worldCup",
        "friendlies": "friendlies",
        "uefa champions league": "championsLeague",
        "uefa europa league": "europaLeague",
        "uefa europa conference league": "conferenceLeague",
        "uefa super cup": "superCup",
        "copa america": "copaAmerica",
        "africa cup of nations": "africaCupOfNations",
        "asian cup": "asianCup",
        "concacaf nations league": "concacafNationsLeague",
        "concacaf gold cup": "concacafGoldCup",
        "olympics football": "olympicsFootball",
        "olympics men": "olympicsFootball",
        "football - olympics men": "olympicsFootball",
        "finalissima": "finalissima"
    ]

    static func localized(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
        // 1) Correspondance exacte.
        if let slug = slugByRawName[key] {
            let value = L("comp.api.\(slug)")
            if value != "comp.api.\(slug)" && !value.isEmpty { return value }
        }
        // 2) Qualifs Coupe du monde suffixées par confédération
        //    (« world cup - qualification europe/south america/… »).
        if key.hasPrefix("world cup - qualification") || key.hasPrefix("uefa world cup qualifiers") {
            let value = L("comp.api.worldCupQualification")
            if value != "comp.api.worldCupQualification" && !value.isEmpty { return value }
        }
        // 3) Qualifs Euro suffixées.
        if key.hasPrefix("euro championship - qualification") {
            let value = L("comp.api.euroQualification")
            if value != "comp.api.euroQualification" && !value.isEmpty { return value }
        }
        return raw
    }
}

/// Traduction + ordonnancement des types de statistiques de match.
/// L'API-Football renvoie les libellés en anglais (« Shots on Goal », « Fouls »,
/// « Ball Possession », « expected_goals »…). On les mappe vers une clé de
/// localisation `stat.<slug>` (traduite dans les 8 langues) et on définit un
/// ordre d'affichage qui met les stats importantes en premier (possession, xG,
/// tirs, arrêts du gardien) plutôt que l'ordre brut de l'API.
enum StatTypeLocalizer {
    /// Type API brut (minuscules) → slug de clé `stat.<slug>`.
    private static let slugByRawType: [String: String] = [
        "ball possession":  "possession",
        "expected_goals":   "xg",
        "expected goals":   "xg",
        "total shots":      "shotsTotal",
        "shots on goal":    "shotsOn",
        "shots off goal":   "shotsOff",
        "blocked shots":    "shotsBlocked",
        "shots insidebox":  "shotsInside",
        "shots outsidebox": "shotsOutside",
        "goalkeeper saves": "saves",
        "total passes":     "passesTotal",
        "passes accurate":  "passesAccurate",
        "passes %":         "passesPct",
        "fouls":            "fouls",
        "corner kicks":     "corners",
        "offsides":         "offsides",
        "yellow cards":     "yellow",
        "red cards":        "red"
    ]

    /// Ordre d'affichage voulu (les plus « parlantes » en haut). Les types absents
    /// de cette liste passent après, dans l'ordre renvoyé par l'API.
    private static let priorityOrder: [String] = [
        "possession", "xg",
        "shotsTotal", "shotsOn", "shotsOff", "shotsBlocked",
        "shotsInside", "shotsOutside",
        "saves",
        "corners", "offsides", "fouls",
        "passesTotal", "passesAccurate", "passesPct",
        "yellow", "red"
    ]

    /// Slug normalisé pour un type brut (ou nil si inconnu).
    static func slug(for rawType: String) -> String? {
        slugByRawType[rawType.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    /// Libellé localisé pour un type brut. Repli : le type brut si non mappé.
    static func localized(_ rawType: String) -> String {
        guard let slug = slug(for: rawType) else { return rawType }
        let key = "stat.\(slug)"
        let value = L(key)
        return (value == key || value.isEmpty) ? rawType : value
    }

    /// Rang de tri d'un type brut (plus petit = plus haut). Types inconnus → grand.
    static func sortRank(for rawType: String) -> Int {
        guard let slug = slug(for: rawType),
              let idx = priorityOrder.firstIndex(of: slug) else { return 999 }
        return idx
    }
}

struct AFGoals: Codable {
    let home: Int?
    let away: Int?
}

struct AFScore: Codable {
    let halftime: AFGoals?
    let fulltime: AFGoals?
    let extratime: AFGoals?
    let penalty: AFGoals?
}

// Classements
struct AFStandingResponse: Codable {
    let league: AFStandingLeague
}

struct AFStandingLeague: Codable {
    let id: Int
    let name: String
    // Optionnel : certaines qualifs renvoient standings absent/null (pas encore
    // publié ou format à élimination) → on ne veut pas faire échouer tout le décodage.
    let standings: [[AFStandingEntry]]?
}

struct AFStandingEntry: Codable, Identifiable {
    let rank: Int
    let team: AFTeam
    let points: Int
    let goalsDiff: Int
    let group: String?
    let form: String?
    let all: AFStatBlock
    let home: AFStatBlock
    let away: AFStatBlock
    let description: String?

    var id: Int { team.id }
}

struct AFStatBlock: Codable {
    let played: Int
    let win: Int
    let draw: Int
    let lose: Int
    let goals: AFGoalsBlock
}

struct AFGoalsBlock: Codable {
    let `for`: Int
    let against: Int
}

// ─────────────────────────────────────────────────────────────────────────────
// BUTEURS / PASSEURS (endpoint players/topscorers)
// ─────────────────────────────────────────────────────────────────────────────

/// Réponse brute de /players (topscorers) : chaque entrée = un joueur + ses stats.
struct AFPlayerResponse: Codable, Identifiable {
    let player: AFPlayer
    let statistics: [AFPlayerStatistics]

    var id: Int { player.id }

    // Nom d'affichage lisible « Premier prénom + Nom court » pour TOUS les classements
    // buteurs/passeurs/combos. Objectif : « Kylian Mbappé », « Ousmane Dembélé »,
    // « Irvin Cardona », « Vinícius Júnior » — jamais l'initiale (« K. Mbappé ») ni
    // l'état civil complet (« Irvin Charly Jose Cardona », « Kylian Mbappé Lottin »,
    // « Vinícius José Paixão de Oliveira Júnior »).
    //
    // Stratégie :
    //   1. Nom court = champ `name` de l'API (typiquement « I. Cardona ») dont on
    //      retire l'initiale de prénom en tête (« I. » → « Cardona »). Si `name` n'a
    //      pas ce motif (ex. « Vinícius Júnior »), on prend au plus ses 2 premiers mots.
    //   2. Premier prénom = 1er mot de `firstname` (« Irvin Charly Jose » → « Irvin »).
    //   3. Résultat = « premier prénom + nom court », en évitant tout doublon.
    var fullName: String {
        // Surcharge manuelle éventuelle (ex. « Masour Dembélé » → « Ousmane Dembélé »).
        if let name = PlayerOverrides.lookup(lastname: player.lastname,
                                             birthDate: player.birth?.date)?.displayName {
            return name
        }
        let usual = player.name.trimmingCharacters(in: .whitespaces)

        // (1) Nom court à partir de `name`.
        let shortLast: String = {
            let parts = usual.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            // Retire TOUTES les initiales en tête (« P. M. Fall » → « Fall »,
            // « I. Cardona » → « Cardona »).
            let withoutInitials = parts.drop { $0.hasSuffix(".") }
            if !withoutInitials.isEmpty, withoutInitials.count < parts.count {
                return withoutInitials.joined(separator: " ")
            }
            // Pas d'initiale : garde au plus 2 mots (« Vinícius Júnior »), tronque le reste.
            return parts.prefix(2).joined(separator: " ")
        }()

        // (2) Premier prénom seulement.
        let firstFull = player.firstname?.trimmingCharacters(in: .whitespaces) ?? ""
        let first = firstFull.split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? ""

        // (3) Composition + garde-fous.
        if !first.isEmpty && !shortLast.isEmpty {
            // Si le nom court contient déjà le prénom, on le garde seul (pas de doublon).
            if shortLast.lowercased().contains(first.lowercased()) { return shortLast }
            // Quand on compose « prénom + nom » et que le nom court comporte encore
            // plusieurs mots (état civil : « Mbappé Lottin »), on ne garde que le
            // PREMIER mot du nom → « Kylian Mbappé » et pas « Kylian Mbappé Lottin ».
            let lastWords = shortLast.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            if lastWords.count > 1, let firstLast = lastWords.first {
                return "\(first) \(firstLast)"
            }
            return "\(first) \(shortLast)"
        }
        if !shortLast.isEmpty { return shortLast }
        if !usual.isEmpty { return usual }
        let last = player.lastname?.trimmingCharacters(in: .whitespaces) ?? ""
        return "\(first) \(last)".trimmingCharacters(in: .whitespaces)
    }

    /// Poste à afficher sur la fiche, LOCALISÉ et au singulier (« Attaquant »).
    /// Applique la surcharge manuelle si elle existe (ex. Dembélé/Barcola/Thuram/Doué
    /// mal classés « Midfielder » → « Attacker »), sinon la valeur brute de l'API.
    /// `nil` si le poste est inconnu → on n'affiche pas la ligne (règle d'or).
    var displayPosition: String? {
        let override = PlayerOverrides.lookup(lastname: player.lastname,
                                              birthDate: player.birth?.date)?.position
        let raw = override ?? statistics.first?.games.position
        guard let raw, !raw.isEmpty else { return nil }
        let normalized = FantasyPosition(apiValue: raw)
        guard normalized != .unknown else { return nil }
        return L(normalized.singularTitleKey)
    }

    // Nom de l'équipe à afficher sous la fiche joueur = son CLUB (Real Madrid pour
    // Mbappé), JAMAIS sa sélection nationale. `statistics.first` peut être une ligne
    // de SÉLECTION (l'API mêle club et sélection) → on privilégie `clubTeamName`
    // (1re ligne de club) et on ne retombe sur `statistics.first` qu'en dernier recours.
    // On passe par TeamNameFormatter.pretty pour normaliser les CAPITALES (« RED Star
    // FC 93 » → « Red Star FC 93 »), comme AFTeam.displayName pour les classements.
    var teamName: String {
        clubTeamName ?? TeamNameFormatter.pretty(statistics.first?.team.name ?? "")
    }
    var goals: Int { statistics.first?.goals.total ?? 0 }
    var assists: Int { statistics.first?.goals.assists ?? 0 }
    var appearances: Int { statistics.first?.games.appearences ?? 0 }
    var penalties: Int { statistics.first?.penalty?.scored ?? 0 }

    // ── Agrégats TOUTES compétitions (endpoint /players) ─────────────────────
    // /players renvoie une ligne de stats PAR compétition. Pour le vivier fantasy
    // on additionne l'ensemble (buts/passes/matchs toutes comps confondues), ce qui
    // évite de manquer les stats d'un joueur selon l'ordre des blocs renvoyés.
    var totalGoals: Int { statistics.reduce(0) { $0 + ($1.goals.total ?? 0) } }
    var totalAssists: Int { statistics.reduce(0) { $0 + ($1.goals.assists ?? 0) } }
    var totalAppearances: Int { statistics.reduce(0) { $0 + ($1.games.appearences ?? 0) } }

    // ── Sélection nationale (SAISON courante uniquement) ─────────────────────
    // API-Football renvoie une ligne de stats par compétition. Les compétitions
    // de SÉLECTIONS ont `league.country == "World"` (Coupe du monde, Euro, Ligue
    // des Nations, qualifs…). On somme UNIQUEMENT ces lignes → matchs et buts en
    // équipe nationale sur la saison. Ce n'est PAS un total carrière (l'API ne le
    // fournit pas) ; le libellé côté vue précise « (saison) » pour rester honnête.
    // Prédicat : cette ligne de stats est-elle une compétition de SÉLECTION ?
    // Extrait pour être réutilisé par nationalLines ET clubLines (une ligne club
    // = « pas une ligne sélection »). Évite toute comparaison structurelle de struct.
    private static func isNationalLine(_ s: AFPlayerStatistics) -> Bool {
        let country = (s.league?.country ?? "").lowercased()
        let name = (s.league?.name ?? "").lowercased()
        // ⚠️ COUPES DE CLUBS UEFA/mondiales à exclure AVANT tout : l'API leur met
        // souvent country == "World" (ex. « UEFA Super Cup », « UEFA Champions
        // League », Coupe du monde des CLUBS) → sinon prises pour des sélections.
        // Une Super Cup jouée par le PSG n'est PAS une sélection.
        let clubIntl = ["uefa super cup", "super cup",
                        "champions league", "europa", "conference league",
                        "club world cup", "intercontinental"]
        if clubIntl.contains(where: { name.contains($0) }) { return false }
        if country == "world" { return true }
        // ⚠️ Certaines compétitions internationales ont country == nil
        // (ex. « UEFA World Cup Qualifiers » → country=None dans l'API).
        // On rattrape ces lignes par le NOM de la compétition, sinon les
        // matchs de qualifs en sélection seraient omis du total saison.
        let markers = ["world cup", "qualifier", "nations league",
                       "euro", "friendlies", "copa america", "africa cup",
                       "afcon", "asian cup", "gold cup", "olympic",
                       "confederations", "concacaf nations"]
        return markers.contains { name.contains($0) }
    }

    // ── Éditions de SÉLECTION TERMINÉES avant le début de la saison de CLUB ────
    // ⚠️ PIÈGE API : `/players?id=&season=2026` agrège TOUTES les lignes indexées
    // sur l'année 2026 côté API, y compris les tournois de sélection JOUÉS à
    // l'ÉTÉ 2026 (Coupe du monde 2026 juin-juil., phase finale Ligue des Nations)
    // — donc AVANT la reprise des championnats 2026-27. Ces lignes gonflent le
    // total « Sélection » d'un joueur qui n'a pas (encore) rejoué en sélection sur
    // la campagne 2026-27 (cas signalé : Désiré Doué → ~12 sélections fantômes).
    // Faute de date par match (l'endpoint stats ne les fournit pas), on EXCLUT ces
    // éditions estivales par NOM de compétition. La liste est volontairement
    // restrictive (tournois à édition figée déjà terminés). 0 requête.
    // ⚠️ NE PAS inclure la Ligue des Nations « courante » à cheval (2026-27) : ici
    // c'est la PHASE FINALE de l'édition PRÉCÉDENTE, jouée en été, qu'on écarte —
    // marquée par l'API sous des libellés « Finals »/« Final Four ».
    private static func isStalePreseasonNationalLine(_ s: AFPlayerStatistics) -> Bool {
        guard isNationalLine(s) else { return false }
        let name = (s.league?.name ?? "").lowercased()
        // ── Règle GÉNÉRALE : on ne RETIENT une ligne de sélection pour la saison
        //    2026-27 que si c'est une compétition COMPÉTITIVE EN COURS, c.-à-d. une
        //    phase de QUALIFICATION (qualifs Euro/CDM, à cheval sur l'année civile).
        //    Tout le reste (amicaux, tournois à édition figée déjà joués à l'été
        //    2026 : Coupe du monde, Euro, phases finales Nations League, Jeux
        //    olympiques, tournois de jeunes U21/U23…) est ÉCARTÉ des STATS de
        //    sélection. L'IDENTITÉ « international français » reste préservée via
        //    `allNationalLines` (non filtré). 0 requête.
        // ⚠️ EXCEPTION AVANT le test « qualif » générique : les QUALIFS de la Coupe
        //    du Monde 2026 (« UEFA World Cup Qualifiers », etc.) sont TERMINÉES (CDM
        //    juin-juillet 2026 déjà jouée) → elles appartiennent à la saison
        //    PRÉCÉDENTE, PAS à 2026-27. On les écarte donc, même si le nom contient
        //    « qualif ». La prochaine campagne CDM (2030) ne rouvre pas avant fin
        //    2027/2028, donc aucune qualif CDM « en cours » à préserver aujourd'hui.
        if name.contains("world cup") { return true }             // qualifs + phase finale CDM 2026
        // Règle GÉNÉRALE : on GARDE les autres phases de QUALIFICATION en cours
        // (ex. « Euro Championship - Qualification » pour l'Euro 2028), à cheval
        // sur l'année civile → compétitives pour la saison 2026-27.
        let isQualifier = name.contains("qualif")   // « … Qualifiers », « Qualification »
        if isQualifier { return false }             // qualif en cours → on GARDE
        // Amicaux internationaux : jamais une sélection « compétitive » de saison.
        if name.contains("friendl") || name.contains("amical") { return true }
        if name.contains("nations league") { return true }        // finales été (les qualifs sont déjà sorties plus haut)
        if name.contains("olympic") { return true }               // Jeux olympiques
        if name.contains("u21") || name.contains("u-21")
            || name.contains("u23") || name.contains("u-23")
            || name.contains("under 21") || name.contains("under-21")
            || name.contains("under 23") || name.contains("under-23") { return true }
        if name.contains("euro") { return true }                  // Euro (phase finale été), qualifs déjà exclues
        if name.contains("copa america") { return true }
        if name.contains("gold cup") || name.contains("concacaf nations") { return true }
        if name.contains("africa cup") || name.contains("afcon") { return true }
        if name.contains("asian cup") { return true }
        if name.contains("confederations") { return true }
        return false
    }

    // Lignes de sélection RETENUES pour les stats (été 2026 écarté). L'IDENTITÉ de
    // la sélection (nationalTeamId/Name/Logo) utilise la liste NON filtrée pour ne
    // pas perdre « France » dans l'en-tête quand le joueur n'a rejoué qu'en été.
    private var nationalLines: [AFPlayerStatistics] {
        statistics.filter { Self.isNationalLine($0) && !Self.isStalePreseasonNationalLine($0) }
    }
    /// Toutes les lignes de sélection, y compris l'été (pour l'identité seulement).
    private var allNationalLines: [AFPlayerStatistics] {
        statistics.filter { Self.isNationalLine($0) }
    }
    /// Vrai si le joueur a au moins une ligne de sélection RETENUE cette saison.
    var hasNationalStats: Bool { !nationalLines.isEmpty }
    var nationalAppearances: Int { nationalLines.reduce(0) { $0 + ($1.games.appearences ?? 0) } }
    var nationalGoals: Int { nationalLines.reduce(0) { $0 + ($1.goals.total ?? 0) } }

    // ── RÉPARTITION des matchs JOUÉS cette saison par TYPE de compétition ─────
    // Demande user : ventiler les matchs de la saison en amical / championnat /
    // coupe nationale / coupe d'Europe / nations. L'API ne fournit pas de champ
    // `type` fiable → on classe chaque ligne de stats par HEURISTIQUE sur le nom
    // (et le pays) de la compétition, dans un ordre de priorité qui évite les
    // faux positifs (« europa » testé avant « euro », etc.).
    enum CompetitionCategory: String, CaseIterable {
        case friendly       // amical (clubs ou sélections)
        case league         // championnat national
        case nationalCup    // coupe nationale (Coupe de France, FA Cup…)
        case europeanCup    // coupe d'Europe de CLUBS (LDC, Ligue Europa, Conf.)
        case nations        // compétitions de SÉLECTIONS (Euro, CDM, Nations…)

        /// Clé de localisation du libellé affiché.
        var titleKey: String { "player.comp.\(rawValue)" }
    }

    /// Classe une ligne de stats dans une catégorie de compétition.
    private static func category(for s: AFPlayerStatistics) -> CompetitionCategory {
        let name = (s.league?.name ?? "").lowercased()
        let country = (s.league?.country ?? "").lowercased()
        // 1) Amical : marqueur explicite (clubs ou sélections).
        if name.contains("friendl") || name.contains("amical") { return .friendly }
        // 2) Sélections nationales (réutilise le prédicat maître pour cohérence).
        if isNationalLine(s) { return .nations }
        // 3) Coupes d'Europe de CLUBS (avant « cup » générique).
        //    ⚠️ « uefa super cup » (Supercoupe d'Europe) explicitement, PAS le
        //    « super cup » générique — sinon les SUPERCOUPES NATIONALES (Trophée
        //    des Champions FR = « Super Cup » côté API pour certaines saisons,
        //    Community Shield, Supercopa, Supercoppa…) seraient prises à tort
        //    pour des coupes d'Europe. On teste le pays juste après.
        let euroClub = ["champions league", "europa league", "europa conference",
                        "conference league", "uefa super cup"]
        if euroClub.contains(where: { name.contains($0) }) { return .europeanCup }
        // 4) Coupe nationale : marqueur « cup / coupe / copa / pokal / trophy » +
        //    les SUPERCOUPES nationales (Trophée des Champions, Community Shield,
        //    Supercopa/Supercoppa/Supercup) et les « trophée/trophy » (le nom FR
        //    « Trophée des Champions » ne contient PAS « trophy » → ajouter « trophée »).
        let cupMarkers = ["cup", "coupe", "copa", "pokal", "trophy", "trophée", "trophée des champions",
                          "coppa", "taça", "beker", "community shield", "supercopa",
                          "supercoppa", "supercup", "super cup", "super copa"]
        if cupMarkers.contains(where: { name.contains($0) }) { return .nationalCup }
        // 5) Par défaut : championnat national (Ligue 1, Premier League, Serie A…).
        _ = country
        return .league
    }

    /// Nombre de matchs JOUÉS cette saison, ventilé par catégorie. On somme les
    /// `appearences` de chaque ligne. Seules les catégories avec ≥ 1 match sont
    /// renvoyées (règle d'or : on n'affiche pas de 0 inventé), ordre stable.
    var appearancesByCategory: [(category: CompetitionCategory, count: Int)] {
        var totals: [CompetitionCategory: Int] = [:]
        for line in statistics {
            // Écarte les tournois de sélection estivaux déjà terminés (cf.
            // isStalePreseasonNationalLine) pour ne pas gonfler la répartition.
            if Self.isStalePreseasonNationalLine(line) { continue }
            let apps = line.games.appearences ?? 0
            guard apps > 0 else { continue }
            totals[Self.category(for: line), default: 0] += apps
        }
        return CompetitionCategory.allCases.compactMap { cat in
            guard let c = totals[cat], c > 0 else { return nil }
            return (cat, c)
        }
    }

    // ── Stats CLUB uniquement (SAISON) ───────────────────────────────────────
    // La fiche joueur veut les stats du joueur DANS SON CLUB, pas en sélection.
    // Lignes club = toutes les lignes SAUF les lignes de sélection. Ainsi un
    // international ne voit pas ses matchs en équipe nationale gonfler le total.
    private var clubLines: [AFPlayerStatistics] {
        statistics.filter { !Self.isNationalLine($0) }
    }
    var clubAppearances: Int { clubLines.reduce(0) { $0 + ($1.games.appearences ?? 0) } }
    var clubGoals: Int { clubLines.reduce(0) { $0 + ($1.goals.total ?? 0) } }
    var clubAssists: Int { clubLines.reduce(0) { $0 + ($1.goals.assists ?? 0) } }
    var clubLineups: Int { clubLines.reduce(0) { $0 + ($1.games.lineups ?? 0) } }
    var clubMinutes: Int { clubLines.reduce(0) { $0 + ($1.games.minutes ?? 0) } }
    var clubYellowCards: Int { clubLines.reduce(0) { $0 + ($1.cards?.yellow ?? 0) } }
    // Rouge = rouge direct + 2e jaune (yellowred), les deux valent une expulsion.
    var clubRedCards: Int {
        clubLines.reduce(0) { $0 + ($1.cards?.red ?? 0) + ($1.cards?.yellowred ?? 0) }
    }
    /// Note moyenne club, pondérée par le nombre de matchs de chaque ligne.
    /// `nil` si aucune ligne club ne fournit de note (fréquent en divisions basses).
    var clubRating: Double? {
        var weightedSum = 0.0
        var totalApps = 0
        for line in clubLines {
            guard let r = line.games.rating, let value = Double(r) else { continue }
            let apps = max(line.games.appearences ?? 0, 1)
            weightedSum += value * Double(apps)
            totalApps += apps
        }
        return totalApps > 0 ? weightedSum / Double(totalApps) : nil
    }

    // ── CLUB actuel du joueur (id + nom) ─────────────────────────────────────
    // ⚠️ `statistics.first` peut être une ligne de SÉLECTION NATIONALE (l'API mêle
    // club et sélection dans le même tableau). Pour « suivre un joueur » et afficher
    // le prochain match de SON CLUB (ex. Real Madrid pour Mbappé, PAS l'équipe de
    // France), on doit prendre la 1re ligne de CLUB, jamais une sélection.
    // JAMAIS de repli sur `statistics.first` : ce serait potentiellement une ligne
    // de SÉLECTION (ex. Mbappé en début de saison n'a qu'une ligne France) et on
    // afficherait « France » comme club, ce qui est faux. Si aucune ligne CLUB
    // n'existe cette saison → `nil`, et l'appelant se rabat sur Wikidata (club de
    // carrière) plutôt que sur une sélection.
    var clubTeamId: Int? {
        clubLines.first?.team.id
    }
    var clubTeamName: String? {
        guard let raw = clubLines.first?.team.name, !raw.isEmpty else { return nil }
        return TeamNameFormatter.pretty(raw)
    }

    // ── SÉLECTION NATIONALE du joueur (id + nom) ─────────────────────────────
    // Symétrique de `clubTeamId` : la 1re ligne de SÉLECTION (France pour Mbappé).
    // Sert à afficher le prochain match de la sélection du joueur dans l'onglet
    // « Joueurs » de l'accueil (championnat + coupe + nations). `nil` si le joueur
    // n'a aucune ligne de sélection cette saison → on n'affiche alors que le club.
    // IDENTITÉ de la sélection : liste NON filtrée (l'été 2026 compte pour savoir
    // QUE le joueur est international français, même s'il n'a pas rejoué depuis).
    var nationalTeamId: Int? { allNationalLines.first?.team.id }
    var nationalTeamName: String? {
        guard let raw = allNationalLines.first?.team.name, !raw.isEmpty else { return nil }
        return TeamNameFormatter.pretty(raw)
    }

    // ── CLUB actuel : logo (pour l'en-tête de la fiche) ──────────────────────
    // Même source que clubTeamId/clubTeamName : la 1re ligne de CLUB. nil si le
    // joueur n'a joué qu'en sélection cette saison (l'en-tête se rabat alors sur
    // le club résolu via /players/teams côté vue).
    var clubTeamLogo: String? { clubLines.first?.team.logo }

    // ── SÉLECTION : logo (drapeau/blason de la fédération) ────────────────────
    // Identité → liste non filtrée (cf. nationalTeamId).
    var nationalTeamLogo: String? { allNationalLines.first?.team.logo }

    // ─────────────────────────────────────────────────────────────────────────
    // STATS AGRÉGÉES PAR CATÉGORIE (pour les sous-chips de la fiche joueur)
    // -------------------------------------------------------------------------
    // Chaque `AFPlayerStatistics` = une ligne par compétition. Pour la fiche, on
    // regroupe ces lignes en 4 « buckets » sélectionnables (Championnat, Coupes,
    // Sélection, Amicaux) + un bucket TOTAL club. Les Coupes sont en plus
    // détaillées par compétition réelle (LDC, Coupe de France…), demande user :
    // « une sous-chip par compétition jouée ». Aucun trophée inventé : on ne
    // montre QUE des matchs/buts par comp (l'API des stats saison ne dit pas si
    // un titre a été gagné).
    // ─────────────────────────────────────────────────────────────────────────

    /// Agrégat de stats d'un ensemble de lignes (une catégorie ou une comp).
    struct StatBucket {
        var appearances = 0
        var lineups = 0
        var minutes = 0
        var goals = 0
        var assists = 0
        var yellowCards = 0
        var redCards = 0
        // Note moyenne pondérée par le nb de matchs (nil si aucune note fournie).
        var rating: Double? = nil

        /// Vrai si le bucket porte au moins une donnée exploitable.
        var hasData: Bool {
            appearances > 0 || goals > 0 || assists > 0 || minutes > 0
                || yellowCards > 0 || redCards > 0
        }
    }

    /// Construit un `StatBucket` à partir d'un lot de lignes de stats.
    private static func aggregate(_ lines: [AFPlayerStatistics]) -> StatBucket {
        var b = StatBucket()
        var weightedRating = 0.0
        var ratedApps = 0
        for l in lines {
            let apps = l.games.appearences ?? 0
            b.appearances += apps
            b.lineups += l.games.lineups ?? 0
            b.minutes += l.games.minutes ?? 0
            b.goals += l.goals.total ?? 0
            b.assists += l.goals.assists ?? 0
            b.yellowCards += l.cards?.yellow ?? 0
            b.redCards += (l.cards?.red ?? 0) + (l.cards?.yellowred ?? 0)
            if let r = l.games.rating, let v = Double(r) {
                let w = max(apps, 1)
                weightedRating += v * Double(w)
                ratedApps += w
            }
        }
        if ratedApps > 0 { b.rating = weightedRating / Double(ratedApps) }
        return b
    }

    /// Une sous-comp de coupe (LDC, Coupe de France…) avec son bucket + logo.
    struct CompetitionBucket: Identifiable {
        let name: String        // nom localisé/joli de la compétition
        let logo: String?       // logo de la ligue (peut être nil)
        let bucket: StatBucket
        var id: String { name }
    }

    /// Toutes les catégories présentes cette saison (≥ 1 match), dans l'ordre
    /// d'affichage des sous-chips. `.league`, `.nations`, `.friendly` → un seul
    /// bucket ; `.nationalCup`/`.europeanCup` sont fusionnées sous « Coupes ».
    /// L'appelant complète avec la chip TOTAL.
    var leagueBucket: StatBucket {
        Self.aggregate(statistics.filter { Self.category(for: $0) == .league })
    }
    /// Nom du CHAMPIONNAT du joueur cette saison (« Ligue 1 »), même s'il n'y a
    /// pas encore joué de match (affiché sous la sous-chip Championnat à 0).
    /// nil si aucune ligne de championnat (rare : joueur sans club de saison).
    var leagueName: String? {
        guard let raw = statistics.first(where: { Self.category(for: $0) == .league })?
            .league?.name, !raw.isEmpty else { return nil }
        return TeamNameFormatter.pretty(raw)
    }
    var nationsBucket: StatBucket {
        // Lignes de sélection RETENUES (été 2026 déjà écarté par nationalLines).
        Self.aggregate(nationalLines)
    }
    var friendlyBucket: StatBucket {
        Self.aggregate(statistics.filter { Self.category(for: $0) == .friendly })
    }
    /// Total CLUB (toutes lignes non-sélection) — pour la chip « Total ».
    var clubTotalBucket: StatBucket { Self.aggregate(clubLines) }
    /// Total SÉLECTION (toutes lignes de sélection).
    var nationalTotalBucket: StatBucket { Self.aggregate(nationalLines) }

    /// Détail des COUPES (Europe + nationale), une entrée par compétition réelle
    /// où le joueur a ≥ 1 match. Ordre : coupes d'Europe d'abord, puis nationales.
    var cupCompetitions: [CompetitionBucket] {
        let cupLines = statistics.filter {
            let c = Self.category(for: $0)
            return c == .europeanCup || c == .nationalCup
        }
        // Regroupe par nom de compétition (plusieurs lignes possibles par comp).
        var order: [String] = []
        var grouped: [String: [AFPlayerStatistics]] = [:]
        for l in cupLines {
            guard (l.games.appearences ?? 0) > 0 else { continue }
            let key = (l.league?.name ?? "").isEmpty ? l.team.name : (l.league?.name ?? "")
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(l)
        }
        // Europe avant nationale : trie sur la catégorie de la 1re ligne.
        func isEuro(_ key: String) -> Bool {
            guard let first = grouped[key]?.first else { return false }
            return Self.category(for: first) == .europeanCup
        }
        let sortedKeys = order.sorted { a, b in
            let ea = isEuro(a), eb = isEuro(b)
            if ea != eb { return ea }        // Europe d'abord
            return a < b
        }
        return sortedKeys.map { key in
            let lines = grouped[key] ?? []
            return CompetitionBucket(name: TeamNameFormatter.pretty(key),
                                     logo: lines.first?.team.logo,
                                     bucket: Self.aggregate(lines))
        }
    }
    /// Cumul de TOUTES les coupes (pour l'en-tête de la sous-chip « Coupes »).
    var cupsTotalBucket: StatBucket {
        Self.aggregate(statistics.filter {
            let c = Self.category(for: $0)
            return c == .europeanCup || c == .nationalCup
        })
    }

    /// Détail des SÉLECTIONS (une entrée par compétition de sélection RETENUE,
    /// c.-à-d. hors éditions estivales déjà terminées). Permet d'afficher QUELLE
    /// compétition explique le total (ex. « Euro U21 Qualification »). Une ligne
    /// par compétition avec ≥ 1 match.
    var nationCompetitions: [CompetitionBucket] {
        var order: [String] = []
        var grouped: [String: [AFPlayerStatistics]] = [:]
        for l in nationalLines {
            guard (l.games.appearences ?? 0) > 0 else { continue }
            let key = (l.league?.name ?? "").isEmpty ? l.team.name : (l.league?.name ?? "")
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(l)
        }
        return order.map { key in
            let lines = grouped[key] ?? []
            return CompetitionBucket(name: TeamNameFormatter.pretty(key),
                                     logo: lines.first?.team.logo,
                                     bucket: Self.aggregate(lines))
        }
    }
}

struct AFPlayer: Codable {
    let id: Int
    let name: String
    let firstname: String?
    let lastname: String?
    let age: Int?
    let nationality: String?
    let photo: String?
    // Champs biographiques fournis par /players?id= (vérifiés via curl 2026-08-16) :
    // birth {date "AAAA-MM-JJ", place, country}, height "191" (cm, en String !),
    // weight "80" (kg, en String !). Optionnels → décodage sûr.
    let birth: AFPlayerBirth?
    let height: String?
    let weight: String?
}

/// Résultat de recherche de joueur (/players/profiles?search=). Ne contient que
/// l'identité, pas de statistiques. Sert à la liste de résultats de la recherche.
struct AFPlayerProfileEntry: Codable {
    let player: AFPlayerProfile
}

struct AFPlayerProfile: Codable, Identifiable {
    let id: Int
    let name: String?
    let firstname: String?
    let lastname: String?
    let nationality: String?
    let photo: String?

    /// Club actuel, résolu APRÈS coup par `searchPlayers` (via /players/teams) pour
    /// désambiguïser les homonymes dans la liste de résultats (« Dembélé » ×N).
    /// NON décodé depuis l'API (l'endpoint /players/profiles ne fournit pas le club) :
    /// exclu de Codable via les CodingKeys ci-dessous. nil = non résolu / sans club.
    var resolvedClubName: String? = nil
    /// ID du club résolu — sert au TRI par notoriété dans `searchPlayers`
    /// (club du catalogue en tête). nil = non résolu ou sans club.
    var resolvedClubId: Int? = nil

    private enum CodingKeys: String, CodingKey {
        case id, name, firstname, lastname, nationality, photo
    }

    /// Nom prêt à l'affichage : NOM COMPLET brut renvoyé par l'API (« Prénom Nom »),
    /// sinon `name`. On N'APPLIQUE PLUS d'heuristique de troncature (elle produisait
    /// des noms faux — « Ethan Lottin » au lieu d'« Ethan Mbappé » — car le patronyme
    /// n'est pas toujours le dernier mot). Décision user 2026-08-18 : afficher le nom
    /// complet, quitte à ce qu'il soit un peu long, plutôt que de deviner à tort.
    ///
    /// Seule correction conservée : la surcharge par NOM COMPLET, utilisée quand
    /// l'API renvoie un PRÉNOM ERRONÉ (ex. Dembélé indexé « Masour » au lieu
    /// d'« Ousmane » → on ne le retrouve pas en cherchant « Ousmane »). La table
    /// remplace alors le nom complet par la version correcte.
    var displayName: String {
        let f = firstname?.trimmingCharacters(in: .whitespaces) ?? ""
        let l = lastname?.trimmingCharacters(in: .whitespaces) ?? ""
        let composed = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        let raw = composed.isEmpty ? (name ?? "").trimmingCharacters(in: .whitespaces) : composed
        if let override = PlayerOverrides.displayName(forFullName: raw) { return override }
        return raw
    }
}

/// Naissance d'un joueur (bloc "birth" d'API-Football).
struct AFPlayerBirth: Codable {
    let date: String?     // "AAAA-MM-JJ"
    let place: String?
    let country: String?
}

struct AFPlayerStatistics: Codable {
    let team: AFTeam
    let league: AFPlayerLeague?
    let games: AFPlayerGames
    let goals: AFPlayerGoals
    let penalty: AFPlayerPenalty?
    let cards: AFPlayerCards?   // cartons jaunes / rouges de la ligne
}

/// Ligue légère d'une ligne de stats joueur — sert à repérer les compétitions
/// de sélections (`country == "World"`) pour compter matchs/buts en équipe nationale.
struct AFPlayerLeague: Codable {
    let name: String?
    let country: String?
}

struct AFPlayerGames: Codable {
    let appearences: Int?   // orthographe volontaire : l'API renvoie "appearences"
    let lineups: Int?       // titularisations (matchs commencés)
    let minutes: Int?
    let position: String?
    // La note moyenne API-Football arrive en String ("7.235294") ou absente/null.
    // On la garde brute et on la formate côté vue (1 décimale).
    let rating: String?
}

struct AFPlayerGoals: Codable {
    let total: Int?
    let assists: Int?
}

struct AFPlayerPenalty: Codable {
    let scored: Int?
    let missed: Int?
}

/// Cartons d'une ligne de stats joueur (bloc "cards" d'API-Football).
struct AFPlayerCards: Codable {
    let yellow: Int?
    let yellowred: Int?   // 2e jaune synonyme d'expulsion → compté avec les rouges
    let red: Int?
}

// ─────────────────────────────────────────────────────────────────────────────
// FICHE JOUEUR ENRICHIE (Wikidata via le proxy : /wikidata/player?name=)
// -----------------------------------------------------------------------------
// API-Football ne donne que les stats de la SAISON. Wikidata apporte les
// ATTRIBUTS CARRIÈRE : total sélections A, parcours clubs (avec dates), club
// actuel + arrivée, distinctions, compétitions majeures, physique, photo, et un
// identifiant Transfermarkt (pour un lien, pas une valeur marchande inventée).
// Tout est nullable : un joueur de Ligue 2 a souvent juste le parcours + le
// physique. La vue masque proprement les sections vides.
// ─────────────────────────────────────────────────────────────────────────────

/// Un club actuel (nom + date d'arrivée « since »).
struct WikidataClub: Codable {
    let name: String
    let since: String?   // "AAAA-MM-JJ" (souvent au 1er janvier : année seule fiable)
}

/// Un passage en club (nom + période + nb de matchs éventuels).
struct WikidataStint: Codable, Identifiable {
    let name: String
    let start: String?
    let end: String?
    let apps: Int?
    // Pas d'`id` dans le JSON : on en fabrique un stable pour SwiftUI (ForEach).
    var id: String { "\(name)|\(start ?? "?")|\(end ?? "?")" }
}

/// Fiche carrière renvoyée par le proxy (source Wikidata). Tous les champs sont
/// optionnels : on affiche ce qui existe, on masque le reste.
struct WikidataPlayer: Codable {
    let qid: String?
    let nationalTeam: String?
    let nationalCaps: Int?
    let nationalGoals: Int?      // buts en sélection A (P1351), nullable
    let currentClub: WikidataClub?
    let previousClubs: [WikidataStint]?
    let height: Double?          // en mètres (ex. 1.78)
    let weight: Double?          // en kg
    let birthDate: String?       // "AAAA-MM-JJ"
    let birthPlace: String?
    let awards: [String]?
    let majorCompetitions: [String]?
    let photoUrl: String?
    let transfermarktId: String?

    /// URL de profil Transfermarkt (le slug est ignoré, seul l'id compte).
    var transfermarktURL: URL? {
        guard let id = transfermarktId, !id.isEmpty else { return nil }
        return URL(string: "https://www.transfermarkt.com/x/profil/spieler/\(id)")
    }

    /// Vrai si la fiche apporte au moins une info exploitable (sinon on n'affiche
    /// aucune section Wikidata).
    var hasAnyContent: Bool {
        (nationalCaps ?? 0) > 0
            || currentClub != nil
            || !(previousClubs ?? []).isEmpty
            || height != nil || weight != nil
            || birthDate != nil || birthPlace != nil
            || !(awards ?? []).isEmpty
            || !(majorCompetitions ?? []).isEmpty
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// CLUBS D'UN JOUEUR (endpoint /players/teams?player= : liste équipes + saisons)
// ─────────────────────────────────────────────────────────────────────────────
// Source AUTORITAIRE du club actuel, INDÉPENDANTE des stats de match : renvoie
// toutes les équipes (clubs + sélections) auxquelles le joueur a appartenu, avec
// les saisons. Contrairement à /players?id=&season= (vide en début de saison tant
// que le club n'a pas joué), cet endpoint connaît toujours l'appartenance actuelle.
// Sert à afficher « Real Madrid » sous Mbappé même avant le 1er match de La Liga.

/// Une entrée de /players/teams : une équipe + les saisons où le joueur y a joué.
struct AFPlayerTeamEntry: Codable {
    let team: AFTeamInfo
    let seasons: [Int]?
}

// ─────────────────────────────────────────────────────────────────────────────
// EFFECTIF D'UNE ÉQUIPE (endpoint /players/squads?team= : 1 appel léger)
// ─────────────────────────────────────────────────────────────────────────────

/// Réponse de /players/squads : une équipe + la liste de ses joueurs (sans stats).
struct AFSquadResponse: Codable {
    let team: AFTeamInfo
    let players: [AFSquadPlayer]
}

/// Un joueur de l'effectif (données légères de /players/squads).
struct AFSquadPlayer: Codable, Identifiable {
    let id: Int
    let name: String
    let age: Int?
    let number: Int?
    let position: String?   // "Goalkeeper", "Defender", "Midfielder", "Attacker"
    let photo: String?

    /// Poste normalisé (pour regrouper l'effectif par ligne).
    /// Applique d'abord une éventuelle correction manuelle par nom (ex. Dembélé,
    /// Barcola, Thuram, Doué mal classés « Midfielder » par l'API) pour rester
    /// COHÉRENT avec le poste affiché sur la fiche du joueur.
    var posGroup: SquadPosition {
        let effective = PlayerOverrides.position(forDisplayName: name) ?? position
        switch (effective ?? "").lowercased() {
        case let p where p.contains("keeper"):   return .goalkeeper
        case let p where p.contains("defender"): return .defender
        case let p where p.contains("midfield"): return .midfielder
        case let p where p.contains("attack"):   return .attacker
        default:                                  return .other
        }
    }
}

/// Regroupement de l'effectif par ligne (ordre d'affichage : G, D, M, A).
enum SquadPosition: Int, CaseIterable {
    case goalkeeper, defender, midfielder, attacker, other
    var titleKey: String {
        switch self {
        case .goalkeeper: return "squad.goalkeepers"
        case .defender:   return "squad.defenders"
        case .midfielder: return "squad.midfielders"
        case .attacker:   return "squad.attackers"
        case .other:      return "squad.others"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// DÉTAIL D'UN MATCH (endpoint fixtures?id= : événements, compos, stats)
// ─────────────────────────────────────────────────────────────────────────────

/// Réponse détaillée d'un match : le fixture complet + événements + compos + stats.
struct AFFixtureFull: Codable {
    let fixture: AFFixtureDetail
    let league: AFLeague
    let teams: AFTeams
    let goals: AFGoals
    let score: AFScore?
    let events: [AFEvent]?
    // `var` (et non `let`) : on peut y réinjecter les compos de l'endpoint dédié
    // `/fixtures/lineups` quand `/fixtures?id=` renvoie un coach/une formation vides.
    var lineups: [AFLineup]?
    let statistics: [AFTeamStatistics]?
}

/// Un événement de match : but, carton, remplacement…
struct AFEvent: Codable, Identifiable {
    let time: AFEventTime
    let team: AFTeam
    let player: AFEventPlayer
    let assist: AFEventPlayer?
    let type: String          // "Goal", "Card", "subst", "Var"
    let detail: String        // "Normal Goal", "Yellow Card", "Substitution 1"…
    let comments: String?

    // Identifiant synthétique (l'API ne fournit pas d'id d'événement)
    var id: String {
        "\(time.elapsed)-\(team.id)-\(player.id ?? 0)-\(type)-\(detail)"
    }

    var minuteLabel: String {
        if let extra = time.extra, extra > 0 { return "\(time.elapsed)+\(extra)'" }
        return "\(time.elapsed)'"
    }

    var isGoal: Bool { type == "Goal" }
    var isCard: Bool { type == "Card" }
    var isSub:  Bool { type.lowercased() == "subst" }

    /// But sur penalty (`detail` = "Penalty").
    var isPenaltyGoal: Bool { isGoal && detail.lowercased().contains("penalty") }
    /// But contre son camp (`detail` = "Own Goal").
    var isOwnGoal: Bool { isGoal && detail.lowercased().contains("own") }
    /// Mention courte à accoler au buteur quand le but n'a pas de passeur « normal »
    /// (penalty / csc). Sert de repère explicite à l'utilisateur (clé de trad).
    var goalDetailKey: String? {
        if isPenaltyGoal { return "goal.penalty" }
        if isOwnGoal { return "goal.ownGoal" }
        return nil
    }

    /// Icône SF Symbol correspondant au type d'événement.
    var symbol: String {
        if isGoal { return "soccerball" }
        if isCard { return detail.contains("Red") ? "rectangle.portrait.fill" : "rectangle.portrait.fill" }
        if isSub  { return "arrow.left.arrow.right" }
        return "circle.fill"
    }
}

struct AFEventTime: Codable {
    let elapsed: Int
    let extra: Int?
}

struct AFEventPlayer: Codable {
    let id: Int?
    let name: String?
}

/// Composition d'une équipe.
struct AFLineup: Codable, Identifiable {
    let team: AFTeam
    let formation: String?
    let startXI: [AFLineupPlayerWrapper]
    let substitutes: [AFLineupPlayerWrapper]
    let coach: AFCoach?

    var id: Int { team.id }
}

struct AFLineupPlayerWrapper: Codable {
    let player: AFLineupPlayer
}

struct AFLineupPlayer: Codable {
    let id: Int?
    let name: String?
    let number: Int?
    let pos: String?          // "G", "D", "M", "F"
    let grid: String?
    let captain: Bool?        // brassard de capitaine (fourni par l'API dans startXI)
}

struct AFCoach: Codable {
    let id: Int?
    let name: String?
    let photo: String?
}

// Décodage de /coachs?team= : plus riche que le bloc coach des compos. On ne
// garde que ce qui sert à identifier la mission en cours (career[].team.id + end).
struct AFCoachEntry: Codable {
    let id: Int?
    let name: String?
    let photo: String?
    let career: [AFCoachCareer]?
}

struct AFCoachCareer: Codable {
    let team: AFTeam?
    let start: String?
    let end: String?   // null = mission en cours
}

/// Statistiques d'une équipe sur le match (possession, tirs…).
struct AFTeamStatistics: Codable, Identifiable {
    let team: AFTeam
    let statistics: [AFStatItem]

    var id: Int { team.id }
}

struct AFStatItem: Codable {
    let type: String
    let value: AFStatValue?
}

/// La valeur d'une stat peut être un entier, une chaîne ("54%") ou null.
enum AFStatValue: Codable {
    case int(Int)
    case string(String)
    case none

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .none; return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        self = .none
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let i):    try c.encode(i)
        case .string(let s): try c.encode(s)
        case .none:          try c.encodeNil()
        }
    }

    var display: String {
        switch self {
        case .int(let i):    return "\(i)"
        case .string(let s): return s
        case .none:          return "–"
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// RECHERCHE D'ÉQUIPE (endpoint teams?search=)
// ─────────────────────────────────────────────────────────────────────────────

/// Une entrée de résultat de recherche d'équipe : l'équipe + son stade.
struct AFTeamResult: Codable, Identifiable {
    let team: AFTeamInfo
    let venue: AFVenue?

    var id: Int { team.id }
}

/// Infos d'équipe renvoyées par /teams (plus riches que l'AFTeam des fixtures).
struct AFTeamInfo: Codable {
    let id: Int
    let name: String
    let code: String?
    let country: String?
    let founded: Int?
    let national: Bool?
    let logo: String?

    /// Nom prêt à l'affichage (voir AFTeam.displayName).
    var displayName: String { TeamNameFormatter.pretty(name) }
}

// ─────────────────────────────────────────────────────────────────────────────
// BILAN DE SAISON D'UNE ÉQUIPE (/teams/statistics?team=&league=&season=)
// -----------------------------------------------------------------------------
// Récapitulatif chiffré de la saison de l'équipe DANS UNE COMPÉTITION donnée :
// matchs joués, V/N/D (dont détail domicile/extérieur), buts pour/contre, clean
// sheets, plus longue série de victoires, forme récente (chaîne "WDLWW"). Tous
// les champs sont optionnels : en tout début de saison certains sous-blocs sont
// null → décodage tolérant, la vue masque ce qui manque.
// ─────────────────────────────────────────────────────────────────────────────
struct AFTeamSeasonStats: Codable {
    let form: String?
    let fixtures: AFStatsFixtures?
    let goals: AFStatsGoals?
    let clean_sheet: AFStatsHAT?
    let biggest: AFStatsBiggest?
    let cards: AFStatsCards?

    // ── Accès lisibles (avec valeurs par défaut sûres) ──
    var played: Int { fixtures?.played?.total ?? 0 }
    var wins: Int { fixtures?.wins?.total ?? 0 }
    var draws: Int { fixtures?.draws?.total ?? 0 }
    var losses: Int { fixtures?.loses?.total ?? 0 }
    var goalsFor: Int { goals?.forGoals?.total?.total ?? 0 }
    var goalsAgainst: Int { goals?.against?.total?.total ?? 0 }
    var goalDiff: Int { goalsFor - goalsAgainst }
    var cleanSheets: Int { clean_sheet?.total ?? 0 }
    var longestWinStreak: Int { biggest?.streak?.wins ?? 0 }
    /// Moyenne de buts marqués par match (String "1.8" côté API) → Double.
    var avgGoalsFor: Double? { goals?.forGoals?.average?.total.flatMap(Double.init) }
    var avgGoalsAgainst: Double? { goals?.against?.average?.total.flatMap(Double.init) }
    /// Vrai s'il y a au moins un match joué (sinon la carte bilan est masquée).
    var hasData: Bool { played > 0 }

    // ── Cartons (fair-play) : sommés sur toutes les tranches de minutes ──
    var yellowCards: Int { cards?.yellow?.total ?? 0 }
    var redCards: Int { cards?.red?.total ?? 0 }
}

/// Bloc "cards" de /teams/statistics. L'API ventile les cartons par tranche de
/// minutes ("0-15", "16-30", … "106-120") ; chaque tranche porte un `total`
/// (parfois null). On somme tous les `total` non nuls pour obtenir le cumul saison.
struct AFStatsCards: Codable {
    let yellow: AFStatsCardBucket?
    let red: AFStatsCardBucket?
}

/// Dictionnaire { tranche → {total, percentage} }. `total` = somme des tranches.
/// DÉCODAGE ROBUSTE (corrigé 2026-08-16, bug fair-play Annecy à 0 carton) :
/// on décode chaque tranche INDÉPENDAMMENT via un conteneur à clés dynamiques.
/// Ainsi, si UNE tranche a une forme inattendue (ex. `percentage` numérique, ou
/// `total` en String selon les ligues), elle est simplement ignorée SANS remettre
/// à zéro tout le bloc — ce qui était le cas avant (un `try?` global renvoyait `[:]`
/// à la moindre anomalie, d'où le classement fair-play à 0).
struct AFStatsCardBucket: Codable {
    let intervals: [String: AFStatsCardInterval]
    var total: Int { intervals.values.compactMap { $0.total }.reduce(0, +) }

    /// Clé dynamique pour parcourir les tranches ("0-15", "16-30", …).
    private struct IntervalKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        // Le bloc peut aussi être un `null` complet → conteneur absent → vide.
        guard let container = try? decoder.container(keyedBy: IntervalKey.self) else {
            intervals = [:]; return
        }
        var acc: [String: AFStatsCardInterval] = [:]
        for key in container.allKeys {
            // Chaque tranche décodée SÉPARÉMENT : une tranche malformée n'affecte
            // pas les autres (on ne perd plus tout le cumul pour une anomalie).
            if let iv = try? container.decode(AFStatsCardInterval.self, forKey: key) {
                acc[key.stringValue] = iv
            }
        }
        intervals = acc
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: IntervalKey.self)
        for (k, v) in intervals {
            if let key = IntervalKey(stringValue: k) { try container.encode(v, forKey: key) }
        }
    }
}

/// Une tranche de minutes. `total` peut arriver en Int OU en String selon la
/// ligue/saison côté API-Football → décodage tolérant aux deux formes.
struct AFStatsCardInterval: Codable {
    let total: Int?
    // `percentage` (String "12.5%") ignoré : on ne s'en sert pas.

    private enum CodingKeys: String, CodingKey { case total }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .total) {
            total = i
        } else if let s = try? c.decode(String.self, forKey: .total), let i = Int(s) {
            total = i
        } else {
            total = nil
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(total, forKey: .total)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAIR-PLAY — classement d'équipes par indiscipline (croissant = plus fair-play)
// -----------------------------------------------------------------------------
// Barème (fixé par l'utilisateur) : carton jaune = 1 point, carton rouge = 3 pts.
// Un « rouge » englobe les rouges directs ET les 2e jaunes (yellowred) — mais
// /teams/statistics ne détaille pas les yellowred au niveau équipe, il fournit
// `cards.red` (rouges) et `cards.yellow` (jaunes) déjà agrégés. On s'en tient donc
// à ces deux compteurs officiels : pas d'invention.
// ─────────────────────────────────────────────────────────────────────────────
struct FairPlayEntry: Identifiable, Sendable {
    let team: AFTeam
    let played: Int
    let yellow: Int
    let red: Int
    var id: Int { team.id }
    /// Points d'indiscipline : jaune×1 + rouge×3. Plus BAS = plus fair-play.
    var points: Int { yellow * 1 + red * 3 }
}

struct AFStatsFixtures: Codable {
    let played: AFStatsHAT?
    let wins: AFStatsHAT?
    let draws: AFStatsHAT?
    let loses: AFStatsHAT?
}

/// Bloc home/away/total en Int (played, wins, clean_sheet…).
struct AFStatsHAT: Codable {
    let home: Int?
    let away: Int?
    let total: Int?
}

struct AFStatsGoals: Codable {
    // "for" est un mot réservé Swift → clé JSON remappée.
    let forGoals: AFStatsGoalsSide?
    let against: AFStatsGoalsSide?
    enum CodingKeys: String, CodingKey { case forGoals = "for", against }
}

struct AFStatsGoalsSide: Codable {
    let total: AFStatsHAT?
    let average: AFStatsAverage?
}

/// Bloc "average" : l'API renvoie les moyennes en STRING ("1.8").
struct AFStatsAverage: Codable {
    let home: String?
    let away: String?
    let total: String?
}

struct AFStatsBiggest: Codable {
    let streak: AFStatsStreak?
}

struct AFStatsStreak: Codable {
    let wins: Int?
    let draws: Int?
    let loses: Int?
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE API-FOOTBALL
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// CACHE RÉSEAU — réduit drastiquement la conso de requêtes API-Football.
// -----------------------------------------------------------------------------
// Chaque réponse brute (Data) est mémorisée par URL avec un horodatage. Si le
// MÊME endpoint est redemandé avant l'expiration du TTL, on ressert la réponse
// mémorisée SANS appel réseau. Ça élimine les doublons coûteux : réouvrir un
// écran, revenir en arrière, basculer entre onglets, ou relancer l'app après un
// simple re-build tapaient l'API à chaque fois → quota épuisé.
//
// TTL volontairement différenciés (voir ttl(for:)) : le direct se rafraîchit
// vite, les données stables (classements, effectifs, matchs passés) tiennent
// plusieurs minutes. Cache purement EN MÉMOIRE (vidé au redémarrage réel de
// l'app) : jamais de donnée périmée servie durablement.
// ─────────────────────────────────────────────────────────────────────────────
actor NetworkCache {
    // Entry Codable : on peut sérialiser tout le store sur disque et le recharger
    // au prochain lancement (le re-build Xcode ne repart donc plus de zéro).
    private struct Entry: Codable { let data: Data; let at: Date }
    private var store: [String: Entry] = [:]

    // ── Persistance disque ──────────────────────────────────────────────────────
    // Fichier unique dans le dossier Caches du conteneur de l'app (nettoyable par
    // le système sous pression de stockage, ce qui est acceptable pour un cache).
    // Chargé une seule fois (paresseusement) au premier accès ; réécrit après chaque
    // `set`. Un cache disque corrompu est simplement ignoré (repli réseau).
    private var didLoadFromDisk = false
    private static let fileURL: URL? = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return dir?.appendingPathComponent("api_football_cache.json")
    }()

    /// Charge le store depuis le disque au premier accès et purge les entrées
    /// nettement trop vieilles (> 24 h) pour ne pas garder un fichier qui enfle.
    private func loadIfNeeded() {
        guard !didLoadFromDisk else { return }
        didLoadFromDisk = true
        guard let url = Self.fileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return }
        let cutoff = Date().addingTimeInterval(-86_400)   // 24 h
        store = decoded.filter { $0.value.at > cutoff }
    }

    /// Écrit le store courant sur disque (best-effort : un échec n'est pas fatal,
    /// le cache mémoire reste valable pour la session en cours).
    private func persist() {
        guard let url = Self.fileURL,
              let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Renvoie la donnée mémorisée si elle est encore fraîche (< ttl), sinon nil.
    func value(for key: String, ttl: TimeInterval) -> Data? {
        loadIfNeeded()
        guard let e = store[key] else { return nil }
        if Date().timeIntervalSince(e.at) < ttl { return e.data }
        store[key] = nil            // périmée : on la retire
        return nil
    }

    func set(_ data: Data, for key: String) {
        loadIfNeeded()
        store[key] = Entry(data: data, at: Date())
        persist()
    }

    /// Vide tout le cache (ex. bouton « Rafraîchir » global si un jour on en veut un).
    func clear() {
        store.removeAll()
        if let url = Self.fileURL { try? FileManager.default.removeItem(at: url) }
    }
}

class FootballAPIService: ObservableObject {
    static let shared = FootballAPIService()
    private let base = "https://v3.football.api-sports.io"

    /// Cache réseau partagé (voir NetworkCache).
    private let cache = NetworkCache()

    // ── Quota API-Football (compteur in-app) ────────────────────────────────────
    // Renseignés à partir des en-têtes de chaque réponse réseau réelle (les hits de
    // cache ne consomment rien et ne les modifient donc pas). `requestsLimit` =
    // plafond du jour (ex. 7500), `requestsRemaining` = ce qu'il reste aujourd'hui.
    // nil tant qu'aucune requête réseau n'a encore renvoyé ces en-têtes.
    @Published var requestsLimit: Int?
    @Published var requestsRemaining: Int?
    /// Nombre d'appels RÉSEAU réels effectués dans cette session (hors hits de cache).
    @Published var sessionNetworkCalls = 0

    /// Date du jour au format `yyyy-MM-dd` (fuseau Europe/Paris), utilisée pour
    /// distinguer un jour passé (cache long) du jour courant (cache court).
    private static func dayDateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "Europe/Paris")
        return fmt.string(from: date)
    }

    /// Extrait `YYYY-MM-DD` d'un endpoint `/fixtures?date=YYYY-MM-DD&...`.
    private static func parseFixtureDate(from endpoint: String) -> String? {
        guard let range = endpoint.range(of: "date=") else { return nil }
        let tail = endpoint[range.upperBound...]
        let value = tail.prefix { $0 != "&" }
        return value.count == 10 ? String(value) : nil
    }

    /// Durée de fraîcheur du cache selon le type d'endpoint. Le direct doit rester
    /// réactif ; le reste peut tenir plusieurs minutes sans gêner l'utilisateur.
    private func ttl(for endpoint: String) -> TimeInterval {
        // TTL allongés (2026-08-17) pour réduire fortement la conso de requêtes :
        // le direct reste réactif, tout le reste tient bien plus longtemps (les
        // classements/calendriers/effectifs ne changent pas d'une minute à l'autre).
        if endpoint.contains("live=all") { return 20 }         // matchs en direct : 20 s
        if endpoint.contains("/standings") { return 1_800 }    // classements : 30 min
        if endpoint.contains("/players/squads") { return 3_600 } // effectifs : 60 min
        if endpoint.contains("/teams?") { return 3_600 }       // infos équipe/stade : 60 min
        if endpoint.contains("/players?") { return 900 }       // fiches/buteurs joueur : 15 min
        // Live PAR JOUR (`/fixtures?date=YYYY-MM-DD`, Live refondu 2026-08-18) :
        // un jour PASSÉ ne change plus jamais (matchs terminés) → cache quasi
        // permanent (24 h) : revenir sur un jour déjà consulté ne coûte AUCUNE
        // requête. Le jour COURANT (ou futur) garde un TTL court (60 s) pour rester
        // frais (scores en direct, compos, reports de match).
        if endpoint.contains("/fixtures?date="),
           let dateStr = Self.parseFixtureDate(from: endpoint) {
            let today = Self.dayDateString(Date())
            if dateStr == today { return 60 }                   // aujourd'hui : 60 s
            // Un jour futur peut encore bouger (report, heure de coup d'envoi) mais
            // pas en temps réel → 30 min ; un jour passé → 24 h.
            return dateStr > today ? 1_800 : 86_400
        }
        return 600                                             // par défaut : 10 min
    }

    /// Saison courante. Les compétitions internationales (EURO, CDM) ont leur
    /// propre année ; on la surcharge au besoin via `season(for:)`.
    // ✅ SAISON EN COURS (plan payant API-Football actif depuis le 2026-08-13).
    // Saison européenne à cheval 2026-27 → indexée « 2026 » côté API-Football.
    // (En plan GRATUIT, seule ~2023 est accessible : y revenir si le forfait
    //  payant est suspendu, sinon « No matches » / « Standings unavailable ».)
    private let defaultSeason = 2026

    /// Championnats joués en ANNÉE CIVILE (saison = l'année en cours),
    /// par opposition aux championnats européens à cheval (août→mai).
    /// Pour API-Football, une saison à cheval 2026-27 se demande avec « 2026 ».
    private static let calendarYearLeagues: Set<String> = [
        "usa_mls",       // MLS : fév → déc
        "bra_seriea",    // Brasileirão : avril → déc
        "arg_primera",   // Argentine : année civile
        "jpn_j1",        // J1 League : fév → déc
        // Liga MX est en Apertura/Clausura mais API-Football l'indexe par année
        // de début (2026) ; on la laisse sur defaultSeason.
    ]

    /// Compétitions de SÉLECTIONS à édition fixe (pas une saison à cheval).
    /// L'année désigne l'édition à afficher côté API-Football :
    ///   • Coupe du Monde 2026 (USA/Can/Mex, juin-juillet 2026) → 2026
    ///   • EURO : prochaine édition = 2028
    ///   • Ligue des Nations : compétition à cheval 2026-27 → laissée sur
    ///     defaultSeason (2026), donc pas listée ici.
    /// À mettre à jour après chaque tournoi (ex. CDM → 2030, EURO → 2028 déjà).
    private static let fixedEditionSeasons: [String: Int] = [
        "nat_worldcup": 2026,
        "nat_euro": 2028,
    ]

    private func season(for competition: Competition) -> Int {
        // Année civile en cours pour les ligues qui jouent de printemps à automne.
        if Self.calendarYearLeagues.contains(competition.id) {
            return Calendar.current.component(.year, from: Date())
        }
        // Sélections à édition fixe (EURO, Coupe du Monde).
        if let year = Self.fixedEditionSeasons[competition.id] {
            return year
        }
        // Sinon : saison européenne à cheval, indexée par son année de début
        // (championnats de clubs + coupes d'Europe + Ligue des Nations).
        return defaultSeason
    }

    /// Saisons à interroger pour les STATS, dans l'ordre de préférence : saison en
    /// cours d'abord, puis la précédente en repli. Motivation : une compétition dont
    /// la saison courante n'a pas encore débuté (typiquement les coupes d'Europe en
    /// août, dont la phase de ligue commence en septembre) ne renvoie aucune stat sur
    /// `season = année en cours`. On retombe alors sur l'édition précédente pour que
    /// l'onglet Stats ne reste pas vide. Les sélections à édition fixe (EURO, CDM) ne
    /// prennent pas de repli : leur saison est déjà la bonne (ou il n'y a rien à voir).
    private func seasonsToTry(for competition: Competition) -> [Int] {
        let s = season(for: competition)
        if Self.fixedEditionSeasons[competition.id] != nil { return [s] }
        // Tournois de SÉLECTIONS / internationaux à édition NON annuelle : la dernière
        // édition peut dater de 2 à 3 ans (Copa América 2024, Coupe d'Asie 2024,
        // CAN 2025…). Un repli court [s, s-1] les manque → on remonte jusqu'à 4 ans
        // pour retrouver la dernière édition réellement disputée.
        if Self.multiYearTournaments.contains(competition.id) {
            return (0...4).map { s - $0 }
        }
        // CHAMPIONNATS NATIONAUX (league / leagueGroups) : PAS de repli sur la saison
        // précédente (décision user 2026-08-17). En intersaison, une Ligue 1 non
        // démarrée ne doit PAS afficher les buteurs/stats de l'édition passée : cela
        // mélangeait un classement vierge, la prochaine journée, et des stats
        // d'une AUTRE saison. On renvoie donc UNIQUEMENT la saison en cours → l'onglet
        // Stats reste honnêtement vide (« saison pas encore commencée ») tant que rien
        // n'a été joué. Le repli [s, s-1] reste réservé aux COUPES D'EUROPE et tournois
        // dont la phase débute plus tard (voir ci-dessous).
        if competition.kind == .league || competition.kind == .leagueGroups {
            return [s]
        }
        // Coupes d'Europe / coupes (mixed, cup) : la phase de ligue démarre en
        // septembre → en août, season courante encore vide. Repli sur l'édition
        // précédente pour ne pas laisser l'onglet Stats désespérément vide.
        return [s, s - 1]
    }

    /// Compétitions dont l'édition n'a PAS lieu tous les ans (ou pas chaque année
    /// civile côté API-Football) : on autorise un repli profond pour afficher la
    /// dernière édition jouée. Voir `seasonsToTry(for:)`.
    private static let multiYearTournaments: Set<String> = [
        "nat_afcon",       // CAN (dernière : 2025)
        "nat_copaamerica", // Copa América (dernière : 2024)
        "nat_goldcup",     // Gold Cup CONCACAF (2025)
        "nat_asiancup",    // Coupe d'Asie AFC (dernière : 2024)
        "nat_nationsleague",
        "intl_clubwc",         // Coupe du monde des clubs (2025)
        "intl_intercontinental",
    ]

    private func fetch<T: Decodable>(_ endpoint: String) async throws -> T {
        guard API_FOOTBALL_KEY != "YOUR_API_FOOTBALL_KEY" else { throw APIError.missingAPIKey }
        guard let url = URL(string: "\(base)\(endpoint)") else { throw APIError.invalidURL }

        // 1) Cache d'abord : si on a une réponse fraîche pour cet endpoint, on la
        //    décode SANS appel réseau (0 requête consommée).
        if let cached = await cache.value(for: endpoint, ttl: ttl(for: endpoint)) {
            do { return try JSONDecoder().decode(T.self, from: cached) }
            catch { /* cache corrompu (rare) : on retombe sur l'appel réseau */ }
        }

        var req = URLRequest(url: url)
        req.setValue(API_FOOTBALL_KEY, forHTTPHeaderField: "x-apisports-key")

        // 2) Retry back-off sur 429 (rate-limit PAR MINUTE d'API-Football, ≠ quota
        // journalier). Sans ça, ouvrir plusieurs fiches d'affilée déclenche
        // « Erreur serveur 429 ». On retente 3 fois avec des pauses croissantes
        // (1,5 / 3 / 4,5 s). Même logique que le back-off du proxy (apiFootball()).
        var attempt = 0
        while true {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            let status = http?.statusCode ?? 200
            // Compteur de quota : lu sur CHAQUE réponse réseau réelle (un hit de cache
            // n'arrive jamais ici → ne fausse pas le compteur).
            updateQuota(from: http)
            if status == 429, attempt < 3 {
                attempt += 1
                let delay = 1.5 * Double(attempt)   // 1,5 / 3 / 4,5 s
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            }
            if status != 200 { throw APIError.serverError(status) }
            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                // 3) Succès : on mémorise la réponse brute pour les prochains appels.
                await cache.set(data, for: endpoint)
                return decoded
            }
            catch { throw APIError.decodingError(error) }
        }
    }

    /// Met à jour le compteur de quota à partir des en-têtes d'une réponse réseau.
    /// API-Football expose le quota JOURNALIER via `x-ratelimit-requests-limit` /
    /// `x-ratelimit-requests-remaining` (les variantes `X-RateLimit-*` sont le quota
    /// PAR MINUTE, qu'on ignore ici). Publié sur le MainActor pour l'affichage.
    @MainActor
    private func updateQuota(from http: HTTPURLResponse?) {
        sessionNetworkCalls += 1
        guard let http else { return }
        // Les clés d'en-tête sont insensibles à la casse côté HTTPURLResponse.
        if let s = http.value(forHTTPHeaderField: "x-ratelimit-requests-limit"),
           let v = Int(s) { requestsLimit = v }
        if let s = http.value(forHTTPHeaderField: "x-ratelimit-requests-remaining"),
           let v = Int(s) { requestsRemaining = v }
    }

    // Matchs d'une compétition (14 jours avant / 7 après)
    // Pour un championnat à poules-ligues distinctes (National 1 = 67/68/69),
    // on agrège les fixtures des 3 poules.
    func fetchMatches(competition: Competition) async throws -> [AFFixture] {
        let s = season(for: competition)
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let from = fmt.string(from: Calendar.current.date(byAdding: .day, value: -14, to: Date())!)
        let to   = fmt.string(from: Calendar.current.date(byAdding: .day, value: 7,  to: Date())!)
        var all: [AFFixture] = []
        for id in competition.allApiIds {
            if let r: AFResponse<AFFixture> = try? await fetch(
                "/fixtures?league=\(id)&season=\(s)&from=\(from)&to=\(to)&timezone=Europe/Paris"
            ) {
                all.append(contentsOf: r.response)
            }
        }
        return all.sorted { $0.fixture.date < $1.fixture.date }
    }

    // TOUS les matchs de la saison/édition (sans fenêtre de dates).
    // Utilisé par la vue « phases » (CDM, EURO, UCL…) qui a besoin de tous les
    // tours, passés comme à venir, pour construire le menu Finale→Groupes.
    //
    // REPLI SAISON : certaines compétitions n'ont pas d'édition chaque année (la CAN
    // 2025 se joue fin 2025 → « season 2025 » ; il n'y a pas de CAN en 2026). Sur la
    // saison courante, `/fixtures` renvoie alors 0 match → écran vide. On essaie donc
    // les saisons de repli (`seasonsToTry` : saison courante puis précédente) et on
    // s'arrête à la 1re qui contient des matchs, pour afficher la dernière édition
    // jouée. Les éditions à saison fixe (CDM 2026, EURO 2028) n'ont qu'une saison.
    func fetchAllFixtures(competition: Competition) async throws -> [AFFixture] {
        for s in seasonsToTry(for: competition) {
            var all: [AFFixture] = []
            for id in competition.allApiIds {
                if let r: AFResponse<AFFixture> = try? await fetch(
                    "/fixtures?league=\(id)&season=\(s)&timezone=Europe/Paris"
                ) {
                    all.append(contentsOf: r.response)
                }
            }
            if !all.isEmpty { return all.sorted { $0.fixture.date < $1.fixture.date } }
        }
        return []
    }

    // Tous les matchs d'une journée / d'un tour (agrégés sur toutes les poules)
    func fetchMatchesByRound(competition: Competition, round: String) async throws -> [AFFixture] {
        let s = season(for: competition)
        let encoded = round.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? round
        var all: [AFFixture] = []
        for id in competition.allApiIds {
            if let r: AFResponse<AFFixture> = try? await fetch(
                "/fixtures?league=\(id)&season=\(s)&round=\(encoded)&timezone=Europe/Paris"
            ) {
                all.append(contentsOf: r.response)
            }
        }
        return all.sorted { $0.fixture.date < $1.fixture.date }
    }

    /// Filtre optionnel des tours selon la compétition.
    /// Coupe de France (`fr_coupe`) : on démarre au 7e tour — on masque les tours
    /// amateurs numérotés 1 à 6 ("1st Round"…"6th Round"). Tout le reste est conservé :
    /// le 7e tour et au-delà, ainsi que TOUS les tours nommés à élimination
    /// (Round of 64/32/16, Quarter/Semi-finals, Final…), qui viennent après le 7e.
    private func filterRounds(_ rounds: [String], for competition: Competition) -> [String] {
        guard competition.id == "fr_coupe" else { return rounds }
        return rounds.filter { round in
            // Extrait le 1er entier présent dans le libellé (ex. "7th Round" → 7,
            // "Round of 64" → 64). On isole les chiffres consécutifs.
            var num = ""
            for ch in round {
                if ch.isNumber { num.append(ch) }
                else if !num.isEmpty { break }   // on s'arrête au 1er groupe de chiffres
            }
            guard let n = Int(num) else {
                // Aucun chiffre : tour nommé (Final, Semi-finals…) → conservé.
                return true
            }
            // "Round of 32/16/…" : grand nombre = tour à élimination tardif → conservé.
            // Sinon c'est un tour numéroté ("Nth Round") : on ne garde que n >= 7.
            let lower = round.lowercased()
            if lower.contains("round of") || lower.contains("1/") { return true }
            return n >= 7
        }
    }

    // Rounds / journées disponibles (union des poules, dédoublonnée en gardant l'ordre)
    func fetchRounds(competition: Competition) async throws -> [String] {
        struct RoundResponse: Codable { let response: [String] }
        let s = season(for: competition)
        var seen = Set<String>()
        var rounds: [String] = []
        for id in competition.allApiIds {
            if let r: RoundResponse = try? await fetch("/fixtures/rounds?league=\(id)&season=\(s)") {
                for round in r.response where !seen.contains(round) {
                    seen.insert(round); rounds.append(round)
                }
            }
        }
        return filterRounds(rounds, for: competition)
    }

    /// Journée « courante » selon API-Football (paramètre current=true).
    /// Renvoie nil si l'API n'en désigne pas (ex. hors saison).
    /// Pour les poules-ligues, la 1re poule qui en désigne une fait foi.
    func fetchCurrentRound(competition: Competition) async throws -> String? {
        struct RoundResponse: Codable { let response: [String] }
        let s = season(for: competition)
        for id in competition.allApiIds {
            if let r: RoundResponse = try? await fetch(
                "/fixtures/rounds?league=\(id)&season=\(s)&current=true"
            ), let cur = r.response.first {
                return cur
            }
        }
        return nil
    }

    // Classement (peut contenir plusieurs poules).
    // Repli saison précédente : en tout début de saison (coupes d'Europe en août),
    // le classement 2026-27 n'est pas encore publié → on retombe sur 2025-26 pour
    // que les rubriques Stats dérivées du classement (attaques/défenses/séries…)
    // ne soient pas vides. Voir fetchTopScorers(competition:).
    /// - Parameter fallbackToPreviousSeason: quand `true` (défaut), on retombe sur
    ///   l'édition précédente si la saison courante n'a pas encore de classement
    ///   (utile pour les rubriques Stats en août). Quand `false`, on N'AFFICHE QUE
    ///   la saison courante : indispensable pour la PHASE DE GROUPES des coupes
    ///   d'Europe — en tout début de saison (tours préliminaires), le classement
    ///   2026-27 n'existe pas encore ; afficher celui de 2025-26 (8 journées jouées)
    ///   est TROMPEUR. Mieux vaut « phase pas encore commencée » (voir PhaseDetailView).
    func fetchStandings(competition: Competition,
                        fallbackToPreviousSeason: Bool = true) async throws -> [[AFStandingEntry]] {
        let seasons = fallbackToPreviousSeason ? seasonsToTry(for: competition)
                                               : [season(for: competition)]
        for s in seasons {
            let poules = try await fetchStandings(competition: competition, season: s)
            if !poules.contains(where: { !$0.isEmpty }) { continue }
            return poules
        }
        return []
    }

    private func fetchStandings(competition: Competition, season s: Int) async throws -> [[AFStandingEntry]] {
        // CAS 1 — poules = ligues DISTINCTES côté API (ex. National 1 = 67/68/69).
        // On interroge chaque ID : chaque réponse fournit une poule → un sous-tableau.
        if let ids = competition.groupApiIds, ids.count > 1 {
            var poules: [[AFStandingEntry]] = []
            for id in ids {
                // Une poule vide (saison pas commencée) ne fait pas échouer les autres.
                if let r: AFResponse<AFStandingResponse> = try? await fetch(
                    "/standings?league=\(id)&season=\(s)"
                ), let poule = r.response.first?.league.standings?.first, !poule.isEmpty {
                    poules.append(poule.sorted { $0.rank < $1.rank })
                }
            }
            return poules
        }

        // CAS 2 — compétition mono-ID (une seule requête).
        // TOLÉRANT : une compétition hors-saison (ex. CAN interrogée sur une année
        // sans édition) renvoie une réponse vide/inattendue → l'API-Football peut
        // faire échouer le décodage. On avale l'erreur et on renvoie [] : la vue
        // affichera « aucun classement » plutôt qu'une erreur « données introuvables ».
        guard let r: AFResponse<AFStandingResponse> = try? await fetch(
            "/standings?league=\(competition.apiId)&season=\(s)"
        ) else { return [] }
        let raw = r.response.first?.league.standings ?? [] as [[AFStandingEntry]]

        // Certains championnats à poules renvoient UN seul sous-tableau mélangeant
        // les poules, différenciées par le champ `group`. On re-sépare par `group`.
        if competition.hasGroups {
            let allEntries = raw.flatMap { $0 }
            let distinctGroups = Set(allEntries.compactMap { $0.group })
            if distinctGroups.count > 1 {
                var order: [String] = []
                var byGroup: [String: [AFStandingEntry]] = [:]
                for e in allEntries {
                    let key = e.group ?? ""
                    if byGroup[key] == nil { order.append(key) }
                    byGroup[key, default: []].append(e)
                }
                return order.sorted().map { key in
                    (byGroup[key] ?? []).sorted { $0.rank < $1.rank }
                }
            }
        }
        return raw
    }

    // Classements d'une ligue de QUALIFICATION (CDM par confédération, EURO UEFA).
    // Renvoie un sous-tableau par groupe (A, B, C…), re-séparé via le champ `group`.
    // Tolérant : une ligue vide/indisponible renvoie [] au lieu d'échouer.
    func fetchQualifierStandings(leagueId: Int, season: Int) async -> [[AFStandingEntry]] {
        let r: AFResponse<AFStandingResponse>
        do {
            r = try await fetch("/standings?league=\(leagueId)&season=\(season)")
        } catch {
            // Log utile en dev pour distinguer « pas de données » d'un échec de décodage.
            print("⚠️ qualif standings league=\(leagueId) season=\(season) : \(error)")
            return []
        }
        let raw = r.response.first?.league.standings ?? []
        let allEntries = raw.flatMap { $0 }
        guard !allEntries.isEmpty else { return [] }

        // Re-séparation par `group` (l'API renvoie souvent tout dans un tableau).
        let distinctGroups = Set(allEntries.compactMap { $0.group })
        if distinctGroups.count > 1 {
            var order: [String] = []
            var byGroup: [String: [AFStandingEntry]] = [:]
            for e in allEntries {
                let key = e.group ?? ""
                if byGroup[key] == nil { order.append(key) }
                byGroup[key, default: []].append(e)
            }
            return order.sorted().map { key in
                (byGroup[key] ?? []).sorted { $0.rank < $1.rank }
            }
        }
        // Un seul groupe (ou pas de champ group) → un unique sous-tableau trié.
        return [allEntries.sorted { $0.rank < $1.rank }]
    }

    // Détail complet d'un match : événements, compositions, statistiques
    func fetchMatchDetail(fixtureId: Int) async throws -> AFFixtureFull {
        let r: AFResponse<AFFixtureFull> = try await fetch(
            "/fixtures?id=\(fixtureId)&timezone=Europe/Paris"
        )
        guard var full = r.response.first else { throw APIError.noData }

        // L'endpoint `/fixtures?id=` peuple les compos mais renvoie SOUVENT le
        // sélectionneur (`coach`) et/ou la `formation` à null (surtout sélections
        // nationales / plan gratuit). L'endpoint DÉDIÉ `/fixtures/lineups?fixture=`
        // les fournit de façon fiable. On l'appelle en repli quand il manque un
        // coach ou une formation, puis on fusionne par équipe (team.id) sans écraser
        // les données déjà présentes.
        let missingCoach = (full.lineups ?? []).contains { ($0.coach?.name ?? "").isEmpty }
        let missingFormation = (full.lineups ?? []).contains { ($0.formation ?? "").isEmpty }
        #if DEBUG
        print("🩺 [coach] /fixtures?id lineups=\(full.lineups?.count ?? 0) " +
              "coaches=\((full.lineups ?? []).map { $0.coach?.name ?? "nil" }) " +
              "formations=\((full.lineups ?? []).map { $0.formation ?? "nil" }) " +
              "missingCoach=\(missingCoach) missingFormation=\(missingFormation)")
        #endif
        if full.lineups?.isEmpty ?? true || missingCoach || missingFormation {
            #if DEBUG
            // Dump BRUT de /fixtures/lineups pour voir la structure réelle du coach.
            if let raw = try? await fetchRaw("/fixtures/lineups?fixture=\(fixtureId)") {
                print("🩺 [coach] RAW /fixtures/lineups (2000 premiers car.):\n" + String(raw.prefix(2000)))
            }
            #endif
            do {
                let lr: AFResponse<AFLineup> = try await fetch(
                    "/fixtures/lineups?fixture=\(fixtureId)"
                )
                #if DEBUG
                print("🩺 [coach] /fixtures/lineups décodé: teams=\(lr.response.count) " +
                      "coaches=\(lr.response.map { $0.coach?.name ?? "nil" }) " +
                      "formations=\(lr.response.map { $0.formation ?? "nil" })")
                #endif
                if !lr.response.isEmpty {
                    let byTeam = Dictionary(uniqueKeysWithValues: lr.response.map { ($0.team.id, $0) })
                    if let existing = full.lineups, !existing.isEmpty {
                        full.lineups = existing.map { line in
                            guard let dedicated = byTeam[line.team.id] else { return line }
                            return AFLineup(
                                team: line.team,
                                formation: (line.formation?.isEmpty == false) ? line.formation : dedicated.formation,
                                startXI: line.startXI.isEmpty ? dedicated.startXI : line.startXI,
                                substitutes: line.substitutes.isEmpty ? dedicated.substitutes : line.substitutes,
                                coach: (line.coach?.name?.isEmpty == false) ? line.coach : dedicated.coach
                            )
                        }
                    } else {
                        // Aucune compo dans /fixtures?id= → on prend entièrement celles du
                        // endpoint dédié.
                        full.lineups = lr.response
                    }
                }
            } catch {
                #if DEBUG
                // Si le décodage de /fixtures/lineups échoue, on le VOIT ici (avant, le
                // try? avalait l'erreur silencieusement → coach jamais rempli sans trace).
                print("🩺 [coach] /fixtures/lineups ÉCHEC: \(error)")
                #endif
            }
        }
        return full
    }

    #if DEBUG
    /// Récupère la réponse BRUTE (String) d'un endpoint, pour diagnostic uniquement.
    private func fetchRaw(_ endpoint: String) async throws -> String {
        guard API_FOOTBALL_KEY != "YOUR_API_FOOTBALL_KEY" else { throw APIError.missingAPIKey }
        guard let url = URL(string: "\(base)\(endpoint)") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.setValue(API_FOOTBALL_KEY, forHTTPHeaderField: "x-apisports-key")
        let (data, _) = try await URLSession.shared.data(for: req)
        return String(data: data, encoding: .utf8) ?? ""
    }
    #endif

    // Buteurs / passeurs d'une compétition (classement des meilleurs buteurs)
    // Pour un championnat à poules-ligues (National 1), on fusionne les buteurs
    // des 3 poules avant de trier.
    func fetchTopScorers(competition: Competition) async throws -> [AFPlayerResponse] {
        // Saisons à tenter : pour les championnats nationaux, uniquement la saison en
        // cours (pas de repli — cf. seasonsToTry). Pour les coupes d'Europe en tout
        // début de saison (août), la phase de ligue 2026-27 ne débute qu'en septembre :
        // on tente alors la saison précédente pour ne pas laisser l'onglet vide.
        for s in seasonsToTry(for: competition) {
            var all: [AFPlayerResponse] = []
            for id in competition.allApiIds {
                if let r: AFResponse<AFPlayerResponse> = try? await fetch(
                    "/players/topscorers?league=\(id)&season=\(s)"
                ) {
                    all.append(contentsOf: r.response)
                }
            }
            if !all.isEmpty {
                // Tri de sécurité : buts décroissants, puis passes décroissantes.
                return all.sorted {
                    if $0.goals != $1.goals { return $0.goals > $1.goals }
                    return $0.assists > $1.assists
                }
            }
        }
        return []
    }

    /// Meilleurs PASSEURS d'une compétition via l'endpoint dédié `/players/topassists`.
    /// IMPORTANT : ne PAS déduire les passeurs de `/players/topscorers`, qui ne classe
    /// que les meilleurs buteurs — leurs passes décisives ne reflètent alors pas le vrai
    /// classement des passeurs (on ratait les passeurs qui marquent peu).
    func fetchTopAssists(competition: Competition) async throws -> [AFPlayerResponse] {
        for s in seasonsToTry(for: competition) {
            var all: [AFPlayerResponse] = []
            for id in competition.allApiIds {
                if let r: AFResponse<AFPlayerResponse> = try? await fetch(
                    "/players/topassists?league=\(id)&season=\(s)"
                ) {
                    all.append(contentsOf: r.response)
                }
            }
            if !all.isEmpty {
                return all.sorted {
                    if $0.assists != $1.assists { return $0.assists > $1.assists }
                    return $0.goals > $1.goals
                }
            }
        }
        return []
    }

    /// Buteurs D'UN CLUB précis (effectif via /players?team=…, paginé). Utilisé par
    /// l'assistant (« les buteurs d'Annecy »). Un effectif tient en 1-2 pages (~25
    /// joueurs) ; on suit la pagination avec une pause anti-429, puis on trie par
    /// buts décroissants. On ne garde que les joueurs ayant au moins un but ou une passe.
    /// - season : saison en cours par défaut (l'appelant peut passer une saison précise).
    func fetchTeamScorers(teamId: Int, season: Int) async throws -> [AFPlayerResponse] {
        var all: [AFPlayerResponse] = []

        // Première page : donne le nombre total de pages.
        let first: AFResponse<AFPlayerResponse> = try await fetch(
            "/players?team=\(teamId)&season=\(season)&page=1"
        )
        all.append(contentsOf: first.response)

        let totalPages = min(first.paging?.total ?? 1, 3)   // un effectif = 1-2 pages
        if totalPages > 1 {
            for page in 2...totalPages {
                try? await Task.sleep(nanoseconds: 300_000_000) // anti rate-limit
                if let r: AFResponse<AFPlayerResponse> = try? await fetch(
                    "/players?team=\(teamId)&season=\(season)&page=\(page)"
                ) {
                    all.append(contentsOf: r.response)
                }
            }
        }

        // On agrège via totalGoals/totalAssists (somme toutes compétitions) puis on
        // ne garde que ceux qui ont marqué ou fait une passe, triés par buts.
        return all
            .filter { $0.totalGoals > 0 || $0.totalAssists > 0 }
            .sorted {
                if $0.totalGoals != $1.totalGoals { return $0.totalGoals > $1.totalGoals }
                return $0.totalAssists > $1.totalAssists
            }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // JEU FANTASY — vivier de joueurs sélectionnables
    // ─────────────────────────────────────────────────────────────────────────

    /// Ligue du vivier fantasy = LIGUE 1 (id API-Football 61). Choix utilisateur
    /// (2026-08-13) : limiter le vivier à un seul championnat pour maîtriser le
    /// quota (l'endpoint /players pagine ~20 joueurs/page → ~30 requêtes pour la L1).
    static let fantasyLeagueApiId = 61

    /// Charge TOUS les joueurs d'une ligue via /players (paginé), pas seulement les
    /// buteurs. Chaque page renvoie ~20 joueurs + leurs stats de saison. On suit la
    /// pagination (`paging.total`) jusqu'à la dernière page. Une page en échec est
    /// ignorée (try?) pour ne pas perdre tout le vivier sur une erreur ponctuelle.
    /// - Note quota : ~30 requêtes pour un championnat de 20 clubs. À n'appeler que
    ///   sur demande explicite (ouverture du sélecteur), pas en tâche de fond.
    func fetchAllPlayers(leagueId: Int, season: Int) async throws -> [AFPlayerResponse] {
        var all: [AFPlayerResponse] = []

        // Première page : donne aussi le nombre total de pages.
        // (Si CETTE requête échoue, on laisse l'erreur remonter : elle est utile
        //  pour distinguer « plan API insuffisant » de « saison vide ».)
        let first: AFResponse<AFPlayerResponse> = try await fetch(
            "/players?league=\(leagueId)&season=\(season)&page=1"
        )
        all.append(contentsOf: first.response)

        let totalPages = min(first.paging?.total ?? 1, 40)   // garde-fou anti-boucle
        if totalPages > 1 {
            for page in 2...totalPages {
                // ⚠️ API-Football limite le débit (~10 req/s en gratuit) : sans pause,
                // les pages suivantes reviennent en 429 et sont perdues (try?). On
                // espace donc légèrement chaque appel (250 ms).
                try? await Task.sleep(nanoseconds: 250_000_000)
                if let r: AFResponse<AFPlayerResponse> = try? await fetch(
                    "/players?league=\(leagueId)&season=\(season)&page=\(page)"
                ) {
                    all.append(contentsOf: r.response)
                }
            }
        }
        return all
    }

    /// Construit le VIVIER de joueurs du jeu fantasy : TOUS les joueurs de la Ligue 1
    /// (pas seulement les buteurs), via /players paginé. Les joueurs sans aucune stat
    /// exploitable sont conservés (prix plancher) : on veut la liste complète de
    /// l'effectif, pas un top. Dédoublonné par id joueur, trié par points décroissants.
    ///
    /// BASCULE DE SAISON : en tout début de saison (ex. août), l'API n'a pas encore
    /// de stats pour la saison en cours → vivier vide. On tente d'abord la saison
    /// courante, et SI ELLE EST VIDE on retombe automatiquement sur la saison
    /// PRÉCÉDENTE (effectif complet, stats connues). Quand la nouvelle saison se
    /// peuplera, la saison courante l'emportera d'elle-même — rien à changer.
    func fetchFantasyPlayerPool() async throws -> [FantasyPlayer] {
        let leagueId = Self.fantasyLeagueApiId
        let currentSeason = seasonForLeagueId(leagueId)

        // 1) Saison en cours.
        var pool = await fantasyPool(leagueId: leagueId, season: currentSeason)

        // 2) Si vide (saison pas encore peuplée), on réessaie la saison précédente.
        if pool.isEmpty {
            pool = await fantasyPool(leagueId: leagueId, season: currentSeason - 1)
        }
        return pool
    }

    /// Construit le vivier fantasy pour UNE saison donnée. Tente /players (effectif
    /// complet, paginé) ; si rien, retombe sur /players/topscorers (buteurs). Renvoie
    /// une liste triée par points décroissants (vide si l'API ne fournit rien).
    /// FALLBACK : si /players ne renvoie rien (plan API, saison vide…), les BUTEURS
    /// suffisent à avoir un vivier non vide. Mieux vaut une liste réduite qu'un vide.
    private func fantasyPool(leagueId: Int, season: Int) async -> [FantasyPlayer] {
        var byId: [Int: FantasyPlayer] = [:]

        // Tentative principale : effectif complet via /players (paginé).
        let raw = (try? await fetchAllPlayers(leagueId: leagueId, season: season)) ?? []
        for p in raw {
            let player = FantasyPlayer(
                id: p.player.id,
                name: p.player.name,
                club: p.teamName,
                photo: p.player.photo,
                position: p.statistics.first?.games.position,
                goals: p.totalGoals,
                assists: p.totalAssists,
                appearances: p.totalAppearances
            )
            if let existing = byId[player.id], existing.points >= player.points { continue }
            byId[player.id] = player
        }

        // FALLBACK topscorers si /players n'a rien donné pour cette saison.
        if byId.isEmpty {
            let scorers = (try? await fetch(
                "/players/topscorers?league=\(leagueId)&season=\(season)"
            ) as AFResponse<AFPlayerResponse>)?.response ?? []
            for sPlayer in scorers {
                let player = FantasyPlayer(
                    id: sPlayer.player.id,
                    name: sPlayer.player.name,
                    club: sPlayer.teamName,
                    photo: sPlayer.player.photo,
                    position: sPlayer.statistics.first?.games.position,
                    goals: sPlayer.goals,
                    assists: sPlayer.assists,
                    appearances: sPlayer.appearances
                )
                if let existing = byId[player.id], existing.points >= player.points { continue }
                byId[player.id] = player
            }
        }

        return byId.values.sorted {
            if $0.points != $1.points { return $0.points > $1.points }
            return $0.name < $1.name
        }
    }

    /// Rafraîchit UNIQUEMENT les joueurs déjà dans l'équipe (par leur id), pour
    /// mettre leurs points à jour à chaque ouverture de l'onglet « Mon équipe »
    /// SANS recharger tout le vivier (≈30 requêtes). Ici : 1 requête par joueur,
    /// soit 5 au maximum. Endpoint /players?id=…&league=…&season=… .
    /// - Note quota : léger, adapté à un appel à chaque affichage de l'onglet.
    /// - Bascule de saison : comme le vivier, on tente la saison courante puis,
    ///   si un joueur n'a aucune stat (saison pas encore peuplée), la précédente.
    func fetchFantasySquadRefresh(ids: [Int]) async -> [FantasyPlayer] {
        guard !ids.isEmpty else { return [] }
        let leagueId = Self.fantasyLeagueApiId
        let currentSeason = seasonForLeagueId(leagueId)

        var result: [FantasyPlayer] = []
        for id in ids {
            // 1) Saison en cours.
            if let p = await fetchOnePlayer(id: id, leagueId: leagueId, season: currentSeason) {
                result.append(p)
                continue
            }
            // 2) Repli saison précédente si rien pour la saison en cours.
            if let p = await fetchOnePlayer(id: id, leagueId: leagueId, season: currentSeason - 1) {
                result.append(p)
            }
            // Espacement anti-429 (l'API limite le débit).
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return result
    }

    /// Récupère UN joueur (stats de saison agrégées) pour une ligue/saison données.
    /// Renvoie nil si l'API ne renvoie rien (joueur inconnu ou saison vide).
    private func fetchOnePlayer(id: Int, leagueId: Int, season: Int) async -> FantasyPlayer? {
        guard let r: AFResponse<AFPlayerResponse> = try? await fetch(
            "/players?id=\(id)&league=\(leagueId)&season=\(season)"
        ), let p = r.response.first else { return nil }
        return FantasyPlayer(
            id: p.player.id,
            name: p.player.name,
            club: p.teamName,
            photo: p.player.photo,
            position: p.statistics.first?.games.position,
            goals: p.totalGoals,
            assists: p.totalAssists,
            appearances: p.totalAppearances
        )
    }

    // ─────────────────────────────────────────────────────────────────────────
    // VARIANTES « PAR POULE » (une seule ligue API à la fois)
    // Pour un championnat à poules-ligues distinctes (National 1 = 67/68/69),
    // ces méthodes ciblent UNE poule précise (leagueId) au lieu d'agréger les 3.
    // Utilisées par CompetitionDetailView quand une poule est sélectionnée, afin
    // que Résultats / Classement / Buteurs / Journées portent tous sur la poule.
    // ─────────────────────────────────────────────────────────────────────────

    /// Matchs d'UNE poule sur une fenêtre glissante (-14 / +7 jours).
    func fetchMatches(competition: Competition, groupApiId: Int) async throws -> [AFFixture] {
        let s = season(for: competition)
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let from = fmt.string(from: Calendar.current.date(byAdding: .day, value: -14, to: Date())!)
        let to   = fmt.string(from: Calendar.current.date(byAdding: .day, value: 7,  to: Date())!)
        let r: AFResponse<AFFixture> = try await fetch(
            "/fixtures?league=\(groupApiId)&season=\(s)&from=\(from)&to=\(to)&timezone=Europe/Paris"
        )
        return r.response.sorted { $0.fixture.date < $1.fixture.date }
    }

    /// TOUS les matchs d'UNE poule (sans fenêtre de dates). Sert à trouver la
    /// prochaine journée quand le championnat n'a pas encore commencé.
    func fetchAllFixtures(competition: Competition, groupApiId: Int) async throws -> [AFFixture] {
        let s = season(for: competition)
        let r: AFResponse<AFFixture> = try await fetch(
            "/fixtures?league=\(groupApiId)&season=\(s)&timezone=Europe/Paris"
        )
        return r.response.sorted { $0.fixture.date < $1.fixture.date }
    }

    /// Journées disponibles d'UNE poule.
    func fetchRounds(competition: Competition, groupApiId: Int) async throws -> [String] {
        struct RoundResponse: Codable { let response: [String] }
        let s = season(for: competition)
        let r: RoundResponse = try await fetch("/fixtures/rounds?league=\(groupApiId)&season=\(s)")
        return filterRounds(r.response, for: competition)
    }

    /// Journée « courante » d'UNE poule (current=true), nil si aucune.
    func fetchCurrentRound(competition: Competition, groupApiId: Int) async throws -> String? {
        struct RoundResponse: Codable { let response: [String] }
        let s = season(for: competition)
        let r: RoundResponse = try await fetch(
            "/fixtures/rounds?league=\(groupApiId)&season=\(s)&current=true"
        )
        return r.response.first
    }

    /// Matchs d'une journée précise d'UNE poule.
    func fetchMatchesByRound(competition: Competition, groupApiId: Int, round: String) async throws -> [AFFixture] {
        let s = season(for: competition)
        let encoded = round.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? round
        let r: AFResponse<AFFixture> = try await fetch(
            "/fixtures?league=\(groupApiId)&season=\(s)&round=\(encoded)&timezone=Europe/Paris"
        )
        return r.response.sorted { $0.fixture.date < $1.fixture.date }
    }

    /// Buteurs d'UNE poule.
    func fetchTopScorers(competition: Competition, groupApiId: Int) async throws -> [AFPlayerResponse] {
        // Repli saison précédente (voir fetchTopScorers(competition:)).
        for s in seasonsToTry(for: competition) {
            if let r: AFResponse<AFPlayerResponse> = try? await fetch(
                "/players/topscorers?league=\(groupApiId)&season=\(s)"
            ), !r.response.isEmpty {
                return r.response.sorted {
                    if $0.goals != $1.goals { return $0.goals > $1.goals }
                    return $0.assists > $1.assists
                }
            }
        }
        return []
    }

    /// Meilleurs passeurs d'UNE poule (endpoint dédié `/players/topassists`).
    func fetchTopAssists(competition: Competition, groupApiId: Int) async throws -> [AFPlayerResponse] {
        for s in seasonsToTry(for: competition) {
            if let r: AFResponse<AFPlayerResponse> = try? await fetch(
                "/players/topassists?league=\(groupApiId)&season=\(s)"
            ), !r.response.isEmpty {
                return r.response.sorted {
                    if $0.assists != $1.assists { return $0.assists > $1.assists }
                    return $0.goals > $1.goals
                }
            }
        }
        return []
    }

    /// Classement d'UNE poule (un seul sous-tableau, trié par rang). [] si vide.
    func fetchStandings(competition: Competition, groupApiId: Int) async throws -> [AFStandingEntry] {
        let s = season(for: competition)
        let r: AFResponse<AFStandingResponse> = try await fetch(
            "/standings?league=\(groupApiId)&season=\(s)"
        )
        let poule = r.response.first?.league.standings?.first ?? []
        return poule.sorted { $0.rank < $1.rank }
    }

    // ── Filtrage de la recherche d'équipe ────────────────────────────────────
    // L'API `teams?search=` renvoie TOUTES les équipes (féminines « W », jeunes
    // U19/U21/U23, réserves « B »/« II », académies…). On veut ne montrer que les
    // équipes PERTINENTES. Double filtre (choix user 2026-08-13) :
    //   1. Heuristique de nom → écarte les variantes W/U19/B/Reserve…
    //   2. Appartenance aux championnats du catalogue → ne garde que les équipes
    //      qui jouent réellement dans une compétition active de l'app.

    /// Cache des IDs d'équipes appartenant aux championnats actifs de l'app.
    /// Chargé paresseusement au 1er usage, puis conservé pour la session (évite
    /// de re-solliciter l'API à chaque recherche). nil = pas encore chargé.
    private var catalogTeamIds: Set<Int>?
    /// teamId → prestige (0 = ligue la plus prioritaire du catalogue, France en
    /// tête). Rempli par `ensureCatalogTeamIds`. Sert au TRI de la recherche joueurs.
    private var catalogTeamRank: [Int: Int] = [:]

    /// Marqueurs de nom qui trahissent une équipe NON pertinente (féminine, jeunes,
    /// réserve). Testés en minuscules, sur des mots/segments délimités.
    private static let excludedTeamMarkers: [String] = [
        "women", "féminin", "feminin", "feminine", "femenino", "femminile", "ladies",
        "u17", "u-17", "u18", "u-18", "u19", "u-19", "u20", "u-20",
        "u21", "u-21", "u22", "u-22", "u23", "u-23",
        "youth", "junior", "juniors", "academy", "reserve", "reserves"
    ]

    /// Vrai si le nom d'équipe correspond à une variante à écarter (W, U19, B…).
    private static func isExcludedByName(_ name: String) -> Bool {
        let lower = name.lowercased()
        // Marqueurs « mot entier » (féminin, jeunes, réserve…).
        for m in excludedTeamMarkers where lower.contains(m) { return true }
        // Suffixe court isolé : « … W », « … B », « … II » (équipe réserve/féminine).
        // On découpe en mots et on teste le dernier token.
        let tokens = lower.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        if let last = tokens.last, ["w", "b", "ii", "c"].contains(last) { return true }
        return false
    }

    /// Charge (une seule fois) l'ensemble des IDs d'équipes des championnats actifs.
    /// Ligues seulement (les IDs de coupes/sélections ne renvoient pas d'effectif
    /// pertinent ici). Chaque ligue est demandée en `try?` : une ligue en échec ne
    /// bloque pas les autres.
    private func ensureCatalogTeamIds() async {
        if catalogTeamIds != nil { return }
        var ids = Set<Int>()
        var rank = [Int: Int]()   // teamId → prestige (plus petit = plus prioritaire)

        // Petit utilitaire : enregistre un club avec un rang de prestige, en gardant
        // le MEILLEUR (plus petit) rang si le club apparaît dans plusieurs comps
        // (ex. un club FR trouvé via sa ligue ET via une coupe d'Europe → garde le
        // rang de sa ligue, donc France reste devant).
        func register(_ teamId: Int, _ prestige: Int) {
            ids.insert(teamId)
            if let existing = rank[teamId] { rank[teamId] = min(existing, prestige) }
            else { rank[teamId] = prestige }
        }

        // 1) LIGUES DE CLUBS — on PRÉSERVE l'ordre du catalogue (France en tête, puis
        //    grands championnats) : l'index dans `leagues` EST le rang de prestige.
        //    (On saute les sélections nationales : la recherche d'équipes nationales
        //    reste filtrée par l'heuristique + le flag `national`.)
        let leagues = Catalog.all
            .filter { $0.isAvailable && ($0.kind == .league || $0.kind == .leagueGroups) }
        for (leagueOrder, comp) in leagues.enumerated() {
            for lid in comp.allApiIds {
                let s = seasonForLeagueId(lid)
                if let r: AFResponse<AFTeamResult> =
                    try? await fetch("/teams?league=\(lid)&season=\(s)") {
                    for t in r.response { register(t.team.id, leagueOrder) }
                }
            }
        }

        // 2) COUPES D'EUROPE (demande user 2026-08-19 : « je veux aussi les coupes
        //    d'Europe ») — UCL/UEL/UECL/Supercoupe : les clubs engagés comptent comme
        //    « connus ». Rang = juste APRÈS toutes les ligues, donc un club trouvé
        //    UNIQUEMENT via une coupe (championnat hors catalogue) reste sous les
        //    clubs des ligues du catalogue, mais un club FR/grand championnat garde
        //    son rang de ligue (via `min` dans `register`). La FRANCE reste 1re.
        let euroCupRank = leagues.count
        let euroCups = Catalog.all
            .filter { $0.isAvailable && $0.section == .europe }
        for comp in euroCups {
            for lid in comp.allApiIds {
                let s = seasonForLeagueId(lid)
                if let r: AFResponse<AFTeamResult> =
                    try? await fetch("/teams?league=\(lid)&season=\(s)") {
                    for t in r.response { register(t.team.id, euroCupRank) }
                }
            }
        }

        catalogTeamIds = ids
        catalogTeamRank = rank
    }

    /// Saison à demander pour un leagueId brut (miroir de `season(for:)` mais à
    /// partir de l'ID API, utilisé pour lister les effectifs).
    private func seasonForLeagueId(_ leagueId: Int) -> Int {
        if let comp = Catalog.all.first(where: { $0.allApiIds.contains(leagueId) }) {
            return season(for: comp)
        }
        return defaultSeason
    }

    // Recherche d'équipe par nom (min. 3 caractères côté API-Football)
    func searchTeams(query: String) async throws -> [AFTeamResult] {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 3 else { return [] }
        // TRADUCTION FR/ES/IT/DE/PT → EN : l'API n'indexe les sélections/clubs qu'en
        // anglais. « Brésil » → « Brazil », « Espagne » → « Spain »… Si la saisie
        // n'est pas un nom de pays connu, on garde la saisie telle quelle (club).
        let q = CountryNameTranslator.englishName(for: raw) ?? raw
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        let r: AFResponse<AFTeamResult> = try await fetch("/teams?search=\(encoded)")

        // Filtre 1 : heuristique de nom (écarte W / U19 / B / réserves…).
        var filtered = r.response.filter { !Self.isExcludedByName($0.team.name) }

        // Filtre 2 : appartenance aux championnats de l'app. On charge (avec cache)
        // les équipes des ligues actives, puis on ne garde que celles présentes.
        // Sécurité : si le cache est vide (échec réseau/quota), on NE filtre PAS
        // par appartenance pour ne pas renvoyer une liste vide à tort.
        await ensureCatalogTeamIds()
        // Une entrée n'est une VRAIE sélection nationale que si `national == true`
        // ET que son nom est un nom de PAYS connu. L'API marque parfois `national`
        // à tort sur des clubs (ex. « Adh Brasil » apparaissait « Brazil · Sélection »
        // en tapant « Brazil ») : on les exclut du groupe sélections.
        func isRealNation(_ t: AFTeamInfo) -> Bool {
            guard t.national ?? false else { return false }
            let n = t.name.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            return CountryFlag.isCountryName(n)
        }
        if let valid = catalogTeamIds, !valid.isEmpty {
            // On garde : (a) les équipes de clubs présentes dans une ligue active,
            // ET (b) les VRAIES sélections nationales (nom = pays), même hors cache.
            filtered = filtered.filter {
                valid.contains($0.team.id) || isRealNation($0.team)
            }
        }

        // Tri (demande user 2026-08-17) : les SÉLECTIONS NATIONALES d'abord, pour
        // qu'en tapant « France » on propose la sélection AVANT les dizaines de
        // clubs français. Au sein de chaque groupe (nations puis clubs), on remonte
        // les noms qui COMMENCENT par la requête (correspondance forte), puis on
        // trie par nom. Ex. « France » → 🇫🇷 France (nation) en tête.
        let needle = q.lowercased()
        func startsWithQuery(_ name: String) -> Bool {
            name.lowercased().hasPrefix(needle)
        }
        return filtered.sorted { a, b in
            let na = a.team.national ?? false, nb = b.team.national ?? false
            if na != nb { return na && !nb }                     // nations d'abord
            let pa = startsWithQuery(a.team.name), pb = startsWithQuery(b.team.name)
            if pa != pb { return pa && !pb }                     // préfixe exact ensuite
            return a.team.name < b.team.name                     // puis alphabétique
        }
    }

    // Recherche de JOUEURS par nom (/players/profiles?search=). Cet endpoint
    // renvoie uniquement l'identité (bloc `player`), sans statistiques — parfait
    // pour une liste de résultats de recherche légère. Min. 3 caractères (règle
    // API-Football). Tolérant : renvoie [] si vide/échec plutôt que de lever.
    func searchPlayers(query: String) async throws -> [AFPlayerProfile] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return [] }
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q

        // 1) Recherche globale par NOM (identité seule, pas de club).
        let r: AFResponse<AFPlayerProfileEntry> = try await fetch("/players/profiles?search=\(encoded)")
        var seen = Set<Int>()
        var candidates = r.response.map { $0.player }.filter { seen.insert($0.id).inserted }

        // 1bis) Recherche par PRÉNOM d'une star mal indexée (2026-08-19). Ousmane
        //   Dembélé est enregistré « Masour Dembélé » dans l'API → taper « Ousmane »
        //   ne le ramène pas. Si la saisie correspond au vrai prénom/nom d'une star,
        //   on relance une recherche par son NOM DE FAMILLE indexé et on fusionne les
        //   fiches (dédoublonnées). La liste blanche plus bas la remontera en tête.
        for lastname in PlayerOverrides.lastnamesToProbe(forQuery: q) {
            let enc = lastname.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? lastname
            if let extra: AFResponse<AFPlayerProfileEntry> =
                try? await fetch("/players/profiles?search=\(enc)") {
                for p in extra.response.map({ $0.player }) where seen.insert(p.id).inserted {
                    candidates.append(p)
                }
            }
        }

        // 2) La recherche doit porter UNIQUEMENT sur prénom/nom : on écarte les
        //    correspondances qui ne matchent que par un autre champ (l'API peut
        //    renvoyer des noms composés éloignés). On garde un joueur si l'un de ses
        //    tokens de prénom OU de nom COMMENCE par la requête (préfixe), ce qui
        //    colle au comportement attendu (« Mbap » → Mbappé, pas « Mbapandza »
        //    seulement si un token débute par la saisie).
        let needle = q.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        func norm(_ s: String) -> String {
            s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        }
        func nameMatches(_ p: AFPlayerProfile) -> Bool {
            // (0) Une STAR connue est TOUJOURS gardée, même si la saisie (vrai prénom
            //     « Ousmane ») ne matche pas le prénom FAUX de l'API (« Masour ») : sa
            //     fiche a été ramenée exprès par la recherche 1bis via son nom de famille.
            if PlayerOverrides.star(lastname: p.lastname,
                                    firstname: p.firstname, fullName: p.name) != nil {
                return true
            }
            let fields = [p.firstname, p.lastname, p.name].compactMap { $0 }
            // (a) un token de prénom/nom COMMENCE par la saisie (« Mbap » → Mbappé) ;
            let tokens = fields
                .flatMap { $0.split(whereSeparator: { $0 == " " || $0 == "-" }) }
                .map { norm(String($0)) }
            if tokens.contains(where: { $0.hasPrefix(needle) }) { return true }
            // (b) repli : la saisie apparaît dans le nom complet (« yamal » présent dans
            //     un nom composé où « Yamal » n'est pas en tête de token). Évite de rater
            //     un joueur dont le nom d'usage est enfoui dans l'état civil de l'API.
            return fields.contains { norm($0).contains(needle) }
        }
        candidates = candidates.filter(nameMatches)

        func hasRealPhoto(_ p: AFPlayerProfile) -> Bool {
            guard let ph = p.photo?.lowercased() else { return false }
            // API-Football sert un placeholder pour les joueurs sans photo.
            return !ph.isEmpty && !ph.contains("placeholder") && !ph.hasSuffix("/0.png")
        }

        // ─── LISTE BLANCHE DE STARS (2026-08-19, remplace le tri par catalogue) ───
        // Le tri « par club du catalogue » dépendait de dizaines d'appels réseau qui
        // échouaient (catalogue vide → tout retombait au même niveau, Ousmane Dembélé
        // — indexé « Masour Dembélé », mauvaise photo — n'apparaissait jamais).
        // Nouvelle règle SANS RÉSEAU : on repère parmi les résultats bruts les fiches
        // qui correspondent à une STAR connue (table statique `PlayerOverrides`), on
        // leur applique nom d'affichage + club EN DUR, et on les remonte EN TÊTE,
        // triées par leur rang de prestige. Le reste suit (photo réelle d'abord).
        var stars: [(p: AFPlayerProfile, rank: Int)] = []
        var others: [AFPlayerProfile] = []
        var seenStar = Set<String>()   // dédoublonne une même star (plusieurs fiches API)
        for var p in candidates {
            if let s = PlayerOverrides.star(lastname: p.lastname,
                                            firstname: p.firstname,
                                            fullName: p.name) {
                // Une seule fiche par star (garde la 1re, souvent la mieux renseignée).
                if seenStar.insert(s.displayName).inserted {
                    p.resolvedClubName = s.club   // club en dur, aucun appel réseau
                    stars.append((p, s.rank))
                }
            } else {
                others.append(p)
            }
        }
        // Stars triées par prestige (0 = tête) puis alphabétique.
        stars.sort {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            return $0.p.displayName.localizedCaseInsensitiveCompare($1.p.displayName) == .orderedAscending
        }
        // Autres joueurs : photo réelle d'abord (signal faible de notoriété — les
        // inconnus n'ont qu'un avatar générique), puis alphabétique.
        others.sort {
            let a = hasRealPhoto($0), b = hasRealPhoto($1)
            if a != b { return a }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        var result = stars.map { $0.p } + others
        result = Array(result.prefix(8))

        // Résolution du club POUR L'AFFICHAGE uniquement (sous-titre de la ligne),
        // limitée aux 8 joueurs affichés — coût borné, mémoïsé par playerId. N'INFLUE
        // PLUS sur le tri (assuré par la liste blanche). Les stars gardent leur club
        // en dur (resolvedClubName déjà rempli) → on ne les re-résout pas.
        for i in result.indices where result[i].resolvedClubName == nil {
            if let club = await cachedPlayerClub(playerId: result[i].id) {
                result[i].resolvedClubName = club.name
                result[i].resolvedClubId = club.id
            }
        }
        return result
    }

    // Cache mémoire du club actuel (id + nom d'affichage) par joueur, pour la
    // recherche. L'absence de clé = pas encore résolu ; une valeur nil (encodée par
    // un id == -1) = déjà résolu SANS club → on ne recoûte pas d'appel.
    private var playerClubCache: [Int: AFTeamInfo] = [:]
    private var playerClubResolved: Set<Int> = []

    /// Club actuel d'un joueur (id + nom), mémoïsé. nil si aucun club / échec réseau.
    private func cachedPlayerClub(playerId: Int) async -> (id: Int, name: String)? {
        if playerClubResolved.contains(playerId) {
            guard let t = playerClubCache[playerId] else { return nil }
            return (t.id, t.displayName)
        }
        let club = await fetchPlayerCurrentClub(playerId: playerId)
        playerClubResolved.insert(playerId)
        if let club { playerClubCache[playerId] = club }
        guard let club else { return nil }
        return (club.id, club.displayName)
    }

    // Infos d'une équipe par son ID (nom, logo, pays) — pour les cartes de
    // l'assistant IA (bloc teamCard) qui ne reçoivent qu'un teamId du proxy.
    func fetchTeamInfo(teamId: Int) async throws -> AFTeamInfo {
        let r: AFResponse<AFTeamResult> = try await fetch("/teams?id=\(teamId)")
        guard let info = r.response.first?.team else { throw APIError.noData }
        return info
    }

    // Fiche complète d'une équipe (équipe + stade/ville) — 1 appel /teams?id=.
    // Réutilise l'endpoint déjà appelé par fetchTeamInfo, mais garde le venue
    // (stade, ville) pour l'en-tête de la fiche équipe. « Non coûteux ».
    func fetchTeamResult(teamId: Int) async throws -> AFTeamResult {
        let r: AFResponse<AFTeamResult> = try await fetch("/teams?id=\(teamId)")
        guard let result = r.response.first else { throw APIError.noData }
        return result
    }

    // Entraîneur actuel d'une équipe (/coachs?team=). 1 appel léger, TOLÉRANT
    // (nil si vide/échec → la vue masque la ligne coach). L'endpoint renvoie
    // l'historique des coachs ; on prend celui dont la mission en cours concerne
    // cette équipe (career sans date de fin sur team.id), sinon le 1er de la liste
    // (API-Football trie généralement le poste actuel en tête). Réutilise le
    // modèle AFCoach (id/name/photo) déjà défini pour les compositions.
    func fetchTeamCoach(teamId: Int) async -> AFCoach? {
        guard let r: AFResponse<AFCoachEntry> =
            try? await fetch("/coachs?team=\(teamId)") else { return nil }
        let entries = r.response
        // PIÈGE : /coachs?team= renvoie TOUT l'historique des entraîneurs du club.
        // Plusieurs entrées peuvent avoir une mission `end == nil` (donnée sale :
        // d'anciens intérimaires restent "ouverts"). Prendre la 1re trouvée donnait
        // un vieux coach (ex. Larguet à l'OM au lieu de De Zerbi). CORRECTIF : parmi
        // les missions SUR CETTE ÉQUIPE encore ouvertes (end == nil), garder celle
        // dont la date de DÉBUT est la plus récente ; à défaut, la mission la plus
        // récente (ouverte ou non) sur cette équipe.
        func latestStart(_ entry: AFCoachEntry, openOnly: Bool) -> String? {
            (entry.career ?? [])
                .filter { $0.team?.id == teamId && (!openOnly || $0.end == nil) }
                .compactMap { $0.start }
                .max()   // dates ISO "YYYY-MM-DD" → tri lexicographique = chrono
        }
        // 1) missions en cours sur cette équipe, la plus récemment débutée.
        let open = entries
            .compactMap { e -> (AFCoachEntry, String)? in
                latestStart(e, openOnly: true).map { (e, $0) }
            }
            .max(by: { $0.1 < $1.1 })?.0
        // 2) repli : mission la plus récente (peu importe end) sur cette équipe.
        let anyRecent = entries
            .compactMap { e -> (AFCoachEntry, String)? in
                latestStart(e, openOnly: false).map { (e, $0) }
            }
            .max(by: { $0.1 < $1.1 })?.0
        guard let c = open ?? anyRecent ?? entries.first else { return nil }
        return AFCoach(id: c.id, name: c.name, photo: c.photo)
    }

    // Bilan de saison d'une équipe DANS une compétition (/teams/statistics).
    // 1 appel. TOLÉRANT : renvoie nil en cas d'échec (la vue masque alors le
    // bloc bilan). league/season sont dérivés des fixtures déjà chargées, cf.
    // `mainLeague(from:)` ci-dessous — pas d'appel supplémentaire pour ça.
    func fetchTeamStatistics(teamId: Int, league: Int, season: Int) async -> AFTeamSeasonStats? {
        // /teams/statistics renvoie un OBJET (pas un tableau) → wrapper dédié.
        let r: AFObjectResponse<AFTeamSeasonStats>? =
            try? await fetch("/teams/statistics?team=\(teamId)&league=\(league)&season=\(season)")
        return r?.response
    }

    // ── LOGO DE COMPÉTITION (par ID API-Football) ──────────────────────────────
    // SOURCE FIABLE du logo de CHAQUE compétition = /leagues?id=<apiId>, qui
    // renvoie `league.logo` (URL) pour TOUTES les ligues API-Football, y compris
    // L1/L2/L3/N1/Coupe de France que TheSportsDB (match par nom) ne trouvait pas.
    // Match par ID (jamais par nom) → aucun risque de mauvaise ligue. Décodage
    // tolérant, mémorisé par le cache réseau. Choix user 2026-08-16 : « vrais logos
    // partout ». Repli monogramme géré côté vue si nil.
    func fetchLeagueLogo(leagueId: Int) async -> URL? {
        guard let r: AFResponse<AFLeagueEntry> =
                try? await fetch("/leagues?id=\(leagueId)"),
              let logo = r.response.first?.league.logo,
              !logo.isEmpty
        else { return nil }
        return URL(string: logo)
    }

    // ── FAIR-PLAY ────────────────────────────────────────────────────────────
    // Classement d'indiscipline d'une compétition : pour CHAQUE équipe, on lit ses
    // cartons via /teams/statistics (seule source fiable ; standings n'a pas les
    // cartons). COÛT : 1 appel standings (ou N pour multi-poules) + 1 appel par
    // équipe (~18-20). Les appels par équipe sont lancés EN PARALLÈLE (TaskGroup)
    // et le cache réseau évite de refacturer si on rouvre la rubrique. Tolérant :
    // une équipe en échec est simplement omise, jamais d'invention de chiffres.
    func fetchFairPlay(competition: Competition) async -> [FairPlayEntry] {
        // Repli saison précédente si la saison en cours n'a pas encore d'équipes
        // publiées (coupes d'Europe en août). Voir fetchTopScorers(competition:).
        for s in seasonsToTry(for: competition) {
            let entries = await fetchFairPlay(competition: competition, season: s)
            if !entries.isEmpty { return entries }
        }
        return []
    }

    private func fetchFairPlay(competition: Competition, season s: Int) async -> [FairPlayEntry] {
        // 1) Équipes de la compétition, associées à LEUR ligue (important en multi-poules
        //    pour interroger /teams/statistics avec le bon league).
        //    SOURCE PRIMAIRE = /teams (disponible dès que la ligue existe, même
        //    avant la publication d'un classement en début de saison). REPLI =
        //    /standings (utile pour les phases de groupes de coupes d'Europe où
        //    /teams?league= peut être moins fiable). Sans ce repli, le fair-play
        //    était VIDE tant que le classement n'était pas publié (cas Ligue 2 en
        //    tout début de saison).
        var teamsByLeague: [(team: AFTeam, league: Int)] = []
        for leagueId in competition.allApiIds {
            var added = false
            if let r: AFResponse<AFTeamResult> = try? await fetch(
                "/teams?league=\(leagueId)&season=\(s)"
            ), !r.response.isEmpty {
                for t in r.response {
                    teamsByLeague.append((AFTeam(id: t.team.id, name: t.team.name, logo: t.team.logo), leagueId))
                }
                added = true
            }
            // Repli sur le classement si /teams n'a rien renvoyé pour cette ligue.
            if !added, let r: AFResponse<AFStandingResponse> = try? await fetch(
                "/standings?league=\(leagueId)&season=\(s)"
            ) {
                let entries = (r.response.first?.league.standings ?? []).flatMap { $0 }
                for e in entries { teamsByLeague.append((e.team, leagueId)) }
            }
        }
        // Dédoublonnage par équipe (au cas où une équipe apparaîtrait deux fois).
        var seen = Set<Int>()
        let uniqueTeams = teamsByLeague.filter { seen.insert($0.team.id).inserted }
        guard !uniqueTeams.isEmpty else { return [] }

        // 2) Stats (cartons) par équipe, en parallèle.
        //    L'appel + l'extraction des champs sont faits dans une méthode dédiée
        //    (contexte isolé de la classe) pour ne pas franchir la frontière
        //    d'isolation avec un AFTeamSeasonStats non-Sendable dans la closure.
        let results: [FairPlayEntry] = await withTaskGroup(of: FairPlayEntry?.self) { group in
            for item in uniqueTeams {
                group.addTask {
                    await self.fairPlayEntry(for: item.team, league: item.league, season: s)
                }
            }
            var acc: [FairPlayEntry] = []
            for await r in group { if let r { acc.append(r) } }
            return acc
        }

        // 3) Tri CROISSANT par points d'indiscipline (plus fair-play en tête).
        //    Départage : moins de rouges d'abord, puis nom.
        return results.sorted {
            if $0.points != $1.points { return $0.points < $1.points }
            if $0.red != $1.red { return $0.red < $1.red }
            return $0.team.name < $1.team.name
        }
    }

    /// Charge les stats d'une équipe et en dérive une entrée fair-play.
    /// Toute la lecture d'`AFTeamSeasonStats` (non-Sendable) reste dans le
    /// contexte isolé de la classe → renvoie un `FairPlayEntry` (Sendable).
    /// TOUJOURS non-nil : le classement doit lister TOUTES les équipes de la
    /// compétition, y compris celles à 0 carton (elles apparaissent en tête, 0 pt).
    /// Si l'appel stats échoue, on garde l'équipe avec 0/0/0 plutôt que de la perdre.
    private func fairPlayEntry(for team: AFTeam, league: Int, season: Int) async -> FairPlayEntry? {
        let stats = await fetchTeamStatistics(teamId: team.id, league: league, season: season)
        return FairPlayEntry(team: team,
                             played: stats?.played ?? 0,
                             yellow: stats?.yellowCards ?? 0,
                             red: stats?.redCards ?? 0)
    }

    // Dérive la compétition "principale" d'une équipe à partir de ses matchs déjà
    // chargés : on prend la ligue (type "League", pas coupe) la plus fréquente, et
    // la saison la plus récente qui lui est associée. Frugal (0 appel réseau) et
    // robuste : fonctionne même si l'équipe joue aussi une coupe / une C1.
    // Renvoie nil si aucune ligue exploitable (→ on n'appelle pas /teams/statistics).
    func mainLeague(from fixtures: [AFFixture]) -> (league: Int, season: Int)? {
        // Ne garder que les compétitions de type championnat (exclut les coupes).
        let leagueFixtures = fixtures.filter {
            ($0.league.type ?? "").caseInsensitiveCompare("League") == .orderedSame
        }
        let pool = leagueFixtures.isEmpty ? fixtures : leagueFixtures
        guard !pool.isEmpty else { return nil }

        // Compter les occurrences par id de ligue.
        var counts: [Int: Int] = [:]
        for f in pool { counts[f.league.id, default: 0] += 1 }
        guard let bestLeague = counts.max(by: { $0.value < $1.value })?.key else { return nil }

        // Saison la plus récente rencontrée pour cette ligue (défaut : defaultSeason).
        let season = pool
            .filter { $0.league.id == bestLeague }
            .compactMap { $0.league.season }
            .max() ?? defaultSeason
        return (bestLeague, season)
    }

    // Effectif d'une équipe — base = /players/squads?team= (1 appel léger, liste
    // complète : identité, poste, n°, photo, sans stats).
    //
    // FIABILITÉ (2026-08-16) : /players/squads est souvent EN RETARD après un
    // transfert (ex. Rulli listé à Marseille alors qu'il est parti à Man City).
    // On recoupe donc avec les joueurs RÉELLEMENT rattachés à l'équipe sur la
    // saison en cours (/players?team=&season=), qui est à jour. DIAGNOSTIC confirmé :
    // Rulli renvoie results:0 sur /players?team=81&season=2026.
    //
    // MAIS en tout début de saison, /players?team=&season=2026 est encore VIDE
    // (stats pas peuplées) → on ne peut pas filtrer sans vider l'effectif à tort.
    // Règle : on ne retire un joueur QUE si la liste des actifs est NON VIDE.
    // Ainsi aujourd'hui l'effectif reste complet ; dès que la saison se peuple,
    // les joueurs partis disparaissent automatiquement, sans changement de code.
    func fetchTeamSquad(teamId: Int) async throws -> [AFSquadPlayer] {
        let r: AFResponse<AFSquadResponse> = try await fetch("/players/squads?team=\(teamId)")
        let squad = r.response.first?.players ?? []

        // Liste (à jour) des joueurs actifs cette saison — tolérante à l'échec.
        let season = defaultSeason
        let activeIds = await fetchActivePlayerIds(teamId: teamId, season: season)

        // Filtre SILENCIEUX : seulement si la source à jour a renvoyé quelque chose.
        guard !activeIds.isEmpty else { return squad }
        return squad.filter { activeIds.contains($0.id) }
    }

    // IDs des joueurs réellement rattachés à une équipe sur une saison donnée
    // (/players?team=&season=, paginé). Utilisé pour écarter de l'effectif les
    // joueurs partis que /players/squads garde en retard. TOLÉRANT : renvoie un
    // Set vide en cas d'échec/liste vide → l'appelant ne filtre alors pas.
    func fetchActivePlayerIds(teamId: Int, season: Int) async -> Set<Int> {
        var ids = Set<Int>()
        // Garde-fou : on plafonne les pages pour ne jamais exploser le quota
        // (un effectif tient en 1-2 pages ; 5 est une marge large).
        var page = 1
        let maxPages = 5
        while page <= maxPages {
            guard let r: AFResponse<AFPlayerResponse> =
                try? await fetch("/players?team=\(teamId)&season=\(season)&page=\(page)")
            else { break }
            for entry in r.response { ids.insert(entry.player.id) }
            let total = r.paging?.total ?? 1
            if page >= total { break }
            page += 1
        }
        return ids
    }

    // Fiche détaillée d'UN joueur sur la saison courante — 1 appel /players?id=.
    // Renvoie identité (âge, nationalité, photo) + stats saison (matchs, buts,
    // passes) via AFPlayerResponse. Chargée uniquement quand on ouvre la fiche.
    func fetchPlayerDetail(playerId: Int, season: Int) async throws -> AFPlayerResponse {
        // Repli sur la saison précédente : en tout début de saison (ex. 2026-27),
        // /players?id=&season=2026 renvoie une liste VIDE car les stats
        // individuelles ne sont pas encore peuplées. On retente alors season-1
        // pour toujours afficher la fiche (identité + dernières stats connues).
        // Vérifié 2026-08-16 : de Lange (id 36827) → 2026 vide, 2025 = fiche complète.
        //
        // TOLÉRANCE : chaque saison est tentée INDÉPENDAMMENT via `try?`. Ainsi un
        // échec réseau/HTTP sur la saison courante (ex. tout début de saison, où
        // l'endpoint peut répondre en erreur plutôt que par une liste vide)
        // n'empêche PAS de retenter la saison précédente. On ne lève noData qu'en
        // dernier recours, si AUCUNE saison n'a renvoyé de fiche. On élargit aussi
        // le repli à season-2 (une fiche « dernière saison connue » vaut mieux que
        // l'écran « indisponible » pour un joueur bien réel comme de Lange).
        for s in [season, season - 1, season - 2] {
            if let r: AFResponse<AFPlayerResponse> =
                try? await fetch("/players?id=\(playerId)&season=\(s)"),
               let p = r.response.first {
                return p
            }
        }
        throw APIError.noData
    }

    // CLUB ACTUEL d'un joueur (id + nom), source AUTORITAIRE indépendante des stats
    // de match. /players/teams?player= renvoie toutes ses équipes, la plus récente
    // en tête. On IGNORE les sélections nationales (`national == true`) et on prend
    // le 1er club → « Real Madrid » pour Mbappé, même avant le 1er match de saison.
    // TOLÉRANT : renvoie nil en cas d'échec (l'appelant retombe alors sur ses autres
    // sources : ligne de club des stats, puis Wikidata).
    func fetchPlayerCurrentClub(playerId: Int) async -> AFTeamInfo? {
        guard let r: AFResponse<AFPlayerTeamEntry> =
            try? await fetch("/players/teams?player=\(playerId)") else { return nil }
        // La 1re équipe de club (non-sélection) = club actuel (liste triée récent→ancien).
        // On écarte les sélections via le flag `national` MAIS AUSSI par le nom : sur
        // /players/teams le champ `national` est parfois absent (→ nil) et une entrée
        // « France » passerait alors pour un club. Une équipe nationale porte le nom
        // d'un pays et n'a pas de suffixe de club (FC, CF, United…) → heuristique sûre.
        func isNationalTeam(_ t: AFTeamInfo) -> Bool {
            if t.national == true { return true }
            let n = t.name.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            return CountryFlag.isCountryName(n)
        }
        return r.response.first(where: { !isNationalTeam($0.team) })?.team
    }

    // Stats de la SAISON EN COURS UNIQUEMENT — 1 appel /players?id=&season=.
    // Contrairement à fetchPlayerDetail (qui replie sur les saisons passées pour
    // TOUJOURS afficher l'identité), ici on veut STRICTEMENT la saison demandée :
    //   • liste vide → le joueur n'a pas encore joué cette saison (ex. L1 pas
    //     démarrée) → la carte stats affichera des zéros honnêtes ;
    //   • JAMAIS de données d'une saison passée présentées comme « saison en cours ».
    // Tolérant à l'échec réseau : renvoie nil (la vue traite nil comme « 0 match »).
    func fetchPlayerSeasonStats(playerId: Int, season: Int) async -> AFPlayerResponse? {
        let r: AFResponse<AFPlayerResponse>? =
            try? await fetch("/players?id=\(playerId)&season=\(season)")
        return r?.response.first
    }

    // ── ENRICHISSEMENT CARRIÈRE via Wikidata (source ouverte, via le proxy) ──
    // API-Football ne fournit que les stats de la SAISON. Le proxy interroge
    // Wikidata pour les ATTRIBUTS CARRIÈRE : total sélections nationales, clubs
    // précédents (dates), club actuel + date d'arrivée, distinctions,
    // compétitions majeures, taille/poids/naissance, photo, id Transfermarkt.
    // Tolérant à l'échec : renvoie nil si le joueur est introuvable ou si le
    // proxy est injoignable → l'app se contente alors des stats de la saison.
    func fetchWikidataPlayer(name: String) async -> WikidataPlayer? {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        guard let url = URL(string: "\(AgentConfig.proxyBaseURL)/wikidata/player?name=\(encoded)") else {
            return nil
        }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 12   // SPARQL peut être lent ; on ne bloque pas trop la fiche
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            // Le proxy renvoie `null` (JSON) quand le joueur est introuvable.
            if data.count <= 4, String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "null" {
                return nil
            }
            return try? JSONDecoder().decode(WikidataPlayer.self, from: data)
        } catch {
            print("⚠️ fetchWikidataPlayer \(name) : \(error)")
            return nil
        }
    }

    // Matchs d'une équipe (derniers + à venir) sur la saison courante
    func fetchTeamFixtures(teamId: Int) async throws -> [AFFixture] {
        let r: AFResponse<AFFixture> = try await fetch(
            "/fixtures?team=\(teamId)&season=\(defaultSeason)&timezone=Europe/Paris"
        )
        return r.response.sorted { $0.fixture.date < $1.fixture.date }
    }

    // Matchs en direct — filtrés sur une liste d'IDs (nil = tous)
    func fetchLiveMatches(competitionIds: [Int]? = nil) async throws -> [AFFixture] {
        let ids = competitionIds.map { $0.map(String.init).joined(separator: "-") }
        let param = ids.map { "&league=\($0)" } ?? ""
        let r: AFResponse<AFFixture> = try await fetch("/fixtures?live=all\(param)&timezone=Europe/Paris")
        return r.response
    }

    // Matchs en direct de toutes les compétitions actives de l'app
    func fetchLiveMatchesForAvailable() async throws -> [AFFixture] {
        try await fetchLiveMatches(competitionIds: Catalog.availableApiIds)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // À VENIR (15 jours) — pour l'écran Live regroupé par rubrique
    // ─────────────────────────────────────────────────────────────────────────

    /// IDs des équipes FRANÇAISES (effectifs des championnats FR de l'app), chargé
    /// paresseusement puis conservé pour la session. Sert à repérer les clubs FR
    /// (PSG, OM… en Coupe d'Europe) afin de les remonter en priorité. nil = pas
    /// encore chargé ; ensemble vide toléré (on retombe alors sur la détection par
    /// nom « France » pour les sélections).
    private var frenchTeamIds: Set<Int>?

    func ensureFrenchTeamIds() async {
        if frenchTeamIds != nil { return }
        var ids = Set<Int>()
        for lid in Set(Catalog.frenchLeagueApiIds) {
            let s = seasonForLeagueId(lid)
            if let r: AFResponse<AFTeamResult> =
                try? await fetch("/teams?league=\(lid)&season=\(s)") {
                for t in r.response { ids.insert(t.team.id) }
            }
        }
        frenchTeamIds = ids
    }

    /// Ensemble courant des IDs d'équipes françaises (vide si pas encore chargé).
    /// Appelle `ensureFrenchTeamIds()` au préalable pour garantir le remplissage.
    var loadedFrenchTeamIds: Set<Int> { frenchTeamIds ?? [] }

    /// Vrai si l'ID d'équipe fait partie des effectifs français chargés.
    func isFrenchTeamId(_ id: Int) -> Bool { (frenchTeamIds ?? []).contains(id) }

    /// Vrai si l'un des deux camps est une équipe française : soit un club dont
    /// l'ID est dans les effectifs FR chargés, soit une équipe nommée « France »
    /// (sélection nationale, non couverte par le cache des clubs).
    func isFrenchFixture(_ f: AFFixture) -> Bool {
        let fr = frenchTeamIds ?? []
        if fr.contains(f.teams.home.id) || fr.contains(f.teams.away.id) { return true }
        let names = [f.teams.home.name, f.teams.away.name].map { $0.lowercased() }
        return names.contains { $0 == "france" }
    }

    /// Tous les matchs À VENIR (statut « non commencé ») des compétitions actives,
    /// dans une fenêtre de `days` jours à partir d'aujourd'hui. Agrège chaque poule
    /// des championnats multi-IDs. Chaque requête est en `try?` (une compétition en
    /// échec ne bloque pas les autres). Charge aussi les effectifs FR (pour la
    /// priorisation côté vue).
    /// - Parameter favoriteTeamIds: si fourni, on ajoute AUSSI les matchs à venir de
    ///   ces équipes quelle que soit la compétition (notamment les AMICAUX, qui ne
    ///   sont dans aucune ligue du catalogue) sur la même fenêtre de dates.
    func fetchUpcomingForAvailable(days: Int = 15,
                                   favoriteTeamIds: [Int] = []) async throws -> [AFFixture] {
        await ensureFrenchTeamIds()
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "Europe/Paris")
        let now = Date()
        let from = fmt.string(from: now)
        let to   = fmt.string(from: Calendar.current.date(byAdding: .day, value: days, to: now)!)

        var all: [AFFixture] = []
        for comp in Catalog.all where comp.isAvailable {
            let s = season(for: comp)
            for id in comp.allApiIds {
                if let r: AFResponse<AFFixture> = try? await fetch(
                    "/fixtures?league=\(id)&season=\(s)&from=\(from)&to=\(to)&timezone=Europe/Paris"
                ) {
                    all.append(contentsOf: r.response)
                }
            }
        }

        // Matchs des équipes FAVORITES — TOUTES compétitions, donc y compris les
        // amicaux (« Friendlies Clubs », hors catalogue). Le dédoublonnage par ID
        // plus bas fusionne avec les matchs de ligue déjà pris.
        // ⚠️ PIÈGE API-Football : combiner `team` avec `from`/`to` EXIGE aussi
        // `season`, sinon l'API renvoie une erreur (avalée par `try?`) → 0 amical.
        // On requête donc la saison courante SANS fenêtre de dates, puis on filtre
        // la fenêtre J+N nous-mêmes (les amicaux de présaison sont indexés 2026).
        for teamId in Set(favoriteTeamIds) {
            if let r: AFResponse<AFFixture> = try? await fetch(
                "/fixtures?team=\(teamId)&season=\(defaultSeason)&timezone=Europe/Paris"
            ) {
                all.append(contentsOf: r.response)
            }
        }

        // Ne garder que les matchs réellement à venir ET dans la fenêtre J+N
        // (les matchs favoris sont récupérés sur toute la saison — sans ce filtre
        // de date on afficherait tout le calendrier).
        //
        // ⚠️ On NE se base PLUS sur une liste blanche de statuts (NS/TBD/PST) :
        // les tours de COUPE non encore programmés remontent avec des codes variés
        // (ex. tour à tirage non fixé) et étaient jetés à tort — c'est pourquoi le
        // match de Servette en Coupe de Suisse n'apparaissait pas. On garde donc
        // TOUT match qui n'est ni en direct, ni terminé, ni annulé, et dont la date
        // tombe dans la fenêtre. Un match sans date exploitable est écarté (sinon on
        // ne peut pas le classer par jour dans la vue « À venir »).
        let windowEnd = Calendar.current.date(byAdding: .day, value: days, to: now)!
        let upcoming = all.filter { f in
            guard !f.isLive, !f.isFinished else { return false }
            if f.fixture.status.short == "CANC" || f.fixture.status.short == "ABD" {
                return false
            }
            guard let d = f.isoDate else { return false }
            return d >= now && d <= windowEnd
        }
        // Dédoublonnage par ID de match (une poule peut renvoyer un doublon).
        var seen = Set<Int>()
        let deduped = upcoming.filter { seen.insert($0.id).inserted }
        return deduped.sorted { $0.fixture.date < $1.fixture.date }
    }

    /// TOUS les matchs (passés, en direct, à venir) des compétitions passées en
    /// argument, sur une fenêtre symétrique de ±`days` jours autour d'aujourd'hui.
    /// Utilisé par l'onglet Live (barre de dates J-7 → J+7) : on récupère toute la
    /// fenêtre en une passe (une requête par poule de compétition), puis la vue
    /// filtre par jour sélectionné côté client. On ne filtre PAS par statut ici :
    /// terminés, en direct et à venir sont tous conservés, chacun affiché selon son
    /// état dans la vue. Chaque requête est en `try?` (échec isolé, non bloquant).
    /// - Parameter competitions: les compétitions suivies (issues du catalogue).
    /// - Parameter days: rayon de la fenêtre (par défaut 7 → 15 jours au total).
    func fetchWindowForCompetitions(_ competitions: [Competition],
                                    days: Int = 7) async throws -> [AFFixture] {
        await ensureFrenchTeamIds()
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "Europe/Paris")
        let now = Date()
        let cal = Calendar.current
        let from = fmt.string(from: cal.date(byAdding: .day, value: -days, to: now)!)
        let to   = fmt.string(from: cal.date(byAdding: .day, value:  days, to: now)!)

        var all: [AFFixture] = []
        for comp in competitions {
            let s = season(for: comp)
            for id in comp.allApiIds {
                if let r: AFResponse<AFFixture> = try? await fetch(
                    "/fixtures?league=\(id)&season=\(s)&from=\(from)&to=\(to)&timezone=Europe/Paris"
                ) {
                    all.append(contentsOf: r.response)
                }
            }
        }

        // Dédoublonnage par ID de match (une poule peut renvoyer un doublon).
        var seen = Set<Int>()
        let deduped = all.filter { seen.insert($0.id).inserted }
        return deduped.sorted { $0.fixture.date < $1.fixture.date }
    }

    /// Matchs d'UN SEUL JOUR pour le Live, via `/fixtures?date=YYYY-MM-DD`.
    ///
    /// ⚡️ ÉCONOMIE DE QUOTA MAJEURE. L'ancienne approche faisait UNE requête PAR
    /// compétition (≈50 → jusqu'à 64 requêtes à chaque ouverture). Ici, `date=`
    /// renvoie en UNE SEULE requête TOUS les matchs de la planète pour ce jour,
    /// toutes compétitions confondues. Le coût ne dépend donc PLUS du nombre de
    /// compétitions suivies : suivre 5 ou 50 compétitions coûte pareil (1 requête
    /// par jour affiché). On filtre ensuite CÔTÉ CLIENT :
    ///   • on garde les matchs des ligues du CATALOGUE branché (via `availableApiIds`) ;
    ///   • + tous les matchs des équipes FAVORITES (même hors catalogue : coupes,
    ///     amicaux…), repérés par l'ID d'équipe domicile/extérieur.
    /// Aucun paramètre `season` : la date est déjà sans ambiguïté côté API.
    /// Le regroupement/tri de la vue (par pays, rang catalogue…) reste inchangé.
    /// - Parameter day: le jour à charger (borné à sa journée civile Europe/Paris).
    /// - Parameter favoriteTeamIds: IDs des équipes favorites (jamais filtrées).
    /// - Parameter includeAllCatalog: si `false` (défaut « léger »), on ne garde que
    ///   les compétitions SUIVIES ; si `true`, tout le catalogue branché.
    /// - Parameter followedApiIds: IDs API des compétitions suivies (mode léger).
    func fetchDayForLive(day: Date,
                         favoriteTeamIds: [Int],
                         includeAllCatalog: Bool,
                         followedApiIds: Set<Int>) async throws -> [AFFixture] {
        try await fetchDayForLiveDetailed(
            day: day,
            favoriteTeamIds: favoriteTeamIds,
            includeAllCatalog: includeAllCatalog,
            followedApiIds: followedApiIds
        ).fixtures
    }

    /// Variante « détaillée » : renvoie en plus le nombre de matchs du jour présents
    /// dans TOUT le catalogue branché (indépendamment du filtre). Comme la requête
    /// `/fixtures?date=` ramène déjà TOUS les matchs du jour, ce compteur est GRATUIT
    /// (aucune requête supplémentaire). Il permet à l'UI de distinguer deux cas :
    ///   - `catalogTotal > 0` mais `fixtures` filtrées vides → « rien dans vos comp.
    ///     suivies, mais d'autres championnats jouent » (proposer « Tout afficher ») ;
    ///   - `catalogTotal == 0` → « pas de match à regarder aujourd'hui ».
    func fetchDayForLiveDetailed(day: Date,
                                 favoriteTeamIds: [Int],
                                 includeAllCatalog: Bool,
                                 followedApiIds: Set<Int>) async throws
        -> (fixtures: [AFFixture], catalogTotal: Int) {
        await ensureFrenchTeamIds()
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "Europe/Paris")
        let dateStr = fmt.string(from: day)

        // Ligues à conserver : tout le catalogue branché, ou seulement les suivies.
        let catalogLeagues = Set(Catalog.availableApiIds)
        let keepLeagues: Set<Int> = includeAllCatalog ? catalogLeagues : followedApiIds
        let favSet = Set(favoriteTeamIds)

        // UNE requête pour TOUS les matchs du jour (toutes compétitions).
        var kept: [AFFixture] = []
        var catalogTotal = 0
        if let r: AFResponse<AFFixture> = try? await fetch(
            "/fixtures?date=\(dateStr)&timezone=Europe/Paris"
        ) {
            // Compteur GRATUIT : combien de matchs du jour sont dans le catalogue
            // branché (toutes compétitions connues de l'app, filtre suivi ignoré).
            catalogTotal = r.response.filter { catalogLeagues.contains($0.league.id) }.count
            kept = r.response.filter { f in
                keepLeagues.contains(f.league.id)
                    || favSet.contains(f.teams.home.id)
                    || favSet.contains(f.teams.away.id)
            }
        }
        return (kept.sorted { $0.fixture.date < $1.fixture.date }, catalogTotal)
    }

    /// Fenêtre ±`days` jours pour l'écran Live REFONDU : on agrège
    ///   1. les matchs des compétitions SUIVIES (comme `fetchWindowForCompetitions`) ;
    ///   2. TOUS les matchs des équipes FAVORITES (quelle que soit la compétition —
    ///      donc coupes nationales, coupes d'Europe et AMICAUX inclus, même hors
    ///      catalogue), pour pouvoir afficher un groupe « Favoris » prioritaire.
    /// On garde passés / en direct / à venir (chacun affiché selon son état dans la
    /// vue). Chaque requête est en `try?` (échec isolé, non bloquant). Dédoublonné
    /// par ID de match, puis filtré à la fenêtre de dates (les matchs favoris sont
    /// récupérés sur toute la saison → on borne nous-mêmes à ±days).
    /// - Parameter competitions: compétitions suivies (catalogue).
    /// - Parameter favoriteTeamIds: IDs des équipes favorites.
    /// - Parameter days: rayon de la fenêtre (par défaut 7).
    func fetchWindowForLive(competitions: [Competition],
                            favoriteTeamIds: [Int],
                            days: Int = 7) async throws -> [AFFixture] {
        await ensureFrenchTeamIds()
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "Europe/Paris")
        let now = Date()
        let cal = Calendar.current
        let from = fmt.string(from: cal.date(byAdding: .day, value: -days, to: now)!)
        let to   = fmt.string(from: cal.date(byAdding: .day, value:  days, to: now)!)

        var all: [AFFixture] = []

        // 1. Compétitions suivies (fenêtre de dates côté serveur).
        for comp in competitions {
            let s = season(for: comp)
            for id in comp.allApiIds {
                if let r: AFResponse<AFFixture> = try? await fetch(
                    "/fixtures?league=\(id)&season=\(s)&from=\(from)&to=\(to)&timezone=Europe/Paris"
                ) {
                    all.append(contentsOf: r.response)
                }
            }
        }

        // 2. Équipes favorites — TOUTES compétitions (coupes + amicaux inclus).
        // ⚠️ PIÈGE API-Football : combiner `team` avec `from`/`to` EXIGE `season`,
        // sinon l'API renvoie une erreur (avalée par `try?`). On requête donc la
        // saison courante SANS fenêtre, puis on borne la fenêtre plus bas.
        for teamId in Set(favoriteTeamIds) {
            if let r: AFResponse<AFFixture> = try? await fetch(
                "/fixtures?team=\(teamId)&season=\(defaultSeason)&timezone=Europe/Paris"
            ) {
                all.append(contentsOf: r.response)
            }
        }

        // Bornage à la fenêtre ±days (indispensable pour les matchs favoris, tirés
        // sur toute la saison), puis dédoublonnage par ID de match.
        let windowStart = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: now))!
        let windowEnd   = cal.date(byAdding: .day, value: days + 1, to: cal.startOfDay(for: now))!
        var seen = Set<Int>()
        let filtered = all.filter { f in
            guard let d = f.isoDate, d >= windowStart, d < windowEnd else { return false }
            return seen.insert(f.id).inserted
        }
        return filtered.sorted { $0.fixture.date < $1.fixture.date }
    }

    /// Fenêtre Live « globale » : TOUS les matchs des compétitions branchées du
    /// catalogue (France, Europe, Monde, sélections) sur ±`days`, PLUS les matchs
    /// des équipes favorites (toutes compétitions : coupes/amicaux inclus). Sert
    /// à ne JAMAIS afficher un jour vide quand la journée a bien eu des matchs,
    /// même si l'utilisateur ne suit rien. Les favoris sont ensuite priorisés par
    /// le regroupement de la vue, pas ici.
    /// - Parameter followedIds: IDs de compétitions SUIVIES par l'utilisateur
    ///   (`Competition.id`). Elles sont chargées EN PREMIER, avant le reste du
    ///   catalogue. Utile quand le quota API est serré : les données qui comptent
    ///   le plus (compétitions suivies + favoris) arrivent avant qu'une éventuelle
    ///   coupure de quota ne fasse échouer les requêtes suivantes (avalées par `try?`).
    func fetchAllForLive(favoriteTeamIds: [Int], extraTeamIds: [Int] = [], days: Int = 7,
                         followedIds: Set<String> = []) async throws -> [AFFixture] {
        await ensureFrenchTeamIds()
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "Europe/Paris")
        let now = Date()
        let cal = Calendar.current
        let from = fmt.string(from: cal.date(byAdding: .day, value: -days, to: now)!)
        let to   = fmt.string(from: cal.date(byAdding: .day, value:  days, to: now)!)

        var all: [AFFixture] = []

        // 1. Toutes les compétitions branchées du catalogue (chaque poule incluse).
        //    ORDRE : compétitions SUIVIES d'abord (elles priment si le quota casse
        //    en cours de balayage), puis le reste du catalogue. Le cache disque +
        //    les TTL longs absorbent les rechargements ; ce tri protège le COLD START.
        let availableComps = Catalog.all.filter { $0.isAvailable }
        let orderedComps = availableComps.sorted { a, b in
            let af = followedIds.contains(a.id), bf = followedIds.contains(b.id)
            if af != bf { return af }          // suivies avant non-suivies
            return false                        // sinon on garde l'ordre du catalogue
        }
        for comp in orderedComps {
            let s = season(for: comp)
            for id in comp.allApiIds {
                if let r: AFResponse<AFFixture> = try? await fetch(
                    "/fixtures?league=\(id)&season=\(s)&from=\(from)&to=\(to)&timezone=Europe/Paris"
                ) {
                    all.append(contentsOf: r.response)
                }
            }
        }

        // 2. Équipes favorites + clubs des joueurs suivis — toutes compétitions
        // (piège API : team+from/to exige season, donc saison courante sans fenêtre,
        // bornage plus bas). Cela garantit que le prochain match du club d'un joueur
        // suivi (ex. Real Madrid pour Mbappé) est présent même si sa compétition
        // n'est pas dans le catalogue chargé au-dessus.
        // ⚠️ On mémorise ces IDs : leurs matchs NE doivent PAS être coupés par la
        // fenêtre ±`days`. Le prochain match d'un club favori peut tomber au-delà de
        // la fenêtre (ex. reprise de la Liga après la trêve internationale) ; il faut
        // le garder pour l'accueil (« prochains matchs de mes favoris »). Le Live, lui,
        // refiltre de toute façon par JOUR affiché, donc ces matchs lointains ne le
        // polluent pas.
        let teamScopedIds = Set(favoriteTeamIds).union(extraTeamIds)
        var teamFixtureIds = Set<Int>()
        for teamId in teamScopedIds {
            if let r: AFResponse<AFFixture> = try? await fetch(
                "/fixtures?team=\(teamId)&season=\(defaultSeason)&timezone=Europe/Paris"
            ) {
                for f in r.response { teamFixtureIds.insert(f.id) }
                all.append(contentsOf: r.response)
            }
        }

        let windowStart = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: now))!
        let windowEnd   = cal.date(byAdding: .day, value: days + 1, to: cal.startOfDay(for: now))!
        var seen = Set<Int>()
        let filtered = all.filter { f in
            guard let d = f.isoDate else { return false }
            // Match d'une équipe suivie/favorite : conservé quelle que soit la date
            // (tant qu'il est à venir ou récent — pas de vieilles archives). Sinon,
            // on borne à la fenêtre ±days comme avant.
            let inWindow = (d >= windowStart && d < windowEnd)
            let isTeamScoped = teamFixtureIds.contains(f.id)
            guard inWindow || isTeamScoped else { return false }
            return seen.insert(f.id).inserted
        }
        return filtered.sorted { $0.fixture.date < $1.fixture.date }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // ACCUEIL — fetch LÉGER des matchs des favoris (pas de balayage catalogue).
    // ─────────────────────────────────────────────────────────────────────────
    // `fetchAllForLive` balaie TOUT le catalogue (des dizaines de requêtes séries)
    // pour alimenter l'onglet Live (matchs du jour, toutes compétitions). L'ACCUEIL,
    // lui, n'affiche QUE le prochain match de chaque favori → il n'a besoin QUE des
    // requêtes `team=` (une par équipe suivie/favorite). On les lance EN PARALLÈLE
    // (TaskGroup) et on saute `ensureFrenchTeamIds()` (utile seulement au Live).
    // → temps de lancement de l'app divisé (plus de balayage catalogue au cold start).
    // Aucune fenêtre de dates : on garde tous les matchs à venir de l'équipe (l'appel
    // `/fixtures?team=&season=` renvoie déjà la saison courante) ; l'appelant filtre
    // « à venir » et ne garde que le plus proche.
    func fetchFavoritesFixtures(teamIds: [Int]) async throws -> [AFFixture] {
        let uniqueIds = Array(Set(teamIds))
        guard !uniqueIds.isEmpty else { return [] }
        let season = defaultSeason
        let groups = await withTaskGroup(of: [AFFixture].self) { group -> [AFFixture] in
            for teamId in uniqueIds {
                group.addTask { await self.teamFixtures(teamId: teamId, season: season) }
            }
            var out: [AFFixture] = []
            for await chunk in group { out.append(contentsOf: chunk) }
            return out
        }
        // Dédoublonnage par id de match (une même affiche peut sortir de 2 équipes).
        var seen = Set<Int>()
        let unique = groups.filter { seen.insert($0.id).inserted }
        return unique.sorted { $0.fixture.date < $1.fixture.date }
    }

    /// Prochains matchs d'une équipe (helper Sendable pour le TaskGroup).
    /// On utilise `next=N` plutôt que `season=` : l'API renvoie directement les N
    /// prochaines rencontres, TOUTES compétitions ET saisons confondues. Indispensable
    /// pour les SÉLECTIONS NATIONALES (France : les qualifs peuvent être indexées sous
    /// une autre saison que `defaultSeason`) et robuste en début de saison club.
    /// MÊME COÛT qu'avant : une seule requête `team=` par équipe (+ cache disque/TTL).
    /// `try?` → tableau vide en cas d'échec (une équipe qui échoue n'annule pas les autres).
    private func teamFixtures(teamId: Int, season: Int) async -> [AFFixture] {
        // Voie principale : `next=N` (toutes compétitions/saisons confondues).
        if let r: AFResponse<AFFixture> = try? await fetch(
            "/fixtures?team=\(teamId)&next=8&timezone=Europe/Paris"
        ), !r.response.isEmpty {
            return r.response
        }
        // REPLI SÉLECTIONS : en creux de calendrier (ex. été, entre deux fenêtres
        // FIFA), `next=` peut renvoyer 0 alors que des matchs À VENIR existent,
        // indexés sous une saison de compétition (Ligue des Nations, qualifs) que
        // `next=` ne remonte pas toujours. On balaie l'année courante ET la suivante
        // (les saisons de sélection sont en année civile) et on garde les matchs
        // futurs non joués. Coût : au plus 2 requêtes, uniquement quand `next=` est vide.
        let now = Date()
        var future: [AFFixture] = []
        for s in [season, season + 1] {
            if let r: AFResponse<AFFixture> = try? await fetch(
                "/fixtures?team=\(teamId)&season=\(s)&timezone=Europe/Paris"
            ) {
                future.append(contentsOf: r.response.filter { f in
                    guard !f.isCancelledOrPostponed, !f.isFinished, !f.isLive,
                          let d = f.isoDate else { return false }
                    return d > now
                })
            }
        }
        return future
    }
}
