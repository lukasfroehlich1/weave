import Foundation

enum AgentStatus: String {
    case idle
    case working
    case needsInput = "permission"
    case review
}

@MainActor
class AgentStatusMonitor {
    static let statusDir = "~/.weave/status".expandingTilde

    private var source: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    var onStatusChange: ((String, AgentStatus) -> Void)?

    func start() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: Self.statusDir, withIntermediateDirectories: true)

        if let files = try? fm.contentsOfDirectory(atPath: Self.statusDir) {
            for file in files {
                try? fm.removeItem(atPath: "\(Self.statusDir)/\(file)")
            }
        }

        dirFD = open(Self.statusDir, O_EVTONLY)
        guard dirFD >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scanStatusFiles()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.dirFD, fd >= 0 { close(fd) }
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func scanStatusFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: Self.statusDir) else { return }
        for file in files {
            let path = "\(Self.statusDir)/\(file)"
            guard let data = fm.contents(atPath: path),
                  let content = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let status = AgentStatus(rawValue: content) else { continue }
            onStatusChange?(file, status)
        }
    }

    nonisolated static func removeStatus(tabID: String) {
        try? FileManager.default.removeItem(atPath: "\(statusDir)/\(tabID)")
    }
}
