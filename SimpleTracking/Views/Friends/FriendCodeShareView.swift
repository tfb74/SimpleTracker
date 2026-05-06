import SwiftUI
import CoreImage.CIFilterBuiltins

/// Sheet zum Teilen des eigenen Friend-Codes:
/// - großer lesbarer Code zum Vorlesen
/// - QR-Code (Standard CIFilter) für schnelles Scannen
/// - "Teilen…"-Button öffnet das iOS-Share-Sheet
struct FriendCodeShareView: View {
    @Environment(\.dismiss) private var dismiss
    let code: String
    let displayName: String

    /// QR-Code zeigt eine HTTPS-Universal-Link-URL — ermöglicht Rich Preview
    /// in iMessage und funktioniert auch wenn die App nicht installiert ist
    /// (führt dann zur Landing-Page mit App-Store-Link).
    private let universalLinkBase = "https://tfb74.github.io/SimpleTracker/friend"

    private var universalLink: String {
        "\(universalLinkBase)?code=\(code)"
    }

    /// QR-Code-Payload — ebenfalls Universal Link, damit der Code auch von
    /// nicht-SimpleTracking-Usern gescannt werden kann (führt zur Landing-Page).
    private var qrPayload: String { universalLink }

    private var shareURL: URL {
        URL(string: universalLink) ?? URL(string: "https://tfb74.github.io/SimpleTracker/")!
    }

    private var shareSubject: String {
        "\(displayName) auf SimpleTracking"
    }

    private var shareMessage: String {
        "Folge mir in SimpleTracking. Tippe auf den Link, um meinen Code automatisch zu übernehmen:"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(displayName)
                    .font(.title3.weight(.semibold))
                    .padding(.top, 8)

                if let qrImage = makeQRImage(from: qrPayload) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                }

                VStack(spacing: 4) {
                    Text("Dein Code")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(code)
                        .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.accentColor)
                }

                Text("Freunde tippen den Code in \"Freund hinzufügen\" ein, oder scannen den QR-Code mit der Kamera.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()

                ShareLink(
                    item: shareURL,
                    subject: Text(shareSubject),
                    message: Text(shareMessage)
                ) {
                    Label("Teilen…", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                Button("Code kopieren") {
                    UIPasteboard.general.string = code
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                .padding(.bottom)
            }
            .navigationTitle("Code teilen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func makeQRImage(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        // Hochskalieren für scharfe Pixel
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
