import SwiftUI
import PhotosUI

/// Edit profile: avatar, display name, Penpot account language, email, and account deletion.
///
/// Name + language are saved together through a single `update-profile` call. Penpot never
/// returns the current `lang`, and `update-profile` nulls any field it isn't sent, so we send
/// name + language + local theme as one set and remember the language locally (in
/// ``AppSettings/accountLanguage``) for next time.
struct ProfileSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings

    @State private var fullname = ""
    @State private var accountLanguage = ""   // Penpot code; "" = auto-detect
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var previewImage: UIImage?
    @State private var isSavingProfile = false
    @State private var isUploadingPhoto = false
    @State private var message: Banner?

    private struct Banner: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    private var hasNameChange: Bool {
        let trimmed = fullname.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed != (appState.profile?.fullname ?? "")
    }
    private var hasLanguageChange: Bool { accountLanguage != (settings.accountLanguage ?? "") }
    private var canSave: Bool {
        !fullname.trimmingCharacters(in: .whitespaces).isEmpty
            && (hasNameChange || hasLanguageChange) && !isSavingProfile
    }

    var body: some View {
        Form {
            avatarSection
            nameAndLanguageSection

            Section("Email") {
                LabeledContent("Current", value: appState.profile?.email ?? SessionStore.email ?? "—")
                NavigationLink("Change Email") { ChangeEmailView() }
            }

            Section {
                NavigationLink {
                    DeleteAccountView()
                } label: {
                    Text("Delete Account").foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if fullname.isEmpty { fullname = appState.profile?.fullname ?? "" }
            accountLanguage = settings.accountLanguage ?? ""
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            if let item { Task { await uploadPhoto(item) } }
        }
        .alert(item: $message) { banner in
            // Ternary inside Text() would type as String and skip localization —
            // keep the literals inside separate Text initializers.
            Alert(title: banner.isError ? Text("Error") : Text("Saved"),
                  message: Text(banner.text),
                  dismissButton: .default(Text("OK")))
        }
    }

    // MARK: Avatar

    private var avatarSection: some View {
        Section {
            HStack(spacing: 16) {
                Button { showPhotoPicker = true } label: {
                    Group {
                        if let previewImage {
                            Image(uiImage: previewImage).resizable().scaledToFill()
                                .frame(width: 60, height: 60).clipShape(Circle())
                        } else {
                            PenpotAvatar(photoID: appState.profile?.photoId,
                                         baseURL: appState.client?.baseURL,
                                         fallbackSymbol: "person.fill",
                                         initials: appState.profile?.displayName ?? SessionStore.email,
                                         size: 60)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        AppIcon.camera.image
                            .font(.workSans(size: 11, weight: .semibold))
                            .foregroundStyle(Color.penpotOnAccent)
                            .frame(width: 22, height: 22)
                            .background(Color.penpotAccent, in: Circle())
                            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                    }
                    .opacity(isUploadingPhoto ? 0.5 : 1)
                }
                .buttonStyle(.plain)
                .disabled(isUploadingPhoto)
                .accessibilityLabel("Change Photo")
                VStack(alignment: .leading, spacing: 6) {
                    Button { showPhotoPicker = true } label: {
                        if isUploadingPhoto {
                            ProgressView()
                        } else {
                            Text("Change Photo")
                        }
                    }
                    .disabled(isUploadingPhoto)
                    if appState.profile?.photoId != nil || previewImage != nil {
                        Button("Reset to Default", role: .destructive, action: resetPhoto)
                            .font(.workSans(.callout))
                            .disabled(isUploadingPhoto)
                    }
                }
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 4)
        } footer: {
            Text("A new photo may take a moment to appear elsewhere in the app.")
        }
    }

    private func uploadPhoto(_ item: PhotosPickerItem) async {
        guard let client = appState.client else { return }
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.9) else {
                message = Banner(text: .appLocalized("Couldn’t read that image."), isError: true)
                return
            }
            previewImage = image
            try await client.updateProfilePhoto(jpeg, mimeType: "image/jpeg", filename: "avatar.jpg")
            // The upload returns no body, so re-resolve the new photo id from team membership
            // — this refreshes the avatar everywhere (teams list, settings header) on dismiss.
            await appState.refreshProfile()
        } catch {
            previewImage = nil
            message = Banner(text: errorText(error), isError: true)
        }
    }

    private func resetPhoto() {
        guard let client = appState.client else { return }
        isUploadingPhoto = true
        Task {
            do {
                try await client.deleteProfilePhoto()
                previewImage = nil
                if let old = appState.profile {
                    appState.profile = Profile(id: old.id, fullname: old.fullname, email: old.email,
                                               photoId: nil, theme: old.theme, lang: old.lang, props: old.props)
                }
            } catch {
                message = Banner(text: errorText(error), isError: true)
            }
            isUploadingPhoto = false
        }
    }

    // MARK: Name + language

    private var nameAndLanguageSection: some View {
        Section {
            TextField("Display name", text: $fullname)
                .textContentType(.name)

            Picker("Account language", selection: $accountLanguage) {
                Text("Auto-detect").tag("")
                ForEach(PenpotLanguage.all) { Text($0.nativeName).tag($0.penpotCode) }
            }

            Button(action: saveProfile) {
                HStack {
                    Spacer()
                    if isSavingProfile { ProgressView() } else { Text("Save").font(.workSans(.body, weight: .bold)) }
                    Spacer()
                }
            }
            .disabled(!canSave)
        } header: {
            Text("Profile")
        } footer: {
            Text("Account language changes the Penpot website and the emails Penpot sends you — not this app’s language. Penpot doesn’t report your current language to apps, so name and language are saved together.")
        }
    }

    private func saveProfile() {
        guard let client = appState.client, canSave else { return }
        let name = fullname.trimmingCharacters(in: .whitespaces)
        isSavingProfile = true
        Task {
            do {
                // Send name + language + local theme as one set so nothing is nulled.
                try await client.updateProfile(fullname: name,
                                               lang: accountLanguage,
                                               theme: settings.theme.rawValue)
                settings.accountLanguage = accountLanguage
                if let old = appState.profile {
                    let updated = Profile(id: old.id, fullname: name, email: old.email,
                                          photoId: old.photoId, theme: settings.theme.rawValue,
                                          lang: accountLanguage, props: old.props)
                    appState.profile = updated
                    SessionStore.cacheProfile(updated)
                }
                message = Banner(text: .appLocalized("Your profile has been updated."), isError: false)
            } catch {
                message = Banner(text: errorText(error), isError: true)
            }
            isSavingProfile = false
        }
    }

    private func errorText(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
