// The user's preferences: the only thing the app writes to disk (non-negotiable #8;
// docs/quality/privacy.md). Each is one small `UserDefaults` value, set in the Settings window.
import AgentvilleCore
import Foundation

@MainActor
enum Preferences {
    private static let announceKey = "announceDone"
    private static let hideNamesKey = "hideNames"

    /// Which finished turns get a "Done!" walk-on (open question 1). Long turns unless chosen otherwise.
    static var announceDone: DoneAnnouncement {
        get { UserDefaults.standard.string(forKey: announceKey).flatMap(DoneAnnouncement.init(rawValue:)) ?? .longTurns }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: announceKey) }
    }

    /// Open question 10: folder names hidden for screenshots and screen shares. Off unless chosen.
    static var hideNames: Bool {
        get { UserDefaults.standard.bool(forKey: hideNamesKey) }
        set { UserDefaults.standard.set(newValue, forKey: hideNamesKey) }
    }
}
