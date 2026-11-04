import SwiftUI

// Avoid the unbundled State macro in some Command Line Tools SDKs.
typealias ViewState<Value> = SwiftUI.State<Value>

enum ThreadStatus: String, Codable, CaseIterable {
    case active = "ACTIVE"
    case waiting = "WAITING"
    case sleeping = "SLEEPING"
    case done = "DONE"

    var symbol: String {
        switch self {
        case .active: "circle.fill"
        case .waiting: "clock"
        case .sleeping: "moon"
        case .done: "checkmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .active: .green
        case .waiting: .orange
        case .sleeping, .done: .secondary
        }
    }
}

struct TimelineEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var createdAt = Date()
    var pinned = false
    var isPreviousNow = false
}

struct ChecklistItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text = ""
    var isCompleted = false
}

struct WorkThread: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var status: ThreadStatus = .active
    var now = ""
    var next = ""
    // Persist drafts separately so an interrupted edit cannot lose the old NOW.
    var nowDraft: String?
    var eventDraft: String?
    // Legacy field retained for decoding old stores and backups; migrated to NOTE.
    var checklist: [ChecklistItem]?
    var timeline: [TimelineEvent] = []
    var order = 0
    var createdAt = Date()
    var updatedAt = Date()
    var completedAt: Date?

    var checklistItems: [ChecklistItem] { checklist ?? [] }

    mutating func migrateLegacyChecklistToNote() {
        guard let checklist else { return }
        let lines = checklist.compactMap { item -> String? in
            guard !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return "\(item.isCompleted ? "✓" : "○") \(item.text)"
        }
        if !lines.isEmpty {
            next += (next.isEmpty ? "" : "\n\n") + lines.joined(separator: "\n")
        }
        // The note and consumed legacy field are persisted in one snapshot.
        // Leaving all other fields intact preserves history, drafts and dates.
        self.checklist = nil
    }

    var sortedTimeline: [TimelineEvent] {
        timeline.sorted {
            if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.createdAt > $1.createdAt
        }
    }

    static var examples: [WorkThread] {
        let date = Date()
        func event(_ text: String, hoursAgo: Double, pinned: Bool = false) -> TimelineEvent {
            TimelineEvent(text: text, createdAt: date.addingTimeInterval(-hoursAgo * 3600), pinned: pinned)
        }
        return [
            WorkThread(title: "Multi-speaker AVSR", now: "Running new calibration at +10 / +5 / 0 dB.",
                       next: "Compute bootstrap CI when runs finish.", timeline: [
                        event("Started new calibration", hoursAgo: 1),
                        event("Found threshold issue", hoursAgo: 2, pinned: true),
                        event("Reproduced baseline", hoursAgo: 4)
                       ], order: 0),
            WorkThread(title: "DLLM Continual Learning", now: "Investigating timestep-wise trajectory drift.",
                       next: "Compare trajectory divergence before and after adaptation.", timeline: [
                        event("Started timestep analysis", hoursAgo: 1.5),
                        event("Changed hypothesis", hoursAgo: 3, pinned: true)
                       ], order: 1),
            WorkThread(title: "Omni Benchmark", status: .waiting, now: "Waiting for Qwen baseline to finish.",
                       next: "Run Gemini comparison.", timeline: [
                        event("Qwen launched", hoursAgo: 2),
                        event("Benchmark setup completed", hoursAgo: 5)
                       ], order: 2)
        ]
    }
}
