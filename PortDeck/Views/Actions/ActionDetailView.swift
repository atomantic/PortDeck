import SwiftUI

/// One palette action: a live data page for readers, a run form for everything else.
///
/// Reader actions (`brain_list_recent`, `goal_list`, `pm2_status`, …) fetch as soon as
/// the page opens and render the payload PortOS returned. Their parameters move into a
/// collapsed Options panel, and the window widens either by editing the page-size
/// parameter or by scrolling to the end of the list.
struct ActionDetailView: View {
    @Environment(AppState.self) private var appState
    let action: PaletteAction
    let instance: PortOSInstance

    /// Derived once: the scroll handler consults these on every frame.
    private let pageSizeParameter: String?

    @State private var arguments: ActionArgumentState
    @State private var display: ActionResultDisplay?
    @State private var errorMessage: String?
    @State private var lastFetchedAt: Date?
    @State private var isRunning = false
    @State private var isPaging = false
    @State private var reachedEnd = false
    @State private var hasScrolled = false
    @State private var showingOptions = false
    @State private var showingDestructiveConfirmation = false

    /// PortOS list tools default to a small window; widen by this step each time.
    private static let pageStep = 5
    /// How close to the end of the content a scroll gets before the next window is fetched.
    private static let paddingBeforeEnd: CGFloat = 240
    private static let scrollSpace = "actionDetailScroll"

    init(action: PaletteAction, instance: PortOSInstance) {
        self.action = action
        self.instance = instance
        // Paging re-invokes the action with a wider window, so it is offered only for
        // read-shaped actions — repeating a writer would repeat its side effect.
        pageSizeParameter = action.isReadShaped ? action.pageSizeParameterName : nil
        _arguments = State(initialValue: DemoMode.isEnabled
            ? DemoFixtures.prefilledArguments(for: action)
            : ActionArgumentState(defaultsFor: action))
    }

    private var hasParameters: Bool { !action.parameters.properties.isEmpty }

