import Foundation
import CoreGraphics

final class DisplaySafetyTests {
    func panel(_ id: UInt32 = 1, identity: String = "builtin", builtin: Bool = true,
               active: Bool = true, online: Bool = true, asleep: Bool = false,
               main: Bool = false, mirror: UInt32 = 0, hz: Double = 165) -> DisplayRecord {
        DisplayRecord(identity: identity, id: id, builtin: builtin, active: active, online: online,
                      asleep: asleep, main: main, mirror: mirror, x: 0, y: 0,
                      width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, hz: hz)
    }
    var external: DisplayRecord { panel(2, identity: "external", builtin: false, main: true, hz: 144.049) }
    func testRefusesOnlyBuiltinAndGhostExternal() {
        expectThrows(try DisplaySafety.targets([panel()]))
        let ghost = panel(2, identity: "external", builtin: false, active: false)
        expectThrows(try DisplaySafety.targets([panel(), ghost]))
    }
    func testRefusesSleepingExternalAndMirror() {
        expectThrows(try DisplaySafety.targets([panel(), panel(2, identity: "ext", builtin: false, asleep: true)]))
        expectThrows(try DisplaySafety.targets([panel(mirror: 2), external]))
    }
    func testRefusesAmbiguousIdentity() {
        expectThrows(try DisplaySafety.targets([panel(), external, panel(3, identity: "external", builtin: false)]))
    }
    func testTargetsFreshBuiltinAndMainExternal() throws {
        let pair = try DisplaySafety.targets([panel(99), external])
        expectEqual(pair.0.id, 99)
        expectEqual(pair.1.identity, "external")
    }
    func testSilentDisableFailureIsRejected() {
        let before = [panel(), external]
        expectThrows(try DisplaySafety.validateDisabled(before, builtin: "builtin", external: "external", now: before))
    }
    func testSuccessfulLogicalDisablePreserves144Hz() {
        let before = [panel(), external]
        expectNoThrow(try DisplaySafety.validateDisabled(before, builtin: "builtin", external: "external",
                            now: [panel(active: false), external]))
    }
    func testExternalBlackoutOrRefreshDowngradeFails() {
        let before = [panel(), external]
        for ext in [panel(2, identity: "external", builtin: false, active: false, main: true, hz: 144.049),
                    panel(2, identity: "external", builtin: false, main: true, hz: 60),
                    panel(2, identity: "external", builtin: false, main: false, hz: 144.049)] {
            expectThrows(try DisplaySafety.validateDisabled(before, builtin: "builtin", external: "external",
                                now: [panel(active: false), ext]))
        }
    }
    func testPhysicalUnplugTriggersRecoveryImmediately() {
        expectTrue(DisplayTrial.shouldRecover(deadline: 25, uptime: 1, before: [panel(), external], external: "external", now: [panel()]))
    }
    func testDeadlineTriggersRecoveryEvenIfCGReportsHealthy() {
        expectTrue(DisplayTrial.shouldRecover(deadline: 25, uptime: 25, before: [panel(), external], external: "external", now: [panel(active: false), external]))
        expectFalse(DisplayTrial.shouldRecover(deadline: 25, uptime: 24.9, before: [panel(), external], external: "external", now: [panel(active: false), external]))
    }
    func testModeReadbackDoesNotTrustModeID() {
        let desired = ModeInfo(id: 15, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 144, isUsable: true)
        let ignored = ModeInfo(id: 15, width: 2560, height: 1440, pixelWidth: 2560, pixelHeight: 1440, refreshRate: 144, isUsable: true)
        expectFalse(ignored.matches(desired))
        let alias = ModeInfo(id: 16, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 144.049, isUsable: true)
        expectTrue(alias.matches(desired))
        let hidpi = ModeInfo(id: 17, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshRate: 144, isUsable: true)
        expectFalse(hidpi.matches(desired))
    }
    func testPersistentProfileMatchesIdentityAcrossDisplayIDChanges() {
        let profile = AutomaticDisplayProfile(builtin: "builtin", external: external, environment: "driver-A")
        expectTrue(profile.allows([panel(90), panel(200, identity: "external", builtin: false, main: true, hz: 144.049)], environment: "driver-A"))
        expectFalse(profile.allows([panel(), external], environment: "driver-B"))
        expectFalse(profile.allows([panel(identity: "other-panel"), external], environment: "driver-A"))
        expectFalse(profile.allows([panel(), panel(2, identity: "other-display", builtin: false, main: true, hz: 144.049)], environment: "driver-A"))
    }
    func testPersistentProfileRejectsChangedModeAndSleepingOrMissingOutput() {
        let profile = AutomaticDisplayProfile(builtin: "builtin", external: external, environment: "driver-A")
        expectFalse(profile.allows([panel()], environment: "driver-A"))
        expectFalse(profile.allows([panel(), panel(2, identity: "external", builtin: false, main: true, hz: 60)], environment: "driver-A"))
        expectFalse(profile.allows([panel(), panel(2, identity: "external", builtin: false, asleep: true, main: true, hz: 144.049)], environment: "driver-A"))
        expectFalse(profile.allows([panel(mirror: 2), external], environment: "driver-A"))
        expectFalse(profile.allows([panel(), external, panel(3, identity: "external", builtin: false)], environment: "driver-A"))
    }
    func testStabilityRequiresContinuousPresenceAndRestartsAfterChange() {
        var gate = DisplayStabilityGate()
        expectFalse(gate.observe("A", now: 0))
        expectFalse(gate.observe("A", now: 3.9))
        expectTrue(gate.observe("A", now: 4))
        expectFalse(gate.observe(nil, now: 5))
        expectFalse(gate.observe("A", now: 6))
        expectFalse(gate.observe("B", now: 9))
        expectFalse(gate.observe("B", now: 12.9))
        expectTrue(gate.observe("B", now: 13))
    }
    func testConfirmedMonitorRecoversLossButDoesNotRevertUserModeChanges() {
        expectFalse(DisplayTrial.monitoringShouldRecover(external: "external", now: [external]))
        expectFalse(DisplayTrial.monitoringShouldRecover(external: "external", now: [panel(2, identity: "external", builtin: false, hz: 60)]))
        expectTrue(DisplayTrial.monitoringShouldRecover(external: "external", now: [panel()]))
        expectTrue(DisplayTrial.monitoringShouldRecover(external: "external", now: [panel(2, identity: "external", builtin: false, asleep: true)]))
        expectTrue(DisplayTrial.monitoringShouldRecover(external: "external", now: [external, external]))
    }
    func testLateConfirmationRemembersOnlyRecentSuccessfullyRestoredManualTests() {
        var t = DisplayTrial.Ticket(token: "t", boot: "boot-A", before: [panel(), external], builtin: "builtin",
            external: "external", deadline: 25, changed: true, state: "restored", detail: "已恢复切换前的显示配置", automatic: false)
        expectTrue(DisplayTrial.canRememberRestoredTest(t, boot: "boot-A", uptime: 26))
        expectFalse(DisplayTrial.canRememberRestoredTest(t, boot: "boot-B", uptime: 26))
        expectFalse(DisplayTrial.canRememberRestoredTest(t, boot: "boot-A", uptime: 326))
        t.state = "recoveryFailed"; expectFalse(DisplayTrial.canRememberRestoredTest(t, boot: "boot-A", uptime: 26))
        t.state = "restored"; t.automatic = true; expectFalse(DisplayTrial.canRememberRestoredTest(t, boot: "boot-A", uptime: 26))
        t.automatic = false; t.changed = false; expectFalse(DisplayTrial.canRememberRestoredTest(t, boot: "boot-A", uptime: 26))
    }
    func testRecoveryUsesPanelUUIDWhenExternalIsMislabelledBuiltin() throws {
        let virtualExternal = panel(1104977153, identity: "external", builtin: true, main: true, hz: 60)
        let renumberedPanel = panel(1104977152, identity: "builtin", builtin: true, active: false, online: false)
        let selected = try DisplaySafety.recoveryPanel([virtualExternal, renumberedPanel], expectedIdentity: "builtin")
        expectEqual(selected.id, UInt32(1104977152))
        expectThrows(try DisplaySafety.recoveryPanel([virtualExternal], expectedIdentity: "builtin"))
        expectThrows(try DisplaySafety.recoveryPanel([virtualExternal, renumberedPanel], expectedIdentity: nil))
        var fakeExternal = virtualExternal; fakeExternal.synthetic = true
        expectFalse(fakeExternal.usable)
        expectTrue(DisplayTrial.monitoringShouldRecover(external: "external", now: [fakeExternal]))
    }
}

