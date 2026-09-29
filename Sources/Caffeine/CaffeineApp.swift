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
    @State private var choosingProcess = false

    var body: some View {
        Group {
            if choosingProcess {
                ProcessPickerView(appState: appState) { choosingProcess = false }
            } else {
                controls
            }
        }
        .frame(width: 360)
    }

    private var controls: some View {
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
                    Text("앱/작업").tag(nil as DurationPreset?)
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
            Text("작동 중에는 체크를 해제해도 화면만 자동으로 꺼지고 작업은 계속됩니다.\n밝기는 직접 조절할 수 있습니다.\n덮개를 닫으면 컴퓨터가 잠들 수 있습니다.")
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
                Button("종료 감시 중지 (\(watchedName))") {
                    appState.stopWatchingProcess()
                }
            } else {
                Button("앱·작업이 종료될 때까지…") {
                    choosingProcess = true
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
    }

}
