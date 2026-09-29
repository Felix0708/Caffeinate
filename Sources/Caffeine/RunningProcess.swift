import AppKit
import Darwin

struct RunningProcess: Identifiable {
    let id: pid_t
    let name: String
    let isApp: Bool

    func matches(query: String, includeBackground: Bool) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return (isApp || includeBackground) &&
            (query.isEmpty || name.localizedCaseInsensitiveContains(query) || String(id) == query)
    }

    static func snapshot() throws -> [RunningProcess] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { throw CocoaError(.fileReadUnknown) }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let size = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let loaded = proc_listallpids(&pids, size)
        guard loaded > 0 else { throw CocoaError(.fileReadUnknown) }

        let apps = Dictionary(uniqueKeysWithValues: NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .map { ($0.processIdentifier, $0.localizedName ?? "App") })

        return pids.prefix(min(Int(loaded), pids.count)).compactMap { pid in
            guard pid > 1, pid != getpid() else { return nil }
            var bytes = [UInt8](repeating: 0, count: 1024)
            let length = proc_name(pid, &bytes, UInt32(bytes.count))
            guard length > 0 else { return nil }
            let name = apps[pid] ?? String(decoding: bytes.prefix(Int(length)).prefix { $0 != 0 }, as: UTF8.self)
            guard !name.isEmpty else { return nil }
            return RunningProcess(id: pid, name: name, isApp: apps[pid] != nil)
        }.sorted {
            if $0.isApp != $1.isApp { return $0.isApp }
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
