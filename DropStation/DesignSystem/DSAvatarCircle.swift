import SwiftUI

/// Initials disc — a small Liquid Glass circle with one or two
/// uppercase letters centred inside, tinted by the caller's
/// accent. Used as the lightweight "account identity" cue in the
/// Settings hero card (Phase 4.2.3) and reusable anywhere a
/// generated-from-string avatar fits — future server switcher,
/// activity attribution, etc.
///
/// Two inits:
///
///   - `init(initials:)` — caller supplies the letters directly.
///   - `init(account:)` — caller passes the raw account string
///     ("vasek", "vasek.zmrhal", "vz@nas.local") and the disc
///     extracts up to two initials from the leading token,
///     ignoring non-letter separators.
///
/// Intentionally cheap and offline — no avatar service, no
/// image cache, no I/O. The accent-tinted disc + rounded
/// monospaced glyphs read as "premium utility" without the
/// complexity of an actual avatar system.
struct DSAvatarCircle: View {
    let initials: String
    let size: CGFloat
    let tint: Color

    init(initials: String, size: CGFloat = 48, tint: Color = .accentColor) {
        // Clamp to the leading two glyphs and uppercase so any
        // input ("vz", "abc", "Foo Bar") renders predictably.
        self.initials = String(initials.prefix(2)).uppercased()
        self.size = size
        self.tint = tint
    }

    /// Best-effort initials extraction from a free-form account
    /// string. Splits the leading token (before any "@") on
    /// non-letter separators (".", "_", "-", digits) and takes
    /// the first character of the first one or two parts.
    /// Falls back to "?" when nothing useful is extractable
    /// (defends against an edge case where the config was
    /// cleared mid-flight).
    init(account: String, size: CGFloat = 48, tint: Color = .accentColor) {
        let token = account.split(separator: "@").first.map(String.init) ?? account
        let parts = token.split(whereSeparator: { !$0.isLetter })
        let derived: String
        if parts.count >= 2 {
            derived = String(parts.prefix(2).compactMap { $0.first })
        } else if let first = parts.first {
            derived = String(first.prefix(2))
        } else {
            derived = "?"
        }
        self.init(initials: derived, size: size, tint: tint)
    }

    var body: some View {
        Circle()
            .fill(tint.opacity(0.18))
            .frame(width: size, height: size)
            .overlay {
                Text(initials)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            .overlay(
                Circle().strokeBorder(tint.opacity(0.25), lineWidth: 0.5)
            )
    }
}
