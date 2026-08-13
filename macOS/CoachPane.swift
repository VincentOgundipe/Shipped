import SwiftUI
import SwiftData

/// A conversation with the coach. The transcript is stored in the local App Group store and
/// never leaves the device except as the prompt for the next reply.
struct CoachPane: View {
    let goal: Goal?
    @Environment(\.modelContext) private var context
    @Environment(\.themePalette) private var palette

    @Query(sort: \ChatMessage.createdAt, order: .forward) private var messages: [ChatMessage]

    @State private var draft = ""
    @State private var isThinking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty {
                            emptyState
                        } else {
                            conversationHeader
                        }

                        ForEach(messages) { message in
                            MessageBubble(message: message, palette: palette)
                                .id(message.persistentModelID)
                        }

                        if isThinking {
                            HStack(spacing: 8) {
                                SkeletonBlock(palette: palette, height: 12, width: 44)
                                SkeletonBlock(palette: palette, height: 12, width: 96)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: TypeScale.bodySm))
                                .foregroundStyle(palette.accentSecondary)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 760, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.persistentModelID, anchor: .bottom) }
                    }
                }
            }

            composer
        }
    }

    private var conversationHeader: some View {
        Text("Coach").labelStyle(palette)
            .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coach").labelStyle(palette)
            Text("Talk it through")
                .displayStyle(palette, size: TypeScale.heading)
            Text("Stuck, rethinking the plan, or want to argue with the deadline. This conversation is stored on this Mac only.")
                .bodyStyle(palette, size: TypeScale.bodySm)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            HairlineDivider()

            VStack(spacing: 10) {
                if !messages.isEmpty {
                    HStack {
                        Spacer()
                        Button {
                            for message in messages { context.delete(message) }
                            try? context.save()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "trash")
                                    .font(.system(size: TypeScale.caption))
                                Text("Clear conversation")
                                    .font(.system(size: TypeScale.caption, weight: .medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.textTertiary)
                        .help("Deletes this conversation from this Mac")
                    }
                }

                HStack(alignment: .bottom, spacing: 10) {
                    TextField("What's in the way?", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: TypeScale.bodySm))
                        .foregroundStyle(palette.text)
                        .lineLimit(1...5)
                        .padding(10)
                        .background(palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.input))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.input)
                                .stroke(palette.border, lineWidth: 1)
                        )
                        .onSubmit { Task { await send() } }

                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: TypeScale.bodySm, weight: .bold))
                            .foregroundStyle(palette.onAccent)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(palette.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: 760)
        }
        .frame(maxWidth: .infinity)
    }

    private func send() async {
        let outgoing = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !outgoing.isEmpty else { return }

        errorMessage = nil
        draft = ""
        context.insert(ChatMessage(role: .user, text: outgoing))
        try? context.save()

        isThinking = true
        defer { isThinking = false }

        // Keep the tail only — enough for continuity without resending a long history.
        let history = messages.suffix(20).map { (role: $0.role.rawValue, text: $0.text) }
        let goalContext = goal.map {
            "\($0.title), deadline \($0.deadline.formatted(date: .abbreviated, time: .omitted)), \($0.daysRemaining) days left"
        }

        do {
            let reply = try await ClaudeClient.chatReply(history: history, goalContext: goalContext)
            context.insert(ChatMessage(role: .assistant, text: reply))
            try? context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let palette: ThemePalette

    var body: some View {
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 60) }
            Text(message.text)
                .font(.system(size: TypeScale.bodySm))
                .foregroundStyle(isUser ? palette.onAccent : palette.text)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? palette.accent : palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: palette.cornerRadius)
                        .stroke(isUser ? .clear : palette.border, lineWidth: 1)
                )
            if !isUser { Spacer(minLength: 60) }
        }
    }
}
