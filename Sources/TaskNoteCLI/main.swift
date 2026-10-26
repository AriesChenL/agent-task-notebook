import Foundation
import TaskCore

let help = """
tasknote — Agent 任务记事本

  tasknote list [--status todo|running|waiting|done|cancelled] [--tag <标签>]
  tasknote show <task-id>
  tasknote add --title <名称> [--status running] [--directory <目录>]
  tasknote update <task-id> [--title ...] [--status ...] [--progress ...] [--next ...]
  tasknote session add <task-id> --tool <工具> --name <会话名> [--session-id ...] [--link ...] [--role ...] [--directory ...]
  tasknote session remove <task-id> --id <session-id>
  tasknote note <task-id> --text <进展记录>
  tasknote path

add/update 也支持 --goal、--directory、--branch、--pr、--progress、--next、--tags（逗号分隔，空字符串清空）。
--start / --end 使用带时区的 ISO 8601，例如 2026-10-23T09:00:00+08:00；空字符串清空。
所有数据输出均为 JSON；错误输出到 stderr，退出码为 1。
TASKNOTE_HOME 可指定隔离的数据目录。无需启动桌面软件。
"""
func emit<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
}
func run() throws {
    var args = Array(CommandLine.arguments.dropFirst())
    guard !args.isEmpty, args[0] != "--help", args[0] != "help" else { print(help); return }
    let command = args.removeFirst()
    var positional: [String] = []; var options: [String: String] = [:]
    var i = 0
    while i < args.count {
        if args[i].hasPrefix("--") {
            guard i + 1 < args.count, !args[i + 1].hasPrefix("--"), options[args[i]] == nil else { throw StoreError.message("缺少参数值或参数重复：\(args[i])") }
            options[args[i]] = args[i + 1]; i += 2
        } else { positional.append(args[i]); i += 1 }
    }
    let fields: Set<String> = ["--title", "--status", "--goal", "--directory", "--branch", "--pr", "--progress", "--next", "--tags", "--start", "--end"]
    let allowed: Set<String>
    switch command {
    case "add", "update": allowed = fields
    case "list": allowed = ["--status", "--tag"]
    case "session": allowed = positional.first == "remove" ? ["--id"] : ["--tool", "--name", "--session-id", "--link", "--role", "--directory"]
    case "note": allowed = ["--text"]
    default: allowed = []
    }
    if let unknown = options.keys.first(where: { !allowed.contains($0) }) { throw StoreError.message("未知参数 \(unknown)") }
    func required(_ key: String) throws -> String {
        guard let value = options[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StoreError.message("必须提供 \(key)") }; return value
    }
    func taskID(_ count: Int = 1) throws -> String {
        guard positional.count == count, let value = positional.last else { throw StoreError.message("请提供完整任务 ID；使用 tasknote --help 查看用法") }; return value
    }
    func apply(_ item: inout TaskItem) throws {
        if let value = options["--start"] { item.startAt = try TaskItem.parseTimestamp(value) }
        if let value = options["--end"] { item.endAt = try TaskItem.parseTimestamp(value) }
        if let value = options["--tags"] { item.tags = TaskItem.parseTags(value) }
        if let value = options["--title"] { item.title = value }
        if let value = options["--status"] { guard let status = TaskStatus(rawValue: value) else { throw StoreError.message("无效状态 \(value)") }; item.status = status }
        if let v = options["--goal"] { item.goal = v }; if let v = options["--directory"] { item.directory = v }
        if let v = options["--branch"] { item.branch = v }; if let v = options["--pr"] { item.pr = v }
        if let v = options["--progress"] { item.progress = v }; if let v = options["--next"] { item.nextStep = v }
    }
    let store = TaskStore()
    switch command {
    case "path": guard positional.isEmpty else { throw StoreError.message("path 不接受位置参数") }; try emit(store.file.path)
    case "list":
        guard positional.isEmpty else { throw StoreError.message("list 不接受位置参数") }
        if let value = options["--status"], TaskStatus(rawValue: value) == nil { throw StoreError.message("无效状态") }
        try emit(store.list().filter { (options["--status"] == nil || $0.status.rawValue == options["--status"]) && (options["--tag"] == nil || $0.tags.contains(where: { $0.caseInsensitiveCompare(options["--tag"]!) == .orderedSame })) })
    case "show": let id = try taskID(); guard let item = try store.list().first(where: { $0.id == id }) else { throw StoreError.message("任务不存在") }; try emit(item)
    case "add":
        guard positional.isEmpty else { throw StoreError.message("add 使用 --title 指定名称") }
        var item = TaskItem(title: try required("--title")); try apply(&item); try emit(store.create(item))
    case "update":
        let id = try taskID(); guard !options.isEmpty else { throw StoreError.message("请提供要更新的字段") }
        try emit(store.update(id: id) { item in try apply(&item); item.activities.append(Activity(options["--progress"] ?? "CLI 更新任务")) })
    case "note":
        let id = try taskID(); let note = try required("--text")
        try emit(store.update(id: id) { $0.activities.append(Activity(note)); $0.progress = note })
    case "session":
        let id = try taskID(2)
        switch positional[0] {
        case "add":
            var session = AgentSession(); session.tool = try required("--tool"); session.name = try required("--name")
            session.sessionID = options["--session-id"] ?? ""; session.link = options["--link"] ?? ""; session.role = options["--role"] ?? ""; session.directory = options["--directory"] ?? ""
            try emit(store.update(id: id) { $0.sessions.append(session); $0.activities.append(Activity("关联会话：\(session.name)")) })
        case "remove":
            let sessionID = try required("--id")
            try emit(store.update(id: id) { item in
                guard item.sessions.contains(where: { $0.id == sessionID }) else { throw StoreError.message("会话不存在") }
                item.sessions.removeAll { $0.id == sessionID }; item.activities.append(Activity("移除关联会话"))
            })
        default: throw StoreError.message("session 支持 add / remove")
        }
    default: throw StoreError.message("未知命令；请使用 tasknote --help")
    }
}
do { try run() } catch { FileHandle.standardError.write(Data("tasknote: \(error.localizedDescription)\n".utf8)); exit(1) }
