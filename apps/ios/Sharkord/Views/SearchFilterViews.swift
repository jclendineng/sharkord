import SwiftUI

// discord's search filters: those that pick someone, a channel or a kind become a token in the
// search box with the choices listed under it, the dates open a wheel
enum FilterPicker: String, Identifiable {
    case from
    case channel
    case mentions
    case has
    case on
    case before
    case after

    var id: String { rawValue }

    // what sits in the search box while the choice is being made
    var token: String {
        switch self {
        case .from:
            "from:"
        case .channel:
            "in:"
        case .mentions:
            "mentions:"
        case .has:
            "has:"
        case .on:
            "during:"
        case .before:
            "before:"
        case .after:
            "after:"
        }
    }

    var isDate: Bool {
        self == .on || self == .before || self == .after
    }

    var dateTitle: String {
        switch self {
        case .before:
            "Before"
        case .after:
            "After"
        default:
            "Pick a date"
        }
    }
}

// discord's "filter results…" menu
struct FilterMenu: View {
    let isFiltering: Bool
    let onChoose: (FilterPicker) -> Void

    var body: some View {
        Menu {
            Section("Filter results…") {
                Button("From a specific person", systemImage: "person.fill") { onChoose(.from) }
                Button("In a specific channel", systemImage: "number") { onChoose(.channel) }
                Button("Has specific data", systemImage: "paperclip") { onChoose(.has) }
                Button("Mention someone", systemImage: "at") { onChoose(.mentions) }
                Button("Sent on a date", systemImage: "calendar") { onChoose(.on) }
                Button("Before a date", systemImage: "calendar.badge.minus") { onChoose(.before) }
                Button("After a date", systemImage: "calendar.badge.plus") { onChoose(.after) }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isFiltering ? Theme.blurple : Theme.text)
                .frame(width: 40, height: 40)
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
                    Chip(label: "has: \(has.rawValue)") { filters.has = nil }
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

// the choices for a token, listed right under the search box and narrowed by what is typed
struct FilterSuggestions: View {
    let picker: FilterPicker
    let text: String
    let onPickUser: (PublicUser) -> Void
    let onPickChannel: (Channel) -> Void
    let onPickHas: (SearchFilters.Has) -> Void

    @Environment(SessionStore.self) private var session

    private var query: String {
        text.trimmingCharacters(in: .whitespaces)
    }

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

    private var kinds: [SearchFilters.Has] {
        SearchFilters.Has.allCases.filter { query.isEmpty || $0.rawValue.contains(query.lowercased()) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                switch picker {
                case .from, .mentions:
                    ForEach(people) { user in
                        Button {
                            onPickUser(user)
                        } label: {
                            HStack(spacing: 14) {
                                AvatarView(user: user, size: 44, showsStatus: false)

                                Text(user.name)
                                    .font(.headline)
                                    .foregroundStyle(Theme.header)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                case .channel:
                    ForEach(textChannels) { channel in
                        Button {
                            onPickChannel(channel)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "number")
                                    .font(.title3)
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 28)

                                Text(channel.name)
                                    .font(.headline)
                                    .foregroundStyle(Theme.header)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                case .has:
                    ForEach(kinds, id: \.self) { kind in
                        Button {
                            onPickHas(kind)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: kind.symbol)
                                    .font(.title3)
                                    .foregroundStyle(Theme.muted)
                                    .frame(width: 28)

                                Text(kind.rawValue)
                                    .font(.headline)
                                    .foregroundStyle(Theme.header)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                case .on, .before, .after:
                    EmptyView()
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

// discord's "pick a date" sheet: a wheel, cancel and save in its header so save is always in view
struct DateFilterSheet: View {
    let picker: FilterPicker
    let onSave: (Date) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            DatePicker("", selection: $date, in: ...Date.now, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .navigationTitle(picker.dateTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: close)
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.height(330)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.listBackground)
    }

    private func save() {
        onSave(date)
        dismiss()
    }

    private func close() {
        dismiss()
    }
}
