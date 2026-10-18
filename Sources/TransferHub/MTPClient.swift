import Foundation

struct MTPProgress: Sendable {
    let filePath: String
    let bytesCopied: Int64
    let totalBytes: Int64
}

enum MTPError: LocalizedError {
    case helperMissing
    case noDevice
    case command(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing: return "The MTP helper is unavailable. Rebuild the app with OpenMTP installed."
        case .noDevice: return "No MTP device found. Unlock the phone and choose File transfer / Android Auto in its USB settings."
        case .command(let message): return message
        }
    }
}

private final class ProcessTimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

struct MTPClient {
    private let executable: URL?

    init() {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/mtp-cli")
        let candidates = [
            bundled,
            URL(fileURLWithPath: "/Applications/OpenMTP.app/Contents/Resources/bin/mtp-cli"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications/OpenMTP.app/Contents/Resources/bin/mtp-cli")
        ]
        executable = candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    var isAvailable: Bool { executable != nil }

    func storages() async throws -> [MTPStorage] {
        let output = try await run(["storage-list"])
        let lines = output.components(separatedBy: .newlines)
        let descriptionPattern = try! NSRegularExpression(pattern: "(?i)description\\s*:\\s*(.+)$")
        let hexPattern = try! NSRegularExpression(pattern: "0x[0-9a-fA-F]+")
        let decimalPattern = try! NSRegularExpression(pattern: "\\d+")
        let found = lines.compactMap { line -> MTPStorage? in
            let full = NSRange(line.startIndex..., in: line)
            guard let descriptionMatch = descriptionPattern.firstMatch(in: line, range: full),
                  let descriptionRange = Range(descriptionMatch.range(at: 1), in: line) else { return nil }
            let prefix = String(line[..<descriptionRange.lowerBound])
            let idMatch = hexPattern.firstMatch(in: prefix, range: NSRange(prefix.startIndex..., in: prefix))
                ?? decimalPattern.firstMatch(in: prefix, range: NSRange(prefix.startIndex..., in: prefix))
            guard let idMatch, let idRange = Range(idMatch.range, in: prefix) else { return nil }
            let rawID = String(prefix[idRange])
            let storageID: String
            if rawID.lowercased().hasPrefix("0x"), let value = UInt64(rawID.dropFirst(2), radix: 16) {
                storageID = String(value)
            } else {
                storageID = rawID
            }
            let name = String(line[descriptionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return MTPStorage(id: storageID, name: name)
        }
        guard !found.isEmpty else { throw MTPError.noDevice }
        return found
    }

    func listFiles(storageID: String, path: String) async throws -> [PhoneFile] {
        let output = try await run(["storage \(storageID)", "lsext \"\(escape(path))\""])
        let timestampPattern = try! NSRegularExpression(pattern: "^(.*?)\\s+(\\d{4}-\\d{2}-\\d{2}\\s+\\d{2}:\\d{2}:\\d{2})")
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return output.components(separatedBy: .newlines).compactMap { line in
            let full = NSRange(line.startIndex..., in: line)
            guard let match = timestampPattern.firstMatch(in: line, range: full),
                  let headerRange = Range(match.range(at: 1), in: line),
                  let matchRange = Range(match.range, in: line),
                  let timestampRange = Range(match.range(at: 2), in: line) else { return nil }
            let header = String(line[headerRange]).split(whereSeparator: \.isWhitespace).map(String.init)
            guard header.count >= 3 else { return nil }
            let name = String(line[matchRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != ".", name != ".." else { return nil }
            let fullPath = path == "/" ? "/\(name)" : "\(path.hasSuffix("/") ? String(path.dropLast()) : path)/\(name)"
            let isFolder = header[2] == "3001"
            return PhoneFile(id: fullPath, name: name, path: fullPath, isDirectory: isFolder, size: Int64(header[1]), modifiedAt: dateFormatter.date(from: String(line[timestampRange])))
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func upload(storageID: String, localPath: String, remoteDirectory: String, progress: (@Sendable (MTPProgress) -> Void)? = nil) async throws {
        _ = try await runTransfer(["-e", "storage \(storageID)", "put \"\(escape(localPath))\" \"\(escape(remoteDirectory))\""], progress: progress)
    }

    func makeDirectory(storageID: String, path: String) async throws {
        _ = try await run(["-e", "storage \(storageID)", "mkdir \"\(escape(path))\""])
    }

    func download(storageID: String, remotePath: String, localPath: String, progress: (@Sendable (MTPProgress) -> Void)? = nil) async throws {
        _ = try await runTransfer(["-e", "storage \(storageID)", "get \"\(escape(remotePath))\" \"\(escape(localPath))\""], progress: progress)
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func run(_ arguments: [String]) async throws -> String {
        try await runProcess(arguments, progress: nil, timeout: 15)
    }

    private func runTransfer(_ arguments: [String], progress: (@Sendable (MTPProgress) -> Void)?) async throws -> String {
        try await runProcess(arguments, progress: progress, timeout: 60 * 60)
    }

    private func runProcess(_ arguments: [String], progress: (@Sendable (MTPProgress) -> Void)?, timeout: TimeInterval) async throws -> String {
        guard let executable else { throw MTPError.helperMissing }
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let timeoutFlag = ProcessTimeoutFlag()
            let pipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning { timeoutFlag.set(); process.terminate() }
                }
                var data = Data()
                while true {
                    let chunk = pipe.fileHandleForReading.availableData
                    if chunk.isEmpty { break }
                    data.append(chunk)
                    if let progress {
                        let text = String(decoding: chunk, as: UTF8.self)
                        for line in text.components(separatedBy: .newlines) where line.hasPrefix(":progress ") {
                            let fields = line.split(separator: " ")
                            guard fields.count >= 4, let copied = Int64(fields[fields.count - 2]), let total = Int64(fields[fields.count - 1]) else { continue }
                            let path = fields.dropFirst().dropLast(2).joined(separator: " ")
                            progress(MTPProgress(filePath: path, bytesCopied: copied, totalBytes: total))
                        }
                    }
                }
                process.waitUntilExit()
                if timeoutFlag.timedOut { throw MTPError.command(progress == nil ? "MTP did not respond within 15 seconds. Check that the phone is unlocked and in File transfer mode, then retry." : "MTP transfer timed out. Retry to resume where supported.") }
                let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard process.terminationStatus == 0 else {
                    throw MTPError.command(output.isEmpty ? "MTP command failed (\(process.terminationStatus))." : output)
                }
                return output
            } catch let error as MTPError {
                throw error
            } catch {
                throw MTPError.command(error.localizedDescription)
            }
        }.value
    }
}
