import SwiftUI

/// Auswahldialog, der erscheint, wenn eine URL über das Teilen-Menü oder das
/// URL-Schema hereinkommt: „In welchem Dienst soll der Link geöffnet werden?“
struct ShareReceiverSheet: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var manager: WebViewManager
    @EnvironmentObject var icons: IconCache

    let urlString: String
    @State private var search = ""

    private var results: [Service] {
        if search.isEmpty { return app.services }
        return app.services.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    /// Dienst, dessen Domain zur geteilten URL passt (wird oben hervorgehoben).
    private var suggested: Service? {
        guard let host = URL(string: urlString.contains("://") ? urlString : "https://" + urlString)?.host
        else { return nil }
        return app.services.first { svc in
            guard let h = URL(string: svc.urlString.contains("://") ? svc.urlString : "https://" + svc.urlString)?.host
            else { return false }
            return h == host || host.hasSuffix(h) || h.hasSuffix(host)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Link öffnen in …").font(.headline)
                    Text(urlString).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
            }
            .padding()
            Divider()

            if app.services.isEmpty {
                VStack(spacing: 8) {
                    Text("Noch keine Dienste vorhanden.").font(.callout)
                    Text("Lege zuerst einen Dienst an.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                if app.services.count > 6 {
                    TextField("Suchen …", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal).padding(.top, 8)
                }
                ScrollView {
                    VStack(spacing: 2) {
                        if let suggested, search.isEmpty {
                            row(suggested, badge: "passend")
                            Divider().padding(.vertical, 4)
                        }
                        ForEach(results) { svc in
                            if !(search.isEmpty && svc.id == suggested?.id) {
                                row(svc, badge: nil)
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 300)
            }

            Divider()
            HStack {
                Spacer()
                Button("Abbrechen") { app.pendingShareURL = nil }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(width: 440)
    }

    private func row(_ svc: Service, badge: String?) -> some View {
        Button {
            open(svc)
        } label: {
            HStack(spacing: 10) {
                ServiceIconView(service: svc, size: 26).environmentObject(icons)
                Text(svc.name)
                if let badge {
                    Text(badge).font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.tint.opacity(0.2), in: Capsule())
                }
                Spacer()
                Image(systemName: "arrow.right.circle").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func open(_ svc: Service) {
        app.select(svc.id)
        manager.load(urlString: urlString, into: svc)
        app.pendingShareURL = nil
    }
}
