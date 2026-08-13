import Foundation
import SwiftData

/// A single turn of the coach conversation. Stored in the App Group store like everything
/// else — the transcript never leaves the device except as the prompt for the next reply.
@Model
final class ChatMessage {
    var roleRaw: String
    var text: String
    var createdAt: Date

    init(role: ChatRole, text: String, createdAt: Date = .now) {
        self.roleRaw = role.rawValue
        self.text = text
        self.createdAt = createdAt
    }

    var role: ChatRole {
        get { ChatRole(rawValue: roleRaw) ?? .user }
        set { roleRaw = newValue.rawValue }
    }
}

enum ChatRole: String, Codable {
    case user
    case assistant
}
