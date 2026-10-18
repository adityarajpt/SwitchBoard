import Foundation

enum ADBError: LocalizedError {
    case missing
    case command(String)

    var errorDescription: String? {
        switch self {
        case .missing: return "ADB was not found. Install Android SDK Platform-Tools, then restart Transfer Hub."
        case .command(let message): return message
        }
    }
}

final class ADBClient: @unchecked Sendable {
    private var executable: URL?

    init() {
        let savedPath = UserDefaults.standard.string(forKey: "transfer-hub.adb-path").map { URL(fileURLWithPath: $0) }
        let candidates = [savedPath].compactMap { $0 } + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)).appendingPathComponent("adb") } + [
            URL(fileURLWithPath: "/opt/homebrew/bin/adb"),
            URL(fileURLWithPath: "/usr/local/bin/adb"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Android/sdk/platform-tools/adb")
        ]
        executable = candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    var isAvailable: Bool { executable != nil }

    func setExecutable(_ url: URL) throws {
        guard url.lastPathComponent == "adb", FileManager.default.isExecutableFile(atPath: url.path) else {
            throw ADBError.command("Choose the executable named adb from Android SDK Platform-Tools.")
        }
        executable = url
        UserDefaults.standard.set(url.path, forKey: "transfer-hub.adb-path")
    }

    func devices() async throws -> [ConnectedDevice] {
        let output = try await run(["devices", "-l"])
        return output.split(separator: "\n").dropFirst(1).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, fields[0] != "*" else { return nil }
            let serial = fields[0]
            let state = fields[1]
            let modelField = fields.first(where: { $0.hasPrefix("model:") })
            let model = modelField.map { String($0.dropFirst("model:".count)).replacingOccurrences(of: "_", with: " ") } ?? "Android device"
            let link: LinkKind = serial.contains(":") ? .wifi : .usb
            return ConnectedDevice(serial: serial, model: model, state: state, link: link, transport: .adb)
        }
    }

    func listFiles(serial: String, path: String) async throws -> [PhoneFile] {
        let safePath = shellQuote(path)
        let output = try await run(["-s", serial, "shell", "ls", "-la", safePath])
        return output.split(separator: "\n").compactMap { raw in
            let line = String(raw)
            guard !line.hasSuffix(":") else { return nil }
            let fields = line.split(maxSplits: 8, whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count == 9, fields[0].first == "d" || fields[0].first == "-" else { return nil }
            let name = fields[8]
            guard name != ".", name != ".." else { return nil }
            let isDir = fields[0].first == "d"
            let fullPath = path == "/" ? "/\(name)" : "\(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "" ? "" : path)/\(name)"
            return PhoneFile(id: fullPath, name: name, path: fullPath, isDirectory: isDir, size: Int64(fields[4]))
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func push(serial: String, localPath: String, remotePath: String) async throws {
        _ = try await run(["-s", serial, "push", localPath, remotePath])
    }

    func pushResumable(serial: String, localPath: String, remotePath: String, jobID: String, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        guard let executable else { throw ADBError.missing }
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: localPath, isDirectory: &isDirectory), isDirectory.boolValue {
            _ = try await run(["-s", serial, "push", localPath, remotePath])
            return
        }
        try await Task.detached(priority: .userInitiated) {
            let source = try FileHandle(forReadingFrom: URL(fileURLWithPath: localPath))
            defer { try? source.close() }
            let total = (try? FileManager.default.attributesOfItem(atPath: localPath)[.size] as? NSNumber)?.int64Value ?? 0
            let partial = remotePath + ".transferhub-\(jobID).part"
            let sizeCommand = "if [ -f \(self.shellQuote(partial)) ]; then wc -c < \(self.shellQuote(partial)); else echo 0; fi"
            let remoteSizeOutput = try await self.runDetached(executable, ["-s", serial, "shell", "sh", "-c", sizeCommand])
            var offset = Int64(remoteSizeOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            if offset > total {
                _ = try await self.runDetached(executable, ["-s", serial, "shell", "rm", "-f", self.shellQuote(partial)])
                offset = 0
            }
            try source.seek(toOffset: UInt64(offset))
            let process = Process()
            let input = Pipe()
            process.executableURL = executable
            process.arguments = ["-s", serial, "shell", "cat >> \(self.shellQuote(partial))"]
            process.standardInput = input
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            let writer = input.fileHandleForWriting
            var sent = offset
            do {
                while true {
                    let data = try source.read(upToCount: 1_048_576) ?? Data()
                    if data.isEmpty { break }
                    try writer.write(contentsOf: data)
                    sent += Int64(data.count)
                    progress(sent, total)
                }
                try writer.close()
            } catch {
                try? writer.close()
                process.terminate()
                throw error
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw ADBError.command("ADB disconnected while sending. Retry to resume the partial file.") }
            guard sent == total else { throw ADBError.command("The source file changed during transfer. Retry to continue.") }
            _ = try await self.runDetached(executable, ["-s", serial, "shell", "mv", "-f", self.shellQuote(partial), self.shellQuote(remotePath)])
        }.value
    }

    func pull(serial: String, remotePath: String, localPath: String) async throws {
        _ = try await run(["-s", serial, "pull", remotePath, localPath])
    }

    func copyRemoteFile(serial: String, source: String, destination: String) async throws {
        let command = "test ! -e \(shellQuote(destination)) && cp -R \(shellQuote(source)) \(shellQuote(destination))"
        _ = try await run(["-s", serial, "shell", "sh", "-c", command])
    }

    func makeDirectory(serial: String, path: String) async throws {
        _ = try await run(["-s", serial, "shell", "sh", "-c", "mkdir -p \(shellQuote(path))"])
    }

    func fileModifiedAt(serial: String, path: String) async throws -> (size: Int64, modifiedAt: Date?) {
        let output = try await run(["-s", serial, "shell", "sh", "-c", "stat -c '%s %Y' \(shellQuote(path))"])
        let fields = output.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2, let size = Int64(fields[0]), let seconds = TimeInterval(fields[1]) else {
            throw ADBError.command("Could not read file metadata for \(URL(fileURLWithPath: path).lastPathComponent).")
        }
        return (size, Date(timeIntervalSince1970: seconds))
    }

    func pullResumable(serial: String, remotePath: String, localPath: String, jobID: String, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        guard let executable else { throw ADBError.missing }
        try await Task.detached(priority: .userInitiated) {
            let sizeCommand = "wc -c < \(self.shellQuote(remotePath))"
            let remoteSizeOutput = try await self.runDetached(executable, ["-s", serial, "shell", "sh", "-c", sizeCommand])
            guard let total = Int64(remoteSizeOutput.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw ADBError.command("Could not read the remote file size.") }
            let partialPath = localPath + ".transferhub-\(jobID).part"
            let partialURL = URL(fileURLWithPath: partialPath)
            let manager = FileManager.default
            var offset = (try? manager.attributesOfItem(atPath: partialPath)[.size] as? NSNumber)?.int64Value ?? 0
            if offset > total {
                try? manager.removeItem(at: partialURL)
                offset = 0
            }
            if !manager.fileExists(atPath: partialPath) { manager.createFile(atPath: partialPath, contents: Data()) }
            let output = try FileHandle(forWritingTo: partialURL)
            try output.seekToEnd()
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executable
            process.arguments = ["-s", serial, "exec-out", "sh", "-c", "tail -c +\(offset + 1) \(self.shellQuote(remotePath))"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try process.run()
            var received = offset
            while true {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty { break }
                try output.write(contentsOf: data)
                received += Int64(data.count)
                progress(received, total)
            }
            try output.close()
            process.waitUntilExit()
            guard process.terminationStatus == 0, received == total else { throw ADBError.command("ADB disconnected while receiving. Retry to resume the partial file.") }
            let destination = URL(fileURLWithPath: localPath)
            if manager.fileExists(atPath: localPath) {
                _ = try manager.replaceItemAt(destination, withItemAt: partialURL)
            } else {
                try manager.moveItem(at: partialURL, to: destination)
            }
        }.value
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func run(_ arguments: [String]) async throws -> String {
        guard let executable else { throw ADBError.missing }
        return try await runDetached(executable, arguments)
    }

    private func runDetached(_ executable: URL, _ arguments: [String]) async throws -> String {
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(decoding: data, as: UTF8.self)
                guard process.terminationStatus == 0 else {
                    throw ADBError.command(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ADB command failed (\(process.terminationStatus))." : output.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                return output
            } catch let error as ADBError {
                throw error
            } catch {
                throw ADBError.command(error.localizedDescription)
            }
        }.value
    }
}
