#if os(macOS)
import Foundation
import BubblesCore

struct ProfileSummary: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
}

final class ProfileRepository {
    private let fm = FileManager.default
    let rootURL: URL
    let profilesURL: URL
    let backupsURL: URL
    let registryURL: URL

    init() {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootURL = appSupport.appendingPathComponent("Bubbles Autoclicker", isDirectory: true)
        profilesURL = rootURL.appendingPathComponent("Profiles", isDirectory: true)
        backupsURL = rootURL.appendingPathComponent("Backups", isDirectory: true)
        registryURL = rootURL.appendingPathComponent("profiles.json")
        try? fm.createDirectory(at: profilesURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: backupsURL, withIntermediateDirectories: true)
    }

    func profileURL(_ id: UUID) -> URL {
        profilesURL.appendingPathComponent("\(id.uuidString).json")
    }

    func loadRegistry() -> (profiles: [ProfileSummary], active: UUID?) {
        struct Registry: Codable { var profiles: [ProfileSummary]; var active: UUID? }
        guard let data = try? Data(contentsOf: registryURL),
              let reg = try? JSONDecoder().decode(Registry.self, from: data) else { return ([], nil) }
        return (reg.profiles, reg.active)
    }

    func saveRegistry(profiles: [ProfileSummary], active: UUID?) throws {
        struct Registry: Codable { var profiles: [ProfileSummary]; var active: UUID? }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Registry(profiles: profiles, active: active))
        try transactionalWrite(data, to: registryURL)
    }

    func loadProfile(_ id: UUID) -> ProfileConfig? {
        let url = profileURL(id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ProfileConfig.self, from: data)
    }

    func saveProfile(_ profile: ProfileConfig, makeBackup: Bool = true) throws {
        let url = profileURL(profile.id)
        if makeBackup, fm.fileExists(atPath: url.path) {
            try? backup(profileID: profile.id, source: url)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        try transactionalWrite(data, to: url)
        pruneBackups(profileID: profile.id, keep: 10)
    }

    func deleteProfile(_ id: UUID) throws {
        let url = profileURL(id)
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
    }

    func exportProfile(_ profile: ProfileConfig, to destination: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: destination, options: .atomic)
    }

    func importProfile(from source: URL, nameOverride: String? = nil) throws -> ProfileConfig {
        let data = try Data(contentsOf: source)
        var profile = try JSONDecoder().decode(ProfileConfig.self, from: data)
        profile.id = UUID()
        if let nameOverride, !nameOverride.trimmingCharacters(in: .whitespaces).isEmpty {
            profile.name = nameOverride
        } else {
            profile.name += " Imported"
        }
        profile.chromeWindow = nil
        try saveProfile(profile, makeBackup: false)
        return profile
    }

    func listBackups(profileID: UUID) -> [URL] {
        let prefix = profileID.uuidString + "_"
        let urls = (try? fm.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
    }

    func restoreBackup(_ url: URL) throws -> ProfileConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ProfileConfig.self, from: data)
    }

    private func backup(profileID: UUID, source: URL) throws {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        let dest = backupsURL.appendingPathComponent("\(profileID.uuidString)_\(formatter.string(from: Date())).json")
        try fm.copyItem(at: source, to: dest)
    }

    private func pruneBackups(profileID: UUID, keep: Int) {
        let urls = listBackups(profileID: profileID)
        for url in urls.dropFirst(keep) { try? fm.removeItem(at: url) }
    }

    private func transactionalWrite(_ data: Data, to url: URL) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: temp, options: .atomic)
        // Validate JSON before replacing a known-good file.
        _ = try JSONSerialization.jsonObject(with: data)
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        try fm.moveItem(at: temp, to: url)
    }
}
#endif
