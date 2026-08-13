import Foundation

enum ClaudeClientError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited
    case offline
    case serverError
    case decodingFailed

    /// Plain sentences that say what went wrong and what to do. Raw API payloads are for
    /// the console, never for the screen.
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key yet. Paste one into Shared/Secrets.swift and rebuild."
        case .invalidAPIKey:
            return "That API key was rejected. Check it in Shared/Secrets.swift."
        case .rateLimited:
            return "Too many requests just now. Wait a moment and try again."
        case .offline:
            return "No connection. Check your network and try again."
        case .serverError:
            return "Claude is having trouble right now. Try again in a minute."
        case .decodingFailed:
            return "The plan came back malformed. Try again."
        }
    }

    /// Maps an HTTP status onto the user-facing case, keeping the raw body in the log only.
    static func from(status: Int, body: String) -> ClaudeClientError {
        #if DEBUG
        print("[ClaudeClient] HTTP \(status): \(body)")
        #endif
        switch status {
        case 401, 403: return .invalidAPIKey
        case 429: return .rateLimited
        case 500...599: return .serverError
        default: return .serverError
        }
    }
}

struct TaskDraft: Decodable, Identifiable, Hashable {
    let date: String
    let title: String

    var id: String { "\(date)|\(title)" }

    var parsedDate: Date? {
        ClaudeClient.dayFormatter.date(from: date)
    }
}

