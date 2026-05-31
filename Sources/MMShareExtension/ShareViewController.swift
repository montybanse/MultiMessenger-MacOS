import AppKit

/// Prinzipalklasse der Share Extension. Holt die geteilte URL/den Text und
/// reicht sie über das URL-Schema an die Haupt-App weiter, die dann den
/// Dienst-Auswahldialog zeigt.
@objc(ShareViewController)
final class ShareViewController: NSViewController {

    override func loadView() {
        // Minimale, unsichtbare Oberfläche – wir leiten sofort weiter.
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        extractURL { [weak self] urlString in
            if let urlString { self?.forward(urlString) }
            self?.finish()
        }
    }

    private func extractURL(_ completion: @escaping (String?) -> Void) {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            completion(nil); return
        }
        let urlType = "public.url"
        let textType = "public.plain-text"

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(urlType) {
                    provider.loadItem(forTypeIdentifier: urlType, options: nil) { data, _ in
                        if let url = data as? URL { completion(url.absoluteString) }
                        else if let s = data as? String { completion(s) }
                        else { completion(nil) }
                    }
                    return
                }
            }
        }
        // Kein URL-Attachment -> Text versuchen.
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(textType) {
                    provider.loadItem(forTypeIdentifier: textType, options: nil) { data, _ in
                        completion((data as? String))
                    }
                    return
                }
            }
        }
        completion(nil)
    }

    private func forward(_ urlString: String) {
        let s = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty,
              let encoded = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let appURL = URL(string: "mmsg://share?url=\(encoded)") else { return }
        NSWorkspace.shared.open(appURL)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
