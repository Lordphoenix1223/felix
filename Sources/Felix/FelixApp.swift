import AppKit
import CoreGraphics

@MainActor
final class FelixApp: NSObject, NSApplicationDelegate {
    private let configuration = FelixConfiguration.load()
    private lazy var nvidia = NVIDIAClient(configuration: configuration)
    private lazy var composio = ComposioClient(configuration: configuration)
    // Do not construct AppKit, Speech, or Accessibility objects before
    // NSApplication has finished creating its application context. macOS 26
    // can abort inside LaunchServices during that early phase.
    private lazy var speech = SpeechService()
    private lazy var selection = SelectionOverlayController()
    private lazy var memory = ConversationStore()
    private lazy var responsePanel = ResponsePanelController()
    private let statusPill = StatusPillController()
    private let pointerOverlay = PointerOverlayController()
    private let actionHistory = FelixActionHistory()
    private let undoStore = FelixUndoStore()
    private let teachingStore = FelixTeachingStore()
    private let preferences = FelixPreferences.load()
    private let automationScheduler = FelixAutomationScheduler()
    private lazy var permissions = FelixPermissionCoordinator()
    private lazy var popover = NSPopover()
    private lazy var popoverController = FelixPopoverViewController()
    private var statusItem: NSStatusItem?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var optionDown = false
    private var optionActivationWork: DispatchWorkItem?
    private var optionMouseIntent = false
    private var composioSessionID: String?
    private var targetProcessID: pid_t?
    private var answerTask: Task<Void, Never>?
    private var activeTurnID = UUID()
    private var requestInFlight = false
    private var lastSpokenAnswer = ""
    private var lastAutomationID: UUID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `open -n` and repeated launcher clicks can otherwise create multiple
        // menu-bar Felix processes. Each process installs its own monitors and
        // overlays, which turns one spoken command into repeated actions.
        if let bundleID = Bundle.main.bundleIdentifier {
            let currentPID = ProcessInfo.processInfo.processIdentifier
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != currentPID }
                .forEach { _ = $0.terminate() }
        }
        NSApp.setActivationPolicy(.accessory)
        SpeechOutput.onSpeakingChanged = { [weak self] speaking in
            guard let self, !speaking else { return }
            Task { @MainActor in self.updatePopover(status: self.permissionStatus()) }
        }
        responsePanel.onClose = { [weak self] in
            self?.answerTask?.cancel()
            self?.answerTask = nil
            self?.speech.stop()
            SpeechOutput.stop()
            self?.pointerOverlay.hide()
            self?.requestInFlight = false
        }
        responsePanel.onStop = { [weak self] in
            self?.answerTask?.cancel()
            self?.answerTask = nil
            self?.speech.stop()
            SpeechOutput.stop()
            self?.pointerOverlay.hide()
            self?.responsePanel.close()
            self?.requestInFlight = false
            self?.updatePopover(status: "READY // CANCELLED")
        }
        responsePanel.onReplay = { [weak self] in
            guard let text = self?.lastSpokenAnswer, !text.isEmpty else { return }
            SpeechOutput.speak(text)
        }
        installMenu()
        automationScheduler.onTick = { [weak self] automation in
            guard let self else { return }
            self.log("automation tick id=\(automation.id) description=\(automation.description.prefix(120))")
            if let action = FelixLocalAnswerRouter.namedSiteAction(for: automation.description), action.toolSlug == "open_url" {
                Task { @MainActor in
                    do {
                        let result = try await self.executeLocalAction(action)
                        self.updatePopover(status: "AUTOMATION // COMPLETE", answer: result)
                    } catch {
                        self.updatePopover(status: "AUTOMATION // BLOCKED", answer: error.localizedDescription)
                    }
                }
            } else {
                self.updatePopover(status: "AUTOMATION // NEEDS REVIEW", answer: "scheduled reminder: \(automation.description)")
            }
        }
        markStartupComplete()
        installOptionShortcut()
        Task { @MainActor in
            await permissions.presentIfNeeded()
            updatePopover(status: permissionStatus())
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        log("applicationWillTerminate")
        speech.stop()
        SpeechOutput.stop()
        answerTask?.cancel()
        answerTask = nil
        pointerOverlay.hide()
        statusPill.hide()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let eventTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes) }
        }
        optionActivationWork?.cancel()
        optionActivationWork = nil
    }

    private func installMenu() {
        let status = NSStatusBar.system.statusItem(withLength: 64)
        statusItem = status
        status.button?.title = "FELIX"
        status.button?.isHidden = false
        status.isVisible = true
        status.button?.toolTip = "Felix — press Option to talk; hold Option and drag to select"
        status.button?.target = self
        status.button?.action = #selector(togglePopover)
        let menu = NSMenu()
        let menuTitle = NSMenuItem(title: "FELIX — open popover", action: #selector(togglePopover), keyEquivalent: "")
        menuTitle.target = self
        let menuSelect = NSMenuItem(title: "Select a region", action: #selector(selectRegion), keyEquivalent: "")
        menuSelect.target = self
        let menuAsk = NSMenuItem(title: "Talk about current screen", action: #selector(quickAsk), keyEquivalent: "")
        menuAsk.target = self
        let menuDescribe = NSMenuItem(title: "Describe current screen", action: #selector(describeScreen), keyEquivalent: "")
        menuDescribe.target = self
        let menuFind = NSMenuItem(title: "Find something on screen", action: #selector(findOnScreen), keyEquivalent: "")
        menuFind.target = self
        let menuGuide = NSMenuItem(title: "Show me where to click", action: #selector(guideClick), keyEquivalent: "")
        menuGuide.target = self
        let menuHistory = NSMenuItem(title: "Show recent actions", action: #selector(showRecentActions), keyEquivalent: "")
        menuHistory.target = self
        let menuTeaching = NSMenuItem(title: "Show teaching steps", action: #selector(showTeachingSteps), keyEquivalent: "")
        menuTeaching.target = self
        let menuUndo = NSMenuItem(title: "Undo last safe automation", action: #selector(undoLastSafeAction), keyEquivalent: "")
        menuUndo.target = self
        let menuQuit = NSMenuItem(title: "Quit Felix", action: #selector(quit), keyEquivalent: "q")
        menuQuit.target = self
        menu.addItem(menuTitle)
        menu.addItem(.separator())
        menu.addItem(menuSelect)
        menu.addItem(menuAsk)
        menu.addItem(menuDescribe)
        menu.addItem(menuFind)
        menu.addItem(menuGuide)
        menu.addItem(menuHistory)
        menu.addItem(menuTeaching)
        menu.addItem(menuUndo)
        menu.addItem(.separator())
        menu.addItem(menuQuit)
        status.menu = menu
        popover.contentViewController = popoverController
        popover.behavior = .transient
        popover.animates = true
        popoverController.onTalk = { [weak self] in self?.runFromPopover { self?.quickAsk() } }
        popoverController.onDescribe = { [weak self] in self?.runFromPopover { self?.describeScreen() } }
        popoverController.onFind = { [weak self] in self?.runFromPopover { self?.findOnScreen() } }
        popoverController.onGuide = { [weak self] in self?.runFromPopover { self?.guideClick() } }
        popoverController.onHistory = { [weak self] in self?.showRecentActions() }
        popoverController.onSelect = { [weak self] in self?.runFromPopover { self?.selectRegion() } }
        popoverController.onConnect = { [weak self] in self?.runFromPopover { self?.connectToolkit() } }
        popoverController.onPermissions = { [weak self] in self?.openPermissions() }
        popoverController.onForget = { [weak self] in
            guard let self else { return }
            Task {
                guard await self.confirm("Forget all locally stored Felix conversation memory?") else { return }
                await self.memory.clear()
                self.responsePanel.show("Local memory cleared.", title: "Felix")
            }
        }
        popoverController.onQuit = { [weak self] in self?.quit() }
        updatePopover(status: configuration.nvidiaAPIKeyIssue ?? (configuration.nvidiaAPIKey == nil ? "DEMO MODE // ADD NVIDIA KEY" : "READY // NVIDIA CONNECTED"))
    }

    private func updatePopover(status: String, answer: String? = nil) {
        statusPill.update(status: status)
        Task { @MainActor in self.popoverController.update(status: status, answer: answer) }
    }

    private func runFromPopover(_ action: @escaping () -> Void) {
        log("runFromPopover: closing popover")
        closePopover()
        action()
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    @objc private func showRecentActions() {
        closePopover()
        Task { @MainActor [weak self] in
            guard let self else { return }
            let records = await self.actionHistory.recent(limit: 8)
            let text = records.isEmpty ? "no actions have been recorded yet." : records.map {
                "• \($0.summary) — \($0.result.split(separator: "\\n").first.map(String.init) ?? $0.result)"
            }.joined(separator: "\n")
            self.responsePanel.show(text, title: "Felix action history")
        }
    }

    @objc private func undoLastSafeAction() {
        Task { @MainActor [weak self] in
            guard let self, let undo = await self.undoStore.latest(), undo.kind == "automation",
                  let rawID = undo.arguments["automation_id"], let id = UUID(uuidString: rawID) else {
                self?.responsePanel.show("there is no reversible Felix action yet.", title: "Felix undo")
                return
            }
            self.automationScheduler.cancel(id)
            await self.undoStore.clear()
            self.responsePanel.show("stopped the last automation: \(undo.summary.lowercased()).", title: "Felix undo")
            SpeechOutput.speak("i stopped the last automation.")
        }
    }

    @objc private func showTeachingSteps() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let steps = await self.teachingStore.recent(limit: 8)
            let text = steps.isEmpty ? "no teaching steps recorded yet." : steps.map {
                "• \($0.instruction)\n  \($0.result)"
            }.joined(separator: "\n\n")
            self.responsePanel.show(text, title: "Felix teaching")
        }
    }

    private func closePopover() { if popover.isShown { popover.performClose(nil) } }

    private func installOptionShortcut() {
        func cancelOptionActivation(_ app: FelixApp) {
            app.optionActivationWork?.cancel()
            app.optionActivationWork = nil
        }

        func scheduleOptionActivation(_ app: FelixApp) {
            guard app.optionDown, !app.optionMouseIntent, app.optionActivationWork == nil else { return }
            // A short grace period lets Option+drag begin rectangle selection
            // without accidentally opening a voice turn. Plain Option then
            // becomes the primary no-menu activation path.
            let work = DispatchWorkItem { [weak app] in
                guard let app, app.optionDown, !app.optionMouseIntent else { return }
                app.optionActivationWork = nil
                app.quickAsk()
            }
            app.optionActivationWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }

        let handle: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let wasDown = self.optionDown
            self.optionDown = event.modifierFlags.contains(.option)
            if self.optionDown && !wasDown {
                scheduleOptionActivation(self)
            } else if !self.optionDown {
                cancelOptionActivation(self)
                self.optionMouseIntent = false
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in handle(event) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in handle(event); return event }

        let mouseDown: (NSEvent) -> Void = { [weak self] event in
            guard let self, self.optionDown || event.modifierFlags.contains(.option) else { return }
            cancelOptionActivation(self)
            self.optionMouseIntent = true
            self.beginSelection(initialPoint: NSEvent.mouseLocation)
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in mouseDown(event) }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in mouseDown(event); return event }

        // Option-only global monitoring is not equally reliable on every macOS
        // privacy state, so Option-F is an explicit fallback trigger.
        let keyDown: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            cancelOptionActivation(self)
            if event.charactersIgnoringModifiers?.lowercased() == "x", SpeechOutput.isSpeaking {
                SpeechOutput.stop()
                self.log("speech stopped by X")
                self.responsePanel.show("Speech stopped.", title: "Felix")
                return
            }
            if event.modifierFlags.contains(.option), event.keyCode == 49 {
                self.quickAsk()
                return
            }
            guard event.modifierFlags.contains(.option), event.keyCode == 3 else { return }
            self.beginSelection(initialPoint: nil)
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in keyDown(event) }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in keyDown(event); return event }

        // NSEvent's global monitor is observational and can be unavailable
        // for key events when Accessibility trust is stale. A listen-only
        // session tap gives Felix a second, explicit path for Option-drag;
        // it never suppresses or rewrites the user's original event.
        let mask = (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let app = Unmanaged<FelixApp>.fromOpaque(refcon).takeUnretainedValue()
            if type == .flagsChanged {
                let option = event.flags.contains(.maskAlternate)
                DispatchQueue.main.async {
                    let wasDown = app.optionDown
                    app.optionDown = option
                    if option && !wasDown { scheduleOptionActivation(app) }
                    if !option {
                        cancelOptionActivation(app)
                        app.optionMouseIntent = false
                    }
                }
            } else if type == .leftMouseDown, event.flags.contains(.maskAlternate) {
                DispatchQueue.main.async {
                    cancelOptionActivation(app)
                    app.optionMouseIntent = true
                    app.log("CGEventTap Option mouseDown")
                    app.beginSelection(initialPoint: NSEvent.mouseLocation)
                }
            }
            return Unmanaged.passUnretained(event)
        }
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        )
        if let eventTap {
            eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            if let eventTapSource { CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes) }
            CGEvent.tapEnable(tap: eventTap, enable: true)
            log("CGEventTap installed")
        } else {
            log("CGEventTap unavailable; using NSEvent monitors")
        }
    }

    private func beginSelection(initialPoint: NSPoint? = nil) {
        guard !requestInFlight else {
            log("ignored duplicate selection while request is in flight")
            return
        }
        requestInFlight = true
        log("beginSelection initialPoint=\(initialPoint != nil)")
        responsePanel.close()
        pointerOverlay.hide()
        // Do not gate the overlay on CGPreflightScreenCaptureAccess(). TCC can
        // report a stale false value after an ad-hoc rebuild even when the
        // current Felix row is enabled. Open the lasso first and validate the
        // permission at the actual CGDisplayCreateImage capture boundary.
        targetProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        selection.begin(initialPoint: initialPoint) { [weak self] rect, screen in
            self?.log("selection finished rect=\(rect) screen=\(screen.frame)")
            self?.process(selection: rect, screen: screen, targetProcessID: self?.targetProcessID)
        } cancellation: { [weak self] in
            self?.requestInFlight = false
            self?.optionMouseIntent = false
            self?.updatePopover(status: "READY // SELECTION CANCELLED")
        }
    }

    private func process(selection: NSRect, screen: NSScreen, targetProcessID: pid_t?) {
        // AppKit can return from the selection overlay before the prior panel
        // has actually left the compositor. Give macOS one run-loop turn so
        // Felix never captures its own answer card or pointer as context.
        let globalSelection = selection.offsetBy(dx: screen.frame.origin.x, dy: screen.frame.origin.y)
        responsePanel.close()
        pointerOverlay.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.captureCleanSelection(selection: globalSelection, screen: screen, targetProcessID: targetProcessID)
        }
    }

    private func captureCleanSelection(selection: NSRect, screen: NSScreen, targetProcessID: pid_t?) {
        guard let image = ScreenCapture.jpeg(for: selection, on: screen) else {
            requestInFlight = false
            permissions.openSettings(for: "Screen Recording")
            responsePanel.show("Felix could not capture this screen. The macOS permission record may be stale; enable the current Felix entry, then try the selection again.", title: "Felix setup")
            SpeechOutput.speak("I couldn't capture that area. Please check Screen Recording permission.")
            return
        }
        log("fresh capture bytes=\(image.count) selection=\(selection)")
        // Keep the target locked for the whole voice turn. The user should
        // never lose visual reference while Felix is listening, thinking, or
        // speaking; close/stop explicitly clears it.
        pointerOverlay.point(at: selection, on: screen, duration: 90)
        updatePopover(status: "LISTENING // SCREEN CAPTURED")
        let contextTask = Task.detached(priority: .userInitiated) {
            FelixScreenContextExtractor.extract(imageJPEG: image, selection: selection, on: screen, targetProcessID: targetProcessID, mode: .fast)
        }
        responsePanel.showListening(targetLocked: true)
        speech.listen(onPartial: { [weak self] partial in
            DispatchQueue.main.async {
                self?.responsePanel.showListening(partial: partial, targetLocked: true)
                self?.statusPill.update(status: "LISTENING // SCREEN CAPTURED", transcript: partial)
            }
        }) { [weak self] result in
            guard let self else { return }
            self.log("speech result=\(result)")
            let question: String
            switch result {
            case .success(let text) where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                question = text
                self.responsePanel.showThinking(targetLocked: true)
            default:
                self.responsePanel.close()
                question = self.askTextFallback()
            }
            guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.requestInFlight = false
                self.updatePopover(status: "READY // NO QUESTION")
                return
            }
            Task {
                var context = await contextTask.value
                if FelixTargetResolver.resolve(question: question, context: context) == nil,
                   Self.isLocationQuestion(question) {
                    context = await Task.detached(priority: .userInitiated) {
                        FelixScreenContextExtractor.extract(imageJPEG: image, selection: selection, on: screen, targetProcessID: targetProcessID, mode: .full)
                    }.value
                }
                self.startAnswer(image: image, question: question, screenContext: context, selection: selection, screen: screen)
            }
        }
    }

    private func askTextFallback() -> String {
        let alert = NSAlert()
        alert.messageText = "Ask Felix"
        alert.informativeText = "Speech recognition was unavailable. Type your question instead."
        let field = NSTextField(string: "What do you think about this?")
        field.frame = NSRect(x: 0, y: 0, width: 360, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Ask")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : ""
    }

    private func confirm(_ summary: String) async -> Bool {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "Felix confirmation"
            alert.informativeText = summary
            alert.addButton(withTitle: "Confirm")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }
    }

    private func startAnswer(image: Data, question: String, screenContext: String, selection: NSRect?, screen: NSScreen?) {
        answerTask?.cancel()
        let turnID = UUID()
        activeTurnID = turnID
        answerTask = Task { [weak self] in
            await self?.answer(image: image, question: question, screenContext: screenContext, selection: selection, screen: screen, turnID: turnID)
        }
    }

    private func answer(image: Data, question: String, screenContext: String = "", selection: NSRect? = nil, screen: NSScreen? = nil, turnID: UUID) async {
        defer { requestInFlight = false }
        guard !question.isEmpty else { return }
        guard turnID == activeTurnID, !Task.isCancelled else { return }
        let startedAt = Date()
        log("answer started question=\(question.prefix(160))")
        do {
            if let issue = configuration.nvidiaAPIKeyIssue {
                throw FelixError.missingConfiguration(issue)
            }
            var context = loadContext()
            context += "\n\nFELIX RESPONSE PREFERENCES: \(preferences.answerStyle). Keep spoken answers under two sentences and about 420 characters unless the request genuinely requires more."
            if let app = NSWorkspace.shared.frontmostApplication {
                context += "\n\nFOREGROUND APPLICATION (higher priority than desktop wallpaper): \(app.localizedName ?? app.bundleIdentifier ?? "unknown")"
            }
            if !screenContext.isEmpty { context += "\n\nCURRENT SCREEN OCR/ACCESSIBILITY EVIDENCE:\n\(screenContext)" }
            let browserContext = FelixBrowserContext.snapshot(for: question)
            if !browserContext.isEmpty { context += "\n\n\(browserContext)" }
            let prior = await memory.context()
            let lowerQuestion = question.lowercased()
            let standaloneScreenQuestion = ["what is this", "what's this", "what is this screen", "describe this screen", "what application"].contains { lowerQuestion.contains($0) }
            if !standaloneScreenQuestion && !prior.isEmpty {
                context += "\n\nHISTORICAL CONVERSATION MEMORY (use only for references, never as visual evidence):\n\(prior)"
            }
            if shouldSearchIntegrations(for: question), let sessionID = await ensureComposioSession() {
                if let candidates = try? await composio.search(sessionID: sessionID, useCase: question) {
                    context += "\n\nComposio tool candidates for this request:\n\(candidates.prefix(20_000))"
                }
            }
            guard turnID == activeTurnID, !Task.isCancelled else { return }
            let localPointer = inferredPointer(for: question, context: screenContext)
            let localAppAnswer = FelixLocalAnswerRouter.foregroundAnswer(
                for: question,
                appName: NSWorkspace.shared.frontmostApplication?.localizedName
            )
            let localTeachingAnswer = FelixLocalAnswerRouter.teachingAnswer(for: question, pointer: localPointer)
            let localNavigationAnswer = FelixLocalAnswerRouter.navigationAnswer(for: question, pointer: localPointer)
            let localBrowserTabAction = FelixLocalAnswerRouter.browserTabAction(for: question, context: browserContext)
            let localNamedSiteAction = FelixLocalAnswerRouter.namedSiteAction(for: question)
            let localAutomationRequest = FelixLocalAnswerRouter.automationRequest(for: question)

            let response: FelixResponse
            if let localAnswer = localAppAnswer ?? localTeachingAnswer ?? localNavigationAnswer {
                log("local answer route used pointer=\(localPointer != nil)")
                response = FelixResponse(
                    spokenText: localAnswer,
                    action: nil,
                    pointer: localPointer,
                    needsConfirmation: false,
                    debugSummary: "Local deterministic answer"
                )
            } else if let localBrowserTabAction {
                response = FelixResponse(spokenText: "i can \(localBrowserTabAction.summary). press confirm to do it.", action: localBrowserTabAction, pointer: nil, needsConfirmation: true, debugSummary: "Local browser tab route")
            } else if let localAutomationRequest {
                let cadence = localAutomationRequest.interval < 60 ? "30 seconds" : "\(max(1, Int(localAutomationRequest.interval / 60))) minutes"
                response = FelixResponse(
                    spokenText: "i can run that every \(cadence). press confirm to start it.",
                    action: FelixAction(kind: "local", toolSlug: "create_automation", arguments: [
                        "description": AnySendable(value: localAutomationRequest.description),
                        "interval": AnySendable(value: localAutomationRequest.interval)
                    ], summary: localAutomationRequest.description, requiresConfirmation: true),
                    pointer: nil, needsConfirmation: true, debugSummary: "Local automation route"
                )
            } else if let localNamedSiteAction {
                let site = (localNamedSiteAction.arguments["url"]?.value as? String) ?? "that site"
                response = FelixResponse(
                    spokenText: "opening \(site).", action: localNamedSiteAction,
                    pointer: nil, needsConfirmation: false, debugSummary: "Allowlisted named-site route"
                )
            } else if Self.isLocationQuestion(question) {
                response = FelixResponse(
                    spokenText: "i couldn't find a matching control in the current foreground app.",
                    action: nil, pointer: nil, needsConfirmation: false,
                    debugSummary: "No verified local target; remote guessing disabled"
                )
            } else {
                responsePanel.show("Thinking…", title: "Felix")
                updatePopover(status: "THINKING // REASONING")
                log("remote vision request context_chars=\(context.count) image_bytes=\(image.count)")
                response = try await nvidia.ask(imageJPEG: image, question: question, context: context)
            }
            let spokenText = response.spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !spokenText.isEmpty else {
                throw FelixError.invalidResponse("Felix received an empty answer. Try asking the question again.")
            }
            // Local AX/OCR evidence is authoritative for “where/find/show”.
            // The model is still useful for explanations, but it must not
            // override a precise local match with a generic box.
            let navigation = Self.isLocationQuestion(question)
            let resolvedPointer = navigation ? localPointer : (localPointer ?? response.pointer)
            let finalSpokenText: String = {
                if let localNavigationAnswer { return localNavigationAnswer }
                if navigation, let pointer = resolvedPointer {
                    return "i found \(pointer.label.lowercased()). look here."
                }
                if navigation { return "i couldn't find a matching control in the current foreground app." }
                return spokenText
            }()
            let usableResponse = FelixResponse(
                spokenText: finalSpokenText,
                action: response.action,
                actions: response.actions,
                pointer: resolvedPointer,
                needsConfirmation: response.needsConfirmation,
                debugSummary: response.debugSummary
            )
            await memory.append(question: question, answer: finalSpokenText)
            guard turnID == activeTurnID, !Task.isCancelled else { return }
            log("answer ready after \(String(format: "%.2f", Date().timeIntervalSince(startedAt)))s")
            responsePanel.show(finalSpokenText, title: "Felix")
            updatePopover(status: "ANSWER READY // SCREEN CONTEXT", answer: finalSpokenText)
            if let selection, let screen {
                await MainActor.run {
                    if let pointer = usableResponse.pointer {
                        let target = NSPoint(
                            x: selection.minX + selection.width * pointer.x / 1000,
                            y: selection.maxY - selection.height * pointer.y / 1000
                        )
                        self.pointerOverlay.point(at: target, label: pointer.label, style: pointer.style, on: screen)
                    } else { self.pointerOverlay.hide() }
                }
            }
            lastSpokenAnswer = finalSpokenText
            SpeechOutput.speak(finalSpokenText)
            if usableResponse.actions.count > 1 {
                let actions = usableResponse.actions
                let list = actions.enumerated().map { "\($0.offset + 1). \($0.element.summary)" }.joined(separator: "\n")
                guard await confirm("Felix wants to run this \(actions.count)-step plan:\n\n\(list)\n\nContinue?") else {
                    responsePanel.show("plan cancelled.", title: "Felix")
                    return
                }
                do {
                    let execution = try await executeAgentPlan(actions, pointer: usableResponse.pointer, selection: selection, screen: screen, question: question, beforeContext: screenContext)
                    responsePanel.show(execution, title: "Felix plan complete")
                    SpeechOutput.speak(execution)
                } catch {
                    responsePanel.show(error.localizedDescription, title: "Felix plan stopped")
                    SpeechOutput.speak("the plan stopped. \(error.localizedDescription)")
                }
                return
            }
            guard let action = usableResponse.action else { return }
            if action.kind == "local", action.toolSlug.lowercased() == "open_url", usableResponse.debugSummary == "Allowlisted named-site route" {
                do {
                    let result = try await self.executeLocalAction(action)
                    responsePanel.show(result, title: "Felix opened it")
                } catch {
                    responsePanel.show(error.localizedDescription, title: "Felix action blocked")
                }
                return
            }
            guard usableResponse.needsConfirmation else { return }
            if action.kind == "local", action.toolSlug.lowercased() == "create_automation",
               let description = action.arguments["description"]?.value as? String {
                let interval = (action.arguments["interval"]?.value as? NSNumber)?.doubleValue
                    ?? (action.arguments["interval_seconds"]?.value as? NSNumber)?.doubleValue
                    ?? 0
                guard interval > 0 else {
                    responsePanel.show("Felix needs a numeric repeat interval before it can schedule this.", title: "Felix automation")
                    return
                }
                let cadence = interval < 60 ? "30 seconds" : "\(max(1, Int(interval / 60))) minutes"
                if await confirm("Felix wants to repeat:\n\n\(description)\n\nEvery \(cadence). Continue?") {
                let automation = await MainActor.run {
                    self.automationScheduler.schedule(description: description, interval: interval)
                }
                lastAutomationID = automation.id
                let result = "automation started. id \(automation.id.uuidString.prefix(8))."
                await actionHistory.append(action: action, result: result, undoable: true)
                await undoStore.save(kind: "automation", summary: description, arguments: ["automation_id": automation.id.uuidString])
                responsePanel.show(result, title: "Felix automation")
                SpeechOutput.speak(result)
                return
                }
            }
            if action.kind == "local", action.toolSlug.lowercased() == "open_url",
               let rawURL = action.arguments["url"]?.value as? String,
               let url = URL(string: rawURL), ["http", "https"].contains(url.scheme?.lowercased()),
               await confirm("Felix wants to open:\n\n\(rawURL)") {
                do {
                    let result = try await self.executeLocalAction(action)
                    responsePanel.show(result, title: "Felix action complete")
                    SpeechOutput.speak(result)
                } catch {
                    responsePanel.show(error.localizedDescription, title: "Felix action blocked")
                    SpeechOutput.speak(error.localizedDescription)
                }
                return
            }
            if action.kind == "local", action.toolSlug.lowercased() == "open_app",
               let name = action.arguments["name"]?.value as? String,
               await confirm("Felix wants to open \(name). Continue?") {
                do {
                    let result = try await self.executeLocalAction(action)
                    responsePanel.show(result, title: "Felix action complete")
                    SpeechOutput.speak(result)
                } catch {
                    responsePanel.show(error.localizedDescription, title: "Felix action blocked")
                    SpeechOutput.speak(error.localizedDescription)
                }
                return
            }
            if action.kind == "local", action.toolSlug.lowercased() == "close_app",
               let name = action.arguments["name"]?.value as? String,
               await confirm("Felix wants to close \(name). Unsaved work may be lost. Continue?") {
                do {
                    let result = try await self.executeLocalAction(action)
                    responsePanel.show(result, title: "Felix action complete")
                    SpeechOutput.speak(result)
                } catch {
                    responsePanel.show(error.localizedDescription, title: "Felix action blocked")
                    SpeechOutput.speak(error.localizedDescription)
                }
                return
            }
            if action.kind == "local", action.toolSlug.lowercased() == "type_text",
               let text = action.arguments["text"]?.value as? String,
               await confirm("Felix wants to insert this text into the focused field:\n\n\(text.prefix(500))") {
                do {
                    let result = try await self.executeLocalAction(action)
                    responsePanel.show(result, title: "Felix action complete")
                    SpeechOutput.speak(result)
                } catch {
                    responsePanel.show(error.localizedDescription, title: "Felix action blocked")
                    SpeechOutput.speak(error.localizedDescription)
                }
                return
            }
            if action.kind == "local", action.toolSlug.lowercased() == "close_browser_tab",
               await confirm("Felix wants to \(action.summary). Continue?") {
                do {
                    let result = try await self.executeLocalAction(action)
                    responsePanel.show(result, title: "Felix action complete")
                } catch {
                    responsePanel.show(error.localizedDescription, title: "Felix action blocked")
                }
                return
            }
            if action.kind == "local", action.toolSlug.lowercased() == "click_point", let pointer = usableResponse.pointer, let selection {
                let target = NSPoint(
                    x: selection.minX + selection.width * pointer.x / 1000,
                    y: selection.maxY - selection.height * pointer.y / 1000
                )
                if await confirm("Felix wants to click \"\(pointer.label)\" at the highlighted location. Continue?") {
                    var arguments = action.arguments
                    arguments["x"] = AnySendable(value: target.x)
                    arguments["y"] = AnySendable(value: target.y)
                    let clickAction = FelixAction(kind: "local", toolSlug: "click_point", arguments: arguments, summary: action.summary, requiresConfirmation: true)
                    do {
                        let result = try await self.executeLocalAction(clickAction)
                        await self.recordTeachingIfRequested(question: question, beforeContext: screenContext, pointer: pointer, screen: screen, result: result)
                        responsePanel.show(result, title: "Felix action complete")
                        SpeechOutput.speak(result)
                    } catch {
                        responsePanel.show(error.localizedDescription, title: "Felix action blocked")
                        SpeechOutput.speak(error.localizedDescription)
                    }
                    return
                }
            }
            // Verified local actions are executable; only unknown or
            // unconfigured connector actions should be held here.
            let hold = "i can’t safely run that action yet. this build supports only its verified local actions and configured composio connectors.\n\nrequested: \(action.summary)"
            responsePanel.show(hold, title: "Felix safety hold")
        } catch {
            log("answer failed: \(error.localizedDescription)")
            updatePopover(status: "ERROR // NEEDS ATTENTION", answer: error.localizedDescription)
            responsePanel.show(error.localizedDescription, title: "Felix error")
            SpeechOutput.speak("I hit a problem. \(error.localizedDescription)")
        }
    }

    private func shouldSearchIntegrations(for question: String) -> Bool {
        let lower = question.lowercased()
        let actionWords = ["send", "email", "message", "calendar", "schedule", "github", "notion", "slack", "create", "update", "post", "add", "remind", "delete", "ticket"]
        return actionWords.contains { lower.contains($0) }
    }

    private func inferredPointer(for question: String, context: String) -> FelixPointer? {
        // There is deliberately no fuzzy fallback here. The old fallback
        // matched arbitrary words in long AX/OCR lines and produced a box
        // labelled “target”, which looked like a successful find while being
        // semantically wrong.
        return FelixTargetResolver.resolve(question: question, context: context)
    }

    private static func isLocationQuestion(_ question: String) -> Bool {
        let lower = question.lowercased()
        return ["where", "find", "locate", "show me", "show", "teach me", "how do i", "how to"].contains { lower.contains($0) }
    }

    private func executeAgentPlan(_ actions: [FelixAction], pointer: FelixPointer?, selection: NSRect?, screen: NSScreen?, question: String, beforeContext: String) async throws -> String {
        guard !actions.isEmpty, actions.count <= 5 else { throw FelixError.invalidResponse("Felix limited this plan to five steps.") }
        var results: [String] = []
        var didClick = false
        for (index, proposed) in actions.enumerated() {
            try Task.checkCancellation()
            guard proposed.kind == "local" else {
                throw FelixError.invalidResponse("step \(index + 1) is not a locally verified action")
            }
            var action = proposed
            if proposed.toolSlug.lowercased() == "click_point" {
                guard let pointer, let selection else { throw FelixError.invalidResponse("step \(index + 1) needs a visible target") }
                let target = NSPoint(x: selection.minX + selection.width * pointer.x / 1000, y: selection.maxY - selection.height * pointer.y / 1000)
                var arguments = proposed.arguments
                arguments["x"] = AnySendable(value: target.x)
                arguments["y"] = AnySendable(value: target.y)
                action = FelixAction(kind: "local", toolSlug: proposed.toolSlug, arguments: arguments, summary: proposed.summary, requiresConfirmation: true)
                didClick = true
            }
            let result = try await executeLocalAction(action)
            results.append("step \(index + 1): \(result)")
            try await Task.sleep(nanoseconds: 220_000_000)
        }
        if didClick, let screen, let afterImage = ScreenCapture.fullScreenJPEG(on: screen) {
            let afterContext = await Task.detached(priority: .userInitiated) {
                FelixScreenContextExtractor.extract(imageJPEG: afterImage, selection: screen.frame, on: screen, mode: .fast)
            }.value
            let changed = afterContext == beforeContext ? "the screen looked unchanged after the click." : "the screen changed after the click."
            results.append(changed)
            if question.lowercased().contains("teach") || question.lowercased().contains("what changed") || question.lowercased().contains("then tell me") {
                await teachingStore.append(instruction: question, beforeContext: beforeContext, afterContext: afterContext, target: pointer?.label, result: changed)
            }
        }
        return results.joined(separator: "\n")
    }

    private func recordTeachingIfRequested(question: String, beforeContext: String, pointer: FelixPointer?, screen: NSScreen?, result: String) async {
        let lower = question.lowercased()
        guard lower.contains("teach") || lower.contains("what changed") || lower.contains("then tell me") else { return }
        var afterContext: String?
        if let screen, let image = ScreenCapture.fullScreenJPEG(on: screen) {
            afterContext = await Task.detached(priority: .userInitiated) {
                FelixScreenContextExtractor.extract(imageJPEG: image, selection: screen.frame, on: screen, mode: .fast)
            }.value
        }
        let change = afterContext == beforeContext ? "the screen looked unchanged after the action." : "i recorded what changed after the action."
        await teachingStore.append(instruction: question, beforeContext: beforeContext, afterContext: afterContext, target: pointer?.label, result: "\(result) \(change)")
    }

    private func executeLocalAction(_ action: FelixAction) async throws -> String {
        let plan = FelixAgentPlan.singleStep(goal: action.summary, action: action)
        log("agent plan id=\(plan.id) steps=\(plan.steps.count) action=\(action.toolSlug)")
        let result = try LocalActionExecutor.execute(action, context: "")
        // Give the OS a moment to publish the changed accessibility/process
        // state, then report what was verified rather than trusting the model.
        try? await Task.sleep(nanoseconds: 220_000_000)
        let verification = LocalActionExecutor.verify(action)
        await actionHistory.append(action: action, result: "\(result)\n\(verification)", undoable: false)
        return "\(result)\n\(verification)"
    }

    @objc private func quickAsk() {
        guard !requestInFlight else {
            log("ignored duplicate quick ask while request is in flight")
            return
        }
        requestInFlight = true
        answerTask?.cancel()
        answerTask = nil
        speech.stop()
        SpeechOutput.stop()
        responsePanel.close()
        pointerOverlay.hide()
        updatePopover(status: "LISTENING // CURRENT SCREEN")
        responsePanel.showListening(targetLocked: false)
        speech.listen(onPartial: { [weak self] partial in
            DispatchQueue.main.async {
                self?.responsePanel.showListening(partial: partial, targetLocked: false)
                self?.statusPill.update(status: "LISTENING // CURRENT SCREEN", transcript: partial)
            }
        }) { [weak self] result in
            guard let self else { return }
            self.log("speech result=\(result)")
            let question: String
            switch result {
            case .success(let text) where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                question = text
                self.responsePanel.showThinking(targetLocked: false)
            default:
                self.responsePanel.close()
                question = self.askTextFallback()
            }
            guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.requestInFlight = false
                self.updatePopover(status: "READY // NO QUESTION")
                return
            }
            // Capture after the user finishes speaking. Dismiss Felix's old
            // answer first: otherwise the next screenshot contains the prior
            // Felix card, and the vision model can faithfully repeat itself.
            self.responsePanel.close()
            self.pointerOverlay.hide()
            guard let screen = NSScreen.main, let image = ScreenCapture.fullScreenJPEG(on: screen) else {
                self.requestInFlight = false
                self.responsePanel.show("I couldn't capture my current screen.", title: "Felix")
                SpeechOutput.speak("I couldn't capture the current screen.")
                return
            }
            self.log("fresh current-screen capture bytes=\(image.count) screen=\(screen.frame)")
            Task.detached(priority: .userInitiated) {
                let context = FelixScreenContextExtractor.extract(imageJPEG: image, selection: screen.frame, on: screen, mode: .fast)
                await MainActor.run {
                    self.startAnswer(image: image, question: question, screenContext: context, selection: screen.frame, screen: screen)
                }
            }
        }
    }

    @objc private func describeScreen() {
        askCurrentScreen("Describe the most important thing visible on this screen in two natural spoken sentences. Point to it.")
    }

    @objc private func findOnScreen() {
        let alert = NSAlert()
        alert.messageText = "Find something on screen"
        alert.informativeText = "Tell Felix what to locate. It will point to the best match."
        let field = NSTextField(string: "the main button")
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Find")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let target = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return }
        askCurrentScreen("Find \(target) on the current screen. Describe it briefly and point to the exact location.")
    }

    @objc private func guideClick() {
        askCurrentScreen("Look at the current screen and identify the most likely next control the user should click. Explain why briefly and point to it. Do not click anything.")
    }

    private func askCurrentScreen(_ question: String) {
        guard !requestInFlight else {
            log("ignored duplicate guided request while request is in flight")
            return
        }
        guard let screen = NSScreen.main else {
            responsePanel.show("i couldn't find an active screen.", title: "felix")
            return
        }
        requestInFlight = true
        responsePanel.close()
        pointerOverlay.hide()
        updatePopover(status: "THINKING // CURRENT SCREEN")
        guard let image = ScreenCapture.fullScreenJPEG(on: screen) else {
            requestInFlight = false
            responsePanel.show("I couldn't capture the current screen.", title: "Felix")
            return
        }
        log("fresh guided capture bytes=\(image.count) question=\(question.prefix(100))")
        responsePanel.showThinking(targetLocked: false)
        Task.detached(priority: .userInitiated) {
            let context = FelixScreenContextExtractor.extract(imageJPEG: image, selection: screen.frame, on: screen)
            await MainActor.run {
                self.startAnswer(image: image, question: question, screenContext: context, selection: screen.frame, screen: screen)
            }
        }
    }

    private func ensureComposioSession() async -> String? {
        if let composioSessionID { return composioSessionID }
        guard configuration.composioAPIKey != nil else { return nil }
        do {
            let sessionID = try await composio.createSession()
            composioSessionID = sessionID
            log("Composio session ready")
            return sessionID
        } catch {
            log("Composio unavailable (optional): \(error.localizedDescription)")
            return nil
        }
    }

    private func loadContext() -> String {
        guard let file = configuration.contextFile, let contents = try? String(contentsOf: file, encoding: .utf8) else { return "" }
        return String(contents.prefix(12_000))
    }

    private func permissionStatus() -> String {
        let missing = permissions.snapshot().missing
        let speechEngine = speech.engineDescription
        return missing.isEmpty ? "READY // \(speechEngine)" : "SETUP // \(missing.joined(separator: " • ")) · \(speechEngine)"
    }

    @objc private func connectToolkit() {
        guard configuration.composioAPIKey != nil else {
            SpeechOutput.speak("Add a Composio API key in Felix setup first.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Connect a Composio toolkit"
        alert.informativeText = "Type a toolkit slug such as gmail, github, notion, or slack."
        let field = NSTextField(string: "gmail")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Open connection")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                guard let sessionID = await ensureComposioSession() else {
                    throw FelixError.network("Composio could not create a session. Check the project key.")
                }
                let url = try await composio.link(sessionID: sessionID, toolkit: field.stringValue)
                _ = await MainActor.run { NSWorkspace.shared.open(url) }
                SpeechOutput.speak("I opened the connection page.")
            } catch {
                responsePanel.show("That integration is unavailable right now. Felix's screen questions still work without it.", title: "Integration unavailable")
                SpeechOutput.speak("I couldn't open that connection. \(error.localizedDescription)")
            }
        }
    }

    @objc private func selectRegion() {
        log("selectRegion action received")
        // The button/menu click that invokes this action also emits a mouseUp.
        // If the overlay is created synchronously, it receives that same
        // mouseUp and cancels itself as an empty selection. Defer creation
        // until the initiating click has completely left the event queue.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.log("selectRegion starting deferred overlay")
            self?.beginSelection(initialPoint: nil)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func openPermissions() {
        permissions.openSettings()
    }

    private func markStartupComplete() {
        let marker = "Felix reached applicationDidFinishLaunching at \(Date())\n"
        try? marker.data(using: .utf8)?.write(to: URL(fileURLWithPath: "/tmp/felix-started"), options: .atomic)
    }

    private func log(_ message: String) {
        let line = "\(Date()) Felix \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/felix-events.log")
        if let data = line.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }
}
