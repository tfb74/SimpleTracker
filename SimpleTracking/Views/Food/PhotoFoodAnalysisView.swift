import SwiftUI
import PhotosUI

struct PhotoFoodAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FoodLogStore.self) private var store

    let defaultDate: Date
    let onComplete: () -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var analyzing = false
    @State private var items: [RecognizedFoodItem] = []
    @State private var diagnostics: AnalysisDiagnostics?
    @State private var errorMessage: String?
    @State private var timestamp = Date()

    var body: some View {
        NavigationStack {
            Group {
                if image == nil {
                    pickerSection
                } else if analyzing {
                    analyzingSection
                } else if !items.isEmpty {
                    resultSection
                } else {
                    errorSection
                }
            }
            .navigationTitle("Foto-Analyse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                if !items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Alle speichern") { saveAll() }
                    }
                }
            }
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                Task { await loadPhoto(from: newItem) }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { uiImage in
                    image = uiImage
                    Task { await analyze() }
                }
            }
        }
    }

    // MARK: - Picker

    private var pickerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 40)

            Text(FoodPhotoAnalyzer.isLLMAvailable
                 ? "Apple Intelligence analysiert dein Foto und schätzt Kalorien & Kohlenhydrate."
                 : "Nur grobe Schätzung möglich — dein Gerät unterstützt Apple Intelligence nicht.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            availabilityBadge

            VStack(spacing: 12) {
                Button {
                    showCamera = true
                } label: {
                    Label("Foto aufnehmen", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity).padding()
                }
                .buttonStyle(.borderedProminent)

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Aus Mediathek wählen", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity).padding()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            Spacer()
        }
    }

    private var availabilityBadge: some View {
        let available = FoodPhotoAnalyzer.isLLMAvailable
        return HStack(spacing: 6) {
            Image(systemName: available ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
            Text(available ? "Apple Intelligence verfügbar (iOS \(UIDevice.current.systemVersion))"
                           : "Apple Intelligence nicht verfügbar — Fallback auf Vision-Heuristik")
                .font(.caption)
        }
        .foregroundStyle(available ? .green : .orange)
        .padding(.horizontal)
    }

    private var analyzingSection: some View {
        VStack(spacing: 16) {
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
            }
            ProgressView(FoodPhotoAnalyzer.isLLMAvailable
                         ? "Apple Intelligence erkennt Lebensmittel…"
                         : "Analysiere Bild…")
                .padding()
            Spacer()
        }
    }

    private var resultSection: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let image {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                }

                if let d = diagnostics {
                    diagnosticsCard(d)
                }

                DatePicker("Zeit", selection: $timestamp).padding(.horizontal)

                HStack {
                    Text("\(items.count) \(items.count == 1 ? "Bestandteil" : "Bestandteile") erkannt")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("Wischen oder Mülleimer zum Entfernen")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding(.horizontal)

                VStack(spacing: 0) {
                    ForEach($items) { $item in
                        RecognizedItemRow(
                            item: $item,
                            onDelete: { deleteItem(id: item.id) }
                        )
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        Divider().padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }

    private func diagnosticsCard(_ d: AnalysisDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Diagnose", systemImage: "stethoscope").font(.caption.bold())

            diagRow("iOS", d.iOSVersion)
            diagRow("LLM verfügbar", d.llmAvailable ? "ja" : "nein")
            diagRow("LLM verwendet", d.llmUsed ? "ja (\(d.llmMillis) ms)"
                                               : (d.llmRequested ? "versucht, kein Ergebnis"
                                                                 : "nicht versucht"))
            diagRow("Fallback", d.fallbackUsed ? "Heuristik" : "–")
            diagRow("Vision-Labels", d.visionLabels.isEmpty
                    ? "(keine)"
                    : "\(d.visionLabels.joined(separator: ", ")) · \(d.visionMillis) ms")
            if let err = d.llmError {
                diagRow("LLM-Fehler", err).foregroundStyle(.red)
            }
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.purple.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    private func diagRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value).foregroundStyle(.primary)
            Spacer()
        }
    }

    private var errorSection: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "Nichts erkannt",
                systemImage: "questionmark.circle",
                description: Text(errorMessage ?? "Das Foto konnte nicht ausgewertet werden.")
            )
            if let d = diagnostics {
                diagnosticsCard(d)
            }
        }
    }

    // MARK: - Actions

    private func loadPhoto(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let ui = UIImage(data: data) else { return }
        image = ui
        await analyze()
    }

    private func analyze() async {
        guard let image else { return }
        analyzing = true
        defer { analyzing = false }
        do {
            let (result, diag) = try await FoodPhotoAnalyzer.analyzeDetailed(image: image)
            items = result
            diagnostics = diag
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteItem(id: RecognizedFoodItem.ID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            items.removeAll { $0.id == id }
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func saveAll() {
        for item in items {
            let entry = FoodEntry(
                timestamp: timestamp,
                name: item.name,
                kind: .food,
                portionGrams: Double(item.portionGrams),
                calories: Double(item.calories),
                carbsGrams: Double(item.carbsGrams),
                source: .photo
            )
            store.add(entry)
        }
        dismiss()
        onComplete()
    }
}

struct RecognizedItemRow: View {
    @Binding var item: RecognizedFoodItem
    let onDelete: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            // Roter Lösch-Hintergrund, sichtbar beim Swipen nach links.
            HStack {
                Spacer()
                Image(systemName: "trash.fill")
                    .foregroundStyle(.white)
                    .padding(.trailing, 20)
            }
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Name", text: $item.name).font(.headline)
                    HStack {
                        numberField("Portion", value: Binding(
                            get: { Double(item.portionGrams) },
                            set: { item.portionGrams = Int($0) }
                        ), unit: "g")
                        numberField("kcal", value: Binding(
                            get: { Double(item.calories) },
                            set: { item.calories = Int($0) }
                        ), unit: "")
                        numberField("KH", value: Binding(
                            get: { Double(item.carbsGrams) },
                            set: { item.carbsGrams = Int($0) }
                        ), unit: "g")
                    }
                    Text(String(format: "%.1f BE", Double(item.carbsGrams) / 12))
                        .font(.caption).foregroundStyle(.purple)
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundStyle(.red)
                        .frame(width: 36, height: 36)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .offset(x: dragOffset)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { v in
                        // Nur nach links erlauben
                        dragOffset = min(0, max(-100, v.translation.width))
                    }
                    .onEnded { v in
                        if v.translation.width < -60 {
                            onDelete()
                        } else {
                            withAnimation(.spring(response: 0.3)) { dragOffset = 0 }
                        }
                    }
            )
        }
    }

    private func numberField(_ label: String, value: Binding<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 3) {
                TextField("0", value: value, format: .number)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                if !unit.isEmpty { Text(unit).font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: - Camera Picker

struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage) -> Void
        init(onPick: @escaping (UIImage) -> Void) { self.onPick = onPick }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let img = info[.originalImage] as? UIImage { onPick(img) }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
