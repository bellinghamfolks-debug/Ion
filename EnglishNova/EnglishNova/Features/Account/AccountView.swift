import SwiftUI
import PhotosUI
import GoogleSignIn
import GoogleSignInSwift
import UIKit

struct AccountView: View {
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var sync: ProgressSyncService
    @StateObject private var avatar = AvatarStore.shared

    @State private var showSignOutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isWorking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if account.isAuthenticated { signedInContent } else { authForm }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(L("الحساب"))
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { avatar.save($0) }.ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    avatar.save(image)
                }
            }
        }
    }

    private var avatarCircle: some View {
        Group {
            if let image = avatar.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.fill").font(.system(size: 38)).foregroundStyle(.white)
            }
        }
        .frame(width: 92, height: 92)
        .background(.white.opacity(0.2))
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
    }

    private var signedInContent: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Menu {
                    Button { showCamera = true } label: { Label(L("التقط صورة"), systemImage: "camera") }
                    Button { showPhotoPicker = true } label: { Label(L("اختر من الصور"), systemImage: "photo") }
                    if avatar.image != nil {
                        Button(role: .destructive) { avatar.clear() } label: { Label(L("إزالة الصورة"), systemImage: "trash") }
                    }
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        avatarCircle
                        Image(systemName: "pencil.circle.fill").font(.title3).foregroundStyle(AppTheme.brand, .white)
                    }
                }
                .accessibilityLabel(L("تغيير صورة الحساب"))

                Text(displayedAccountName).font(.title3.bold()).foregroundStyle(.white)
                if let email = account.currentUser?.email {
                    Text(email).font(.footnote).foregroundStyle(.white.opacity(0.85)).environment(\.layoutDirection, .leftToRight)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))

            InfoCard(title: L("المزامنة"), systemImage: "arrow.triangle.2.circlepath", tint: AppTheme.accentTeal) {
                Text(L("احفظ نسخة من تقدّمك في حسابك لتستعيدها على جهاز آخر. المزامنة تشمل بيانات التعلّم والإعدادات التي يدعمها النسخ الاحتياطي."))
                    .font(.footnote).foregroundStyle(.secondary)
                if let when = sync.lastSyncedAt {
                    LabeledContent(L("آخر مزامنة"), value: when.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                }
                PrimaryButton(title: L("حفظ التقدّم في الحساب"), systemImage: "icloud.and.arrow.up", isLoading: sync.isSyncing) {
                    Task { await sync.push() }
                }
                Button { Task { await sync.pull() } } label: {
                    Label(L("استعادة التقدّم المحفوظ"), systemImage: "icloud.and.arrow.down").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered).disabled(sync.isSyncing)
                if let message = sync.syncMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
            }

            Button(role: .destructive) { showSignOutConfirm = true } label: {
                Label(L("تسجيل الخروج"), systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .confirmationDialog(L("تسجيل الخروج؟"), isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button(L("تسجيل الخروج"), role: .destructive) {
                    GIDSignIn.sharedInstance.signOut()
                    account.logout()
                }
                Button(L("إلغاء"), role: .cancel) {}
            } message: {
                Text(L("سيبقى تقدّمك المحلي على هذا الجهاز. تأكد من المزامنة إذا أردت استعادته على جهاز آخر."))
            }

            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label(L("حذف الحساب"), systemImage: "trash").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered).tint(.red)
            .confirmationDialog(L("حذف الحساب نهائيًا؟"), isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button(L("حذف الحساب"), role: .destructive) { Task { await account.deleteAccount() } }
                Button(L("إلغاء"), role: .cancel) {}
            } message: {
                Text(L("سيُحذف الحساب والتقدّم المتزامن من خادم EnglishNova. هذا الإجراء لا يحذف تلقائيًا البيانات المحلية الموجودة على جهازك."))
            }
        }
    }

    private var authForm: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.checkmark").font(.system(size: 44)).foregroundStyle(AppTheme.brand)
                Text(L("زامن تقدّمك بين أجهزتك")).font(.title3.bold())
                Text(L("الحساب اختياري للتعلّم المحلي، ومفيد للمزامنة وميزات المدرّب عبر الإنترنت."))
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            GoogleSignInButton {
                Task { await signInWithGoogle() }
            }
            .frame(minHeight: AppTheme.minimumTapHeight)
            .accessibilityLabel(LE("تسجيل الدخول باستخدام Google", "Sign in with Google"))

            Text(LE(
                "يتم التحقق من رمز هوية Google على خادم EnglishNova ثم تُنشأ جلسة التطبيق. لا يعتمد الخادم على معرّف مستخدم غير موثّق من الهاتف.",
                "Your Google ID token is verified by the EnglishNova server before an app session is created."
            ))
            .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)

            HStack {
                Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
                Text(L("أو")).font(.caption).foregroundStyle(.secondary)
                Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
            }

            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { option in Text(option.title).tag(option) }
            }
            .pickerStyle(.segmented)

            InfoCard(title: mode.title, systemImage: mode == .signIn ? "lock.open.fill" : "person.badge.plus") {
                if mode == .register { field(L("اسم العرض"), text: $displayName, systemImage: "person", keyboard: .default) }
                field(L("البريد الإلكتروني"), text: $email, systemImage: "envelope", keyboard: .emailAddress)
                secureField(L("كلمة المرور"), text: $password)
                if mode == .register {
                    Label(L("استخدم 8 أحرف على الأقل، مع حرف ورقم."), systemImage: passwordStrong ? "checkmark.circle.fill" : "info.circle")
                        .font(.caption2).foregroundStyle(passwordStrong ? AppTheme.success : .secondary)
                }
                if let error = account.lastError { Text(error).font(.caption).foregroundStyle(.red) }
                PrimaryButton(title: mode.title, systemImage: mode == .signIn ? "arrow.right.circle.fill" : "person.badge.plus",
                              isLoading: isWorking, isDisabled: !canSubmit) {
                    Task { await submit() }
                }
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, systemImage: String, keyboard: UIKeyboardType) -> some View {
        HStack {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 22)
            TextField(title, text: text).keyboardType(keyboard).textInputAutocapitalization(.never).autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
        }
        .padding(12).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func secureField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 22)
            SecureField(title, text: text).textInputAutocapitalization(.never).autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
        }
        .padding(12).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private var displayedAccountName: String {
        let name = account.currentUser?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !name.isEmpty ? name : (account.currentUser?.email ?? L("حسابك"))
    }

    private var passwordStrong: Bool {
        password.count >= 8 && password.contains(where: { $0.isLetter }) && password.contains(where: { $0.isNumber })
    }

    private var canSubmit: Bool {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else { return false }
        return mode == .signIn || passwordStrong
    }

    @MainActor private func submit() async {
        isWorking = true
        defer { isWorking = false }
        let ok: Bool
        if mode == .register {
            ok = await account.register(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password,
                                        displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            ok = await account.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        }
        if ok { await sync.pull() }
    }

    @MainActor private func signInWithGoogle() async {
        account.lastError = nil
        guard let clientID = configuredValue("GIDClientID"), let serverClientID = configuredValue("GIDServerClientID") else {
            account.lastError = LE(
                "تسجيل Google مدمج، لكن معرّفات OAuth الخاصة بمشروع EnglishNova لم تُضبط في البناء بعد.",
                "Google Sign-In is integrated, but this build is missing the EnglishNova OAuth client IDs."
            )
            return
        }
        guard let presenter = presentingViewController() else {
            account.lastError = LE("تعذر فتح نافذة Google الآن.", "Google Sign-In could not be presented.")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID, serverClientID: serverClientID)
            let result = try await googleSignIn(presenting: presenter)
            guard let idToken = result.user.idToken?.tokenString, !idToken.isEmpty else {
                account.lastError = LE("لم يعُد Google برمز هوية صالح.", "Google did not return a valid ID token.")
                return
            }
            let name = result.user.profile?.name ?? ""
            if await account.signInWithGoogle(idToken: idToken, displayName: name) { await sync.pull() }
        } catch {
            account.lastError = LE("لم يكتمل تسجيل الدخول باستخدام Google.", "Google Sign-In did not complete.")
        }
    }

    private func configuredValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }

    private func presentingViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
    }

    private func googleSignIn(presenting presenter: UIViewController) async throws -> GIDSignInResult {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
                if let error { continuation.resume(throwing: error) }
                else if let result { continuation.resume(returning: result) }
                else { continuation.resume(throwing: CancellationError()) }
            }
        }
    }

    private enum Mode: String, CaseIterable {
        case signIn, register
        var title: String { self == .signIn ? L("تسجيل الدخول") : L("إنشاء حساب") }
    }
}
