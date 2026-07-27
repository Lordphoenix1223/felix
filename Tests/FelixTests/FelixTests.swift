import XCTest
@testable import Felix

final class FelixTests: XCTestCase {
    func testPackageHasExpectedName() {
        XCTAssertEqual("Felix".lowercased(), "felix")
    }

    func testDotEnvParserHandlesCommentsAndQuotedValues() {
        let values = DotEnv.parse("# comment\nNVIDIA_MODEL=moonshotai/kimi-k2.6\nFELIX_CONTEXT_FILE=\"~/context.md\"\n")
        XCTAssertEqual(values["NVIDIA_MODEL"], "moonshotai/kimi-k2.6")
        XCTAssertEqual(values["FELIX_CONTEXT_FILE"], "~/context.md")
    }

    func testDotEnvParserIgnoresMalformedLines() {
        let values = DotEnv.parse("not-an-assignment\n=missing-key\nCOMPOSIO_API_KEY=test-key\n")
        XCTAssertNil(values["not-an-assignment"])
        XCTAssertEqual(values["COMPOSIO_API_KEY"], "test-key")
    }

    func testLocalForegroundAnswerDoesNotNeedVisionModel() {
        let answer = FelixLocalAnswerRouter.foregroundAnswer(
            for: "What application am I using?",
            appName: "ChatGPT"
        )
        XCTAssertEqual(answer, "you’re using chatgpt.")
    }

    func testLocalNavigationAnswerUsesExactPointer() {
        let pointer = FelixPointer(x: 120, y: 240, label: "New chat", style: "target")
        let answer = FelixLocalAnswerRouter.navigationAnswer(
            for: "where is the new chat button?",
            pointer: pointer
        )
        XCTAssertEqual(answer, "i found new chat. look here.")
    }

    func testLocalNavigationAnswerDoesNotInventTarget() {
        XCTAssertNil(FelixLocalAnswerRouter.navigationAnswer(for: "where is the hidden folder?", pointer: nil))
    }

    func testTargetResolverPrefersExactAccessibilityControl() {
        let context = "role=AXButton | title=New chat | center_top_left=(84,96)\ntext=ChatGPT | center_top_left=(500,80)"
        let pointer = FelixTargetResolver.resolve(question: "where is the new chat button?", context: context)
        XCTAssertEqual(pointer?.label, "New chat")
        XCTAssertEqual(pointer?.x, 84)
        XCTAssertEqual(pointer?.y, 96)
    }

    func testTargetResolverSupportsNewConversationSynonym() {
        let context = "role=AXButton | title=New conversation | center_top_left=(72,110)"
        let pointer = FelixTargetResolver.resolve(question: "show me how to start a new chat", context: context)
        XCTAssertEqual(pointer?.label, "New conversation")
    }

    func testTargetResolverRejectsGenericModelTarget() {
        let context = "role=AXButton | title=target | center_top_left=(500,500)\ntext=look here | center_top_left=(500,500)"
        XCTAssertNil(FelixTargetResolver.resolve(question: "where is the new chat button?", context: context))
    }

    func testTargetResolverRejectsNavigationWithoutEvidence() {
        let context = "Foreground application: ChatGPT\ntext=the new chat button is probably near the top left"
        XCTAssertNil(FelixTargetResolver.resolve(question: "where is the new chat button?", context: context))
    }

    func testTargetResolverRejectsAmbiguousControls() {
        let context = "role=AXButton | title=New chat | center_top_left=(84,96)\nrole=AXButton | title=New chat | center_top_left=(700,96)"
        XCTAssertNil(FelixTargetResolver.resolve(question: "where is the new chat button?", context: context))
    }

    func testTargetResolverReadsHelpAndIdentifierEvidence() {
        let context = "role=AXButton | identifier=new-chat | help=Start a new conversation | center_top_left=(72,110)"
        let pointer = FelixTargetResolver.resolve(question: "show me where to start a new conversation", context: context)
        XCTAssertEqual(pointer?.label, "Start a new conversation")
    }

