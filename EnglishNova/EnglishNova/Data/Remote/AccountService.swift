import Foundation
import Combine

/// Owns the signed-in account state and talks to the EnglishNova server for
/// registration, login and Sign in with Apple. The session token is kept in the
/// Keychain (encrypted at rest, this device only).
@MainActor
final class AccountService: ObservableObject {
    @Published private(set) var currentUser: AuthUser?
    @Published private(set) var isAuthenticated = false
    @Published var lastError: String?

    private let api: APIClient
    private let keychain: KeychainStore
    private let tokenAccount = "server.authToken"

    init(api: APIClient = APIClient(configuration: APIConfiguration(baseURL: nil)),
         keychain: KeychainStore = KeychainStore()) {
        self.api = api
        self.keychain = keychain
        if let token = keychain.string(for: tokenAccount), !token.isEmpty {
            isAuthenticated = true
            Task { await refreshMe() }
        }
    }

    var token: String? { keychain.string(for: tokenAccount) }

    // MARK: - Auth flows

    func register(email: String, password: String, displayName: String) async -> Bool {
        await run {
            let body = RegisterBody(email: email, password: password, displayName: displayName)
            let response = try await api.send(path: "auth/register", method: "POST",
                                              body: body, response: AuthResponse.self)
            try self.persist(response)
        }
    }

    func login(email: String, password: String) async -> Bool {
        await run {
            let body = LoginBody(email: email, password: password)
            let response = try await api.send(path: "auth/login", method: "POST",
                                              body: body, response: AuthResponse.self)
            try self.persist(response)
        }
    }

    func signInWithApple(identityToken: String, displayName: String) async -> Bool {
        await run {
            let body = AppleSignInBody(identityToken: identityToken, displayName: displayName)
            let response = try await api.send(path: "auth/apple", method: "POST",
                                              body: body, response: AuthResponse.self)
            try self.persist(response)
        }
    }

    func refreshMe() async {
        guard let token else { return }
        do {
            let response = try await api.get(path: "me", response: MeResponse.self, bearerToken: token)
            currentUser = response.user
            isAuthenticated = true
        } catch {
            // A 401 means the token is stale — sign out locally.
            if case APIError.server(let status, _) = error, status == 401 { logout() }
        }
    }

    func logout() {
        keychain.delete(tokenAccount)
        currentUser = nil
        isAuthenticated = false
    }

    // MARK: - Helpers

    private func persist(_ response: AuthResponse) throws {
        try keychain.setString(response.token, for: tokenAccount)
        currentUser = response.user
        isAuthenticated = true
    }

    private func run(_ operation: @escaping () async throws -> Void) async -> Bool {
        lastError = nil
        do {
            try await operation()
            return true
        } catch {
            lastError = friendlyMessage(for: error)
            return false
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if case APIError.server(let status, let message) = error {
            if message.contains("email_taken") { return "هذا البريد مُسجَّل بالفعل." }
            if message.contains("invalid_credentials") { return "البريد أو كلمة المرور غير صحيحة." }
            if message.contains("weak_password") { return "كلمة المرور يجب أن تكون ٨ أحرف على الأقل." }
            if message.contains("invalid_email") { return "صيغة البريد غير صحيحة." }
            return "تعذّر إتمام الطلب (\(status))."
        }
        if case APIError.missingBaseURL = error { return "لم يتم تعيين عنوان الخادم في الإعدادات." }
        if case APIError.insecureBaseURL = error { return "عنوان الخادم يجب أن يكون HTTPS صالحًا." }
        return (error as? LocalizedError)?.errorDescription ?? "تعذّر الاتصال بالخادم."
    }
}
