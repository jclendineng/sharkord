import SwiftUI

// discord's poll card: pick answers and vote, then the results as bars. closed polls and
// anyone who already voted see the results straight away
struct PollView: View {
    let message: Message
    let poll: Poll

    @Environment(SessionStore.self) private var session

    @State private var picked: Set<Int> = []
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var ownVotes: Set<Int> {
        poll.votes(of: session.ownUserId)
    }

    private var canEnd: Bool {
        message.userId == session.ownUserId || session.can(.manageMessages)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let isClosed = poll.isClosed(at: context.date)
            let showsResults = isClosed || !ownVotes.isEmpty

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(poll.question)
                        .font(.headline)
                        .foregroundStyle(Theme.header)

                    Text(poll.allowMultiple ? "Select one or more answers" : "Select one answer")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                VStack(spacing: 6) {
                    ForEach(poll.answers) { answer in
                        PollAnswerRow(
                            answer: answer,
                            total: poll.voterCount,
                            showsResults: showsResults,
                            isPicked: showsResults ? ownVotes.contains(answer.id) : picked.contains(answer.id),
                            allowMultiple: poll.allowMultiple,
                            isWinner: isClosed && isLeading(answer)
                        ) {
                            pick(answer)
                        }
                        .disabled(showsResults || isWorking)
                    }
                }

                footer(isClosed: isClosed, showsResults: showsResults, now: context.date)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.red)
                }
            }
            .padding(14)
            .frame(maxWidth: 420, alignment: .leading)
            .background(Theme.listBackground, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12).stroke(Theme.divider, lineWidth: 1)
            }
        }
    }

    private func footer(isClosed: Bool, showsResults: Bool, now: Date) -> some View {
        HStack(spacing: 10) {
            Text(status(isClosed: isClosed, now: now))
                .font(.caption)
                .foregroundStyle(Theme.muted)

            Spacer(minLength: 0)

            if !isClosed && canEnd {
                Button("End Poll", action: end)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .buttonStyle(.plain)
                    .disabled(isWorking)
            }

            if !isClosed && !ownVotes.isEmpty {
                Button(action: removeVote) {
                    Text("Remove Vote")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.header)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.inputBackground, in: .rect(cornerRadius: 8))
                        .contentShape(.rect(cornerRadius: 8))
                }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
            } else if !showsResults {
                Button(action: vote) {
                    Text("Vote")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(picked.isEmpty ? Theme.blurple.opacity(0.45) : Theme.blurple, in: .rect(cornerRadius: 8))
                        .contentShape(.rect(cornerRadius: 8))
                }
                    .buttonStyle(.plain)
                    .disabled(picked.isEmpty || isWorking)
            }
        }
    }

    private func status(isClosed: Bool, now: Date) -> String {
        let count = poll.voterCount
        let votes = count == 1 ? "1 vote" : "\(count) votes"

        if isClosed {
            return "\(votes) · Poll closed"
        }

        let remaining = poll.expiresDate.timeIntervalSince(now)
        let hours = Int(remaining / 3600)

        if hours >= 24 {
            return "\(votes) · \(hours / 24)d left"
        }

        if hours >= 1 {
            return "\(votes) · \(hours)h left"
        }

        return "\(votes) · \(max(1, Int(remaining / 60)))m left"
    }

    private func isLeading(_ answer: Poll.Answer) -> Bool {
        let most = poll.answers.map(\.userIds.count).max() ?? 0

        return most > 0 && answer.userIds.count == most
    }

    private func pick(_ answer: Poll.Answer) {
        if poll.allowMultiple {
            if picked.contains(answer.id) {
                picked.remove(answer.id)
            } else {
                picked.insert(answer.id)
            }
        } else {
            picked = [answer.id]
        }
    }

    private func vote() {
        submit(Array(picked))
    }

    private func removeVote() {
        submit([])
    }

    private func submit(_ answerIds: [Int]) {
        struct VoteInput: Encodable {
            let messageId: Int
            let answerIds: [Int]
        }

        run {
            try await session.perform("polls.vote", VoteInput(messageId: message.id, answerIds: answerIds))
            picked = []
        }
    }

    private func end() {
        run {
            try await session.perform("polls.end", ["messageId": message.id])
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil

        Task {
            do {
                try await work()
            } catch {
                errorMessage = error.localizedDescription
            }

            isWorking = false
        }
    }
}

private struct PollAnswerRow: View {
    let answer: Poll.Answer
    let total: Int
    let showsResults: Bool
    let isPicked: Bool
    let allowMultiple: Bool
    let isWinner: Bool
    let onTap: () -> Void

    private var share: Double {
        total == 0 ? 0 : Double(answer.userIds.count) / Double(total)
    }

    private var marker: String {
        if allowMultiple {
            return isPicked ? "checkmark.square.fill" : "square"
        }

        return isPicked ? "checkmark.circle.fill" : "circle"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                if let emoji = answer.emoji {
                    EmojiView(value: emoji, size: 20)
                }

                Text(answer.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.header)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsResults {
                    if isWinner {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.yellow)
                    }

                    Text("\(answer.userIds.count) · \(Int((share * 100).rounded()))%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.text)
                }

                if isPicked || !showsResults {
                    Image(systemName: marker)
                        .foregroundStyle(isPicked ? Theme.blurple : Theme.muted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(alignment: .leading) {
                if showsResults {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill((isPicked ? Theme.blurple : Theme.muted).opacity(0.3))
                            .frame(width: proxy.size.width * share)
                    }
                }
            }
            .background(Theme.inputBackground)
            .clipShape(.rect(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isPicked ? Theme.blurple : .clear, lineWidth: 1.5)
            }
            .hoverBrighten(cornerRadius: 8)
        }
        .buttonStyle(.plain)
    }
}
