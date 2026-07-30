import SwiftUI
import ServiceManagement
import OSLog

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, sessions, updates, account, about

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .sessions: "Sessions"
        case .updates: "Updates"
        case .account: "Account"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gear"
        case .sessions: "person.2.fill"
        case .updates: "arrow.triangle.2.circlepath"
        case .account: "person.crop.circle"
        case .about: "info.circle"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: .green
        case .sessions: .purple
        case .updates: .blue
        case .account: .red
        case .about: .orange
        }
    }
}

private struct SettingsIconBadge: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.callout).fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color, in: RoundedRectangle(cornerRadius: 5))
    }
}

struct SettingsView: View {
    // UpdateService still uses legacy ObservableObject; migrate to @Observable
    // and switch this to @Environment(UpdateService.self) when touching that file.
    @Environment(AppState.self) var appState
    @EnvironmentObject var updateService: UpdateService
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label {
                    Text(tab.label)
                } icon: {
                    SettingsIconBadge(systemImage: tab.systemImage, color: tab.iconColor)
                }
                .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 160, max: 200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedTab.label)
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.xs)
                    .padding(.leading, Spacing.xl)

                switch selectedTab {
                case .general:
                    GeneralTab()
                        .environment(appState)
                case .sessions:
                    SessionsTab()
                        .environment(appState)
                case .updates:
                    UpdatesTab()
                        .environmentObject(updateService)
                case .account:
                    AccountTab()
                        .environment(appState)
                case .about:
                    AboutTab()
                        .environment(appState)
                }
            }
            .padding(.horizontal)
            .navigationTitle("")
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .navigationSplitViewStyle(.balanced)
        .background(SettingsWindowAccessor())
        .frame(width: 580, height: 380)
    }
}

struct GeneralTab: View {
    @Environment(AppState.self) var appState
    @AppStorage(AppStorageKeys.launchAtLogin) private var launchAtLogin = AppStorageKeys.Defaults.launchAtLogin
    @AppStorage(AppStorageKeys.refreshInterval) private var refreshInterval: Double = AppStorageKeys.Defaults.refreshInterval
    @AppStorage(AppStorageKeys.sessionActivityThreshold) private var sessionActivityThreshold: Double = AppStorageKeys.Defaults.sessionActivityThreshold
    @AppStorage(AppStorageKeys.menuBarSlot1) private var menuBarSlot1: MenuBarSlot = AppStorageKeys.Defaults.menuBarSlot1
    @AppStorage(AppStorageKeys.menuBarSlot2) private var menuBarSlot2: MenuBarSlot = AppStorageKeys.Defaults.menuBarSlot2

    private let logger = Logger(subsystem: "com.ccinfo.app", category: "Settings")

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled: enabled)
                    }

                Picker("Auto-refresh", selection: $refreshInterval) {
                    Text("Manual").tag(0.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                    Text("10 minutes").tag(600.0)
                }
                .onChange(of: refreshInterval) { _, _ in
                    appState.updateRefreshInterval()
                }

                Picker("Session Activity", selection: $sessionActivityThreshold) {
                    Text("5 minutes").tag(300.0)
                    Text("10 minutes").tag(600.0)
                    Text("30 minutes").tag(1800.0)
                    Text("1 hour").tag(3600.0)
                    Text("4 hours").tag(14400.0)
                }
                .onChange(of: sessionActivityThreshold) { _, _ in
                    appState.updateSessionActivityThreshold()
                }
            }

            Section("MenuBar Display") {
                Picker("Slot 1", selection: $menuBarSlot1) {
                    ForEach(MenuBarSlot.allCases, id: \.self) { slot in
                        Text(slot.displayName).tag(slot)
                    }
                }
                .onChange(of: menuBarSlot1) { _, newValue in
                    if newValue == menuBarSlot2 {
                        menuBarSlot2 = MenuBarSlot.allCases.first { $0 != newValue } ?? .contextWindow
                    }
                }

                Picker("Slot 2", selection: $menuBarSlot2) {
                    ForEach(MenuBarSlot.allCases, id: \.self) { slot in
                        Text(slot.displayName).tag(slot)
                    }
                }
                .onChange(of: menuBarSlot2) { _, newValue in
                    if newValue == menuBarSlot1 {
                        menuBarSlot1 = MenuBarSlot.allCases.first { $0 != newValue } ?? .contextWindow
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Failed to update launch at login: \(error.localizedDescription)")
            // Revert the toggle on failure
            launchAtLogin = !enabled
        }
    }
}

struct SessionsTab: View {
    @Environment(AppState.self) var appState

    @FocusState private var focusedSlug: String?
    @State private var pendingResetSlug: String?
    @State private var pendingClearOrphans = false

