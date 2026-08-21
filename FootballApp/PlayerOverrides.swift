import Foundation

// ═════════════════════════════════════════════════════════════════════════════
// CORRECTIONS MANUELLES DE FICHES JOUEURS
// ─────────────────────────────────────────────────────────────────────────────
// API-Football contient quelques erreurs d'état civil ou de poste, notamment pour
// les internationaux français :
//   • Ousmane Dembélé est enregistré « Masour Dembélé » (mauvais prénom) ;
//   • plusieurs ATTAQUANTS (Dembélé, Barcola, Thuram, Doué) sont classés
//     « Midfielder » au lieu d'« Attacker ».
//
// On corrige ces cas de façon DÉTERMINISTE (jamais de devinette) via une petite
// table de surcharges, sur le même principe que `OfficialTeamNames`. La clé est
// « nom de famille normalisé + année de naissance » : suffisamment discriminante
// pour ces joueurs connus, sans dépendre d'un ID API-Football qu'on ne pourrait
// pas vérifier hors-ligne. Si aucune surcharge ne correspond, on garde la donnée
// de l'API telle quelle.
// ═════════════════════════════════════════════════════════════════════════════

enum PlayerOverrides {
    /// Une correction possible : nom d'affichage et/ou poste normalisé (anglais,
    /// tel qu'attendu par `FantasyPosition(apiValue:)` : "Attacker", "Midfielder"…).
    struct Override {
        var displayName: String?
        var position: String?
    }

    /// Table des corrections, clé = "nomdefamillenormalisé|annéedenaissance".
    private static let table: [String: Override] = [
        // Ousmane Dembélé (né le 15/05/1997) : prénom ET poste erronés dans l'API.
        "dembele|1997": Override(displayName: "Ousmane Dembélé", position: "Attacker"),
        // Harry Maguire (né le 05/03/1993) : prénom erroné (« Jacob ») dans l'API.
        "maguire|1993": Override(displayName: "Harry Maguire"),
        // Kylian Mbappé (né le 20/12/1998) : l'API renvoie l'état civil « Mbappé
        // Lottin » → on force le nom d'usage.
        "mbappe lottin|1998": Override(displayName: "Kylian Mbappé"),
        "mbappe|1998":        Override(displayName: "Kylian Mbappé"),
        // Attaquants mal classés « Midfielder » par l'API → poste corrigé seul.
        "barcola|2002": Override(position: "Attacker"),  // Bradley Barcola
        "thuram|1997":  Override(position: "Attacker"),  // Marcus Thuram
        "doue|2005":    Override(position: "Attacker"),  // Désiré Doué
    ]

    /// Clé de correspondance à partir du nom de famille et de la date de naissance
    /// ("AAAA-MM-JJ"). `nil` si l'un des deux manque → aucune surcharge possible.
    private static func key(lastname: String?, birthDate: String?) -> String? {
        guard let last = lastname, !last.isEmpty,
              let year = birthDate?.split(separator: "-").first, year.count == 4
        else { return nil }
        return "\(normalized(last))|\(year)"
    }

    /// Surcharge éventuelle pour un joueur (nom de famille + date de naissance).
    static func lookup(lastname: String?, birthDate: String?) -> Override? {
        guard let k = key(lastname: lastname, birthDate: birthDate) else { return nil }
        return table[k]
    }

    // ── Repli par NOM seul (effectif /players/squads) ───────────────────────────
    // L'endpoint effectif ne renvoie ni date de naissance ni nom de famille séparé
    // (juste « O. Dembélé »). On ne peut donc pas utiliser la clé nom+année. Pour
    // corriger le POSTE dans l'effectif on mappe le nom de famille (dernier mot,
    // normalisé) → poste, à partir des mêmes joueurs connus que la table ci-dessus.
    // Volontairement restreint à ces attaquants mal classés « Midfielder ».
    private static let positionByLastname: [String: String] = [
        "dembele": "Attacker",
        "barcola": "Attacker",
        "thuram":  "Attacker",
        "doue":    "Attacker",
    ]

    /// Poste corrigé pour un nom d'effectif (« O. Dembélé » → "Attacker"), sinon nil.
    /// On isole le dernier mot du nom, normalisé, et on le cherche dans la table.
    static func position(forDisplayName name: String) -> String? {
        let last = name
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .last
            .map(String.init)
        guard let last, !last.isEmpty else { return nil }
        return positionByLastname[normalized(last)]
    }

    // ── Correction du NOM COMPLET (recherche /players/profiles) ─────────────────
    // Depuis 2026-08-18, la recherche affiche le NOM COMPLET brut de l'API (plus
    // d'heuristique de troncature). Cette table ne sert donc PLUS à raccourcir un
    // nom, mais UNIQUEMENT à corriger les cas où l'API renvoie un PRÉNOM ERRONÉ —
    // sinon on ne retrouve pas le joueur en tapant son vrai prénom (ex. Dembélé
    // indexé « Masour Dembélé » au lieu d'« Ousmane Dembélé »). Clé = nom complet
    // brut normalisé, valeur = nom complet CORRECT. À n'utiliser que pour ces
    // erreurs de données ; les noms longs mais exacts (« Ethan Mbappé Lottin »)
    // s'affichent désormais tels quels.
    private static let displayNameByFullName: [String: String] = [
        "masour dembele": "Ousmane Dembélé",
    ]

