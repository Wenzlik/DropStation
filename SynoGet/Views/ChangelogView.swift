import SwiftUI

/// Renders the bundled `CHANGELOG.md` as a scrollable Markdown document inside the
/// app. The file is added to the SynoGet target's resources via project.yml so
/// it ships alongside the binary instead of being a remote fetch.
struct ChangelogView: View {
    @State private var sections: [Section] = []
    @State private var loadError: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Couldn't read changelog",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if sections.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(sections) { section in
                            SectionView(section: section)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("What's new")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func load() {
        do {
            guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") else {
                loadError = "CHANGELOG.md is not bundled with the app."
                return
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            sections = Self.parse(text)
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Crude Markdown chunker: splits on `##` version headings and keeps each
    /// version's body verbatim so the iOS Markdown renderer can lay out
    /// sub-headings, bullets and inline emphasis.
    private static func parse(_ text: String) -> [Section] {
        // Skip everything before the first version heading (intro paragraph).
        let lines = text.components(separatedBy: "\n")
        var sections: [Section] = []
        var currentTitle: String?
        var currentBody: [String] = []

        for line in lines {
            if line.hasPrefix("## ") {
                if let title = currentTitle {
                    sections.append(Section(title: title, body: currentBody.joined(separator: "\n")))
                }
                currentTitle = String(line.dropFirst(3))
                currentBody = []
            } else if currentTitle != nil {
                // Drop the link-reference footer ([0.3.0]: https://…).
                if line.hasPrefix("[") && line.contains("]:") { continue }
                currentBody.append(line)
            }
        }
        if let title = currentTitle {
            sections.append(Section(title: title, body: currentBody.joined(separator: "\n")))
        }
        return sections
    }

    struct Section: Identifiable {
        let title: String
        let body: String
        var id: String { title }
    }
}

private struct SectionView: View {
    let section: ChangelogView.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.title2.weight(.semibold))
            Text(rendered)
                .font(.body)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
    }

    private var rendered: AttributedString {
        // AttributedString's full-document Markdown parser handles headings,
        // bullet lists, inline code, bold/italic and links. Fall back to plain
        // text if parsing fails for any reason.
        (try? AttributedString(
            markdown: section.body,
            options: .init(interpretedSyntax: .full)
        )) ?? AttributedString(section.body)
    }
}
