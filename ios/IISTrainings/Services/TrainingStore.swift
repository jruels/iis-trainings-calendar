import Foundation
import Observation

/// Owns the class list: cached on disk, refreshed from monday.
@MainActor
@Observable
final class TrainingStore {
    private(set) var trainings: [Training] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var lastUpdated: Date?
    private(set) var isSampleData = false

    /// Bumped on every successful refresh so views can replay their
    /// chalk-drawing animation.
    private(set) var revision = 0

    var hasToken: Bool { KeychainStore.readToken() != nil }

    init() {
        if let cached = Self.loadCache() {
            trainings = cached.trainings
            lastUpdated = cached.savedAt
        } else {
            trainings = SampleData.make()
            isSampleData = true
        }
    }

    /// All instructor names on the calendar, alphabetical, real people only.
    var instructors: [InstructorInfo] {
        var seen: [String: InstructorInfo] = [:]
        for t in trainings where t.hasRealInstructor && seen[t.instructor] == nil {
            seen[t.instructor] = InstructorInfo(name: t.instructor, hex: t.instructorHex)
        }
        return seen.values.sorted { $0.name < $1.name }
    }

    func refreshIfStale(maxAge: TimeInterval = 300) async {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < maxAge, !isSampleData { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        guard let token = KeychainStore.readToken() else {
            lastError = nil
            if trainings.isEmpty || isSampleData {
                trainings = SampleData.make()
                isSampleData = true
            }
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            // Always pull every board; the Completed toggle filters locally.
            let fresh = try await MondayClient(token: token).fetchAll()
            trainings = fresh
            isSampleData = false
            lastUpdated = Date()
            lastError = nil
            revision += 1
            Self.saveCache(CacheFile(savedAt: Date(), trainings: fresh))
        } catch is CancellationError {
            // View went away mid-refresh; keep what we have.
        } catch let error as URLError where error.code == .cancelled {
            // Same as above.
        } catch {
            lastError = error.localizedDescription
        }
    }

    func useSampleData() {
        trainings = SampleData.make()
        isSampleData = true
        lastUpdated = nil
        revision += 1
        Self.clearCache()
    }

    // MARK: Disk cache

    private struct CacheFile: Codable {
        let savedAt: Date
        let trainings: [Training]
    }

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("trainings-cache.json")
    }

    private static func loadCache() -> CacheFile? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(CacheFile.self, from: data)
    }

    private static func saveCache(_ file: CacheFile) {
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL)
    }
}

struct InstructorInfo: Identifiable, Hashable {
    let name: String
    let hex: String?
    var id: String { name }
}

/// UserDefaults keys shared by @AppStorage and the store.
enum Prefs {
    static let myName = "myName"
    static let showWeekends = "showWeekends"
    static let hideCancelled = "hideCancelled"
    static let includeCompleted = "includeCompleted"
    static let instructorFilter = "instructorFilter"
    static let mode = "calendarMode"

    static let mineToken = "__mine__"
}

/// What the person has chosen to see.
struct TrainingFilter: Equatable {
    var instructor: String = ""      // "" = everyone, Prefs.mineToken = me
    var myName: String = "Jason Smith"
    var hideCancelled: Bool = true
    var includeCompleted: Bool = true
    var search: String = ""

    var isActive: Bool { !instructor.isEmpty || !search.isEmpty }

    func apply(_ all: [Training]) -> [Training] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        let who: String? = {
            if instructor.isEmpty { return nil }
            return instructor == Prefs.mineToken ? myName : instructor
        }()
        return all.filter { t in
            if hideCancelled, t.isCancelled || t.isPendingReschedule { return false }
            if !includeCompleted, t.source == .completed { return false }
            if let who, t.instructor.caseInsensitiveCompare(who) != .orderedSame { return false }
            if !needle.isEmpty {
                let hay = [t.name, t.segment ?? "", t.instructor, t.customer, t.client, t.opportunity, t.location]
                    .joined(separator: " ").lowercased()
                if !hay.contains(needle) { return false }
            }
            return true
        }
    }
}
