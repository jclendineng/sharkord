import SwiftUI

// the pickers a filter needs before it can be applied
enum FilterPicker: String, Identifiable {
    case from
    case channel
    case mentions
    case on
    case before
    case after

    var id: String { rawValue }

    var title: String {
        switch self {
        case .from:
            "From"
        case .channel:
            "In Channel"
        case .mentions:
            "Mentions"
        case .on:
            "Sent On"
        case .before:
            "Before"
        case .after:
            "After"
        }
    }
}

// discord's "filter results…" menu
struct FilterMenu: View {
    @Binding var filters: SearchFilters
    @Binding var picker: FilterPicker?

    var body: some View {
        Menu {
            Section("Filter results…") {
                Button("From a specific person", systemImage: "person.fill") { picker = .from }
                Button("In a specific channel", systemImage: "number") { picker = .channel }

                Menu("Has specific data", systemImage: "paperclip") {
                    ForEach(SearchFilters.Has.allCases, id: \.self) { kind in
                        Button(kind.title) { filters.has = kind }
                    }
                }

                Button("Mention someone", systemImage: "at") { picker = .mentions }
                Button("Sent on a date", systemImage: "calendar") { picker = .on }
                Button("Before a date", systemImage: "calendar.badge.minus") { picker = .before }
                Button("After a date", systemImage: "calendar.badge.plus") { picker = .after }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(filters.isEmpty ? Theme.text : Theme.blurple)
        }
    }
}

// the filters in use, each removable on its own
struct FilterChips: View {
    @Binding var filters: SearchFilters

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                if let from = filters.from {
                    Chip(label: "from: \(from.name)") { filters.from = nil }
                }

                if let channel = filters.channel {
                    Chip(label: "in: #\(channel.name)") { filters.channel = nil }
                }

                if let mentions = filters.mentions {
                    Chip(label: "mentions: \(mentions.name)") { filters.mentions = nil }
                }

                if let has = filters.has {
                    Chip(label: "has: \(has.title.lowercased())") { filters.has = nil }
                }

                if let on = filters.on {
                    Chip(label: "during: \(on.formatted(date: .abbreviated, time: .omitted))") { filters.on = nil }
                }

                if let before = filters.before {
                    Chip(label: "before: \(before.formatted(date: .abbreviated, time: .omitted))") { filters.before = nil }
                }

                if let after = filters.after {
                    Chip(label: "after: \(after.formatted(date: .abbreviated, time: .omitted))") { filters.after = nil }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
    }
}

private struct Chip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                Text(label)
                    .lineLimit(1)

                Image(systemName: "xmark")
                    .font(.caption2.bold())
            }
            .font(.subheadline)
            .foregroundStyle(Theme.header)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.inputBackground, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(label)")
    }
}

struct FilterPickerSheet: View {
    let picker: FilterPicker
    @Binding var filters: SearchFilters

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var date = Date.now

    private var people: [PublicUser] {
        session.members
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var textChannels: [Channel] {
        session.channelSections
            .flatMap(\.channels)
            .filter { $0.type == .text && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(picker.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: close)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.deepBackground)
    }

    @ViewBuilder
    private var content: some View {
        switch picker {
        case .from, .mentions:
            List(people) { user in
                Button(action: { pick(user) }) {
                    HStack(spacing: 12) {
                        AvatarView(user: user, size: 32, showsStatus: true)

                        Text(user.name)
                            .foregroundStyle(Theme.header)
                    }
                }
            }
            .settingsListStyle()
            .searchable(text: $query, prompt: "Find someone")
        case .channel:
            List(textChannels) { channel in
                Button(action: { pick(channel) }) {
                    Label(channel.name, systemImage: "number")
                        .foregroundStyle(Theme.header)
                }
            }
            .settingsListStyle()
            .searchable(text: $query, prompt: "Find a channel")
        case .on, .before, .after:
            VStack {
                DatePicker(picker.title, selection: $date, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(Theme.blurple)

                Button(action: pickDate) {
                    Text("Apply")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Theme.blurple, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(16)
        }
    }

    private func pick(_ user: PublicUser) {
        if picker == .from {
            filters.from = user
        } else {
            filters.mentions = user
        }

        dismiss()
    }

    private func pick(_ channel: Channel) {
        filters.channel = channel
        dismiss()
    }

    // sent on a day replaces a range, and a range replaces sent on, they would contradict
    private func pickDate() {
        switch picker {
        case .on:
            filters.on = date
            filters.before = nil
            filters.after = nil
        case .before:
            filters.before = date
            filters.on = nil
        case .after:
            filters.after = date
            filters.on = nil
        case .from, .channel, .mentions:
            break
        }

        dismiss()
    }

    private func close() {
        dismiss()
    }
}
