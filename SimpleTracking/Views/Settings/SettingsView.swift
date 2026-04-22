import SwiftUI
import PhotosUI
import UIKit

struct SettingsView: View {
    @Environment(UserSettings.self)     private var settings
    @Environment(HealthKitService.self)  private var healthKit
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(AdService.self)         private var ads
    @State private var mockService  = MockDataService.shared
    @State private var isResetting  = false
    @State private var expandedWheel: String? = nil   // "age" | "weight" | "height" | nil
    @State private var appearanceExpanded = false
    @State private var languageExpanded = false
    @State private var unitsExpanded = false
    @State private var avatarPickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DisclosureGroup(
                        isExpanded: $appearanceExpanded,
                        content: {
                            ForEach(AppColorScheme.allCases, id: \.self) { scheme in
                                colorSchemeRow(scheme)
                            }
                        },
                        label: {
                            HStack {
                                Text(lt("Erscheinungsbild"))
                                Spacer()
                                Text(settings.colorScheme.displayName)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    )
                }

                Section {
                    DisclosureGroup(
                        isExpanded: $languageExpanded,
                        content: {
                            ForEach(AppLanguage.allCases, id: \.self) { language in
                                languageRow(language)
                            }
                        },
                        label: {
                            HStack {
                                Text(lt("Sprachen"))
                                Spacer()
                                Text(settings.appLanguage.displayName)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    )
                }

                Section {
                    DisclosureGroup(
                        isExpanded: $unitsExpanded,
                        content: {
                            ForEach(UnitPreference.allCases, id: \.self) { pref in
                                unitPreferenceRow(pref)
                            }
                        },
                        label: {
                            HStack {
                                Text(lt("Einheiten"))
                                Spacer()
                                Text(settings.unitPreference.displayName)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    )
                }

                // MARK: Profile (für Score-Berechnung)
                Section {
                    profileIdentityEditor
                    profileWheel(
                        id: "age",
                        label: lt("Alter"), icon: "person.fill", unit: lt("Jahre"),
                        range: 1...199, defaultValue: 25,
                        value: Binding(
                            get: { settings.ageYears == 0 ? 25 : settings.ageYears },
                            set: { settings.ageYears = $0 }
                        )
                    )
                    profileWheel(
                        id: "weight",
                        label: lt("Gewicht"), icon: "scalemass.fill", unit: "kg",
                        range: 1...500, defaultValue: 80,
                        value: Binding(
                            get: { settings.weightKg == 0 ? 80 : Int(settings.weightKg.rounded()) },
                            set: { settings.weightKg = Double($0) }
                        )
                    )
                    profileWheel(
                        id: "height",
                        label: lt("Größe"), icon: "ruler.fill", unit: "cm",
                        range: 30...250, defaultValue: 150,
                        value: Binding(
                            get: { settings.heightCm == 0 ? 150 : Int(settings.heightCm.rounded()) },
                            set: { settings.heightCm = Double($0) }
                        )
                    )
                    if settings.profileComplete {
                        HStack {
                            Text("BMI")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f", settings.bmi))
                                .bold()
                            Text("–")
                            Text(settings.bmiCategory.label)
                                .foregroundStyle(settings.bmiCategory.color)
                                .bold()
                        }
                        .font(.subheadline)
                    }
                } header: {
                    Text(lt("Profil & Score"))
                } footer: {
                    Text(lt("Alter und Gewicht beeinflussen deinen persönlichen Fitness-Score und die Kalorienberechnung. Falls in Apple Health hinterlegt, werden Alter, Geschlecht und Gewicht automatisch von dort übernommen – die Felder hier dienen als Fallback."))
                }

                // MARK: HealthKit
                Section {
                    if healthKit.importInProgress {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(lt("Import läuft …"), systemImage: "square.and.arrow.down")
                                .font(.headline)
                            Text(healthKit.importStatus)
                                .font(.subheadline).foregroundStyle(.secondary)
                            ProgressView(value: healthKit.importProgress)
                                .tint(.accentColor)
                                .animation(.easeInOut, value: healthKit.importProgress)
                            Text(lf("%d importiert, davon %d mit Route", healthKit.importedCount, healthKit.importedRouteCount))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    } else {
                        // Primary action — prominent
                        Button {
                            Task { await healthKit.fullImportFromHealth() }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lt("Alle Workouts aus Health importieren"))
                                        .font(.body.weight(.semibold))
                                    Text(lt("Liest den gesamten Verlauf aus Apple Health"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if !healthKit.importStatus.isEmpty && healthKit.importedCount > 0 {
                            Label(healthKit.importStatus, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green).font(.caption)
                        }

                        // Per-source breakdown — THE diagnostic. If an
                        // expected source (Garmin Connect, Adidas Running…) is
                        // missing here, iOS has silently denied read access
                        // for that source. The buttons below open the right
                        // Settings page with one tap.
                        if !healthKit.importSourceBreakdown.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(lt("Quellen aus Apple Health"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(healthKit.importSourceBreakdown, id: \.name) { row in
                                    HStack {
                                        Image(systemName: "app.badge").foregroundStyle(.tertiary)
                                        Text(row.name).font(.caption)
                                        Spacer()
                                        Text("\(row.count)").font(.caption.monospacedDigit()).bold()
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Button {
                            Task { try? await healthKit.requestAuthorization() }
                        } label: {
                            Label(lt("HealthKit-Berechtigungen anfordern"), systemImage: "heart.text.square")
                        }

                        // Deep link into iPhone Settings → Health → Apps →
                        // SimpleTracking, which is the ONLY place the user
                        // can flip read permissions after the first prompt.
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label(lt("iPhone-Einstellungen öffnen"), systemImage: "gearshape")
                        }
                    }
                } header: {
                    Text(lt("Gesundheit"))
                } footer: {
                    Text(lt("Der Import liest **alle** Workouts aus Apple Health – auch die, die vorher von anderen Apps (z. B. Strava, Runtastic, Apple Workout) aufgezeichnet wurden.\n\nRouten (GPS) werden mit übernommen, sofern die Quell-App sie in Health gespeichert hat.\n\nFalls Workouts fehlen: iPhone-Einstellungen → Health → Datenzugriff & Geräte → SimpleTracking → alle Lese-Schalter (Workouts, Strecken/Routen, Distanz, Herzfrequenz, …) aktivieren und Import erneut starten."))
                }

                // MARK: Daten zurücksetzen
                Section {
                    if isResetting {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(mockService.statusMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ProgressView(value: mockService.progress)
                                .tint(.accentColor)
                                .animation(.easeInOut, value: mockService.progress)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Button(role: .destructive) {
                            Task {
                                isResetting = true
                                await mockService.deleteAll()
                                await healthKit.importAllWorkouts()
                                isResetting = false
                            }
                        } label: {
                            Label(lt("Alle Workouts löschen"), systemImage: "trash")
                        }

                        Button(role: .destructive) {
                            FoodLogStore.shared.removeAll()
                        } label: {
                            Label(lt("Alle Ernährung löschen"), systemImage: "trash")
                        }
                    }
                } header: {
                    Text(lt("Daten zurücksetzen"))
                } footer: {
                    Text(lt("Löscht alle von SimpleTracking in Apple Health geschriebenen Workouts bzw. alle lokal gespeicherten Ernährungs-Einträge. Kann nicht rückgängig gemacht werden."))
                }

                // MARK: Achievements
                Section {
                    NavigationLink(destination: AchievementsView()) {
                        Label(lt("Erfolge & Bestenlisten"), systemImage: "trophy.fill")
                    }
                    Toggle(isOn: Binding(
                        get: { settings.gameCenterSyncEnabled },
                        set: { newValue in
                            settings.gameCenterSyncEnabled = newValue
                            if newValue {
                                Task { await gameCenter.authenticate() }
                            }
                        }
                    )) {
                        Label(lt("Mit Game Center synchronisieren"), systemImage: "gamecontroller")
                    }
                    if settings.gameCenterSyncEnabled {
                        HStack {
                            Text(lt("Status"))
                            Spacer()
                            Text(gameCenter.isAuthenticated
                                 ? lf("Angemeldet als %@", gameCenter.playerName)
                                 : lt("Nicht angemeldet"))
                                .foregroundStyle(gameCenter.isAuthenticated ? .green : .secondary)
                                .font(.caption)
                        }
                    }
                } footer: {
                    Text(lt("Erfolge werden immer lokal gespeichert. Mit aktivierter Synchronisation werden sie zusätzlich an Game Center übertragen, sobald der Dienst freigeschaltet ist."))
                }

                Section {
                    LabeledContent(lt("Wöchentliche Vollbild-Ad"), value: ads.weeklyInterstitialSummary)
                    LabeledContent(lt("Status"), value: ads.interstitialStatusLabel)
                    LabeledContent(lt("Skips übrig"), value: "\(ads.weeklyInterstitialSkipsRemaining)/\(AdService.weeklyInterstitialSkipLimit)")
                    LabeledContent(lt("Zuletzt gezeigt"), value: ads.lastWeeklyInterstitialShownLabel)

                    #if DEBUG
                    Button {
                        ads.forceDebugWeeklyInterstitialPrompt()
                    } label: {
                        Label(lt("Ankündigung testen"), systemImage: "play.rectangle")
                    }

                    Button(role: .destructive) {
                        ads.resetWeeklyInterstitialState()
                    } label: {
                        Label(lt("Werbe-Status zurücksetzen"), systemImage: "arrow.counterclockwise")
                    }
                    #endif
                } header: {
                    Text(lt("Werbung"))
                } footer: {
                    Text(lt("Die Vollbild-Ad wird maximal einmal pro Kalenderwoche gezeigt. Vorher erscheint ein Hinweis; bis zu drei Mal pro Woche darfst du verschieben."))
                }

                // MARK: Info
                Section(lt("Info")) {
                    LabeledContent(lt("Version"), value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    LabeledContent(lt("Build"),   value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                }
            }
            .tint(.primary)
            .appChrome(title: lt("Einstellungen"), accent: .indigo, metrics: headerMetrics)
            .onChange(of: avatarPickerItem) { _, newItem in
                guard let newItem else { return }
                Task { await loadAvatar(from: newItem) }
            }
        }
    }

    private var headerMetrics: [AppHeaderMetric] {
        let bestScore = healthKit.workouts.map { $0.score(settings: settings).displayScore }.max()

        return [
            AppHeaderMetric(
                title: "BMI",
                value: settings.profileComplete ? String(format: "%.1f", settings.bmi) : "--",
                systemImage: "figure",
                tint: .indigo
            ),
            AppHeaderMetric(
                title: "Bester Score",
                value: bestScore.map(String.init) ?? "--",
                systemImage: "star.fill",
                tint: .orange
            )
        ]
    }

    private var profileIdentityEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                UserAvatarView(
                    size: 72,
                    name: profileDisplayName,
                    photoData: settings.avatarImageData,
                    preset: settings.avatarPreset,
                    fallbackImage: gameCenter.isAuthenticated ? gameCenter.playerAvatar : nil
                )

                VStack(alignment: .leading, spacing: 10) {
                    TextField(lt("Name"), text: Binding(
                        get: { settings.profileName },
                        set: { settings.profileName = $0 }
                    ))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()

                    HStack(spacing: 10) {
                        PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                            Image(systemName: "photo.badge.plus")
                                .font(.headline)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(lt("Foto wählen"))

                        if settings.avatarImageData != nil {
                            Button(role: .destructive) {
                                settings.avatarImageData = nil
                            } label: {
                                Image(systemName: "trash")
                                    .font(.headline)
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel(lt("Foto entfernen"))
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(lt("Avatar"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(ProfileAvatarPreset.allCases, id: \.self) { preset in
                            avatarPresetChip(preset)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var profileDisplayName: String {
        let gameCenterName = gameCenter.isAuthenticated ? gameCenter.playerName : UIDevice.current.name
        return settings.effectiveProfileName(fallbackName: gameCenterName)
    }

    private func avatarPresetChip(_ preset: ProfileAvatarPreset) -> some View {
        let isSelected = settings.avatarPreset == preset

        return Button {
            settings.avatarPreset = preset
        } label: {
            ZStack(alignment: .topTrailing) {
                UserAvatarView(
                    size: 58,
                    name: profileDisplayName,
                    photoData: nil,
                    preset: preset,
                    fallbackImage: nil
                )
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSelected ? preset.accentColor : Color.clear,
                            lineWidth: 3
                        )
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white, preset.accentColor)
                        .background(Color(.systemBackground), in: Circle())
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func languageRow(_ language: AppLanguage) -> some View {
        let isSelected = settings.appLanguage == language

        return Button {
            settings.appLanguage = language
        } label: {
            HStack {
                Text(language.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func colorSchemeRow(_ scheme: AppColorScheme) -> some View {
        let isSelected = settings.colorScheme == scheme

        return Button {
            settings.colorScheme = scheme
        } label: {
            HStack {
                Label(scheme.displayName, systemImage: scheme.systemImage)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private func unitPreferenceRow(_ preference: UnitPreference) -> some View {
        let isSelected = settings.unitPreference == preference

        return Button {
            settings.unitPreference = preference
        } label: {
            HStack {
                Text(preference.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    // MARK: - Profile Wheel Helper

    @ViewBuilder
    private func profileWheel(id: String,
                              label: String, icon: String, unit: String,
                              range: ClosedRange<Int>, defaultValue: Int,
                              value: Binding<Int>) -> some View {
        let isExpanded = expandedWheel == id

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                expandedWheel = isExpanded ? nil : id
            }
        } label: {
            HStack {
                Label(label, systemImage: icon)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(value.wrappedValue) \(unit)")
                    .font(.callout.bold())
                    .foregroundStyle(isExpanded ? Color.accentColor : .secondary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }

        if isExpanded {
            Picker(label, selection: value) {
                ForEach(range, id: \.self) { n in
                    Text("\(n) \(unit)").tag(n)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 130)
            .clipped()
            .onAppear {
                if value.wrappedValue == 0 { value.wrappedValue = defaultValue }
            }
        }
    }

    private func loadAvatar(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let preparedData = image.preparedAvatarData() else { return }

        settings.avatarImageData = preparedData
    }
}
