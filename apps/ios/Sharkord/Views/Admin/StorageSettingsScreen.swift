import SwiftUI

// others.getStorageSettings and the storage part of others.updateSettings
struct StorageSettingsScreen: View {
    // packages/shared statics/storage.ts
    private static let megabyte = 1024 * 1024
    private static let gigabyte = 1024 * megabyte
    private static let maxFilesPerMessage = 20
    private static let ttlRange = 1800...(86_400 * 7)

    @Environment(SessionStore.self) private var session

    @State private var storage: AdminStorage?
    @State private var settings: AdminStorage.Settings?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var saved: AdminStorage.Settings?

    var body: some View {
        Group {
            if let binding = Binding($settings), let storage {
                form(binding, storage: storage)
            } else if let errorMessage {
                ContentUnavailableView("Couldn't load storage", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ProgressView()
            }
        }
        .background(Theme.deepBackground)
        .navigationTitle("Storage")
        .inlineNavigationTitle()
        .task {
            await load()
        }
    }

    private func form(_ settings: Binding<AdminStorage.Settings>, storage: AdminStorage) -> some View {
        let uploadsOn = settings.wrappedValue.storageUploadEnabled

        return SettingsForm {
            Section("Disk") {
                DiskUsageBar(disk: storage.diskMetrics, quota: settings.wrappedValue.storageQuota)

                LabeledContent("Used by Sharkord", value: Self.bytes(storage.diskMetrics.sharkordUsedSpace))
                LabeledContent("Free on Disk", value: Self.bytes(storage.diskMetrics.freeSpace))
                LabeledContent("Disk Size", value: Self.bytes(storage.diskMetrics.totalSpace))
            }

            if !storage.pluginStorage.isEmpty {
                Section("Used by Plugins") {
                    ForEach(storage.pluginStorage) { usage in
                        LabeledContent {
                            Text("\(Self.bytes(usage.usedSpace)) · \(usage.fileCount) files")
                        } label: {
                            Text(usage.installed ? usage.pluginId : "\(usage.pluginId) (removed)")
                        }
                    }
                }
            }

            Section {
                Toggle("Allow Uploads", isOn: settings.storageUploadEnabled)
                Toggle("File Sharing in Direct Messages", isOn: settings.storageFileSharingInDirectMessages)
                    .disabled(!uploadsOn)
            } header: {
                Text("Uploads")
            } footer: {
                Text("Turning uploads off doesn't touch files already uploaded.")
                    .wrappingFooter()
            }

            Section {
                SizeRow(
                    title: "Server Quota",
                    value: settings.storageQuota,
                    presets: [25, 100, 250].map { $0 * Self.gigabyte },
                    range: Self.gigabyte...(1024 * Self.gigabyte),
                    unit: Self.gigabyte
                )

                Picker("When Full", selection: settings.storageOverflowAction) {
                    Text("Prevent New Uploads").tag("prevent")
                    Text("Delete Oldest Files").tag("delete")
                }

                SizeRow(
                    title: "Per Member",
                    value: settings.storageSpaceQuotaByUser,
                    presets: [0, 1, 20, 100].map { $0 * Self.gigabyte },
                    range: 0...(100 * Self.gigabyte),
                    unit: Self.gigabyte
                )
            } header: {
                Text("Quotas")
            } footer: {
                Text("The quota isn't a hard limit: an upload is written first and the rule applies after, so keep more disk free than the quota. 0 per member means unlimited, a role can override it in Roles.")
                    .wrappingFooter()
            }
            .disabled(!uploadsOn)

            Section("Limits") {
                SizeRow(
                    title: "Max File Size",
                    value: settings.storageUploadMaxFileSize,
                    presets: [25, 100, 500, 1024].map { $0 * Self.megabyte },
                    range: Self.megabyte...(2 * Self.gigabyte),
                    unit: Self.megabyte
                )

                SizeRow(
                    title: "Max Avatar Size",
                    value: settings.storageMaxAvatarSize,
                    presets: [1, 3, 10].map { $0 * Self.megabyte },
                    range: Self.megabyte...(50 * Self.megabyte),
                    unit: Self.megabyte
                )

                SizeRow(
                    title: "Max Banner Size",
                    value: settings.storageMaxBannerSize,
                    presets: [1, 3, 10].map { $0 * Self.megabyte },
                    range: Self.megabyte...(100 * Self.megabyte),
                    unit: Self.megabyte
                )

                Stepper(
                    "Files per Message: \(settings.wrappedValue.storageMaxFilesPerMessage)",
                    value: settings.storageMaxFilesPerMessage,
                    in: 0...Self.maxFilesPerMessage
                )
            }
            .disabled(!uploadsOn)

            Section {
                Toggle("Optimize Images", isOn: settings.storageImageOptimizationEnabled)

                if settings.wrappedValue.storageImageOptimizationEnabled {
                    VStack(alignment: .leading) {
                        Text("Quality: \(settings.wrappedValue.storageImageOptimizationQuality)")

                        Slider(
                            value: Binding(
                                get: { Double(settings.wrappedValue.storageImageOptimizationQuality) },
                                set: { settings.wrappedValue.storageImageOptimizationQuality = Int($0.rounded()) }
                            ),
                            in: 1...100,
                            step: 1
                        )
                        .tint(Theme.blurple)
                    }
                }
            } header: {
                Text("Images")
            } footer: {
                Text("Converts uploaded images to WebP. Higher quality keeps more detail and uses more space.")
                    .wrappingFooter()
            }

            Section {
                Picker("Links Expire After", selection: settings.storageSignedUrlsTtlSeconds) {
                    ForEach(ttlChoices(including: settings.wrappedValue.storageSignedUrlsTtlSeconds), id: \.self) { seconds in
                        Text(Self.duration(seconds)).tag(seconds)
                    }
                }
            } header: {
                Text("Security")
            } footer: {
                Text("Every file link carries a token that expires, handed only to people who can see the file, so nobody can guess their way to one. The apps fetch fresh links on their own.")
                    .wrappingFooter()
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.red)
                }
            }
        }
        .settingsListStyle()
        .toolbar {
            ActionToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save", action: save)
                        .disabled(settings.wrappedValue == saved)
                }
            }
        }
    }

    // the web client's presets and the longest the server takes, plus whatever is set now
    private func ttlChoices(including current: Int) -> [Int] {
        let choices = [3600, 6 * 3600, 12 * 3600, 86_400, 3 * 86_400, 7 * 86_400]

        return choices.contains(current) ? choices : (choices + [current]).sorted()
    }

    private func load() async {
        do {
            let loaded: AdminStorage = try await session.request("others.getStorageSettings")

            storage = loaded
            settings = loaded.storageSettings
            saved = loaded.storageSettings
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard var settings else {
            return
        }

        settings.storageSignedUrlsTtlSeconds = min(max(settings.storageSignedUrlsTtlSeconds, Self.ttlRange.lowerBound), Self.ttlRange.upperBound)

        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await session.perform("others.updateSettings", settings)
                self.settings = settings
                saved = settings
            } catch {
                errorMessage = error.localizedDescription
            }

            isSaving = false
        }
    }

    static func bytes(_ count: Int) -> String {
        Int64(count).formatted(.byteCount(style: .binary))
    }

    private static func duration(_ seconds: Int) -> String {
        if seconds % 86_400 == 0 {
            let days = seconds / 86_400

            return days == 1 ? "1 day" : "\(days) days"
        }

        if seconds % 3600 == 0 {
            let hours = seconds / 3600

            return hours == 1 ? "1 hour" : "\(hours) hours"
        }

        return "\(seconds / 60) minutes"
    }
}

