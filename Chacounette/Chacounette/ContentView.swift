import SwiftUI

struct ContentView: View {
    @State private var isLoading = true
    @State private var failed = false
    @State private var hasLoaded = false
    @State private var reloadToken = 0

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if SiteConfig.isConfigured {
                WebView(isLoading: $isLoading, failed: $failed, reloadToken: reloadToken)
                    .ignoresSafeArea(.container, edges: [.top, .bottom])

                if isLoading && !hasLoaded && !failed {
                    ProgressView()
                }

                if failed {
                    offlineView
                }
            } else {
                notConfiguredView
            }
        }
        .onChange(of: isLoading) { loading in
            if !loading { hasLoaded = true }
        }
    }

    private var offlineView: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Chacounette est hors ligne.")
                .font(.title2.weight(.semibold))
            Text("Vérifie ta connexion internet, puis réessaie.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Réessayer") {
                failed = false
                isLoading = true
                reloadToken += 1
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var notConfiguredView: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Adresse du site à renseigner")
                .font(.title2.weight(.semibold))
            Text("Ouvre le fichier SiteConfig.swift et remplace l’adresse par celle de ton site GitHub Pages.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
