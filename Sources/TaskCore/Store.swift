import Foundation
import Darwin

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case todo, running, waiting, done
    public var label: String { switch self { case .todo: "待开始"; case .running: "进行中"; case .waiting: "等我处理"; case .done: "已完成" } }
    public var icon: String { switch self { case .todo: "circle"; case .running: "circle.lefthalf.filled"; case .waiting: "hand.raised.fill"; case .done: "checkmark.circle.fill" } }
}
public struct AgentSession: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID().uuidString
    public var tool = "Claude Code"
    public var name = ""
    public var sessionID = ""
    public var link = ""
    public var role = ""
    public var directory = ""
    public init() {}
}
public struct Activity: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID().uuidString
    public var date = Date()
    public var text: String
    public init(_ text: String) { self.text = text }
}
public struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID().uuidString
    public var title: String
    public var goal = ""
    public var status: TaskStatus = .todo
    public var directory = ""
    public var branch = ""
    public var pr = ""
    public var progress = ""
    public var nextStep = ""
    public var startAt: Date?
    public var endAt: Date?
    public var tags: [String] = []
    public var sessions: [AgentSession] = []
    public var activities: [Activity] = []
    public var createdAt = Date()
    public var updatedAt = Date()
    public var revision = 0
    public init(title: String) { self.title = title }
    private enum CodingKeys: String, CodingKey { case id, title, goal, status, directory, branch, pr, progress, nextStep, sessions, activities, createdAt, updatedAt, revision, tags, startAt, endAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        goal = try c.decode(String.self, forKey: .goal)
        status = try c.decode(TaskStatus.self, forKey: .status)
        directory = try c.decode(String.self, forKey: .directory)
        branch = try c.decode(String.self, forKey: .branch)
        pr = try c.decode(String.self, forKey: .pr)
        progress = try c.decode(String.self, forKey: .progress)
        nextStep = try c.decode(String.self, forKey: .nextStep)
        sessions = try c.decode([AgentSession].self, forKey: .sessions)
        activities = try c.decode([Activity].self, forKey: .activities)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        revision = try c.decode(Int.self, forKey: .revision)
        startAt = try c.decodeIfPresent(Date.self, forKey: .startAt)
        endAt = try c.decodeIfPresent(Date.self, forKey: .endAt)
        tags = Self.normalizeTags(try c.decodeIfPresent([String].self, forKey: .tags) ?? [])
    }
    // Inclusive first day, exclusive day after the last day; missing endpoints are points.
    public func overlaps(from: Date, until: Date) -> Bool {
        guard from < until, let first = startAt ?? endAt else { return false }
        let last = endAt ?? first
        return first < until && last >= from
    }
    public func validateTimeRange() throws {
        if let startAt, let endAt, endAt < startAt { throw StoreError.message("结束时间不能早于开始时间") }
    }
    public static func parseTimestamp(_ text: String) throws -> Date? {
        if text.isEmpty { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        throw StoreError.message("时间格式应为带时区的 ISO 8601，例如 2026-10-23T09:00:00+08:00；空字符串清空时间")
    }
    public static func normalizeTags(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
    public static func parseTags(_ text: String) -> [String] { normalizeTags(text.components(separatedBy: CharacterSet(charactersIn: ",，\n"))) }

}
private struct Database: Codable { var version = 1; var tasks: [TaskItem] = [] }
public enum StoreError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}
public struct TaskStore: Sendable {
    public let directory: URL
    public init(directory: URL? = nil) {
        self.directory = directory ?? ProcessInfo.processInfo.environment["TASKNOTE_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/TaskNotebook", isDirectory: true)
    }
    public var file: URL { directory.appendingPathComponent("tasks.json") }
    private func locked<T>(_ action: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(directory.appendingPathComponent("store.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw StoreError.message("无法打开数据锁") }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw StoreError.message("无法锁定数据") }
        defer { flock(fd, LOCK_UN) }
        return try action()
    }
    private func read() throws -> Database {
        guard FileManager.default.fileExists(atPath: file.path) else { return Database() }
        let db = try JSONDecoder().decode(Database.self, from: Data(contentsOf: file))
        guard db.version == 1 else { throw StoreError.message("数据版本不受支持，未修改文件") }
        return db
    }
    private func write(_ db: Database) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(db).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    public func list() throws -> [TaskItem] { try locked { try read().tasks.sorted { $0.updatedAt > $1.updatedAt } } }
    public func create(_ task: TaskItem) throws -> TaskItem {
        try locked {
            guard !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StoreError.message("任务名称不能为空") }
            try task.validateTimeRange()
            var db = try read()
            guard !db.tasks.contains(where: { $0.id == task.id }) else { throw StoreError.message("任务 ID 已存在") }
            var item = task; item.tags = TaskItem.normalizeTags(item.tags); item.activities.append(Activity("创建任务")); db.tasks.append(item); try write(db); return item
        }
    }
    public func update(id: String, expectedRevision: Int? = nil, _ change: (inout TaskItem) throws -> Void) throws -> TaskItem {
        try locked {
            var db = try read()
            guard let index = db.tasks.firstIndex(where: { $0.id == id }) else { throw StoreError.message("找不到任务 \(id)") }
            if let expectedRevision, db.tasks[index].revision != expectedRevision { throw StoreError.message("任务已被其他窗口或 Agent 更新。请复制未保存内容，关闭编辑后重新打开。") }
            var item = db.tasks[index]; try change(&item)
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StoreError.message("任务名称不能为空") }
            try item.validateTimeRange()
            item.tags = TaskItem.normalizeTags(item.tags)
            item.id = id; item.revision = db.tasks[index].revision + 1; item.updatedAt = Date()
            db.tasks[index] = item; try write(db); return item
        }
    }
    public func delete(id: String, expectedRevision: Int) throws {
        try locked {
            var db = try read()
            guard let item = db.tasks.first(where: { $0.id == id }) else { throw StoreError.message("任务不存在") }
            guard item.revision == expectedRevision else { throw StoreError.message("任务已更新，请刷新后再删除") }
            db.tasks.removeAll { $0.id == id }; try write(db)
        }
    }
}
