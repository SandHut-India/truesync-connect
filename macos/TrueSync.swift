import SwiftUI
import AppKit
import Foundation
import Security
import PDFKit

struct Pair: Codable { let id: String; let secret: String; let code: String; let expiresAt: Double }
struct PrintOptions: Codable { let copies: Int; let color: Bool; let duplex: Bool; let width: Double; let height: Double; let orientation: String; let fit: Bool; let margin: Double; let dpi: Int; let tray: String }
struct Command: Codable { let id: String; let jobId: String; let printer: String; let options: PrintOptions }
struct Poll: Codable { let paired: Bool; let command: Command? }
struct Receipt: Codable { let id: String; let result: String; let error: String }
struct FileResponse: Codable { let file: String }
struct APIError: Error { let status: Int }

enum Config {
    static let defaultApi = "https://truesync-2026.web.app/api/"
    static var apiBase: String {
        if let env = ProcessInfo.processInfo.environment["TRUESYNC_API_BASE"], !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return normalize(env)
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrueSyncConnector")
        let file = folder.appendingPathComponent("config.json")
        if let data = try? Data(contentsOf: file),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let configured = json["apiBase"] as? String,
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return normalize(configured)
        }
        return defaultApi
    }
    static var siteURL: URL {
        var trimmed = apiBase
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if trimmed.hasSuffix("/api") { trimmed = String(trimmed.dropLast(4)) }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return URL(string: trimmed + "/")!
    }
    static func normalize(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if !trimmed.hasSuffix("/api") { trimmed += "/api" }
        return trimmed + "/"
    }
}

// Only this application's credential is read, updated or removed.
enum Credential {
    static let service = "app.truesync.connector"
    static func query(_ account: String = "paired-computer") -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] }
    static func read() throws -> Pair? {
        var q = query(); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = value as? Data else { throw APIError(status: Int(status)) }
        return try JSONDecoder().decode(Pair.self, from: bytes)
    }
    static func save(_ pair: Pair) throws {
        let data = try JSONEncoder().encode(pair)
        let updated = SecItemUpdate(query() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecItemNotFound { var q = query(); q[kSecValueData as String] = data; guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw APIError(status: -1) } }
        else if updated != errSecSuccess { throw APIError(status: Int(updated)) }
    }
    static func remove() { SecItemDelete(query() as CFDictionary) }
}