func expectThrows<T>(_ body: @autoclosure () throws -> T) {
    do { _ = try body() } catch { return }
    fatalError("Expected a rejected unsafe operation")
}
func expectNoThrow<T>(_ body: @autoclosure () throws -> T) {
    do { _ = try body() } catch { fatalError("Unexpected error: \(error)") }
}
func expectEqual<T: Equatable>(_ a: T, _ b: T) { if a != b { fatalError("Values differ") } }
func expectTrue(_ value: Bool) { if !value { fatalError("Expected true") } }
func expectFalse(_ value: Bool) { if value { fatalError("Expected false") } }

@main
struct RunSafetyChecks {
    static func main() throws {
        let args = CommandLine.arguments
        if args.count == 4, args[1] == "watchdog-fixture" {
            DisplayTrial.recoveryFolderOverride = URL(fileURLWithPath: args[2])
            try DisplayTrial.watchdog(token: args[3])
            return
        }
        let checks = DisplaySafetyTests()
        checks.testRefusesOnlyBuiltinAndGhostExternal()
        checks.testRefusesSleepingExternalAndMirror()
        checks.testRefusesAmbiguousIdentity()
        try checks.testTargetsFreshBuiltinAndMainExternal()
        checks.testSilentDisableFailureIsRejected()
        checks.testSuccessfulLogicalDisablePreserves144Hz()
        checks.testExternalBlackoutOrRefreshDowngradeFails()
        checks.testPhysicalUnplugTriggersRecoveryImmediately()
        checks.testDeadlineTriggersRecoveryEvenIfCGReportsHealthy()
        checks.testModeReadbackDoesNotTrustModeID()
        checks.testPersistentProfileMatchesIdentityAcrossDisplayIDChanges()
        checks.testPersistentProfileRejectsChangedModeAndSleepingOrMissingOutput()
        checks.testStabilityRequiresContinuousPresenceAndRestartsAfterChange()
        checks.testConfirmedMonitorRecoversLossButDoesNotRevertUserModeChanges()
        checks.testLateConfirmationRemembersOnlyRecentSuccessfullyRestoredManualTests()
        try checks.testRecoveryUsesPanelUUIDWhenExternalIsMislabelledBuiltin()
        let live = DisplaySafety.records()
        expectTrue(UUID(uuidString: DisplayTrial.bootIdentity) != nil)
        expectFalse(live.contains { $0.identity == "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF" })
        expectTrue(live.allSatisfy { CGDisplayVendorNumber($0.id) != UInt32.max && CGDisplayModelNumber($0.id) != UInt32.max })
        try checkIndependentWatchdog()
        try checkConfirmedMonitor()
        print("PASS: 16 display safety checks + independent deadline and persistent monitor processes (no display configuration or real preferences changed)")
    }
}

