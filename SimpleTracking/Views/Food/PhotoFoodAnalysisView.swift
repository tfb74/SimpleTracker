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
    @State private var kindHint: FoodKind?
    @State private var analyzing = false
    @State private var items: [RecognizedFoodItem] = []
    @State private var diagnostics: AnalysisDiagnostics?
    @State private var errorMessage: String?
    @State private var timestamp = Date()

    // Live-Fortschritt während der Analyse
    @State private var progressLog: [ProgressEntry] = []
    @State private var currentStageMessage: String = ""
    @State private var currentStageIcon: String = "viewfinder"

    private struct ProgressEntry: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String?
        let isReasoning: Bool
    }

    var body: some View {
        NavigationStack {
            Group {
                if image == nil {
                    pickerSection
                } else if kindHint == nil {
                    kindSelectionSection
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
                    kindHint = nil
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

    // MARK: - Kind Selection

    private var kindSelectionSection: some View {
        VStack(spacing: 24) {
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                    .padding(.top, 20)
            }

            VStack(spacing: 6) {
                Text("Was ist auf dem Foto?")
                    .font(.title3.bold())
                Text("Der Hinweis verbessert die Erkennung.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                kindButton(title: "Essen", systemImage: "fork.knife", kind: .food, tint: .orange)
                kindButton(title: "Getränk", systemImage: "cup.and.saucer.fill", kind: .drink, tint: .blue)
            }
            .padding(.horizontal)

            Spacer()
        }
    }

    private func kindButton(title: String, systemImage: String, kind: FoodKind, tint: Color) -> some View {
        Button {
            kindHint = kind
            Task { await analyze() }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 32))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(tint.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(tint.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
        VStack(spacing: 14) {
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
            }

            // Aktueller Schritt prominent
            HStack(spacing: 10) {
                ProgressView().scaleEffect(0.85)
                Image(systemName: currentStageIcon)
                    .foregroundStyle(Color.accentColor)
                Text(currentStageMessage.isEmpty ? "Starte Analyse…" : currentStageMessage)
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)

            // Reasoning-Log: feste Höhe, intern scrollend, auto-scroll ans Ende
            reasoningLog
                .padding(.horizontal)

            Spacer(minLength: 0)
        }
        .padding(.vertical)
    }

    private var reasoningLog: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    if progressLog.isEmpty {
                        Text("KI-Verlauf erscheint hier…")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(progressLog) { entry in
                            progressEntryView(entry)
                                .id(entry.id)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(10)
            }
            .frame(height: 170)              // ~5-7 Zeilen, kompakt
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            // Sanfter Verlauf oben/unten als visueller Scroll-Hint
            .mask(
                LinearGradient(
                    colors: [.clear, .black, .black, .black, .black, .black, .clear],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .onChange(of: progressLog.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func progressEntryView(_ entry: ProgressEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.icon)
                .font(.caption)
                .foregroundStyle(entry.isReasoning ? Color.purple : Color.green)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                if let detail = entry.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .italic(entry.isReasoning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(entry.isReasoning ? Color.purple.opacity(0.08) : Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
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
        kindHint = nil
    }

    private func analyze() async {
        guard let image else { return }
        analyzing = true
        progressLog = []
        currentStageMessage = ""
        currentStageIcon = "viewfinder"
        defer { analyzing = false }
        do {
            let (result, diag) = try await FoodPhotoAnalyzer.analyzeDetailed(
                image: image,
                kindHint: kindHint,
                progress: { stage in
                    await handleProgress(stage)
                }
            )
            items = result
            diagnostics = diag
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handleProgress(_ stage: AnalysisStage) async {
        // Aktueller Stage oben prominent anzeigen
        currentStageMessage = stage.displayMessage
        currentStageIcon    = stage.systemImage

        // Bei "Result"-Stages: ins Verlaufsprotokoll aufnehmen
        switch stage {
        case .visionCompleted(let labels):
            withAnimation(.easeOut(duration: 0.25)) {
                progressLog.append(ProgressEntry(
                    icon: "viewfinder",
                    title: "Bildlabels erkannt",
                    detail: labels.prefix(5).joined(separator: ", "),
                    isReasoning: false
                ))
            }

        case .llmReasoningResult(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            withAnimation(.easeOut(duration: 0.25)) {
                progressLog.append(ProgressEntry(
                    icon: "brain",
                    title: "Überlegung",
                    detail: trimmed.isEmpty ? nil : trimmed,
                    isReasoning: true
                ))
            }

        case .llmVerifyingResult(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            withAnimation(.easeOut(duration: 0.25)) {
                progressLog.append(ProgressEntry(
                    icon: "checkmark.circle",
                    title: "Selbstprüfung",
                    detail: trimmed.isEmpty ? nil : trimmed,
                    isReasoning: true
                ))
            }

        default:
            // Andere Stages werden nur in der oberen Statuszeile angezeigt
            break
        }
    }

    private func deleteItem(id: RecognizedFoodItem.ID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            items.removeAll { $0.id == id }
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func saveAll() {
        let kind = kindHint ?? .food
        for item in items {
            let entry = FoodEntry(
                timestamp: timestamp,
                name: item.name,
                kind: kind,
                portionGrams: kind == .food ? Double(item.portionGrams) : nil,
                portionMilliliters: kind == .drink ? Double(item.portionGrams) : nil,
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
