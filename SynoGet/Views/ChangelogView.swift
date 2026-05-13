import SwiftUI

/// Renders the bundled `CHANGELOG.md` as a scrollable document. The body of each
/// version section is parsed into typed blocks (heading / paragraph / bullet list)
/// and laid out with proper spacing instead of being dumped into a single Text —
/// SwiftUI's Text + AttributedString doesn't preserve paragraph breaks between
/// Markdown blocks, so without this everything collapses into one paragraph.
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
                    VStack(alignment: .leading, spacing: 20) {
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

    /// Split the file into version sections by `## ` heading. Everything before the
    /// first version (the project intro paragraph) is dropped. Link-reference
    /// footers (`[0.3.0]: https://…`) are dropped too.
    private static func parse(_ text: String) -> [Section] {
        let lines = text.components(separatedBy: "\n")
        var sections: [Section] = []
        var currentTitle: String?
        var currentBody: [String] = []

        for line in lines {
            if line.hasPrefix("## ") {
                if let title = currentTitle {
                    sections.append(Section(title: title, blocks: Block.parse(currentBody)))
                }
                currentTitle = String(line.dropFirst(3))
                currentBody = []
            } else if currentTitle != nil {
                if line.hasPrefix("[") && line.contains("]:") { continue }
                currentBody.append(line)
            }
        }
        if let title = currentTitle {
            sections.append(Section(title: title, blocks: Block.parse(currentBody)))
        }
        return sections
    }

    struct Section: Identifiable {
        let title: String
        let blocks: [Block]
        var id: String { title }
    }

    enum Block: Identifiable {
        case heading(String)        // ### Subheading
        case paragraph(String)
        case bullets([String])

        var id: String {
            switch self {
            case .heading(let s): return "h:\(s)"
            case .paragraph(let s): return "p:\(s.prefix(40))"
            case .bullets(let xs): return "b:\(xs.first?.prefix(40) ?? "")"
            }
        }

        /// Walk lines, fold consecutive non-bullet text into paragraphs and
        /// consecutive `- ` lines into a single bullet block. Empty lines flush
        /// whatever is being accumulated.
        static func parse(_ lines: [String]) -> [Block] {
            var blocks: [Block] = []
            var bullets: [String] = []
            var paragraph: [String] = []

            func flushBullets() {
                if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
            }
            func flushParagraph() {
                if !paragraph.isEmpty {
                    let joined = paragraph.joined(separator: " ")
                    if !joined.trimmingCharacters(in: .whitespaces).isEmpty {
                        blocks.append(.paragraph(joined))
                    }
                    paragraph = []
                }
            }

            for rawLine in lines {
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    flushBullets()
                    flushParagraph()
                } else if trimmed.hasPrefix("### ") {
                    flushBullets()
                    flushParagraph()
                    blocks.append(.heading(String(trimmed.dropFirst(4))))
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    flushParagraph()
                    bullets.append(String(trimmed.dropFirst(2)))
                } else {
                    flushBullets()
                    paragraph.append(trimmed)
                }
            }
            flushBullets()
            flushParagraph()
            return blocks
        }
    }
}

// MARK: - Rendering

private struct SectionView: View {
    let section: ChangelogView.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(section.title)
                .font(.title2.weight(.semibold))
            ForEach(section.blocks) { block in
                BlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 16, style: .continuous))
    }
}

private struct BlockView: View {
    let block: ChangelogView.Block

    var body: some View {
        switch block {
        case .heading(let text):
            Text(text)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        case .paragraph(let text):
            Text(attributed(text))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("•")
                            .foregroundStyle(.tint)
                            .font(.body.weight(.bold))
                        Text(attributed(item))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// Parse inline Markdown (bold/italic/code/links) for a single line. Block-level
    /// constructs are already handled by Block.parse, so the `.inlineOnlyPreservingWhitespace`
    /// option is what we want.
    private func attributed(_ s: String) -> AttributedString {
        var opts = AttributedString.MarkdownParsingOptions()
        opts.interpretedSyntax = .inlineOnlyPreservingWhitespace
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }
}