enum Printing {
    static func printers() -> [String] {
        var destinations: UnsafeMutablePointer<cups_dest_t>?; let count = cupsGetDests(&destinations)
        defer { cupsFreeDests(count, destinations) }
        guard count > 0, let destinations else { return [] }
        return (0..<Int(count)).compactMap { i in guard let name = destinations[i].name else { return nil }; return String(cString: name) }
    }
    static func settings(_ o: PrintOptions) -> [String: String] {
        var values = ["copies": String(o.copies), "media": String(format: "Custom.%.2fx%.2fmm", locale: Locale(identifier: "en_US_POSIX"), o.width, o.height), "sides": o.duplex ? "two-sided-long-edge" : "one-sided", "print-color-mode": o.color ? "color" : "monochrome", "ColorModel": o.color ? "RGB" : "Gray", "fit-to-page": o.fit ? "true" : "false", "Resolution": "\(o.dpi)dpi", "Collate": "True"]
        let standardSizes: [(Double, Double, String)] = [(210,297,"iso_a4_210x297mm"),(297,420,"iso_a3_297x420mm"),(148,210,"iso_a5_148x210mm"),(215.9,279.4,"na_letter_8.5x11in"),(215.9,355.6,"na_legal_8.5x14in")]
        if let paper = standardSizes.first(where: { abs($0.0-o.width)<0.2 && abs($0.1-o.height)<0.2 }) { values["media"] = paper.2 }
        values["printer-resolution"] = "\(o.dpi)dpi"
        if o.orientation != "auto" { values["orientation-requested"] = o.orientation == "landscape" ? "4" : "3" }
        if !o.fit { values["scaling"] = "100" }
        for edge in ["top", "bottom", "left", "right"] { values["page-\(edge)"] = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), o.margin * 72 / 25.4) }
        if !o.tray.isEmpty { values["InputSlot"] = o.tray }
        return values
    }
    static func print(_ bytes: Data, command: Command, folder: URL) -> Receipt {
        let failed = { (message: String) in Receipt(id: command.id, result: "failed", error: message) }
        guard printers().contains(command.printer) else { return failed("Printer unavailable. Add it in macOS System Settings → Printers & Scanners.") }
        guard let pdf = PDFDocument(data: bytes), pdf.pageCount > 0 else { return failed("This PDF could not be opened.") }
        let file = folder.appendingPathComponent("document-\(command.id).pdf")
        defer { try? FileManager.default.removeItem(at: file) }
        do { try bytes.write(to: file, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        catch { return failed("The document could not be prepared on this Mac.") }
        var options: UnsafeMutablePointer<cups_option_t>?; var count: Int32 = 0
        for (key, value) in settings(command.options) { count = cupsAddOption(key, value, count, &options) }
        defer { cupsFreeOptions(count, options) }
        let jobID = cupsPrintFile(command.printer, file.path, "TrueSync-\(command.id)", count, options)
        guard jobID > 0 else { return failed("macOS could not send this print. Check the printer and its queue before retrying.") }
        // The system has copied the PDF into its spool. Remove our temporary copy now.
        try? FileManager.default.removeItem(at: file)
        var missing = 0
        for _ in 0..<120 {
            var jobs: UnsafeMutablePointer<cups_job_t>?; let jobCount = cupsGetJobs(&jobs, command.printer, 1, CUPS_WHICHJOBS_ALL)
            var state: ipp_jstate_t?
            if jobCount > 0, let jobs { for i in 0..<Int(jobCount) where jobs[i].id == jobID { state = jobs[i].state } }
            cupsFreeJobs(jobCount, jobs)
            if state == IPP_JSTATE_COMPLETED { return Receipt(id: command.id, result: "printed", error: "") }
            if state == IPP_JSTATE_ABORTED || state == IPP_JSTATE_CANCELED { return failed("macOS reported a stopped print. Check the output before retrying.") }
            if state == nil { missing += 1; if missing >= 5 { break } } else { missing = 0 }
            Thread.sleep(forTimeInterval: 1)
        }
        return Receipt(id: command.id, result: "unconfirmed", error: "Check the printed pages. macOS has not reported completion.")
    }
}

@MainActor final class Connector: ObservableObject {
    @Published var status = "Ready to connect your Mac."
    @Published var code = ""
    @Published var paired = false
    @Published var printerNames: [String] = []
    @Published var active = false
    @Published var printing = false
    var pair: Pair?
    var loop: Task<Void, Never>?
    var heartbeat: Task<Void, Never>?
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TrueSyncConnector")
    func request<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
        var req = URLRequest(url: URL(string: Config.apiBase + path)!)
        req.timeoutInterval = 110
        if let pair { req.setValue("Bearer \(pair.id).\(pair.secret)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw APIError(status: status) }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func prepare() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where file.lastPathComponent.hasPrefix("document-") && file.pathExtension == "pdf" { try FileManager.default.removeItem(at: file) }
    }
    func start() {
        guard !active else { return }; loop?.cancel(); heartbeat?.cancel(); active = true
        loop = Task { await run() }
        heartbeat = Task { while !Task.isCancelled { try? await Task.sleep(nanoseconds: 10_000_000_000); if printing && pair != nil { let _: Poll? = try? await request("connector/poll", body: ["ready": false, "printers": printerNames]) } } }
    }
    func run() async {
        do { try prepare(); pair = try Credential.read() } catch { status = "Could not open secure storage. Allow TrueSync access to its own Keychain item, then reopen the app."; active = false; return }
        while !Task.isCancelled {
            do {
                if pair == nil {
                    let created: Pair = try await request("connector/pair", body: ["name": Host.current().localizedName ?? "Shop Mac"])
                    try Credential.save(created); pair = created
                    for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where file.pathExtension == "json" { try FileManager.default.removeItem(at: file) }
                }
                code = pair!.code
                printerNames = await Task.detached { Printing.printers() }.value
                try await flush()
                let response: Poll = try await request("connector/poll", body: ["printers": printerNames])
                paired = response.paired
                status = paired ? "Connected · \(printerNames.count) printer(s) ready" : "Enter this code in TrueSync → Printers to pair this Mac."
                if let command = response.command { printing = true; status = "Printing on \(command.printer)…"; try await execute(command); printing = false }
            }             catch let e as APIError where e.status == 401 { pair = nil; paired = false; Credential.remove(); status = "Connection removed or code expired. Preparing a new code…" }
            catch let e as APIError { printing = false; status = "TrueSync error \(e.status). Retrying…" }
            catch { printing = false; status = "Waiting for internet or TrueSync. \(error.localizedDescription)" }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
        }
    }
    func execute(_ command: Command) async throws {
        guard UUID(uuidString: command.id) != nil else { throw APIError(status: 400) }
        let path = folder.appendingPathComponent(command.id + ".json")
        guard !FileManager.default.fileExists(atPath: path.path) else { return }
        var receipt = Receipt(id: command.id, result: "unconfirmed", error: "Printing was interrupted. Check the pages before retrying.")
        try JSONEncoder().encode(receipt).write(to: path, options: .atomic)
        do {
            let file: FileResponse = try await request("connector/file/" + command.id)
            guard let bytes = Data(base64Encoded: file.file) else { throw APIError(status: 400) }
            let folder = self.folder
            receipt = await Task.detached { Printing.print(bytes, command: command, folder: folder) }.value
        } catch { receipt = Receipt(id: command.id, result: "failed", error: "Could not prepare this print. Check the printer before retrying.") }
        try JSONEncoder().encode(receipt).write(to: path, options: .atomic)
        try await flush()
    }
    struct OK: Decodable { let ok: Bool }
    func flush() async throws {
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            let receipt: Receipt
            do { receipt = try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: file)) }
            catch {
                try? FileManager.default.moveItem(at: file, to: file.appendingPathExtension("orphan"))
                continue
            }
            do {
                let _: OK = try await request("connector/result", body: ["id": receipt.id, "result": receipt.result, "error": receipt.error])
                try FileManager.default.removeItem(at: file)
            } catch let e as APIError where [403, 404, 410].contains(e.status) {
                try FileManager.default.removeItem(at: file)
            } catch let e as APIError where e.status == 401 {
                throw e
            } catch {
                status = "Could not confirm a print result yet. Will retry. \(error.localizedDescription)"
                return
            }
        }
    }
    func disconnect() {
        loop?.cancel(); heartbeat?.cancel(); Credential.remove(); pair = nil; paired = false; active = false; code = ""; status = "Disconnected. Remove this Mac in TrueSync → Printers to revoke server access too."
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    var lock: Int32 = -1
    func applicationDidFinishLaunching(_ notification: Notification) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TrueSyncConnector")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        lock = Darwin.open(dir.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
        if lock < 0 || flock(lock, LOCK_EX | LOCK_NB) != 0 { NSApplication.shared.terminate(nil); return }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct TrueSyncApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) var delegate
    @StateObject var connector = Connector()
    init() {
        if CommandLine.arguments.contains("--self-test") {
            let options = PrintOptions(copies: 2, color: false, duplex: true, width: 210, height: 297, orientation: "portrait", fit: true, margin: 5, dpi: 300, tray: "")
            precondition(Printing.settings(options)["copies"] == "2")
            precondition(Printing.settings(options)["sides"] == "two-sided-long-edge")
            precondition(Printing.settings(options)["media"] == "iso_a4_210x297mm")
            print("PASS macOS print option mapping; printer enumeration: \(Printing.printers().count) installed. No job submitted.")
            exit(0)
        }
    }
    var body: some Scene {
        WindowGroup("TrueSync Connector", id: "connector") {
            VStack(alignment: .leading, spacing: 18) {
                HStack { Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 44, height: 44); Text("TrueSync.").font(.system(size: 28, weight: .bold)) }
                Text("Your Mac. Your printer. In sync.").font(.title2.bold())
                Text(connector.status).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !connector.paired && !connector.code.isEmpty { Text(connector.code).font(.system(size: 32, weight: .bold, design: .monospaced)).textSelection(.enabled); Text("This code expires in 10 minutes.").font(.caption).foregroundStyle(.secondary) }
                if connector.paired { Text(connector.printerNames.isEmpty ? "Add your printer in System Settings → Printers & Scanners." : connector.printerNames.joined(separator: "\n")).font(.callout) }
                HStack {
                    Button("Open TrueSync") { NSWorkspace.shared.open(Config.siteURL) }.buttonStyle(.borderedProminent)
                    if !connector.active { Button("Connect this Mac") { connector.start() }.buttonStyle(.bordered) }
                    else { Button("Disconnect") { connector.disconnect() }.disabled(connector.printing) }
                }
                Text("Keep this app open while your shop is open. Closing this window leaves it in the menu bar. No QZ Tray needed.").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }.padding(28).frame(width: 480, height: 380).background(Color(red: 0.97, green: 0.98, blue: 0.95)).tint(Color(red: 0.09, green: 0.31, blue: 0.26))
        }.windowResizability(.contentSize)
        MenuBarExtra("TrueSync", systemImage: "printer.fill") { ConnectorMenu(connector: connector) }
    }
}
struct ConnectorMenu: View {
    @ObservedObject var connector: Connector
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Text(connector.status)
        Button("Open connector") { openWindow(id: "connector"); NSApplication.shared.activate(ignoringOtherApps: true) }
        Button("Quit TrueSync Connector") { NSApplication.shared.terminate(nil) }
    }
}
