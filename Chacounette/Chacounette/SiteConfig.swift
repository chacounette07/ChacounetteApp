import Foundation

enum SiteConfig {
    /// ⚠️ À MODIFIER : l'adresse de ton site GitHub Pages, avec le "/" final.
    /// Exemple : "https://marie.github.io/chacounette/"
    static let address = "https://chacounette07.github.io/Groupe-Chacounette/"

    static var url: URL {
        URL(string: address) ?? URL(string: "https://github.com")!
    }

    static var isConfigured: Bool {
        !address.contains("TON-NOM") && !address.contains("TON-DEPOT")
    }
}
