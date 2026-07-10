import Foundation

/// Parses the strict-JSON `{thought, actions[], confidence, memory}`
/// payload every Brain implementation asks the model for, once each
/// provider has unwrapped its own response envelope down to raw model
/// text. Mirrors BrainResponseParser.kt.
enum BrainResponseParser {

    static func parse(_ rawModelText: String) throws -> BrainDecision {
        let cleaned = stripCodeFences(rawModelText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw BrainError("Brain returned non-JSON: \(cleaned.prefix(200))")
        }

        let thought = (obj["thought"] as? String) ?? ""
        let confidence: Double
        if let d = obj["confidence"] as? Double {
            confidence = d
        } else if let n = obj["confidence"] as? NSNumber {
            confidence = n.doubleValue
        } else {
            confidence = 0.5
        }
        let actionsArr = (obj["actions"] as? [[String: Any]]) ?? []
        let actions = actionsArr.compactMap { Action.from(json: $0) }
        let memoryRaw = (obj["memory"] as? String) ?? ""
        let memoryUpdate = memoryRaw.isEmpty ? nil : memoryRaw
        let goalComplete = (obj["goalComplete"] as? Bool) ?? false

        return BrainDecision(
            thought: thought,
            actions: actions,
            confidence: confidence,
            memoryUpdate: memoryUpdate,
            goalComplete: goalComplete
        )
    }

    static func stripCodeFences(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("```") else { return t }
        guard let firstNewline = t.firstIndex(of: "\n") else { return t }
        let withoutOpen = String(t[t.index(after: firstNewline)...])
        if let endRange = withoutOpen.range(of: "```", options: .backwards) {
            return String(withoutOpen[withoutOpen.startIndex..<endRange.lowerBound])
        }
        return withoutOpen
    }
}
