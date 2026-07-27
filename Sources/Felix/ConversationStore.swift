import Foundation

struct FelixTurn: Codable, Sendable {
    let timestamp: Date
    let question: String
    let answer: String
}

actor ConversationStore {
    private let fileURL: URL
    private var turns: [FelixTurn]

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Felix", isDirectory: true)
        fileURL = support.appendingPathComponent("conversation.json")
        turns = (try? Self.read(from: fileURL)) ?? []
    }

    func context(limit: Int = 8) -> String {
        turns.suffix(limit).map { turn in
            "User: \(turn.question)\nFelix: \(turn.answer)"
        }.joined(separator: "\n\n")
    }

    func append(question: String, answer: String) {
        turns.append(FelixTurn(timestamp: Date(), question: String(question.prefix(2_000)), answer: String(answer.prefix(4_000))))
        turns = Array(turns.suffix(40))
        try? save()
    }

    func clear() {
        turns.removeAll()
        try? save()
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(turns).write(to: fileURL, options: .atomic)
    }

    private static func read(from url: URL) throws -> [FelixTurn] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([FelixTurn].self, from: data)
    }
}
