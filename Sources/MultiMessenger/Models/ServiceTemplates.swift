import Foundation

/// Vorgefertigter Dienst-Katalog. Wird beim Hinzufügen angeboten.
struct ServiceTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    let urlString: String
    let symbol: String        // SF-Symbol als Platzhalter-Icon
    let category: String
    var userAgent: String = ""   // leer = Standard-Kennung (Safari)

    init(id: String, name: String, urlString: String, symbol: String,
         category: String, userAgent: String = "") {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.symbol = symbol
        self.category = category
        self.userAgent = userAgent
    }

    func makeService(workspaceID: UUID?) -> Service {
        Service(
            name: name,
            urlString: urlString,
            workspaceID: workspaceID,
            iconSymbol: symbol,
            useFavicon: true,
            templateID: id,
            userAgent: userAgent
        )
    }
}

enum ServiceCatalog {
    static let all: [ServiceTemplate] = [
        // Messenger
        .init(id: "whatsapp",   name: "WhatsApp",     urlString: "https://web.whatsapp.com",        symbol: "message.fill",        category: "Messenger"),
        .init(id: "telegram",   name: "Telegram",     urlString: "https://web.telegram.org",        symbol: "paperplane.fill",     category: "Messenger"),
        .init(id: "signal",     name: "Signal",       urlString: "https://app.signal.org",          symbol: "lock.fill",           category: "Messenger"),
        .init(id: "messenger",  name: "Messenger",    urlString: "https://www.messenger.com",       symbol: "message.circle.fill", category: "Messenger"),
        .init(id: "threema",    name: "Threema",      urlString: "https://web.threema.ch",          symbol: "lock.shield.fill",    category: "Messenger"),

        // Teams / Arbeit
        .init(id: "slack",      name: "Slack",        urlString: "https://app.slack.com/client",    symbol: "number.square.fill",  category: "Arbeit", userAgent: UserAgentPreset.chrome),
        .init(id: "mattermost", name: "Mattermost",   urlString: "https://", /* eigene Instanz */   symbol: "bubble.left.and.bubble.right.fill", category: "Arbeit"),
        .init(id: "teams",      name: "MS Teams",     urlString: "https://teams.microsoft.com",     symbol: "person.2.fill",       category: "Arbeit", userAgent: UserAgentPreset.chrome),
        .init(id: "discord",    name: "Discord",      urlString: "https://discord.com/app",         symbol: "gamecontroller.fill", category: "Arbeit"),
        .init(id: "gchat",      name: "Google Chat",  urlString: "https://chat.google.com",         symbol: "bubble.left.fill",    category: "Arbeit"),
        .init(id: "element",    name: "Element/Matrix", urlString: "https://app.element.io",        symbol: "circle.hexagongrid.fill", category: "Arbeit"),

        // E-Mail
        .init(id: "gmail",      name: "Gmail",        urlString: "https://mail.google.com",         symbol: "envelope.fill",       category: "E-Mail"),
        .init(id: "outlook",    name: "Outlook",      urlString: "https://outlook.office.com/mail", symbol: "envelope.badge.fill", category: "E-Mail"),
        .init(id: "proton",     name: "Proton Mail",  urlString: "https://mail.proton.me",          symbol: "envelope.circle.fill",category: "E-Mail"),

        // Soziale Netzwerke
        .init(id: "linkedin",   name: "LinkedIn",     urlString: "https://www.linkedin.com",        symbol: "briefcase.fill",      category: "Netzwerke"),
        .init(id: "xing",       name: "Xing",         urlString: "https://www.xing.com",            symbol: "person.crop.square.fill", category: "Netzwerke"),
        .init(id: "instagram",  name: "Instagram",    urlString: "https://www.instagram.com",       symbol: "camera.fill",         category: "Netzwerke"),
        .init(id: "facebook",   name: "Facebook",     urlString: "https://www.facebook.com",        symbol: "f.square.fill",       category: "Netzwerke"),
        .init(id: "x",          name: "X / Twitter",  urlString: "https://x.com",                   symbol: "bird.fill",           category: "Netzwerke"),
        .init(id: "mastodon",   name: "Mastodon",     urlString: "https://mastodon.social",         symbol: "number",              category: "Netzwerke"),
        .init(id: "bluesky",    name: "Bluesky",      urlString: "https://bsky.app",                symbol: "cloud.fill",          category: "Netzwerke"),

        // Meetings / Video
        .init(id: "bbb",        name: "BigBlueButton", urlString: "https://", /* eigene Instanz */  symbol: "video.fill",          category: "Meetings", userAgent: UserAgentPreset.chrome),
        .init(id: "meet",       name: "Google Meet",  urlString: "https://meet.google.com",         symbol: "video.circle.fill",   category: "Meetings"),
        .init(id: "zoom",       name: "Zoom",         urlString: "https://app.zoom.us/wc",          symbol: "video.badge.waveform",category: "Meetings"),
        .init(id: "jitsi",      name: "Jitsi Meet",   urlString: "https://meet.jit.si",             symbol: "video.bubble.left.fill", category: "Meetings"),
    ]

    static var categories: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for t in all where !seen.contains(t.category) {
            seen.insert(t.category)
            result.append(t.category)
        }
        return result
    }
}
