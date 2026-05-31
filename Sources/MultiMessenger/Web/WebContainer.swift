import SwiftUI
import WebKit

/// Zeigt die WebView des aktuell ausgewählten Dienstes. Andere (wache) WebViews
/// bleiben im Speicher des Managers erhalten, werden aber aus der Ansicht entfernt.
struct WebContainer: NSViewRepresentable {
    let service: Service
    @ObservedObject var manager: WebViewManager

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let webView = manager.webView(for: service)

        // Falls bereits korrekt eingehängt: nichts tun.
        if webView.superview === container { return }

        webView.removeFromSuperview()
        for sub in container.subviews { sub.removeFromSuperview() }

        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
