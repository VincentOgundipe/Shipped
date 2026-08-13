import Foundation

/// Talks to Supabase's REST API (PostgREST) directly over HTTPS — no SDK dependency, same
/// pattern as `ClaudeClient` and `NotionClient` already in this file's neighbourhood.
enum SupabaseSyncError: LocalizedError {
    case notConfigured
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Sync isn't set up yet. Add your Supabase URL, key, and pairing ID to Secrets.swift."
        case .badResponse(let message):
            return "Sync failed: \(message)"
        }
    }
}

/// Wire format for one row. Both tables share enough shape that a single struct with
/// optional fields covers them, rather than two near-identical types.
struct SyncRow: Codable {
    var id: UUID
    var sync_group: String
    var goal_id: UUID?
    var title: String
    var deadline: Date?
    var original_deadline: Date?
    var created_at: Date?
    var capacity: String?
    var check_in_hour: Int?
    var recut_count: Int?
    var is_archived: Bool?
    var completed_at: Date?
    var rest_days: [Date]?
    var plan_snapshot: [String: String]?
    var date: Date?
    var is_done: Bool?
    var task_order: Int?
    var updated_at: Date
    var deleted: Bool = false
}

enum SupabaseSync {
    static var isConfigured: Bool {
        !Secrets.supabaseURL.isEmpty && !Secrets.supabaseAnonKey.isEmpty && !Secrets.syncGroupID.isEmpty
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static func request(path: String, method: String) throws -> URLRequest {
        guard isConfigured else { throw SupabaseSyncError.notConfigured }
        var request = URLRequest(url: URL(string: "\(Secrets.supabaseURL)/rest/v1/\(path)")!)
        request.httpMethod = method
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Secrets.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return request
    }

    /// Upsert-by-id: creates or overwrites, keyed on the primary key both tables share.
    static func upsert(table: String, rows: [SyncRow]) async throws {
        guard !rows.isEmpty else { return }
        var request = try request(path: "\(table)?on_conflict=id", method: "POST")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(rows)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SupabaseSyncError.badResponse(String(data: data, encoding: .utf8) ?? "unknown")
        }
    }

    /// Everything for this pairing group changed after `since`. Pass `.distantPast` for a
    /// full pull (first sync on a fresh device).
    static func fetchChanged(table: String, since: Date) async throws -> [SyncRow] {
        let sinceString = ISO8601DateFormatter().string(from: since)
        let query = "sync_group=eq.\(Secrets.syncGroupID)&updated_at=gt.\(sinceString)&order=updated_at.asc"
        let request = try request(path: "\(table)?\(query)", method: "GET")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SupabaseSyncError.badResponse(String(data: data, encoding: .utf8) ?? "unknown")
        }
        return try decoder.decode([SyncRow].self, from: data)
    }
}
