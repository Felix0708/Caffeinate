import Foundation
import Combine
import SwiftUI
import ServiceManagement

public enum DurationPreset: Int, CaseIterable, Identifiable {
    case indefinite = 0
    case min15 = 900
    case min30 = 1800
    case hour1 = 3600
    case hour2 = 7200

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .indefinite: return "무제한"
        case .min15: return "15분"
        case .min30: return "30분"
        case .hour1: return "1시간"
        case .hour2: return "2시간"
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var isActive: Bool = false
    @Published public var currentMode: AwakeMode = .display
    @Published public var selectedPreset: DurationPreset = .indefinite
    @Published public var remainingSeconds: Int = 0

    // 스마트 트리거 옵션
    @Published public var onlyOnACPower: Bool = false
    @Published public var batterySafeguardEnabled: Bool = true
    @Published public var batteryThreshold: Int = 20

    // 로그인 시 자동 실행 (Launch at Login)
    @Published public var launchAtLogin: Bool = false

    // 프로세스 감시
    @Published public var watchedPID: Int32? = nil
    @Published public var watchedProcessName: String? = nil

    // 상태 표시 문자열
    @Published public var statusMessage: String = "꺼짐 · 컴퓨터 자동 잠자기 허용"

    private var countdownTimer: AnyCancellable?
    private let powerManager = PowerManager.shared

    public init() {
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    // MARK: - Actions

    public func toggle() {
        if isActive {
            deactivate()
        } else {
            activate(preset: selectedPreset, mode: currentMode)
        }
    }

    @discardableResult
    public func activate(preset: DurationPreset, mode: AwakeMode? = nil) -> Bool {
        let targetMode = mode ?? currentMode
        deactivate()
        self.selectedPreset = preset
        self.currentMode = targetMode

        // AC 전원 전용 옵션 체크
        if onlyOnACPower && !PowerManager.isACPowerConnected() {
            self.statusMessage = "활성화 실패: AC 전원 미연결"
            return false
        }

        // 배터리 세이프가드 체크
        if batterySafeguardEnabled, let percent = PowerManager.currentBatteryPercentage(), percent <= batteryThreshold, !PowerManager.isACPowerConnected() {
            self.statusMessage = "활성화 실패: 배터리 부족 (\(percent)%)"
            return false
        }

        let reason = "Caffeine: \(targetMode.rawValue)"
        let success = powerManager.activate(mode: targetMode, reason: reason)

        if success {
            self.isActive = true
            self.remainingSeconds = preset.rawValue
            startTickTimer()
            updateStatusMessage()
        } else {
            self.statusMessage = "시스템 절전 방지 활성화 실패"
        }
        return success
    }

    public func setMode(_ mode: AwakeMode) {
        self.currentMode = mode
        if isActive {
            guard powerManager.activate(mode: mode, reason: "Caffeine: Mode changed to \(mode.rawValue)") else {
                deactivate()
                self.statusMessage = "절전 방지 모드 변경 실패: 절전 허용 상태로 전환"
                return
            }
            updateStatusMessage()
        }
    }

    public func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        } catch {
            self.statusMessage = "로그인 항목 설정 실패: \(error.localizedDescription)"
            self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    public func startWatchingProcess(pid: Int32, name: String? = nil) {
        guard pid > 0, PowerManager.isProcessRunning(pid: pid) else {
            self.statusMessage = "PID \(pid) 프로세스를 찾을 수 없습니다."
            return
        }
        guard activate(preset: .indefinite) else { return }
        self.watchedPID = pid
        self.watchedProcessName = name ?? "PID \(pid)"
        updateStatusMessage()
    }

    public func stopWatchingProcess() {
        self.watchedPID = nil
        self.watchedProcessName = nil
        updateStatusMessage()
    }

    public func deactivate() {
        powerManager.deactivate()
        countdownTimer?.cancel()
        countdownTimer = nil
        self.isActive = false
        self.remainingSeconds = 0
        self.watchedPID = nil
        self.watchedProcessName = nil
        self.statusMessage = "꺼짐 · 컴퓨터 자동 잠자기 허용"
    }

    // MARK: - Menu Bar Display Helpers

    public var menuBarIconName: String {
        return isActive ? "cup.and.saucer.fill" : "cup.and.saucer"
    }

    public var menuBarTitle: String {
        guard isActive else { return "" }
        if let watchedName = watchedProcessName {
            return " [\(watchedName)]"
        }
        if selectedPreset != .indefinite && remainingSeconds > 0 {
            return " \(formatRemainingTime(remainingSeconds))"
        }
        return ""
    }

    // MARK: - Internal Timer Loop

    private func startTickTimer() {
        countdownTimer?.cancel()
        countdownTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.onTick()
            }
    }

    private func onTick() {
        guard isActive else { return }

        // 1. 타이머 카운트다운
        if selectedPreset != .indefinite {
            if remainingSeconds > 1 {
                remainingSeconds -= 1
            } else {
                deactivate()
                return
            }
        }

        // 2. 프로세스 감시 체크
        if let pid = watchedPID {
            if !PowerManager.isProcessRunning(pid: pid) {
                deactivate()
                return
            }
        }

        // 3. 전원 및 배터리 조건 체크
        let isAC = PowerManager.isACPowerConnected()
        if onlyOnACPower && !isAC {
            deactivate()
            return
        }

        if batterySafeguardEnabled, !isAC, let percent = PowerManager.currentBatteryPercentage() {
            if percent <= batteryThreshold {
                deactivate()
                return
            }
        }

        updateStatusMessage()
    }

    private func updateStatusMessage() {
        if !isActive {
            if statusMessage != "꺼짐 · 컴퓨터 자동 잠자기 허용" {
                statusMessage = "꺼짐 · 컴퓨터 자동 잠자기 허용"
            }
            return
        }

        var parts: [String] = []
        parts.append("작동 중")
        parts.append(currentMode == .display ? "화면 자동 꺼짐 방지" : "화면 자동 꺼짐 허용")

        if let watched = watchedProcessName {
            parts.append("감시 중: \(watched)")
        } else if selectedPreset != .indefinite {
            parts.append("남은 시간: \(formatRemainingTime(remainingSeconds))")
        } else {
            parts.append("무제한 유지")
        }

        let message = "● " + parts.joined(separator: " · ")
        if statusMessage != message {
            statusMessage = message
        }
    }

    private func formatRemainingTime(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
}
