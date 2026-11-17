import Foundation

enum MondayError: LocalizedError {
    case missingToken
    case http(Int)
    case api(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingToken: "Add your monday API token in Settings."
        case .http(let code): code == 401 ? "monday rejected the API token (401)." : "monday returned HTTP \(code)."
        case .api(let message): "monday API: \(message)"
        case .decoding(let message): "Couldn't read monday's reply: \(message)"
        }
    }
}

/// Reads the three boards behind the monday "Calendar" dashboard and turns
/// every dated item into a `Training`.
struct MondayClient {
    let token: String

    static let endpoint = URL(string: "https://api.monday.com/v2")!
    static let apiVersion = "2025-04"

    /// Parent-level column ids, identical on all three boards.
    enum Col {
        static let instructor = "color_mm15thk1"
        static let status = "color_mm1bshmb"
        static let timeline = "timerange_mm1cf8pp"
        static let startTime = "hour_mm15ypeg"
        static let endTime = "hour_mm15xbd2"
        static let timezone = "dropdown_mm158c1g"
        static let opportunity = "text_mm2125xz"
        static let delivery = "color_mm21f51p"
        static let location = "location_mm2nbxj9"
        static let customer = "board_relation_mm212ywa"
        static let client = "board_relation_mm21sd50"
        static let clientContact = "board_relation_mm21g5yf"
        static let confirmed = "boolean_mm2dm4ap"
    }

    /// Subitem columns on the Bootcamps board (subitems board 18407475641).
    enum SubCol {
        static let instructor = "color_mm25xv4v"
        static let timeline = "timerange_mm2517h7"
        static let status = "status"
    }

    private static let columnFields = """
        id text value
        ... on StatusValue { label label_style { color } }
        ... on BoardRelationValue { display_value }
        ... on MirrorValue { display_value }
    """

    private static let parentQuery = """
    query ($boardId: ID!, $cursor: String) {
      boards(ids: [$boardId]) {
        items_page(limit: 100, cursor: $cursor) {
          cursor
          items { id name group { title } column_values { \(columnFields) } }
        }
      }
    }
    """

    private static let subitemQuery = """
    query ($boardId: ID!, $cursor: String) {
      boards(ids: [$boardId]) {
        items_page(limit: 40, cursor: $cursor) {
          cursor
          items {
            id name group { title }
            column_values { \(columnFields) }
            subitems { id name column_values { \(columnFields) } }
          }
        }
      }
    }
    """

    // MARK: Public

    func fetchAll(includeCompleted: Bool = true) async throws -> [Training] {
        guard !token.isEmpty else { throw MondayError.missingToken }
        let boards: [SourceBoard] = includeCompleted ? SourceBoard.allCases : [.trainings, .bootcamps]

        return try await withThrowingTaskGroup(of: [Training].self) { group in
            for board in boards {
                group.addTask { try await fetch(board) }
            }
            var all: [Training] = []
            var seen = Set<String>()
            for try await chunk in group {
                for t in chunk where seen.insert(t.id).inserted { all.append(t) }
            }
            return all.sorted { ($0.start, $0.displayTitle) < ($1.start, $1.displayTitle) }
        }
    }

    // MARK: Fetching

    private func fetch(_ board: SourceBoard) async throws -> [Training] {
        let withSubitems = board == .bootcamps
        var items: [APIItem] = []
        var cursor: String?
        repeat {
            let page = try await fetchPage(board: board.boardID, cursor: cursor, withSubitems: withSubitems)
            items += page.items
            cursor = page.cursor
        } while cursor != nil

        return items.flatMap { item in Self.trainings(from: item, board: board) }
    }

    private func fetchPage(board: String, cursor: String?, withSubitems: Bool) async throws -> APIItemsPage {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "API-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var variables: [String: Any] = ["boardId": board]
        variables["cursor"] = cursor ?? NSNull()
        let body: [String: Any] = [
            "query": withSubitems ? Self.subitemQuery : Self.parentQuery,
            "variables": variables,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MondayError.http(http.statusCode)
        }

        let envelope: APIEnvelope
        do {
            envelope = try JSONDecoder().decode(APIEnvelope.self, from: data)
        } catch {
            throw MondayError.decoding(error.localizedDescription)
        }
        if let message = envelope.errors?.first?.message ?? envelope.error_message {
            throw MondayError.api(message)
        }
        guard let page = envelope.data?.boards?.first?.items_page else {
            throw MondayError.api("Board \(board) returned no data. Check the token's access.")
        }
        return page
    }

    // MARK: Mapping

