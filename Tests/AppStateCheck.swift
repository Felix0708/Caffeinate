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

@main
struct AppStateCheck {
    @MainActor
    static func main() async {
        let state = AppState()
        let power = PowerManager.shared
        defer { state.deactivate() }

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

        state.startWatchingProcess(pid: 123)
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
        print("PASS: timer/watch transitions, activation failures, power guards, toggle")
    }
}
