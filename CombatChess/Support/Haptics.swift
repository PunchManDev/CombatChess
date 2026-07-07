import UIKit
import AudioToolbox

/// Haptics + lightweight system SFX (PRD §5.4), gated by Settings toggles.
enum Haptics {
    static var hapticsEnabled: Bool {
        return UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true
    }

    static var soundEnabled: Bool {
        return UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func warning() {
        guard hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func success() {
        guard hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        guard hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func moveSound() {
        guard soundEnabled else { return }
        AudioServicesPlaySystemSound(1104)
    }

    static func hitSound() {
        guard soundEnabled else { return }
        AudioServicesPlaySystemSound(1103)
    }
}
