// SPDX-License-Identifier: GPL-3.0-only
// Verified profile: iPhone18,1 / 24C5037i. Offsets are relative to decoded CacheData.
import Foundation

enum FaceTimeAudioChoice: Int, CaseIterable, Identifiable {
    case keep, enable, restoreOriginal
    var id: Int { rawValue }
    var title: LocalizedStringResource {
        switch self {
        case .keep: "Keep Current"
        case .enable: "Enable"
        case .restoreOriginal: "Disable (Restore Original)"
        }
    }
}

struct FaceTimeAudioFlags: Equatable, Codable, Sendable {
    let greenTea: Bool
    let notGreenTea: Bool

    static let enabled = Self(greenTea: false, notGreenTea: true)
    static let restricted = Self(greenTea: true, notGreenTea: false)
}

// Bind saved values to their verified layout; never reuse offsets across builds.
struct FaceTimeAudioOriginal: Codable, Equatable, Sendable {
    let productType: String
    let build: String
    let layoutUUID: String
    let flags: FaceTimeAudioFlags

    init(document: GestaltDocument) throws {
        flags = try FaceTimeAudioCache.flags(in: document)
        // flags(in:) has validated these exact profile identifiers.
        productType = FaceTimeAudioCache.productType
        build = FaceTimeAudioCache.build
        layoutUUID = FaceTimeAudioCache.layoutUUID
    }

    func flags(in document: GestaltDocument) throws -> FaceTimeAudioFlags {
        _ = try FaceTimeAudioCache.validatedData(in: document)
        guard document.extra[GestaltKeys.productType] as? String == productType,
              document.root["CacheVersion"] as? String == build,
              document.root["CacheUUID"] as? String == layoutUUID else {
            throw GestaltFailure("The FaceTime Audio cache layout or values do not match the verified profile.")
        }
        return flags
    }
}

struct CachedBooleanChange: Identifiable {
    let name: String
    let offset: Int
    let before: Bool
    let after: Bool
    var id: Int { offset }
}

enum FaceTimeAudioCache {
    static let productType = "iPhone18,1"
    static let build = "24C5037i"
    static let layoutUUID = "7F1DF278-18B7-4E5A-8425-09E8830DE9AF"
    static let greenTeaOffset = 0xBF8
    static let notGreenTeaOffset = 0xFD0
    static let greenTeaKey = "iyfxmLogGVIaH7aEgqwcIA"
    static let notGreenTeaKey = "4snMZS8LJkSctKypt2m+xA"

    static func validatedData(in document: GestaltDocument) throws -> Data {
        guard document.extra[GestaltKeys.productType] as? String == productType,
              document.root["CacheVersion"] as? String == build else {
            throw GestaltFailure("FaceTime Audio supports iPhone 17 Pro on iOS 27.3 (24C5037i).")
        }
        guard document.root["CacheUUID"] as? String == layoutUUID,
              let data = document.root["CacheData"] as? Data, data.count == 6480,
              data[0x17FF] == 1, data[0x187A] == 1,
              [greenTeaOffset, notGreenTeaOffset].allSatisfy({ offset in
                  data[offset] <= 1 && data[(offset + 1)..<(offset + 8)].allSatisfy { $0 == 0 }
              }),
              [greenTeaKey, notGreenTeaKey, "green-tea", "not-green-tea"].allSatisfy({ document.extra[$0] == nil }) else {
            throw GestaltFailure("The FaceTime Audio cache layout or values do not match the verified profile.")
        }
        return data
    }

    static func flags(in document: GestaltDocument) throws -> FaceTimeAudioFlags {
        let data = try validatedData(in: document)
        return FaceTimeAudioFlags(greenTea: data[greenTeaOffset] == 1,
                                  notGreenTea: data[notGreenTeaOffset] == 1)
    }

    static func changes(from original: GestaltDocument, to edited: GestaltDocument) -> [CachedBooleanChange] {
        guard let before = original.root["CacheData"] as? Data,
              let after = edited.root["CacheData"] as? Data,
              before != after,
              (try? validatedData(in: original)) != nil,
              after.count == before.count else { return [] }
        return [("green-tea", greenTeaOffset), ("not-green-tea", notGreenTeaOffset)].compactMap { name, offset in
            guard before[offset] != after[offset] else { return nil }
            return CachedBooleanChange(name: name, offset: offset, before: before[offset] != 0, after: after[offset] != 0)
        }
    }

    static func validateEdit(from original: GestaltDocument, to edited: GestaltDocument) throws {
        guard original.root["CacheData"] as? Data != edited.root["CacheData"] as? Data else { return }
        let before = try validatedData(in: original)
        let after = try validatedData(in: edited)
        guard before.indices.allSatisfy({ index in
            index == greenTeaOffset || index == notGreenTeaOffset || before[index] == after[index]
        }) else {
            throw GestaltFailure("The FaceTime Audio edit changes unrelated cache bytes.")
        }
    }
}
