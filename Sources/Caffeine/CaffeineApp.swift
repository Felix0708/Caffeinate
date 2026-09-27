import SwiftUI
import AppKit

@main
struct CaffeineApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView(appState: appState)
        } label: {
            HStack(spacing: 2) {
                Image(systemName: appState.menuBarIconName)
                if !appState.menuBarTitle.isEmpty {
                    Text(appState.menuBarTitle)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        // 1. 현재 상태 헤더
        Text("☕️ Caffeine")
            .font(.headline)
        Text(appState.statusMessage)
            .font(.caption)

        Divider()

        // 2. 즉시 토글
        Button(appState.isActive ? "Caffeine 끄기 (절전 허용)" : "Caffeine 켜기 (절전 방지)") {
            appState.toggle()
        }
        .keyboardShortcut("t", modifiers: [.command])

        Divider()

        // 3. 시간 설정 (타이머)
        Menu("⏱️ 유지 시간 (Timer)") {
            ForEach(DurationPreset.allCases) { preset in
                Button {
                    appState.activate(preset: preset)
                } label: {
                    HStack {
                        Text(preset.label)
                        if appState.isActive && appState.selectedPreset == preset && appState.watchedPID == nil {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        // 4. 모드 선택
        Menu("🎯 절전 방지 모드") {
            Button {
                appState.setMode(.display)
            } label: {
                HStack {
                    Text("화면 켜짐 유지 (-d)")
                    if appState.currentMode == .display {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }

            Button {
                appState.setMode(.system)
            } label: {
                HStack {
                    Text("시스템만 유지 (-i)")
                    if appState.currentMode == .system {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }
        }

        Divider()

        // 5. 스마트 트리거 옵션
        Toggle("⚡️ AC 전원 연결 중에만 동작", isOn: $appState.onlyOnACPower)
            .onChange(of: appState.onlyOnACPower) { newValue in
                if newValue && !PowerManager.isACPowerConnected() && appState.isActive {
                    appState.deactivate()
                }
            }

        Toggle("🔋 배터리 20% 이하 시 자동 해제", isOn: $appState.batterySafeguardEnabled)

        Divider()

        // 6. 프로세스 감시
        if let watchedName = appState.watchedProcessName {
            Button("🛑 프로세스 감시 중지 (\(watchedName))") {
                appState.stopWatchingProcess()
            }
        } else {
            Button("🔍 프로세스 감시 (-w PID)...") {
                promptForPID()
            }
        }

        Divider()

        // 7. 부팅 시 자동 시작 (Launch at Login)
        Toggle("🚀 컴퓨터 켤 때 자동 시작", isOn: Binding(
            get: { appState.launchAtLogin },
            set: { appState.setLaunchAtLogin(enabled: $0) }
        ))

        Divider()

        // 8. 종료
        Button("Caffeine 종료") {
            appState.deactivate()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private func promptForPID() {
        let alert = NSAlert()
        alert.messageText = "프로세스 감시 (caffeinate -w <PID>)"
        alert.informativeText = "감시할 프로세스의 PID(숫자)를 입력하세요.\n해당 프로세스(빌드, 인코딩, 파이썬 학습 등)가 종료되면 Caffeine도 자동으로 해제됩니다."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "감시 시작")
        alert.addButton(withTitle: "취소")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.placeholderString = "예: 12345"
        alert.accessoryView = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let pid = Int32(text), pid > 0 {
                appState.startWatchingProcess(pid: pid)
            }
        }
    }
}
