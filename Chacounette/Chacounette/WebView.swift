import SwiftUI
import WebKit
import UIKit

/// Affiche le site de Chacounette. Tout changement publié sur le site apparaît ici.
struct WebView: UIViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var failed: Bool
    var reloadToken: Int

    /// Ajouté par l'app : fait vibrer le téléphone à chaque appui sur « Caresser » ou sur la photo,
    /// même si le site n'a pas été modifié pour ça.
    static let hapticScript = """
    document.addEventListener('click', function (e) {
      var t = e.target;
      if (t && t.closest && t.closest('[data-purr], #portrait')) {
        try { window.webkit.messageHandlers.haptic.postMessage('light'); } catch (err) {}
      }
    }, true);
    """

    /// Ajouté par l'app : l'interface du site ne peut plus être zoomée (pincement, double appui).
    /// Le zoom de la photo dans la galerie est géré par le site lui-même.
    static let lockZoomScript = """
    (function () {
      function lock() {
        var css = document.createElement('style');
        css.textContent = 'html, body { touch-action: pan-x pan-y; }';
        (document.head || document.documentElement).appendChild(css);

        var m = document.querySelector('meta[name=viewport]');
        if (!m) {
          m = document.createElement('meta');
          m.name = 'viewport';
          m.content = 'width=device-width, initial-scale=1';
          (document.head || document.documentElement).appendChild(m);
        }
        if (m.content.indexOf('user-scalable') === -1) {
          m.content += ', maximum-scale=1, user-scalable=no';
        }
      }
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', lock);
      } else {
        lock();
      }
    })();
    """

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "ChacounetteApp"
        config.userContentController.add(context.coordinator, name: "haptic")
        config.userContentController.add(context.coordinator, name: "notifications")
        config.userContentController.add(context.coordinator, name: "share")
        config.userContentController.addUserScript(
            WKUserScript(source: WebView.hapticScript,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true)
        )
        config.userContentController.addUserScript(
            WKUserScript(source: WebView.lockZoomScript,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true)
        )

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        // La page gère elle-même les marges de la barre d'état (env(safe-area-inset-*))
        web.scrollView.contentInsetAdjustmentBehavior = .never
        // Pas de zoom sur l'interface (le pincement reste disponible pour la page : photo de la galerie)
        web.scrollView.pinchGestureRecognizer?.isEnabled = false
        web.scrollView.minimumZoomScale = 1.0
        web.scrollView.maximumZoomScale = 1.0

        // Tirer vers le bas = recharger la page depuis le site (dernière version)
        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator,
                          action: #selector(Coordinator.pulledToRefresh),
                          for: .valueChanged)
        web.scrollView.refreshControl = refresh

        context.coordinator.webView = web
        context.coordinator.refreshControl = refresh
        context.coordinator.loadHome()
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.lastToken != reloadToken {
            context.coordinator.lastToken = reloadToken
            context.coordinator.reload()
        }
    }

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        for name in ["haptic", "notifications", "share"] {
            web.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebView
        weak var webView: WKWebView?
        weak var refreshControl: UIRefreshControl?
        var lastToken = 0
        private var triedCache = false
        private let generator = UIImpactFeedbackGenerator(style: .medium)
        private var lastHaptic = Date.distantPast

        init(_ parent: WebView) {
            self.parent = parent
        }

        private func setState(loading: Bool, failed: Bool) {
            DispatchQueue.main.async {
                self.parent.isLoading = loading
                self.parent.failed = failed
            }
        }

        func loadHome() {
            guard let web = webView else { return }
            triedCache = false
            generator.prepare()
            web.load(URLRequest(url: SiteConfig.url))
        }

        func reload() {
            guard let web = webView else { return }
            triedCache = false
            if web.url != nil {
                web.reloadFromOrigin()
            } else {
                web.load(URLRequest(url: SiteConfig.url,
                                    cachePolicy: .reloadIgnoringLocalCacheData))
            }
        }

        @objc func pulledToRefresh() {
            reload()
        }

        // Navigation

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            setState(loading: true, failed: false)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            triedCache = false
            refreshControl?.endRefreshing()
            setState(loading: false, failed: false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handle(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handle(error)
        }

        private func handle(_ error: Error) {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled { return }
            if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
            refreshControl?.endRefreshing()

            // Hors ligne : on essaie d'abord d'afficher la dernière version en mémoire
            if !triedCache, let web = webView {
                triedCache = true
                let failing = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? SiteConfig.url
                web.load(URLRequest(url: failing, cachePolicy: .returnCacheDataDontLoad))
                return
            }
            setState(loading: false, failed: true)
        }

        // Les liens vers d'autres sites (ou mail, téléphone) s'ouvrent hors de l'app
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let isWeb = url.scheme == "http" || url.scheme == "https"
            if !isWeb || url.host != SiteConfig.url.host {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        // Le site peut déclencher une vibration légère (bouton « Caresser »)
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "notifications":
                handleNotifications(message.body)
                return
            case "share":
                handleShare(message.body)
                return
            case "haptic":
                break
            default:
                return
            }
            // Anti-doublon : le site et l'app peuvent envoyer le même signal
            let now = Date()
            if now.timeIntervalSince(lastHaptic) < 0.15 { return }
            lastHaptic = now
            generator.impactOccurred(intensity: 0.9)
            generator.prepare()
        }

        // MARK: - Rappel quotidien

        private func handleNotifications(_ body: Any) {
            guard let dict = body as? [String: Any],
                  let action = dict["action"] as? String else { return }
            let hour = (dict["hour"] as? NSNumber)?.intValue ?? 9
            let minute = (dict["minute"] as? NSNumber)?.intValue ?? 0
            let reply: ([String: Any]) -> Void = { [weak self] state in
                self?.sendNotificationState(state)
            }
            switch action {
            case "enable":
                NotificationManager.shared.enable(hour: hour, minute: minute, completion: reply)
            case "disable":
                NotificationManager.shared.disable(completion: reply)
            default:
                NotificationManager.shared.status(completion: reply)
            }
        }

        /// Renvoie l'état au site, qui met à jour l'interrupteur.
        private func sendNotificationState(_ state: [String: Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: state),
                  let json = String(data: data, encoding: .utf8) else { return }
            webView?.evaluateJavaScript("window.chacounetteNotif && window.chacounetteNotif(\(json));",
                                        completionHandler: nil)
        }

        // MARK: - Partage (photo du jour, score du quiz)

        private func handleShare(_ body: Any) {
            guard let dict = body as? [String: Any] else { return }
            var items: [Any] = []
            if let text = dict["text"] as? String {
                items.append(text)
            }
            if let link = dict["link"] as? String,
               let url = URL(string: link),
               url.scheme?.hasPrefix("http") == true {
                items.append(url)
            }
            let baseItems = items

            if let imageString = dict["image"] as? String,
               let imageURL = URL(string: imageString) {
                URLSession.shared.dataTask(with: imageURL) { [weak self] data, _, _ in
                    var all = baseItems
                    if let data = data, let image = UIImage(data: data) {
                        all.insert(image, at: 0)
                    }
                    DispatchQueue.main.async { self?.presentShareSheet(all) }
                }.resume()
            } else {
                presentShareSheet(baseItems)
            }
        }

        private func presentShareSheet(_ items: [Any]) {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard !items.isEmpty,
                  let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }),
                  let root = window.rootViewController else { return }
            var top = root
            while let presented = top.presentedViewController {
                top = presented
            }
            let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if let popover = sheet.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            top.present(sheet, animated: true)
        }
    }
}
