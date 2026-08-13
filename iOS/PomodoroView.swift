import SwiftUI

struct PomodoroView: View {
    @State private var timer = PomodoroTimer()
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private var phaseColor: Color {
        timer.phase == .focus ? palette.accent : palette.accentSecondary
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Text(timer.phase.label.uppercased())
                    .font(.system(size: TypeScale.label, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(phaseColor)

                ZStack {
                    Circle()
                        .stroke(palette.border, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: timer.progress)
                        .stroke(phaseColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: timer.progress)
                    Text(timer.timeLabel)
                        .font(.system(size: 48, weight: palette.displayWeight))
                        .foregroundStyle(palette.text)
                        .contentTransition(.numericText())
                }
                .frame(width: 220, height: 220)
                .padding(.vertical, 8)

                Text(timer.completedFocusSessions > 0
                     ? "\(timer.completedFocusSessions) session\(timer.completedFocusSessions == 1 ? "" : "s") today"
                     : "First session of the day")
                    .font(.system(size: TypeScale.bodySm))
                    .foregroundStyle(palette.textSecondary)

                Spacer()

                HStack(spacing: 14) {
                    Button {
                        timer.reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: TypeScale.body))
                            .frame(width: 52, height: 46)
                    }
                    .buttonStyle(OutlinePillButtonStyle(palette: palette))

                    Button {
                        timer.isRunning ? timer.pause() : timer.start()
                    } label: {
                        Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: TypeScale.subheading))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(FilledPillButtonStyle(palette: palette))

                    Button {
                        timer.skip()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: TypeScale.body))
                            .frame(width: 52, height: 46)
                    }
                    .buttonStyle(OutlinePillButtonStyle(palette: palette))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
            }
            .screenBackground()
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(palette.accent)
                }
            }
        }
    }
}
