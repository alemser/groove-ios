import SwiftUI
import UserNotifications

/// Register, update, and monitor the turntable's stylus/cartridge. Wear is
/// computed server-side from vinyl-format play duration
/// (`groove-catalog`'s `/catalog/stylus`) — nothing to configure beyond the
/// cartridge definition itself.
struct StylusView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = StylusModel()

    @State private var sourceMode: SourceMode = .catalog
    @State private var selectedCatalogID: Int64?
    @State private var customBrand = ""
    @State private var customModel = ""
    @State private var customProfile = ""
    @State private var customLifetimeText = ""
    @State private var isNew = true
    @State private var initialHoursText = ""
    @State private var isSaving = false
    @State private var isReplacing = false
    @State private var showReplaceConfirm = false
    @State private var didSyncForm = false
    @AppStorage("stylusAlertEnabled") private var stylusAlertEnabled = true
    @AppStorage("stylusAlertThresholdLeftPercent") private var stylusAlertThresholdLeftPercent = 15
    @AppStorage("stylusAlertLastProfileID") private var stylusAlertLastProfileID = 0

    enum SourceMode: String, CaseIterable, Identifiable {
        case catalog = "Catalog"
        case custom = "Custom"
        var id: String { rawValue }
    }

    var body: some View {
        Form {
            if let metrics = model.state?.metrics, model.state?.active == true {
                metricsSection(metrics)
            }
            stylusSection
            usageSection
            if model.state?.profile != nil {
                alertSection
            }
            if shouldShowReplacementAlert, let left = currentLifeLeftPercent {
                replacementAlertSection(leftPercent: left)
            }
            actionsSection
        }
        .scrollContentBackground(.hidden)
        .grooveScreenBackground()
        .navigationTitle("Stylus Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.configure(settings)
            if stylusAlertEnabled { await ensureNotificationPermissionIfNeeded() }
        }
        .onChange(of: model.phase) { _, phase in
            if phase == .loaded {
                syncFormIfNeeded()
                evaluateStylusAlert()
            }
        }
        .onChange(of: model.state?.metrics.wearPercent) { _, _ in evaluateStylusAlert() }
        .onChange(of: model.state?.profile?.id) { _, _ in evaluateStylusAlert() }
        .onChange(of: stylusAlertEnabled) { _, isEnabled in
            if isEnabled {
                Task { await ensureNotificationPermissionIfNeeded() }
            }
            evaluateStylusAlert()
        }
        .onChange(of: stylusAlertThresholdLeftPercent) { _, _ in evaluateStylusAlert() }
        .confirmationDialog("Replace Stylus", isPresented: $showReplaceConfirm, titleVisibility: .visible) {
            Button("Replace Stylus Now", role: .destructive) { Task { await doReplace() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current stylus will be archived and the usage counter reset to zero.")
        }
    }

    // MARK: - Metrics

    private func metricsSection(_ m: StylusMetrics) -> some View {
        Section("Usage") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Condition").font(.subheadline).foregroundStyle(Brand.muted)
                    Spacer()
                    Badge(text: conditionTitle(m.state), color: conditionColor(m.state), filled: true)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(Brand.border)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(wearGradient)
                            .frame(width: max(4, geo.size.width * min(CGFloat(m.wearPercent) / 100, 1)))
                    }
                    .frame(height: 8)
                }
                .frame(height: 8)
                Text(String(format: "%.1f%% worn", m.wearPercent))
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)

            InfoRow(label: "Vinyl hours (this stylus)", value: String(format: "%.1f h", m.vinylHoursSinceInstall))
            InfoRow(label: "Total stylus hours", value: String(format: "%.1f h", m.stylusHoursTotal))
            InfoRow(label: "Remaining", value: String(format: "%.1f h", m.remainingHours))
        }
    }

    private func conditionTitle(_ state: String) -> String {
        switch state {
        case "overdue": return "Overdue"
        case "soon": return "Replace Soon"
        case "plan": return "Plan Replacement"
        default: return "Healthy"
        }
    }

    private func conditionColor(_ state: String) -> Color {
        switch state {
        case "overdue": return Brand.err
        case "soon": return Brand.warn
        case "plan": return Brand.gold
        default: return Brand.ok
        }
    }

    private var wearGradient: LinearGradient {
        LinearGradient(colors: [Brand.ok, Brand.gold, Brand.warn, Brand.err], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Stylus definition

    private var stylusSection: some View {
        Section("Stylus") {
            Picker("Source", selection: $sourceMode) {
                ForEach(SourceMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if sourceMode == .catalog {
                Picker("Model", selection: $selectedCatalogID) {
                    Text("Select…").tag(Int64?.none)
                    ForEach(model.catalog) { item in
                        Text(item.displayLabel).tag(Optional(item.id))
                    }
                }
                .pickerStyle(.navigationLink)
            } else {
                TextField("Brand", text: $customBrand).autocorrectionDisabled()
                TextField("Model", text: $customModel).autocorrectionDisabled()
                TextField("Profile (e.g. Elliptical)", text: $customProfile).autocorrectionDisabled()
                HStack {
                    Text("Lifetime hours")
                    Spacer()
                    TextField("800", text: $customLifetimeText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }
        }
    }

    // MARK: - Usage at install

    private var usageSection: some View {
        Section {
            Toggle("Brand new stylus", isOn: $isNew)
            if !isNew {
                HStack {
                    Text("Hours already used")
                    Spacer()
                    TextField("0", text: $initialHoursText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }
        } header: {
            Text("Usage at Install")
        } footer: {
            Text("If the stylus was previously used, enter the hours already logged before installing it.")
                .foregroundStyle(Brand.muted)
        }
    }

    // MARK: - Notification alert

    private var alertSection: some View {
        Section {
            Toggle("Replacement alert", isOn: $stylusAlertEnabled)
            if stylusAlertEnabled {
                Stepper(value: $stylusAlertThresholdLeftPercent, in: 5...50, step: 1) {
                    HStack {
                        Text("Alert when life left is")
                        Spacer()
                        Text("\(stylusAlertThresholdLeftPercent)%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Brand.muted)
                    }
                }
            }
        } header: {
            Text("Notification")
        } footer: {
            Text(
                stylusAlertEnabled
                    ? "You will be warned when remaining stylus life reaches this threshold."
                    : "Enable to receive replacement reminders."
            )
            .foregroundStyle(Brand.muted)
        }
    }

    private func replacementAlertSection(leftPercent: Int) -> some View {
        Section {
            Label(
                "Stylus life reached the configured threshold (\(leftPercent)% left).",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(Brand.warn)
            Text("Recommendation: plan replacement now and use \"Replace Stylus Now\" after changing the stylus to reset tracking.")
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
        } header: {
            Text("Replacement Reminder")
        }
    }

    private var currentLifeLeftPercent: Int? {
        guard let wear = model.state?.metrics.wearPercent else { return nil }
        return Int(max(0, 100 - wear).rounded())
    }

    private var shouldShowReplacementAlert: Bool {
        guard model.state?.profile != nil, stylusAlertEnabled, let left = currentLifeLeftPercent else { return false }
        return left <= stylusAlertThresholdLeftPercent
    }

    private func evaluateStylusAlert() {
        guard stylusAlertEnabled,
              let profileID = model.state?.profile?.id,
              let left = currentLifeLeftPercent else { return }

        let profileIDInt = Int(profileID)
        if left <= stylusAlertThresholdLeftPercent {
            guard stylusAlertLastProfileID != profileIDInt else { return }
            stylusAlertLastProfileID = profileIDInt
            Task { await scheduleReplacementLocalNotification(leftPercent: left, profileID: profileIDInt) }
        } else if stylusAlertLastProfileID == profileIDInt {
            // Rearm the alert for the same profile if usage moves back above threshold.
            stylusAlertLastProfileID = 0
        }
    }

    private func ensureNotificationPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    private func scheduleReplacementLocalNotification(leftPercent: Int, profileID: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Stylus Replacement Reminder"
        content.body = "Only \(leftPercent)% stylus life left. Plan replacement soon."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "stylus-replacement-\(profileID)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await center.add(request)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            Button {
                Task { await doSave() }
            } label: {
                HStack {
                    Spacer()
                    if isSaving { ProgressView().tint(Brand.accent).padding(.trailing, 6) }
                    Text(isSaving ? "Saving…" : "Save Stylus Settings").fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(isSaving || isReplacing || !canSave)

            if model.state?.profile != nil {
                Button(role: .destructive) {
                    showReplaceConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        if isReplacing { ProgressView().padding(.trailing, 6) }
                        Text(isReplacing ? "Replacing…" : "Replace Stylus Now")
                        Spacer()
                    }
                }
                .disabled(isSaving || isReplacing)
            }
        } footer: {
            if let p = model.state?.profile {
                Text("Installed \(Format.absolute(p.installedAt)) · \(p.brand) \(p.model) (\(p.stylusProfile))")
                    .foregroundStyle(Brand.muted)
            } else if let error = model.actionError {
                Text(error).foregroundStyle(Brand.err)
            }
        }
    }

    private var canSave: Bool {
        switch sourceMode {
        case .catalog:
            return selectedCatalogID != nil
        case .custom:
            return !customBrand.trimmed.isEmpty && !customModel.trimmed.isEmpty
                && !customProfile.trimmed.isEmpty && Int(customLifetimeText.trimmed) != nil
        }
    }

    private func doSave() async {
        isSaving = true
        defer { isSaving = false }
        if await model.save(buildRequest()) {
            syncFormFromState()
        }
    }

    private func doReplace() async {
        isReplacing = true
        defer { isReplacing = false }
        if await model.replace(buildRequest()) {
            syncFormFromState()
        }
    }

    private func buildRequest() -> StylusSaveRequest {
        StylusSaveRequest(
            catalogId: sourceMode == .catalog ? selectedCatalogID : nil,
            brand: sourceMode == .custom ? customBrand.trimmed : nil,
            model: sourceMode == .custom ? customModel.trimmed : nil,
            stylusProfile: sourceMode == .custom ? customProfile.trimmed : nil,
            lifetimeHours: sourceMode == .custom ? Int(customLifetimeText.trimmed) : nil,
            initialUsedHours: (!isNew && !initialHoursText.trimmed.isEmpty) ? Double(initialHoursText.trimmed) : nil,
            isNew: isNew
        )
    }

    // MARK: - Form sync

    private func syncFormIfNeeded() {
        guard !didSyncForm else { return }
        syncFormFromState()
    }

    private func syncFormFromState() {
        didSyncForm = true
        guard let p = model.state?.profile else { return }
        if !p.isCustom, let cid = p.catalogId {
            sourceMode = .catalog
            selectedCatalogID = cid
        } else {
            sourceMode = .custom
            customBrand = p.brand
            customModel = p.model
            customProfile = p.stylusProfile
            customLifetimeText = String(p.lifetimeHours)
        }
        isNew = p.initialUsedHours <= 0
        initialHoursText = p.initialUsedHours > 0 ? String(format: "%.1f", p.initialUsedHours) : ""
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
