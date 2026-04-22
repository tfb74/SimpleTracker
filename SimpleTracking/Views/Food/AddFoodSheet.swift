import SwiftUI

struct AddFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    let defaultDate: Date

    enum Mode: String, Identifiable, CaseIterable {
        case manual, barcode, photo
        var id: String { rawValue }
    }
    @State private var mode: Mode? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                methodButton(.manual,
                             title: "Manuell eingeben",
                             subtitle: "Name, Menge, Kalorien und Kohlenhydrate selbst angeben.",
                             icon: "square.and.pencil",
                             color: .blue)

                methodButton(.barcode,
                             title: "Barcode scannen",
                             subtitle: "Verpackte Lebensmittel — Nährwerte aus Open Food Facts.",
                             icon: "barcode.viewfinder",
                             color: .green)

                methodButton(.photo,
                             title: "Foto analysieren",
                             subtitle: FoodPhotoAnalyzer.isLLMAvailable
                                 ? "Apple Intelligence erkennt Speisen und schätzt Nährwerte."
                                 : "Ohne Apple Intelligence nur grobe Schätzung über Bildlabels.",
                             icon: "camera.viewfinder",
                             color: .purple)
                Spacer()
            }
            .padding()
            .navigationTitle("Eintrag hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .sheet(item: $mode) { selected in
                switch selected {
                case .manual:
                    ManualFoodEntryView(defaultDate: defaultDate) { dismiss() }
                case .barcode:
                    BarcodeEntryView(defaultDate: defaultDate) { dismiss() }
                case .photo:
                    PhotoFoodAnalysisView(defaultDate: defaultDate) { dismiss() }
                }
            }
        }
    }

    private func methodButton(_ target: Mode, title: String, subtitle: String,
                              icon: String, color: Color) -> some View {
        Button { mode = target } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .background(color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
