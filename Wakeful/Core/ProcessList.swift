import AppKit
import Darwin

struct RunningProcess: Hashable {
    let pid: pid_t
    let name: String
}

enum ProcessList {
    /// All processes, by short name (`comm`, up to 16 characters).
    /// Uses `sysctl` because libproc's `proc_listallpids` returns nothing inside the App Sandbox.
    static func all() -> [RunningProcess] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        // Leave headroom for processes spawned between the two calls.
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 16)
        size = procs.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 3, &procs, &size, nil, 0) == 0 else { return [] }

        return procs.prefix(size / MemoryLayout<kinfo_proc>.stride).compactMap { info in
            var comm = info.kp_proc.p_comm
            let name = withUnsafeBytes(of: &comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return info.kp_proc.p_pid > 0 && !name.isEmpty ? RunningProcess(pid: info.kp_proc.p_pid, name: name) : nil
        }
    }

    /// Running processes whose name matches one of the configured AI agent names.
    static func agents(matching names: [String]) -> [RunningProcess] {
        let wanted = Set(names.map { $0.lowercased() })
        return all()
            .filter { wanted.contains($0.name.lowercased()) }
            .sorted { $0.name == $1.name ? $0.pid < $1.pid : $0.name < $1.name }
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        // EPERM means the process exists but belongs to someone else (or the sandbox denies signals).
        kill(pid, 0) == 0 || errno == EPERM
    }

    static func regularApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}
