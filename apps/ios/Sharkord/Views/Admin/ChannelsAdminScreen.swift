import SwiftUI

// channels.add, update, delete and reorder, categories.add, update, delete and reorder.
// the lists come from the session, which the channel and category events keep current
struct ChannelsAdminScreen: View {
    @Environment(SessionStore.self) private var session

    @State private var editMode = EditMode.inactive
    @State private var creating: ChannelType?
    @State private var isNewCategoryPresented = false
    @State private var isCategoryOrderPresented = false
    @State private var renaming: ChannelCategory?
    @State private var newName = ""
    @State private var errorMessage: String?

    private var sortedCategories: [ChannelCategory] {
        session.categories.sorted { $0.position < $1.position }
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(Theme.red)
            }

            ForEach(sortedCategories) { category in
                Section {
                    ForEach(channels(in: category.id)) { channel in
                        NavigationLink {
                            ChannelEditor(channel: channel)
                        } label: {
                            Label(channel.name, systemImage: icon(for: channel))
                                .foregroundStyle(Theme.header)
                        }
                    }
                    .onMove { from, to in
                        move(in: category, from: from, to: to)
                    }
                } header: {
                    HStack {
                        Text(category.name)

                        Spacer()

                        if session.can(.manageCategories) {
                            Menu {
                                Button("Rename", systemImage: "pencil") {
                                    newName = category.name
                                    renaming = category
                                }

                                Button("Delete Category", systemImage: "trash", role: .destructive) {
                                    deleteCategory(category)
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
                }
            }
        }
        .settingsListStyle()
        .environment(\.editMode, $editMode)
        .navigationTitle("Channels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if session.can(.manageChannels) {
                        Button("New Text Channel", systemImage: "number") { creating = .text }
                        Button("New Voice Channel", systemImage: "speaker.wave.2") { creating = .voice }
                    }

                    if session.can(.manageCategories) {
                        Button("New Category", systemImage: "folder.badge.plus") {
                            newName = ""
                            isNewCategoryPresented = true
                        }

                        Button("Reorder Categories", systemImage: "arrow.up.arrow.down") {
                            isCategoryOrderPresented = true
                        }
                    }

                    if session.can(.manageChannels) {
                        Button(editMode.isEditing ? "Done Reordering" : "Reorder Channels", systemImage: "line.3.horizontal") {
                            withAnimation {
                                editMode = editMode.isEditing ? .inactive : .active
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $creating) { type in
            NewChannelSheet(type: type, categories: sortedCategories)
        }
        .sheet(isPresented: $isCategoryOrderPresented) {
            CategoryOrderSheet(categories: sortedCategories)
        }
        .alert("New Category", isPresented: $isNewCategoryPresented) {
            TextField("Name", text: $newName)
            Button("Create", action: createCategory)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Category", isPresented: isRenaming) {
            TextField("Name", text: $newName)
            Button("Save", action: renameCategory)
            Button("Cancel", role: .cancel) {}
        }
    }

    private func icon(for channel: Channel) -> String {
        if channel.type == .voice {
            return "speaker.wave.2.fill"
        }

        return channel.private ? "lock" : "number"
    }

    private var isRenaming: Binding<Bool> {
        Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )
    }

    private func channels(in categoryId: Int) -> [Channel] {
        session.channels
            .filter { !$0.isDm && $0.categoryId == categoryId }
            .sorted { $0.position < $1.position }
    }

    // the server takes the whole new order of a category
    private func move(in category: ChannelCategory, from: IndexSet, to: Int) {
        var ordered = channels(in: category.id)

        ordered.move(fromOffsets: from, toOffset: to)

        struct OrderInput: Encodable {
            let categoryId: Int
            let channelIds: [Int]
        }

        run {
            try await session.perform("channels.reorder", OrderInput(categoryId: category.id, channelIds: ordered.map(\.id)))
        }
    }

    private func createCategory() {
        let name = newName.trimmingCharacters(in: .whitespaces)

        guard !name.isEmpty else {
            return
        }

        run {
            let _: Int = try await session.perform("categories.add", ["name": name])
        }
    }

    private func renameCategory() {
        guard let category = renaming else {
            return
        }

        struct RenameInput: Encodable {
            let categoryId: Int
            let name: String
        }

        let name = newName.trimmingCharacters(in: .whitespaces)

        run {
            try await session.perform("categories.update", RenameInput(categoryId: category.id, name: name))
        }
    }

    private func deleteCategory(_ category: ChannelCategory) {
        run {
            try await session.perform("categories.delete", ["categoryId": category.id])
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        errorMessage = nil

        Task {
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension ChannelType: Identifiable {
    var id: String { rawValue }
}

struct ChannelEditor: View {
    // helpers/channels.ts
    private static let nameLimit = 27
    private static let topicLimit = 128

    let channel: Channel

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var topic = ""
    @State private var isPrivate = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isConfirmingDelete = false

    private var canSave: Bool {
        (2...Self.nameLimit).contains(name.trimmingCharacters(in: .whitespaces).count) && topic.count <= Self.topicLimit && !isSaving
    }

    var body: some View {
        List {
            Section("Name") {
                TextField("Channel name", text: $name)
                    .textInputAutocapitalization(.never)
            }

            if channel.type == .text {
                Section {
                    TextField("What is this channel for?", text: $topic, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Topic")
                } footer: {
                    Text("\(topic.count)/\(Self.topicLimit)")
                }
            }

            Section {
                Toggle("Private Channel", isOn: $isPrivate)

                if session.can(.manageChannelPermissions) {
                    NavigationLink("Permissions") {
                        ChannelPermissionsScreen(channelId: channel.id)
                    }
                }
            } footer: {
                Text("Only the roles and members given access in Permissions can see a private channel.")
            }

            Section {
                Button("Delete Channel", role: .destructive) { isConfirmingDelete = true }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                }
            }
        }
        .settingsListStyle()
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
        .confirmationDialog("Delete #\(channel.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Channel", role: .destructive, action: delete)
        } message: {
            Text("Its messages are deleted with it. This can't be undone.")
        }
        .onAppear {
            name = channel.name
            topic = channel.topic ?? ""
            isPrivate = channel.private
        }
    }

    private func save() {
        struct UpdateInput: Encodable {
            let channelId: Int
            let name: String
            let topic: String?
            let `private`: Bool
        }

        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = UpdateInput(
            channelId: channel.id,
            name: name.trimmingCharacters(in: .whitespaces),
            topic: channel.type == .text ? (trimmedTopic.isEmpty ? nil : trimmedTopic) : channel.topic,
            private: isPrivate
        )

        run {
            try await session.perform("channels.update", input)
            dismiss()
        }
    }

    private func delete() {
        run {
            try await session.perform("channels.delete", ["channelId": channel.id])
            dismiss()
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }
}

private struct NewChannelSheet: View {
    let type: ChannelType
    let categories: [ChannelCategory]

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var categoryId: Int?
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                Section("Name") {
                    TextField(type == .voice ? "General Voice" : "general", text: $name)
                        .textInputAutocapitalization(.never)
                }

                Section("Category") {
                    Picker("Category", selection: $categoryId) {
                        ForEach(categories) { category in
                            Text(category.name).tag(Int?.some(category.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.red)
                    }
                }
            }
            .settingsListStyle()
            .navigationTitle(type == .voice ? "New Voice Channel" : "New Text Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Create", action: create)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || categoryId == nil)
                    }
                }
            }
            .onAppear {
                categoryId = categoryId ?? categories.first?.id
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.deepBackground)
    }

    private func create() {
        guard let categoryId else {
            return
        }

        struct NewChannelInput: Encodable {
            let type: ChannelType
            let name: String
            let categoryId: Int
        }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                let _: Int = try await session.perform(
                    "channels.add",
                    NewChannelInput(type: type, name: name.trimmingCharacters(in: .whitespaces), categoryId: categoryId)
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }

    private func close() {
        dismiss()
    }
}

private struct CategoryOrderSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var ordered: [ChannelCategory]
    @State private var errorMessage: String?

    init(categories: [ChannelCategory]) {
        _ordered = State(initialValue: categories)
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                }

                ForEach(ordered) { category in
                    Text(category.name)
                        .foregroundStyle(Theme.header)
                }
                .onMove { from, to in
                    ordered.move(fromOffsets: from, toOffset: to)
                }
            }
            .settingsListStyle()
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        .presentationBackground(Theme.deepBackground)
    }

    private func save() {
        Task {
            do {
                try await session.perform("categories.reorder", ["categoryIds": ordered.map(\.id)])
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func close() {
        dismiss()
    }
}
