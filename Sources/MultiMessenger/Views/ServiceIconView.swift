import SwiftUI

/// Rendert das Icon eines Dienstes (eigenes Bild, Favicon oder SF-Symbol)
/// mit optionalem Ungelesen-Badge und Schlaf-Symbol.
struct ServiceIconView: View {
    @EnvironmentObject var icons: IconCache
    let service: Service
    var size: CGFloat = 28
    var unread: Int = 0
    var muted: Bool = false
    var sleeping: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            iconImage
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
                .opacity(sleeping ? 0.45 : 1.0)
                .overlay {
                    if sleeping {
                        // Pause-Symbol über schlafenden Diensten.
                        Image(systemName: "pause.circle.fill")
                            .font(.system(size: size * 0.42, weight: .semibold))
                            .foregroundStyle(.white, .secondary)
                            .shadow(radius: 1)
                    }
                }

            if unread > 0 {
                Text(unread > 99 ? "99+" : "\(unread)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(muted ? Color.gray : Color.red, in: Capsule())
                    .offset(x: 6, y: -6)
            } else if muted {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(Color.gray, in: Circle())
                    .offset(x: 6, y: -6)
            }
        }
    }

    @ViewBuilder
    private var iconImage: some View {
        if let data = service.iconData, let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage).resizable().scaledToFill()
        } else if service.useFavicon, let logo = icons.image(forURLString: service.urlString) {
            Image(nsImage: logo)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(size * 0.12)
                .frame(width: size, height: size)
        } else {
            Image(systemName: service.iconSymbol)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(
                    LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
        }
    }

    /// Stabile Akzentfarbe aus dem Namen ableiten.
    private var accent: Color {
        let palette: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo, .red, .mint, .cyan]
        let hash = abs(service.name.hashValue)
        return palette[hash % palette.count]
    }
}