    var body: some View {
        let activeSlugs = Set(appState.activeSessions.map(\.projectDirectory))
        let allSlugs = activeSlugs.union(appState.customSessionNameStore.entries.keys)
        let activeSorted = activeSlugs.sorted()
        let orphanedSorted = allSlugs.subtracting(activeSlugs).sorted()

        Group {
            if activeSlugs.isEmpty && appState.customSessionNameStore.entries.isEmpty {
                emptyState
            } else {
                Form {
                    Section("Active Sessions") {
                        ForEach(activeSorted, id: \.self) { slug in
                            sessionRow(slug)
                        }
                    }
                    if !orphanedSorted.isEmpty {
                        Section {
                            ForEach(orphanedSorted, id: \.self) { slug in
                                sessionRow(slug)
                            }
                        } header: {
                            HStack {
                                Text("Custom Names without Active Session")
                                Spacer()
                                Button {
                                    pendingClearOrphans = true
                                } label: {
                                    Label("Clear orphans", systemImage: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .onChange(of: focusedSlug) { oldSlug, _ in
            // Skip when the user merely tabbed through a row without typing —
            // the rename model only holds a draft once `setDraft` has been called.
            guard let oldSlug,
                  appState.sessionRenameModel.hasDraft(for: oldSlug) else { return }
            // Don't silently clear an existing custom name on blur. Force the
            // user through the explicit Reset path (with confirmation dialog)
            // so a stray Backspace + Tab cannot wipe a persisted name.
            let trimmedDraft = appState.sessionRenameModel.draft(for: oldSlug)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let alreadyPersisted = appState.customSessionNameStore.customName(for: oldSlug) != nil
            if trimmedDraft.isEmpty && alreadyPersisted {
                appState.sessionRenameModel.discard(slug: oldSlug)
                return
            }
            appState.sessionRenameModel.commitDraft(for: oldSlug)
        }
        .confirmationDialog(
            Text("Reset custom name?"),
            isPresented: Binding(
                get: { pendingResetSlug != nil },
                set: { if !$0 { pendingResetSlug = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingResetSlug
        ) { slug in
            Button("Reset to Default", role: .destructive) {
                appState.sessionRenameModel.reset(slug: slug)
                pendingResetSlug = nil
            }
            Button("Cancel", role: .cancel) {
                pendingResetSlug = nil
            }
        } message: { _ in
            Text("This will remove the custom name. The default project name will be shown again.")
        }
        .confirmationDialog(
            Text("Clear all orphans?"),
            isPresented: $pendingClearOrphans,
            titleVisibility: .visible
        ) {
            Button("Clear orphans", role: .destructive) {
                let active = Set(appState.activeSessions.map(\.projectDirectory))
                appState.customSessionNameStore.pruneOrphans(activeSlugs: active)
                pendingClearOrphans = false
            }
            Button("Cancel", role: .cancel) {
                pendingClearOrphans = false
            }
        } message: {
            Text("This will remove every custom name whose project is no longer active.")
        }
    }

    private func sessionRow(_ slug: String) -> some View {
        LabeledContent {
            HStack(spacing: Spacing.sm) {
                TextField(
                    "",
                    text: bindingForDraft(slug),
                    prompt: Text(verbatim: placeholder(for: slug))
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .focused($focusedSlug, equals: slug)
                .onSubmit { appState.sessionRenameModel.commitDraft(for: slug) }
                .frame(minWidth: 140, idealWidth: 200)
                .accessibilitySortPriority(2)
                Button(role: .destructive) {
                    pendingResetSlug = slug
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset to Default")
                .accessibilityLabel(String(localized: "Reset to Default"))
                .accessibilitySortPriority(1)
            }
        } label: {
            Text(slug)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    /// Resolves the placeholder shown in an empty TextField. For active sessions
    /// uses `appState.displayName(for:)` (which already prefers a custom name and
    /// falls back to projectName). For orphans no `ActiveSession` exists, so the
    /// slug itself serves as the visible placeholder.
    private func placeholder(for slug: String) -> String {
        if let session = appState.activeSessions.first(where: { $0.projectDirectory == slug }) {
            return appState.displayName(for: session)
        }
        return slug
    }

    /// Per-slug binding routed through the shared rename model. The model's
    /// `draft(for:)` returns the live draft when one exists, otherwise the
    /// persisted name — so the TextField shows the right value on first paint
    /// without needing a separate `onAppear` seed.
    private func bindingForDraft(_ slug: String) -> Binding<String> {
        Binding(
            get: { appState.sessionRenameModel.draft(for: slug) },
            set: { appState.sessionRenameModel.setDraft($0, for: slug) }
        )
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "person.2.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No sessions yet — start using Claude in a project.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AccountTab: View {
    @Environment(AppState.self) var appState
    @State private var orgIdCopied = false
    @State private var copyResetTask: Task<Void, Never>?
    @State private var showingSignOutConfirmation = false

    var body: some View {
        Form {
            if appState.isAuthenticated, let creds = appState.credentials {
                LabeledContent("Status") { HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("Connected") } }

                LabeledContent("Organization") {
                    VStack(alignment: .trailing, spacing: Spacing.xs) {
                        if let orgName = creds.organizationName {
                            Text(orgName).font(.body)
                        }

                        HStack(spacing: 6) {
                            Text(String(creds.organizationId.prefix(8)) + "...")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Button {
                                copyOrgId(creds.organizationId)
                            } label: {
                                Image(systemName: orgIdCopied ? "checkmark" : "doc.on.doc")
                                    .font(.caption2)
                                    .foregroundStyle(orgIdCopied ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "Copy Organization ID"))
                        }
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        showingSignOutConfirmation = true
                    }
                    .confirmationDialog(
                        String(localized: "Sign out of Claude?"),
                        isPresented: $showingSignOutConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Sign out", role: .destructive) {
                            appState.signOut()
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This removes your credentials and clears the local usage history on this Mac.")
                    }
                }
            } else {
                LabeledContent("Status") { HStack { Image(systemName: "xmark.circle.fill").foregroundStyle(.red); Text("Not connected") } }
                Section { Button("Sign in") { appState.showingAuth = true }.buttonStyle(.borderedProminent) }
            }
        }.formStyle(.grouped)
    }

    private func copyOrgId(_ orgId: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(orgId, forType: .string)
        withAnimation { orgIdCopied = true }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { orgIdCopied = false }
        }
    }
}

struct AboutTab: View {
    @Environment(AppState.self) var appState

    private var versionLabel: String {
        let value = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let isVersion = value.contains(".")
        return isVersion ? String(localized: "Version \(value)") : String(localized: "Build \(value)")
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text(verbatim: "ccInfo").font(.title2).fontWeight(.semibold)   // product name
            Text("Know your limits. Use them wisely.").font(.subheadline).foregroundStyle(.secondary)
            Text(versionLabel).font(.caption).foregroundStyle(.tertiary)

            Divider().frame(width: 64).frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Text("Pricing Data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                PricingStatusRow(
                    dataSource: appState.pricingDataSource,
                    lastUpdate: appState.pricingLastUpdate
                )
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, Spacing.xl)
    }
}

struct PricingStatusRow: View {
    let dataSource: PricingDataSource
    let lastUpdate: Date?

    @State private var now = Date()
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusLabel)
                .font(.caption)

            if let lastUpdate {
                Text("— \(relativeTime(for: lastUpdate, now: now))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            now = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                Task { @MainActor in now = Date() }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var statusColor: Color {
        switch dataSource {
        case .live: return .green
        case .cached: return .yellow
        case .bundled: return .gray
        }
    }

    private var statusLabel: String {
        switch dataSource {
        case .live: return String(localized: "Live")
        case .cached: return String(localized: "Cached")
        case .bundled: return String(localized: "Bundled")
        }
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private func relativeTime(for date: Date, now: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: now)
    }
}

struct UpdatesTab: View {
    @EnvironmentObject var updateService: UpdateService
    @State private var isChecking = false

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Automatically check for updates",
                    isOn: Binding(
                        get: { updateService.automaticallyChecksForUpdates },
                        set: { updateService.automaticallyChecksForUpdates = $0 }
                    )
                )
            }

            Section {
                HStack {
                    Button("Check for Updates") {
                        isChecking = true
                        updateService.checkForUpdates()
                        // Reset after a short delay — Sparkle takes over with its own UI
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            isChecking = false
                        }
                    }
                    .disabled(!updateService.canCheckForUpdates || isChecking)

                    if isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    final class Coordinator {
        var observer: Any?
        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            Self.centerOnMouseScreen(window)
            Self.activateAboveAllWindows(window)

            // Observe every subsequent window open
            context.coordinator.observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { notification in
                guard let window = notification.object as? NSWindow else { return }
                Self.centerOnMouseScreen(window)
                Self.activateAboveAllWindows(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            Self.activateAboveAllWindows(window)
        }
    }

    /// Bring window above all other windows, then reset to normal level
    private static func activateAboveAllWindows(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        // Reset to normal level so the window can be covered by other windows later
        DispatchQueue.main.async {
            window.level = .normal
        }
    }

    /// Center window on the screen where the mouse cursor is located
    private static func centerOnMouseScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        guard let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) else { return }

        let screenFrame = targetScreen.visibleFrame
        let windowSize = window.frame.size
        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.midY - windowSize.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