    static func trainings(from item: APIItem, board: SourceBoard) -> [Training] {
        let c = item.columns
        let base = Training(
            id: item.id,
            itemID: item.id,
            source: board,
            group: item.group?.title ?? "",
            name: item.name,
            segment: nil,
            instructor: c.label(Col.instructor),
            instructorHex: c.color(Col.instructor),
            status: c.label(Col.status),
            statusHex: c.color(Col.status),
            start: DayKey(year: 2000, month: 1, day: 1),
            end: DayKey(year: 2000, month: 1, day: 1),
            startTime: c.hour(Col.startTime),
            endTime: c.hour(Col.endTime),
            timeZoneLabel: c.text(Col.timezone),
            delivery: c.label(Col.delivery),
            deliveryHex: c.color(Col.delivery),
            location: c.text(Col.location),
            opportunity: c.text(Col.opportunity),
            customer: c.display(Col.customer),
            client: c.display(Col.client),
            clientContact: c.display(Col.clientContact),
            confirmed: c.checked(Col.confirmed)
        )

        // Bootcamp segments: each subitem is one instructor's block with its
        // own dates. Times, zone, customer etc. come from the parent course.
        var segments: [Training] = []
        for sub in item.subitems ?? [] {
            let sc = sub.columns
            guard let range = sc.timeline(SubCol.timeline) else { continue }
            var seg = base
            seg.id = "sub-\(sub.id)"
            seg.start = range.0
            seg.end = range.1
            let parts = sub.name.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            let weekPart = parts.first { $0.lowercased().hasPrefix("week") }
            let namePart = parts.first { !$0.lowercased().hasPrefix("week") && !$0.isEmpty }
            seg.segment = weekPart ?? sub.name
            let label = sc.label(SubCol.instructor)
            seg.instructor = label.isEmpty ? (namePart ?? "Unassigned") : label
            seg.instructorHex = label.isEmpty ? nil : sc.color(SubCol.instructor)
            let segStatus = sc.label(SubCol.status)
            if !segStatus.isEmpty, !base.isCancelled { seg.status = segStatus; seg.statusHex = sc.color(SubCol.status) }
            segments.append(seg)
        }
        if !segments.isEmpty { return segments }

        guard let range = c.timeline(Col.timeline) else { return [] }
        var t = base
        t.start = range.0
        t.end = range.1
        return [t]
    }
}

// MARK: - Wire format

struct APIEnvelope: Decodable {
    let data: APIData?
    let errors: [APIErrorMessage]?
    let error_message: String?
}

struct APIErrorMessage: Decodable { let message: String }
struct APIData: Decodable { let boards: [APIBoard]? }
struct APIBoard: Decodable { let items_page: APIItemsPage }
struct APIItemsPage: Decodable {
    let cursor: String?
    let items: [APIItem]
}
struct APIGroup: Decodable { let title: String }

struct APIItem: Decodable {
    let id: String
    let name: String
    let group: APIGroup?
    let column_values: [APIColumnValue]
    let subitems: [APIItem]?

    var columns: ColumnBag { ColumnBag(values: column_values) }
}

struct APIColumnValue: Decodable {
    struct LabelStyle: Decodable { let color: String? }
    let id: String
    let text: String?
    let value: String?
    let label: String?
    let label_style: LabelStyle?
    let display_value: String?
}

/// Typed accessors over an item's column values.
struct ColumnBag {
    private let byID: [String: APIColumnValue]

    init(values: [APIColumnValue]) {
        byID = Dictionary(values.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func text(_ id: String) -> String {
        (byID[id]?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func label(_ id: String) -> String {
        (byID[id]?.label ?? byID[id]?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func color(_ id: String) -> String? { byID[id]?.label_style?.color }

    func display(_ id: String) -> String {
        (byID[id]?.display_value ?? byID[id]?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func json(_ id: String) -> [String: Any]? {
        guard let raw = byID[id]?.value, let data = raw.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    func timeline(_ id: String) -> (DayKey, DayKey)? {
        guard let j = json(id), let from = (j["from"] as? String).flatMap(DayKey.init(iso:)) else { return nil }
        let to = (j["to"] as? String).flatMap(DayKey.init(iso:)) ?? from
        return from <= to ? (from, to) : (to, from)
    }

    func hour(_ id: String) -> ClockTime? {
        guard let j = json(id), let h = (j["hour"] as? NSNumber)?.intValue else { return nil }
        return ClockTime(hour: h, minute: (j["minute"] as? NSNumber)?.intValue ?? 0)
    }

    func checked(_ id: String) -> Bool {
        guard let j = json(id) else { return false }
        if let s = j["checked"] as? String { return s == "true" }
        return (j["checked"] as? Bool) ?? false
    }
}
