import Foundation
import Combine

// Compile with the real AppState and this deterministic replacement for IOKit.
public enum AwakeMode: String {
    case display, system
}

final class PowerManager {
    static let shared = PowerManager()
    static var acConnected = true
    static var battery = 100
    var activationSucceeds = true
    var isActive = false

    func activate(mode: AwakeMode, reason: String) -> Bool {
        isActive = activationSucceeds
        return isActive
    }
    func deactivate() { isActive = false }
    static func isACPowerConnected() -> Bool { acConnected }
    static func currentBatteryPercentage() -> Int? { battery }
    static func isProcessRunning(pid: Int32) -> Bool { pid == 123 }
}

// The privileged write is replaced, so checks never change the Mac's sleep settings.
final class SleepSettingStub: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    private var writes = 0
    func read() -> Bool { lock.lock(); defer { lock.unlock() }; return enabled }
    func write(_ value: Bool) -> Bool {
        Thread.sleep(forTimeInterval: 0.1)
        lock.lock()
        defer { lock.unlock() }
        enabled = value
        writes += 1
        return true
    }
    var writeCount: Int { lock.lock(); defer { lock.unlock() }; return writes }
}

@main
struct AppStateCheck {
    @MainActor
    static func main() async {
        let state = AppState()
        let power = PowerManager.shared
        defer { state.deactivate() }

        assert(try! SystemSleepSetting.parseSetting("System-wide power settings:\n SleepDisabled\t0\n") == false)
        assert(try! SystemSleepSetting.parseSetting(" SleepDisabled 1\n") == true)
        for invalid in ["", " sleep 0", " SleepDisabled 2", " SleepDisabled 0\n SleepDisabled 1"] {
            do {
                _ = try SystemSleepSetting.parseSetting(invalid)
                assertionFailure("Unknown settings must not be shown as off")
            } catch {}
        }
        _ = try! SystemSleepSetting.readSetting() // Read-only integration with pmset.
        let settingStore = SleepSettingStub()
        let sleep = SystemSleepSetting(read: { settingStore.read() }, write: { settingStore.write($0) })
        assert(sleep.isEnabled == false)
        let change = Task { await sleep.setEnabled(true) }
        while !sleep.isChanging { await Task.yield() }
        await sleep.setEnabled(false) // Ignore repeated clicks during authorization.
        await change.value
        assert(sleep.isEnabled == true && sleep.errorMessage == nil && settingStore.writeCount == 1)
        await sleep.setEnabled(false)
        assert(sleep.isEnabled == false && settingStore.writeCount == 2)
        _ = settingStore.write(true) // Pick up changes made outside this app.
        sleep.refresh()
        assert(sleep.isEnabled == true)
        let failedWrites: [@Sendable (Bool) throws -> Bool] = [
            { _ in false }, // Authentication cancelled.
            { _ in throw CocoaError(.userCancelled) }, // Command failed.
            { _ in true } // Command returned, but setting did not change.
        ]
        for writer in failedWrites {
            let failed = SystemSleepSetting(read: { false }, write: writer)
            await failed.setEnabled(true)
            assert(failed.isEnabled == false && failed.errorMessage != nil && !failed.isChanging)
        }
        let unknown = SystemSleepSetting(read: { throw CocoaError(.fileReadUnknown) }, write: { _ in
            assertionFailure("Must not write when current state is unknown")
            return true
        })
        await unknown.setEnabled(true)
        assert(unknown.isEnabled == nil && unknown.errorMessage != nil)

        let editor = RunningProcess(id: 123, name: "Sample Editor", isApp: true)
        let worker = RunningProcess(id: 456, name: "python3", isApp: false)
        assert(editor.matches(query: " EDITOR ", includeBackground: false))
        assert(!worker.matches(query: "python", includeBackground: false))
        assert(worker.matches(query: "PYTHON", includeBackground: true))
        assert(worker.matches(query: "456", includeBackground: true))
        assert(!editor.matches(query: "missing", includeBackground: true))

        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        try! child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        let snapshot = try! RunningProcess.snapshot()
        assert(snapshot.contains { $0.id == child.processIdentifier && $0.name == "sleep" })
        assert(!snapshot.contains { $0.id == ProcessInfo.processInfo.processIdentifier })
        assert(Set(snapshot.map(\.id)).count == snapshot.count)
        child.terminate()
        child.waitUntilExit()
        let refreshed = try! RunningProcess.snapshot()
        assert(!refreshed.contains { $0.id == child.processIdentifier })

        func assertInactive() {
            assert(!state.isActive && !power.isActive)
            assert(state.remainingSeconds == 0)
            assert(state.watchedPID == nil && state.watchedProcessName == nil)
            assert(state.menuBarTitle.isEmpty)
        }

        assert(state.activate(preset: .indefinite))
        var updates = 0
        let observation = state.objectWillChange.sink { updates += 1 }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        assert(updates == 0, "Unchanged status must not rebuild the menu every second")
        observation.cancel()

        assert(state.startWatchingProcess(pid: editor.id, name: editor.name))
        assert(state.watchedProcessName == editor.name && state.menuBarTitle.contains(editor.name))
        assert(state.isActive && state.watchedPID == 123)
        state.setMode(.system)
        assert(state.isActive && state.watchedPID == 123)
        assert(state.activate(preset: .min15))
        assert(state.watchedPID == nil && state.watchedProcessName == nil)
        assert(state.remainingSeconds == 900 && state.menuBarTitle.contains("15m"))
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        assert(state.remainingSeconds < 900 && state.remainingSeconds > 0)
        let remaining = state.remainingSeconds
        state.setMode(.display)
        assert(state.selectedPreset == .min15 && state.remainingSeconds == remaining)

        power.activationSucceeds = false
        state.setMode(.display)
        assertInactive()
        assert(state.statusMessage.contains("모드 변경 실패"))
        let failureMessage = state.statusMessage
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        assert(state.statusMessage == failureMessage)

        power.activationSucceeds = true
        state.startWatchingProcess(pid: 123)
        power.activationSucceeds = false
        assert(!state.activate(preset: .min30))
        assertInactive()
        state.startWatchingProcess(pid: 123)
        assertInactive()
        assert(state.statusMessage == "시스템 절전 방지 활성화 실패")

        assert(!state.startWatchingProcess(pid: 456, name: worker.name))
        assertInactive()

        power.activationSucceeds = true
        state.startWatchingProcess(pid: 123)
        state.onlyOnACPower = true
        PowerManager.acConnected = false
        assert(!state.activate(preset: .hour1))
        assertInactive()
        assert(state.statusMessage.contains("AC 전원 미연결"))
        state.startWatchingProcess(pid: 123)
        assertInactive()
        assert(state.statusMessage.contains("AC 전원 미연결"))

        state.onlyOnACPower = false
        PowerManager.battery = 20
        state.startWatchingProcess(pid: 123)
        assertInactive()
        assert(state.statusMessage.contains("배터리 부족"))

        PowerManager.battery = 100
        state.startWatchingProcess(pid: 0)
        assertInactive()
        state.toggle()
        assert(state.isActive)
        state.toggle()
        assertInactive()
        print("PASS: timer/watch transitions, power guards, system sleep parsing/readback/cancellation/failures")
    }
}
