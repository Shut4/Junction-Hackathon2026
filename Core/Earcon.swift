import Foundation

/// Hazard warning beeps: sharp square-ish tones, more beeps when closer (critical: one every 0.5 s).
/// Navigation is speech only (no sound, no vibration), so a beep always means a hazard.
/// DeveloperMode tuning of warning sounds and vibration, persisted between launches. Names match the DeveloperMode labels.
public struct FeedbackTuning: Sendable, Codable, Equatable {
    /// Seconds from one critical beep (and vibration pulse) to the next, and how many.
    public var criticalInterval = 0.5, criticalCount = 3
    /// Hazard beep pitch (Hz), length (s), gap between the two "high" beeps (s) and the lower single "normal" beep.
    public var hazardFrequency = 1320.0, beepDuration = 0.07, highGap = 0.05, normalFrequency = 990.0
    public var hazardVolume: Float = 0.45
    /// Continuous buzzer for very close head-height obstacles: pitch (Hz). Each chunk lasts one depth frame.
    public var buzzerFrequency = 880.0
    /// Vibration per hazard level (normal is off by default).
    public var vibrateCritical = true, vibrateHigh = true, vibrateNormal = false
    public init() {}
}
public enum Earcon: Sendable, Equatable {
    case hazard(SpeechPriority)
    /// One chunk (`seconds` long, no gaps) of the continuous close-obstacle buzzer; chunks are played back to back.
    case buzzer(seconds: Double)
    /// Default seconds from one critical beep to the next (vibration pulses use the same rhythm).
    public static let criticalInterval = FeedbackTuning().criticalInterval

    struct Note { var frequency: Double; var duration: Double; var gap: Double; var square: Bool }
    func notes(_ t: FeedbackTuning) -> [Note] {
        switch self {
        case .hazard(let p):
            let beep = Note(frequency: t.hazardFrequency, duration: t.beepDuration, gap: t.highGap, square: true)
            let spaced = Note(frequency: t.hazardFrequency, duration: t.beepDuration, gap: max(0, t.criticalInterval - t.beepDuration), square: true)
            switch p {
            case .critical: return Array(repeating: spaced, count: max(1, t.criticalCount) - 1) + [Note(frequency: t.hazardFrequency, duration: t.beepDuration, gap: 0, square: true)]
            case .high: return [beep, Note(frequency: t.hazardFrequency, duration: t.beepDuration, gap: 0, square: true)]
            case .normal: return [Note(frequency: t.normalFrequency, duration: t.beepDuration, gap: 0, square: true)]
            case .low: return []
            }
        case .buzzer(let seconds):
            return [Note(frequency: t.buzzerFrequency, duration: seconds, gap: 0, square: true)]
        }
    }
    func volume(_ t: FeedbackTuning) -> Float { t.hazardVolume }

    /// Stereo PCM (left, right; always centred) at `sampleRate`, with 5 ms fades so the notes do not click.
    public func samples(sampleRate: Double = 44_100, tuning: FeedbackTuning = FeedbackTuning()) -> (left: [Float], right: [Float]) {
        let gain = min(1, max(0, volume(tuning))) * 0.707
        let gains = (left: gain, right: gain)
        var mono: [Float] = []
        for note in notes(tuning) {
            let count = Int(note.duration * sampleRate), fade = max(1, Int(0.005 * sampleRate))
            for i in 0..<count {
                let phase = 2 * Double.pi * note.frequency * Double(i) / sampleRate
                var v = Float(sin(phase))
                // Soft square wave (a few odd harmonics) is sharper than a sine without being harsh.
                if note.square { v = Float(sin(phase) + sin(3 * phase) / 3 + sin(5 * phase) / 5) * 0.8 }
                let envelope = Float(min(1, Double(min(i, count - 1 - i)) / Double(fade)))
                mono.append(v * envelope)
            }
            mono += [Float](repeating: 0, count: Int(note.gap * sampleRate))
        }
        return (mono.map { $0 * gains.left }, mono.map { $0 * gains.right })
    }
}
