// The user's preferences: the only thing the app writes to disk (non-negotiable #8;
// docs/quality/privacy.md). Each is one small `UserDefaults` value. The Settings window arrives in
// M7; until then the status menu sets them.
import AgentvilleCore
import Foundation

@MainActor
enum Preferences {
    private static let announceKey = "announceDone"

    /// Which finished turns get a "Done!" walk-on (open question 1). Long turns unless chosen otherwise.
    static var announceDone: DoneAnnouncement {
        get { UserDefaults.standard.string(forKey: announceKey).flatMap(DoneAnnouncement.init(rawValue:)) ?? .longTurns }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: announceKey) }
    }
}
