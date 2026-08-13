import Foundation
import Observation

/// A focus-session countdown. Deliberately not persisted or synced — a running timer is a
/// transient "I'm working right now" state, not data that means anything on another device.
@Observable
final class PomodoroTimer {
    enum Phase: Equatable {
        case focus
        case shortBreak

        var duration: TimeInterval {
            switch self {
            case .focus: return 25 * 60
            case .shortBreak: return 5 * 60
            }
        }

        var label: String {
            switch self {
            case .focus: return "Focus"
            case .shortBreak: return "Break"
            }
        }
    }

    private(set) var phase: Phase = .focus
    private(set) var remaining: TimeInterval = Phase.focus.duration
    private(set) var isRunning = false
    private(set) var completedFocusSessions = 0

    private var timer: Timer?

    var progress: Double {
        1 - (remaining / phase.duration)
    }

    var timeLabel: String {
        let total = max(0, Int(remaining.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        pause()
        remaining = phase.duration
    }

    func skip() {
        pause()
        advancePhase()
    }

    private func tick() {
        guard remaining > 1 else {
            pause()
            advancePhase()
            return
        }
        remaining -= 1
    }

    private func advancePhase() {
        if phase == .focus {
            completedFocusSessions += 1
            phase = .shortBreak
        } else {
            phase = .focus
        }
        remaining = phase.duration
    }

    deinit {
        timer?.invalidate()
    }
}
