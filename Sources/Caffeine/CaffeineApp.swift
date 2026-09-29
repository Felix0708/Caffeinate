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
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Caffeine", systemImage: appState.menuBarIconName)
                .font(.headline)
            Text("컴퓨터 자동 잠자기 방지")
                .font(.subheadline)
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(appState.isActive ? "자동 잠자기 방지 끄기" : "자동 잠자기 방지 켜기") {
                appState.toggle()
            }
            .keyboardShortcut("t", modifiers: [.command])
            .buttonStyle(.borderedProminent)

            Divider()

            Text("유지 시간")
                .font(.subheadline.bold())
            Picker("유지 시간", selection: Binding<DurationPreset?>(
                get: { appState.watchedPID == nil ? appState.selectedPreset : nil },
                set: { if let preset = $0 { appState.activate(preset: preset) } }
            )) {
                if appState.watchedPID != nil {
                    Text("PID").tag(nil as DurationPreset?)
                }
                ForEach(DurationPreset.allCases) { preset in
                    Text(preset.label).tag(Optional(preset))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("시간을 변경하면 바로 시작합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("화면 자동 꺼짐도 방지", isOn: Binding(
                get: { appState.currentMode == .display },
                set: { appState.setMode($0 ? .display : .system) }
            ))
            Text("작동 중에는 체크를 해제해도 화면만 자동으로 꺼지고 작업은 계속됩니다. 밝기는 직접 조절할 수 있습니다.\n덮개를 닫으면 컴퓨터가 잠들 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Toggle("AC 전원 연결 중에만 동작", isOn: $appState.onlyOnACPower)
                .onChange(of: appState.onlyOnACPower) { newValue in
                    if newValue && !PowerManager.isACPowerConnected() && appState.isActive {
                        appState.deactivate()
                    }
                }
            Toggle("배터리 20% 이하 시 자동 해제", isOn: $appState.batterySafeguardEnabled)

            if let watchedName = appState.watchedProcessName {
                Button("프로세스 감시 중지 (\(watchedName))") {
                    appState.stopWatchingProcess()
                }
            } else {
                Button("프로세스 감시 (PID)…") {
                    promptForPID()
                }
            }

            Divider()

            Toggle("로그인 시 자동 시작", isOn: Binding(
                get: { appState.launchAtLogin },
                set: { appState.setLaunchAtLogin(enabled: $0) }
            ))
            Button("Caffeine 종료") {
                appState.deactivate()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .toggleStyle(.checkbox)
        .padding(16)
        .frame(width: 360)
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