    /// Nom d'affichage corrigé quand l'API renvoie un prénom faux (« Masour Dembélé »
    /// → « Ousmane Dembélé »), sinon nil (on garde alors le nom complet de l'API).
    static func displayName(forFullName name: String) -> String? {
        displayNameByFullName[normalized(name)]
    }

    // ── LISTE BLANCHE DE STARS pour la recherche (2026-08-19) ───────────────────
    // DÉCISION user : le tri « par club du catalogue » dépendait de dizaines d'appels
    // réseau (découvrir les clubs de chaque ligue + résoudre le club de chaque
    // homonyme) qui échouaient → Ousmane Dembélé (indexé « Masour Dembélé », mauvaise
    // photo) ne remontait jamais. On le remplace par une TABLE STATIQUE des joueurs
    // notoires : AUCUN appel réseau, remontée GARANTIE en tête de recherche.
    //
    // Une star est identifiée par son NOM DE FAMILLE normalisé (matche la recherche
    // API) + un ou plusieurs PRÉNOMS acceptés (dont le prénom FAUX de l'API, ex.
    // « masour » pour Dembélé). Le club et le rang de prestige (0 = plus prioritaire)
    // sont fournis en dur → on affiche le bon club sans requête.
    struct Star {
        let displayName: String   // nom d'affichage correct
        let club: String          // club actuel (affiché tel quel)
        let firstnames: [String]  // prénoms acceptés, normalisés (dont le faux de l'API)
        let rank: Int             // prestige : 0 = tout en tête
    }

    /// Table des stars, clé = nom de famille normalisé. Plusieurs stars peuvent
    /// partager un nom (rare) → on lève une liste et on désambiguïse par prénom.
    static let knownStars: [String: [Star]] = [
        "dembele": [
            Star(displayName: "Ousmane Dembélé", club: "Paris Saint Germain",
                 firstnames: ["ousmane", "masour"], rank: 0),
        ],
        "mbappe": [
            Star(displayName: "Kylian Mbappé", club: "Real Madrid",
                 firstnames: ["kylian"], rank: 0),
        ],
        "mbappe lottin": [
            Star(displayName: "Kylian Mbappé", club: "Real Madrid",
                 firstnames: ["kylian"], rank: 0),
        ],
    ]

    /// Renvoie la star correspondant à un candidat de recherche, sinon nil.
    /// On matche sur le NOM DE FAMILLE ; si des prénoms sont renseignés, l'un d'eux
    /// doit apparaître dans le prénom OU le nom complet brut de la fiche API.
    static func star(lastname: String?, firstname: String?, fullName: String?) -> Star? {
        let hay = [firstname, lastname, fullName]
            .compactMap { $0 != nil ? normalized($0!) : nil }
            .joined(separator: " ")
        guard !hay.isEmpty else { return nil }
        for (last, stars) in knownStars {
            guard hay.contains(last) else { continue }
            for s in stars {
                if s.firstnames.isEmpty { return s }
                if s.firstnames.contains(where: { hay.contains($0) }) { return s }
            }
        }
        return nil
    }

    /// Vrai si le candidat est une star connue (utilisé pour prioriser/filtrer).
    static func isKnownStar(fullName: String?, lastname: String?, firstname: String?) -> Bool {
        star(lastname: lastname, firstname: firstname, fullName: fullName) != nil
    }

    // ── Recherche par PRÉNOM d'une star mal indexée (2026-08-19) ─────────────────
    // L'endpoint /players/profiles?search= cherche par prénom/nom. Une star dont le
    // PRÉNOM est faux dans l'API (Ousmane Dembélé y est « Masour Dembélé ») est donc
    // introuvable en tapant son VRAI prénom (« Ousmane »). Pour permettre malgré tout
    // la recherche par prénom, on expose les NOMS DE FAMILLE à re-chercher quand la
    // saisie correspond au vrai prénom (ou nom) d'une star : on relance alors une
    // recherche par ce nom de famille pour ramener la fiche, puis la liste blanche la
    // remonte en tête. Dérivé automatiquement de `knownStars` (aucune double saisie).
    /// Noms de famille (indexés API) des stars dont un prénom/nom accepté COMMENCE par
    /// la saisie. Sert à relancer une recherche ciblée. Vide si rien ne correspond.
    static func lastnamesToProbe(forQuery query: String) -> [String] {
        let q = normalized(query)
        guard q.count >= 3 else { return [] }
        var out = Set<String>()
        for (lastname, stars) in knownStars {
            for s in stars {
                // La saisie amorce le nom de famille indexé, le nom d'affichage,
                // ou l'un des prénoms acceptés (dont le vrai prénom « ousmane »).
                let terms = [lastname, normalized(s.displayName)] + s.firstnames
                if terms.contains(where: { $0.hasPrefix(q) || q.hasPrefix($0) }) {
                    out.insert(lastname)
                }
            }
        }
        return Array(out)
    }

    private static func normalized(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
