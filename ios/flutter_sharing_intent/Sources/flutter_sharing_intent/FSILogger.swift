// FSILogger.swift
// Persistent, file-based debug logger shared between the host app and the
// Share Extension process via the App Group container. Needed because the
// extension and the host app run as separate processes and neither can be
// reliably attached to a debugger over wireless Xcode/Flutter tooling, so
// stdout/NSLog output alone is not enough to diagnose hand-off issues.

import Foundation

public final class FSILogger {
    public static let shared = FSILogger()

    private let queue = DispatchQueue(label: "com.techind.flutter_sharing_intent.logger")
    private let maxBytes = 512 * 1024 // truncate to keep the shared file group small

    private var logFileURL: URL? {
        let groupId = (Bundle.main.object(forInfoDictionaryKey: kAppGroupIdKey) as? String)
            ?? "group.\(Bundle.main.bundleIdentifier ?? "")"
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupId)?
            .appendingPathComponent("fsi_debug.log")
    }

    private init() {}

    public func log(_ message: String, tag: String = "") {
        queue.async {
            guard let url = self.logFileURL else { return }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestamp = formatter.string(from: Date())
            let prefix = tag.isEmpty ? "" : "[\(tag)] "
            let line = "\(timestamp) \(prefix)\(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    handle.seekToEndOfFile()
                    handle.write(data)
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
            self.trimIfNeeded(url: url)
        }
    }

    private func trimIfNeeded(url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > maxBytes,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let trimmed = String(content.suffix(maxBytes / 2))
        try? trimmed.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    public func readAll() -> String {
        queue.sync {
            guard let url = logFileURL, let content = try? String(contentsOf: url, encoding: .utf8) else {
                return ""
            }
            return content
        }
    }

    public func clear() {
        queue.sync {
            guard let url = logFileURL else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }

    public var fileURLForSharing: URL? {
        queue.sync { logFileURL }
    }
}
