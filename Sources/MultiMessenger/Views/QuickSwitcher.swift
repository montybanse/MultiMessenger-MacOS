import SwiftUI

/// Schnell-Umschalter (⌘K): Dienst per Tippen finden und wechseln.
struct QuickSwitcher: View {
    @EnvironmentObject var app: AppState
    @State private var query = ""
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
                        .onSubmit(selectFirst)
                }
                .padding()

                Divider()

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(results) { service in
                            Button { choose(service) } label: {
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
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 320)
            }
            .frame(width: 460)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
            .shadow(radius: 30)
        }
        .onAppear { focused = true }
        .onExitCommand { app.showQuickSwitcher = false }
    }

    private func selectFirst() {
        if let first = results.first { choose(first) }
    }

    private func choose(_ service: Service) {
        app.select(service.id)
        app.showQuickSwitcher = false
        query = ""
    }
}
