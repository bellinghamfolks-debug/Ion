import Foundation
import Combine

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

    func register(email: String, password: String, displayName: String) async -> Bool {
        await run {
            let body = RegisterBody(email: email, password: password, displayName: displayName)
            let response = try await self.api.send(path: "auth/register", method: "POST", body: body, response: AuthResponse.self)
            try self.persist(response)
        }
    }

    func login(email: String, password: String) async -> Bool {
        await run {
            let body = LoginBody(email: email, password: password)
            let response = try await self.api.send(path: "auth/login", method: "POST", body: body, response: AuthResponse.self)
            try self.persist(response)
        }
    }

    func signInWithGoogle(idToken: String, displayName: String) async -> Bool {
        await run {
            let body = GoogleSignInBody(idToken: idToken, displayName: displayName)
            let response = try await self.api.send(path: "auth/google", method: "POST", body: body, response: AuthResponse.self)
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
            if case APIError.server(let status, _) = error, status == 401 {
                logout(showMessage: false)
            }
        }
    }

    func logout() { logout(showMessage: true) }

    private func logout(showMessage: Bool) {
        keychain.delete(tokenAccount)
        currentUser = nil
        isAuthenticated = false
        if showMessage { ToastCenter.shared.show(L("تم تسجيل الخروج"), style: .info) }
    }

    func deleteAccount() async -> Bool {
        guard let token else { return false }
        struct DeleteResponse: Decodable { let deleted: Bool }
        do {
            _ = try await api.send(path: "me", method: "DELETE", body: Optional<EmptyBody>.none,
                                   response: DeleteResponse.self, bearerToken: token)
            logout(showMessage: false)
            ToastCenter.shared.show(L("تم حذف الحساب من الخادم"), style: .info)
            return true
        } catch {
            lastError = friendlyMessage(for: error)
            return false
        }
    }

    private func persist(_ response: AuthResponse) throws {
        try keychain.setString(response.token, for: tokenAccount)
        currentUser = response.user
        isAuthenticated = true
        let displayName = response.user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        ToastCenter.shared.show(displayName.isEmpty ? L("تم تسجيل الدخول") : Lf("مرحبًا، %@", displayName))
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
            if message.contains("email_taken") { return L("يوجد حساب بهذا البريد بالفعل. جرّب تسجيل الدخول.") }
            if message.contains("invalid_credentials") { return L("البريد الإلكتروني أو كلمة المرور غير صحيحين.") }
            if message.contains("weak_password") { return L("استخدم كلمة مرور من 8 أحرف على الأقل، وبها حرف ورقم.") }
            if message.contains("invalid_email") { return L("تحقق من كتابة البريد الإلكتروني.") }
            if message.contains("invalid_google_token") { return LE("تعذر التحقق من حساب Google. حاول مرة أخرى.", "Google sign-in could not be verified. Please try again.") }
            if message.contains("google_not_configured") { return LE("تسجيل Google غير مهيأ على الخادم بعد.", "Google Sign-In is not configured on the server yet.") }
            if status >= 500 { return L("الخدمة غير متاحة الآن. حاول مرة أخرى بعد قليل.") }
            return Lf("تعذر إتمام الطلب. رمز الاستجابة: %@.", "\(status)")
        }
        if case APIError.missingBaseURL = error { return L("تعذر الوصول إلى خدمة EnglishNova.") }
        if case APIError.insecureBaseURL = error { return L("تعذر الاتصال لأن عنوان الخدمة غير آمن.") }
        return (error as? LocalizedError)?.errorDescription ?? L("تعذر الاتصال. تحقق من الإنترنت ثم حاول مرة أخرى.")
    }
}
