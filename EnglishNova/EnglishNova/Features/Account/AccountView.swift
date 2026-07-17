import SwiftUI
import AuthenticationServices
import PhotosUI

/// Account screen: create an account or sign in (email/password + Sign in with
/// Apple), then sync progress to/from the server.
struct AccountView: View {
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var sync: ProgressSyncService
    @StateObject private var avatar = AvatarStore.shared
    @State private var showSignOutConfirm = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showCamera = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if account.isAuthenticated {
                    signedInContent
                } else {
                    authForm
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle("الحساب والمزامنة")
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { avatar.save($0) }.ignoresSafeArea()
        }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
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
                Image(systemName: "person.fill")
                    .font(.system(size: 38)).foregroundStyle(.white)
            }
        }
        .frame(width: 92, height: 92)
        .background(.white.opacity(0.2))
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
    }

    // MARK: - Signed in

    private var signedInContent: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Menu {
                    Button { showCamera = true } label: { Label("التقاط بالكاميرا", systemImage: "camera") }
                    Button { showPhotoPicker = true } label: { Label("اختيار من الصور", systemImage: "photo") }
                    if avatar.image != nil {
                        Button(role: .destructive) { avatar.clear() } label: { Label("إزالة الصورة", systemImage: "trash") }
                    }
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        avatarCircle
                        Image(systemName: "pencil.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.brand, .white)
                    }
                }
                .accessibilityLabel("تغيير صورة الملف الشخصي")
                Text(account.currentUser?.displayName.isEmpty == false
                     ? account.currentUser!.displayName
                     : (account.currentUser?.email ?? "حسابك"))
                    .font(.title3.bold()).foregroundStyle(.white)
                if let email = account.currentUser?.email {
                    Text(email).font(.footnote).foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(AppTheme.heroGradient,
                        in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .shadow(color: AppTheme.brand.opacity(0.3), radius: 14, y: 7)

            InfoCard(title: "مزامنة التقدّم", systemImage: "arrow.triangle.2.circlepath", tint: AppTheme.accentTeal) {
                Text("يُحفظ تقدّمك (النقاط، السلسلة، المهارات، القاموس، الإعدادات) في حسابك لتستعيده على أي جهاز.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let when = sync.lastSyncedAt {
                    Label(when.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        .font(.caption).foregroundStyle(.secondary)
                }
                PrimaryButton(title: "احفظ تقدّمي الآن", systemImage: "icloud.and.arrow.up",
                              isLoading: sync.isSyncing) {
                    Task { await sync.push() }
                }
                Button {
                    Task { await sync.pull() }
                } label: {
                    Label("استعادة التقدّم من الحساب", systemImage: "icloud.and.arrow.down")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(sync.isSyncing)
                if let message = sync.syncMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }

            Button(role: .destructive) {
                showSignOutConfirm = true
            } label: {
                Label("تسجيل الخروج", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .confirmationDialog("تسجيل الخروج", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("تسجيل الخروج", role: .destructive) { account.logout() }
                Button("إلغاء", role: .cancel) {}
            } message: {
                Text("تأكّد أنك حفظت تقدّمك في حسابك قبل الخروج. هل تريد تسجيل الخروج؟")
            }
        }
    }

    // MARK: - Auth form

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isWorking = false

    private enum Mode: String, CaseIterable { case signIn, register
        var titleAr: String { self == .signIn ? "تسجيل الدخول" : "حساب جديد" }
    }

    private var authForm: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "graduationcap.circle.fill")
                    .font(.system(size: 44)).foregroundStyle(AppTheme.brand)
                Text("احفظ تقدّمك في السحابة")
                    .font(.title3.bold())
                Text("أنشئ حسابًا لمزامنة تعلّمك عبر أجهزتك.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.titleAr).tag($0) }
            }
            .pickerStyle(.segmented)

            InfoCard(title: mode.titleAr, systemImage: "envelope.fill") {
                if mode == .register {
                    field("الاسم", text: $displayName, systemImage: "person", keyboard: .default)
                }
                field("البريد الإلكتروني", text: $email, systemImage: "envelope", keyboard: .emailAddress)
                secureField("كلمة المرور", text: $password)

                if let error = account.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }

                PrimaryButton(title: mode.titleAr,
                              systemImage: mode == .signIn ? "arrow.right.circle.fill" : "person.badge.plus",
                              isLoading: isWorking,
                              isDisabled: email.isEmpty || password.isEmpty) {
                    Task { await submit() }
                }
            }

            HStack {
                Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
                Text("أو").font(.caption).foregroundStyle(.secondary)
                Rectangle().fill(.secondary.opacity(0.3)).frame(height: 1)
            }

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await handleApple(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: AppTheme.minimumTapHeight)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text("Sign in with Apple يتطلب نسخة موقّعة بحساب مطوّر Apple؛ قد لا يعمل في النسخة المثبّتة يدويًا. البريد وكلمة المرور يعملان دائمًا.")
                .font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func field(_ title: String, text: Binding<String>, systemImage: String,
                       keyboard: UIKeyboardType) -> some View {
        HStack {
            Image(systemName: systemImage).foregroundStyle(.secondary).frame(width: 22)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func secureField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 22)
            SecureField(title, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .environment(\.layoutDirection, .leftToRight)
        }
        .padding(12)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    @MainActor private func submit() async {
        isWorking = true
        defer { isWorking = false }
        let ok: Bool
        if mode == .register {
            ok = await account.register(email: email, password: password, displayName: displayName)
        } else {
            ok = await account.login(email: email, password: password)
        }
        if ok { await sync.pull() }   // restore existing progress on sign-in
    }

    @MainActor private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                account.lastError = "تعذّر قراءة رمز Apple."
                return
            }
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            if await account.signInWithApple(identityToken: token, displayName: name) {
                await sync.pull()
            }
        case .failure(let error):
            account.lastError = error.localizedDescription
        }
    }
}
