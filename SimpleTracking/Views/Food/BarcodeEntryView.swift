import SwiftUI
import VisionKit

struct BarcodeEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FoodLogStore.self) private var store

    let defaultDate: Date
    let onComplete: () -> Void

    @State private var scannedCode: String?
    @State private var product: OFFProduct?
    @State private var loading = false
    @State private var errorMessage: String?

    // Portion editable
    @State private var portionGrams: Double = 100
    @State private var timestamp: Date = Date()
    @State private var kind: FoodKind = .food

    var body: some View {
        NavigationStack {
            Group {
                if product == nil && !loading {
                    scannerSection
                } else if loading {
                    ProgressView("Lade Produktdaten…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let p = product {
                    productForm(for: p)
                }
            }
            .navigationTitle("Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                if product != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Speichern") { save() }
                    }
                }
            }
            .alert("Nicht gefunden", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ), actions: {
                Button("Erneut scannen") { scannedCode = nil }
                Button("Manuell") {
                    dismiss()
                    // User can tap "Manuell" in the main picker again.
                }
            }, message: { Text(errorMessage ?? "") })
        }
        .task(id: scannedCode) {
            guard let code = scannedCode, product == nil else { return }
            await lookup(code)
        }
    }

    // MARK: - Scanner

    @ViewBuilder
    private var scannerSection: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            BarcodeScannerRepresentable(onScan: { scannedCode = $0 })
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Text("Richte die Kamera auf den Barcode")
                        .font(.footnote)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                }
        } else {
            ContentUnavailableView(
                "Barcode-Scan nicht verfügbar",
                systemImage: "exclamationmark.triangle",
                description: Text("Dein Gerät unterstützt keinen DataScanner. Nutze stattdessen die manuelle Eingabe.")
            )
        }
    }

    // MARK: - Product Form

    private func productForm(for p: OFFProduct) -> some View {
        let factor = portionGrams / 100.0
        let kcal = p.kcalPer100g * factor
        let carbs = p.carbsPer100g * factor

        return Form {
            Section("Produkt") {
                HStack {
                    VStack(alignment: .leading) {
                        Text(p.name).font(.headline)
                        if let b = p.brand { Text(b).font(.caption).foregroundStyle(.secondary) }
                        Text("Barcode: \(p.barcode)").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            }

            Section("Zeitpunkt & Art") {
                DatePicker("Zeit", selection: $timestamp)
                Picker("Art", selection: $kind) {
                    ForEach(FoodKind.allCases, id: \.self) {
                        Label($0.displayName, systemImage: $0.systemImage).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Portion") {
                HStack {
                    Text("Menge")
                    Spacer()
                    TextField("g", value: $portionGrams, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text(kind == .drink ? "ml" : "g").foregroundStyle(.secondary)
                }
                Slider(value: $portionGrams, in: 10...500, step: 5)
            }

            Section("Nährwerte (berechnet)") {
                row("Kalorien", value: String(format: "%.0f kcal", kcal), color: .orange)
                row("Kohlenhydrate", value: String(format: "%.1f g", carbs), color: .blue)
                row("Broteinheiten", value: String(format: "%.1f BE", carbs / 12), color: .purple)
            }
        }
    }

    private func row(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(color).bold()
        }
    }

    // MARK: - Actions

    private func lookup(_ code: String) async {
        loading = true
        defer { loading = false }
        do {
            product = try await OpenFoodFactsService.lookup(barcode: code)
        } catch {
            errorMessage = "Das Produkt mit Barcode \(code) ist nicht in Open Food Facts hinterlegt."
            scannedCode = nil
        }
    }

    private func save() {
        guard let p = product else { return }
        let factor = portionGrams / 100.0
        let entry = FoodEntry(
            timestamp: timestamp,
            name: p.name,
            kind: kind,
            portionGrams: kind == .food ? portionGrams : nil,
            portionMilliliters: kind == .drink ? portionGrams : nil,
            calories: p.kcalPer100g * factor,
            carbsGrams: p.carbsPer100g * factor,
            source: .barcode,
            barcode: p.barcode
        )
        store.add(entry)
        dismiss()
        onComplete()
    }
}

// MARK: - VisionKit DataScanner wrapper

struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode()],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var didScan = false
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didScan else { return }
            for item in addedItems {
                if case let .barcode(code) = item, let payload = code.payloadStringValue {
                    didScan = true
                    onScan(payload)
                    dataScanner.stopScanning()
                    return
                }
            }
        }
    }
}
