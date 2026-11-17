import AppKit
import Foundation
import SwiftUI

/// The addresses this app sends people to.
///
/// One account name, spelled once. The site and the source both hang off it,
/// and a build already installed keeps whatever it was compiled with — so a
/// rename that touched one of the two would leave a dead link in every copy out
/// in the world.
///
/// The tip jar is a second account somewhere else entirely, and it is spelled
/// differently. GitHub Sponsors cannot pay into an Indian account, so the money
/// goes through Ko-fi, whose handle carries no hyphens — nothing may derive one
/// name from the other. The suite reads both spellings out of this file.
///
/// Those name the original project and its author, whom this fork credits.
/// Releases and problem reports are the exception: they belong to whoever
/// built this copy, so they are read out of the feed it updates from.
enum Links {
    static let owner = "aaditya-v-more"
    static let kofiAccount = "aadityavmore"

    static let site = URL(string: "https://\(owner).github.io/claude-graft/")!
    static let source = URL(string: "https://github.com/\(owner)/claude-graft")!
    static let support = URL(string: "https://ko-fi.com/\(kofiAccount)")!

    /// The repository this copy's updates are published from. Its version
    /// numbers are its own, so What's New pointed at the original's releases
    /// described a different list, and a problem with this copy reported there
    /// reached someone who never built it.
    static let published: URL = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)
        .flatMap(Links.repository(fromFeed:)) ?? Links.source
    static let releases = published.appending(path: "releases")
    static let newIssue = published.appending(path: "issues/new")

    /// The two shapes a feed published from GitHub takes: the appcast read raw
    /// off a branch, or served by Pages from the owner's own subdomain.
    static func repository(fromFeed feed: String) -> URL? {
        guard let url = URL(string: feed), let host = url.host else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if host == "raw.githubusercontent.com", parts.count >= 2 {
            return URL(string: "https://github.com/\(parts[0])/\(parts[1])")
        }
        let pages = ".github.io"
        if host.hasSuffix(pages), let repository = parts.first {
            return URL(string: "https://github.com/\(host.dropLast(pages.count))/\(repository)")
        }
        return nil
    }

    /// The original's developer, as a person rather than a repository. A third
    /// spelling, for the same reason as the tip jar: it is not the GitHub name.
    static let linkedIn = URL(string: "https://www.linkedin.com/in/aadityavmore/")!

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

/// A quiet text link for the sidebar's footer. Underlined only under the
/// pointer, because two permanently underlined words at the foot of a sidebar
/// read as an error message rather than an invitation.
struct FooterLink: View {
    let title: String
    let icon: String
    let url: URL
    let help: String

    @State private var hovering = false

    init(_ title: String, icon: String, url: URL, help: String) {
        self.title = L10n.text(title)
        self.icon = icon
        self.url = url
        self.help = L10n.text(help)
    }

    var body: some View {
        Button { Links.open(url) } label: {
            Label(title, systemImage: icon)
                .font(.callout)
                .foregroundStyle(hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .underline(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

/// The Help menu. SwiftUI's own offers a single item that says help isn't
/// available, which on a Mac reads as an app nobody looks after.
struct GraftHelpCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button(L10n.text("Claude Graft Help")) { Links.open(Links.site) }
            Button(L10n.text("What’s New in Claude Graft")) { Links.open(Links.releases) }
            Divider()
            // Problems go to the repository this copy came from, which is
            // why the original's developer is not offered as an address.
            Button(L10n.text("Report a Problem…")) { Links.open(Links.newIssue) }
            Button(L10n.text("Aaditya More on LinkedIn")) { Links.open(Links.linkedIn) }
            Divider()
            Button(L10n.text("View Source on GitHub")) { Links.open(Links.source) }
            Button(L10n.text("Support Claude Graft…")) { Links.open(Links.support) }
        }
    }
}
