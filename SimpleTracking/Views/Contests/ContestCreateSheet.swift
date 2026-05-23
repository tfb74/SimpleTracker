import SwiftUI

struct ContestCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ContestService.self) private var contestService
    @Environment(TeamService.self) private var teamService

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var selectedType: ContestType = .dailyStreak
    @State private var selectedMetric: ContestMetric = .steps
    @State private var targetValue: Double = 10000
    @State private var startDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var endDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var scope: ContestScope = .friends
    @State private var selectedTeamID: String?

    @State private var isCreating = false
    @State private var errorMessage: String?

    private var allowedMetrics: [ContestMetric] {
        ContestMetric.allowed(for: selectedType)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(lt("Titel")) {
                    TextField(lt("z. B. Mai-Schritt-Challenge"), text: $title)
                    TextField(lt("Beschreibung (optional)"), text: $description, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section(lt("Typ")) {
                    Picker(lt("Typ"), selection: $selectedType) {
                        ForEach(ContestType.allCases) { type in
                            Label(type.displayName, systemImage: type.systemImage).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedType) { _, _ in
                        // Wenn aktuelle Metrik nicht mehr passt, auf erste erlaubte wechseln
                        if !allowedMetrics.contains(selectedMetric) {
                            selectedMetric = allowedMetrics.first ?? .steps
                        }
                    }
                    Text(selectedType.explanation)
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section(lt("Metrik & Ziel")) {
                    Picker(lt("Metrik"), selection: $selectedMetric) {
                        ForEach(allowedMetrics, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if selectedType != .scoreRace {
                        Stepper(value: $targetValue, in: 100...1_000_000, step: stepperStep) {
                            HStack {
                                Text(targetValueLabel)
                                Spacer()
                                Text(formattedTarget)
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }

                Section(lt("Zeitraum")) {
                    DatePicker(lt("Start"), selection: $startDate, displayedComponents: [.date])
                    DatePicker(lt("Ende"), selection: $endDate, in: startDate..., displayedComponents: [.date])
                }

                Section(lt("Wer macht mit")) {
                    Picker(lt("Scope"), selection: $scope) {
                        Text(lt("Freunde")).tag(ContestScope.friends)
                        if !teamService.myTeams.isEmpty {
                            Text(lt("Team")).tag(ContestScope.team)
                            Text(lt("Firma")).tag(ContestScope.company)
                        }
                    }
                    .pickerStyle(.segmented)

                    if scope == .team || scope == .company {
                        if teamService.myTeams.isEmpty {
                            Text(lt("Du bist in keinem Team. Lege erst eines an unter Mehr → Teams."))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Picker(lt("Team auswählen"), selection: $selectedTeamID) {
                                Text(lt("Bitte wählen")).tag(String?.none)
                                ForEach(teamService.myTeams) { team in
                                    Text(team.name).tag(String?.some(team.id))
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(lt("Neuer Contest"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lt("Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lt("Erstellen")) {
                        Task { await create() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canCreate || isCreating)
                }
            }
        }
    }

    private var canCreate: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard endDate > startDate else { return false }
        if scope != .friends && selectedTeamID == nil { return false }
        return true
    }

    private var stepperStep: Double {
        switch selectedMetric {
        case .steps:        return 1000
        case .distanceKm:   return 1
        case .calories:     return 100
        case .workoutScore: return 50
        }
    }

    private var targetValueLabel: String {
        switch selectedType {
        case .dailyStreak:                       return lt("Tagesziel")
        case .cumulativeTotal, .calorieGoal:     return lt("Gesamtziel")
        case .scoreRace:                         return lt("Ziel")
        }
    }

    private var formattedTarget: String {
        switch selectedMetric {
        case .distanceKm: return String(format: "%.1f km", targetValue)
        default:          return "\(Int(targetValue)) \(selectedMetric.unit)"
        }
    }

    private func create() async {
        isCreating = true
        errorMessage = nil
        do {
            _ = try await contestService.createContest(
                title: title.trimmingCharacters(in: .whitespaces),
                description: description.trimmingCharacters(in: .whitespaces),
                type: selectedType,
                metric: selectedMetric,
                targetValue: selectedType == .scoreRace ? 0 : targetValue,
                startDate: startDate,
                endDate: endDate,
                scope: scope,
                teamID: selectedTeamID
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isCreating = false
    }
}

// MARK: - Join Sheet

struct ContestJoinSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ContestService.self) private var contestService

    var prefilledCode: String? = nil

    @State private var code: String = ""
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.badge.key")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 20)

                VStack(spacing: 6) {
                    Text(lt("Contest beitreten"))
                        .font(.title2.bold())
                    Text(lt("Gib den Invite-Code des Contests ein."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TextField("ABCD-EF12", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }

                Button {
                    Task { await join() }
                } label: {
                    Group {
                        if isJoining { ProgressView() }
                        else         { Text(lt("Beitreten")) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.count < 8 || isJoining)
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lt("Abbrechen")) { dismiss() }
                }
            }
            .task {
                if let prefilledCode { code = prefilledCode }
            }
        }
    }

    private func join() async {
        isJoining = true
        errorMessage = nil
        do {
            _ = try await contestService.joinContest(inviteCode: code)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isJoining = false
    }
}
