import Foundation
import AuthenticationServices
import CryptoKit

enum AuthProvider: String, Codable {
    case apple
    case google
    case email
}

enum AuthError: LocalizedError {
    case googleNotConfigured
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .googleNotConfigured:
            return "Google sign-in needs a client ID. Add one in Shared/Secrets.swift."
        case .cancelled:
            return nil
        case .failed(let message):
            return message
        }
    }
}

/// Google OAuth via PKCE, run entirely from the device — a public client needs no server
/// and no client secret.
enum GoogleAuth {
    private static let authorizeURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    static var isConfigured: Bool { !Secrets.googleOAuthClientID.isEmpty }

    /// Google iOS clients call back on the reversed client ID: the whole identifier with the
    /// domain flipped to the front. For "123-abc.apps.googleusercontent.com" that is
    /// "com.googleusercontent.apps.123-abc" — the "123-abc" part must be kept intact.
    private static var callbackScheme: String {
        let identifier = Secrets.googleOAuthClientID
            .replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return identifier.isEmpty ? "" : "com.googleusercontent.apps.\(identifier)"
    }

    static func signIn(presentationAnchor: ASPresentationAnchor?) async throws -> (id: String, email: String?) {
        guard isConfigured else { throw AuthError.googleNotConfigured }

        let verifier = randomURLSafeString(length: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let redirectURI = "\(callbackScheme):/oauth2redirect"

        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            .init(name: "client_id", value: Secrets.googleOAuthClientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: AuthError.cancelled)
                    } else {
                        continuation.resume(throwing: AuthError.failed(error.localizedDescription))
                    }
                    return
                }
                guard let url else {
                    continuation.resume(throwing: AuthError.failed("No callback URL returned."))
                    return
                }
                continuation.resume(returning: url)
            }
            session.presentationContextProvider = PresentationProvider.shared
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw AuthError.failed("Google didn't return an authorization code.")
        }

        return try await exchange(code: code, verifier: verifier, redirectURI: redirectURI)
    }

    private static func exchange(
        code: String,
        verifier: String,
        redirectURI: String
    ) async throws -> (id: String, email: String?) {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var body = URLComponents()
        body.queryItems = [
            .init(name: "client_id", value: Secrets.googleOAuthClientID),
            .init(name: "code", value: code),
            .init(name: "code_verifier", value: verifier),
            .init(name: "grant_type", value: "authorization_code"),
            .init(name: "redirect_uri", value: redirectURI),
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "token exchange failed"
            throw AuthError.failed(message)
        }

        struct TokenResponse: Decodable { let id_token: String }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        let claims = decodeJWTClaims(token.id_token)

        guard let subject = claims["sub"] as? String else {
            throw AuthError.failed("Google response missing a user identifier.")
        }
        return (id: subject, email: claims["email"] as? String)
    }

    private static func decodeJWTClaims(_ jwt: String) -> [String: Any] {
        let segments = jwt.split(separator: ".")
        guard segments.count > 1 else { return [:] }
        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    private static func randomURLSafeString(length: Int) -> String {
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// ASWebAuthenticationSession needs a window to present over.
final class PresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PresentationProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
        #else
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #endif
    }
}
