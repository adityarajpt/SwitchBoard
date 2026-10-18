import AppKit
import CoreImage.CIFilterBuiltins
import Darwin
import Foundation
import Network

struct PortalUpload: Sendable {
    let id: String
    let name: String
    let size: Int64
    let url: URL
}

private struct UploadManifest: Codable {
    let id: String
    let name: String
    let size: Int64
    var received: Int64
}

private struct OutboxEntry: Codable, Identifiable {
    let id: String
    let name: String
    let size: Int64
    let path: String
}

private struct HTTPRequest {
    let method: String
    let target: String
    let headers: [String: String]
    let body: Data
}

@MainActor
final class WiFiPortal: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var address: String?
    @Published private(set) var qrImage: NSImage?
    @Published private(set) var lastError: String?

    var onUploadComplete: ((PortalUpload) -> Void)?
    var onUploadProgress: ((String, String, Int64, Int64) -> Void)?

    private var listener: NWListener?
    private var token = ""
    private var outbox: [String: OutboxEntry] = [:]
    private let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("TransferHub", isDirectory: true)
    private let incoming = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads/Transfer Hub", isDirectory: true)
    private let chunkLimit = 1_048_576

    func start() throws {
        guard listener == nil else { return }
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        isStarting = true
        let candidate = NWEndpoint.Port(rawValue: 8765)!
        do {
            let newListener = try NWListener(using: .tcp, on: candidate)
            configure(newListener, port: candidate)
        } catch {
            let randomListener = try NWListener(using: .tcp, on: .any)
            configure(randomListener, port: nil)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        isStarting = false
        address = nil
        qrImage = nil
        token = ""
    }

    func clearError() { lastError = nil }

    func addOutboxFiles(_ urls: [URL]) throws {
        let outboxFolder = appSupport.appendingPathComponent("WiFi Outbox", isDirectory: true)
        try FileManager.default.createDirectory(at: outboxFolder, withIntermediateDirectories: true)
        for url in urls {
            let id = UUID().uuidString
            let destination = outboxFolder.appendingPathComponent(id + "-" + url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: destination)
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            outbox[id] = OutboxEntry(id: id, name: url.lastPathComponent, size: size, path: destination.path)
        }
    }

    private func configure(_ newListener: NWListener, port: NWEndpoint.Port?) {
        listener = newListener
        newListener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.receive(connection) }
        }
        newListener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    guard let port = newListener.port, let ip = self.localIPv4() else {
                        self.lastError = "Could not find this Mac's local Wi-Fi address."
                        self.stop()
                        return
                    }
                    let url = "http://\(ip):\(port.rawValue)/?t=\(self.token)"
                    self.address = url
                    self.qrImage = self.makeQR(url)
                    self.isRunning = true
                    self.isStarting = false
                case .failed(let error):
                    self.lastError = error.localizedDescription
                    self.stop()
                default: break
                }
            }
        }
        newListener.start(queue: .main)
        _ = port
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveMore(connection, buffer: Data())
    }

    private func receiveMore(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: chunkLimit + 16_384) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var next = buffer
                if let data { next.append(data) }
                if let request = self.parse(next) {
                    self.respond(to: request, on: connection)
                } else if next.count > self.chunkLimit + 16_384 || complete || error != nil {
                    self.sendStatus(400, body: Data("Malformed request".utf8), contentType: "text/plain", on: connection)
                } else {
                    self.receiveMore(connection, buffer: next)
                }
            }
        }
    }

    private func parse(_ data: Data) -> HTTPRequest? {
        let delimiter = Data([13, 10, 13, 10])
        guard let range = data.range(of: delimiter),
              let head = String(data: data[..<range.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let requestParts = first.split(separator: " ").map(String.init)
        guard requestParts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon]).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard contentLength <= chunkLimit else { return HTTPRequest(method: "413", target: "", headers: [:], body: Data()) }
        let bodyStart = range.upperBound
        guard data.count - bodyStart >= contentLength else { return nil }
        let body = data[bodyStart..<data.index(bodyStart, offsetBy: contentLength)]
        return HTTPRequest(method: requestParts[0], target: requestParts[1], headers: headers, body: Data(body))
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        if request.method == "413" {
            sendStatus(413, body: Data("Chunk too large".utf8), contentType: "text/plain", on: connection)
            return
        }
        guard let components = URLComponents(string: "http://localhost\(request.target)") else {
            sendStatus(400, body: Data("Bad URL".utf8), contentType: "text/plain", on: connection)
            return
        }
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        guard query["t"] == token, !token.isEmpty else {
            sendStatus(403, body: Data("Session expired".utf8), contentType: "text/plain", on: connection)
            return
        }
        let path = components.path
        if request.method == "GET", path == "/" {
            sendStatus(200, body: Data(pageHTML.utf8), contentType: "text/html; charset=utf-8", on: connection)
        } else if request.method == "POST", path == "/api/start" {
            startUpload(request.body, on: connection)
        } else if request.method == "PUT", path == "/api/chunk" {
            writeChunk(query: query, body: request.body, on: connection)
        } else if request.method == "POST", path == "/api/finish" {
            finishUpload(query: query, on: connection)
        } else if request.method == "GET", path == "/api/outbox" {
            let entries = outbox.values.map { ["id": $0.id, "name": $0.name, "size": String($0.size)] }
            sendJSON(["files": entries], on: connection)
        } else if request.method == "GET", path == "/api/outbox/file" {
            sendOutboxFile(id: query["id"] ?? "", on: connection)
        } else {
            sendStatus(404, body: Data("Not found".utf8), contentType: "text/plain", on: connection)
        }
    }

    private func startUpload(_ body: Data, on connection: NWConnection) {
        guard let input = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let name = input["name"] as? String,
              let size = input["size"] as? Int64 else {
            sendStatus(400, body: Data("Invalid upload metadata".utf8), contentType: "text/plain", on: connection)
            return
        }
        let safeName = URL(fileURLWithPath: name).lastPathComponent
        guard !safeName.isEmpty, size >= 0 else {
            sendStatus(400, body: Data("Invalid file".utf8), contentType: "text/plain", on: connection)
            return
        }
        let id = (input["id"] as? String).flatMap { UUID(uuidString: $0) == nil ? nil : $0 } ?? UUID().uuidString
        let manifestURL = appSupport.appendingPathComponent("wifi-\(id).json")
        let partURL = appSupport.appendingPathComponent("wifi-\(id).part")
        var manifest: UploadManifest
        if let data = try? Data(contentsOf: manifestURL), let saved = try? JSONDecoder().decode(UploadManifest.self, from: data), saved.size == size, saved.name == safeName {
            let actual = (try? partURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            manifest = UploadManifest(id: saved.id, name: saved.name, size: size, received: min(actual, size))
        } else {
            manifest = UploadManifest(id: id, name: safeName, size: size, received: 0)
            FileManager.default.createFile(atPath: partURL.path, contents: Data())
        }
        persist(manifest, to: manifestURL)
        onUploadProgress?(manifest.id, manifest.name, manifest.received, manifest.size)
        sendJSON(["id": manifest.id, "offset": manifest.received], on: connection)
    }

    private func writeChunk(query: [String: String], body: Data, on connection: NWConnection) {
        guard let id = query["id"], let offset = Int64(query["offset"] ?? ""),
              let uuid = UUID(uuidString: id) else {
            sendStatus(400, body: Data("Invalid chunk".utf8), contentType: "text/plain", on: connection)
            return
        }
        let manifestURL = appSupport.appendingPathComponent("wifi-\(uuid.uuidString).json")
        let partURL = appSupport.appendingPathComponent("wifi-\(uuid.uuidString).part")
        guard let data = try? Data(contentsOf: manifestURL), var manifest = try? JSONDecoder().decode(UploadManifest.self, from: data),
              manifest.received == offset, offset + Int64(body.count) <= manifest.size else {
            sendStatus(409, body: Data("Offset mismatch".utf8), contentType: "text/plain", on: connection)
            return
        }
        do {
            let handle = try FileHandle(forWritingTo: partURL)
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: body)
            try handle.close()
            manifest.received += Int64(body.count)
            persist(manifest, to: manifestURL)
            onUploadProgress?(manifest.id, manifest.name, manifest.received, manifest.size)
            sendJSON(["offset": manifest.received], on: connection)
        } catch {
            sendStatus(500, body: Data(error.localizedDescription.utf8), contentType: "text/plain", on: connection)
        }
    }

    private func finishUpload(query: [String: String], on connection: NWConnection) {
        guard let id = query["id"], let uuid = UUID(uuidString: id) else {
            sendStatus(400, body: Data("Invalid upload id".utf8), contentType: "text/plain", on: connection)
            return
        }
        let manifestURL = appSupport.appendingPathComponent("wifi-\(uuid.uuidString).json")
        let partURL = appSupport.appendingPathComponent("wifi-\(uuid.uuidString).part")
        guard let data = try? Data(contentsOf: manifestURL), let manifest = try? JSONDecoder().decode(UploadManifest.self, from: data),
              manifest.received == manifest.size else {
            sendStatus(409, body: Data("Upload is incomplete".utf8), contentType: "text/plain", on: connection)
            return
        }
        do {
            let destination = uniqueDestination(named: manifest.name)
            try FileManager.default.moveItem(at: partURL, to: destination)
            try? FileManager.default.removeItem(at: manifestURL)
            onUploadComplete?(PortalUpload(id: manifest.id, name: manifest.name, size: manifest.size, url: destination))
            sendJSON(["ok": true, "name": manifest.name], on: connection)
        } catch {
            sendStatus(500, body: Data(error.localizedDescription.utf8), contentType: "text/plain", on: connection)
        }
    }

    private func sendOutboxFile(id: String, on connection: NWConnection) {
        guard let entry = outbox[id], let handle = FileHandle(forReadingAtPath: entry.path) else {
            sendStatus(404, body: Data("File not found".utf8), contentType: "text/plain", on: connection)
            return
        }
        let encodedName = entry.name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "file"
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename*=UTF-8''\(encodedName)\r\nContent-Length: \(entry.size)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.sendNextFileChunk(handle, connection: connection) }
        })
    }

    private func sendNextFileChunk(_ handle: FileHandle, connection: NWConnection) {
        let data = handle.readData(ofLength: chunkLimit)
        if data.isEmpty {
            try? handle.close()
            connection.cancel()
            return
        }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard error == nil else { try? handle.close(); connection.cancel(); return }
            Task { @MainActor in self?.sendNextFileChunk(handle, connection: connection) }
        })
    }

    private func sendJSON(_ object: Any, on connection: NWConnection) {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        sendStatus(200, body: data, contentType: "application/json", on: connection)
    }

    private func sendStatus(_ status: Int, body: Data, contentType: String, on connection: NWConnection) {
        let reason = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 409: "Conflict", 413: "Payload Too Large", 500: "Internal Server Error"][status] ?? "Error"
        var response = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func persist(_ manifest: UploadManifest, to url: URL) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func uniqueDestination(named name: String) -> URL {
        let initial = incoming.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: initial.path) else { return initial }
        let base = initial.deletingPathExtension().lastPathComponent
        let ext = initial.pathExtension
        var suffix = 2
        while true {
            let candidateName = ext.isEmpty ? "\(base) (\(suffix))" : "\(base) (\(suffix)).\(ext)"
            let candidate = incoming.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            suffix += 1
        }
    }

    private func makeQR(_ value: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent.integral) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func localIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var current: UnsafeMutablePointer<ifaddrs>? = first
        var addresses: [(String, String)] = []
        while let item = current {
            let interface = item.pointee
            if let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET), (interface.ifa_flags & UInt32(IFF_UP)) != 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let hostBytes = host.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
                    addresses.append((String(cString: interface.ifa_name), String(decoding: hostBytes, as: UTF8.self)))
                }
            }
            current = interface.ifa_next
        }
        return addresses.first(where: { $0.0 == "en0" })?.1 ?? addresses.first(where: { $0.0.hasPrefix("en") })?.1
    }

    private var pageHTML: String {
        """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark"><title>Transfer Hub</title>
        <style>body{font:16px -apple-system,system-ui;background:#0e1116;color:#f4f6f8;max-width:680px;margin:32px auto;padding:0 18px}h1{font-size:26px}p,.hint{color:#a5adb8}.card{background:#171c24;border:1px solid #29313d;border-radius:16px;padding:18px;margin:14px 0}input,button{font:inherit}button{background:#b8e86b;border:0;border-radius:10px;padding:12px 16px;color:#18200e;font-weight:700;margin-top:12px}progress{width:100%;height:12px}li{padding:9px 0;border-bottom:1px solid #29313d}a{color:#c5ef82}</style>
        <h1>Transfer Hub</h1><p>Connected to your Mac on the local network.</p><p><strong>Important:</strong> this phone and the Mac must be on the same Wi-Fi network. Cellular, guest Wi-Fi, or router client isolation may block transfers.</p>
        <section class="card"><h2>Send to Mac</h2><input id="files" type="file" multiple><button onclick="uploadAll()">Upload selected files</button><p id="status" class="hint">Files save to Downloads / Transfer Hub on your Mac.</p><progress id="progress" max="100" value="0"></progress></section>
        <section class="card"><h2>Get from Mac</h2><ul id="outbox"><li>Loading…</li></ul><button onclick="refreshOutbox()">Refresh files</button></section>
        <script>
        const token=new URLSearchParams(location.search).get('t');
        const api=(p)=>p+(p.includes('?')?'&':'?')+'t='+encodeURIComponent(token);
        async function refreshOutbox(){const r=await fetch(api('/api/outbox'));const j=await r.json();const el=document.getElementById('outbox');el.innerHTML='';if(!j.files.length){el.innerHTML='<li class="hint">No files sent from the Mac yet.</li>';return}for(const f of j.files){const li=document.createElement('li');const a=document.createElement('a');a.href=api('/api/outbox/file?id='+encodeURIComponent(f.id));a.textContent=f.name+' · '+(Number(f.size)/1048576).toFixed(1)+' MB';li.appendChild(a);el.appendChild(li)}}
        async function uploadAll(){const list=[...document.getElementById('files').files];const status=document.getElementById('status'),bar=document.getElementById('progress');for(const file of list){const key='transfer-hub:'+file.name+':'+file.size+':'+file.lastModified;let id=localStorage.getItem(key);let start=await fetch(api('/api/start'),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id,name:file.name,size:file.size})});if(!start.ok){status.textContent='Could not start '+file.name;return}let state=await start.json();id=state.id;localStorage.setItem(key,id);let offset=state.offset;status.textContent='Sending '+file.name;bar.value=file.size?offset/file.size*100:0;while(offset<file.size){const end=Math.min(offset+1048576,file.size);let response;for(let attempt=0;attempt<3;attempt++){try{response=await fetch(api('/api/chunk?id='+encodeURIComponent(id)+'&offset='+offset),{method:'PUT',body:file.slice(offset,end)});if(response.ok)break}catch(e){}await new Promise(r=>setTimeout(r,500*(attempt+1)))}if(!response||!response.ok){status.textContent='Paused at '+Math.round(offset/file.size*100)+'%. Re-select the same file to resume.';return}offset=(await response.json()).offset;bar.value=file.size?offset/file.size*100:100}let done=await fetch(api('/api/finish?id='+encodeURIComponent(id)),{method:'POST'});if(!done.ok){status.textContent='Could not finish '+file.name;return}localStorage.removeItem(key)}status.textContent='All selected files arrived on your Mac.';bar.value=100;document.getElementById('files').value='';}
        refreshOutbox();
        </script>
        """
    }
}
