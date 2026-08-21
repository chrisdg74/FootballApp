import Foundation

// ═════════════════════════════════════════════════════════════════════════════
// QUIZ — BANQUE DE QUESTIONS 100 % LOCALE (5 CHAMPIONNATS)
// ─────────────────────────────────────────────────────────────────────────────
// Mini-jeux hors-ligne : AUCUNE requête API (préserve le quota). 5 quiz — un par
// grand championnat (Ligue 1, Premier League, Liga, Bundesliga, Serie A). Chaque
// partie tire 10 questions AU HASARD dans le championnat choisi (voir QuizGame).
//
// LOCALISATION (décision user 2026-08-19 : « français d'abord ») : pendant la
// phase de rédaction/vérification, les ÉNONCÉS sont écrits EN CLAIR EN FRANÇAIS
// dans `question:` (pas de clé `L(...)`). On traduira en 8 langues une fois le
// contenu figé. Les RÉPONSES sont des NOMS PROPRES (clubs, stades, joueurs,
// villes) → identiques dans toutes les langues, jamais traduites.
//
// EXACTITUDE : on privilégie des faits STABLES et intemporels (stades, surnoms,
// palmarès historiques, légendes, villes, fondations) plutôt que l'actualité
// récente — le quiz reste juste et durable.
// ═════════════════════════════════════════════════════════════════════════════

/// Les 5 championnats couverts par les quiz. `rawValue` = clé stable (scores,
/// persistance). `nameKey` sera traduit ; en attendant on affiche `displayName`.
enum QuizLeague: String, CaseIterable, Identifiable {
    case ligue1        = "ligue1"
    case premierLeague = "premierLeague"
    case liga          = "liga"
    case bundesliga    = "bundesliga"
    case serieA        = "serieA"

    var id: String { rawValue }

    /// Clé de localisation du nom du championnat (UI).
    var nameKey: String { "quiz.league.\(rawValue)" }

    /// Nom lisible de repli (utilisé tant que la localisation n'est pas branchée).
    var displayName: String {
        switch self {
        case .ligue1:        return "Ligue 1"
        case .premierLeague: return "Premier League"
        case .liga:          return "Liga"
        case .bundesliga:    return "Bundesliga"
        case .serieA:        return "Serie A"
        }
    }

    /// Emoji drapeau du pays du championnat (visuel léger, sans asset).
    var flag: String {
        switch self {
        case .ligue1:        return "🇫🇷"
        case .premierLeague: return "🏴󠁧󠁢󠁥󠁮󠁧󠁿"
        case .liga:          return "🇪🇸"
        case .bundesliga:    return "🇩🇪"
        case .serieA:        return "🇮🇹"
        }
    }
}

/// Une question à choix multiples. `question` = énoncé (français en clair pour la
/// phase de rédaction). `options` affichées telles quelles (noms propres).
/// `correctIndex` = index (0-based) de la bonne réponse.
struct QuizQuestion: Identifiable {
    let id: Int
    let league: QuizLeague
    let question: String
    let options: [String]
    let correctIndex: Int

    /// Énoncé affiché. (Plus tard : bascule sur `L(...)` quand traduit.)
    var text: String { question }
    /// Réponse correcte (nom propre, non traduit).
    var correctAnswer: String { options[correctIndex] }
}

enum QuizData {
    /// Banque complète, tous championnats confondus.
    static var questions: [QuizQuestion] {
        ligue1 + premierLeague + liga + bundesliga + serieA
    }

    /// Questions d'un championnat donné.
    static func questions(for league: QuizLeague) -> [QuizQuestion] {
        switch league {
        case .ligue1:        return ligue1
        case .premierLeague: return premierLeague
        case .liga:          return liga
        case .bundesliga:    return bundesliga
        case .serieA:        return serieA
        }
    }

