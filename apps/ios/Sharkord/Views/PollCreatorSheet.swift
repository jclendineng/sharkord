import SwiftUI

// discord's create poll sheet: a question, up to ten answers each with an emoji, how long it
// runs and whether several answers can be picked. bounds from packages/shared statics/polls.ts
struct PollCreatorSheet: View {
    private static let questionLimit = 300
    private static let answerLimit = 55
    private static let maxAnswers = 10
    private static let durations: [(hours: Int, title: String)] = [
        (1, "1 hour"), (4, "4 hours"), (8, "8 hours"), (24, "24 hours"),
        (72, "3 days"), (168, "1 week"), (336, "2 weeks")
    ]

    // the answer whose emoji is being picked
    private struct EmojiTarget: Identifiable {
        let id: UUID
    }

    private struct DraftAnswer: Identifiable {
        let id = UUID()
        var text = ""
        var emoji: String?
    }

    let channelId: Int

    @Environment(SessionStore.self) private var session
    @Environment(ServerListStore.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var question = ""
    @State private var answers = [DraftAnswer(), DraftAnswer()]
    @State private var durationHours = 24
    @State private var allowMultiple = false
    @State private var emojiFor: EmojiTarget?
    @State private var errorMessage: String?
    @State private var isPosting = false

    private var filledAnswers: [DraftAnswer] {
        answers.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var canPost: Bool {
        !question.trimmingCharacters(in: .whitespaces).isEmpty && !filledAnswers.isEmpty && !isPosting
    }

    var body: some View {
        NavigationStack {
            SettingsForm {
                Section {
                    TextField("", text: $question, prompt: Text("What question do you want to ask?"), axis: .vertical)
                        .labelsHidden()
                        .lineLimit(1...4)
                        .onChange(of: question) { _, value in
                            question = String(value.prefix(Self.questionLimit))
                        }
                } header: {
                    Text("Question")
                } footer: {
                    Text("\(question.count)/\(Self.questionLimit)")
                        .wrappingFooter()
                }

                Section("Answers") {
                    ForEach($answers) { $answer in
                        HStack(spacing: 10) {
                            Button {
                                emojiFor = EmojiTarget(id: answer.id)
                            } label: {
                                Group {
                                    if let emoji = answer.emoji {
                                        EmojiView(value: emoji, size: 22)
                                    } else {
                                        Image(systemName: "face.smiling")
                                            .font(.title3)
                                            .foregroundStyle(Theme.muted)
                                    }
                                }
                                .frame(width: 30, height: 30)
                            }
                            .buttonStyle(.plain)

                            TextField("Type your answer", text: $answer.text)
                                .onChange(of: answer.text) { _, value in
                                    answer.text = String(value.prefix(Self.answerLimit))
                                }
                        }
                    }
                    .onDelete(perform: removeAnswers)

                    if answers.count < Self.maxAnswers {
                        Button("Add Another Answer", systemImage: "plus", action: addAnswer)
                    }
                }

                Section {
                    Picker("Duration", selection: $durationHours) {
                        ForEach(Self.durations, id: \.hours) { duration in
                            Text(duration.title).tag(duration.hours)
                        }
                    }

                    Toggle("Allow Multiple Answers", isOn: $allowMultiple)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.red)
                    }
                }
            }
            .settingsListStyle()
            .navigationTitle("Create a Poll")
            .inlineNavigationTitle()
            .toolbar {
                ActionToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: close)
                }

                ActionToolbarItem(placement: .confirmationAction) {
                    if isPosting {
                        ProgressView()
                    } else {
                        Button("Post", action: post)
                            .disabled(!canPost)
                    }
                }
            }
            // handed over by hand: on a mac a sheet's background is worked out before it inherits
            // anything, so a sheet reading a store it was not given crashed on opening
            .sheet(item: $emojiFor) { target in
                EmojiPickerView(includesCustom: false) { shortcode in
                    setEmoji(shortcode, for: target.id)
                }
                    .environment(session)
                    .environment(servers)
                    .appSheet(addsClose: true)
            }
        }
        .presentationBackground(Theme.deepBackground)
    }

    private func addAnswer() {
        answers.append(DraftAnswer())
    }

    private func removeAnswers(_ offsets: IndexSet) {
        answers.remove(atOffsets: offsets)

        if answers.isEmpty {
            answers.append(DraftAnswer())
        }
    }

    private func setEmoji(_ shortcode: String, for id: UUID) {
        if let index = answers.firstIndex(where: { $0.id == id }) {
            answers[index].emoji = shortcode
        }
    }

    private func post() {
        struct AnswerInput: Encodable {
            let text: String
            let emoji: String?
        }

        struct PollInput: Encodable {
            let channelId: Int
            let question: String
            let answers: [AnswerInput]
            let durationHours: Int
            let allowMultiple: Bool
        }

        let input = PollInput(
            channelId: channelId,
            question: question.trimmingCharacters(in: .whitespacesAndNewlines),
            answers: filledAnswers.map { AnswerInput(text: $0.text.trimmingCharacters(in: .whitespaces), emoji: $0.emoji) },
            durationHours: durationHours,
            allowMultiple: allowMultiple
        )

        isPosting = true
        errorMessage = nil

        Task {
            do {
                let _: Int = try await session.perform("polls.create", input)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }

            isPosting = false
        }
    }

    private func close() {
        dismiss()
    }
}
