import SwiftUI

/// "Trust this server?" prompt shown when the NAS presents a
/// self-signed certificate the user hasn't pinned (or a
/// previously-pinned cert that changed). Surfaced from
/// `SessionStore.State.untrustedCertificate`. Confirm pins the
/// fingerprint and retries; cancel returns to the login form.
///
/// Two tones:
///   - First encounter (`isCertChange == false`) — calm, accent.
///     "This is normal for a Synology NAS; trust it to continue."
///   - Certificate changed (`isCertChange == true`) — orange
///     warning. "Could be a DSM update, could be interception —
///     only continue if expected."
struct CertificateTrustView: View {
    @EnvironmentObject private var session: SessionStore
    let host: String
    let fingerprint: String
    let isCertChange: Bool

    @State private var isWorking = false

    private var tint: Color { isCertChange ? .orange : .accentColor }

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: DSSpacing.xl) {
                    DSCard(.primary) {
                        VStack(alignment: .leading, spacing: DSSpacing.lg) {
                            header
                            fingerprintBlock
                            explanation
                            actions
                        }
                    }
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, 56)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            disc
            DSEyebrow(isCertChange ? "Security warning" : "First connection")
            Text(isCertChange ? "Certificate changed" : "Untrusted certificate")
                .font(.title2.weight(.semibold))
        }
    }

    private var disc: some View {
        Image(systemName: isCertChange ? "lock.trianglebadge.exclamationmark" : "lock.shield")
            .font(.system(size: 26, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: 60, height: 60)
            .glassEffect(.regular.tint(tint.opacity(0.18)), in: .circle)
            .overlay(Circle().strokeBorder(tint.opacity(0.22), lineWidth: 0.5))
            .accessibilityHidden(true)
    }

    private var fingerprintBlock: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            DSEyebrow("\(host) · SHA-256")
            Text(fingerprint)
                .font(.footnote.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DSRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.tile, style: .continuous)
                .strokeBorder(Color.dsSurfaceHairline, lineWidth: 0.5)
        )
    }

    private var explanation: some View {
        Text(isCertChange
             ? "The certificate for \(host) changed since you last trusted it. This can happen after a DSM update or a certificate renewal — but it can also mean someone is intercepting the connection. Only continue if you were expecting this change."
             : "DropStation can't verify \(host)'s certificate against a trusted authority. Synology NAS devices ship with a self-signed certificate by default. If you recognise this server, trust the certificate to continue.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        VStack(spacing: DSSpacing.sm) {
            Button {
                isWorking = true
                Task { await session.trustCertificate(host: host, fingerprint: fingerprint) }
            } label: {
                HStack {
                    if isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text(isCertChange ? "Trust anyway" : "Trust and continue")
                            .font(.body.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)

            Button(role: .cancel) {
                session.declineCertificate()
            } label: {
                Text("Cancel")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .disabled(isWorking)
        }
        .padding(.top, DSSpacing.xs)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
            startPoint: .top, endPoint: .bottom
        )
    }
}
