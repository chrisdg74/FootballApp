import Foundation

// ─────────────────────────────────────────────────────────────────────────────
// NOMS OFFICIELS DES CLUBS (principalement français)
// -----------------------------------------------------------------------------
// API-Football renvoie souvent un nom COURT ou tronqué (« Annecy », « Paris SG »,
// « PAU »…) au lieu du nom officiel complet (« FC Annecy », « Paris Saint-Germain »).
// Cette table corrige UNIQUEMENT les clubs qu'on connaît, par le nom BRUT renvoyé
// par l'API (clé stable, pas d'ID à deviner). Pour tout club absent de la table,
// on garde le nom de l'API tel quel — JAMAIS de nom inventé.
//
// Correspondance INSENSIBLE à la casse et aux accents (voir `official(for:)`).
// Pour ajouter un club : ajouter une ligne `"<nom API>": "<nom officiel>"`.
// ─────────────────────────────────────────────────────────────────────────────
enum OfficialTeamNames {

    /// Table : nom BRUT de l'API (normalisé) → nom officiel complet.
    /// À enrichir au fil de l'eau ; ne mettre que des noms CERTAINS.
    private static let table: [String: String] = [
        "annecy": "FC Annecy",
        "paris sg": "Paris Saint-Germain",
        "paris saint germain": "Paris Saint-Germain",
        "marseille": "Olympique de Marseille",
        "lyon": "Olympique Lyonnais",
        "monaco": "AS Monaco",
        "lille": "LOSC Lille",
        "rennes": "Stade Rennais FC",
        "nice": "OGC Nice",
        "lens": "RC Lens",
        "nantes": "FC Nantes",
        "strasbourg": "RC Strasbourg Alsace",
        "montpellier": "Montpellier HSC",
        "brest": "Stade Brestois 29",
        "toulouse": "Toulouse FC",
        "reims": "Stade de Reims",
        "auxerre": "AJ Auxerre",
        "angers": "Angers SCO",
        "le havre": "Le Havre AC",
        "saint etienne": "AS Saint-Étienne",
        "metz": "FC Metz",
        "pau": "Pau FC",
        "red star": "Red Star FC",
        "guingamp": "EA Guingamp",
        "bastia": "SC Bastia",
        "grenoble": "Grenoble Foot 38",
        "amiens": "Amiens SC",
        "caen": "SM Caen",
        "laval": "Stade Lavallois",
        "rodez": "Rodez AF",
        "troyes": "ES Troyes AC",
        "clermont foot": "Clermont Foot 63",
        "dunkerque": "USL Dunkerque",
        "bordeaux": "FC Girondins de Bordeaux",
    ]

    /// Normalise pour la comparaison : minuscules, sans accents, espaces réduits.
    private static func normalized(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Renvoie le nom officiel si connu, sinon le nom passé tel quel (fallback sûr).
    static func official(for apiName: String) -> String {
        table[normalized(apiName)] ?? apiName
    }

    // ── Stade « maison » des SÉLECTIONS NATIONALES ────────────────────────────
    // API-Football rattache à tort à certaines sélections le stade d'un CLUB (ex.
    // l'équipe de France → « Groupama Stadium » de Lyon). Pour les sélections dont
    // on connaît le stade officiel avec CERTITUDE, on force le bon (demande user
    // 2026-08-16 : France = Stade de France, Saint-Denis). Clé = nom BRUT de la
    // sélection (normalisé). Absent de la table → on garde le stade de l'API.
    private static let nationalVenues: [String: (name: String, city: String)] = [
        "france": ("Stade de France", "Saint-Denis"),
    ]

    /// Stade officiel forcé d'une sélection nationale (nom + ville), si connu.
    /// À n'utiliser QUE pour les équipes `national == true`.
    static func nationalHomeVenue(for apiName: String) -> (name: String, city: String)? {
        nationalVenues[normalized(apiName)]
    }
}