func checkConfirmedMonitor() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("DisplayFocusMonitorChecks-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    guard let screen = DisplaySafety.records().first(where: { $0.usable && $0.mirror == 0 }) else {
        throw SafetyError.refused("Read-only fixture needs one awake screen")
    }
    let token = UUID().uuidString
    // changed=false prevents this helper from ever applying a display transaction or changing preferences.
    let t = DisplayTrial.Ticket(token: token, boot: DisplayTrial.bootIdentity, before: [screen],
        builtin: screen.identity, external: screen.identity, deadline: 0, changed: false,
        state: "monitoring", detail: "fixture")
    let file = root.appendingPathComponent("trial.json")
    try JSONEncoder().encode(t).write(to: file, options: .atomic)
    let worker = Process()
    worker.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    worker.arguments = ["watchdog-fixture", root.path, token]
    worker.standardInput = FileHandle.nullDevice; worker.standardOutput = FileHandle.nullDevice; worker.standardError = FileHandle.nullDevice
    try worker.run()
    var ready = false
    for _ in 0..<100 {
        if FileManager.default.fileExists(atPath: root.appendingPathComponent(token + ".ready").path) { ready = true; break }
        if !worker.isRunning { break }
        Thread.sleep(forTimeInterval: 0.025)
    }
    expectTrue(ready)
    Thread.sleep(forTimeInterval: 0.25)
    expectTrue(worker.isRunning) // confirmed monitoring must survive the expired confirmation deadline
    let lost = DisplayTrial.Ticket(token: token, boot: t.boot, before: t.before,
        builtin: t.builtin, external: "fixture-unplugged", deadline: 0, changed: false, state: "monitoring", detail: "fixture")
    try JSONEncoder().encode(lost).write(to: file, options: .atomic)
    for _ in 0..<120 {
        if !worker.isRunning { break }
        Thread.sleep(forTimeInterval: 0.025)
    }
    if worker.isRunning { worker.terminate(); fatalError("Persistent monitor fixture timed out") }
    worker.waitUntilExit(); expectEqual(worker.terminationStatus, 0)
    let result = try JSONDecoder().decode(DisplayTrial.Ticket.self, from: Data(contentsOf: file))
    expectEqual(result.state, "restored"); expectFalse(result.changed)
}

