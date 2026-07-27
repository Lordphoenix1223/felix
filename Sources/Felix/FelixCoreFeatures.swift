import AppKit
import Foundation

enum FelixStorage {
    static func directory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Felix", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            let probe = support.appendingPathComponent(".write-probe-\(UUID().uuidString)")
            try Data().write(to: probe, options: .atomic)
            try? FileManager.default.removeItem(at: probe)
            return support
        } catch {
            return FileManager.default.temporaryDirectory.appendingPathComponent("Felix", isDirectory: true)
        }
    }
}

struct FelixPreferences: Codable, Sendable {
    var answerStyle: String = "short, conversational, lowercase"
    var speechRate: Double = 170
    var modelMode: String = "automatic"
    var rememberConversation: Bool = true

    private static let key = "Felix.preferences"

    static func load() -> FelixPreferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(FelixPreferences.self, from: data) else { return FelixPreferences() }
        return value
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}

struct FelixActionRecord: Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let action: String
    let summary: String
    let result: String
    let undoable: Bool
}

actor FelixActionHistory {
    private var records: [FelixActionRecord] = []
    private let fileURL: URL

    init() {
        fileURL = FelixStorage.directory().appendingPathComponent("actions.json")
        records = (try? Self.read(from: fileURL)) ?? []
    }

    func append(action: FelixAction, result: String, undoable: Bool) {
        records.append(FelixActionRecord(id: UUID(), timestamp: Date(), action: action.toolSlug,
            summary: String(action.summary.prefix(300)), result: String(result.prefix(600)), undoable: undoable))
        records = Array(records.suffix(100))
        try? save()
    }

    func recent(limit: Int = 10) -> [FelixActionRecord] { Array(records.suffix(limit).reversed()) }

    func latest() -> FelixActionRecord? { records.last }

    func clear() {
        records.removeAll()
        try? save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: fileURL, options: .atomic)
    }

    private static func read(from url: URL) throws -> [FelixActionRecord] {
        try JSONDecoder().decode([FelixActionRecord].self, from: Data(contentsOf: url))
    }
}

struct FelixUndoRecord: Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let kind: String
    let summary: String
    let arguments: [String: String]
}

actor FelixUndoStore {
    private var record: FelixUndoRecord?
    private let fileURL: URL

    init() {
        fileURL = FelixStorage.directory().appendingPathComponent("last-undo.json")
        record = try? JSONDecoder().decode(FelixUndoRecord.self, from: Data(contentsOf: fileURL))
    }

    func save(kind: String, summary: String, arguments: [String: String]) {
        record = FelixUndoRecord(id: UUID(), timestamp: Date(), kind: kind, summary: summary, arguments: arguments)
        try? persist()
    }

    func latest() -> FelixUndoRecord? { record }

    func clear() {
        record = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: fileURL, options: .atomic)
    }
}

struct FelixTeachingStep: Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let instruction: String
    let beforeContext: String
    let afterContext: String?
    let target: String?
    let result: String
}

actor FelixTeachingStore {
    private var steps: [FelixTeachingStep] = []
    private let fileURL: URL

    init() {
        fileURL = FelixStorage.directory().appendingPathComponent("teaching-steps.json")
        steps = (try? JSONDecoder().decode([FelixTeachingStep].self, from: Data(contentsOf: fileURL))) ?? []
    }

    func append(instruction: String, beforeContext: String, afterContext: String?, target: String?, result: String) {
        steps.append(FelixTeachingStep(id: UUID(), timestamp: Date(), instruction: String(instruction.prefix(500)), beforeContext: String(beforeContext.prefix(3000)), afterContext: afterContext.map { String($0.prefix(3000)) }, target: target, result: String(result.prefix(1000))))
        steps = Array(steps.suffix(50))
        try? persist()
    }

    func recent(limit: Int = 5) -> [FelixTeachingStep] { Array(steps.suffix(limit).reversed()) }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(steps).write(to: fileURL, options: .atomic)
    }
}

struct FelixAgentStep: Codable, Sendable {
    let id: UUID
    let summary: String
    let actionSlug: String?
    var state: String
}

struct FelixAgentPlan: Codable, Sendable {
    let id: UUID
    let goal: String
    var steps: [FelixAgentStep]

    static func singleStep(goal: String, action: FelixAction?) -> FelixAgentPlan {
        FelixAgentPlan(id: UUID(), goal: goal, steps: [FelixAgentStep(id: UUID(), summary: action?.summary ?? goal,
            actionSlug: action?.toolSlug, state: "ready")])
    }
}

enum FelixNamedSiteResolver {
    static func url(for request: String) -> URL? {
        let value = request.lowercased()
        let sites: [(terms: [String], host: String)] = [
            (["youtube"], "https://www.youtube.com"), (["github"], "https://github.com"),
            (["google drive", "drive"], "https://drive.google.com"), (["notion"], "https://www.notion.so"),
            (["gmail", "email"], "https://mail.google.com")
        ]
        guard let site = sites.first(where: { $0.terms.contains(where: { value.contains($0) }) }) else { return nil }
        return URL(string: site.host)
    }
}

struct FelixAutomation: Codable, Sendable {
    let id: UUID
    let description: String
    let interval: TimeInterval
    var state: String
    let createdAt: Date
}

@MainActor
final class FelixAutomationScheduler: NSObject {
    private(set) var automations: [FelixAutomation] = []
    private var timers: [UUID: Timer] = [:]
    private let fileURL: URL
    var onTick: ((FelixAutomation) -> Void)?

    override init() {
        fileURL = FelixStorage.directory().appendingPathComponent("automations.json")
        automations = (try? JSONDecoder().decode([FelixAutomation].self, from: Data(contentsOf: fileURL))) ?? []
        super.init()
        automations.filter { $0.state == "active" }.forEach(arm)
    }

    func schedule(description: String, interval: TimeInterval) -> FelixAutomation {
        let automation = FelixAutomation(id: UUID(), description: description, interval: max(30, interval), state: "active", createdAt: Date())
        automations.append(automation)
        arm(automation)
        persist()
        return automation
    }

    func pause(_ id: UUID) { setState(id, state: "paused"); timers[id]?.invalidate(); timers[id] = nil; persist() }
    func resume(_ id: UUID) {
        guard let automation = automations.first(where: { $0.id == id }) else { return }
        setState(id, state: "active")
        arm(automation)
        persist()
    }
    func cancel(_ id: UUID) { timers[id]?.invalidate(); timers[id] = nil; automations.removeAll { $0.id == id }; persist() }

    func activeAutomation() -> FelixAutomation? { automations.last(where: { $0.state == "active" }) }

    private func arm(_ automation: FelixAutomation) {
        timers[automation.id]?.invalidate()
        timers[automation.id] = Timer.scheduledTimer(withTimeInterval: automation.interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let current = self.automations.first(where: { $0.id == automation.id }), current.state == "active" else { return }
                self.onTick?(current)
            }
        }
    }

    private func setState(_ id: UUID, state: String) {
        guard let index = automations.firstIndex(where: { $0.id == id }) else { return }
        automations[index].state = state
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(automations).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Felix automation persistence failed: %@", error.localizedDescription)
        }
    }
}
