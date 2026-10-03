import Foundation
import Testing
@testable import AgentvilleCore
@testable import AgentvilleWire

/// The M6 scenarios' header comments promise what the crew does; this replays them through the
/// store and the crew together, as the app does, and checks those promises.
@Suite("Crew scenarios")
struct CrewScenarioTests {
    /// Replays a scenario file, stepping the sim at 60 Hz; `check` runs after every step.
    static func replay(_ file: String, release: Bool, until: Double, check: (Double, CrewSim, SessionStore) throws -> Void) throws {
        let scenario = try Scenario.parse(try readRepoFile("Tools/scenarios/\(file)"))
        let store = SessionStore()
        let sim = CrewSim(stage: CrewSimTests.stage, seed: 5)
        sim.home = { _ in Home(x: 1200, y: 120, scale: 2) }
        if release { sim.release([]) }
        var steps = scenario.steps[...]
        var t = 0.0
        while t < until {
            while let s = steps.first, s.at <= t {
                steps.removeFirst()
                guard case .event(let e) = s.step else { continue }
                CrewNoticeTests.apply(store, sim, e, now: s.at)
            }
            _ = sim.update(dt: 1.0 / 60, sessions: store.sessions)
            t += 1.0 / 60
            try check(t, sim, store)
        }
    }

    static func walkOns(_ sim: CrewSim) -> [CrewMember] {
        sim.members.values.filter { $0.walkOn != nil }
    }

    @Test("walk-ons.jsonl: Done!, Needs you until answered, no walk-on for a short turn, \"+2 more\", Bye!")
    func walkOnsScenario() throws {
        var sawDone = false, sawBoth = false, sawQuick = false, sawFold = false, sawBye = false, dotLeftBy31 = true
        try Self.replay("walk-ons.jsonl", release: false, until: 52) { t, sim, _ in
            let w = Self.walkOns(sim)
            if t > 23.5, t < 24, w.contains(where: { $0.id == "wo-blog" && $0.bubble?.sub == "blog · 22s" }) { sawDone = true }
            if t > 26, t < 28, Set(w.map(\.id)) == ["wo-blog", "wo-dot"] { sawBoth = true }
            if sim.members["wo-quick"] != nil { sawQuick = true }
            if t > 31.5, t < 33, sim.members["wo-dot"]?.mode == .hold { dotLeftBy31 = false }
            if t > 42, t < 44, w.count == 1, w[0].walkOn?.more == 2, w[0].bubble?.sub?.hasSuffix("· +2 more") == true { sawFold = true }
            if t > 48, sim.members["wo-chess"]?.mode == .leave, sim.members["wo-chess"]?.bubble?.text == "Bye!" { sawBye = true }
        }
        #expect(sawDone && sawBoth && !sawQuick && dotLeftBy31 && sawFold && sawBye)
    }

    @Test("crowd.jsonl: +4, \"2 need you\", \"homelab finished\", My turn!, the crowd poofs, then comes back with +2")
    func crowdScenario() throws {
        var sawFour = false, sawNeed = false, sawFinished = false, sawMyTurn = false, poofed = false, sawBack = false
        try Self.replay("crowd.jsonl", release: true, until: 34) { t, sim, _ in
            let c = sim.members[CrewSim.crowdID]
            if t > 3, t < 6, c?.bubble?.text == "+4" { sawFour = true }
            if t > 7, t < 12, c?.bubble?.sub == "2 need you", c?.emote == .icon(.bang) { sawNeed = true }
            if t > 12, t < 14, c?.bubble?.text == "homelab finished" { sawFinished = true }
            if t > 18, t < 19, sim.members["cr-12"]?.bubble?.text == "My turn!" { sawMyTurn = true }
            if t > 25, t < 29, c == nil { poofed = true }
            if t > 32, c?.bubble?.text == "+2" { sawBack = true }
        }
        #expect(sawFour && sawNeed && sawFinished && sawMyTurn && poofed && sawBack)
    }
}