func checkIndependentWatchdog() throws {
    // changed=false is essential: this fixture MUST NEVER execute a display configuration transaction.
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("DisplayFocusChecks-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    guard let screen = DisplaySafety.records().first(where: { $0.usable && $0.mirror == 0 }) else {
        throw SafetyError.refused("Read-only fixture needs one awake screen")
    }
    let token = UUID().uuidString
    let ticket = DisplayTrial.Ticket(token: token, boot: DisplayTrial.bootIdentity, before: [screen],
        builtin: screen.identity, external: screen.identity,
        deadline: ProcessInfo.processInfo.systemUptime + 1, changed: false, state: "armed", detail: "fixture")
    let file = root.appendingPathComponent("trial.json")
    try JSONEncoder().encode(ticket).write(to: file)
    let worker = Process()
    worker.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    worker.arguments = ["watchdog-fixture", root.path, token]
    worker.standardInput = FileHandle.nullDevice
    worker.standardOutput = FileHandle.nullDevice
    worker.standardError = FileHandle.nullDevice
    try worker.run()
    var sawReady = false
    for _ in 0..<200 {
        if FileManager.default.fileExists(atPath: root.appendingPathComponent(token + ".ready").path) { sawReady = true }
        if !worker.isRunning { break }
        Thread.sleep(forTimeInterval: 0.025)
    }
    if worker.isRunning { worker.terminate(); fatalError("Watchdog fixture timed out") }
    worker.waitUntilExit()
    expectTrue(sawReady)
    expectEqual(worker.terminationStatus, 0)
    let result = try JSONDecoder().decode(DisplayTrial.Ticket.self, from: Data(contentsOf: file))
    expectEqual(result.state, "restored")
    expectFalse(result.changed)
}
