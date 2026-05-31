import SwiftUI

/// Inhalt des Menüleisten-Popovers: kompakte Übersicht aller Dienste mit
/// Ungelesen-Zählern, DND-Schalter und Schnellsprung ins Hauptfenster.
struct MenuBarPanel: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var icons: IconCache
    @EnvironmentObject var manager: WebViewManager

    /// Aktion zum Öffnen des Hauptfensters bei einem bestimmten Dienst.
    var onOpenService: (UUID) -> Void
    var onOpenMain: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if app.services.isEmpty {
                Text("Noch keine Dienste.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(app.services) { service in
                            row(service)
                        }
                    }
                    .padding(8)
                }
            }
            Divider()
            footer
        }
        .frame(width: 320, height: 420)
    }

    private var header: some View {
        HStack {
            Image(systemName: "bubble.left.and.bubble.right.fill").foregroundStyle(.tint)
            Text("MultiMessenger").font(.headline)
            Spacer()
            if app.totalUnread > 0 {
                Text("\(app.totalUnread)")
                    .font(.caption.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(.red, in: Capsule())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func row(_ service: Service) -> some View {
        let unread = app.unread[service.id] ?? 0
        return Button {
            onOpenService(service.id)
        } label: {
            HStack(spacing: 10) {
                ServiceIconView(service: service, size: 26,
                                muted: service.muted,
                                sleeping: manager.isSleeping(service.id, selected: app.selectedServiceID))
                    .environmentObject(icons)
                VStack(alignment: .leading, spacing: 1) {
                    Text(service.name).lineLimit(1)
                    if service.locked {
                        Label("geschützt", systemImage: "lock.fill")
                            .font(.caption2).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                    }
                }
                Spacer()
                if unread > 0 {
                    Text(unread > 99 ? "99+" : "\(unread)")
                        .font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(service.muted ? Color.gray : Color.red, in: Capsule())
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(service.id == app.selectedServiceID ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Button {
                app.settings.dndEnabled.toggle()
            } label: {
                Label(app.settings.dndEnabled ? "Nicht stören: AN" : "Nicht stören",
                      systemImage: app.settings.dndEnabled ? "moon.fill" : "bell.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(app.settings.dndEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))

            Spacer()

            Button {
                onOpenMain()
            } label: {
                Label("Öffnen", systemImage: "macwindow")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}
