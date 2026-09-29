import SwiftUI
import AppKit

@main
struct CaffeineApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var systemSleep = SystemSleepSetting()

    var body: some Scene {
        MenuBarExtra {
            MenuView(appState: appState, systemSleep: systemSleep)
        } label: {
            HStack(spacing: 2) {
                Image(systemName: systemSleep.isEnabled == true ? "cup.and.saucer.fill" : appState.menuBarIconName)
                if systemSleep.isEnabled == true {
                    Image(systemName: "laptopcomputer")
                }
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
    @ObservedObject var systemSleep: SystemSleepSetting
    @State private var choosingProcess = false

    var body: some View {
        Group {
            if choosingProcess {
                ProcessPickerView(appState: appState) { choosingProcess = false }
            } else {
                ScrollView { controls }
                    .frame(height: 640)
            }
        }
        .frame(width: 360)
        .onAppear { systemSleep.refresh() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            systemSleep.refresh()
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Caffeine", systemImage: appState.menuBarIconName)
                .font(.headline)
            if systemSleep.isEnabled == true {
                Label("덮개 닫아도 계속 실행 · 켜짐", systemImage: "laptopcomputer")
                    .font(.subheadline.bold())
            }
            Text("기본 기능 · 자동 잠자기 방지")
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
            Text("작동 중에는 체크를 해제해도 화면만 자동으로 꺼지고 작업은 계속됩니다.\n밝기는 직접 조절할 수 있습니다.\n덮개를 닫고 쓰려면 아래 별도 설정을 켜세요.")
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

            Toggle("덮개 닫아도 계속 실행", isOn: Binding(
                get: { systemSleep.isEnabled == true },
                set: { enabled in Task { await systemSleep.setEnabled(enabled) } }
            ))
            .disabled(systemSleep.isChanging || systemSleep.isEnabled == nil)
            Text(systemSleep.isChanging ? "관리자 인증 대기 중…" :
                    systemSleep.isEnabled == true ? "켜짐 · 시스템 잠자기 차단" :
                    systemSleep.isEnabled == false ? "꺼짐 · 덮개를 닫으면 잠들 수 있음" : "상태 확인 불가")
                .font(.caption.bold())
            Text("관리자 인증이 필요한 별도 시스템 설정입니다.\n타이머·앱 종료·위 배터리 보호로 꺼지지 않습니다.\n가방에 넣기 전에는 직접 체크를 해제하세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = systemSleep.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
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
            .disabled(systemSleep.isChanging)
            .keyboardShortcut("q", modifiers: [.command])
        }
        .toggleStyle(.checkbox)
        .padding(16)
    }

}
