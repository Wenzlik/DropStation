import SwiftUI

/// One row in a settings-style list. Six variants share a single
/// anatomy (optional leading SF Symbol → primary label → trailing
/// slot) and are constructed via static factories so call sites
/// stay declarative:
///
///     DSSettingsRow.value(label: "App", value: "DropStation")
///     DSSettingsRow.toggle(label: "Remember session", isOn: $remember)
///     DSSettingsRow.navigation(label: "Version", value: "0.4.0 (8)") {
///         ChangelogView()
///     }
///     DSSettingsRow.link(label: "Source on GitHub", destination: url)
///     DSSettingsRow.picker(label: "Theme", selection: $mode,
///                          options: AppearanceMode.allCases,
///                          optionLabel: \.label)
///     DSSettingsRow.button(label: "Sign out", action: doSignOut)
///
/// Tappable variants (link / navigation / button / picker) wear
/// `DSRowButtonStyle` so press feedback matches the Downloads
/// list. Read-only variants (value / toggle) render without a
/// pressed state.
///
/// Row is intentionally chrome-free — no internal divider, no
/// outer background. The hosting `DSSectionCard` supplies the
/// material surface; callers can insert `Divider()` between rows
/// in the section's content closure.
struct DSSettingsRow: View {
    /// Storage for the variant-specific behaviour. Each factory
    /// builds one of these; `body` switches on it.
    fileprivate enum Kind {
        case value(String)
        case toggle(Binding<Bool>)
        case picker(AnyView)
        case link(URL, trailingText: String?)
        case navigation(AnyView, trailingText: String?)
        case button(role: ButtonRole?, trailingText: String?, action: () -> Void)
    }

    private let systemImage: String?
    private let label: LocalizedStringKey
    private let kind: Kind

    fileprivate init(systemImage: String?, label: LocalizedStringKey, kind: Kind) {
        self.systemImage = systemImage
        self.label = label
        self.kind = kind
    }

    var body: some View {
        switch kind {
        case .value(let text):
            shell(trailing: valueText(text))
        case .toggle(let binding):
            shell(trailing: Toggle("", isOn: binding).labelsHidden())
        case .picker(let pickerView):
            shell(trailing: pickerView)
        case .link(let url, let trailingText):
            Link(destination: url) {
                shell(trailing: trailingWithChevron(trailingText: trailingText, chevron: "arrow.up.right"))
            }
            .buttonStyle(DSRowButtonStyle())
        case .navigation(let destination, let trailingText):
            NavigationLink {
                destination
            } label: {
                shell(trailing: trailingWithChevron(trailingText: trailingText, chevron: "chevron.right"))
            }
            .buttonStyle(DSRowButtonStyle())
        case .button(let role, let trailingText, let action):
            Button(role: role, action: action) {
                shell(trailing: trailingText.map(buttonTrailingText) ?? AnyView(EmptyView()))
            }
            .buttonStyle(DSRowButtonStyle())
        }
    }

    /// Shared row anatomy. Caller supplies the trailing element;
    /// shell handles the leading icon, label, padding, and tap
    /// area shaping so every variant lines up vertically.
    @ViewBuilder
    private func shell<Trailing: View>(trailing: Trailing) -> some View {
        HStack(spacing: DSSpacing.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: 22, alignment: .center)
            }
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: DSSpacing.sm)
            trailing
        }
        .padding(.horizontal, DSSpacing.lg)
        .padding(.vertical, DSSpacing.md)
        .contentShape(Rectangle())
    }

    private func valueText(_ value: String) -> some View {
        Text(value)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    /// Trailing slot for link / navigation: optional value text +
    /// a chevron glyph. `chevron` is the SF Symbol name —
    /// `chevron.right` for push, `arrow.up.right` for external.
    @ViewBuilder
    private func trailingWithChevron(trailingText: String?, chevron: String) -> some View {
        HStack(spacing: 4) {
            if let trailingText {
                valueText(trailingText)
            }
            Image(systemName: chevron)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    /// Trailing for `.button` variants that surface a value
    /// alongside the action (rare — e.g. "Reset (defaults)").
    /// Wrapped in AnyView so the switch arms stay shape-
    /// compatible.
    private func buttonTrailingText(_ value: String) -> AnyView {
        AnyView(valueText(value))
    }
}

// MARK: - Factories

extension DSSettingsRow {
    /// Read-only row: label + value text.
    static func value(
        systemImage: String? = nil,
        label: LocalizedStringKey,
        value: String
    ) -> DSSettingsRow {
        DSSettingsRow(systemImage: systemImage, label: label, kind: .value(value))
    }

    /// Toggle row backed by a `Binding<Bool>`.
    static func toggle(
        systemImage: String? = nil,
        label: LocalizedStringKey,
        isOn: Binding<Bool>
    ) -> DSSettingsRow {
        DSSettingsRow(systemImage: systemImage, label: label, kind: .toggle(isOn))
    }

    /// Inline picker. `options` lists the choices; `optionLabel`
    /// maps each option to its display string. The actual Picker
    /// view is captured into an `AnyView` so the generic type
    /// doesn't bleed into `DSSettingsRow`.
    static func picker<T: Hashable>(
        systemImage: String? = nil,
        label: LocalizedStringKey,
        selection: Binding<T>,
        options: [T],
        optionLabel: @escaping (T) -> String
    ) -> DSSettingsRow {
        let picker = Picker("", selection: selection) {
            ForEach(options, id: \.self) { option in
                Text(optionLabel(option)).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        return DSSettingsRow(systemImage: systemImage, label: label, kind: .picker(AnyView(picker)))
    }

    /// External link row — opens the URL in the default browser /
    /// app. Trailing chevron is `arrow.up.right` to communicate
    /// "leaves the app".
    static func link(
        systemImage: String? = nil,
        label: LocalizedStringKey,
        destination: URL,
        value: String? = nil
    ) -> DSSettingsRow {
        DSSettingsRow(systemImage: systemImage, label: label, kind: .link(destination, trailingText: value))
    }

    /// Push navigation row — pushes the destination onto the
    /// enclosing NavigationStack. Trailing chevron is
    /// `chevron.right` (in-app push).
    static func navigation<Destination: View>(
        systemImage: String? = nil,
        label: LocalizedStringKey,
        value: String? = nil,
        @ViewBuilder destination: () -> Destination
    ) -> DSSettingsRow {
        let dest = destination()
        return DSSettingsRow(systemImage: systemImage, label: label, kind: .navigation(AnyView(dest), trailingText: value))
    }

    /// Action row — invokes the supplied closure on tap. Optional
    /// `role` flags destructive actions (`Forget this device`)
    /// with the system red tint.
    static func button(
        systemImage: String? = nil,
        label: LocalizedStringKey,
        role: ButtonRole? = nil,
        value: String? = nil,
        action: @escaping () -> Void
    ) -> DSSettingsRow {
        DSSettingsRow(systemImage: systemImage, label: label, kind: .button(role: role, trailingText: value, action: action))
    }
}