    private var canPage: Bool {
        pageSizeParameter != nil
            && display?.hasCollection == true
            && display?.rows.isEmpty == false
            && !reachedEnd
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if let errorMessage {
                        VStack(spacing: 10) {
                            InlineMessage(text: errorMessage, kind: .error)
                            Button("Try again") { startRun() }
                                .buttonStyle(.bordered)
                                .disabled(isRunning)
                        }
                    }
                    inputSection
                    resultsSection
                    pagingFooter
                    if !action.isReader { runButton }
                }
                .padding(16)
                .background {
                    // Rows live in a plain stack, so `onAppear` fires once for every row at
                    // layout time and never again — scroll position is the only usable signal
                    // for "the reader scrolled to the end, fetch the next window".
                    GeometryReader { content in
                        Color.clear.onChange(of: content.frame(in: .named(Self.scrollSpace)).minY) { _, offset in
                            if offset < -24, !hasScrolled { hasScrolled = true }
                            let remaining = content.size.height - viewport.size.height + offset
                            if hasScrolled, remaining < Self.paddingBeforeEnd { loadMore() }
                        }
                    }
                }
            }
            .coordinateSpace(name: Self.scrollSpace)
        }
        .background(Color.portCanvas)
        .navigationTitle(action.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if action.isReader {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { startRun() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(isRunning)
                        .accessibilityLabel("Refresh \(action.label)")
                }
            }
        }
        .confirmationDialog("Run destructive action?", isPresented: $showingDestructiveConfirmation, titleVisibility: .visible) {
            Button("Run \(action.label)", role: .destructive) { startRun() }
        } message: {
            Text("PortOS marks this action as destructive. It will run immediately on \(instance.displayName).")
        }
        .onAppear {
            if action.isReader, display == nil { startRun() }
        }
    }

    // MARK: - Sections

    private var header: some View {
        PortPanel {
            VStack(alignment: .leading, spacing: 8) {
                Label(action.section, systemImage: action.presentation.icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(action.presentation.tint)
                Text(action.label).font(.title2.weight(.bold))
                if !action.description.isEmpty {
                    Text(action.description).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text(instance.displayName).font(.caption.weight(.semibold)).foregroundStyle(Color.portAccent)
                    if let lastFetchedAt {
                        Text("Updated \(lastFetchedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if isRunning {
                        ProgressView().controlSize(.mini)
                    }
                }
            }
        }
    }

    /// Readers keep their parameters out of the way; run forms lead with them.
    @ViewBuilder
    private var inputSection: some View {
        if !hasParameters {
            if !action.isReader { InlineMessage(text: "This action does not need any input.") }
        } else if action.isReader {
            optionsPanel
        } else {
            PortPanel {
                ActionParameterForm(action: action, state: $arguments)
            }
        }
    }

    private var optionsPanel: some View {
        PortPanel {
            DisclosureGroup(isExpanded: $showingOptions) {
                VStack(alignment: .leading, spacing: 16) {
                    ActionParameterForm(action: action, state: $arguments) { reachedEnd = false }
                    Button("Fetch") { startRun() }
                        .buttonStyle(.borderedProminent)
                        .tint(.portAccent)
                        .disabled(isRunning)
                }
                .padding(.top, 12)
            } label: {
                Label("Options", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        if let display {
            ActionResultView(display: display)
        } else if isRunning {
            ProgressView("Fetching from \(instance.displayName)…")
                .padding(.vertical, 40)
        }
    }

    @ViewBuilder
    private var pagingFooter: some View {
        if isPaging {
            ProgressView().padding(.vertical, 8)
        } else if canPage {
            Button("Load more") { loadMore() }
                .buttonStyle(.bordered)
                .disabled(isRunning)
        } else if reachedEnd, display?.rows.isEmpty == false {
            Text("That is everything PortOS returned for this action.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var runButton: some View {
        Button {
            if action.destructive == true { showingDestructiveConfirmation = true }
            else { startRun() }
        } label: {
            HStack {
                if isRunning { ProgressView().tint(.white) }
                Label("Run on \(instance.displayName)", systemImage: "play.fill")
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(action.destructive == true ? .portOffline : .portAccent)
        .disabled(isRunning)
    }

    // MARK: - Behavior

    /// Widens the result window and refetches. PortOS clamps its own maximum, so a page
    /// that comes back no longer than the last one latches the end of the list.
    private func loadMore() {
        // `!isRunning` gates the *mutation*, not just the fetch: scroll fires this every frame,
        // and `startRun`'s own guard would let each one widen the window again while the
        // request it already started is still in flight.
        guard canPage, !isRunning, let key = pageSizeParameter, let rowCount = display?.rows.count else { return }
        let requested = max(arguments.integer(for: key) ?? Self.pageStep, rowCount)
        arguments.setValue(String(requested + Self.pageStep), for: key)
        startRun(paging: true)
    }

    /// Claims the in-flight slot synchronously, then dispatches. Scroll events arrive faster
    /// than a task starts, so a guard inside the task would let a second request through.
    private func startRun(paging: Bool = false) {
        guard !isRunning else { return }
        isRunning = true
        isPaging = paging
        Task { await run(paging: paging) }
    }

    @MainActor
    private func run(paging: Bool) async {
        defer {
            isRunning = false
            isPaging = false
        }
        guard let baseURL = instance.baseURL else {
            errorMessage = "This instance does not have a usable endpoint."
            return
        }
        errorMessage = nil
        if !paging { reachedEnd = false }
        let previousRowCount = display?.rows.count ?? 0
        do {
            let payload = try ActionArgumentBuilder.build(action: action, state: arguments)
            let password = try appState.credentials.password(for: instance.localID)
            let response = try await appState.api.invokeAction(
                id: action.id,
                arguments: payload,
                baseURL: baseURL,
                password: password
            )
            try Task.checkCancellation()
            let result = ActionResultDisplay(result: response.result, envelopeOK: response.ok)
            display = result
            lastFetchedAt = .now
            // End of list: the window stopped growing, or PortOS returned fewer rows than
            // the window asked for — asking for more would just repeat the same page.
            if paging, result.rows.count <= previousRowCount { reachedEnd = true }
            if let requested = pageSizeParameter.flatMap({ arguments.integer(for: $0) }),
               result.rows.count < requested {
                reachedEnd = true
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