    func testTargetResolverPrefersAccessibilityOverTranscriptOCR() {
        let context = "text=where is the new chat button? | center_top_left=(520,720)\nrole=AXButton | title=New chat | center_top_left=(84,96)"
        let pointer = FelixTargetResolver.resolve(question: "where is the new chat button?", context: context)
        XCTAssertEqual(pointer?.label, "New chat")
        XCTAssertEqual(pointer?.x, 84)
    }

    func testTargetResolverRejectsMultipleOCRMentionsAsUnambiguous() {
        let context = "text=New chat | center_top_left=(84,96)\ntext=where is the new chat button? | center_top_left=(520,720)"
        XCTAssertNil(FelixTargetResolver.resolve(question: "where is the new chat button?", context: context))
    }

    func testTeachingAnswerIsConcreteAndShort() {
        let pointer = FelixPointer(x: 100, y: 200, label: "New chat", style: "target")
        XCTAssertEqual(FelixLocalAnswerRouter.teachingAnswer(for: "can you teach me how to open a new chat", pointer: pointer), "i’ll teach you: look at new chat, then click it to start a new chat.")
    }

    func testBrowserTabActionTargetsNamedTab() {
        let action = FelixLocalAnswerRouter.browserTabAction(for: "close my youtube tab", context: "browser=Chrome\ntitle=GitHub\nurl=https://github.com")
        XCTAssertEqual(action?.toolSlug, "close_browser_tab")
        XCTAssertEqual(action?.arguments["target"]?.value as? String, "youtube")
        XCTAssertEqual(action?.arguments["browser"]?.value as? String, "Google Chrome")
    }

    func testNamedSiteResolverUsesExplicitAllowlistedHosts() {
        XCTAssertEqual(FelixNamedSiteResolver.url(for: "open youtube")?.absoluteString, "https://www.youtube.com")
        XCTAssertNil(FelixNamedSiteResolver.url(for: "open a random site"))
        XCTAssertEqual(FelixLocalAnswerRouter.namedSiteAction(for: "go to github")?.toolSlug, "open_url")
    }

    func testAutomationRequestParsesNumericCadence() {
        let request = FelixLocalAnswerRouter.automationRequest(for: "every 2 minutes click enter")
        XCTAssertEqual(request?.interval, 120)
        XCTAssertEqual(request?.description, "click enter")
        let wordRequest = FelixLocalAnswerRouter.automationRequest(for: "every two minutes, click enter")
        XCTAssertEqual(wordRequest?.interval, 120)
        XCTAssertEqual(wordRequest?.description, "click enter")
    }

    func testAutomationRequestRejectsVagueSchedules() {
        XCTAssertNil(FelixLocalAnswerRouter.automationRequest(for: "maybe every day remind me"))
        XCTAssertNil(FelixLocalAnswerRouter.automationRequest(for: "every few minutes click enter"))
    }

    func testSingleStepAgentPlanStartsReadyForVerification() {
        let plan = FelixAgentPlan.singleStep(goal: "open the app", action: nil)
        XCTAssertEqual(plan.steps.count, 1)
        XCTAssertEqual(plan.steps[0].state, "ready")
    }

    func testResponsePromotesSingleActionAndCapsPlans() {
        let action = FelixAction(kind: "local", toolSlug: "open_url", arguments: [:], summary: "open the site", requiresConfirmation: true)
        let single = FelixResponse(spokenText: "ok", action: action, pointer: nil, needsConfirmation: true, debugSummary: "test")
        XCTAssertEqual(single.actions.count, 1)
        XCTAssertEqual(single.actions.first?.toolSlug, "open_url")

        let plan = FelixResponse(spokenText: "ok", actions: Array(repeating: action, count: 8), pointer: nil, needsConfirmation: true, debugSummary: "test")
        XCTAssertEqual(plan.actions.count, 5)
    }

    @MainActor
    func testAutomationIntervalHasSafeMinimum() {
        let scheduler = FelixAutomationScheduler()
        let automation = scheduler.schedule(description: "test", interval: 1)
        XCTAssertEqual(automation.interval, 30)
        scheduler.cancel(automation.id)
    }
}
