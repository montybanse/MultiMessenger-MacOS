import SwiftUI

/// Schnell-Umschalter (⌘J): Dienst per Tippen finden und mit Pfeiltasten +
/// Enter wechseln.
struct QuickSwitcher: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
    /// Index des aktuell hervorgehobenen Treffers (für Pfeiltasten-Navigation).
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var results: [Service] {
        if query.isEmpty { return app.services }
        return app.services.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { app.showQuickSwitcher = false }

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Dienst wechseln …", text: $query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($focused)
                        .onSubmit(selectCurrent)
                        // Pfeiltasten steuern die Auswahl, ohne den Textcursor zu bewegen.
                        .onKeyPress(.downArrow) { move(1); return .handled }
                        .onKeyPress(.upArrow)   { move(-1); return .handled }
                }
                .padding()

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, service in
                                row(service, highlighted: index == selection)
                                    .id(index)
                                    .onTapGesture { choose(service) }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selection) { _, new in
                        withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(new, anchor: .center) }
                    }
                }
            }
            .frame(width: 460)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
            .shadow(radius: 30)
        }
        .onAppear {
            // Kurze Verzögerung: in onAppear ist das TextField noch nicht
            // fokussierbar. Nach einem Tick klappt die Vorauswahl zuverlässig.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                focused = true
            }
        }
        .onChange(of: query) { _, _ in selection = 0 }   // bei neuer Suche oben beginnen
        .onExitCommand { app.showQuickSwitcher = false }
    }

    private func row(_ service: Service, highlighted: Bool) -> some View {
        HStack {
            ServiceIconView(service: service, size: 24)
            Text(service.name)
            Spacer()
            if let count = app.unread[service.id], count > 0 {
                Text("\(count)").font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.red, in: Capsule())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(highlighted ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }

    /// Verschiebt die Hervorhebung um `delta`, begrenzt auf die Trefferliste.
    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + delta, 0), results.count - 1)
    }

    private func selectCurrent() {
        guard !results.isEmpty else { return }
        let idx = min(max(selection, 0), results.count - 1)
        choose(results[idx])
    }

    private func choose(_ service: Service) {
        app.select(service.id)
        app.showQuickSwitcher = false
        query = ""
    }
}