enum ClaudeClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-sonnet-4-5-20250929"

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar.appDefault
        f.timeZone = .current
        return f
    }()

    private static let coachPersona = """
    You are a blunt, practical execution coach. You do not motivate, you schedule. \
    Every task you write is a specific action with a visible finish line — never \
    "research X", "think about Y", or "stay consistent".
    """

    // MARK: - First plan

    static func generatePlan(
        goalTitle: String,
        deadline: Date,
        capacity: Capacity,
        sourceMaterial: String? = nil
    ) async throws -> [TaskDraft] {
        let today = dayFormatter.string(from: .now)
        let deadlineString = dayFormatter.string(from: deadline)

        // When the user already has a real plan (a workout split, a syllabus, ...), the job
        // is to schedule THEIR content across the days, not invent generic substitute tasks
        // that happen to share its title.
        let sourceBlock = sourceMaterial.map {
            """


            The user already has their own plan for this, pasted below. Use it as the actual
            source of the day-by-day work — carry over its real structure (specific
            exercises, sections, topics, whatever it contains) rather than inventing generic
            tasks. Only fill gaps it doesn't cover.

            THEIR PLAN:
            \($0.prefix(12000))
            """
        } ?? ""

        let prompt = """
        \(coachPersona)

        Goal: \(goalTitle)
        Start date: \(today)
        Deadline: \(deadlineString)
        Time available: \(capacity.promptDescription)
        \(sourceBlock)

        Reverse-engineer this goal into a day-by-day plan from the start date through \
        the deadline. Rules:
        - One task per day. Size each task to the time available stated above.
        - Tasks must compound — each one should depend on or build from earlier ones.
        - Front-load the work that unblocks everything else.
        - It is fine to leave a rest day roughly once a week; omit those dates entirely.
        """

        return try await requestDrafts(prompt: prompt)
    }

    // MARK: - Recut after falling behind

    /// Redistributes unfinished work across the days that are left.
    /// - Parameter keepingDeadline: true compresses the remaining work into the existing
    ///   deadline (denser days); false spreads it at the original pace past the deadline.
    static func recutPlan(
        goalTitle: String,
        newDeadline: Date,
        capacity: Capacity,
        missedDayCount: Int,
        unfinishedTasks: [String],
        remainingTasks: [String],
        keepingDeadline: Bool
    ) async throws -> [TaskDraft] {
        let today = dayFormatter.string(from: .now)
        let deadlineString = dayFormatter.string(from: newDeadline)

        let pressure = keepingDeadline
            ? """
              The deadline is NOT moving. Absorb the dropped work into the days that \
              remain, even though that makes each day heavier than the stated capacity. \
              Say plainly in the task titles what got compressed.
              """
            : """
              The deadline has been pushed to absorb the missed days. Keep daily load at \
              the stated capacity — the cost of falling behind is time, not intensity.
              """

        let prompt = """
        \(coachPersona)

        The user fell behind on this goal and is recommitting today.

        Goal: \(goalTitle)
        Today: \(today)
        Deadline: \(deadlineString)
        Time available: \(capacity.promptDescription)
        Days missed: \(missedDayCount)

        Work that was scheduled and never done:
        \(unfinishedTasks.isEmpty ? "(none)" : unfinishedTasks.map { "- \($0)" }.joined(separator: "\n"))

        Work still scheduled ahead:
        \(remainingTasks.isEmpty ? "(none)" : remainingTasks.map { "- \($0)" }.joined(separator: "\n"))

        \(pressure)

        Rebuild the plan from today through the deadline. Merge the dropped work back in \
        where it makes sense — drop anything now genuinely unnecessary rather than padding.
        """

        return try await requestDrafts(prompt: prompt)
    }

    // MARK: - Captured text

    /// Slots pasted work into the days that are left, without disturbing what's already
    /// scheduled — the point is to fold a brain dump into the plan, not flood today.
    static func scheduleCapturedWork(
        capturedText: String,
        goalTitle: String,
        deadline: Date,
        capacity: Capacity,
        existingUpcoming: [String]
    ) async throws -> [TaskDraft] {
        let today = dayFormatter.string(from: .now)
        let deadlineString = dayFormatter.string(from: deadline)

        let prompt = """
        \(coachPersona)

        The user pasted some notes and wants the real work in them folded into the plan
        they're already running.

        Goal: \(goalTitle)
        Today: \(today)
        Deadline: \(deadlineString)
        Time available per day: \(capacity.promptDescription)

        Already scheduled ahead (do not duplicate these):
        \(existingUpcoming.isEmpty ? "(nothing)" : existingUpcoming.map { "- \($0)" }.joined(separator: "\n"))

        PASTED NOTES:
        \(capturedText.prefix(12000))

        Extract only concrete, actionable work that genuinely serves the goal. Ignore
        journaling, reference material, and anything already scheduled. Spread what's left
        across days from tomorrow to the deadline, respecting the daily time available, and
        prefer days that currently look lighter. Return nothing but the new tasks — do not
        restate existing ones.
        """

        return try await requestDrafts(prompt: prompt)
    }

    // MARK: - Capacity-aware timeline

    struct TimelineEstimate: Decodable {
        let days: Int
        let rationale: String
    }

    /// Given how much time the user can actually give it, estimates a realistic deadline —
    /// asked before the user picks one, not after, so the deadline is informed by capacity
    /// instead of the two being picked independently and only reconciled by however hard
    /// `generatePlan` has to squeeze the days that result.
    static func estimateGoalTimeline(goalTitle: String, capacity: Capacity) async throws -> TimelineEstimate {
        let prompt = """
        Goal: \(goalTitle)
        Time available: \(capacity.promptDescription)

        Estimate a realistic number of days to hit this goal at that pace. Be honest, not
        optimistic — a plan built on a rushed estimate is the one that gets abandoned.
        """

        let data = try await sendForStructuredOutput(
            prompt: prompt,
            toolName: "submit_estimate",
            toolDescription: "Submit the realistic timeline estimate.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "days": ["type": "integer"],
                    "rationale": ["type": "string", "description": "One short sentence explaining the estimate"],
                ],
                "required": ["days", "rationale"],
            ]
        )
        guard let estimate = try? JSONDecoder().decode(TimelineEstimate.self, from: data) else {
            throw ClaudeClientError.decodingFailed
        }
        return estimate
    }

    // MARK: - Routines

    struct RoutineActivityDraft: Decodable {
        /// 1=Sunday...7=Saturday, or nil if it runs every day the routine is active.
        let weekday: Int?
        let title: String
    }

    /// Builds a routine's per-day activities — either preserving a plan the user already has,
    /// or designing one from a short description, depending on `isExistingPlan`. Mirrors
    /// `generatePlan`'s `sourceMaterial` handling: when the user already has a real plan, the
    /// job is to schedule THEIR content, not invent a substitute that shares only its shape.
    static func generateRoutineActivities(
        title: String,
        activeWeekdays: [Int],
        capacity: Capacity,
        sourceMaterial: String,
        isExistingPlan: Bool
    ) async throws -> [RoutineActivityDraft] {
        let weekdayList = activeWeekdays.sorted().map { Weekday.full($0) }.joined(separator: ", ")

        let sourceInstruction = isExistingPlan
            ? """
              The user already has their own plan for this, pasted below. Preserve its real
              structure (specific exercises, sections, whatever it contains) rather than
              inventing generic activities. If it already specifies which day does what, honor
              that mapping onto the days listed above; otherwise spread its content across
              those days sensibly.
              """
            : """
              The user described what they want below. Design activities for the days listed
              above that genuinely deliver on that description.
              """

        let prompt = """
        \(coachPersona)

        Routine: \(title)
        Runs on: \(weekdayList)
        Time available per session: \(capacity.promptDescription)

        \(sourceInstruction)

        \(isExistingPlan ? "THEIR PLAN" : "WHAT THEY WANT"):
        \(sourceMaterial.prefix(12000))

        One activity per day listed above. If the same thing happens every day it runs, return
        a single activity with no weekday attached rather than repeating it for each day.
        """

        let data = try await sendForStructuredOutput(
            prompt: prompt,
            toolName: "submit_activities",
            toolDescription: "Submit the routine's per-day activities.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "activities": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "weekday": [
                                    "type": ["integer", "null"],
                                    "description": "1=Sunday...7=Saturday, or null if it runs every active day",
                                ],
                                "title": ["type": "string"],
                            ],
                            "required": ["weekday", "title"],
                        ],
                    ],
                ],
                "required": ["activities"],
            ]
        )
        struct Wrapper: Decodable { let activities: [RoutineActivityDraft] }
        guard let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data) else {
            throw ClaudeClientError.decodingFailed
        }
        return wrapper.activities
    }

    struct GoalSuggestion: Decodable {
        let title: String
        let days: Int
        /// Populated when the notes are too vague to commit to a goal yet.
        var questions: [String]?

        var needsClarification: Bool { !(questions ?? []).isEmpty }
    }

    /// Reads pasted text and either proposes a goal, or asks what it needs to know first.
    ///
    /// Vague notes produce vague goals, and a vague goal produces a plan the user abandons —
    /// so the model is explicitly allowed to come back with questions instead of guessing.
    /// - Parameter answers: previously asked question/answer pairs, fed back on the second pass.
    static func suggestGoal(
        from capturedText: String,
        answers: [(question: String, answer: String)] = []
    ) async throws -> GoalSuggestion {
        let answerBlock = answers.isEmpty ? "" : """

        The user has already answered these:
        \(answers.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n\n"))
        """

        let clarifyRule = answers.isEmpty ? """
        If the notes are too vague to name a specific, testable goal — no clear outcome, no
        way to tell whether it was hit, or several unrelated threads with no obvious primary
        one — do NOT guess. Return up to three short, concrete questions instead, each
        answerable in a sentence.
        """ : """
        The user has answered your questions. Commit to a goal now; do not ask more.
        """

        let prompt = """
        Below is text the user pasted. Identify the single most plausible goal they are
        working toward, phrased the way they would say it — specific and testable, under 90
        characters. Then estimate a realistic number of days to hit it.

        \(clarifyRule)

        TEXT:
        \(capturedText.prefix(12000))
        \(answerBlock)
        """

        let data = try await sendForStructuredOutput(
            prompt: prompt,
            toolName: "submit_goal",
            toolDescription: "Submit the identified goal, or clarifying questions if the notes are too vague.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "The goal, empty string if asking questions instead"],
                    "days": ["type": "integer", "description": "Realistic number of days to hit it, 0 if asking questions instead"],
                    "questions": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Up to three clarifying questions; empty if the goal is clear",
                    ],
                ],
                "required": ["title", "days", "questions"],
            ]
        )
        guard let suggestion = try? JSONDecoder().decode(GoalSuggestion.self, from: data) else {
            throw ClaudeClientError.decodingFailed
        }
        return suggestion
    }

    // MARK: - Coach chat

    /// A conversational reply. History is passed in full each time; nothing is stored server
    /// side, and the transcript lives only in the local store.
    static func chatReply(
        history: [(role: String, text: String)],
        goalContext: String?
    ) async throws -> String {
        guard let apiKey = Secrets.anthropicAPIKey.isEmpty ? nil : Secrets.anthropicAPIKey else {
            throw ClaudeClientError.missingAPIKey
        }

        var system = """
        \(coachPersona)

        You are talking with the user about their execution. Be brief — two or three
        sentences unless they ask for depth. Push for specifics. If they describe work, offer
        to turn it into scheduled tasks rather than doing it for them.
        """
        if let goalContext {
            system += "\n\nTheir current goal: \(goalContext)"
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": system,
            "messages": history.map { ["role": $0.role, "content": $0.text] },
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeClientError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw ClaudeClientError.serverError }
        guard http.statusCode == 200 else {
            throw ClaudeClientError.from(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        struct MessageResponse: Decodable {
            struct Block: Decodable { let text: String? }
            let content: [Block]
        }
        let decoded = try JSONDecoder().decode(MessageResponse.self, from: data)
        guard let reply = decoded.content.first(where: { $0.text != nil })?.text else {
            throw ClaudeClientError.decodingFailed
        }
        return reply
    }

    // MARK: - Transport

    private struct DraftsWrapper: Decodable { let tasks: [TaskDraft] }

    private static func requestDrafts(prompt: String) async throws -> [TaskDraft] {
        let data = try await sendForStructuredOutput(
            prompt: prompt,
            toolName: "submit_plan",
            toolDescription: "Submit the day-by-day task plan.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "tasks": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "date": ["type": "string", "description": "YYYY-MM-DD"],
                                "title": ["type": "string"],
                            ],
                            "required": ["date", "title"],
                        ],
                    ],
                ],
                "required": ["tasks"],
            ]
        )
        guard let wrapper = try? JSONDecoder().decode(DraftsWrapper.self, from: data) else {
            throw ClaudeClientError.decodingFailed
        }
        return wrapper.tasks.filter { $0.parsedDate != nil }
    }

    /// Forces the model's reply through a single tool call matching `inputSchema`, so the
    /// result is always schema-valid JSON — no "please respond with ONLY json" prompting and
    /// no fragile regex-style extraction of a JSON blob out of free text, both of which fail
    /// silently the moment the model adds a stray sentence of commentary.
    private static func sendForStructuredOutput(
        prompt: String,
        toolName: String,
        toolDescription: String,
        inputSchema: [String: Any]
    ) async throws -> Data {
        guard let apiKey = Secrets.anthropicAPIKey.isEmpty ? nil : Secrets.anthropicAPIKey else {
            throw ClaudeClientError.missingAPIKey
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8192,
            "temperature": 0.4,
            "tools": [[
                "name": toolName,
                "description": toolDescription,
                "input_schema": inputSchema,
            ]],
            "tool_choice": ["type": "tool", "name": toolName],
            "messages": [["role": "user", "content": prompt]],
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeClientError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw ClaudeClientError.serverError }
        guard http.statusCode == 200 else {
            throw ClaudeClientError.from(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = root["content"] as? [[String: Any]],
            let toolUse = content.first(where: { $0["type"] as? String == "tool_use" }),
            let input = toolUse["input"]
        else {
            throw ClaudeClientError.decodingFailed
        }
        return try JSONSerialization.data(withJSONObject: input)
    }

}
