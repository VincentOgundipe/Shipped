import Foundation
import SwiftData

/// Everything the user has ever pasted or imported, kept permanently.
///
/// This exists to make new features backward compatible. Capture used to consume the pasted
/// text and discard it, so anything built later — re-planning, search, an Instagram importer,
/// a second goal drawn from the same material — could only ever see input from *after* that
/// feature shipped. Storing the source means new features can reach back over old material.
@Model
final class CapturedDocument {
    var text: String
    var createdAt: Date
    /// Where it came from, so importers can be told apart. Free-form rather than an enum so
    /// adding a source later needs no migration.
    var source: String
    /// Optional human label — a filename, a note title, a URL.
    var title: String?
    /// What was produced from it, for provenance: "tasks", "goal", or nil if unused so far.
    var outcome: String?
    /// Set when this document produced or fed a goal, so history is traceable.
    var relatedGoalTitle: String?

    init(
        text: String,
        source: String,
        title: String? = nil,
        outcome: String? = nil,
        relatedGoalTitle: String? = nil,
        createdAt: Date = .now
    ) {
        self.text = text
        self.source = source
        self.title = title
        self.outcome = outcome
        self.relatedGoalTitle = relatedGoalTitle
        self.createdAt = createdAt
    }

    /// First line, for listing without dumping the whole document.
    var preview: String {
        let firstLine = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? text
        return firstLine.count > 90 ? String(firstLine.prefix(90)) + "…" : firstLine
    }

    var wordCount: Int {
        text.split(whereSeparator: \.isWhitespace).count
    }
}

enum CaptureSource {
    static let paste = "paste"
    static let notion = "notion"
    static let instagram = "instagram-export"
    static let file = "file"
}

// MARK: - Schema policy
//
// Every model change must be additive so existing stores keep working:
//
//  1. New properties get a default value (`var x: Bool = false`) or are optional. SwiftData's
//     lightweight migration then opens old stores untouched — this is how `isArchived`,
//     `restDays`, `planSnapshot` and `completedAt` were added without losing the live goal.
//  2. Never rename or delete a property in place. Add the new one, migrate in code, and leave
//     the old one until nothing reads it.
//  3. Prefer `String` over `enum` for stored discriminators (see `source` above) so adding a
//     case is not a schema change.
//  4. New entities are additive too — appending `CapturedDocument.self` to the schema does
//     not disturb `Goal` or `DailyTask`.
//  5. Preserve *inputs*, not just outputs. A feature that consumes data and throws the source
//     away caps what every later feature can do.
