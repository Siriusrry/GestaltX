// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 huamidev
import Foundation
import SwiftUI
import Combine

@MainActor
final class GestaltManager: ObservableObject {
    @Published private(set) var snapshot: DocumentSnapshot?
    @Published private(set) var working: GestaltDocument?
    @Published private(set) var isBusy = false
    @Published private(set) var status = "Connect to your device or open a plist."
    @Published private(set) var deviceAccessible = false
    @Published private(set) var backups: [BackupRecord] = []
    @Published private(set) var logs: [String] = []
    @Published var message: String?
    @Published var isRespringing = false
    @Published var needsRespring = false
    @Published var choices: [String: PresetChoice] = [:]
    @Published var regionID = "keep"
    @Published var regionCodeID = "keep"
    @Published var changesName = false
    @Published var modelName = ""
    @Published var subtype = 0
    @Published private(set) var faceTimeAudioChoice: FaceTimeAudioChoice = .keep
    private let files: GestaltFileStore
    private var exploitLogObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        let deviceID = defaults.string(forKey: "GestaltX.installationID") ?? UUID().uuidString
        defaults.set(deviceID, forKey: "GestaltX.installationID")
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GestaltX/Backups", isDirectory: true)
        files = GestaltFileStore(deviceURL: URL(fileURLWithPath: GestaltKeys.devicePath), backupDirectory: directory,
                                deviceID: deviceID, acquire: {
            #if targetEnvironment(simulator)
            throw GestaltFailure("Device access is unavailable in the Simulator. Open a plist to explore GestaltX.")
            #else
            guard let signedGroup = GXEntitlementsReader.usableAppGroup() else {
                throw GestaltFailure("The signed app has no usable App Group. Enable its App Group capability and sign it again.")
            }
            let handle = worse_query((GestaltKeys.devicePath as NSString).deletingLastPathComponent,
                                     signedGroup, false, false)
            guard handle >= 0 else {
                if handle == -1 { throw GestaltFailure("The signed app has no usable App Group. Enable its App Group capability and sign it again.") }
                throw GestaltFailure("MobileGestalt access was denied. Check the OS version and App Group signing.")
            }
            return handle
            #endif
        }, release: { worse_query_release($0) }, eventSink: { text in
            NotificationCenter.default.post(name: Notification.Name("GestaltX.worse_query.log"), object: nil,
                                            userInfo: ["message": text])
        })
        exploitLogObserver = NotificationCenter.default.addObserver(forName: Notification.Name("GestaltX.worse_query.log"), object: nil, queue: nil) { [weak self] notification in
            guard let text = notification.userInfo?["message"] as? String else { return }
            DispatchQueue.main.async { [weak self] in self?.log("[worse_query] " + text) }
        }
    }

    deinit { if let exploitLogObserver { NotificationCenter.default.removeObserver(exploitLogObserver) } }

    var changeKeys: [String] {
        guard let before = snapshot?.document.extra, let after = preview?.extra else { return [] }
        return Set(before.keys).union(after.keys).filter { key in
            switch (before[key], after[key]) {
            case (nil, nil): return false
            case (nil, _), (_, nil): return true
            case (let a?, let b?): return !GestaltDocument.valuesEqual(a, b)
            }
        }.sorted()
    }
    var cacheDataChanges: [CachedBooleanChange] {
        guard let original = snapshot?.document, let edited = preview else { return [] }
        return FaceTimeAudioCache.changes(from: original, to: edited)
    }
    var changeCount: Int { changeKeys.count + cacheDataChanges.count }
    var hasDocument: Bool { snapshot != nil }
    var sourceIsDevice: Bool { snapshot?.source == .device }
    var displayedName: String {
        working?.artwork["ArtworkDeviceProductDescription"] as? String ?? working?.extra["Z/dqyWS6OZTRy10UcmUAhw"] as? String ?? UIDevice.current.model
    }
    var preview: GestaltDocument? {
        guard var doc = working, let snapshot else { return nil }
        for capability in Capability.all {
            capability.apply(choices[capability.id] ?? .keep, to: &doc, restoringFrom: snapshot)
        }
        if subtype != 0 {
            doc.setArtwork(NSNumber(value: subtype), for: "ArtworkDeviceSubType")
            doc.set(NSNumber(value: true), for: "YlEtTtHlNesRBMal1CqRaA")
        }
        if changesName {
            doc.setArtwork(modelName.trimmingCharacters(in: .whitespacesAndNewlines), for: "ArtworkDeviceProductDescription")
            doc.set(modelName.trimmingCharacters(in: .whitespacesAndNewlines), for: "Z/dqyWS6OZTRy10UcmUAhw")
            doc.set(modelName.trimmingCharacters(in: .whitespacesAndNewlines), for: "bbtR9jQx50Fv5Af/affNtA")
        }
        doc.applyRegion(salesRegion: RegionPreset.all.first { $0.id == regionID },
                        regionCode: RegionPreset.all.first { $0.id == regionCodeID })
        return doc
    }

    private func log(_ text: String) {
        let time = Date.now.formatted(date: .omitted, time: .standard)
        logs.append("[\(time)] \(text)")
        if logs.count > 1000 { logs.removeFirst(logs.count - 1000) }
    }
    private func failed(_ error: Error) { message = error.localizedDescription; log(error.localizedDescription) }
    private func accept(_ loaded: DocumentSnapshot) {
        snapshot = loaded; working = loaded.document
        choices = [:]; regionID = "keep"; regionCodeID = "keep"; changesName = false; subtype = 0
        faceTimeAudioChoice = .keep
        modelName = loaded.document.artwork["ArtworkDeviceProductDescription"] as? String ?? ""
    }
    func clearStaged() {
        if let snapshot { accept(snapshot) }
    }

    func stageFaceTimeAudio(_ choice: FaceTimeAudioChoice) {
        guard !isBusy, var document = working, let snapshot else { return }
        do {
            let flags: FaceTimeAudioFlags
            switch choice {
            case .keep: flags = try FaceTimeAudioCache.flags(in: snapshot.document)
            case .enable: flags = .enabled
            case .restoreOriginal: flags = try snapshot.originalFaceTimeAudioFlags()
            }
            try document.setFaceTimeAudio(flags)
            working = document
            faceTimeAudioChoice = choice
        } catch { failed(error) }
    }

    var canRestoreFaceTimeAudio: Bool {
        guard !isBusy, let snapshot, let working,
              let original = try? snapshot.originalFaceTimeAudioFlags(),
              let current = try? FaceTimeAudioCache.flags(in: working) else { return false }
        return faceTimeAudioChoice != .keep || current != original
    }

    func restoreFaceTimeAudio() async {
        guard !isBusy, let before = snapshot, let pending = working else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            var restored = before.document
            try restored.setFaceTimeAudio(before.originalFaceTimeAudioFlags())
            let result: DocumentSnapshot
            if restored.matches(before.document) {
                result = before
            } else {
                logChanges(from: before.document, to: restored, prefix: "[restore-facetime] ")
                result = try await files.commit(restored, expected: before)
                needsRespring = result.source == .device
                message = L(result.source == .device
                            ? "FaceTime Audio flags written and verified. Restart the iPhone, then test an audio call."
                            : "Local changes saved. Export the plist to keep a copy.")
            }
            snapshot = result
            working = before.rebasingPendingEdits(pending, onto: result.document, excluding: [], preservingCacheData: false)
            faceTimeAudioChoice = .keep
            log("[restore-facetime] " + L("Original values restored."))
            await reloadBackups()
        } catch { failed(error); await reloadBackups() }
    }

    func canRestore(_ capability: Capability) -> Bool {
        guard !isBusy, let snapshot, let working else { return false }
        if (choices[capability.id] ?? .keep) != .keep { return true }
        if capability.id == "dynamicIsland" && subtype != 0 { return true }
        return capability.keys.contains { key in
            switch (snapshot.originalValue(for: key), working.extra[key]) {
            case (nil, nil): false
            case (let a?, let b?): !GestaltDocument.valuesEqual(a, b)
            default: true
            }
        }
    }

    func restoreCapability(_ capability: Capability) async {
        guard !isBusy, let before = snapshot, let pending = working else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            var restored = before.document
            let removesAdded = choices[capability.id] == .removeAdded
            let absentKeys = removesAdded ? Set(capability.keys) : Set<String>()
            capability.apply(removesAdded ? .removeAdded : .disable, to: &restored, restoringFrom: before)
            let result: DocumentSnapshot
            if restored.matches(before.document) && absentKeys.isEmpty {
                result = before
            } else {
                for line in diffLines(before.document.extra, restored.extra) { log("[restore-field] " + line) }
                result = try await files.commit(restored, expected: before, originallyAbsentKeys: absentKeys)
                needsRespring = result.source == .device
                message = L(result.source == .device ? "Original values restored." : "Local changes saved. Export the plist to keep a copy.")
            }
            snapshot = result
            working = before.rebasingPendingEdits(pending, onto: result.document, excluding: Set(capability.keys))
            choices[capability.id] = .keep
            if capability.id == "dynamicIsland" { subtype = 0 }
            log("[restore-field] " + L(capability.title) + ": " + L("Original values restored."))
            await reloadBackups()
        } catch { failed(error); await reloadBackups() }
    }
    func clearLog() { logs = [] }

    // MARK: - Exploit-process logging

    private func describe(_ value: Any?) -> String {
        guard let value else { return "∅" }
        if let data = value as? Data { return "\(data.count) bytes" }
        let text = PlistValueKind.detect(value).text(for: value)
        return text.count > 80 ? String(text.prefix(80)) + "…" : text
    }

    private func diffLines(_ before: [String: Any], _ after: [String: Any], prefix: String = "") -> [String] {
        var lines: [String] = []
        for key in Set(before.keys).union(after.keys).sorted() {
            let path = prefix.isEmpty ? key : prefix + "." + key
            switch (before[key], after[key]) {
            case (nil, let value?): lines.append("+ \(path) = \(describe(value))")
            case (let value?, nil): lines.append("- \(path)  (was \(describe(value)))")
            case (let oldValue?, let newValue?):
                guard !GestaltDocument.valuesEqual(oldValue, newValue) else { continue }
                if let oldDict = oldValue as? [String: Any], let newDict = newValue as? [String: Any] {
                    lines.append(contentsOf: diffLines(oldDict, newDict, prefix: path))
                } else {
                    lines.append("~ \(path): \(describe(oldValue)) → \(describe(newValue))")
                }
            default: break
            }
        }
        return lines
    }

    private func summarize(_ document: GestaltDocument) -> [String] {
        var lines = ["CacheExtra: \(document.extra.count) keys"]
        if let cacheData = document.root["CacheData"] as? Data { lines.append("CacheData: \(cacheData.count) bytes") }
        if let model = document.artwork["ArtworkDeviceProductDescription"] as? String { lines.append("model name: \(model)") }
        if let subtype = document.artwork["ArtworkDeviceSubType"] { lines.append("subtype: \(describe(subtype))") }
        if let region = document.extra[GestaltKeys.regionCode] as? String { lines.append("region code: \(region)") }
        for key in [GestaltKeys.regionInfo, GestaltKeys.legacyRegionInfo] {
            if let info = document.extra[key] as? String { lines.append("region info: \(info)") }
        }
        if let product = document.extra[GestaltKeys.productType] as? String { lines.append("product type: \(product)") }
        return lines
    }

    private func logChanges(from original: GestaltDocument, to edited: GestaltDocument, prefix: String) {
        for line in diffLines(original.root, edited.root) { log(prefix + line) }
        for change in FaceTimeAudioCache.changes(from: original, to: edited) {
            log(prefix + "CacheData.\(change.name) @\(String(format: "0x%X", change.offset)): \(change.before) → \(change.after)")
        }
    }

    func connect(showErrorAlert: Bool = true) async {
        guard !isBusy else { return }
        isBusy = true; status = "Checking device access…"
        log("[read] Starting MobileGestalt access")
        defer { isBusy = false }
        do {
            let result = try await files.loadDevice()
            accept(result); deviceAccessible = true; status = "Device connected"
            log("[read] plist: \(result.data.count) bytes")
            for line in summarize(result.document) { log("[read] " + line) }
            log(L("Device connected"))
        } catch {
            deviceAccessible = false; status = "Device access unavailable"
            if showErrorAlert { failed(error) } else { log(error.localizedDescription) }
        }
        await reloadBackups()
    }

    func open(_ url: URL) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 16 * 1024 * 1024 else { throw GestaltFailure("Choose a plist smaller than 16 MB.") }
            let result = try await files.loadLocal(data: Data(contentsOf: url), name: url.lastPathComponent)
            accept(result); status = "Local file opened"; needsRespring = false
            log("[open] \(url.lastPathComponent): \(result.data.count) bytes")
            for line in summarize(result.document) { log("[open] " + line) }
            log(L("Local file opened") + ": " + url.lastPathComponent)
        } catch { failed(error) }
    }

    func stage(_ draft: FieldDraft) throws {
        let key = draft.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw GestaltFailure("Enter a field key.") }
        guard var doc = working else { throw GestaltFailure("Load a document first.") }
        if draft.originalKey != key && doc.extra[key] != nil { throw GestaltFailure("That key already exists. Edit the existing field instead.") }
        let value = try draft.kind.parse(draft.text)
        if let originalKey = draft.originalKey, originalKey != key { doc.set(nil, for: originalKey) }
        doc.set(value, for: key); working = doc
        // Explicit field edits take precedence: discard presets that would overwrite the key.
        for capability in Capability.all where capability.keys.contains(key) { choices[capability.id] = .keep }
        if [GestaltKeys.regionCode, GestaltKeys.regionInfo, GestaltKeys.legacyRegionInfo].contains(key) { regionID = "keep"; regionCodeID = "keep" }
        if key == GestaltKeys.artwork { subtype = 0 }
        if [GestaltKeys.artwork, "Z/dqyWS6OZTRy10UcmUAhw", "bbtR9jQx50Fv5Af/affNtA"].contains(key) { changesName = false }
    }
    func removeField(_ key: String) {
        working?.set(nil, for: key)
        for capability in Capability.all where capability.keys.contains(key) { choices[capability.id] = .keep }
        if [GestaltKeys.regionCode, GestaltKeys.regionInfo, GestaltKeys.legacyRegionInfo].contains(key) { regionID = "keep"; regionCodeID = "keep" }
        if key == GestaltKeys.artwork { subtype = 0 }
        if [GestaltKeys.artwork, "Z/dqyWS6OZTRy10UcmUAhw", "bbtR9jQx50Fv5Af/affNtA"].contains(key) { changesName = false }
    }

    func apply() async {
        guard !isBusy, let snapshot, let edited = preview, changeCount > 0 else { return }
        if changesName && modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { failed(GestaltFailure("Enter a model name before applying.")); return }
        isBusy = true
        defer { isBusy = false }
        do {
            log("[apply] source=\(snapshot.source.rawValue) fields=\(changeCount)")
            logChanges(from: snapshot.document, to: edited, prefix: "[diff] ")
            let absentKeys = Set(Capability.all.filter { choices[$0.id] == .removeAdded }.flatMap(\.keys))
            let result = try await files.commit(edited, expected: snapshot, originallyAbsentKeys: absentKeys)
            accept(result); needsRespring = result.source == .device
            status = result.source == .device ? "Changes verified on device" : "Local changes saved"
            let changedFaceTimeAudio = !FaceTimeAudioCache.changes(from: snapshot.document, to: edited).isEmpty
            message = L(result.source == .device
                        ? (changedFaceTimeAudio ? "FaceTime Audio flags written and verified. Restart the iPhone, then test an audio call." : "Write verified. Some features require a device restart.")
                        : "Local changes saved. Export the plist to keep a copy.")
            log(L(status)); await reloadBackups()
        } catch { failed(error); await reloadBackups() }
    }

    func backup() async {
        guard !isBusy, let snapshot else { return }
        isBusy = true; defer { isBusy = false }
        do { try await files.backup(snapshot); log(L("Backup saved")); message = L("Backup saved"); await reloadBackups() }
        catch { failed(error) }
    }
    func reloadBackups() async {
        do { backups = try await files.backups() } catch { failed(error) }
    }
    func restore(_ record: BackupRecord) async {
        guard !isBusy, let snapshot else { return }
        isBusy = true; defer { isBusy = false }
        do {
            let data = try await files.backupData(record)
            let restored = try GestaltDocument(data: data)
            log("[restore] \(record.filename) · \(record.byteCount) bytes · reason=\(record.reason)")
            logChanges(from: snapshot.document, to: restored, prefix: "[restore-diff] ")
            let result = try await files.commit(restored, expected: snapshot, restoring: record)
            accept(result); needsRespring = result.source == .device
            message = L(result.source == .device ? "Backup restored and verified." : "Backup opened as a local document.")
            log(message ?? ""); await reloadBackups()
        } catch { failed(error); await reloadBackups() }
    }
    func openBackup(_ record: BackupRecord) async {
        guard !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        do {
            let data = try await files.backupData(record)
            accept(try await files.loadLocal(data: data, name: record.filename)); status = "Local file opened"
        } catch { failed(error) }
    }
    func deleteBackup(_ record: BackupRecord) async {
        guard !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        do { try await files.deleteBackup(record); await reloadBackups() } catch { failed(error) }
    }
    func exportBackup(_ record: BackupRecord) async -> URL? {
        do { return try exportData(await files.backupData(record), name: record.filename) }
        catch { failed(error); return nil }
    }
    func exportDocument() -> URL? {
        guard let doc = preview else { return nil }
        do { return try exportData(doc.encoded(), name: "MobileGestalt-GestaltX.plist") }
        catch { failed(error); return nil }
    }
    private func exportData(_ data: Data, name: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name); try data.write(to: url, options: .atomic)
        return url
    }
}
