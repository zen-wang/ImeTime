import ImeTimeCore
import PhotosUI
import SwiftUI

struct CreateProfileView: View {
    @State private var viewModel: CreateProfileViewModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    let onCreated: (Profile) -> Void

    init(userID: UUID, profiles: any ProfileRepository, onCreated: @escaping (Profile) -> Void) {
        _viewModel = State(initialValue: CreateProfileViewModel(userID: userID, profiles: profiles))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("頭像（選填）") {
                    HStack(spacing: 16) {
                        avatarPreview
                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker("從相簿選擇", selection: $pickerItem, matching: .images)
                            if CameraPicker.isAvailable {
                                Button("拍一張") { isShowingCamera = true }
                            }
                        }
                    }
                }
                Section("名稱") {
                    TextField("朋友怎麼叫你（最多 \(DisplayName.maxLength) 字）", text: $viewModel.displayNameInput)
                        .textInputAutocapitalization(.never)
                }
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                Button {
                    Task {
                        if let profile = await viewModel.save() { onCreated(profile) }
                    }
                } label: {
                    if viewModel.isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("完成").frame(maxWidth: .infinity)
                    }
                }
                .disabled(viewModel.isSaving)
            }
            .navigationTitle("建立個人檔案")
        }
        .onChange(of: pickerItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    viewModel.avatarImage = image
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CameraPicker { image in viewModel.avatarImage = image }
                .ignoresSafeArea()
        }
    }

    private var avatarPreview: some View {
        Group {
            if let image = viewModel.avatarImage {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
    }
}