    /// Petit helper interne pour numéroter automatiquement et fixer le championnat.
    private static func build(_ league: QuizLeague,
                              _ items: [(String, [String], Int)]) -> [QuizQuestion] {
        items.enumerated().map { idx, it in
            QuizQuestion(id: league.hashValue &+ idx,
                         league: league,
                         question: it.0, options: it.1, correctIndex: it.2)
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// LIGUE 1 🇫🇷 — Vague 1 (faits stables : stades, palmarès, surnoms, villes, légendes)
// ═════════════════════════════════════════════════════════════════════════════
extension QuizData {
    static let ligue1: [QuizQuestion] = build(.ligue1, [
        ("Dans quel stade le Paris Saint-Germain joue-t-il ses matchs à domicile ?", ["Groupama Stadium", "Parc des Princes", "Stade de France", "Stade Vélodrome"], 1),
        ("Quel club est surnommé « Les Gones » ?", ["AS Saint-Étienne", "Olympique Lyonnais", "Olympique de Marseille", "OGC Nice"], 1),
        ("Quel est le stade de l'Olympique de Marseille ?", ["Stade de la Meinau", "Stade Bollaert", "Stade Geoffroy-Guichard", "Stade Vélodrome"], 3),
        ("Quel club français a remporté la Ligue des champions en 1993 ?", ["AS Saint-Étienne", "Olympique de Marseille", "AS Monaco", "Paris SG"], 1),
        ("Combien de titres de champion de France l'AS Saint-Étienne compte-t-elle (record) ?", ["10", "7", "8", "5"], 0),
        ("Quel club joue au Stade Geoffroy-Guichard ?", ["Olympique Lyonnais", "AS Saint-Étienne", "FC Nantes", "RC Lens"], 1),
        ("Quel club est surnommé « Les Sang et Or » ?", ["Stade Rennais", "RC Lens", "Montpellier HSC", "FC Lorient"], 1),
        ("Dans quel stade le LOSC Lille joue-t-il ses matchs à domicile ?", ["Stade Marcel-Picot", "Stade Pierre-Mauroy", "Stade Bollaert-Delelis", "Stade du Hainaut"], 1),
        ("Quel gardien de l'OM, champion du monde 1998 et d'Europe 2000, a marqué les années 1990-2000 ?", ["Grégory Coupet", "Bernard Lama", "Ulrich Ramé", "Fabien Barthez"], 3),
        ("Quel stade accueille les matchs de l'Olympique Lyonnais depuis 2016 ?", ["Parc OL historique", "Stade de Gerland rénové", "Stade Gerland", "Groupama Stadium"], 3),
        ("Quel club de Ligue 1 est surnommé « Les Canaris » ?", ["FC Sochaux", "AJ Auxerre", "FC Nantes", "Stade Brestois"], 2),
        ("Quel joueur a marqué 38 buts en une seule saison de Ligue 1 (record moderne, 2015-16) ?", ["Edinson Cavani", "Kylian Mbappé", "Alexandre Lacazette", "Zlatan Ibrahimović"], 3),
        ("Dans quel stade les Girondins de Bordeaux ont-ils longtemps évolué (inauguré pour l'Euro 2016) ?", ["Stade Chaban-Delmas", "Stade du Moustoir", "Stade de la Mosson", "Matmut Atlantique"], 3),
        ("Quel club est surnommé « Le Gym » ?", ["Toulouse FC", "AS Monaco", "OGC Nice", "Montpellier HSC"], 2),
        ("Quelle principauté abrite le club de l'AS Monaco ?", ["Saint-Marin", "Andorre", "Liechtenstein", "Monaco"], 3),
        ("Quel stade parisien situé porte de Saint-Cloud a une capacité d'environ 48 000 places ?", ["Stade Charléty", "Parc des Princes", "Stade de France", "Stade Jean-Bouin"], 1),
        ("Quel entraîneur belge a mené l'OM à la victoire en Ligue des champions 1993 ?", ["Raymond Goethals", "Guy Roux", "Arsène Wenger", "Gérard Houllier"], 0),
        ("Quel club est basé au Stade Bollaert-Delelis ?", ["AC Amiens", "LOSC Lille", "RC Lens", "Valenciennes"], 2),
        ("En quelle année le Paris SG a-t-il disputé sa première finale de Ligue des champions (perdue contre le Bayern) ?", ["2020", "2022", "2017", "2019"], 0),
        ("Quel meneur de jeu brésilien, capitaine du PSG dans les années 1990, a été élu meilleur joueur de l'histoire du club lors de ses 50 ans ?", ["Ricardo", "Raí", "David Ginola", "Valdo"], 1),
        ("Quel attaquant libérien a remporté le Ballon d'Or 1995 en jouant au PSG puis au Milan AC ?", ["Jean-Pierre Papin", "Youri Djorkaeff", "Sonny Anderson", "George Weah"], 3),
        ("Quel club a créé la surprise en remportant le titre de champion de France 2011-12 ?", ["Montpellier HSC", "Lille OSC", "Olympique de Marseille", "Paris SG"], 0),
        ("Quel club joue au Stade de la Beaujoire ?", ["FC Nantes", "SM Caen", "Stade Rennais", "FC Lorient"], 0),
        ("Quel joueur marseillais, Soulier d'Or européen, est surnommé « JPP » ?", ["Jean-Pierre Adams", "Jean-Paul Bertrand-Demanes", "Jean-Pierre François", "Jean-Pierre Papin"], 3),
        ("Quel club nordiste a remporté la Ligue 1 en 2020-21 devant le PSG ?", ["AS Monaco", "LOSC Lille", "RC Lens", "Paris SG"], 1),
        ("Dans quel stade évolue le RC Strasbourg ?", ["Stade de la Meinau", "Stade Saint-Symphorien", "Stade Auguste-Delaune", "Stade Bollaert"], 0),
        ("Dans quel stade évolue le Stade de Reims ?", ["Stade Marcel-Picot", "Stade Gabriel-Montpied", "Stade Auguste-Delaune", "Stade de l'Aube"], 2),
        ("Quel entraîneur emblématique a passé près de 44 ans à l'AJ Auxerre ?", ["Roger Lemerre", "Jean Tigana", "Guy Roux", "Aimé Jacquet"], 2),
        ("Dans quel stade évolue le Toulouse FC ?", ["Stadium de Toulouse", "Stade de la Mosson", "Allianz Riviera", "Stade des Costières"], 0),
        ("Quel club est surnommé « La Paillade » ?", ["OGC Nice", "Nîmes Olympique", "Montpellier HSC", "Toulouse FC"], 2),
        ("Quel stade de l'AS Monaco est réputé pour sa faible capacité et son parking sous les tribunes ?", ["Stade Louis-II", "Stade Vélodrome", "Stade de la Mosson", "Allianz Riviera"], 0),
        ("Quel attaquant français, buteur en finale de l'Euro 2000, a évolué à l'AS Monaco et à la Juventus ?", ["David Trezeguet", "Thierry Henry", "Zinédine Zidane", "Patrick Vieira"], 0),
        ("Quels clubs s'opposent dans le « derby rhônalpin » face à l'AS Saint-Étienne ?", ["AS Monaco", "Montpellier HSC", "Olympique Lyonnais", "OGC Nice"], 2),
        ("Quel joueur suédois a inscrit plus de 150 buts au PSG entre 2012 et 2016 ?", ["Freddie Ljungberg", "Zlatan Ibrahimović", "Henrik Larsson", "Ola Toivonen"], 1),
        ("Quel club niçois joue à l'Allianz Riviera ?", ["AS Monaco", "Toulouse FC", "OGC Nice", "Montpellier HSC"], 2),
        ("Quel club a remporté 7 titres de champion de France consécutifs entre 2002 et 2008 ?", ["Olympique de Marseille", "AS Monaco", "Olympique Lyonnais", "Paris SG"], 2),
        ("Quel stade stéphanois est surnommé « le Chaudron » ?", ["Stade Geoffroy-Guichard", "Stade Vélodrome", "Parc des Princes", "Groupama Stadium"], 0),
        ("Quel milieu, capitaine des Bleus champions du monde 1998, a soulevé la Ligue des champions avec l'OM en 1993 ?", ["Emmanuel Petit", "Christian Karembeu", "Zinédine Zidane", "Didier Deschamps"], 3),
        ("Quel club a remporté la Coupe de France un nombre record de fois (plus de 14 fois) ?", ["Olympique de Marseille", "AS Saint-Étienne", "Paris SG", "Olympique Lyonnais"], 2),
        ("Quel entraîneur italien a offert à l'OGC Nice de bons parcours avant d'entraîner l'Angleterre ? (indice : sélectionneur des Three Lions)", ["Fabio Capello", "Lucien Favre", "Patrick Vieira", "Claudio Ranieri"], 3),
    ])
}

// ═════════════════════════════════════════════════════════════════════════════
// PREMIER LEAGUE 🏴 — Vague 1
// ═════════════════════════════════════════════════════════════════════════════
extension QuizData {
    static let premierLeague: [QuizQuestion] = build(.premierLeague, [
        ("Dans quel stade Manchester United joue-t-il ses matchs à domicile ?", ["Old Trafford", "Anfield", "Emirates Stadium", "Etihad Stadium"], 0),
        ("Quel est le stade de Liverpool FC ?", ["Anfield", "Old Trafford", "Stamford Bridge", "Goodison Park"], 0),
        ("Quel club londonien joue à Stamford Bridge ?", ["Chelsea", "West Ham", "Arsenal", "Tottenham"], 0),
        ("Quel club est surnommé « The Gunners » ?", ["Aston Villa", "Arsenal", "Chelsea", "Everton"], 1),
        ("Quel club de Manchester joue à l'Etihad Stadium ?", ["Wigan", "Manchester City", "Manchester United", "Bolton"], 1),
        ("Quel club est surnommé « The Reds » et joue à Anfield ?", ["Liverpool", "Arsenal", "Nottingham Forest", "Manchester United"], 0),
        ("Quel entraîneur écossais a dirigé Manchester United de 1986 à 2013 ?", ["José Mourinho", "Alex Ferguson", "Kenny Dalglish", "Arsène Wenger"], 1),
        ("Quel club a réalisé une saison de championnat invincible en 2003-04 (« The Invincibles ») ?", ["Chelsea", "Manchester United", "Liverpool", "Arsenal"], 3),
        ("Quel joueur français a longtemps détenu le record de buts d'Arsenal, dépassé récemment... par lui-même ? (meilleur buteur de l'histoire du club)", ["Olivier Giroud", "Thierry Henry", "Nicolas Anelka", "Robert Pirès"], 1),
        ("Quel manager français a dirigé Arsenal de 1996 à 2018 ?", ["Claude Puel", "Rémi Garde", "Gérard Houllier", "Arsène Wenger"], 3),
        ("Quel club londonien joue à l'Emirates Stadium ?", ["Arsenal", "Fulham", "Chelsea", "Tottenham"], 0),
        ("Quel club de Liverpool joue à Goodison Park ?", ["Everton", "Liverpool", "Tranmere", "Bolton"], 0),
        ("Quel club a remporté la Premier League 2015-16 de manière surprise, dirigé par Claudio Ranieri ?", ["Arsenal", "Manchester United", "Leicester City", "Tottenham"], 2),
        ("Quel joueur gallois a passé toute sa carrière de club à Manchester United comme milieu ?", ["Craig Bellamy", "Aaron Ramsey", "Gareth Bale", "Ryan Giggs"], 3),
        ("Quel club est surnommé « The Blues » à Londres ?", ["Chelsea", "Crystal Palace", "Arsenal", "Tottenham"], 0),
        ("Quel attaquant anglais détient le record de buts en Premier League (plus de 260) ?", ["Wayne Rooney", "Harry Kane", "Andy Cole", "Alan Shearer"], 3),
        ("Quel club de Newcastle joue à St James' Park ?", ["Sunderland", "Middlesbrough", "Leeds United", "Newcastle United"], 3),
        ("Quel club de Londres est surnommé « The Hammers » ?", ["Chelsea", "Fulham", "Arsenal", "West Ham United"], 3),
        ("Quel gardien danois a gardé les buts de Manchester United dans les années 1990 ?", ["David Seaman", "Peter Schmeichel", "Fabien Barthez", "Edwin van der Sar"], 1),
        ("Quel club joue au Tottenham Hotspur Stadium, à Londres ?", ["Tottenham Hotspur", "West Ham", "Fulham", "Brentford"], 0),
        ("Quel manager portugais a remporté la Premier League avec Chelsea en 2004-05 et 2005-06 ?", ["Rafael Benítez", "José Mourinho", "André Villas-Boas", "Carlo Ancelotti"], 1),
        ("Quel club a remporté la première édition de la Premier League en 1992-93 ?", ["Blackburn Rovers", "Liverpool", "Arsenal", "Manchester United"], 3),
        ("Quel club a remporté trois titres de Premier League consécutifs (1998-99, 1999-2000, 2000-01) ?", ["Chelsea", "Manchester United", "Liverpool", "Arsenal"], 1),
        ("Quel milieu français a remporté la PL avec Arsenal (dont « The Invincibles ») en tant que capitaine des Gunners ?", ["Marcel Desailly", "Patrick Vieira", "Claude Makélélé", "Emmanuel Petit"], 1),
        ("Quel club joue à Villa Park, à Birmingham ?", ["Wolverhampton", "Aston Villa", "Birmingham City", "West Bromwich Albion"], 1),
        ("Quel joueur portugais a fait ses débuts européens à Manchester United avant de rejoindre le Real Madrid ?", ["Cristiano Ronaldo", "Nani", "Bebé", "Luís Figo"], 0),
        ("Quel club de Londres est surnommé « The Cottagers » ?", ["Chelsea", "Arsenal", "Fulham", "Millwall"], 2),
        ("Quel entraîneur allemand a mené Liverpool au titre de Premier League 2019-20 ?", ["Ralf Rangnick", "Pep Guardiola", "Jürgen Klopp", "Thomas Tuchel"], 2),
        ("Quel manager espagnol dirige Manchester City et a gagné plusieurs titres de PL ?", ["Mikel Arteta", "Roberto Martínez", "Pep Guardiola", "Unai Emery"], 2),
        ("Quel club a remporté la Premier League 1994-95 avec Alan Shearer et Chris Sutton (« SAS ») ?", ["Liverpool", "Manchester United", "Blackburn Rovers", "Arsenal"], 2),
        ("Quel joueur égyptien est une star de Liverpool et grand buteur de la Premier League ?", ["Sadio Mané", "Riyad Mahrez", "Mohamed Salah", "Yaya Touré"], 2),
        ("Quel derby oppose Liverpool à Everton ?", ["Le North London derby", "Le derby des Midlands", "Le derby du Merseyside", "Le derby de Manchester"], 2),
        ("Quel derby oppose Arsenal à Tottenham ?", ["Le North London derby", "Le derby du Merseyside", "Le derby de Manchester", "Le derby de Londres-Est"], 0),
        ("Quel club joue à Selhurst Park, dans le sud de Londres ?", ["Brighton", "Millwall", "Crystal Palace", "Charlton"], 2),
        ("Quel milieu défensif français a joué à Chelsea et au Real Madrid, donnant son nom à un rôle (« le poste de... ») ?", ["Patrick Vieira", "Didier Deschamps", "Claude Makélélé", "N'Golo Kanté"], 2),
        ("Quel attaquant anglais, capitaine de Tottenham et de l'Angleterre, est un grand buteur des années 2010-2020 ?", ["Jamie Vardy", "Raheem Sterling", "Dele Alli", "Harry Kane"], 3),
        ("Quel club a remporté la Premier League en 2011-12 grâce à un but d'Agüero à la 94e minute ?", ["Chelsea", "Arsenal", "Manchester City", "Manchester United"], 2),
        ("Quel milieu défensif français a remporté la PL avec Leicester (2016) puis Chelsea (2017) ?", ["Paul Pogba", "N'Golo Kanté", "Blaise Matuidi", "Moussa Sissoko"], 1),
        ("Quel club joue au London Stadium (ancien stade olympique) depuis 2016 ?", ["Chelsea", "Arsenal", "Tottenham", "West Ham United"], 3),
        ("Quel manager norvégien, ancien joueur du club, a entraîné Manchester United de 2018 à 2021 ?", ["Erik ten Hag", "David Moyes", "Louis van Gaal", "Ole Gunnar Solskjær"], 3),
    ])
}

// ═════════════════════════════════════════════════════════════════════════════
// LIGA 🇪🇸 — Vague 1
// ═════════════════════════════════════════════════════════════════════════════
extension QuizData {
    static let liga: [QuizQuestion] = build(.liga, [
        ("Dans quel stade le FC Barcelone joue-t-il historiquement ses matchs à domicile ?", ["Mestalla", "Camp Nou", "Santiago Bernabéu", "Metropolitano"], 1),
        ("Quel est le stade du Real Madrid ?", ["Metropolitano", "Ramón Sánchez-Pizjuán", "Camp Nou", "Santiago Bernabéu"], 3),
        ("Comment s'appelle le « clásico » de la Liga ?", ["Atlético – Real", "Séville – Betis", "Real Madrid – FC Barcelone", "Valence – Villarreal"], 2),
        ("Quel club madrilène joue au stade Metropolitano ?", ["Atlético de Madrid", "Real Madrid", "Rayo Vallecano", "Getafe"], 0),
        ("Quel joueur argentin est le meilleur buteur de l'histoire du FC Barcelone ?", ["Lionel Messi", "Diego Maradona", "Luis Suárez", "Samuel Eto'o"], 0),
        ("Quel club est surnommé « Los Blancos » ?", ["Valence CF", "FC Barcelone", "Real Madrid", "Atlético de Madrid"], 2),
        ("Quel club catalan est surnommé « Blaugrana » ?", ["FC Barcelone", "Villarreal", "Espanyol Barcelone", "Girona"], 0),
        ("Quel joueur portugais détient le record de buts du Real Madrid ?", ["Cristiano Ronaldo", "Luís Figo", "Pepe", "Ricardo Carvalho"], 0),
        ("Quel club de Séville joue au stade Ramón Sánchez-Pizjuán ?", ["Cadix", "Grenade", "Séville FC", "Real Betis"], 2),
        ("Combien de fois le Real Madrid a-t-il gagné la Coupe d'Europe / Ligue des champions (record) ?", ["Plus de 14", "9", "3", "6"], 0),
        ("Quel entraîneur a incarné le « tiki-taka » du Barça de 2008 à 2012 ?", ["Luis Enrique", "Frank Rijkaard", "Pep Guardiola", "Ernesto Valverde"], 2),
        ("Quel club de Valence joue au stade de Mestalla ?", ["Elche", "Valence CF", "Levante", "Villarreal"], 1),
        ("Quel attaquant français, Ballon d'Or 2022, est le meilleur buteur français de l'histoire du Real Madrid ?", ["Raphaël Varane", "Ferland Mendy", "Karim Benzema", "Zinédine Zidane"], 2),
        ("Quel club basque joue au stade San Mamés à Bilbao ?", ["Athletic Bilbao", "Alavés", "Osasuna", "Real Sociedad"], 0),
        ("Quel club est surnommé « Los Colchoneros » ?", ["Atlético de Madrid", "Rayo Vallecano", "Real Madrid", "Getafe"], 0),
        ("Quel numéro 10 argentin a joué au FC Barcelone dans les années 1980 avant Naples ?", ["Lionel Messi", "Juan Román Riquelme", "Gabriel Batistuta", "Diego Maradona"], 3),
        ("Quel gardien espagnol a été capitaine du Real et de l'Espagne championne du monde 2010 ?", ["David de Gea", "Iker Casillas", "Víctor Valdés", "Pepe Reina"], 1),
        ("Quel entraîneur français a dirigé le Real Madrid vers plusieurs Ligues des champions dans les années 2010-2020 ?", ["Julen Lopetegui", "Santiago Solari", "Rafael Benítez", "Zinédine Zidane"], 3),
        ("Quel club de Saint-Sébastien joue au stade Anoeta / Reale Arena ?", ["Alavés", "Athletic Bilbao", "Eibar", "Real Sociedad"], 3),
        ("Quel Néerlandais a joué puis entraîné le FC Barcelone (la « Dream Team » championne d'Europe 1992) ?", ["Frank Rijkaard", "Ronald Koeman", "Louis van Gaal", "Johan Cruyff"], 3),
        ("Quel attaquant brésilien surnommé « R9 » a joué au FC Barcelone puis au Real Madrid ?", ["Rivaldo", "Neymar", "Ronaldo", "Ronaldinho"], 2),
        ("Quel milieu espagnol formé à La Masia a formé le duo emblématique avec Iniesta au Barça ?", ["David Silva", "Sergio Busquets", "Xavi", "Cesc Fàbregas"], 2),
        ("Quel club de la région de Castellón joue au stade de la Cerámica ?", ["Elche", "Valence", "Levante", "Villarreal"], 3),
        ("Quel club de Séville, rival du Séville FC, joue au stade Benito Villamarín ?", ["Séville FC", "Cadix", "Málaga", "Real Betis"], 3),
        ("Quel Brésilien surnommé « Ronnie » a remporté le Ballon d'Or en jouant au FC Barcelone (2005) ?", ["Kaká", "Ronaldinho", "Ronaldo", "Rivaldo"], 1),
        ("Avec le Real Madrid, quel club catalan compte le plus de titres de champion d'Espagne ?", ["Villarreal", "Espanyol", "FC Barcelone", "Girona"], 2),
        ("Quel entraîneur argentin surnommé « El Cholo » dirige l'Atlético de Madrid depuis 2011 ?", ["Diego Simeone", "Jorge Sampaoli", "Marcelo Bielsa", "Mauricio Pochettino"], 0),
        ("Quel milieu croate, Ballon d'Or 2018, est une légende du Real Madrid ?", ["Luka Modrić", "Ivan Rakitić", "Mateo Kovačić", "Marcelo Brozović"], 0),
        ("Quel club madrilène a été sacré champion de la Liga en 2020-21 ?", ["Séville FC", "Atlético de Madrid", "Real Madrid", "FC Barcelone"], 1),
        ("Quel Uruguayen a formé le trio d'attaque « MSN » au Barça avec Messi et Neymar ?", ["Darwin Núñez", "Edinson Cavani", "Luis Suárez", "Diego Forlán"], 2),
        ("Quel milieu espagnol du Barça, artisan du tiki-taka, a été le partenaire de passes de Xavi ?", ["Sergi Roberto", "Andrés Iniesta", "Thiago Alcántara", "Sergio Busquets"], 1),
        ("Quel club madrilène est surnommé « Los Merengues » ?", ["Atlético de Madrid", "Getafe", "Leganés", "Real Madrid"], 3),
        ("Quel attaquant français a rejoint le FC Barcelone en 2017 depuis le Borussia Dortmund ?", ["Kingsley Coman", "Ousmane Dembélé", "Antoine Griezmann", "Kylian Mbappé"], 1),
        ("Quel attaquant français, champion du monde 2018, a joué à l'Atlético puis au Barça ?", ["Olivier Giroud", "Antoine Griezmann", "Karim Benzema", "Nabil Fekir"], 1),
        ("Quel club galicien joue au stade de Riazor à La Corogne ?", ["Real Oviedo", "Deportivo La Corogne", "Sporting Gijón", "Celta Vigo"], 1),
        ("Quel club de Galice joue au stade de Balaídos à Vigo ?", ["Deportivo La Corogne", "Racing Santander", "Real Oviedo", "Celta Vigo"], 3),
        ("Quel Néerlandais, vainqueur de la C1 1992 avec le Barça, est devenu sélectionneur des Pays-Bas ?", ["Frank de Boer", "Marc Overmars", "Patrick Kluivert", "Ronald Koeman"], 3),
        ("Quel club a remporté la Liga 2013-14 en devançant Real et Barça, dirigé par Simeone ?", ["Real Madrid", "Atlético de Madrid", "FC Barcelone", "Athletic Bilbao"], 1),
        ("Quel attaquant français, révélé à l'Olympique Lyonnais, est devenu une légende du Real Madrid (Ballon d'Or 2022) ?", ["Ferland Mendy", "Eduardo Camavinga", "Karim Benzema", "Aurélien Tchouaméni"], 2),
        ("Quel entraîneur italien a remporté la Liga et la Ligue des champions avec le Real Madrid dans les années 2020 ?", ["Carlo Ancelotti", "Massimiliano Allegri", "Antonio Conte", "Fabio Capello"], 0),
    ])
}

// ═════════════════════════════════════════════════════════════════════════════
// BUNDESLIGA 🇩🇪 — Vague 1
// ═════════════════════════════════════════════════════════════════════════════
extension QuizData {
    static let bundesliga: [QuizQuestion] = build(.bundesliga, [
        ("Dans quel stade le Bayern Munich joue-t-il ses matchs à domicile ?", ["Olympiastadion", "Veltins-Arena", "Allianz Arena", "Signal Iduna Park"], 2),
        ("Quel est le stade du Borussia Dortmund, célèbre pour son « Mur Jaune » ?", ["Allianz Arena", "Signal Iduna Park", "Rhein-Energie-Stadion", "Volksparkstadion"], 1),
        ("Quel club allemand détient de loin le plus de titres de Bundesliga ?", ["Borussia Dortmund", "Borussia Mönchengladbach", "Bayern Munich", "Hambourg SV"], 2),
        ("Quel est le surnom de la tribune sud du Borussia Dortmund ?", ["Les Rouges", "La Bombonera", "Le Mur Jaune", "Le Chaudron"], 2),
        ("Quel club de la Ruhr joue à la Veltins-Arena à Gelsenkirchen ?", ["Bayer Leverkusen", "Bochum", "Schalke 04", "Borussia Dortmund"], 2),
        ("Quel gardien a été capitaine du Bayern et de l'Allemagne championne du monde 2014 ?", ["Sepp Maier", "Oliver Kahn", "Manuel Neuer", "Jens Lehmann"], 2),
        ("Quel attaquant polonais a battu le record de buts sur une saison de Bundesliga au Bayern ?", ["Lukas Podolski", "Robert Lewandowski", "Mario Gómez", "Miroslav Klose"], 1),
        ("Quel club de Leverkusen est lié à l'entreprise pharmaceutique Bayer ?", ["VfL Wolfsburg", "TSG Hoffenheim", "RB Leipzig", "Bayer Leverkusen"], 3),
        ("Quel club a remporté la Bundesliga 2023-24 en restant invaincu, entraîné par Xabi Alonso ?", ["Bayer Leverkusen", "Bayern Munich", "Borussia Dortmund", "VfB Stuttgart"], 0),
        ("Quel « Kaiser », légende du Bayern, a été champion du monde comme joueur (1974) et sélectionneur (1990) ?", ["Karl-Heinz Rummenigge", "Gerd Müller", "Franz Beckenbauer", "Uli Hoeneß"], 2),
        ("Quel buteur légendaire du Bayern des années 1970 est surnommé « Der Bomber » ?", ["Rudi Völler", "Karl-Heinz Rummenigge", "Jürgen Klinsmann", "Gerd Müller"], 3),
        ("Quel entraîneur allemand a marqué Dortmund puis Liverpool avec son « gegenpressing » ?", ["Julian Nagelsmann", "Hansi Flick", "Jürgen Klopp", "Thomas Tuchel"], 2),
        ("Quel club de Hambourg a été relégué de Bundesliga en 2018 après 55 saisons consécutives ?", ["Werder Brême", "Hanovre 96", "FC Sankt Pauli", "Hambourg SV"], 3),
        ("Quel club de Rhénanie joue au stade Rhein-Energie à Cologne ?", ["Borussia Mönchengladbach", "FC Cologne", "Fortuna Düsseldorf", "Bayer Leverkusen"], 1),
        ("Quel club a remporté la Ligue des champions 2012-13 en battant Dortmund à Wembley ?", ["Real Madrid", "Borussia Dortmund", "Chelsea", "Bayern Munich"], 3),
        ("Quel jeune ailier anglais a explosé au Borussia Dortmund avant de rejoindre Manchester United ?", ["Jadon Sancho", "Jude Bellingham", "Marcus Rashford", "Phil Foden"], 0),
        ("Quel club de Basse-Saxe est lié au groupe automobile Volkswagen ?", ["Eintracht Brunswick", "VfL Wolfsburg", "Hanovre 96", "Werder Brême"], 1),
        ("Quel club a remporté son unique titre de Bundesliga en 2008-09, entraîné par Felix Magath ?", ["VfL Wolfsburg", "Werder Brême", "Bayer Leverkusen", "Bayern Munich"], 0),
        ("Quel club de Francfort joue au Deutsche Bank Park (Waldstadion) ?", ["Eintracht Francfort", "Darmstadt 98", "FSV Mayence 05", "SC Fribourg"], 0),
        ("Quel milieu allemand du Bayern, champion du monde 2014, était surnommé « Schweini » ?", ["Toni Kroos", "Bastian Schweinsteiger", "Michael Ballack", "Mesut Özil"], 1),
        ("Quel club, adossé à une marque de boisson énergisante, est monté rapidement en Bundesliga depuis Leipzig ?", ["Union Berlin", "RB Leipzig", "TSG Hoffenheim", "FC Augsbourg"], 1),
        ("Quel milieu allemand est passé du Bayer Leverkusen au Real Madrid, multiple vainqueur de C1 ?", ["Mesut Özil", "İlkay Gündoğan", "Sami Khedira", "Toni Kroos"], 3),
        ("Quel club du sud-ouest joue à la Mercedes-Benz Arena (MHPArena) de Stuttgart ?", ["TSG Hoffenheim", "VfB Stuttgart", "FC Augsbourg", "SC Fribourg"], 1),
        ("Quel entraîneur allemand a mené le Bayern au triplé (dont la C1) en 2019-20 ?", ["Julian Nagelsmann", "Niko Kovač", "Thomas Tuchel", "Hansi Flick"], 3),
        ("Quel club de Brême, historique de Bundesliga, joue au Weserstadion ?", ["Hambourg SV", "Hanovre 96", "VfL Wolfsburg", "Werder Brême"], 3),
        ("Quel milieu allemand créatif, formé à Schalke, a joué au Real Madrid puis à Arsenal ?", ["Toni Kroos", "Mesut Özil", "Julian Draxler", "Leon Goretzka"], 1),
        ("Quel club domine le palmarès du doublé Coupe-Championnat allemand ?", ["Schalke 04", "Bayern Munich", "VfB Stuttgart", "Borussia Dortmund"], 1),
        ("Quel ailier français formé au PSG a remporté la C1 avec le Bayern (2020), buteur en finale ?", ["Kingsley Coman", "Ousmane Dembélé", "Anthony Martial", "Nabil Fekir"], 0),
        ("Quel club de Mönchengladbach a remporté 5 titres dans les années 1970, grand rival du Bayern ?", ["Borussia Mönchengladbach", "Hambourg SV", "FC Cologne", "Schalke 04"], 0),
        ("Quel attaquant allemand du Bayern, champion du monde 2014, était surnommé « Poldi » ?", ["André Schürrle", "Thomas Müller", "Lukas Podolski", "Mario Götze"], 2),
        ("Quel joueur allemand a marqué le but vainqueur de la finale du Mondial 2014 ?", ["Thomas Müller", "Miroslav Klose", "Mario Götze", "Bastian Schweinsteiger"], 2),
        ("Quel attaquant polyvalent du Bayern est surnommé « Raumdeuter » (interprète de l'espace) ?", ["Serge Gnabry", "Leroy Sané", "Thomas Müller", "Robert Lewandowski"], 2),
        ("Quel club berlinois de Köpenick s'est fait une place en Bundesliga par son esprit populaire ?", ["FC Cologne", "Union Berlin", "Hertha Berlin", "RB Leipzig"], 1),
        ("Quel stade olympique accueille chaque année la finale de la Coupe d'Allemagne (DFB-Pokal) ?", ["Olympiastadion de Berlin", "Signal Iduna Park", "Volksparkstadion", "Allianz Arena"], 0),
        ("Quel milieu allemand, capitaine de Manchester City, est passé par le Borussia Dortmund ?", ["Joshua Kimmich", "Toni Kroos", "Leon Goretzka", "İlkay Gündoğan"], 3),
        ("Quel entraîneur allemand est devenu le plus jeune à diriger le Bayern (2021) ?", ["Julian Nagelsmann", "Domenico Tedesco", "Marco Rose", "Edin Terzić"], 0),
        ("Quel club de Fribourg, réputé pour sa formation, joue à l'Europa-Park Stadion ?", ["FC Augsbourg", "TSG Hoffenheim", "Mayence 05", "SC Fribourg"], 3),
        ("Quel milieu polyvalent du Bayern, formé à Stuttgart, est un pilier de la Mannschaft ?", ["Joshua Kimmich", "Niklas Süle", "Matthias Ginter", "Antonio Rüdiger"], 0),
        ("Quel club a remporté onze titres consécutifs de Bundesliga entre 2013 et 2023 ?", ["Bayern Munich", "RB Leipzig", "Borussia Dortmund", "Bayer Leverkusen"], 0),
        ("Quel attaquant allemand, meilleur buteur de l'histoire des Coupes du monde, a joué au Werder puis au Bayern ?", ["Gerd Müller", "Jürgen Klinsmann", "Rudi Völler", "Miroslav Klose"], 3),
    ])
}

// ═════════════════════════════════════════════════════════════════════════════
// SERIE A 🇮🇹 — Vague 1
// ═════════════════════════════════════════════════════════════════════════════
extension QuizData {
    static let serieA: [QuizQuestion] = build(.serieA, [
        ("Dans quel stade l'AC Milan et l'Inter Milan jouent-ils ?", ["Stade olympique", "Allianz Stadium", "Diego-Maradona", "San Siro"], 3),
        ("Quel club turinois joue à l'Allianz Stadium ?", ["Juventus", "AC Milan", "AS Rome", "Torino"], 0),
        ("Quel club détient le record de titres de champion d'Italie (scudetti) ?", ["AS Rome", "AC Milan", "Inter Milan", "Juventus"], 3),
        ("Comment appelle-t-on le derby entre l'AC Milan et l'Inter ?", ["Derby della Mole", "Derby della Madonnina", "Derby d'Italia", "Derby della Capitale"], 1),
        ("Comment appelle-t-on le derby entre la Juventus et l'Inter ?", ["Derby della Capitale", "Derby della Lanterna", "Derby d'Italia", "Derby della Madonnina"], 2),
        ("Quel club romain joue au Stade olympique et est surnommé « i Giallorossi » ?", ["Fiorentina", "Lazio Rome", "AS Rome", "Naples"], 2),
        ("Quel attaquant suédois a joué à la Juventus, l'Inter ET l'AC Milan ?", ["Hernán Crespo", "Zlatan Ibrahimović", "Christian Vieri", "Andriy Shevchenko"], 1),
        ("Quel club napolitain a été porté par Diego Maradona dans les années 1980 ?", ["Naples", "AS Rome", "Fiorentina", "Sampdoria"], 0),
        ("Quel gardien-capitaine surnommé « Gigi » a passé l'essentiel de sa carrière à la Juventus ?", ["Walter Zenga", "Gianluca Pagliuca", "Gianluigi Buffon", "Dino Zoff"], 2),
        ("Quel club est surnommé « la Vieille Dame » (la Vecchia Signora) ?", ["Juventus", "Inter Milan", "Genoa", "AC Milan"], 0),
        ("Quel numéro 10 italien est surnommé « Il Divin Codino » (la divine petite queue de cheval) ?", ["Christian Vieri", "Roberto Baggio", "Filippo Inzaghi", "Alessandro Del Piero"], 1),
        ("Quel club a réalisé le triplé (Serie A, Coupe, Ligue des champions) en 2009-10 sous Mourinho ?", ["Juventus", "AS Rome", "Inter Milan", "AC Milan"], 2),
        ("Quel numéro 10 de l'AS Rome, « il Capitano », a passé toute sa carrière au club ?", ["Daniele De Rossi", "Alessandro Nesta", "Gabriel Batistuta", "Francesco Totti"], 3),
        ("Quel milieu français, « Zizou », a évolué à la Juventus avant le Real Madrid ?", ["Patrick Vieira", "Michel Platini", "Didier Deschamps", "Zinédine Zidane"], 3),
        ("Quel milieu français a remporté trois Ballons d'Or consécutifs en jouant à la Juventus (1983-85) ?", ["Michel Platini", "Alain Giresse", "Zinédine Zidane", "Jean Tigana"], 0),
        ("Quel club joue au stade Diego-Armando-Maradona ?", ["Naples", "AS Rome", "Lazio", "Cagliari"], 0),
        ("Quel attaquant ukrainien « Sheva » a brillé à l'AC Milan (Ballon d'Or 2004) ?", ["Marco van Basten", "Andriy Shevchenko", "Filippo Inzaghi", "Hernán Crespo"], 1),
        ("Quel meneur italien de l'AC Milan, champion du monde 2006, est réputé pour son élégance et ses coups francs ?", ["Clarence Seedorf", "Kaká", "Gennaro Gattuso", "Andrea Pirlo"], 3),
        ("Quel club romain, rival de l'AS Rome, est surnommé « i Biancocelesti » ?", ["Lazio Rome", "Bologne", "AS Rome", "Fiorentina"], 0),
        ("Quel attaquant argentin, star de la Fiorentina, est surnommé « Batigol » ?", ["Christian Vieri", "Luca Toni", "Francesco Totti", "Gabriel Batistuta"], 3),
        ("Quel club de Florence joue au stade Artemio-Franchi ?", ["Empoli", "AC Sienne", "Fiorentina", "Bologne"], 2),
        ("Quel défenseur italien de l'AC Milan, symbole de longévité, a joué jusqu'à plus de 40 ans (« Paolo ») ?", ["Franco Baresi", "Paolo Maldini", "Alessandro Costacurta", "Giorgio Chiellini"], 1),
        ("Quel Néerlandais « Cygne d'Utrecht » a marqué l'histoire de l'AC Milan comme buteur ?", ["Ruud Gullit", "Frank Rijkaard", "Marco van Basten", "Dennis Bergkamp"], 2),
        ("Quel club piémontais est le rival de la Juventus dans le « Derby della Mole » ?", ["Bologne", "Torino", "Genoa", "Sampdoria"], 1),
        ("Quel club a dominé la Serie A avec neuf scudetti consécutifs entre 2012 et 2020 ?", ["AC Milan", "Naples", "Juventus", "Inter Milan"], 2),
        ("Quel attaquant argentin « El Toro » est devenu capitaine et grand buteur de l'Inter ?", ["Diego Milito", "Gonzalo Higuaín", "Mauro Icardi", "Lautaro Martínez"], 3),
        ("Quel milieu combatif de l'AC Milan, champion du monde 2006, est surnommé « Ringhio » ?", ["Gennaro Gattuso", "Clarence Seedorf", "Andrea Pirlo", "Massimo Ambrosini"], 0),
        ("Quel entraîneur portugais a remporté le triplé avec l'Inter Milan en 2010 ?", ["Marcello Lippi", "Roberto Mancini", "José Mourinho", "Fabio Capello"], 2),
        ("Quel attaquant suédois est revenu à l'AC Milan et a contribué au scudetto 2021-22 ?", ["Rafael Leão", "Ante Rebić", "Zlatan Ibrahimović", "Olivier Giroud"], 2),
        ("Quel club a remporté le scudetto 2022-23, 33 ans après le précédent, dans la ville de Maradona ?", ["Lazio", "AC Milan", "Naples", "Inter Milan"], 2),
        ("Quel défenseur de la Juventus, champion du monde 2006, était surnommé « Chiello » ?", ["Andrea Barzagli", "Giorgio Chiellini", "Fabio Cannavaro", "Leonardo Bonucci"], 1),
        ("Quel défenseur italien a remporté le Ballon d'Or 2006 après le titre mondial, capitaine de la Squadra ?", ["Fabio Cannavaro", "Paolo Maldini", "Alessandro Nesta", "Marco Materazzi"], 0),
        ("Quel attaquant italien « Pippo », grand renard des surfaces, a joué à la Juventus et l'AC Milan ?", ["Christian Vieri", "Alessandro Del Piero", "Luca Toni", "Filippo Inzaghi"], 3),
        ("Quel club génois, l'un des plus anciens d'Italie, est surnommé « il Grifone » ?", ["Sampdoria", "Genoa", "Torino", "Cagliari"], 1),
        ("Quel numéro 10 emblématique de la Juventus, surnommé « Pinturicchio », y a passé toute sa carrière ?", ["Alessandro Nesta", "Roberto Baggio", "Francesco Totti", "Alessandro Del Piero"], 3),
        ("Quel Brésilien, Ballon d'Or 2007, a brillé au milieu de l'AC Milan ?", ["Adriano", "Kaká", "Ronaldinho", "Ronaldo"], 1),
        ("Quel club a remporté le scudetto 2020-21, mettant fin à la domination de la Juventus, sous Conte ?", ["Inter Milan", "AC Milan", "Naples", "Atalanta"], 0),
        ("Quel club de Bergame pratique un football offensif réputé sous Gasperini (« la Dea ») ?", ["Brescia", "Atalanta", "Hellas Vérone", "Sassuolo"], 1),
        ("Quel gardien italien, formé à l'AC Milan, est devenu titulaire du PSG et de la Squadra ?", ["Gianluigi Donnarumma", "Wojciech Szczęsny", "Salvatore Sirigu", "Alex Meret"], 0),
        ("Quel entraîneur italien a gagné le scudetto avec l'Inter (2020-21) après en avoir gagné trois avec la Juventus ?", ["Massimiliano Allegri", "Luciano Spalletti", "Maurizio Sarri", "Antonio Conte"], 3),
    ])
}
