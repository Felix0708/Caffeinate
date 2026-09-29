import SwiftUI

struct ProcessPickerView: View {
    @ObservedObject var appState: AppState
    let onClose: () -> Void
    @State private var processes: [RunningProcess] = []
    @State private var query = ""
    @State private var includeBackground = false
    @State private var errorMessage: String?

    private var matches: [RunningProcess] {
        processes.filter { $0.matches(query: query, includeBackground: includeBackground) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("앱·작업 선택").font(.headline)
                Spacer()
                Button("돌아가기", action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            Text("선택한 항목이 종료될 때까지 잠자기를 방지합니다.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            TextField("앱 또는 작업 이름 검색", text: $query)
                .textFieldStyle(.roundedBorder)
            Toggle("백그라운드 작업도 표시", isOn: $includeBackground)
                .toggleStyle(.checkbox)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if matches.isEmpty {
                        Text("일치하는 항목이 없습니다.\n백그라운드 작업 표시나 새로고침을 시도하세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical)
                    }
                    ForEach(matches) { process in
                        Button {
                            if appState.startWatchingProcess(pid: process.id, name: process.name) {
                                onClose()
                            } else {
                                errorMessage = appState.statusMessage
                            }
                        } label: {
                            HStack {
                                Image(systemName: process.isApp ? "app" : "terminal")
                                Text(process.name).lineLimit(1)
                                Spacer()
                                Text("PID \(process.id)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
            .frame(height: 230)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("앱 안의 작업 완료가 아니라 앱·프로세스 종료를 기준으로 합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("목록 새로고침", action: refresh)
        }
        .padding(16)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        do {
            processes = try RunningProcess.snapshot()
            errorMessage = nil
        } catch {
            processes = []
            errorMessage = "실행 목록을 읽지 못했습니다. 새로고침을 눌러주세요."
        }
    }
}