// how full the disk is, with sharkord's own files drawn apart from everything else on it
private struct DiskUsageBar: View {
    let disk: AdminStorage.Disk
    let quota: Int

    private func fraction(_ value: Int) -> CGFloat {
        guard disk.totalSpace > 0 else {
            return 0
        }

        return min(CGFloat(value) / CGFloat(disk.totalSpace), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let other = max(disk.usedSpace - disk.sharkordUsedSpace, 0)

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Theme.blurple)
                        .frame(width: proxy.size.width * fraction(disk.sharkordUsedSpace))

                    Rectangle()
                        .fill(Theme.muted.opacity(0.6))
                        .frame(width: proxy.size.width * fraction(other))

                    Spacer(minLength: 0)
                }
                .background(Theme.muted.opacity(0.2))
                .clipShape(.capsule)
            }
            .frame(height: 10)

            HStack(spacing: 14) {
                legend("Sharkord", color: Theme.blurple)
                legend("Other", color: Theme.muted.opacity(0.6))

                Spacer()

                Text("\(StorageSettingsScreen.bytes(disk.sharkordUsedSpace)) of \(StorageSettingsScreen.bytes(quota)) quota")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 4)
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
    }
}

// a size picked from the web client's presets, or typed in
private struct SizeRow: View {
    let title: String
    @Binding var value: Int
    let presets: [Int]
    let range: ClosedRange<Int>
    let unit: Int

    @State private var isCustomPresented = false
    @State private var custom = ""

    private var unitName: String {
        unit >= 1024 * 1024 * 1024 ? "GB" : "MB"
    }

    var body: some View {
        LabeledContent(title) {
            Menu {
                ForEach(presets, id: \.self) { preset in
                    Button(label(preset)) { value = preset }
                }

                Button("Custom…", systemImage: "pencil", action: showCustom)
            } label: {
                HStack(spacing: 4) {
                    Text(label(value))

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
            }
        }
        .alert(title, isPresented: $isCustomPresented) {
            TextField(unitName, text: $custom)
                .keyboard(.number)

            Button("Set", action: applyCustom)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("In \(unitName), from \(range.lowerBound / unit) to \(range.upperBound / unit).")
        }
    }

    private func label(_ size: Int) -> String {
        size == 0 ? "Unlimited" : StorageSettingsScreen.bytes(size)
    }

    private func showCustom() {
        custom = String(value / unit)
        isCustomPresented = true
    }

    private func applyCustom() {
        guard let number = Int(custom) else {
            return
        }

        value = min(max(number * unit, range.lowerBound), range.upperBound)
    }
}
