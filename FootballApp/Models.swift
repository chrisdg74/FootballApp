import Foundation
import SwiftUI

// Les couleurs et dégradés vivent désormais sur `Competition` (Competitions.swift).
// Ce fichier est conservé pour d'éventuels modèles complémentaires.

// Petit helper de traduction : NSLocalizedString avec repli sur la clé.
// Si l'utilisateur a choisi une langue dans les réglages (LocaleManager), on lit
// la table du bundle `.lproj` correspondant ; sinon on retombe sur le comportement
// standard (langue système). Le repli final est TOUJOURS la clé elle-même.
func L(_ key: String) -> String {
    if let bundle = LocaleManager.shared.bundle {
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    return NSLocalizedString(key, comment: "")
}
