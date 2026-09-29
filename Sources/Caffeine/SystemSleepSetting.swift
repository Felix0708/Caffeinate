import Foundation
import Combine

// This is a persistent, system-wide setting, independent of the app's assertions.
@MainActor
final class SystemSleepSetting: ObservableObject {
    @Published private(set) var isEnabled: Bool?
    @Published private(set) var isChanging = false
    @Published private(set) var errorMessage: String?

    private let read: () throws -> Bool
    private let write: @Sendable (Bool) throws -> Bool

    init(read: @escaping () throws -> Bool = SystemSleepSetting.readSetting,
         write: @escaping @Sendable (Bool) throws -> Bool = { try SystemSleepSetting.writeSetting($0) }) {
        self.read = read
        self.write = write
        refresh()
    }

    func refresh(clearError: Bool = true) {
        guard !isChanging else { return }
        do {
            isEnabled = try read()
            if clearError { errorMessage = nil }
        } catch {
            isEnabled = nil
            errorMessage = "시스템 설정을 읽지 못했습니다. 잠시 후 다시 확인하세요."
        }
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isChanging, isEnabled != nil, isEnabled != enabled else { return }
        isChanging = true
        errorMessage = nil
        let write = self.write
        do {
            let applied = try await Task.detached { try write(enabled) }.value
            if !applied { errorMessage = "변경을 취소했습니다." }
        } catch {
            errorMessage = "설정을 변경하지 못했습니다. 관리자 인증을 확인하고 다시 시도하세요."
        }
        isChanging = false
        refresh(clearError: false)
        if errorMessage == nil, isEnabled != enabled {
            errorMessage = "변경 결과를 확인하지 못했습니다. 현재 상태를 다시 확인하세요."
        }
    }

    nonisolated static func parseSetting(_ output: String) throws -> Bool {
        let values = output.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.first == "SleepDisabled", fields.count == 2 else { return nil }
            return String(fields[1])
        }
        guard values.count == 1, let value = values.first, value == "0" || value == "1" else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return value == "1"
    }

    nonisolated static func readSetting() throws -> Bool {
        try parseSetting(run("/usr/bin/pmset", arguments: ["-g"]))
    }

    nonisolated static func writeSetting(_ enabled: Bool) throws -> Bool {
        // Only fixed commands reach the administrator shell; no user input or passwords.
        let script = """
        try
            do shell script "/usr/bin/pmset -a disablesleep \(enabled ? "1" : "0")" with administrator privileges
        on error number -128
            return "cancelled"
        end try
        """
        return try run("/usr/bin/osascript", arguments: ["-e", script])
            .trimmingCharacters(in: .whitespacesAndNewlines) != "cancelled"
    }

    nonisolated private static func run(_ executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableRuntimeMismatch) }
        return String(decoding: data, as: UTF8.self)
    }
}
